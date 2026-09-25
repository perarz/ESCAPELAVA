--!strict
-- CollapsePlanner.luau
-- DESTRUKCJA v4, faza C — zamienia ZBIÓR spadających chunków w GRUPY KOLAPSU.
-- Czysta logika: bez serwisów, instancji i yieldów. Plan: DESTRUCTION_PLAN.md → „v4”.
--
-- Zasada: LOGICZNE CHUNKI ≠ FIZYCZNE BRYŁY. Solver może zwrócić 100 chunków, ale wykonawca
-- (faza D) nie robi 100 brył — robi po jednej na grupę. Planner mówi tylko, CO spada razem;
-- nie wie, jak to poleci (fizyka, animacja), ile kosztuje ani kto na tym stoi — to decyduje
-- PhysicsDirector. Dzięki temu fizykę można wymienić bez ruszania solvera i plannera.
--
-- Algorytm:
--   1. spadające chunki łączą się po interfejsach z szerokością ≥ BondMinWidth, ale tylko
--      w obrębie jednego elementu (ten sam part) albo poziom z poziomem (strop + belka).
--      Ściany i słupy NIE łączą się ze stropami — przewracają się osobno (nie tektura)
--   2. spójne składowe = kandydaci na grupy
--   3. za duża grupa (rzut > GroupMaxFootprint albo za dużo chunków) jest cięta na pół
--      wzdłuż dłuższej osi, po środkach chunków — czyli po granicach chunków, które leżą
--      na liniach konstrukcji; każda połowa jeszcze raz rozbita na spójne kawałki
--   4. grupa mniejsza niż GroupMinVolume dołącza do największej spadającej sąsiadki
--   5. głębokość (pasmo), zawias (styki ze STOJĄCĄ konstrukcją, które dalej mają materiał),
--      pasażerowie (listwy i ozdoby doczepione do chunków grupy)
-- Członkostwo i kolejność są deterministyczne (sortowanie po id) — ten sam stan daje ten
-- sam plan na każdym serwerze.

local Core = require(script.Parent.StructureCore)

local CollapsePlanner = {}

local HORIZONTAL = Core.HORIZONTAL
local GROUND = Core.GROUND

type Chunk = Core.Chunk
type Iface = Core.Iface

export type Group = {
	groupId: string,
	chunkIds: { number },
	depth: number,
	pivot: { number }, -- id interfejsów ze stojącą konstrukcją, które dalej mają materiał
	parts: { number }, -- party (indeksy SID) tworzące grupę
	splitParts: { number }, -- z tego: party, które mają też chunki POZA grupą (trzeba je przeciąć)
	followers: { number }, -- listwy/ozdoby jadące z grupą
	volume: number,
	min: Vector3,
	max: Vector3,
}

-- Minimalny interfejs stanu, którego potrzebuje planner (BuildingState go spełnia).
export type StateView = {
	chunks: { Chunk },
	ifaces: { Iface },
	attachments: { { part: number, owner: number } },
	partChunks: { [number]: { number } },
	cfg: any,
	widthOf: (any, Iface) -> number,
	isAlive: (any, number) -> boolean,
}

local function volumeOf(c: Chunk): number
	local e = c.max - c.min
	return e.X * e.Y * e.Z
end

local function bondAllowed(a: Chunk, b: Chunk): boolean
	return a.part == b.part or (HORIZONTAL[a.kind] ~= nil and HORIZONTAL[b.kind] ~= nil)
end

local function bounds(chunks: { Chunk }, ids: { number }): (Vector3, Vector3)
	local mn = chunks[ids[1]].min
	local mx = chunks[ids[1]].max
	for i = 2, #ids do
		local c = chunks[ids[i]]
		mn = mn:Min(c.min)
		mx = mx:Max(c.max)
	end
	return mn, mx
end

-- Spójne składowe podzbioru `ids` po krawędziach `adj` (tylko w obrębie podzbioru).
local function components(ids: { number }, adj: { [number]: { number } }): { { number } }
	local inSet: { [number]: boolean } = {}
	for _, id in ipairs(ids) do
		inSet[id] = true
	end
	local seen: { [number]: boolean } = {}
	local out: { { number } } = {}
	local sorted = table.clone(ids)
	table.sort(sorted)
	for _, start in ipairs(sorted) do
		if seen[start] then continue end
		local comp: { number } = {}
		local stack = { start }
		seen[start] = true
		while #stack > 0 do
			local id = table.remove(stack) :: number
			table.insert(comp, id)
			for _, n in ipairs(adj[id] or {}) do
				if inSet[n] and not seen[n] then
					seen[n] = true
					table.insert(stack, n)
				end
			end
		end
		table.sort(comp)
		table.insert(out, comp)
	end
	return out
end

function CollapsePlanner.plan(state: StateView, falling: { number }, reach: { [number]: number }, collapseId: number): { Group }
	local cfg = state.cfg.Planner
	local chunks = state.chunks
	local fallingSet: { [number]: boolean } = {}
	for _, id in ipairs(falling) do
		fallingSet[id] = true
	end

	-- 1. Wiązania między spadającymi chunkami + sąsiedztwo „jakiekolwiek” (do kroku 4).
	local bond: { [number]: { number } } = {}
	local touch: { [number]: { number } } = {}
	local function link(map: { [number]: { number } }, a: number, b: number)
		map[a] = map[a] or {}
		map[b] = map[b] or {}
		table.insert(map[a], b)
		table.insert(map[b], a)
	end
	for _, f in ipairs(state.ifaces) do
		if f.from == GROUND or not fallingSet[f.from] or not fallingSet[f.to] then continue end
		local w = state:widthOf(f)
		if w <= 0 then continue end
		link(touch, f.from, f.to)
		if w >= cfg.BondMinWidth and bondAllowed(chunks[f.from], chunks[f.to]) then
			link(bond, f.from, f.to)
		end
	end

	-- 2 + 3. Składowe, za duże cięte na pół wzdłuż dłuższej osi.
	local groupsIds: { { number } } = {}
	local function split(ids: { number })
		local mn, mx = bounds(chunks, ids)
		local dx, dz = mx.X - mn.X, mx.Z - mn.Z
		if #ids <= 1 or (math.max(dx, dz) <= cfg.GroupMaxFootprint and #ids <= cfg.GroupMaxChunks) then
			table.insert(groupsIds, ids)
			return
		end
		local axis = if dx >= dz then "X" else "Z"
		local sorted = table.clone(ids)
		table.sort(sorted, function(a, b)
			local ca = Core.component(chunks[a].center, axis)
			local cb = Core.component(chunks[b].center, axis)
			if math.abs(ca - cb) > Core.EPS then
				return ca < cb
			end
			return a < b
		end)
		local half = #sorted // 2
		local left = table.move(sorted, 1, half, 1, {})
		local right = table.move(sorted, half + 1, #sorted, 1, {})
		for _, part in ipairs({ left, right }) do
			for _, comp in ipairs(components(part, bond)) do
				split(comp)
			end
		end
	end
	for _, comp in ipairs(components(falling, bond)) do
		split(comp)
	end

	-- 4. Małe grupy dołączają do największej spadającej sąsiadki (kawałek filarka nie jest
	--    osobną bryłą fizyki — jedzie z tym, czego dotyka).
	local groupOf: { [number]: number } = {}
	local volumes: { number } = {}
	for gi, ids in ipairs(groupsIds) do
		local v = 0
		for _, id in ipairs(ids) do
			groupOf[id] = gi
			v += volumeOf(chunks[id])
		end
		volumes[gi] = v
	end
	local order = {}
	for gi in ipairs(groupsIds) do
		table.insert(order, gi)
	end
	table.sort(order, function(a, b)
		if volumes[a] ~= volumes[b] then
			return volumes[a] < volumes[b]
		end
		return groupsIds[a][1] < groupsIds[b][1]
	end)
	local merged: { [number]: boolean } = {}
	for _, gi in ipairs(order) do
		if merged[gi] or volumes[gi] >= cfg.GroupMinVolume then continue end
		local best, bestVolume = nil :: number?, -1
		for _, id in ipairs(groupsIds[gi]) do
			for _, n in ipairs(touch[id] or {}) do
				local other = groupOf[n]
				if other ~= gi and not merged[other] and volumes[other] > bestVolume then
					best, bestVolume = other, volumes[other]
				end
			end
		end
		if best then
			for _, id in ipairs(groupsIds[gi]) do
				table.insert(groupsIds[best], id)
				groupOf[id] = best
			end
			volumes[best] += volumes[gi]
			merged[gi] = true
		end
	end

	-- 5. Rekordy grup.
	local baseLevel = math.huge
	for _, id in ipairs(falling) do
		baseLevel = math.min(baseLevel, chunks[id].level)
	end
	local ownerFollowers: { [number]: { number } } = {}
	for _, a in ipairs(state.attachments) do
		ownerFollowers[a.owner] = ownerFollowers[a.owner] or {}
		table.insert(ownerFollowers[a.owner], a.part)
	end

	local groups: { Group } = {}
	for gi, ids in ipairs(groupsIds) do
		if merged[gi] then continue end
		table.sort(ids)
		local inGroup: { [number]: boolean } = {}
		local minLevel = math.huge
		for _, id in ipairs(ids) do
			inGroup[id] = true
			minLevel = math.min(minLevel, chunks[id].level)
		end

		local partSet: { [number]: boolean } = {}
		local parts: { number } = {}
		local followers: { number } = {}
		for _, id in ipairs(ids) do
			local p = chunks[id].part
			if not partSet[p] then
				partSet[p] = true
				table.insert(parts, p)
			end
			for _, f in ipairs(ownerFollowers[id] or {}) do
				table.insert(followers, f)
			end
		end
		table.sort(parts)
		table.sort(followers)
		local splitParts: { number } = {}
		for _, p in ipairs(parts) do
			for _, cid in ipairs(state.partChunks[p] or {}) do
				if not inGroup[cid] then
					table.insert(splitParts, p)
					break
				end
			end
		end

		local pivot: { number } = {}
		for _, f in ipairs(state.ifaces) do
			if not inGroup[f.to] or f.from == GROUND or fallingSet[f.from] then continue end
			if reach[f.from] ~= nil and state:isAlive(f.from) and state:widthOf(f) >= state.cfg.MinInterfaceWidth then
				table.insert(pivot, f.id)
			end
		end

		local mn, mx = bounds(chunks, ids)
		table.insert(groups, {
			groupId = collapseId .. ":" .. ids[1],
			chunkIds = ids,
			depth = minLevel - baseLevel,
			pivot = pivot,
			parts = parts,
			splitParts = splitParts,
			followers = followers,
			volume = volumes[gi],
			min = mn,
			max = mx,
		})
	end
	table.sort(groups, function(a, b)
		if a.depth ~= b.depth then
			return a.depth < b.depth
		end
		return a.chunkIds[1] < b.chunkIds[1]
	end)
	return groups
end

return CollapsePlanner
