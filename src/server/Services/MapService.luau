--!strict
-- MapService.luau
-- Snapshot mapy przy starcie serwera, restore po każdej rundzie.
-- Po wybuchu bomby parts są unanchored + tumble po świecie. Bez restore mapa zostaje
-- w "rozjebanym" stanie kolejnej rundy.
--
-- Strategia (07.10 — ODBUDOWA TYLKO NARUSZONYCH JEDNOSTEK):
--   1. Init: mapa dzieli się na JEDNOSTKI (`Config.Map.RestoreGroups`: każdy budynek
--      i każda grupa dekoracji osobno). Każda jednostka ma klon w ServerStorage.MapSnapshot
--      i ODCISK: liczba partów, zakotwiczonych, z kolizją, z atrybutami obrażeń + sumy
--      pozycji, rozmiarów, osi i kolorów.
--   2. RoundEnded: kasujemy obce rzeczy podrzucone do kontenerów, a jednostkę stawiamy
--      od nowa TYLKO wtedy, gdy zniknęła albo jej odcisk się zmienił.
--
-- DLACZEGO NIE CAŁA MAPA (jak do 07.10): kasowanie i stawianie 25,6 tys. partów po
-- każdej rundzie wysyłało każdemu graczowi całe miasto jeszcze raz, a silnik liczył jego
-- cienie i oświetlenie od zera — przy 30 graczach i rundzie co ~2 min to stały skok
-- sieci. Nietknięty budynek zostaje tą samą instancją, więc klient nie dostaje nic.
--
-- ⚠️ Pułapka odcisku: wszystko, co runda zmienia na parcie mapy, MUSI być w odcisku,
-- inaczej zostanie na następną rundę. Obrażenia bez zmiany kształtu (HP + przyciemnienie)
-- łapią atrybuty `Config.Destruction.DamageAttributes` — kolor sam nie wystarczy, bo
-- ciemny part ciemniejący do ciemnego prawie nie zmienia koloru. Nowy rodzaj zmiany
-- (np. materiał, przezroczystość ustawiana przez serwer) = dopisać go w `fingerprint`.
--
-- Co NIE jest snapshotowane (nieruszane przez restore):
--   - Workspace.Map.Locked (Baseplate, Spawn, SpawnPoints, geometria nieusuwalna — bomba ich nie tyka)
--   - Workspace.Lobby, Workspace.Lava (osobne foldery pod Workspace)
--
-- Timing: czekamy RESTORE_DELAY po RoundEnded, żeby PlayerService.sendSurvivorsToLobby
-- (odpalany przez StateChanged → POST_ROUND, deferred BindableEvent) zdążył wyteleportować
-- żywych zanim wywalimy ich części pod nogami.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local GameLoopService = require(script.Parent.GameLoopService)

local MapService = {}

local SNAPSHOT_NAME = "MapSnapshot"
local RESTORE_DELAY = 0.5
-- Odcisk 25 tys. partów to kilkadziesiąt ms — rozkładamy na klatki, żeby serwer nie
-- przycinał w POST_ROUND (gracze właśnie wracają do lobby i chodzą).
local FRAME_BUDGET = 0.004

local DMG_HP = Config.Destruction.DamageAttributes.HP
local DMG_COLOR = Config.Destruction.DamageAttributes.OrigColor
local TOLERANCE = Config.Map.RestoreTolerance

type Print = { number }

type Unit = {
	name: string,
	container: Instance, -- kontener nigdy nie jest kasowany, więc referencja jest stała
	live: Instance?,
	snapshot: Instance,
	print: Print,
}

local units: { Unit } = {}
-- Kontenery (Workspace.Map, foldery ze ścieżek RestoreGroups i ich przodkowie). Ich
-- dzieci, które nie są jednostką ani kontenerem, to obce rzeczy z rundy → kasowane.
local containers: { Instance } = {}
local isContainer: { [Instance]: boolean } = {}
local initialized = false

local function getMap(): Folder?
	local map = Workspace:FindFirstChild("Map")
	if map and map:IsA("Folder") then return map end
	return nil
end

local function isLocked(map: Instance, inst: Instance): boolean
	return inst.Parent == map and inst.Name == "Locked"
end

-- Sumy w liczbach Luau (double), NIE w Vector3 — Vector3 to float32 i suma 25 tys.
-- pozycji rzędu setek studów gubiłaby dziesiąte części studa.
local function fingerprint(root: Instance): Print
	local n, anchored, collide, damaged = 0, 0, 0, 0
	local px, py, pz, sx, sy, sz = 0, 0, 0, 0, 0, 0
	local rx, ry, rz, ux, uy, uz = 0, 0, 0, 0, 0, 0
	local cr, cg, cb, tr = 0, 0, 0, 0
	local function add(part: BasePart)
		n += 1
		if part.Anchored then anchored += 1 end
		if part.CanCollide then collide += 1 end
		if part:GetAttribute(DMG_HP) ~= nil or part:GetAttribute(DMG_COLOR) ~= nil then
			damaged += 1
		end
		local cf = part.CFrame
		local p, r, u = cf.Position, cf.RightVector, cf.UpVector
		px += p.X; py += p.Y; pz += p.Z
		rx += r.X; ry += r.Y; rz += r.Z
		ux += u.X; uy += u.Y; uz += u.Z
		local s = part.Size
		sx += s.X; sy += s.Y; sz += s.Z
		local c = part.Color
		cr += c.R; cg += c.G; cb += c.B
		tr += part.Transparency
	end
	if root:IsA("BasePart") then
		add(root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			add(d)
		end
	end
	return { n, anchored, collide, damaged, px, py, pz, sx, sy, sz, rx, ry, rz, ux, uy, uz, cr, cg, cb, tr }
end

local COUNT_FIELDS = 4 -- pierwsze pola to liczby całkowite: porównanie dokładne

local function samePrint(a: Print, b: Print): boolean
	for i = 1, #a do
		if i <= COUNT_FIELDS then
			if a[i] ~= b[i] then return false end
		elseif math.abs(a[i] - b[i]) > TOLERANCE then
			return false
		end
	end
	return true
end

-- Ścieżki RestoreGroups → kontenery. Brak folderu z listy = ostrzeżenie, nie błąd:
-- jego zawartość odbuduje się wtedy jako część większej jednostki (bezpieczny kierunek).
local function resolveContainers(map: Folder)
	containers = { map }
	isContainer = { [map] = true }
	for _, path in ipairs(Config.Map.RestoreGroups) do
		local node: Instance = map
		for _, name in ipairs(path) do
			local nxt = node:FindFirstChild(name)
			if not nxt then
				warn(("[Map] RestoreGroups: brak %s w %s — ta gałąź odbudowuje się w całości"):format(name, node:GetFullName()))
				break
			end
			node = nxt
			if not isContainer[node] then
				isContainer[node] = true
				table.insert(containers, node)
			end
		end
	end
end

local function takeSnapshot()
	local map = getMap()
	if not map then
		warn("[Map] Workspace.Map nie istnieje — snapshot skip (po restoracji nie odrodzi się mapa)")
		return
	end

	-- Wyczyść poprzedni snapshot (idempotentność na wypadek hot-reload)
	local old = ServerStorage:FindFirstChild(SNAPSHOT_NAME)
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = SNAPSHOT_NAME
	folder.Parent = ServerStorage

	resolveContainers(map)
	units = {}
	for _, container in ipairs(containers) do
		for _, child in ipairs(container:GetChildren()) do
			if isContainer[child] or isLocked(map, child) then continue end
			-- Clone respektuje Archivable. Boot-state = wszystko Anchored=true, joints intact.
			local copy = child:Clone()
			if not copy then
				warn(("[Map] %s nie jest Archivable — nie odbuduje się po rundzie"):format(child:GetFullName()))
				continue
			end
			copy.Parent = folder
			table.insert(units, {
				name = child:GetFullName(),
				container = container,
				live = child,
				snapshot = copy,
				print = fingerprint(child),
			})
		end
	end

	print(("[Map] snapshot: %d jednostek w %d kontenerach"):format(#units, #containers))
end

local function cleanupActiveBombs(): number
	-- Bombs in flight mają task.delay(fuse=2.5s, detonate). Jeśli wybuchną PO restoracji,
	-- niszczą świeżą mapę. Destroy ich tutaj — fuse closure w BombService sprawdza
	-- `if bomb.Parent then detonate()` więc destroyed bomba po prostu znika cicho.
	-- Gracz traci rzut na końcu rundy, ale fairer niż zepsuta mapa kolejnej rundy.
	local count = 0
	for _, inst in ipairs(Workspace:GetChildren()) do
		if inst.Name == "BombProjectile" then
			inst:Destroy()
			count += 1
		end
	end
	return count
end

local function restoreMap()
	if #units == 0 then
		warn("[Map] brak snapshotu — restore skip")
		return
	end
	local map = getMap()
	if not map then
		warn("[Map] Workspace.Map zniknął — restore skip")
		return
	end
	local started = os.clock()

	-- 1) Obce dzieci kontenerów — to, co runda podrzuciła obok jednostek. Stary restore
	--    kasował wszystko pod Map poza Locked, więc tu zachowanie jest to samo.
	local known: { [Instance]: boolean } = {}
	for _, unit in ipairs(units) do
		if unit.live then known[unit.live] = true end
	end
	local foreign = 0
	for _, container in ipairs(containers) do
		for _, child in ipairs(container:GetChildren()) do
			if known[child] or isContainer[child] or isLocked(map, child) then continue end
			child:Destroy()
			foreign += 1
		end
	end

	-- 2) Jednostki: odbudowa tylko zmienionych.
	local restored: { string } = {}
	local sliceStart = os.clock()
	for _, unit in ipairs(units) do
		local live = unit.live
		local dirty = live == nil or live.Parent ~= unit.container or not samePrint(fingerprint(live), unit.print)
		if dirty then
			if live then live:Destroy() end
			-- Snapshot zostaje nienaruszony — kolejny restore też zadziała.
			local copy = unit.snapshot:Clone()
			copy.Parent = unit.container
			unit.live = copy
			table.insert(restored, unit.snapshot.Name)
		end
		if os.clock() - sliceStart > FRAME_BUDGET then
			task.wait()
			sliceStart = os.clock()
		end
	end

	print(("[Map] restored %d/%d jednostek (%s), obcych usunięto %d, %.0f ms"):format(
		#restored, #units, if #restored > 0 then table.concat(restored, ", ") else "—",
		foreign, (os.clock() - started) * 1000))
end

function MapService.init()
	if initialized then return end
	initialized = true

	takeSnapshot()

	GameLoopService.RoundEnded:Connect(function()
		-- Cleanup PRZED waitem — gdyby bomba miała fuse'a w trakcie RESTORE_DELAY,
		-- musimy ją usunąć zanim wybuchnie i niczego nie rozjebie po restorze.
		local cleaned = cleanupActiveBombs()
		if cleaned > 0 then
			print(("[Map] usunięto %d bomb w locie przed restorem"):format(cleaned))
		end
		task.wait(RESTORE_DELAY)
		restoreMap()
	end)
end

return MapService
