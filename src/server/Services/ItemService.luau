--!strict
-- ItemService.luau
-- Inventory per gracz (5 slotów). Persystencja przez PlayerDataService.
--
-- Slot schema: data.inventory[slotIndex] = { itemId = "bomb", count = 2 } or nil
-- Slot indexes: 1..MAX_SLOTS
--
-- API:
--   ItemService.getInventory(player) -> { [slot] = { itemId, count } }
--   ItemService.give(player, itemId, count) -> ok: boolean, reason: string?
--   ItemService.consume(player, slot, count) -> ok: boolean (do użycia w ItemService.use lub bombService)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local ItemService = {}

local USE_RATE_LIMIT = 0.2 -- sek minimum między UseItem (anti-spam, niezależne od per-item cooldown)
local lastUseAt: { [Player]: number } = {}
local lastUseByItem: { [Player]: { [string]: number } } = {} -- per gracz, per itemId

-- Inventory schema: data.inventory = { [itemId] = count }
-- Każdy item type ma jeden "slot" z total count. Unlimited stack per type.
-- Hotbar UI mapuje pierwsze N item types na 5 fizycznych slotów po kolei.

local useHandlers: { [string]: (Player, string, Vector3) -> (boolean, string?) } = {}

function ItemService.registerUseHandler(itemId: string, handler: (Player, string, Vector3) -> (boolean, string?))
	useHandlers[itemId] = handler
end

local function log(player: Player, action: string, itemId: string, count: number, total: number)
	print(("[Item] %s %s %s x%d → total=%d"):format(player.Name, action, itemId, count, total))
end

-- Migration: stary format `{ [slot] = { itemId, count } }` → nowy `{ [itemId] = count }`.
-- Wykonuje się przy pierwszym dostępie inventory każdego playera (jeśli wymagane).
local function migrateInventory(data: any)
	if not data.inventory then
		data.inventory = {}
		return
	end
	-- Sprawdź czy stary format (klucze są liczbowe i wartości to tabele z itemId/count)
	local needsMigration = false
	for k, v in pairs(data.inventory) do
		if type(k) == "number" and type(v) == "table" and v.itemId then
			needsMigration = true
			break
		end
	end
	if not needsMigration then return end

	local newInv = {}
	for _, entry in pairs(data.inventory) do
		if type(entry) == "table" and entry.itemId then
			newInv[entry.itemId] = (newInv[entry.itemId] or 0) + (entry.count or 0)
		end
	end
	data.inventory = newInv
end

local function snapshot(player: Player)
	local data = PlayerDataService.get(player)
	if not data then return {} end
	migrateInventory(data)
	return data.inventory or {}
end

local function replicate(player: Player)
	Remotes.InventoryChanged:FireClient(player, snapshot(player))
end

function ItemService.getInventory(player: Player)
	return snapshot(player)
end

function ItemService.getCount(player: Player, itemId: string): number
	local inv = snapshot(player)
	return inv[itemId] or 0
end

-- Dodaje N sztuk itemu. Unlimited stack (cap = ItemDefinitions[itemId].maxStack jako sanity).
function ItemService.give(player: Player, itemId: string, count: number): (boolean, string?)
	assert(count > 0, "ItemService.give: count > 0")
	local def = ItemDefinitions.get(itemId)
	if not def then return false, "unknown_item" end

	local newTotal = 0
	PlayerDataService.update(player, function(data)
		migrateInventory(data)
		local current = data.inventory[itemId] or 0
		local newAmount = math.min(current + count, def.maxStack)
		data.inventory[itemId] = newAmount
		newTotal = newAmount
		return data
	end)

	log(player, "give", itemId, count, newTotal)
	replicate(player)
	return true, nil
end

-- Usuwa N sztuk konkretnego itemu.
function ItemService.consume(player: Player, itemId: string, count: number): boolean
	assert(count > 0)
	local ok = false
	local newTotal = 0
	PlayerDataService.update(player, function(data)
		migrateInventory(data)
		local current = data.inventory[itemId] or 0
		if current < count then
			return data
		end
		local newAmount = current - count
		if newAmount <= 0 then
			data.inventory[itemId] = nil
		else
			data.inventory[itemId] = newAmount
		end
		newTotal = newAmount
		ok = true
		return data
	end)
	if ok then
		log(player, "consume", itemId, count, newTotal)
		replicate(player)
	end
	return ok
end

-- Dispatcher: użycie itemu po itemId. Klient fires UseItem(itemId, direction) → tu trafia.
function ItemService.use(player: Player, itemId: any, direction: any): (boolean, string?)
	local now = os.clock()
	local last = lastUseAt[player] or 0
	if now - last < USE_RATE_LIMIT then
		return false, "rate_limited"
	end
	lastUseAt[player] = now

	if type(itemId) ~= "string" then
		return false, "invalid_payload"
	end
	if typeof(direction) ~= "Vector3" then
		return false, "invalid_direction"
	end
	if direction.Magnitude < 0.01 or direction.Magnitude > 1000 then
		return false, "invalid_direction"
	end

	local def = ItemDefinitions.get(itemId)
	if not def then return false, "unknown_item" end

	if ItemService.getCount(player, itemId) <= 0 then
		return false, "no_items"
	end

	lastUseByItem[player] = lastUseByItem[player] or {}
	local lastForItem = lastUseByItem[player][itemId] or 0
	if def.cooldown and now - lastForItem < def.cooldown then
		return false, "cooldown"
	end

	local handler = useHandlers[itemId]
	if not handler then return false, "no_handler" end

	if not ItemService.consume(player, itemId, 1) then
		return false, "consume_failed"
	end

	local ok, reason = handler(player, itemId, direction.Unit)
	if ok then
		lastUseByItem[player][itemId] = now
	end
	return ok, reason
end

local function onUseItem(player: Player, itemId: any, direction: any)
	local ok, reason = ItemService.use(player, itemId, direction)
	Remotes.UseItemResult:FireClient(player, ok, tostring(itemId), reason)
	if not ok then
		print(("[Item] use FAIL %s item=%s reason=%s"):format(player.Name, tostring(itemId), tostring(reason)))
	end
end

local function onPlayerRemoving(player: Player)
	lastUseAt[player] = nil
	lastUseByItem[player] = nil
end

local initialized = false
function ItemService.init()
	if initialized then return end
	initialized = true

	-- Replicate gdy data się ładuje
	PlayerDataService.subscribe(function(eventKey, player, _oldData, _newData)
		if eventKey == "loaded" or eventKey == "loaded_default" then
			task.delay(1, function()
				if player.Parent then
					replicate(player)
				end
			end)
		end
	end)

	Remotes.UseItem.OnServerEvent:Connect(onUseItem)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return ItemService
