--!strict
-- ShopService.luau
-- Server-authoritative kupowanie (sklep-NPC). Klient FireServer(BuyItem, itemId) — server
-- waliduje WSZYSTKO. Klient nigdy nie modyfikuje kasy/inwentarza, tylko wysyła intent.
--
-- Sklep to NPC w lobby (stragan Config.Shop.ShopModelName → Config.Shop.NpcName, szukany
-- rekurencyjnie pod Workspace.Lobby). Kamera/UI są czysto klienckie
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
-- Rate limit tylko na SPAM remote'a, nie na klikanie: spam zakupów nie jest exploitem
-- ekonomii (CashService.spend i ItemService.give są atomic per gracz), więc gracz dalej
-- klika KUP ile chce — `RateLimits.BuyItemPerSecond` jest ponad ludzkie tempo. Przegląd
-- 29.09 (A-10): bez sufitu pętla exploitera zamieniała każdą prośbę w linię logu i odesłany
-- ShopResult. Ponad limit prośba przepada PO CICHU — odpowiedź byłaby tym samym spamem.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CashService = require(script.Parent.CashService)
local ItemService = require(script.Parent.ItemService)
local LoadoutService = require(script.Parent.LoadoutService)

local ShopService = {}

local function log(player: Player, itemId: string, ok: boolean, reason: string?)
	print(("[Shop] %s buy %s → %s%s"):format(
		player.Name, itemId,
		ok and "OK" or "FAIL",
		reason and (" (" .. reason .. ")") or ""
	))
end

-- ── NPC sprzedawcy ──────────────────────────────────────────────────────────
-- Szukany REKURENCYJNIE: Workspace.Lobby → stragan → NPC. Stragan siedzi kilka poziomów
-- w głąb dekoracji lobby (Lobby.Lobby.Lobby.Decorations.Shops.WeaponsShop) i wędruje
-- w drzewie przy każdej przebudowie lobby — sztywna ścieżka psułaby się za każdym razem,
-- a objaw (każdy zakup odrzucony jako "too_far") nie wskazywałby przyczyny.
local npcCache: Model? = nil

local function findNpc(): Model?
	if npcCache and npcCache.Parent then
		return npcCache
	end
	npcCache = nil
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	-- ZAWSZE przez stragan, NIGDY po samej nazwie NPC. W lobby stoją DWA modele o nazwie
	-- "NPC" (ClothesShop i WeaponsShop), a FindFirstChild po samej nazwie zwraca tego od
	-- ubrań — 115 studów od właściwego. Fallback "gdyby drzewo się spłaszczyło" byłby więc
	-- nie ratunkiem, tylko cichym błędem: sklep mierzyłby dystans do złego sprzedawcy.
	-- Brak straganu = fail closed (warn w nearShop/init), nie zgadywanie.
	local stall = lobby:FindFirstChild(Config.Shop.ShopModelName, true)
	local npc = stall and stall:FindFirstChild(Config.Shop.NpcName, true)
	if npc and npc:IsA("Model") then
		npcCache = npc
		return npc
	end
	return nil
end

-- HumanoidRootPart PRZED PrimaryPart: w tym NPC PrimaryPart to Head, a mierzenie dystansu
-- od głowy zabiera ~1.5 studa z budżetu InteractDistance bez żadnego powodu.
local function npcAnchor(npc: Model): BasePart?
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	if npc.PrimaryPart then
		return npc.PrimaryPart
	end
	return npc:FindFirstChildWhichIsA("BasePart")
end

-- Prompt tworzymy MY, jeśli NPC go nie ma. To element FUNKCJONALNY, nie wygląd — bez niego
-- sklepu nie da się otworzyć w ogóle, a brak jednego obiektu w Studio wyłączał całą
-- mechanikę po cichu. Kacper może postawić własny o nazwie Config.Shop.PromptName
-- (dowolnie ostylowany) i kod go wtedy nie tknie.
local function ensurePrompt(npc: Model)
	local existing = npc:FindFirstChild(Config.Shop.PromptName, true)
	if existing and existing:IsA("ProximityPrompt") then
		return
	end
	local anchor = npcAnchor(npc)
	if not anchor then
		warn(("[Shop] %s nie ma żadnego BasePart — nie mam gdzie powiesić promptu"):format(npc.Name))
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Config.Shop.PromptName
	prompt.ActionText = Config.Shop.PromptActionText
	prompt.ObjectText = Config.Shop.PromptObjectText
	prompt.KeyboardKeyCode = Config.Shop.PromptKeyCode
	prompt.MaxActivationDistance = Config.Shop.PromptMaxDistance
	-- NPC stoi za ladą, między dekoracjami straganu — z wymaganą linią wzroku prompt
	-- znikałby losowo, zależnie od tego, pod jakim kątem gracz podejdzie.
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	print(("[Shop] utworzono %s na %s"):format(Config.Shop.PromptName, anchor:GetFullName()))
end

-- Markery kamer to czyste znaczniki pozycji, ale w Studio powstają jako zwykłe party:
-- widoczne, kolidujące i NIEZAKOTWICZONE — czyli przy starcie Play spadają i zabierają ze
-- sobą kadr. Wymuszamy kontrakt w kodzie, tak samo jak LavaService robi warstwom lawy:
-- dostawienie kolejnego markera to jedno przeciągnięcie parta, bez pamiętania o czterech
-- checkboxach. `Locked` celowo NIE ruszamy — zablokowałoby Kacprowi klikanie markera
-- w Studio, a w tej scenie nie ma destrukcji, przed którą trzeba by go chronić.
local function prepareCameraMarkers()
	local scene = Workspace:FindFirstChild(Config.Shop.SceneName)
	if not scene then
		warn(("[Shop] brak Workspace.%s — kamera sklepu nie ma dokąd jechać"):format(
			Config.Shop.SceneName))
		return
	end
	local cams = scene:FindFirstChild(Config.Shop.CamerasFolder)
	if not cams then
		return
	end
	for _, part in ipairs(cams:GetChildren()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Transparency = 1
		end
	end
end

-- Gate proximity: gracz musi realnie stać przy NPC-sprzedawcy. Fail closed — brak NPC =
-- błąd mapy, nie przepuszczamy zakupu (warn, żeby było widać przyczynę na teście).
local function nearShop(player: Player): boolean
	local npc = findNpc()
	if not npc then
		warn(("[Shop] nie znalazłem %s/%s pod Workspace.Lobby — zakup odrzucony"):format(
			Config.Shop.ShopModelName, Config.Shop.NpcName))
		return false
	end
	local anchor = npcAnchor(npc)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (anchor and hrp and hrp:IsA("BasePart")) then
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

	-- Wolny slot w loadoucie → item wskakuje sam. Pełny → leży w ekwipunku; klient pokaże
	-- „ADD IT IN INVENTORY” (zna loadout), serwer niczego za gracza nie podmienia.
	LoadoutService.addIfFree(player, itemId)
	return true, nil
end

-- Okno jednosekundowe per gracz (patrz nagłówek). Tabela okna jest używana ponownie —
-- zero alokacji na zakup.
local buyWindow: { [Player]: { start: number, count: number } } = {}

local function allowBuy(player: Player): boolean
	local now = os.clock()
	local w = buyWindow[player]
	if not w then
		buyWindow[player] = { start = now, count = 1 }
		return true
	end
	if now - w.start >= 1 then
		w.start, w.count = now, 1
		return true
	end
	w.count += 1
	return w.count <= Config.RateLimits.BuyItemPerSecond
end

local function onBuyItem(player: Player, itemId: any)
	if not allowBuy(player) then return end
	local ok, reason = buy(player, itemId)
	log(player, tostring(itemId), ok, reason)
	Remotes.ShopResult:FireClient(player, ok, tostring(itemId), reason)
end

local initialized = false
function ShopService.init()
	if initialized then return end
	initialized = true

	Remotes.BuyItem.OnServerEvent:Connect(onBuyItem)
	Players.PlayerRemoving:Connect(function(player: Player)
		buyWindow[player] = nil
	end)

	local npc = findNpc()
	if npc then
		ensurePrompt(npc)
	else
		warn(("[Shop] nie znalazłem NPC (%s → %s) pod Workspace.Lobby — sklepu nie da się otworzyć"):format(
			Config.Shop.ShopModelName, Config.Shop.NpcName))
	end
	prepareCameraMarkers()
end

return ShopService
