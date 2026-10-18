--!strict
-- GradientShimmerController.luau (10.10) — „żywy” gradient w UI (połysk przesuwający się po
-- napisie). Prośba Kacpra przy liczniku kasy: „gradient, taki co ciągle się rusza”.
--
-- KONTRAKT: `UIGradient` postawiony w Studio z atrybutem `ShimmerPeriod` (liczba, sekundy na
-- pełne kołysanie tam i z powrotem) → kod kołysze jego `Offset.X` sinusem ±`ShimmerAmplitude`
-- (atrybut, domyślnie 0,35 szerokości). Kolory, kąt (`Rotation`) i szerokość połysku ustawia się
-- na samym gradiencie w Studio. Działa dla całego PlayerGui, także dla UI dodanego później. Bez
-- atrybutu gradient stoi jak dotąd.
--
-- Do 10.10 (wieczór) przesuw szedł od −1 do 1 i wracał skokiem: na końcu przelotu napis
-- przeskakiwał z koloru jednego końca gradientu na drugi (Kacper: „nie płynny”). Sinus nie ma
-- skoku i cały czas widać gradient, a nie jeden kolor końca.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GradientShimmerController = {}

local ATTR = "ShimmerPeriod"
local DEFAULT_AMPLITUDE = 0.35
-- Zwykła (mocna) tabela: Roblox potrafi zebrać wpis z Instance jako SŁABYM kluczem, choć obiekt
-- żyje — połysk stawał wtedy w losowym momencie (ten sam błąd co ramka slotu w HotbarController).
-- Usunięte gradienty sprząta `step` po `Parent == nil`.
local tracked: { [UIGradient]: boolean } = {}
local initialized = false

local function track(inst: Instance)
	if inst:IsA("UIGradient") and typeof(inst:GetAttribute(ATTR)) == "number" then
		tracked[inst] = true
	end
end

local function step()
	local now = os.clock()
	for gradient in pairs(tracked) do
		if not gradient.Parent then
			tracked[gradient] = nil
			continue
		end
		local period = gradient:GetAttribute(ATTR)
		if typeof(period) ~= "number" or period <= 0 then continue end
		local amp = gradient:GetAttribute("ShimmerAmplitude")
		local amplitude = if typeof(amp) == "number" then amp else DEFAULT_AMPLITUDE
		gradient.Offset = Vector2.new(amplitude * math.sin(now * 2 * math.pi / period), gradient.Offset.Y)
	end
end

function GradientShimmerController.init()
	if initialized then return end
	initialized = true
	RunService.RenderStepped:Connect(step)
	-- task.spawn: WaitForChild yielduje, a kolejne kontrolery nie mogą na to czekać (hard rule 9).
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		playerGui.DescendantAdded:Connect(track)
		for _, inst in ipairs(playerGui:GetDescendants()) do
			track(inst)
		end
	end)
end

return GradientShimmerController
