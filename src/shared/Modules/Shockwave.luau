--!strict
-- Shockwave.luau
-- Matematyka fali uderzeniowej: w którą stronę i jak szybko leci kawałek wyrzucony przez
-- wybuch. JEDNA dla serwera i klienta (2026-09-23): serwer pcha nią gruz serwerowy, a klient
-- wystrzeliwuje nią kawałki dziury, które od v3 animuje u siebie. Dwie kopie tych wzorów
-- dałyby dwa różne „odczucia” wybuchu zależnie od tego, czy kawałek jest serwerowy.
--
-- Liczby w `Config.Destruction.Shockwave`. Przeniesione 1:1 z DestructionService (a tam ze
-- sprawdzonych lekcji starego systemu — patrz DESTRUCTION_PLAN.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local WAVE = Config.Destruction.Shockwave

local Shockwave = {}

-- Stożek "na zewnątrz i w górę": stromo w epicentrum (jedyna wolna droga to góra),
-- płasko na krawędzi (wolna przestrzeń w bok). Nigdy w dół.
function Shockwave.direction(position: Vector3, center: Vector3, distance: number, radius: number, rng: Random): Vector3
	local delta = position - center
	local horizontal = Vector3.new(delta.X, 0, delta.Z)

	local dir: Vector3
	if horizontal.Magnitude < 0.5 then
		dir = Vector3.yAxis
	else
		local frac = math.clamp(distance / radius, 0, 1)
		local angle = math.rad(WAVE.AngleNear + (WAVE.AngleFar - WAVE.AngleNear) * frac)
		dir = horizontal.Unit * math.cos(angle) + Vector3.yAxis * math.sin(angle)
	end

	-- Jitter — bez niego siatka podobnych kawałków leci jak jeden sztywny blok.
	if WAVE.AngleJitter > 0 then
		local j = math.tan(math.rad(WAVE.AngleJitter))
		dir = dir + Vector3.new(
			(rng:NextNumber() * 2 - 1) * j,
			(rng:NextNumber() * 2 - 1) * j,
			(rng:NextNumber() * 2 - 1) * j
		)
	end

	-- GWARANCJA: nigdy w dół (podłoga pod bombą z pełną siłą wbitą w ziemię = zero wizualnie).
	if dir.Y < 0.05 then
		dir = Vector3.new(dir.X, 0.05, dir.Z)
	end
	return dir.Unit
end

-- Mały kafel wystrzeliwuje, wielka płyta się osuwa.
function Shockwave.sizeScale(size: Vector3): number
	local volume = math.max(size.X * size.Y * size.Z, 0.001)
	return math.clamp((WAVE.ReferenceChunkVolume / volume) ^ WAVE.SizeFalloffPower, WAVE.MinSizeScale, 1)
end

-- Prędkość liniowa i kątowa kawałka o rozmiarze `size`, leżącego `distance` studów od
-- epicentrum (dystans do POWIERZCHNI — liczy caller). `minT` = floor falloffu: krawędź
-- zasięgu ma drgnąć, nie stać.
function Shockwave.velocity(
	position: Vector3,
	size: Vector3,
	center: Vector3,
	distance: number,
	radius: number,
	impulse: number,
	minT: number,
	rng: Random
): (Vector3, Vector3)
	local t = math.max(1 - distance / math.max(radius, 0.001), minT)
	local scale = Shockwave.sizeScale(size)
	local linear = Shockwave.direction(position, center, distance, radius, rng) * impulse * t * scale
	local angular = Vector3.new(
		(rng:NextNumber() * 2 - 1) * WAVE.Spin,
		(rng:NextNumber() * 2 - 1) * WAVE.Spin,
		(rng:NextNumber() * 2 - 1) * WAVE.Spin
	) * (t * scale)
	return linear, angular
end

return Shockwave
