--!strict
-- GameLoopService.luau
-- State machine: LOBBY → PREPARING → COUNTDOWN → ROUND → FINISHING → RESETTING → POST_ROUND.
--
-- (lawa przyspiesza płynnie — LavaService liczy prędkość z czasu od startu rundy).
-- Emituje stany przez BindableEventy (dla serwisów) i RemoteEventy (dla klientów).
--
-- Zewnętrzne serwisy (PlayerService) mogą wstrzyknąć getAliveCountProvider żeby runda
-- mogła wcześnie kończyć gdy wszyscy umrą.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local STATE = {
	LOBBY = "LOBBY",
	PREPARING = "PREPARING",
	COUNTDOWN = "COUNTDOWN",
	FINISHING = "FINISHING",
	RESETTING = "RESETTING",
	ROUND = "ROUND",
	POST_ROUND = "POST_ROUND",
}

local GameLoopService = {}
GameLoopService.STATE = STATE

local stateChanged = Instance.new("BindableEvent")
local roundEnded = Instance.new("BindableEvent")
local roundFinished = Instance.new("BindableEvent")
GameLoopService.RoundFinished = roundFinished.Event -- result snapshot before transition/cleanup
GameLoopService.StateChanged = stateChanged.Event   -- (newState: string)
GameLoopService.RoundEnded = roundEnded.Event       -- ()

local currentState: string = STATE.LOBBY
local currentStateDuration: number = 0
local currentStateStartedAt: number = 0
local started = false

local aliveProvider: () -> number = function() return 0 end
local prepareRound: (() -> ())? = nil
local stateEndsAt = 0

function GameLoopService.setRoundPreparer(fn: () -> ())
	prepareRound = fn
end

-- TRYB DEV (Config.Dev): pomijanie czekania. `skipRequested` jest JEDNORAZOWY — każdy
-- wait konsumuje go i czyści, więc jedno naciśnięcie klawisza = jeden pominięty etap (w rundzie = koniec rundy),
-- a nie lawina przeskoków. `forceEndRound` żyje do końca rundy (czyszczony na starcie).
local skipRequested = false
local forceEndRound = false

function GameLoopService.setAliveCountProvider(fn: () -> number)
	aliveProvider = fn
end

-- Wołane WYŁĄCZNIE przez DevService (po walidacji uprawnień). Zwraca opis dla logu.
function GameLoopService.devSkip(): string
	skipRequested = true
	return currentState
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

local function setState(newState: string, duration: number?)
	currentState = newState
	local dur = duration or 0
	currentStateDuration = dur
	currentStateStartedAt = os.clock()
	stateEndsAt = Workspace:GetServerTimeNow() + dur
	stateChanged:Fire(newState, dur)
	Remotes.GameStateChanged:FireAllClients(newState, dur, stateEndsAt)
	print(("[GameLoop] state → %s (dur=%ds)"):format(newState, dur))
end

-- Replikuje aktualny state do konkretnego gracza (na PlayerAdded).
-- Klient yieldje na WaitForChild HUD i może minąć moment gdy server odpala
-- pierwsze setState — bez tego HUD utknie na default tekście.
function GameLoopService.replicateTo(player: Player)
	local stateElapsed = os.clock() - currentStateStartedAt
	local stateRemaining = math.max(currentStateDuration - stateElapsed, 0)
	Remotes.GameStateChanged:FireClient(player, currentState, stateRemaining, stateEndsAt)
end

local function waitWithEarlyEnd(duration: number, endCheck: (() -> boolean)?): boolean
	-- Yield FIRST, check AFTER. Roblox BindableEvents w deferred mode (default od 2023)
	-- wywołują listenery na następnej klatce; sprawdzanie endCheck przed pierwszym
	-- yieldem łapie alive=0 zanim PlayerService.sendEveryoneToRound zdąży się odpalić.
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		task.wait(0.25)
		-- Dev skip przerywa czekanie (w rundzie = koniec rundy, jak `devEndRound`).
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
	setState(STATE.PREPARING, 0)
	assert(prepareRound, "PlayerService round preparer missing")
	prepareRound()
	-- Spawns finish before countdown; clients get time to settle lighting and unveil.
	task.wait(Config.RoundTransition.SettleTime + Config.RoundTransition.FadeOutTime)
	setState(STATE.COUNTDOWN, Config.Game.StartCountdown)
	-- Never skip the visible countdown: every participant shares the same start.
	task.wait(Config.Game.StartCountdown)
	skipRequested = false
end

local function runRound()
	-- Świeży start: żądanie "zakończ rundę" z poprzedniej rundy nie może ubić tej.
	forceEndRound = false
	setState(STATE.ROUND, Config.Lava.RoundDuration)

	-- Let deferred ROUND listeners release root locks and start the lava before checks.
	task.wait()

	-- Runda w OSOBNYM pcall, bo na roundEnded wiszą: restore mapy (MapService),
	-- cleanup cashu i mostów. Wyniki publikuje wcześniejszy RoundFinished.
	-- Gdyby błąd w rundzie przeleciał do pcall'a całej pętli gry, żadna
	-- z tych rzeczy by się nie wykonała i kolejna runda startowałaby w rozjebanym świecie
	-- (mapa w gruzach, aliveSet pełen duchów → runda kończy się natychmiast albo wcale).
	local ok, err = pcall(function()
		if waitWithEarlyEnd(Config.Lava.RoundDuration, shouldEndRound) then
			print("[GameLoop] runda kończy się wcześniej — wszyscy martwi")
		end
	end)
	if not ok then
		warn(("[GameLoop] błąd w trakcie rundy: %s — kończę rundę awaryjnie"):format(tostring(err)))
	end

	forceEndRound = false
	setState(STATE.FINISHING, Config.Game.FinishHold)
	roundFinished:Fire()
	-- Leave the lava/map in place while the last death and result are readable.
	task.wait(Config.Game.FinishHold)
	setState(STATE.RESETTING, Config.RoundTransition.ResetCoverTime)
	task.wait(Config.RoundTransition.ResetCoverTime)
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
			setState(STATE.LOBBY, 0) -- releases any preparation locks on failure
			task.wait(5)
		end
	end
end

-- Runda dużo dłuższa niż projektowe ~80s to zawsze ustawienie TESTOWE (patrz komentarz
-- przy Config.Lava.RoundDuration). Głośny warn co boot, żeby 10-minutowa runda nie pojechała
-- cicho na produkcję razem z Lava.Enabled i Dev.Enabled.
local DESIGN_ROUND_SECONDS = 180

local function warnIfRoundTooLong()
	local total = Config.Lava.RoundDuration
	if total <= DESIGN_ROUND_SECONDS then return end
	warn(("[GameLoop] RUNDA WYDŁUŻONA: %ds (%.1f min) — tryb testowy. Produkcja: 80 s, lawa 0 → 3.0 stud/s. PRZYWRÓĆ PRZED LAUNCHEM!")
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
