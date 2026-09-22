-- COFNIĘCIE LIGHTINGU do stanu sprzed 2026-09-16 (wklej do Command Bar w Studio i Enter).
-- Zapisane ZANIM Claude przestawił oświetlenie — jeśli stare podobało Ci się bardziej,
-- albo chcesz wrócić po kawałku, bierz stąd pojedyncze linijki.
local L = game:GetService("Lighting")

L.Brightness = 2.2
L.ExposureCompensation = 0.25
L.ClockTime = 14
L.GeographicLatitude = 41.7
L.Ambient = Color3.fromRGB(160, 160, 160)
L.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
L.ColorShift_Top = Color3.fromRGB(255, 255, 255)
L.ColorShift_Bottom = Color3.fromRGB(255, 255, 255)
L.EnvironmentDiffuseScale = 1
L.EnvironmentSpecularScale = 0.6
L.ShadowSoftness = 0.1
L.FogStart = 0
L.FogEnd = 12000
L.FogColor = Color3.fromRGB(255, 255, 255)

local atmo = L:FindFirstChildOfClass("Atmosphere")
if atmo then
	atmo.Density = 0.229
	atmo.Offset = 0.208
	atmo.Glare = 0.78
	atmo.Haze = 0.16
	atmo.Color = Color3.fromRGB(255, 255, 255)
	atmo.Decay = Color3.fromRGB(255, 255, 255)
end

local bloom = L:FindFirstChildOfClass("BloomEffect")
if bloom then
	bloom.Enabled = true
	bloom.Intensity = 0.85
	bloom.Size = 36
	bloom.Threshold = 0.8
end

local cc = L:FindFirstChild("ColorCorrection")
if cc and cc:IsA("ColorCorrectionEffect") then
	cc.Enabled = true
	cc.Brightness = -0.2
	cc.Contrast = 0.6
	cc.Saturation = 0.3
	cc.TintColor = Color3.fromRGB(198, 249, 255)
end

local rays = L:FindFirstChildOfClass("SunRaysEffect")
if rays then
	rays.Enabled = true
	rays.Intensity = 0.35
	rays.Spread = 1
end

local blur = L:FindFirstChildOfClass("BlurEffect")
if blur then
	blur.Enabled = true
	blur.Size = 0
end

print("[Lighting] przywrocono wartosci sprzed 2026-09-16")
