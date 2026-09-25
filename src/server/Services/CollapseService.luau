--!strict
-- CollapseService.luau
-- DESTRUKCJA v4, faza D — WYKONAWCA: zamienia wynik solvera w to, co widać i czuć w grze.
-- Plan, decyzje i pomiary: DESTRUCTION_PLAN.md → „v4”.
--
-- Co klatkę bierze wyniki `StructuralService.flushAll()` i:
--   * KRUSZY osłabione elementy (Crumbled): ich fragment znika z mapy — duży leci jako
--     fragment fizyki serwera (ściany mogą naprawdę odlecieć — decyzja Kacpra), mały u klientów.
--     Brak niewidzialnych awarii: zniszczony strukturalnie element nie stoi dalej w mapie.
--   * PUSZCZA GRUPY KOLAPSU prawdziwą fizyką serwera (decyzja Kacpra: gracz jedzie razem
--     z piętrem). Grupa = jedna spawana bryła, nie setki partów.
--   * pilnuje BUDŻETU fizyki (koszt grupy = 1 + kawałki z kolizją; rezerwa dla grup, na
--     których stoi gracz) i kolejności (najpierw jeźdźcy, potem to, co blisko graczy, od dołu).
--     Ponad budżet grupa nie znika z gry: jej kolizja i tak odchodzi (wynik strukturalny
--     zawsze się dzieje), tylko upadek animują klienci.
--   * po zatrzymaniu KOTWICZY grupę (platforma, decyzja Kacpra: duże zostają do końca rundy,
--     małe znikają po kilku sekundach), sprząta zatopione w lawie, zadaje przygniecenie.
--
-- DLACZEGO filtr kolizji na starcie: w OrangeBuilding 158 par partów konstrukcji na siebie
-- nachodzi (słupy przez stropy, stropy w belki). Odkotwiczony kawałek nachodzący na stojący
-- silnik wypycha gwałtownie — „wybuchowy” skok, dokładnie ten sztuczny efekt. Pary, które
-- nachodzą w chwili startu, dostają NoCollisionConstraint; z resztą świata grupa zderza się
-- normalnie (ląduje na piętrze niżej, gracz na niej stoi).
--
-- ZALEŻNOŚCI: StructuralService (stan i kawałki), DebrisService (fragmenty, przygniecenie),
-- LavaService (powierzchnia). Przekazanie klientom (DestructionService) wstrzykiwane w init —
-- DestructionService woła ten serwis (rubble), więc bezpośredni require byłby cyklem.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Shockwave = require(ReplicatedStorage.Shared.Modules.Shockwave)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerService = require(script.Parent.PlayerService)
local LavaService = require(script.Parent.LavaService)
local DebrisService = require(script.Parent.DebrisService)
local StructuralService = require(script.Parent.StructuralService)

local Structure = script.Parent.Parent.Structure
local Pieces = require(Structure.Pieces)
local CollapsePlanner = require(Structure.CollapsePlanner)

local CollapseService = {}

local CFG = Config.Structure.Collapse
local DBR = Config.Destruction.Debris
local ATTACKER_ATTR = "BlastAttackerId" -- ten sam atrybut, z którego DebrisService bierze kill credit

type Rec = StructuralService.Rec
type Cause = StructuralService.Cause
type Box = Pieces.Box

type Active = {
	key: string,
	rec: Rec,
	def: CollapsePlanner.Group,
	cause: Cause?,
	priority: number, -- 0 = ktoś na niej stoi, 1 = gracz blisko, 2 = reszta
	cost: number,
	volume: number,
	center: Vector3,
	pieces: { BasePart },
	followers: { BasePart },
	followerCollide: { [BasePart]: boolean },
	filters: { Instance },
	root: BasePart?,
	phase: string, -- "Queued" | "Flying" | "Settled" | "Gone"
	queuedAt: number,
	releasedAt: number,
	stillSince: number?,
	retireAt: number?,
}

export type Injected = {
	-- Przekazanie instancji klientom do animacji (Remotes.DebrisFall), serwer kasuje po chwili.
	handOff: (list: { Instance }, center: Vector3, launch: boolean) -> (),
	-- Drobnica i meble leżące na kawałkach, które zaraz spadną — też do klientów.
	dropResting: (pieces: { BasePart }, center: Vector3) -> (),
}

local deps: Injected? = nil
local queue: { Active } = {}
local flying: { Active } = {}
local settledTemp: { Active } = {}
local used = 0
local lastMonitor = 0
-- Kawałek → grupa. Słabe klucze: skasowany sam wypada.
local rubbleOf: { [BasePart]: Active } = setmetatable({}, { __mode = "k" }) :: any
local flyingOf: { [BasePart]: Active } = setmetatable({}, { __mode = "k" }) :: any

local concrete = PhysicalProperties.new(DBR.Density, DBR.Friction, DBR.Elasticity, DBR.FrictionWeight, DBR.ElasticityWeight)

local function log(fmt: string, ...: any)
	if CFG.Debug then
		print("[Collapse] " .. string.format(fmt, ...))
	end
end

local function boxCenter(b: Box): Vector3
	return (b.min + b.max) * 0.5
end

-- ============================================================================
-- Kruszenie osłabionego elementu (Crumbled): fragment chunka znika z mapy
-- ============================================================================

local function launchFragment(part: BasePart, from: Vector3?, attackerId: number)
	part.Anchored = false
	part:SetAttribute(ATTACKER_ATTR, attackerId)
	part.Parent = DebrisService.getFolder()
	DebrisService.register(part)
	local away = if from then part.Position - from else Vector3.yAxis
	local dir = if away.Magnitude > 1e-3 then away.Unit else Vector3.yAxis
	part.AssemblyLinearVelocity = dir * CFG.FragmentSpeed + Vector3.new(0, CFG.FragmentSpeed * 0.3, 0)
end

local function crumble(rec: Rec, chunkId: number, cause: Cause?)
	local c = rec.state.chunks[chunkId]
	local box: Box = { min = c.min, max = c.max }
	local center = if cause and cause.center then cause.center else (c.min + c.max) * 0.5
	local attackerId = if cause then cause.attackerUserId else 0
	local toClients: { Instance } = {}
	local fragments: { BasePart } = {}
	for _, piece in ipairs(table.clone(StructuralService.piecesOf(rec, c.part))) do
		local pb = Pieces.boxOf(piece)
		local inter = Pieces.intersect(pb, box, CFG.MinPieceSize)
		if not inter then continue end
		local keep = Pieces.merge(Pieces.subtract(pb, box, CFG.MinPieceSize))
		local fragment: BasePart
		if #keep == 0 then
			StructuralService.releasePiece(rec, c.part, piece)
			fragment = piece
		else
			table.sort(keep, function(a, b)
				return Pieces.volume(a) > Pieces.volume(b)
			end)
			fragment = Pieces.spawnBox(piece, inter)
			for i = 2, #keep do
				StructuralService.addPiece(rec, c.part, Pieces.spawnBox(piece, keep[i]))
			end
			Pieces.setBox(piece, keep[1])
		end
		fragments[#fragments + 1] = fragment
		if Pieces.volume(inter) >= CFG.FragmentMinVolume and DebrisService.reserve(1) > 0 then
			launchFragment(fragment, center, attackerId)
		else
			table.insert(toClients, fragment)
		end
	end
	-- Listwy i szyby wiszące na skruszonym elemencie spadają razem z nim (test 24.09: bez tego
	-- zostawały w powietrzu).
	local loose: { Instance } = {}
	for _, partIndex in ipairs(StructuralService.attachmentsOf(rec, chunkId)) do
		for _, p in ipairs(table.clone(StructuralService.piecesOf(rec, partIndex))) do
			if p.Anchored then
				StructuralService.releasePiece(rec, partIndex, p)
				table.insert(loose, p)
			end
		end
	end
	if deps then
		-- Meble i drobnica stojące na tym, co się skruszyło.
		deps.dropResting(fragments, center)
		if #toClients > 0 then
			deps.handOff(toClients, center, true)
		end
		if #loose > 0 then
			deps.handOff(loose, center, false)
		end
	end
end

-- Osłabiony element ciemnieje (bez tego osłabianie jest niewidzialne i „2. bomba go
-- przecięła” wygląda jak losowość). Kolor przez atrybut oryginału — jak v3.
local ORIG_COLOR_ATTR = "DestrOrigColor"

local function darken(rec: Rec, chunkIds: { number })
	local hpByKind = Config.Structure.Damage.HP
	local worstByPart: { [number]: number } = {}
	for _, id in ipairs(chunkIds) do
		local c = rec.state.chunks[id]
		local hp = hpByKind[c.kind]
		if hp then
			local frac = math.clamp(rec.state.rt[id].damage / hp, 0, 1)
			worstByPart[c.part] = math.max(worstByPart[c.part] or 0, frac)
		end
	end
	for partIndex, frac in pairs(worstByPart) do
		for _, piece in ipairs(StructuralService.piecesOf(rec, partIndex)) do
			local orig = piece:GetAttribute(ORIG_COLOR_ATTR)
			if typeof(orig) ~= "Color3" then
				orig = piece.Color
				piece:SetAttribute(ORIG_COLOR_ATTR, orig)
			end
			piece.Color = (orig :: Color3):Lerp(Color3.fromRGB(35, 32, 30), frac * Config.Destruction.DamageFeedback.DarkenMax)
		end
	end
end

-- ============================================================================
-- Plan kolapsu → kolejka (priorytet, koszt)
-- ============================================================================

local function priorityOf(g: CollapsePlanner.Group): number
	local best = 2
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end
		local feet = hrp.Position - Vector3.new(0, 2.5, 0)
		local p = feet
		if p.X >= g.min.X - 1 and p.X <= g.max.X + 1 and p.Z >= g.min.Z - 1 and p.Z <= g.max.Z + 1
			and p.Y >= g.max.Y - 1 and p.Y <= g.max.Y + CFG.RiderHeight then
			return 0
		end
		local d = (hrp.Position:Max(g.min):Min(g.max) - hrp.Position).Magnitude
		if d <= CFG.NearPlayerDistance then
			best = 1
		end
	end
	return best
end

local function enqueue(rec: Rec, plan: any)
	for _, g in ipairs(plan.groups :: { CollapsePlanner.Group }) do
		table.insert(queue, {
			key = rec.id .. ":" .. g.groupId,
			rec = rec,
			def = g,
			cause = plan.cause,
			priority = priorityOf(g),
			cost = 1 + #g.parts,
			volume = g.volume,
			center = (g.min + g.max) * 0.5,
			pieces = {},
			followers = {},
			followerCollide = {},
			filters = {},
			root = nil,
			phase = "Queued",
			queuedAt = os.clock(),
			releasedAt = 0,
		})
	end
	-- Najpierw jeźdźcy, potem to, co blisko graczy; w obrębie — od dołu (kaskada), większe pierwsze.
	table.sort(queue, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		if a.def.depth ~= b.def.depth then
			return a.def.depth < b.def.depth
		end
		return a.volume > b.volume
	end)
	log("%s: kolaps #%d → %d grup w kolejce (przyczyna seq %s)", rec.id, plan.collapseId, #plan.groups,
		if plan.cause then tostring(plan.cause.seq) else "-")
end

-- ============================================================================
-- Kawałki grupy: odcinamy to, co leży w jej chunkach
-- ============================================================================

-- Zbiera kawałki spadające z grupą. Kawałek w całości w grupie spada cały; kawałek na
-- granicy jest dzielony po granicy chunków — ORYGINAŁ zostaje w części stojącej (gracz na
-- nim nie traci gruntu), nowe kawałki powstają dla reszty. Resztki zniszczonych chunków
-- tego samego parta, które dotykają grupy, lecą razem z nią (nic nie wisi w powietrzu).
local function takePieces(a: Active): { BasePart }
	local rec, g = a.rec, a.def
	local st = rec.state
	local inGroup: { [number]: boolean } = {}
	for _, id in ipairs(g.chunkIds) do
		inGroup[id] = true
	end
	local out: { BasePart } = {}
	for _, partIndex in ipairs(g.parts) do
		local groupBoxes: { Box } = {}
		local fallBoxes: { Box } = {}
		for _, cid in ipairs(st.partChunks[partIndex] or {}) do
			local c = st.chunks[cid]
			local b = { min = c.min, max = c.max }
			if inGroup[cid] then
				table.insert(groupBoxes, b)
				table.insert(fallBoxes, b)
			elseif st.rt[cid].state == "Destroyed" then
				table.insert(fallBoxes, b)
			end
		end
		for _, piece in ipairs(table.clone(StructuralService.piecesOf(rec, partIndex))) do
			local pb = Pieces.boxOf(piece)
			local touchesGroup = false
			for _, b in ipairs(groupBoxes) do
				if Pieces.intersect(pb, b, CFG.MinPieceSize) then
					touchesGroup = true
					break
				end
			end
			if not touchesGroup then continue end
			local fall: { Box } = {}
			local keep: { Box } = { pb }
			for _, b in ipairs(fallBoxes) do
				local inter = Pieces.intersect(pb, b, CFG.MinPieceSize)
				if inter then
					table.insert(fall, inter)
					local nextKeep: { Box } = {}
					for _, k in ipairs(keep) do
						for _, r in ipairs(Pieces.subtract(k, b, CFG.MinPieceSize)) do
							table.insert(nextKeep, r)
						end
					end
					keep = nextKeep
				end
			end
			fall = Pieces.merge(fall)
			keep = Pieces.merge(keep)
			if #keep == 0 then
				StructuralService.releasePiece(rec, partIndex, piece)
				table.insert(out, piece)
			else
				table.sort(keep, function(x, y)
					return Pieces.volume(x) > Pieces.volume(y)
				end)
				for _, f in ipairs(fall) do
					table.insert(out, Pieces.spawnBox(piece, f))
				end
				for i = 2, #keep do
					StructuralService.addPiece(rec, partIndex, Pieces.spawnBox(piece, keep[i]))
				end
				Pieces.setBox(piece, keep[1])
			end
		end
	end
	return out
end

local function takeFollowers(a: Active): { BasePart }
	local out: { BasePart } = {}
	for _, partIndex in ipairs(a.def.followers) do
		for _, p in ipairs(table.clone(StructuralService.piecesOf(a.rec, partIndex))) do
			if p.Anchored then
				StructuralService.releasePiece(a.rec, partIndex, p)
				table.insert(out, p)
			end
		end
	end
	return out
end

-- ============================================================================
-- Start lotu
-- ============================================================================

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function penetration(a: BasePart, b: BasePart): number
	local ba, bb = Pieces.boxOf(a), Pieces.boxOf(b)
	local o = ba.max:Min(bb.max) - ba.min:Max(bb.min)
	return math.min(o.X, o.Y, o.Z)
end

-- NoCollisionConstraint dla par kawałek grupy ↔ cokolwiek, na co w chwili startu nachodzi.
local function filterOverlaps(a: Active, own: { [BasePart]: boolean })
	local count = 0
	for _, p in ipairs(a.pieces) do
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size)) do
			if count >= CFG.OverlapFilterMax then return end
			if own[hit] or hit:IsA("Terrain") or not hit.CanCollide or isCharacterPart(hit) then continue end
			if penetration(p, hit) <= CFG.OverlapMinDepth then continue end
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = p
			nc.Part1 = hit
			nc.Parent = p
			table.insert(a.filters, nc)
			count += 1
		end
	end
end

local function release(a: Active): boolean
	local pieces = takePieces(a)
	if #pieces == 0 then
		a.rec.state:retire(a.def.chunkIds)
		a.phase = "Gone"
		return false
	end
	local followers = takeFollowers(a)
	a.pieces = pieces
	a.followers = followers

	table.sort(pieces, function(x, y)
		local sx, sy = x.Size, y.Size
		return sx.X * sx.Y * sx.Z > sy.X * sy.Y * sy.Z
	end)
	local root = pieces[1]
	a.root = root

	local own: { [BasePart]: boolean } = {}
	for _, p in ipairs(pieces) do
		own[p] = true
	end
	for _, p in ipairs(followers) do
		own[p] = true
	end
	filterOverlaps(a, own)

	-- Spawanie: jedna bryła. Spawy zostają po zatrzymaniu — kolejny wybuch budzi całą bryłę.
	for i = 2, #pieces do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = pieces[i]
		w.Parent = pieces[i]
	end
	for _, f in ipairs(followers) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = f
		w.Parent = f
		-- Pasażer (listwa, rama okna) leci bez kolizji i bez masy — mniej kontaktów, a bryłę
		-- prowadzi konstrukcja, nie ozdoba.
		a.followerCollide[f] = f.CanCollide
		f.CanCollide = false
		f.Massless = true
	end

	for _, p in ipairs(pieces) do
		p.CustomPhysicalProperties = concrete
		p.Anchored = false
		flyingOf[p] = a
	end
	for _, f in ipairs(followers) do
		f.Anchored = false
		flyingOf[f] = a
	end
	-- Drobnica i meble na tym, co spada — do klientów (inaczej wisiałyby w powietrzu).
	if deps then
		deps.dropResting(pieces, a.center)
	end

	pcall(function()
		root:SetNetworkOwner(nil) -- serwer: bryła z kolizją należąca do klienta = exploit (podnieść nad lawę)
	end)
	local r = Random.new(#a.key + a.def.chunkIds[1])
	root.AssemblyLinearVelocity = Vector3.new(0, -CFG.FallSpeed, 0)
	root.AssemblyAngularVelocity = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(-0.3, 0.3), r:NextNumber(-1, 1)) * CFG.Spin

	a.phase = "Flying"
	a.releasedAt = os.clock()
	used += a.cost
	table.insert(flying, a)
	Remotes.StructureFX:FireAllClients("collapse", a.center, math.clamp(a.volume / 4000, 0.2, 1))
	log("%s: grupa %s leci (P%d, koszt %d, kawałków %d, pasażerów %d, filtr %d, budżet %d/%d)",
		a.rec.id, a.def.groupId, a.priority, a.cost, #pieces, #followers, #a.filters, used, CFG.MaxCost)
	return true
end

-- Ponad budżet: wynik strukturalny i tak się dzieje (kolizja grupy znika), tylko upadek
-- animują klienci zamiast fizyki serwera.
local function degrade(a: Active)
	local pieces = takePieces(a)
	for _, f in ipairs(takeFollowers(a)) do
		table.insert(pieces, f)
	end
	if deps and #pieces > 0 then
		deps.handOff(pieces, a.center, false)
	end
	a.rec.state:retire(a.def.chunkIds)
	a.phase = "Gone"
	log("%s: grupa %s ponad budżet (P%d, koszt %d, zajęte %d/%d) — upadek u klientów", a.rec.id, a.def.groupId, a.priority, a.cost, used, CFG.MaxCost)
end

local function fits(a: Active): boolean
	local free = CFG.MaxCost - used - (if a.priority == 0 then 0 else CFG.ReserveP0)
	return a.cost <= free
end

-- ============================================================================
-- Lot → osiadanie / lawa / przygniecenie
-- ============================================================================

local function finishFlight(a: Active)
	local i = table.find(flying, a)
	if i then
		table.remove(flying, i)
	end
	used = math.max(0, used - a.cost) -- zwrot budżetu dokładnie raz: tylko przy wyjściu z listy lotu
end

local function destroyGroup(a: Active)
	for _, p in ipairs(a.pieces) do
		if p.Parent then p:Destroy() end
	end
	for _, f in ipairs(a.followers) do
		if f.Parent then f:Destroy() end
	end
	a.rec.state:retire(a.def.chunkIds)
	a.phase = "Gone"
end

local function settle(a: Active)
	finishFlight(a)
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			p.Anchored = true
			rubbleOf[p] = a
			flyingOf[p] = nil
		end
	end
	for _, f in ipairs(a.followers) do
		if f.Parent then
			f.Anchored = true
			f.Massless = false
			f.CanCollide = a.followerCollide[f] ~= false
			rubbleOf[f] = a
			flyingOf[f] = nil
		end
	end
	for _, nc in ipairs(a.filters) do
		nc:Destroy()
	end
	table.clear(a.filters)
	a.rec.state:settle(a.def.chunkIds)
	a.phase = "Settled"
	a.stillSince = nil
	if a.volume < CFG.SmallRubbleVolume then
		a.retireAt = os.clock() + CFG.SmallRubbleLifetime
		table.insert(settledTemp, a)
	end
	log("%s: grupa %s osiadła po %.1f s (%s)", a.rec.id, a.def.groupId, os.clock() - a.releasedAt,
		if a.retireAt then "mała — zniknie" else "platforma do końca rundy")
end

local function groupTop(a: Active): number
	local top = -math.huge
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			top = math.max(top, Pieces.boxOf(p).max.Y)
		end
	end
	return top
end

local function crushCheck(dt: number)
	if #flying == 0 then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerService.isAlive(player) then continue end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end
		for _, a in ipairs(flying) do
			local hit = false
			for _, p in ipairs(a.pieces) do
				if not p.Parent then continue end
				local v = p.AssemblyLinearVelocity
				local speed = v.Magnitude
				if speed < CFG.CrushSpeed then continue end
				-- Kontakt z zapasem na drogę przebytą między sprawdzeniami (szybka płyta
				-- przelatuje kilka studów na tick).
				local d = Fracture.boxSurfaceDistance(Vector3.zero, p.Size, p.CFrame:PointToObjectSpace(hrp.Position))
				if d > CFG.CrushContact + speed * dt then continue end
				-- Musi lecieć W gracza — jeździec na górze ma prędkość bryły od siebie (dot < 0).
				if v:Dot(hrp.Position - p.Position) <= 0 then continue end
				local volumeT = math.clamp(a.volume / CFG.CrushVolumeForMax, 0, 1)
				local speedT = math.clamp(speed / CFG.CrushSpeedForMax, 0, 1)
				local dmg = math.max(CFG.CrushMinDamage, CFG.CrushMaxDamage * volumeT * speedT)
				local attacker = if a.cause then a.cause.attackerUserId else nil
				if DebrisService.applyCrush(player, dmg, attacker, CFG.CrushMaxDamage) then
					log("przygniecenie %s: %.0f dmg (grupa %s, %.0f stud/s)", player.Name, dmg, a.def.groupId, speed)
				end
				hit = true
				break
			end
			if hit then break end
		end
	end
end

local function monitor(now: number, dt: number)
	local lava = LavaService.getSurfaceY()
	for i = #flying, 1, -1 do
		local a = flying[i]
		local root = a.root
		if not root or not root.Parent then
			finishFlight(a)
			destroyGroup(a)
			continue
		end
		if groupTop(a) < lava - CFG.LavaCullMargin then
			finishFlight(a)
			destroyGroup(a)
			log("%s: grupa %s zatonęła w lawie", a.rec.id, a.def.groupId)
			continue
		end
		local slow = root.AssemblyLinearVelocity.Magnitude < CFG.SettleSpeed
			and root.AssemblyAngularVelocity.Magnitude < CFG.SettleSpeed * 0.5
		if slow then
			a.stillSince = a.stillSince or now
		else
			a.stillSince = nil
		end
		if (a.stillSince and now - a.stillSince >= CFG.SettleTime) or now - a.releasedAt >= CFG.MaxFallTime then
			settle(a)
		end
	end
	for i = #settledTemp, 1, -1 do
		local a = settledTemp[i]
		if a.phase ~= "Settled" then
			table.remove(settledTemp, i)
		elseif (a.retireAt or math.huge) <= now or groupTop(a) < lava - CFG.LavaCullMargin then
			table.remove(settledTemp, i)
			destroyGroup(a)
		end
	end
	crushCheck(dt)
end

-- ============================================================================
-- Pętla
-- ============================================================================

local function step()
	for _, f in ipairs(StructuralService.flushAll()) do
		local result = f.result
		local cause = if result.plan then result.plan.cause else nil
		local darkened = table.clone(result.damaged)
		for _, id in ipairs(result.destroyed) do
			local rt = f.rec.state.rt[id]
			if rt.reason == "Crumbled" then
				crumble(f.rec, id, rt.cause or cause)
			else
				table.insert(darkened, id)
			end
		end
		if #darkened > 0 then
			darken(f.rec, darkened)
		end
		if result.plan then
			enqueue(f.rec, result.plan)
		end
	end

	-- Kolejka w ustalonej kolejności (jeźdźcy, bliskie, od dołu). Grupa bez miejsca CZEKA,
	-- aż osiadające grupy zwolnią budżet — dopiero po MaxQueueWait upadek przejmują klienci
	-- (test 24.09: natychmiastowe oddawanie klientom = górne piętra po prostu znikały).
	local now = os.clock()
	local released = 0
	while #queue > 0 and released < CFG.MaxReleasesPerFrame do
		local a = queue[1]
		if fits(a) then
			table.remove(queue, 1)
			if release(a) then
				released += 1
			end
		elseif now - a.queuedAt >= CFG.MaxQueueWait then
			table.remove(queue, 1)
			degrade(a)
		else
			break
		end
	end

	local period = 1 / CFG.MonitorHz
	if now - lastMonitor >= period then
		local dt = if lastMonitor > 0 then now - lastMonitor else period
		lastMonitor = now
		monitor(now, dt)
	end
end

-- ============================================================================
-- API dla DestructionService: zatrzymany gruz kolapsu budzi się od kolejnego wybuchu
-- ============================================================================

function CollapseService.isRubble(part: BasePart): boolean
	return rubbleOf[part] ~= nil
end

function CollapseService.isFlying(part: BasePart): boolean
	return flyingOf[part] ~= nil
end

-- Wybuch przy leżącej bryle: odkotwiczamy ją i pchamy falą (jeśli budżet pozwala).
-- Zwraca true, gdy bryła poleciała.
function CollapseService.wakeRubble(part: BasePart, center: Vector3, radius: number, impulse: number, minT: number): boolean
	local a = rubbleOf[part]
	if not a or a.phase ~= "Settled" or not a.root or not a.root.Parent then
		return false
	end
	a.priority = 2
	if not fits(a) then
		return false
	end
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			rubbleOf[p] = nil
			flyingOf[p] = a
			p.Anchored = false
		end
	end
	for _, f in ipairs(a.followers) do
		if f.Parent then
			rubbleOf[f] = nil
			flyingOf[f] = a
			f.CanCollide = false
			f.Massless = true
			f.Anchored = false
		end
	end
	local root = a.root :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local d = Fracture.boxSurfaceDistance(Vector3.zero, root.Size, root.CFrame:PointToObjectSpace(center))
	local linear, angular = Shockwave.velocity(root.Position, root.Size, center, d, radius, impulse, minT, Random.new())
	root.AssemblyLinearVelocity = linear
	root.AssemblyAngularVelocity = angular
	local i = table.find(settledTemp, a)
	if i then
		table.remove(settledTemp, i)
	end
	a.retireAt = nil
	a.phase = "Flying"
	a.releasedAt = os.clock()
	a.stillSince = nil
	used += a.cost
	table.insert(flying, a)
	return true
end

local function clearAll()
	-- Kawałki sprząta MapService (są w mapie) — tu tylko rejestry i budżet.
	table.clear(queue)
	table.clear(flying)
	table.clear(settledTemp)
	table.clear(rubbleOf)
	table.clear(flyingOf)
	used = 0
end

function CollapseService.init(injected: Injected)
	deps = injected
	RunService.Heartbeat:Connect(step)
	GameLoopService.RoundEnded:Connect(clearAll)
end

return CollapseService
