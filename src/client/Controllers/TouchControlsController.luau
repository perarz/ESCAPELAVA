--!strict
-- TouchControlsController.luau (28.10) — przyciski dotykowe `HUD.TouchControls` (telefon, tablet).
--
-- Jedyny właściciel tych przycisków: kiedy w ogóle są (tryb dotyku), gdzie stoją (przy skoku
-- Robloxa), co znaczy wciśnięcie i puszczenie, czy ramka świeci. Co robi akcja, wie tylko
-- właściciel mechaniki (MovementController, PushController, BridgeController, RpgController) —
-- rejestruje się przez `bind`, a kiedy przycisk ma sens, mówi przez `setShown` (most: tylko
-- w trybie budowy; AIM: tylko z RPG w ręce). Bez remote'ów: akcje idą tymi samymi funkcjami
-- co klawiatura, serwer waliduje jak dotąd.
--
-- Kontrakt Studio (STUDIO_CONTRACT → „Telefon”): `HUD.TouchControls` (Frame, Visible=false)
-- z przyciskami-dziećmi `Sprint`, `Push`, `Build`, `Rotate`, `Aim`, `Fire` (GuiButton, każdy
-- z `SelectStroke` UIStroke i `Pop` UIScale). Kontener ma AnchorPoint 0,5/0,5 i stoi na środku
-- skoku — pozycje przycisków są liczone od tego środka.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.UI.TouchControls
local localPlayer = Players.LocalPlayer

export type Handlers = { press: (() -> ())?, release: (() -> ())? }

local TouchControlsController = {}

local handlers: { [string]: Handlers } = {}
local wanted: { [string]: boolean } = {} -- setShown właściciela mechaniki
local lit: { [string]: boolean } = {}
local held: { [string]: InputObject } = {} -- wciśnięcie, które jeszcze trwa (dla `release`)
local buttons: { [string]: GuiButton } = {}
local container: GuiObject? = nil
local hud: ScreenGui? = nil
local fallbackPosition: UDim2? = nil
local touchMode = false
local initialized = false

local function touchGui(): ScreenGui?
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	return if tg and tg:IsA("ScreenGui") then tg else nil
end

-- Tryb dotyku = Roblox pokazuje własną gałkę i skok. Nasze przyciski pojawiają się i znikają
-- razem z nimi (też gdy gra wyłączy `GuiService.TouchControlsEnabled`). Zanim PlayerModule
-- postawi TouchGui — sam dotyk bez klawiatury.
local function detectTouch(): boolean
	if not UserInputService.TouchEnabled then return false end
	local tg = touchGui()
	if tg then return tg.Enabled end
	return not UserInputService.KeyboardEnabled
end

local function jumpButton(): GuiObject?
	local tg = touchGui()
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") then jump else nil
end

-- Skok ma 70 pt na telefonie i 120 pt w innym miejscu na tablecie — stałe pozycje ze Studio
-- nachodziłyby na niego na jednym z nich. Środek klastra = środek skoku. AbsolutePosition obu
-- ScreenGui leży w jednej przestrzeni, więc różnica z HUD-em uwzględnia jego DeviceSafeInsets.
local function place()
	local c, h = container, hud
	if not (c and h) then return end
	local jump = jumpButton()
	local target = fallbackPosition
	if jump and jump.AbsoluteSize.X > 0 then
		local center = jump.AbsolutePosition + jump.AbsoluteSize * 0.5 - h.AbsolutePosition
		target = UDim2.fromOffset(math.round(center.X), math.round(center.Y))
	end
	if target and c.Position ~= target then
		c.Position = target
	end
end

local function release(name: string)
	if not held[name] then return end
	held[name] = nil
	local h = handlers[name]
	if h and h.release then h.release() end
end

local function refresh()
	local c = container
	if c then c.Visible = touchMode end
	for name, b in pairs(buttons) do
		local show = touchMode and wanted[name] == true
		if b.Visible ~= show then
			b.Visible = show
		end
		-- Schowany w trakcie trzymania (śmierć, koniec trybu budowy) = puszczony.
		if not show then release(name) end
	end
end

local function applyLit(name: string)
	local b = buttons[name]
	local stroke = b and b:FindFirstChild("SelectStroke")
	if not (stroke and stroke:IsA("UIStroke")) then return end
	local color = if lit[name] then CFG.LitStroke else CFG.IdleStroke
	TweenService:Create(stroke, TweenInfo.new(CFG.StrokeTime), { Color = color }):Play()
end

local function pop(b: GuiButton)
	local ui = b:FindFirstChild("Pop")
	if not (ui and ui:IsA("UIScale")) then return end
	ui.Scale = CFG.PressScale
	TweenService:Create(ui, TweenInfo.new(CFG.PressTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
end

local function hookButton(name: string, b: GuiButton)
	buttons[name] = b
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		-- Myszka zostaje dla emulatora urządzeń w Studio.
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
		if held[name] or not b.Visible then return end
		held[name] = input
		pop(b)
		local h = handlers[name]
		if h and h.press then h.press() end
	end)
	applyLit(name)
end

function TouchControlsController.isTouch(): boolean
	return touchMode
end

function TouchControlsController.bind(name: string, h: Handlers)
	handlers[name] = h
end

function TouchControlsController.setShown(name: string, shown: boolean)
	if (wanted[name] == true) == shown then return end
	wanted[name] = shown
	refresh()
end

-- Biała ramka = stan włączony (trzymany sprint, celowanie) — jak wybrany slot paska.
function TouchControlsController.setLit(name: string, on: boolean)
	if (lit[name] == true) == on then return end
	lit[name] = on
	applyLit(name)
end

function TouchControlsController.init()
	if initialized then return end
	initialized = true

	-- Puszczenie liczymy na TYM SAMYM dotyku, gdziekolwiek palec się podniesie: `InputEnded`
	-- przycisku nie przychodzi, gdy palec zsunie się z niego w trakcie (wieczny sprint).
	UserInputService.InputEnded:Connect(function(input)
		for name, began in pairs(held) do
			if began == input then release(name) end
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		for name in pairs(held) do release(name) end
	end)

	task.spawn(function()
		while true do
			touchMode = detectTouch()
			place()
			refresh()
			task.wait(CFG.PollInterval)
		end
	end)

	task.spawn(function()
		local gui = localPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD")
		local c = gui:WaitForChild(CFG.ContainerName, 30)
		if not (gui:IsA("ScreenGui") and c and c:IsA("GuiObject")) then
			if UserInputService.TouchEnabled then
				warn(("[TouchControls] brak HUD.%s — na dotyku działają tylko gałka, skok i itemy"):format(CFG.ContainerName))
			end
			return
		end
		hud, container = gui, c
		fallbackPosition = c.Position
		for _, child in ipairs(c:GetChildren()) do
			if child:IsA("GuiButton") then hookButton(child.Name, child) end
		end
		place()
		refresh()
	end)
end

return TouchControlsController
