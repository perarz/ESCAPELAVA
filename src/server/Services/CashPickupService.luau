--!strict
-- CashPickupService.luau
-- Cash rozsiane po mapie do zbierania. Magnet pickup (gracz w MagnetRange → cash leci
-- do niego, server credituje). Spawn z Workspace.Map.CashSpawns (BasePart markery
-- które stawia Kacper w Studio), asset z ReplicatedStorage.Cash (Kacper podrzuca model).
--
-- Lifecycle:
--   Boot: snapshot pozycji z Workspace.Map.CashSpawns (Vector3[]). Przeżyje MapService
--         restore (snapshot to czyste pozycje, nie referencje do Part'ów).
--   ROUND start: spawn (subset, SpawnFraction). Każda pozycja → raycast w dół 100 stud.
--                Skip jeśli grunt poniżej aktualnej lawy + safety margin.
--   Heartbeat 10Hz: per cash znajdź najbliższego alive gracza w MagnetRange. Hit →
--                   atomic Collected flag → CashService.add + CashCollected RemoteEvent
--                   (all clients animują pickup) → Destroy.
--   Lawa touched cash: silent destroy (bez credit).
--   POST_ROUND: cleanup pozostałych cash.
--
-- Architektura skali (kilkuset active):
--   * Cash anchored — server zawsze widzi prawdziwą pozycję, klient nie cheatuje.
--   * Magnet check 10Hz (nie 60Hz) — 10 cash × 30 graczy = 300 distance²/s, pomijalne.
--   * Atomic Collected flag PRZED credit zapobiega double-pickup (Heartbeat race).
--   * Brak per-tick replikacji (cash nie rusza się aż do pickup → wtedy Destroy).
--   * Asset clone tylko raz per spawn point per runda; cleanup batched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashService = require(script.Parent.CashService)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerService = require(script.Parent.PlayerService)
local LavaService = require(script.Parent.LavaService)

local CashPickupService = {}

local ACTIVE_FOLDER_NAME = "ActiveCash"
local SPAWN_FOLDER_NAME = "CashSpawns"
local TEMPLATE_NAME = "Cash"

-- Kacper trzyma spawny pod Workspace.Map.Locked.CashSpawns (NIE bezpośrednio pod Map).
-- Powód: Locked folder jest podwójnie chroniony — MapService.snapshot skipuje "Locked"
-- (parts nie znikną po restore rundy) + BombService.isProtected pomija wszystko pod Locked
-- (bomba nie wyrzuca markerów w powietrze). Fallback: gdyby w przyszłości postawił bezpośrednio
-- w Workspace.Map.CashSpawns, też zadziała.
local SPAWN_PARENT_CANDIDATES = {
	{ "Locked", "CashSpawns" },   -- preferowane (pod Map.Locked)
	{ "CashSpawns" },             -- fallback (bezpośrednio pod Map)
}

local spawnPositions: { Vector3 } = {}
local activeFolder: Folder? = nil
local heartbeatConn: RBXScriptConnection? = nil
local roundActive = false
local initialized = false

local function log(msg: string)
	print("[Cash] " .. msg)
end

local function getOrCreateActiveFolder(): Folder
	if activeFolder and activeFolder.Parent then return activeFolder end
	local existing = Workspace:FindFirstChild(ACTIVE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		activeFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = ACTIVE_FOLDER_NAME
	folder.Parent = Workspace
	activeFolder = folder
	return folder
end

local function findSpawnsFolder(map: Instance): (Folder?, string?)
	-- Próbuje znaleźć folder CashSpawns wg listy candidate ścieżek (relative do Map).
	-- Zwraca (folder, path) lub (nil, nil).
	for _, segments in ipairs(SPAWN_PARENT_CANDIDATES) do
		local current: Instance = map
		local ok = true
		for _, segName in ipairs(segments) do
			local nextChild = current:FindFirstChild(segName)
			if not nextChild then
				ok = false
				break
			end
			current = nextChild
		end
		if ok and current:IsA("Folder") then
			return current :: Folder, "Workspace.Map." .. table.concat(segments, ".")
		end
	end
	return nil, nil
end

local function takeSpawnSnapshot()
	-- Workspace.Map.Locked.CashSpawns to lista BasePart markerów (anchored, transparent).
	-- Bierzemy ich Position raz na boot; same Parts nie są używane w runtime, więc nawet
	-- gdyby ktoś je usunął/przeniósł, snapshot pozycji (Vector3[]) działa dalej.
	local map = Workspace:FindFirstChild("Map")
	if not map then
		warn("[Cash] Workspace.Map nie istnieje — cash nie będzie spawnował")
		return
	end

	local spawns, foundPath = findSpawnsFolder(map)
	if not spawns then
		warn("[Cash] nie znalazłem CashSpawns w Workspace.Map.Locked ani Workspace.Map — cash nie będzie spawnował")
		return
	end

	local positions: { Vector3 } = {}
	local yOffset = Vector3.new(0, Config.Cash.SpawnHeightOffset, 0)
	for _, child in ipairs(spawns:GetChildren()) do
		if child:IsA("BasePart") then
			-- Doliczam offset Y od razu w snapshot — server-side magnet detection i klient-side
			-- hover bazują na tej samej pozycji, brak desync. Tunowanie tylko w Config.
			table.insert(positions, child.Position + yOffset)
		end
	end
	spawnPositions = positions
	log(("snapshot: %d spawn points (źródło: %s, offset Y=+%d)"):format(#positions, foundPath or "?", Config.Cash.SpawnHeightOffset))
end

local function getCashTemplate(): Instance?
	-- Preferuj asset Kacpra z ReplicatedStorage. Brak → fallback default Part.
	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	if template then return template end
	return nil
end

local function makeDefaultCashVisual(): BasePart
	-- Fallback gdy ReplicatedStorage.Cash nie istnieje. Złoty Part + BillboardGui "$10".
	-- Nie cudo, ale grywalne; Kacper podmieni gdy będzie miał asset.
	local part = Instance.new("Part")
	part.Name = "Cash"
	part.Size = Config.Cash.DefaultSize
	part.Color = Config.Cash.DefaultColor
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.new(0, 80, 0, 30)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ("$%d"):format(Config.Cash.Value)
	label.TextColor3 = Color3.fromRGB(255, 255, 200)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(80, 50, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui

	return part
end

local function prepareCashInstance(template: Instance?, position: Vector3): BasePart?
	-- Zwraca anchored BasePart (lub Model PrimaryPart) gotowy do parent → ActiveCash.
	-- Asset Kacpra może być Model lub BasePart. Cash MUSI być nie-collide, anchored, can-touch.
	local instance: Instance
	if template then
		instance = template:Clone()
	else
		instance = makeDefaultCashVisual()
	end

	local rootPart: BasePart? = nil

	if instance:IsA("Model") then
		-- Model: znajdź PrimaryPart (Kacper powinien go ustawić). Brak → użyj first BasePart.
		local primary = instance.PrimaryPart
		if not primary then
			for _, d in ipairs(instance:GetDescendants()) do
				if d:IsA("BasePart") then
					instance.PrimaryPart = d
					primary = d
					break
				end
			end
		end
		if not primary then
			warn("[Cash] template Model bez BasePart — skip")
			instance:Destroy()
			return nil
		end
		instance:PivotTo(CFrame.new(position))
		rootPart = primary
	elseif instance:IsA("BasePart") then
		instance.Position = position
		rootPart = instance
	else
		warn("[Cash] template nie jest BasePart ani Model — skip")
		instance:Destroy()
		return nil
	end

	if not rootPart then return nil end

	-- Ujednolicenie własności na wszystkich Parts cash'a (Model może mieć kilka).
	local parts: { BasePart } = {}
	if instance:IsA("Model") then
		for _, d in ipairs(instance:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(parts, d) end
		end
	else
		table.insert(parts, instance :: BasePart)
	end
	for _, p in ipairs(parts) do
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = true
		p.CanQuery = true
	end

	-- Atomic collect flag — heartbeat ustawia "Collected"=true PRZED credit, druga klatka
	-- nie zdąży tego samego cash'a credit'ować.
	rootPart:SetAttribute("Collected", false)

	-- Pomocnik: szybki getter pozycji w heartbeat bez rozróżniania Model/Part.
	-- (Dla BasePart instance == rootPart, więc finalna nazwa to "Cash" — jak wcześniej.)
	rootPart.Name = "CashRoot"
	instance.Name = "Cash"
	instance.Parent = getOrCreateActiveFolder()

	return rootPart
end

local function isPositionSafe(pos: Vector3): boolean
	-- Skip pozycje które są pod lawą (z marginesem) — gracz nie zdążyłby do nich dobiec,
	-- a magnet by działał czyli cash znikałoby gdy gracz przechodzi obok bez kontaktu.
	local lavaY = LavaService.getSurfaceY()
	if pos.Y < lavaY + Config.Cash.LavaSafetyMargin then
		return false
	end
	return true
end

local function shuffle<T>(t: { T }): { T }
	-- Fisher-Yates in place
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

local function spawnRoundCash()
	if #spawnPositions == 0 then return end

	getOrCreateActiveFolder():ClearAllChildren()
	local template = getCashTemplate()

	-- Wybór subset wg SpawnFraction. Kopiujemy listę żeby shuffle nie zmieniał snapshotu.
	local positions = table.clone(spawnPositions)
	shuffle(positions)
	local target = math.max(1, math.floor(#positions * Config.Cash.SpawnFraction + 0.5))

	local spawned, skipped = 0, 0
	for i = 1, math.min(target, #positions) do
		local pos = positions[i]
		if not isPositionSafe(pos) then
			skipped += 1
			continue
		end
		local root = prepareCashInstance(template, pos)
		if root then
			spawned += 1
		end
	end
	log(("spawned %d (skipped %d nad lawą)"):format(spawned, skipped))
end

local function getRootPart(child: Instance): BasePart?
	-- "Cash" w ActiveCash może być BasePart lub Model. Root to BasePart z attributem "Collected".
	if child:IsA("BasePart") then return child end
	if child:IsA("Model") then
		local primary = child.PrimaryPart
		if primary then return primary end
		return child:FindFirstChild("CashRoot") :: BasePart?
	end
	return nil
end

local function collect(cashInstance: Instance, root: BasePart, player: Player)
	if root:GetAttribute("Collected") then return end
	root:SetAttribute("Collected", true)

	local position = root.Position
	CashService.add(player, Config.Cash.Value, "pickup:cash")

	-- Klient animuje lokalnie (czyta `fromPosition`, tween do swojego HRP).
	Remotes.CashCollected:FireAllClients(player, position)

	cashInstance:Destroy()
end

local function magnetTick()
	if not roundActive then return end
	local folder = activeFolder
	if not folder then return end

	-- Cache live alive players raz per tick — niezmienne w ciągu kilkudziesięciu ms.
	local alivePlayers: { { player: Player, hrp: BasePart } } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if PlayerService.isAlive(p) then
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				table.insert(alivePlayers, { player = p, hrp = hrp })
			end
		end
	end
	if #alivePlayers == 0 then return end

	local rangeSq = Config.Cash.MagnetRange * Config.Cash.MagnetRange
	-- Poziom lawy liczony RAZ na tick — cash zalany lawą znika w tym samym przebiegu,
	-- w którym i tak iterujemy po paczkach. Wcześniej robił to osobny listener Touched
	-- wpięty w LavaPart; przy gruzie z wybuchów ten listener kosztował tysiące wywołań
	-- na sekundę, a odpalał się dla wszystkiego, nie tylko dla cashu.
	local lavaY = LavaService.getSurfaceY()

	for _, cashInstance in ipairs(folder:GetChildren()) do
		local root = getRootPart(cashInstance)
		if not root then continue end
		if root:GetAttribute("Collected") then continue end

		if root.Position.Y < lavaY then
			cashInstance:Destroy()
			continue
		end

		-- Najbliższy alive w MagnetRange wygrywa (deterministycznie distance²).
		local bestPlayer: Player? = nil
		local bestDistSq = rangeSq
		local cashPos = root.Position
		for _, entry in ipairs(alivePlayers) do
			local d = entry.hrp.Position - cashPos
			local dSq = d.X*d.X + d.Y*d.Y + d.Z*d.Z
			if dSq < bestDistSq then
				bestDistSq = dSq
				bestPlayer = entry.player
			end
		end
		if bestPlayer then
			collect(cashInstance, root, bestPlayer)
		end
	end
end

local function startRound()
	if roundActive then return end
	spawnRoundCash()
	roundActive = true
	if not heartbeatConn then
		-- Throttled: 10Hz wystarczy do magnet feelu (gracz max ~16 stud/s biegnąc;
		-- 0.1s × 16 = 1.6 stud przesuwu między tickami — niewidoczne).
		local interval = 1 / Config.Cash.HeartbeatHz
		local accumulator = 0
		heartbeatConn = RunService.Heartbeat:Connect(function(dt)
			accumulator += dt
			if accumulator >= interval then
				accumulator = 0
				magnetTick()
			end
		end)
	end
end

local function endRound()
	roundActive = false
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	local folder = activeFolder
	if folder then
		folder:ClearAllChildren()
	end
end

function CashPickupService.init()
	if initialized then return end
	initialized = true

	takeSpawnSnapshot()
	getOrCreateActiveFolder()

	-- StateChanged: spawn na ROUND start, cleanup na POST_ROUND/LOBBY.
	-- (RoundEnded BindableEvent triggeruje POST_ROUND, ale MapService czeka 0.5s na restore
	-- — jeśli czyściłbym cash dopiero w RoundEnded → cleanupActiveBombs to MapService
	-- nie tknie ActiveCash bo to osobny folder Workspace. Bezpiecznie czyścić w StateChanged
	-- POST_ROUND żeby aktualny stan był zsynchronizowany ze stanem GameLoop.)
	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == GameLoopService.STATE.ROUND then
			startRound()
		elseif newState == GameLoopService.STATE.POST_ROUND
			or newState == GameLoopService.STATE.LOBBY then
			endRound()
		end
	end)
end

return CashPickupService
