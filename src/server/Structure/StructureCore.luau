--!strict
-- StructureCore.luau
-- DESTRUKCJA v4 — wspólne funkcje grafu konstrukcji. Czysta logika: żadnych serwisów,
-- żadnego `require`, żadnych yieldów. Plan: DESTRUCTION_PLAN.md → „v4”.
--
-- Używają tego:
--   StructureBake (narzędzie Studio) — buduje dane budynku
--   BuildingState (runtime, faza B) — liczy, co traci podparcie
--   StructuralService (runtime, faza D) — sprawdza, czy dane pasują do mapy (`geometryHash`)
-- Jedna kopia tych funkcji = bake i gra NIE MOGĄ się rozjechać w tym, jak widzą budynek.

local StructureCore = {}

StructureCore.GROUND = 0
StructureCore.EPS = 1e-4
StructureCore.STRUCTURAL = { Slab = true, Beam = true, Wall = true, Column = true, Block = true }
StructureCore.VERTICAL = { Wall = true, Column = true, Block = true }
StructureCore.HORIZONTAL = { Slab = true, Beam = true }

local STRUCTURAL = StructureCore.STRUCTURAL
local HORIZONTAL = StructureCore.HORIZONTAL
local EPS = StructureCore.EPS
local GROUND = StructureCore.GROUND

export type PartRec = {
	inst: BasePart,
	index: number,
	min: Vector3,
	max: Vector3,
	kind: string,
	permanent: boolean,
	chunks: { number },
}

export type Chunk = {
	id: number,
	part: number,
	kind: string,
	level: number,
	min: Vector3,
	max: Vector3,
	center: Vector3,
	permanent: boolean,
}

export type Iface = {
	id: number,
	from: number, -- GROUND (0) albo id chunka
	to: number,
	kind: string, -- "Bearing" | "Lateral" | "Continuity"
	width: number, -- długość styku wzdłuż `axis` (stud)
	span: number, -- tylko Continuity: poziomy dystans między środkami chunków
	lo: Vector3, -- obszar styku w świecie — dziura, która go przetnie, zwęża interfejs
	hi: Vector3,
	axis: string, -- "X" | "Y" | "Z" — wzdłuż której osi mierzona jest szerokość
}

-- ============================================================================
-- Geometria
-- ============================================================================

local function isAxis(v: Vector3): boolean
	return math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) > 0.999
end

local function halfExtents(cf: CFrame, s: Vector3): Vector3
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	) * 0.5
end

-- Prostopadłościan parta w osiach świata. Dla partów obróconych o dowolny kąt to otoczka,
-- dlatego taki part nigdy nie zostaje konstrukcją (flaga `aligned`).
function StructureCore.worldBox(p: BasePart): (Vector3, Vector3, boolean)
	local cf = p.CFrame
	local half = halfExtents(cf, p.Size)
	return cf.Position - half, cf.Position + half, isAxis(cf.RightVector) and isAxis(cf.UpVector)
end

-- Pudełko w układzie parta (offset + size) → prostopadłościan w świecie.
function StructureCore.localBoxToWorld(cf: CFrame, offset: Vector3, size: Vector3): (Vector3, Vector3)
	local c = cf:PointToWorldSpace(offset)
	local half = halfExtents(cf, size)
	return c - half, c + half
end

-- Część wspólna dwóch prostopadłościanów powiększonych o `pad`. nil = rozłączne.
function StructureCore.intersect(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3, pad: number): (Vector3?, Vector3?)
	local lo = aMin:Max(bMin) - Vector3.one * pad
	local hi = aMax:Min(bMax) + Vector3.one * pad
	if lo.X > hi.X or lo.Y > hi.Y or lo.Z > hi.Z then
		return nil, nil
	end
	return lo, hi
end

function StructureCore.boxDistance(mn: Vector3, mx: Vector3, p: Vector3): number
	return (mn - p):Max(p - mx):Max(Vector3.zero).Magnitude
end

function StructureCore.horizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function StructureCore.component(v: Vector3, axis: string): number
	return if axis == "X" then v.X elseif axis == "Y" then v.Y else v.Z
end

-- Oś, wzdłuż której element PRZENOSI obciążenie: wszystko pionowo, poza belką — ta wzdłuż
-- swojej długości. Przecięcie przekroju prostopadłego do tej osi = element przestaje nieść.
function StructureCore.loadAxis(c: Chunk): string
	if c.kind == "Beam" then
		return if (c.max.X - c.min.X) >= (c.max.Z - c.min.Z) then "X" else "Z"
	end
	return "Y"
end

-- ============================================================================
-- Klasyfikacja i zbieranie partów budynku
-- ============================================================================

function StructureCore.classify(p: BasePart, size: Vector3, aligned: boolean, cfg: any, small: any): string
	local attrs = cfg.Attributes
	local forced = p:GetAttribute(attrs.Kind)
	if typeof(forced) == "string" and (STRUCTURAL[forced] or forced == "Trim" or forced == "Other") then
		return forced
	end
	if p:GetAttribute(attrs.NonStructural) == true then
		return "Trim"
	end
	-- Szkło nigdy nie nosi — jest pasażerem ramy albo ściany (spada razem z nimi). Do BakeVersion 2
	-- było pomijane w ogóle i po zawaleniu ściany wisiało w powietrzu (test 24.09).
	if p.Material == Enum.Material.Glass then
		return "Trim"
	end
	-- Bez kolizji nic nie podpiera w grze; obrócony albo nie-prostopadłościan — nie da się
	-- rzetelnie policzyć styków z otoczki.
	if not p.CanCollide then
		return "Other"
	end
	if not aligned or not (p:IsA("Part") and (p :: Part).Shape == Enum.PartType.Block) then
		return "Other"
	end
	-- Drobnica v3 (Destructible.isSmall) dalej jest drobnicą — pada razem z tym, na czym leży.
	local s = p.Size
	if s.X * s.Y * s.Z < small.MaxVolume or math.max(s.X, s.Y, s.Z) < small.MinCutSize then
		return "Other"
	end

	local C = cfg.Classify
	local x, y, z = size.X, size.Y, size.Z
	local d = { x, y, z }
	table.sort(d)
	if d[3] < C.MinStructuralSize then
		return "Other"
	end
	local hMin, hMax = math.min(x, z), math.max(x, z)
	-- Strop: cienki w pionie i szeroki w obu osiach poziomych. Gruby, ale płaski (wysokość
	-- najwyżej połowa krótszego boku poziomego) też jest stropem — inaczej wypadłby na belkę.
	if hMin >= C.SlabMinWidth and (y <= C.SlabMaxThickness or y <= hMin * 0.5) then
		return "Slab"
	end
	if d[1] <= C.TrimMaxThickness or d[2] <= C.TrimMaxWidth then
		return "Trim"
	end
	if y >= C.VerticalMinHeight and hMin <= C.WallMaxThickness then
		return if hMax <= C.ColumnMaxWidth then "Column" else "Wall"
	end
	if y < hMax and hMax >= C.BeamMinLength then
		return "Beam"
	end
	return "Block"
end

local function isExcluded(inst: Instance, root: Instance, excluded: { [string]: boolean }): boolean
	local node = inst.Parent
	while node and node ~= root do
		if excluded[node.Name] then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Kolejność partów = kolejność SID. Musi być deterministyczna (ta sama mapa → te same ID),
-- więc sortujemy po geometrii, a nie po kolejności dzieci w drzewie.
local function lessPart(a: PartRec, b: PartRec): boolean
	local ka = { a.min.Y, a.min.X, a.min.Z, a.max.Y, a.max.X, a.max.Z }
	local kb = { b.min.Y, b.min.X, b.min.Z, b.max.Y, b.max.X, b.max.Z }
	for i = 1, 6 do
		local va = math.floor(ka[i] * 1000 + 0.5)
		local vb = math.floor(kb[i] * 1000 + 0.5)
		if va ~= vb then
			return va < vb
		end
	end
	return a.inst:GetFullName() < b.inst:GetFullName()
end

function StructureCore.collectParts(building: Instance, cfg: any, small: any): { PartRec }
	local excluded: { [string]: boolean } = {}
	for _, name in ipairs(cfg.ExcludeFolders) do
		excluded[name] = true
	end
	local list: { PartRec } = {}
	for _, d in ipairs(building:GetDescendants()) do
		if not d:IsA("BasePart") or d:IsA("Terrain") then continue end
		if isExcluded(d, building, excluded) then continue end
		local mn, mx, aligned = StructureCore.worldBox(d)
		local kind = StructureCore.classify(d, mx - mn, aligned, cfg, small)
		table.insert(list, {
			inst = d,
			index = 0,
			min = mn,
			max = mx,
			kind = kind,
			-- Locked to kontrakt „wybuch nigdy nie tyka” — taka konstrukcja stoi zawsze.
			permanent = d:GetAttribute(cfg.Attributes.Permanent) == true or d.Locked,
			chunks = {},
		})
	end
	table.sort(list, lessPart)
	for i, rec in ipairs(list) do
		rec.index = i
	end
	return list
end

-- Odcisk geometrii: runtime porówna go z mapą — niezgodność = kolaps wyłączony dla budynku.
-- Dwa niezależne hashe wielomianowe mod liczby pierwsze < 2^31 — iloczyny mieszczą się
-- w dokładności double (bit32 nie ma mnożenia bez utraty bitów).
function StructureCore.geometryHash(parts: { PartRec }): string
	local h1, h2 = 7, 11
	local function feed(n: number)
		local v = math.floor(n * 100 + 0.5) % 2147483629
		h1 = (h1 * 131 + v) % 2147483629
		h2 = (h2 * 257 + v) % 2147483587
	end
	for _, p in ipairs(parts) do
		feed(p.min.X); feed(p.min.Y); feed(p.min.Z)
		feed(p.max.X); feed(p.max.Y); feed(p.max.Z)
		feed(#p.kind)
	end
	return string.format("%08x%08x", h1, h2)
end

-- ============================================================================
-- SOLVER — „zasięg” = odległość od ostatniej PRAWDZIWEJ podpory
-- ============================================================================
-- Dijkstra po chunkach. Continuity dolicza przęsło; Bearing i Lateral od PIONU zerują zasięg
-- (to jest podpora), od POZIOMU go dziedziczą (stoisz na wsporniku = jesteś na wsporniku).
-- Chunk spada, gdy nie ma drogi z zasięgiem ≤ MaxSpan swojego rodzaju. Z tego wynika
-- naturalny wspornik i nadproże — bez reguł „N z M podpór”. Do tego przeciążenie: poziom,
-- na którym stoi spadający pion, pęka razem z nim (opis przy pętli w `solve`).
-- `dead` = chunki, które nie przenoszą i nie są przenoszone (zniszczone, już spadające).
-- `widths` = bieżące szerokości interfejsów (runtime: zwężone dziurami); brak = z danych.
-- Solver NIE yielduje — stan musi być spójny od początku do końca obliczenia.

type Heap = { keys: { number }, vals: { number } }

local function heapPush(h: Heap, key: number, val: number)
	local keys, vals = h.keys, h.vals
	local i = #keys + 1
	keys[i], vals[i] = key, val
	while i > 1 do
		local parent = i // 2
		if keys[parent] <= keys[i] then break end
		keys[parent], keys[i] = keys[i], keys[parent]
		vals[parent], vals[i] = vals[i], vals[parent]
		i = parent
	end
end

local function heapPop(h: Heap): (number, number)
	local keys, vals = h.keys, h.vals
	local topKey, topVal = keys[1], vals[1]
	local n = #keys
	keys[1], vals[1] = keys[n], vals[n]
	keys[n], vals[n] = nil, nil
	n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local m = i
		if l <= n and keys[l] < keys[m] then m = l end
		if r <= n and keys[r] < keys[m] then m = r end
		if m == i then break end
		keys[m], keys[i] = keys[i], keys[m]
		vals[m], vals[i] = vals[i], vals[m]
		i = m
	end
	return topKey, topVal
end

function StructureCore.outgoing(ifaces: { Iface }): { [number]: { Iface } }
	local out: { [number]: { Iface } } = {}
	for _, f in ipairs(ifaces) do
		local list = out[f.from]
		if not list then
			list = {}
			out[f.from] = list
		end
		table.insert(list, f)
	end
	return out
end

function StructureCore.incoming(ifaces: { Iface }): { [number]: { Iface } }
	local inn: { [number]: { Iface } } = {}
	for _, f in ipairs(ifaces) do
		local list = inn[f.to]
		if not list then
			list = {}
			inn[f.to] = list
		end
		table.insert(list, f)
	end
	return inn
end

function StructureCore.solve(
	chunks: { Chunk },
	out: { [number]: { Iface } },
	cfg: any,
	dead: { [number]: boolean }?,
	widths: { [number]: number }?
): ({ [number]: number }, { number })
	local deadSet: { [number]: boolean } = dead or {}
	local minW = cfg.MinInterfaceWidth
	local maxSpan = cfg.MaxSpan
	local reach: { [number]: number } = {}
	local heap: Heap = { keys = {}, vals = {} }
	-- Poziomy pęknięte pod spadającym pionem (przeciążenie, niżej): nie niosą i same spadają.
	local overloaded: { [number]: boolean } = {}

	local function widthOf(f: Iface): number
		if widths then
			local w = widths[f.id]
			if w then
				return w
			end
		end
		return f.width
	end

	local function relax(x: number, d: number)
		if deadSet[x] or overloaded[x] then return end
		if d > (maxSpan[chunks[x].kind] or 0) + EPS then return end
		local cur = reach[x]
		if cur == nil or d < cur - EPS then
			reach[x] = d
			heapPush(heap, d, x)
		end
	end

	local function propagate()
		table.clear(reach)
		for _, c in ipairs(chunks) do
			if c.permanent then
				relax(c.id, 0)
			end
		end
		for _, f in ipairs(out[GROUND] or {}) do
			if widthOf(f) >= minW then
				relax(f.to, 0)
			end
		end
		while #heap.keys > 0 do
			local d, c = heapPop(heap)
			if d > (reach[c] or math.huge) + EPS then continue end -- nieaktualny wpis kopca
			-- Zasięg ZERUJE tylko prawdziwa podpora: pion (słup, ściana) albo poziom, który sam
			-- leży bezpośrednio na podporze. Coś, co stoi na wsporniku albo z niego zwisa, dziedziczy
			-- jego zasięg — inaczej podparcie „prało się” przez oparcie: wieża stała na filarkach,
			-- filarki na belce, belka na wsporniku stropu sąsiedniej bryły (zmierzone na
			-- OrangeBuilding: cały parter pod wieżą zniszczony, a wieża nie spadała).
			local inherit = if HORIZONTAL[chunks[c].kind] then d else 0
			for _, f in ipairs(out[c] or {}) do
				if widthOf(f) < minW then continue end
				relax(f.to, if f.kind == "Continuity" then d + f.span else inherit)
			end
		end
	end

	-- PRZECIĄŻENIE (decyzja Kacpra 25.09): pion, który spada, choć stoi (Bearing) na żywym
	-- poziomie, spada tylko dlatego, że odziedziczył za duży zasięg — sam poziom stoi, bo jego
	-- MaxSpan jest większy. Fizycznie taki poziom dalej pod pionem LEŻY, więc bez tej reguły
	-- pion po odkotwiczeniu nie ma dokąd spaść: zmierzone w grze 25.09 — grupa „osiadała”
	-- w miejscu po 0,7 s, a wszystko, co na niej stało, razem z nią (kontrakt 11: stan nie
	-- może przeczyć widocznej geometrii). Kawałek poziomu pod takim pionem pęka i spada.
	-- Iteracja do punktu stałego: pęknięty poziom może zrzucić kolejny pion. Skończona —
	-- każdy obrót dokłada co najmniej jeden poziom do `overloaded`.
	propagate()
	while true do
		local added = false
		for from, list in pairs(out) do
			if from == GROUND or deadSet[from] or overloaded[from] or reach[from] == nil then continue end
			if not HORIZONTAL[chunks[from].kind] then continue end
			for _, f in ipairs(list) do
				if f.kind ~= "Bearing" or widthOf(f) < minW then continue end
				local v = f.to
				if not HORIZONTAL[chunks[v].kind] and not deadSet[v] and reach[v] == nil then
					overloaded[from] = true
					added = true
					break
				end
			end
		end
		if not added then break end
		propagate()
	end

	local falling: { number } = {}
	for _, c in ipairs(chunks) do
		if not deadSet[c.id] and reach[c.id] == nil then
			table.insert(falling, c.id)
		end
	end
	return reach, falling
end

return StructureCore
