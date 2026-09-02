--!strict
-- RewardsService.luau
-- Wypłaca nagrodę za wygraną rundę: WSZYSCY ocaleli po Endgame dostają Config.Rewards.Win $.
-- Fires Remotes.RoundWon(winners, reward) — klient wyświetla banner "NAME WON $X".
--
-- Kill rewards są w KillService (per-hit trigger). RewardsService tylko o survival bonus.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local CashService = require(script.Parent.CashService)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerService = require(script.Parent.PlayerService)

local RewardsService = {}
local initialized = false

local function onRoundEnded()
	-- Listener odpala się na deferred queue PRZED PlayerService.sendSurvivorsToLobby
	-- (bo roundEnded:Fire() wykonane przed setState(POST_ROUND) → stateChanged:Fire()).
	-- Więc aliveSet nadal ma prawidłowych winners.
	local winners = PlayerService.getAliveList()
	if #winners == 0 then
		Remotes.RoundWon:FireAllClients({}, 0)
		return
	end

	local reward = Config.Rewards.Win
	for _, p in ipairs(winners) do
		CashService.add(p, reward, "win_bonus")
		-- Wins licznik (leaderstats Tab). LeaderstatsService sync'uje przez "updated" event.
		PlayerDataService.update(p, function(data)
			data.wins = (data.wins or 0) + 1
			return data
		end)
	end

	Remotes.RoundWon:FireAllClients(winners, reward)
end

function RewardsService.init()
	if initialized then return end
	initialized = true

	GameLoopService.RoundEnded:Connect(onRoundEnded)
end

return RewardsService
