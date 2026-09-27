--!strict
-- DebrisFXController.luau
-- LOKALNY GRUZ — wszystko, co po wybuchu leci, pada i leży, a NIE jest stanem gry.
-- Druga połowa „hybrydowego gruzu” z DESTRUCTION_PLAN.md: serwer trzyma dziury, resztki
-- ścian i duże płyty; każdy klient dorysowuje resztę u siebie:
--   * odłamki z otoczenia (seed wybuchu)                           — Remotes.BlastFX
--   * odłamki szyb (payload `glass`)                               — Remotes.BlastFX
--   * KAWAŁKI DZIUR (v3, payload `cuts` → Fracture.planHole)       — Remotes.BlastFX
--   * PRZEJĘTE MEBLE I DROBNICA (v3, kopie partów, które serwer
--     za chwilę skasuje)                                           — Remotes.DebrisFall
-- Zero replikacji, zero fizyki serwera. ILE tego gracz widzi i jak długo leży, decyduje
-- jego tryb grafiki (QualityController → Config.Graphics.Profiles): telefon nie płaci
-- za pobojowisko, które chce widzieć mocny PC.
--
-- 🔴 ZASADA NR 1 — LOKALNY GRUZ NIE ISTNIEJE DLA NICZEGO, CO WPŁYWA NA GRĘ (2026-09-23,
-- pytanie Kacpra: „co jak jeden gracz ma Ziemniaka, drugi Pełny — widzą inne party i mogą
-- chodzić po innym gruzie?”). Każdy lokalny part ma `CanCollide = false`, `CanQuery = false`
-- i `CanTouch = false`. Leci fizyką silnika BEZ ZDERZEŃ, a odbicie od ściany, lądowanie
-- i stertę liczymy sami promieniem, który omija postacie i sam gruz. Skutek: nie da się
-- na nim stanąć, nie popycha, nie łapie kamery, celowania ani stawiania mostu — tryb
-- grafiki zmienia WYŁĄCZNIE obraz.
-- ⚠️ Pierwsza wersja v3 dawała gruzowi kolizję: w Pełnym gracz mógł stanąć na kawałku,
-- którego inni nie mieli (u nich wisiał nad podłogą). Do tego `CanQuery = false` Roblox
-- honoruje TYLKO przy `CanCollide = false` — więc gruz z kolizją był widoczny dla promieni
-- klienta, w tym dla celownika mostu (most stanąłby na gruzie, którego nikt inny nie ma).
-- ⛔ Nie wracać do kolizji lokalnego gruzu — także nie przez grupę kolizji dla postaci:
-- to zależy od zachowania silnika (czujnik podłogi Humanoida, kamera), którego nie da się
-- sprawdzić bez gry, a zasada wyżej działa z definicji.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Destructible = require(ReplicatedStorage.Shared.Modules.Destructible)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Shockwave = require(ReplicatedStorage.Shared.Modules.Shockwave)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local QualityController = require(script.Parent.QualityController)

local DebrisFXController = {}

local FX = Config.Destruction.FX
local FRAC = Config.Destruction.Fracture
local SMALL = Config.Destruction.Small
local PROPS = Config.Destruction.Props

type Profile = QualityController.Profile

local FALLBACK_COLOR = Color3.fromRGB(132, 126, 118)
local FALLBACK_MATERIAL = Enum.Material.Concrete

-- ============================================================================
-- Folder i promień, którym gruz „widzi” świat
-- ============================================================================

local folder: Folder? = nil

local function getFolder(): Folder
	local f = folder
	if f and f.Parent then return f end
	local new = Instance.new("Folder")
	new.Name = "LocalDebris"
	new.Parent = Workspace
	folder = new
	return new
end

-- Omija postacie (gruz przenika graczy) i sam gruz. Lawa ma CanQuery = false, więc promień
-- przez nią przechodzi — gruz tonie pod taflą i ląduje na tym, co pod nią.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local rayFilterAt = -math.huge

local function refreshRayFilter(now: number)
	if now - rayFilterAt < 0.5 then return end
	rayFilterAt = now
	local list: { Instance } = { getFolder() }
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			table.insert(list, char)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

-- Każdy lokalny part: zero kolizji i zero zapytań. KOLEJNOŚĆ ma znaczenie — Roblox
-- honoruje CanQuery = false tylko przy CanCollide = false.
local function makeGhostly(part: BasePart, profile: Profile)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = part.CastShadow and profile.CastShadows
end

local function randomUnit(rng: Random): Vector3
	return Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
end

-- Lokalny gruz budynku jest CIEMNOSZARY (decyzja Kacpra 25.09) — nie ma kolizji, więc kolor
-- mówi graczowi „przez to przejdziesz, na tym nie staniesz”. Lekki rozrzut jasności, żeby
-- sterta nie wyglądała jak jeden plastikowy klocek.
local function debrisColor(rng: Random): Color3
	local base = FX.LocalDebrisColor
	local k = 1 + rng:NextNumber(-FX.LocalDebrisColorJitter, FX.LocalDebrisColorJitter)
	return Color3.new(math.clamp(base.R * k, 0, 1), math.clamp(base.G * k, 0, 1), math.clamp(base.B * k, 0, 1))
end

-- Kawałek gruzu budynku (odłamek dziury albo posiekana bryła): box albo klin, lekki shrink
-- i obrót (siatka nie może czytać się jak siatka), ciemnoszary, z materiałem i wariantem
-- źródła — mapa stoi na Plastic + „Studs” (hard rule 15). Jedno miejsce dla obu dróg.
local function makeChunk(rng: Random, cf: CFrame, size: Vector3, mat: any, var: any, tr: any): BasePart
	local part: BasePart
	if rng:NextNumber() < FRAC.WedgeChance then
		-- Czasem klin zamiast boxa — poszarpane krawędzie czytają się jako "odłamany".
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
	part.Name = "LocalChunk"
	local rj = math.rad(FRAC.ChunkRotJitter)
	part.Size = size * FRAC.ChunkShrink
	part.CFrame = cf * CFrame.Angles(rng:NextNumber(-rj, rj), rng:NextNumber(-rj, rj), rng:NextNumber(-rj, rj))
	part.Color = debrisColor(rng)
	if typeof(mat) == "EnumItem" then
		pcall(function()
			part.Material = mat
		end)
	end
	-- Wariant PO materiale — ustawienie materiału czyści wariant.
	if typeof(var) == "string" then
		part.MaterialVariant = var
	end
	if typeof(tr) == "number" then
		part.Transparency = tr
	end
	Utils.smoothSurfaces(part)
	return part
end

-- ============================================================================
-- Pula lokalnego gruzu: sufit, czas życia, gaśnięcie, lot, przewracanie mebli
-- ============================================================================

type Body = {
	root: Instance,       -- BasePart (lecący/leżący kawałek) albo Model (przewracany mebel)
	parts: { BasePart },
	base: { number },     -- Transparency każdego parta na starcie — gaśnięcie liczy się od niej
	state: string,        -- "fly" | "topple" | "rest" | "gone"
	expireAt: number,
	fadeUntil: number,
	-- lot (BasePart)
	lastPos: Vector3,
	flyUntil: number,
	bounces: number,
	-- przewracanie (Model)
	pivot: Vector3,
	axis: Vector3,
	startCF: CFrame,
	drop: number,
	t0: number,
	angle: number,
	toppleTime: number,
	shatter: boolean,
}

local bodies: { Body } = {}
local liveParts = 0
local rrCursor = 0
-- Części rozsypanych mebli dopisywane PO pętli puli (dopisywanie w trakcie przesuwałoby indeksy).
local deferred: { Body } = {}
local stepping = false

-- Sterta: najwyższy punkt leżącego gruzu w komórce siatki XZ. Kawałek spadający na komórkę
-- kładzie się NA stercie, a nie przenika przez nią na podłogę — bez tego pobojowisko w trybie
-- Pełnym byłoby płaskim dywanem. Sama liczba, zero zapytań do silnika.
local heights: { [number]: number } = {}

local function cellKey(x: number, z: number): number
	local cx = math.floor(x / FX.LandCellSize) + 65536
	local cz = math.floor(z / FX.LandCellSize) + 65536
	return cx * 131072 + cz
end

local function newBody(root: Instance, parts: { BasePart }, state: string, lifetime: number, expireAt: number?): Body
	local base = table.create(#parts)
	for i, p in ipairs(parts) do
		base[i] = p.Transparency
	end
	local now = os.clock()
	return {
		root = root,
		parts = parts,
		base = base,
		state = state,
		-- Rozrzucony czas życia: gruz gaśnie falami, nie wszystko w jednej klatce.
		expireAt = expireAt or (now + lifetime * (0.8 + 0.4 * math.random())),
		fadeUntil = 0,
		lastPos = if root:IsA("BasePart") then root.Position else Vector3.zero,
		flyUntil = now + FX.MaxFlightTime,
		bounces = 0,
		pivot = Vector3.zero,
		axis = Vector3.xAxis,
		startCF = CFrame.identity,
		drop = 0,
		t0 = now,
		angle = 0,
		toppleTime = FX.ToppleTime,
		shatter = false,
	}
end

local function destroyBody(b: Body)
	if b.state == "gone" then return end
	b.state = "gone"
	liveParts -= #b.parts
	if b.root.Parent then
		b.root:Destroy()
	end
end

local function enforceCap(profile: Profile)
	-- Najstarsze znikają od razu: sufit to sufit, a świeży wybuch jest ważniejszy
	-- od gruzu sprzed kilkunastu sekund.
	while liveParts > profile.MaxLocalParts and #bodies > 1 do
		destroyBody(table.remove(bodies, 1) :: Body)
	end
end

local function addBody(b: Body, profile: Profile)
	if stepping then
		table.insert(deferred, b)
		return
	end
	table.insert(bodies, b)
	liveParts += #b.parts
	enforceCap(profile)
end

-- Kawałek, który leci: bez kolizji, z prędkością — lądowanie liczy checkFlight.
local function launchPiece(part: BasePart, linear: Vector3, angular: Vector3, lifetime: number, profile: Profile)
	makeGhostly(part, profile)
	part.Anchored = false
	part.Parent = getFolder()
	part.AssemblyLinearVelocity = linear
	part.AssemblyAngularVelocity = angular
	addBody(newBody(part, { part }, "fly", lifetime), profile)
end

-- ---- Lądowanie -------------------------------------------------------------

-- Kładzie kawałek na powierzchni, tuż nad punktem (bez tego zamarłby w losowym obrocie,
-- do połowy w podłodze). NA KTÓREJ ścianie leży — losowo, z wagą (pole ściany)^RestFaceExponent,
-- i z losowym obrotem wokół normalnej (27.09, Kacper: „zawsze stoją góra do góry, takie
-- spiczaste, na całej mapie”). Wcześniej wygrywała oś najbliższa normalnej (najmniejszy
-- obrót), a odłamki ze ścian lecą zwykle pionowo — lądowały na sztorc, wszystkie tak samo.
local restRng = Random.new()

local function restAxis(sizes: { number }): number
	local e = FX.RestFaceExponent
	local w = {
		(sizes[2] * sizes[3]) ^ e, -- leży na ścianie prostopadłej do X
		(sizes[1] * sizes[3]) ^ e,
		(sizes[1] * sizes[2]) ^ e,
	}
	local roll = restRng:NextNumber() * (w[1] + w[2] + w[3])
	if roll < w[1] then return 1 end
	if roll < w[1] + w[2] then return 2 end
	return 3
end

local function land(b: Body, p: BasePart, point: Vector3, normal: Vector3)
	local sizes = { p.Size.X, p.Size.Y, p.Size.Z }
	local k = restAxis(sizes)
	-- Kierunki osi parta w świecie: oś k wzdłuż normalnej (strona losowa), następna w losowym
	-- kierunku w płaszczyźnie podłoża, trzecia z iloczynu (układ prawoskrętny: e_k × e_j = e_l).
	local j = k % 3 + 1
	local l = j % 3 + 1
	local ref = if math.abs(normal.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local a = normal:Cross(ref).Unit
	local c = normal:Cross(a)
	local theta = restRng:NextNumber(0, math.pi * 2)
	local dirs: { Vector3 } = { Vector3.zero, Vector3.zero, Vector3.zero }
	dirs[k] = if restRng:NextNumber() < 0.5 then normal else -normal
	dirs[j] = a * math.cos(theta) + c * math.sin(theta)
	dirs[l] = dirs[k]:Cross(dirs[j])
	local rotation = CFrame.fromMatrix(Vector3.zero, dirs[1], dirs[2], dirs[3])
	local half = sizes[k] * 0.5
	p.Anchored = true
	p.CFrame = CFrame.new(point + normal * (half + 0.01)) * rotation
	b.state = "rest"

	if normal.Y >= FX.FloorNormalY then
		local key = cellKey(point.X, point.Z)
		local top = point.Y + half * 2
		local current = heights[key]
		if not current or current < top then
			heights[key] = top
		end
	end
end

-- Dotknięcie podłoża: szybki kawałek odbija się raz (grzechot), wolny kładzie się płasko.
local function touchFloor(b: Body, p: BasePart, point: Vector3, normal: Vector3, velocity: Vector3)
	local into = -velocity:Dot(normal)
	if b.bounces < FX.MaxBounces and into > FX.BounceMinSpeed then
		b.bounces += 1
		local vn = velocity:Dot(normal) * normal
		local vt = velocity - vn
		p.CFrame = (p.CFrame - p.CFrame.Position) + point + normal * (Utils.worldHalfY(p) + 0.05)
		p.AssemblyLinearVelocity = vt * FX.BounceFriction - vn * FX.Restitution
		p.AssemblyAngularVelocity = p.AssemblyAngularVelocity * 0.5
		return
	end
	land(b, p, point, normal)
end

-- Ściana albo sufit: odbicie z tłumieniem, kawałek wraca przed powierzchnię.
local function bounceWall(p: BasePart, point: Vector3, normal: Vector3, velocity: Vector3)
	local vn = velocity:Dot(normal) * normal
	local vt = velocity - vn
	local s = p.Size
	local r = math.min(s.X, s.Y, s.Z) * 0.5
	p.CFrame = (p.CFrame - p.CFrame.Position) + point + normal * (r + 0.05)
	p.AssemblyLinearVelocity = vt * FX.BounceFriction - vn * FX.WallRestitution
end

-- Jeden kawałek w locie: promień po drodze od ostatniego sprawdzenia (nic nie przeleci
-- przez ścianę, nawet gdy budżet sprawdza go co kilka klatek) + sonda podłoża pod spodem.
-- Zwraca liczbę wystrzelonych promieni (budżet klatki).
local function checkFlight(b: Body, now: number): number
	local p = b.root :: BasePart
	if now >= b.flyUntil then
		-- Wisi w próżni albo utonął w lawie bez dna — zostaje, gdzie jest, i zgaśnie.
		p.Anchored = true
		b.state = "rest"
		return 0
	end
	local rays = 0
	local velocity = p.AssemblyLinearVelocity
	local current = p.Position
	local delta = current - b.lastPos
	if delta.Magnitude > 0.02 then
		rays += 1
		local hit = Workspace:Raycast(b.lastPos, delta, rayParams)
		-- Ruchoma bryła (spadająca grupa kolapsu v4) to nie podłoże: kawałek, który „wylądował”
		-- na niej, zostawał w powietrzu, gdy bryła poleciała dalej (test 24.09).
		if hit and not hit.Instance.Anchored then
			hit = nil
		end
		if hit then
			if hit.Normal.Y >= FX.FloorNormalY then
				touchFloor(b, p, hit.Position, hit.Normal, velocity)
			else
				bounceWall(p, hit.Position, hit.Normal, velocity)
			end
			b.lastPos = p.Position
			return rays
		end
	end

	if velocity.Y <= 1 then
		local halfY = Utils.worldHalfY(p)
		local bottom = current.Y - halfY
		local key = cellKey(current.X, current.Z)
		local pile = heights[key]
		if pile and bottom <= pile and bottom >= pile - FX.PileSnap then
			-- Spadł na stertę — kładzie się na niej, ale tylko gdy pod stertą dalej jest podłoże
			-- (strop pod nią mógł się zawalić — wtedy sterta już nie istnieje).
			rays += 1
			local under = Workspace:Raycast(current, Vector3.new(0, -(halfY + FX.RestSupportProbe), 0), rayParams)
			if under and under.Instance.Anchored then
				touchFloor(b, p, Vector3.new(current.X, pile, current.Z), Vector3.yAxis, velocity)
			else
				heights[key] = nil
			end
		else
			rays += 1
			local ground = Workspace:Raycast(current, Vector3.new(0, -(halfY + 0.2), 0), rayParams)
			if ground and ground.Instance.Anchored and ground.Normal.Y >= FX.FloorNormalY then
				touchFloor(b, p, ground.Position, ground.Normal, velocity)
			end
		end
	end
	b.lastPos = p.Position
	return rays
end

-- ---- Przewracanie mebli ------------------------------------------------------

-- Mebel rozsypuje się na części (tryb Pełny, po przewróceniu albo od razu przy odrzucie).
-- Części przejmują czas życia mebla, żeby zgasły razem z resztą.
local function shatterBody(b: Body, profile: Profile, rng: Random)
	local model = b.root
	liveParts -= #b.parts
	for _, p in ipairs(b.parts) do
		if not p.Parent then continue end
		p.Parent = getFolder()
		p.Anchored = false
		p.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 0.6), rng:NextNumber(-1, 1)) * FX.DropSpeed
		p.AssemblyAngularVelocity = randomUnit(rng) * FX.DropSpin
		addBody(newBody(p, { p }, "fly", 0, b.expireAt), profile)
	end
	b.parts = {}
	b.state = "gone"
	model:Destroy() -- pusta skorupa — części już wyniesione do folderu
end

-- Animacja (zakotwiczona — zero fizyki): najpierw spadek, jeśli mebel stał na czymś,
-- czego już nie ma, potem obrót wokół dolnej krawędzi z przyspieszeniem, jak prawdziwe
-- przewracanie się.
local function stepTopple(b: Body, now: number, profile: Profile)
	local model = b.root :: Model
	local g = Workspace.Gravity
	local t = now - b.t0
	local fallTime = if b.drop > 0 then math.sqrt(2 * b.drop / g) else 0
	local yOffset = -math.min(b.drop, 0.5 * g * t * t)
	local u = math.clamp((t - fallTime) / b.toppleTime, 0, 1)
	local angle = b.angle * u * u
	local pivot = b.pivot
	model:PivotTo(
		CFrame.new(pivot) * CFrame.fromAxisAngle(b.axis, angle) * CFrame.new(-pivot)
			* (b.startCF + Vector3.new(0, yOffset, 0))
	)
	if u >= 1 then
		if b.shatter then
			shatterBody(b, profile, Random.new())
		else
			b.state = "rest"
		end
	end
end

local function startTopple(model: Model, parts: { BasePart }, center: Vector3, launch: boolean, profile: Profile, rng: Random)
	local bbCF, bbSize = model:GetBoundingBox()
	local halfY = math.abs(bbCF.XVector.Y) * bbSize.X * 0.5
		+ math.abs(bbCF.YVector.Y) * bbSize.Y * 0.5
		+ math.abs(bbCF.ZVector.Y) * bbSize.Z * 0.5
	local bottom = bbCF.Position - Vector3.new(0, halfY, 0)
	refreshRayFilter(os.clock())
	local ground = Workspace:Raycast(bottom + Vector3.new(0, 0.5, 0), Vector3.new(0, -80, 0), rayParams)
	local groundY = if ground and ground.Instance.Anchored then ground.Position.Y else bottom.Y

	-- Kierunek: OD wybuchu (fala przewraca meble na zewnątrz), z losowym odchyleniem.
	local away = bbCF.Position - center
	local dir = Vector3.new(away.X, 0, away.Z)
	if dir.Magnitude < 0.5 then
		local a = rng:NextNumber(0, math.pi * 2)
		dir = Vector3.new(math.cos(a), 0, math.sin(a))
	else
		dir = CFrame.Angles(0, math.rad(rng:NextNumber(-FX.ToppleJitter, FX.ToppleJitter)), 0):VectorToWorldSpace(dir.Unit)
	end
	-- Odległość od środka do krawędzi, wokół której mebel się obraca.
	local extent = math.abs(bbCF.XVector:Dot(dir)) * bbSize.X * 0.5
		+ math.abs(bbCF.YVector:Dot(dir)) * bbSize.Y * 0.5
		+ math.abs(bbCF.ZVector:Dot(dir)) * bbSize.Z * 0.5

	local b = newBody(model, parts, "topple", profile.RubbleLifetime)
	b.pivot = Vector3.new(bbCF.Position.X, groundY, bbCF.Position.Z) + dir * extent
	-- Obrót o +kąt wokół (góra × kierunek) przechyla wierzch mebla W STRONĘ `dir`.
	b.axis = Vector3.yAxis:Cross(dir).Unit
	b.startCF = model:GetPivot()
	b.drop = math.max(0, bottom.Y - groundY)
	b.t0 = os.clock()
	b.angle = math.rad(FX.ToppleAngle + rng:NextNumber(-FX.ToppleJitter, FX.ToppleJitter))
	-- Odrzucony od wybuchu przewraca się gwałtowniej niż ten, który tylko stracił równowagę.
	b.toppleTime = if launch then FX.ToppleTime * 0.6 else FX.ToppleTime
	b.shatter = profile.ShatterFurniture
	addBody(b, profile)
end

-- ---- Krok puli ---------------------------------------------------------------

local function stepFlight(now: number, profile: Profile)
	local n = #bodies
	if n == 0 then return end
	refreshRayFilter(now)
	-- Budżet promieni na klatkę, sprawdzanie po kolei (round-robin). Kawałek pominięty w tej
	-- klatce nie przeleci przez ścianę — następne sprawdzenie obejmie całą drogę od ostatniego.
	local used = 0
	local examined = 0
	while examined < n and used < profile.RaysPerFrame do
		rrCursor = (rrCursor % n) + 1
		examined += 1
		local b = bodies[rrCursor]
		if b.state == "fly" and b.root.Parent then
			used += checkFlight(b, now)
		end
	end
end

-- Leżący gruz i przewrócone meble: czy dalej mają pod sobą podłoże? Strop pod nimi mógł
-- spaść (kolaps v4) — wtedy kawałek leci dalej, a mebel rozsypuje się i spada. Bez tego
-- zostawały w powietrzu i dało się przez nie przechodzić (test 24.09). Po kolei, z budżetem.
local restCursor = 0

local function stepRest(now: number, profile: Profile)
	local n = #bodies
	if n == 0 then return end
	local checks, examined = 0, 0
	while examined < n and checks < FX.RestChecksPerFrame do
		restCursor = (restCursor % n) + 1
		examined += 1
		local b = bodies[restCursor]
		if b.state ~= "rest" or b.fadeUntil > 0 or not b.root.Parent then continue end
		checks += 1
		local pos: Vector3
		local halfY: number
		local root = b.root
		if root:IsA("BasePart") then
			pos = root.Position
			halfY = Utils.worldHalfY(root)
		else
			local cf, size = (root :: Model):GetBoundingBox()
			pos = cf.Position
			halfY = math.abs(cf.XVector.Y) * size.X * 0.5 + math.abs(cf.YVector.Y) * size.Y * 0.5
				+ math.abs(cf.ZVector.Y) * size.Z * 0.5
		end
		local ground = Workspace:Raycast(pos, Vector3.new(0, -(halfY + FX.RestSupportProbe), 0), rayParams)
		if ground and ground.Instance.Anchored then continue end
		heights[cellKey(pos.X, pos.Z)] = nil
		if root:IsA("BasePart") then
			root.Anchored = false
			b.state = "fly"
			b.flyUntil = now + FX.MaxFlightTime
			b.lastPos = root.Position
			b.bounces = FX.MaxBounces -- spada, nie odbija się jak od wybuchu
		else
			shatterBody(b, profile, Random.new())
		end
	end
end

local function stepPool()
	if #bodies == 0 and #deferred == 0 then return end
	local now = os.clock()
	local profile = QualityController.profile()
	local fade = math.max(FX.FragFadeTime, 0.01)

	stepping = true
	local kept = 0
	for i = 1, #bodies do
		local b = bodies[i]
		local alive = b.state ~= "gone" and b.root.Parent ~= nil
		if alive and b.state == "topple" then
			stepTopple(b, now, profile)
			alive = b.state ~= "gone"
		end
		if alive then
			if b.fadeUntil == 0 and now >= b.expireAt then
				b.fadeUntil = now + fade
			end
			if b.fadeUntil > 0 then
				local a = 1 - math.clamp((b.fadeUntil - now) / fade, 0, 1)
				if a >= 1 then
					alive = false
				else
					for k, p in ipairs(b.parts) do
						local base = b.base[k]
						p.Transparency = base + (1 - base) * a
					end
				end
			end
		end
		if alive then
			kept += 1
			bodies[kept] = b
		else
			destroyBody(b)
		end
	end
	for i = kept + 1, #bodies do
		bodies[i] = nil
	end
	stepping = false

	for _, b in ipairs(deferred) do
		table.insert(bodies, b)
		liveParts += #b.parts
	end
	table.clear(deferred)
	enforceCap(profile)

	stepFlight(now, profile)
	stepRest(now, profile)
end

local function clearAll()
	for _, b in ipairs(bodies) do
		destroyBody(b)
	end
	table.clear(bodies)
	table.clear(deferred)
	table.clear(heights)
	liveParts = 0
end

local function cameraPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Kolejny wybuch rusza gruz, który już leży: podrzuca go (Pełny rozsypuje też meble).
-- Przy okazji nic nie zostaje zawieszone nad świeżą dziurą w podłodze — podrzucony gruz
-- spadnie przez nią, bo promień lądowania już tej podłogi nie widzi.
local function stirResting(center: Vector3, radius: number, impulse: number, minT: number, rng: Random, profile: Profile)
	for _, b in ipairs(bodies) do
		if b.state ~= "rest" or not b.root.Parent then continue end
		if b.root:IsA("BasePart") then
			local p = b.root :: BasePart
			local d = (p.Position - center).Magnitude
			if d > radius then continue end
			local linear, angular = Shockwave.velocity(p.Position, p.Size, center, d, radius, impulse, minT, rng)
			p.Anchored = false
			p.AssemblyLinearVelocity = linear
			p.AssemblyAngularVelocity = angular
			b.state = "fly"
			b.bounces = 0
			b.lastPos = p.Position
			b.flyUntil = os.clock() + FX.MaxFlightTime
		elseif profile.ShatterFurniture then
			local pos = (b.root :: Model):GetPivot().Position
			if (pos - center).Magnitude <= radius then
				stepping = true
				shatterBody(b, profile, rng)
				stepping = false
			end
		end
	end
	for _, b in ipairs(deferred) do
		table.insert(bodies, b)
		liveParts += #b.parts
	end
	table.clear(deferred)
	-- Sterta pod podrzuconym gruzem przestaje istnieć — liczymy ją od nowa, gdy opadnie.
	table.clear(heights)
end

-- ============================================================================
-- Odłamki z otoczenia (seed wybuchu) — kolory/materiały PRÓBKOWANE z geometrii wokół
-- epicentrum, żeby gruz wyglądał jak budynek, który właśnie pękł
-- ============================================================================

type Sample = { color: Color3, material: Enum.Material, variant: string }

-- Party CHRONIONE (Locked / Map.Locked / ActiveCash) są pomijane — odłamek w kolorze
-- nietykalnego Baseplate wyglądał, jakby wybuch właśnie go rozwalił. Drobnica też
-- (v3): w sklepie z ubraniami pierwsze sześć trafień to były szmatki, a odłamki ścian
-- mają wyglądać jak ściana.
local function sampleSurroundings(center: Vector3, radius: number): { Sample }
	local samples: { Sample } = {}
	local ctx = Destructible.buildContext()
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(center, math.min(radius, 30))) do
		if part.Transparency > 0.6 then continue end
		if not Destructible.canSpawnFXFrom(part, ctx) then continue end
		if Destructible.isSmall(part) then continue end
		-- Wariant materiału razem z materiałem: mapa to Plastic + MaterialVariant "Studs",
		-- a sam Plastic daje gołe odłamki obok ściany pokrytej teksturą studsów.
		table.insert(samples, { color = part.Color, material = part.Material, variant = part.MaterialVariant })
		if #samples >= 6 then break end
	end
	if #samples == 0 then
		table.insert(samples, { color = FALLBACK_COLOR, material = FALLBACK_MATERIAL, variant = "" })
	end
	return samples
end

local function spawnFrag(rng: Random, center: Vector3, radius: number, samples: { Sample }, profile: Profile)
	local sample = samples[rng:NextInteger(1, #samples)]

	local frag: BasePart
	if rng:NextNumber() < 0.35 then
		frag = Instance.new("WedgePart")
	else
		frag = Instance.new("Part")
	end
	frag.Name = "LocalFrag"

	local s = rng:NextNumber(FX.FragMinSize, FX.FragMaxSize)
	frag.Size = Vector3.new(
		s * rng:NextNumber(0.6, 1.4),
		s * rng:NextNumber(0.6, 1.4),
		s * rng:NextNumber(0.6, 1.4)
	)
	frag.Color = debrisColor(rng)
	frag.Material = sample.material
	frag.MaterialVariant = sample.variant
	-- Gładko, a nie jak chce `Instance.new`: odłamek ma 0.4-1.5 studa, więc domyślny
	-- stud bywa większy niż jego ściana i drobnica wygląda jak sypiące się klocki LEGO.
	Utils.smoothSurfaces(frag)
	frag.CastShadow = false

	-- Spawn w powłoce wokół epicentrum, z biasem w górę (gruz "wyrywa się" z podłoża).
	local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.1, 1), rng:NextNumber(-1, 1))
	if dir.Magnitude < 0.05 then dir = Vector3.yAxis end
	dir = dir.Unit
	local spawnDist = radius * rng:NextNumber(0.1, 0.45)
	frag.CFrame = CFrame.new(center + dir * spawnDist)
		* CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi))

	-- Wyrzut stożkiem na zewnątrz i w górę (kąt losowy 20-70° od poziomu).
	local horizontal = Vector3.new(dir.X, 0, dir.Z)
	if horizontal.Magnitude < 0.05 then horizontal = Vector3.xAxis end
	local angle = math.rad(rng:NextNumber(20, 70))
	local launch = horizontal.Unit * math.cos(angle) + Vector3.yAxis * math.sin(angle)

	launchPiece(
		frag,
		launch * rng:NextNumber(FX.FragMinSpeed, FX.FragMaxSpeed),
		randomUnit(rng) * 20,
		profile.FragLifetime,
		profile
	)
end

-- ============================================================================
-- Szkło (etap 2): odłamki szyb z payloadu BlastFX. Serwer tłucze party, my renderujemy
-- lokalnie cienkie, szklane drzazgi wylatujące z szyby OD wybuchu.
-- ============================================================================

local function spawnGlassShards(rng: Random, center: Vector3, panes: { any }, profile: Profile)
	-- ⚠️ BUDŻET DZIELONY PROPORCJONALNIE DO POWIERZCHNI, nie „kto pierwszy, ten lepszy".
	-- Przy zwykłym odliczaniu pierwsze tafle zjadłyby cały limit, a dalsze pękałyby BEZ
	-- ani jednego odłamka — czyli dokładnie ten objaw, który naprawiamy, tylko przesunięty
	-- na sąsiedni budynek. Tak wielka szyba dostaje najwięcej kawałków (bo jest większością
	-- powierzchni), a każda mała i tak ma zagwarantowane `ShardsPerPaneMin`.
	local totalArea = 0
	for _, pane in ipairs(panes) do
		if typeof(pane) == "table" and typeof(pane.size) == "Vector3" then
			local s3 = { pane.size.X, pane.size.Y, pane.size.Z }
			table.sort(s3)
			totalArea += s3[2] * s3[3]
		end
	end
	if totalArea <= 0 then return end

	local perPaneMin = math.max(1, math.round(FX.ShardsPerPaneMin * profile.GlassShardScale))
	local perPaneMax = math.max(perPaneMin, math.round(FX.ShardsPerPaneMax * profile.GlassShardScale))

	for _, pane in ipairs(panes) do
		if typeof(pane) ~= "table" then continue end
		local cf = pane.cf
		local size = pane.size
		local color = pane.color
		if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then continue end
		if typeof(color) ~= "Color3" then color = Color3.fromRGB(180, 220, 235) end

		-- Osie szyby: najcieńsza = normalna, dwie pozostałe rozpinają taflę.
		local axes = {
			{ len = size.X, vec = cf.RightVector },
			{ len = size.Y, vec = cf.UpVector },
			{ len = size.Z, vec = cf.LookVector },
		}
		table.sort(axes, function(a, b)
			return a.len < b.len
		end)
		local normal = axes[1].vec
		-- Odłamki lecą OD wybuchu (strona tafli przeciwna do epicentrum).
		if normal:Dot(cf.Position - center) < 0 then
			normal = -normal
		end

		local area = axes[2].len * axes[3].len
		local count = math.clamp(
			math.round(area / FX.ShardAreaPerShard * profile.GlassShardScale),
			perPaneMin,
			perPaneMax
		)
		-- Udział tej tafli w budżecie całego wybuchu, proporcjonalnie do jej powierzchni.
		local share = math.round(profile.GlassShardsPerBlastMax * area / totalArea)
		count = math.clamp(math.min(count, share), perPaneMin, perPaneMax)

		-- ⚠️ ROZMIAR ODŁAMKA ROŚNIE Z TAFLĄ. Bez tego wielka szyba dostaje tę samą drobnicę
		-- co mała i „znika" zamiast się rozpaść. „Komórka" mówi, ile powierzchni przypada
		-- na jeden kawałek; odnosimy ją do typowej szyby. (Mniej odłamków w Ziemniaku =
		-- większa komórka = większe kawałki — szyba dalej widocznie się rozpada.)
		local cell = math.sqrt(area / math.max(count, 1))
		local scale = math.clamp(cell / FX.ShardCellRef, 1, FX.ShardScaleMax)

		for _ = 1, count do
			-- `WedgePart`, nie `Part`: klin zbiega się do krawędzi, czyli ma ostry koniec.
			local shard = Instance.new("WedgePart")
			shard.Name = "LocalGlassShard"
			-- X = grubość tafli, Y = szerokość u podstawy, Z = DŁUGOŚĆ drzazgi.
			shard.Size = Vector3.new(
				FX.ShardThickness,
				rng:NextNumber(FX.ShardWidthMin, FX.ShardWidthMax) * scale,
				rng:NextNumber(FX.ShardLengthMin, FX.ShardLengthMax) * scale
			)
			local h2 = axes[2].len * 0.5
			local h3 = axes[3].len * 0.5
			shard.CFrame = CFrame.new(
				cf.Position
					+ axes[2].vec * rng:NextNumber(-h2, h2)
					+ axes[3].vec * rng:NextNumber(-h3, h3)
			) * CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi))
			shard.Color = color
			shard.Material = Enum.Material.Glass
			Utils.smoothSurfaces(shard)
			shard.Transparency = 0.4
			shard.Reflectance = 0.2
			shard.CastShadow = false
			-- Duży kawał szkła ma OPADAĆ, nie odlatywać jak iskra — inaczej wielka tafla
			-- znowu „znika", tylko szybciej.
			local slow = math.sqrt(scale)
			launchPiece(
				shard,
				normal * (rng:NextNumber(6, 16) / slow)
					+ Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1, 4), rng:NextNumber(-3, 3)) / slow,
				randomUnit(rng) * (25 / scale),
				FX.ShardLifetime,
				profile
			)
		end
	end
end

-- ============================================================================
-- Kawałki dziur (v3) — ten sam plan co na serwerze, z tego samego seeda
-- ============================================================================

type ChunkJob = { cut: any, chunk: Fracture.Chunk, volume: number }

-- Ile kawałków z bryły o tym rozmiarze (27.09 — `FX.DebrisPieceVolume` / `DebrisMaxPieces`):
-- proporcjonalnie do objętości, z sufitem. Mały part to 1-3 kawałki, duży — większe kawałki.
local function pieceCap(size: Vector3): number
	return math.clamp(math.ceil(size.X * size.Y * size.Z / FX.DebrisPieceVolume), 1, FX.DebrisMaxPieces)
end

local function spawnCutChunks(
	rng: Random,
	cuts: { any },
	center: Vector3,
	radius: number,
	impulse: number,
	minT: number,
	camPos: Vector3?,
	profile: Profile
)
	local jobs: { ChunkJob } = {}
	for _, cut in ipairs(cuts) do
		if typeof(cut) ~= "table" then continue end
		if typeof(cut.cf) ~= "CFrame" or typeof(cut.size) ~= "Vector3" or typeof(cut.lc) ~= "Vector3" then continue end
		if typeof(cut.seed) ~= "number" or typeof(cut.hole) ~= "number" then continue end
		if camPos and (cut.cf.Position - camPos).Magnitude > profile.FXDistance + cut.size.Magnitude * 0.5 then
			continue
		end
		-- v4: dziura to prostokąt `win` (tyle zabrała kolizja serwera) — kawałki wypełniają
		-- dokładnie ten prostokąt. Poszarpany obrys v3 by do niego nie pasował: w rogach
		-- prostokąta materiał znikałby bez żadnego kawałka.
		local holeChunks: { Fracture.Chunk }
		local win = cut.win
		if typeof(win) == "table" and typeof(win.offset) == "Vector3" and typeof(win.size) == "Vector3" then
			holeChunks = {}
			local slices = Fracture.slice(win.size, FRAC.TargetChunkSize, FRAC.MinChunkSize, pieceCap(win.size), Random.new(cut.seed))
			for _, c in ipairs(slices) do
				table.insert(holeChunks, { offset = win.offset + c.offset, size = c.size })
			end
		else
			holeChunks = Fracture.planHole(cut.size, cut.lc, cut.hole, cut.seed, FRAC).hole
		end
		for _, chunk in ipairs(holeChunks) do
			local s = chunk.size
			table.insert(jobs, { cut = cut, chunk = chunk, volume = s.X * s.Y * s.Z })
		end
	end
	if #jobs == 0 then return end

	-- Sufit trybu: zostają NAJWIĘKSZE kawałki — to je widać z daleka i to one mówią
	-- „tu była ściana”. Dziura w świecie jest i tak pełna (robi ją serwer).
	if #jobs > profile.CutChunksPerBlast then
		table.sort(jobs, function(a, b)
			return a.volume > b.volume
		end)
	end

	for i = 1, math.min(#jobs, profile.CutChunksPerBlast) do
		local job = jobs[i]
		local cut = job.cut
		local part = makeChunk(rng, cut.cf * CFrame.new(job.chunk.offset), job.chunk.size, cut.mat, cut.var, cut.tr)

		local d = Fracture.boxSurfaceDistance(Vector3.zero, part.Size, part.CFrame:PointToObjectSpace(center))
		local linear, angular = Shockwave.velocity(part.Position, part.Size, center, d, radius, impulse, minT, rng)
		launchPiece(part, linear, angular, profile.RubbleLifetime, profile)
	end
end

-- ============================================================================
-- Przejęcie mebli i drobnicy od serwera (v3, Remotes.DebrisFall)
-- ============================================================================

-- Już obsłużone (słabe klucze) — drugi wybuch w tym samym miejscu nie robi drugiej kopii.
local handled: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Oryginał znika u nas OD RAZU (serwer skasuje go za HandoffDelay). Tylko lokalnie:
-- LocalTransparencyModifier i lokalne CanCollide/CanQuery nie wracają na serwer.
local function hideLocally(inst: Instance)
	local function hide(d: Instance)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			d.CanCollide = false -- najpierw: CanQuery=false działa tylko przy CanCollide=false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Decal") then -- Texture dziedziczy po Decal
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles")
		then
			(d :: any).Enabled = false
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			(d :: any).Enabled = false
		end
	end
	hide(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		hide(d)
	end
end

local function countParts(inst: Instance): number
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function instancePosition(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- Kopia mebla/parta, która pada (albo leci) u nas. Kopia PRZED schowaniem oryginału —
-- sklonowałaby się niewidzialna. Zwraca, ile partów postawiła (budżet trybu grafiki).
--   * mebel (Model): przewraca się od wybuchu; w Pełnym potem rozsypuje się na części,
--     a odrzucony (blisko bomby) rozsypuje się od razu, części lecą od wybuchu
--   * duży pojedynczy part budynku: SIEKANY na kawałki wielkości odłamków dziury
--     (FX.HandoffSliceAbove) — bez kolizji jeden wielki kloc to „ściana, przez którą się
--     przechodzi” (zgłoszenie Kacpra 25.09: zaklinowane stropy 22×33, szyny drabiny 66)
--   * mały pojedynczy part: leci (odrzut) albo pada z lekkim, losowym ruchem
local function spawnFall(
	inst: Instance,
	launch: boolean,
	center: Vector3,
	radius: number,
	impulse: number,
	rng: Random,
	profile: Profile,
	budgetLeft: number
): number
	if inst:IsA("BasePart") and not Destructible.isSmall(inst :: BasePart) and budgetLeft >= 2 then
		local src = inst :: BasePart
		local size = src.Size
		if math.max(size.X, size.Y, size.Z) > FX.HandoffSliceAbove then
			local cf = src.CFrame
			local slices = Fracture.slice(size, FRAC.TargetChunkSize, FRAC.MinChunkSize, math.min(pieceCap(size), budgetLeft), rng)
			for _, c in ipairs(slices) do
				local chunk = makeChunk(rng, cf * CFrame.new(c.offset), c.size, src.Material, src.MaterialVariant, src.Transparency)
				local linear: Vector3, angular: Vector3
				if launch then
					local d = Fracture.boxSurfaceDistance(Vector3.zero, chunk.Size, chunk.CFrame:PointToObjectSpace(center))
					linear, angular = Shockwave.velocity(chunk.Position, chunk.Size, center, d, radius, impulse, 0.15, rng)
				else
					-- Rozpad w miejscu: kawałki rozchodzą się lekko, a opadają same (grawitacja).
					linear = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 0.5), rng:NextNumber(-1, 1)) * FX.DropSpeed
					angular = randomUnit(rng) * FX.DropSpin
				end
				launchPiece(chunk, linear, angular, profile.RubbleLifetime, profile)
			end
			return #slices
		end
	end

	local ok, copy = pcall(function()
		return inst:Clone()
	end)
	if not ok or copy == nil then return 0 end
	local root = copy :: Instance

	local parts: { BasePart } = {}
	local function prep(d: Instance)
		if d:IsA("BasePart") then
			d.Anchored = true -- do czasu, aż zdecydujemy: przewracanie (zakotwiczone) albo lot
			makeGhostly(d, profile)
			table.insert(parts, d)
		elseif d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy() -- lokalna kopia dekoracji nie ma prawa niczego uruchamiać
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") then
			d:Destroy() -- części mają być niezależne (rozsypanie mebla)
		end
	end
	prep(root)
	for _, d in ipairs(root:GetDescendants()) do
		prep(d)
	end
	if #parts == 0 then
		root:Destroy()
		return 0
	end
	root.Parent = getFolder()

	-- Mebel/drobnica dostaje tylko ułamek impulsu bomby — mebel to nie pocisk.
	local isLight = not inst:IsA("BasePart") or Destructible.isSmall(inst :: BasePart)
	local speed = if isLight then impulse * SMALL.LaunchSpeedFactor else impulse

	if root:IsA("Model") then
		if launch and profile.ShatterFurniture then
			for _, p in ipairs(parts) do
				local d = Fracture.boxSurfaceDistance(Vector3.zero, p.Size, p.CFrame:PointToObjectSpace(center))
				local linear = Shockwave.velocity(p.Position, p.Size, center, d, radius, speed, 0.15, rng)
				launchPiece(p, linear, randomUnit(rng) * FX.LaunchSpin, profile.RubbleLifetime, profile)
			end
			root:Destroy() -- pusta skorupa
		else
			startTopple(root :: Model, parts, center, launch, profile, rng)
		end
		return #parts
	end

	local p = root :: BasePart
	if launch then
		local d = Fracture.boxSurfaceDistance(Vector3.zero, p.Size, p.CFrame:PointToObjectSpace(center))
		local linear = Shockwave.velocity(p.Position, p.Size, center, d, radius, speed, 0.15, rng)
		launchPiece(p, linear, randomUnit(rng) * FX.LaunchSpin, profile.RubbleLifetime, profile)
	else
		launchPiece(
			p,
			Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 0.5), rng:NextNumber(-1, 1)) * FX.DropSpeed,
			randomUnit(rng) * FX.DropSpin,
			profile.RubbleLifetime,
			profile
		)
	end
	return 1
end

-- Rekwizyt, który zniknął (wieszak, roślina — decyzja Kacpra 26.09): sam obłok pyłu w jego
-- pudełku, zero kopii i kawałków. Serwer skasował oryginał od razu, więc nie ma czego chować.
local VAPOR_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local function spawnVapor(cf: CFrame, size: Vector3, profile: Profile)
	local anchor = Instance.new("Part")
	anchor.Name = "PropVapor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = size:Max(Vector3.one * 0.5)
	anchor.CFrame = cf
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = VAPOR_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(190, 182, 170), Color3.fromRGB(130, 124, 116))
	local scale = math.clamp(math.max(size.X, size.Y, size.Z) * 0.45, 1.5, 6)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, scale * 0.4),
		NumberSequenceKeypoint.new(1, scale),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.8, 1.6)
	dust.Rate = 0
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Speed = NumberRange.new(2, 7)
	dust.Acceleration = Vector3.new(0, -3, 0)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Parent = anchor
	anchor.Parent = getFolder()
	dust:Emit(math.max(1, math.round(PROPS.VaporDust * profile.ParticleScale)))
	task.delay(2, function()
		anchor:Destroy()
	end)
end

-- Mebel rozpadający się od razu (26.09): części lecą od wybuchu i znikają po `ShatterLife`
-- w obu trybach grafiki (decyzja Kacpra: „party, co szybko znikają”).
local function spawnShatter(inst: Instance, center: Vector3, radius: number, impulse: number, rng: Random, profile: Profile): number
	local ok, copy = pcall(function()
		return inst:Clone()
	end)
	if not ok or copy == nil then return 0 end
	local root = copy :: Instance
	local parts: { BasePart } = {}
	local function prep(d: Instance)
		if d:IsA("BasePart") then
			d.Anchored = true
			table.insert(parts, d)
		elseif d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
	prep(root)
	for _, d in ipairs(root:GetDescendants()) do
		prep(d)
	end
	if #parts == 0 then
		root:Destroy()
		return 0
	end
	root.Parent = getFolder()
	local speed = impulse * SMALL.LaunchSpeedFactor
	for _, p in ipairs(parts) do
		local d = Fracture.boxSurfaceDistance(Vector3.zero, p.Size, p.CFrame:PointToObjectSpace(center))
		local linear = Shockwave.velocity(p.Position, p.Size, center, d, radius, speed, 0.15, rng)
		launchPiece(p, linear, randomUnit(rng) * FX.LaunchSpin, PROPS.ShatterLife, profile)
	end
	if not root:IsA("BasePart") then
		root:Destroy() -- pusta skorupa modelu (części przeniósł launchPiece)
	end
	return #parts
end

local function onDebrisFall(fall: any)
	if typeof(fall) ~= "table" then return end
	local center = fall.center
	local radius = fall.radius
	local impulse = fall.impulse
	if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" or typeof(impulse) ~= "number" then return end

	local profile = QualityController.profile()
	local camPos = cameraPosition()
	local rng = Random.new()
	local budget = profile.FallPartsPerBlast

	local function handle(list: any, count: any, launch: boolean)
		if typeof(list) ~= "table" or typeof(count) ~= "number" then return end
		-- Po indeksie, nie ipairs: referencja do parta, którego nie mamy (StreamingEnabled),
		-- dojeżdża jako nil i robi dziurę w tablicy.
		for i = 1, math.min(count, 2000) do
			local inst = list[i]
			if typeof(inst) ~= "Instance" or handled[inst] then continue end
			handled[inst] = true
			local pos = instancePosition(inst)
			local near = pos ~= nil and (camPos == nil or (pos - camPos).Magnitude <= profile.FXDistance)
			if near and budget > 0 then
				if countParts(inst) <= budget then
					budget -= spawnFall(inst, launch, center, radius, impulse, rng, profile, budget)
				end
			end
			-- Oryginał chowamy ZAWSZE — także ponad budżetem i daleko: serwer i tak go
			-- zaraz skasuje, a widoczny oryginał obok spadającej kopii to podwójny mebel.
			hideLocally(inst)
		end
	end

	-- Rozpadające się meble pierwsze (26.09): są w zasięgu dziury, najbliżej wybuchu.
	local shatter, nShatter = fall.shatter, fall.nShatter
	if typeof(shatter) == "table" and typeof(nShatter) == "number" then
		for i = 1, math.min(nShatter, 500) do
			local inst = shatter[i]
			if typeof(inst) ~= "Instance" or handled[inst] then continue end
			handled[inst] = true
			local pos = instancePosition(inst)
			local near = pos ~= nil and (camPos == nil or (pos - camPos).Magnitude <= profile.FXDistance)
			if near and budget > 0 and countParts(inst) <= budget then
				budget -= spawnShatter(inst, center, radius, impulse, rng, profile)
			end
			hideLocally(inst)
		end
	end
	-- Rekwizyty, które zniknęły (wieszaki i drobne): obłok pyłu, bez kopii.
	local vapor = fall.vapor
	if typeof(vapor) == "table" then
		for i = 1, math.min(#vapor, 500) do
			local v = vapor[i]
			if typeof(v) ~= "table" or typeof(v.cf) ~= "CFrame" or typeof(v.size) ~= "Vector3" then continue end
			if camPos == nil or (v.cf.Position - camPos).Magnitude <= profile.FXDistance then
				spawnVapor(v.cf, v.size, profile)
			end
		end
	end

	-- Odrzucane pierwsze: są najbliżej wybuchu, więc budżet trybu idzie na to, co widać.
	handle(fall.launch, fall.nLaunch, true)
	handle(fall.drop, fall.nDrop, false)
end

-- ============================================================================
-- Wybuch
-- ============================================================================

local function onBlastFX(blast: any)
	if typeof(blast) ~= "table" then return end
	local center = blast.center
	local radius = blast.radius
	local seed = blast.seed
	if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" or typeof(seed) ~= "number" then return end
	local impulse = if typeof(blast.impulse) == "number" then blast.impulse else 0
	local minT = if typeof(blast.minT) == "number" then blast.minT else 0.1

	local profile = QualityController.profile()
	local camPos = cameraPosition()
	-- Ten sam seed na każdym kliencie = identyczny wzór odłamków u wszystkich.
	local rng = Random.new(seed)

	-- Gruz, który już leży w zasięgu, dostaje falą (i nie zawiśnie nad nową dziurą).
	-- OSOBNY generator: każdy gracz ma inny leżący gruz, więc losowania zużyte tutaj
	-- rozjechałyby wzór odłamków z seeda, który ma być u wszystkich identyczny.
	stirResting(center, radius, impulse, minT, Random.new(), profile)

	-- Kawałki dziur liczymy zawsze (każdy ma własny dystans od kamery) — dziura w ścianie
	-- widocznej z daleka ma mieć swój gruz, nawet gdy samego wybuchu nie widać.
	if typeof(blast.cuts) == "table" then
		spawnCutChunks(rng, blast.cuts :: { any }, center, radius, impulse, minT, camPos, profile)
	end

	-- Daleki wybuch — odłamków i szkła i tak nie widać, szkoda fizyki klienta.
	if camPos and (camPos - center).Magnitude > profile.FXDistance then return end

	if profile.ClientFrags > 0 then
		local samples = sampleSurroundings(center, radius)
		for _ = 1, profile.ClientFrags do
			spawnFrag(rng, center, radius, samples, profile)
		end
	end

	if typeof(blast.glass) == "table" then
		spawnGlassShards(rng, center, blast.glass :: { any }, profile)
	end
end

local initialized = false
function DebrisFXController.init()
	if initialized then return end
	initialized = true

	-- Listenery PRZED czymkolwiek, co mogłoby yieldować (hard rule 9).
	Remotes.BlastFX.OnClientEvent:Connect(onBlastFX)
	Remotes.DebrisFall.OnClientEvent:Connect(onDebrisFall)
	RunService.Heartbeat:Connect(stepPool)

	-- Koniec rundy: mapa zaraz wraca ze snapshotu, a gracze lecą do lobby — gruz
	-- z poprzedniej rundy nie może leżeć na świeżej mapie.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: any)
		if newState ~= "ROUND" then
			clearAll()
		end
	end)
	-- Przejście na Ziemniaka w trakcie gry: od razu przytnij do nowego sufitu.
	QualityController.Changed:Connect(function()
		enforceCap(QualityController.profile())
	end)
end

return DebrisFXController
