--!strict
-- StructureBake.luau
-- DESTRUKCJA v4, faza P0 — NARZĘDZIE STUDIO (Command Bar, tryb Edit). W grze nic tego nie woła.
-- Plan, decyzje i pomiary: DESTRUCTION_PLAN.md → „v4”. Uruchamianie: STRUCTURE_BAKE.luau
-- w korzeniu repo.
--
-- Z budynku robi DANE KONSTRUKCJI:
--   * klasyfikuje party: Slab / Beam / Wall / Column / Block (konstrukcja = węzły grafu)
--     albo Trim / Other (listwy, ozdoby — doczepione do właściciela, nie są węzłami)
--   * tnie konstrukcję na CHUNKI. Chunk ≠ part: słup 5×5×67 to jeden part i kilka pasm,
--     strop 58×23 to jeden part i kilka pól
--   * szuka INTERFEJSÓW podparcia między chunkami: Bearing (A pod B), Lateral (pion trzyma
--     poziom z boku), Continuity (to samo ułożenie; nalicza przęsło). Każdy pamięta OBSZAR
--     styku — dziura, która go przetnie, zwęża interfejs (BuildingState.applyHole)
--   * zapisuje pary partów, które na siebie NACHODZĄ — przy kolapsie trzeba je odfiltrować,
--     bo silnik gwałtownie wypycha odkotwiczony part z partu, na który nachodzi
--   * sprawdza najważniejsze: NIETKNIĘTY budynek musi stać — 0 spadających chunków.
--     Chunk bez drogi do podpory = CZERWONY (do naprawy w mapie albo świadomego oznaczenia).
--
-- Wspólne funkcje (klasyfikacja, solver, odcisk geometrii) są w StructureCore — gra używa
-- tych samych. Command Bar klonuje CAŁY folder Structure (STRUCTURE_BAKE.luau), bo `require`
-- w Studio trzyma STARĄ wersję modułu między wywołaniami (hard rule 14), a klon pojedynczego
-- modułu nie widziałby sąsiada przez `script.Parent`.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Core = require(script.Parent.StructureCore)

local StructureBake = {}

local STRUCTURAL = Core.STRUCTURAL
local VERTICAL = Core.VERTICAL
local HORIZONTAL = Core.HORIZONTAL
local GROUND = Core.GROUND
local EPS = Core.EPS

type PartRec = Core.PartRec
type Chunk = Core.Chunk
type Iface = Core.Iface

type Contact = {
	a: number,
	b: number,
	rel: string, -- "AB" = A pod B, "BA" = B pod A, "side" = styk boczny albo przenikanie
	lo: Vector3, -- część wspólna BEZ luzu (na osi dotyku lo ≈ hi)
	hi: Vector3,
	depth: number, -- głębokość przenikania (0 przy samym dotyku)
}

export type Result = {
	building: Instance,
	buildingId: string,
	mapRevision: number,
	groundY: number,
	levels: { number },
	parts: { PartRec },
	chunks: { Chunk },
	ifaces: { Iface },
	attachments: { { part: number, owner: number } },
	unattached: { number },
	trimLinks: { { number } },
	demoted: { number }, -- konstrukcja bez podparcia w nietkniętym budynku → listwa (DemoteUnsupported)
	overlaps: { { number } },
	deepOverlaps: number,
	invalid: { number },
	hash: string,
	stats: { [string]: any },
}

-- ============================================================================
-- Styki między partami (sweep po osi X)
-- ============================================================================

local function findContacts(parts: { PartRec }, pad: number): { Contact }
	local order = table.create(#parts)
	for i = 1, #parts do
		order[i] = i
	end
	table.sort(order, function(i, j)
		return parts[i].min.X < parts[j].min.X
	end)

	local contacts: { Contact } = {}
	for oi = 1, #order do
		local A = parts[order[oi]]
		for oj = oi + 1, #order do
			local B = parts[order[oj]]
			if B.min.X > A.max.X + pad then break end
			local near = Core.intersect(A.min, A.max, B.min, B.max, pad)
			if not near then continue end
			-- Część wspólna BEZ luzu: ujemna = szczelina, ~0 = dotyk, dodatnia = przenikanie.
			-- Zapisujemy ją surową — luz dokładamy dopiero przy porównaniach, inaczej sąsiednie
			-- pole stropu „dotykające” belki na 0,3 studa dostałoby jej pełną szerokość.
			local lo, hi = A.min:Max(B.min), A.max:Min(B.max)
			local o = hi - lo
			local depth = math.max(0, math.min(o.X, o.Y, o.Z))
			local rel: string
			if math.abs(o.Y) <= pad and o.X > pad and o.Z > pad then
				-- Styk w płaszczyźnie poziomej: niższy podpiera wyższy.
				rel = if A.max.Y <= B.max.Y then "AB" else "BA"
			elseif o.Y > pad and (math.abs(o.X) <= pad or math.abs(o.Z) <= pad) and (o.X > pad or o.Z > pad) then
				rel = "side"
			elseif o.X > pad and o.Y > pad and o.Z > pad then
				-- Przenikanie. „Piętrowe” (jeden wyraźnie niżej w obu krawędziach) = oparcie;
				-- reszta (słup przez strop, strop wpuszczony w belkę) — reguły boczne.
				if A.min.Y < B.min.Y - pad and A.max.Y < B.max.Y - pad then
					rel = "AB"
				elseif B.min.Y < A.min.Y - pad and B.max.Y < A.max.Y - pad then
					rel = "BA"
				else
					rel = "side"
				end
			else
				continue -- styk krawędzią albo narożnikiem — nic nie przenosi
			end
			table.insert(contacts, { a = A.index, b = B.index, rel = rel, lo = lo, hi = hi, depth = depth })
		end
	end
	return contacts
end

-- ============================================================================
-- Poziomy i podział na chunki
-- ============================================================================

local function findLevels(parts: { PartRec }, tol: number): { number }
	local ys: { number } = {}
	for _, p in ipairs(parts) do
		if p.kind == "Slab" then
			table.insert(ys, (p.min.Y + p.max.Y) * 0.5)
		end
	end
	table.sort(ys)
	local levels: { number } = {}
	local sum, count, last = 0, 0, -math.huge
	for _, y in ipairs(ys) do
		if count > 0 and y - last > tol then
			table.insert(levels, sum / count)
			sum, count = 0, 0
		end
		sum += y
		count += 1
		last = y
	end
	if count > 0 then
		table.insert(levels, sum / count)
	end
	return levels
end

local function uniformCuts(a: number, b: number, maxSize: number): { number }
	local n = math.ceil((b - a) / maxSize - EPS)
	local cuts: { number } = {}
	for i = 1, n - 1 do
		table.insert(cuts, a + (b - a) * i / n)
	end
	return cuts
end

-- Linia podziału przyciągana do konstrukcji pod spodem: strop pęka wzdłuż belki albo ściany,
-- nie w losowym miejscu siatki (naturalniejsza linia oderwania).
local function snapCuts(cuts: { number }, candidates: { number }, snap: number, a: number, b: number, minSeg: number): { number }
	local moved: { number } = {}
	for _, c in ipairs(cuts) do
		local best, bestD = c, snap
		for _, k in ipairs(candidates) do
			local dd = math.abs(k - c)
			if dd < bestD and k > a + minSeg and k < b - minSeg then
				best, bestD = k, dd
			end
		end
		table.insert(moved, best)
	end
	table.sort(moved)
	local out: { number } = {}
	local last = a
	for _, c in ipairs(moved) do
		if c - last >= minSeg and b - c >= minSeg then
			table.insert(out, c)
			last = c
		end
	end
	return out
end

local function intervals(a: number, b: number, cuts: { number }): { { number } }
	local list: { { number } } = {}
	local last = a
	for _, c in ipairs(cuts) do
		table.insert(list, { last, c })
		last = c
	end
	table.insert(list, { last, b })
	return list
end

local function levelIndex(levels: { number }, y: number): number
	local n = 0
	for _, l in ipairs(levels) do
		if l < y - EPS then
			n += 1
		end
	end
	return n
end

local function buildChunks(parts: { PartRec }, contacts: { Contact }, levels: { number }, cfg: any): { Chunk }
	-- Kandydaci na linie podziału: środki elementów, które dotykają parta (podpory stropu,
	-- słupy pod belką). Kierunek: element biegnący wzdłuż Z daje linię X i odwrotnie.
	local candX: { [number]: { number } } = {}
	local candZ: { [number]: { number } } = {}
	local function addCand(owner: number, other: PartRec)
		local sx = other.max.X - other.min.X
		local sz = other.max.Z - other.min.Z
		candX[owner] = candX[owner] or {}
		candZ[owner] = candZ[owner] or {}
		if sx <= sz then
			table.insert(candX[owner], (other.min.X + other.max.X) * 0.5)
		end
		if sz <= sx then
			table.insert(candZ[owner], (other.min.Z + other.max.Z) * 0.5)
		end
	end
	for _, c in ipairs(contacts) do
		local A, B = parts[c.a], parts[c.b]
		if STRUCTURAL[A.kind] and STRUCTURAL[B.kind] and (A.kind ~= "Slab" or B.kind ~= "Slab") then
			addCand(A.index, B)
			addCand(B.index, A)
		end
	end

	local maxSize = cfg.ChunkMaxSize
	local chunks: { Chunk } = {}
	for _, p in ipairs(parts) do
		if not STRUCTURAL[p.kind] then continue end
		local cutsX, cutsY, cutsZ = {}, {}, {}
		local sx, sz = p.max.X - p.min.X, p.max.Z - p.min.Z
		local cx, cz = candX[p.index] or {}, candZ[p.index] or {}
		if p.kind == "Slab" then
			cutsX = snapCuts(uniformCuts(p.min.X, p.max.X, maxSize), cx, cfg.SnapDistance, p.min.X, p.max.X, cfg.MinSegment)
			cutsZ = snapCuts(uniformCuts(p.min.Z, p.max.Z, maxSize), cz, cfg.SnapDistance, p.min.Z, p.max.Z, cfg.MinSegment)
		elseif p.kind == "Beam" or p.kind == "Wall" then
			if sx >= sz then
				cutsX = snapCuts(uniformCuts(p.min.X, p.max.X, maxSize), cx, cfg.SnapDistance, p.min.X, p.max.X, cfg.MinSegment)
			else
				cutsZ = snapCuts(uniformCuts(p.min.Z, p.max.Z, maxSize), cz, cfg.SnapDistance, p.min.Z, p.max.Z, cfg.MinSegment)
			end
		end
		if VERTICAL[p.kind] then
			-- Pion dzielony na pasma po poziomach stropów: ściana przez 6 pięter to 6 pasm,
			-- a dziura na parterze odbiera podporę tylko pasmu parteru.
			local last = p.min.Y
			for _, l in ipairs(levels) do
				if l - last >= cfg.MinBandHeight and p.max.Y - l >= cfg.MinBandHeight then
					table.insert(cutsY, l)
					last = l
				end
			end
		end
		for _, ix in ipairs(intervals(p.min.X, p.max.X, cutsX)) do
			for _, iy in ipairs(intervals(p.min.Y, p.max.Y, cutsY)) do
				for _, iz in ipairs(intervals(p.min.Z, p.max.Z, cutsZ)) do
					local mn = Vector3.new(ix[1], iy[1], iz[1])
					local mx = Vector3.new(ix[2], iy[2], iz[2])
					local center = (mn + mx) * 0.5
					local chunk: Chunk = {
						id = #chunks + 1,
						part = p.index,
						kind = p.kind,
						level = levelIndex(levels, center.Y),
						min = mn,
						max = mx,
						center = center,
						permanent = p.permanent,
					}
					table.insert(chunks, chunk)
					table.insert(p.chunks, chunk.id)
				end
			end
		end
	end
	return chunks
end

-- ============================================================================
-- Interfejsy
-- ============================================================================

-- Styk boczny / przenikanie — kierunek zależy od rodzajów:
--   pion → poziom: Lateral (ściana i słup trzymają strop i belkę wpuszczone z boku)
--   poziom → pion: tylko rodzaje z `LateralHoldsVertical` (belka tak — węzeł ramy; strop NIE:
--     bez tego po podcięciu słupów cała wieża „wisiałaby” na cienkim stropie parteru)
--   to samo ułożenie: Continuity w obie strony (nalicza przęsło — wspornik, nadproże)
local function sideLinks(ka: string, kb: string, holdsVertical: { [string]: boolean }): { { any } }
	if VERTICAL[ka] and HORIZONTAL[kb] then
		local links: { { any } } = { { true, "Lateral" } }
		if holdsVertical[kb] then
			table.insert(links, { false, "Lateral" })
		end
		return links
	end
	if HORIZONTAL[ka] and VERTICAL[kb] then
		local links: { { any } } = { { false, "Lateral" } }
		if holdsVertical[ka] then
			table.insert(links, { true, "Lateral" })
		end
		return links
	end
	return { { true, "Continuity" }, { false, "Continuity" } }
end

-- Szerokość styku = najdłuższy wymiar obszaru spośród podanych osi.
local function widest(lo: Vector3, hi: Vector3, axes: { string }): (number, string)
	local e = hi - lo
	local best, bestAxis = -math.huge, axes[1]
	for _, a in ipairs(axes) do
		local v = Core.component(e, a)
		if v > best then
			best, bestAxis = v, a
		end
	end
	return best, bestAxis
end

local HORIZONTAL_AXES = { "X", "Z" }
local ALL_AXES = { "X", "Z", "Y" }

local function buildIfaces(parts: { PartRec }, chunks: { Chunk }, contacts: { Contact }, groundY: number, cfg: any): { Iface }
	local pad = cfg.ContactPadding
	local ifaces: { Iface } = {}
	local byKey: { [string]: Iface } = {}

	local function add(from: number, to: number, kind: string, lo: Vector3, hi: Vector3, width: number, axis: string)
		local nlo, nhi = lo:Min(hi), lo:Max(hi)
		local key = from .. ">" .. to .. ">" .. kind
		local f = byKey[key]
		if f then
			-- Dwa styki tych samych chunków (np. przenikanie + dotyk) — obszar sumujemy,
			-- szerokość zostaje większa.
			f.lo = f.lo:Min(nlo)
			f.hi = f.hi:Max(nhi)
			if width > f.width then
				f.width = width
				f.axis = axis
			end
			return
		end
		local span = 0
		if kind == "Continuity" and from ~= GROUND then
			span = Core.horizontalDistance(chunks[from].center, chunks[to].center)
		end
		f = {
			id = #ifaces + 1,
			from = from,
			to = to,
			kind = kind,
			width = width,
			span = span,
			lo = nlo,
			hi = nhi,
			axis = axis,
		}
		byKey[key] = f
		table.insert(ifaces, f)
	end

	-- 1. Styki między RÓŻNYMI partami konstrukcji, rozpisane na chunki.
	for _, c in ipairs(contacts) do
		local A, B = parts[c.a], parts[c.b]
		if not STRUCTURAL[A.kind] or not STRUCTURAL[B.kind] then continue end
		for _, ia in ipairs(A.chunks) do
			local ca = chunks[ia]
			for _, ib in ipairs(B.chunks) do
				local cb = chunks[ib]
				-- Część styku przypadająca na tę parę chunków (surowa, bez luzu).
				local rlo = c.lo:Max(ca.min):Max(cb.min)
				local rhi = c.hi:Min(ca.max):Min(cb.max)
				local e = rhi - rlo
				if e.X < -pad or e.Y < -pad or e.Z < -pad then continue end
				if c.rel == "side" then
					-- Styk boczny: potrzebne realne nakładanie w pionie.
					if e.Y <= pad then continue end
				else
					-- Oparcie: potrzebna realna POWIERZCHNIA, nie sama krawędź.
					if e.X <= pad or e.Z <= pad then continue end
				end
				local width, axis = widest(rlo, rhi, HORIZONTAL_AXES)
				if width <= pad then continue end
				if c.rel == "AB" then
					add(ia, ib, "Bearing", rlo, rhi, width, axis)
				elseif c.rel == "BA" then
					add(ib, ia, "Bearing", rlo, rhi, width, axis)
				else
					for _, link in ipairs(sideLinks(A.kind, B.kind, cfg.LateralHoldsVertical)) do
						if link[1] then
							add(ia, ib, link[2], rlo, rhi, width, axis)
						else
							add(ib, ia, link[2], rlo, rhi, width, axis)
						end
					end
				end
			end
		end
	end

	-- 2. Sąsiednie chunki TEGO SAMEGO parta: pionowo = oparcie (pasmo niżej trzyma wyższe),
	--    poziomo = ciągłość (strop, belka, ściana nad wyrwą).
	for _, p in ipairs(parts) do
		local list = p.chunks
		for i = 1, #list do
			local a = chunks[list[i]]
			for j = i + 1, #list do
				local b = chunks[list[j]]
				local lo, hi = a.min:Max(b.min), a.max:Min(b.max)
				local o = hi - lo
				if math.abs(o.Y) <= EPS and o.X > EPS and o.Z > EPS then
					local lower, upper = if a.min.Y < b.min.Y then a else b, if a.min.Y < b.min.Y then b else a
					local width, axis = widest(lo, hi, HORIZONTAL_AXES)
					add(lower.id, upper.id, "Bearing", lo, hi, width, axis)
				elseif o.Y > EPS and ((math.abs(o.X) <= EPS and o.Z > EPS) or (math.abs(o.Z) <= EPS and o.X > EPS)) then
					-- Strop/belka: szerokość wzdłuż krawędzi w poziomie; ściana: także wysokość.
					local width, axis = widest(lo, hi, if HORIZONTAL[p.kind] then HORIZONTAL_AXES else ALL_AXES)
					add(a.id, b.id, "Continuity", lo, hi, width, axis)
					add(b.id, a.id, "Continuity", lo, hi, width, axis)
				end
			end
		end
	end

	-- 3. Grunt: spód chunka przy najniższym poziomie budynku.
	for _, c in ipairs(chunks) do
		if c.min.Y <= groundY + cfg.GroundTolerance then
			local lo = Vector3.new(c.min.X, c.min.Y, c.min.Z)
			local hi = Vector3.new(c.max.X, c.min.Y, c.max.Z)
			local width, axis = widest(lo, hi, HORIZONTAL_AXES)
			add(GROUND, c.id, "Bearing", lo, hi, width, axis)
		end
	end
	return ifaces
end

-- ============================================================================
-- Listwy i ozdoby: doczepione do chunka, z którym mają największy styk
-- ============================================================================

local function attach(parts: { PartRec }, chunks: { Chunk }, contacts: { Contact }, pad: number): ({ { part: number, owner: number } }, { number })
	local best: { [number]: { owner: number, score: number } } = {}
	local links: { [number]: { number } } = {} -- ozdoba ↔ ozdoba (drugi przebieg: łańcuchy)
	local function consider(trim: PartRec, structural: PartRec, lo: Vector3, hi: Vector3)
		for _, id in ipairs(structural.chunks) do
			local c = chunks[id]
			local l2, h2 = Core.intersect(lo, hi, c.min, c.max, pad)
			if l2 and h2 then
				local e = h2 - l2
				local score = e.X * e.Y + e.Y * e.Z + e.X * e.Z
				local cur = best[trim.index]
				if not cur or score > cur.score then
					best[trim.index] = { owner = id, score = score }
				end
			end
		end
	end
	for _, c in ipairs(contacts) do
		local A, B = parts[c.a], parts[c.b]
		local sa, sb = STRUCTURAL[A.kind] ~= nil, STRUCTURAL[B.kind] ~= nil
		if sa and not sb then
			consider(B, A, c.lo, c.hi)
		elseif sb and not sa then
			consider(A, B, c.lo, c.hi)
		elseif not sa and not sb then
			links[A.index] = links[A.index] or {}
			links[B.index] = links[B.index] or {}
			table.insert(links[A.index], B.index)
			table.insert(links[B.index], A.index)
		end
	end
	-- Łańcuchy (listwa na listwie na ścianie): BFS od już doczepionych.
	local queue: { number } = {}
	for idx in pairs(best) do
		table.insert(queue, idx)
	end
	table.sort(queue)
	local qi = 1
	while qi <= #queue do
		local idx = queue[qi]
		qi += 1
		for _, other in ipairs(links[idx] or {}) do
			if not best[other] then
				best[other] = { owner = best[idx].owner, score = 0 }
				table.insert(queue, other)
			end
		end
	end

	local attachments: { { part: number, owner: number } } = {}
	local unattached: { number } = {}
	for _, p in ipairs(parts) do
		if STRUCTURAL[p.kind] then continue end
		local b = best[p.index]
		if b then
			table.insert(attachments, { part = p.index, owner = b.owner })
		else
			table.insert(unattached, p.index)
		end
	end
	return attachments, unattached
end

-- ============================================================================
-- Analiza
-- ============================================================================

function StructureBake.analyze(building: Instance, config: any): Result
	-- Ustawienia TEGO budynku (26.09: własny próg listwy, degradacja) — to samo bierze gra.
	local cfg = Core.buildingConfig(config.Structure, building.Name)
	local own = config.Structure.Buildings and config.Structure.Buildings[building.Name]
	local demote = typeof(own) == "table" and own.DemoteUnsupported == true
	local small = config.Destruction.Small
	local pad = cfg.ContactPadding

	local parts = Core.collectParts(building, cfg, small)
	-- Odcisk PRZED degradacją (niżej): to odcisk mapy, nie wyniku analizy — gra liczy go
	-- z samego `collectParts` i porównuje z zapisanymi danymi.
	local hash = Core.geometryHash(parts)
	local contacts = findContacts(parts, pad)

	-- Degradacja (26.09, `DemoteUnsupported`): element konstrukcji bez podparcia w NIETKNIĘTYM
	-- budynku staje się listwą, a analiza idzie od nowa (poziomy, chunki, interfejsy), aż nic nie
	-- jest czerwone. Kolejny przebieg bywa potrzebny: zdegradowany element mógł nieść następny.
	local demoted: { number } = {}
	local groundY = math.huge
	local levels: { number } = {}
	local chunks: { Chunk } = {}
	local ifaces: { Iface } = {}
	local invalid: { number } = {}
	for _ = 1, 5 do
		groundY = math.huge
		for _, p in ipairs(parts) do
			table.clear(p.chunks)
			if STRUCTURAL[p.kind] then
				groundY = math.min(groundY, p.min.Y)
			end
		end
		levels = findLevels(parts, cfg.LevelTolerance)
		chunks = buildChunks(parts, contacts, levels, cfg)
		ifaces = buildIfaces(parts, chunks, contacts, groundY, cfg)
		local _, red = Core.solve(chunks, Core.outgoing(ifaces), cfg, nil, nil)
		invalid = red
		if not demote or #invalid == 0 then break end
		for _, id in ipairs(invalid) do
			local p = parts[chunks[id].part]
			if STRUCTURAL[p.kind] then
				p.kind = "Trim"
				table.insert(demoted, p.index)
			end
		end
	end
	table.sort(demoted)
	local attachments, unattached = attach(parts, chunks, contacts, pad)

	-- Styki z udziałem listwy/ozdoby (26.09): gra liczy z nich, czy listwa ma jeszcze czego
	-- się trzymać (StructuralService.takeUnsupportedStrips). Właściciel z `attach` mówi tylko,
	-- z kim listwa leci, gdy spada — o tym, CZY spada, decyduje oparcie.
	local trimLinks: { { number } } = {}
	for _, c in ipairs(contacts) do
		if not (STRUCTURAL[parts[c.a].kind] and STRUCTURAL[parts[c.b].kind]) then
			table.insert(trimLinks, { c.a, c.b })
		end
	end

	local overlaps: { { number } } = {}
	local deep = 0
	for _, c in ipairs(contacts) do
		if c.depth > cfg.OverlapReportDepth then
			table.insert(overlaps, { c.a, c.b })
			if c.depth > 0.5 then
				deep += 1
			end
		end
	end

	local mapRevision = building:GetAttribute(cfg.Attributes.MapRevision)
	return {
		building = building,
		buildingId = building.Name,
		-- Liczba całkowita: `%d` w raporcie i w zapisie rzuca błąd dla ułamka.
		mapRevision = if typeof(mapRevision) == "number" then math.floor(mapRevision) else 0,
		groundY = groundY,
		levels = levels,
		parts = parts,
		chunks = chunks,
		ifaces = ifaces,
		attachments = attachments,
		unattached = unattached,
		trimLinks = trimLinks,
		demoted = demoted,
		overlaps = overlaps,
		deepOverlaps = deep,
		invalid = invalid,
		hash = hash,
		stats = {},
	}
end

-- Ile chunków spada, gdy zniszczyć jeden — najbardziej krytyczne elementy budynku.
-- Plus zachłanny szacunek „ile bomb kładzie budynek”: bomba w środku któregoś chunka
-- przecina wszystkie chunki `BombEstimateKinds` w promieniu `BombEstimateRadius`;
-- każda kolejna tam, gdzie zrzuci najwięcej. Zachłanny = nie optymalny — to rząd wielkości.
function StructureBake.stress(result: Result, config: any)
	local cfg = config.Structure
	local chunks = result.chunks
	local out = Core.outgoing(result.ifaces)
	local invalidSet: { [number]: boolean } = {}
	for _, id in ipairs(result.invalid) do
		invalidSet[id] = true
	end

	local critical: { { id: number, falls: number } } = {}
	for _, c in ipairs(chunks) do
		if c.permanent or invalidSet[c.id] then continue end
		local _, falling = Core.solve(chunks, out, cfg, { [c.id] = true }, nil)
		table.insert(critical, { id = c.id, falls = #falling - #result.invalid })
	end
	table.sort(critical, function(a, b)
		return a.falls > b.falls
	end)
	result.stats.critical = critical

	local dead: { [number]: boolean } = {}
	for id in pairs(invalidSet) do
		dead[id] = true
	end
	local target = math.ceil(#chunks * cfg.BombEstimateFallShare)
	local kinds = cfg.BombEstimateKinds
	local radius = cfg.BombEstimateRadius
	local function blast(at: Vector3): { number }
		local hit: { number } = {}
		for _, c in ipairs(chunks) do
			if not dead[c.id] and not c.permanent and kinds[c.kind] and Core.boxDistance(c.min, c.max, at) <= radius then
				table.insert(hit, c.id)
			end
		end
		return hit
	end
	local bombs, down = 0, 0
	local plan: { { at: Vector3, fell: number } } = {}
	while bombs < cfg.BombEstimateMax do
		local bestHit: { number }? = nil
		local bestAt = Vector3.zero
		local bestScore = 0
		for _, c in ipairs(chunks) do
			if dead[c.id] or c.permanent or not kinds[c.kind] then continue end
			local hit = blast(c.center)
			for _, id in ipairs(hit) do
				dead[id] = true
			end
			local _, falling = Core.solve(chunks, out, cfg, dead, nil)
			for _, id in ipairs(hit) do
				dead[id] = nil
			end
			local score = #falling + #hit
			if score > bestScore then
				bestHit, bestAt, bestScore = hit, c.center, score
			end
		end
		if not bestHit then break end
		bombs += 1
		table.insert(plan, { at = bestAt, fell = bestScore })
		for _, id in ipairs(bestHit) do
			dead[id] = true
		end
		local _, falling = Core.solve(chunks, out, cfg, dead, nil)
		for _, id in ipairs(falling) do
			dead[id] = true
		end
		down = 0
		for _ in pairs(dead) do
			down += 1
		end
		if down >= target then break end
	end
	result.stats.bombs = bombs
	result.stats.bombsReached = down >= target
	result.stats.bombsTarget = target
	result.stats.bombPlan = plan
end

-- ============================================================================
-- Dane dla gry — ten sam kształt, który zapisuje `write` i czyta BuildingState
-- ============================================================================

function StructureBake.toData(result: Result, config: any): { [string]: any }
	return {
		BuildingId = result.buildingId,
		BakeVersion = config.Structure.BakeVersion,
		GeometryHash = result.hash,
		MapRevision = result.mapRevision,
		GroundY = result.groundY,
		Levels = result.levels,
		PartCount = #result.parts,
		Chunks = result.chunks,
		Interfaces = result.ifaces,
		Attachments = result.attachments,
		TrimLinks = result.trimLinks,
		Demoted = result.demoted,
		Overlaps = result.overlaps,
	}
end

-- ============================================================================
-- Raport (Output)
-- ============================================================================

local function count(list: { any }, key: string): { [string]: number }
	local out: { [string]: number } = {}
	for _, v in ipairs(list) do
		local k = v[key]
		out[k] = (out[k] or 0) + 1
	end
	return out
end

local function fmtCounts(t: { [string]: number }, order: { string }): string
	local parts = {}
	for _, k in ipairs(order) do
		if t[k] then
			table.insert(parts, k .. " " .. t[k])
		end
	end
	return table.concat(parts, ", ")
end

local function fmtBox(mn: Vector3, mx: Vector3): string
	return string.format("x[%.0f..%.0f] y[%.0f..%.0f] z[%.0f..%.0f]", mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z)
end

function StructureBake.report(result: Result): string
	local lines = {}
	local function line(s: string)
		table.insert(lines, s)
	end
	local kinds = { "Slab", "Beam", "Wall", "Column", "Block", "Trim", "Other" }
	local permanent = 0
	for _, c in ipairs(result.chunks) do
		if c.permanent then permanent += 1 end
	end
	local levelStr = {}
	for _, l in ipairs(result.levels) do
		table.insert(levelStr, string.format("%.1f", l))
	end

	line(string.format("[StructureBake] %s — hash %s, MapRevision %d", result.buildingId, result.hash, result.mapRevision))
	line("  party: " .. fmtCounts(count(result.parts, "kind"), kinds) .. string.format("  (razem %d)", #result.parts))
	line(string.format("  grunt Y %.1f | poziomy stropów: %s", result.groundY, table.concat(levelStr, " / ")))
	line("  chunki: " .. fmtCounts(count(result.chunks, "kind"), kinds) .. string.format("  (razem %d, stałych %d)", #result.chunks, permanent))
	line("  interfejsy: " .. fmtCounts(count(result.ifaces, "kind"), { "Bearing", "Lateral", "Continuity" }) .. string.format("  (razem %d)", #result.ifaces))
	line(string.format("  doczepione listwy/ozdoby: %d | bez właściciela: %d | styki listew: %d | nachodzące pary: %d (głęboko > 0.5: %d)",
		#result.attachments, #result.unattached, #result.trimLinks, #result.overlaps, result.deepOverlaps))
	if #result.demoted > 0 then
		line(string.format("  zdegradowane do listew (DemoteUnsupported — bez podparcia w nietkniętym budynku): %d", #result.demoted))
	end

	if #result.invalid == 0 then
		line("  ✅ NIETKNIĘTY BUDYNEK STOI: 0 spadających chunków")
	else
		line(string.format("  🔴 NIETKNIĘTY BUDYNEK NIE STOI: %d chunków bez drogi do podpory (czerwone):", #result.invalid))
		for i = 1, math.min(15, #result.invalid) do
			local c = result.chunks[result.invalid[i]]
			local p = result.parts[c.part]
			line(string.format("     #%d %s %s  ← %s", c.id, c.kind, fmtBox(c.min, c.max), p.inst:GetFullName()))
		end
		if #result.invalid > 15 then
			line(string.format("     … i %d kolejnych", #result.invalid - 15))
		end
	end
	for i = 1, math.min(5, #result.unattached) do
		local p = result.parts[result.unattached[i]]
		line(string.format("  ⚠️ bez właściciela: %s %s  ← %s", p.kind, fmtBox(p.min, p.max), p.inst:GetFullName()))
	end

	local critical = result.stats.critical
	if critical then
		local top = {}
		for i = 1, math.min(5, #critical) do
			local c = result.chunks[critical[i].id]
			table.insert(top, string.format("#%d %s (%d)", c.id, c.kind, critical[i].falls))
		end
		line("  najbardziej nośne (ile chunków spada bez nich): " .. table.concat(top, ", "))
	end
	if result.stats.bombs then
		line(string.format("  szacunek „ile bomb” (zachłanny): %d%s (cel Kacpra ~8; do %d z %d chunków)",
			result.stats.bombs, if result.stats.bombsReached then "" else "+ (limit)", result.stats.bombsTarget, #result.chunks))
		local steps = {}
		for i, b in ipairs(result.stats.bombPlan or {}) do
			table.insert(steps, string.format("%d:(%.0f,%.0f,%.0f)→%d", i, b.at.X, b.at.Y, b.at.Z, b.fell))
		end
		if #steps > 0 then
			line("    bomby (pozycja → ile chunków padło): " .. table.concat(steps, " "))
		end
	end
	return table.concat(lines, "\n")
end

-- ============================================================================
-- Podgląd kolorami (Studio) — zielony: stoi, żółty: stały, czerwony: nie stoi,
-- jasnoniebieski: listwa/ozdoba doczepiona, fioletowy: listwa/ozdoba bez właściciela
-- ============================================================================

local DEBUG_FOLDER = "StructureDebug"
-- Pudełko podglądu wystaje tyle poza chunk. MUSI być na zewnątrz: chunk ma wymiary parta,
-- więc pudełko mniejsze od niego siedziało w środku ściany i zasłaniał je sam part
-- (zgłoszenie 2026-09-24: „nie widać żadnych kolorów”). Nachodzenie sąsiednich pudełek
-- przy okazji rysuje linie podziału chunków.
local DEBUG_INFLATE = 0.15
-- Trzy odcienie zieleni na zmianę, żeby sąsiednie chunki tego samego parta było widać osobno.
local VALID_COLORS = { Color3.fromRGB(60, 200, 90), Color3.fromRGB(25, 130, 55), Color3.fromRGB(150, 235, 120) }

function StructureBake.clear()
	local old = Workspace:FindFirstChild(DEBUG_FOLDER)
	if old then
		old:Destroy()
	end
end

-- Folder podglądu: nie trafia do zapisanego placu (Archivable = false).
function StructureBake.debugFolder(): Folder
	StructureBake.clear()
	local folder = Instance.new("Folder")
	folder.Name = DEBUG_FOLDER
	folder.Archivable = false
	folder.Parent = Workspace
	return folder
end

function StructureBake.box(folder: Instance, mn: Vector3, mx: Vector3, color: Color3, transparency: number, onTop: boolean)
	local a = Instance.new("BoxHandleAdornment")
	a.Adornee = Workspace.Terrain -- Terrain stoi w (0,0,0), więc CFrame adornmentu = pozycja w świecie
	a.CFrame = CFrame.new((mn + mx) * 0.5)
	a.Size = mx - mn + Vector3.one * (DEBUG_INFLATE * 2)
	a.Color3 = color
	a.Transparency = transparency
	a.AlwaysOnTop = onTop
	a.ZIndex = if onTop then 5 else 0
	a.Parent = folder
end

function StructureBake.show(result: Result)
	local folder = StructureBake.debugFolder()
	local invalidSet: { [number]: boolean } = {}
	for _, id in ipairs(result.invalid) do
		invalidSet[id] = true
	end
	for _, c in ipairs(result.chunks) do
		if invalidSet[c.id] then
			StructureBake.box(folder, c.min, c.max, Color3.fromRGB(235, 40, 40), 0.25, true)
		elseif c.permanent then
			StructureBake.box(folder, c.min, c.max, Color3.fromRGB(240, 200, 40), 0.5, false)
		else
			StructureBake.box(folder, c.min, c.max, VALID_COLORS[c.id % #VALID_COLORS + 1], 0.35, false)
		end
	end
	-- Listwy i ozdoby doczepione do chunka: nie są nośne, spadną razem z właścicielem.
	-- Bez nich podgląd wyglądał, jakby ramy okien były „wycięte” (zgłoszenie 2026-09-24).
	for _, a in ipairs(result.attachments) do
		local p = result.parts[a.part]
		StructureBake.box(folder, p.min, p.max, Color3.fromRGB(110, 190, 255), 0.45, false)
	end
	for _, idx in ipairs(result.unattached) do
		local p = result.parts[idx]
		StructureBake.box(folder, p.min, p.max, Color3.fromRGB(200, 60, 220), 0.3, true)
	end
end

-- ============================================================================
-- Zapis: atrybut SID na partach + ServerStorage.StructureData.<Budynek> (ModuleScript)
-- ============================================================================

local function num(n: number): string
	local r = math.floor(n * 1000 + 0.5) / 1000
	return tostring(r)
end

local function vec(v: Vector3): string
	return "Vector3.new(" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. ")"
end

function StructureBake.write(result: Result, config: any, force: boolean?)
	local cfg = config.Structure
	if #result.invalid > 0 and not force then
		error(string.format("[StructureBake] %s ma %d czerwonych chunków — napraw albo oznacz, zapis przerwany", result.buildingId, #result.invalid))
	end

	local sidAttr = cfg.Attributes.SID
	for _, p in ipairs(result.parts) do
		p.inst:SetAttribute(sidAttr, result.buildingId .. ":" .. p.index)
	end

	local data = StructureBake.toData(result, config)
	local src = {}
	local function w(s: string)
		table.insert(src, s)
	end
	w("-- WYGENEROWANE przez StructureBake — nie edytować ręcznie. DESTRUCTION_PLAN.md → „v4”.")
	w("return {")
	w(string.format("\tBuildingId = %q,", data.BuildingId))
	w(string.format("\tBakeVersion = %d,", data.BakeVersion))
	w(string.format("\tGeometryHash = %q,", data.GeometryHash))
	w(string.format("\tMapRevision = %d,", data.MapRevision))
	w(string.format("\tGroundY = %s,", num(data.GroundY)))
	local levels = {}
	for _, l in ipairs(data.Levels) do
		table.insert(levels, num(l))
	end
	w("\tLevels = {" .. table.concat(levels, ",") .. "},")
	w(string.format("\tPartCount = %d, -- SID = \"%s:<indeks>\"", data.PartCount, data.BuildingId))
	w("\tChunks = {")
	for _, c in ipairs(data.Chunks) do
		w(string.format("\t\t{ id = %d, part = %d, kind = %q, level = %d, min = %s, max = %s, center = %s, permanent = %s },",
			c.id, c.part, c.kind, c.level, vec(c.min), vec(c.max), vec(c.center), tostring(c.permanent)))
	end
	w("\t},")
	w("\tInterfaces = {")
	for _, f in ipairs(data.Interfaces) do
		w(string.format("\t\t{ id = %d, from = %d, to = %d, kind = %q, width = %s, span = %s, lo = %s, hi = %s, axis = %q },",
			f.id, f.from, f.to, f.kind, num(f.width), num(f.span), vec(f.lo), vec(f.hi), f.axis))
	end
	w("\t},")
	local att = {}
	for _, a in ipairs(data.Attachments) do
		table.insert(att, "{ part = " .. a.part .. ", owner = " .. a.owner .. " }")
	end
	w("\tAttachments = {" .. table.concat(att, ", ") .. "},")
	local tl = {}
	for _, l in ipairs(data.TrimLinks) do
		table.insert(tl, "{" .. l[1] .. "," .. l[2] .. "}")
	end
	w("\tTrimLinks = {" .. table.concat(tl, ",") .. "},")
	local dm = {}
	for _, idx in ipairs(data.Demoted) do
		table.insert(dm, tostring(idx))
	end
	w("\tDemoted = {" .. table.concat(dm, ",") .. "},")
	local ov = {}
	for _, o in ipairs(data.Overlaps) do
		table.insert(ov, "{" .. o[1] .. "," .. o[2] .. "}")
	end
	w("\tOverlaps = {" .. table.concat(ov, ",") .. "},")
	w("}")

	local folder = ServerStorage:FindFirstChild("StructureData")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StructureData"
		folder.Parent = ServerStorage
	end
	local old = (folder :: Instance):FindFirstChild(data.BuildingId)
	if old then
		old:Destroy()
	end
	local module = Instance.new("ModuleScript")
	module.Name = data.BuildingId
	module.Source = table.concat(src, "\n")
	module.Parent = folder
	print(string.format("[StructureBake] zapisano %s: %d chunków, %d interfejsów, SID na %d partach — teraz Cmd+S",
		data.BuildingId, #data.Chunks, #data.Interfaces, data.PartCount))
end

return StructureBake
