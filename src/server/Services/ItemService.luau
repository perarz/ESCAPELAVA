--!strict
-- ItemService.luau
-- Inventory per gracz. Persystencja przez PlayerDataService.
--
-- Inventory schema: data.inventory = { [itemId] = count }
-- Każdy item type ma jeden "slot" z total count. Unlimited stack per type.
-- Hotbar UI mapuje pierwsze N item types na 5 fizycznych slotów po kolei.
--
-- Użycie itemów NIE idzie przez ItemService — każdy item ma własny remote + service
-- (bomba: ThrowBomb→BombService, most: BuildBridge→BridgeService). Stary generic
-- dispatcher UseItem został wycięty jako dead code (nic go nie wołało).
--
-- API:
--   ItemService.getInventory(player) -> { [itemId] = count }
--   ItemService.getCount(player, itemId) -> number
--   ItemService.give(player, itemId, count) -> ok: boolean, reason: string?
--   ItemService.consume(player, itemId, count) -> ok: boolean

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Dev = require(ReplicatedStorage.Shared.Modules.Dev)
local PlayerDataService = require(script.Parent.PlayerDataService)

local ItemService = {}

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

-- TRYB DEV: syntetyczne inventory — wszystkie itemy ze sklepu po InfiniteItemCount.
-- Wstrzykiwane w JEDNYM miejscu (snapshot), więc getCount / getInventory / replikacja
-- do hotbara widzą to samo automatycznie. NIC nie jest zapisywane: prawdziwe
-- `data.inventory` deva zostaje nietknięte i wraca po wyłączeniu Config.Dev.Enabled.
local function devInventory()
	local inv = {}
	for _, itemId in ipairs(ItemDefinitions.shopOrder) do
		inv[itemId] = Config.Dev.InfiniteItemCount
	end
	return inv
end

local function snapshot(player: Player)
	if Dev.hasInfiniteItems(player) then
		return devInventory()
	end
	local data = PlayerDataService.get(player)
	if not data then return {} end
	migrateInventory(data)
	return data.inventory or {}
end

local function replicate(player: Player)
	Remotes.InventoryChanged:FireClient(player, snapshot(player))
end

-- Stan startowy po `ClientReady`. Przed wczytaniem danych nie wysyła nic (pusty pasek
-- nadpisałby się zaraz i tak, ale mignąłby graczowi) — wyśle subskrypcja „loaded”.
function ItemService.replicateTo(player: Player)
	if Dev.hasInfiniteItems(player) or PlayerDataService.get(player) then
		replicate(player)
	end
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
	-- Wynik update MUSI być propagowany. Gdy dane gracza nie są jeszcze załadowane
	-- (cache pusty — join w trakcie retry DataStore), update nic nie zapisuje. Wcześniej
	-- give i tak zwracało true, więc caller (sklep, nagroda, dev product) był przekonany
	-- że gracz dostał item, a log drukował total=0.
	local ok = PlayerDataService.update(player, function(data)
		migrateInventory(data)
		local current = data.inventory[itemId] or 0
		local newAmount = math.min(current + count, def.maxStack)
		data.inventory[itemId] = newAmount
		newTotal = newAmount
		return data
	end)
	if not ok then
		warn(("[Item] give FAIL %s %s x%d — dane gracza niezaładowane"):format(player.Name, itemId, count))
		return false, "data_not_loaded"
	end

	log(player, "give", itemId, count, newTotal)
	replicate(player)
	return true, nil
end

-- Usuwa N sztuk konkretnego itemu.
function ItemService.consume(player: Player, itemId: string, count: number): boolean
	assert(count > 0)

	-- Dev: zużycie jest no-opem, ale MUSI zwrócić true — cała reszta (BombService.throw,
	-- BridgeService.build) traktuje `false` jako "abort, nie rzucaj". Bez replikacji:
	-- syntetyczne inventory się nie zmieniło, więc hotbar nie ma czego odświeżać.
	if Dev.hasInfiniteItems(player) then
		local def = ItemDefinitions.get(itemId)
		return def ~= nil
	end

	local ok = false
	local newTotal = 0
	-- Brak danych w cache = brak mutacji; bez tego guardu consume zwracało false z powodu
	-- `ok`, ale bez rozróżnienia "nie miał itemu" od "dane się nie załadowały".
	local updated = PlayerDataService.update(player, function(data)
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
	if not updated then
		warn(("[Item] consume FAIL %s %s x%d — dane gracza niezaładowane"):format(player.Name, itemId, count))
		return false
	end
	if ok then
		log(player, "consume", itemId, count, newTotal)
		replicate(player)
	end
	return ok
end

local initialized = false
function ItemService.init()
	if initialized then return end
	initialized = true

	-- Replicate gdy data się ładuje
	PlayerDataService.subscribe(function(eventKey, player, _oldData, _newData)
		if eventKey == "loaded" or eventKey == "loaded_default" then
			-- Od razu; spóźniony klient dostanie inventory z `replicateTo` (paczka 3).
			replicate(player)
		end
	end)
end

return ItemService
