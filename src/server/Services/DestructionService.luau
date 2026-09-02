--!strict
-- DestructionService.luau
-- SYSTEM DESTRUKCJI v2 — etap 1+2. Pełny plan i decyzje: DESTRUCTION_PLAN.md.
--
-- Wejście dla KAŻDEGO źródła wybuchu (bomba dziś, sabotage/kule ognia jutro):
--   DestructionService.detonate(center, params, attacker)
--
-- Ten service odpowiada WYŁĄCZNIE za skutki wybuchu na geometrii i gruzie:
--   - fala uderzeniowa z falloffem SKUTKU: blisko NISZCZY (fracture na nierówne kawałki
--     → realna dziura w ścianie), średnio RANI (HP w attribute + przyciemnienie/pył —
--     dobije następna bomba), daleko PCHA (impuls na wszystko już-nieanchorowane)
--   - kategorie (etap 2): tag "Pillar" → filar (HP na 2-3 bomby), Material Glass → szyba
--     (ginie od samej fali w dużym glassRadius, odłamki kliencki), ActiveBridges → most
--     (kruche drewno), reszta → ściana
--   - podparcie (etap 2): anchored remnant bez łączności z resztą świata SPADA jak gruz
--     (odpowiedź na test: "większe party wiszą anchored po wybuchu")
--   - hybrydowy gruz: serwer trzyma tylko znaczące kawałki (rejestr w DebrisService),
--     drobnicę i całe VFX wybuchu renderują klienci lokalnie (Remotes.BlastFX + seed)
-- Damage/knockback/ragdoll GRACZY nie jest tu — robi go BombService.applyDamageAndKnockback,
-- ale osłonę (occlusion przez ściany) liczy TEN service: computeOcclusion.
--
-- Struktura wyniku fracture:
--   - kawałki w kuli wybuchu → nieanchorowany gruz w Workspace.BlastDebris (impuls stożkiem)
--   - kawałki poza kulą → anchored "remnants" w miejscu oryginału (Parent = Parent oryginału;
--     w Map sprząta je MapService restore, w ActiveBridges — BridgeService cleanup)
--   - non-Block (Wedge/Mesh/Union/kule/cylindry) nie da się pociąć → lecą W CAŁOŚCI

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Destructible = require(ReplicatedStorage.Shared.Modules.Destructible)
local DebrisService = require(script.Parent.DebrisService)
local StructureService = require(script.Parent.StructureService)

local DestructionService = {}

local CFG = Config.Destruction
local CAT = CFG.Categories
local FRAC = CFG.Fracture
local WAVE = CFG.Shockwave
local FEED = CFG.DamageFeedback
local OCC = CFG.Occlusion
local SUP = CFG.Support

local rng = Random.new()

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

export type DestructionParams = {
	radius: number,       -- zasięg działania na geometrię (stud)
	damage: number,       -- dmg strukturalny w epicentrum (liniowy falloff do 0 na krawędzi)
	impulse: number,      -- prędkość gruzu w epicentrum (stud/s)
	minImpulseT: number?, -- floor falloffu impulsu (krawędź ma drgnąć, nie stać)
	glassRadius: number?, -- osobny (większy) promień tłuczenia szyb; 0/nil = tylko główny
}

export type BlastStats = {
	structural: number, -- anchored kandydaci w zasięgu
	fractured: number,  -- partów pociętych na kawałki
	launched: number,   -- partów wystrzelonych w całości (non-Block / brak budżetu)
	damaged: number,    -- partów rannych (HP attribute, przetrwały)
	glass: number,      -- stłuczonych szyb
	felled: number,     -- remnantów które spadły z braku podparcia
	chunks: number,     -- kawałków gruzu serwerowego stworzonych
	pushed: number,     -- już-nieanchorowanych obiektów pchniętych falą
	millis: number,
}

-- Attribute na partach mapy: pozostałe HP strukturalne (brak = pełne HP kategorii).
local HP_ATTR = "DestrHP"
-- Attribute: oryginalny kolor sprzed przyciemnienia (feedback obrażeń).
local ORIG_COLOR_ATTR = "DestrOrigColor"
-- Attribute na gruzie: UserId sprawcy (etap 3: crush kill credit).
local ATTACKER_ATTR = "BlastAttackerId"

-- ============================================================================
-- Ochrona i kwalifikacja — reguły w `Shared.Modules.Destructible` (współdzielone
-- z klientem, żeby FX nie rysowało zniszczenia tam, gdzie serwer nic nie niszczy).
-- ============================================================================

type Ctx = Destructible.Context
local buildCtx = Destructible.buildContext
local isProtected = Destructible.isProtected
local isDestructible = Destructible.isDestructible

-- Kategoria → max HP. Kolejność: tag filara wygrywa z materiałem i lokalizacją.
-- (Szyby w GŁÓWNYM promieniu nie przechodzą przez HP — tłucze je osobny pass glassRadius.)
local function categoryHP(part: BasePart, ctx: Ctx): number
	if CollectionService:HasTag(part, CFG.PillarTag) then
		return CAT.Pillar.HP
	end
	if ctx.activeBridges and part:IsDescendantOf(ctx.activeBridges) then
		return CAT.Bridge.HP
	end
	return CAT.Wall.HP
end

-- ============================================================================
-- Matematyka fali (przeniesiona 1:1 ze sprawdzonych lekcji — patrz DESTRUCTION_PLAN.md)
-- ============================================================================

-- Odległość do POWIERZCHNI parta, nie środka. Dla non-Block (kule, wedge) przybliżenie
-- bounding boxem — wystarczające.
local function surfaceDistance(part: BasePart, point: Vector3): number
	local lp = part.CFrame:PointToObjectSpace(point)
	return Fracture.boxSurfaceDistance(Vector3.zero, part.Size, lp)
end

-- Stożek "na zewnątrz i w górę": stromo w epicentrum (jedyna wolna droga to góra),
-- płasko na krawędzi (wolna przestrzeń w bok). Nigdy w dół.
local function launchDirection(position: Vector3, center: Vector3, distance: number, radius: number): Vector3
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
local function sizeScale(size: Vector3): number
	local volume = math.max(size.X * size.Y * size.Z, 0.001)
	return math.clamp((WAVE.ReferenceChunkVolume / volume) ^ WAVE.SizeFalloffPower, WAVE.MinSizeScale, 1)
end

local function applyImpulse(part: BasePart, center: Vector3, radius: number, impulse: number, minT: number)
	local d = surfaceDistance(part, center)
	local t = math.max(1 - d / radius, minT)
	local scale = sizeScale(part.Size)
	part.AssemblyLinearVelocity = launchDirection(part.Position, center, d, radius) * impulse * t * scale
	part.AssemblyAngularVelocity = Vector3.new(
		(rng:NextNumber() * 2 - 1) * WAVE.Spin,
		(rng:NextNumber() * 2 - 1) * WAVE.Spin,
		(rng:NextNumber() * 2 - 1) * WAVE.Spin
	) * (t * scale)
end

-- ============================================================================
-- Feedback obrażeń: ranny part ciemnieje + pyli (bez tego mechanika HP jest niewidzialna
-- i filar "na 3 bomby" wygląda jak bug "bomba nie działa")
-- ============================================================================

local function applyDamageFeedback(part: BasePart, hpLeft: number, maxHp: number, dmg: number)
	local orig = part:GetAttribute(ORIG_COLOR_ATTR)
	if typeof(orig) ~= "Color3" then
		orig = part.Color
		part:SetAttribute(ORIG_COLOR_ATTR, orig)
	end
	local frac = 1 - math.clamp(hpLeft / maxHp, 0, 1)
	part.Color = (orig :: Color3):Lerp(Color3.fromRGB(35, 32, 30), frac * FEED.DarkenMax)

	-- Pył tylko przy konkretnym trafieniu — krawędź zasięgu nie spamuje emitterami
	-- (server-side instancja = replikacja do wszystkich, oszczędzamy).
	if dmg >= FEED.DustMinDamage and FEED.DustPerHit > 0 then
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = SMOKE_TEXTURE
		dust.Color = ColorSequence.new(Color3.fromRGB(170, 158, 140), Color3.fromRGB(120, 112, 100))
		dust.Size = NumberSequence.new(1.2, 3.5)
		dust.Transparency = NumberSequence.new(0.4, 1)
		dust.Lifetime = NumberRange.new(0.5, 0.9)
		dust.Rate = 0
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.Speed = NumberRange.new(3, 8)
		dust.Parent = part
		dust:Emit(FEED.DustPerHit)
		Debris:AddItem(dust, 1.5)
	end
end

-- ============================================================================
-- Fracture: part → gruz + remnants
-- ============================================================================

local function copyVisuals(source: BasePart, target: BasePart)
	target.Color = source.Color
	target.Material = source.Material
	target.Transparency = source.Transparency
	target.Reflectance = source.Reflectance
	target.CastShadow = source.CastShadow
end

local function spawnDebrisChunk(
	source: BasePart,
	cf: CFrame,
	size: Vector3,
	center: Vector3,
	radius: number,
	impulse: number,
	minT: number,
	attackerId: number
)
	-- Czasem wedge zamiast boxa — poszarpane krawędzie czytają się jako "odłamany".
	local part: BasePart
	if rng:NextNumber() < FRAC.WedgeChance then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end

	part.Name = "BlastChunk"
	-- Lekki shrink + obrót: kawałki nie tworzą idealnej siatki, gruz wygląda na połamany.
	part.Size = size * FRAC.ChunkShrink
	local rj = math.rad(FRAC.ChunkRotJitter)
	part.CFrame = cf * CFrame.Angles(
		rng:NextNumber(-rj, rj),
		rng:NextNumber(-rj, rj),
		rng:NextNumber(-rj, rj)
	)
	copyVisuals(source, part)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = true
	part:SetAttribute(ATTACKER_ATTR, attackerId)
	part.Parent = DebrisService.getFolder()

	DebrisService.register(part)
	applyImpulse(part, center, radius, impulse, minT)
end

local function spawnRemnant(source: BasePart, cf: CFrame, size: Vector3, remnantsOut: { BasePart })
	local part = Instance.new("Part")
	-- Nazwa oryginału — remnant to dalej "ściana": kolejna bomba potnie go dalej,
	-- a restore (MapService / BridgeService cleanup) sprzątnie z końcem rundy.
	part.Name = source.Name
	part.Size = size
	part.CFrame = cf
	copyVisuals(source, part)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = source.CanCollide
	-- HP celowo świeże (pełne HP kategorii, bez attribute) — remnant jest mniejszy od
	-- oryginału, "ranny" remnant z ułamkiem HP sypałby się od kichnięcia.
	-- Filar-remnant PRZESTAJE być filarem (tag nie przechodzi) — pocięty filar to gruz ścian.
	part.Parent = source.Parent
	table.insert(remnantsOut, part)
end

-- Wystrzel part W CAŁOŚCI (non-Block których nie umiemy ciąć / resztka budżetu).
local function launchWhole(
	part: BasePart,
	center: Vector3,
	radius: number,
	impulse: number,
	minT: number,
	attackerId: number
)
	-- Destroy jointów PRZED odkotwiczeniem — ozdoby bywają zweldowane w modele.
	for _, joint in ipairs(part:GetJoints()) do
		if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
			joint:Destroy()
		end
	end
	part.Anchored = false
	part:SetAttribute(ATTACKER_ATTR, attackerId)
	part.Parent = DebrisService.getFolder()
	DebrisService.register(part)
	applyImpulse(part, center, radius, impulse, minT)
end

-- Tnie Block part: kawałki w kuli wybuchu → gruz, poza → anchored remnants.
-- Zwraca liczbę zużytych kawałków gruzu (budżet).
-- `holeRadius` — promień DZIURY, nie zasięgu wybuchu. Wyprowadzany z modelu obrażeń
-- (patrz caller): tam gdzie bomba zadaje więcej niż HP kategorii, materiał znika.
-- Dzięki temu mocniejsza bomba robi większą dziurę bez żadnej osobnej gałki, a bomba
-- o radius 24 NIE wycina 48-studowego okna w ścianie (regres z testu 2026-08-12).
local function fractureBlock(
	part: BasePart,
	center: Vector3,
	radius: number,
	holeRadius: number,
	impulse: number,
	minT: number,
	attackerId: number,
	chunkBudget: number,
	remnantsOut: { BasePart }
): number
	local localCenter = part.CFrame:PointToObjectSpace(center)
	local maxChunks = math.min(FRAC.MaxChunksPerPart, chunkBudget)

	-- Wariacja PER WYBUCH: bez niej dwie bomby w tę samą ścianę dawały bliźniaczy wzór.
	local target = FRAC.TargetChunkSize * rng:NextNumber(1 - FRAC.ChunkSizeJitter, 1 + FRAC.ChunkSizeJitter)
	local effectiveHole = holeRadius * rng:NextNumber(1 - FRAC.HoleRadiusJitter, 1 + FRAC.HoleRadiusJitter)
	-- Przesunięcie szumu: ten sam kształt wyrwy nie powtórzy się w innym wybuchu.
	local noiseOffset = rng:NextNumber(0, 1000)

	-- Promień dziury modulowany szumem Perlina zależnym od KIERUNKU — granica przestaje
	-- być kulą, robi się poszarpaną wyrwą. Kawałki są boxami, więc krawędź i tak jest
	-- schodkowa, ale to obrys decyduje o tym, czy dziura czyta się jako "wyrwana" czy
	-- "wycięta cyrklem". Cięcie tnie do `effectiveHole × (1 + irregularity)`, żeby pas
	-- wybrzuszeń też był rozdrobniony — inaczej wyrwa miałaby ząbki wielkości płyt.
	local function holeRadiusToward(offset: Vector3): number
		if FRAC.HoleIrregularity <= 0 then return effectiveHole end
		local d = offset - localCenter
		local n = math.noise(
			d.X * FRAC.HoleNoiseScale + noiseOffset,
			d.Y * FRAC.HoleNoiseScale,
			d.Z * FRAC.HoleNoiseScale + noiseOffset
		)
		return effectiveHole * (1 + math.clamp(n * 2, -1, 1) * FRAC.HoleIrregularity)
	end

	local chunks = Fracture.slice(
		part.Size,
		target,
		FRAC.MinChunkSize,
		maxChunks,
		rng,
		{ center = localCenter, radius = effectiveHole * (1 + FRAC.HoleIrregularity) }
	)

	local used = 0
	for _, chunk in ipairs(chunks) do
		local worldCF = part.CFrame * CFrame.new(chunk.offset)
		-- Test po ŚRODKU kawałka, nie po jego powierzchni. Przy dystansie do powierzchni
		-- wielka płyta, która ledwo dotyka epicentrum rogiem, kwalifikowała się jako
		-- "w wybuchu" i odlatywała CAŁA — to był powód "wysadzam ścianę i nie ma ściany".
		-- Po środku: odlatuje to, co realnie jest w dziurze, reszta zostaje jako remnant.
		local inBlast = (chunk.offset - localCenter).Magnitude <= holeRadiusToward(chunk.offset)
		if inBlast and used < maxChunks then
			spawnDebrisChunk(part, worldCF, chunk.size, center, radius, impulse, minT, attackerId)
			used += 1
		else
			-- Poza kulą ALBO budżet wyczerpany w połowie parta — kawałek zostaje w świecie
			-- (pass podparcia niżej zdecyduje, czy ma prawo wisieć).
			spawnRemnant(part, worldCF, chunk.size, remnantsOut)
		end
	end

	part:Destroy()
	return used
end

-- ============================================================================
-- Szyby (etap 2): giną od samej fali w dużym promieniu, przez ściany (bez occlusion —
-- design: "szyby sypią się na sąsiednich blokach"). Zero gruzu serwerowego.
-- ============================================================================

type GlassPane = { cf: CFrame, size: Vector3, color: Color3 }
type GlassEntry = { pane: GlassPane, distance: number, part: BasePart }

local function shatterGlass(center: Vector3, glassRadius: number, ctx: Ctx): ({ GlassPane }, number)
	if glassRadius <= 0 then
		return {}, 0
	end

	local entries: { GlassEntry } = {}
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(center, glassRadius)) do
		if part.Material ~= Enum.Material.Glass then continue end
		if part:IsA("Terrain") then continue end
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then continue end
		if isProtected(part, ctx) then continue end
		if not isDestructible(part, ctx) then continue end
		if DebrisService.isRegistered(part) then continue end

		table.insert(entries, {
			pane = { cf = part.CFrame, size = part.Size, color = part.Color },
			distance = (part.Position - center).Magnitude,
			part = part,
		})
	end

	-- Server tłucze WSZYSTKIE; payload FX capowany do najbliższych (bandwidth).
	table.sort(entries, function(a, b)
		return a.distance < b.distance
	end)

	local panes: { GlassPane } = {}
	for i, entry in ipairs(entries) do
		entry.part:Destroy()
		if i <= CFG.FX.GlassMaxPanes then
			table.insert(panes, entry.pane)
		end
	end
	return panes, #entries
end

-- ============================================================================
-- Podparcie (etap 2, wersja 2 po teście "wysadziłem dół i reszta wisi"): sprawdzamy
-- PIONOWĄ KOLUMNĘ geometrii wokół epicentrum — nie tylko świeże remnanty, ale też
-- pre-istniejące party (piętra NAD wybuchem). Part bez transytywnej drogi podparcia
-- spada jak gruz. KIERUNKOWO: sąsiad całkowicie POWYŻEJ parta go nie podpiera
-- ("wiszenie na niebie" nie istnieje); kontakt boczny (przęsło, wspornik) podpiera.
-- UWAGA: to jest "structural lite" per wybuch — pełny kolaps sekcji (filary) to etap 4.
-- ============================================================================

-- Połowa wysokości world-space AABB parta (działa dla obróconych).
local function worldHalfY(part: BasePart): number
	local cf = part.CFrame
	local s = part.Size * 0.5
	return math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z
end

local function settleStructure(
	center: Vector3,
	radius: number,
	remnants: { BasePart },
	attackerId: number,
	ctx: Ctx
): number
	if not SUP.Enabled then
		return 0
	end

	-- ---- Zbiór kandydatów: kolumna + remnanty -----------------------------
	local set: { [BasePart]: boolean } = {}
	local list: { BasePart } = {}

	local function addCandidate(part: BasePart)
		if set[part] then return end
		if not part.Parent or not part.Anchored then return end
		if DebrisService.isRegistered(part) then return end
		set[part] = true
		table.insert(list, part)
	end

	local columnSize = Vector3.new(
		radius * SUP.ColumnRadiusFactor * 2,
		SUP.ColumnHeight,
		radius * SUP.ColumnRadiusFactor * 2
	)
	for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(center), columnSize)) do
		if part:IsA("Terrain") then continue end
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then continue end
		if isProtected(part, ctx) then continue end
		-- Tylko geometria mapy. Mosty graczy NIE wchodzą z samej bliskości (wiszą w
		-- powietrzu Z DESIGNU — sprawdzanie podparcia by je zrzucało przy każdej bombie);
		-- ich połamane kawałki wchodzą przez listę remnants niżej.
		if not (ctx.map and part:IsDescendantOf(ctx.map)) then continue end
		addCandidate(part)
	end
	for _, r in ipairs(remnants) do
		addCandidate(r)
	end

	if #list == 0 then
		return 0
	end

	-- ---- Sąsiedztwo + zewnętrzne podpory ----------------------------------
	local halfYCache: { [BasePart]: number } = {}
	local function getHalfY(p: BasePart): number
		local v = halfYCache[p]
		if not v then
			v = worldHalfY(p)
			halfYCache[p] = v
		end
		return v
	end

	local supported: { [BasePart]: boolean } = {}
	local queue: { BasePart } = {}
	-- adjOut[n] = party które n podpiera (krawędzie skierowane w górę/w bok).
	local adjOut: { [BasePart]: { BasePart } } = {}
	local pad = Vector3.one * (SUP.Padding * 2)

	for _, p in ipairs(list) do
		if not p.Parent then continue end
		local pTop = p.Position.Y + getHalfY(p)
		for _, n in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + pad)) do
			if n == p or n:IsA("Terrain") then continue end
			-- Kierunkowość: n może podpierać p tylko gdy NIE jest całkowicie nad nim.
			local nBottom = n.Position.Y - getHalfY(n)
			if nBottom >= pTop - SUP.AboveEpsilon then continue end

			if set[n] then
				local out = adjOut[n]
				if not out then
					out = {}
					adjOut[n] = out
				end
				table.insert(out, p)
			elseif n.Anchored and not DebrisService.isRegistered(n) then
				-- Zewnętrzna podpora: protected (Baseplate, Map.Locked), geometria poza
				-- kolumną, lobby. Uśpiony gruz (w rejestrze) NIE podpiera — sam może odlecieć.
				if not supported[p] then
					supported[p] = true
					table.insert(queue, p)
				end
			end
		end
	end

	-- ---- BFS: podparcie rozchodzi się po krawędziach ----------------------
	local i = 1
	while i <= #queue do
		local p = queue[i]
		i += 1
		for _, q in ipairs(adjOut[p] or {}) do
			if not supported[q] then
				supported[q] = true
				table.insert(queue, q)
			end
		end
	end

	-- ---- Niepodparte spadają ----------------------------------------------
	local felled = 0
	for _, p in ipairs(list) do
		if p.Parent and not supported[p] then
			p.Anchored = false
			p:SetAttribute(ATTACKER_ATTR, attackerId)
			p.Parent = DebrisService.getFolder()
			DebrisService.register(p)
			-- Lekki tumble — spadająca płyta nie jedzie w dół jak winda.
			p.AssemblyAngularVelocity = Vector3.new(
				rng:NextNumber(-1, 1),
				rng:NextNumber(-1, 1),
				rng:NextNumber(-1, 1)
			) * 2
			felled += 1
		end
	end
	return felled
end

-- ============================================================================
-- Occlusion (etap 2): ile osłony mają gracze za ścianami. Publiczne API dla BombService.
-- Liczone PO destrukcji geometrii — zdmuchnięta ściana nie osłania (jest po niej dziura).
-- ============================================================================

function DestructionService.computeOcclusion(center: Vector3, targetPos: Vector3): number
	if not OCC.Enabled then return 1 end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { DebrisService.getFolder() } -- latający gruz nie osłania
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then table.insert(exclude, char) end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true

	local origin = center
	local hits = 0
	for _ = 1, OCC.MaxHits do
		local delta = targetPos - origin
		if delta.Magnitude < 0.5 then break end
		local result = Workspace:Raycast(origin, delta, params)
		if not result then break end
		local inst = result.Instance
		-- Szkło i mocno przezroczyste nie osłaniają (i tak pękają od fali).
		if inst.Material ~= Enum.Material.Glass and inst.Transparency < 0.5 and inst.CanCollide then
			hits += 1
		end
		origin = result.Position + delta.Unit * 0.1
	end
	return OCC.PerWallFactor ^ hits
end

-- ============================================================================
-- Detonacja
-- ============================================================================

type StructCandidate = { part: BasePart, distance: number }

function DestructionService.detonate(center: Vector3, params: DestructionParams?, attacker: Player?): BlastStats?
	if not params then return nil end
	local radius = params.radius or 0
	if radius <= 0 then return nil end
	local damage = params.damage or 0
	local impulse = params.impulse or 0
	local minT = params.minImpulseT or 0.1
	local glassRadius = params.glassRadius or 0
	local attackerId = attacker and attacker.UserId or 0

	local startClock = os.clock()
	local ctx = buildCtx()

	-- ---- Szyby PRZED BlastFX — payload musi mieć listę stłuczonych szyb ----
	local glassPanes, glassCount = shatterGlass(center, glassRadius, ctx)

	-- VFX — klienci mają widzieć błysk w tej samej klatce co skutki fizyczne.
	-- Seed pozwala każdemu klientowi wygenerować IDENTYCZNE kosmetyczne odłamki lokalnie.
	local seed = rng:NextInteger(1, 2_000_000_000)
	Remotes.BlastFX:FireAllClients(center, radius, seed, glassPanes)

	-- ---- Zbiórka i klasyfikacja -------------------------------------------
	local structList: { StructCandidate } = {}
	local pushList: { BasePart } = {}
	-- Diagnostyka kontraktu mapy: party, które wybuch OBJĄŁ, ale nie mógł pociąć.
	-- Bez tego "postawiłem klocki i nic się nie dzieje" nie daje ŻADNEGO sygnału —
	-- a przyczyną jest zwykle jedno z dwóch przeoczeń przy budowaniu (2026-08-12).
	local skipOutsideMap: { BasePart } = {}
	local skipUnanchored: { BasePart } = {}

	for _, part in ipairs(Workspace:GetPartBoundsInRadius(center, radius)) do
		-- Terrain to też BasePart — Anchored=false na nim rzuca error.
		if part:IsA("Terrain") then continue end
		-- Gracze: damage/knockback robi BombService. Łapie też Accessory (rodzic = Character).
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then continue end
		-- Chronione są pomijane ŚWIADOMIE (kontrakt) — nie raportujemy ich jako problem.
		if isProtected(part, ctx) then continue end

		if DebrisService.isRegistered(part) then
			-- Nasz gruz (nawet uśpiony-zakotwiczony) — budzimy i pchamy, NIE tniemy dalej.
			table.insert(pushList, part)
		elseif part.Anchored then
			if isDestructible(part, ctx) then
				table.insert(structList, { part = part, distance = surfaceDistance(part, center) })
			else
				table.insert(skipOutsideMap, part)
			end
		else
			-- Luźne nieanchorowane (BombProjectile innych bomb itp.) — sama fala.
			-- Nieanchorowany part to dla systemu gruz, nie konstrukcja: nie pęka.
			table.insert(skipUnanchored, part)
			table.insert(pushList, part)
		end
	end

	if CFG.Debug and (#skipOutsideMap > 0 or #skipUnanchored > 0) then
		local function sample(list: { BasePart }): string
			local names = {}
			for i = 1, math.min(3, #list) do
				table.insert(names, list[i]:GetFullName())
			end
			return table.concat(names, ", ")
		end
		if #skipOutsideMap > 0 then
			warn(("[Destr] %d partów w zasięgu NIE zostało pociętych — są POZA Workspace.Map (kontrakt: cała geometria budynków pod Map). Przykłady: %s"):format(
				#skipOutsideMap, sample(skipOutsideMap)))
		end
		if #skipUnanchored > 0 then
			warn(("[Destr] %d partów w zasięgu NIE zostało pociętych — mają Anchored=false (nieanchorowany part = gruz, nie konstrukcja; dostaje tylko impuls). Przykłady: %s"):format(
				#skipUnanchored, sample(skipUnanchored)))
		end
	end

	-- Najbliższe pierwsze — budżet gruzu ma ucinać DALEKIE skutki, nie losowe.
	table.sort(structList, function(a, b)
		return a.distance < b.distance
	end)

	-- Budżet kawałków: sufit per wybuch + globalny soft-cap. MinChunksPerBlast gwarantuje,
	-- że bomba za 50$ przy zapchanym serwerze i tak coś rozwali (lekcja ze starego systemu).
	local globalRoom = math.max(
		CFG.Debris.MinChunksPerBlast,
		CFG.Debris.MaxMovingDebris - DebrisService.getMovingCount()
	)
	local chunkBudget = math.min(FRAC.MaxServerChunksPerBlast, globalRoom)

	-- ---- Pass 1: struktura (damage → fracture / launch / ranny) ------------
	local fractured = 0
	local launched = 0
	local damaged = 0
	local chunksUsed = 0
	local remnants: { BasePart } = {}

	for _, cand in ipairs(structList) do
		local part = cand.part
		-- Part mógł zniknąć w trakcie (drugi wybuch w tej samej klatce, restore).
		if not part.Parent then continue end
		-- Mógł też przestać być strukturą W TRAKCIE tej pętli: kolaps sekcji (wywołany
		-- kilka iteracji wcześniej przez padnięty filar) odkotwicza całe piętro i oddaje
		-- je DebrisService. Taki part to już gruz — nie tniemy go drugi raz, dostanie
		-- tylko impuls w passie fali.
		if DebrisService.isRegistered(part) then
			table.insert(pushList, part)
			continue
		end

		local dmg = damage * (1 - math.clamp(cand.distance / radius, 0, 1))
		if dmg <= 0 then continue end

		local maxHp = categoryHP(part, ctx)
		local hpAttr = part:GetAttribute(HP_ATTR)
		local hp = if typeof(hpAttr) == "number" then hpAttr :: number else maxHp

		if dmg < hp then
			-- RANNY: przeżył, ale następna bomba dobije. Ciemnieje + pyli (czytelny stan).
			part:SetAttribute(HP_ATTR, hp - dmg)
			applyDamageFeedback(part, hp - dmg, maxHp, dmg)
			damaged += 1
			continue
		end

		-- ZNISZCZONY.
		-- Filar musi zgłosić się do StructureService ZANIM zniknie — po Destroy nie da
		-- się już odczytać jego tagu ani pozycji. Kolaps (jeśli padł ostatni filar pasma)
		-- leci od razu; kawałki tego filara i tak powstaną niżej.
		if CollectionService:HasTag(part, CFG.PillarTag) then
			StructureService.notifyPillarDestroyed(part, attackerId)
		end

		-- Promień DZIURY z modelu obrażeń: materiał znika tam, gdzie bomba zadaje więcej
		-- niż zostało HP. `hp` to stan RESZTKOWY, więc dobity filar (HP 300, ostatnie 40)
		-- robi dziurę tak dużą jak ściana z HP 40 — spójne bez dodatkowych gałek.
		local holeRadius = math.clamp(
			radius * (1 - hp / damage),
			FRAC.MinHoleRadius,
			radius
		)

		local remaining = chunkBudget - chunksUsed
		if part:IsA("Part") and part.Shape == Enum.PartType.Block and remaining >= 4 then
			local used = fractureBlock(part, center, radius, holeRadius, impulse, minT, attackerId, remaining, remnants)
			chunksUsed += used
			fractured += 1
		elseif remaining >= 1 then
			launchWhole(part, center, radius, impulse, minT, attackerId)
			chunksUsed += 1
			launched += 1
		else
			-- Budżet w zerze: zostaw na 1 HP — wygląda na "ledwo się trzyma", dobije
			-- następna bomba gdy budżet wróci (gruz usypia po ~0.6s).
			part:SetAttribute(HP_ATTR, 1)
			applyDamageFeedback(part, 1, maxHp, dmg)
			damaged += 1
		end
	end

	-- ---- Pass 2: fala na już-nieanchorowanych ------------------------------
	-- Assembly ma JEDNĄ prędkość — dedup po AssemblyRootPart, żeby drugi zapis nie
	-- nadpisywał pierwszego w ramach tej samej bryły.
	local pushed = 0
	local handledAssemblies: { [BasePart]: boolean } = {}

	for _, part in ipairs(pushList) do
		if not part.Parent then continue end
		DebrisService.wake(part) -- no-op dla nie-gruzu

		local root = part.AssemblyRootPart or part
		if handledAssemblies[root] then continue end
		handledAssemblies[root] = true

		applyImpulse(part, center, radius, impulse, minT)
		pushed += 1
	end

	-- ---- Pass 3: podparcie -------------------------------------------------
	-- Jedna klatka przerwy ZANIM liczymy sąsiedztwo: świeżo stworzone remnanty muszą
	-- wejść do broadphase spatial queries, inaczej GetPartBoundsInBox ich nie widzi
	-- i pass podparcia liczy na dziurawych danych. Detonate i tak żyje w wątku fuse
	-- (task.delay), więc yield jest bezpieczny; damage graczy (BombService, po return)
	-- przesuwa się o klatkę — niezauważalne.
	task.wait()
	local felled = settleStructure(center, radius, remnants, attackerId, ctx)

	local stats: BlastStats = {
		structural = #structList,
		fractured = fractured,
		launched = launched,
		damaged = damaged,
		glass = glassCount,
		felled = felled,
		chunks = chunksUsed,
		pushed = pushed,
		millis = (os.clock() - startClock) * 1000,
	}

	if CFG.Debug then
		print(("[Destr] r=%d dmg=%d | struktura=%d pękło=%d całych=%d rannych=%d szkło=%d spadło=%d | kawałki=%d pchnięte=%d | gruz=%d/%d ms=%.2f"):format(
			radius, damage,
			stats.structural, stats.fractured, stats.launched, stats.damaged,
			stats.glass, stats.felled,
			stats.chunks, stats.pushed,
			DebrisService.getMovingCount(), CFG.Debris.MaxMovingDebris, stats.millis))
	end

	return stats
end

function DestructionService.init()
	-- Stateless poza rng — init tylko dosypuje folder gruzu wcześnie, żeby klienci mieli
	-- go zreplikowanego zanim poleci pierwszy kawałek.
	DebrisService.getFolder()
end

return DestructionService
