--!strict
-- SkillTreeFx.luau (09.11) — wygląd stanów i mikroanimacje panelu drzewka umiejętności
-- (plan: docs/SKILLS_PLAN.md → „Mikroanimacje”). Wzór: ShopFx. Helper bez `init`.
--
-- PODZIAŁ: stan drzewka, kamerę i rozmowę z serwerem trzyma SkillTreeController; tu są tylko
-- reakcje na jego wywołania. Brak elementu w placu = brak efektu, nigdy błąd: animacja nie
-- może zablokować zakupu.
--
-- KONTRAKT PANELU (StarterGui.SkillTree, szczegóły: STUDIO_CONTRACT → „Drzewko umiejętności”):
--   Panel.Tree: Circle, Lines, Nodes, Selector, Rays, Sparkles, NodeTemplate, LineTemplate
--   Panel.Details: NodeName, Effect, ReqLabel, ReqBar.Fill, ReqCount, Price, UnlockButton, StatusLabel
--   Panel.Header.RebirthBadge, Panel.RebirthButton, Panel.CloseButton, Panel.Confirm.Box, Panel.Reward
-- Pola i połączenia KLONUJE kod z szablonów (jak kropki sklepu), a ich pozycje liczy z
-- SkillDefinitions i Config.Skills.Layout: korzeń na środku, odnogi promieniście.
--
-- Zasady ze sklepu (UI_RULES): jedna UIScale na element (najechanie, klik i wskok idą przez nią),
-- pozycje liczone w kodzie, `MouseEnter` ignorowany na dotyku, `pressed` zdejmowany globalnie.
-- SPOCZYNEK (krąg, pierścienie, poświaty, lawa w liniach, łuk wyboru) to JEDNA pętla Heartbeat,
-- która chodzi tylko przy otwartym panelu — bez stosu zapętlonych tweenów do pilnowania.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local SkillDefinitions = require(ReplicatedStorage.Shared.Modules.SkillDefinitions)
local ShopFx = require(script.Parent.ShopFx)
local SparkleBurst = require(script.Parent.SparkleBurst)

local SKILLS = Config.Skills
local CFG = SKILLS.Fx
local COLORS = SKILLS.Colors
local LAYOUT = SKILLS.Layout
local TEXTS = SKILLS.Texts
local WHITE = Color3.new(1, 1, 1)

local SkillTreeFx = {}

-- "owned" kupione · "available" do kupienia (poprzednie pole jest) · "locked" brak poprzedniego ·
-- "sealed" odnoga zamknięta do rebirthu
export type NodeState = "owned" | "available" | "locked" | "sealed"
export type Detail = {
	title: string,
	desc: string,
	price: string,
	color: Color3,
	reqText: string?,   -- nil = pole bez wymagania (pasek i licznik znikają)
	reqHave: number?,
	reqNeed: number?,
	buttonText: string,
	buttonEnabled: boolean,
}

type Button = { inst: GuiObject, scale: UIScale, hovered: boolean, pressed: boolean, hoverScale: number }
type TextPart = { label: TextLabel, home: UDim2, transparency: number, stroke: UIStroke?, strokeTransparency: number }
type NodeView = {
	id: string,
	level: number,
	order: number,          -- kolejność odnogi (kaskada otwarcia)
	requires: string?,
	button: Button,
	offset: Vector2,
	size: number,
	color: Color3,
	fill: GuiObject?,
	icon: ImageLabel?,
	ring: ImageLabel?,
	ringSize: UDim2,
	glow: ImageLabel?,
	lock: ImageLabel?,
	lockHome: UDim2,
	tag: TextLabel?,
	sealText: string,
	state: NodeState,
}
type LineView = {
	child: string,
	frame: GuiObject,
	base: GuiObject?,
	lava: GuiObject?,
	flow: UIGradient?,
	from: Vector2,
	to: Vector2,
	length: number,
	lit: boolean,
}

local bound = false
local panel: GuiObject? = nil
local panelHome = UDim2.new()
local circle: ImageLabel? = nil
local selector: ImageLabel? = nil
local selectorScale: UIScale? = nil
local rays: GuiObject? = nil
local raysScale: UIScale? = nil
local sparkles: GuiObject? = nil

local nodeViews: { [string]: NodeView } = {}
local nodeOrder: { NodeView } = {}
local lineViews: { LineView } = {}
local allButtons: { Button } = {}

local nameParts: { TextPart } = {}
local effectParts: { TextPart } = {}
local reqParts: { TextPart } = {}
local countParts: { TextPart } = {}
local priceParts: { TextPart } = {}
local priceScales: { UIScale } = {}
local reqBar: GuiObject? = nil
local reqFill: GuiObject? = nil
local statusLabel: TextLabel? = nil
local statusScales: { UIScale } = {}

local unlockInst: GuiObject? = nil
local unlockButton: Button? = nil
local unlockLabel: TextLabel? = nil
local unlockGradient: UIGradient? = nil
local unlockText = ""

local rebirthButton: Button? = nil
local rebirthLabel: TextLabel? = nil
local rebirthGradient: UIGradient? = nil
local rebirthBorder: ImageLabel? = nil
local rebirthAvailable = false

local badgeLabel: TextLabel? = nil
local badgeScale: UIScale? = nil

local confirmFrame: GuiObject? = nil
local confirmScale: UIScale? = nil
local confirmLines: { [string]: TextLabel } = {}

local rewardFrame: GuiObject? = nil
local rewardScale: UIScale? = nil
local rewardRays: GuiObject? = nil
local rewardLines: { [string]: TextLabel } = {}

local selectedId: string? = nil
local isOpen = false
local openToken = 0     -- każde otwarcie i zamknięcie; stare opóźnione kroki wiedzą, że są nieaktualne
local statusToken = 0
local waitToken = 0
local countToken = 0
local raysToken = 0
local rewardToken = 0
local idleConn: RBXScriptConnection? = nil
local clock = 0
local pulseAt = 0
local circleBurstValue = Instance.new("NumberValue") -- dodatkowy obrót kręgu po rebirthie (stopnie)

-- ============================================================================
-- Drobne pomocniki
-- ============================================================================

local function tween(inst: Instance, time: number, style: Enum.EasingStyle, dir: Enum.EasingDirection, goal: { [string]: any }, delayTime: number?): Tween
	local info = TweenInfo.new(time, style, dir, 0, false, delayTime or 0)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function scaleOf(obj: Instance, name: string): UIScale
	local existing = obj:FindFirstChild(name)
	if existing and existing:IsA("UIScale") then return existing end
	local created = Instance.new("UIScale")
	created.Name = name
	created.Parent = obj
	return created
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function at(offset: Vector2): UDim2
	return UDim2.new(0.5, offset.X, 0.5, offset.Y)
end

local function setGradient(gradient: UIGradient?, colors: { Color3 })
	if gradient then
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
end

-- ============================================================================
-- Przyciski i pola: jedna skala, stan z hovered + pressed
-- ============================================================================

local function targetScale(b: Button): number
	if b.pressed then return CFG.PressScale end
	if b.hovered then return b.hoverScale end
	return 1
end

local function settle(b: Button)
	if b.pressed then
		tween(b.scale, CFG.PressTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Scale = targetScale(b) })
	else
		tween(b.scale, CFG.HoverTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = targetScale(b) })
	end
end

local function pop(b: Button?, from: number, time: number, delayTime: number?)
	if not b then return end
	b.scale.Scale = from
	tween(b.scale, time, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = targetScale(b) }, delayTime)
end

local function popScale(scale: UIScale?, from: number, time: number)
	if not scale then return end
	scale.Scale = from
	tween(scale, time, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
end

local function shake(obj: GuiObject?)
	if not obj then return end
	obj.Rotation = 0
	local info = TweenInfo.new(CFG.ShakeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	TweenService:Create(obj, info, { Rotation = CFG.ShakeDegrees }):Play()
end

-- `onHover(hovered)` dla dodatkowej reakcji (przechył ikony pola).
local function hookButton(inst: Instance?, scaleName: string, hoverScale: number, onHover: ((boolean) -> ())?): Button?
	if not (inst and inst:IsA("GuiButton")) then return nil end
	local b: Button = { inst = inst, scale = scaleOf(inst, scaleName), hovered = false, pressed = false, hoverScale = hoverScale }
	table.insert(allButtons, b)
	inst.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		b.hovered = true
		settle(b)
		if onHover then onHover(true) end
	end)
	inst.MouseLeave:Connect(function()
		b.hovered = false
		b.pressed = false
		settle(b)
		if onHover then onHover(false) end
	end)
	inst.MouseButton1Down:Connect(function()
		b.pressed = true
		settle(b)
	end)
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

-- Etykieta i jej cień (`<Nazwa>Shadow` obok). Tekst cienia kopiuje TextShadowController;
-- ruch i przezroczystość animujemy sami.
local function collectText(root: Instance, name: string): { TextPart }
	local parts: { TextPart } = {}
	local label = root:FindFirstChild(name, true)
	local main = textPart(label)
	if main then table.insert(parts, main) end
	local parent = label and label.Parent
	local shadow = textPart(parent and parent:FindFirstChild(name .. "Shadow"))
	if shadow then table.insert(parts, shadow) end
	return parts
end

local function setText(parts: { TextPart }, text: string)
	local first = parts[1]
	if first then first.label.Text = text end
end

local function setVisible(parts: { TextPart }, visible: boolean)
	local first = parts[1]
	if first then first.label.Visible = visible end
end

local function enterText(parts: { TextPart }, slideX: number)
	for _, p in ipairs(parts) do
		p.label.Position = p.home + UDim2.fromOffset(slideX, 0)
		p.label.TextTransparency = 1
		tween(p.label, CFG.TextTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out,
			{ Position = p.home, TextTransparency = p.transparency })
		local stroke = p.stroke
		if stroke then
			stroke.Transparency = 1
			tween(stroke, CFG.TextTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out,
				{ Transparency = p.strokeTransparency })
		end
	end
end

-- Mignięcie na czerwono tego, czego brakuje. Gradient koloru (cena) na czas mignięcia
-- wyłączamy: mnożyłby czerwień przez zieleń.
local function flashMissing(parts: { TextPart })
	local main = parts[1]
	if not main then return end
	local label = main.label
	if label:GetAttribute("Flashing") == true then return end
	label:SetAttribute("Flashing", true)
	local gradient = label:FindFirstChildOfClass("UIGradient")
	local hadGradient = gradient ~= nil and gradient.Enabled
	local original = label.TextColor3
	if gradient then gradient.Enabled = false end
	-- `reverses` = tam i z powrotem, więc po ostatnim powtórzeniu kolor wraca do wyjściowego.
	local info = TweenInfo.new(CFG.FlashTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, CFG.FlashRepeats - 1, true)
	local t = TweenService:Create(label, info, { TextColor3 = COLORS.Missing })
	t.Completed:Connect(function()
		label.TextColor3 = original
		if gradient and hadGradient then gradient.Enabled = true end
		label:SetAttribute("Flashing", nil)
	end)
	t:Play()
end

-- ============================================================================
-- Budowa drzewka z szablonów
-- ============================================================================

local function nodeOffset(def: SkillDefinitions.Node): (Vector2, number)
	if def.branch == "start" then return Vector2.zero, 0 end
	local order = table.find(SkillDefinitions.branchOrder, def.branch) or 1
	local angle = math.rad(LAYOUT.StartAngle + (order - 1) * (360 / #SkillDefinitions.branchOrder))
	local radius = if def.level >= 2 then LAYOUT.Radius2 else LAYOUT.Radius1
	return Vector2.new(math.cos(angle), math.sin(angle)) * radius, order
end

local function imageChild(parent: Instance, name: string): ImageLabel?
	local child = parent:FindFirstChild(name)
	return if child and child:IsA("ImageLabel") then child else nil
end

local function buildNodes(tree: Instance, onNode: (string) -> ())
	local template = tree:FindFirstChild("NodeTemplate")
	local container = tree:FindFirstChild("Nodes")
	if not (template and template:IsA("GuiButton") and container) then
		warn("[SkillTree] brak Tree.NodeTemplate albo Tree.Nodes — drzewko bez pól")
		return
	end
	for _, def in ipairs(SkillDefinitions.nodes) do
		local inst = template:Clone()
		inst.Name = def.id
		local offset, order = nodeOffset(def)
		-- Korzeń trochę większy od reszty.
		local size = template.Size.X.Offset * (if def.level == 0 then 1.25 else 1)
		inst.Size = UDim2.fromOffset(size, size)
		inst.Position = at(offset)
		inst.Visible = true

		local branch = SkillDefinitions.branches[def.branch]
		local color = if branch then branch.color else SkillDefinitions.startColor
		local icon = imageChild(inst, "Icon")
		if icon then icon.Image = if branch then branch.icon else SkillDefinitions.icons.start end
		local ring = imageChild(inst, "Ring")
		local lock = imageChild(inst, "Lock")
		if lock then lock.Image = SkillDefinitions.icons.lock end
		local tag = inst:FindFirstChild("Tag")
		local fill = inst:FindFirstChild("Fill")

		local button = hookButton(inst, "Pop", CFG.HoverScale, function(hovered: boolean)
			if icon then
				tween(icon, CFG.HoverTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out,
					{ Rotation = if hovered then CFG.HoverTilt else 0 })
			end
		end)
		if not button then
			inst:Destroy()
			continue
		end
		local view: NodeView = {
			id = def.id,
			level = def.level,
			order = order,
			requires = def.requires,
			button = button,
			offset = offset,
			size = size,
			color = color,
			fill = if fill and fill:IsA("GuiObject") then fill else nil,
			icon = icon,
			ring = ring,
			ringSize = if ring then ring.Size else UDim2.new(),
			glow = imageChild(inst, "Glow"),
			lock = lock,
			lockHome = if lock then lock.Position else UDim2.new(),
			tag = if tag and tag:IsA("TextLabel") then tag else nil,
			sealText = TEXTS.BranchLocked:format(SkillDefinitions.rebirthOf(def)),
			state = "locked",
		}
		nodeViews[def.id] = view
		table.insert(nodeOrder, view)
		inst.Parent = container
		local id = def.id
		inst.Activated:Connect(function() onNode(id) end)
	end
end

local function buildLines(tree: Instance)
	local template = tree:FindFirstChild("LineTemplate")
	local container = tree:FindFirstChild("Lines")
	if not (template and template:IsA("GuiObject") and container) then return end
	for _, view in ipairs(nodeOrder) do
		local parent = view.requires and nodeViews[view.requires]
		if not parent then continue end
		local frame = template:Clone()
		frame.Name = view.id
		local delta = view.offset - parent.offset
		local length = delta.Magnitude
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		frame.Size = UDim2.fromOffset(length, LAYOUT.LineThickness)
		frame.Position = at((parent.offset + view.offset) / 2)
		frame.Visible = true
		local base = frame:FindFirstChild("Base")
		-- `Lava` siedzi w `Base` (rozmiar bez offsetów, więc 0 skali = dokładnie zero szerokości).
		local lava = frame:FindFirstChild("Lava", true)
		local flow = lava and lava:FindFirstChild("Flow")
		frame.Parent = container
		table.insert(lineViews, {
			child = view.id,
			frame = frame,
			base = if base and base:IsA("GuiObject") then base else nil,
			lava = if lava and lava:IsA("GuiObject") then lava else nil,
			flow = if flow and flow:IsA("UIGradient") then flow else nil,
			from = parent.offset,
			to = view.offset,
			length = length,
			lit = false,
		})
	end
end

-- ============================================================================
-- Wygląd stanów
-- ============================================================================

local function dropLock(view: NodeView)
	local lock = view.lock
	if not lock then return end
	lock.Visible = true
	lock.Position = view.lockHome
	lock.Rotation = 0
	lock.ImageTransparency = 0
	local t = tween(lock, CFG.LockDropTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Position = view.lockHome + UDim2.fromOffset(0, CFG.LockDrop),
		Rotation = CFG.LockSpin,
		ImageTransparency = 1,
	})
	t.Completed:Connect(function()
		-- Stan mógł się zmienić w trakcie spadania (rebirth) — wtedy kłódka ma zostać.
		if view.state == "owned" or view.state == "available" then
			lock.Visible = false
		end
		lock.Position = view.lockHome
		lock.Rotation = 0
		lock.ImageTransparency = 0
	end)
end

local function applyNode(view: NodeView, state: NodeState, animate: boolean)
	local previous = view.state
	view.state = state
	local fillColor: Color3
	local iconColor: Color3
	local iconTransparency = 0
	if state == "owned" then
		fillColor, iconColor = view.color, WHITE
	elseif state == "available" then
		fillColor, iconColor = COLORS.NodeAvailable, view.color
	else
		fillColor, iconColor, iconTransparency = COLORS.NodeLocked, COLORS.IconLocked, 0.45
	end
	local changed = animate and previous ~= state
	local fill, icon = view.fill, view.icon
	if fill then
		if changed then
			tween(fill, CFG.ColorTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundColor3 = fillColor })
		else
			fill.BackgroundColor3 = fillColor
		end
	end
	if icon then
		if changed then
			tween(icon, CFG.ColorTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,
				{ ImageColor3 = iconColor, ImageTransparency = iconTransparency })
		else
			icon.ImageColor3 = iconColor
			icon.ImageTransparency = iconTransparency
		end
	end
	local ring = view.ring
	if ring then
		ring.ImageColor3 = view.color
		ring.Visible = state == "available"
	end
	local glow = view.glow
	if glow then
		glow.ImageColor3 = COLORS.GlowOwned
		glow.Visible = state == "owned"
	end
	local lock = view.lock
	local lockedNow = state == "locked" or state == "sealed"
	local lockedBefore = previous == "locked" or previous == "sealed"
	if lock then
		if changed and lockedBefore and not lockedNow then
			dropLock(view) -- kłódka pęka i spada
		else
			lock.Visible = lockedNow
		end
	end
	local tag = view.tag
	if tag then
		-- Napis „REBIRTH n” pod ZEWNĘTRZNYM polem zamkniętej odnogi — wiadomo, na co się gra,
		-- a pod polem wewnętrznym zasłaniałoby go następne pole.
		tag.Text = view.sealText
		tag.Visible = state == "sealed" and view.level == 2
	end
end

local function applyLine(line: LineView, animate: boolean)
	local child = nodeViews[line.child]
	if not child then return end
	local lit = child.state == "owned"
	local baseColor = if child.state == "locked" or child.state == "sealed" then COLORS.LineLocked else COLORS.LineAvailable
	local base, lava = line.base, line.lava
	if base then
		if animate then
			tween(base, CFG.ColorTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundColor3 = baseColor })
		else
			base.BackgroundColor3 = baseColor
		end
	end
	if lava then
		local full = UDim2.fromScale(if lit then 1 else 0, 1)
		if animate and lit ~= line.lit then
			lava.Visible = true
			local t = tween(lava, CFG.LineFillTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Size = full })
			if not lit then
				t.Completed:Connect(function()
					if not line.lit then lava.Visible = false end
				end)
			end
		else
			lava.Size = full
			lava.Visible = lit
		end
	end
	line.lit = lit
end

-- ============================================================================
-- Spoczynek: jedna pętla przy otwartym panelu
-- ============================================================================

local function wave(period: number, phase: number): number
	return 0.5 + 0.5 * math.sin((clock / period + phase) * math.pi * 2)
end

local function idleStep(dt: number)
	clock += dt
	local c = circle
	if c then
		c.Rotation = (clock / CFG.CircleSpinTime * 360 + circleBurstValue.Value) % 360
	end
	for i, view in ipairs(nodeOrder) do
		if view.state == "available" then
			local ring = view.ring
			if ring then
				local t = wave(CFG.RingBreathTime, i * 0.13)
				ring.ImageTransparency = lerp(CFG.RingTransparency[1], CFG.RingTransparency[2], t)
				local s = lerp(CFG.RingScale[2], CFG.RingScale[1], t)
				local base = view.ringSize
				ring.Size = UDim2.new(base.X.Scale * s, base.X.Offset * s, base.Y.Scale * s, base.Y.Offset * s)
			end
		elseif view.state == "owned" then
			local glow = view.glow
			if glow then
				glow.ImageTransparency = lerp(CFG.GlowTransparency[1], CFG.GlowTransparency[2], wave(CFG.GlowPulseTime, i * 0.21))
			end
		end
	end
	local flowOffset = ((clock / CFG.LavaFlowTime) % 1) * 2 - 1
	for _, line in ipairs(lineViews) do
		if line.lit and line.flow then
			line.flow.Offset = Vector2.new(flowOffset, 0)
		end
	end
	local sel = selector
	if sel and sel.Visible then
		sel.Rotation = (clock / CFG.SelectorSpinTime * 360) % 360
	end
	local reward = rewardRays
	if reward and rewardFrame and rewardFrame.Visible then
		reward.Rotation = (reward.Rotation + CFG.RaysSpin * dt) % 360
	end
	local burst = rays
	if burst and burst.Visible then
		burst.Rotation = (burst.Rotation + CFG.RaysSpin * dt) % 360
	end
	-- REBIRTH dostępny: przycisk co kilka sekund pulsuje, błyskawice migają.
	local border = rebirthBorder
	if border then
		if rebirthAvailable then
			border.Visible = true
			local flicker = math.noise(clock / CFG.LightningFlickerTime, 7.3) + 0.5
			border.ImageTransparency = lerp(CFG.LightningTransparency[1], CFG.LightningTransparency[2], math.clamp(flicker, 0, 1))
		else
			border.Visible = false
		end
	end
	if rebirthAvailable and clock >= pulseAt then
		pulseAt = clock + CFG.RebirthPulseInterval
		local b = rebirthButton
		if b and not b.hovered and not b.pressed then
			pop(b, CFG.RebirthPulseScale, CFG.RebirthPulseTime)
		end
	end
end

local function stopIdle()
	if idleConn then
		idleConn:Disconnect()
		idleConn = nil
	end
end

local function startIdle()
	stopIdle()
	clock = 0
	pulseAt = CFG.RebirthPulseInterval
	idleConn = RunService.Heartbeat:Connect(idleStep)
end

-- ============================================================================
-- API dla SkillTreeController
-- ============================================================================

-- `onNode(id)` — kliknięte pole. Przyciski (UNLOCK, REBIRTH, X, okno potwierdzenia) kontroler
-- podpina sam po nazwie; tu dostają tylko reakcję na kursor i kliknięcie.
function SkillTreeFx.bind(gui: ScreenGui, onNode: (string) -> ())
	if bound then return end
	bound = true
	local p = gui:FindFirstChild("Panel")
	if not (p and p:IsA("GuiObject")) then
		warn("[SkillTree] brak SkillTree.Panel — panel bez animacji")
		return
	end
	panel = p
	panelHome = p.Position

	local tree = p:FindFirstChild("Tree")
	if tree then
		circle = imageChild(tree, "Circle")
		if circle then
			circle.ImageColor3 = COLORS.Circle
			circle.ImageTransparency = CFG.CircleTransparency
		end
		selector = imageChild(tree, "Selector")
		if selector then
			selectorScale = scaleOf(selector, "Pop")
			selector.Visible = false
		end
		local r = tree:FindFirstChild("Rays")
		if r and r:IsA("GuiObject") then
			rays = r
			raysScale = scaleOf(r, "Pop")
			r.Visible = false
		end
		local s = tree:FindFirstChild("Sparkles")
		sparkles = if s and s:IsA("GuiObject") then s else nil
		buildNodes(tree, onNode)
		buildLines(tree)
	end

	nameParts = collectText(p, "NodeName")
	effectParts = collectText(p, "Effect")
	reqParts = collectText(p, "ReqLabel")
	countParts = collectText(p, "ReqCount")
	priceParts = collectText(p, "Price")
	for _, part in ipairs(priceParts) do
		table.insert(priceScales, scaleOf(part.label, "Pop"))
	end
	local bar = p:FindFirstChild("ReqBar", true)
	reqBar = if bar and bar:IsA("GuiObject") then bar else nil
	local fill = bar and bar:FindFirstChild("Fill")
	reqFill = if fill and fill:IsA("GuiObject") then fill else nil
	local statusParts = collectText(p, "StatusLabel")
	statusLabel = statusParts[1] and statusParts[1].label
	for _, part in ipairs(statusParts) do
		table.insert(statusScales, scaleOf(part.label, "Pop"))
	end

	local unlock = p:FindFirstChild("UnlockButton", true)
	unlockInst = if unlock and unlock:IsA("GuiObject") then unlock else nil
	unlockButton = hookButton(unlock, "Hover", CFG.ButtonHoverScale)
	if unlock then
		local label = unlock:FindFirstChild("Label")
		unlockLabel = if label and label:IsA("TextLabel") then label else nil
		local f = unlock:FindFirstChild("Fill")
		unlockGradient = f and f:FindFirstChildOfClass("UIGradient")
	end

	local rebirth = p:FindFirstChild("RebirthButton", true)
	rebirthButton = hookButton(rebirth, "Hover", CFG.ButtonHoverScale)
	if rebirth then
		local label = rebirth:FindFirstChild("Label")
		rebirthLabel = if label and label:IsA("TextLabel") then label else nil
		local f = rebirth:FindFirstChild("Fill")
		rebirthGradient = f and f:FindFirstChildOfClass("UIGradient")
		rebirthBorder = imageChild(rebirth, "Border")
	end

	hookButton(p:FindFirstChild("CloseButton", true), "Hover", CFG.ButtonHoverScale)

	local badge = p:FindFirstChild("RebirthBadge", true)
	if badge then
		badgeScale = scaleOf(badge, "Pop")
		local label = badge:FindFirstChild("Label")
		badgeLabel = if label and label:IsA("TextLabel") then label else nil
	end

	local confirm = p:FindFirstChild("Confirm")
	if confirm and confirm:IsA("GuiObject") then
		confirmFrame = confirm
		confirm.Visible = false
		local box = confirm:FindFirstChild("Box")
		if box then
			confirmScale = scaleOf(box, "Pop")
			for _, name in ipairs({ "Title", "Lose", "Keep", "Gain", "Extra" }) do
				local label = box:FindFirstChild(name)
				if label and label:IsA("TextLabel") then confirmLines[name] = label end
			end
			hookButton(box:FindFirstChild("ConfirmButton"), "Hover", CFG.ButtonHoverScale)
			hookButton(box:FindFirstChild("CancelButton"), "Hover", CFG.ButtonHoverScale)
		end
	end

	local reward = p:FindFirstChild("Reward")
	if reward and reward:IsA("GuiObject") then
		rewardFrame = reward
		reward.Visible = false
		rewardScale = scaleOf(reward, "Pop")
		local rr = reward:FindFirstChild("Rays")
		rewardRays = if rr and rr:IsA("GuiObject") then rr else nil
		for _, name in ipairs({ "Title", "Line1", "Line2" }) do
			local label = reward:FindFirstChild(name)
			if label and label:IsA("TextLabel") then rewardLines[name] = label end
		end
	end

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

-- Stany wszystkich pól naraz. `animate` = pokaż przejścia (zakup, odsłonięcie odnogi);
-- false = ustaw od razu (otwarcie panelu).
function SkillTreeFx.render(states: { [string]: NodeState }, animate: boolean)
	for _, view in ipairs(nodeOrder) do
		applyNode(view, states[view.id] or "locked", animate)
	end
	for _, line in ipairs(lineViews) do
		applyLine(line, animate)
	end
end

function SkillTreeFx.open()
	openToken += 1
	isOpen = true
	for _, b in ipairs(allButtons) do
		b.hovered = false
		b.pressed = false
	end
	local p = panel
	if p then
		p.Position = panelHome + UDim2.fromOffset(CFG.PanelHiddenOffset, 0)
		tween(p, CFG.PanelOpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Position = panelHome })
	end
	if confirmFrame then confirmFrame.Visible = false end
	if rewardFrame then rewardFrame.Visible = false end
	if rays then rays.Visible = false end
	-- Kaskada: pola wskakują od korzenia w głąb odnóg, linie rysują się za nimi.
	for _, view in ipairs(nodeOrder) do
		local delayTime = CFG.CascadeDelay + view.level * CFG.CascadeLevelStagger + view.order * CFG.CascadeBranchStagger
		pop(view.button, CFG.NodePopFrom, CFG.NodePopTime, delayTime)
		if view.icon then view.icon.Rotation = 0 end
	end
	for _, line in ipairs(lineViews) do
		local child = nodeViews[line.child]
		local delayTime = CFG.CascadeDelay
			+ (if child then (child.level - 0.5) * CFG.CascadeLevelStagger + child.order * CFG.CascadeBranchStagger else 0)
		local frame = line.frame
		-- Obrót GUI idzie wokół środka, więc „rysowanie od początku” to długość i środek naraz.
		frame.Size = UDim2.fromOffset(0, LAYOUT.LineThickness)
		frame.Position = at(line.from)
		tween(frame, CFG.LineDrawTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
			Size = UDim2.fromOffset(line.length, LAYOUT.LineThickness),
			Position = at((line.from + line.to) / 2),
		}, math.max(0, delayTime))
	end
	startIdle()
end

-- `done` chowa panel. Ponowne otwarcie w trakcie zjazdu zmienia żeton, więc panel zostaje.
function SkillTreeFx.close(done: () -> ())
	openToken += 1
	local token = openToken
	isOpen = false
	stopIdle()
	statusToken += 1
	waitToken += 1
	countToken += 1
	local p = panel
	if not p then
		done()
		return
	end
	local t = tween(p, CFG.PanelCloseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In,
		{ Position = panelHome + UDim2.fromOffset(CFG.PanelHiddenOffset, 0) })
	t.Completed:Connect(function()
		if token == openToken then done() end
	end)
end

-- Szczegóły wybranego pola. `animate` = wybór się zmienił (łuk wskakuje, nazwa wjeżdża, pasek
-- rośnie od zera, licznik odlicza); false = te same pola z nowymi wartościami.
function SkillTreeFx.select(id: string, detail: Detail, animate: boolean)
	selectedId = id
	local view = nodeViews[id]
	local sel = selector
	if sel and view then
		sel.Position = at(view.offset)
		sel.Size = UDim2.fromOffset(view.size * 1.75, view.size * 1.75)
		sel.ImageColor3 = view.color
		sel.Visible = true
		if animate then popScale(selectorScale, CFG.SelectorPopFrom, CFG.SelectorPopTime) end
	end

	setText(nameParts, detail.title)
	local nameMain = nameParts[1]
	if nameMain then nameMain.label.TextColor3 = detail.color end
	setText(effectParts, detail.desc)
	setText(priceParts, detail.price)
	setVisible(priceParts, detail.price ~= "")

	local have, need = detail.reqHave or 0, detail.reqNeed or 0
	local hasBar = detail.reqText ~= nil and need > 0
	setVisible(reqParts, detail.reqText ~= nil)
	setText(reqParts, detail.reqText or "")
	setVisible(countParts, hasBar)
	if reqBar then reqBar.Visible = hasBar end
	countToken += 1
	if hasBar then
		local frac = math.clamp(have / need, 0, 1)
		local fill = reqFill
		if fill then
			if animate then fill.Size = UDim2.fromScale(0, 1) end
			fill.Visible = frac > 0
			tween(fill, CFG.BarTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Size = UDim2.fromScale(frac, 1) })
		end
		local shown = math.min(have, need)
		if animate and shown > 0 then
			local token = countToken
			task.spawn(function()
				local started = os.clock()
				while token == countToken do
					local t = math.clamp((os.clock() - started) / CFG.CountTime, 0, 1)
					setText(countParts, ("%d/%d"):format(math.floor(shown * t + 0.5), need))
					if t >= 1 then break end
					RunService.Heartbeat:Wait()
				end
			end)
		else
			setText(countParts, ("%d/%d"):format(shown, need))
		end
	end

	unlockText = detail.buttonText
	waitToken += 1
	if unlockLabel then unlockLabel.Text = unlockText end
	setGradient(unlockGradient, if detail.buttonEnabled then COLORS.Unlock else COLORS.Disabled)

	if animate then
		enterText(nameParts, CFG.NameSlide)
		enterText(effectParts, 0)
		for _, s in ipairs(priceScales) do popScale(s, CFG.PricePopFrom, CFG.PricePopTime) end
		ShopFx.feedback("Switch")
	end
end

function SkillTreeFx.setRebirth(text: string, available: boolean)
	rebirthAvailable = available
	if rebirthLabel then rebirthLabel.Text = text end
	setGradient(rebirthGradient, if available then COLORS.Rebirth else COLORS.Disabled)
	if not available and rebirthBorder then rebirthBorder.Visible = false end
end

function SkillTreeFx.setBadge(text: string, animate: boolean)
	if badgeLabel then badgeLabel.Text = text end
	if animate then popScale(badgeScale, CFG.BadgePopFrom, CFG.BadgePopTime) end
end

-- Czekanie na serwer: napis UNLOCK zamienia się w skaczące kropki. Koniec: `waiting(false)`,
-- kolejny `select` albo zamknięcie.
function SkillTreeFx.waiting(on: boolean)
	waitToken += 1
	local label = unlockLabel
	if not label then return end
	if not on then
		label.Text = unlockText
		return
	end
	local token = waitToken
	task.spawn(function()
		local step = 0
		while token == waitToken and isOpen do
			step = step % 3 + 1
			label.Text = string.rep(".", step)
			task.wait(CFG.WaitDotTime)
		end
	end)
end

function SkillTreeFx.clearStatus()
	statusToken += 1
	if statusLabel then statusLabel.Text = "" end
	for _, s in ipairs(statusScales) do s.Scale = 1 end
end

-- Napis pod UNLOCK: wskakuje i sam znika po `StatusHold`.
function SkillTreeFx.status(text: string, color: Color3)
	local label = statusLabel
	if not label then return end
	statusToken += 1
	local token = statusToken
	label.TextColor3 = color
	label.Text = text
	for _, s in ipairs(statusScales) do popScale(s, CFG.StatusPopFrom, CFG.StatusPopTime) end
	task.delay(CFG.StatusHold, function()
		if token == statusToken then SkillTreeFx.clearStatus() end
	end)
end

-- Udany zakup (po odpowiedzi serwera — `render` pokazał już nowy stan): pole zgniata się
-- i wyskakuje, promienie i gwiazdki w jego miejscu.
function SkillTreeFx.bought(id: string)
	local view = nodeViews[id]
	if view then
		local b = view.button
		b.scale.Scale = CFG.BuySquash
		tween(b.scale, CFG.BuyPopTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out, { Scale = targetScale(b) })
		local burst = rays
		if burst then
			raysToken += 1
			local token = raysToken
			burst.Position = at(view.offset)
			burst.Visible = true
			for _, ray in ipairs(burst:GetChildren()) do
				if ray:IsA("GuiObject") then
					ray.BackgroundColor3 = view.color
					ray.BackgroundTransparency = 0
				end
			end
			popScale(raysScale, 0.3, CFG.RaysPopTime)
			task.delay(CFG.RaysPopTime + CFG.RaysHold, function()
				if token ~= raysToken then return end
				local last: Tween? = nil
				for _, ray in ipairs(burst:GetChildren()) do
					if ray:IsA("GuiObject") then
						last = tween(ray, CFG.RaysFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
					end
				end
				local function hide()
					if token == raysToken then burst.Visible = false end
				end
				if last then last.Completed:Connect(hide) else hide() end
			end)
		end
		local stars = sparkles
		if stars then
			stars.Position = at(view.offset)
			SparkleBurst.play(stars)
		end
	end
	pop(unlockButton, 1.14, CFG.BuyPopTime)
	ShopFx.feedback("Buy")
end

-- Odmowa: UNLOCK trzęsie się, a to, czego brakuje, miga na czerwono.
-- `missing`: "cash" → cena, "requirement" → wymaganie i licznik, nil → samo drgnięcie.
function SkillTreeFx.failed(missing: string?)
	shake(unlockInst)
	if missing == "cash" then
		flashMissing(priceParts)
	elseif missing == "requirement" then
		flashMissing(reqParts)
		flashMissing(countParts)
	end
	ShopFx.feedback("Fail")
end

-- Okno potwierdzenia rebirthu. `lines`: Title, Lose, Keep, Gain, Extra ("" = linia znika).
function SkillTreeFx.confirm(show: boolean, lines: { [string]: string }?)
	local frame = confirmFrame
	if not frame then return end
	if not show then
		frame.Visible = false
		return
	end
	for name, label in pairs(confirmLines) do
		local text = lines and lines[name]
		if text then
			label.Text = text
			label.Visible = text ~= ""
		end
	end
	frame.BackgroundTransparency = 1
	frame.Visible = true
	tween(frame, CFG.ConfirmPopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = CFG.ConfirmDim })
	popScale(confirmScale, CFG.ConfirmPopFrom, CFG.ConfirmPopTime)
end

function SkillTreeFx.confirmVisible(): boolean
	return confirmFrame ~= nil and confirmFrame.Visible
end

-- Po udanym rebirthcie: pola gasną od końców odnóg do korzenia, lawa cofa się z linii, krąg
-- przyspiesza. Potem `reveal()` (kontroler rysuje nowe drzewko z animacją) i wyskakuje nagroda.
-- `reward`: Title, Line1, Line2 ("" = linia znika).
function SkillTreeFx.rebirthSequence(reward: { [string]: string }, reveal: () -> ())
	local token = openToken
	ShopFx.feedback("Buy")
	circleBurstValue.Value = 0
	tween(circleBurstValue, CFG.CircleBurstTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out,
		{ Value = CFG.CircleBurstTurns * 360 })
	if selector then selector.Visible = false end

	-- Kolejność gaśnięcia: najpierw poziom II, potem I, na końcu korzeń.
	local owned: { NodeView } = {}
	for _, view in ipairs(nodeOrder) do
		if view.state == "owned" then table.insert(owned, view) end
	end
	table.sort(owned, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		return a.order < b.order
	end)
	for i, view in ipairs(owned) do
		task.delay((i - 1) * CFG.ResetStagger, function()
			if token ~= openToken then return end
			applyNode(view, "available", true)
			if view.glow then view.glow.Visible = false end
			if view.ring then view.ring.Visible = false end
			for _, line in ipairs(lineViews) do
				if line.child == view.id then applyLine(line, true) end
			end
		end)
	end

	local total = math.max(0, #owned - 1) * CFG.ResetStagger + CFG.ResetFadeTime + CFG.RewardDelay
	task.delay(total, function()
		if token ~= openToken then return end
		reveal()
		local frame = rewardFrame
		if not frame then return end
		rewardToken += 1
		local rToken = rewardToken
		for name, label in pairs(rewardLines) do
			local text = reward[name]
			if text then
				label.Text = text
				label.Visible = text ~= ""
			end
		end
		frame.Visible = true
		popScale(rewardScale, CFG.RewardPopFrom, CFG.RewardPopTime)
		ShopFx.feedback("Buy")
		task.delay(CFG.RewardPopTime + CFG.RewardHold, function()
			if rToken ~= rewardToken then return end
			local scale = rewardScale
			if not scale then
				frame.Visible = false
				return
			end
			local t = tween(scale, CFG.RewardFadeTime, Enum.EasingStyle.Back, Enum.EasingDirection.In, { Scale = 0 })
			t.Completed:Connect(function()
				if rToken == rewardToken then frame.Visible = false end
			end)
		end)
	end)
end

return SkillTreeFx
