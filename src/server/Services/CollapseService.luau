--!strict
-- CollapseService.luau
-- DESTRUKCJA v4, faza D — WYKONAWCA: zamienia wynik solvera w to, co widać i czuć w grze.
-- Plan, decyzje i pomiary: DESTRUCTION_PLAN.md → „v4”.
--
-- Co klatkę bierze wyniki `StructuralService.flushAll()` i:
--   * KRUSZY osłabione elementy (Crumbled): ich fragment znika z mapy — duży leci jako
--     fragment fizyki serwera (ściany mogą naprawdę odlecieć — decyzja Kacpra), mały u klientów.
--     Brak niewidzialnych awarii: zniszczony strukturalnie element nie stoi dalej w mapie.
--   * PUSZCZA GRUPY KOLAPSU prawdziwą fizyką serwera (decyzja Kacpra: gracz jedzie razem
--     z piętrem). Grupa = jedna spawana bryła, nie setki partów.
--   * pilnuje BUDŻETU fizyki (koszt grupy = 1 + kawałki z kolizją; rezerwa dla grup, na
--     których stoi gracz) i kolejności (najpierw jeźdźcy, potem to, co blisko graczy, od dołu).
--     Ponad budżet grupa nie znika z gry: jej kolizja i tak odchodzi (wynik strukturalny
--     zawsze się dzieje), tylko upadek animują klienci.
--   * po zatrzymaniu KOTWICZY grupę (platforma, decyzja Kacpra: duże zostają do końca rundy,
--     małe znikają po kilku sekundach), sprząta zatopione w lawie.
--   * pilnuje, żeby osiadła bryła miała na czym leżeć (29.09, M-1): gdy spod niej zniknie
--     oparcie (niższe piętro ruszyło, wybuch, zniknęła bryła pod spodem), budzi ją — spada
--     fizyką (decyzja Kacpra 29.09). Bez tego rumowisko wisiało w powietrzu do końca rundy.
--   * NIE zadaje obrażeń: przygniecenie usunięte (decyzja Kacpra 29.09 — „usuwamy obrażenia
--     od spadającego gruzu”). Jadący na walącym się piętrze dostaje zwykły fall damage.
--
-- DLACZEGO filtr kolizji na starcie: w OrangeBuilding 158 par partów konstrukcji na siebie
-- nachodzi (słupy przez stropy, stropy w belki). Odkotwiczony kawałek nachodzący na stojący
-- silnik wypycha gwałtownie — „wybuchowy” skok, dokładnie ten sztuczny efekt. Pary, które
-- nachodzą w chwili startu, dostają NoCollisionConstraint; z resztą świata grupa zderza się
-- normalnie (ląduje na piętrze niżej, gracz na niej stoi).
--
-- ZALEŻNOŚCI: StructuralService (stan i kawałki), DebrisService (rozpoznanie uśpionego gruzu
-- jako podłoża; od 28.09 już nie fragmenty kruszenia — te są tu, jako jednoelementowe grupy),
-- LavaService (powierzchnia). Przekazanie klientom (DestructionService) wstrzykiwane w init —
-- DestructionService woła ten serwis (rubble), więc bezpośredni require byłby cyklem.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Shockwave = require(ReplicatedStorage.Shared.Modules.Shockwave)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local GameLoopService = require(script.Parent.GameLoopService)
local LavaService = require(script.Parent.LavaService)
local DebrisService = require(script.Parent.DebrisService)
local StructuralService = require(script.Parent.StructuralService)

local Structure = script.Parent.Parent.Structure
local Pieces = require(Structure.Pieces)
local CollapsePlanner = require(Structure.CollapsePlanner)

local CollapseService = {}

local CFG = Config.Structure.Collapse
local DBR = Config.Destruction.Debris

type Rec = StructuralService.Rec
type Cause = StructuralService.Cause
type Box = Pieces.Box

type Active = {
	key: string,
	rec: Rec,
	def: CollapsePlanner.Group,
	cause: Cause?,
	priority: number, -- 0 = ktoś na niej stoi, 1 = gracz blisko, 2 = reszta
	cost: number,
	volume: number,
	center: Vector3,
	pieces: { BasePart },
	followers: { BasePart },
	followerCollide: { [BasePart]: boolean },
	filters: { Instance },
	root: BasePart?,
	phase: string, -- "Queued" | "Flying" | "Settled" | "Gone"
	queuedAt: number,
	releasedAt: number,
	startCF: CFrame, -- korzeń przy odkotwiczeniu (czy grupa w ogóle ruszyła)
	jamCheckAt: number?, -- kiedy sprawdzić, czy nie zaklinowana; nil = nie sprawdzać
	stillSince: number?,
	retireAt: number?,
	fragment: boolean?, -- fragment kruszenia (28.09): jedna bryła bez chunków, wylatuje od wybuchu
	unstuck: boolean?, -- siatka zaklinowania: stopień 1 (odblokowanie) już był (28.09)
	-- Osiadła: czy ma na czym leżeć (29.09, M-1)
	restMin: Vector3?, -- pudełko, w którym leży (flagowanie po zdarzeniach w okolicy)
	restMax: Vector3?,
	supportCheckedAt: number?,
	recheck: boolean?, -- coś pod nią mogło zniknąć — sprawdzić w najbliższym przebiegu
	held: boolean?, -- budzona bez impulsu nie ruszyła się: trzyma ją fizyka, nie sprawdzać w tle
	recheckWakeCF: CFrame?, -- korzeń przy budzeniu „bez oparcia” (czy potem się ruszyła)
	unsupportedSince: number?, -- bez oparcia, ale bez miejsca w budżecie — od kiedy czeka
	-- Budzona: limit prędkości w bok/w górę, żeby silnik jej nie wystrzelił (29.09, M-4)
	clampUntil: number?,
	clampH: number?,
	clampUp: number?,
	clampSpin: number?,
}

export type Injected = {
	-- Przekazanie instancji klientom do animacji (Remotes.DebrisFall), serwer kasuje po chwili.
	handOff: (list: { Instance }, center: Vector3, launch: boolean) -> (),
	-- Drobnica i meble leżące na kawałkach, które zaraz spadną — też do klientów.
	dropResting: (pieces: { BasePart }, center: Vector3) -> (),
}

local deps: Injected? = nil
local queue: { Active } = {}
local flying: { Active } = {}
local settledTemp: { Active } = {}
-- WSZYSTKIE osiadłe grupy (małe są też w settledTemp) — sprawdzanie oparcia (M-1).
local settledAll: { Active } = {}
local recheckCursor = 0
local used = 0
local lastMonitor = 0
local rng = Random.new()
-- Kawałek → grupa. Słabe klucze: skasowany sam wypada.
local rubbleOf: { [BasePart]: Active } = setmetatable({}, { __mode = "k" }) :: any
local flyingOf: { [BasePart]: Active } = setmetatable({}, { __mode = "k" }) :: any

local concrete = PhysicalProperties.new(DBR.Density, DBR.Friction, DBR.Elasticity, DBR.FrictionWeight, DBR.ElasticityWeight)

local function log(fmt: string, ...: any)
	if CFG.Debug then
		print("[Collapse] " .. string.format(fmt, ...))
	end
end

local function boxCenter(b: Box): Vector3
	return (b.min + b.max) * 0.5
end

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function ownSet(a: Active): { [BasePart]: boolean }
	local own: { [BasePart]: boolean } = {}
	for _, p in ipairs(a.pieces) do
		own[p] = true
	end
	for _, f in ipairs(a.followers) do
		own[f] = true
	end
	return own
end

-- Pudełko świata wszystkich żywych kawałków grupy (dla osiadłej: gdzie DZIŚ leży).
local function groupBox(a: Active): (Vector3, Vector3)
	local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, list in ipairs({ a.pieces, a.followers }) do
		for _, p in ipairs(list) do
			if p.Parent then
				local b = Pieces.boxOf(p)
				mn, mx = mn:Min(b.min), mx:Max(b.max)
			end
		end
	end
	return mn, mx
end

local function unlistSettled(a: Active)
	local i = table.find(settledAll, a)
	if i then
		table.remove(settledAll, i)
	end
	i = table.find(settledTemp, a)
	if i then
		table.remove(settledTemp, i)
	end
end

-- W tym miejscu mogło zniknąć coś, na czym leżą osiadłe bryły (grupa ruszyła, wybuch, bryła
-- znikła) — te, których pudełko sięga regionu, sprawdzi najbliższy przebieg monitora (M-1).
-- Flaga, nie sprawdzenie od razu: resztki po cięciu wchodzą do broadphase dopiero w następnej
-- klatce (to samo, na co czeka podparcie „po” w DestructionService).
local function flagRubbleNear(mn: Vector3, mx: Vector3)
	local pad = Vector3.one * CFG.RubbleRecheckPad
	local lo, hi = mn - pad, mx + pad
	for _, a in ipairs(settledAll) do
		local rmn, rmx = a.restMin, a.restMax
		if rmn and rmx and rmn.X <= hi.X and rmx.X >= lo.X and rmn.Y <= hi.Y and rmx.Y >= lo.Y
			and rmn.Z <= hi.Z and rmx.Z >= lo.Z
		then
			a.recheck = true
			a.held = nil
		end
	end
end

-- `hb` leży POD `b`: górą co najwyżej JamProbe nad spodem `b`, z zakładką w poziomie
-- (`o` = nachodzenie pudełek). Jedna definicja dla lądowania, logu, odblokowania i łańcucha.
local function isBelow(b: Box, hb: Box, o: Vector3): boolean
	return hb.max.Y <= b.min.Y + CFG.JamProbe and o.X > CFG.JamBelowOverlap and o.Z > CFG.JamBelowOverlap
end

-- Chunk parta budynku w miejscu styku (pudełko chunka z luzem pół studa) albo nil. Na granicy
-- chunków luz łapie oba — a dokładnie tam `takePieces` tnie party, więc styk kawałka grupy
-- z resztą tego samego parta ZAWSZE leży na granicy. Rozstrzyga chunk, w którym LEŻY trafiony
-- kawałek (największa część wspólna jego pudełka), nie kolejność listy — ta dawała stojącej
-- reszcie parta stan „Falling” spadającej grupy (przegląd 29.09, M-5).
local function chunkAt(rec: Rec, index: number, contact: Vector3, hit: BasePart?): number?
	local st = rec.state
	local found: number? = nil
	local candidates: { number }? = nil
	for _, cid in ipairs(st.partChunks[index] or {}) do
		local c = st.chunks[cid]
		local lo, hi = c.min - Vector3.one * 0.5, c.max + Vector3.one * 0.5
		if contact.X >= lo.X and contact.X <= hi.X and contact.Y >= lo.Y and contact.Y <= hi.Y and contact.Z >= lo.Z and contact.Z <= hi.Z then
			if not found then
				found = cid
			else
				local list = candidates or { found :: number }
				table.insert(list, cid)
				candidates = list
			end
		end
	end
	if not candidates or not hit then
		return found
	end
	local hb = Pieces.boxOf(hit)
	local best, bestVolume = found, -1
	for _, cid in ipairs(candidates) do
		local c = st.chunks[cid]
		local inter = Pieces.intersect(hb, { min = c.min, max = c.max }, 0)
		local v = if inter then Pieces.volume(inter) else 0
		if v > bestVolume then
			best, bestVolume = cid, v
		end
	end
	return best
end

-- Kawałek grupy, która spada: w locie albo jeszcze w kolejce (chunk `Falling`, kawałek dalej
-- zakotwiczony — ruszy, gdy przyjdzie jego kolej).
local function isFallingPiece(hit: BasePart, contact: Vector3): boolean
	if flyingOf[hit] then
		return true
	end
	local rec, index, kind = StructuralService.ownerOf(hit)
	if not rec or not index or kind ~= "structure" then
		return false
	end
	local cid = chunkAt(rec, index, contact, hit)
	return cid ~= nil and rec.state:stateOf(cid) == "Falling"
end

-- STOJĄCA część budynku v4 w miejscu styku: konstrukcja, która nie spada, albo listwa/ozdoba
-- (te niczego nie niosą — zostają, póki czegoś dotykają).
local function isStandingPiece(hit: BasePart, contact: Vector3): boolean
	local rec, index, kind = StructuralService.ownerOf(hit)
	if not rec or not index then
		return false
	end
	if kind ~= "structure" then
		return true
	end
	local cid = chunkAt(rec, index, contact, hit)
	return cid == nil or rec.state:stateOf(cid) ~= "Falling"
end

-- Stojąca KONSTRUKCJA v4 (nie listwa, nie ozdoba) — na tym grupa może WYLĄDOWAĆ. Listwa niczego
-- nie niesie: ta sama zasada, z której filtr przy starcie przepuszcza grupę przez listwy
-- (28.09). Wcześniej `groundUnder` liczył listwę jako grunt i bryła, która opadła pół studa
-- na parapet albo gzyms, osiadała na nim w powietrzu (przegląd 29.09, M-3).
local function isStandingStructure(hit: BasePart, contact: Vector3): boolean
	local rec, index, kind = StructuralService.ownerOf(hit)
	if not rec or not index or kind ~= "structure" then
		return false
	end
	local cid = chunkAt(rec, index, contact, hit)
	return cid == nil or rec.state:stateOf(cid) ~= "Falling"
end

-- Spoiny kawałków z czymkolwiek SPOZA grupy — zabezpieczenie (stary system robi to samo przed
-- odkotwiczeniem: „ozdoby bywają zweldowane w modele” — DestructionService.launchServer): grupa
-- przyspawana do stojącej konstrukcji byłaby częścią zakotwiczonej bryły i nie ruszyłaby się
-- ani o setną studa. Zmierzone 28.09: w 10 budynkach placu 0 spoin — to NIE była przyczyna
-- zaklinowań z 28.09, ale wystarczy jedno „Join Surfaces” w Studio, żeby wróciła. Własne spawy
-- grupy (root ↔ kawałki) łączą party z `own` — zostają.
local function cutExternalJoints(parts: { BasePart }, own: { [BasePart]: boolean }): number
	local cut = 0
	for _, p in ipairs(parts) do
		if not p.Parent then continue end
		for _, j in ipairs(p:GetJoints()) do
			local other: BasePart? = nil
			if j:IsA("WeldConstraint") then
				local w = j :: WeldConstraint
				other = if w.Part0 == p then w.Part1 else w.Part0
			elseif j:IsA("JointInstance") then
				local w = j :: JointInstance
				other = if w.Part0 == p then w.Part1 else w.Part0
			else
				continue -- NoCollisionConstraint i reszta constraintów nie łączą brył
			end
			if other == nil or not own[other] then
				j:Destroy()
				cut += 1
			end
		end
	end
	return cut
end

-- Czy para wymaga filtra: nachodzenie głębsze niż OverlapMinDepth (słup przez strop) ALBO
-- JAKIEKOLWIEK nachodzenie w poziomie (styk z boku). Test 25.09: grupy ruszały o 0,4-0,6
-- studa i stawały bez niczego pod spodem — sąsiad nachodzący z boku o setne studa daje
-- silnikowi siłę dociskającą, a z nią tarcie, które trzyma cały element.
local function needsFilter(a: BasePart, b: BasePart): boolean
	local ba, bb = Pieces.boxOf(a), Pieces.boxOf(b)
	local o = ba.max:Min(bb.max) - ba.min:Max(bb.min)
	local depth = math.min(o.X, o.Y, o.Z)
	if depth <= 0 then
		return false
	end
	return depth > CFG.OverlapMinDepth or o.Y > depth
end

-- Filtry kolizji (NoCollisionConstraint) w chwili startu grupy. Poza nachodzeniem (wyżej)
-- także DOTYK (do ReleaseContactPad) — log 28.09: 10 z 38 grup zaklinowanych, najczęściej
-- o styk „BOK 0.00” ze stojącą belką albo stropem (kawałek odcięty po granicy chunka dotyka
-- reszty parta całą ścianą, a obrót startowy wciska go w sąsiadów) i o listwy pod spodem:
--   * stojąca część budynku v4 (konstrukcja, która nie spada, listwa, ozdoba) — z KAŻDEJ
--     strony, także od spodu: solver właśnie orzekł, że grupy nie trzyma (za wąski styk,
--     listwa niczego nie niesie), więc fizyka nie może jej na tym zatrzymać (decyzja Kacpra
--     28.09: „spada od razu” — najwyżej na moment przenika przez sam róg belki);
--   * inna spadająca grupa (w locie albo w kolejce) — tylko z BOKU. Od spodu i od góry
--     zostaje: piętro jedzie na piętrze.
-- Reszta świata (fundament, ulice, teren, osiadłe rumowisko, meble) zostaje — na tym grupy lądują.
local function filterAtRelease(pieces: { BasePart }, own: { [BasePart]: boolean }, filters: { Instance })
	local count = 0
	local pad = Vector3.one * (CFG.ReleaseContactPad * 2)
	for _, p in ipairs(pieces) do
		local b = Pieces.boxOf(p)
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + pad)) do
			if count >= CFG.OverlapFilterMax then return end
			if own[hit] or hit:IsA("Terrain") or not hit.CanCollide or isCharacterPart(hit) then continue end
			local hb = Pieces.boxOf(hit)
			local o = hb.max:Min(b.max) - hb.min:Max(b.min) -- ujemne = szczelina
			local contact = (hb.min:Max(b.min) + hb.max:Min(b.max)) * 0.5
			local lateral = math.min(o.X, o.Z) < o.Y -- najpłytsze nachodzenie w poziomie = styk z boku
			local filter = needsFilter(p, hit)
				or isStandingPiece(hit, contact)
				or (lateral and isFallingPiece(hit, contact))
			if not filter then continue end
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = p
			nc.Part1 = hit
			nc.Parent = p
			table.insert(filters, nc)
			count += 1
		end
	end
end

-- Fragment kruszenia: bez kolizji ze WSZYSTKIM, czego dotyka w chwili startu (nie tylko z tym,
-- na co nachodzi). Test 25.09: 4 z 11 zaklinowań to filarek leżący na fragmencie skruszonej
-- ściany pod sobą — fragment startuje z prędkością w górę i od wybuchu, więc podpierał
-- (a nawet podnosił) dokładnie to, co przez jego skruszenie straciło podparcie. Z dalszym
-- światem (podłoga, na którą spadnie) zderza się normalnie.
local function filterContacts(fragment: BasePart, filters: { Instance })
	local count = 0
	local pad = Vector3.one * (CFG.StubContact * 2)
	for _, hit in ipairs(Workspace:GetPartBoundsInBox(fragment.CFrame, fragment.Size + pad)) do
		if count >= CFG.OverlapFilterMax then return end
		if hit == fragment or hit:IsA("Terrain") or not hit.CanCollide or isCharacterPart(hit) then continue end
		local nc = Instance.new("NoCollisionConstraint")
		nc.Part0 = fragment
		nc.Part1 = hit
		nc.Parent = fragment
		table.insert(filters, nc)
		count += 1
	end
end

-- Kawałki oddawane klientom tracą kolizję na serwerze OD RAZU. Kasowanie i tak czeka
-- `HandoffDelay` (klient musi zdążyć skopiować), ale kolizja przez ten czas trzymała to, co
-- na nich leżało — test 25.09: grupa stojąca na przekazanym fragmencie ruszała dopiero po
-- 0,25 s i łapała się na sprawdzanie zaklinowania. Klient animuje własną kopię bez kolizji.
local function handOffNow(list: { Instance }, center: Vector3, launch: boolean)
	if not deps or #list == 0 then
		return
	end
	for _, inst in ipairs(list) do
		if inst:IsA("BasePart") then
			inst.CanCollide = false
		end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
	deps.handOff(list, center, launch)
end

-- ============================================================================
-- Kruszenie osłabionego elementu (Crumbled): fragment chunka znika z mapy
-- ============================================================================

-- `reserved` = budżet już obiecany w tej samej klatce, ale jeszcze nie zajęty (fragmenty kruszenia).
local function fits(a: Active, reserved: number?): boolean
	local free = CFG.MaxCost - used - (reserved or 0) - (if a.priority == 0 then 0 else CFG.ReserveP0)
	return a.cost <= free
end

-- Fragment kruszenia = jednoelementowa grupa kolapsu (28.09, decyzje Kacpra). Do 28.09 był
-- gruzem DebrisService: bomba go tylko pchała, nigdy nie cięła, miał osobny budżet i leżał do
-- końca rundy. Teraz to samo rumowisko co bryły pięter: wspólny budżet fizyki (bez miejsca —
-- animacja u klientów, jak mały fragment), osiada, a leżący jest cięty bombą (`cutRubble`),
-- budzony, gaśnie w lawie; mały znika po `SmallRubbleLifetime`, duży zostaje platformą.
local fragmentSeq = 0

local function newFragment(rec: Rec, part: BasePart, cause: Cause?): Active
	fragmentSeq += 1
	local b = Pieces.boxOf(part)
	local s = part.Size
	local volume = s.X * s.Y * s.Z
	local id = "F" .. fragmentSeq
	return {
		key = rec.id .. ":" .. id,
		rec = rec,
		def = {
			groupId = id, chunkIds = {}, depth = 0, pivot = {}, parts = {}, splitParts = {},
			followers = {}, volume = volume, min = b.min, max = b.max,
		},
		cause = cause,
		priority = 2,
		cost = 2, -- jak grupa: 1 + kawałki z kolizją
		volume = volume,
		center = part.Position,
		pieces = { part },
		followers = {},
		followerCollide = {},
		filters = {},
		root = part,
		phase = "Queued",
		queuedAt = os.clock(),
		releasedAt = 0,
		startCF = part.CFrame,
		jamCheckAt = nil,
		stillSince = nil,
		retireAt = nil,
		fragment = true,
	}
end

-- Filtr kontaktów ma być już założony (a.filters) — patrz komentarz w `crumble`.
local function launchFragment(a: Active, from: Vector3?)
	local part = a.root :: BasePart
	part.CustomPhysicalProperties = concrete
	part.Anchored = false
	flyingOf[part] = a
	pcall(function()
		part:SetNetworkOwner(nil) -- bryła z kolizją należąca do klienta = exploit
	end)
	local away = if from then part.Position - from else Vector3.yAxis
	local dir = if away.Magnitude > 1e-3 then away.Unit else Vector3.yAxis
	part.AssemblyLinearVelocity = dir * CFG.FragmentSpeed + Vector3.new(0, CFG.FragmentSpeed * 0.3, 0)
	a.phase = "Flying"
	a.releasedAt = os.clock()
	-- Wylatuje od wybuchu — sprawdzanie zaklinowania nie dotyczy (jak obudzone rumowisko).
	a.jamCheckAt = nil
	used += a.cost
	table.insert(flying, a)
end

local function crumble(rec: Rec, chunkId: number, cause: Cause?)
	local c = rec.state.chunks[chunkId]
	local box: Box = { min = c.min, max = c.max }
	local center = if cause and cause.center then cause.center else (c.min + c.max) * 0.5
	local toClients: { Instance } = {}
	local toLaunch: { Active } = {}
	local reserved = 0
	local fragments: { BasePart } = {}
	for _, piece in ipairs(table.clone(StructuralService.piecesOf(rec, c.part))) do
		local pb = Pieces.boxOf(piece)
		local inter = Pieces.intersect(pb, box, CFG.MinPieceSize)
		if not inter then continue end
		local keep = Pieces.merge(Pieces.subtract(pb, box, CFG.MinPieceSize))
		local fragment: BasePart
		if #keep == 0 then
			StructuralService.releasePiece(rec, c.part, piece)
			fragment = piece
		else
			table.sort(keep, function(a, b)
				return Pieces.volume(a) > Pieces.volume(b)
			end)
			fragment = Pieces.spawnBox(piece, inter)
			for i = 2, #keep do
				StructuralService.addPiece(rec, c.part, Pieces.spawnBox(piece, keep[i]))
			end
			Pieces.setBox(piece, keep[1])
		end
		fragments[#fragments + 1] = fragment
		local frag = if Pieces.volume(inter) >= CFG.FragmentMinVolume then newFragment(rec, fragment, cause) else nil
		if frag and fits(frag, reserved) then
			reserved += frag.cost
			table.insert(toLaunch, frag)
		else
			table.insert(toClients, fragment)
		end
	end
	-- Filtr nachodzących par PRZED odkotwiczeniem (test 25.09): bez niego fragment belki
	-- tkwiący w słupie albo stropie klinował się w miejscu, DebrisService usypiał go jako
	-- leżący, a słup albo strop, który przez to kruszenie stracił podparcie, leżał potem
	-- na tym fragmencie — i tak aż do dachu. Zmierzone: 11 z 21 spadających grup w serii
	-- 6 bomb leży bezpośrednio na skruszonym elemencie.
	for _, frag in ipairs(toLaunch) do
		local part = frag.root :: BasePart
		cutExternalJoints({ part }, { [part] = true })
		filterContacts(part, frag.filters)
		launchFragment(frag, center)
	end
	if #toLaunch + #toClients > 0 then
		log("%s: kruszenie ch%d — fragmentów fizyką %d, u klientów %d (budżet %d/%d)",
			rec.id, chunkId, #toLaunch, #toClients, used, CFG.MaxCost)
	end
	flagRubbleNear(c.min, c.max)
	-- Listwy i szyby, które przez to kruszenie straciły OSTATNIE oparcie, spadają (test 24.09:
	-- bez tego zostawały w powietrzu). Od 26.09 tylko te — wcześniej spadały wszystkie listwy
	-- chunka, także trzymające się czegoś jeszcze, a te wiszące na innych listwach zostawały.
	local loose: { Instance } = {}
	for _, u in ipairs(StructuralService.takeUnsupportedStrips(rec)) do
		table.insert(loose, u.piece)
	end
	if deps then
		-- Meble i drobnica stojące na tym, co się skruszyło.
		deps.dropResting(fragments, center)
		handOffNow(toClients, center, true)
		handOffNow(loose, center, false)
	end
end

-- Osłabiony element ciemnieje (bez tego osłabianie jest niewidzialne i „2. bomba go
-- przecięła” wygląda jak losowość). Kolor przez atrybut oryginału — jak v3.
local ORIG_COLOR_ATTR = "DestrOrigColor"

local function darken(rec: Rec, chunkIds: { number })
	local hpByKind = Config.Structure.Damage.HP
	local worstByPart: { [number]: number } = {}
	for _, id in ipairs(chunkIds) do
		local c = rec.state.chunks[id]
		local hp = hpByKind[c.kind]
		if hp then
			local frac = math.clamp(rec.state.rt[id].damage / hp, 0, 1)
			worstByPart[c.part] = math.max(worstByPart[c.part] or 0, frac)
		end
	end
	for partIndex, frac in pairs(worstByPart) do
		for _, piece in ipairs(StructuralService.piecesOf(rec, partIndex)) do
			local orig = piece:GetAttribute(ORIG_COLOR_ATTR)
			if typeof(orig) ~= "Color3" then
				orig = piece.Color
				piece:SetAttribute(ORIG_COLOR_ATTR, orig)
			end
			piece.Color = (orig :: Color3):Lerp(Color3.fromRGB(35, 32, 30), frac * Config.Destruction.DamageFeedback.DarkenMax)
		end
	end
end

-- ============================================================================
-- Plan kolapsu → kolejka (priorytet, koszt)
-- ============================================================================

local function priorityOf(g: CollapsePlanner.Group): number
	local best = 2
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end
		local feet = hrp.Position - Vector3.new(0, 2.5, 0)
		local p = feet
		if p.X >= g.min.X - 1 and p.X <= g.max.X + 1 and p.Z >= g.min.Z - 1 and p.Z <= g.max.Z + 1
			and p.Y >= g.max.Y - 1 and p.Y <= g.max.Y + CFG.RiderHeight then
			return 0
		end
		local d = (hrp.Position:Max(g.min):Min(g.max) - hrp.Position).Magnitude
		if d <= CFG.NearPlayerDistance then
			best = 1
		end
	end
	return best
end

local function enqueue(rec: Rec, plan: any)
	for _, g in ipairs(plan.groups :: { CollapsePlanner.Group }) do
		table.insert(queue, {
			key = rec.id .. ":" .. g.groupId,
			rec = rec,
			def = g,
			cause = plan.cause,
			priority = priorityOf(g),
			cost = 1 + #g.parts,
			volume = g.volume,
			center = (g.min + g.max) * 0.5,
			pieces = {},
			followers = {},
			followerCollide = {},
			filters = {},
			root = nil,
			phase = "Queued",
			queuedAt = os.clock(),
			releasedAt = 0,
			startCF = CFrame.identity,
		})
	end
	-- Najpierw jeźdźcy, potem to, co blisko graczy; w obrębie — od dołu (kaskada), większe pierwsze.
	table.sort(queue, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		if a.def.depth ~= b.def.depth then
			return a.def.depth < b.def.depth
		end
		return a.volume > b.volume
	end)
	log("%s: kolaps #%d → %d grup w kolejce (przyczyna seq %s)", rec.id, plan.collapseId, #plan.groups,
		if plan.cause then tostring(plan.cause.seq) else "-")
end

-- ============================================================================
-- Kawałki grupy: odcinamy to, co leży w jej chunkach
-- ============================================================================

-- Zbiera kawałki spadające z grupą. Kawałek w całości w grupie spada cały; kawałek na
-- granicy jest dzielony po granicy chunków — ORYGINAŁ zostaje w części stojącej (gracz na
-- nim nie traci gruntu), nowe kawałki powstają dla reszty. Resztki zniszczonych chunków
-- tego samego parta, które dotykają grupy, lecą razem z nią (nic nie wisi w powietrzu).
local function takePieces(a: Active): { BasePart }
	local rec, g = a.rec, a.def
	local st = rec.state
	local inGroup: { [number]: boolean } = {}
	for _, id in ipairs(g.chunkIds) do
		inGroup[id] = true
	end
	local out: { BasePart } = {}
	for _, partIndex in ipairs(g.parts) do
		local groupBoxes: { Box } = {}
		local fallBoxes: { Box } = {}
		for _, cid in ipairs(st.partChunks[partIndex] or {}) do
			local c = st.chunks[cid]
			local b = { min = c.min, max = c.max }
			if inGroup[cid] then
				table.insert(groupBoxes, b)
				table.insert(fallBoxes, b)
			elseif st.rt[cid].state == "Destroyed" then
				table.insert(fallBoxes, b)
			end
		end
		for _, piece in ipairs(table.clone(StructuralService.piecesOf(rec, partIndex))) do
			local pb = Pieces.boxOf(piece)
			local touchesGroup = false
			for _, b in ipairs(groupBoxes) do
				if Pieces.intersect(pb, b, CFG.MinPieceSize) then
					touchesGroup = true
					break
				end
			end
			if not touchesGroup then continue end
			local fall: { Box } = {}
			local keep: { Box } = { pb }
			for _, b in ipairs(fallBoxes) do
				local inter = Pieces.intersect(pb, b, CFG.MinPieceSize)
				if inter then
					table.insert(fall, inter)
					local nextKeep: { Box } = {}
					for _, k in ipairs(keep) do
						for _, r in ipairs(Pieces.subtract(k, b, CFG.MinPieceSize)) do
							table.insert(nextKeep, r)
						end
					end
					keep = nextKeep
				end
			end
			fall = Pieces.merge(fall)
			keep = Pieces.merge(keep)
			if #keep == 0 then
				StructuralService.releasePiece(rec, partIndex, piece)
				table.insert(out, piece)
			else
				table.sort(keep, function(x, y)
					return Pieces.volume(x) > Pieces.volume(y)
				end)
				for _, f in ipairs(fall) do
					table.insert(out, Pieces.spawnBox(piece, f))
				end
				for i = 2, #keep do
					StructuralService.addPiece(rec, partIndex, Pieces.spawnBox(piece, keep[i]))
				end
				Pieces.setBox(piece, keep[1])
			end
		end
	end

	-- KIKUTY innych partów (decyzja Kacpra 25.09: „spadają z tym, co trzymają”). Dziura ~18
	-- studów przecina chunk słupa albo belki (~20-22) — solver uznaje cały chunk za zniszczony,
	-- ale nad i pod dziurą zostają pasy materiału, zakotwiczone. Test 25.09: dach, strop i belki
	-- zawisały dokładnie na takich kikutach. Kawałek innego parta, którego styk z grupą leży
	-- w ZNISZCZONYM chunku, jest odcinany po granicy tego chunka i leci z grupą (jak kikut
	-- słupa zwisający ze stropu). Kikut, którego nic nie rusza (pień słupa na podłodze), zostaje.
	local ownParts: { [number]: boolean } = {}
	for _, partIndex in ipairs(g.parts) do
		ownParts[partIndex] = true
	end
	local taken: { [BasePart]: boolean } = {}
	for _, p in ipairs(out) do
		taken[p] = true
	end
	local pad = Vector3.one * CFG.StubContact
	local stubs: { BasePart } = {}
	for _, p in ipairs(out) do
		local pb = Pieces.boxOf(p)
		local near: Box = { min = pb.min - pad, max = pb.max + pad }
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + pad * 2)) do
			if taken[hit] or not hit.Anchored then continue end
			local hrec, hidx, kind = StructuralService.ownerOf(hit)
			if hrec ~= rec or kind ~= "structure" or not hidx or ownParts[hidx] then continue end
			local hb = Pieces.boxOf(hit)
			local fall: { Box } = {}
			for _, cid in ipairs(st.partChunks[hidx] or {}) do
				if st.rt[cid].state ~= "Destroyed" then continue end
				local c = st.chunks[cid]
				local inter = Pieces.intersect(hb, { min = c.min, max = c.max }, CFG.MinPieceSize)
				if inter and Pieces.intersect(inter, near, 0) then
					table.insert(fall, inter)
				end
			end
			if #fall == 0 then continue end
			taken[hit] = true
			local keep: { Box } = { hb }
			for _, f in ipairs(fall) do
				local nextKeep: { Box } = {}
				for _, k in ipairs(keep) do
					for _, r in ipairs(Pieces.subtract(k, f, CFG.MinPieceSize)) do
						table.insert(nextKeep, r)
					end
				end
				keep = nextKeep
			end
			fall = Pieces.merge(fall)
			keep = Pieces.merge(keep)
			if #keep == 0 then
				StructuralService.releasePiece(rec, hidx, hit)
				table.insert(stubs, hit)
			else
				table.sort(keep, function(x, y)
					return Pieces.volume(x) > Pieces.volume(y)
				end)
				for _, f in ipairs(fall) do
					table.insert(stubs, Pieces.spawnBox(hit, f))
				end
				for i = 2, #keep do
					StructuralService.addPiece(rec, hidx, Pieces.spawnBox(hit, keep[i]))
				end
				Pieces.setBox(hit, keep[1])
			end
		end
	end
	for _, s in ipairs(stubs) do
		table.insert(out, s)
	end
	return out
end

-- Listwy, które po zabraniu kawałków grupy (`takePieces` — woła się PRZED tym) straciły
-- OSTATNIE oparcie: doczepione w bake'u do chunków grupy lecą z nią jako pasażerowie, reszta
-- idzie do klientów. Listwa, która dotyka jeszcze czegoś stojącego, ZOSTAJE (decyzja Kacpra
-- 26.09) — wcześniej leciała z grupą każda doczepiona, np. szyna drabiny przez trzy piętra
-- razem z górnym stropem, a szczebel wiszący tylko na innej listwie zostawał w powietrzu.
local function takeFollowers(a: Active): ({ BasePart }, { BasePart })
	local mine: { [number]: boolean } = {}
	for _, partIndex in ipairs(a.def.followers) do
		mine[partIndex] = true
	end
	local ride: { BasePart } = {}
	local drop: { BasePart } = {}
	for _, u in ipairs(StructuralService.takeUnsupportedStrips(a.rec)) do
		table.insert(if mine[u.index] then ride else drop, u.piece)
	end
	return ride, drop
end

-- ============================================================================
-- Start lotu
-- ============================================================================

local function release(a: Active): boolean
	local pieces = takePieces(a)
	if #pieces == 0 then
		a.rec.state:retire(a.def.chunkIds)
		a.phase = "Gone"
		return false
	end
	local followers, loose = takeFollowers(a)
	handOffNow(loose, a.center, false)
	a.pieces = pieces
	a.followers = followers

	table.sort(pieces, function(x, y)
		local sx, sy = x.Size, y.Size
		return sx.X * sx.Y * sx.Z > sy.X * sy.Y * sy.Z
	end)
	local root = pieces[1]
	a.root = root

	local own = ownSet(a)
	local joints = cutExternalJoints(pieces, own) + cutExternalJoints(followers, own)
	filterAtRelease(a.pieces, own, a.filters)

	-- Spawanie: jedna bryła. Spawy zostają po zatrzymaniu — kolejny wybuch budzi całą bryłę.
	for i = 2, #pieces do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = pieces[i]
		w.Parent = pieces[i]
	end
	for _, f in ipairs(followers) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = f
		w.Parent = f
		-- Pasażer (listwa, rama okna) leci bez kolizji i bez masy — mniej kontaktów, a bryłę
		-- prowadzi konstrukcja, nie ozdoba.
		a.followerCollide[f] = f.CanCollide
		f.CanCollide = false
		f.Massless = true
	end

	for _, p in ipairs(pieces) do
		p.CustomPhysicalProperties = concrete
		p.Anchored = false
		flyingOf[p] = a
	end
	for _, f in ipairs(followers) do
		f.Anchored = false
		flyingOf[f] = a
	end
	-- Drobnica i meble na tym, co spada — do klientów (inaczej wisiałyby w powietrzu).
	if deps then
		deps.dropResting(pieces, a.center)
	end

	pcall(function()
		root:SetNetworkOwner(nil) -- serwer: bryła z kolizją należąca do klienta = exploit (podnieść nad lawę)
	end)
	local r = Random.new(#a.key + a.def.chunkIds[1])
	root.AssemblyLinearVelocity = Vector3.new(0, -CFG.FallSpeed, 0)
	root.AssemblyAngularVelocity = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(-0.3, 0.3), r:NextNumber(-1, 1)) * CFG.Spin

	a.phase = "Flying"
	a.releasedAt = os.clock()
	a.startCF = root.CFrame
	a.jamCheckAt = a.releasedAt + CFG.JamCheckTime
	used += a.cost
	table.insert(flying, a)
	Remotes.StructureFX:FireAllClients("collapse", a.center, math.clamp(a.volume / 4000, 0.2, 1))
	-- Rumowisko leżące na tej grupie (np. zawalone wcześniej piętro wyżej) traci oparcie (M-1).
	flagRubbleNear(a.def.min, a.def.max)
	log("%s: grupa %s leci (P%d, koszt %d, kawałków %d, pasażerów %d, filtr %d, spoiny %d, budżet %d/%d)",
		a.rec.id, a.def.groupId, a.priority, a.cost, #pieces, #followers, #a.filters, joints, used, CFG.MaxCost)
	return true
end

-- Ponad budżet: wynik strukturalny i tak się dzieje (kolizja grupy znika), tylko upadek
-- animują klienci zamiast fizyki serwera.
local function degrade(a: Active)
	local pieces = takePieces(a)
	local ride, loose = takeFollowers(a)
	for _, list in ipairs({ ride, loose }) do
		for _, f in ipairs(list) do
			table.insert(pieces, f)
		end
	end
	handOffNow(pieces, a.center, false)
	a.rec.state:retire(a.def.chunkIds)
	a.phase = "Gone"
	flagRubbleNear(a.def.min, a.def.max)
	log("%s: grupa %s ponad budżet (P%d, koszt %d, zajęte %d/%d) — upadek u klientów", a.rec.id, a.def.groupId, a.priority, a.cost, used, CFG.MaxCost)
end

-- ============================================================================
-- Lot → osiadanie / lawa / przygniecenie
-- ============================================================================

local function finishFlight(a: Active)
	local i = table.find(flying, a)
	if i then
		table.remove(flying, i)
	end
	used = math.max(0, used - a.cost) -- zwrot budżetu dokładnie raz: tylko przy wyjściu z listy lotu
end

local function destroyGroup(a: Active)
	local mn, mx = groupBox(a)
	unlistSettled(a)
	for _, p in ipairs(a.pieces) do
		if p.Parent then p:Destroy() end
	end
	for _, f in ipairs(a.followers) do
		if f.Parent then f:Destroy() end
	end
	a.rec.state:retire(a.def.chunkIds)
	a.phase = "Gone"
	flagRubbleNear(mn, mx)
end

-- `forced`: kotwiczenie po MaxFallTime, a nie dlatego, że leży — sprawdzić oparcie od razu.
local function settle(a: Active, forced: boolean?)
	finishFlight(a)
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			Utils.anchorAtRest(p) -- bez zerowania prędkości leżąca bryła działała jak taśmociąg
			rubbleOf[p] = a
			flyingOf[p] = nil
		end
	end
	for _, f in ipairs(a.followers) do
		if f.Parent then
			Utils.anchorAtRest(f)
			f.Massless = false
			f.CanCollide = a.followerCollide[f] ~= false
			rubbleOf[f] = a
			flyingOf[f] = nil
		end
	end
	for _, nc in ipairs(a.filters) do
		nc:Destroy()
	end
	table.clear(a.filters)
	a.rec.state:settle(a.def.chunkIds)
	a.phase = "Settled"
	a.stillSince = nil
	a.clampUntil = nil
	-- Od teraz pilnujemy, czy ma na czym leżeć (M-1).
	a.restMin, a.restMax = groupBox(a)
	a.supportCheckedAt = os.clock()
	a.recheck = if forced then true else nil
	a.held = nil
	local wakeCF = a.recheckWakeCF
	if wakeCF and a.root then
		-- Budzona bez impulsu, bo pudełka świata nie widziały pod nią oparcia (obrócona bryła
		-- ma pudełko większe od siebie) — a nie ruszyła się: trzyma ją fizyka. Nie sprawdzamy
		-- jej w tle, dopóki pod spodem coś się nie zmieni — inaczej budziłaby się w kółko.
		if (a.root.Position - wakeCF.Position).Magnitude < CFG.JamMinMove then
			a.held = true
		end
	end
	a.recheckWakeCF = nil
	if not table.find(settledAll, a) then
		table.insert(settledAll, a)
	end
	if a.volume < CFG.SmallRubbleVolume then
		a.retireAt = os.clock() + CFG.SmallRubbleLifetime
		table.insert(settledTemp, a)
	end
	if not a.fragment then -- fragmenty: podsumowanie jest w logu kruszenia
		log("%s: grupa %s osiadła po %.1f s (%s)", a.rec.id, a.def.groupId, os.clock() - a.releasedAt,
			if a.retireAt then "mała — zniknie" else "platforma do końca rundy")
	end
end

local function groupTop(a: Active): number
	local top = -math.huge
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			top = math.max(top, Pieces.boxOf(p).max.Y)
		end
	end
	return top
end

-- ============================================================================
-- Zaklinowana grupa (siatka bezpieczeństwa, decyzje Kacpra 25.09 i 28.09)
-- ============================================================================
-- Solver mówi „spada”, a fizyka trzyma — przy setkach serwerów to się zdarzy w sposób, którego
-- nikt nie przewidział. Grupa, która po odkotwiczeniu w ogóle nie ruszyła i nie leży na niczym
-- pewnym, przechodzi DWA stopnie (28.09):
--   1. ODBLOKOWANIE — traci spoiny z otoczeniem i kolizję ze wszystkim, czego dotyka (poza
--      spadającą grupą pod nią i nad nią — piętro jedzie na piętrze), i leci dalej fizyką
--      serwera. Gracz na niej jedzie dalej; do 28.09 podłoga znikała mu spod nóg.
--   2. Gdy utknie drugi raz — upadek u klientów (jak grupa ponad budżetem): nic nie wisi
--      w powietrzu (kontrakt 15), a to, co na niej leżało, spada dalej prawdziwą fizyką.
-- Log mówi, CO ją trzymało — żeby naprawiać przyczyny, a nie tylko skutki.

-- Opis podpory: dla konstrukcji v4 — part, rodzaj i STAN chunka w miejscu styku. To rozstrzyga
-- przyczynę: Intact = solver przeczy fizyce, Destroyed = geometria nie zniknęła, Falling =
-- łańcuch (leży na innej zaklinowanej), Settled = prawidłowe rumowisko.
local function describeHolder(hit: BasePart, contact: Vector3): string
	if rubbleOf[hit] then
		return "rumowisko " .. rubbleOf[hit].def.groupId
	end
	if flyingOf[hit] then
		return "grupa w locie " .. flyingOf[hit].def.groupId
	end
	if DebrisService.isRegistered(hit) then
		return "gruz serwera"
	end
	local rec, index, kind = StructuralService.ownerOf(hit)
	if not rec or not index then
		return hit:GetFullName()
	end
	local cid = chunkAt(rec, index, contact, hit)
	if cid then
		local c = rec.state.chunks[cid]
		local rt = rec.state.rt[cid]
		return ("%s #%d %s ch%d %s%s"):format(tostring(kind), index, c.kind, cid, rt.state, if rt.reason then "/" .. rt.reason else "")
	end
	return ("%s #%d %s poza chunkami"):format(tostring(kind), index, rec.parts[index].kind)
end

-- Czy para ma filtr kolizji (NoCollisionConstraint może wisieć na którymkolwiek z dwóch).
local function hasFilter(a: BasePart, b: BasePart): boolean
	for _, owner in ipairs({ a, b }) do
		for _, c in ipairs(owner:GetChildren()) do
			if c:IsA("NoCollisionConstraint") and ((c.Part0 == a and c.Part1 == b) or (c.Part0 == b and c.Part1 == a)) then
				return true
			end
		end
	end
	return false
end

local function isAbove(b: Box, hb: Box, o: Vector3): boolean
	return hb.min.Y >= b.max.Y - CFG.JamProbe and o.X > CFG.JamBelowOverlap and o.Z > CFG.JamBelowOverlap
end

type Contact = { part: BasePart, hit: BasePart, box: Box, hitBox: Box, o: Vector3 }
type HolderEntry = { rank: number, depth: number, text: string }

-- KAŻDY styk kawałków grupy z kolizją i bez filtra (pudełka z luzem JamProbe) — pod spodem,
-- nad nią albo z boku. Test 25.09: wersja szukająca tylko podpory od spodu nie widziała styków
-- powstałych dopiero w ruchu. Jedna lista dla logu, łańcucha i odblokowania.
local function contactsOf(a: Active): { Contact }
	local own = ownSet(a)
	local out: { Contact } = {}
	for _, p in ipairs(a.pieces) do
		if not p.Parent then continue end
		local b = Pieces.boxOf(p)
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.one * (CFG.JamProbe * 2))) do
			if own[hit] or not hit.CanCollide or isCharacterPart(hit) or hit:IsA("Terrain") then continue end
			if hasFilter(p, hit) then continue end
			local hb = Pieces.boxOf(hit)
			local o = hb.max:Min(b.max) - hb.min:Max(b.min) -- ujemne = szczelina
			if o.X < -CFG.JamProbe or o.Y < -CFG.JamProbe or o.Z < -CFG.JamProbe then continue end
			table.insert(out, { part = p, hit = hit, box = b, hitBox = hb, o = o })
		end
	end
	return out
end

-- Co trzyma grupę, do logu: najpierw to, co POD spodem, potem z boku (najgłębsze pierwsze), na
-- końcu nad nią. Log 28.09: przy limicie 6 wpisów w kolejności z silnika podpora od spodu przy
-- 6 z 10 zaklinowań mogła się nie zmieścić. Plus „przyspawana”: spoina z czymś zakotwiczonym
-- trzyma bryłę bez żadnego styku.
local function holdersOf(a: Active, contacts: { Contact }): string
	local kinds: { [string]: number } = {}
	for _, id in ipairs(a.def.chunkIds) do
		local k = a.rec.state.chunks[id].kind
		kinds[k] = (kinds[k] or 0) + 1
	end
	local kindList: { string } = {}
	for k, n in pairs(kinds) do
		table.insert(kindList, k .. "×" .. n)
	end
	table.sort(kindList)
	local entries: { HolderEntry } = {}
	local seen: { [BasePart]: boolean } = {}
	for _, c in ipairs(contacts) do
		if seen[c.hit] then continue end
		seen[c.hit] = true
		local rank, depth, where = 2, math.min(c.o.X, c.o.Z), ""
		if isBelow(c.box, c.hitBox, c.o) then
			rank, depth, where = 1, 0, "POD"
		elseif isAbove(c.box, c.hitBox, c.o) then
			rank, depth, where = 3, 0, "NAD"
		else
			where = ("BOK %.2f"):format(depth)
		end
		local contact = (c.hitBox.min:Max(c.box.min) + c.hitBox.max:Min(c.box.max)) * 0.5
		table.insert(entries, { rank = rank, depth = depth, text = where .. " " .. describeHolder(c.hit, contact) })
	end
	table.sort(entries, function(x, y)
		if x.rank ~= y.rank then
			return x.rank < y.rank
		end
		return x.depth > y.depth
	end)
	local names: { string } = {}
	for k = 1, math.min(#entries, CFG.JamLogMax) do
		table.insert(names, entries[k].text)
	end
	if #entries > CFG.JamLogMax then
		table.insert(names, ("(+%d)"):format(#entries - CFG.JamLogMax))
	end
	local root = a.root
	local welded = root ~= nil and root.Parent ~= nil and root:IsGrounded()
	return ("[%s, kawałków %d%s] %s"):format(table.concat(kindList, " "), #a.pieces,
		if welded then ", PRZYSPAWANA do zakotwiczonego" else "",
		if #names > 0 then table.concat(names, "; ") else "zero styków bez filtra")
end

-- Na czym grupa LEŻY, jeśli to coś pewnego: geometria mapy spoza budynków v4 (fundament,
-- ulica, ściany mapy), teren, osiadłe rumowisko albo uśpiony gruz. nil = nic takiego pod
-- spodem (trzyma ją własna konstrukcja budynku albo tarcie z boku — to przypadek dla siatki).
-- Test 27.09 (CyanOffice): panele 3×6×1 stojące na belce tuż nad fundamentem po zniszczeniu
-- belki opadały na `Map.Locked.Foundation` o mniej niż `JamMinMove`; siatka brała je za
-- zaklinowane i klienci siekli je na drobny gruz — Kacper: „sypią się, choć nie powinny”.
-- Stojąca konstrukcja v4 pod spodem liczy się (28.09) tylko wtedy, gdy grupa naprawdę na nią
-- OPADŁA (`moved` ≥ LandMinDrop): styki ze startu mają filtr (filterAtRelease), więc bez tego
-- ściana opadła o pół studa na stojącą belkę zostałaby odblokowana i przeleciała przez nią.
local function groundUnder(a: Active, moved: number): string?
	local own = ownSet(a)
	for _, p in ipairs(a.pieces) do
		if not p.Parent then continue end
		local b = Pieces.boxOf(p)
		for _, hit in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.one * (CFG.JamProbe * 2))) do
			if own[hit] or not hit.CanCollide or not hit.Anchored or isCharacterPart(hit) then continue end
			if hit:IsA("Terrain") then
				return "teren"
			end
			if hasFilter(p, hit) then continue end -- fizyka tego styku nie widzi
			local hb = Pieces.boxOf(hit)
			local o = hb.max:Min(b.max) - hb.min:Max(b.min)
			if not isBelow(b, hb, o) then continue end
			local r = rubbleOf[hit]
			if r then
				if r.phase == "Settled" then
					return "rumowisko " .. r.def.groupId
				end
				continue
			end
			if flyingOf[hit] then continue end
			if DebrisService.isRegistered(hit) then
				return "gruz serwera" -- zakotwiczony = uśpiony
			end
			if StructuralService.ownerOf(hit) then
				local contact = (hb.min:Max(b.min) + hb.max:Min(b.max)) * 0.5
				if moved >= CFG.LandMinDrop and isStandingStructure(hit, contact) then
					return "stojąca konstrukcja " .. describeHolder(hit, contact)
				end
				-- Trzyma od startu (bez filtra tylko ponad OverlapFilterMax) albo to listwa (M-3): siatka.
				continue
			end
			return hit:GetFullName()
		end
	end
	return nil
end

-- Leży na innej spadającej grupie — w locie (sprawdzanej, odblokowanej, właśnie osiadającej)
-- albo jeszcze w kolejce (zakotwiczona, czeka na budżet): przyczyna jest pod spodem, ta ruszy,
-- gdy ruszy tamta (albo osiądzie na niej, gdy tamta osiądzie). Log 28.09: 5:154 leżała na
-- 5:29 i obie szły do klientów, a każde zaklinowanie przesuwało okno pozostałych o
-- JamCheckTime — kaskada do 2,6 s wiszenia.
local function restsOnFalling(contacts: { Contact }): boolean
	for _, c in ipairs(contacts) do
		if not isBelow(c.box, c.hitBox, c.o) then continue end
		local contact = (c.hitBox.min:Max(c.box.min) + c.hitBox.max:Min(c.box.max)) * 0.5
		if isFallingPiece(c.hit, contact) then
			return true
		end
	end
	return false
end

-- Stopień 1: odblokowanie (opis na górze sekcji). Zwraca (spoiny, filtry).
local function unstick(a: Active, contacts: { Contact }): (number, number)
	local own = ownSet(a)
	local joints = cutExternalJoints(a.pieces, own) + cutExternalJoints(a.followers, own)
	local count = 0
	for _, c in ipairs(contacts) do
		if count >= CFG.OverlapFilterMax then break end
		-- Spadająca grupa (w locie albo w kolejce) pod nią albo na niej: jadą razem.
		if isBelow(c.box, c.hitBox, c.o) or isAbove(c.box, c.hitBox, c.o) then
			local contact = (c.hitBox.min:Max(c.box.min) + c.hitBox.max:Min(c.box.max)) * 0.5
			if isFallingPiece(c.hit, contact) then continue end
		end
		local nc = Instance.new("NoCollisionConstraint")
		nc.Part0 = c.part
		nc.Part1 = c.hit
		nc.Parent = c.part
		table.insert(a.filters, nc)
		count += 1
	end
	local root = a.root :: BasePart
	-- Pchnięcie w dół budzi bryłę — uśpiona nie zauważy, że zniknęło to, co ją trzymało.
	root.AssemblyLinearVelocity = Vector3.new(0, -CFG.FallSpeed, 0)
	a.unstuck = true
	a.startCF = root.CFrame
	a.stillSince = nil
	a.jamCheckAt = os.clock() + CFG.JamCheckTime
	return joints, count
end

-- Stopień 2: upadek u klientów.
local function jam(a: Active, moved: number, holders: string)
	local mn, mx = groupBox(a)
	finishFlight(a)
	local list: { Instance } = {}
	local function take(p: BasePart)
		if p.Parent then
			-- Kolizja odchodzi OD RAZU: to, co leżało na tej grupie, ma ruszyć teraz,
			-- a nie po opóźnieniu przekazania (klient i tak animuje własną kopię).
			Utils.anchorAtRest(p)
			p.CanCollide = false
			flyingOf[p] = nil
			table.insert(list, p)
		end
	end
	for _, p in ipairs(a.pieces) do
		take(p)
	end
	for _, f in ipairs(a.followers) do
		take(f)
	end
	for _, nc in ipairs(a.filters) do
		nc:Destroy()
	end
	table.clear(a.filters)
	handOffNow(list, a.center, false)
	a.rec.state:retire(a.def.chunkIds)
	a.phase = "Gone"
	a.jamCheckAt = nil
	flagRubbleNear(mn, mx)
	log("%s: grupa %s ZAKLINOWANA mimo odblokowania (ruch %.2f stud w %.2f s), trzyma: %s — upadek u klientów",
		a.rec.id, a.def.groupId, moved, os.clock() - a.releasedAt, holders)
end

-- Sprawdza grupy, którym minął `JamCheckTime` — od najniższej, bo górna mogła leżeć na dolnej:
-- dolna odblokowana w tym samym przebiegu dostaje nowe okno, a górna na niej czeka
-- (`restsOnFalling`) zamiast iść osobno do siatki.
local function checkJams(now: number)
	local due: { Active } = {}
	for _, a in ipairs(flying) do
		if a.jamCheckAt and now >= a.jamCheckAt and a.root and a.root.Parent then
			table.insert(due, a)
		end
	end
	if #due == 0 then return end
	table.sort(due, function(x, y)
		return (x.root :: BasePart).Position.Y < (y.root :: BasePart).Position.Y
	end)
	for _, a in ipairs(due) do
		if not a.jamCheckAt or now < a.jamCheckAt then continue end -- przesunięta przez wcześniejsze zaklinowanie
		-- Ruch = przesunięcie ALBO obrót: ściana, która zaczyna się przewracać na zawiasie,
		-- przez pierwsze ułamki sekundy prawie nie obniża środka, a nie jest zaklinowana.
		local cf = (a.root :: BasePart).CFrame
		local moved = (cf.Position - a.startCF.Position).Magnitude
		local _, angle = a.startCF:ToObjectSpace(cf):ToAxisAngle()
		if moved >= CFG.JamMinMove or math.abs(angle) >= CFG.JamMinAngle then
			a.jamCheckAt = nil -- ruszyła: dalej zwykłe osiadanie
			continue
		end
		-- Nie ruszyła, bo już leży na gruncie (spadła o mniej niż JamMinMove) — osiada.
		local ground = groundUnder(a, moved)
		if ground then
			a.jamCheckAt = nil
			log("%s: grupa %s wylądowała (ruch %.2f stud) na: %s", a.rec.id, a.def.groupId, moved, ground)
			settle(a)
			continue
		end
		local contacts = contactsOf(a)
		-- MaxFallTime: sufit czekania — łańcuch, który się nie rozwiązuje, idzie dalej siatką.
		if restsOnFalling(contacts) and now - a.releasedAt < CFG.MaxFallTime then
			a.jamCheckAt = now + CFG.JamCheckTime
			a.startCF = cf
			continue
		end
		local holders = holdersOf(a, contacts)
		if not a.unstuck then
			local joints, filters = unstick(a, contacts)
			log("%s: grupa %s ODBLOKOWANA (ruch %.2f stud w %.2f s, spoiny %d, filtry %d), trzymało: %s",
				a.rec.id, a.def.groupId, moved, now - a.releasedAt, joints, filters, holders)
			continue
		end
		-- Kolizja zaklinowanej zaraz zniknie — nowe okno dostają TYLKO grupy, które jej dotykały
		-- (leżały na niej albo ją podpierały). Do 29.09 dostawała je każda grupa w locie, także
		-- w innym budynku: przy kilku kolapsach naraz naprawdę zaklinowana czekała kolejne
		-- JamCheckTime po każdym cudzym zaklinowaniu (przegląd 29.09, M-6).
		local touching: { [Active]: boolean } = {}
		for _, c in ipairs(contacts) do
			local g = flyingOf[c.hit]
			if g and g ~= a then
				touching[g] = true
			end
		end
		jam(a, moved, holders)
		for other in pairs(touching) do
			if other.jamCheckAt and other.root and other.root.Parent then
				other.jamCheckAt = now + CFG.JamCheckTime
				other.startCF = other.root.CFrame
				other.stillSince = nil
			end
		end
	end
end

-- ============================================================================
-- Osiadła bryła bez oparcia (29.09, M-1) i budzenie (M-4)
-- ============================================================================

-- Budzi osiadłą grupę: znowu fizyka serwera. Jedno miejsce dla budzenia wybuchem (z impulsem)
-- i budzenia bez oparcia (bez impulsu). Silnik wypycha budzoną bryłę z geometrii, w którą jest
-- wbita — od 28.09 grupa „spada od razu” przez stojące belki i listwy, więc może osiąść,
-- przenikając belkę — i bez limitu wystrzeliwał ją jak z procy. Filtr kolizji tu nie pomoże:
-- pudełka świata obróconego rumowiska nie odróżniają „wbita” od „leży”, a filtr na tym, na
-- czym leży, puściłby ją przez podłogę. Dlatego przez WakeClampTime przycinamy prędkość w bok
-- i w górę do nadanej + zapas; w dół bez limitu — spadanie to grawitacja (przegląd 29.09, M-4).
local function wakeGroup(a: Active, linear: Vector3, angular: Vector3)
	local mn, mx = groupBox(a)
	unlistSettled(a)
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			rubbleOf[p] = nil
			flyingOf[p] = a
			p.Anchored = false
		end
	end
	for _, f in ipairs(a.followers) do
		if f.Parent then
			rubbleOf[f] = nil
			flyingOf[f] = a
			f.CanCollide = false
			f.Massless = true
			f.Anchored = false
		end
	end
	local root = a.root :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	root.AssemblyLinearVelocity = linear
	root.AssemblyAngularVelocity = angular
	a.clampUntil = os.clock() + CFG.WakeClampTime
	a.clampH = Vector3.new(linear.X, 0, linear.Z).Magnitude + CFG.WakeSpeedMargin
	a.clampUp = math.max(linear.Y, 0) + CFG.WakeSpeedMargin
	a.clampSpin = angular.Magnitude + CFG.WakeSpinMargin
	a.retireAt = nil
	a.held = nil
	a.phase = "Flying"
	a.releasedAt = os.clock()
	-- Obudzone rumowisko leży na ziemi — to, że nie spada, jest prawidłowe, nie zaklinowaniem.
	a.jamCheckAt = nil
	a.stillSince = nil
	used += a.cost
	table.insert(flying, a)
	-- To, co leżało na niej, traci oparcie, gdy ruszy.
	flagRubbleNear(mn, mx)
end

-- Limit prędkości budzonych brył (opis przy wakeGroup). Co klatkę — wypchnięcie z geometrii
-- dzieje się w jednym kroku fizyki, monitor 10 Hz by go nie złapał.
local function clampWakes(now: number)
	for _, a in ipairs(flying) do
		local untilT = a.clampUntil
		if not untilT then continue end
		if now >= untilT then
			a.clampUntil = nil
			continue
		end
		local root = a.root
		if not root or not root.Parent then continue end
		local v = root.AssemblyLinearVelocity
		local h = Vector3.new(v.X, 0, v.Z)
		local hm = h.Magnitude
		local limH = a.clampH or CFG.WakeSpeedMargin
		if hm > limH then
			h = h * (limH / hm)
		end
		local nv = Vector3.new(h.X, math.min(v.Y, a.clampUp or CFG.WakeSpeedMargin), h.Z)
		if nv ~= v then
			root.AssemblyLinearVelocity = nv
		end
		local w = root.AssemblyAngularVelocity
		local wm = w.Magnitude
		local limW = a.clampSpin or CFG.WakeSpinMargin
		if wm > limW then
			root.AssemblyAngularVelocity = w * (limW / wm)
		end
	end
end

-- Czy osiadła bryła ma na czym leżeć: pod DOLNĄ połową któregoś kawałka (ściana obok to nie
-- podparcie) jest coś zakotwiczonego z kolizją, co nie leci. Świadomie hojne: listwa i mebel
-- pod spodem też się liczą, bo fizycznie trzymają (M-3 dotyczy tylko lądowania). Pudełka świata
-- są otoczką obróconych kawałków, więc możliwa jest pomyłka „brak oparcia” — rozstrzyga ją
-- fizyka: bryła budzona bez impulsu, która się nie ruszy, jest trzymana (`held` w settle).
local function hasSupport(a: Active): boolean
	local own = ownSet(a)
	for _, list in ipairs({ a.pieces, a.followers }) do
		for _, p in ipairs(list) do
			if not p.Parent then continue end
			local b = Pieces.boxOf(p)
			local mid = (b.min.Y + b.max.Y) * 0.5
			for _, hit in ipairs(Workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.one * (CFG.JamProbe * 2))) do
				if own[hit] then continue end
				if hit:IsA("Terrain") then
					return true
				end
				if not hit.Anchored or not hit.CanCollide or flyingOf[hit] or isCharacterPart(hit) then continue end
				local hb = Pieces.boxOf(hit)
				if hb.max.Y > mid then continue end -- obok albo nad, nie pod
				local o = hb.max:Min(b.max) - hb.min:Max(b.min)
				if o.X > 0 and o.Z > 0 then
					return true
				end
			end
		end
	end
	return false
end

-- Bez oparcia i bez miejsca w budżecie przez MaxQueueWait — upadek u klientów, jak grupa ponad
-- budżetem: nic nie wisi w powietrzu (kontrakt 15).
local function dropToClients(a: Active)
	local mn, mx = groupBox(a)
	local list: { Instance } = {}
	for _, l in ipairs({ a.pieces, a.followers }) do
		for _, p in ipairs(l) do
			if p.Parent then
				rubbleOf[p] = nil
				table.insert(list, p)
			end
		end
	end
	unlistSettled(a)
	handOffNow(list, a.center, false)
	a.rec.state:retire(a.def.chunkIds)
	a.phase = "Gone"
	flagRubbleNear(mn, mx)
	log("%s: grupa %s bez oparcia, brak miejsca w budżecie — upadek u klientów", a.rec.id, a.def.groupId)
end

local function wakeUnsupported(a: Active, now: number)
	if a.phase ~= "Settled" or not a.root or not a.root.Parent then return end
	a.priority = 2
	if not fits(a) then
		a.unsupportedSince = a.unsupportedSince or now
		if now - (a.unsupportedSince :: number) >= CFG.MaxQueueWait then
			dropToClients(a)
		else
			a.recheck = true -- czeka na budżet jak grupa w kolejce
		end
		return
	end
	a.unsupportedSince = nil
	a.recheckWakeCF = (a.root :: BasePart).CFrame
	wakeGroup(a, Vector3.zero, Vector3.zero)
	log("%s: grupa %s bez oparcia — spada", a.rec.id, a.def.groupId)
end

-- Najpierw bryły oflagowane zdarzeniem (flagRubbleNear), potem po kolei w tle — łapie też to,
-- czego żadne zdarzenie nie zgłosi (np. uśpiony gruz DebrisService wycofany budżetem).
local function recheckSettled(now: number)
	local n = #settledAll
	if n == 0 then return end
	local budget = CFG.RubbleRecheckPerTick
	local toWake: { Active } = {}
	local function check(a: Active)
		budget -= 1
		a.recheck = nil
		a.supportCheckedAt = now
		if not a.root or not a.root.Parent then return end
		if hasSupport(a) then
			a.unsupportedSince = nil
		else
			table.insert(toWake, a)
		end
	end
	for _, a in ipairs(settledAll) do
		if budget <= 0 then break end
		if a.recheck then
			check(a)
		end
	end
	for _ = 1, n do
		if budget <= 0 then break end
		recheckCursor = recheckCursor % n + 1
		local a = settledAll[recheckCursor]
		if not a.held and now - (a.supportCheckedAt or 0) >= CFG.RubbleRecheckInterval then
			check(a)
		end
	end
	for _, a in ipairs(toWake) do
		wakeUnsupported(a, now)
	end
end

local function monitor(now: number)
	local lava = LavaService.getSurfaceY()
	checkJams(now)
	for i = #flying, 1, -1 do
		local a = flying[i]
		local root = a.root
		if not root or not root.Parent then
			finishFlight(a)
			destroyGroup(a)
			continue
		end
		if groupTop(a) < lava - CFG.LavaCullMargin then
			finishFlight(a)
			destroyGroup(a)
			log("%s: grupa %s zatonęła w lawie", a.rec.id, a.def.groupId)
			continue
		end
		local slow = root.AssemblyLinearVelocity.Magnitude < CFG.SettleSpeed
			and root.AssemblyAngularVelocity.Magnitude < CFG.SettleSpeed * 0.5
		if slow then
			a.stillSince = a.stillSince or now
		else
			a.stillSince = nil
		end
		-- Grupa czekająca na sprawdzenie zaklinowania nie osiada w miejscu — inaczej
		-- zaklinowana zostałaby zakotwiczona w powietrzu, zanim ktokolwiek to zauważy.
		if a.jamCheckAt == nil then
			local calm = a.stillSince ~= nil and now - (a.stillSince :: number) >= CFG.SettleTime
			if calm or now - a.releasedAt >= CFG.MaxFallTime then
				settle(a, not calm)
			end
		end
	end
	for i = #settledTemp, 1, -1 do
		local a = settledTemp[i]
		if a.phase ~= "Settled" then
			table.remove(settledTemp, i)
		elseif (a.retireAt or math.huge) <= now or groupTop(a) < lava - CFG.LavaCullMargin then
			table.remove(settledTemp, i)
			destroyGroup(a)
		end
	end
	recheckSettled(now)
end

-- ============================================================================
-- Pętla
-- ============================================================================

local function step()
	for _, f in ipairs(StructuralService.flushAll()) do
		local result = f.result
		local cause = if result.plan then result.plan.cause else nil
		local darkened = table.clone(result.damaged)
		for _, id in ipairs(result.destroyed) do
			local rt = f.rec.state.rt[id]
			if rt.reason == "Crumbled" then
				crumble(f.rec, id, rt.cause or cause)
			else
				table.insert(darkened, id)
			end
		end
		if #darkened > 0 then
			darken(f.rec, darkened)
		end
		if result.plan then
			enqueue(f.rec, result.plan)
		end
	end

	-- Kolejka w ustalonej kolejności (jeźdźcy, bliskie, od dołu). Grupa bez miejsca CZEKA,
	-- aż osiadające grupy zwolnią budżet — dopiero po MaxQueueWait upadek przejmują klienci
	-- (test 24.09: natychmiastowe oddawanie klientom = górne piętra po prostu znikały).
	local now = os.clock()
	local released = 0
	while #queue > 0 and released < CFG.MaxReleasesPerFrame do
		local a = queue[1]
		if fits(a) then
			table.remove(queue, 1)
			if release(a) then
				released += 1
			end
		elseif now - a.queuedAt >= CFG.MaxQueueWait then
			table.remove(queue, 1)
			degrade(a)
		else
			break
		end
	end

	clampWakes(now)

	local period = 1 / CFG.MonitorHz
	if now - lastMonitor >= period then
		lastMonitor = now
		monitor(now)
	end
end

-- ============================================================================
-- API dla DestructionService: zatrzymany gruz kolapsu budzi się od kolejnego wybuchu
-- ============================================================================

function CollapseService.isRubble(part: BasePart): boolean
	return rubbleOf[part] ~= nil
end

function CollapseService.isFlying(part: BasePart): boolean
	return flyingOf[part] ~= nil
end

-- Wybuch przy leżącej bryle: odkotwiczamy ją i pchamy falą (jeśli budżet pozwala).
-- Zwraca true, gdy bryła poleciała.
function CollapseService.wakeRubble(part: BasePart, center: Vector3, radius: number, impulse: number, minT: number): boolean
	local a = rubbleOf[part]
	if not a or a.phase ~= "Settled" or not a.root or not a.root.Parent then
		return false
	end
	a.priority = 2
	if not fits(a) then
		return false
	end
	local root = a.root :: BasePart
	local d = Fracture.boxSurfaceDistance(Vector3.zero, root.Size, root.CFrame:PointToObjectSpace(center))
	-- Mniejszy odrzut niż dla gruzu (decyzja Kacpra 25.09): pełny impuls wyrzucał leżącą bryłę
	-- 72 stud/s na 45 studów („umieram i nie wiem od czego”).
	local linear, angular = Shockwave.velocity(root.Position, root.Size, center, d, radius, impulse * CFG.WakeImpulseFactor, minT, Random.new())
	a.recheckWakeCF = nil
	wakeGroup(a, linear, angular)
	return true
end

-- Bryła W LOCIE trafiona kolejnym wybuchem (M-2, decyzja Kacpra 29.09): odrzut ×WakeImpulseFactor
-- jak obudzone rumowisko, liczony z KORZENIA (największego kawałka — nie z trafionego kikuta)
-- i DODANY do prędkości: spadające piętro dalej spada, tylko lekko popchnięte. Do 29.09 szła
-- przez zwykłe odpychanie DestructionService, które USTAWIAŁO prędkość całej spawanej bryły
-- z rozmiaru trafionego kawałka — mały kikut dawał pełny impuls i piętro wylatywało.
-- Raz na bryłę na wybuch.
function CollapseService.pushFlying(parts: { BasePart }, center: Vector3, radius: number, impulse: number, minT: number)
	local done: { [Active]: boolean } = {}
	for _, part in ipairs(parts) do
		local a = flyingOf[part]
		if not a or done[a] or a.phase ~= "Flying" then continue end
		done[a] = true
		local root = a.root
		if not root or not root.Parent then continue end
		local d = Fracture.boxSurfaceDistance(Vector3.zero, root.Size, root.CFrame:PointToObjectSpace(center))
		local linear, angular = Shockwave.velocity(root.Position, root.Size, center, d, radius, impulse * CFG.WakeImpulseFactor, minT, Random.new())
		root.AssemblyLinearVelocity += linear
		root.AssemblyAngularVelocity += angular
	end
end

-- Wybuch w tym miejscu — osiadłe bryły w zasięgu sprawdzą oparcie (M-1): dziura w stropie,
-- zbudzony gruz albo mebel spod spodu nie zgłaszają się tu same.
function CollapseService.noteBlast(center: Vector3, radius: number)
	local r = Vector3.one * radius
	flagRubbleNear(center - r, center + r)
end

-- ============================================================================
-- Cięcie leżącego rumowiska (decyzja Kacpra 25.09: „bomba tnie leżącą bryłę jak ścianę”)
-- ============================================================================
-- Wcześniej wybuch tylko budził i pchał leżące bryły — duża platforma ledwo drgnęła i dla
-- gracza wyglądało to tak, że bomba „przestała rozwalać” budynek po zawaleniu. Teraz ta sama
-- dziura-prostokąt co w konstrukcji (Fracture.planWindow, kawałki dziury u klientów),
-- a potem zwykłe `wakeRubble` z DestructionService — resztki osiadają tam, gdzie da fizyka.

-- Spawy grupy od nowa: przycięty kawałek ma inny rozmiar i środek, a spawu ze starym
-- przesunięciem nie przesuwamy (przestawienie CFrame spawanego parta ciągnie za sobą bryłę).
-- Korzeń = największy kawałek. Martwe kawałki wypadają z list.
local function reweld(a: Active)
	local pieces: { BasePart } = {}
	for _, p in ipairs(a.pieces) do
		if p.Parent then
			table.insert(pieces, p)
		end
	end
	local followers: { BasePart } = {}
	for _, f in ipairs(a.followers) do
		if f.Parent then
			table.insert(followers, f)
		end
	end
	a.pieces, a.followers = pieces, followers
	for _, list in ipairs({ pieces, followers }) do
		for _, p in ipairs(list) do
			for _, j in ipairs(p:GetJoints()) do
				if j:IsA("WeldConstraint") then
					j:Destroy()
				end
			end
		end
	end
	if #pieces == 0 then
		-- Z bryły nic nie zostało — jej listwy nie mogą zostać w powietrzu.
		for _, f in ipairs(followers) do
			rubbleOf[f] = nil
		end
		handOffNow(followers, a.center, false)
		unlistSettled(a)
		a.rec.state:retire(a.def.chunkIds)
		a.root = nil
		a.phase = "Gone"
		if a.restMin and a.restMax then
			flagRubbleNear(a.restMin, a.restMax) -- to, co leżało na niej, traci oparcie
		end
		return
	end
	table.sort(pieces, function(x, y)
		local sx, sy = x.Size, y.Size
		return sx.X * sx.Y * sx.Z > sy.X * sy.Y * sy.Z
	end)
	local root = pieces[1]
	a.root = root
	for _, list in ipairs({ pieces, followers }) do
		for _, p in ipairs(list) do
			if p ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
		end
	end
end

-- Dziura w leżącym kawałku. Zwraca payload dla klientów (ten sam format co dziura v4 —
-- `win` = prostokąt zabrany z kolizji) i żywy kawałek grupy do obudzenia, albo nil, gdy
-- wybuch kawałka nie sięga albo to nie jest leżące rumowisko.
function CollapseService.cutRubble(part: BasePart, center: Vector3, holeRadius: number, feetWorld: { Vector3 }): ({ [string]: any }?, BasePart?)
	local a = rubbleOf[part]
	if not a or a.phase ~= "Settled" then
		return nil, nil
	end
	local cf, size = part.CFrame, part.Size
	local lc = cf:PointToObjectSpace(center)
	local plan = Fracture.planWindow(size, lc, holeRadius, Config.Structure.Damage.MinStrip)
	local hole = plan.hole
	if not hole then
		return nil, nil
	end
	local payload = {
		cf = cf,
		size = size,
		lc = lc,
		hole = holeRadius,
		seed = rng:NextInteger(1, 2_000_000_000),
		win = { offset = hole.offset, size = hole.size },
		color = part.Color,
		mat = part.Material,
		var = part.MaterialVariant,
		tr = part.Transparency,
	}
	-- Spawy tego kawałka PRZED zmianą rozmiaru i pozycji (reweld postawi je od nowa).
	for _, j in ipairs(part:GetJoints()) do
		if j:IsA("WeldConstraint") then
			j:Destroy()
		end
	end
	local isFollower = table.find(a.followers, part) ~= nil
	local rem = plan.remnants
	if #rem == 0 then
		rubbleOf[part] = nil
		part:Destroy()
	else
		-- Oryginał zostaje resztką pod graczami, nowe resztki powstają obok (fix przenikania).
		local reuse = Pieces.pickReuse(rem, cf, feetWorld)
		for i, box in ipairs(rem) do
			if i ~= reuse then
				local piece = Pieces.spawn(part, cf * CFrame.new(box.offset), box.size)
				piece.CustomPhysicalProperties = part.CustomPhysicalProperties
				rubbleOf[piece] = a
				table.insert(if isFollower then a.followers else a.pieces, piece)
			end
		end
		part.Size = rem[reuse].size
		part.CFrame = cf * CFrame.new(rem[reuse].offset)
	end
	reweld(a)
	if a.phase == "Settled" then
		a.restMin, a.restMax = groupBox(a)
	end
	return payload, a.root
end

local function clearAll()
	-- Kawałki sprząta MapService (są w mapie) — tu tylko rejestry i budżet.
	table.clear(queue)
	table.clear(flying)
	table.clear(settledTemp)
	table.clear(settledAll)
	recheckCursor = 0
	table.clear(rubbleOf)
	table.clear(flyingOf)
	used = 0
end

function CollapseService.init(injected: Injected)
	deps = injected
	RunService.Heartbeat:Connect(step)
	GameLoopService.RoundEnded:Connect(clearAll)
end

return CollapseService
