--!strict
-- StructuralService.luau
-- DESTRUKCJA v4, faza D — JEDYNY właściciel stanu konstrukcji budynków v4 w rundzie.
-- Plan, decyzje i pomiary: DESTRUCTION_PLAN.md → „v4”.
--
-- Trzyma, dla każdego budynku z `Config.Structure.Buildings`:
--   * BuildingState (który chunk stoi, jest osłabiony, zniszczony, spada)
--   * KAWAŁKI: fizyczne party, które dziś tworzą każdy part konstrukcji z bake'u (dziura
--     dzieli part na pasy, kolaps odcina go po granicy chunków)
-- Reszta mapy zostaje na v3 — DestructionService pyta `ownerOf`, zanim zdecyduje, którą
-- ścieżką idzie part.
--
-- KIERUNEK ZALEŻNOŚCI (bez cykli):
--   DestructionService → StructuralService (tnie dziury, zadaje obrażenia)
--   CollapseService    → StructuralService (co klatkę `flushAll`, potem wykonuje wynik)
-- Ten serwis nie wie nic o fizyce, graczach ani efektach — tylko stan i geometria dziur.
--
-- CYKL RUNDY: MapService po rundzie podmienia mapę na świeże klony, więc stare instancje
-- są martwe. Budynki budujemy od nowa przy starcie i na każdym COUNTDOWN (bomb wtedy nie
-- ma — rzucać można tylko w ROUND).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local GameLoopService = require(script.Parent.GameLoopService)

local Structure = script.Parent.Parent.Structure
local Core = require(Structure.StructureCore)
local StructureBake = require(Structure.StructureBake)
local BuildingState = require(Structure.BuildingState)
local Pieces = require(Structure.Pieces)

local StructuralService = {}

local CFG = Config.Structure
local D = CFG.Damage

type BuildingState = BuildingState.BuildingState
export type Cause = BuildingState.Cause

export type Rec = {
	id: string,
	folder: Instance,
	state: BuildingState,
	parts: { Core.PartRec }, -- indeks = SID z bake'u
	pieces: { [number]: { BasePart } }, -- part → jego dzisiejsze kawałki
	attachedTo: { [number]: { number } }, -- chunk → listwy/szyby (indeksy partów), które na nim wiszą
	min: Vector3, -- prostopadłościan budynku (szybki filtr wybuchu)
	max: Vector3,
	source: string, -- "baked" | "live"
}

type Owner = { rec: Rec, index: number }

local buildings: { [string]: Rec } = {}
-- Kawałek → (budynek, part). Słabe klucze: skasowany kawałek sam wypada.
local owners: { [BasePart]: Owner } = setmetatable({}, { __mode = "k" }) :: any
local causeSeq = 0
local rng = Random.new()

-- ============================================================================
-- Budowa budynków (start serwera + każdy COUNTDOWN)
-- ============================================================================

local function loadData(id: string, folder: Instance, parts: { Core.PartRec }): (any?, { Core.PartRec }, string)
	local store = ServerStorage:FindFirstChild("StructureData")
	local saved = store and store:FindFirstChild(id)
	if saved and saved:IsA("ModuleScript") then
		local ok, data = pcall(require, saved)
		if ok and typeof(data) == "table" then
			if data.BakeVersion == CFG.BakeVersion and data.GeometryHash == Core.geometryHash(parts) then
				return data, parts, "baked"
			end
			warn(("[Structure] %s: zapisane dane NIE pasują do mapy (wersja bake'u albo odcisk geometrii) — zrób ponownie STRUCTURE_BAKE TRYB 3"):format(id))
		end
	end
	if not CFG.AnalyzeIfMissing then
		return nil, parts, "none"
	end
	local result = StructureBake.analyze(folder, Config)
	return StructureBake.toData(result, Config), result.parts, "live"
end

function StructuralService.rebuild()
	table.clear(buildings)
	table.clear(owners)
	local map = Workspace:FindFirstChild("Map")
	local root = map and map:FindFirstChild("Buildings", true)
	if not root then
		warn("[Structure] nie ma folderu Buildings w Workspace.Map — destrukcja v4 wyłączona")
		return
	end
	for id in pairs(CFG.Buildings) do
		local folder = root:FindFirstChild(id)
		if not folder then
			warn(("[Structure] budynek %s z Config.Structure.Buildings nie istnieje w mapie"):format(id))
			continue
		end
		local parts = Core.collectParts(folder, CFG, Config.Destruction.Small)
		local data, dataParts, source = loadData(id, folder, parts)
		if not data then
			continue -- brak danych → budynek zostaje na v3
		end
		local state = BuildingState.new(data, Config)
		if not state.enabled then
			warn(("[Structure] %s: nietknięty budynek NIE stoi (%d chunków bez podpory) — kolaps wyłączony, dziury działają. Sprawdź STRUCTURE_BAKE."):format(id, state.baselineFalling))
		end
		local rec: Rec = {
			id = id,
			folder = folder,
			state = state,
			parts = dataParts,
			pieces = {},
			attachedTo = {},
			min = Vector3.one * math.huge,
			max = -Vector3.one * math.huge,
			source = source,
		}
		for _, a in ipairs(data.Attachments) do
			local list = rec.attachedTo[a.owner]
			if not list then
				list = {}
				rec.attachedTo[a.owner] = list
			end
			table.insert(list, a.part)
		end
		for _, p in ipairs(dataParts) do
			rec.pieces[p.index] = { p.inst }
			owners[p.inst] = { rec = rec, index = p.index }
			rec.min = rec.min:Min(p.min)
			rec.max = rec.max:Max(p.max)
		end
		buildings[id] = rec
		if CFG.Collapse.Debug then
			print(("[Structure] %s: %d partów, %d chunków, dane: %s, kolaps %s"):format(
				id, #dataParts, #state.chunks, source, if state.enabled then "włączony" else "WYŁĄCZONY"))
		end
	end
end

-- ============================================================================
-- Odczyt
-- ============================================================================

-- (budynek, indeks parta, "structure" | "attached") — albo nil, gdy part nie jest v4.
function StructuralService.ownerOf(part: BasePart): (Rec?, number?, string?)
	local o = owners[part]
	if not o then
		return nil, nil, nil
	end
	local kind = if Core.STRUCTURAL[o.rec.parts[o.index].kind] then "structure" else "attached"
	return o.rec, o.index, kind
end

function StructuralService.buildings(): { [string]: Rec }
	return buildings
end

-- Listwy i szyby wiszące na chunku (indeksy partów).
function StructuralService.attachmentsOf(rec: Rec, chunkId: number): { number }
	return rec.attachedTo[chunkId] or {}
end

-- Dzisiejsze kawałki parta (skasowane odfiltrowane).
function StructuralService.piecesOf(rec: Rec, index: number): { BasePart }
	local list = rec.pieces[index]
	if not list then
		return {}
	end
	local alive: { BasePart } = {}
	for _, p in ipairs(list) do
		if p.Parent then
			table.insert(alive, p)
		end
	end
	rec.pieces[index] = alive
	return alive
end

function StructuralService.addPiece(rec: Rec, index: number, part: BasePart)
	local list = rec.pieces[index]
	if not list then
		list = {}
		rec.pieces[index] = list
	end
	table.insert(list, part)
	owners[part] = { rec = rec, index = index }
end

-- Kawałek przestaje być konstrukcją (spada, kruszy się) — wybuch nie potraktuje go
-- więcej jako części budynku.
function StructuralService.releasePiece(rec: Rec, index: number, part: BasePart)
	local list = rec.pieces[index]
	if list then
		local i = table.find(list, part)
		if i then
			table.remove(list, i)
		end
	end
	owners[part] = nil
end

-- ============================================================================
-- Wybuch (woła DestructionService)
-- ============================================================================

function StructuralService.newCause(attacker: Player?, center: Vector3): Cause
	causeSeq += 1
	return {
		causeId = causeSeq,
		attackerUserId = if attacker then attacker.UserId else 0,
		seq = causeSeq,
		time = os.clock(),
		center = center,
	}
end

-- Czy wybuch sięga któregoś budynku v4 (tani filtr przed pracą).
function StructuralService.anyNear(center: Vector3, radius: number): boolean
	for _, rec in pairs(buildings) do
		if Core.boxDistance(rec.min, rec.max, center) < radius then
			return true
		end
	end
	return false
end

-- Dziura-prostokąt w kawałku (kolizja v4, Fracture.planWindow). Oryginał zostaje przycięty
-- do pasa, na którym stoją gracze; pozostałe pasy to nowe kawałki. Zwraca payload dla
-- klientów (kawałki dziury animują oni) albo nil, gdy wybuch nie sięga kawałka.
function StructuralService.cutHole(part: BasePart, center: Vector3, holeRadius: number, cause: Cause, feetWorld: { Vector3 }): { [string]: any }?
	local o = owners[part]
	if not o or not Core.STRUCTURAL[o.rec.parts[o.index].kind] then
		return nil
	end
	local rec, index = o.rec, o.index
	local cf, size = part.CFrame, part.Size
	local lc = cf:PointToObjectSpace(center)
	local plan = Fracture.planWindow(size, lc, holeRadius, D.MinStrip)
	local hole = plan.hole
	if not hole then
		return nil
	end
	local hmin, hmax = Core.localBoxToWorld(cf, hole.offset, hole.size)
	local payload = {
		cf = cf,
		size = size,
		lc = lc,
		hole = holeRadius,
		seed = rng:NextInteger(1, 2_000_000_000),
		win = { offset = hole.offset, size = hole.size },
		color = part.Color,
		mat = part.Material,
		var = part.MaterialVariant,
		tr = part.Transparency,
	}

	local rem = plan.remnants
	if #rem == 0 then
		StructuralService.releasePiece(rec, index, part)
		part:Destroy()
	else
		local reuse = Pieces.pickReuse(rem, cf, feetWorld)
		-- Nowe pasy PRZED przycięciem oryginału — gracz na oryginale nie traci gruntu.
		for i, box in ipairs(rem) do
			if i ~= reuse then
				StructuralService.addPiece(rec, index, Pieces.spawn(part, cf * CFrame.new(box.offset), box.size))
			end
		end
		part.Size = rem[reuse].size
		part.CFrame = cf * CFrame.new(rem[reuse].offset)
	end
	rec.state:applyHole(index, hmin, hmax, cause)
	return payload
end

-- Obrażenia strukturalne (osłabianie — sumują się) dla każdego budynku w zasięgu.
function StructuralService.structuralDamage(center: Vector3, radius: number, damage: number, cause: Cause)
	for _, rec in pairs(buildings) do
		if Core.boxDistance(rec.min, rec.max, center) < radius then
			rec.state:applyStructuralDamage(center, radius, damage, cause)
		end
	end
end

-- ============================================================================
-- Flush (woła CollapseService raz na klatkę)
-- ============================================================================

export type Flushed = { rec: Rec, result: BuildingState.FlushResult }

function StructuralService.flushAll(): { Flushed }
	local out: { Flushed } = {}
	for _, rec in pairs(buildings) do
		local result = rec.state:flush()
		if result then
			table.insert(out, { rec = rec, result = result })
		end
	end
	return out
end

function StructuralService.init()
	StructuralService.rebuild()
	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == "COUNTDOWN" then
			StructuralService.rebuild()
		end
	end)
end

return StructuralService
