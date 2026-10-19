--!strict
-- Client bootstrap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Wyłącz Roblox default Backpack hotbar — mamy własny Hotbar UI.
-- Roblox Tool equipped pokazuje swój hotbar pod dolnym ekranem co nakłada się na nasz.
local function disableDefaultBackpack()
	-- SetCoreGuiEnabled może rzucić błąd zanim CoreGui załaduje — retry loop.
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
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

local LoadoutState = require(script.Controllers.LoadoutState)
local UIController = require(script.Controllers.UIController)
local ShopController = require(script.Controllers.ShopController)
local HotbarController = require(script.Controllers.HotbarController)
local ToolController = require(script.Controllers.ToolController)
local PushController = require(script.Controllers.PushController)
local CashController = require(script.Controllers.CashController)
local CashCounterController = require(script.Controllers.CashCounterController)
local BridgeController = require(script.Controllers.BridgeController)
local GrappleController = require(script.Controllers.GrappleController)
local MovementController = require(script.Controllers.MovementController)
local CooldownBarController = require(script.Controllers.CooldownBarController)
local WinBannerController = require(script.Controllers.WinBannerController)
local KillMessageController = require(script.Controllers.KillMessageController)
local LavaHeatController = require(script.Controllers.LavaHeatController)
local LavaSurfaceController = require(script.Controllers.LavaSurfaceController)
local LavaSwimController = require(script.Controllers.LavaSwimController)
local HudScaleController = require(script.Controllers.HudScaleController)
local CashDigitsController = require(script.Controllers.CashDigitsController)
local ExplosionFXController = require(script.Controllers.ExplosionFXController)
local DebrisFXController = require(script.Controllers.DebrisFXController)
local DevController = require(script.Controllers.DevController)
local RoundTransitionController = require(script.Controllers.RoundTransitionController)
local LadderController = require(script.Controllers.LadderController)
local TextShadowController = require(script.Controllers.TextShadowController)
local GradientShimmerController = require(script.Controllers.GradientShimmerController)
local InventoryController = require(script.Controllers.InventoryController)

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
start("UIController", UIController)
start("ShopController", ShopController)
start("HotbarController", HotbarController)
start("ToolController", ToolController)
start("PushController", PushController)
start("CashController", CashController)
start("CashCounterController", CashCounterController)
start("BridgeController", BridgeController)
start("GrappleController", GrappleController)
start("MovementController", MovementController)
start("CooldownBarController", CooldownBarController)
start("WinBannerController", WinBannerController)
start("KillMessageController", KillMessageController)
start("LavaHeatController", LavaHeatController)
start("LavaSurfaceController", LavaSurfaceController)
start("LavaSwimController", LavaSwimController)
start("HudScaleController", HudScaleController)
start("CashDigitsController", CashDigitsController)
start("ExplosionFXController", ExplosionFXController)
start("DebrisFXController", DebrisFXController)
start("DevController", DevController)
start("RoundTransitionController", RoundTransitionController)
start("LadderController", LadderController)
start("TextShadowController", TextShadowController)
start("GradientShimmerController", GradientShimmerController)
start("InventoryController", InventoryController)

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

-- Wszystkie listenery stoją — dopiero teraz serwer wysyła stan startowy (init.server).
Remotes.ClientReady:FireServer()

print("[Client] ESCAPE LAVA client ready.")
