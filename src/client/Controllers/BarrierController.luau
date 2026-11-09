--!strict
-- BarrierController.luau (09.11) — bariery na skraju mapy widać z bliska jako czerwone pole
-- siłowe (Kacper: „lekko migająca czerwona tekstura, żeby było wiadome, że nie można przejść”;
-- decyzje: tylko z bliska, materiał ForceField). Opis i liczby: `Config.Barrier`.
--
-- WYŁĄCZNIE WYGLĄD I WYŁĄCZNIE U TEGO GRACZA: materiał, kolor i przezroczystość ustawiamy na
-- kliencie, więc nie replikują się ani do serwera, ani do innych. Kolizja zostaje z placu
-- (CanCollide), promienie też — bariera dalej zatrzymuje i dalej jest pudłem dla haka.
-- Daleko od barier (prawie cała gra) nie dotykamy żadnej właściwości.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local CFG = Config.Barrier

local BarrierController = {}

local localPlayer = Players.LocalPlayer
local walls: { BasePart } = {}
local shown: { [BasePart]: number } = {} -- ostatnio ustawiona przezroczystość
local initialized = false

-- Ściany z placu; budowane od nowa, gdy którejś zabraknie (podmiana w Studio, restart mapy).
local function collect(): boolean
	table.clear(walls)
	table.clear(shown)
	local folder = Utils.barrierFolder()
	if not folder then return false end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.ForceField
			d.Color = CFG.Color
			d.CastShadow = false
			d.Transparency = 1
			shown[d] = 1
			table.insert(walls, d)
		end
	end
	return #walls > 0
end

-- Odległość punktu od POWIERZCHNI pudła ściany (0 w środku).
local function distanceTo(part: BasePart, point: Vector3): number
	local half = part.Size * 0.5
	local p = part.CFrame:PointToObjectSpace(point)
	local outside = Vector3.new(
		math.max(math.abs(p.X) - half.X, 0),
		math.max(math.abs(p.Y) - half.Y, 0),
		math.max(math.abs(p.Z) - half.Z, 0)
	)
	return outside.Magnitude
end

-- Postać, a bez niej (śmierć, obserwowanie) kamera.
local function viewer(): Vector3?
	local root = Utils.getRoot(localPlayer)
	if root then return root.Position end
	local cam = Workspace.CurrentCamera
	return cam and cam.CFrame.Position
end

local function step()
	if #walls == 0 or walls[1].Parent == nil then
		if not collect() then return end
	end
	local at = viewer()
	if not at then return end
	local wave = 0.5 + 0.5 * math.sin(os.clock() * 2 * math.pi / CFG.PulsePeriod)
	local pulse = CFG.PulseMin + (CFG.PulseMax - CFG.PulseMin) * wave
	for _, wall in ipairs(walls) do
		local d = distanceTo(wall, at)
		local seen = math.clamp((CFG.ShowDistance - d) / (CFG.ShowDistance - CFG.FullDistance), 0, 1)
		local t = 1 - seen * (1 - pulse)
		local last = shown[wall] or 1
		-- Bez zapisu, gdy nic się nie zmienia (daleko: stale 1).
		if math.abs(t - last) > 0.005 then
			wall.Transparency = t
			shown[wall] = t
		end
	end
end

function BarrierController.init()
	if initialized then return end
	initialized = true
	RunService.Heartbeat:Connect(step)
end

return BarrierController
