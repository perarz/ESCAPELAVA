--!strict
-- ShopService.luau
-- Server-authoritative kupowanie (sklep-NPC). Klient FireServer(BuyItem, itemId) — server
-- waliduje WSZYSTKO. Klient nigdy nie modyfikuje kasy/inwentarza, tylko wysyła intent.
--
-- Sklep to NPC w lobby (Workspace.Lobby.<Config.Shop.NpcName>). Kamera/UI są czysto klienckie
-- (ShopController) — server nie wie ani nie ufa, że sklep jest "otwarty". Jedyny gate,
-- który MA sens server-side, to ODLEGŁOŚĆ gracza od NPC (hard rule #3): legalny gracz stoi
-- przy sprzedawcy w lobby, cheater odpala BuyItem z dowolnego miejsca. W ROUND gracz jest
-- teleportowany do strefy rundy (daleko od NPC), więc distance blokuje zakup w trakcie gry.
--
-- Walidacje (każda failure → ShopResult z reason):
--   1. itemId to string i istnieje w ItemDefinitions
--   2. gracz jest przy NPC (Config.Shop.InteractDistance)
--   3. gracz ma kasę
--   4. atomowo: give → spend (z undo gdy spend padnie)
--
-- Rate limit celowo brak — spam zakupów nie jest exploitem (CashService.spend i
-- ItemService.give są atomic per gracz). Gracz może klikać KUP ile chce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashService = require(script.Parent.CashService)
local ItemService = require(script.Parent.ItemService)

local ShopService = {}

local function log(player: Player, itemId: string, ok: boolean, reason: string?)
	print(("[Shop] %s buy %s → %s%s"):format(
		player.Name, itemId,
		ok and "OK" or "FAIL",
		reason and (" (" .. reason .. ")") or ""
	))
end

-- Gate proximity: gracz musi realnie stać przy NPC-sprzedawcy. Fail closed — brak NPC =
-- błąd mapy, nie przepuszczamy zakupu (warn, żeby było widać przyczynę na teście).
local function nearShop(player: Player): boolean
	local lobby = Workspace:FindFirstChild("Lobby")
	local npc = lobby and lobby:FindFirstChild(Config.Shop.NpcName)
	if not npc then
		warn(("[Shop] brak Workspace.Lobby.%s — nie mogę zweryfikować odległości, zakup odrzucony"):format(
			Config.Shop.NpcName))
		return false
	end
	local anchor = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (anchor and anchor:IsA("BasePart") and hrp and hrp:IsA("BasePart")) then
		return false
	end
	return (anchor.Position - hrp.Position).Magnitude <= Config.Shop.InteractDistance
end

local function buy(player: Player, itemId: any): (boolean, string?)
	if type(itemId) ~= "string" then
		return false, "invalid_payload"
	end

	local def = ItemDefinitions.get(itemId)
	if not def then
		return false, "unknown_item"
	end

	if not nearShop(player) then
		return false, "too_far"
	end

	-- Kasa sprawdzona server-side (klient nigdy nie decyduje).
	local current = CashService.get(player)
	if current < def.price then
		return false, "not_enough_cash"
	end

	-- Bezpieczna kolejność: give FIRST (atomic — albo cały item wszedł, albo nic),
	-- POTEM spend. Gdyby spend padł (teoretycznie niemożliwe po sprawdzeniu current),
	-- cofamy give, żeby gracz nie dostał darmowego itemu.
	local giveOk, giveReason = ItemService.give(player, itemId, 1)
	if not giveOk then
		return false, giveReason or "inventory_full"
	end

	local spendOk = CashService.spend(player, def.price, "buy_" .. itemId)
	if not spendOk then
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
