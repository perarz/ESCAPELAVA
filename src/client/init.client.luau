--!strict
-- Client bootstrap.

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
disableDefaultBackpack()

local UIController = require(script.Controllers.UIController)
local ShopController = require(script.Controllers.ShopController)
local HotbarController = require(script.Controllers.HotbarController)
local ToolController = require(script.Controllers.ToolController)
local PushController = require(script.Controllers.PushController)
local CashController = require(script.Controllers.CashController)
local CashPopupController = require(script.Controllers.CashPopupController)
local BridgeController = require(script.Controllers.BridgeController)
local MovementController = require(script.Controllers.MovementController)
local CooldownBarController = require(script.Controllers.CooldownBarController)
local WinBannerController = require(script.Controllers.WinBannerController)
local KillFeedController = require(script.Controllers.KillFeedController)
local HudVisibilityController = require(script.Controllers.HudVisibilityController)
local DailyRewardsController = require(script.Controllers.DailyRewardsController)
local LavaHeatController = require(script.Controllers.LavaHeatController)
local HudScaleController = require(script.Controllers.HudScaleController)
local CashDigitsController = require(script.Controllers.CashDigitsController)
local ExplosionFXController = require(script.Controllers.ExplosionFXController)
local DebrisFXController = require(script.Controllers.DebrisFXController)
local DevController = require(script.Controllers.DevController)

UIController.init()
ShopController.init()
HotbarController.init()
ToolController.init()
PushController.init()
CashController.init()
CashPopupController.init()
BridgeController.init()
MovementController.init()
CooldownBarController.init()
WinBannerController.init()
KillFeedController.init()
HudVisibilityController.init()
DailyRewardsController.init()
LavaHeatController.init()
HudScaleController.init()
CashDigitsController.init()
ExplosionFXController.init()
DebrisFXController.init()
DevController.init()

print("[Client] ESCAPE LAVA client ready.")
