--!strict
-- StatsService.luau (09.11) — właściciel statystyk gracza: `kills`, `survived`, `played`.
--
-- Każda w dwóch licznikach (zapis: `data.stats`, PlayerDataService):
--   total — od początku gry, tylko do wyświetlania;
--   cycle — od ostatniego rebirthu. Na nim stoją wymagania pól drzewka (SkillDefinitions):
--           liczone od początku gry byłyby po pierwszym okrążeniu spełnione na zawsze.
--
-- Skąd przychodzą (ten serwis sam niczego nie nasłuchuje, żeby nie było drugiej listy
-- uczestników ani drugiego liczenia zabójstw):
--   kill              — KillService.processDeath, razem z nagrodą za zabójstwo;
--   played / survived — RewardsService na RoundFinished: uczestnicy z PlayerService
--                       (bez pomijających i dołączających) i snapshot ocalałych.
--
-- Zerowanie `cycle` przy rebirthie robi SkillService w SWOJEJ jednej mutacji danych przez
-- `resetCycleIn` — reset drzewka, licznik rebirthów i statystyki muszą zmienić się razem.
--
-- API:
--   StatsService.add(player, stat, amount?)            — jedna statystyka
--   StatsService.recordRound(participants, survivors)  — koniec rundy, jedna zmiana na gracza
--   StatsService.getCycle(player, stat) -> number
--   StatsService.snapshot(player) -> { total, cycle }? — kopia do wysłania klientowi
--   StatsService.resetCycleIn(data)                    — WYŁĄCZNIE wewnątrz mutatora PlayerDataService
--   StatsService.onChanged(callback(player))           — po każdej zmianie (SkillService odświeża panel)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillDefinitions = require(ReplicatedStorage.Shared.Modules.SkillDefinitions)
local PlayerDataService = require(script.Parent.PlayerDataService)

local StatsService = {}

type Counters = { [string]: number }
export type Snapshot = { total: Counters, cycle: Counters }

local STATS = SkillDefinitions.stats
local listeners: { (Player) -> () } = {}

-- Tylko znane statystyki i tylko nieujemne liczby całkowite (zapis mógł powstać w starszej
-- wersji albo być uszkodzony; DataStore przyjmuje wyłącznie typy JSON).
local function cleanCounters(raw: any): Counters
	local out: Counters = {}
	for _, stat in ipairs(STATS) do
		local value = if type(raw) == "table" then raw[stat] else nil
		if type(value) == "number" and value == value and value >= 0 and value < math.huge then
			out[stat] = math.floor(value)
		else
			out[stat] = 0
		end
	end
	return out
end

local function sanitize(raw: any): Snapshot
	local source = if type(raw) == "table" then raw else {}
	return { total = cleanCounters(source.total), cycle = cleanCounters(source.cycle) }
end

local function isStat(stat: string): boolean
	return table.find(STATS, stat) ~= nil
end

local function notify(player: Player)
	for _, callback in ipairs(listeners) do
		task.spawn(callback, player)
	end
end

-- Jedna mutacja danych na wywołanie; `changes` = { [stat] = o ile }.
local function apply(player: Player, changes: Counters): boolean
	local ok = PlayerDataService.update(player, function(data)
		local stats = sanitize(data.stats)
		for stat, amount in pairs(changes) do
			stats.total[stat] += amount
			stats.cycle[stat] += amount
		end
		data.stats = stats
		return data
	end)
	if ok then notify(player) end
	return ok
end

function StatsService.add(player: Player, stat: string, amount: number?)
	local by = amount or 1
	if not isStat(stat) or by <= 0 or by % 1 ~= 0 then return end
	apply(player, { [stat] = by })
end

-- Koniec rundy: każdy uczestnik +1 `played`, ocalały dodatkowo +1 `survived`. Jedna zmiana
-- danych i jedno powiadomienie na gracza (zamiast dwóch pod rząd).
function StatsService.recordRound(participants: { Player }, survivors: { Player })
	local survived: { [Player]: boolean } = {}
	for _, player in ipairs(survivors) do
		survived[player] = true
	end
	local counted: { [Player]: boolean } = {}
	for _, player in ipairs(participants) do
		if counted[player] or player.Parent ~= Players then continue end
		counted[player] = true
		apply(player, if survived[player] then { played = 1, survived = 1 } else { played = 1 })
	end
	-- Ocalały spoza listy uczestników nie powinien się zdarzyć; gdyby się zdarzył, nie gubimy
	-- mu rundy.
	for _, player in ipairs(survivors) do
		if not counted[player] and player.Parent == Players then
			counted[player] = true
			apply(player, { played = 1, survived = 1 })
		end
	end
end

function StatsService.getCycle(player: Player, stat: string): number
	local data = PlayerDataService.get(player)
	if not data then return 0 end
	return sanitize(data.stats).cycle[stat] or 0
end

function StatsService.snapshot(player: Player): Snapshot?
	local data = PlayerDataService.get(player)
	if not data then return nil end
	return sanitize(data.stats)
end

-- Zeruje licznik od ostatniego rebirthu W PODANEJ tabeli danych. Bez yieldu i bez
-- powiadomień: woła to SkillService w środku własnej mutacji i sam rozsyła nowy stan.
function StatsService.resetCycleIn(data: any)
	local stats = sanitize(data.stats)
	stats.cycle = cleanCounters(nil)
	data.stats = stats
end

function StatsService.onChanged(callback: (Player) -> ())
	table.insert(listeners, callback)
end

local initialized = false
function StatsService.init()
	if initialized then return end
	initialized = true
	-- Porządek po wczytaniu, jak kosmetyki: od tej chwili `data.stats` ma zawsze pełny kształt.
	PlayerDataService.subscribe(function(eventKey, player, _old, _data)
		if eventKey ~= "loaded" and eventKey ~= "loaded_default" then return end
		if player.Parent ~= Players then return end
		PlayerDataService.update(player, function(current)
			current.stats = sanitize(current.stats)
			return current
		end)
	end)
end

return StatsService
