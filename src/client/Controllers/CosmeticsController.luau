--!strict
-- CosmeticsController — sklep i garderoba COSMETICS.
-- v6c (10.11, Kacper): katalog = po lewej ramka z samą postacią w obecnym stroju (`Body.Dressing`,
-- kopia w ViewportFrame), kasa nad nią; po prawej karty (`Body.Shelf`) przewijane we własnych
-- granicach. Klik w kartę przenosi do przebieralni ze sceną (`Body.Fitting` + kamera na platformie
-- `ClothesShopScene`): przymierzenie, BUY / EQUIP, BACK wraca do katalogu.
-- Studio owns the GUI templates (StarterGui.Cosmetics); this controller owns state, layout and
-- disposable local copies (card viewports, the frame model, the fitting-room model). It never
-- teleports or resizes the actual player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Definitions = require(ReplicatedStorage.Shared.Modules.CosmeticDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local State = require(script.Parent.CosmeticsState)
local Preview = require(script.Parent.CosmeticsPreview)
local Shop = require(script.Parent.ShopController)
local ShopFx = require(script.Parent.ShopFx)
local LobbySign = require(script.Parent.LobbySign)
local RoundSkip = require(script.Parent.RoundSkipState)
local HudButtonFx = require(script.Parent.HudButtonFx)

local Controller = {}
local player = Players.LocalPlayer
local CFG = Config.Cosmetics.UI
local WHITE = Color3.new(1, 1, 1)

-- Elementy z placu (kontrakt: STUDIO_CONTRACT → COSMETICS).
local gui: ScreenGui? = nil
local backdrop: TextButton? = nil
local root: Frame? = nil
local body: Frame? = nil
local fitScale: UIScale? = nil
local dressing: Frame? = nil
local frame: Frame? = nil
local view: ViewportFrame? = nil
local frameLed: UIGradient? = nil
local shelf: Frame? = nil
local scroll: ScrollingFrame? = nil
local template: Frame? = nil
local title: TextLabel? = nil
local titleShadow: TextLabel? = nil
local titleFlow: UIGradient? = nil
local closeButton: GuiButton? = nil
local wallet: Frame? = nil
local balance: TextLabel? = nil
local status: TextLabel? = nil
local empty: TextLabel? = nil
local unlocked: Frame? = nil
local button: GuiButton? = nil -- HUD.SideButtons.CosmeticsButton
local hudGui: ScreenGui? = nil
-- Przebieralnia (Body.Fitting).
local fitting: Frame? = nil
local productName: TextLabel? = nil
local rarityTag: Frame? = nil
local priceRow: Frame? = nil
local productPrice: TextLabel? = nil
local pricePosition = UDim2.new()
local priceShadowPosition = UDim2.new()
local needMore: TextLabel? = nil
local actionButton: TextButton? = nil
local sweep: UIGradient? = nil

-- Stan ekranu.
local opened = false
local lobby = false
local mode = "shop" -- "shop" (sprzedawca) | "wardrobe" (przycisk w HUD: tylko posiadane)
local selected: string? = nil -- przedmiot w przebieralni; nil = katalog
local tryingOn = false -- false po UNEQUIP: przebieralnia pokazuje strój bez wybranego przedmiotu
local cash = 0
local shownCash = 0
local count: { from: number, to: number, started: number }? = nil
local pending: { action: string, id: string, token: number }? = nil
local requestToken = 0
local savedHudEnabled = false
local controls: any = nil
local ownedControls = false
local animation: RBXScriptConnection? = nil
local openToken = 0 -- zmienia się przy otwarciu i zamknięciu; stara pętla połysku wie, że ma skończyć
local canShine = false
local unlockToken = 0

-- Postać w ramce katalogu (kopia w ViewportFrame).
local outfitModel: Model? = nil
local outfitAngle = 0
local outfitCenter = Vector3.zero
local outfitSize = Vector3.one
-- Postać w przebieralni (kopia na platformie sceny) i kamera.
local preview: Model? = nil
local previewBase: CFrame? = nil
local previewAngle = 0
local fittingFill: Attachment? = nil
local camera: Camera? = nil
local savedCameraType: Enum.CameraType? = nil
local savedCameraFov: number? = nil
local cameraTweens: { Tween } = {}
-- Kadr bez krążenia za myszą i odległość do punktu, wokół którego kamera krąży (jak sklep broni:
-- tween przesuwa te wartości, a na kamerę przenosi je `animate` — dwaj piszący by się szarpali).
local camBase = Instance.new("CFrameValue")
local camOrbit = Instance.new("NumberValue")
local mouseOffset = Vector2.zero
-- Przeciąganie: obraca model ramki (katalog) albo model przebieralni.
local lastDrag = 0
local dragInput: InputObject? = nil
local dragX = 0
-- Bezwładność obrotu (13.11): po puszczeniu postać kręci się jeszcze chwilę i wytraca prędkość,
-- zamiast stawać w miejscu. Prędkość (°/s) liczona z ostatnich ruchów palca/myszy.
local spinVelocity = 0
local lastMove = 0

-- Jedno miejsce, które obraca model (przebieralnia albo ramka katalogu) o `degrees`.
local function turn(degrees: number)
	if selected and preview and previewBase then
		previewAngle = (previewAngle + degrees) % 360
		preview:PivotTo(previewBase * CFrame.Angles(0, math.rad(previewAngle), 0))
	elseif outfitModel then
		outfitAngle = (outfitAngle + degrees) % 360
		outfitModel:PivotTo(CFrame.Angles(0, math.rad(outfitAngle), 0))
	end
end

-- Układ (px przy wysokości ekranu `CFG.Height`; liczy `fit`).
local layoutWidth, layoutHeight = CFG.Width, CFG.Height
local shelfWidth = CFG.Width

-- Karty: jedna tabela na kartę, czyszczona przy każdym `rebuild`.
type CardFx = { id: string?, card: GuiButton, viewport: ViewportFrame?, base: CFrame?, center: Vector3,
	available: boolean, hovered: boolean, amp: number, phase: number,
	led: UIGradient?, stars: ImageLabel?, shine: ImageLabel? }
local tiles: { Frame } = {}
local cardFx: { CardFx } = {}

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

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

-- „LED”: obrys w kolorze rzadkości z wąskim białym pasem; `animate` obraca gradient, więc pas
-- obiega ramkę. Bez pasa (`still`) — karta COMING SOON.
local function ledColors(accent: Color3, still: boolean?): ColorSequence
	if still then return ColorSequence.new(accent) end
	local w = CFG.LedBand
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, accent), ColorSequenceKeypoint.new(0.5 - w, accent),
		ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(0.5 + w, accent),
		ColorSequenceKeypoint.new(1, accent),
	})
end

local function ledOf(parent: Instance?): UIGradient?
	local led = parent and parent:FindFirstChild("Led")
	local stroke = led and led:FindFirstChild("Stroke")
	local flow = stroke and stroke:FindFirstChild("Flow")
	return if flow and flow:IsA("UIGradient") then flow else nil
end

-- Karta: sunburst z ui-resources (ImageLabel, 09.11); UNLOCKED!: belki z ramek.
local function setRays(rays: Instance?, color: Color3)
	if not rays then return end
	if rays:IsA("ImageLabel") then rays.ImageColor3 = color; return end
	for _, ray in ipairs(rays:GetChildren()) do
		if ray:IsA("Frame") then ray.BackgroundColor3 = color end
	end
end

-- Plakietka rzadkości: ta sama na karcie i w przebieralni. Szerokość z napisu, nie stała —
-- „EPIC” w ramce na „HALLOWEEN” wyglądał na pusty pasek.
local function showTag(tag: Instance?, label: string, accent: Color3)
	if not tag or not tag:IsA("GuiObject") then return end
	local text = tag:FindFirstChild("Label")
	if text and text:IsA("TextLabel") then
		text.Text = label
		local bounds = TextService:GetTextSize(label, text.TextSize, Enum.Font.FredokaOne, Vector2.new(2000, 200))
		tag.Size = UDim2.fromOffset(bounds.X + CFG.TagPadding, tag.Size.Y.Offset)
	end
	setTint(tag:FindFirstChild("Fill"), ColorSequence.new(accent, darker(accent, CFG.TagShade)))
end

-- Karta: cena na tabliczce (jeszcze nie kupione) albo napis OWNED / WEARING pod nazwą (Kacper 10.11).
-- Szerokość tabliczki z napisu, nie `AutomaticSize` (pętla rozmiaru, UI_RULES).
local function showCardState(card: Instance, def: Definitions.Definition)
	local wearing = State.equipped(def.category) == def.id
	local owned = State.owns(def.id)
	local stateLabel = card:FindFirstChild("State")
	if stateLabel and stateLabel:IsA("TextLabel") then
		stateLabel.Visible = owned
		stateLabel.Text = if wearing then "WEARING" else "OWNED"
		stateLabel.TextColor3 = if wearing then CFG.StateColors.Wearing else CFG.StateColors.Owned
	end
	local row = card:FindFirstChild("PriceRow")
	if not row or not row:IsA("GuiObject") then return end
	row.Visible = not owned
	local price = row:FindFirstChild("Price")
	if owned or not price or not price:IsA("TextLabel") then return end
	-- 13.11 (Kacper): płyta ceny jest większa; w spoczynku pokazuje cenę, po najechaniu zmienia się
	-- w BUY i klik kupuje od razu (bez przymierzania). Dotyk nie ma najechania: „BUY 750$”.
	local priceValue = Definitions.getPrice(def.id)
	local priceText = tostring(priceValue or "—") .. "$"
	local touch = not UserInputService.MouseEnabled
	local hovered = touch or row:GetAttribute("Hover") == true
	local affordable = priceValue == nil or cash >= priceValue
	local text, colors = priceText, CFG.Colors.PlatePrice
	if pending and pending.id == def.id then
		text = "..."
	elseif hovered and not affordable then
		colors = CFG.Colors.Disabled -- najechanie bez pieniędzy: cena zostaje, płyta szarzeje
	elseif hovered and State.isReady() then
		text, colors = if touch then "BUY " .. priceText else "BUY", CFG.Colors.PlateHover
	end
	price.Text = text
	price.TextSize = CFG.PlateTextSize
	setTint(row:FindFirstChild("Plate"), colors)
	row.AnchorPoint = Vector2.new(1, 1)
	local icon = row:FindFirstChild("CashIcon")
	if icon and icon:IsA("GuiObject") then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 4, 0.5, 0)
		icon.Size = UDim2.fromOffset(CFG.PlateIconSize, CFG.PlateIconSize)
	end
	local width = TextService:GetTextSize(price.Text, price.TextSize, Enum.Font.FredokaOne, Vector2.new(2000, 200)).X
	row.Size = UDim2.fromOffset(CFG.PlateIconRoom + width + CFG.PricePlatePadding, CFG.PlateHeight)
	price.Position = UDim2.fromOffset(CFG.PlateIconRoom, 0)
	price.Size = UDim2.new(0, width, 1, 0)
	local shadow = row:FindFirstChild("PriceShadow")
	if shadow and shadow:IsA("TextLabel") then
		shadow.Text = price.Text
		shadow.TextSize = CFG.PlateTextSize
		shadow.Position = UDim2.fromOffset(CFG.PlateIconRoom - 3, 3)
		shadow.Size = price.Size
	end
end

-- Przebieralnia: cena napisem z ikoną, OWNED / WEARING w tym samym miejscu.
local function showFittingPrice(def: Definitions.Definition)
	local row, price = priceRow, productPrice
	if not row or not price then return end
	local wearing = State.equipped(def.category) == def.id
	local owned = State.owns(def.id)
	price.Text = if wearing then "WEARING" elseif owned then "OWNED"
		else tostring(Definitions.getPrice(def.id) or "—") .. "$"
	setTint(price, if wearing then CFG.Colors.Wearing elseif owned then CFG.Colors.Owned else CFG.Colors.Price)
	local icon = row:FindFirstChild("CashIcon")
	if icon and icon:IsA("GuiObject") then icon.Visible = not owned end
	-- Without the cash icon (OWNED/WEARING) the word starts where the icon was.
	local shift = if owned then -pricePosition.X.Offset else 0
	price.Position = pricePosition + UDim2.fromOffset(shift, 0)
	local shadow = row:FindFirstChild("PriceShadow")
	if shadow and shadow:IsA("GuiObject") then shadow.Position = priceShadowPosition + UDim2.fromOffset(shift, 0) end
end

local function updateButton()
	-- Drzewko u maga (10.11, Kacper): przycisk COSMETICS znika na czas panelu.
	if button then
		button.Visible = lobby and not Shop.isOpen() and not opened
			and player:GetAttribute(Config.Skills.OpenAttribute) ~= true
	end
end

-- Reakcja jak w sklepie broni (ShopFx, 09.11): jedna skala `Hover` liczona z `hovered` + `pressed`.
-- `MouseEnter` z palca ignorujemy (na dotyku `MouseLeave` nie przychodzi i przycisk zostawałby
-- powiększony), a `pressed` zdejmuje globalny `InputEnded`, bo puszczenie poza przyciskiem nie daje
-- `MouseButton1Up`. Karty mają osobną listę, czyszczoną przy każdym `rebuild`.
type Reactive = { scale: UIScale, hovered: boolean, pressed: boolean, hover: number, press: number }
local buttons: { Reactive } = {}
local cardButtons: { Reactive } = {}
local HOVER_INFO = TweenInfo.new(CFG.HoverTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(CFG.PressTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function settle(b: Reactive)
	local target = if b.pressed then b.press elseif b.hovered then b.hover else 1
	TweenService:Create(b.scale, if b.pressed then PRESS_INFO else HOVER_INFO, { Scale = target }):Play()
end

local function react(btn: GuiButton, hoverScale: number, pressScale: number, list: { Reactive })
	local scale = btn:FindFirstChild("Hover")
	if not scale or not scale:IsA("UIScale") then return end
	local b: Reactive = { scale = scale, hovered = false, pressed = false, hover = hoverScale, press = pressScale }
	table.insert(list, b)
	btn.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		b.hovered = true
		settle(b)
	end)
	btn.MouseLeave:Connect(function()
		b.hovered, b.pressed = false, false
		settle(b)
	end)
	btn.MouseButton1Down:Connect(function()
		b.pressed = true
		settle(b)
	end)
end

local function releaseAll()
	for _, list in ipairs({ buttons, cardButtons }) do
		for _, b in ipairs(list) do
			if b.pressed then b.pressed = false; settle(b) end
		end
	end
end

-- Schowany przycisk (katalog przy przejściu do przebieralni, całe GUI przy zamknięciu) nie dostaje
-- `MouseLeave` — bez tego po powrocie karta albo X stałyby powiększone.
local function resetReactive()
	for _, list in ipairs({ buttons, cardButtons }) do
		for _, b in ipairs(list) do
			b.hovered, b.pressed = false, false
			b.scale.Scale = 1
		end
	end
	for _, fx in ipairs(cardFx) do fx.hovered = false end
end

-- Odmowa zakupu / klik w COMING SOON: drga jak w sklepie broni.
local function shake(obj: GuiObject?)
	if not obj then return end
	obj.Rotation = 0
	local info = TweenInfo.new(CFG.ShakeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	TweenService:Create(obj, info, { Rotation = CFG.ShakeDegrees }):Play()
end

-- Połysk przelatuje po BUY co `ShineInterval`, tylko gdy przedmiot jest do kupienia i gracza na niego stać.
local function shineLoop(token: number)
	local info = TweenInfo.new(CFG.ShineTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	while token == openToken do
		task.wait(CFG.ShineInterval)
		local gradient = sweep
		if token == openToken and canShine and gradient then
			gradient.Offset = Vector2.new(-CFG.ShineOffset, 0)
			TweenService:Create(gradient, info, { Offset = Vector2.new(CFG.ShineOffset, 0) }):Play()
		end
	end
end

-- Błysk z ui-resources przelatuje po karcie, kiedy najedziesz na nią myszką.
local function flash(image: ImageLabel?)
	if not image then return end
	image.Position = UDim2.fromScale(-0.3, 0.25)
	image.Visible = true
	local tween = TweenService:Create(image, TweenInfo.new(CFG.CardShineTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(1.3, 0.75) })
	tween.Completed:Connect(function() image.Visible = false end)
	tween:Play()
end

-- ============================================================================
-- Postać w ramce katalogu (lokalna kopia w ViewportFrame, obecny strój)
-- ============================================================================

local function destroyOutfit()
	if outfitModel then
		local world = outfitModel.Parent
		outfitModel:Destroy()
		if world and world:IsA("WorldModel") then world:Destroy() end
		outfitModel = nil
	end
end

-- Kadr liczony raz z postaci przodem do kamery; obrót postaci go nie zmienia, więc nic nie skacze.
local function frameCamera()
	local vp = view
	if not vp or not outfitModel then return end
	local cam = vp.CurrentCamera
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = vp
		vp.CurrentCamera = cam
	end
	local viewCamera = cam :: Camera
	viewCamera.FieldOfView = CFG.ViewFov
	local half = math.tan(math.rad(CFG.ViewFov / 2))
	-- Tuż po włączeniu GUI rozmiar bywa jeszcze 0 — wtedy proporcje z układu, a po przeliczeniu
	-- kadr poprawi sygnał `AbsoluteSize` (init).
	local aspect = if vp.AbsoluteSize.Y >= 1 then vp.AbsoluteSize.X / vp.AbsoluteSize.Y else 0.6
	local radius = math.max(outfitSize.X, outfitSize.Z) / 2
	local shift = outfitSize.Y * CFG.ViewShift
	local distance = math.max((outfitSize.Y / 2 + shift) / half, radius / (half * math.max(aspect, 0.1))) * CFG.ViewMargin
	local focus = outfitCenter - Vector3.new(0, shift, 0)
	-- Model stoi przodem do −Z (PivotTo(identity)), więc kamera patrzy od −Z.
	viewCamera.CFrame = CFrame.lookAt(focus + Vector3.new(0, 0, -distance), focus)
end

local function buildOutfit()
	destroyOutfit()
	local vp = view
	if not vp then return end
	local model = Preview.character(false)
	if not model then return end
	model:PivotTo(CFrame.identity)
	pcall(Preview.outfit, model, State.outfit(), nil)
	local box, size = model:GetBoundingBox()
	outfitCenter, outfitSize = box.Position, size
	local world = Instance.new("WorldModel")
	model.Parent = world
	world.Parent = vp
	outfitModel = model
	outfitAngle = 0
	spinVelocity = 0
	frameCamera()
end

-- ============================================================================
-- Przebieralnia ze sceną (lokalna kopia na platformie + kamera Scriptable)
-- ============================================================================

local function restoreCamera()
	dragInput = nil
	spinVelocity = 0
	for _, tween in ipairs(cameraTweens) do tween:Cancel() end
	table.clear(cameraTweens)
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
	spinVelocity = 0
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
	-- Oko wyżej niż środek postaci i patrzy poziomo, na wprost (Kacper 12.11).
	local eye = box.Position + Vector3.new(0, bounds.Y * CFG.FittingEyeOffset, 0)
	local aspect = cam.ViewportSize.X / math.max(1, cam.ViewportSize.Y)
	local distance = math.max(bounds.Y / CFG.FittingHeightFraction, math.max(bounds.X, bounds.Z) / math.max(aspect, 0.1)) / (2 * math.tan(math.rad(CFG.CameraFov / 2)))
	-- Optional authored marker overrides the automatic front view without code changes.
	local scene = workspace:FindFirstChild(Config.Cosmetics.SceneName)
	local marker = scene and scene:FindFirstChild("CosmeticsCamera", true)
	local target = if marker and marker:IsA("BasePart") then marker.CFrame
		else CFrame.lookAt(eye + base.LookVector * distance, eye)
	for _, tween in ipairs(cameraTweens) do tween:Cancel() end
	table.clear(cameraTweens)
	cam.FieldOfView = CFG.CameraFov
	-- Wjazd z obecnego kadru; dalej kamerę pisze `animate` (krążenie za myszą wokół postaci).
	if not selected then camBase.Value = cam.CFrame end
	camOrbit.Value = (target.Position - box.Position).Magnitude
	local info = TweenInfo.new(CFG.OpenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	cameraTweens = { TweenService:Create(camBase, info, { Value = target }) }
	cameraTweens[1]:Play()
	mouseOffset = Vector2.zero
	return true
end

-- Katalog i przebieralnia to dwa widoki tego samego GUI; tło katalogu zasłania scenę.
local function showCatalog(visible: boolean)
	for _, object in ipairs({ dressing, shelf, title, titleShadow, closeButton } :: { GuiObject? }) do
		if object then object.Visible = visible end
	end
	if fitting then fitting.Visible = not visible end
	if backdrop then
		backdrop.BackgroundTransparency = if visible then CFG.BackdropTransparency else 1
		for _, child in ipairs(backdrop:GetChildren()) do
			if child:IsA("GuiObject") then child.Visible = visible end
		end
	end
end

local function choose(id: string)
	if not opened or not lobby then return end
	if not Definitions.getTemplate(id) then say("THIS COSMETIC IS COMING SOON"); return end
	if not dress(id) then return end
	selected, tryingOn = id, true
	resetReactive()
	showCatalog(false)
	say("")
	refresh()
end

local function back()
	selected, tryingOn = nil, false
	resetReactive()
	restoreCamera()
	showCatalog(true)
	say("")
	refresh()
end

-- Zakup prosto z płyty ceny na karcie (13.11): bez przymierzania, serwer waliduje jak zawsze.
local function quickBuy(id: string, plate: GuiObject?)
	if pending or not opened or not lobby or not State.isReady() or State.owns(id) then return end
	if not Definitions.getTemplate(id) then say("THIS COSMETIC IS COMING SOON"); return end
	local price = Definitions.getPrice(id)
	if price and cash < price then
		shake(plate)
		ShopFx.feedback("Fail")
		say(("NEED %d$ MORE"):format(price - cash))
		return
	end
	ShopFx.feedback("Press")
	requestToken += 1
	local token = requestToken
	pending = { action = "buy", id = id, token = token }
	Remotes.BuyCosmetic:FireServer(id)
	refresh()
	task.delay(CFG.RequestTimeout, function()
		if pending and pending.token == token then
			pending = nil
			if opened then say("NO RESPONSE — PLEASE TRY AGAIN"); refresh() end
		end
	end)
end

-- ============================================================================
-- Karty
-- ============================================================================

local function hookCard(fx: CardFx, onClick: () -> ())
	local card = fx.card
	card.MouseEnter:Connect(function()
		fx.hovered = true
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then flash(fx.shine) end
	end)
	card.MouseLeave:Connect(function() fx.hovered = false end)
	card.Activated:Connect(onClick)
	react(card, CFG.CardHoverScale, CFG.CardPressScale, cardButtons)
end

local function paintCard(card: Instance, look: any)
	local accent: Color3 = look.Accent
	local fill = card:FindFirstChild("Fill")
	local fillGradient = fill and fill:FindFirstChild("Gradient")
	if fillGradient and fillGradient:IsA("UIGradient") then fillGradient.Color = look.Fill end
	local art = card:FindFirstChild("Art")
	setRays(art and art:FindFirstChild("Rays"), accent)
	-- Okrągły półton za przedmiotem (ui-resources, v6c) — akcent rozjaśniony, inaczej ginie na karcie.
	local halftone = card:FindFirstChild("RoundHalftone")
	if halftone and halftone:IsA("ImageLabel") then halftone.ImageColor3 = accent:Lerp(WHITE, CFG.HalftoneLighten) end
	showTag(card:FindFirstChild("RarityTag"), look.Label, accent)
end

local function setupCard(tile: Frame, def: Definitions.Definition): CardFx
	local card = tile:FindFirstChild("Card") :: TextButton
	local rarity = rarityOf(def)
	paintCard(card, rarity)
	local stars = card:FindFirstChild("Stars")
	local starImage = if stars and stars:IsA("ImageLabel") then stars else nil
	if starImage then
		starImage.Visible = rarity.Stars
		starImage.ImageColor3 = rarity.Accent:Lerp(WHITE, 0.55)
	end
	local nameLabel = card:FindFirstChild("ItemName") :: TextLabel
	nameLabel.Text = def.name:upper()
	for _, name in ipairs({ "Mystery", "Lock" }) do
		local o = card:FindFirstChild(name)
		if o and o:IsA("GuiObject") then o.Visible = false end
	end
	local viewport = card:FindFirstChild("Preview") :: ViewportFrame
	local available, center = Preview.card(viewport, def.id)
	local unavailable = card:FindFirstChild("Unavailable")
	if unavailable and unavailable:IsA("GuiObject") then unavailable.Visible = not available end
	local led = ledOf(card)
	if led then led.Color = ledColors(rarity.Accent) end
	local shine = card:FindFirstChild("ShineFx")
	local fx: CardFx = { id = def.id, card = card, viewport = viewport,
		base = viewport.CurrentCamera and viewport.CurrentCamera.CFrame, center = center,
		available = available, hovered = false, amp = 0, phase = 0, led = led, stars = starImage,
		shine = if shine and shine:IsA("ImageLabel") then shine else nil }
	local id = def.id
	hookCard(fx, function() ShopFx.feedback("Press"); choose(id) end)
	-- Płyta ceny jest osobnym przyciskiem: najechanie zmienia ją w BUY, klik kupuje od razu.
	local plate = card:FindFirstChild("PriceRow")
	if plate and plate:IsA("GuiObject") then
		local hit = Instance.new("TextButton")
		hit.Name = "BuyHit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 30
		hit.Parent = plate
		hit.MouseEnter:Connect(function()
			if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
			plate:SetAttribute("Hover", true)
			showCardState(card, def)
		end)
		hit.MouseLeave:Connect(function()
			plate:SetAttribute("Hover", false)
			showCardState(card, def)
		end)
		hit.Activated:Connect(function() quickBuy(id, plate) end)
	end
	-- Nazwa kończy się przed większą płytą ceny.
	for _, name in ipairs({ "ItemName", "ItemNameShadow" }) do
		local label = card:FindFirstChild(name)
		if label and label:IsA("GuiObject") then label.Size = UDim2.new(1, -CFG.PlateNameReserve, 0, label.Size.Y.Offset) end
	end
	showCardState(card, def)
	return fx
end

-- COMING SOON (Kacper 10.11: „dodaj więcej itemów, placeholder na razie”): wygląda jak karta,
-- nie da się jej kupić ani przymierzyć. Liczba w `PlaceholderCount`.
local function setupPlaceholder(tile: Frame): CardFx
	local card = tile:FindFirstChild("Card") :: TextButton
	paintCard(card, CFG.Placeholder)
	for _, name in ipairs({ "Preview", "Unavailable", "Stars", "PriceRow", "State" }) do
		local o = card:FindFirstChild(name)
		if o and o:IsA("GuiObject") then o.Visible = false end
	end
	for _, name in ipairs({ "Mystery", "Lock" }) do
		local o = card:FindFirstChild(name)
		if o and o:IsA("GuiObject") then o.Visible = true end
	end
	local nameLabel = card:FindFirstChild("ItemName") :: TextLabel
	nameLabel.Text = "???"
	local led = ledOf(card)
	if led then led.Color = ledColors(CFG.Placeholder.Accent, true) end
	local fx: CardFx = { id = nil, card = card, viewport = nil, base = nil, center = Vector3.zero,
		available = false, hovered = false, amp = 0, phase = 0, led = nil, stars = nil, shine = nil }
	hookCard(fx, function()
		shake(card)
		ShopFx.feedback("Fail")
		say("COMING SOON")
	end)
	return fx
end

rebuild = function()
	if not scroll or not template then return end
	for _, tile in ipairs(tiles) do tile:Destroy() end
	table.clear(tiles)
	table.clear(cardFx)
	table.clear(cardButtons)
	local gap, pad = CFG.CardGap, CFG.CardPadding
	-- Szerokość `Items` = panel bez wcięcia (6 px z każdej strony) i paska przewijania.
	local inner = shelfWidth - 12 - CFG.ScrollBar - pad * 2
	local columns = math.clamp(math.floor((inner + gap) / (CFG.MinCard + gap)), CFG.MinColumns, CFG.MaxColumns)
	local cellW = (inner - gap * (columns - 1)) / columns
	local cellH = cellW * CFG.CardAspect
	local entries: { string | false } = {}
	for _, id in ipairs(Definitions.shopOrder) do
		if Definitions.get(id) and (mode == "shop" or State.owns(id)) then table.insert(entries, id) end
	end
	local realCount = #entries
	if mode == "shop" then
		for _ = 1, CFG.PlaceholderCount do table.insert(entries, false) end
	end
	for i, entry in ipairs(entries) do
		local row, col = (i - 1) // columns, (i - 1) % columns
		local tile = template:Clone()
		tile.Name = if entry then entry else "ComingSoon" .. (i - realCount)
		tile.Visible = true
		tile.Position = UDim2.fromOffset(pad + col * (cellW + gap), pad + row * (cellH + gap))
		tile.Size = UDim2.fromOffset(cellW, cellH)
		local def = if entry then Definitions.get(entry) else nil
		table.insert(cardFx, if def then setupCard(tile, def) else setupPlaceholder(tile))
		tile.Parent = scroll
		table.insert(tiles, tile)
	end
	local rows = math.ceil(#entries / columns)
	scroll.CanvasSize = UDim2.fromOffset(0, if rows > 0 then pad * 2 + rows * (cellH + gap) - gap else 0)
	if empty then empty.Visible = realCount == 0 end
end

refresh = function()
	if balance then balance.Text = tostring(shownCash) .. "$" end
	if title then title.Text = if mode == "shop" then "COSMETICS" else "WARDROBE" end
	for _, tile in ipairs(tiles) do
		local def = Definitions.get(tile.Name)
		local card = tile:FindFirstChild("Card")
		if card and def then showCardState(card, def) end
	end
	local def = if selected then Definitions.get(selected) else nil
	canShine = false
	if not def then return end
	local rarity = rarityOf(def)
	if productName then productName.Text = def.name:upper() end
	showTag(rarityTag, rarity.Label, rarity.Accent)
	showFittingPrice(def)
	-- Turn "can't afford" into a goal: how much is missing and how many survived rounds pay it.
	local price = Definitions.getPrice(def.id)
	local owned = State.owns(def.id)
	local missing = if price and not owned then price - cash else 0
	if needMore then
		needMore.Visible = missing > 0
		if missing > 0 then
			local rounds = math.ceil(missing / math.max(1, Config.Rewards.Win))
			needMore.Text = ("NEED %d$ MORE — SURVIVE %d ROUND%s"):format(missing, rounds, if rounds == 1 then "" else "S")
		end
	end
	canShine = State.isReady() and pending == nil and missing <= 0 and not owned
	if actionButton then
		local active = State.equipped(def.category) == def.id
		local ready = State.isReady() and pending == nil
		actionButton.Text = if pending then "..." elseif not State.isReady() then "LOADING..."
			elseif active then "UNEQUIP" elseif owned then "EQUIP" else "BUY"
		actionButton.Active = ready
		local surface = actionButton:FindFirstChild("Surface")
		local gradient = surface and surface:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = if not ready or missing > 0 then CFG.Colors.Disabled
				elseif active then CFG.Colors.Unequip elseif owned then CFG.Colors.Equip else CFG.Colors.Buy
		end
	end
end

-- Gdzie jest kursor względem środka ekranu (-1…1). Na dotyku i padzie kursora nie ma, więc kamera
-- wraca na środek zamiast krążyć wokół ostatniego palca (jak `ShopController`).
local function mouseTarget(cam: Camera): Vector2
	local last = UserInputService:GetLastInputType()
	if not UserInputService.MouseEnabled or last == Enum.UserInputType.Touch or last.Name:sub(1, 7) == "Gamepad" then
		return Vector2.zero
	end
	local at = UserInputService:GetMouseLocation()
	local size = cam.ViewportSize
	return Vector2.new(math.clamp(at.X / size.X * 2 - 1, -1, 1), math.clamp(at.Y / size.Y * 2 - 1, -1, 1))
end

local function animate(dt: number)
	local now = os.clock()
	if count then
		local t = math.clamp((now - count.started) / CFG.CashCountTime, 0, 1)
		shownCash = math.round(count.from + (count.to - count.from) * t)
		if t >= 1 then count = nil end
		if balance then balance.Text = tostring(shownCash) .. "$" end
	end
	-- Bezwładność obrotu: trzymany, ale nieruszany palec zeruje prędkość (postać ma stać);
	-- puszczony po ruchu — kręci się dalej i wytraca prędkość wykładniczo.
	if dragInput then
		if now - lastMove > CFG.SpinHoldTime then spinVelocity = 0 end
	elseif spinVelocity ~= 0 then
		if math.abs(spinVelocity) < CFG.SpinStopVelocity then
			spinVelocity = 0
		else
			turn(spinVelocity * dt)
			spinVelocity *= math.exp(-CFG.SpinFriction * dt)
			lastDrag = now -- samoobrót wraca dopiero po `FittingSpinDelay` od zatrzymania
		end
	end
	if not selected then
		if titleFlow then
			titleFlow.Color = LobbySign.sequence(Config.Cosmetics.SignFlowColors, Config.Cosmetics.SignFlowSpan, now * Config.Cosmetics.SignFlowSpeed)
		end
		if frameLed then frameLed.Rotation = (frameLed.Rotation + dt * CFG.LedSpeed) % 360 end
		local twinkle = 0.15 + 0.6 * (1 - math.cos(now * 2 * math.pi / CFG.StarsPeriod)) / 2
		for _, fx in ipairs(cardFx) do
			if fx.led then fx.led.Rotation = (fx.led.Rotation + dt * CFG.LedSpeed) % 360 end
			if fx.stars and fx.stars.Visible then fx.stars.ImageTransparency = twinkle end
			local target = if fx.hovered then 1 else 0
			fx.amp += (target - fx.amp) * math.min(1, dt * CFG.SwayEase)
			if fx.amp < 0.001 then continue end
			fx.phase += dt * CFG.CardSwaySpeed
			-- Sway, not a full turn: the front of a hat or vest is what sells it.
			local vp = fx.viewport
			local cam = vp and vp.CurrentCamera
			if fx.available and cam and fx.base then
				local yaw = math.rad(math.sin(fx.phase) * CFG.CardSwayDegrees * fx.amp)
				cam.CFrame = CFrame.lookAt(fx.center + CFrame.Angles(0, yaw, 0) * (fx.base.Position - fx.center), fx.center)
			end
		end
		-- Postać w ramce kręci się sama, dopóki gracz jej nie przeciąga.
		if outfitModel and not dragInput and now - lastDrag > CFG.FittingSpinDelay then
			outfitAngle = (outfitAngle + dt * CFG.FittingSpinSpeed) % 360
			outfitModel:PivotTo(CFrame.Angles(0, math.rad(outfitAngle), 0))
		end
	else
		-- Przebieralnia: kamera krąży lekko za myszą wokół postaci (jak sklep broni, 12.11).
		local cam = camera
		if cam then
			local parallax = CFG.FittingParallax
			mouseOffset = mouseOffset:Lerp(mouseTarget(cam), 1 - math.exp(-parallax.Rate * dt))
			local pitch = math.rad(parallax.PitchDegrees) * mouseOffset.Y
			local yaw = math.rad(parallax.YawDegrees) * mouseOffset.X
			cam.CFrame = camBase.Value * CFrame.new(0, 0, -camOrbit.Value) * CFrame.Angles(pitch, yaw, 0)
				* CFrame.new(0, 0, camOrbit.Value)
		end
		if preview and previewBase and not dragInput and now - lastDrag > CFG.FittingSpinDelay then
			-- Idle turntable in the fitting room (shows the backpack's back) until the player drags.
			previewAngle = (previewAngle + dt * CFG.FittingSpinSpeed) % 360
			preview:PivotTo(previewBase * CFrame.Angles(0, math.rad(previewAngle), 0))
		end
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
		name.TextColor3 = rarity.Accent
	end
	local rays = popup:FindFirstChild("Rays")
	setRays(rays, rarity.Accent)
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

close = function()
	if not opened then return end
	opened = false
	openToken += 1
	canShine = false
	releaseAll()
	if animation then animation:Disconnect(); animation = nil end
	count, shownCash = nil, cash
	unlockToken += 1
	if unlocked then unlocked.Visible = false end
	if hudGui then hudGui.Enabled = savedHudEnabled end
	selected, tryingOn = nil, false
	restoreCamera()
	destroyOutfit()
	if gui then gui.Enabled = false end
	if ownedControls and controls then controls:Enable() end
	ownedControls = false
	player:SetAttribute("CosmeticsOpen", false)
	updateButton()
end

local function open(which: string)
	if opened or not lobby or Shop.isOpen() or not gui or not dressing or not shelf or not fitting then return end
	if player:GetAttribute(Config.Skills.OpenAttribute) == true then return end -- drzewko u maga (09.11)
	if not controls then
		local ps = player:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm then
			local ok, result = pcall(function() return (require(pm) :: any):GetControls() end)
			if ok then controls = result end
		end
	end
	-- require(PlayerModule) may yield: revalidate the lobby before acquiring the UI.
	if opened or not lobby or Shop.isOpen() then return end
	opened, mode = true, which
	selected, tryingOn = nil, false
	resetReactive()
	if hudGui then savedHudEnabled = hudGui.Enabled; hudGui.Enabled = false end
	player:SetAttribute("CosmeticsOpen", true)
	if controls then controls:Disable(); ownedControls = true end
	gui.Enabled = true
	showCatalog(true)
	if scroll then scroll.CanvasPosition = Vector2.zero end
	if not animation then animation = RunService.RenderStepped:Connect(animate) end
	rebuild()
	buildOutfit()
	refresh()
	openToken += 1
	task.spawn(shineLoop, openToken)
	say(if State.isReady() then "" else "LOADING YOUR WARDROBE...")
	updateButton()
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

-- Układ katalogu liczony z ekranu: poziomo ramka po lewej, karty po prawej; pionowo ramka na
-- górze, karty pod nią. `Root.Fit` skaluje całość do wysokości (pion: szerokości) ekranu.
-- Przebieralnia ma własny układ z placu (pełny ekran).
local function fit()
	if not (fitScale and gui and root and dressing and shelf) then return end
	local abs = gui.AbsoluteSize
	local portrait = abs.X < abs.Y
	local factor = math.max(0.1, if portrait then abs.X / CFG.PortraitWidth else abs.Y / CFG.Height)
	layoutWidth, layoutHeight = abs.X / factor, abs.Y / factor
	root.Size = UDim2.fromOffset(layoutWidth, layoutHeight)
	fitScale.Scale = factor
	local margin, top, gap = CFG.Margin, CFG.Top, CFG.ColumnGap
	local below = layoutHeight - top - margin
	local titleX: number
	if portrait then
		local dressH = math.floor(below * CFG.PortraitDressingShare)
		dressing.Position = UDim2.fromOffset(margin, top)
		dressing.Size = UDim2.fromOffset(layoutWidth - margin * 2, dressH)
		shelf.Position = UDim2.fromOffset(margin, top + dressH + gap)
		shelfWidth = layoutWidth - margin * 2
		shelf.Size = UDim2.fromOffset(shelfWidth, below - dressH - gap)
		titleX = layoutWidth / 2
	else
		dressing.Position = UDim2.fromOffset(margin, top)
		dressing.Size = UDim2.fromOffset(CFG.DressingWidth, below)
		local shelfX = margin + CFG.DressingWidth + gap
		shelfWidth = layoutWidth - shelfX - margin
		shelf.Position = UDim2.fromOffset(shelfX, top)
		shelf.Size = UDim2.fromOffset(shelfWidth, below)
		titleX = shelfX + shelfWidth / 2
	end
	if wallet then
		wallet.Position = UDim2.fromOffset(margin, math.max(24, CFG.BalanceSafeTopPixels / factor))
	end
	-- Tytuł i X nad panelem, nie na jego krawędzi.
	if closeButton then
		closeButton.Position = UDim2.fromOffset(layoutWidth - margin - closeButton.Size.X.Offset, CFG.HeaderY)
	end
	if title then
		title.TextSize = if portrait then 54 else 76
		title.Position = UDim2.fromOffset(titleX, CFG.HeaderY - 6)
		if titleShadow then
			titleShadow.TextSize = title.TextSize
			titleShadow.Position = title.Position + UDim2.fromOffset(-3, 3)
		end
	end
	if opened then rebuild(); refresh(); frameCamera() end
end

-- Przeciąganie myszą / palcem obraca postać w ramce (katalog) albo na platformie (przebieralnia).
local function rotateBy(dx: number, width: number)
	local degrees = dx / math.max(1, width) * CFG.DragDegrees
	local now = os.clock()
	-- Wygładzona prędkość chwilowa; ucięta, żeby jeden skok myszy nie wystrzelił postaci.
	local dt = math.max(now - lastMove, 1 / 240)
	local instant = math.clamp(degrees / dt, -CFG.SpinMaxVelocity, CFG.SpinMaxVelocity)
	spinVelocity = spinVelocity + (instant - spinVelocity) * 0.4
	lastMove = now
	lastDrag = now
	turn(degrees)
end

local function dragFrom(area: GuiObject)
	area.InputBegan:Connect(function(input)
		if dragInput or not (preview or outfitModel) then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
			dragX = input.Position.X
			spinVelocity = 0 -- złapanie postaci zatrzymuje wybieg
			lastMove = os.clock()
			lastDrag = os.clock()
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
		if outfitModel then Preview.outfit(outfitModel, State.outfit(), nil) end
		if preview and selected then Preview.outfit(preview, State.outfit(), if tryingOn then selected else nil) end
		refresh()
	end)
	-- „Lobby” liczone per gracz: pomijający rundę stoi w lobby także w jej trakcie (06.11). Stąd
	-- prompt straganu ustawiany tutaj, u siebie; serwer zostawia go włączonego i waliduje zakup.
	local gameState = ""
	local function refreshLobby()
		lobby = gameState == "LOBBY" or RoundSkip.isSittingOut()
		if not lobby then close() end
		updateButton()
		local lobbyFolder = workspace:FindFirstChild("Lobby")
		local prompt = lobbyFolder and lobbyFolder:FindFirstChild(Config.Cosmetics.PromptName, true)
		if prompt and prompt:IsA("ProximityPrompt") then prompt.Enabled = lobby end
	end
	RoundSkip.onChanged(refreshLobby)
	Remotes.GameStateChanged.OnClientEvent:Connect(function(state: any)
		gameState = state
		refreshLobby()
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
		if bought then celebrate(bought); ShopFx.feedback("Buy") end
		if not success then shake(actionButton); ShopFx.feedback("Fail") end
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
	player:GetAttributeChangedSignal(Config.Skills.OpenAttribute):Connect(updateButton)
	-- COSMETICS sign above the seller: HUD-button colours flow through the letters, same as
	-- SHOP (LobbySign, 03.11).
	task.spawn(function()
		local lobbyFolder = workspace:WaitForChild("Lobby", 30)
		local sign = lobbyFolder and lobbyFolder:FindFirstChild(Config.Cosmetics.SignName, true)
		local label = sign and sign:FindFirstChild("Label")
		local grad = label and label:FindFirstChildOfClass("UIGradient")
		if not (sign and sign:IsA("BillboardGui") and grad) then
			warn("[Cosmetics] missing Lobby." .. Config.Cosmetics.SignName .. ".Label.UIGradient — sign stays static")
			return
		end
		LobbySign.start(sign :: BillboardGui, grad, Config.Cosmetics.SignFlowColors, Config.Cosmetics.SignFlowSpeed, Config.Cosmetics.SignFlowSpan)
	end)
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
				local labelShadow = object:FindFirstChild("LabelShadow")
				local function syncLabel()
					label.Text = object.Text
					if labelShadow and labelShadow:IsA("TextLabel") then labelShadow.Text = object.Text end
				end
				syncLabel()
				object:GetPropertyChangedSignal("Text"):Connect(syncLabel)
			end
		end
		backdrop = gui:FindFirstChild("Backdrop") :: TextButton
		root = gui:FindFirstChild("Root") :: Frame
		local b = (root :: Frame):FindFirstChild("Body") :: Frame
		body = b
		local dressingFrame = b:FindFirstChild("Dressing")
		local shelfFrame = b:FindFirstChild("Shelf")
		local fittingFrame = b:FindFirstChild("Fitting")
		if not (dressingFrame and dressingFrame:IsA("Frame") and shelfFrame and shelfFrame:IsA("Frame")
			and fittingFrame and fittingFrame:IsA("Frame")) then
			-- Plac sprzed v6c (bez Dressing/Shelf/Fitting): sklep się nie otworzy, zamiast rzucać błędami.
			warn("[Cosmetics] StarterGui.Cosmetics needs Body.Dressing, Body.Shelf and Body.Fitting (shop_v6c) — shop disabled")
			return
		end
		dressing, shelf, fitting = dressingFrame, shelfFrame, fittingFrame
		frame = dressingFrame:FindFirstChild("Frame") :: Frame
		view = (frame :: Frame):FindFirstChild("View") :: ViewportFrame
		frameLed = ledOf(frame)
		if frameLed then frameLed.Color = ledColors(Config.Cosmetics.SignFlowColors[1]) end
		scroll = shelfFrame:FindFirstChild("Items") :: ScrollingFrame
		empty = shelfFrame:FindFirstChild("Empty") :: TextLabel
		template = gui:FindFirstChild("CardTemplate") :: Frame
		title = b:FindFirstChild("Title") :: TextLabel
		titleShadow = b:FindFirstChild("TitleShadow") :: TextLabel
		titleFlow = title and title:FindFirstChildOfClass("UIGradient")
		closeButton = b:FindFirstChild("CloseButton") :: GuiButton
		wallet = b:FindFirstChild("Cash") :: Frame
		balance = (wallet :: any).Body:FindFirstChild("CashLabel") :: TextLabel
		status = b:FindFirstChild("Status") :: TextLabel
		unlocked = b:FindFirstChild("Unlocked") :: Frame
		productName = fittingFrame:FindFirstChild("ItemName") :: TextLabel
		rarityTag = fittingFrame:FindFirstChild("RarityTag") :: Frame
		local row = fittingFrame:FindFirstChild("PriceRow") :: Frame
		priceRow = row
		local fittingPrice = row:FindFirstChild("Price") :: TextLabel
		productPrice = fittingPrice
		pricePosition = fittingPrice.Position
		local fittingPriceShadow = row:FindFirstChild("PriceShadow")
		if fittingPriceShadow and fittingPriceShadow:IsA("GuiObject") then priceShadowPosition = fittingPriceShadow.Position end
		needMore = fittingFrame:FindFirstChild("NeedMore") :: TextLabel
		actionButton = fittingFrame:FindFirstChild("ActionButton") :: TextButton
		fitScale = (root :: Frame):FindFirstChild("Fit") :: UIScale
		fit()
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		;(view :: ViewportFrame):GetPropertyChangedSignal("AbsoluteSize"):Connect(frameCamera)
		local x = closeButton :: GuiButton
		local backButton = fittingFrame:FindFirstChild("BackButton") :: GuiButton
		local backSurface = backButton:FindFirstChild("Surface")
		local backGradient = backSurface and backSurface:FindFirstChildOfClass("UIGradient")
		if backGradient then backGradient.Color = CFG.Colors.Back end -- 12.11: gradient z Config, nie z placu
		local buy = actionButton :: TextButton
		x.Activated:Connect(function() ShopFx.feedback("Press"); close() end)
		backButton.Activated:Connect(function() ShopFx.feedback("Press"); back() end)
		buy.Activated:Connect(function() ShopFx.feedback("Press"); act() end)
		for _, btn in ipairs({ x, backButton, buy } :: { GuiButton }) do
			react(btn, CFG.ButtonHoverScale, CFG.ButtonPressScale, buttons)
		end
		local surface = buy:FindFirstChild("Surface")
		local sweepFrame = surface and surface:FindFirstChild("Sweep")
		local sweepGradient = sweepFrame and sweepFrame:FindFirstChildOfClass("UIGradient")
		if sweepGradient then
			sweep = sweepGradient
			sweepGradient.Offset = Vector2.new(-CFG.ShineOffset, 0)
			-- 13.11: połysk przechodzący po BUY jest jasną zielenią, nie czystą bielą.
			sweepGradient.Color = ColorSequence.new(Color3.fromRGB(150, 255, 175))
		end
		UserInputService.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then releaseAll() end
		end)
		local rotateArea = fittingFrame:FindFirstChild("RotateArea") :: GuiObject
		dragFrom(frame :: Frame)
		dragFrom(rotateArea)
		UserInputService.InputChanged:Connect(function(input)
			if not dragInput then return end
			local mouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			if (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) or input == dragInput then
				local dx = input.Position.X - dragX
				dragX = input.Position.X
				rotateBy(dx, if selected then rotateArea.AbsoluteSize.X else (frame :: Frame).AbsoluteSize.X)
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
		if btn and btn:IsA("GuiButton") then
			button = btn
			HudButtonFx.hook(btn) -- hover rośnie jak INVENTORY (13.11)
			btn.Activated:Connect(function() open("wardrobe") end)
		end
		updateButton()
		refresh()
	end)
end
return Controller
