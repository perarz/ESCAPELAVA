--!strict
-- ShopFx.luau (06.11) — mikroanimacje, wibracje i dźwięki panelu sklepu (Kacper: „więcej haptyki,
-- mikroanimacji”). Wygląd panelu stoi w Studio, stan sklepu i kamerę trzyma ShopController;
-- tu są tylko reakcje na jego wywołania. Helper bez `init`. Brak elementu w placu = brak efektu,
-- nigdy błąd: animacja nie może zablokować zakupu. Config: Config.Shop.Fx.
--
-- JEDEN UIScale NA PRZYCISK: najechanie, kliknięcie i wskok idą przez tę samą skalę (dwa UIScale
-- na obiekcie się nie sumują). `targetScale` liczy stan z `hovered` i `pressed`, a nowy tween na
-- tej samej właściwości przerywa poprzedni.
--
-- DOTYK: `MouseEnter` przychodzi też z palca, a `MouseLeave` często nie, więc na dotyku przycisk
-- zostawałby powiększony. Puszczenie poza przyciskiem nie daje `MouseButton1Up`, dlatego
-- `pressed` zdejmuje globalny `InputEnded`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.Shop.Fx

local ShopFx = {}

type Button = { scale: UIScale, hovered: boolean, pressed: boolean }
type TextPart = { label: TextLabel, home: UDim2, transparency: number, stroke: UIStroke?, strokeTransparency: number }

local HOVER_INFO = TweenInfo.new(CFG.HoverTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(CFG.PressTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TEXT_INFO = TweenInfo.new(CFG.TextTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local DOT_INFO = TweenInfo.new(CFG.DotTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHINE_INFO = TweenInfo.new(CFG.ShineTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local panel: GuiObject? = nil
local panelHome = UDim2.new()
local buyButton: GuiObject? = nil
local buy: Button? = nil
local prev: Button? = nil
local nextBtn: Button? = nil
local close: Button? = nil
local allButtons: { Button } = {}
local nameParts: { TextPart } = {}
local descParts: { TextPart } = {}
local priceLabels: { GuiObject } = {}
local priceScales: { UIScale } = {}
local status: TextLabel? = nil
local statusScales: { UIScale } = {}
local sweep: UIGradient? = nil
local dotsFrame: Instance? = nil
local dotTemplate: Frame? = nil
local dots: { Frame } = {}
local lavaImage: ImageLabel? = nil
local lavaTween: Tween? = nil

local canAfford = false
local openToken = 0 -- zmienia się przy każdym otwarciu i zamknięciu; stare pętle i zjazdy wiedzą, że są nieaktualne
local statusToken = 0

-- ============================================================================
-- Wibracje i dźwięki
-- ============================================================================

local haptics: { [string]: any } = {}
local sounds: { [string]: Sound } = {}
local lastFeedback: { [string]: number } = {}

local function playHaptic(typeName: string)
	local effect = haptics[typeName]
	if effect == nil then
		local ok, created = pcall(function(): any
			local h: any = Instance.new("HapticEffect" :: any)
			h.Type = (Enum :: any).HapticEffectType[typeName]
			h.Parent = Workspace
			return h
		end)
		-- false = silnik tego nie zna; nie próbujemy drugi raz przy każdym kliknięciu.
		effect = if ok then created else false
		haptics[typeName] = effect
	end
	if effect then
		pcall(function() effect:Play() end)
	end
end

local function playSound(id: string)
	local sound = sounds[id]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Parent = SoundService
		sounds[id] = sound
	end
	SoundService:PlayLocalSound(sound)
end

local function feedback(kind: string)
	local entry = (CFG.Feedback :: any)[kind]
	if not entry then return end
	local now = os.clock()
	if now - (lastFeedback[kind] or 0) < CFG.FeedbackMinGap then return end
	lastFeedback[kind] = now
	if entry.Haptic ~= "" then
		for i = 1, entry.HapticRepeat do
			task.delay((i - 1) * CFG.HapticRepeatGap, playHaptic, entry.Haptic)
		end
	end
	if entry.Sound ~= "" then playSound(entry.Sound) end
end

-- ============================================================================
-- Przyciski
-- ============================================================================

local function scaleOf(obj: Instance, name: string): UIScale
	local existing = obj:FindFirstChild(name)
	if existing and existing:IsA("UIScale") then return existing end
	local created = Instance.new("UIScale")
	created.Name = name
	created.Parent = obj
	return created
end

local function targetScale(b: Button): number
	if b.pressed then return CFG.PressScale end
	if b.hovered then return CFG.HoverScale end
	return 1
end

local function settle(b: Button)
	local info = if b.pressed then PRESS_INFO else HOVER_INFO
	TweenService:Create(b.scale, info, { Scale = targetScale(b) }):Play()
end

local function pop(b: Button?, from: number, time: number, delayTime: number?)
	if not b then return end
	b.scale.Scale = from
	local info = TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delayTime or 0)
	TweenService:Create(b.scale, info, { Scale = targetScale(b) }):Play()
end

local function popScales(scales: { UIScale }, from: number, time: number)
	local info = TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, s in ipairs(scales) do
		s.Scale = from
		TweenService:Create(s, info, { Scale = 1 }):Play()
	end
end

local function shake(obj: GuiObject?)
	if not obj then return end
	obj.Rotation = 0
	local info = TweenInfo.new(CFG.ShakeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	TweenService:Create(obj, info, { Rotation = CFG.ShakeDegrees }):Play()
end

local function hookButton(inst: Instance?, scaleName: string, activatedFeedback: string?): Button?
	if not (inst and inst:IsA("GuiButton")) then return nil end
	local b: Button = { scale = scaleOf(inst, scaleName), hovered = false, pressed = false }
	table.insert(allButtons, b)
	inst.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		b.hovered = true
		settle(b)
	end)
	inst.MouseLeave:Connect(function()
		b.hovered = false
		b.pressed = false
		settle(b)
	end)
	inst.MouseButton1Down:Connect(function()
		b.pressed = true
		settle(b)
	end)
	if activatedFeedback then
		local kind: string = activatedFeedback
		inst.Activated:Connect(function() feedback(kind) end)
	end
	return b
end

-- ============================================================================
-- Teksty
-- ============================================================================

local function textPart(inst: Instance?): TextPart?
	if not (inst and inst:IsA("TextLabel")) then return nil end
	local stroke = inst:FindFirstChildOfClass("UIStroke")
	return {
		label = inst,
		home = inst.Position,
		transparency = inst.TextTransparency,
		stroke = stroke,
		strokeTransparency = if stroke then stroke.Transparency else 0,
	}
end

-- Etykieta i jej cień (`<Nazwa>Shadow` obok niej). Cień animujemy osobno, bo TextShadowController
-- kopiuje tylko tekst i widoczność.
local function collectText(gui: Instance, name: string): { TextPart }
	local parts: { TextPart } = {}
	local label = gui:FindFirstChild(name, true)
	local main = textPart(label)
	if main then table.insert(parts, main) end
	local parent = label and label.Parent
	local shadow = textPart(parent and parent:FindFirstChild(name .. "Shadow"))
	if shadow then table.insert(parts, shadow) end
	return parts
end

local function enterText(parts: { TextPart }, slideX: number)
	for _, p in ipairs(parts) do
		p.label.Position = p.home + UDim2.fromOffset(slideX, 0)
		p.label.TextTransparency = 1
		TweenService:Create(p.label, TEXT_INFO, { Position = p.home, TextTransparency = p.transparency }):Play()
		local stroke = p.stroke
		if stroke then
			stroke.Transparency = 1
			TweenService:Create(stroke, TEXT_INFO, { Transparency = p.strokeTransparency }):Play()
		end
	end
end

-- ============================================================================
-- Kropki i połysk
-- ============================================================================

-- Pozycje liczone, nie UIListLayout: rosnąca kropka przesuwałaby sąsiednie (UI_RULES).
local function buildDots(count: number)
	local template = dotTemplate
	if not (dotsFrame and template) or #dots == count then return end
	for _, d in ipairs(dots) do d:Destroy() end
	table.clear(dots)
	for i = 1, count do
		local d = template:Clone()
		d.Name = "Dot"
		d.Position = UDim2.new(0.5, (i - (count + 1) / 2) * CFG.DotSpacing, 0.5, 0)
		d.Visible = true
		d.Parent = dotsFrame
		dots[i] = d
	end
end

local function setDot(index: number, animate: boolean)
	for i, d in ipairs(dots) do
		local size = if i == index then CFG.DotActiveSize else CFG.DotIdleSize
		local color = if i == index then CFG.DotActiveColor else CFG.DotIdleColor
		if animate then
			TweenService:Create(d, DOT_INFO, { Size = UDim2.fromOffset(size, size), BackgroundColor3 = color }):Play()
		else
			d.Size = UDim2.fromOffset(size, size)
			d.BackgroundColor3 = color
		end
	end
end

local function shineLoop(token: number)
	while token == openToken do
		task.wait(CFG.ShineInterval)
		local gradient = sweep
		if token == openToken and canAfford and gradient then
			gradient.Offset = Vector2.new(-CFG.ShineOffset, 0)
			TweenService:Create(gradient, SHINE_INFO, { Offset = Vector2.new(CFG.ShineOffset, 0) }):Play()
		end
	end
end

-- Obraz jest szerszy od pasa o jeden kafelek, więc przesuw o kafelek zapętla się bez przeskoku.
-- Tween zamiast pętli co klatkę, a gdy panel jest schowany, nic nie chodzi.
local function stopLava()
	if lavaTween then
		lavaTween:Cancel()
		lavaTween = nil
	end
end

local function startLava()
	stopLava()
	local image = lavaImage
	local tile = if image then image.TileSize.X.Offset else 0
	if not image or tile <= 0 then return end
	image.Position = UDim2.new()
	local info = TweenInfo.new(tile / CFG.LavaSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	lavaTween = TweenService:Create(image, info, { Position = UDim2.fromOffset(-tile, 0) })
	if lavaTween then lavaTween:Play() end
end

-- ============================================================================
-- API dla ShopController
-- ============================================================================

function ShopFx.bind(gui: ScreenGui)
	local p = gui:FindFirstChild("Panel")
	if p and p:IsA("GuiObject") then
		panel = p
		panelHome = p.Position
	end
	local buyInst = gui:FindFirstChild("BuyButton", true)
	buyButton = if buyInst and buyInst:IsA("GuiObject") then buyInst else nil
	buy = hookButton(buyInst, "Hover", "Press")
	prev = hookButton(gui:FindFirstChild("PrevButton", true), "Pop")
	nextBtn = hookButton(gui:FindFirstChild("NextButton", true), "Pop")
	close = hookButton(gui:FindFirstChild("CloseButton", true), "Hover", "Press")

	nameParts = collectText(gui, "ItemName")
	descParts = collectText(gui, "Description")
	for _, part in ipairs(collectText(gui, "Price")) do
		table.insert(priceLabels, part.label)
		table.insert(priceScales, scaleOf(part.label, "Pop"))
	end
	local statusParts = collectText(gui, "StatusLabel")
	status = statusParts[1] and statusParts[1].label
	for _, part in ipairs(statusParts) do
		table.insert(statusScales, scaleOf(part.label, "Pop"))
	end

	local sweepFrame = gui:FindFirstChild("Sweep", true)
	local gradient = sweepFrame and sweepFrame:FindFirstChildOfClass("UIGradient")
	if gradient then
		sweep = gradient
		gradient.Offset = Vector2.new(-CFG.ShineOffset, 0)
	end

	dotsFrame = gui:FindFirstChild("Dots", true)
	local template = dotsFrame and dotsFrame:FindFirstChild("DotTemplate")
	dotTemplate = if template and template:IsA("Frame") then template else nil

	local lava = gui:FindFirstChild("Lava1", true)
	lavaImage = if lava and lava:IsA("ImageLabel") then lava else nil

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		for _, b in ipairs(allButtons) do
			if b.pressed then
				b.pressed = false
				settle(b)
			end
		end
	end)
end

function ShopFx.open(itemCount: number)
	openToken += 1
	buildDots(itemCount)
	for _, b in ipairs(allButtons) do
		b.hovered = false
		b.pressed = false
	end
	local p = panel
	if p then
		p.Position = UDim2.new(panelHome.X, UDim.new(CFG.PanelHiddenY, 0))
		local info = TweenInfo.new(CFG.PanelOpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(p, info, { Position = panelHome }):Play()
	end
	for i, b in ipairs({ buy, prev, nextBtn, close } :: { Button? }) do
		pop(b, CFG.ButtonPopFrom, CFG.ButtonPopTime, CFG.ButtonPopDelay + (i - 1) * CFG.ButtonPopStagger)
	end
	startLava()
	task.spawn(shineLoop, openToken)
end

-- `done` chowa panel. Ponowne otwarcie w trakcie zjazdu zmienia żeton, więc panel zostaje.
function ShopFx.close(done: () -> ())
	openToken += 1
	local token = openToken
	stopLava()
	local p = panel
	if not p then
		done()
		return
	end
	local info = TweenInfo.new(CFG.PanelCloseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(p, info, { Position = UDim2.new(panelHome.X, UDim.new(CFG.PanelHiddenY, 0)) })
	tween.Completed:Connect(function()
		if token == openToken then done() end
	end)
	tween:Play()
end

-- `direction`: -1 / 1 = przewinięcie, 0 = pierwszy item po otwarciu (bez animacji treści).
function ShopFx.itemChanged(index: number, direction: number)
	setDot(index, direction ~= 0)
	if direction == 0 then return end
	enterText(nameParts, direction * CFG.NameSlide)
	enterText(descParts, 0)
	popScales(priceScales, CFG.PricePopFrom, CFG.PricePopTime)
	pop(if direction > 0 then nextBtn else prev, CFG.ArrowPopFrom, CFG.ArrowPopTime)
	feedback("Switch")
end

function ShopFx.setCanAfford(value: boolean)
	canAfford = value
end

function ShopFx.bought()
	pop(buy, CFG.BuyPopFrom, CFG.BuyPopTime)
	popScales(priceScales, CFG.PricePopFrom, CFG.PricePopTime)
	feedback("Buy")
end

function ShopFx.failed()
	shake(buyButton)
	for _, label in ipairs(priceLabels) do shake(label) end
	feedback("Fail")
end

function ShopFx.clearStatus()
	statusToken += 1
	if status then status.Text = "" end
	for _, s in ipairs(statusScales) do s.Scale = 1 end
end

-- Napis pod BUY. Każdy znika po `StatusHold`, także „...”: serwer po cichu odrzuca prośby ponad
-- limit, więc odpowiedź może nie przyjść, a napis nie może wisieć w nieskończoność.
function ShopFx.setStatus(text: string, color: Color3, animate: boolean)
	local label = status
	if not label then return end
	statusToken += 1
	local token = statusToken
	label.TextColor3 = color
	label.Text = text
	if animate then
		popScales(statusScales, CFG.StatusPopFrom, CFG.StatusPopTime)
	end
	task.delay(CFG.StatusHold, function()
		if token ~= statusToken then return end
		local info = TweenInfo.new(CFG.StatusHideTime, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local last: Tween? = nil
		for _, s in ipairs(statusScales) do
			last = TweenService:Create(s, info, { Scale = CFG.StatusPopFrom })
			last:Play()
		end
		if last then
			last.Completed:Connect(function()
				if token == statusToken then ShopFx.clearStatus() end
			end)
		end
	end)
end

return ShopFx
