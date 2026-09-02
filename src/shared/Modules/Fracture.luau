--!strict
-- Fracture.luau
-- Czysta matematyka cięcia prostopadłościanu na nierówne kawałki (system destrukcji v2,
-- DESTRUCTION_PLAN.md). Zero Instance, zero side effectów — sam PLAN cięcia w local space
-- parta. Deterministyczna przy tym samym Random — serwer i klient mogą niezależnie
-- generować spójne wzory.
--
-- Algorytm: iteracyjny podział nierównymi płaszczyznami. Bierzemy box, tniemy najdłuższą
-- oś w losowym punkcie 30-70%, powtarzamy aż wszystko <= targetSize. Nierówne cięcia dają
-- "kostkę gruzu" zamiast idealnej siatki kafelków — kluczowa różnica między gruzem a LEGO.
--
-- Adaptacyjność (focus): kawałki POZA kulą wybuchu nie są docinane do targetSize — zostają
-- DUŻE (wracają do świata jako anchored "remnant" ściany). Dzięki temu dziura po bombie ma
-- drobny gruz, a reszta panelu to 2-4 płyty, nie 60 kafelków.

export type Chunk = {
	offset: Vector3, -- środek kawałka w LOCAL space oryginalnego parta
	size: Vector3,
}

-- Kula wybuchu w LOCAL space parta (center = CFrame:PointToObjectSpace(blastCenter)).
export type Focus = {
	center: Vector3,
	radius: number,
}

local Fracture = {}

-- Odległość punktu od POWIERZCHNI boxa (0 gdy punkt w środku). Lekcja ze starego systemu:
-- dystans do środka parta kłamie dla dużych paneli (strop 26×26 nad bombą miał "15 studów").
function Fracture.boxSurfaceDistance(boxCenter: Vector3, boxSize: Vector3, point: Vector3): number
	local d = point - boxCenter
	local h = boxSize * 0.5
	local dx = math.max(math.abs(d.X) - h.X, 0)
	local dy = math.max(math.abs(d.Y) - h.Y, 0)
	local dz = math.max(math.abs(d.Z) - h.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Tnie box o rozmiarze `size` na kawałki ~targetSize.
--   minSize   — wymiar poniżej którego NIE tniemy (drobnica = particle klienta, nie party)
--   maxChunks — twardy sufit liczby kawałków (duży panel nie może urodzić setek partów);
--               po osiągnięciu limitu reszta zostaje w większych kawałkach
--   focus     — opcjonalna kula wybuchu: kawałki poza nią nie są docinane (patrz nagłówek)
-- STRATEGIA CIĘCIA (przepisana 2026-08-12 po teście Kacpra "cała ściana wylatuje
-- zamiast dziury"): zamiast przechodzić boxy w dowolnej kolejności (stack LIFO) i cofać
-- się, gdy skończy się budżet, w każdej iteracji tniemy NAJWIĘKSZY box wymagający cięcia.
--
-- To jest cała różnica między dziurą a zniknięciem ściany:
--   * budżet `maxChunks` ląduje tam, gdzie faktycznie trafiła bomba, a nie w losowym rogu
--   * zawsze dzielimy największego winowajcę, więc kawałki w dziurze wychodzą RÓWNE
--     (poprzednio przy wyczerpanym budżecie zostawały 31-studowe płyty tuż przy epicentrum,
--     które potem odlatywały w całości — stąd "wyleciała cała ściana")
-- Koszt: O(maxChunks²) porównań, przy 48 kawałkach ~2300 tanich operacji na part.
function Fracture.slice(
	size: Vector3,
	targetSize: number,
	minSize: number,
	maxChunks: number,
	rng: Random,
	focus: Focus?
): { Chunk }
	local boxes: { Chunk } = { { offset = Vector3.zero, size = size } }

	local function longestAxis(s: Vector3): number
		return math.max(s.X, s.Y, s.Z)
	end

	local function axisLength(s: Vector3, axis: number): number
		if axis == 1 then return s.X elseif axis == 2 then return s.Y end
		return s.Z
	end

	-- Wybór OSI cięcia losowany z wagą ∝ długość². Zawsze-najdłuższa oś dawała regularną
	-- kratę: te same proporcje kawałków i ten sam wzór pęknięć przy każdym wybuchu.
	-- Waga kwadratowa sprawia, że długa oś nadal zwykle wygrywa (kawałki nie robią się
	-- igłami), ale czasem tnie w poprzek — i wzór za każdym razem wychodzi inny.
	local function pickCutAxis(s: Vector3): number
		local w1 = if s.X >= minSize * 2 then s.X * s.X else 0
		local w2 = if s.Y >= minSize * 2 then s.Y * s.Y else 0
		local w3 = if s.Z >= minSize * 2 then s.Z * s.Z else 0
		local total = w1 + w2 + w3
		if total <= 0 then
			-- Nie powinno się zdarzyć (needsCut gwarantuje najdłuższą oś tnącą), ale
			-- gdyby — tniemy najdłuższą, żeby nigdy nie zwrócić nieprawidłowej osi.
			local longest = longestAxis(s)
			return if longest == s.X then 1 elseif longest == s.Y then 2 else 3
		end
		local roll = rng:NextNumber() * total
		if roll < w1 then return 1 end
		if roll < w1 + w2 then return 2 end
		return 3
	end

	local function needsCut(box: Chunk): boolean
		local longest = longestAxis(box.size)
		if longest <= targetSize then return false end
		-- Obie połówki muszą wyjść >= minSize (zakres cięcia zawężamy niżej).
		if longest < minSize * 2 then return false end
		-- Poza kulą wybuchu nie tniemy: kawałek zostaje DUŻY i wraca jako anchored remnant.
		if focus and Fracture.boxSurfaceDistance(box.offset, box.size, focus.center) > focus.radius then
			return false
		end
		return true
	end

	while #boxes < maxChunks do
		-- Najgrubszy box kwalifikujący się do cięcia. Deterministyczne (kolejność tablicy
		-- + pierwsze maksimum), więc ten sam seed daje ten sam wynik u każdego klienta.
		local bestIndex: number? = nil
		local bestLongest = 0
		for i, box in ipairs(boxes) do
			if needsCut(box) then
				local longest = longestAxis(box.size)
				if longest > bestLongest then
					bestLongest = longest
					bestIndex = i
				end
			end
		end
		if not bestIndex then break end

		local box = boxes[bestIndex :: number]
		local s = box.size
		local axis = pickCutAxis(s)
		local axisLen = axisLength(s, axis)

		-- Nierówne cięcie 30-70%, zawężone tak, żeby obie połówki wyszły >= minSize
		-- (dla boxa ledwo powyżej 2×minSize zakres zbiega do ~50/50 — wciąż tniemy).
		local lo = math.max(0.3, minSize / axisLen)
		local hi = math.min(0.7, 1 - minSize / axisLen)
		local frac = rng:NextNumber(lo, hi)
		local a = axisLen * frac
		local b = axisLen - a

		local function make(offsetAlong: number, newLen: number): Chunk
			if axis == 1 then
				return { offset = box.offset + Vector3.new(offsetAlong, 0, 0), size = Vector3.new(newLen, s.Y, s.Z) }
			elseif axis == 2 then
				return { offset = box.offset + Vector3.new(0, offsetAlong, 0), size = Vector3.new(s.X, newLen, s.Z) }
			else
				return { offset = box.offset + Vector3.new(0, 0, offsetAlong), size = Vector3.new(s.X, s.Y, newLen) }
			end
		end

		boxes[bestIndex :: number] = make(-(axisLen / 2) + a / 2, a)
		table.insert(boxes, make((axisLen / 2) - b / 2, b))
	end

	return boxes
end

return Fracture
