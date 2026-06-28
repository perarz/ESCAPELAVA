--!strict
-- MapService.luau
-- Snapshot mapy przy starcie serwera, restore po każdej rundzie.
-- Po wybuchu bomby parts są unanchored + tumble po świecie. Bez restore mapa zostaje
-- w "rozjebanym" stanie kolejnej rundy.
--
-- Strategia:
--   1. Init: clone'uj wszystkie children Workspace.Map (POZA "Locked" folder) do
--      ServerStorage.MapSnapshot. Snapshot to czysta kopia z bootu Studio.
--   2. Listener na GameLoopService.RoundEnded — destroy aktualne destructibles
--      i clone snapshot z powrotem do Map.
--
-- Co NIE jest snapshotowane (nieruszane przez restore):
--   - Workspace.Map.Locked (Baseplate, Spawn, geometria nieusuwalna — bomba ich nie tyka)
--   - Workspace.Lobby, Workspace.Lava, Workspace.SpawnPoints (osobne foldery pod Workspace)
--
-- Timing: czekamy RESTORE_DELAY po RoundEnded, żeby PlayerService.sendSurvivorsToLobby
-- (odpalany przez StateChanged → POST_ROUND, deferred BindableEvent) zdążył wyteleportować
-- żywych zanim wywalimy ich części pod nogami.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local GameLoopService = require(script.Parent.GameLoopService)

local MapService = {}

local SNAPSHOT_NAME = "MapSnapshot"
local RESTORE_DELAY = 0.5

local snapshotFolder: Folder? = nil
local initialized = false

local function getMap(): Folder?
	local map = Workspace:FindFirstChild("Map")
	if map and map:IsA("Folder") then return map end
	return nil
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

	local count = 0
	for _, child in ipairs(map:GetChildren()) do
		if child.Name == "Locked" then continue end
		-- Clone respektuje Archivable. Boot-state = wszystko Anchored=true, joints intact.
		local copy = child:Clone()
		copy.Parent = folder
		count += 1
	end

	snapshotFolder = folder
	print(("[Map] snapshot: %d destructible children"):format(count))
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
	if not snapshotFolder then
		warn("[Map] brak snapshotu — restore skip")
		return
	end
	local map = getMap()
	if not map then
		warn("[Map] Workspace.Map zniknął — restore skip")
		return
	end

	-- Destroy wszystko POZA Locked
	for _, child in ipairs(map:GetChildren()) do
		if child.Name == "Locked" then continue end
		child:Destroy()
	end

	-- Clone snapshot back (snapshot zostaje nienaruszony — kolejny restore też zadziała)
	for _, snap in ipairs(snapshotFolder:GetChildren()) do
		local copy = snap:Clone()
		copy.Parent = map
	end

	print("[Map] restored")
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
