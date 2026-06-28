--!strict
-- GameLoopService.luau
-- State machine rund: LOBBY → COUNTDOWN → ROUND (Easy/Mid/Hard/Endgame) → POST_ROUND → LOBBY.
-- Emituje stany przez BindableEventy (dla serwisów) i RemoteEventy (dla klientów).
--
-- Zewnętrzne serwisy (PlayerService) mogą wstrzyknąć getAliveCountProvider żeby runda
-- mogła wcześnie kończyć gdy wszyscy umrą.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local STATE = {
	LOBBY = "LOBBY",
	COUNTDOWN = "COUNTDOWN",
	ROUND = "ROUND",
	POST_ROUND = "POST_ROUND",
}

local GameLoopService = {}
GameLoopService.STATE = STATE

local stateChanged = Instance.new("BindableEvent")
local phaseChanged = Instance.new("BindableEvent")
local roundEnded = Instance.new("BindableEvent")
GameLoopService.StateChanged = stateChanged.Event   -- (newState: string)
GameLoopService.PhaseChanged = phaseChanged.Event   -- (phaseName: string, phaseIndex: number, duration: number)
GameLoopService.RoundEnded = roundEnded.Event       -- ()

local currentState: string = STATE.LOBBY
local currentStateDuration: number = 0
local currentStateStartedAt: number = 0
local currentPhaseIndex: number = 0
local currentPhaseName: string = ""
local currentPhaseDuration: number = 0
local currentPhaseStartedAt: number = 0
local started = false

local aliveProvider: () -> number = function() return 0 end

function GameLoopService.setAliveCountProvider(fn: () -> number)
	aliveProvider = fn
end

function GameLoopService.getState(): string
	return currentState
end

function GameLoopService.getPhaseProgress(): (number, number, number)
	-- zwraca (phaseIndex, elapsed, duration); 0,0,0 jeśli nie w rundzie
	if currentState ~= STATE.ROUND or currentPhaseIndex == 0 then
		return 0, 0, 0
	end
	return currentPhaseIndex, os.clock() - currentPhaseStartedAt, currentPhaseDuration
end

local function setState(newState: string, duration: number?)
	currentState = newState
	local dur = duration or 0
	currentStateDuration = dur
	currentStateStartedAt = os.clock()
	if newState ~= STATE.ROUND then
		currentPhaseIndex = 0
		currentPhaseName = ""
	end
	stateChanged:Fire(newState, dur)
	Remotes.GameStateChanged:FireAllClients(newState, dur)
	print(("[GameLoop] state → %s (dur=%ds)"):format(newState, dur))
end

local function setPhase(name: string, index: number, duration: number)
	currentPhaseIndex = index
	currentPhaseName = name
	currentPhaseDuration = duration
	currentPhaseStartedAt = os.clock()
	phaseChanged:Fire(name, index, duration)
	Remotes.PhaseChanged:FireAllClients(name, index, duration)
	print(("[GameLoop] phase %d (%s) — %ds"):format(index, name, duration))
end

-- Replikuje aktualny state + phase do konkretnego gracza (na PlayerAdded).
-- Klient yieldje na WaitForChild HUD i może minąć moment gdy server odpala
-- pierwsze setState — bez tego HUD utknie na default tekście.
function GameLoopService.replicateTo(player: Player)
	local stateElapsed = os.clock() - currentStateStartedAt
	local stateRemaining = math.max(currentStateDuration - stateElapsed, 0)
	Remotes.GameStateChanged:FireClient(player, currentState, stateRemaining)
	if currentState == STATE.ROUND and currentPhaseIndex > 0 then
		local phaseElapsed = os.clock() - currentPhaseStartedAt
		local phaseRemaining = math.max(currentPhaseDuration - phaseElapsed, 0)
		Remotes.PhaseChanged:FireClient(player, currentPhaseName, currentPhaseIndex, phaseRemaining)
	end
end

local function waitWithEarlyEnd(duration: number, endCheck: (() -> boolean)?): boolean
	-- Yield FIRST, check AFTER. Roblox BindableEvents w deferred mode (default od 2023)
	-- wywołują listenery na następnej klatce; sprawdzanie endCheck przed pierwszym
	-- yieldem łapie alive=0 zanim PlayerService.sendEveryoneToRound zdąży się odpalić.
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		task.wait(0.25)
		if endCheck and endCheck() then
			return true
		end
	end
	return false
end

local function shouldEndRound(): boolean
	return #Players:GetPlayers() > 0 and aliveProvider() <= 0
end

local function runLobby()
	setState(STATE.LOBBY, Config.Game.LobbyDuration)
	currentPhaseIndex = 0

	-- Czekamy aż osiągniemy MinPlayers...
	while #Players:GetPlayers() < Config.Game.MinPlayers do
		task.wait(1)
	end

	-- ...potem odliczamy LobbyDuration. Jeśli ktoś wyjdzie poniżej min, reset.
	local elapsed = 0
	while elapsed < Config.Game.LobbyDuration do
		task.wait(1)
		if #Players:GetPlayers() < Config.Game.MinPlayers then
			elapsed = 0
		else
			elapsed += 1
		end
	end
end

local function runCountdown()
	setState(STATE.COUNTDOWN, Config.Game.CountdownDuration)
	task.wait(Config.Game.CountdownDuration)
end

local function totalRoundDuration(): number
	local sum = 0
	for _, phase in ipairs(Config.Lava.Phases) do
		sum += phase.Duration
	end
	return sum
end

local function runRound()
	setState(STATE.ROUND, totalRoundDuration())

	-- Daj PlayerService.sendEveryoneToRound szansę odpalić (BindableEvent deferred mode
	-- queuuje listenery do następnej klatki) i pre-populować aliveSet zanim startujemy
	-- fazy. Bez tego pierwsza faza widzi alive=0 i kończy rundę natychmiast.
	task.wait()

	for i, phase in ipairs(Config.Lava.Phases) do
		setPhase(phase.Name, i, phase.Duration)
		local endedEarly = waitWithEarlyEnd(phase.Duration, shouldEndRound)
		if endedEarly then
			print("[GameLoop] runda kończy się wcześniej — wszyscy martwi")
			break
		end
	end

	currentPhaseIndex = 0
	roundEnded:Fire()
	Remotes.RoundEnded:FireAllClients()
end

local function runPostRound()
	setState(STATE.POST_ROUND, Config.Game.PostRoundDuration)
	task.wait(Config.Game.PostRoundDuration)
end

local function gameLoop()
	while true do
		local ok, err = pcall(function()
			runLobby()
			runCountdown()
			runRound()
			runPostRound()
		end)
		if not ok then
			warn(("[GameLoop] crash w pętli: %s — restartuję za 5s"):format(tostring(err)))
			task.wait(5)
		end
	end
end

function GameLoopService.start()
	if started then
		warn("[GameLoop] start() wywołane drugi raz, ignoruję")
		return
	end
	started = true
	task.spawn(gameLoop)
end

return GameLoopService
