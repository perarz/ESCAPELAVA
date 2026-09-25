--!strict
-- DestructionService.luau
-- SYSTEM DESTRUKCJI — v2 (2026-08-11, etapy 1+2) przebudowany do v3 (2026-09-23).
-- Pełny plan i decyzje: DESTRUCTION_PLAN.md (rozdział „v3”).
--
-- Wejście dla KAŻDEGO źródła wybuchu (bomba dziś, sabotage/kule ognia jutro):
--   DestructionService.detonate(center, params, attacker)
--
-- v3 W JEDNYM ZDANIU: serwer trzyma tylko STAN GRY (dziury, resztki ścian, duże płyty),
-- wszystko drobne animują KLIENCI — każdy w swoim trybie grafiki (Config.Graphics).
-- Powód (zgłoszenie Kacpra po testach na telefonach z kolegami: „4 bomby naraz = lagi,
-- przenikanie przez podłogę, wieszaki znikają”), zmierzone na mapie:
--   * do 110 kawałków dziury na wybuch było fizyką serwera — każdy replikował pozycję
--     do każdego gracza przez kilka sekund; 4 bomby = kilkaset ruchomych partów
--   * pass podparcia zrzucał party „niepodparte” JUŻ PRZED wybuchem (~3500 na mapie,
--     1724 w samym zielonym budynku) — każda bomba w pobliżu robiła z nich gruz
--   * każdy ranny part dostawał własny emiter pyłu tworzony na serwerze (338 z jednej bomby)
--   * podłogi to wielkie pojedyncze party; wybuch kasował oryginał i stawiał resztki jako
--     NOWE party — pod obciążeniem nowe docierały do telefonu później niż skasowanie,
--     więc gracz przez chwilę stał na niczym i spadał pod podłogę
--
-- PRZEBIEG WYBUCHU (plan → ogłoszenie → zastosowanie → podparcie):
--   1. PLAN — świat jeszcze nietknięty:
--        * szyby w glassRadius
--        * KONSTRUKCJA: HP z falloffem po dystansie do POWIERZCHNI; ranna ciemnieje;
--          zniszczony Block → plan dziury (Fracture.planHole z seedem); inna bryła →
--          wyrzut w całości (duża = gruz serwera, reszta = u klientów)
--        * DROBNICA: próg jednorazowy; pada cały MEBEL (Destructible.assemblyOf)
--        * drobnica leżąca na tym, co znika (dziura, wyrzucona bryła)
--   2. PODPARCIE „PRZED” — graf konstrukcji w kolumnie wokół epicentrum. Liczony
--      w środku planu: po klasyfikacji konstrukcji, ale ZANIM cokolwiek zostanie
--      oznaczone do przekazania klientom (inaczej oznaczone nie podpierałoby nawet „przed”)
--   3. OGŁOSZENIE — Remotes.BlastFX (wybuch, szyby, plany dziur) i Remotes.DebrisFall
--      (drobnica do przejęcia przez klientów)
--   4. ZASTOSOWANIE — szyby znikają; party z dziurą są PRZYCINANE, nie kasowane (applyCut);
--      wyrzucone lecą; drobnica znika po HandoffDelay
--   5. PODPARCIE „PO” (klatkę później, osobny wątek) — spada tylko to, co podparcie
--      STRACIŁO; największe płyty → gruz serwera, reszta → DebrisFall
-- Damage/knockback/ragdoll GRACZY nie jest tu — robi go BombService.applyDamageAndKnockback
-- zaraz po powrocie z detonate (po etapie 4, więc zdmuchnięta ściana już nie osłania).
-- Osłonę graczy (occlusion przez ściany) liczy TEN service: computeOcclusion.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Shockwave = require(ReplicatedStorage.Shared.Modules.Shockwave)
local Destructible = require(ReplicatedStorage.Shared.Modules.Destructible)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local DebrisService = require(script.Parent.DebrisService)
-- Destrukcja v4 (DESTRUCTION_PLAN.md → „v4”): party budynków z `Config.Structure.Buildings`
-- idą ścieżką v4 (dziura-prostokąt + stan konstrukcji), reszta mapy zostaje na v3.
-- JEDNO rozgałęzienie w pętli wybuchu (`ownerOf`) — v3 niczego w budynkach v4 nie tnie,
-- nie liczy im HP ani podparcia.
local StructuralService = require(script.Parent.StructuralService)
local CollapseService = require(script.Parent.CollapseService)

local DestructionService = {}

local CFG = Config.Destruction
local CAT = CFG.Categories
local FRAC = CFG.Fracture
local FEED = CFG.DamageFeedback
local OCC = CFG.Occlusion
local SUP = CFG.Support
local SMALL = CFG.Small
local DBR = CFG.Debris

local rng = Random.new()

export type DestructionParams = {
	radius: number,       -- zasięg działania na geometrię (stud)
	damage: number,       -- dmg strukturalny w epicentrum (liniowy falloff do 0 na krawędzi)
	impulse: number,      -- prędkość gruzu w epicentrum (stud/s)
	minImpulseT: number?, -- floor falloffu impulsu (krawędź ma drgnąć, nie stać)
	glassRadius: number?, -- osobny (większy) promień tłuczenia szyb; 0/nil = tylko główny
}

export type BlastStats = {
	structural: number,     -- konstrukcja (nie drobnica) w zasięgu
	cut: number,            -- partów z dziurą
	remnants: number,       -- NOWYCH partów-resztek (po scaleniu; przycięty oryginał się nie liczy)
	launchedServer: number, -- brył wyrzuconych w całości jako gruz serwera
	damaged: number,        -- konstrukcji rannej (HP attribute, przetrwała)
	glass: number,          -- stłuczonych szyb
	smallParts: number,     -- partów drobnicy przekazanych klientom (łącznie z meblami)
	handoff: number,        -- instancji (mebli i pojedynczych partów) przekazanych klientom
	felled: number,         -- spadło z utraty podparcia (łącznie)
	felledServer: number,   -- z tego zostało gruzem serwera (duże płyty)
	pushed: number,         -- już-nieanchorowanych obiektów pchniętych falą
	cpuMs: number,          -- czysty czas CPU (BEZ czekania na klatki — stary `ms` je wliczał)
	frames: number,         -- ile klatek wybuch czekał (budżet CPU + broadphase)
}

-- Attribute na partach mapy: pozostałe HP strukturalne (brak = pełne HP kategorii).
local HP_ATTR = "DestrHP"
-- Attribute: oryginalny kolor sprzed przyciemnienia (feedback obrażeń).
local ORIG_COLOR_ATTR = "DestrOrigColor"
-- Attribute na gruzie: UserId sprawcy (crush kill credit w DebrisService).
local ATTACKER_ATTR = "BlastAttackerId"

-- HRP → stopy. ⚠️ Ta sama liczba żyje w FallDamageService (HRP_TO_FEET) i LavaService
-- (FEET_OFFSET) — kandydat do Config, dopóki są trzy kopie.
local HRP_TO_FEET = 2.5

-- ============================================================================
-- Ochrona i kwalifikacja — reguły w `Shared.Modules.Destructible` (współdzielone
-- z klientem, żeby FX nie rysowało zniszczenia tam, gdzie serwer nic nie niszczy).
-- ============================================================================

type Ctx = Destructible.Context
local buildCtx = Destructible.buildContext
local isProtected = Destructible.isProtected
local isDestructible = Destructible.isDestructible
local isSmall = Destructible.isSmall

-- Kategoria KONSTRUKCJI → max HP. Kolejność: tag filara wygrywa z lokalizacją.
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

-- Próg pęknięcia DROBNICY. Mosty graczy są kruche (sabotaż PvP), reszta — próg drobnicy.
local function smallBreakHP(part: BasePart, ctx: Ctx): number
	if ctx.activeBridges and part:IsDescendantOf(ctx.activeBridges) then
		return CAT.Bridge.HP
	end
	return CAT.Small.HP
end

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Odległość do POWIERZCHNI parta, nie środka. Dla non-Block (kule, wedge) przybliżenie
-- bounding boxem — wystarczające.
local function surfaceDistance(part: BasePart, point: Vector3): number
	local lp = part.CFrame:PointToObjectSpace(point)
	return Fracture.boxSurfaceDistance(Vector3.zero, part.Size, lp)
end

local function pushPart(part: BasePart, center: Vector3, radius: number, impulse: number, minT: number)
	local d = surfaceDistance(part, center)
	local linear, angular = Shockwave.velocity(part.Position, part.Size, center, d, radius, impulse, minT, rng)
	part.AssemblyLinearVelocity = linear
	part.AssemblyAngularVelocity = angular
end

-- ============================================================================
-- Budżet CPU per klatka (v3) — kilka bomb w jednej klatce nie zamraża serwera
-- ============================================================================

local frameIndex = 0
local spentFrame = -1
local spentMs = 0

local function charge(ms: number)
	if spentFrame ~= frameIndex then
		spentFrame = frameIndex
		spentMs = 0
	end
	spentMs += ms
end

local function budgetLeft(): boolean
	return spentFrame ~= frameIndex or spentMs < CFG.FrameBudgetMs
end

-- Czeka, aż w bieżącej klatce zostanie budżet. Zwraca liczbę przeczekanych klatek.
local function awaitBudget(): number
	local waited = 0
	while not budgetLeft() and waited < CFG.MaxBudgetWaitFrames do
		task.wait()
		waited += 1
	end
	return waited
end

-- ============================================================================
-- Feedback obrażeń: ranna konstrukcja ciemnieje (bez tego mechanika HP jest niewidzialna
-- i filar "na 2 bomby" wygląda jak bug "bomba nie działa"). Pył przy trafieniu robi
-- klient — serwerowy emiter per part był jednym z głównych kosztów (patrz nagłówek).
-- ============================================================================

local function applyDamageFeedback(part: BasePart, hpLeft: number, maxHp: number)
	local orig = part:GetAttribute(ORIG_COLOR_ATTR)
	if typeof(orig) ~= "Color3" then
		orig = part.Color
		part:SetAttribute(ORIG_COLOR_ATTR, orig)
	end
	local frac = 1 - math.clamp(hpLeft / maxHp, 0, 1)
	part.Color = (orig :: Color3):Lerp(Color3.fromRGB(35, 32, 30), frac * FEED.DarkenMax)
end

-- ============================================================================
-- Przekazanie drobnicy klientom (v3) — Remotes.DebrisFall
-- ============================================================================

-- Party przekazane klientom, które serwer skasuje za chwilę. Następny wybuch w tej samej
-- okolicy (4 bomby naraz) ich nie tyka, nie liczy jako podpór ani osłony. Słabe klucze —
-- skasowany part sam wypada.
local pendingParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

type Handoff = {
	launch: { Instance },  -- odrzucane od wybuchu
	drop: { Instance },    -- padające
	seen: { [Instance]: boolean },
	parts: number,         -- ile BasePartów łącznie (statystyka)
}

local function newHandoff(): Handoff
	return { launch = {}, drop = {}, seen = {}, parts = 0 }
end

-- Dopisuje mebel/part do przekazania. `force` = konstrukcja, która i tak znika ze świata
-- (wyrzucona bryła, płyta bez podparcia) — nie może przepaść na suficie payloadu, bo
-- zostałaby w świecie mimo decyzji, że jej nie ma. Drobnica ponad sufitem po prostu
-- ZOSTAJE na miejscu (lepsze niż zniknąć bez animacji).
local function handOff(h: Handoff, inst: Instance, launch: boolean, force: boolean?): boolean
	if h.seen[inst] then return true end
	if not force and #h.launch + #h.drop >= SMALL.MaxHandoffPerBlast then
		return false
	end
	h.seen[inst] = true
	if inst:IsA("BasePart") then
		pendingParts[inst :: BasePart] = true
		h.parts += 1
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				pendingParts[d] = true
				h.parts += 1
			end
		end
	end
	table.insert(if launch then h.launch else h.drop, inst)
	return true
end

-- Ogłoszenie + skasowanie po HandoffDelay. Kolejność jest kontraktem: klient MUSI dostać
-- listę, zanim do niego dojedzie usunięcie — inaczej nie ma już czego skopiować, a mebel
-- zwyczajnie znika (dokładnie zgłoszony objaw). Remote idzie przed kasowaniem w tym samym
-- strumieniu, a opóźnienie pokrywa odroczone wywołanie handlera po stronie klienta.
local function sendHandoff(h: Handoff, center: Vector3, radius: number, impulse: number)
	local nLaunch, nDrop = #h.launch, #h.drop
	if nLaunch + nDrop == 0 then return end

	Remotes.DebrisFall:FireAllClients({
		center = center,
		radius = radius,
		impulse = impulse,
		nLaunch = nLaunch,
		launch = h.launch,
		nDrop = nDrop,
		drop = h.drop,
	})

	local all = table.clone(h.launch)
	table.move(h.drop, 1, nDrop, nLaunch + 1, all)
	task.delay(SMALL.HandoffDelay, function()
		for _, inst in ipairs(all) do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end)
end

-- Drobnica, którą wolno dopisać do przekazania jako „przyczepioną” do czegoś, co znika.
-- Zwraca JEDNOSTKĘ, która odpada razem z tym partem (sam part, mebel albo rekwizyt), albo nil,
-- gdy part jest konstrukcją i sam nie odpada. Jedno miejsce dla wszystkich „przyczepionych”:
-- drobnica i meble (v3), rekwizyty w całości (dekoracje, 24.09), listwy/szyby budynku v4.
local function looseUnit(n: BasePart, ctx: Ctx): Instance?
	if n:IsA("Terrain") or not n.Anchored or pendingParts[n] then return nil end
	if isProtected(n, ctx) or not isDestructible(n, ctx) then return nil end
	if DebrisService.isRegistered(n) or isCharacterPart(n) or CollapseService.isRubble(n) then return nil end
	local prop = Destructible.propOf(n, ctx)
	if prop then return prop end
	local _, _, v4Kind = StructuralService.ownerOf(n)
	if v4Kind == "structure" then return nil end
	if isSmall(n) or v4Kind == "attached" then
		return Destructible.assemblyOf(n, ctx)
	end
	return nil
end

local function pointInChunks(point: Vector3, chunks: { Fracture.Chunk }, margin: number): boolean
	for _, c in ipairs(chunks) do
		local d = point - c.offset
		local h = c.size * 0.5
		if math.abs(d.X) <= h.X + margin and math.abs(d.Y) <= h.Y + margin and math.abs(d.Z) <= h.Z + margin then
			return true
		end
	end
	return false
end

-- Drobnica dotykająca parta, który znika W CAŁOŚCI (wyrzucona bryła, płyta bez podparcia)
-- — bez tego obrazki, listwy i rzeczy stojące na płycie wisiałyby w powietrzu.
local function collectAttachedTo(part: BasePart, h: Handoff, ctx: Ctx)
	local pad = Vector3.one * (SMALL.AttachPadding * 2)
	for _, n in ipairs(Workspace:GetPartBoundsInBox(part.CFrame, part.Size + pad)) do
		if n ~= part then
			local unit = looseUnit(n, ctx)
			if unit then
				handOff(h, unit, false)
			end
		end
	end
end

-- ============================================================================
-- Szyby (etap 2): giną od samej fali w dużym promieniu, przez ściany (bez occlusion —
-- design: "szyby sypią się na sąsiednich blokach"). Zero gruzu serwerowego.
-- ============================================================================

type GlassPane = { cf: CFrame, size: Vector3, color: Color3 }
type GlassEntry = { pane: GlassPane, distance: number, part: BasePart }

local function collectGlass(center: Vector3, glassRadius: number, ctx: Ctx): ({ GlassEntry }, { [BasePart]: boolean })
	local entries: { GlassEntry } = {}
	local set: { [BasePart]: boolean } = {}
	if glassRadius <= 0 then
		return entries, set
	end
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(center, glassRadius)) do
		if part.Material ~= Enum.Material.Glass then continue end
		if part:IsA("Terrain") or isCharacterPart(part) then continue end
		if isProtected(part, ctx) or not isDestructible(part, ctx) then continue end
		if DebrisService.isRegistered(part) or pendingParts[part] then continue end
		set[part] = true
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
	return entries, set
end

-- ============================================================================
-- Dziury: przycinanie zamiast kasowania (fix „przenikanie przez podłogę”)
-- ============================================================================

type Cut = {
	part: BasePart,
	cf: CFrame,          -- CFrame parta PRZED przycięciem
	size: Vector3,
	localCenter: Vector3,
	seed: number,
	hole: number,        -- promień dziury z modelu obrażeń
	color: Color3,       -- wygląd do payloadu (kawałki dziury u klientów)
	plan: Fracture.HolePlan,
}

-- Nowa resztka. Kolor ORYGINALNY sprzed przyciemnienia i świeże HP: resztka jest mniejsza
-- od parta, "ranna" resztka z ułamkiem HP sypałaby się od kichnięcia (a ciemna ze
-- świeżym HP kłamałaby o swoim stanie). Filar-resztka przestaje być filarem (tag nie
-- przechodzi) — pocięty filar to gruz ścian. Textures (tapety) przechodzą, Decale nie —
-- obrazek powieliłby się na każdej resztce.
local function spawnRemnant(source: BasePart, cf: CFrame, size: Vector3): BasePart
	local part = Instance.new("Part")
	-- Nazwa oryginału — resztka to dalej "ściana": kolejna bomba potnie ją dalej,
	-- a restore (MapService / BridgeService cleanup) sprzątnie z końcem rundy.
	part.Name = source.Name
	part.Size = size
	part.CFrame = cf
	Utils.copyAppearance(source, part)
	local orig = source:GetAttribute(ORIG_COLOR_ATTR)
	if typeof(orig) == "Color3" then
		part.Color = orig
	end
	part.Anchored = true
	part.CanCollide = source.CanCollide
	part.CanQuery = source.CanQuery
	part.CanTouch = source.CanTouch
	part.CollisionGroup = source.CollisionGroup
	for _, child in ipairs(source:GetChildren()) do
		if child:IsA("Texture") then
			child:Clone().Parent = part
		end
	end
	part.Parent = source.Parent
	return part
end

-- Stopy graczy w local space parta — do wyboru resztki, która zostaje ORYGINAŁEM.
local function feetIn(cf: CFrame, feetWorld: { Vector3 }): { Vector3 }
	local out = table.create(#feetWorld)
	for i, f in ipairs(feetWorld) do
		out[i] = cf:PointToObjectSpace(f)
	end
	return out
end

-- Która resztka dostaje ORYGINALNĄ instancję parta: ta, na której stoi najwięcej graczy,
-- a przy remisie największa. Tolerancja pionowa jest hojna, bo pozycja postaci na serwerze
-- jest spóźniona względem klienta (network ownership).
local function pickReuse(rem: { Fracture.Chunk }, feetLocal: { Vector3 }): number
	local best, bestScore, bestVolume = 1, -1, -1
	for i, box in ipairs(rem) do
		local h = box.size * 0.5
		local score = 0
		for _, lf in ipairs(feetLocal) do
			local d = lf - box.offset
			if math.abs(d.X) <= h.X + 1 and math.abs(d.Y) <= h.Y + 3 and math.abs(d.Z) <= h.Z + 1 then
				score += 1
			end
		end
		local volume = box.size.X * box.size.Y * box.size.Z
		if score > bestScore or (score == bestScore and volume > bestVolume) then
			best, bestScore, bestVolume = i, score, volume
		end
	end
	return best
end

-- Świeży stan dla oryginału, który od teraz jest resztką (patrz spawnRemnant).
local function makeFresh(part: BasePart)
	local orig = part:GetAttribute(ORIG_COLOR_ATTR)
	if typeof(orig) == "Color3" then
		part.Color = orig
	end
	part:SetAttribute(ORIG_COLOR_ATTR, nil)
	part:SetAttribute(HP_ATTR, nil)
	if CollectionService:HasTag(part, CFG.PillarTag) then
		CollectionService:RemoveTag(part, CFG.PillarTag)
	end
end

-- 🔴 FIX „PRZENIKANIE PRZEZ PODŁOGĘ” (zgłoszenie 2026-09-23: „wybuch obok → dziura
-- w podłodze, ale jednocześnie przez nią przenikam, choć w tym miejscu dziury nie ma”).
-- Podłogi na tej mapie to wielkie pojedyncze party (zmierzone: 57×57×0.5, 7200 std²),
-- a wybuch tnie CAŁY part, któremu przekroczy HP — także ten, na którym gracz stoi
-- czterdzieści studów dalej. v2 kasował oryginał i stawiał resztki jako NOWE party. Pod
-- obciążeniem (4 bomby, telefon) usunięcie oryginału docierało do klienta wcześniej niż
-- nowe resztki → pod stopami chwilowo nic → postać zaczynała spadać, a resztka pojawiała
-- się już nad nią.
-- Teraz ORYGINAŁ ZOSTAJE: przycinamy go (Size + CFrame) do resztki, na której stoją gracze,
-- a pozostałe resztki powstają jako nowe party PRZED przycięciem. Dla gracza na przyciętej
-- resztce part pod stopami nigdy nie przestaje istnieć.
-- Zwraca liczbę NOWYCH partów.
local function applyCut(
	cut: Cut,
	feetWorld: { Vector3 },
	remnantsOut: { BasePart },
	originOf: { [BasePart]: BasePart },
	stale: { [BasePart]: boolean }
): number
	local part = cut.part
	-- Part mógł w trakcie planu przestać być konstrukcją (odkotwiczony, zarejestrowany jako
	-- gruz) — wtedy nie tniemy go drugi raz.
	if not part.Parent or not part.Anchored or DebrisService.isRegistered(part) then
		return 0
	end
	local rem = cut.plan.remnants
	if #rem == 0 then
		part:Destroy() -- cały part wypadł w dziurze
		return 0
	end

	local reuse = pickReuse(rem, feetIn(cut.cf, feetWorld))
	local created = 0
	for i, box in ipairs(rem) do
		if i ~= reuse then
			local r = spawnRemnant(part, cut.cf * CFrame.new(box.offset), box.size)
			table.insert(remnantsOut, r)
			originOf[r] = part
			created += 1
		end
	end

	local keep = rem[reuse]
	part.Size = keep.size
	part.CFrame = cut.cf * CFrame.new(keep.offset)
	makeFresh(part)
	-- Graf podparcia sprzed wybuchu zna ten part w STAREJ geometrii — jego stare
	-- sąsiedztwo jest nieważne, liczymy je od nowa jak dla resztki.
	stale[part] = true
	table.insert(remnantsOut, part)
	originOf[part] = part
	return created
end

-- Bryła wyrzucona w całości jako gruz serwera (duża kula/walec/klin/union).
local function launchServer(part: BasePart, center: Vector3, radius: number, impulse: number, minT: number, attackerId: number)
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
	pushPart(part, center, radius, impulse, minT)
end

-- ============================================================================
-- PODPARCIE v3: „spada tylko to, co podparcie STRACIŁO”
-- ============================================================================
-- Graf KONSTRUKCJI w pionowej kolumnie wokół epicentrum (kolumna, nie kula — po
-- wysadzeniu podstawy wieży spaść mają też piętra wysoko nad wybuchem). Krawędź n → p
-- znaczy „n podpiera p”: dotykają się i n NIE jest całkowicie nad p (wiszenie na niebie
-- nie istnieje; kontakt boczny podpiera). Wszystko poza kolumną, chronione i spoza grafu
-- (lobby, mosty) to podpora zewnętrzna. Drobnica w grafie nie istnieje w ogóle.
--
-- Liczony DWA razy: przed wybuchem (s0) i po (s1). Spada s0 \ s1. Wersja v2 zrzucała
-- wszystko, co było „niepodparte” według tej reguły — a zmierzone ~3500 partów mapy jest
-- takie z designu (cienkie listwy, rzeczy wiszące), więc każda bomba w pobliżu robiła
-- z nich gruz serwera.

type Graph = {
	nodes: { BasePart },
	isNode: { [BasePart]: boolean },
	nbrs: { [BasePart]: { BasePart } },
	s0: { [BasePart]: boolean },
}

local function isGraphNode(p: BasePart, ctx: Ctx): boolean
	if p:IsA("Terrain") or not p.Anchored then return false end
	if not (ctx.map and p:IsDescendantOf(ctx.map)) then return false end
	if isProtected(p, ctx) or DebrisService.isRegistered(p) or pendingParts[p] then return false end
	-- Budynki v4 mają własny solver; ich party (i gruz ich kolapsu) nie są węzłami v3 —
	-- dla v3 to podpora zewnętrzna.
	if StructuralService.ownerOf(p) or CollapseService.isRubble(p) then return false end
	-- Rekwizyty nie są konstrukcją (odpadają w całości przez looseUnit).
	if Destructible.propOf(p, ctx) then return false end
	return not isSmall(p)
end

-- Sąsiedzi warci zapamiętania: konstrukcja albo coś chronionego (to podpiera zawsze).
-- Postacie i gruz w locie odpadają tu (nieanchorowane), uśpiony gruz — przy liczeniu.
local function queryNeighbors(p: BasePart, ctx: Ctx): { BasePart }
	local pad = Vector3.one * (SUP.Padding * 2)
	local list: { BasePart } = {}
	for _, n in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + pad)) do
		if n == p or n:IsA("Terrain") or not n.Anchored then continue end
		-- Drobnica i rekwizyty (meble) nie podpierają konstrukcji — szafka to nie filar.
		if (isSmall(n) or Destructible.propOf(n, ctx) ~= nil) and not isProtected(n, ctx) then continue end
		table.insert(list, n)
	end
	return list
end

type NeighborSource = (BasePart) -> ({ BasePart }, { BasePart }?, boolean)

-- BFS od podpór zewnętrznych po krawędziach „podpiera”. `lists(p)` zwraca (lista główna,
-- lista dodatkowa, czy lista główna jest STARA — wtedy pomijamy w niej party przycięte
-- od tamtej pory, bo ich stary kontakt mógł zniknąć).
local function computeSupported(
	nodeList: { BasePart },
	isNode: { [BasePart]: boolean },
	lists: NeighborSource,
	stale: { [BasePart]: boolean }
): { [BasePart]: boolean }
	local halfY: { [BasePart]: number } = {}
	local function hy(p: BasePart): number
		local v = halfY[p]
		if not v then
			v = Utils.worldHalfY(p)
			halfY[p] = v
		end
		return v
	end

	local supported: { [BasePart]: boolean } = {}
	local queue: { BasePart } = {}
	local out: { [BasePart]: { BasePart } } = {}

	local function consider(p: BasePart, n: BasePart)
		if not n.Parent or not n.Anchored or pendingParts[n] then return end
		-- Tolerancja „całkowicie powyżej” najwyżej POŁOWA grubości p — przy stałych 0.5
		-- part cieńszy niż 0.5 nie miał podparcia z boku (sąsiad obok liczył się jako „nad”).
		local ph = hy(p)
		local eps = math.min(SUP.AboveEpsilon, ph)
		if n.Position.Y - hy(n) >= p.Position.Y + ph - eps then return end
		if isNode[n] then
			local o = out[n]
			if not o then
				o = {}
				out[n] = o
			end
			table.insert(o, p)
		elseif not DebrisService.isRegistered(n) then
			if not supported[p] then
				supported[p] = true
				table.insert(queue, p)
			end
		end
	end

	for _, p in ipairs(nodeList) do
		local main, extra, isOld = lists(p)
		for _, n in ipairs(main) do
			if n ~= p and not (isOld and stale[n]) then
				consider(p, n)
			end
		end
		if extra then
			for _, n in ipairs(extra) do
				consider(p, n)
			end
		end
	end

	local i = 1
	while i <= #queue do
		local p = queue[i]
		i += 1
		local o = out[p]
		if o then
			for _, q in ipairs(o) do
				if not supported[q] then
					supported[q] = true
					table.insert(queue, q)
				end
			end
		end
	end
	return supported
end

local NO_STALE: { [BasePart]: boolean } = {}

local function buildGraph(center: Vector3, radius: number, ctx: Ctx): Graph
	local graph: Graph = { nodes = {}, isNode = {}, nbrs = {}, s0 = {} }
	local column = Vector3.new(
		radius * SUP.ColumnRadiusFactor * 2,
		SUP.ColumnHeight,
		radius * SUP.ColumnRadiusFactor * 2
	)
	for _, p in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(center), column)) do
		if not graph.isNode[p] and isGraphNode(p, ctx) then
			graph.isNode[p] = true
			table.insert(graph.nodes, p)
		end
	end
	for _, p in ipairs(graph.nodes) do
		graph.nbrs[p] = queryNeighbors(p, ctx)
	end
	graph.s0 = computeSupported(graph.nodes, graph.isNode, function(p: BasePart)
		return graph.nbrs[p], nil, true
	end, NO_STALE)
	return graph
end

-- Stan „po”: stare węzły bez zniszczonych i przyciętych + wszystkie resztki (ze świeżym
-- sąsiedztwem, dopisanym też po stronie starych sąsiadów). Zwraca party, które spadają.
local function settleGraph(
	graph: Graph,
	remnants: { BasePart },
	originOf: { [BasePart]: BasePart },
	stale: { [BasePart]: boolean },
	ctx: Ctx
): { BasePart }
	local nodes: { BasePart } = {}
	local isNode: { [BasePart]: boolean } = {}
	for _, p in ipairs(graph.nodes) do
		if p.Parent and p.Anchored and not stale[p] and not pendingParts[p] and not DebrisService.isRegistered(p) then
			table.insert(nodes, p)
			isNode[p] = true
		end
	end
	for _, r in ipairs(remnants) do
		if r.Parent and not isNode[r] then
			table.insert(nodes, r)
			isNode[r] = true
		end
	end

	local fresh: { [BasePart]: { BasePart } } = {}
	local extra: { [BasePart]: { BasePart } } = {}
	for _, r in ipairs(remnants) do
		if not r.Parent then continue end
		local list = queryNeighbors(r, ctx)
		fresh[r] = list
		for _, n in ipairs(list) do
			-- Stary węzeł nie zna nowej resztki — dopisujemy ją po jego stronie. (Resztka
			-- sąsiadująca z resztką zna ją z własnego, świeżego zapytania.)
			if graph.isNode[n] and not stale[n] then
				local e = extra[n]
				if not e then
					e = {}
					extra[n] = e
				end
				table.insert(e, r)
			end
		end
	end

	local s1 = computeSupported(nodes, isNode, function(p: BasePart)
		local f = fresh[p]
		if f then
			return f, nil, false
		end
		return graph.nbrs[p] or {}, extra[p], true
	end, stale)

	local fell: { BasePart } = {}
	for _, p in ipairs(nodes) do
		local origin = originOf[p] or p
		if graph.s0[origin] and not s1[p] then
			table.insert(fell, p)
		end
	end
	return fell
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
		-- Szkło, mocno przezroczyste i DROBNICA nie osłaniają. Drobnica od v3: wieszak
		-- albo listwa to nie ściana — a do tego za chwilę znika (przekazana klientom).
		if
			inst.Material ~= Enum.Material.Glass
			and inst.Transparency < 0.5
			and inst.CanCollide
			and not pendingParts[inst]
			and not isSmall(inst)
		then
			hits += 1
		end
		origin = result.Position + delta.Unit * 0.1
	end
	return OCC.PerWallFactor ^ hits
end

-- ============================================================================
-- Diagnostyka kontraktu mapy
-- ============================================================================

-- Każdy part zgłaszany RAZ na sesję serwera (słabe klucze). v2 drukował te same ścieżki
-- przy każdym wybuchu — i zgłaszał WŁASNY pocisk bomby (poprawione w BombService).
local reported: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function reportContract(unanchoredInMap: { BasePart }, outsideMap: { BasePart })
	if not CFG.Debug then return end
	local function sample(list: { BasePart }): string
		local names = {}
		for i = 1, math.min(3, #list) do
			table.insert(names, list[i]:GetFullName())
		end
		return table.concat(names, ", ")
	end
	if #outsideMap > 0 then
		warn(("[Destr] %d partów w zasięgu wybuchu jest POZA Workspace.Map — wybuch ich nie tnie (kontrakt: geometria budynków pod Map). Każdy part zgłaszam raz. Przykłady: %s"):format(
			#outsideMap, sample(outsideMap)))
	end
	if #unanchoredInMap > 0 then
		warn(("[Destr] %d partów W Workspace.Map ma Anchored=false — dla wybuchu to gruz, nie konstrukcja (dostaje tylko impuls, zero cięcia). Każdy part zgłaszam raz. Przykłady: %s"):format(
			#unanchoredInMap, sample(unanchoredInMap)))
	end
end

-- ============================================================================
-- Detonacja
-- ============================================================================

type Hit = { part: BasePart, distance: number, dmg: number, unit: Instance? }
type Damaged = { part: BasePart, hpLeft: number, maxHp: number }

local function newStats(): BlastStats
	return {
		structural = 0, cut = 0, remnants = 0, launchedServer = 0, damaged = 0, glass = 0,
		smallParts = 0, handoff = 0, felled = 0, felledServer = 0, pushed = 0,
		cpuMs = 0, frames = 0,
	}
end

local function logBlast(radius: number, damage: number, stats: BlastStats)
	if not CFG.Debug then return end
	print(("[Destr] r=%d dmg=%d | konstrukcja=%d dziur=%d (nowych resztek %d) wyrzut=%d rannych=%d szkło=%d | drobnica→klienci %d partów w %d mebl./partach | spadło=%d (serwer %d) pchnięte=%d | gruz serwera=%d/%d | cpu=%.1fms klatek=%d"):format(
		radius, damage,
		stats.structural, stats.cut, stats.remnants, stats.launchedServer, stats.damaged, stats.glass,
		stats.smallParts, stats.handoff,
		stats.felled, stats.felledServer, stats.pushed,
		DebrisService.getTotalCount(), DBR.MaxTotalDebris,
		stats.cpuMs, stats.frames))
end

-- Etap 5 w osobnym wątku: podparcie „po” wymaga klatki przerwy (świeże resztki muszą
-- wejść do broadphase, inaczej GetPartBoundsInBox ich nie widzi), a obrażenia graczy
-- (BombService, zaraz po powrocie z detonate) nie mają na co czekać.
local function settleLater(
	graph: Graph,
	remnants: { BasePart },
	originOf: { [BasePart]: BasePart },
	stale: { [BasePart]: boolean },
	ctx: Ctx,
	center: Vector3,
	radius: number,
	damage: number,
	impulse: number,
	serverLeft: number,
	attackerId: number,
	stats: BlastStats
)
	task.wait()
	stats.frames += 1 + awaitBudget()
	local t0 = os.clock()

	local fell = settleGraph(graph, remnants, originOf, stale, ctx)
	-- Największe pierwsze: gruzem serwera (platforma, crush) zostają płyty, które coś znaczą.
	table.sort(fell, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	local count = math.min(#fell, SUP.MaxFelledPerBlast)
	local granted = 0
	if count > 0 and serverLeft > 0 then
		granted = DebrisService.reserve(math.min(count, serverLeft))
	end

	local h = newHandoff()
	local toServer: { BasePart } = {}
	for i = 1, count do
		local p = fell[i]
		if i <= granted then
			table.insert(toServer, p)
		else
			handOff(h, p, false, true)
		end
		collectAttachedTo(p, h, ctx)
	end
	sendHandoff(h, center, radius, impulse)

	for _, p in ipairs(toServer) do
		if not p.Parent then continue end
		-- Joints przed odkotwiczeniem — zweldowany sąsiad zostałby pociągnięty za płytą.
		for _, joint in ipairs(p:GetJoints()) do
			if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
				joint:Destroy()
			end
		end
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
	end

	stats.felled = count
	stats.felledServer = #toServer
	stats.smallParts += h.parts - (count - #toServer)
	stats.handoff += #h.launch + #h.drop
	local ms = (os.clock() - t0) * 1000
	charge(ms)
	stats.cpuMs += ms
	logBlast(radius, damage, stats)
end

function DestructionService.detonate(center: Vector3, params: DestructionParams?, attacker: Player?): BlastStats?
	if not params then return nil end
	local radius = params.radius or 0
	if radius <= 0 then return nil end
	local damage = params.damage or 0
	local impulse = params.impulse or 0
	local minT = params.minImpulseT or 0.1
	local glassRadius = params.glassRadius or 0
	local attackerId = if attacker then attacker.UserId else 0

	local stats = newStats()
	stats.frames += awaitBudget()
	local t0 = os.clock()
	local ctx = buildCtx()

	-- ===== 1. PLAN (świat jeszcze nietknięty) ==================================
	local glassEntries, glassSet = collectGlass(center, glassRadius, ctx)

	local push: { BasePart } = {}
	local structList: { Hit } = {}
	local smallHits: { Hit } = {}
	local v4Hits: { Hit } = {}
	local rubbleHits: { BasePart } = {}
	local unanchoredInMap: { BasePart } = {}
	local outsideMap: { BasePart } = {}

	for _, part in ipairs(Workspace:GetPartBoundsInRadius(center, radius)) do
		-- Terrain to też BasePart — Anchored=false na nim rzuca error.
		if part:IsA("Terrain") then continue end
		-- Gracze: damage/knockback robi BombService. Łapie też Accessory (rodzic = Character).
		if isCharacterPart(part) then continue end
		-- Chronione są pomijane ŚWIADOMIE (kontrakt) — nie raportujemy ich jako problem.
		if isProtected(part, ctx) then continue end
		if glassSet[part] or pendingParts[part] then continue end

		if DebrisService.isRegistered(part) then
			-- Nasz gruz (nawet uśpiony-zakotwiczony) — budzimy i pchamy, NIE tniemy dalej.
			table.insert(push, part)
			continue
		end
		if CollapseService.isRubble(part) then
			-- Leżąca bryła kolapsu v4 — wybuch ją budzi i pcha (CollapseService), nie tnie.
			table.insert(rubbleHits, part)
			continue
		end
		if not part.Anchored then
			-- Luźne (inne bomby w locie itp.) — sama fala. Nieanchorowany part to dla
			-- systemu gruz, nie konstrukcja. Zgłaszamy tylko, gdy leży w mapie (tam to
			-- błąd kontraktu); bomby i luźne zabawki poza mapą są w porządku.
			table.insert(push, part)
			-- Spadająca grupa kolapsu v4 leży w mapie odkotwiczona z założenia — to nie błąd kontraktu.
			if ctx.map and part:IsDescendantOf(ctx.map) and not reported[part] and not CollapseService.isFlying(part) then
				reported[part] = true
				table.insert(unanchoredInMap, part)
			end
			continue
		end
		if not isDestructible(part, ctx) then
			if not reported[part] then
				reported[part] = true
				table.insert(outsideMap, part)
			end
			continue
		end

		local distance = surfaceDistance(part, center)
		local dmg = damage * (1 - math.clamp(distance / radius, 0, 1))
		if dmg <= 0 then continue end

		local _, _, v4Kind = StructuralService.ownerOf(part)
		if v4Kind == "structure" then
			table.insert(v4Hits, { part = part, distance = distance, dmg = dmg })
			continue
		end
		-- Rekwizyt (dekoracje): nigdy nie cięty jak ściana — pada cały, z tym samym progiem co
		-- drobnica. Sprawdzany PRZED drobnicą: drobna część szafki też ma nieść całą szafkę.
		local prop = Destructible.propOf(part, ctx)
		if prop then
			if dmg >= smallBreakHP(part, ctx) then
				table.insert(smallHits, { part = part, distance = distance, dmg = dmg, unit = prop })
			end
			continue
		end
		-- Listwy i ozdoby budynku v4 (Trim/Other) łamią się jak drobnica.
		if isSmall(part) or v4Kind == "attached" then
			if dmg >= smallBreakHP(part, ctx) then
				table.insert(smallHits, { part = part, distance = distance, dmg = dmg })
			end
		else
			table.insert(structList, { part = part, distance = distance, dmg = dmg })
		end
	end
	reportContract(unanchoredInMap, outsideMap)

	-- ---- Konstrukcja: HP → ranna / dziura / wyrzut w całości ------------------
	-- Najbliższe pierwsze — ewentualne sufity mają ucinać DALEKIE skutki, nie losowe.
	table.sort(structList, function(a, b)
		return a.distance < b.distance
	end)
	stats.structural = #structList

	local cuts: { Cut } = {}
	local damaged: { Damaged } = {}
	local launchWhole: { BasePart } = {}
	for _, hit in ipairs(structList) do
		local part = hit.part
		if not part.Parent then continue end
		-- Mógł przestać być konstrukcją W TRAKCIE tej pętli: kolaps sekcji (wywołany kilka
		-- iteracji wcześniej przez padnięty filar) odkotwicza całe piętro i oddaje je
		-- DebrisService. Taki part to już gruz — dostanie tylko impuls.
		if DebrisService.isRegistered(part) then
			table.insert(push, part)
			continue
		end

		local maxHp = categoryHP(part, ctx)
		local hpAttr = part:GetAttribute(HP_ATTR)
		local hp = if typeof(hpAttr) == "number" then hpAttr :: number else maxHp
		if hit.dmg < hp then
			-- RANNY: przeżył, ale następna bomba dobije. Ciemnieje (czytelny stan).
			table.insert(damaged, { part = part, hpLeft = hp - hit.dmg, maxHp = maxHp })
			continue
		end

		-- Promień DZIURY z modelu obrażeń: materiał znika tam, gdzie bomba zadaje więcej
		-- niż zostało HP. `hp` to stan RESZTKOWY, więc dobity filar robi dziurę tak dużą
		-- jak ściana z tym samym resztkowym HP — spójne bez dodatkowych gałek.
		local holeRadius = math.clamp(radius * (1 - hp / math.max(damage, 0.001)), FRAC.MinHoleRadius, radius)

		if part:IsA("Part") and part.Shape == Enum.PartType.Block then
			local seed = rng:NextInteger(1, 2_000_000_000)
			local localCenter = part.CFrame:PointToObjectSpace(center)
			local plan = Fracture.planHole(part.Size, localCenter, holeRadius, seed, FRAC)
			if #plan.hole == 0 then
				-- HP przekroczone, ale żaden kawałek nie wypadł w dziurze (epicentrum tuż
				-- przy rogu wielkiej płyty). Zostaje „ledwo się trzyma” — dobije następna.
				table.insert(damaged, { part = part, hpLeft = 1, maxHp = maxHp })
			else
				table.insert(cuts, {
					part = part,
					cf = part.CFrame,
					size = part.Size,
					localCenter = localCenter,
					seed = seed,
					hole = holeRadius,
					color = part.Color,
					plan = plan,
				})
			end
		else
			table.insert(launchWhole, part)
		end
	end

	-- ===== 2. PODPARCIE „PRZED” ==================================================
	-- Tylko gdy z konstrukcji coś realnie znika. Wybuch, który zbił szyby i przewrócił
	-- wieszaki, nie ma czego zawalić — i nie płaci za graf.
	-- ⚠️ KOLEJNOŚĆ: graf „przed” MUSI powstać, zanim cokolwiek z tego wybuchu zostanie
	-- oznaczone do przekazania klientom (handOff → pendingParts). Oznaczony part graf
	-- pomija — więc bryła wyrzucona u klientów nie liczyłaby się jako podpora nawet
	-- w stanie „przed”, a płyta, którą tylko ona trzymała, nie spadłaby nigdy.
	local graph: Graph? = nil
	if SUP.Enabled and (#cuts > 0 or #launchWhole > 0) then
		graph = buildGraph(center, radius, ctx)
	end

	-- Stopy graczy raz na wybuch (wybór resztki, która zostaje oryginałem — v3 i v4).
	local feetWorld: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = Utils.getRoot(player)
		if root then
			table.insert(feetWorld, root.Position - Vector3.new(0, HRP_TO_FEET, 0))
		end
	end

	-- ===== 2b. BUDYNKI v4 — dziury-prostokąty i stan konstrukcji =================
	-- Po grafie v3 (ten i tak pomija party v4), PRZED ogłoszeniem: BlastFX niesie też plany
	-- dziur v4. Co spada, policzy CollapseService w następnej klatce (jeden flush na paczkę
	-- wybuchów). Obrażenia strukturalne idą zawsze, gdy wybuch sięga budynku v4 — także
	-- wtedy, gdy nic nie przeciął (osłabianie sumuje się: decyzja Kacpra 24.09).
	local v4Cuts: { any } = {}
	if #v4Hits > 0 or StructuralService.anyNear(center, radius) then
		local SD = Config.Structure.Damage
		local cause = StructuralService.newCause(attacker, center)
		local holeRadius = math.clamp(radius * (1 - SD.HoleThreshold / math.max(damage, 0.001)), SD.MinHoleRadius, radius)
		table.sort(v4Hits, function(a, b)
			return a.distance < b.distance
		end)
		for _, hit in ipairs(v4Hits) do
			if hit.dmg >= SD.HoleThreshold and hit.part.Parent then
				local payload = StructuralService.cutHole(hit.part, center, holeRadius, cause, feetWorld)
				if payload then
					table.insert(v4Cuts, payload)
				end
			end
		end
		StructuralService.structuralDamage(center, radius, damage, cause)
	end

	-- ---- Wyrzut w całości: duże → gruz serwera (budżet), reszta → u klientów -----
	local handoff = newHandoff()
	local serverLeft = DBR.MaxServerPiecesPerBlast
	local launchServerList: { BasePart } = {}
	local bigLaunch: { BasePart } = {}
	for _, part in ipairs(launchWhole) do
		local s = part.Size
		if s.X * s.Y * s.Z >= DBR.PlatformMinVolume then
			table.insert(bigLaunch, part)
		else
			handOff(handoff, part, true, true)
		end
	end
	if #bigLaunch > 0 then
		local granted = DebrisService.reserve(math.min(#bigLaunch, serverLeft))
		serverLeft -= granted
		for i, part in ipairs(bigLaunch) do
			if i <= granted then
				table.insert(launchServerList, part)
			else
				handOff(handoff, part, true, true)
			end
		end
	end

	-- ---- Drobnica: pada CAŁY mebel; najbliższa część decyduje odrzut vs upadek ----
	table.sort(smallHits, function(a, b)
		return a.distance < b.distance
	end)
	for _, hit in ipairs(smallHits) do
		if pendingParts[hit.part] then continue end -- już w drodze razem ze swoim meblem
		local unit = hit.unit or Destructible.assemblyOf(hit.part, ctx)
		if not handOff(handoff, unit, hit.dmg >= SMALL.LaunchDamage) then
			break -- sufit payloadu: reszta drobnicy zostaje na miejscu
		end
	end

	-- ---- Drobnica leżąca na tym, co znika --------------------------------------
	-- Dziura: tylko to, co wisi/stoi NAD dziurą (rzut środka na part wypada w kawałku
	-- dziury). Obrazek na ocalałej części ściany zostaje.
	local attachPad = Vector3.one * (SMALL.AttachPadding * 2)
	for _, cut in ipairs(cuts) do
		local h = cut.size * 0.5
		for _, n in ipairs(Workspace:GetPartBoundsInBox(cut.cf, cut.size + attachPad)) do
			local unit = looseUnit(n, ctx)
			if not unit then continue end
			local lp = cut.cf:PointToObjectSpace(n.Position)
			local onPart = Vector3.new(
				math.clamp(lp.X, -h.X, h.X),
				math.clamp(lp.Y, -h.Y, h.Y),
				math.clamp(lp.Z, -h.Z, h.Z)
			)
			if pointInChunks(onPart, cut.plan.hole, SMALL.AttachPadding) then
				handOff(handoff, unit, false)
			end
		end
	end
	for _, part in ipairs(launchWhole) do
		collectAttachedTo(part, handoff, ctx)
	end
	-- To samo dla dziur v4: drobnica wisząca/stojąca nad prostokątem dziury.
	for _, cut in ipairs(v4Cuts) do
		local h = cut.size * 0.5
		local holeArea = { { offset = cut.win.offset, size = cut.win.size } }
		for _, n in ipairs(Workspace:GetPartBoundsInBox(cut.cf, cut.size + attachPad)) do
			local unit = looseUnit(n, ctx)
			if not unit then continue end
			local lp = cut.cf:PointToObjectSpace(n.Position)
			local onPart = Vector3.new(
				math.clamp(lp.X, -h.X, h.X),
				math.clamp(lp.Y, -h.Y, h.Y),
				math.clamp(lp.Z, -h.Z, h.Z)
			)
			if pointInChunks(onPart, holeArea, SMALL.AttachPadding) then
				handOff(handoff, unit, false)
			end
		end
	end

	-- ===== 3. OGŁOSZENIE =========================================================
	-- Klienci mają widzieć błysk w tej samej klatce co skutki fizyczne. Seed pozwala
	-- każdemu klientowi wygenerować IDENTYCZNE kosmetyczne odłamki lokalnie.
	local glassPanes: { GlassPane } = {}
	for i, entry in ipairs(glassEntries) do
		if i > CFG.FX.GlassMaxPanes then break end
		table.insert(glassPanes, entry.pane)
	end
	local cutPayload = table.create(#cuts)
	for i, cut in ipairs(cuts) do
		local p = cut.part
		cutPayload[i] = {
			cf = cut.cf,
			size = cut.size,
			lc = cut.localCenter,
			seed = cut.seed,
			hole = cut.hole,
			color = cut.color,
			mat = p.Material,
			var = p.MaterialVariant,
			tr = p.Transparency,
		}
	end
	-- Dziury v4: payload gotowy z StructuralService (z `win` — prostokąt, który klient
	-- rozbija na kawałki; poszarpany obrys v3 by do niego nie pasował).
	for _, v4 in ipairs(v4Cuts) do
		table.insert(cutPayload, v4)
	end
	Remotes.BlastFX:FireAllClients({
		center = center,
		radius = radius,
		impulse = impulse,
		minT = minT,
		seed = rng:NextInteger(1, 2_000_000_000),
		glass = glassPanes,
		cuts = cutPayload,
	})
	sendHandoff(handoff, center, radius, impulse)

	-- ===== 4. ZASTOSOWANIE =======================================================
	for _, entry in ipairs(glassEntries) do
		if entry.part.Parent then
			entry.part:Destroy()
		end
	end

	local remnants: { BasePart } = {}
	local originOf: { [BasePart]: BasePart } = {}
	local stale: { [BasePart]: boolean } = {}
	local newRemnants = 0
	for _, cut in ipairs(cuts) do
		newRemnants += applyCut(cut, feetWorld, remnants, originOf, stale)
	end

	for _, part in ipairs(launchServerList) do
		if part.Parent and part.Anchored and not DebrisService.isRegistered(part) then
			launchServer(part, center, radius, impulse, minT, attackerId)
		end
	end

	for _, d in ipairs(damaged) do
		if d.part.Parent then
			d.part:SetAttribute(HP_ATTR, d.hpLeft)
			applyDamageFeedback(d.part, d.hpLeft, d.maxHp)
		end
	end

	-- Fala na już-nieanchorowanych. Assembly ma JEDNĄ prędkość — dedup po
	-- AssemblyRootPart, żeby drugi zapis nie nadpisywał pierwszego w tej samej bryle.
	local handledAssemblies: { [BasePart]: boolean } = {}
	for _, part in ipairs(push) do
		if not part.Parent then continue end
		DebrisService.wake(part) -- no-op dla nie-gruzu
		local root = part.AssemblyRootPart or part
		if handledAssemblies[root] then continue end
		handledAssemblies[root] = true
		pushPart(part, center, radius, impulse, minT)
		stats.pushed += 1
	end
	-- Leżące bryły kolapsu v4 — budzi je CollapseService (budżet; jedna bryła = jeden impuls,
	-- kolejne jej kawałki z tej listy są już w locie i zwracają false).
	for _, part in ipairs(rubbleHits) do
		if part.Parent then
			CollapseService.wakeRubble(part, center, radius, impulse, minT)
		end
	end

	stats.cut = #cuts
	stats.remnants = newRemnants
	stats.launchedServer = #launchServerList
	stats.damaged = #damaged
	stats.glass = #glassEntries
	stats.smallParts = handoff.parts
	stats.handoff = #handoff.launch + #handoff.drop
	local ms = (os.clock() - t0) * 1000
	charge(ms)
	stats.cpuMs += ms

	-- ===== 5. PODPARCIE „PO” — osobny wątek, klatkę później =======================
	if graph then
		task.spawn(settleLater, graph, remnants, originOf, stale, ctx, center, radius, damage, impulse, serverLeft, attackerId, stats)
	else
		logBlast(radius, damage, stats)
	end

	return stats
end

-- ============================================================================
-- API dla CollapseService (v4). Wstrzykiwane w init.server — CollapseService nie może
-- wołać tego serwisu wprost, bo ten woła jego (cykl require).
-- ============================================================================

-- Instancje do animacji u klientów (kruszone fragmenty, grupy ponad budżetem fizyki).
function DestructionService.handOffToClients(list: { Instance }, center: Vector3, launch: boolean)
	local h = newHandoff()
	for _, inst in ipairs(list) do
		handOff(h, inst, launch, true)
	end
	local col = Config.Structure.Collapse
	sendHandoff(h, center, col.HandoffRadius, if launch then col.HandoffImpulse else 0)
end

-- Drobnica i meble leżące na kawałkach, które właśnie spadają — do klientów, inaczej
-- zostałyby w powietrzu. Kawałki są już odkotwiczone, więc same się nie kwalifikują.
function DestructionService.dropResting(pieces: { BasePart }, center: Vector3)
	local ctx = buildCtx()
	local h = newHandoff()
	for _, p in ipairs(pieces) do
		if p.Parent then
			collectAttachedTo(p, h, ctx)
		end
	end
	sendHandoff(h, center, Config.Structure.Collapse.HandoffRadius, 0)
end

function DestructionService.init()
	-- Licznik klatek dla budżetu CPU (awaitBudget). Heartbeat = jedna klatka serwera.
	RunService.Heartbeat:Connect(function()
		frameIndex += 1
	end)
	-- Folder gruzu zakładany wcześnie, żeby klienci mieli go zreplikowanego, zanim
	-- poleci pierwszy kawałek.
	DebrisService.getFolder()
end

return DestructionService
