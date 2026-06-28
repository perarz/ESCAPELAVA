--!strict
-- ShopController.luau
-- Toggle ShopMenu, render oferty z ItemDefinitions, fire BuyItem na klik.
-- Klient NIGDY nie modyfikuje inventory/coins — tylko intent → server.
--
-- KONTRAKT NAZW w StarterGui (postawione przez MCP, Kacper modyfikuje styl):
--   StarterGui.HUD.ShopButton (TextButton)
--   StarterGui.HUD.ShopMenu (Frame, Visible=false domyślnie)
--     ├── CloseButton (TextButton)
--     ├── StatusLabel (TextLabel)
--     └── Offers (ScrollingFrame)
--         └── OfferTemplate (Frame, Visible=false; klient klonuje per oferta)
--             ├── ItemName (TextLabel)
--             ├── Price (TextLabel)
--             └── BuyButton (TextButton)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local ShopController = {}

local localPlayer = Players.LocalPlayer

local REASON_TEXT = {
	rate_limited = "Za szybko klikasz",
	alive_in_round = "Sklep niedostępny w trakcie rundy",
	unknown_item = "Nieznany przedmiot",
	not_enough_cash = "Nie masz tyle kasy",
	inventory_full = "Plecak pełny",
	internal_error = "Błąd serwera, spróbuj ponownie",
	invalid_payload = "Błąd klienta",
}

local function showStatus(statusLabel: TextLabel, text: string, color: Color3)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	-- Auto-clear po 3s
	task.delay(3, function()
		if statusLabel.Text == text then
			statusLabel.Text = ""
		end
	end)
end

local function renderOffers(offersContainer: ScrollingFrame, template: Frame)
	-- Wyczyść stare offer'y (oprócz template i UIListLayout)
	for _, child in ipairs(offersContainer:GetChildren()) do
		if child:IsA("Frame") and child.Name == "Offer" then
			child:Destroy()
		end
	end

	for layoutOrder, itemId in ipairs(ItemDefinitions.shopOrder) do
		local def = ItemDefinitions.get(itemId)
		if not def then continue end

		local offer = template:Clone()
		offer.Name = "Offer"
		offer.Visible = true
		offer.LayoutOrder = layoutOrder
		offer.Parent = offersContainer

		local nameLabel = offer:FindFirstChild("ItemName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = def.name
		end
		local priceLabel = offer:FindFirstChild("Price")
		if priceLabel and priceLabel:IsA("TextLabel") then
			priceLabel.Text = "💰 " .. tostring(def.price)
		end
		local buyBtn = offer:FindFirstChild("BuyButton")
		if buyBtn and buyBtn:IsA("TextButton") then
			buyBtn.Activated:Connect(function()
				Remotes.BuyItem:FireServer(itemId)
			end)
		end
	end
end

local function setupShop()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD", 10)
	if not hud then
		warn("[ShopController] PlayerGui.HUD nie istnieje")
		return
	end

	local button = hud:WaitForChild("ShopButton", 5)
	local menu = hud:WaitForChild("ShopMenu", 5)
	if not button or not menu then
		warn("[ShopController] ShopButton lub ShopMenu nie istnieje")
		return
	end

	-- CloseButton może siedzieć płytko pod ShopMenu lub zagłębione (np. w header Frame).
	-- Rekursywny find żeby Kacper mógł przebudowywać layout w Studio bez kodu.
	local closeBtn = menu:FindFirstChild("CloseButton", true)
	local statusLabel = menu:FindFirstChild("StatusLabel")
	local offers = menu:FindFirstChild("Offers")
	local template = offers and offers:FindFirstChild("OfferTemplate")

	if not (offers and template and statusLabel) then
		warn("[ShopController] menu brakuje child'ów (Offers / OfferTemplate / StatusLabel)")
		return
	end

	renderOffers(offers :: ScrollingFrame, template :: Frame)

	-- Toggle menu — akceptuje TextButton i ImageButton (Kacper zmienił styling)
	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			menu.Visible = not menu.Visible
		end)

		-- Hover effect: powiększenie + lekka rotacja.
		-- Pivot rotacji = center ikonki (żeby children — TextLabel "SHOP" — obracali się
		-- razem z ikonką wokół tego samego punktu, a nie swingowali po łuku z górno-lewego rogu).
		local guiButton = button :: GuiButton
		local absSize = guiButton.AbsoluteSize
		local oldAnchor = guiButton.AnchorPoint
		local oldPosition = guiButton.Position
		guiButton.AnchorPoint = Vector2.new(0.5, 0.5)
		guiButton.Position = UDim2.new(
			oldPosition.X.Scale, oldPosition.X.Offset + absSize.X * (0.5 - oldAnchor.X),
			oldPosition.Y.Scale, oldPosition.Y.Offset + absSize.Y * (0.5 - oldAnchor.Y)
		)

		local originalSize = guiButton.Size
		local originalRotation = guiButton.Rotation
		local hoverSize = UDim2.new(
			originalSize.X.Scale * 1.1, originalSize.X.Offset * 1.1,
			originalSize.Y.Scale * 1.1, originalSize.Y.Offset * 1.1
		)
		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		guiButton.MouseEnter:Connect(function()
			TweenService:Create(guiButton, tweenInfo, {
				Size = hoverSize,
				Rotation = originalRotation - 5,
			}):Play()
		end)
		guiButton.MouseLeave:Connect(function()
			TweenService:Create(guiButton, tweenInfo, {
				Size = originalSize,
				Rotation = originalRotation,
			}):Play()
		end)
	else
		warn("[ShopController] HUD.ShopButton nie jest GuiButton (TextButton/ImageButton) — nie będzie klikalne")
	end

	-- Akceptuje TextButton i ImageButton (Kacper zmienił styling header'a → ImageButton X)
	if closeBtn and closeBtn:IsA("GuiButton") then
		closeBtn.Activated:Connect(function()
			menu.Visible = false
		end)
	else
		warn("[ShopController] ShopMenu.CloseButton nie istnieje lub nie jest GuiButton")
	end

	-- ShopResult handler
	Remotes.ShopResult.OnClientEvent:Connect(function(success: boolean, itemId: string, reason: string?)
		if success then
			local def = ItemDefinitions.get(itemId)
			local name = def and def.name or itemId
			showStatus(statusLabel :: TextLabel, "Kupiono " .. name, Color3.fromRGB(120, 220, 120))
		else
			local text = REASON_TEXT[reason or ""] or ("Błąd: " .. tostring(reason))
			showStatus(statusLabel :: TextLabel, text, Color3.fromRGB(255, 120, 120))
		end
	end)
end

function ShopController.init()
	-- Podpinamy ShopResult listener PRZED setupShop (yieldy na WaitForChild),
	-- bo server może fire'ować ShopResult w innych momentach.
	-- Actually setupShop podpina ShopResult; ten init.client robi require + init().
	setupShop()
end

return ShopController
