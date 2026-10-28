--!strict
-- PlayerDataService.luau
-- DataStore wrapper z atomic UpdateAsync, retry, throttle, session lock, BindToClose.
-- Trzyma combined state per gracz: { cash, inventory }. Jeden DataStore key per UserId.
--
-- Filozofia:
--   * Klient nigdy nie dotyka DataStore — server jest source of truth.
--   * UpdateAsync zamiast Get+Set: atomic, brak race condition gdy gracz disconnect.
--   * Session lock: nadpisuję key tylko jeśli to wejście gracza go zarezerwowało (lockId match).
--     Zabezpiecza przed roll-back gdy gracz w dwóch serwerach jednocześnie.
--   * BindToClose: gdy serwer się zamyka (shutdown, restart, update), force save WSZYSTKICH
--     graczy zanim Roblox zabije proces (max 30s).
--   * Auto-save co 60s + on PlayerRemoving — gracz traci max ~60s progress przy crashu.
--   * Nieudane wczytanie (po `LoadRetries` próbach) = wyrzucenie z komunikatem, nie gra na
--     domyślnych danych (decyzja Kacpra 29.09). Wyjątek: Studio — tam bez „API Services”
--     DataStore nie działa wcale, więc gra idzie na domyślnych w pamięci, bez zapisu.
--
-- API:
--   PlayerDataService.get(player)            -> data | nil  (live in-memory state)
--   PlayerDataService.update(player, mutator) -> ok  (mutator: (data) -> data; atomic + replicate?)
--   PlayerDataService.subscribe(callback)     -> () (fired po każdej mutacji; key:string, player, oldData, newData)
--   PlayerDataService.waitForData(player, timeout) -> bool (yielduje, aż dane są w pamięci)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local PlayerDataService = {}

local PD = Config.PlayerData

-- VERSIONED key namespace — jeśli kiedyś zmieniamy schemat, bump tej liczby
-- żeby nie crashować starych danych w nowym kodzie. Studio ma osobny magazyn (sufiks).
local DATASTORE_NAME = "ESCAPELAVA_PlayerData_v1" .. (if RunService:IsStudio() then PD.StudioStoreSuffix else "")

local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1, 1e9))
-- Lock jest per WEJŚCIE gracza, nie per serwer (przegląd 29.09, A-2). Ze wspólnym
-- `sessionId` szybki powrót na TEN SAM serwer brał klucz od razu — nie czekał na final save
-- z wyjścia, więc mógł wczytać dane sprzed niego, a „duch” z przerwanego wczytania miał ten
-- sam lock co nowy gracz i nadpisywał jego zapis.
local joinSeq = 0
local lockIdOf: { [Player]: string } = {}

-- In-memory state per player
local cache: { [Player]: any } = {}
local lastSaveAt: { [Player]: number } = {}
local saveInFlight: { [Player]: boolean } = {}
-- Gracze których LOAD failował — trzymają default w pamięci. Save ZABLOKOWANY:
-- zapis defaultu nadpisałby prawdziwe dane w DataStore (session lock nie chroni,
-- bo po czystym wyjściu na innym serwerze _sessionId=nil i check przepuszcza).
-- Od 29.09 tylko w Studio — poza nim nieudane wczytanie wyrzuca gracza.
local loadFailed: { [Player]: boolean } = {}
local subscribers: { (string, Player, any, any) -> () } = {}
-- Zapisy do DataStore w toku (także final save z PlayerRemoving i zwolnienie locka) —
-- BindToClose czeka, aż spadnie do zera (przegląd 29.09, A-6).
local pendingWrites = 0
-- KOŃCOWY ZAPIS = JEDEN na gracza (08.10): przy zamykaniu ten sam gracz był zapisywany dwa
-- razy pod rząd — przez BindToClose i przez PlayerRemoving. Drugi wywołujący CZEKA na pierwszy
-- końcowy zapis, zamiast pisać od nowa. "running" | "done"; nil = jeszcze nie było albo się
-- nie udał. BindToClose czeka na TEN stan, nie na wątki — opis przy BindToClose (19.10).
local finalSaveState: { [Player]: string } = {}
-- Od startu BindToClose auto-zapis nie dokłada zapisów — końcowy zapis każdego i tak idzie.
local closing = false

-- Session lock przy ŁADOWANIU. Sam lock przy zapisie nie wystarczy: jeśli load bezwarunkowo
-- przejmie klucz, poprzedni serwer (gracz przeskoczył serwery / szybki rejoin) trafi przy
-- swoim final save w gałąź "owned by other server" i JEGO zapis przepadnie — czyli mechanizm
-- chroniący dane sam je kasuje. Dlatego czekamy, aż tamten serwer zwolni lock swoim
-- final save (zwykle ułamek sekundy), i dopiero wtedy ładujemy. Starszy niż `LockStaleSec`
-- lock = serwer padł bez BindToClose → przejmujemy; ostatnia z `LockWaitAttempts` prób
-- przejmuje siłą.

local function defaultData(): any
	return {
		cash = 0,
		wins = 0,                -- wygrane rundy (przeżycie do końca) — leaderstats Tab
		inventory = {},          -- { [itemId] = count }  (np. { bomb = 3 })
		cosmetics = { owned = {}, equipped = {} }, -- permanent IDs; separate from consumable inventory
		-- appearance — wygląd postaci { skin, shirt, pants, sleeves, legs }, same ID
		-- z palet (NIE Color3: DataStore przyjmuje wyłącznie typy JSON-owalne).
		-- Celowo BRAK w defaultach: nieobecne pole = „jeszcze nie losowano", i to jest
		-- sygnał dla AppearanceService, żeby wylosować zestaw przy pierwszym wejściu.
		-- Stare save'y sprzed 2026-09-21 wchodzą tą samą ścieżką, bez migracji.
		-- (settings.graphics — wybór trybu grafiki 23.09-08.10; tryby usunięte 08.10, jeden profil
		-- dla wszystkich. Stare zapisy mogą mieć to pole — nikt go już nie czyta.)
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
	-- Additive migration: keep existing cash/inventory and the same DataStore namespace.
	-- CosmeticsService validates IDs/categories; unknown owned IDs are retained for future catalogs.
	if type(data.cosmetics) ~= "table" then
		data.cosmetics = { owned = {}, equipped = {} }
	end
end

local function notifySubscribers(eventKey: string, player: Player, oldData: any, newData: any)
	for _, cb in ipairs(subscribers) do
		task.spawn(cb, eventKey, player, oldData, newData)
	end
end

local function withRetry<T>(operation: () -> T, attempts: number): (boolean, T?)
	local backoff = PD.InitialBackoff
	for attempt = 1, attempts do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		warn(("[PlayerData] retry %d/%d po błędzie: %s"):format(attempt, attempts, tostring(result)))
		if attempt < attempts then
			task.wait(backoff)
			backoff *= 2
		end
	end
	return false, nil
end

-- Zwolnienie locka, który wzięło wczytanie gracza, który w międzyczasie WYSZEDŁ. Jego
-- PlayerRemoving przyszedł przed końcem wczytania, więc final save nie miał czego zapisać —
-- bez tego lock wisiał do `LockStaleSec`, a gracz trzymany w pamięci był auto-zapisywany
-- do końca życia serwera (przegląd 29.09, A-2). Zdejmujemy tylko WŁASNY lock.
local function releaseLock(key: string, lockId: string)
	pendingWrites += 1
	withRetry(function()
		return store:UpdateAsync(key, function(existing)
			if existing and existing._sessionId == lockId then
				existing._sessionId = nil
				return existing
			end
			return nil
		end)
	end, PD.SaveRetries)
	pendingWrites -= 1
end

local function loadPlayer(player: Player)
	local key = "u_" .. tostring(player.UserId)
	joinSeq += 1
	local lockId = sessionId .. "#" .. tostring(joinSeq)
	lockIdOf[player] = lockId
	-- W Studio bez „API Services” każda próba i tak się nie uda — tam krótko, jak zapis.
	local loadAttempts = if RunService:IsStudio() then PD.SaveRetries else PD.LoadRetries
	-- UpdateAsync na load żeby od razu zatwierdzić session lock (atomic).
	local ok, data
	for attempt = 1, PD.LockWaitAttempts do
		local lockedByOther = false
		local lastAttempt = attempt == PD.LockWaitAttempts

		ok, data = withRetry(function()
			return store:UpdateAsync(key, function(existing)
				if existing and existing._sessionId and existing._sessionId ~= lockId then
					local lockAge = os.time() - (existing._savedAt or 0)
					-- Świeży cudzy lock = tamten serwer (albo poprzednie wejście na tym) jeszcze
					-- robi final save. Zwracamy nil → UpdateAsync anuluje zapis i czekamy.
					if lockAge < PD.LockStaleSec and not lastAttempt then
						lockedByOther = true
						return nil
					end
					warn(("[PlayerData] przejmuję lock %s (wiek locka %ds) — poprzedni serwer padł albo nie zwolnił"):format(
						player.Name, lockAge))
				end
				lockedByOther = false
				local d = existing or defaultData()
				migrateSchema(d)
				d._sessionId = lockId
				d._savedAt = os.time()
				return d
			end)
		end, loadAttempts)

		if not lockedByOther then break end
		print(("[PlayerData] %s — klucz zajęty (inny serwer albo poprzednie wejście), czekam (%d/%d)"):format(
			player.Name, attempt, PD.LockWaitAttempts))
		task.wait(PD.LockWaitDelay)
		-- Gracz mógł wyjść w trakcie czekania — bez tego wstawilibyśmy cache dla ducha,
		-- którego PlayerRemoving już nie posprząta.
		if not player.Parent then return end
	end

	if not ok or type(data) ~= "table" then
		-- PlayerRemoving mógł już posprzątać, gdy retry czekało na odpowiedź DataStore.
		-- Nie odtwarzaj cache ani subskrypcji dla gracza, którego już nie ma.
		if not player.Parent then
			lockIdOf[player] = nil
			return
		end
		if RunService:IsStudio() then
			warn(("[PlayerData] LOAD FAIL %s — Studio: gram na domyślnych w pamięci (NIE zapisuję). Sprawdź Game Settings → Security → Enable Studio Access to API Services."):format(player.Name))
			-- Nie nadpisujemy DataStore defaultem — loadFailed blokuje TEŻ save przy
			-- leave/BindToClose (bez tego savePlayer przy wyjściu nadpisałby prawdziwe dane).
			data = defaultData()
			loadFailed[player] = true
			cache[player] = data
			notifySubscribers("loaded_default", player, nil, data)
			return
		end
		-- Poza Studio: wszystkie próby zawiodły (awaria DataStore). Gra na domyślnych danych
		-- oznaczałaby sesję, której nic się nie zapisze, a wygląd i itemy wyglądałyby na
		-- stracone — decyzja Kacpra 29.09: komunikat i wyjście, dane w DataStore są nietknięte.
		warn(("[PlayerData] LOAD FAIL %s po %d próbach — wyrzucam z komunikatem"):format(player.Name, PD.LoadRetries))
		lockIdOf[player] = nil
		if player.Parent then
			player:Kick(PD.LoadFailKickMessage)
		end
		return
	end

	-- Wyszedł w trakcie wczytania (PlayerRemoving już był i nie miał czego zapisać).
	if not player.Parent then
		releaseLock(key, lockId)
		lockIdOf[player] = nil
		return
	end

	cache[player] = data
	-- Jitter: gracze którzy weszli razem (start serwera, fala z TikToka) mieliby auto-save
	-- w tej samej sekundzie → 20 UpdateAsync w jednym ticku i wspólny retry-storm przy błędzie.
	-- Cofnięcie deadline'u o losowe 0-30s rozkłada zapisy równomiernie w oknie.
	lastSaveAt[player] = os.clock() - math.random() * (PD.AutoSaveInterval * 0.5)
	notifySubscribers("loaded", player, nil, data)
	print(("[PlayerData] loaded %s cash=%d items=%d"):format(player.Name, data.cash or 0, (function() local n=0 for _ in pairs(data.inventory or {}) do n+=1 end return n end)()))
end

local function writePlayer(player: Player, isClosing: boolean?): boolean
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
	local lockId = lockIdOf[player]
	if not data or not lockId then return false end
	saveInFlight[player] = true
	pendingWrites += 1

	local key = "u_" .. tostring(player.UserId)
	local skippedByLock = false
	local ok = withRetry(function()
		store:UpdateAsync(key, function(existing)
			-- Session lock check: zapisujemy tylko jeśli to NASZ lock (tego wejścia) albo klucz
			-- pusty/zwolniony — nikt inny nie przejął.
			if existing and existing._sessionId and existing._sessionId ~= lockId then
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
	end, PD.SaveRetries)

	saveInFlight[player] = false
	pendingWrites -= 1
	-- Pominięcie przez lock NIE jest sukcesem. Wcześniej leciał tu print "saved" mimo że
	-- nic nie zapisaliśmy — dokładnie ten log kłamałby przy diagnozie utraty danych.
	if skippedByLock then
		-- Klucz należy do kogoś innego — ten serwer ma nieaktualny stan i żaden jego zapis już
		-- nie przejdzie. Wypisujemy gracza z auto-zapisu; wcześniej `lastSaveAt` się nie
		-- odświeżał i UpdateAsync leciał co 5 s do końca życia serwera (przegląd 29.09, A-2).
		warn(("[PlayerData] save SKIP %s — session lock trzyma inny serwer, nic nie zapisano; koniec auto-zapisu"):format(player.Name))
		lastSaveAt[player] = nil
		return false
	end
	if ok then
		lastSaveAt[player] = os.clock()
		print(("[PlayerData] saved %s cash=%d"):format(player.Name, data.cash or 0))
		return true
	end
	-- Następna próba za SaveFailRetryDelay, nie w kolejnym obrocie pętli co 5 s (A-7).
	if lastSaveAt[player] then
		lastSaveAt[player] = os.clock() - PD.AutoSaveInterval + PD.SaveFailRetryDelay
	end
	warn(("[PlayerData] SAVE FAIL %s — zostawiam w pamięci, kolejna próba za %d s"):format(player.Name, PD.SaveFailRetryDelay))
	return false
end

-- Wejście do zapisu. Końcowy zapis (wyjście gracza / zamknięcie serwera) idzie RAZ — patrz
-- `finalSaveState`; nieudany można ponowić (stan wraca do nil).
local function savePlayer(player: Player, isClosing: boolean?): boolean
	if not isClosing then
		if closing then return false end
		return writePlayer(player, false)
	end
	local state = finalSaveState[player]
	if state == "done" then
		return true
	end
	if state == "running" then
		while finalSaveState[player] == "running" do
			task.wait(0.05)
		end
		return finalSaveState[player] == "done"
	end
	finalSaveState[player] = "running"
	local ok = writePlayer(player, true)
	finalSaveState[player] = if ok then "done" else nil
	return ok
end

function PlayerDataService.get(player: Player): any
	return cache[player]
end

-- Permanent transactions must stop before final save snapshots the session. Existing
-- readers may still need cache during PlayerRemoving/BindToClose, so get() stays unchanged.
function PlayerDataService.isWritable(player: Player): boolean
	return cache[player] ~= nil and not closing and finalSaveState[player] == nil
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

-- Czeka, aż dane gracza są w pamięci (wczytane albo — w Studio — domyślne). false = limit
-- czasu albo gracz wyszedł (np. wyrzucony po nieudanym wczytaniu). PlayerService czeka tak
-- przed PIERWSZYM spawnem, żeby wygląd szedł od razu z zapisu (decyzja Kacpra 29.09, A-1).
function PlayerDataService.waitForData(player: Player, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not cache[player] do
		if not player.Parent or os.clock() >= deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
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
	lockIdOf[player] = nil
	finalSaveState[player] = nil
end

local function autoSaveLoop()
	while true do
		task.wait(5)
		-- Snapshot listy PRZED zapisami — savePlayer yielduje (UpdateAsync), a gracz
		-- dołączający w trakcie dodałby klucz do lastSaveAt podczas trawersu pairs()
		-- = undefined behavior next() w Lua. Zbieramy due-listę bez yieldów, potem save.
		local due: { Player } = {}
		for player, last in pairs(lastSaveAt) do
			if os.clock() - last >= PD.AutoSaveInterval then
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
	-- task.spawn: wczytanie yielduje (UpdateAsync). Synchroniczne blokowało init całego
	-- serwera, a „loaded” gracza obecnego od startu leciał, zanim Cash/Item/Settings zdążyły
	-- się zapisać jako subskrybenci — i przepadał (nie było kasy ani itemów u klienta).
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end

	task.spawn(autoSaveLoop)

	-- BindToClose: ratunek przy shutdown servera (Roblox restart, update, place close).
	-- Mamy ~30s zanim Roblox zabije proces — save wszystkich w parallel. Po `cache`, nie po
	-- Players: gracz, którego Roblox już usunął, może być w trakcie final save z PlayerRemoving
	-- (cache czyścimy dopiero po nim) — wcześniej BindToClose go nie widział i kończył się,
	-- zanim ten zapis doszedł (przegląd 29.09, A-6).
	--
	-- CZEKAMY NA DANE, NIE NA WĄTKI (19.10, zmierzone w logu Studio: każde wyjście z Play
	-- 26,7-27,2 s, a sam zapis 0,7 s). W Studio klient rozłącza się ~0,6 s PRZED BindToClose,
	-- więc końcowy zapis robi PlayerRemoving, a wątek BindToClose tylko czeka na niego w pętli
	-- `task.wait`. Do 19.10 czekaliśmy, aż ten wątek się skończy — a on w trakcie zamykania nie
	-- budził się wcale (dlaczego silnik go nie wznawia — nieustalone), więc BindToClose stał
	-- pełne `CloseWaitMax` przy zerze zapisów w toku. Ta pętla budzi się normalnie (doliczała do
	-- 25,1 s), więc patrzy tylko na stan: `finalSaveState` "running" ustawia się PRZED pierwszym
	-- yieldem `savePlayer`, a gracz z udanym zapisem z PlayerRemoving znika z `cache`.
	game:BindToClose(function()
		closing = true
		print("[PlayerData] BindToClose — saving all players")
		for p in pairs(cache) do
			task.spawn(savePlayer, p, true)
		end
		local function stillSaving(): { string }
			local names = {}
			for p in pairs(cache) do
				if finalSaveState[p] == "running" then table.insert(names, p.Name) end
			end
			return names
		end
		local deadline = os.clock() + PD.CloseWaitMax
		local started = os.clock()
		while (pendingWrites > 0 or #stillSaving() > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
		local waiting = stillSaving()
		if pendingWrites > 0 or #waiting > 0 then
			-- Diagnostyka: co trzyma zamknięcie, gdyby wiszenie wróciło (lekcja 11 — log, nie zgadywanie).
			local inFlight = {}
			for p, f in pairs(saveInFlight) do
				if f then table.insert(inFlight, p.Name) end
			end
			warn(("[PlayerData] BindToClose: limit %d s minął — zapisów w toku %d, końcowy zapis niezakończony: %s, w locie: %s"):format(
				PD.CloseWaitMax, pendingWrites,
				if #waiting > 0 then table.concat(waiting, ", ") else "—",
				if #inFlight > 0 then table.concat(inFlight, ", ") else "—"))
		end
		print(("[PlayerData] BindToClose done po %.1f s (zapisów w toku: %d)"):format(os.clock() - started, pendingWrites))
	end)
end

return PlayerDataService
