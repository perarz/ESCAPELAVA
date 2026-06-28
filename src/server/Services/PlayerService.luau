--!strict
-- PlayerService.luau
-- Zarządza spawn/respawn i trackuje żywych. Wstrzykuje getAliveCount do GameLoopService.
--
-- KONTRAKT NAZW (Kacper buduje w Studio):
--   Workspace.Map.Spawn (BasePart) — punkt respu / teleportu do lobby; Position+offset = pozycja gracza
--   Workspace.SpawnPoints (Folder)
--     └── *  (dowolne BasePart'y) — punkty spawn na rundę; kod losuje z puli
--
-- Filozofia: CharacterAutoLoads = false. Każdy spawn jest jawny:
--   - LOBBY/POST_ROUND  → wszyscy w Workspace.Map.Spawn
--   - ROUND start       → load + teleport na losowy Workspace.SpawnPoints/*
--   - Death w ROUND     → respawn z powrotem do Workspace.Map.Spawn (aliveSet -= player)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local GameLoopService = require(script.Parent.GameLoopService)

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
	-- Preferowany: Workspace.SpawnPoints/* (pula punktów dla multiplayera)
	-- Fallback 1: Workspace.Map.Spawn (jedna pozycja, dla małej mapy / testów)
	-- Fallback 2: Config.Spawn.FallbackRoundPosition (Vector3 z Configa)
	local pool: { Vector3 } = {}

	local folder = Workspace:FindFirstChild("SpawnPoints")
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(pool, child.Position + Vector3.new(0, child.Size.Y / 2 + 3, 0))
			end
		end
	end

	if #pool == 0 then
		local map = Workspace:FindFirstChild("Map")
		if map then
			-- recursive — Spawn może być pod Map.Locked
			local sp = map:FindFirstChild("Spawn", true)
			if sp and sp:IsA("BasePart") then
				table.insert(pool, sp.Position + Vector3.new(0, sp.Size.Y / 2 + 3, 0))
			end
		end
	end

	if #pool == 0 then
		if not warnedNoSpawns then
			warnedNoSpawns = true
			warn("[PlayerService] brak round spawn (Workspace.SpawnPoints i Workspace.Map.Spawn) — używam fallback Config")
		end
		table.insert(pool, Config.Spawn.FallbackRoundPosition)
	end
	return pool
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
	player:LoadCharacter()
	local char = player.Character
	if char then
		teleportCharacter(char, getLobbyTargetPosition())
	end
end

local function onDeath(player: Player)
	if not aliveSet[player] then return end
	aliveSet[player] = nil
	disconnectDied(player)
	Remotes.PlayerDied:FireAllClients(player, "round")

	task.defer(function()
		if not player.Parent then return end -- left server
		sendToLobby(player)
	end)
end

local function hookHumanoid(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") then return end
	disconnectDied(player)
	diedConns[player] = hum.Died:Connect(function()
		onDeath(player)
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
	for i, player in ipairs(players) do
		local pos = pool[((i - 1) % #pool) + 1]
		player:LoadCharacter()
		local char = player.Character
		if char then
			teleportCharacter(char, pos)
		else
			aliveSet[player] = nil
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
