--!strict
-- PlayerService.luau
-- Zarządza spawn/respawn i trackuje żywych. Wstrzykuje getAliveCount do GameLoopService.
--
-- KONTRAKT NAZW (Kacper buduje w Studio):
--   Workspace.Map.<dowolnie>.Spawn (BasePart) — punkt respu / teleportu do lobby
--   Workspace.Map.Locked.SpawnPoints (Folder, recursive)
--     └── *  (dowolne BasePart'y, np. "Spawn") — punkty spawn na rundę; kod losuje z puli
--
-- Filozofia: CharacterAutoLoads = false. Każdy spawn jest jawny:
--   - LOBBY/POST_ROUND  → wszyscy w Workspace.Map.Spawn
--   - ROUND start       → load + teleport na losowy Map.Locked.SpawnPoints/*
--   - Death w ROUND     → respawn z powrotem do Workspace.Map.Spawn (aliveSet -= player)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local GameLoopService = require(script.Parent.GameLoopService)
local KillService = require(script.Parent.KillService)
-- Spawn idzie przez AppearanceService, nie przez `player:LoadCharacter()` — wszyscy mają
-- wyglądać jak postacie z tej gry, a nie przynosić własne avatary (decyzja 2026-09-21).
local AppearanceService = require(script.Parent.AppearanceService)

local PlayerService = {}

local aliveSet: { [Player]: boolean } = {}
local diedConns: { [Player]: RBXScriptConnection } = {}
local initialized = false
local warnedNoLobby = false
local warnedNoSpawns = false

local function getLobbyTargetPosition(): Vector3
	-- Preferowany: Workspace.Lobby.Spawn (BasePart w wizualnym lobby)
	-- Fallback: Workspace.Map.Spawn (legacy)
	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		local spawn = lobby:FindFirstChild("Spawn")
		if spawn and spawn:IsA("BasePart") then
			return spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + Config.Spawn.LobbyYOffset, 0)
		end
	end
	local map = Workspace:FindFirstChild("Map")
	if map then
		-- recursive — Kacper może trzymać Spawn pod Map.Locked żeby bomba go nie ruszała
		local spawn = map:FindFirstChild("Spawn", true)
		if spawn and spawn:IsA("BasePart") then
			return spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + Config.Spawn.LobbyYOffset, 0)
		end
	end
	if not warnedNoLobby then
		warnedNoLobby = true
		warn("[PlayerService] Workspace.Lobby.Spawn ani Workspace.Map.Spawn (BasePart) nie istnieje — używam fallback")
	end
	return Config.Spawn.FallbackLobbyPosition
end

local function getRoundSpawnPool(): { Vector3 }
	-- Preferowany: Workspace.Map.Locked.SpawnPoints/* (pula punktów dla multiplayera,
	--   pod Locked żeby bomba ich nie ruszała i MapService nie snapshotował)
	-- Fallback 1: Workspace.SpawnPoints/* (legacy root-level folder)
	-- Fallback 2: Workspace.Map.Spawn (jedna pozycja, dla małej mapy / testów)
	-- Fallback 3: Config.Spawn.FallbackRoundPosition (Vector3 z Configa)
	local pool: { Vector3 } = {}

	local function harvest(folder: Instance)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(pool, child.Position + Vector3.new(0, child.Size.Y / 2 + 3, 0))
			end
		end
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		-- recursive — Kacper trzyma SpawnPoints pod Map.Locked
		local folder = map:FindFirstChild("SpawnPoints", true)
		if folder then harvest(folder) end
	end

	if #pool == 0 then
		local folder = Workspace:FindFirstChild("SpawnPoints")
		if folder then harvest(folder) end
	end

	if #pool == 0 and map then
		local sp = map:FindFirstChild("Spawn", true)
		if sp and sp:IsA("BasePart") then
			table.insert(pool, sp.Position + Vector3.new(0, sp.Size.Y / 2 + 3, 0))
		end
	end

	if #pool == 0 then
		if not warnedNoSpawns then
			warnedNoSpawns = true
			warn("[PlayerService] brak round spawn (Map.Locked.SpawnPoints, Workspace.SpawnPoints, Map.Spawn) — używam fallback Config")
		end
		table.insert(pool, Config.Spawn.FallbackRoundPosition)
	end
	return pool
end

-- Marker spawnu, który NIE JEST zakotwiczony, po starcie Play po prostu spada — a razem
-- z nim spada punkt, w który teleportujemy graczy (kod czyta jego POZYCJĘ, nie zapamiętaną
-- wartość). Objaw jest wtedy nie do odróżnienia od błędu w logice spawnu: gracze lądują
-- pod podłogą albo w losowym miejscu, mimo że kod działa poprawnie.
-- 2026-09-20: Workspace.Lobby.Spawn przyjechał z Anchored = false, stąd ta bramka.
-- Wymuszamy zamiast tylko ostrzegać, bo to jedna właściwość, a koszt przeoczenia to
-- popsuta cała runda. Wygląd (Transparency, CanCollide) zostaje Kacprowi — ruszamy
-- WYŁĄCZNIE to, co psuje mechanikę.
local function anchorSpawnMarkers()
	local fixed: { string } = {}

	local function anchor(part: Instance?)
		if part and part:IsA("BasePart") and not part.Anchored then
			part.Anchored = true
			table.insert(fixed, part:GetFullName())
		end
	end

	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		anchor(lobby:FindFirstChild("Spawn"))
	end

	local map = Workspace:FindFirstChild("Map")
	local folders: { Instance } = {}
	if map then
		local f = map:FindFirstChild("SpawnPoints", true)
		if f then table.insert(folders, f) end
		local s = map:FindFirstChild("Spawn", true)
		anchor(s)
	end
	local rootFolder = Workspace:FindFirstChild("SpawnPoints")
	if rootFolder then table.insert(folders, rootFolder) end

	for _, folder in ipairs(folders) do
		for _, child in ipairs(folder:GetChildren()) do
			anchor(child)
		end
	end

	if #fixed > 0 then
		warn(("[PlayerService] zakotwiczyłem %d marker(ów) spawnu, bo spadłyby przy starcie: %s"):format(
			#fixed, table.concat(fixed, ", ")))
	end
end

local function shuffled<T>(arr: { T }): { T }
	local copy = table.clone(arr)
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function getAliveCount(): number
	local n = 0
	for _ in pairs(aliveSet) do
		n += 1
	end
	return n
end

function PlayerService.isAlive(player: Player): boolean
	return aliveSet[player] == true
end

function PlayerService.getAliveList(): { Player }
	-- Snapshot listy żywych (dla RewardsService — wyliczenie winnerów przed cleanup).
	local list: { Player } = {}
	for p in pairs(aliveSet) do
		table.insert(list, p)
	end
	return list
end

local function disconnectDied(player: Player)
	local conn = diedConns[player]
	if conn then
		conn:Disconnect()
		diedConns[player] = nil
	end
end

local function teleportCharacter(character: Model, position: Vector3)
	task.wait() -- frame na fizykę po LoadCharacter
	if character.Parent then
		character:PivotTo(CFrame.new(position))
	end
end

local function sendToLobby(player: Player)
	AppearanceService.loadCharacter(player)
	local char = player.Character
	if char then
		teleportCharacter(char, getLobbyTargetPosition())
	end
end

local function onDeath(player: Player, hum: Humanoid?)
	if not aliveSet[player] then return end
	aliveSet[player] = nil
	disconnectDied(player)

	-- Kill credit — jeśli attacker był tagged w oknie czasu, dostaje $. Fires PlayerKilled.
	if hum then
		KillService.processDeath(player, hum)
	end

	-- Sygnał zmiany stanu alive → false (single source: aliveSet). Obecnie bez konsumenta
	-- po stronie klienta (HudVisibilityController usunięty razem ze sklepem).
	Remotes.AliveChanged:FireClient(player, false)
	Remotes.PlayerDied:FireAllClients(player, "round")

	task.defer(function()
		if not player.Parent then return end -- left server
		sendToLobby(player)
	end)
end

-- Zdejmuje domyślną regenerację życia. Roblox wkłada do KAŻDEJ postaci skrypt `Health`
-- leczący ~1% HP/s; przy lawie raniącej zamiast zabijającej to on decydowałby o tym,
-- czy da się ją przeczekać. Kasujemy, a nie wyłączamy: `Disabled` po starcie nie przerywa
-- pętli, która już się kręci. Skrypt bywa dokładany chwilę PO `CharacterAdded`, stąd wait.
local function stripHealthRegen(character: Model)
	if not Config.Game.DisableHealthRegen then return end
	task.spawn(function()
		local health = character:WaitForChild("Health", 5)
		if health and health:IsA("BaseScript") then
			health:Destroy()
		end
	end)
end

local function hookHumanoid(player: Player, character: Model)
	stripHealthRegen(character)
	local hum = character:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then return end
	disconnectDied(player)
	diedConns[player] = hum.Died:Connect(function()
		onDeath(player, hum)
	end)
end

local LOBBY_NEAR_THRESHOLD = 25 -- stud; ponad = teleport, poniżej = zostaw w lobby

local function sendSurvivorsToLobby()
	-- POST_ROUND/LOBBY: teleportuj TYLKO graczy fizycznie daleko od lobby spota.
	-- Martwi spectator'zy są już w lobby po onDeath — nie chcemy ich znowu LoadCharacter.
	local target = getLobbyTargetPosition()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			-- Brak postaci (np. fresh join w trakcie POST_ROUND) — zwykły load+teleport.
			sendToLobby(p)
		elseif (hrp.Position - target).Magnitude > LOBBY_NEAR_THRESHOLD then
			-- Daleko od lobby → survivor jeszcze na mapie. Teleport bez LoadCharacter
			-- (zachowujemy skin/health/inventory).
			char:PivotTo(CFrame.new(target))
		end
	end
	aliveSet = {}
end

local function sendEveryoneToRound()
	-- Pre-populate aliveSet SYNCHRONICZNIE przed jakimkolwiek yield, żeby
	-- GameLoop.shouldEndRound widział alive>0 zanim my zdążymy zrobić LoadCharacter.
	aliveSet = {}
	local players = Players:GetPlayers()
	for _, player in ipairs(players) do
		aliveSet[player] = true
	end

	local pool = shuffled(getRoundSpawnPool())

	-- LoadCharacter w pcall PER GRACZ. Bez tego jeden błąd (padnięty avatar, gracz
	-- wychodzący w tej samej klatce) przerywał CAŁĄ pętlę: reszta zostawała w aliveSet
	-- jako żywa, ale nigdy nie lądowała na mapie — runda nie mogła skończyć się wcześniej,
	-- bo licznik żywych nigdy nie schodził do zera.
	local spawned: { { char: Model, pos: Vector3 } } = {}
	for i, player in ipairs(players) do
		local pos = pool[((i - 1) % #pool) + 1]
		local ok, err = pcall(function()
			AppearanceService.loadCharacter(player)
		end)
		local char = player.Character
		if ok and char then
			table.insert(spawned, { char = char, pos = pos })
			Remotes.AliveChanged:FireClient(player, true)
		else
			if not ok then
				warn(("[PlayerService] LoadCharacter %s nie powiódł się: %s"):format(player.Name, tostring(err)))
			end
			aliveSet[player] = nil
		end
	end

	-- Jedna klatka na fizykę dla WSZYSTKICH, nie jedna na gracza. Przy 20 graczach stary
	-- wariant rozciągał spawn na ~20 klatek i część graczy była w rundzie wcześniej niż reszta.
	task.wait()
	for _, entry in ipairs(spawned) do
		if entry.char.Parent then
			entry.char:PivotTo(CFrame.new(entry.pos))
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		hookHumanoid(player, character)
	end)

	-- Fresh join idzie do lobby niezależnie od stanu (w trakcie rundy = spectator w lobby).
	sendToLobby(player)
end

local function onPlayerRemoving(player: Player)
	aliveSet[player] = nil
	disconnectDied(player)
end

function PlayerService.init()
	if initialized then return end
	initialized = true

	Players.CharacterAutoLoads = false

	-- PRZED pierwszym spawnem: nieanchorowany marker zdążyłby już odjechać.
	anchorSpawnMarkers()

	GameLoopService.setAliveCountProvider(getAliveCount)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end

	GameLoopService.StateChanged:Connect(function(newState: string)
		if newState == GameLoopService.STATE.ROUND then
			sendEveryoneToRound()
		elseif newState == GameLoopService.STATE.LOBBY
			or newState == GameLoopService.STATE.POST_ROUND then
			sendSurvivorsToLobby()
		end
		-- COUNTDOWN: bez zmian, gracze nadal w lobby
	end)
end

return PlayerService
