--!strict
-- HudScaleController.luau
-- Jednolite skalowanie HUD (i od 18.10 panelu Inventory): każdy top-level element dostaje UIScale
-- (name: "HudScale") = viewportY / Config.UI.ReferenceHeight.
--
-- Model projektowania (ustalony z Kacprem, 2026-07-05):
--   * HUD projektowany W PIKSELACH przy 2560×1440 (monitor Kacpra = skala 1.0 — to co
--     widzi w Studio to dokładnie design).
--   * Pozycje elementów: AnchorPoint do najbliższej krawędzi/rogu + px margines w Position
--     offset. Marginesy NIE skalują się (celowo — "przy krawędzi" znaczy przy krawędzi
--     na każdym monitorze; to naprawia dryf elementów między aspect ratio 16:9/16:10).
--   * Rozmiary top-level: px (Offset). Wnętrza elementów: Scale-of-parent lub px — oba
--     działają, bo UIScale mnoży CAŁE poddrzewo (rozmiary, offsety i TEKST jednolicie).
--
-- Skala liczona z WYSOKOŚCI ekranu (nie szerokości) — na ultrawide HUD nie puchnie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local HudScaleController = {}

local CFG = Config.UI
local initialized = false

local function ensureScale(element: GuiObject): UIScale
	local existing = element:FindFirstChild("HudScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "HudScale"
	scale.Parent = element
	return scale
end

-- Jedna reguła dla każdego ScreenGui z listy `Config.UI.ScaledGuis` (18.10: HUD + Inventory).
-- Element z atrybutem `NoHudScale = true` zostaje bez skali (np. pełnoekranowe tło panelu —
-- przy skali < 1 przestałoby zakrywać ekran).
local function scaleGui(gui: ScreenGui)
	local function factor(): number
		-- AbsoluteSize ScreenGui = viewport minus GUI inset — właściwa baza.
		return math.clamp(gui.AbsoluteSize.Y / CFG.ReferenceHeight, CFG.MinScale, CFG.MaxScale)
	end
	local function apply(child: Instance, f: number)
		if child:IsA("GuiObject") and child:GetAttribute("NoHudScale") ~= true then
			ensureScale(child).Scale = f
		end
	end
	local function applyAll()
		local f = factor()
		for _, child in ipairs(gui:GetChildren()) do
			apply(child, f)
		end
	end
	applyAll()
	-- Zmiana rozmiaru okna / fullscreen toggle → przelicz.
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyAll)
	-- Elementy dodane później (np. kod tworzy nowe top-level nody) też dostają skalę.
	gui.ChildAdded:Connect(function(child)
		apply(child, factor())
	end)
end

function HudScaleController.init()
	if initialized then return end
	initialized = true

	local pgui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, name in ipairs(CFG.ScaledGuis) do
		task.spawn(function()
			local gui = pgui:WaitForChild(name)
			if gui:IsA("ScreenGui") then
				scaleGui(gui)
			end
		end)
	end
end

return HudScaleController
