--!strict
-- PlayerDataService.luau
-- DataStore wrapper z atomic UpdateAsync, retry, throttle, session lock, BindToClose.
-- Trzyma combined state per gracz: { cash, inventory }. Jeden DataStore key per UserId.
--
-- Filozofia:
--   * Klient nigdy nie dotyka DataStore — server jest source of truth.
--   * UpdateAsync zamiast Get+Set: atomic, brak race condition gdy gracz disconnect.
--   * Session lock: nadpisuję key tylko jeśli ten serwer go zarezerwował (sessionId match).
--     Zabezpiecza przed roll-back gdy gracz w dwóch serwerach jednocześnie.
--   * BindToClose: gdy serwer się zamyka (shutdown, restart, update), force save WSZYSTKICH
--     graczy zanim Roblox zabije proces (max 30s).
--   * Auto-save co 60s + on PlayerRemoving — gracz traci max ~60s progress przy crashu.
--
-- API:
--   PlayerDataService.get(player)            -> data | nil  (live in-memory state)
--   PlayerDataService.update(player, mutator) -> ok  (mutator: (data) -> data; atomic + replicate?)
--   PlayerDataService.subscribe(callback)     -> () (fired po każdej mutacji; key:string, player, oldData, newData)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDataService = {}

-- VERSIONED key namespace — jeśli kiedyś zmieniamy schemat, bump tej liczby
-- żeby nie crashować starych danych w nowym kodzie.
local DATASTORE_NAME = "ESCAPELAVA_PlayerData_v1"

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1, 1e9))

-- In-memory state per player
local cache: { [Player]: any } = {}
local lastSaveAt: { [Player]: number } = {}
local saveInFlight: { [Player]: boolean } = {}
-- Gracze których LOAD failował — trzymają default w pamięci. Save ZABLOKOWANY:
-- zapis defaultu nadpisałby prawdziwe dane w DataStore (session lock nie chroni,
-- bo po czystym wyjściu na innym serwerze _sessionId=nil i check przepuszcza).
local loadFailed: { [Player]: boolean } = {}
local subscribers: { (string, Player, any, any) -> () } = {}

local AUTO_SAVE_INTERVAL = 60        -- sekund
local MAX_RETRIES = 3
local INITIAL_BACKOFF = 0.5          -- sekund (×2 każda retry)

-- Session lock przy ŁADOWANIU. Sam lock przy zapisie nie wystarczy: jeśli load bezwarunkowo
-- przejmie klucz, poprzedni serwer (gracz przeskoczył serwery / szybki rejoin) trafi przy
-- swoim final save w gałąź "owned by other server" i JEGO zapis przepadnie — czyli mechanizm
-- chroniący dane sam je kasuje. Dlatego czekamy, aż tamten serwer zwolni lock swoim
-- final save (zwykle ułamek sekundy), i dopiero wtedy ładujemy.
local LOCK_STALE_SEC = 90            -- starszy lock = serwer padł bez BindToClose → przejmujemy
local LOCK_WAIT_ATTEMPTS = 3         -- ile razy czekamy zanim przejmiemy siłą
local LOCK_WAIT_DELAY = 2            -- sekund między próbami

local function defaultData(): any
	return {
		cash = 0,
		wins = 0,                -- wygrane rundy (przeżycie do końca) — leaderstats Tab
		inventory = {},          -- { [itemId] = count }  (np. { bomb = 3 })
		_sessionId = nil,        -- ustawiamy po load — wykryjemy "fork" gdy ktoś zacznie w innym serwerze
		_savedAt = 0,
	}
end

-- Migracja schematu starych save'ów: pre-rename gracze mają `data.coins`, nowy kod
-- używa `data.cash`. Przepisujemy raz przy load i save'ujemy nową formę. Idempotentne:
-- jeśli `data.cash` już istnieje, nie nadpisujemy. Pole `coins` zostaje wyczyszczone
-- po skopiowaniu żeby kolejne loady nie próbowały migrować w kółko.
local function migrateSchema(data: any)
	if type(data) ~= "table" then return end
	if data.cash == nil and data.coins ~= nil then
		data.cash = data.coins
		data.coins = nil
	end
	-- Save'y sprzed leaderboardu nie mają pola wins.
	if data.wins == nil then
		data.wins = 0
	end
end

local function notifySubscribers(eventKey: string, player: Player, oldData: any, newData: any)
	for _, cb in ipairs(subscribers) do
		task.spawn(cb, eventKey, player, oldData, newData)
	end
end

local function withRetry<T>(operation: () -> T): (boolean, T?)
	local backoff = INITIAL_BACKOFF
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		warn(("[PlayerData] retry %d/%d po błędzie: %s"):format(attempt, MAX_RETRIES, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(backoff)
			backoff *= 2
		end
	end
	return false, nil
end

local function loadPlayer(player: Player)
	local key = "u_" .. tostring(player.UserId)
	-- UpdateAsync na load żeby od razu zatwierdzić session lock (atomic).
	local ok, data
	for attempt = 1, LOCK_WAIT_ATTEMPTS do
		local lockedByOther = false
		local lastAttempt = attempt == LOCK_WAIT_ATTEMPTS

		ok, data = withRetry(function()
			return store:UpdateAsync(key, function(existing)
				if existing and existing._sessionId and existing._sessionId ~= sessionId then
					local lockAge = os.time() - (existing._savedAt or 0)
					-- Świeży cudzy lock = tamten serwer jeszcze żyje i zaraz zrobi final save.
					-- Zwracamy nil → UpdateAsync anuluje zapis (żadnej operacji write) i czekamy.
					if lockAge < LOCK_STALE_SEC and not lastAttempt then
						lockedByOther = true
						return nil
					end
					warn(("[PlayerData] przejmuję lock %s (wiek locka %ds) — poprzedni serwer padł albo nie zwolnił"):format(
						player.Name, lockAge))
				end
				lockedByOther = false
				local d = existing or defaultData()
				migrateSchema(d)
				d._sessionId = sessionId
				d._savedAt = os.time()
				return d
			end)
		end)

		if not lockedByOther then break end
		print(("[PlayerData] %s — klucz zajęty przez inny serwer, czekam (%d/%d)"):format(
			player.Name, attempt, LOCK_WAIT_ATTEMPTS))
		task.wait(LOCK_WAIT_DELAY)
		-- Gracz mógł wyjść w trakcie czekania — bez tego wstawilibyśmy cache dla ducha,
		-- którego PlayerRemoving już nie posprząta.
		if not player.Parent then return end
	end

	if not ok or type(data) ~= "table" then
		warn(("[PlayerData] LOAD FAIL %s — wstawiam default w pamięci (NIE zapisuję)"):format(player.Name))
		-- Crucial: nie nadpisujemy DataStore default'em, bo to mogłoby usunąć istniejący stan
		-- gdyby tylko storage failował. Trzymamy default tylko w pamięci aż user disconnect.
		-- loadFailed blokuje TEŻ save przy leave/BindToClose (bez tego "NIE zapisuję" było
		-- prawdą tylko na load — savePlayer przy wyjściu i tak nadpisywał prawdziwe dane).
		data = defaultData()
		loadFailed[player] = true
		cache[player] = data
		notifySubscribers("loaded_default", player, nil, data)
		return
	end

	cache[player] = data
	-- Jitter: gracze którzy weszli razem (start serwera, fala z TikToka) mieliby auto-save
	-- w tej samej sekundzie → 20 UpdateAsync w jednym ticku i wspólny retry-storm przy błędzie.
	-- Cofnięcie deadline'u o losowe 0-30s rozkłada zapisy równomiernie w oknie.
	lastSaveAt[player] = os.clock() - math.random() * (AUTO_SAVE_INTERVAL * 0.5)
	notifySubscribers("loaded", player, nil, data)
	print(("[PlayerData] loaded %s cash=%d items=%d"):format(player.Name, data.cash or 0, (function() local n=0 for _ in pairs(data.inventory or {}) do n+=1 end return n end)()))
end

local function savePlayer(player: Player, isClosing: boolean?): boolean
	if loadFailed[player] then
		warn(("[PlayerData] save SKIP %s — load failował, nie nadpisuję DataStore defaultem"):format(player.Name))
		return false
	end
	if saveInFlight[player] then
		-- Auto-save: po prostu odpuść, następny tick spróbuje ponownie.
		if not isClosing then return false end
		-- Final save (leave / BindToClose): MUSI się wykonać — czekamy aż in-flight
		-- auto-save skończy. Bez tego: return false → cache czyszczony bez zapisu
		-- ostatnich mutacji + _sessionId nigdy nie zwolniony.
		while saveInFlight[player] do
			task.wait(0.05)
		end
	end
	local data = cache[player]
	if not data then return false end
	saveInFlight[player] = true

	local key = "u_" .. tostring(player.UserId)
	local skippedByLock = false
	local ok = withRetry(function()
		store:UpdateAsync(key, function(existing)
			-- Session lock check: zapisujemy tylko jeśli to NASZ session lub key pusty/stary
			-- (czyli ostatni zapis był z naszego serwera; nikt inny nie przejął).
			if existing and existing._sessionId and existing._sessionId ~= sessionId then
				-- Inny serwer już zalokował tego gracza (np. teleport do innego place).
				-- Pomijamy save — ten serwer ma stary state, nadpisanie cofnęłoby tamten.
				-- nil zamiast existing: anuluje operację zapisu zamiast przepisywać to samo.
				skippedByLock = true
				return nil
			end
			-- Reset przy każdym wywołaniu transformu — UpdateAsync może go wołać wielokrotnie
			-- (konflikt zapisu), liczy się TYLKO ostatnie wywołanie.
			skippedByLock = false
			data._savedAt = os.time()
			-- Przy isClosing zwalniamy session lock (player faktycznie wyszedł)
			if isClosing then
				data._sessionId = nil
			end
			return data
		end)
	end)

	saveInFlight[player] = false
	-- Pominięcie przez lock NIE jest sukcesem. Wcześniej leciał tu print "saved" mimo że
	-- nic nie zapisaliśmy — dokładnie ten log kłamałby przy diagnozie utraty danych.
	if skippedByLock then
		warn(("[PlayerData] save SKIP %s — session lock trzyma inny serwer, nic nie zapisano"):format(player.Name))
		return false
	end
	if ok then
		lastSaveAt[player] = os.clock()
		print(("[PlayerData] saved %s cash=%d"):format(player.Name, data.cash or 0))
		return true
	end
	warn(("[PlayerData] SAVE FAIL %s — zostawiam w pamięci, retry na następnym tick"):format(player.Name))
	return false
end

function PlayerDataService.get(player: Player): any
	return cache[player]
end

-- Mutacja in-place: mutator dostaje ŻYWĄ referencję cache (nie kopię — świadomy trade-off,
-- zero alokacji per mutacja) i zwraca state (zwykle tę samą tabelę). Konsekwencja dla
-- subscriberów: oldData i newData to TA SAMA tabela — diffowanie wartości przed/po NIE działa.
-- Zmiany lecą do in-memory cache; DataStore save odbywa się na auto-save / leave / BindToClose.
function PlayerDataService.update(player: Player, mutator: (any) -> any): boolean
	local data = cache[player]
	if not data then return false end
	local newData = mutator(data)
	if newData == nil then return false end
	cache[player] = newData
	notifySubscribers("updated", player, data, newData)
	return true
end

function PlayerDataService.subscribe(callback: (string, Player, any, any) -> ())
	table.insert(subscribers, callback)
end

local function onPlayerAdded(player: Player)
	loadPlayer(player)
end

local function onPlayerRemoving(player: Player)
	savePlayer(player, true)
	cache[player] = nil
	lastSaveAt[player] = nil
	saveInFlight[player] = nil
	loadFailed[player] = nil
end

local function autoSaveLoop()
	while true do
		task.wait(5)
		-- Snapshot listy PRZED zapisami — savePlayer yielduje (UpdateAsync), a gracz
		-- dołączający w trakcie dodałby klucz do lastSaveAt podczas trawersu pairs()
		-- = undefined behavior next() w Lua. Zbieramy due-listę bez yieldów, potem save.
		local due: { Player } = {}
		for player, last in pairs(lastSaveAt) do
			if os.clock() - last >= AUTO_SAVE_INTERVAL then
				table.insert(due, player)
			end
		end
		for _, player in ipairs(due) do
			if cache[player] then -- mógł wyjść między snapshotem a teraz
				savePlayer(player, false)
			end
		end
	end
end

local initialized = false
function PlayerDataService.init()
	if initialized then return end
	initialized = true

	if RunService:IsStudio() then
		print("[PlayerData] Studio session — DataStore będzie działał tylko jeśli włączone 'Enable Studio Access to API Services' w Game Settings.")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end

	task.spawn(autoSaveLoop)

	-- BindToClose: ratunek przy shutdown servera (Roblox restart, update, place close).
	-- Mamy ~30s zanim Roblox zabije proces — save wszystkich w parallel.
	game:BindToClose(function()
		print("[PlayerData] BindToClose — saving all players")
		local players = Players:GetPlayers()
		local threads = {}
		for _, p in ipairs(players) do
			local thread = task.spawn(function()
				savePlayer(p, true)
			end)
			table.insert(threads, thread)
		end
		-- Czekamy do 25s (zostaw 5s buffer dla Roblox)
		local deadline = os.clock() + 25
		while os.clock() < deadline do
			local anyAlive = false
			for _, t in ipairs(threads) do
				if coroutine.status(t) ~= "dead" then anyAlive = true break end
			end
			if not anyAlive then break end
			task.wait(0.1)
		end
		print("[PlayerData] BindToClose done")
	end)
end

return PlayerDataService
