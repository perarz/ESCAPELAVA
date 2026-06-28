--!strict
-- HotbarController.luau
-- Renderuje hotbar (5 slotów) z inventory replicated przez InventoryChanged.
-- Klient klika slot → select. Klik LMB w world (InputController) → użycie selectedSlot.
--
-- KONTRAKT NAZW w StarterGui (postawione przez MCP):
--   StarterGui.HUD.Hotbar (Frame, horizontal layout)
--     ├── Slot1..Slot5 (TextButton)
--     │   ├── Keybind (TextLabel) — "1", "2"...
--     │   ├── Count (TextLabel) — "x3"
--     │   ├── ItemName (TextLabel) — placeholder dla ikony, np. "Bomb"
--     │   └── SelectStroke (UIStroke) — Thickness=0 default, 3 gdy slot selected
--
-- Public API:
--   HotbarController.getSelected() -> slotIndex: number?  (do InputController)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local HotbarController = {}

local localPlayer = Players.LocalPlayer

-- Inventory nowy schema: { [itemId] = count }
local inventory: { [string]: number } = {}
-- Mapping fizycznego slotu (1-5) → itemId (lub nil)
local slotToItem: { [number]: string? } = {}
local selectedSlot: number? = nil
local slotButtons: { [number]: TextButton } = {}

local function rebuildSlotMapping()
	-- Pierwsze N item types z ItemDefinitions.shopOrder (które gracz ma) → sloty 1..N
	slotToItem = {}
	local slotIndex = 1
	for _, itemId in ipairs(ItemDefinitions.shopOrder) do
		if slotIndex > 5 then break end
		if (inventory[itemId] or 0) > 0 then
			slotToItem[slotIndex] = itemId
			slotIndex += 1
		end
	end
end

local function refreshSlot(slot: number)
	local btn = slotButtons[slot]
	if not btn then return end

	local itemId = slotToItem[slot]
	local nameLabel = btn:FindFirstChild("ItemName")
	local countLabel = btn:FindFirstChild("Count")
	local stroke = btn:FindFirstChild("SelectStroke")

	if itemId then
		local def = ItemDefinitions.get(itemId)
		local count = inventory[itemId] or 0
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = def and def.name or itemId
		end
		if countLabel and countLabel:IsA("TextLabel") then
			countLabel.Text = count > 1 and ("x" .. tostring(count)) or ""
		end
	else
		if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Text = "" end
		if countLabel and countLabel:IsA("TextLabel") then countLabel.Text = "" end
	end

	if stroke and stroke:IsA("UIStroke") then
		stroke.Thickness = (selectedSlot == slot) and 3 or 0
	end
end

local function refreshAll()
	rebuildSlotMapping()
	for slot = 1, 5 do
		refreshSlot(slot)
	end
end

local function setSelected(slot: number?)
	if slot == selectedSlot then
		-- Klik na ten sam slot = deselect (schowaj Tool)
		selectedSlot = nil
		Remotes.UnequipItem:FireServer()
	else
		selectedSlot = slot
		-- Equip item z mappingu — fires EquipItem(itemId)
		local itemId = slot and slotToItem[slot]
		if itemId then
			Remotes.EquipItem:FireServer(itemId)
		end
	end
	refreshAll()
end

function HotbarController.getSelected(): number?
	return selectedSlot
end

function HotbarController.getInventoryEntry(slot: number)
	local itemId = slotToItem[slot]
	if not itemId then return nil end
	return { itemId = itemId, count = inventory[itemId] or 0 }
end

function HotbarController.getSelectedItemId(): string?
	if not selectedSlot then return nil end
	return slotToItem[selectedSlot]
end

local function ensureSelectionValid()
	if selectedSlot and not slotToItem[selectedSlot] then
		selectedSlot = nil
		refreshAll()
	end
end

function HotbarController.init()
	-- Listener PRZED setupUI (yieldy)
	Remotes.InventoryChanged.OnClientEvent:Connect(function(newInventory)
		inventory = newInventory or {}
		refreshAll()
		ensureSelectionValid()
	end)

	-- UseItemResult feedback (success → slot się zaktualizuje przez InventoryChanged, error → log)
	Remotes.UseItemResult.OnClientEvent:Connect(function(success: boolean, _slot: number, reason: string?)
		if not success then
			-- TODO: pokaż mały toast w UI; na razie print
			print(("[Hotbar] use FAIL — %s"):format(tostring(reason)))
		end
	end)

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD", 10)
	if not hud then
		warn("[HotbarController] PlayerGui.HUD nie istnieje")
		return
	end

	local hotbar = hud:WaitForChild("Hotbar", 5)
	if not hotbar then
		warn("[HotbarController] HUD.Hotbar nie istnieje")
		return
	end

	for slot = 1, 5 do
		local btn = hotbar:FindFirstChild("Slot" .. slot)
		if btn and btn:IsA("TextButton") then
			slotButtons[slot] = btn
			btn.Activated:Connect(function()
				setSelected(slot)
			end)
		end
	end

	-- Klawisze 1-5 też selectują (PC convenience)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local key = input.KeyCode
		local map = {
			[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5,
		}
		local slot = map[key]
		if slot then setSelected(slot) end
	end)

	refreshAll()
end

return HotbarController
