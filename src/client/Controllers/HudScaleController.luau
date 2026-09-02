--!strict
-- HudScaleController.luau
-- Jednolite skalowanie HUD: każdy top-level element StarterGui.HUD dostaje UIScale
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

function HudScaleController.init()
	if initialized then return end
	initialized = true

	task.spawn(function()
		local pgui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local hud = pgui:WaitForChild("HUD", 10)
		if not hud or not hud:IsA("ScreenGui") then
			warn("[HudScale] PlayerGui.HUD nie istnieje — skalowanie nieaktywne")
			return
		end

		local function applyAll()
			-- AbsoluteSize ScreenGui = viewport minus GUI inset — właściwa baza.
			local factor = math.clamp(hud.AbsoluteSize.Y / CFG.ReferenceHeight, CFG.MinScale, CFG.MaxScale)
			for _, child in ipairs(hud:GetChildren()) do
				if child:IsA("GuiObject") then
					ensureScale(child).Scale = factor
				end
			end
		end

		applyAll()
		-- Zmiana rozmiaru okna / fullscreen toggle → przelicz.
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyAll)
		-- Elementy dodane później (np. kod tworzy nowe top-level nody) też dostają skalę.
		hud.ChildAdded:Connect(function(child)
			if child:IsA("GuiObject") then
				local factor = math.clamp(hud.AbsoluteSize.Y / CFG.ReferenceHeight, CFG.MinScale, CFG.MaxScale)
				ensureScale(child).Scale = factor
			end
		end)
	end)
end

return HudScaleController
