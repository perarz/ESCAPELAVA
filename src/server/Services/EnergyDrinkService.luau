--!strict
-- EnergyDrinkService.luau (20.10) — energy drink: łyk w biegu, potem `Config.EnergyDrink.Duration`
-- sekund sprintu bez zużywania staminy.
--
-- Decyzje Kacpra 20.10: pijesz w biegu (krótki łyk, bieg się nie zatrzymuje), stamina się nie
-- kończy, a pasek staminy mieni się kolorami — „i tyle”. Napój NIE przyspiesza, więc anti-cheat
-- nie potrzebuje okna bezkarności (prędkość sprintu zostaje ta sama).
--
-- Flow:
--   1. EquipItem("energy_drink") → Tool `EnergyDrinkTool` w ręce (model ReplicatedStorage.EnergyDrink)
--   2. Tool.Activated → EnergyDrinkController zaczyna łyk u siebie i wysyła DrinkEnergy
--   3. Serwer waliduje NIEZALEŻNIE (żywy, nie ragdoll, cooldown, Tool w ręce, count) → consume
--   4. Okno działania w atrybutach gracza `EnergyStart` / `EnergyEnd` (czas serwera)
--   5. Klienci: gest łyku widzą wszyscy (EnergyDrinkController), efekt liczy MovementController
--      właściciela
--
-- DLACZEGO ATRYBUTY, A NIE REMOTE DO WŁAŚCICIELA: stamina żyje w całości u klienta, więc serwer
-- nie ma czego pilnować poza CZASEM. Atrybut na Playerze to jedno źródło prawdy „czy działa” dla
-- wszystkich klientów naraz (gest u innych graczy), dojeżdża też do kogoś, kto dołączył w trakcie
-- — RemoteEvent by przepadł (hard rule 9). Klient nie może go podrobić: atrybut ustawiony
-- lokalnie się nie replikuje.
--
-- ⚠️ CLEANUP NA `RoundEnded`, nie tylko na `CharacterRemoving` — ocalali nie dostają nowej
-- postaci po rundzie (lekcja z BombService / GrappleService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local ItemService = require(script.Parent.ItemService)
local LoadoutService = require(script.Parent.LoadoutService)
local PlayerService = require(script.Parent.PlayerService)
local GameLoopService = require(script.Parent.GameLoopService)
local RagdollService = require(script.Parent.RagdollService)

local EnergyDrinkService = {}

local ITEM_ID = "energy_drink"
local TOOL_NAME = "EnergyDrinkTool"
local CFG = Config.EnergyDrink

local equippedTools: { [Player]: Tool } = {}
local lastDrinkAt: { [Player]: number } = {}
local lastEquipAt: { [Player]: number } = {}

local function log(player: Player, action: string, extra: string?)
	print(("[EnergyDrink] %s %s%s"):format(player.Name, action, extra and (" " .. extra) or ""))
end

local function clearEffect(player: Player)
	player:SetAttribute(CFG.StartAttribute, nil)
	player:SetAttribute(CFG.EndAttribute, nil)
end

-- ── Przedmiot w ręce ─────────────────────────────────────────────────────────────────
-- `Utils.makeHeldTool`: model spłaszczony do Toola, zweldowany do największej bryły (korpus
-- puszki). Do tego obrót uchwytu z Configu — model stoi wieczkiem po osi +X, więc bez obrotu
-- puszka leżałaby w dłoni jak wałek.
local function canGrip(): CFrame
	local r = CFG.GripRotation
	return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

local function giveTool(player: Player)
	local existing = equippedTools[player]
	if existing then
		existing:Destroy()
		equippedTools[player] = nil
	end

	local def = ItemDefinitions.get(ITEM_ID)
	local template = if def and def.toolModel then Utils.getAsset(def.toolModel) else nil
	if not (template and template:IsA("Model")) then
		-- Bez modelu nie ma Toola, a bez Toola nie ma czego aktywować — napoju nie da się
		-- wypić. Głośno, bo to brak w placu, nie w kodzie.
		warn(("[EnergyDrink] brak modelu %s w ReplicatedStorage — napoju nie da się wyciągnąć")
			:format(tostring(def and def.toolModel)))
		return
	end

	local char = player.Character
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end

	local tool = Utils.makeHeldTool(template, TOOL_NAME, ITEM_ID, function()
		return canGrip()
	end)
	if not tool then
		return
	end

	tool.Parent = char
	equippedTools[player] = tool
end

local function removeTool(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

function EnergyDrinkService.unequip(player: Player)
	removeTool(player)
end

-- ── Łyk ──────────────────────────────────────────────────────────────────────────────
local function handleDrink(player: Player)
	-- 1. Żywy gracz w rundzie, nie w ragdollu (w locie bezwładnego ciała nie ma łyku; klient
	--    blokuje to samo u siebie, ale nie ufamy mu — hard rule 2).
	if not PlayerService.isAlive(player) then return end
	if RagdollService.isRagdolled(player) then return end

	-- 2. Cooldown zużywany na PRÓBIE — spam remote'a nie dojdzie do zapisu danych.
	local now = os.clock()
	if now - (lastDrinkAt[player] or 0) < Config.RateLimits.EnergyDrink * Config.RateLimits.ServerTolerance then return end
	lastDrinkAt[player] = now

	-- 3. Pije to, co TRZYMA. Tool daje tylko equip, a equip pilnuje loadoutu — bez tego
	--    oszust piłby napój spoza swoich 3 slotów.
	local tool = equippedTools[player]
	if not (tool and tool.Parent ~= nil and tool.Parent == player.Character) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end

	-- 4. Zużycie PRZED efektem (atomic, race-safe — jak hak i most).
	if not ItemService.consume(player, ITEM_ID, 1) then return end

	-- 5. Okno działania. Drugi napój w trakcie działania ODNAWIA czas do pełna (nie sumuje się)
	--    i nie robi przerwy na łyk: początek zostaje stary, przesuwa się tylko koniec.
	local t = Workspace:GetServerTimeNow()
	local oldStart = player:GetAttribute(CFG.StartAttribute)
	local oldEnd = player:GetAttribute(CFG.EndAttribute)
	local start = t + CFG.SipTime
	if type(oldStart) == "number" and type(oldEnd) == "number" and oldEnd > t then
		start = math.min(oldStart, start)
	end
	player:SetAttribute(CFG.StartAttribute, start)
	player:SetAttribute(CFG.EndAttribute, t + CFG.SipTime + CFG.Duration)

	-- Ostatnia puszka znika z ręki PO łyku, nie w jego trakcie — gest jej potrzebuje. Dopóki
	-- coś zostało, Tool zostaje (jak hak: „kliknij znowu, żeby wziąć” wkurza).
	local left = ItemService.getCount(player, ITEM_ID)
	if left <= 0 then
		task.delay(CFG.SipTime, function()
			if equippedTools[player] == tool then
				removeTool(player)
			end
		end)
	end

	log(player, "łyk", ("na %.0fs, zostało=%d"):format(CFG.Duration, left))
end

-- ── Equip / unequip ──────────────────────────────────────────────────────────────────
local function onEquipItem(player: Player, itemId: any)
	if itemId ~= ITEM_ID then
		-- Gracz wyciąga INNY item — puszkę chowamy (jak każdy serwis itemu, lekcja 11.10
		-- „mam 2 naraz”). Bez limitu: chowanie jest idempotentne.
		removeTool(player)
		return
	end
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now

	if not PlayerService.isAlive(player) then return end
	if ItemService.getCount(player, ITEM_ID) <= 0 then return end
	if not LoadoutService.canEquip(player, ITEM_ID) then return end -- tylko z loadoutu (18.10)

	giveTool(player)
end

local function onUnequipItem(player: Player)
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now
	removeTool(player)
end

local initialized = false
function EnergyDrinkService.init()
	if initialized then return end
	initialized = true

	Remotes.DrinkEnergy.OnServerEvent:Connect(handleDrink)
	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.UnequipItem.OnServerEvent:Connect(onUnequipItem)

	-- Śmierć kończy efekt: po respawnie w lobby gracz nie może mieć resztki napoju z rundy.
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			removeTool(player)
			clearEffect(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeTool(player)
		lastDrinkAt[player] = nil
		lastEquipAt[player] = nil
	end)

	-- Ocalali NIE dostają nowej postaci po rundzie (tylko teleport do lobby), więc
	-- `CharacterRemoving` na nich nie leci — bez tego zostawaliby z puszką i efektem.
	GameLoopService.RoundEnded:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			removeTool(player)
			clearEffect(player)
		end
	end)
end

return EnergyDrinkService
