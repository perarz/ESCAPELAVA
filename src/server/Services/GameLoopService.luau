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

-- TRYB DEV (Config.Dev): pomijanie czekania. `skipRequested` jest JEDNORAZOWY — każdy
-- wait konsumuje go i czyści, więc jedno naciśnięcie klawisza = jedna pominięta faza,
-- a nie lawina przeskoków. `forceEndRound` żyje do końca rundy (czyszczony na starcie).
local skipRequested = false
local forceEndRound = false

function GameLoopService.setAliveCountProvider(fn: () -> number)
	aliveProvider = fn
end

-- Wołane WYŁĄCZNIE przez DevService (po walidacji uprawnień). Zwraca opis dla logu.
function GameLoopService.devSkip(): string
	skipRequested = true
	return currentState == STATE.ROUND and ("faza " .. currentPhaseName) or currentState
end

function GameLoopService.devEndRound(): boolean
	if currentState ~= STATE.ROUND then
		return false
	end
	forceEndRound = true
	return true
end

local function consumeSkip(): boolean
	if not skipRequested then return false end
	skipRequested = false
	return true
end

-- Czekanie przerywalne devowym skipem. 0.1s ziarnistość = klawisz działa natychmiastowo
-- w odczuciu, a koszt to 10 iteracji/s w jednym wątku pętli gry.
local function waitSkippable(duration: number)
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		task.wait(0.1)
		if consumeSkip() then return end
	end
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
		-- Dev skip kończy TĘ fazę, ale nie rundę — pętla faz leci dalej do następnej.
		if consumeSkip() then
			return false
		end
		if endCheck and endCheck() then
			return true
		end
	end
	return false
end

local function shouldEndRound(): boolean
	if forceEndRound then return true end
	return #Players:GetPlayers() > 0 and aliveProvider() <= 0
end

local function waitForMinPlayers()
	-- duration=0 → UIController pokazuje "Players: N" zamiast countdownu. Wcześniej
	-- wysyłaliśmy LobbyDuration OD RAZU i dopiero czekali na MinPlayers — klient
	-- odliczał do 0:00 i wisiał (widoczne przy MinPlayers=2, gracz sam na serwerze).
	if #Players:GetPlayers() >= Config.Game.MinPlayers then return end
	setState(STATE.LOBBY, 0)
	repeat
		task.wait(1)
	until #Players:GetPlayers() >= Config.Game.MinPlayers
end

local function runLobby()
	waitForMinPlayers()
	setState(STATE.LOBBY, Config.Game.LobbyDuration)

	-- Countdown LobbyDuration. Spadek poniżej min → wróć do trybu oczekiwania
	-- (klient dostaje świeży state, timer restartuje od pełna — nie kłamie).
	local elapsed = 0
	while elapsed < Config.Game.LobbyDuration do
		task.wait(1)
		if consumeSkip() then return end
		if #Players:GetPlayers() < Config.Game.MinPlayers then
			waitForMinPlayers()
			setState(STATE.LOBBY, Config.Game.LobbyDuration)
			elapsed = 0
		else
			elapsed += 1
		end
	end
end

local function runCountdown()
	setState(STATE.COUNTDOWN, Config.Game.CountdownDuration)
	waitSkippable(Config.Game.CountdownDuration)
end

local function totalRoundDuration(): number
	local sum = 0
	for _, phase in ipairs(Config.Lava.Phases) do
		sum += phase.Duration
	end
	return sum
end

local function runRound()
	-- Świeży start: żądanie "zakończ rundę" z poprzedniej rundy nie może ubić tej.
	forceEndRound = false
	setState(STATE.ROUND, totalRoundDuration())

	-- Daj PlayerService.sendEveryoneToRound szansę odpalić (BindableEvent deferred mode
	-- queuuje listenery do następnej klatki) i pre-populować aliveSet zanim startujemy
	-- fazy. Bez tego pierwsza faza widzi alive=0 i kończy rundę natychmiast.
	task.wait()

	-- Pętla faz w OSOBNYM pcall, bo na roundEnded wiszą: restore mapy (MapService),
	-- wypłata nagród (RewardsService), cleanup cashu i mostów.
	-- Gdyby błąd w fazie przeleciał do pcall'a całej pętli gry, żadna
	-- z tych rzeczy by się nie wykonała i kolejna runda startowałaby w rozjebanym świecie
	-- (mapa w gruzach, aliveSet pełen duchów → runda kończy się natychmiast albo wcale).
	local ok, err = pcall(function()
		for i, phase in ipairs(Config.Lava.Phases) do
			setPhase(phase.Name, i, phase.Duration)
			local endedEarly = waitWithEarlyEnd(phase.Duration, shouldEndRound)
			if endedEarly then
				print("[GameLoop] runda kończy się wcześniej — wszyscy martwi")
				break
			end
		end
	end)
	if not ok then
		warn(("[GameLoop] błąd w trakcie rundy: %s — kończę rundę awaryjnie"):format(tostring(err)))
	end

	currentPhaseIndex = 0
	forceEndRound = false
	roundEnded:Fire()
	Remotes.RoundEnded:FireAllClients()
end

local function runPostRound()
	setState(STATE.POST_ROUND, Config.Game.PostRoundDuration)
	waitSkippable(Config.Game.PostRoundDuration)
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

-- Runda dużo dłuższa niż projektowe ~80s to zawsze ustawienie TESTOWE (patrz komentarz
-- przy Config.Lava.Phases). Głośny warn co boot, żeby 10-minutowa runda nie pojechała
-- cicho na produkcję razem z Lava.Enabled i Dev.Enabled.
local DESIGN_ROUND_SECONDS = 180

local function warnIfRoundTooLong()
	local total = totalRoundDuration()
	if total <= DESIGN_ROUND_SECONDS then return end
	warn(("[GameLoop] RUNDA WYDŁUŻONA: %ds (%.1f min) — tryb testowy. Wartości produkcyjne to ~80s (5/20/20/20/15). PRZYWRÓĆ PRZED LAUNCHEM!")
		:format(total, total / 60))
end

function GameLoopService.start()
	if started then
		warn("[GameLoop] start() wywołane drugi raz, ignoruję")
		return
	end
	started = true
	warnIfRoundTooLong()
	task.spawn(gameLoop)
end

return GameLoopService
