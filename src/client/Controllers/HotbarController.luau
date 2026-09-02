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
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
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
-- Debounce EquipItem/UnequipItem (mirror Config.RateLimits.EquipItem — server enforces).
local lastEquipAt = 0

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
		-- Biały stroke = "to trzymasz w ręku". Animowany thickness zamiast skoku 0→3.
		local selected = (selectedSlot == slot)
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = selected and 3 or 0,
		}):Play()
	end
end

local function popSlot(slot: number)
	-- "Pop" slotu przy equipie — chwilowe powiększenie z Back easing (soczysty feedback).
	local btn = slotButtons[slot]
	if not btn then return end
	local scale = btn:FindFirstChild("EquipPop")
	if not scale or not scale:IsA("UIScale") then
		scale = Instance.new("UIScale")
		scale.Name = "EquipPop"
		scale.Parent = btn
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 1.12
	TweenService:Create(uiScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function refreshAll()
	rebuildSlotMapping()
	for slot = 1, 5 do
		refreshSlot(slot)
	end
end

local function setSelected(slot: number?)
	-- Klik na PUSTY slot = no-op. Bez tego UI zaznaczało pusty slot (stroke), a serwer
	-- dalej trzymał poprzedni Tool w ręku — desync między tym co widać a tym co jest.
	if slot ~= nil and slot ~= selectedSlot and not slotToItem[slot] then return end

	local now = os.clock()
	if now - lastEquipAt < Config.RateLimits.EquipItem then return end
	lastEquipAt = now

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
			popSlot(slot :: number)
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

	local hoverTI = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for slot = 1, 5 do
		local btn = hotbar:FindFirstChild("Slot" .. slot)
		if btn and btn:IsA("TextButton") then
			slotButtons[slot] = btn
			btn.Activated:Connect(function()
				setSelected(slot)
			end)

			-- Hover: rozjaśnienie tła slotu (subtelne "jestem klikalny").
			local baseBg = btn.BackgroundColor3
			local hoverBg = Color3.new(
				math.min(baseBg.R * 1.3 + 0.05, 1),
				math.min(baseBg.G * 1.3 + 0.05, 1),
				math.min(baseBg.B * 1.3 + 0.05, 1)
			)
			btn.MouseEnter:Connect(function()
				TweenService:Create(btn, hoverTI, { BackgroundColor3 = hoverBg }):Play()
			end)
			btn.MouseLeave:Connect(function()
				TweenService:Create(btn, hoverTI, { BackgroundColor3 = baseBg }):Play()
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
