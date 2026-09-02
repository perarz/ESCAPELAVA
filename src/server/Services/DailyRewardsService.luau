--!strict
-- DailyRewardsService.luau
-- Daily login reward ze streakiem. Dzień = kalendarzowy dzień UTC (floor(os.time()/86400))
-- — CAŁA logika czasu server-side; klient dostaje gotowe liczby (zegar klienta = niezaufany).
--
-- Zasady (ustalone z Kacprem):
--   * Claim raz na dzień kalendarzowy UTC (reset o północy UTC, nie 24h od claima).
--   * Pominięty dzień → streak reset do 1 przy następnym claimie.
--   * Dzień 8+ → ostatnia nagroda z Config.DailyRewards.Rewards w kółko (500$/dzień).
--
-- Flow:
--   * load → push DailyRewardsInfo (task.delay 1s — klient musi zdążyć z Connect).
--   * ClaimDaily → validate (rate limit, data loaded, nie claimowane dziś) → credit
--     przez CashService (loguje transakcję) → persist streak → push świeże info.
--   * Klient odlicza secondsToNextDay lokalnie; po zejściu do 0 pokazuje CLAIM —
--     server i tak waliduje przy claimie, więc drift zegara klienta jest niegroźny.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CashService = require(script.Parent.CashService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local DailyRewardsService = {}

local SECONDS_PER_DAY = 86400

local lastClaimAttemptAt: { [Player]: number } = {}
local initialized = false

local function currentDayNumber(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

local function secondsToNextDay(): number
	return SECONDS_PER_DAY - (os.time() % SECONDS_PER_DAY)
end

-- Efektywny streak: 0 jeśli przerwany (ostatni claim starszy niż wczoraj).
-- Zwraca też claimedToday — obie wartości liczone z tego samego snapshotu danych.
local function effectiveState(data: any): (number, boolean)
	local today = currentDayNumber()
	local lastDay = data.lastClaimDay or 0
	local streak = data.dailyStreak or 0

	if lastDay == today then
		return streak, true
	elseif lastDay == today - 1 then
		return streak, false
	else
		return 0, false -- przerwany (lub pierwszy raz) — następny claim = dzień 1
	end
end

local function pushInfo(player: Player)
	local data = PlayerDataService.get(player)
	if not data then return end
	local streak, claimedToday = effectiveState(data)
	Remotes.DailyRewardsInfo:FireClient(player, streak, claimedToday, secondsToNextDay())
end

local function rewardForDay(day: number): number
	local rewards = Config.DailyRewards.Rewards
	return rewards[math.min(day, #rewards)]
end

local function onClaimDaily(player: Player)
	local now = os.clock()
	if now - (lastClaimAttemptAt[player] or 0) < Config.RateLimits.DailyClaim then return end
	lastClaimAttemptAt[player] = now

	local data = PlayerDataService.get(player)
	if not data then return end -- DataStore jeszcze nie załadował

	local streak, claimedToday = effectiveState(data)
	if claimedToday then
		pushInfo(player) -- odśwież klienta — pewnie ma stale state
		return
	end

	local newStreak = streak + 1
	local reward = rewardForDay(newStreak)
	local today = currentDayNumber()

	-- Persist PRZED credit — gdyby serwer padł między, gracz traci $ ale nie może
	-- claimować drugi raz (odwrotna kolejność = duplikacja przy crashu).
	local ok = PlayerDataService.update(player, function(d)
		d.dailyStreak = newStreak
		d.lastClaimDay = today
		return d
	end)
	if not ok then return end

	CashService.add(player, reward, "daily_day" .. newStreak)
	pushInfo(player)
end

local function onPlayerRemoving(player: Player)
	lastClaimAttemptAt[player] = nil
end

function DailyRewardsService.init()
	if initialized then return end
	initialized = true

	PlayerDataService.subscribe(function(eventKey, player, _oldData, _newData)
		if eventKey == "loaded" or eventKey == "loaded_default" then
			-- Ten sam pattern co ItemService: 1s żeby klient zdążył podpiąć OnClientEvent.
			task.delay(1, function()
				if player.Parent then
					pushInfo(player)
				end
			end)
		end
	end)

	Remotes.ClaimDaily.OnServerEvent:Connect(onClaimDaily)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DailyRewardsService
