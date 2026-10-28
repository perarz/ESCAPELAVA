--!strict
-- Studio owns the GUI templates. This controller owns their state and a disposable
-- dressing-room copy; it never teleports or resizes the actual player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Definitions = require(ReplicatedStorage.Shared.Modules.CosmeticDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local State = require(script.Parent.CosmeticsState)
local Preview = require(script.Parent.CosmeticsPreview)
local Shop = require(script.Parent.ShopController)

local Controller = {}
local player = Players.LocalPlayer
local CFG = Config.Cosmetics.UI
local gui: ScreenGui? = nil
local backdrop: TextButton? = nil
local backdropStuds: ImageLabel? = nil
local backdropTone: UIGradient? = nil
local toneBase: ColorSequence? = nil
local drift = 0
local root: Frame? = nil
local catalog: Frame? = nil
local fitting: Frame? = nil
local scroll: ScrollingFrame? = nil
local template: Frame? = nil
local button: GuiButton? = nil
local title: TextLabel? = nil
local balance: TextLabel? = nil
local wallet: Frame? = nil
local status: TextLabel? = nil
local empty: TextLabel? = nil
local productName: TextLabel? = nil
local productPrice: TextLabel? = nil
local priceRow: Frame? = nil
local pricePosition = UDim2.new()
local priceShadowPosition = UDim2.new()
local rarityTag: Frame? = nil
local needMore: TextLabel? = nil
local unlocked: Frame? = nil
local unlockToken = 0
local actionButton: TextButton? = nil
local scale: UIScale? = nil
local dragInput: InputObject? = nil
local dragX = 0
local hudGui: ScreenGui? = nil
local savedHudEnabled = false
local opened = false
local lobby = false
local mode = "shop"
local selected: string? = nil
local tryingOn = false
local cash = 0
local shownCash = 0
local count: { from: number, to: number, started: number }? = nil
local animation: RBXScriptConnection? = nil
local lastDrag = 0
local pending: { action: string, id: string, token: number }? = nil
local requestToken = 0
local preview: Model? = nil
local fittingFill: Attachment? = nil
local previewBase: CFrame? = nil
local previewAngle = 0
local camera: Camera? = nil
local savedCameraType: Enum.CameraType? = nil
local savedCameraFov: number? = nil
local controls: any = nil
local ownedControls = false
local cameraTween: Tween? = nil
local tiles: { Frame } = {}
-- Per-card motion: large cards always sway, the rest ease in under the cursor.
type CardFx = { viewport: ViewportFrame, base: CFrame?, center: Vector3, rays: GuiObject?,
	available: boolean, always: boolean, hovered: boolean, amp: number, phase: number }
local cardFx: { CardFx } = {}
local layoutWidth = CFG.Width
local layoutColumns = CFG.Columns
local layoutRowHeight = CFG.RowHeight
local refresh: () -> ()
local rebuild: () -> ()
local close: () -> ()

local messages = {
	not_enough_cash = "NOT ENOUGH CASH", already_owned = "ALREADY OWNED",
	asset_unavailable = "MODEL NOT READY", attachment_missing = "MODEL NEEDS FITTING",
	lobby_only = "AVAILABLE IN LOBBY", too_far = "RETURN TO THE COSMETICS STAND",
	shop_unavailable = "SHOP UNAVAILABLE", data_not_ready = "LOADING YOUR WARDROBE...",
	character_unavailable = "CHARACTER NOT READY", not_owned = "NOT OWNED",
	price_unavailable = "PRICE UNAVAILABLE", data_unavailable = "DATA UNAVAILABLE",
}

local function say(text: string)
	if status then status.Text = text end
end

local function rarityOf(def: Definitions.Definition): any
	return CFG.Rarities[def.rarity] or CFG.Rarities.Common
end

local function setTint(object: Instance?, colors: ColorSequence)
	local tint = object and object:FindFirstChild("Tint")
	if tint and tint:IsA("UIGradient") then tint.Color = colors end
end

local function setRays(rays: Instance?, color: Color3)
	if not rays then return end
	for _, ray in ipairs(rays:GetChildren()) do
		if ray:IsA("Frame") then ray.BackgroundColor3 = color end
	end
end

-- One price presentation for cards and the fitting room: amount, OWNED or WEARING.
local function showPrice(row: Instance, def: Definitions.Definition)
	local price = row:FindFirstChild("Price", true)
	if not price or not price:IsA("TextLabel") then return end
	local wearing = State.equipped(def.category) == def.id
	local owned = State.owns(def.id)
	price.Text = if wearing then "WEARING" elseif owned then "OWNED"
		else tostring(Definitions.getPrice(def.id) or "—") .. "$"
	setTint(price, if wearing then CFG.Colors.Wearing elseif owned then CFG.Colors.Owned else CFG.Colors.Price)
	local icon = row:FindFirstChild("CashIcon")
	if icon and icon:IsA("GuiObject") then icon.Visible = not owned end
end

-- The catalog studs belong to the opaque backdrop; the fitting room shows the scene.
local function showBackdrop(visible: boolean)
	if not backdrop then return end
	backdrop.BackgroundTransparency = if visible then CFG.BackdropTransparency else 1
	for _, child in ipairs(backdrop:GetChildren()) do
		if child:IsA("GuiObject") then child.Visible = visible end
	end
end

local function updateButton()
	if button then button.Visible = lobby and not Shop.isOpen() and not opened end
end

local function restoreCamera()
	dragInput = nil
	if cameraTween then cameraTween:Cancel(); cameraTween = nil end
	if preview then preview:Destroy(); preview = nil end
	if fittingFill then fittingFill:Destroy(); fittingFill = nil end
	previewBase = nil
	if camera then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		if savedCameraFov then camera.FieldOfView = savedCameraFov end
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end
	end
	camera, savedCameraType, savedCameraFov = nil, nil, nil
end

close = function()
	if not opened then return end
	opened = false
	if animation then animation:Disconnect(); animation = nil end
	count, shownCash = nil, cash
	unlockToken += 1
	if unlocked then unlocked.Visible = false end
	if hudGui then hudGui.Enabled = savedHudEnabled end
	selected = nil
	if gui then gui.Enabled = false end
	restoreCamera()
	if ownedControls and controls then controls:Enable() end
	ownedControls = false
	player:SetAttribute("CosmeticsOpen", false)
	updateButton()
end

local function platform(): BasePart?
	local node: Instance? = workspace:FindFirstChild(Config.Cosmetics.SceneName)
	for _, name in ipairs(Config.Cosmetics.PlatformPath) do node = node and node:FindFirstChild(name) end
	return if node and node:IsA("BasePart") then node else nil
end

local function dress(id: string): boolean
	local stand = platform()
	if not stand then say("DRESSING ROOM NOT READY"); return false end
	local model = Preview.character(false)
	if not model then say("CHARACTER NOT READY"); return false end
	-- The platform is rotated: Size.Y is not its world height. Use projected extents.
	local cf, sz = stand.CFrame, stand.Size
	local top = stand.Position.Y + (math.abs(cf.RightVector.Y) * sz.X
		+ math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z) / 2
	local bottom = math.huge
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local p, s = part.CFrame, part.Size
			bottom = math.min(bottom, p.Y - (math.abs(p.RightVector.Y)*s.X + math.abs(p.UpVector.Y)*s.Y + math.abs(p.LookVector.Y)*s.Z)/2)
		end
	end
	if bottom == math.huge then model:Destroy(); return false end
	local offset = model:GetPivot().Position.Y - bottom
	local base = CFrame.new(stand.Position.X, top + offset, stand.Position.Z) * CFrame.Angles(0, math.rad(CFG.StandYaw), 0)
	model:PivotTo(base)
	local ok, mounted = pcall(Preview.outfit, model, State.outfit(), id)
	if not ok or not mounted then
		model:Destroy()
		say("MODEL NEEDS FITTING")
		return false
	end
	if preview then preview:Destroy() end
	preview, previewBase, previewAngle = model, base, 0
	lastDrag = os.clock()
	-- Mount parts were anchored by Preview; this model cannot affect rays or physics.
	-- Anchor to the stationary platform, outside the rotating preview model.
	if fittingFill then fittingFill:Destroy() end
	local fillAnchor = Instance.new("Attachment")
	fillAnchor.Name = "FittingFill"
	fillAnchor.Parent = stand
	fillAnchor.WorldPosition = base:PointToWorldSpace(CFG.FittingFillOffset)
	fittingFill = fillAnchor
	local fill = Instance.new("PointLight")
	fill.Brightness = CFG.FittingFillBrightness
	fill.Range = CFG.FittingFillRange
	fill.Color = CFG.FittingFillColor
	fill.Shadows = false
	fill.Parent = fillAnchor
	model.Parent = workspace
	local cam = workspace.CurrentCamera
	if not cam then restoreCamera(); return false end
	if not camera then
		camera, savedCameraType, savedCameraFov = cam, cam.CameraType, cam.FieldOfView
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local box, bounds = model:GetBoundingBox()
	local focus = box.Position + Vector3.new(0, bounds.Y * CFG.FittingFocusOffset, 0)
	local aspect = cam.ViewportSize.X / math.max(1, cam.ViewportSize.Y)
	local distance = math.max(bounds.Y / CFG.FittingHeightFraction, math.max(bounds.X, bounds.Z) / math.max(aspect, 0.1)) / (2 * math.tan(math.rad(CFG.CameraFov / 2)))
	-- Optional authored marker overrides the automatic front view without code changes.
	local scene = workspace:FindFirstChild(Config.Cosmetics.SceneName)
	local marker = scene and scene:FindFirstChild("CosmeticsCamera", true)
	local target = if marker and marker:IsA("BasePart") then marker.CFrame
		else CFrame.lookAt(focus + base.LookVector * distance + Vector3.new(0, CFG.FittingCameraLift, 0), focus)
	if cameraTween then cameraTween:Cancel() end
	cam.FieldOfView = CFG.CameraFov
	cameraTween = TweenService:Create(cam, TweenInfo.new(CFG.OpenTime), { CFrame = target })
	cameraTween:Play()
	return true
end

local function choose(id: string)
	if not opened or not lobby then return end
	if not Definitions.getTemplate(id) then say("THIS COSMETIC IS COMING SOON"); return end
	if not dress(id) then return end
	selected = id
	tryingOn = true
	if catalog then catalog.Visible = false end
	if fitting then fitting.Visible = true end
	showBackdrop(false)
	say("")
	refresh()
end

local function back()
	selected = nil
	restoreCamera()
	if catalog then catalog.Visible = true end
	if fitting then fitting.Visible = false end
	showBackdrop(true)
	say("")
	refresh()
end

local function hover(btn: GuiButton)
	local pop = btn:FindFirstChild("Hover")
	if not pop or not pop:IsA("UIScale") then return end
	local tween: Tween? = nil
	local function animate(value: number)
		if tween then tween:Cancel() end
		tween = TweenService:Create(pop, TweenInfo.new(CFG.HoverTime), { Scale = value })
		tween:Play()
	end
	btn.MouseEnter:Connect(function() animate(CFG.HoverScale) end)
	btn.MouseLeave:Connect(function() animate(1) end)
end

rebuild = function()
	if not scroll or not template then return end
	for _, tile in ipairs(tiles) do tile:Destroy() end
	table.clear(tiles)
	table.clear(cardFx)
	local occupied: { [number]: { [number]: boolean } } = {}
	local columns, gap = layoutColumns, CFG.Gap
	local padding = CFG.CardPadding
	local width = layoutWidth - CFG.ScreenMargin * 2 - padding * 2
	local cell = (width - gap * (columns - 1)) / columns
	local lastRow = 0
	for _, id in ipairs(Definitions.shopOrder) do
		local def = Definitions.get(id)
		if not def or (mode == "wardrobe" and not State.owns(id)) then continue end
		local span = if CFG.LargeCards[id] then 2 else 1
		span = math.min(span, columns)
		local row, col = 1, 1
		while true do
			local fits = col + span - 1 <= columns
			for y = row, row + span - 1 do
				for x = col, col + span - 1 do
					if occupied[y] and occupied[y][x] then fits = false end
				end
			end
			if fits then break end
			col += 1
			if col > columns then row += 1; col = 1 end
		end
		for y = row, row + span - 1 do
			occupied[y] = occupied[y] or {}
			for x = col, col + span - 1 do occupied[y][x] = true end
		end
		lastRow = math.max(lastRow, row + span - 1)
		local tile = template:Clone()
		tile.Name, tile.Visible = id, true
		tile.Position = UDim2.fromOffset(padding+(col-1)*(cell+gap), padding+(row-1)*(layoutRowHeight+gap))
		tile.Size = UDim2.fromOffset(cell*span+gap*(span-1), layoutRowHeight*span+gap*(span-1))
		local card = tile:FindFirstChild("Card") :: TextButton
		local rarity = rarityOf(def)
		local fill = card:FindFirstChild("Fill") :: Frame
		local gradient = fill:FindFirstChild("Gradient")
		if gradient and gradient:IsA("UIGradient") then gradient.Color = rarity.Fill end
		local art = card:FindFirstChild("Art")
		local rays = art and art:FindFirstChild("Rays")
		setRays(rays, rarity.Rays)
		local rarityLabel = card:FindFirstChild("Rarity")
		if rarityLabel and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarity.Label
			rarityLabel.TextColor3 = rarity.Text
		end
		local nameLabel = card:FindFirstChild("ItemName") :: TextLabel
		nameLabel.Text = def.name:upper()
		local viewport = card:FindFirstChild("Preview") :: ViewportFrame
		local available, center = Preview.card(viewport, id)
		local unavailable = card:FindFirstChild("Unavailable") :: TextLabel
		unavailable.Visible = not available
		local fx: CardFx = { viewport = viewport, base = viewport.CurrentCamera and viewport.CurrentCamera.CFrame,
			center = center, rays = if rays and rays:IsA("GuiObject") then rays else nil, available = available,
			always = span > 1, hovered = false, amp = if span > 1 then 1 else 0, phase = 0 }
		table.insert(cardFx, fx)
		card.MouseEnter:Connect(function() fx.hovered = true end)
		card.MouseLeave:Connect(function() fx.hovered = false end)
		card.Activated:Connect(function() choose(id) end)
		hover(card)
		tile.Parent = scroll
		table.insert(tiles, tile)
	end
	scroll.CanvasSize = UDim2.fromOffset(0, math.max(0,lastRow*(layoutRowHeight+gap)-gap+padding*2))
	if empty then empty.Visible = #tiles == 0 end
end

refresh = function()
	local body = root and root:FindFirstChild("Body")
	if body then
		for _, name in ipairs({ "Header", "Title", "TitleShadow", "CloseButton" }) do
			local element = body:FindFirstChild(name)
			if element and element:IsA("GuiObject") then element.Visible = selected == nil end
		end
	end
	if balance then balance.Text = tostring(shownCash) .. "$" end
	if title then title.Text = if mode == "shop" then "COSMETICS" else "WARDROBE" end
	for _, tile in ipairs(tiles) do
		local def = Definitions.get(tile.Name)
		local card = tile:FindFirstChild("Card")
		local row = card and card:FindFirstChild("PriceRow")
		if row and def then showPrice(row, def) end
	end
	local def = if selected then Definitions.get(selected) else nil
	if not def then return end
	local rarity = rarityOf(def)
	if productName then productName.Text = def.name:upper() end
	if rarityTag then
		local label = rarityTag:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then label.Text = rarity.Label end
		setTint(rarityTag:FindFirstChild("Fill"), rarity.Fill)
	end
	if priceRow and productPrice then
		showPrice(priceRow, def)
		-- Without the cash icon (OWNED/WEARING) the word starts where the icon was.
		local icon = priceRow:FindFirstChild("CashIcon")
		local shift = if icon and icon:IsA("GuiObject") and not icon.Visible then -pricePosition.X.Offset else 0
		productPrice.Position = pricePosition + UDim2.fromOffset(shift, 0)
		local shadow = priceRow:FindFirstChild("PriceShadow")
		if shadow and shadow:IsA("GuiObject") then shadow.Position = priceShadowPosition + UDim2.fromOffset(shift, 0) end
	end
	-- Turn "can't afford" into a goal: how much is missing and how many survived rounds pay it.
	local price = Definitions.getPrice(def.id)
	local missing = if price and not State.owns(def.id) then price - cash else 0
	if needMore then
		needMore.Visible = missing > 0
		if missing > 0 then
			local rounds = math.ceil(missing / math.max(1, Config.Rewards.Win))
			needMore.Text = ("NEED %d$ MORE — SURVIVE %d ROUND%s"):format(missing, rounds, if rounds == 1 then "" else "S")
		end
	end
	if actionButton then
		local active = State.equipped(def.category) == def.id
		local ready = State.isReady() and pending == nil
		actionButton.Text = if pending then "..." elseif not State.isReady() then "LOADING..."
			elseif active then "UNEQUIP" elseif State.owns(def.id) then "EQUIP" else "BUY"
		actionButton.Active = ready
		local surface = actionButton:FindFirstChild("Surface")
		local gradient = surface and surface:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = if not ready or missing > 0 then CFG.Colors.Disabled
				elseif active then CFG.Colors.Unequip elseif State.owns(def.id) then CFG.Colors.Equip else CFG.Colors.Buy
		end
	end
end

local function animate(dt: number)
	local now = os.clock()
	if count then
		local t = math.clamp((now - count.started) / CFG.CashCountTime, 0, 1)
		shownCash = math.round(count.from + (count.to - count.from) * t)
		if t >= 1 then count = nil end
		if balance then balance.Text = tostring(shownCash) .. "$" end
	end
	if catalog and catalog.Visible then
		local studs = backdropStuds
		local tile = if studs then studs.TileSize.X.Offset else 0
		if studs and tile > 0 then
			-- Wraps after one tile; Studs is one tile larger than the screen, so no edge shows.
			drift = (drift + dt * CFG.BackdropDriftSpeed) % tile
			studs.Position = UDim2.fromOffset(-drift, -drift)
		end
		local tone, base = backdropTone, toneBase
		if tone and base then
			local glow = (1 - math.cos(now * 2 * math.pi / CFG.BackdropGlowPeriod)) / 2
			local keys = table.clone(base.Keypoints)
			local last = keys[#keys]
			keys[#keys] = ColorSequenceKeypoint.new(last.Time, last.Value:Lerp(CFG.BackdropGlowPeak, glow))
			tone.Color = ColorSequence.new(keys)
			tone.Offset = Vector2.new(0, -glow * CFG.BackdropGlowLift)
		end
		for _, fx in ipairs(cardFx) do
			local target = if fx.always or fx.hovered then 1 else 0
			fx.amp += (target - fx.amp) * math.min(1, dt * CFG.SwayEase)
			if fx.amp < 0.001 then continue end
			fx.phase += dt * CFG.CardSwaySpeed
			if fx.rays then fx.rays.Rotation = (fx.rays.Rotation + dt * CFG.RaysSpeed * fx.amp) % 360 end
			-- Sway, not a full turn: the front of a hat or vest is what sells it.
			local cam = fx.viewport.CurrentCamera
			if fx.available and cam and fx.base then
				local yaw = math.rad(math.sin(fx.phase) * CFG.CardSwayDegrees * fx.amp)
				cam.CFrame = CFrame.lookAt(fx.center + CFrame.Angles(0, yaw, 0) * (fx.base.Position - fx.center), fx.center)
			end
		end
	end
	-- Idle turntable in the fitting room (shows the backpack's back) until the player drags.
	if preview and previewBase and not dragInput and now - lastDrag > CFG.FittingSpinDelay then
		previewAngle = (previewAngle + dt * CFG.FittingSpinSpeed) % 360
		preview:PivotTo(previewBase * CFrame.Angles(0, math.rad(previewAngle), 0))
	end
	local rays = unlocked and unlocked.Visible and unlocked:FindFirstChild("Rays")
	if rays and rays:IsA("GuiObject") then rays.Rotation = (rays.Rotation + dt * CFG.UnlockedRaysSpeed) % 360 end
end

-- Purchase moment in the middle of the screen, where the player is looking.
local function celebrate(def: Definitions.Definition)
	local popup = unlocked
	if not popup then return end
	unlockToken += 1
	local token = unlockToken
	local rarity = rarityOf(def)
	local name = popup:FindFirstChild("ItemName")
	if name and name:IsA("TextLabel") then
		name.Text = def.name:upper()
		name.TextColor3 = rarity.Text
	end
	local rays = popup:FindFirstChild("Rays")
	setRays(rays, rarity.Text)
	-- Rays flash and fade, so the item now worn by the character stays visible.
	for _, ray in ipairs(if rays then rays:GetChildren() else {}) do
		if ray:IsA("Frame") then
			ray.BackgroundTransparency = 0
			TweenService:Create(ray, TweenInfo.new(CFG.UnlockedHold + CFG.UnlockedFadeTime), { BackgroundTransparency = 1 }):Play()
		end
	end
	local pop = popup:FindFirstChild("Pop")
	popup.Visible = true
	if pop and pop:IsA("UIScale") then
		pop.Scale = 0
		TweenService:Create(pop, TweenInfo.new(CFG.UnlockedPopTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	task.delay(CFG.UnlockedHold, function()
		if token ~= unlockToken then return end
		if pop and pop:IsA("UIScale") then
			TweenService:Create(pop, TweenInfo.new(CFG.UnlockedFadeTime, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
		task.delay(CFG.UnlockedFadeTime, function()
			if token == unlockToken then popup.Visible = false end
		end)
	end)
end

local function open(which: string)
	if opened or not lobby or Shop.isOpen() or not gui then return end
	if not controls then
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm then
			local ok, result = pcall(function() return (require(pm) :: any):GetControls() end)
			if ok then controls = result end
		end
	end
	-- require(PlayerModule) may yield: revalidate the lobby before acquiring the UI.
	if not lobby or Shop.isOpen() then return end
	opened, mode = true, which
	if hudGui then savedHudEnabled = hudGui.Enabled; hudGui.Enabled = false end
	player:SetAttribute("CosmeticsOpen", true)
	if controls then controls:Disable(); ownedControls = true end
	gui.Enabled = true
	if catalog then catalog.Visible = true end
	if fitting then fitting.Visible = false end
	showBackdrop(true)
	if scroll then scroll.CanvasPosition = Vector2.zero end
	if not animation then animation = RunService.RenderStepped:Connect(animate) end
	selected = nil
	rebuild()
	refresh()
	say(if State.isReady() then "" else "LOADING YOUR WARDROBE...")
	updateButton()
	local body = root and root:FindFirstChild("Body")
	local pop = body and body:FindFirstChild("Pop")
	if pop and pop:IsA("UIScale") then
		pop.Scale = CFG.OpenScale
		TweenService:Create(pop, TweenInfo.new(CFG.OpenTime, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

local function act()
	local id = selected
	if pending or not id or not opened or not lobby or not State.isReady() then return end
	local def = Definitions.get(id)
	if not def then return end
	local action = if State.owns(id) then "equip" else "buy"
	local requestId = if action == "equip" and State.equipped(def.category) == id then "" else id
	requestToken += 1
	local token = requestToken
	pending = { action = action, id = requestId, token = token }
	if action == "buy" then Remotes.BuyCosmetic:FireServer(id)
	else Remotes.SetCosmetic:FireServer(def.category, requestId) end
	refresh()
	task.delay(CFG.RequestTimeout, function()
		if pending and pending.token == token then
			pending = nil
			if opened then say("NO RESPONSE — PLEASE TRY AGAIN"); refresh() end
		end
	end)
end

local initialized = false
function Controller.init()
	if initialized then return end
	initialized = true
	State.onChanged(function()
		if not opened then return end
		if mode == "wardrobe" then rebuild() end
		if preview and selected then Preview.outfit(preview, State.outfit(), if tryingOn then selected else nil) end
		refresh()
	end)
	Remotes.GameStateChanged.OnClientEvent:Connect(function(state: any)
		lobby = state == "LOBBY"
		if not lobby then close() end
		updateButton()
	end)
	Remotes.CashChanged.OnClientEvent:Connect(function(value: any)
		if type(value) ~= "number" then return end
		-- A purchase made here should be felt: the wallet counts down instead of jumping.
		if opened and value < shownCash then
			count = { from = shownCash, to = value, started = os.clock() }
		else
			count, shownCash = nil, value
		end
		cash = value
		refresh()
	end)
	Remotes.CosmeticResult.OnClientEvent:Connect(function(success: boolean, action: string, id: string, reason: string?)
		if pending and pending.action == action and pending.id == id then pending = nil end
		if not opened then return end
		local bought = if success and action == "buy" then Definitions.get(id) else nil
		if bought then celebrate(bought) end
		say(if bought then "" elseif success then "OUTFIT SAVED"
			else (reason and (messages :: any)[reason]) or "COULD NOT COMPLETE — TRY AGAIN")
		-- Unequip should show the outfit without the selected item until it is selected again.
		if success and action == "equip" and id == "" then
			tryingOn = false
			if preview then Preview.outfit(preview, State.outfit(), nil) end
		end
		refresh()
	end)
	player.CharacterRemoving:Connect(close)
	player.CharacterAdded:Connect(close)
	Shop.onOpenChanged(function(isOpen: boolean) if isOpen then close() end; updateButton() end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == Config.Cosmetics.PromptName then open("shop") end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not opened then return end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			if selected then back() else close() end
		end
	end)
	task.spawn(function()
		local pg = player:WaitForChild("PlayerGui")
		local found = pg:WaitForChild("Cosmetics", 30)
		if not found or not found:IsA("ScreenGui") then warn("[Cosmetics] missing StarterGui.Cosmetics"); return end
		gui = found
		gui.Enabled = false
		-- Button surfaces and labels are authored separately, preventing empty text
		-- strokes from drawing a second rectangular border behind rounded buttons.
		for _, object in ipairs(gui:GetDescendants()) do
			if object:IsA("TextButton") and object:GetAttribute("SeparateLabel") then
				local label = object:FindFirstChild("Label") :: TextLabel
				local function syncLabel() label.Text = object.Text end
				syncLabel()
				object:GetPropertyChangedSignal("Text"):Connect(syncLabel)
			end
		end
		backdrop = gui:FindFirstChild("Backdrop") :: TextButton
		local studs = backdrop:FindFirstChild("Studs")
		if studs and studs:IsA("ImageLabel") then
			backdropStuds = studs
			local tile = studs.TileSize.X.Offset
			studs.Size = UDim2.new(1, tile, 1, tile)
		end
		local tone = backdrop:FindFirstChild("Tone")
		if tone and tone:IsA("UIGradient") then backdropTone, toneBase = tone, tone.Color end
		root = gui:FindFirstChild("Root") :: Frame
		local body = root:FindFirstChild("Body") :: Frame
		catalog = body:FindFirstChild("Catalog") :: Frame
		fitting = body:FindFirstChild("Fitting") :: Frame
		scroll = catalog:FindFirstChild("Items") :: ScrollingFrame
		template = gui:FindFirstChild("CardTemplate") :: Frame
		title = body:FindFirstChild("Title") :: TextLabel
		wallet = body:FindFirstChild("Cash") :: Frame
		balance = wallet.Body:FindFirstChild("CashLabel") :: TextLabel
		status = body:FindFirstChild("Status") :: TextLabel
		empty = catalog:FindFirstChild("Empty") :: TextLabel
		productName = fitting:FindFirstChild("ItemName") :: TextLabel
		rarityTag = fitting:FindFirstChild("RarityTag") :: Frame
		local row = fitting:FindFirstChild("PriceRow") :: Frame
		priceRow = row
		local fittingPrice = row:FindFirstChild("Price") :: TextLabel
		productPrice = fittingPrice
		pricePosition = fittingPrice.Position
		local fittingPriceShadow = row:FindFirstChild("PriceShadow")
		if fittingPriceShadow and fittingPriceShadow:IsA("GuiObject") then priceShadowPosition = fittingPriceShadow.Position end
		needMore = fitting:FindFirstChild("NeedMore") :: TextLabel
		unlocked = body:FindFirstChild("Unlocked") :: Frame
		actionButton = fitting:FindFirstChild("ActionButton") :: TextButton
		scale = root:FindFirstChild("Fit") :: UIScale
		local function fit()
			if not (scale and gui and root) then return end
			local portrait = gui.AbsoluteSize.X < gui.AbsoluteSize.Y
			local factor = if portrait then gui.AbsoluteSize.X / CFG.PortraitWidth else gui.AbsoluteSize.Y / CFG.Height
			factor = math.max(0.1, factor)
			layoutWidth = gui.AbsoluteSize.X / factor
			layoutColumns = if portrait then 2 else CFG.Columns
			local height = gui.AbsoluteSize.Y / factor
			layoutRowHeight = if portrait then CFG.RowHeight else math.max(CFG.RowHeight, (height-CFG.CatalogTop-CFG.CatalogBottom-CFG.Gap-CFG.CardPadding*2)/2)
			root.Size = UDim2.fromOffset(layoutWidth, height)
			scale.Scale = factor
			if wallet then
				wallet.Position = UDim2.fromOffset(CFG.ScreenMargin, math.max(CFG.BalanceTop, CFG.BalanceSafeTopPixels / factor))
			end
			if title then
				title.TextSize = if portrait then 54 else 76
				title.Size = UDim2.fromOffset(layoutWidth * 0.5,96)
				local shadow = title.Parent:FindFirstChild("TitleShadow")
				if shadow and shadow:IsA("TextLabel") then shadow.TextSize = title.TextSize; shadow.Size = title.Size end
			end
			if opened then rebuild(); refresh() end
		end
		fit()
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		local closeButton = body:FindFirstChild("CloseButton") :: GuiButton
		local backButton = fitting:FindFirstChild("BackButton") :: GuiButton
		closeButton.Activated:Connect(close)
		hover(closeButton)
		backButton.Activated:Connect(back)
		hover(backButton)
		actionButton.Activated:Connect(act)
		hover(actionButton)
		local rotateArea = fitting:FindFirstChild("RotateArea") :: GuiObject
		rotateArea.InputBegan:Connect(function(input)
			if not selected or not preview or dragInput then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragInput = input
				dragX = input.Position.X
				lastDrag = os.clock()
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not dragInput or not preview or not previewBase then return end
			local mouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			if (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or input == dragInput then
				local dx = input.Position.X - dragX
				dragX = input.Position.X
				previewAngle = (previewAngle + dx / math.max(1, rotateArea.AbsoluteSize.X) * CFG.DragDegrees) % 360
				lastDrag = os.clock()
				preview:PivotTo(previewBase * CFrame.Angles(0, math.rad(previewAngle), 0))
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragInput = nil end
		end)
		UserInputService.WindowFocusReleased:Connect(function() dragInput = nil end)
		local hud = pg:WaitForChild("HUD")
		hudGui = hud :: ScreenGui
		local side = hud:WaitForChild("SideButtons")
		local btn = side:WaitForChild("CosmeticsButton", 30)
		if btn and btn:IsA("GuiButton") then button = btn; btn.Activated:Connect(function() open("wardrobe") end) end
		updateButton()
		refresh()
	end)
end
return Controller
