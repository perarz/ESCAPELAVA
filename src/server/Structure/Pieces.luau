--!strict
-- Pieces.luau
-- DESTRUKCJA v4, faza D — FIZYCZNE KAWAŁKI partów konstrukcji. Plan: DESTRUCTION_PLAN.md → „v4”.
--
-- Part konstrukcji z bake'u to na starcie jeden kawałek. Dziura dzieli go na pasy, grupa
-- kolapsu odcina go po granicy chunków, skruszony chunk zabiera swój fragment. Każdy kawałek
-- jest prostopadłościanem wyrównanym do osi świata (konstrukcją są tylko party wyrównane —
-- StructureCore.classify), więc całą geometrię da się liczyć na prostych pudełkach.
--
-- Zasada z v3, której nie łamiemy: ORYGINALNY part zostaje w świecie (przycięty), nowe
-- kawałki powstają obok — gracz stojący na oryginale nigdy nie traci gruntu pod nogami.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local Pieces = {}

export type Box = { min: Vector3, max: Vector3 }

local EPS = 1e-3

-- ============================================================================
-- Czysta geometria pudełek
-- ============================================================================

function Pieces.volume(b: Box): number
	local e = b.max - b.min
	return e.X * e.Y * e.Z
end

function Pieces.intersect(a: Box, b: Box, minSize: number): Box?
	local mn = a.min:Max(b.min)
	local mx = a.max:Min(b.max)
	local e = mx - mn
	if e.X <= minSize or e.Y <= minSize or e.Z <= minSize then
		return nil
	end
	return { min = mn, max = mx }
end

-- a minus b → najwyżej 6 pudełek (plasterki wzdłuż X, potem Y, potem Z).
function Pieces.subtract(a: Box, b: Box, minSize: number): { Box }
	if not Pieces.intersect(a, b, minSize) then
		return { a }
	end
	local out: { Box } = {}
	local function keep(mn: Vector3, mx: Vector3)
		local e = mx - mn
		if e.X > minSize and e.Y > minSize and e.Z > minSize then
			table.insert(out, { min = mn, max = mx })
		end
	end
	local mn, mx = a.min, a.max
	-- X
	keep(mn, Vector3.new(b.min.X, mx.Y, mx.Z))
	keep(Vector3.new(b.max.X, mn.Y, mn.Z), mx)
	local x0, x1 = math.max(mn.X, b.min.X), math.min(mx.X, b.max.X)
	-- Y (w środkowym plastrze X)
	keep(Vector3.new(x0, mn.Y, mn.Z), Vector3.new(x1, b.min.Y, mx.Z))
	keep(Vector3.new(x0, b.max.Y, mn.Z), Vector3.new(x1, mx.Y, mx.Z))
	local y0, y1 = math.max(mn.Y, b.min.Y), math.min(mx.Y, b.max.Y)
	-- Z (w środkowym plastrze X i Y)
	keep(Vector3.new(x0, y0, mn.Z), Vector3.new(x1, y1, b.min.Z))
	keep(Vector3.new(x0, y0, b.max.Z), Vector3.new(x1, y1, mx.Z))
	return out
end

-- Łączy pudełka, które razem tworzą pudełko (wspólna ściana na całej powierzchni).
-- Mniej kawałków = mniej nowych instancji do replikacji.
function Pieces.merge(boxes: { Box }): { Box }
	local list = table.clone(boxes)
	local changed = true
	while changed do
		changed = false
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				local same = 0
				local touchAxis: string? = nil
				for _, ax in ipairs({ "X", "Y", "Z" }) do
					local amn, amx = (a.min :: any)[ax], (a.max :: any)[ax]
					local bmn, bmx = (b.min :: any)[ax], (b.max :: any)[ax]
					if math.abs(amn - bmn) < EPS and math.abs(amx - bmx) < EPS then
						same += 1
					elseif math.abs(amx - bmn) < EPS or math.abs(bmx - amn) < EPS then
						touchAxis = ax
					end
				end
				if same == 2 and touchAxis then
					list[i] = { min = a.min:Min(b.min), max = a.max:Max(b.max) }
					table.remove(list, j)
					changed = true
					break
				end
			end
			if changed then break end
		end
	end
	return list
end

-- ============================================================================
-- Kawałek w świecie
-- ============================================================================

function Pieces.boxOf(part: BasePart): Box
	local cf, s = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local half = Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	) * 0.5
	return { min = cf.Position - half, max = cf.Position + half }
end

-- Rozmiar w osiach parta dla pudełka w osiach świata (part obrócony o wielokrotność 90°).
local function localSize(cf: CFrame, worldSize: Vector3): Vector3
	local function along(v: Vector3): number
		return math.abs(v.X) * worldSize.X + math.abs(v.Y) * worldSize.Y + math.abs(v.Z) * worldSize.Z
	end
	return Vector3.new(along(cf.RightVector), along(cf.UpVector), along(cf.LookVector))
end

local function placed(cf: CFrame, b: Box): (CFrame, Vector3)
	local rot = cf - cf.Position
	return CFrame.new((b.min + b.max) * 0.5) * rot, localSize(cf, b.max - b.min)
end

-- Przycina ISTNIEJĄCY part do pudełka (obrót zostaje). Oryginał zostaje w świecie.
function Pieces.setBox(part: BasePart, b: Box)
	local cf, size = placed(part.CFrame, b)
	part.Size = size
	part.CFrame = cf
end

-- Nowy kawałek z wyglądem i zachowaniem źródła (hard rule 15: wygląd przez
-- Utils.copyAppearance — sam Material dałby goły plastik bez wariantu „Studs”).
-- Tekstury (tapety) przechodzą, Decale nie — obrazek powieliłby się na każdym kawałku.
function Pieces.spawn(source: BasePart, cf: CFrame, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = source.Name
	part.Size = size
	part.CFrame = cf
	Utils.copyAppearance(source, part)
	part.Anchored = true
	part.CanCollide = source.CanCollide
	part.CanQuery = source.CanQuery
	part.CanTouch = source.CanTouch
	part.CollisionGroup = source.CollisionGroup
	for _, child in ipairs(source:GetChildren()) do
		if child:IsA("Texture") then
			child:Clone().Parent = part
		end
	end
	for name, value in pairs(source:GetAttributes()) do
		part:SetAttribute(name, value)
	end
	part.Parent = source.Parent
	return part
end

function Pieces.spawnBox(source: BasePart, b: Box): Part
	local cf, size = placed(source.CFrame, b)
	return Pieces.spawn(source, cf, size)
end

return Pieces
