--!strict
-- C4Path.luau (01.11)
-- Tor lotu C4 jako wzór od czasu: rzut i spadanie po utracie podłoża (grawitacja z sufitem
-- prędkości spadania) plus koziołkowanie wokół osi.
--
-- Shared, bo z tego samego wzoru korzystają obie strony:
--   serwer — gdzie ładunek jest i gdzie się przyklei (promień co klatkę)
--   klient — płynna kopia w locie, liczona od czasu serwera (C4Controller)
-- Dlaczego kopia u klienta (zgłoszenia Kacpra 01.11): ładunek przestawiany przez serwer co
-- klatkę dojeżdżał do graczy skokowo, a fizyka serwera (próba z 01.11) — z opóźnieniem na
-- starcie i przeskokiem przy przyklejeniu. Dwie osobne kopie wzoru rozjechałyby się, więc
-- jest jeden.

local Config = require(script.Parent.Config)

local CFG = Config.C4

local C4Path = {}

-- Środek bbox po `t` s lotu.
function C4Path.position(origin: Vector3, vel: Vector3, t: number): Vector3
	local g, cap = CFG.Gravity, CFG.FallMaxSpeed
	-- Chwila, w której spadanie dochodzi do sufitu; dalej leci w dół ze stałą prędkością.
	local tc = math.max((vel.Y + cap) / g, 0)
	local y
	if t <= tc then
		y = vel.Y * t - 0.5 * g * t * t
	else
		y = vel.Y * tc - 0.5 * g * tc * tc - cap * (t - tc)
	end
	return origin + Vector3.new(vel.X * t, y, vel.Z * t)
end

-- Ramka bbox po `t` s: pozycja z toru, obrót startowy zakręcony wokół `axis` (świat).
function C4Path.frame(start: CFrame, vel: Vector3, axis: Vector3, t: number): CFrame
	return CFrame.new(C4Path.position(start.Position, vel, t))
		* CFrame.fromAxisAngle(axis, CFG.Spin * t) * start.Rotation
end

return C4Path
