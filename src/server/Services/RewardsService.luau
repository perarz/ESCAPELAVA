--!strict
-- RewardsService.luau
-- Wypłaca nagrodę snapshotowi ocalałych na RoundFinished, przed FINISHING hold i cleanup.
-- Każdy ocalały dostaje Config.Rewards.Win $ razy jego mnożnik z drzewka (GREED + rebirthy,
-- SkillService.cashMultiplier); runda nie ma dawnych faz/Endgame.
-- Remotes.RoundWon idzie do każdego ocalałego osobno z JEGO kwotą — „YOU SURVIVED! +X$”
-- (WinMessageController).
-- Tu też zamykają się statystyki rundy (StatsService): rozegrana dla uczestników, przetrwana
-- dla ocalałych — ten sam snapshot, co nagroda.
--
-- Kill rewards są w KillService (per-hit trigger). RewardsService tylko o survival bonus.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CashService = require(script.Parent.CashService)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerService = require(script.Parent.PlayerService)
local SkillService = require(script.Parent.SkillService)
local StatsService = require(script.Parent.StatsService)

local RewardsService = {}
local initialized = false

local function onRoundEnded()
	-- Snapshot at FINISHING, before the 3-second hold and cleanup can change survivors.
	local winners = PlayerService.getAliveList()
	-- Uczestnicy czytani TERAZ: PlayerService czyści ich listę dopiero przy powrocie do lobby.
	StatsService.recordRound(PlayerService.getRoundPlayers(), winners)
	if #winners == 0 then
		Remotes.RoundWon:FireAllClients({}, 0)
		return
	end

	for _, p in ipairs(winners) do
		local reward = math.round(Config.Rewards.Win * SkillService.cashMultiplier(p))
		CashService.add(p, reward, "win_bonus")
		-- Wins licznik (leaderstats Tab). LeaderstatsService sync'uje przez "updated" event.
		PlayerDataService.update(p, function(data)
			data.wins = (data.wins or 0) + 1
			return data
		end)
		-- Każdy widzi SWOJĄ kwotę (mnożniki różnią się między graczami).
		Remotes.RoundWon:FireClient(p, { p }, reward)
	end
end

function RewardsService.init()
	if initialized then return end
	initialized = true

	GameLoopService.RoundFinished:Connect(onRoundEnded)
end

return RewardsService
