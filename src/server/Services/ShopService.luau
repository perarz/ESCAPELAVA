--!strict
-- ShopService.luau
-- Server-authoritative kupowanie. Klient FireServer(BuyItem, itemId) — server waliduje wszystko.
-- Klient nigdy nie modyfikuje kasy/inwentarza, tylko intent.
--
-- Walidacje (każda failure → ShopResult z reason):
--   1. Gracz nie alive w ROUND (sklep tylko w lobby/spectator)
--   2. ItemDefinitions[itemId] istnieje
--   3. Inventory ma miejsce (give może odmówić)
--   4. CashService.spend pomyślny (atomic)
--
-- Rate limit usunięty — spam zakupów nie jest realnym exploitem (CashService.spend
-- jest atomic per gracz, inventory.give też). Gracz może klikać ile chce.
--
-- ShopResult firowany do klienta z reason — UI pokazuje feedback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashService = require(script.Parent.CashService)
local ItemService = require(script.Parent.ItemService)
local PlayerService = require(script.Parent.PlayerService)

local ShopService = {}

local function log(player: Player, itemId: string, ok: boolean, reason: string?)
	print(("[Shop] %s buy %s → %s%s"):format(
		player.Name, itemId,
		ok and "OK" or "FAIL",
		reason and (" ("..reason..")") or ""
	))
end

local function buy(player: Player, itemId: any): (boolean, string?)
	-- Typecheck z klienta — nie ufamy
	if type(itemId) ~= "string" then
		return false, "invalid_payload"
	end

	-- Gracz alive w ROUND nie może shopować
	if PlayerService.isAlive(player) then
		return false, "alive_in_round"
	end

	local def = ItemDefinitions.get(itemId)
	if not def then
		return false, "unknown_item"
	end

	-- Sprawdź czy gracz ma kasę (server-side, klient nigdy nie decyduje)
	local current = CashService.get(player)
	if current < def.price then
		return false, "not_enough_cash"
	end

	-- Najpierw sprawdź czy inventory ma miejsce — give zwraca false bez modyfikacji
	-- jeśli pełne. Ale "sprawdź" i "give" są osobno = race window. Robimy CashService.spend
	-- ZANIM give? Nie, bo wtedy gracz traci kasę i nie dostaje itemu jeśli inventory full.
	-- Bezpieczna kolejność: give FIRST (atomic — albo cały item wszedł, albo nic), POTEM spend.
	-- Jeśli spend zwróci false (race condition gdzie ktoś inny wydał kasę graczowi?
	-- niemożliwe bo CashService.spend jest server-only single thread per player), undo give.
	local giveOk, giveReason = ItemService.give(player, itemId, 1)
	if not giveOk then
		return false, giveReason or "inventory_full"
	end

	local spendOk = CashService.spend(player, def.price, "buy_" .. itemId)
	if not spendOk then
		-- Teoretycznie nie powinno się zdarzyć (sprawdziliśmy current >= price wyżej).
		-- Jeśli się zdarzy, undo give żeby gracz nie dostał free itemu.
		-- (Poprzednia wersja skanowała inventory starym schematem slotowym i crashowała
		-- na "attempt to index number" — nowy schemat to { [itemId] = count }.)
		warn("[Shop] CRITICAL: spend failed after give succeeded — undoing give")
		ItemService.consume(player, itemId, 1)
		return false, "internal_error"
	end

	return true, nil
end

local function onBuyItem(player: Player, itemId: any)
	local ok, reason = buy(player, itemId)
	log(player, tostring(itemId), ok, reason)
	Remotes.ShopResult:FireClient(player, ok, tostring(itemId), reason)
end

local initialized = false
function ShopService.init()
	if initialized then return end
	initialized = true

	Remotes.BuyItem.OnServerEvent:Connect(onBuyItem)
end

return ShopService
