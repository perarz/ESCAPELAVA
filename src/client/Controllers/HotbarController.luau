--!strict
-- HotbarController.luau
-- Renderuje hotbar (5 slotów) z inventory replicated przez InventoryChanged.
-- Klient klika slot (albo klawisz 1-5) → EquipItem / UnequipItem; użycie trzymanego itemu
-- obsługują kontrolery itemów (ToolController, BridgeController, GrappleController).
--
-- KONTRAKT NAZW w StarterGui (postawione przez MCP):
--   StarterGui.HUD.Hotbar (Frame, horizontal layout)
--     ├── Slot1..Slot5 (TextButton)
--     │   ├── Keybind (TextLabel) — "1", "2"...
--     │   ├── Count (TextLabel) — "x3"
--     │   ├── ItemName (TextLabel) — nazwa itemu (po angielsku, z ItemDefinitions)
--     │   ├── Icon (ImageLabel, opcjonalny) — ikona itemu z ItemDefinitions.<id>.icon (10.10)
--     │   └── SelectStroke (UIStroke) — wygląd z Studio = niezaznaczony; biała gdy slot selected
--     (11.10) sloty BEZ UIListLayout — stałe pozycje ze Studio, bo wybrany slot podskakuje i zostaje
--     wyżej (`Config.UI.HotbarEquip`); layout trzymałby pozycję i podskok byłby niemożliwy.
--
-- ZAZNACZENIE = item, którego Tool (atrybut `ItemId`, stawia go serwer) jest TERAZ w postaci
-- (przegląd 29.09, B-3). Do 29.09 hotbar pamiętał numer slotu: po śmierci / końcu rundy serwer
-- zabierał Tool, a slot dalej wyglądał na zaznaczony — pierwszy klik „odznaczał” i dopiero
-- drugi wyposażał; po skończeniu się pierwszego itemu zaznaczenie przeskakiwało na następny.
-- Stan z postaci nie może się rozjechać z tym, co gracz trzyma w ręce.

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
local equippedItem: string? = nil -- odczyt z postaci (patrz nagłówek), nie pamięć kliknięć
local slotButtons: { [number]: TextButton } = {}
-- Debounce EquipItem/UnequipItem (mirror Config.RateLimits.EquipItem — server enforces).
local lastEquipAt = 0
local CFG_EQ = Config.UI.HotbarEquip
-- Animacja wyciągnięcia (11.10): pozycja ze Studio = slot „na dole”; wybrany jedzie w górę.
local slotBase: { [number]: UDim2 } = {}
local slotRaised: { [number]: boolean } = {}
-- Żeton per slot: nowa zmiana stanu unieważnia czekające opadnięcie (patrz `animateSlot`).
local slotToken: { [number]: number } = {}

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

-- Ramka slotu ustawiona w Studio = stan „niezaznaczony”, zapamiętana w init, ZANIM cokolwiek
-- ją przestawi. Do 10.10 była zapamiętywana leniwie w tabeli ze słabymi kluczami: Roblox potrafi
-- zebrać wpis z Instance jako kluczem, choć obiekt żyje — wtedy „normalną” stawała się biała
-- ramka zaznaczenia i nie znikała po schowaniu itemu.
local strokeNormal: { [number]: { color: Color3, thickness: number, transparency: number } } = {}

local function equipScale(btn: GuiObject): UIScale
	local existing = btn:FindFirstChild("EquipPop")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "EquipPop"
	scale.Parent = btn
	return scale
end

-- Wyciągnięcie: slot podskakuje (sprężyście), zostaje wyżej i trochę większy, ikona się buja.
-- Schowanie: opada na miejsce — z opóźnieniem `DeselectDelay`, bo auto-re-equip bomby po rzucie
-- zabiera i oddaje Tool w tej samej chwili; bez tego slot podskakiwałby przy każdym rzucie.
local function animateSlot(slot: number, selected: boolean)
	local btn = slotButtons[slot]
	local base = slotBase[slot]
	if not btn or not base then return end
	local token = (slotToken[slot] or 0) + 1
	slotToken[slot] = token
	local raised = slotRaised[slot] == true
	local scale = equipScale(btn)
	if selected then
		if raised then return end -- żeton już anulował czekające opadnięcie
		slotRaised[slot] = true
		TweenService:Create(btn, TweenInfo.new(CFG_EQ.RaiseTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = base + UDim2.fromOffset(0, -CFG_EQ.Raise),
		}):Play()
		scale.Scale = CFG_EQ.PopScale
		TweenService:Create(scale, TweenInfo.new(CFG_EQ.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = CFG_EQ.SelectedScale,
		}):Play()
		local icon = btn:FindFirstChild("Icon")
		if icon and icon:IsA("GuiObject") then
			icon.Rotation = CFG_EQ.IconWiggle
			TweenService:Create(icon, TweenInfo.new(CFG_EQ.WiggleTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
				Rotation = 0,
			}):Play()
		end
	else
		if not raised then return end
		task.delay(CFG_EQ.DeselectDelay, function()
			if slotToken[slot] ~= token then return end
			slotRaised[slot] = false
			local info = TweenInfo.new(CFG_EQ.DropTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(btn, info, { Position = base }):Play()
			TweenService:Create(scale, info, { Scale = 1 }):Play()
		end)
	end
end

local function refreshSlot(slot: number)
	local btn = slotButtons[slot]
	if not btn then return end

	local itemId = slotToItem[slot]
	local nameLabel = btn:FindFirstChild("ItemName")
	local countLabel = btn:FindFirstChild("Count")
	local stroke = btn:FindFirstChild("SelectStroke")
	-- Ikona itemu (10.10): `Icon` (ImageLabel) w slocie, obrazek z `ItemDefinitions.<id>.icon`.
	-- Brak ikony w definicji = sama nazwa, jak dawniej.
	local icon = btn:FindFirstChild("Icon")

	if itemId then
		local def = ItemDefinitions.get(itemId)
		local count = inventory[itemId] or 0
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = def and def.name or itemId
		end
		if countLabel and countLabel:IsA("TextLabel") then
			countLabel.Text = count > 1 and ("x" .. tostring(count)) or ""
		end
		if icon and icon:IsA("ImageLabel") then
			local image = def and def.icon
			icon.Image = if typeof(image) == "string" then image else ""
			icon.Visible = icon.Image ~= ""
		end
	else
		if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Text = "" end
		if countLabel and countLabel:IsA("TextLabel") then countLabel.Text = "" end
		if icon and icon:IsA("ImageLabel") then
			icon.Image = ""
			icon.Visible = false
		end
	end

	local selected = itemId ~= nil and itemId == equippedItem
	animateSlot(slot, selected)
	local normal = strokeNormal[slot]
	if stroke and stroke:IsA("UIStroke") and normal then
		-- Biała ramka = "to trzymasz w ręku". Niezaznaczony slot wraca do ramki ustawionej
		-- w Studio (od 10.10 projekt z Figmy: czarna, 7).
		local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(stroke, ti, {
			Color = if selected then Color3.fromRGB(255, 255, 255) else normal.color,
			Thickness = if selected then math.max(normal.thickness, 3) else normal.thickness,
			Transparency = if selected then 0 else normal.transparency,
		}):Play()
	end
end

local function refreshAll()
	rebuildSlotMapping()
	for slot = 1, 5 do
		refreshSlot(slot)
	end
end

local function setSelected(slot: number)
	-- Klik na PUSTY slot = no-op (serwer i tak trzyma poprzedni Tool w ręce).
	local itemId = slotToItem[slot]
	if not itemId then return end

	local now = os.clock()
	if now - lastEquipAt < Config.RateLimits.EquipItem then return end
	lastEquipAt = now

	if itemId == equippedItem then
		-- Klik na to, co trzymasz = schowaj. Obramowanie zniknie, gdy serwer zabierze Tool.
		Remotes.UnequipItem:FireServer()
	else
		-- Animacja rusza, gdy Tool naprawdę jest w ręce (`syncEquipped`), nie przy kliknięciu.
		Remotes.EquipItem:FireServer(itemId)
	end
end

-- Co gracz trzyma w ręce: Tool z atrybutem ItemId w postaci (bez niego — nic).
local function readEquipped(char: Model?): string?
	if not char then return nil end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			local id = child:GetAttribute("ItemId")
			if typeof(id) == "string" then
				return id
			end
		end
	end
	return nil
end

local function syncEquipped()
	local id = readEquipped(localPlayer.Character)
	if id ~= equippedItem then
		equippedItem = id
		refreshAll()
	end
end

local function hookCharacter(char: Model)
	-- Nowa postać (śmierć, start rundy) nie ma Toola — zaznaczenie znika samo.
	syncEquipped()
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then syncEquipped() end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then syncEquipped() end
	end)
end

function HotbarController.init()
	-- Listener PRZED setupUI (yieldy)
	Remotes.InventoryChanged.OnClientEvent:Connect(function(newInventory)
		inventory = newInventory or {}
		refreshAll()
	end)
	localPlayer.CharacterAdded:Connect(hookCharacter)
	if localPlayer.Character then
		hookCharacter(localPlayer.Character)
	end

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
			slotBase[slot] = btn.Position
			local stroke = btn:FindFirstChild("SelectStroke")
			if stroke and stroke:IsA("UIStroke") then
				strokeNormal[slot] = {
					color = stroke.Color, thickness = stroke.Thickness, transparency = stroke.Transparency,
				}
			end
			btn.Activated:Connect(function()
				setSelected(slot)
			end)

			-- Hover: rozjaśnienie tła slotu (subtelne "jestem klikalny"). Od 10.10 tło slotu to
			-- dziecko `Fill` (gradient z Figmy) — gradient na samym przycisku zjadał ramkę.
			local fill = btn:FindFirstChild("Fill")
			local bgTarget: GuiObject = if fill and fill:IsA("GuiObject") then fill else btn
			local baseBg = bgTarget.BackgroundColor3
			local hoverBg = Color3.new(
				math.min(baseBg.R * 1.3 + 0.05, 1),
				math.min(baseBg.G * 1.3 + 0.05, 1),
				math.min(baseBg.B * 1.3 + 0.05, 1)
			)
			btn.MouseEnter:Connect(function()
				TweenService:Create(bgTarget, hoverTI, { BackgroundColor3 = hoverBg }):Play()
			end)
			btn.MouseLeave:Connect(function()
				TweenService:Create(bgTarget, hoverTI, { BackgroundColor3 = baseBg }):Play()
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
