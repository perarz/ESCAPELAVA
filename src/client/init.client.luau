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

UIController.init()
ShopController.init()
HotbarController.init()
ToolController.init()
PushController.init()
CashController.init()
CashPopupController.init()
BridgeController.init()

print("[Client] ESCAPE LAVA client ready.")
