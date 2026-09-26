--!strict
-- PropService.luau
-- REKWIZYTY PO WYBUCHU (26.09, decyzje Kacpra) — JEDYNY właściciel stanu mebli, które wybuch
-- odepchnął w całości. Plan i decyzje: DESTRUCTION_PLAN.md → „Rekwizyty: wieszaki i meble”.
--
--   * pamięć trafień: mebel znosi JEDNO trafienie (odepchnięcie), drugie go rozwala
--   * odepchnięty mebel: spawy do największej części, fizyka serwera (`SetNetworkOwner(nil)` —
--     bryła z kolizją należąca do klienta to exploit), po `PushSettleTime` bezruchu kotwiczony
--     tam, gdzie leży. NIE przez DebrisService: ten rozłupuje kawałki przy twardym uderzeniu
--     (fall-fracture) i liczy przygniecenie — skrzynia to nie płyta stropu.
-- Co z rekwizytem zrobić (zniknięcie / rozpad / odepchnięcie), decyduje DestructionService —
-- tu tylko stan. Po rundzie MapService podmienia mapę na świeże klony, a słabe klucze
-- czyszczą się same.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Shockwave = require(ReplicatedStorage.Shared.Modules.Shockwave)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local PropService = {}

local PROPS = Config.Destruction.Props
local SMALL = Config.Destruction.Small

type Moving = { root: BasePart, parts: { BasePart }, since: number, stillSince: number? }

local hits: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local unitOfPart: { [BasePart]: Instance } = setmetatable({}, { __mode = "k" }) :: any
local moving: { Moving } = {}
local rng = Random.new()
local initialized = false

-- Ile razy wybuch odepchnął ten rekwizyt (0 = nietknięty).
function PropService.hitsOf(unit: Instance): number
	return hits[unit] or 0
end

-- Odepchnięty mebel, do którego należy part — także gdy już leży zakotwiczony. Kolejny
-- wybuch musi go poznać, zanim potraktuje jego party jak luźny gruz.
function PropService.pushedOf(part: BasePart): Instance?
	return unitOfPart[part]
end

function PropService.push(unit: Instance, center: Vector3, radius: number, impulse: number, minT: number)
	local parts: { BasePart } = {}
	if unit:IsA("BasePart") then
		table.insert(parts, unit)
	end
	for _, d in ipairs(unit:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return
	end
	table.sort(parts, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	local root = parts[1]
	-- Spawy PRZED odkotwiczeniem — inaczej części rozjadą się w pierwszej klatce.
	for i = 2, #parts do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = parts[i]
		w.Parent = parts[i]
	end
	for _, p in ipairs(parts) do
		p.Anchored = false
		unitOfPart[p] = unit
	end
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	-- Mebel dostaje ułamek impulsu bomby — to nie pocisk (ten sam współczynnik co drobnica).
	local d = Fracture.boxSurfaceDistance(Vector3.zero, root.Size, root.CFrame:PointToObjectSpace(center))
	local linear, angular = Shockwave.velocity(root.Position, root.Size, center, d, radius, impulse * SMALL.LaunchSpeedFactor, minT, rng)
	root.AssemblyLinearVelocity = linear
	root.AssemblyAngularVelocity = angular
	hits[unit] = (hits[unit] or 0) + 1
	table.insert(moving, { root = root, parts = parts, since = os.clock(), stillSince = nil })
end

-- Zatrzymany mebel kotwiczymy: zero fizyki i ruchu sieciowego, a stoi jak platforma.
-- `anchorAtRest` zeruje też prędkość — zakotwiczony part ją zachowuje (lekcja „taśmy” 25.09).
local function step()
	local now = os.clock()
	for i = #moving, 1, -1 do
		local m = moving[i]
		if not m.root.Parent then
			table.remove(moving, i)
			continue
		end
		local still = m.root.AssemblyLinearVelocity.Magnitude < 0.5 and m.root.AssemblyAngularVelocity.Magnitude < 0.5
		if still then
			m.stillSince = m.stillSince or now
		else
			m.stillSince = nil
		end
		local settled = m.stillSince ~= nil and now - (m.stillSince :: number) >= PROPS.PushSettleTime
		if settled or now - m.since >= PROPS.PushMaxTime then
			for _, p in ipairs(m.parts) do
				if p.Parent then
					Utils.anchorAtRest(p)
				end
			end
			table.remove(moving, i)
		end
	end
end

function PropService.init()
	if initialized then return end
	initialized = true
	RunService.Heartbeat:Connect(step)
end

return PropService
