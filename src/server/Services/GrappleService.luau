--!strict
-- GrappleService.luau
-- Hak (item `grapple`) — celujesz, trafiasz, LECISZ PO ŁUKU DO TEGO PUNKTU i kończysz
-- lot trochę nad nim. Lot prowadzi klient (network ownership), serwer decyduje, DOKĄD.
--
-- Flow:
--   1. Klient klika slot hotbara z hakiem → EquipItem("grapple") → Tool w ręce (model
--      ReplicatedStorage.HandHook)
--   2. Tool.Activated → GrappleController wysyła FireGrapple(punkt, w który celuje mysz)
--   3. Serwer waliduje NIEZALEŻNIE (alive, ROUND, cooldown, count, zasięg, własny raycast)
--   4. consume 1 sztuka → punkt docelowy + czas lotu → Remotes.Grappled do właściciela
--   5. Remotes.GrappleFX do wszystkich — lina rysowana lokalnie przez cały lot
--
-- Dlaczego łuk PROWADZONY, a nie rzut ani lina po prostej — historia przy Config.Grapple.
--
-- ⚠️ CZTERY RZECZY, BEZ KTÓRYCH TO NIE DZIAŁA:
--
-- (a) LOT PROWADZI KLIENT. Postać ma network ownership gracza, więc serwerowa siła czy
--     prędkość na HRP byłaby natychmiast nadpisana (hard rule 12). Serwer wysyła wyłącznie
--     PUNKT i CZAS — ten sam podział co przy Remotes.Pushed.
--
-- (b) `AntiCheatService.grantGrace` PRZED lotem, ale NA CZAS LOTU, nie domyślne 4 s.
--     Anti-cheat mierzy realnie przebytą drogę, a lot to kilkadziesiąt studów w ułamku
--     sekundy — bez okna hak zabiłby gracza jako „cheatera". Krótkie okno, bo każda
--     sekunda bezkarności ponad lot to darmowy speedhack dla kogoś, kto hak ma.
--
-- (c) `FallDamageService.suppressMidairRagdoll` na czas lotu. Zjazd hakiem w dół wygląda
--     dla fall damage jak swobodny spadek i gracz byłby wywracany w połowie liny. Wyłączamy
--     WYŁĄCZNIE wywrotkę w locie — obrażenia za upadek liczą się dalej od punktu startu
--     (decyzja Kacpra 2026-09-23: zjazd w dół boli jak skok z tej wysokości).
--
-- (d) CLEANUP NA `RoundEnded`, nie tylko na `CharacterRemoving`. Ocalali nie dostają nowej
--     postaci po rundzie — są wyłącznie teleportowani do lobby — więc bez tego listenera
--     zostawaliby z hakiem w ręce i klikali w pustkę (lekcja z BombService, 2026-09-21).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Destructible = require(ReplicatedStorage.Shared.Modules.Destructible)
local GrappleArc = require(ReplicatedStorage.Shared.Modules.GrappleArc)
local ItemService = require(script.Parent.ItemService)
local LoadoutService = require(script.Parent.LoadoutService)
local PlayerService = require(script.Parent.PlayerService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local GameLoopService = require(script.Parent.GameLoopService)
local FallDamageService = require(script.Parent.FallDamageService)
local RagdollService = require(script.Parent.RagdollService)

local GrappleService = {}

local ITEM_ID = "grapple"
local CFG = Config.Grapple

local equippedTools: { [Player]: Tool } = {}
local lastFireAt: { [Player]: number } = {}
local lastEquipAt: { [Player]: number } = {}

local function log(player: Player, action: string, extra: string?)
	print(("[Grapple] %s %s%s"):format(player.Name, action, extra and (" " .. extra) or ""))
end

-- ── Przedmiot w ręce ─────────────────────────────────────────────────────────────────
-- Wzorzec 1:1 z BridgeService: model spłaszczony do Toola i zweldowany do największej
-- bryły. W przeciwieństwie do bomby hak NICZEGO nie wystrzeliwuje fizycznie, więc Handle
-- jest wyłącznie uchwytem — nie musi być nośnikiem sensownej fizyki.
local function giveGrappleTool(player: Player)
	local existing = equippedTools[player]
	if existing then
		existing:Destroy()
		equippedTools[player] = nil
	end

	local def = ItemDefinitions.get(ITEM_ID)
	local template = if def and def.toolModel then Utils.getAsset(def.toolModel) else nil
	if not (template and template:IsA("Model")) then
		-- Brak modelu = brak przedmiotu w ręce, ale hak dalej DZIAŁA. Item mechaniczny
		-- nie może przestać działać przez brakujący asset.
		warn(("[Grapple] brak modelu %s w ReplicatedStorage — hak bez wyglądu w ręce")
			:format(tostring(def and def.toolModel)))
		return
	end

	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end

	local model = template:Clone()
	local primary = model.PrimaryPart or Utils.largestPart(model)
	if not primary then
		model:Destroy()
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = "GrappleTool"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("ItemId", ITEM_ID)

	primary.Name = "Handle"
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			-- Massless: 27 partów o realnej masie przechyla postać i psuje jej fizykę.
			d.Massless = true
			table.insert(parts, d)
		end
	end
	-- ⚠️ Weld PRZED przeniesieniem do Toola — inaczej jest jedna klatka luźnych części
	-- i model rozjeżdża się w dłoni. `weldModel` sam zdejmuje `Anchored` po spięciu
	-- całości, więc nie robimy tego drugi raz: wszystkie 27 partów HandHooka przychodzi
	-- z Workspace zakotwiczonych, a zakotwiczony Handle nie przyczepi się do ręki.
	Utils.weldModel(model, primary)
	for _, p in ipairs(parts) do
		p.Parent = tool
	end
	for _, leftover in ipairs(model:GetChildren()) do
		leftover.Parent = tool
	end
	model:Destroy()

	tool.Parent = char
	equippedTools[player] = tool
end

local function removeGrappleTool(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

function GrappleService.unequip(player: Player)
	removeGrappleTool(player)
end

-- Czy w TO wolno się zaczepić. Reguła: geometria mapy i mosty — czyli dokładnie to, co
-- system destrukcji uznaje za świat (`Destructible.isDestructible`). Gruz odpada, bo
-- znika i się rusza; lawa odpada sama, bo ma wymuszone `CanQuery = false`; lobby i scena
-- sklepu odpadają, bo nie leżą pod `Workspace.Map`.
local function isAnchorable(part: BasePart, ctx: Destructible.Context): boolean
	return Destructible.isDestructible(part, ctx)
end

local function buildRaycastParams(char: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local ignore: { Instance } = { char }
	-- Postacie innych graczy — hak zaczepia się o świat, nie o ludzi.
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character and other.Character ~= char then
			table.insert(ignore, other.Character)
		end
	end
	local debris = Workspace:FindFirstChild("BlastDebris")
	if debris then table.insert(ignore, debris) end
	local cash = Workspace:FindFirstChild("ActiveCash")
	if cash then table.insert(ignore, cash) end

	params.FilterDescendantsInstances = ignore
	return params
end

local function handleFireGrapple(player: Player, targetPos: any)
	-- 1. Typecheck — klient kłamie (hard rule: server validate WSZYSTKO).
	if typeof(targetPos) ~= "Vector3" then return end
	if targetPos ~= targetPos then return end -- NaN

	-- 2. Żywy gracz w rundzie.
	if not PlayerService.isAlive(player) then return end

	-- 2b. Nie w ragdollu (zgłoszenie Kacpra 26.09: „podczas ragdolla da się handhookiem lecieć
	--     i kolegę w kosmos wywaliło”). Lot ciągnie korzeń postaci LinearVelocity z siłą
	--     liczoną pod stojącą postać, a ciało wisi wtedy na przegubach toolboxa — solver
	--     wystrzeliwuje całość. Sprawdzane PRZED cooldownem i zużyciem: w ragdollu hak nic
	--     nie kosztuje. Klient blokuje to samo u siebie, ale nie ufamy mu (hard rule 2).
	if RagdollService.isRagdolled(player) then return end

	-- 3. Cooldown. Zużywa się na PRÓBIE, nie na sukcesie — inaczej spam kliknięć w niebo
	--    kosztuje serwer raycast przy każdym kliknięciu.
	local now = os.clock()
	if now - (lastFireAt[player] or 0) < Config.RateLimits.Grapple * Config.RateLimits.ServerTolerance then return end
	lastFireAt[player] = now

	-- 4. Ma czym strzelać.
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end

	local char = player.Character
	local hrp = Utils.getRoot(player)
	if not (char and hrp) then return end

	local origin = hrp.Position
	local delta = targetPos - origin
	local dist = delta.Magnitude
	if dist < 1 or dist > CFG.MaxRange then return end

	-- 5. WŁASNY raycast. Z punktu podanego przez klienta bierzemy WYŁĄCZNIE KIERUNEK —
	--    zaczep powstaje tam, gdzie trafi promień serwera. Klient nie może więc skłamać
	--    ani o zasięgu (MaxRange), ani o geometrii (isAnchorable), a steruje dokładnie
	--    tym, czym ma sterować. Skutek uboczny jest pożądany: gdy między graczem a celem
	--    stoi ściana, hak zaczepia się O TĘ ŚCIANĘ zamiast odmówić działania.
	local ctx = Destructible.buildContext()
	local params = buildRaycastParams(char)
	local result = Workspace:Raycast(origin, delta.Unit * CFG.MaxRange, params)
	if not result then return end
	if not isAnchorable(result.Instance, ctx) then return end

	-- 6. Zużycie PRZED wysłaniem lotu (atomic, race-safe — tak jak przy moście).
	if not ItemService.consume(player, ITEM_ID, 1) then return end

	-- 7. DOKĄD lecimy. Cel odsunięty od powierzchni wzdłuż normalnej (środek HRP nie może
	--    stanąć NA ścianie, więc bez tego lot zawsze kończyłby się pchaniem w mur) i lekko
	--    podniesiony — „trochę wyżej": trafisz tuż pod krawędzią dachu, dolecisz ponad nią.
	local goal = result.Position + result.Normal * CFG.Standoff + Vector3.new(0, CFG.Lift, 0)
	-- Czas lotu z TEGO SAMEGO łuku, po którym poleci klient (GrappleArc). Łuk jest dłuższy
	-- niż linia prosta — liczony z cięciwy dawałby za krótkie okno, więc anti-cheat
	-- zamknąłby je, zanim gracz doleci. Klient dostaje to jako twardy sufit, a anti-cheat
	-- i fall damage dokładnie to samo okno (plus zapas na ping).
	local arc = GrappleArc.plan(origin, goal)
	local maxTime = math.min(CFG.MaxFlightTime, arc.duration + CFG.TimeMargin)

	-- 8. Okna PRZED wysłaniem lotu — pierwsza klatka lotu musi je już zastać.
	AntiCheatService.grantGrace(player, maxTime + CFG.NetMargin)
	FallDamageService.suppressMidairRagdoll(player, maxTime + CFG.NetMargin)

	Remotes.Grappled:FireClient(player, result.Position, goal, maxTime)
	Remotes.GrappleFX:FireAllClients(player, result.Position, goal, maxTime)

	-- Item zużyty do zera → nie ma już czym strzelać, więc przedmiot znika z ręki.
	-- Dopóki coś zostało, Tool ZOSTAJE: „kliknij jeszcze raz, żeby znowu wziąć hak"
	-- byłoby dokładnie tym rodzajem podwójnego kliknięcia, który wkurza.
	if ItemService.getCount(player, ITEM_ID) <= 0 then
		removeGrappleTool(player)
	end

	log(player, "zaczep", ("dist=%.1f luk=%.2fs sufit=%.2fs zostalo=%d")
		:format(dist, arc.duration, maxTime, ItemService.getCount(player, ITEM_ID)))
end

-- ── Equip / unequip ──────────────────────────────────────────────────────────────────
local function onEquipItem(player: Player, itemId: any)
	if itemId ~= ITEM_ID then
		-- Gracz wyciąga INNY item — hak chowamy (jak BombService / BridgeService). Do 11.10 ten
		-- przypadek był pomijany i hak zostawał w ręce obok nowego itemu („mam 2 naraz”).
		-- Bez limitu: chowanie jest idempotentne, a limit mógłby je zgubić.
		removeGrappleTool(player)
		return
	end
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now

	if not PlayerService.isAlive(player) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	if not LoadoutService.canEquip(player, ITEM_ID) then return end -- tylko z loadoutu (18.10)

	giveGrappleTool(player)
end

local function onUnequipItem(player: Player)
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now
	removeGrappleTool(player)
end

local function onPlayerRemoving(player: Player)
	removeGrappleTool(player)
	lastFireAt[player] = nil
	lastEquipAt[player] = nil
end

local initialized = false
function GrappleService.init()
	if initialized then return end
	initialized = true

	Remotes.FireGrapple.OnServerEvent:Connect(handleFireGrapple)
	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.UnequipItem.OnServerEvent:Connect(onUnequipItem)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			removeGrappleTool(player)
		end)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- ⚠️ Ocalali NIE dostają nowej postaci po rundzie (są tylko teleportowani do lobby),
	-- więc `CharacterRemoving` na nich nie leci i bez tego zostawaliby z hakiem w ręce.
	GameLoopService.RoundEnded:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			removeGrappleTool(player)
		end
	end)
end

return GrappleService
