--!strict
-- GrappleArc.luau
-- Kształt lotu hakiem: parabola (kwadratowa krzywa Béziera) od startu do celu, ze szczytem
-- nad linią prostą. Dlaczego parabola PROWADZONA, a nie rzut — patrz historia przy
-- Config.Grapple (trzy odrzucone modele).
--
-- Shared, bo z tej samej krzywej korzystają obie strony:
--   serwer — czas lotu, czyli okna anti-cheata i wyłączenia ragdolla w locie
--   klient — trajektoria, po której prowadzi postać
-- Dwie kopie tego wzoru rozjechałyby się dokładnie tak, jak rozjechałby się ghost mostu
-- liczony osobno przez klienta i serwer (ta sama zasada co `ItemDefinitions.worldSize`):
-- serwer zamknąłby okno bezkarności, zanim klient dolatuje, i anti-cheat zabiłby gracza
-- w końcówce lotu.

local Config = require(script.Parent.Config)

local CFG = Config.Grapple

local GrappleArc = {}

export type Arc = {
	p0: Vector3,       -- start
	p1: Vector3,       -- punkt kontrolny (nad środkiem cięciwy)
	p2: Vector3,       -- cel — lot KOŃCZY się dokładnie tutaj
	duration: number,  -- sekundy lotu przy średniej prędkości Config.Grapple.FlightSpeed
}

-- Długość łuku liczona numerycznie: kwadratowy Bézier nie ma ładnego wzoru na długość,
-- a 16 odcinków daje błąd rzędu setnych części studa przy łukach, jakie tu powstają.
local LENGTH_SAMPLES = 16

function GrappleArc.point(arc: Arc, s: number): Vector3
	local u = 1 - s
	return arc.p0 * (u * u) + arc.p1 * (2 * u * s) + arc.p2 * (s * s)
end

-- Pochodna po parametrze KRZYWEJ s, nie po czasie — na prędkość przelicza `ease`.
function GrappleArc.derivative(arc: Arc, s: number): Vector3
	return (arc.p1 - arc.p0) * (2 * (1 - s)) + (arc.p2 - arc.p1) * (2 * s)
end

function GrappleArc.plan(from: Vector3, goal: Vector3): Arc
	local chord = goal - from
	-- Wysokość łuku od dystansu POZIOMEGO: przy wspinaczce pionowo w górę łuku nie ma
	-- (wyglądałby jak błąd), a przy locie na wprost jest pełny.
	local horizontal = Vector3.new(chord.X, 0, chord.Z).Magnitude
	local height = math.min(horizontal * CFG.ArcRatio, CFG.ArcMax)
	-- Szczyt kwadratowego Béziera leży w połowie drogi od cięciwy do punktu kontrolnego,
	-- więc żeby łuk wznosił się `height` nad cięciwą, kontrolny idzie DWA RAZY wyżej.
	local p1 = (from + goal) * 0.5 + Vector3.new(0, 2 * height, 0)

	local arc: Arc = { p0 = from, p1 = p1, p2 = goal, duration = 0 }
	local length, prev = 0, from
	for i = 1, LENGTH_SAMPLES do
		local q = GrappleArc.point(arc, i / LENGTH_SAMPLES)
		length += (q - prev).Magnitude
		prev = q
	end
	arc.duration = length / CFG.FlightSpeed
	return arc
end

-- Tempo po łuku: s(u) = u + k·u·(1−u), gdzie u = upływ czasu 0..1.
-- Na starcie (1 + k) × średnia — szarpnięcie; na końcu (1 − k) × średnia — „dolecisz",
-- a nie „rąbniesz". Zwraca (s, ds/du).
function GrappleArc.ease(u: number): (number, number)
	local k = CFG.ArcEase
	return u + k * u * (1 - u), 1 + k * (1 - 2 * u)
end

return GrappleArc
