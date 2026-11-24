--[[
HUD_PREVIEW.luau (15.11) — podgląd w EDIT taki sam jak w Play.

Po co: w Play `HudScaleController` daje każdemu elementowi HUD skalę
„wysokość ekranu / Config.UI.ReferenceHeight” (min/max z Config). W Edit nic tego nie robi,
więc w placu zostawały stare, wymieszane skale (część 0,66, część żadna) i kasa w Edit
wyglądała na większą i wyżej niż w grze.

Jak: wklej CAŁY plik do Command Bar w Studio (tryb EDIT) i Enter. Liczy skalę z obecnego
rozmiaru okna — ten sam wzór co gra, łącznie z `FitHeight` (INVENTORY, drzewko). Po zmianie
rozmiaru okna Studio odpal jeszcze raz. Na grę nie wpływa: w Play kod i tak nadpisuje skale.
Zapis Cmd+S niepotrzebny (ale nie szkodzi).
]]

-- Klon modułu = świeży `require` (zwykły `require` w Command Bar trzyma starą wersję Config).
local configModule = game.ReplicatedStorage.Shared.Modules.Config:Clone()
local UI = require(configModule).UI
configModule:Destroy()

local hud = game.StarterGui:FindFirstChild("HUD")
local viewportY = if hud then hud.AbsoluteSize.Y else workspace.CurrentCamera.ViewportSize.Y
local factor = math.clamp(viewportY / UI.ReferenceHeight, UI.MinScale, UI.MaxScale)

local count = 0
for _, name in ipairs(UI.ScaledGuis) do
	local gui = game.StarterGui:FindFirstChild(name)
	if not gui then continue end
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute("NoHudScale") ~= true then
			local scale = factor
			local designH = child.Size.Y.Offset
			if child:GetAttribute("FitHeight") == true and designH > 0 then
				scale = math.min(scale, viewportY * UI.FitHeightFraction / designH)
			end
			local s = child:FindFirstChild("HudScale")
			if not (s and s:IsA("UIScale")) then
				s = Instance.new("UIScale")
				s.Name = "HudScale"
				s.Parent = child
			end
			s.Scale = scale
			count += 1
		end
	end
end
print(("[HUD_PREVIEW] okno %d px → skala %.3f, ustawione %d elementów"):format(viewportY, factor, count))
