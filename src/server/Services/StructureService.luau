--!strict
-- StructureService.luau
-- SYSTEM DESTRUKCJI v2 — etap 4: KOLAPS SEKCJI BUDYNKU (DESTRUCTION_PLAN.md).
--
-- Różnica wobec passu podparcia w DestructionService (etap 2): tamten jest GEOMETRYCZNY
-- ("czy ten part czegokolwiek dotyka"), ten jest KONSTRUKCYJNY ("czy to piętro ma jeszcze
-- na czym stać"). Strop opierający się krawędzią o sąsiednią ścianę przejdzie test dotyku,
-- ale gdy padną filary pod nim — i tak ma runąć. To jest ten moment na klip.
--
-- MODEL (celowo prosty — nie symulujemy statyki):
--   budynek = folder/model pod Workspace.Map
--   pasmo   = filary (tag `Pillar`) o zbliżonej wysokości = jedno piętro
--   gdy padnie CollapseThreshold filarów pasma → wszystko POWYŻEJ pasma w tym budynku
--   odkotwicza się i leci w dół (dalej obsługuje je DebrisService: izolacja, usypianie,
--   fall-fracture, crush). Po drodze creak: ostrzeżenie przy CreakThreshold.
--
-- Snapshot struktury robimy PRZED każdą rundą, nie raz na boot — MapService po każdej
-- rundzie podmienia geometrię na świeże klony, więc stare referencje są martwe.
--
-- Ownership: ten service NIE niszczy niczego sam i nie liczy obrażeń. Dostaje sygnał
-- `notifyPillarDestroyed` od DestructionService i decyduje wyłącznie o kolapsie.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local GameLoopService = require(script.Parent.GameLoopService)
local DebrisService = require(script.Parent.DebrisService)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local StructureService = {}

local CFG = Config.Destruction
local COL = CFG.Collapse

local ATTACKER_ATTR = "BlastAttackerId"

local rng = Random.new()

type Band = {
	building: Instance,
	topY: number,       -- górna krawędź najwyższego filara pasma = poziom "podłogi wyżej"
	total: number,
	dead: number,
	collapsed: boolean,
	lastCreakAt: number,
	center: Vector3,    -- do FX (skąd leci trzeszczenie/rumble)
}

-- Filar → pasmo, do którego należy. Klucz to instancja: gdy MapService podmieni mapę,
-- stare wpisy zwyczajnie przestają być trafiane, a rescan buduje tabelę od zera.
local pillarBand: { [BasePart]: Band } = {}
local bands: { Band } = {}
local initialized = false

-- ============================================================================
-- Skan struktury
-- ============================================================================

-- Budynek = bezpośrednie dziecko Workspace.Map będące kontenerem (Folder/Model).
-- Filar leżący luzem pod Map (bez folderu) dostaje własny "budynek" = sam Map, czyli
-- działa, tylko bez podziału na budynki — wygodne przy testowych klockach Kacpra.
local function getBuildingOf(part: BasePart, map: Instance): Instance
	local node: Instance = part
	while node.Parent and node.Parent ~= map do
		node = node.Parent
	end
	return node.Parent == map and node or map
end

function StructureService.rescan()
	table.clear(pillarBand)
	table.clear(bands)

	if not COL.Enabled then return end
	local map = Workspace:FindFirstChild("Map")
	if not map then return end

	-- Filary pogrupowane per budynek, posortowane po Y — pasma tworzymy przez klastrowanie
	-- sąsiadów w pionie (BandTolerance), więc nie musimy nic zakładać o wysokości pięter.
	local byBuilding: { [Instance]: { BasePart } } = {}
	for _, inst in ipairs(CollectionService:GetTagged(CFG.PillarTag)) do
		if not inst:IsA("BasePart") then continue end
		if not inst:IsDescendantOf(map) then continue end
		local building = getBuildingOf(inst, map)
		local list = byBuilding[building]
		if not list then
			list = {}
			byBuilding[building] = list
		end
		table.insert(list, inst)
	end

	local bandCount = 0
	for building, pillars in pairs(byBuilding) do
		table.sort(pillars, function(a, b)
			return a.Position.Y < b.Position.Y
		end)

		local current: { BasePart } = {}
		local function flush()
			if #current == 0 then return end
			local topY = -math.huge
			local sum = Vector3.zero
			for _, p in ipairs(current) do
				topY = math.max(topY, p.Position.Y + Utils.worldHalfY(p))
				sum += p.Position
			end
			local band: Band = {
				building = building,
				topY = topY,
				total = #current,
				dead = 0,
				collapsed = false,
				lastCreakAt = 0,
				center = sum / #current,
			}
			for _, p in ipairs(current) do
				pillarBand[p] = band
			end
			table.insert(bands, band)
			bandCount += 1
			current = {}
		end

		for _, p in ipairs(pillars) do
			if #current > 0 and (p.Position.Y - current[#current].Position.Y) > COL.BandTolerance then
				flush()
			end
			table.insert(current, p)
		end
		flush()
	end

	if CFG.Debug and bandCount > 0 then
		print(("[Struct] zeskanowano %d pasm filarów w %d budynkach"):format(
			bandCount, (function()
				local n = 0
				for _ in pairs(byBuilding) do n += 1 end
				return n
			end)()))
	end
end

-- ============================================================================
-- Kolaps
-- ============================================================================

local function collapseBand(band: Band, attackerId: number)
	band.collapsed = true

	-- Wszystko powyżej poziomu pasma W TYM budynku leci. Bierzemy dolną krawędź parta,
	-- nie środek — strop leżący NA filarach ma środek wyżej, ale dołem stoi dokładnie
	-- na `topY`; margines 0.5 stud łapie go razem z resztą piętra.
	local victims: { BasePart } = {}
	for _, desc in ipairs(band.building:GetDescendants()) do
		if not desc:IsA("BasePart") then continue end
		if not desc.Anchored then continue end
		if desc.Locked then continue end
		if DebrisService.isRegistered(desc) then continue end
		if desc.Position.Y - Utils.worldHalfY(desc) < band.topY - 0.5 then continue end
		table.insert(victims, desc)
		if #victims >= COL.MaxPartsPerCollapse then break end
	end

	if #victims == 0 then return 0 end

	-- Miejsce w rejestrze gruzu ZANIM oddamy piętro fizyce (2026-09-13). Kolaps to
	-- największy jednorazowy zastrzyk partów w całej grze — bez rezerwacji wypychałby
	-- z budżetu sam siebie: pierwsze odkotwiczone kawałki kasowałyby ostatnie.
	DebrisService.reserve(#victims)

	local folder = DebrisService.getFolder()
	for _, part in ipairs(victims) do
		-- Joints przed odkotwiczeniem — piętra bywają zweldowane w modele.
		for _, joint in ipairs(part:GetJoints()) do
			if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
				joint:Destroy()
			end
		end
		part.Anchored = false
		part:SetAttribute(ATTACKER_ATTR, attackerId)
		part.Parent = folder
		DebrisService.register(part)
		-- Lekki rozrzut na boki: sekcja "odrywa się" i wali, zamiast zjeżdżać jak winda.
		part.AssemblyLinearVelocity = Vector3.new(
			rng:NextNumber(-1, 1),
			0,
			rng:NextNumber(-1, 1)
		) * COL.ImpulseSpread
		part.AssemblyAngularVelocity = Vector3.new(
			rng:NextNumber(-1, 1),
			rng:NextNumber(-1, 1),
			rng:NextNumber(-1, 1)
		) * 1.5
	end

	Remotes.StructureFX:FireAllClients("collapse", band.center, math.min(#victims / 60, 1))

	if CFG.Debug then
		print(("[Struct] KOLAPS sekcji: %s, pasmo topY=%.1f, %d partów leci"):format(
			band.building.Name, band.topY, #victims))
	end
	return #victims
end

-- ============================================================================
-- API dla DestructionService
-- ============================================================================

-- Wołane gdy zniszczony zostaje part z tagiem Pillar. Zwraca true, gdy to wywołało kolaps.
function StructureService.notifyPillarDestroyed(part: BasePart, attackerId: number): boolean
	if not COL.Enabled then return false end
	local band = pillarBand[part]
	if not band or band.collapsed then return false end

	pillarBand[part] = nil
	band.dead += 1
	local ratio = band.dead / band.total

	if ratio >= COL.CollapseThreshold then
		collapseBand(band, attackerId)
		return true
	end

	if ratio >= COL.CreakThreshold then
		local now = os.clock()
		if now - band.lastCreakAt >= COL.CreakCooldown then
			band.lastCreakAt = now
			-- Ostrzeżenie: pył ze stropów + trzeszczenie + mikro-shake. Telegrafuje
			-- "stąd trzeba spadać", zamiast zabijać bez zapowiedzi.
			Remotes.StructureFX:FireAllClients("creak", band.center, ratio)
			if CFG.Debug then
				print(("[Struct] creak: %s, pasmo topY=%.1f, filary %d/%d martwe"):format(
					band.building.Name, band.topY, band.dead, band.total))
			end
		end
	end
	return false
end

function StructureService.init()
	if initialized then return end
	initialized = true

	StructureService.rescan()

	-- MapService odtwarza mapę 0.5s po RoundEnded, tworząc ŚWIEŻE klony partów — stare
	-- referencje w pillarBand są wtedy martwe. COUNTDOWN jest bezpiecznie po restorze
	-- (POST_ROUND trwa 10s), a jednocześnie przed pierwszą bombą następnej rundy.
	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == GameLoopService.STATE.COUNTDOWN then
			StructureService.rescan()
		end
	end)
end

return StructureService
