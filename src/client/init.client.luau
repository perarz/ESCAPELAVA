--!strict
-- Client bootstrap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Wyłącz Roblox default Backpack hotbar — mamy własny Hotbar UI.
-- Roblox Tool equipped pokazuje swój hotbar pod dolnym ekranem co nakłada się na nasz.
-- 15.11: także domyślny pasek zdrowia — zastępuje go HUD.HealthBar (HealthBarController).
local function disableDefaultBackpack()
	-- SetCoreGuiEnabled może rzucić błąd zanim CoreGui załaduje — retry loop.
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then return end
		task.wait(0.5)
	end
end
-- task.spawn (paczka 3): do 5 s prób NIE może wstrzymywać podpięcia listenerów.
-- Twarda zasada tego pliku: od startu do `ClientReady` yielduje tylko `require` (moduły
-- i remote'y) — żaden listener nie może czekać na UI ani na postać.
task.spawn(disableDefaultBackpack)

local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

-- EKRAN ŁADOWANIA czeka na stan startowy (decyzja Kacpra 18.10: „wszystko ma się
-- załadować w tym UI”). Atrybut jest LOKALNY (klient na własnym Playerze — serwer go nie
-- widzi) i czyta go `ReplicatedFirst.LoadingScreen`, który nie może requirować modułów.
-- Kasa, inventory i loadout przychodzą dopiero po wczytaniu danych gracza; stan gry od razu.
local player = Players.LocalPlayer
local got = { state = false, cash = false, inventory = false, loadout = false }
local function mark(key: string)
	if got[key] then return end
	got[key] = true
	if got.state and got.cash and got.inventory and got.loadout then
		player:SetAttribute("ClientStateReady", true)
	end
end
Remotes.GameStateChanged.OnClientEvent:Connect(function() mark("state") end)
Remotes.CashChanged.OnClientEvent:Connect(function() mark("cash") end)
Remotes.InventoryChanged.OnClientEvent:Connect(function() mark("inventory") end)
Remotes.LoadoutChanged.OnClientEvent:Connect(function() mark("loadout") end)


local LoadoutState = require(script.Controllers.LoadoutState)
local SettingsState = require(script.Controllers.SettingsState)
local CosmeticsState = require(script.Controllers.CosmeticsState)
local CosmeticsController = require(script.Controllers.CosmeticsController)
local UIController = require(script.Controllers.UIController)
local ShopController = require(script.Controllers.ShopController)
local HotbarController = require(script.Controllers.HotbarController)
local ToolController = require(script.Controllers.ToolController)
local ItemEquipController = require(script.Controllers.ItemEquipController)
local PushController = require(script.Controllers.PushController)
local CashController = require(script.Controllers.CashController)
local ItemPickupController = require(script.Controllers.ItemPickupController)
local PromptController = require(script.Controllers.PromptController)
local CashCounterController = require(script.Controllers.CashCounterController)
local BridgeController = require(script.Controllers.BridgeController)
local GrappleController = require(script.Controllers.GrappleController)
local EnergyDrinkController = require(script.Controllers.EnergyDrinkController)
local BandageController = require(script.Controllers.BandageController)
local RpgController = require(script.Controllers.RpgController)
local C4Controller = require(script.Controllers.C4Controller)
local MovementController = require(script.Controllers.MovementController)
local CooldownBarController = require(script.Controllers.CooldownBarController)
local WinMessageController = require(script.Controllers.WinMessageController)
local KillMessageController = require(script.Controllers.KillMessageController)
local HealthBarController = require(script.Controllers.HealthBarController)
local LavaMeterController = require(script.Controllers.LavaMeterController)
local LavaHeatController = require(script.Controllers.LavaHeatController)
local LavaSurfaceController = require(script.Controllers.LavaSurfaceController)
local LavaSwimController = require(script.Controllers.LavaSwimController)
local LavaSplashController = require(script.Controllers.LavaSplashController)
local FallImpactController = require(script.Controllers.FallImpactController)
local TowerAmbienceController = require(script.Controllers.TowerAmbienceController)
local HudScaleController = require(script.Controllers.HudScaleController)
local TouchControlsController = require(script.Controllers.TouchControlsController)
local CashDigitsController = require(script.Controllers.CashDigitsController)
local ExplosionFXController = require(script.Controllers.ExplosionFXController)
local DebrisFXController = require(script.Controllers.DebrisFXController)
local DevController = require(script.Controllers.DevController)
local RoundTransitionController = require(script.Controllers.RoundTransitionController)
local LadderController = require(script.Controllers.LadderController)
local TextShadowController = require(script.Controllers.TextShadowController)
local GradientShimmerController = require(script.Controllers.GradientShimmerController)
local InventoryController = require(script.Controllers.InventoryController)
local RoundSkipController = require(script.Controllers.RoundSkipController)
local SpectateController = require(script.Controllers.SpectateController)
local SettingsController = require(script.Controllers.SettingsController)
local BarrierController = require(script.Controllers.BarrierController)
local LobbyVisibilityController = require(script.Controllers.LobbyVisibilityController)
local SkillTreeController = require(script.Controllers.SkillTreeController)
local RoundEventController = require(script.Controllers.RoundEventController)
local SupplyDropController = require(script.Controllers.SupplyDropController)
local AirstrikeController = require(script.Controllers.AirstrikeController)
local TrainController = require(script.Controllers.TrainController)
local LowGravityController = require(script.Controllers.LowGravityController)

-- KAŻDY KONTROLER W OSOBNYM WĄTKU (paczka 3, przegląd 29.09 B-1). Dawniej startowały po
-- kolei, a kilka czekało na UI — kontroler nr 5 nie podpinał listenerów, dopóki nr 4 nie
-- znalazł swojego HUD, a błąd jednego zatrzymywał wszystkie następne (też ruch i kamerę).
-- `task.spawn` wykonuje init od razu aż do pierwszego yieldu, więc po tej pętli każdy
-- kontroler ma już podpięte listenery, które stoją w nim przed czekaniem na UI.
local function start(name: string, controller: { init: () -> () })
	task.spawn(function()
		local ok, err = xpcall(controller.init, debug.traceback)
		if not ok then
			warn(("[Client] %s.init padł: %s"):format(name, tostring(err)))
		end
	end)
end

-- LoadoutState pierwszy: pasek i panel czytają z niego stan, a jego listenery muszą stać
-- przed `ClientReady`.
start("LoadoutState", LoadoutState)
-- Ustawienia też przed `ClientReady` — stan startowy z serwera nie może trafić w próżnię.
start("SettingsState", SettingsState)
start("CosmeticsState", CosmeticsState)
start("CosmeticsController", CosmeticsController)
start("UIController", UIController)
start("ShopController", ShopController)
start("HotbarController", HotbarController)
start("ToolController", ToolController)
start("ItemEquipController", ItemEquipController)
start("PushController", PushController)
start("CashController", CashController)
start("ItemPickupController", ItemPickupController)
start("PromptController", PromptController)
start("CashCounterController", CashCounterController)
start("BridgeController", BridgeController)
start("GrappleController", GrappleController)
start("EnergyDrinkController", EnergyDrinkController)
start("BandageController", BandageController)
start("RpgController", RpgController)
start("C4Controller", C4Controller)
start("MovementController", MovementController)
start("CooldownBarController", CooldownBarController)
start("WinMessageController", WinMessageController)
start("KillMessageController", KillMessageController)
start("HealthBarController", HealthBarController)
start("LavaMeterController", LavaMeterController)
start("LavaHeatController", LavaHeatController)
start("LavaSurfaceController", LavaSurfaceController)
start("LavaSwimController", LavaSwimController)
start("LavaSplashController", LavaSplashController)
start("FallImpactController", FallImpactController)
start("TowerAmbienceController", TowerAmbienceController)
start("HudScaleController", HudScaleController)
start("TouchControlsController", TouchControlsController)
start("CashDigitsController", CashDigitsController)
start("ExplosionFXController", ExplosionFXController)
start("DebrisFXController", DebrisFXController)
start("DevController", DevController)
start("RoundTransitionController", RoundTransitionController)
start("LadderController", LadderController)
start("TextShadowController", TextShadowController)
start("GradientShimmerController", GradientShimmerController)
start("InventoryController", InventoryController)
start("RoundSkipController", RoundSkipController)
start("SpectateController", SpectateController)
start("SettingsController", SettingsController)
start("BarrierController", BarrierController)
start("LobbyVisibilityController", LobbyVisibilityController)
-- Wydarzenia rundy (24.11): napis i syrena, skrzynia zrzutu, rakiety nalotu.
start("RoundEventController", RoundEventController)
start("SupplyDropController", SupplyDropController)
start("AirstrikeController", AirstrikeController)
start("TrainController", TrainController)
start("LowGravityController", LowGravityController)
-- Drzewko u maga (09.11): listenery stanu stoją przed czekaniem na panel, więc przed `ClientReady`.
start("SkillTreeController", SkillTreeController)

-- Wszystkie listenery stoją — dopiero teraz serwer wysyła stan startowy (init.server).
Remotes.ClientReady:FireServer()

print("[Client] ESCAPE LAVA client ready.")
