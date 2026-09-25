--!strict
-- BuildingState.luau
-- DESTRUKCJA v4, faza B — stan konstrukcji JEDNEGO budynku w rundzie.
-- Czysta logika: bez serwisów, bez tworzenia instancji, bez yieldów. Plan i decyzje:
-- DESTRUCTION_PLAN.md → „v4”. Dane wejściowe: to, co robi StructureBake.toData
-- (w grze: ServerStorage.StructureData.<Budynek>).
--
-- KTO WOŁA (faza D): StructuralService — jeden BuildingState na budynek, nowy przy każdym
-- resecie mapy. Wybuch → applyHole (dla każdego przeciętego parta) + applyStructuralDamage
-- → budynek „brudny” → flush RAZ na klatkę → wynik: zniszczone, osłabione, plan kolapsu.
--
-- STANY CHUNKA (jedna funkcja przejść, compare-and-set — dwa wybuchy w tej samej klatce nie
-- zrobią podwójnego kolapsu ani podwójnego zniszczenia):
--   Intact → Damaged (suma obrażeń ≥ DamagedFrom × HP: widoczne rysy)
--   Intact|Damaged → Destroyed (Severed: dziura przez cały przekrój nośny;
--                                Crumbled: suma obrażeń ≥ HP — geometrię kruszy wykonawca)
--   Intact|Damaged → Falling (solver: brak drogi do podpory) → Settled → Retired
-- Destroyed / Falling / Settled / Retired niczego nie podpierają.
--
-- BRAK NIEWIDZIALNYCH AWARII: interfejs traci szerokość TYLKO tam, gdzie dziura realnie
-- zabrała materiał, a element „zniszczony” strukturalnie ma zniknąć też z mapy (Crumbled —
-- wykonawca dostaje listę `destroyed`). Gracz nie zobaczy stojącego słupa pod spadającym
-- stropem.

local Core = require(script.Parent.StructureCore)
local CollapsePlanner = require(script.Parent.CollapsePlanner)

local GROUND = Core.GROUND
local EPS = Core.EPS

type Chunk = Core.Chunk
type Iface = Core.Iface

export type Cause = {
	causeId: number,
	attackerUserId: number,
	seq: number, -- globalny licznik zdarzeń serwera — JEDYNE źródło kolejności
	time: number,
	center: Vector3?, -- epicentrum (kierunek odrzutu skruszonych kawałków)
}

type ChunkRt = {
	state: string,
	reason: string?,
	damage: number,
	cause: Cause?,
	collapseId: number?,
}

export type CollapsePlan = {
	collapseId: number,
	buildingId: string,
	revision: number,
	cause: Cause?,
	assists: { number },
	groups: { CollapsePlanner.Group },
}

export type FlushResult = {
	buildingId: string,
	revision: number,
	destroyed: { number }, -- zniszczone od ostatniego flusha (Crumbled = do skruszenia w mapie)
	damaged: { number }, -- nowo osłabione (rysy)
	plan: CollapsePlan?,
}

local ALIVE: { [string]: boolean } = { Intact = true, Damaged = true }
local FALLING: { [string]: boolean } = { Falling = true }
local SETTLING: { [string]: boolean } = { Falling = true, Settled = true }

local BuildingState = {}
BuildingState.__index = BuildingState

export type BuildingState = typeof(setmetatable(
	{} :: {
		id: string,
		cfg: any,
		chunks: { Chunk },
		ifaces: { Iface },
		attachments: { { part: number, owner: number } },
		out: { [number]: { Iface } },
		inn: { [number]: { Iface } },
		partChunks: { [number]: { number } },
		touching: { [number]: { Iface } },
		rt: { [number]: ChunkRt },
		removed: { [number]: { { number } } },
		width: { [number]: number },
		ifaceCause: { [number]: Cause },
		revision: number,
		dirty: boolean,
		pending: { Cause },
		logDestroyed: { number },
		logDamaged: { number },
		collapseSeq: number,
		enabled: boolean,
		baselineFalling: number,
	},
	BuildingState
))

function BuildingState.new(data: any, config: any): BuildingState
	local cfg = config.Structure
	local self = setmetatable({
		id = data.BuildingId,
		cfg = cfg,
		chunks = data.Chunks,
		ifaces = data.Interfaces,
		attachments = data.Attachments,
		out = Core.outgoing(data.Interfaces),
		inn = Core.incoming(data.Interfaces),
		partChunks = {},
		touching = {},
		rt = {},
		removed = {},
		width = {},
		ifaceCause = {},
		revision = 0,
		dirty = false,
		pending = {},
		logDestroyed = {},
		logDamaged = {},
		collapseSeq = 0,
		enabled = true,
		baselineFalling = 0,
	}, BuildingState)

	for _, c in ipairs(self.chunks) do
		local list = self.partChunks[c.part]
		if not list then
			list = {}
			self.partChunks[c.part] = list
		end
		table.insert(list, c.id)
		self.rt[c.id] = { state = "Intact", damage = 0 }
	end
	local function touch(id: number, f: Iface)
		local list = self.touching[id]
		if not list then
			list = {}
			self.touching[id] = list
		end
		table.insert(list, f)
	end
	for _, f in ipairs(self.ifaces) do
		if f.from ~= GROUND then
			touch(f.from, f)
		end
		touch(f.to, f)
	end

	-- Nietknięty budynek MUSI stać. Jeśli nie stoi (dane nie pasują albo bake ma czerwone),
	-- kolaps jest wyłączony — dziury dalej działają, ale nic nie spada samo z siebie.
	local _, falling = Core.solve(self.chunks, self.out, cfg, nil, nil)
	self.baselineFalling = #falling
	self.enabled = #falling == 0
	return self
end

-- ============================================================================
-- Odczyt
-- ============================================================================

function BuildingState.stateOf(self: BuildingState, id: number): string
	return self.rt[id].state
end

function BuildingState.isAlive(self: BuildingState, id: number): boolean
	local rt = self.rt[id]
	return rt ~= nil and ALIVE[rt.state] == true
end

function BuildingState.widthOf(self: BuildingState, f: Iface): number
	return self.width[f.id] or f.width
end

-- ============================================================================
-- Przejścia stanów — JEDYNE miejsce, które zmienia `state`
-- ============================================================================

function BuildingState.transition(self: BuildingState, id: number, from: { [string]: boolean }, to: string): boolean
	local rt = self.rt[id]
	if not rt or not from[rt.state] then
		return false
	end
	rt.state = to
	return true
end

local function touched(self: BuildingState, cause: Cause)
	self.dirty = true
	self.revision += 1
	table.insert(self.pending, cause)
end

-- ============================================================================
-- Dziura (geometria)
-- ============================================================================

-- Suma odcinków (bez podwójnego liczenia nakładających się dziur).
local function unionLength(list: { { number } }): number
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		return a[1] < b[1]
	end)
	local total, curA, curB = 0, nil :: number?, 0
	for _, seg in ipairs(sorted) do
		if curA == nil then
			curA, curB = seg[1], seg[2]
		elseif seg[1] <= curB then
			curB = math.max(curB, seg[2])
		else
			total += curB - (curA :: number)
			curA, curB = seg[1], seg[2]
		end
	end
	if curA ~= nil then
		total += curB - curA
	end
	return total
end

-- Czy dziura przecina CAŁY przekrój nośny chunka (prostopadły do osi, wzdłuż której
-- element niesie) — słup 5×5 przy dziurze 18×18 zawsze, ściana 20 szer. tylko przy trafieniu
-- na całą długość, strop tylko gdy dziura zabierze całe pole.
function BuildingState.severs(self: BuildingState, c: Chunk, hmin: Vector3, hmax: Vector3): boolean
	local tol = self.cfg.Damage.SeverTolerance
	local L = Core.loadAxis(c)
	local overlapL = math.min(Core.component(c.max, L), Core.component(hmax, L))
		- math.max(Core.component(c.min, L), Core.component(hmin, L))
	if overlapL <= EPS then
		return false
	end
	for _, A in ipairs({ "X", "Y", "Z" }) do
		if A == L then continue end
		if Core.component(hmin, A) > Core.component(c.min, A) + tol then return false end
		if Core.component(hmax, A) < Core.component(c.max, A) - tol then return false end
	end
	return true
end

-- Dziura wycięta w parcie `partIndex` (prostopadłościan w świecie). Zwraca, czy coś się
-- zmieniło. Chunki w stanie innym niż Intact/Damaged są pomijane — bomba w trakcie kolapsu
-- nie tnie ponownie tego, co już spada.
function BuildingState.applyHole(self: BuildingState, partIndex: number, hmin: Vector3, hmax: Vector3, cause: Cause): boolean
	local ids = self.partChunks[partIndex]
	if not ids then
		return false
	end
	local pad = self.cfg.ContactPadding
	local changed = false
	local seen: { [number]: boolean } = {}
	for _, id in ipairs(ids) do
		local rt = self.rt[id]
		if not ALIVE[rt.state] then continue end
		if self:severs(self.chunks[id], hmin, hmax) and self:transition(id, ALIVE, "Destroyed") then
			rt.reason = "Severed"
			rt.cause = cause
			table.insert(self.logDestroyed, id)
			changed = true
		end
		for _, f in ipairs(self.touching[id] or {}) do
			if seen[f.id] then continue end
			seen[f.id] = true
			if not Core.intersect(f.lo, f.hi, hmin, hmax, pad) then continue end
			-- Odcinek zabrany wzdłuż osi szerokości, przycięty do obszaru styku.
			local a = math.max(Core.component(f.lo, f.axis), Core.component(hmin, f.axis))
			local b = math.min(Core.component(f.hi, f.axis), Core.component(hmax, f.axis))
			if b - a <= EPS then continue end
			local list = self.removed[f.id]
			if not list then
				list = {}
				self.removed[f.id] = list
			end
			table.insert(list, { a, b })
			local w = math.max(0, f.width - unionLength(list))
			if w < self:widthOf(f) - EPS then
				self.width[f.id] = w
				self.ifaceCause[f.id] = cause
				changed = true
			end
		end
	end
	if changed then
		touched(self, cause)
	end
	return changed
end

-- ============================================================================
-- Obrażenia strukturalne (osłabianie — decyzja Kacpra 24.09: sumują się)
-- ============================================================================

function BuildingState.applyStructuralDamage(self: BuildingState, center: Vector3, radius: number, damage: number, cause: Cause): boolean
	local D = self.cfg.Damage
	local changed = false
	for _, c in ipairs(self.chunks) do
		local hp = D.HP[c.kind]
		if not hp or c.permanent then continue end
		local rt = self.rt[c.id]
		if not ALIVE[rt.state] then continue end
		local d = Core.boxDistance(c.min, c.max, center)
		if d >= radius then continue end
		local dmg = damage * D.StructuralPowerFactor * (1 - d / radius)
		if dmg <= 0 then continue end
		rt.damage += dmg
		rt.cause = cause
		changed = true
		if rt.damage >= hp then
			if self:transition(c.id, ALIVE, "Destroyed") then
				rt.reason = "Crumbled"
				table.insert(self.logDestroyed, c.id)
			end
		elseif rt.damage >= hp * D.DamagedFrom and self:transition(c.id, { Intact = true }, "Damaged") then
			table.insert(self.logDamaged, c.id)
		end
	end
	if changed then
		touched(self, cause)
	end
	return changed
end

-- ============================================================================
-- Flush: JEDEN solve na budynek, niezależnie od liczby wybuchów od poprzedniego
-- ============================================================================

-- Kto uruchomił kolaps: zdarzenie o NAJWYŻSZYM `seq` spośród tych, które zmieniły granicę
-- spadającego obszaru (zniszczony podpierający chunk albo zwężony interfejs podpory).
-- Asysty: pozostali sprawcy z tej granicy. Kolejność zdarzeń u klientów nie gra roli.
local function blame(self: BuildingState, falling: { number }, pending: { Cause }): (Cause?, { number })
	local fallingSet: { [number]: boolean } = {}
	for _, id in ipairs(falling) do
		fallingSet[id] = true
	end
	local found: { Cause } = {}
	for _, id in ipairs(falling) do
		for _, f in ipairs(self.inn[id] or {}) do
			if f.from ~= GROUND and fallingSet[f.from] then continue end
			local cause: Cause? = nil
			if f.from ~= GROUND then
				local rt = self.rt[f.from]
				if rt.state == "Destroyed" then
					cause = rt.cause
				end
			end
			cause = cause or self.ifaceCause[f.id]
			if cause then
				table.insert(found, cause)
			end
		end
	end
	if #found == 0 then
		found = pending
	end
	local best: Cause? = nil
	for _, c in ipairs(found) do
		if not best or c.seq > best.seq then
			best = c
		end
	end
	local assists: { number } = {}
	local seenAttacker: { [number]: boolean } = {}
	for _, c in ipairs(found) do
		local uid = c.attackerUserId
		if uid ~= 0 and (not best or uid ~= best.attackerUserId) and not seenAttacker[uid] then
			seenAttacker[uid] = true
			table.insert(assists, uid)
		end
	end
	table.sort(assists)
	return best, assists
end

function BuildingState.flush(self: BuildingState): FlushResult?
	if not self.dirty then
		return nil
	end
	self.dirty = false
	local pending = self.pending
	self.pending = {}
	local result: FlushResult = {
		buildingId = self.id,
		revision = self.revision,
		destroyed = self.logDestroyed,
		damaged = self.logDamaged,
		plan = nil,
	}
	self.logDestroyed = {}
	self.logDamaged = {}
	if not self.enabled then
		return result
	end

	local dead: { [number]: boolean } = {}
	for id, rt in pairs(self.rt) do
		if not ALIVE[rt.state] then
			dead[id] = true
		end
	end
	local reach, falling = Core.solve(self.chunks, self.out, self.cfg, dead, self.width)
	if #falling == 0 then
		return result
	end

	self.collapseSeq += 1
	local collapseId = self.collapseSeq
	local cause, assists = blame(self, falling, pending)
	-- Planner PRZED przejściem w Falling: pivot szuka stojących sąsiadów po stanie sprzed.
	local groups = CollapsePlanner.plan(self :: any, falling, reach, collapseId)
	for _, id in ipairs(falling) do
		if self:transition(id, ALIVE, "Falling") then
			self.rt[id].collapseId = collapseId
		end
	end
	self.revision += 1
	result.revision = self.revision
	result.plan = {
		collapseId = collapseId,
		buildingId = self.id,
		revision = self.revision,
		cause = cause,
		assists = assists,
		groups = groups,
	}
	return result
end

-- ============================================================================
-- Wykonawca (faza D) zgłasza koniec lotu i sprzątanie
-- ============================================================================

function BuildingState.settle(self: BuildingState, ids: { number })
	for _, id in ipairs(ids) do
		self:transition(id, FALLING, "Settled")
	end
end

function BuildingState.retire(self: BuildingState, ids: { number })
	for _, id in ipairs(ids) do
		self:transition(id, SETTLING, "Retired")
	end
end

return BuildingState
