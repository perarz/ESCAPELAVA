--!strict
-- Fracture.luau
-- Czysta matematyka cięcia prostopadłościanu na nierówne kawałki (system destrukcji,
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
--
-- v3 (2026-09-23): `planHole` — JEDEN plan dziury dla serwera i klienta. Serwer bierze z
-- niego resztki (scalone), klient kawałki z dziury, które animuje u siebie. Obie strony
-- wołają go z tym samym seedem i tymi samymi liczbami, więc dostają ten sam podział:
-- kawałek, który klient wystrzeliwuje, to dokładnie ten, którego serwer nie postawił.

export type Chunk = {
	offset: Vector3, -- środek kawałka w LOCAL space oryginalnego parta
	size: Vector3,
}

-- Kula wybuchu w LOCAL space parta (center = CFrame:PointToObjectSpace(blastCenter)).
export type Focus = {
	center: Vector3,
	radius: number,
}

-- Liczby planu dziury — w grze to `Config.Destruction.Fracture`. Moduł celowo nie czyta
-- Config sam: zostaje czystą matematyką, którą da się policzyć z dowolnymi liczbami.
export type HoleConfig = {
	TargetChunkSize: number,
	MinChunkSize: number,
	MaxChunksPerPart: number,
	ChunkSizeJitter: number,
	HoleRadiusJitter: number,
	HoleIrregularity: number,
	HoleNoiseScale: number,
}

export type HolePlan = {
	hole: { Chunk },     -- kawałki W dziurze (klient je animuje, serwer ich nie stawia)
	remnants: { Chunk }, -- to, co zostaje w ścianie — już SCALONE w możliwie duże bryły
}

-- Węzeł drzewa podziałów: liść = kawałek, węzeł wewnętrzny = box przecięty na `a` i `b`.
type Node = {
	offset: Vector3,
	size: Vector3,
	a: number?,
	b: number?,
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

-- Tnie box o rozmiarze `size` na kawałki ~targetSize i ZAPAMIĘTUJE drzewo podziałów.
--   minSize   — wymiar poniżej którego NIE tniemy (drobnica = particle klienta, nie party)
--   maxChunks — twardy sufit liczby kawałków (duży panel nie może urodzić setek partów);
--               po osiągnięciu limitu reszta zostaje w większych kawałkach
--   focus     — opcjonalna kula wybuchu: kawałki poza nią nie są docinane (patrz nagłówek)
-- Zwraca (węzły, indeksy liści w kolejności kawałków). Drzewo jest potrzebne do scalania
-- resztek w `planHole` — dwa sąsiednie kawałki z jednego cięcia, oba poza dziurą, to
-- z powrotem dokładnie ich rodzic.
--
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
local function sliceTree(
	size: Vector3,
	targetSize: number,
	minSize: number,
	maxChunks: number,
	rng: Random,
	focus: Focus?
): ({ Node }, { number })
	local nodes: { Node } = { { offset = Vector3.zero, size = size } }
	local leaves: { number } = { 1 }

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

	local function needsCut(box: Node): boolean
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

	while #leaves < maxChunks do
		-- Najgrubszy liść kwalifikujący się do cięcia. Deterministyczne (kolejność tablicy
		-- + pierwsze maksimum), więc ten sam seed daje ten sam wynik u każdego klienta.
		local bestPos: number? = nil
		local bestLongest = 0
		for pos, idx in ipairs(leaves) do
			local box = nodes[idx]
			if needsCut(box) then
				local longest = longestAxis(box.size)
				if longest > bestLongest then
					bestLongest = longest
					bestPos = pos
				end
			end
		end
		if not bestPos then break end

		local parentIdx = leaves[bestPos :: number]
		local box = nodes[parentIdx]
		local s = box.size
		local axis = pickCutAxis(s)
		local axisLen = axisLength(s, axis)

		-- Nierówne cięcie 30-70%, zawężone tak, żeby obie połówki wyszły >= minSize
		-- (dla boxa ledwo powyżej 2×minSize zakres zbiega do ~50/50 — wciąż tniemy).
		local lo = math.max(0.3, minSize / axisLen)
		local hi = math.min(0.7, 1 - minSize / axisLen)
		local frac = rng:NextNumber(lo, hi)
		local lenA = axisLen * frac
		local lenB = axisLen - lenA

		local function make(offsetAlong: number, newLen: number): Node
			if axis == 1 then
				return { offset = box.offset + Vector3.new(offsetAlong, 0, 0), size = Vector3.new(newLen, s.Y, s.Z) }
			elseif axis == 2 then
				return { offset = box.offset + Vector3.new(0, offsetAlong, 0), size = Vector3.new(s.X, newLen, s.Z) }
			else
				return { offset = box.offset + Vector3.new(0, 0, offsetAlong), size = Vector3.new(s.X, s.Y, newLen) }
			end
		end

		table.insert(nodes, make(-(axisLen / 2) + lenA / 2, lenA))
		local aIdx = #nodes
		table.insert(nodes, make((axisLen / 2) - lenB / 2, lenB))
		local bIdx = #nodes
		box.a = aIdx
		box.b = bIdx
		-- Ta sama kolejność liści co dawniej w płaskiej tablicy (a w miejscu rodzica, b na
		-- końcu), więc wybór „pierwszego maksimum” zachowuje się identycznie.
		leaves[bestPos :: number] = aIdx
		table.insert(leaves, bIdx)
	end

	return nodes, leaves
end

-- Płaska lista kawałków (bez drzewa) — dla wywołań, które nie scalają resztek
-- (pękanie gruzu przy upadku w DebrisService).
function Fracture.slice(
	size: Vector3,
	targetSize: number,
	minSize: number,
	maxChunks: number,
	rng: Random,
	focus: Focus?
): { Chunk }
	local nodes, leaves = sliceTree(size, targetSize, minSize, maxChunks, rng, focus)
	local out: { Chunk } = table.create(#leaves)
	for i, idx in ipairs(leaves) do
		local n = nodes[idx]
		out[i] = { offset = n.offset, size = n.size }
	end
	return out
end

-- PLAN DZIURY (v3). Wszystkie losowania — rozmiar kawałka, promień dziury, przesunięcie
-- szumu, cięcia — idą z `Random.new(seed)` w stałej kolejności, więc serwer i każdy
-- klient liczą z tych samych liczb dokładnie ten sam podział.
--   size        — rozmiar parta
--   localCenter — epicentrum w LOCAL space parta. Liczy je SERWER i wysyła gotowe:
--                 klient przeliczający je z CFrame mógłby dostać inną ostatnią cyfrę
--                 i kawałek na granicy dziury wypadłby po złej stronie.
--   holeRadius  — promień dziury z modelu obrażeń (DestructionService)
--
-- Kształt dziury: promień modulowany szumem Perlina zależnym od KIERUNKU — granica
-- przestaje być kulą, robi się poszarpaną wyrwą. Kawałki są boxami, więc krawędź i tak
-- jest schodkowa, ale to obrys decyduje o tym, czy dziura czyta się jako "wyrwana" czy
-- "wycięta cyrklem". Cięcie tnie do `effectiveHole × (1 + irregularity)`, żeby pas
-- wybrzuszeń też był rozdrobniony — inaczej wyrwa miałaby ząbki wielkości płyt.
--
-- Kawałek należy do dziury po ŚRODKU, nie po powierzchni. Przy dystansie do powierzchni
-- wielka płyta, która ledwo dotyka epicentrum rogiem, kwalifikowała się jako "w wybuchu"
-- i odlatywała CAŁA — to był powód "wysadzam ścianę i nie ma ściany".
--
-- RESZTKI SĄ SCALANE: cięcia przy granicy kuli dzielą też kawałki, które ostatecznie
-- zostają w ścianie. Jeśli oba kawałki z jednego cięcia zostają, ich suma to dokładnie
-- box sprzed cięcia — więc wstawiamy JEDEN part zamiast dwóch (i rekurencyjnie w górę
-- drzewa). Mniej nowych partów = mniejszy skok replikacji po wybuchu i mniej szczelin.
function Fracture.planHole(
	size: Vector3,
	localCenter: Vector3,
	holeRadius: number,
	seed: number,
	cfg: HoleConfig
): HolePlan
	local rng = Random.new(seed)
	-- Wariacja PER WYBUCH: bez niej dwie bomby w tę samą ścianę dawały bliźniaczy wzór.
	local target = cfg.TargetChunkSize * rng:NextNumber(1 - cfg.ChunkSizeJitter, 1 + cfg.ChunkSizeJitter)
	local effectiveHole = holeRadius * rng:NextNumber(1 - cfg.HoleRadiusJitter, 1 + cfg.HoleRadiusJitter)
	-- Przesunięcie szumu: ten sam kształt wyrwy nie powtórzy się w innym wybuchu.
	local noiseOffset = rng:NextNumber(0, 1000)
	local irregularity = cfg.HoleIrregularity
	local noiseScale = cfg.HoleNoiseScale

	local function holeRadiusToward(offset: Vector3): number
		if irregularity <= 0 then return effectiveHole end
		local d = offset - localCenter
		local n = math.noise(
			d.X * noiseScale + noiseOffset,
			d.Y * noiseScale,
			d.Z * noiseScale + noiseOffset
		)
		return effectiveHole * (1 + math.clamp(n * 2, -1, 1) * irregularity)
	end

	local nodes, leaves = sliceTree(
		size,
		target,
		cfg.MinChunkSize,
		cfg.MaxChunksPerPart,
		rng,
		{ center = localCenter, radius = effectiveHole * (1 + irregularity) }
	)

	local inHole: { [number]: boolean } = {}
	local hole: { Chunk } = {}
	for _, idx in ipairs(leaves) do
		local n = nodes[idx]
		if (n.offset - localCenter).Magnitude <= holeRadiusToward(n.offset) then
			inHole[idx] = true
			table.insert(hole, { offset = n.offset, size = n.size })
		end
	end

	-- Scalanie: poddrzewo bez ani jednego kawałka dziury = jedna resztka o rozmiarze
	-- korzenia tego poddrzewa. Zwraca true, gdy CAŁE poddrzewo zostaje w ścianie.
	local remnants: { Chunk } = {}
	local function collect(idx: number): boolean
		local n = nodes[idx]
		local a, b = n.a, n.b
		if a == nil or b == nil then
			return not inHole[idx]
		end
		local keepA = collect(a)
		local keepB = collect(b)
		if keepA and keepB then
			return true
		end
		if keepA then
			local na = nodes[a]
			table.insert(remnants, { offset = na.offset, size = na.size })
		end
		if keepB then
			local nb = nodes[b]
			table.insert(remnants, { offset = nb.offset, size = nb.size })
		end
		return false
	end
	if collect(1) then
		-- Żaden kawałek nie trafił do dziury — cały part zostaje (caller to rozpozna).
		table.insert(remnants, { offset = nodes[1].offset, size = nodes[1].size })
	end

	return { hole = hole, remnants = remnants }
end

-- ============================================================================
-- OKNO (destrukcja v4, 2026-09-24) — dziura jako PROSTOKĄT na wylot
-- ============================================================================
-- Kolizja dziury w v4. Resztki to najwyżej 4 pasy wokół prostokąta: nad i pod dziurą na
-- całą szerokość, po bokach na wysokość dziury. Zmierzone na mapie (200 bomb): średnio
-- 6 nowych partów na bombę (max 16) zamiast 45 (max 149) z planHole — koszt wybuchu to
-- replikacja nowych instancji, nie matematyka. Poszarpaną krawędź dorysowują klienci
-- (bez kolizji); widoczna krawędź ma zostać w ~1 studzie od tej kolizji.
-- Płaszczyzna cięcia = dwie najdłuższe osie parta; najkrótsza to grubość (tniemy na wylot).
export type WindowPlan = {
	hole: Chunk?,        -- prostokąt dziury w local space; nil = wybuch nie sięga parta
	remnants: { Chunk }, -- ≤ 4 pasy, które zostają; pusto = part znika w całości
}

function Fracture.planWindow(size: Vector3, localCenter: Vector3, holeRadius: number, minStrip: number): WindowPlan
	local dims = { size.X, size.Y, size.Z }
	local cs = { localCenter.X, localCenter.Y, localCenter.Z }
	local order = { 1, 2, 3 }
	table.sort(order, function(a, b)
		return dims[a] < dims[b]
	end)
	local t, u, v = order[1], order[2], order[3]
	local hu, hv = dims[u] * 0.5, dims[v] * 0.5
	local u0, u1 = math.max(cs[u] - holeRadius, -hu), math.min(cs[u] + holeRadius, hu)
	local v0, v1 = math.max(cs[v] - holeRadius, -hv), math.min(cs[v] + holeRadius, hv)
	if u0 >= u1 or v0 >= v1 then
		return { hole = nil, remnants = { { offset = Vector3.zero, size = size } } }
	end
	-- Pas węższy niż minStrip nie zostaje — dziura sięga wtedy krawędzi. Cienka listewka
	-- przy krawędzi to part, który nic nie wnosi, a kosztuje replikację i wygląda jak błąd.
	if u0 + hu < minStrip then u0 = -hu end
	if hu - u1 < minStrip then u1 = hu end
	if v0 + hv < minStrip then v0 = -hv end
	if hv - v1 < minStrip then v1 = hv end

	local function box(uLo: number, uHi: number, vLo: number, vHi: number): Chunk
		local off = { 0, 0, 0 }
		local sz = { dims[1], dims[2], dims[3] }
		off[u], sz[u] = (uLo + uHi) * 0.5, uHi - uLo
		off[v], sz[v] = (vLo + vHi) * 0.5, vHi - vLo
		off[t], sz[t] = 0, dims[t]
		return { offset = Vector3.new(off[1], off[2], off[3]), size = Vector3.new(sz[1], sz[2], sz[3]) }
	end

	local remnants: { Chunk } = {}
	if v1 < hv then table.insert(remnants, box(-hu, hu, v1, hv)) end -- nad dziurą
	if v0 > -hv then table.insert(remnants, box(-hu, hu, -hv, v0)) end -- pod dziurą
	if u0 > -hu then table.insert(remnants, box(-hu, u0, v0, v1)) end -- z lewej
	if u1 < hu then table.insert(remnants, box(u1, hu, v0, v1)) end -- z prawej
	return { hole = box(u0, u1, v0, v1), remnants = remnants }
end

return Fracture
