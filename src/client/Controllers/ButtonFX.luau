--!strict
-- ButtonFX.luau
-- Wspólne efekty hover dla przycisków HUD (Shop, Daily Rewards, przyszłe kafelki).
-- Moduł-helper, NIE kontroler (brak init) — kontrolery wołają applyTileHover przy setupie.
--
-- Efekt hover kafelka: lekki obrót + rozjaśnienie tekstury. Rotation nie wpływa na
-- UIListLayout (layout mierzy nieobrócony box), więc bezpieczne w HUD.SideButtons —
-- drugi kafelek nie drga gdy pierwszy się obraca.

local TweenService = game:GetService("TweenService")

local ButtonFX = {}

local TI_IN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_ROTATION = -4       -- stopnie; ujemne = lekki przechył w lewo
local GLOW_TRANSPARENCY = 0.86  -- docelowa transparency białej nakładki na hover (1 = brak)

local function makeGlow(tile: GuiObject): Frame
	-- Biała półprzezroczysta nakładka = uniwersalne "rozjaśnienie" kafelka.
	-- (Tintowanie ImageColor3 nie działa gdy bazowy tint jest biały — brak headroomu.)
	-- ZIndex niżej niż wewnętrzny przycisk (5) → glow leży na BG, pod stroke/ikoną/tekstem.
	local glow = Instance.new("Frame")
	glow.Name = "HoverGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0.5, 0)
	glow.Size = UDim2.new(0.96, 0, 0.94, 0)
	glow.BackgroundColor3 = Color3.new(1, 1, 1)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = glow
	glow.Parent = tile
	return glow
end

function ButtonFX.applyTileHover(tile: GuiObject)
	local baseRotation = tile.Rotation
	local glow = makeGlow(tile)

	tile.MouseEnter:Connect(function()
		TweenService:Create(tile, TI_IN, { Rotation = baseRotation + HOVER_ROTATION }):Play()
		TweenService:Create(glow, TI_IN, { BackgroundTransparency = GLOW_TRANSPARENCY }):Play()
	end)
	tile.MouseLeave:Connect(function()
		TweenService:Create(tile, TI_OUT, { Rotation = baseRotation }):Play()
		TweenService:Create(glow, TI_OUT, { BackgroundTransparency = 1 }):Play()
	end)
end

return ButtonFX
