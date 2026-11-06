--!strict
-- RoundSkipController.luau (06.11) — mała ramka SKIP pod licznikiem (Kacper: domyślnie grają
-- wszyscy, kto nie chce, klika; po kliknięciu DON'T SKIP cofa decyzję). Przełącznik trwa do
-- odkliknięcia. Sam nic nie decyduje: wysyła prośbę, a tekst i kolor bierze z atrybutu ustawionego
-- przez serwer (RoundSkipService).
--
-- KONTRAKT: StarterGui.HUD.<ButtonParent>.<ButtonName> (Config.RoundSkip) — przezroczysty przycisk
-- większy od ramki (pole kliknięcia), z UIScale `Pop`, `Fill` z UIGradient (mini ramka) i `Label`
-- (cień kopiuje TextShadowController). Jako dziecko licznika skaluje się razem z nim; osobny
-- element z offsetem rozjeżdżałby się przy innej wysokości ekranu.
--
-- WIDOCZNOŚĆ: tylko gdy gracz stoi w lobby. Na mapie napis tylko by przeszkadzał, a kliknięcie
-- i tak zmieniłoby dopiero następną rundę.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local RoundSkipState = require(script.Parent.RoundSkipState)
local ShopController = require(script.Parent.ShopController)

local RoundSkipController = {}

local CFG = Config.RoundSkip
local player = Players.LocalPlayer

local button: GuiButton? = nil
local onMap = false
local initialized = false

local function refresh()
	local btn = button
	if not btn then return end
	btn.Visible = not onMap and not ShopController.isOpen() and player:GetAttribute("CosmeticsOpen") ~= true
	local wants = RoundSkipState.wantsSkip()
	local label = btn:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = if wants then CFG.TextOn else CFG.TextOff
	end
	local fill = btn:FindFirstChild("Fill")
	local gradient = fill and fill:FindFirstChildOfClass("UIGradient")
	if gradient then
		local colors = if wants then CFG.ColorsOn else CFG.ColorsOff
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	if fill and fill:IsA("GuiObject") then
		-- Wysokość z Studio; szerokość idzie za długością napisu. Przycisk i pole kliknięcia stoją.
		local width = if wants then CFG.WidthOn else CFG.WidthOff
		local goal = UDim2.fromOffset(width, fill.Size.Y.Offset)
		TweenService:Create(fill, TweenInfo.new(CFG.ResizeTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = goal }):Play()
	end
end

local function hookAnimation(btn: GuiButton)
	local scale = btn:FindFirstChild("Pop")
	if not (scale and scale:IsA("UIScale")) then return end
	local pop: UIScale = scale
	local hoverInfo = TweenInfo.new(CFG.HoverTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		-- Na dotyku `MouseLeave` często nie przychodzi i przycisk zostałby powiększony.
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		TweenService:Create(pop, hoverInfo, { Scale = CFG.HoverScale }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(pop, hoverInfo, { Scale = 1 }):Play()
	end)
	btn.Activated:Connect(function()
		pop.Scale = CFG.PressFrom
		TweenService:Create(pop, TweenInfo.new(CFG.PressTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

function RoundSkipController.init()
	if initialized then return end
	initialized = true

	-- Listenery PRZED czekaniem na HUD (zasada 9).
	RoundSkipState.onChanged(refresh)
	player:GetAttributeChangedSignal("CosmeticsOpen"):Connect(refresh)
	ShopController.onOpenChanged(function() refresh() end)
	Remotes.AliveChanged.OnClientEvent:Connect(function(isAlive: any)
		onMap = isAlive == true
		refresh()
	end)
	Remotes.GameStateChanged.OnClientEvent:Connect(function(state: any)
		-- Ocalałych serwer przenosi do lobby bez AliveChanged.
		if state == "LOBBY" then
			onMap = false
			refresh()
		end
	end)

	local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
	local parent = hud:WaitForChild(CFG.ButtonParent)
	local btn = parent:WaitForChild(CFG.ButtonName, 30)
	if not (btn and btn:IsA("GuiButton")) then
		warn(("[RoundSkip] brak HUD.%s.%s — pomijanie rund niedostępne"):format(CFG.ButtonParent, CFG.ButtonName))
		return
	end
	button = btn
	hookAnimation(btn)
	btn.Activated:Connect(function()
		Remotes.SetSkipRound:FireServer(not RoundSkipState.wantsSkip())
	end)
	refresh()
end

return RoundSkipController
