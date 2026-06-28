--!strict
-- CashService.luau
-- Server-authoritative kasa per gracz. Persystencja przez PlayerDataService (DataStore).
-- Każda transakcja logowana z timestamp + powodem (Hard rule #6).
--
-- API:
--   CashService.get(player) -> number
--   CashService.add(player, amount, reason) -> number (nowy balance)
--   CashService.spend(player, amount, reason) -> boolean (true gdy udało się)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local CashService = {}

local function log(player: Player, delta: number, reason: string, newBalance: number)
	print(("[Cash] %s %+d (%s) → %d  t=%.1f"):format(player.Name, delta, reason, newBalance, os.clock()))
end

local function replicate(player: Player, delta: number?, reason: string?)
	local data = PlayerDataService.get(player)
	if not data then return end
	Remotes.CashChanged:FireClient(player, data.cash or 0, delta, reason)
end

function CashService.get(player: Player): number
	local data = PlayerDataService.get(player)
	if not data then return 0 end
	return data.cash or 0
end

function CashService.add(player: Player, amount: number, reason: string): number
	assert(amount >= 0, "CashService.add: amount musi być >= 0; użyj spend() do odjęcia")
	local newBalance = 0
	local ok = PlayerDataService.update(player, function(data)
		data.cash = (data.cash or 0) + amount
		newBalance = data.cash
		return data
	end)
	if not ok then
		warn(("[Cash] add FAIL %s — brak danych w cache (player jeszcze nieload?)"):format(player.Name))
		return 0
	end
	log(player, amount, reason, newBalance)
	replicate(player, amount, reason)
	return newBalance
end

function CashService.spend(player: Player, amount: number, reason: string): boolean
	assert(amount >= 0, "CashService.spend: amount musi być >= 0")
	local success = false
	local newBalance = 0
	PlayerDataService.update(player, function(data)
		local current = data.cash or 0
		if current < amount then
			return data -- niezmieniony
		end
		data.cash = current - amount
		newBalance = data.cash
		success = true
		return data
	end)
	if success then
		log(player, -amount, reason, newBalance)
		replicate(player, -amount, reason)
	end
	return success
end

local STARTER_PACK = 100        -- jednorazowy bonus dla nowych graczy (production)
local STUDIO_BONUS = 1000       -- DODATKOWE cash TYLKO w Studio (na testy, nie wpływa na produkcję)

local initialized = false
function CashService.init()
	if initialized then return end
	initialized = true

	-- Replicate gdy gracz dostanie loaded data (z DataStore lub default)
	PlayerDataService.subscribe(function(eventKey, player, _oldData, newData)
		if eventKey == "loaded" or eventKey == "loaded_default" then
			-- Starter pack tylko gdy gracz NIGDY nie miał kasy.
			if newData and not newData._starterReceived and (newData.cash or 0) == 0 then
				PlayerDataService.update(player, function(data)
					data.cash = (data.cash or 0) + STARTER_PACK
					data._starterReceived = true
					return data
				end)
				log(player, STARTER_PACK, "starter_pack", STARTER_PACK)
			end
			-- Studio bonus za każde uruchomienie Play — żeby Kacper miał czym testować.
			-- Production server (RunService:IsStudio() == false) nie wzbudza tego.
			if RunService:IsStudio() then
				CashService.add(player, STUDIO_BONUS, "studio_test_bonus")
			end
			task.delay(1, function()
				if player.Parent then
					replicate(player, nil, "init")
				end
			end)
		end
	end)
end

return CashService
