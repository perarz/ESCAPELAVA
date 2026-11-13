--!strict
-- LeaderstatsService.luau
-- Roblox Tab-leaderboard (leaderstats folder per gracz): Cash + Wins + Rebirths (09.11,
-- decyzja Kacpra: kolumna w tabeli zamiast znaczka przy nicku).
-- Read-only mirror danych z PlayerDataService — jedyny writer to subscriber niżej.
-- Tworzone dopiero na "loaded"/"loaded_default" żeby nie pokazywać 0 i nie skakać
-- po dociągnięciu DataStore (ten sam pattern co ItemService replicate).

local PlayerDataService = require(script.Parent.PlayerDataService)

local LeaderstatsService = {}
local initialized = false

local function getOrCreateStats(player: Player): (IntValue, IntValue, IntValue)
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

	-- Trzecia w kolejności tworzenia: tabela sortuje po pierwszej kolumnie (Cash), jak dotąd.
	local rebirths = folder:FindFirstChild("Rebirths")
	if not rebirths then
		rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Parent = folder
	end

	return cash :: IntValue, wins :: IntValue, rebirths :: IntValue
end

local function sync(player: Player, data: any)
	if type(data) ~= "table" then return end
	if not player.Parent then return end -- left server między eventem a task.spawn
	local cash, wins, rebirths = getOrCreateStats(player)
	cash.Value = data.cash or 0
	wins.Value = data.wins or 0
	-- Lustro zapisu, jak pozostałe kolumny (właściciel: SkillService).
	local skills = data.skills
	local count = if type(skills) == "table" then skills.rebirths else nil
	rebirths.Value = if type(count) == "number" and count >= 0 and count < math.huge then math.floor(count) else 0
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
