--!strict
-- StructuralService.luau
-- DESTRUKCJA v4, faza D — JEDYNY właściciel stanu konstrukcji budynków v4 w rundzie.
-- Plan, decyzje i pomiary: DESTRUCTION_PLAN.md → „v4”.
--
-- Trzyma, dla każdego budynku z `Config.Structure.Buildings`:
--   * BuildingState (który chunk stoi, jest osłabiony, zniszczony, spada)
--   * KAWAŁKI: fizyczne party, które dziś tworzą każdy part konstrukcji z bake'u (dziura
--     dzieli part na pasy, kolaps odcina go po granicy chunków, bomba wycina odcinek listwy)
--   * OPARCIE LISTEW (26.09): listwa zostaje, póki dotyka czegoś stojącego — pass
--     `takeUnsupportedStrips` po każdej zmianie budynku oddaje te, które straciły ostatnie
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
	-- Listwa/ozdoba → party, których dotyka (bake: TrimLinks). Mówi tylko, KOGO sprawdzać;
	-- czy dalej dotyka, liczy pass podparcia na dzisiejszych kawałkach.
	stripLinks: { [number]: { number } },
	-- Listwy bez oparcia już w NIETKNIĘTYM budynku (tak je postawiono) — pass ich nie zrzuca.
	designFloating: { [number]: boolean },
	min: Vector3, -- prostopadłościan budynku (szybki filtr wybuchu)
	max: Vector3,
	source: string, -- "baked" | "live"
}

type Owner = { rec: Rec, index: number }
export type StripPiece = { index: number, piece: BasePart }

local buildings: { [string]: Rec } = {}
-- Kawałek → (budynek, part). Słabe klucze: skasowany kawałek sam wypada.
local owners: { [BasePart]: Owner } = setmetatable({}, { __mode = "k" }) :: any
local causeSeq = 0
local rng = Random.new()

-- ============================================================================
-- Oparcie listew (26.09, decyzja Kacpra: „zostaje, póki dotyka czegoś stojącego”)
-- ============================================================================

local STRIP_PAD = CFG.ContactPadding

-- Ta sama definicja styku co w bake'u (`Core.intersect`: szczelina do 2 × luz). Własna, ciaśniejsza
-- wersja (≤ 1 × luz) gubiła styki, które bake zapisał w TrimLinks — test 26.09: podkłady torów
-- leżą 0,2 studa nad belkami i wszystkie wyszły jako „wiszące w projekcie”.
local function touches(a: Pieces.Box, b: Pieces.Box): boolean
	return Core.intersect(a.min, a.max, b.min, b.max, STRIP_PAD) ~= nil
end

-- Kawałki listew bez drogi do stojącej konstrukcji. BFS po DZISIEJSZYCH kawałkach: start =
-- kawałek listwy dotykający kawałka konstrukcji, dalej przez styki listwa↔listwa (szczebel
-- trzyma się szyny, szyna stropu). Styk sprawdzamy na pudełkach kawałków, nie partów: dziura
-- albo wycięty odcinek mógł zabrać akurat miejsce styku. Pełny pass na OrangeBuilding
-- (193 listwy, 583 styki) = 0,15 ms (pomiar 26.09), więc liczymy zawsze cały budynek.
local function unsupportedStrips(rec: Rec): { StripPiece }
	local STRUCTURAL = Core.STRUCTURAL
	local live: { [number]: { BasePart } } = {}
	local function piecesOf(index: number): { BasePart }
		local list = live[index]
		if not list then
			list = StructuralService.piecesOf(rec, index)
			live[index] = list
		end
		return list
	end
	local boxes: { [BasePart]: Pieces.Box } = {}
	local function boxOf(p: BasePart): Pieces.Box
		local b = boxes[p]
		if not b then
			b = Pieces.boxOf(p)
			boxes[p] = b
		end
		return b
	end

	local supported: { [BasePart]: boolean } = {}
	local queue: { StripPiece } = {}
	for index, links in pairs(rec.stripLinks) do
		for _, piece in ipairs(piecesOf(index)) do
			if not piece.Anchored then continue end
			for _, other in ipairs(links) do
				if not STRUCTURAL[rec.parts[other].kind] then continue end
				for _, q in ipairs(piecesOf(other)) do
					if q.Anchored and touches(boxOf(piece), boxOf(q)) then
						supported[piece] = true
						break
					end
				end
				if supported[piece] then break end
			end
			if supported[piece] then
				table.insert(queue, { index = index, piece = piece })
			end
		end
	end
	local qi = 1
	while qi <= #queue do
		local cur = queue[qi]
		qi += 1
		for _, other in ipairs(rec.stripLinks[cur.index]) do
			if STRUCTURAL[rec.parts[other].kind] then continue end
			for _, q in ipairs(piecesOf(other)) do
				if not supported[q] and q.Anchored and touches(boxOf(cur.piece), boxOf(q)) then
					supported[q] = true
					table.insert(queue, { index = other, piece = q })
				end
			end
		end
	end

	local out: { StripPiece } = {}
	for index in pairs(rec.stripLinks) do
		for _, piece in ipairs(piecesOf(index)) do
			if not supported[piece] then
				table.insert(out, { index = index, piece = piece })
			end
		end
	end
	return out
end

-- ============================================================================
-- Goście budynku (26.09, decyzja Kacpra: „tylko ten kawałek torów, nie całe”)
-- ============================================================================
-- Party spoza budynku (tory z `OutsideDecorations.Railway`), których kawałek leży w obrysie
-- budynku, są jego LISTWAMI: stoją, póki dotykają czegoś stojącego, i spadają z budynkiem.
-- Szyna idzie przez pół mapy jednym partem, więc dzielimy ją na granicy obrysu: środek jest
-- gościem, końce zostają poza v4. Dzielenie jest idempotentne — StructuralService.init rusza
-- przed MapService.init, więc migawka mapy (i każde przywrócenie po rundzie) ma już
-- podzielone szyny, a kawałek na samej granicy obrysu tylko go muska i jest pomijany.

-- Przedział wzdłuż NAJDŁUŻSZEJ osi parta, na którym jego oś środkowa leży w obrysie.
local function spanInside(part: BasePart, bmin: Vector3, bmax: Vector3): (number?, number, number, number)
	local size = part.Size
	local dims = { size.X, size.Y, size.Z }
	local long = 1
	for i = 2, 3 do
		if dims[i] > dims[long] then
			long = i
		end
	end
	local cf = part.CFrame
	-- ⚠️ Oś +Z parta to −LookVector (LookVector patrzy w −Z). Z LookVector szyna była cięta
	-- w lustrzanym miejscu: środek lądował poza budynkiem (test 26.09).
	local axis = if long == 1 then cf.RightVector elseif long == 2 then cf.UpVector else -cf.LookVector
	local h = dims[long] * 0.5
	local t0, t1 = -h, h
	for _, k in ipairs({ "X", "Y", "Z" }) do
		local a = Core.component(axis, k)
		local c = Core.component(cf.Position, k)
		local lo, hi = Core.component(bmin, k), Core.component(bmax, k)
		if math.abs(a) < 1e-6 then
			if c < lo or c > hi then
				return nil, 0, long, h
			end
		else
			local u0, u1 = (lo - c) / a, (hi - c) / a
			t0, t1 = math.max(t0, math.min(u0, u1)), math.min(t1, math.max(u0, u1))
		end
	end
	if t1 - t0 < D.MinStrip then
		return nil, 0, long, h
	end
	return t0, t1, long, h
end

local function addGuests(rec: Rec, map: Instance, names: { string }): number
	local added: { number } = {}
	local isGuest: { [number]: boolean } = {}
	for _, name in ipairs(names) do
		local folder = map:FindFirstChild(name, true)
		if not folder then
			warn(("[Structure] %s: folder gości %q nie istnieje w mapie"):format(rec.id, name))
			continue
		end
		for _, d in ipairs(folder:GetDescendants()) do
			-- `owners`: kawałek toru należy już do drugiego budynku (tory idą przez oba).
			if not d:IsA("BasePart") or owners[d] then continue end
			local t0, t1, long, h = spanInside(d, rec.min, rec.max)
			if not t0 then continue end
			-- Końcówka krótsza niż MinStrip idzie z gościem (jak pasy dziury).
			if t0 + h < D.MinStrip then t0 = -h end
			if h - t1 < D.MinStrip then t1 = h end
			if t0 > -h or t1 < h then
				local cf, size = d.CFrame, d.Size
				local dims = { size.X, size.Y, size.Z }
				local function box(lo: number, hi: number): (CFrame, Vector3)
					local off = { 0, 0, 0 }
					local sz = table.clone(dims)
					off[long], sz[long] = (lo + hi) * 0.5, hi - lo
					return cf * CFrame.new(off[1], off[2], off[3]), Vector3.new(sz[1], sz[2], sz[3])
				end
				if t0 > -h then
					Pieces.spawn(d, box(-h, t0))
				end
				if t1 < h then
					Pieces.spawn(d, box(t1, h))
				end
				local midCf, midSize = box(t0, t1)
				d.Size = midSize
				d.CFrame = midCf
			end
			local index = #rec.parts + 1
			local mn, mx = Core.worldBox(d)
			rec.parts[index] = { inst = d, index = index, min = mn, max = mx, kind = "Trim", permanent = false, chunks = {} }
			rec.pieces[index] = { d }
			owners[d] = { rec = rec, index = index }
			table.insert(added, index)
			isGuest[index] = true
		end
	end
	-- Styki gościa z każdym partem budynku (i innym gościem), którego dotyka. Listwa budynku
	-- dostaje link zwrotny — oparcie płynie po łańcuchu w obie strony.
	local pad = CFG.ContactPadding
	for _, g in ipairs(added) do
		local G = rec.parts[g]
		local links: { number } = rec.stripLinks[g] or {}
		rec.stripLinks[g] = links
		for _, q in ipairs(rec.parts) do
			if q.index == g or not Core.intersect(G.min, G.max, q.min, q.max, pad) then continue end
			table.insert(links, q.index)
			if not Core.STRUCTURAL[q.kind] and not isGuest[q.index] then
				local back = rec.stripLinks[q.index]
				if not back then
					back = {}
					rec.stripLinks[q.index] = back
				end
				table.insert(back, g)
			end
		end
	end
	return #added
end

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
	local first = true
	for id, own in pairs(CFG.Buildings) do
		-- Jeden budynek na klatkę (27.09): analiza na żywo to 3-34 ms na budynek, przy dziewięciu
		-- ~150 ms przycięcia serwera w jednej klatce. Rebuild idzie przy starcie i na COUNTDOWN,
		-- kiedy bomb nie ma, więc chwilowo niepełna lista budynków niczego nie psuje.
		if not first then
			task.wait()
		end
		first = false
		local folder = root:FindFirstChild(id)
		if not folder then
			warn(("[Structure] budynek %s z Config.Structure.Buildings nie istnieje w mapie"):format(id))
			continue
		end
		local bcfg = Core.buildingConfig(CFG, id)
		local parts = Core.collectParts(folder, bcfg, Config.Destruction.Small)
		local data, dataParts, source = loadData(id, folder, parts)
		if not data then
			continue -- brak danych → budynek zostaje na v3
		end
		-- Degradacja z bake'u (DemoteUnsupported): w danych liczonych na żywo już jest,
		-- w zapisanych — tylko lista, bo `collectParts` jej nie zna.
		for _, idx in ipairs(data.Demoted or {}) do
			dataParts[idx].kind = "Trim"
		end
		-- Solver w grze liczy TYMI SAMYMI ustawieniami budynku co bake (MaxSpan per budynek, 27.09)
		-- — inaczej budynek, który w bake'u stoi, w grze od razu miałby czerwone chunki.
		local bconfig = table.clone(Config)
		bconfig.Structure = bcfg
		local state = BuildingState.new(data, bconfig)
		if not state.enabled then
			warn(("[Structure] %s: nietknięty budynek NIE stoi (%d chunków bez podpory) — kolaps wyłączony, dziury działają. Sprawdź STRUCTURE_BAKE."):format(id, state.baselineFalling))
		end
		local rec: Rec = {
			id = id,
			folder = folder,
			state = state,
			parts = dataParts,
			pieces = {},
			stripLinks = {},
			designFloating = {},
			min = Vector3.one * math.huge,
			max = -Vector3.one * math.huge,
			source = source,
		}
		for _, p in ipairs(dataParts) do
			rec.pieces[p.index] = { p.inst }
			owners[p.inst] = { rec = rec, index = p.index }
			rec.min = rec.min:Min(p.min)
			rec.max = rec.max:Max(p.max)
		end
		for _, l in ipairs(data.TrimLinks or {}) do
			for k = 1, 2 do
				local from, to = l[k], l[3 - k]
				if Core.STRUCTURAL[dataParts[from].kind] then continue end
				local list = rec.stripLinks[from]
				if not list then
					list = {}
					rec.stripLinks[from] = list
				end
				table.insert(list, to)
			end
		end
		local guests = if typeof(own) == "table" and own.Guests and map then addGuests(rec, map, own.Guests) else 0
		-- Stan „przed” dla passu podparcia listew: to, co wisi już w projekcie, zostaje (także
		-- gość, który budynku nie dotyka — np. filar toru stojący w obrysie na gruncie).
		local floating = 0
		for _, u in ipairs(unsupportedStrips(rec)) do
			if not rec.designFloating[u.index] then
				floating += 1
			end
			rec.designFloating[u.index] = true
		end
		buildings[id] = rec
		if CFG.Collapse.Debug then
			print(("[Structure] %s: %d partów (+%d gości, %d zdegradowanych), %d chunków, wiszących w projekcie %d, dane: %s, kolaps %s"):format(
				id, #dataParts - guests, guests, #(data.Demoted or {}), #state.chunks, floating, source,
				if state.enabled then "włączony" else "WYŁĄCZONY"))
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

-- Instancja oddawana klientom W CAŁOŚCI (ozdoba, szyba, mebel z drobnicy): jej kawałki
-- przestają być częścią budynku OD RAZU. Skasuje ją dopiero `HandoffDelay`, a do tego czasu
-- pass podparcia liczyłby ją jako oparcie — listwa, która trzymała się tylko jej, zostałaby
-- w powietrzu.
function StructuralService.releaseInstance(inst: Instance)
	local function release(p: Instance)
		if p:IsA("BasePart") then
			local o = owners[p]
			if o then
				StructuralService.releasePiece(o.rec, o.index, p)
			end
		end
	end
	release(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		release(d)
	end
end

-- Zwalnia z budynku i zwraca kawałki listew, które straciły OSTATNIE oparcie (wołający
-- oddaje je klientom albo zabiera z grupą kolapsu). Wołają: DestructionService po wybuchu,
-- CollapseService po kruszeniu i przy starcie grupy.
function StructuralService.takeUnsupportedStrips(rec: Rec): { StripPiece }
	local out: { StripPiece } = {}
	for _, u in ipairs(unsupportedStrips(rec)) do
		if rec.designFloating[u.index] then continue end
		StructuralService.releasePiece(rec, u.index, u.piece)
		table.insert(out, u)
	end
	return out
end

-- To samo dla każdego budynku w zasięgu wybuchu.
function StructuralService.takeUnsupportedStripsNear(center: Vector3, radius: number): { BasePart }
	local out: { BasePart } = {}
	for _, rec in pairs(buildings) do
		if Core.boxDistance(rec.min, rec.max, center) < radius then
			for _, u in ipairs(StructuralService.takeUnsupportedStrips(rec)) do
				table.insert(out, u.piece)
			end
		end
	end
	return out
end

-- ============================================================================
-- Wybuch (woła DestructionService)
-- ============================================================================

-- Listwa, z której bomba wycina odcinek (decyzja Kacpra 26.09): zwykły prostopadłościan
-- budynku v4, który nie jest konstrukcją ani szkłem. Szkło tłucze pass szyb; MeshPart, klin
-- czy walec nie dają się przyciąć pudełkiem — te padają w całości, jak drobnica.
function StructuralService.isCuttableStrip(part: BasePart): boolean
	local o = owners[part]
	if not o or Core.STRUCTURAL[o.rec.parts[o.index].kind] then
		return false
	end
	return part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block and part.Material ~= Enum.Material.Glass
end

-- Wycina z listwy odcinek, na którym wybuch przekracza jej próg (`breakRadius` = zasięg
-- progu): na wylot przez przekrój, wzdłuż najdłuższej osi. Półdługość odcinka √(R² − d⊥²),
-- gdzie d⊥ to odległość epicentrum od listwy w przekroju. Resztki zostają w budynku (oryginał
-- tam, gdzie stoją gracze), wycięty odcinek wraca do wołającego — idzie do klientów. Krótka
-- listwa (szczebel) wraca cała. nil = wybuch jej nie sięga.
function StructuralService.cutStrip(part: BasePart, center: Vector3, breakRadius: number, feetWorld: { Vector3 }): BasePart?
	local o = owners[part]
	if not o then
		return nil
	end
	local rec, index = o.rec, o.index
	local cf, size = part.CFrame, part.Size
	local lc = cf:PointToObjectSpace(center)
	local dims = { size.X, size.Y, size.Z }
	local cs = { lc.X, lc.Y, lc.Z }
	local long = 1
	for i = 2, 3 do
		if dims[i] > dims[long] then
			long = i
		end
	end
	local perp2 = 0
	for i = 1, 3 do
		if i ~= long then
			local e = math.max(math.abs(cs[i]) - dims[i] * 0.5, 0)
			perp2 += e * e
		end
	end
	local reach2 = breakRadius * breakRadius - perp2
	-- Trafiona listwa traci zawsze choć tyle, żeby było widać, że pękła.
	local half = math.max(if reach2 > 0 then math.sqrt(reach2) else 0, D.MinStrip * 0.5)
	local h = dims[long] * 0.5
	local v0 = math.max(cs[long] - half, -h)
	local v1 = math.min(cs[long] + half, h)
	if v0 >= v1 then
		return nil
	end
	-- Końcówka krótsza niż MinStrip nie zostaje (jak pasy dziury w ścianie).
	if v0 + h < D.MinStrip then v0 = -h end
	if h - v1 < D.MinStrip then v1 = h end

	local function box(lo: number, hi: number): { offset: Vector3, size: Vector3 }
		local off = { 0, 0, 0 }
		local sz = { dims[1], dims[2], dims[3] }
		off[long], sz[long] = (lo + hi) * 0.5, hi - lo
		return { offset = Vector3.new(off[1], off[2], off[3]), size = Vector3.new(sz[1], sz[2], sz[3]) }
	end
	local rem: { { offset: Vector3, size: Vector3 } } = {}
	if v0 > -h then table.insert(rem, box(-h, v0)) end
	if v1 < h then table.insert(rem, box(v1, h)) end
	if #rem == 0 then
		StructuralService.releasePiece(rec, index, part)
		return part
	end
	local cut = box(v0, v1)
	local segment = Pieces.spawn(part, cf * CFrame.new(cut.offset), cut.size)
	local reuse = Pieces.pickReuse(rem, cf, feetWorld)
	-- Nowe resztki PRZED przycięciem oryginału — gracz na oryginale nie traci gruntu.
	for i, b in ipairs(rem) do
		if i ~= reuse then
			StructuralService.addPiece(rec, index, Pieces.spawn(part, cf * CFrame.new(b.offset), b.size))
		end
	end
	part.Size = rem[reuse].size
	part.CFrame = cf * CFrame.new(rem[reuse].offset)
	return segment
end

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
