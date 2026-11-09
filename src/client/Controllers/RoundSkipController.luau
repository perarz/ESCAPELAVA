--!strict
-- RoundSkipController.luau (06.11) — mała ramka SKIP po lewej od hotbara (Kacper: domyślnie grają
-- wszyscy, kto nie chce, klika; po kliknięciu DON'T SKIP cofa decyzję). Przełącznik trwa do
-- odkliknięcia. Sam nic nie decyduje: wysyła prośbę, a tekst i kolor bierze z atrybutu ustawionego
-- przez serwer (RoundSkipService).
--
-- KONTRAKT: StarterGui.HUD.<ButtonParent>.<ButtonName> (Config.RoundSkip) — przezroczysty przycisk
-- wielkości slotu, z `Fill` z UIGradient i `Label`
-- (cień kopiuje TextShadowController). Osobna ramka ma pozycję i skalę hotbara, więc ukrycie slotów nie ukrywa SKIP.
--
-- WIDOCZNOŚĆ: tylko gdy gracz stoi w lobby. Na mapie napis tylko by przeszkadzał, a kliknięcie
-- i tak zmieniłoby dopiero następną rundę. Na ekranie ROUND OVER (FINISHING, RESETTING) też
-- schowany (Kacper 09.11) — wraca razem z lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local RoundSkipState = require(script.Parent.RoundSkipState)
local ShopController = require(script.Parent.ShopController)

local RoundSkipController = {}

local CFG = Config.RoundSkip
local player = Players.LocalPlayer

local HIDDEN_STATES = { FINISHING = true, RESETTING = true }

local button: GuiButton? = nil
local onMap = false
local gameState = ""
local initialized = false

local function refresh()
	local btn = button
	if not btn then return end
	btn.Visible = not onMap and not HIDDEN_STATES[gameState] and not ShopController.isOpen()
		and player:GetAttribute("CosmeticsOpen") ~= true
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
		if typeof(state) ~= "string" then return end
		gameState = state
		-- Ocalałych serwer przenosi do lobby bez AliveChanged.
		if state == "LOBBY" then onMap = false end
		refresh()
	end)

	local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
	local parent = hud:WaitForChild(CFG.ButtonParent, 30)
	local btn = parent and parent:WaitForChild(CFG.ButtonName, 30)
	if not (btn and btn:IsA("GuiButton")) then
		warn(("[RoundSkip] brak HUD.%s.%s — pomijanie rund niedostępne"):format(CFG.ButtonParent, CFG.ButtonName))
		return
	end
	button = btn
	btn.Activated:Connect(function()
		Remotes.SetSkipRound:FireServer(not RoundSkipState.wantsSkip())
	end)
	refresh()
end

return RoundSkipController
