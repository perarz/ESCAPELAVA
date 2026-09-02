--!strict
-- LeaderstatsService.luau
-- Roblox Tab-leaderboard (leaderstats folder per gracz): Cash + Wins.
-- Read-only mirror danych z PlayerDataService — jedyny writer to subscriber niżej.
-- Tworzone dopiero na "loaded"/"loaded_default" żeby nie pokazywać 0 i nie skakać
-- po dociągnięciu DataStore (ten sam pattern co ItemService replicate).

local PlayerDataService = require(script.Parent.PlayerDataService)

local LeaderstatsService = {}
local initialized = false

local function getOrCreateStats(player: Player): (IntValue, IntValue)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	local cash = folder:FindFirstChild("Cash")
	if not cash then
		cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Parent = folder
	end

	local wins = folder:FindFirstChild("Wins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "Wins"
		wins.Parent = folder
	end

	return cash :: IntValue, wins :: IntValue
end

local function sync(player: Player, data: any)
	if type(data) ~= "table" then return end
	if not player.Parent then return end -- left server między eventem a task.spawn
	local cash, wins = getOrCreateStats(player)
	cash.Value = data.cash or 0
	wins.Value = data.wins or 0
end

function LeaderstatsService.init()
	if initialized then return end
	initialized = true

	PlayerDataService.subscribe(function(eventKey, player, _oldData, newData)
		if eventKey == "loaded" or eventKey == "loaded_default" or eventKey == "updated" then
			sync(player, newData)
		end
	end)
end

return LeaderstatsService
