--!strict
-- StructureTests.luau
-- DESTRUKCJA v4, fazy B/C — scenariusze solvera i plannera NA PRAWDZIWEJ MAPIE, bez Play.
-- Uruchamianie: STRUCTURE_TEST.luau (Command Bar, tryb Edit). To obliczenia na danych budynku
-- (obserwacja), a nie test gry: mapa się nie zmienia, nic nie spada naprawdę. Plan:
-- DESTRUCTION_PLAN.md → „v4” (fazy i test akceptacyjny).
--
-- Wybuch symulowany tak, jak zrobi to DestructionService v4 w fazie D: każdy part konstrukcji,
-- na którego powierzchni obrażenia ≥ HoleThreshold, dostaje „okno” (Fracture.planWindow),
-- a do tego idą obrażenia strukturalne (osłabianie). Uproszczenie testu: kolejne bomby liczą
-- dziury na NIEPOCIĘTYCH partach (geometria mapy stoi w miejscu) — stan budynku i tak
-- sumuje zabrany materiał po odcinkach, więc nakładające się dziury nie liczą się podwójnie.
--
-- Scenariusze są pod OrangeBuilding (prototyp v4) — pozycje w układzie lokalnym budynku.

local Core = require(script.Parent.StructureCore)
local StructureBake = require(script.Parent.StructureBake)
local BuildingState = require(script.Parent.BuildingState)

local StructureTests = {}

type BuildingState = BuildingState.BuildingState

type Ctx = {
	result: StructureBake.Result,
	data: any,
	config: any,
	fracture: any,
	bomb: { radius: number, damage: number },
	seq: number,
	origin: Vector3,
}

local function newState(ctx: Ctx): BuildingState
	return BuildingState.new(ctx.data, ctx.config)
end

local function nextCause(ctx: Ctx, attacker: number): BuildingState.Cause
	ctx.seq += 1
	return { causeId = ctx.seq, attackerUserId = attacker, seq = ctx.seq, time = ctx.seq }
end

-- Zwraca (przeciętych partów, nowych partów-resztek) — to drugie to koszt replikacji wybuchu.
local function bomb(ctx: Ctx, state: BuildingState, center: Vector3, attacker: number?): (number, number)
	local D = ctx.config.Structure.Damage
	local radius, damage = ctx.bomb.radius, ctx.bomb.damage
	local cause = nextCause(ctx, attacker or 1)
	local cut, newParts = 0, 0
	for _, p in ipairs(ctx.result.parts) do
		if not Core.STRUCTURAL[p.kind] then continue end
		local inst = p.inst
		local lp = inst.CFrame:PointToObjectSpace(center)
		local d = ctx.fracture.boxSurfaceDistance(Vector3.zero, inst.Size, lp)
		if d >= radius then continue end
		if damage * (1 - d / radius) < D.HoleThreshold then continue end
		local holeR = math.clamp(radius * (1 - D.HoleThreshold / damage), D.MinHoleRadius, radius)
		local plan = ctx.fracture.planWindow(inst.Size, lp, holeR, D.MinStrip)
		if plan.hole then
			local hmin, hmax = Core.localBoxToWorld(inst.CFrame, plan.hole.offset, plan.hole.size)
			state:applyHole(p.index, hmin, hmax, cause)
			cut += 1
			newParts += math.max(#plan.remnants - 1, 0)
		end
	end
	state:applyStructuralDamage(center, radius, damage, cause)
	return cut, newParts
end

local function summarize(flush: BuildingState.FlushResult?): string
	if not flush then
		return "brak zmian"
	end
	local s = string.format("zniszczone %d, osłabione %d", #flush.destroyed, #flush.damaged)
	local plan = flush.plan
	if not plan then
		return s .. " | nic nie spada"
	end
	local total = 0
	local sizes = {}
	for _, g in ipairs(plan.groups) do
		total += #g.chunkIds
		table.insert(sizes, string.format("%d/d%d", #g.chunkIds, g.depth))
	end
	return s .. string.format(" | KOLAPS #%d: %d chunków w %d grupach [%s], przyczyna seq %s, asysty %d",
		plan.collapseId, total, #plan.groups, table.concat(sizes, " "),
		if plan.cause then tostring(plan.cause.seq) else "-", #plan.assists)
end

local function countStates(state: BuildingState): { [string]: number }
	local out: { [string]: number } = {}
	for _, rt in pairs(state.rt) do
		out[rt.state] = (out[rt.state] or 0) + 1
	end
	return out
end

local function fmtStates(state: BuildingState): string
	local t = countStates(state)
	local parts = {}
	for _, k in ipairs({ "Intact", "Damaged", "Destroyed", "Falling" }) do
		if t[k] then
			table.insert(parts, k .. " " .. t[k])
		end
	end
	return table.concat(parts, ", ")
end

-- Odcisk stanu (do porównania dwóch dróg dojścia do tego samego wyniku).
local function stateKey(state: BuildingState): string
	local parts = {}
	for id = 1, #state.chunks do
		local s = state.rt[id].state
		table.insert(parts, if s == "Destroyed" or s == "Falling" then "x" else "o")
	end
	return table.concat(parts)
end

-- ============================================================================
-- Scenariusze OrangeBuilding
-- ============================================================================

function StructureTests.runOrange(building: Instance, config: any, fracture: any, bombParams: any): (string, BuildingState, BuildingState.CollapsePlan?)
	local result = StructureBake.analyze(building, config)
	local origin = Vector3.new(math.huge, 0, math.huge)
	for _, p in ipairs(result.parts) do
		if Core.STRUCTURAL[p.kind] then
			origin = Vector3.new(math.min(origin.X, p.min.X), 0, math.min(origin.Z, p.min.Z))
		end
	end
	local ctx: Ctx = {
		result = result,
		data = StructureBake.toData(result, config),
		config = config,
		fracture = fracture,
		bomb = { radius = bombParams.radius, damage = bombParams.damage },
		seq = 0,
		origin = origin,
	}
	local function P(x: number, y: number, z: number): Vector3
		return Vector3.new(origin.X + x, y, origin.Z + z)
	end

	local lines = {}
	local function L(s: string)
		table.insert(lines, s)
	end
	L(string.format("[StructureTests] %s — %d chunków, %d interfejsów, bomba r=%d dmg=%d",
		result.buildingId, #result.chunks, #result.ifaces, ctx.bomb.radius, ctx.bomb.damage))

	-- Wieża = chunki nad parterem w części frontowej (z ≤ 34 w układzie budynku).
	local towerIds: { number } = {}
	for _, c in ipairs(result.chunks) do
		if c.level >= 1 and c.center.Z - origin.Z <= 34 then
			table.insert(towerIds, c.id)
		end
	end
	local function towerDown(st: BuildingState): number
		local n = 0
		for _, id in ipairs(towerIds) do
			local s = st.rt[id].state
			if s == "Falling" or s == "Destroyed" then
				n += 1
			end
		end
		return n
	end

	-- S1: nietknięty budynek stoi (warunek włączenia kolapsu).
	local st = newState(ctx)
	L(string.format("S1 nietknięty: kolaps włączony=%s, spada bez wybuchu: %d  %s",
		tostring(st.enabled), st.baselineFalling, if st.enabled and st.baselineFalling == 0 then "✅" else "❌"))

	-- S2: dziura w środku stropu wieży (Y54, płyta 58×23) — dziura ≠ zawalenie.
	st = newState(ctx)
	local cut, newParts = bomb(ctx, st, P(31, 56, 16))
	local flush = st:flush()
	L(string.format("S2 dziura w stropie wieży: przeciętych %d, nowych partów %d | %s  %s",
		cut, newParts, summarize(flush), if flush and flush.plan == nil then "✅" else "⚠️"))

	-- S3: trzy dziury w rzędzie przez strop, jedna paczka (jeden flush).
	st = newState(ctx)
	for _, x in ipairs({ 10, 31, 52 }) do
		bomb(ctx, st, P(x, 56, 16))
	end
	L("S3 trzy dziury w rzędzie w stropie wieży (jeden flush): " .. summarize(st:flush()))

	-- S4: osłabianie — bomba ~10 studów od środkowego słupa frontu (za daleko, żeby przeciąć).
	local column: number? = nil
	for _, c in ipairs(result.chunks) do
		local p = result.parts[c.part]
		if c.kind == "Column" and c.level == 0 and p.max.Y - p.min.Y >= 60
			and math.abs(c.center.X - origin.X - 31) < 4 and c.center.Z - origin.Z < 10 then
			column = c.id
		end
	end
	st = newState(ctx)
	if column then
		bomb(ctx, st, P(31, 20, 16))
		local f1 = st:flush()
		local after1 = string.format("%s (obrażenia %.0f)", st.rt[column].state, st.rt[column].damage)
		bomb(ctx, st, P(31, 20, 16))
		local f2 = st:flush()
		L(string.format("S4 osłabianie słupa: po 1. bombie %s | po 2. %s/%s | %s  %s",
			after1, st.rt[column].state, tostring(st.rt[column].reason), summarize(f2),
			if st.rt[column].state == "Destroyed" and f1 and f1.plan == nil then "✅" else "⚠️"))
	else
		L("S4 osłabianie słupa: ⚠️ nie znaleziono środkowego słupa frontu")
	end

	-- S5: jeden słup przecięty bombą tuż przy nim — budynek stoi (trzymają filarki i belki).
	st = newState(ctx)
	bomb(ctx, st, P(31, 14, 8))
	L("S5 bomba przy środkowym słupie frontu: " .. summarize(st:flush()) .. "  | " .. fmtStates(st))

	-- S6: parter pod wieżą, bomba po bombie (pozycje z zachłannego szacunku bake'u),
	--     flush po każdej — ile bomb do upadku wieży (≥ 80% jej chunków).
	StructureBake.stress(result, config)
	st = newState(ctx)
	local lastPlan: BuildingState.CollapsePlan? = nil
	local s6 = {}
	local bombsToTower: number? = nil
	for i, b in ipairs(result.stats.bombPlan) do
		bomb(ctx, st, b.at, i)
		local f = st:flush()
		if f and f.plan then
			lastPlan = f.plan
		end
		local down = towerDown(st)
		table.insert(s6, string.format("%d→wieża %d/%d%s", i, down, #towerIds, if f and f.plan then string.format(" (kolaps: %d grup)", #f.plan.groups) else ""))
		if not bombsToTower and down >= #towerIds * 0.8 then
			bombsToTower = i
		end
	end
	L("S6 bomby w parter: " .. table.concat(s6, " | "))
	L(string.format("   wieża leży po %s bombach (cel Kacpra ~8)  %s",
		if bombsToTower then tostring(bombsToTower) else "więcej niż " .. #result.stats.bombPlan,
		if bombsToTower then "✅" else "⚠️"))
	if lastPlan then
		local g = lastPlan.groups
		local maxChunks, maxFoot, pivots, followers = 0, 0, 0, 0
		for _, grp in ipairs(g) do
			maxChunks = math.max(maxChunks, #grp.chunkIds)
			maxFoot = math.max(maxFoot, math.max(grp.max.X - grp.min.X, grp.max.Z - grp.min.Z))
			if #grp.pivot > 0 then pivots += 1 end
			followers += #grp.followers
		end
		L(string.format("   ostatni kolaps: %d grup, największa %d chunków / rzut %.0f, z zawiasem %d, pasażerów %d, przyczyna seq %s (atakujący %s), asysty %d",
			#g, maxChunks, maxFoot, pivots, followers,
			if lastPlan.cause then tostring(lastPlan.cause.seq) else "-",
			if lastPlan.cause then tostring(lastPlan.cause.attackerUserId) else "-", #lastPlan.assists))
	end
	L("   stan końcowy: " .. fmtStates(st))

	-- S7: dwie bomby w tej samej klatce (jeden flush) vs osobno — ten sam wynik.
	local plan2 = result.stats.bombPlan
	if #plan2 >= 2 then
		local a = newState(ctx)
		bomb(ctx, a, plan2[1].at)
		bomb(ctx, a, plan2[2].at)
		a:flush()
		local b = newState(ctx)
		bomb(ctx, b, plan2[1].at)
		b:flush()
		bomb(ctx, b, plan2[2].at)
		b:flush()
		local same = stateKey(a) == stateKey(b)
		L(string.format("S7 dwie bomby w jednej klatce vs po kolei: ten sam wynik=%s  %s", tostring(same), if same then "✅" else "❌"))
	end

	-- S8: bomba w środek spadającej grupy — spadające chunki się nie zmieniają.
	if lastPlan and #lastPlan.groups > 0 then
		local g = lastPlan.groups[1]
		local target = st.chunks[g.chunkIds[1]]
		local before: { [number]: string } = {}
		for id, rt in pairs(st.rt) do
			if rt.state == "Falling" then
				before[id] = rt.state
			end
		end
		bomb(ctx, st, target.center, 99)
		local f = st:flush()
		local changed = 0
		for id in pairs(before) do
			if st.rt[id].state ~= "Falling" then
				changed += 1
			end
		end
		local replanned = 0
		if f and f.plan then
			for _, grp in ipairs(f.plan.groups) do
				for _, id in ipairs(grp.chunkIds) do
					if before[id] then
						replanned += 1
					end
				end
			end
		end
		L(string.format("S8 bomba w spadającą grupę: zmienionych spadających %d, ponownie zaplanowanych %d  %s",
			changed, replanned, if changed == 0 and replanned == 0 then "✅" else "❌"))
	end

	return table.concat(lines, "\n"), st, lastPlan
end

-- ============================================================================
-- Podgląd stanu (Studio): stoi = blada zieleń, osłabiony = pomarańcz, zniszczony = czerwień,
-- spadający = kolor grupy (każda grupa inny), listwy/ozdoby = jak właściciel, bladziej
-- ============================================================================

local GROUP_COLORS = {
	Color3.fromRGB(80, 140, 255), Color3.fromRGB(255, 210, 60), Color3.fromRGB(200, 90, 255),
	Color3.fromRGB(60, 220, 220), Color3.fromRGB(255, 120, 180), Color3.fromRGB(150, 255, 90),
	Color3.fromRGB(255, 150, 60), Color3.fromRGB(120, 120, 255),
}

function StructureTests.show(state: BuildingState, plan: BuildingState.CollapsePlan?)
	local folder = StructureBake.debugFolder()
	local groupColor: { [number]: Color3 } = {}
	if plan then
		for i, g in ipairs(plan.groups) do
			for _, id in ipairs(g.chunkIds) do
				groupColor[id] = GROUP_COLORS[(i - 1) % #GROUP_COLORS + 1]
			end
		end
	end
	for _, c in ipairs(state.chunks) do
		local rt = state.rt[c.id]
		if rt.state == "Destroyed" then
			StructureBake.box(folder, c.min, c.max, Color3.fromRGB(200, 30, 30), 0.2, true)
		elseif rt.state == "Falling" then
			StructureBake.box(folder, c.min, c.max, groupColor[c.id] or Color3.fromRGB(80, 140, 255), 0.25, false)
		elseif rt.state == "Damaged" then
			StructureBake.box(folder, c.min, c.max, Color3.fromRGB(255, 140, 30), 0.3, false)
		else
			StructureBake.box(folder, c.min, c.max, Color3.fromRGB(90, 200, 110), 0.75, false)
		end
	end
end

return StructureTests
