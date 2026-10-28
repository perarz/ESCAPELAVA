--!strict
-- DebrisService.luau
-- Cykl życia gruzu serwerowego (system destrukcji v2 — DESTRUCTION_PLAN.md; etap 1+3).
-- JEDYNY właściciel rejestru gruzu. DestructionService tworzy kawałki i je tu rejestruje,
-- dalej dzieje się:
--   - izolacja kolizji gruz↔gruz przez SelfCollisionTime — party dostające prędkość w tej
--     samej klatce natychmiast wchodzą w kontakt i solver zjada im pęd (objaw ze starego
--     systemu: "bliskie ledwo drgnęły, dalsze poleciały")
--   - właściwości betonu (density/friction/elasticity) — bez nich gruz odbija się jak guma
--   - usypianie: kawałek nieruchomy przez SleepTime → Anchored = chodliwa platforma za
--     zero fizyki i zero ruchu sieciowego; kolejny wybuch budzi (wake)
--   - FALL-FRACTURE (etap 3): kawałek który twardo uderzył (nagła delta prędkości) pęka
--     na 2-3 mniejsze + pył. TWARDY limit jednej generacji i floor rozmiaru — bez tego
--     liczba partów rośnie wykładniczo
--   - (29.09) gruz NIE rani — przygniecenie usunięte decyzją Kacpra („usuwamy obrażenia od
--     spadającego gruzu”); wcześniej duży, szybki kawałek zadawał obrażenia z kill creditem
--   - sprzątanie całości na RoundEnded
--
-- Gruz żyje w Workspace.BlastDebris (POZA Workspace.Map) — MapService restore go nie widzi,
-- sprzątamy go sami. Anchored remnants ścian zostają w Map i sprząta je restore.
--
-- v3 (2026-09-23): trafia tu już TYLKO duży gruz — płyty, które straciły podparcie,
-- i duże bryły wyrzucone w całości (najwyżej `MaxServerPiecesPerBlast` na wybuch).
-- Kawałki dziur i drobnica są animowane u klientów (DestructionService → DebrisFall /
-- BlastFX), bo replikacja pozycji setek ruchomych partów do każdego gracza była głównym
-- źródłem lagów przy kilku bombach naraz. (Kliencki gruz nie ma kolizji w ogóle —
-- patrz DebrisFXController — więc nie potrzebuje stąd żadnych grup kolizji.)

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxDebris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerService = require(script.Parent.PlayerService)
local LavaService = require(script.Parent.LavaService)

local DebrisService = {}

local DBR = Config.Destruction.Debris
local IMP = Config.Destruction.Impact
local FRAC = Config.Destruction.Fracture

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Entry = {
	restoreAt: number,      -- os.clock() przywrócenia collision group; 0 = już przywrócona
	stillSince: number?,    -- od kiedy nieprzerwanie poniżej progu prędkości (nil = w ruchu)
	asleep: boolean,        -- true = zakotwiczony jako leżąca platforma
	generation: number,     -- 0 = z wybuchu; 1 = z fall-fracture (dalej NIE pęka)
	lastVelocity: Vector3?, -- prędkość z poprzedniego ticku skanu (detekcja uderzeń)
	-- --- cykl życia (przebudowa 2026-09-13) ---
	persistent: boolean,    -- true = dość duży, żeby zostać platformą; false = drobnica
	bornAt: number,         -- os.clock() rejestracji (FIFO + twardy sufit wieku drobnicy)
	seq: number,            -- rosnący numer rejestracji — stabilne "kto starszy"
	expireAt: number,       -- os.clock() wycofania; 0 = nie wygasa (jeszcze leci / platforma)
	supportCheckedAt: number, -- ostatnia re-weryfikacja podparcia uśpionego kawałka
}

-- Klucz = instancja — dwa wybuchy w to samo miejsce w tej samej klatce nie robią duplikatów.
local registry: { [BasePart]: Entry } = {}
-- Liczniki trzymane inkrementalnie (reserve() pyta o nie MIĘDZY skanami) i przeliczane
-- autorytatywnie w każdym skanie, żeby nie zdryfowały.
local movingCount = 0
local totalCount = 0
local persistentCount = 0
local seqCounter = 0

local folder: Folder? = nil
local initialized = false
local groupAvailable = false

local rng = Random.new()

local DEBRIS_PROPERTIES = PhysicalProperties.new(
	DBR.Density,
	DBR.Friction,
	DBR.Elasticity,
	DBR.FrictionWeight,
	DBR.ElasticityWeight
)

-- ============================================================================
-- Collision group
-- ============================================================================

local function ensureCollisionGroup()
	if groupAvailable or DBR.SelfCollisionTime <= 0 then return end
	-- RegisterCollisionGroup rzuca gdy grupa już istnieje — to nie jest błąd, więc pcall.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(DBR.CollisionGroup)
	end)
	-- Gruz nie koliduje z gruzem; ze światem i graczami dalej tak. Gdyby limit 32 grup był
	-- wyczerpany — degradacja po cichu do zachowania bez izolacji.
	local ok = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(DBR.CollisionGroup, DBR.CollisionGroup, false)
	end)
	if ok then
		groupAvailable = true
	else
		warn("[Debris] nie udało się zarejestrować collision group — gruz będzie kolidował sam ze sobą")
	end
end

-- ============================================================================
-- Public API
-- ============================================================================

function DebrisService.getFolder(): Folder
	local f = folder
	if f and f.Parent then return f end
	local existing = Workspace:FindFirstChild("BlastDebris")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local new = Instance.new("Folder")
	new.Name = "BlastDebris"
	new.Parent = Workspace
	folder = new
	return new
end

function DebrisService.getMovingCount(): number
	return movingCount
end

-- Wszystko w rejestrze: w locie + uśpione platformy. TO jest liczba, która decyduje
-- o obciążeniu (uśpiony part nie kosztuje fizyki, ale dalej kosztuje render, pamięć
-- i replikację) — stary `MaxMovingDebris` liczył tylko ruchome i dlatego nie ograniczał
-- niczego: kawałek po zaśnięciu zwalniał budżet, a suma rosła do końca rundy.
function DebrisService.getTotalCount(): number
	return totalCount
end

function DebrisService.isRegistered(part: BasePart): boolean
	return registry[part] ~= nil
end

-- ============================================================================
-- Wycofywanie gruzu (budżet + wygasanie drobnicy)
-- ============================================================================

local function unregister(part: BasePart, entry: Entry)
	registry[part] = nil
	totalCount -= 1
	if entry.asleep then
		if entry.persistent then persistentCount -= 1 end
	else
		movingCount -= 1
	end
end

-- Wycofanie kawałka: półprzezroczystość + zdjęcie kolizji, Destroy po RetireFade.
-- Nie tweenujemy per-klatkę — tween na serwerze replikuje właściwość co klatkę, a tu
-- wycofujemy nawet kilkadziesiąt partów naraz. Dwa zapisy i Debris:AddItem wystarczą,
-- żeby kawałek zgasł zamiast zniknąć "pyknięciem".
local function retire(part: BasePart, entry: Entry)
	unregister(part, entry)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = math.max(part.Transparency, 0.6)
	RobloxDebris:AddItem(part, DBR.RetireFade)
end

-- Czy w pobliżu kawałka stoi żywy gracz. Platformy spod nóg nie kasujemy — znikająca
-- platforma to niezawiniona śmierć w lawie (zasada "gracz nie może być wkurzony").
local function playerNearby(position: Vector3, playerPositions: { Vector3 }): boolean
	for _, playerPosition in ipairs(playerPositions) do
		if (playerPosition - position).Magnitude <= DBR.RetireSafeDistance then
			return true
		end
	end
	return false
end

-- Zwalnia `needed` miejsc w rejestrze kasując NAJSTARSZY gruz. Kolejność ofiar:
-- najpierw drobnica, potem platformy; w obrębie klasy — od najstarszej.
local function makeRoom(needed: number): number
	if needed <= 0 then return 0 end

	-- Ten przebieg nie yielduje: pozycje graczy są wspólne dla wszystkich kandydatów,
	-- ale nie przechodzą do kolejnego wybuchu ani skanu.
	local playerPositions: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerService.isAlive(player) then continue end
		local root = Utils.getRoot(player)
		if root then table.insert(playerPositions, root.Position) end
	end
	local candidates: { { part: BasePart, entry: Entry } } = {}
	for part, entry in pairs(registry) do
		if not part.Parent then continue end
		if entry.asleep and playerNearby(part.Position, playerPositions) then continue end
		table.insert(candidates, { part = part, entry = entry })
	end
	table.sort(candidates, function(a, b)
		if a.entry.persistent ~= b.entry.persistent then
			return b.entry.persistent -- drobnica (false) idzie pierwsza
		end
		return a.entry.seq < b.entry.seq
	end)

	local freed = 0
	for _, c in ipairs(candidates) do
		if freed >= needed then break end
		retire(c.part, c.entry)
		freed += 1
	end
	return freed
end

-- Rezerwacja miejsca pod świeży wybuch. Decyzja Kacpra 2026-09-13: przy pełnym budżecie
-- ustępuje STARY gruz, a nowy wybuch jest zawsze pełny — bomba za 50$, która "nic nie
-- zrobiła", wkurza bardziej niż zniknięcie gruzu sprzed pół minuty.
-- Zwraca ile kawałków realnie wolno stworzyć.
function DebrisService.reserve(want: number): number
	local room = DBR.MaxTotalDebris - totalCount
	if room < want then
		makeRoom(want - room)
		room = DBR.MaxTotalDebris - totalCount
	end
	return math.clamp(math.min(want, room), 0, want)
end

-- Rejestruje ŚWIEŻY kawałek gruzu: właściwości betonu, izolacja kolizji, server authority.
-- Caller (DestructionService / fall-fracture) odpowiada za Parent, CFrame i prędkości.
function DebrisService.register(part: BasePart, generation: number?)
	if registry[part] then
		DebrisService.wake(part)
		return
	end

	-- Twardy sufit także dla callerów, którzy nie wołali reserve() — rejestr nie może
	-- rosnąć w nieskończoność. Zwalniamy PACZKĘ (~10% budżetu), nie jeden part: makeRoom
	-- sortuje cały rejestr, a v2 wołał go przy KAŻDEJ rejestracji ponad limitem — przy
	-- wybuchu, który zrzucił 472 party, to było 212 pełnych sortowań w jednej klatce.
	if totalCount >= DBR.MaxTotalDebris then
		makeRoom(math.max(1, math.floor(DBR.MaxTotalDebris * 0.1)))
	end

	part.CustomPhysicalProperties = DEBRIS_PROPERTIES
	-- Server authority — bez tego Roblox oddaje ownership najbliższemu graczowi i exploiter
	-- może flingować kawałkami mapy. pcall bo rzuca dla anchored.
	pcall(function()
		part:SetNetworkOwner(nil)
	end)

	local restoreAt = 0
	if groupAvailable and DBR.SelfCollisionTime > 0 then
		part.CollisionGroup = DBR.CollisionGroup
		restoreAt = os.clock() + DBR.SelfCollisionTime
	end

	local size = part.Size
	seqCounter += 1
	registry[part] = {
		restoreAt = restoreAt,
		stillSince = nil,
		asleep = false,
		generation = generation or 0,
		lastVelocity = nil,
		-- Klasa kawałka rozstrzygana RAZ, przy rejestracji: duży = kandydat na platformę,
		-- mały = drobnica z terminem ważności. Jedno miejsce, więc gruz z wybuchu,
		-- z fall-fracture i z kolapsu sekcji podlegają tej samej regule.
		persistent = (size.X * size.Y * size.Z) >= DBR.PlatformMinVolume,
		bornAt = os.clock(),
		seq = seqCounter,
		expireAt = 0,
		supportCheckedAt = 0,
	}
	totalCount += 1
	movingCount += 1
end

-- Budzenie znanego gruzu trafionego kolejnym wybuchem: odkotwiczenie uśpionej platformy
-- + świeże okno izolacji kolizji.
function DebrisService.wake(part: BasePart)
	local entry = registry[part]
	if not entry then return end

	if entry.asleep then
		part.Anchored = false
		entry.asleep = false
		if entry.persistent then persistentCount -= 1 end
		movingCount += 1
	end
	entry.stillSince = nil
	entry.expireAt = 0 -- termin ważności drobnicy liczy się od ZAŚNIĘCIA, nie od spawnu

	if groupAvailable and DBR.SelfCollisionTime > 0 then
		part.CollisionGroup = DBR.CollisionGroup
		entry.restoreAt = os.clock() + DBR.SelfCollisionTime
	end
end

-- ============================================================================
-- Fall-fracture (etap 3): twarde uderzenie → kawałek pęka na mniejsze
-- ============================================================================

-- Throttle dźwięków uderzeń (etap 5): przy kolapsie piętra ląduje naraz 200 kawałków —
-- bez limitu to ściana szumu i zjazd FPS. Dźwięk jedzie na anchorze pyłu (server-side
-- instancja replikuje się sama), więc nie potrzebuje własnego remote'a.
local impactSoundBudget = 0
local impactSoundWindow = 0

local function tryImpactSound(anchor: BasePart)
	local FX = Config.Destruction.FX
	if FX.ImpactSoundId == "" then return end
	local now = os.clock()
	if now - impactSoundWindow >= 1 then
		impactSoundWindow = now
		impactSoundBudget = 0
	end
	if impactSoundBudget >= FX.ImpactSoundsPerSecond then return end
	impactSoundBudget += 1

	local sound = Instance.new("Sound")
	sound.SoundId = FX.ImpactSoundId
	sound.Volume = 0.7
	sound.PlaybackSpeed = rng:NextNumber(0.9, 1.15) -- rozstrojenie: 6 identycznych = robot
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 180
	sound.Parent = anchor
	sound:Play()
end

local function spawnImpactDust(position: Vector3, volume: number)
	if volume < IMP.DustMinVolume then return end
	local anchor = Instance.new("Part")
	anchor.Name = "ImpactDustFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	RobloxDebris:AddItem(anchor, 1.5)

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(175, 162, 140), Color3.fromRGB(125, 116, 102))
	dust.Size = NumberSequence.new(1.5, 4.5)
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Rate = 0
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Speed = NumberRange.new(4, 10)
	dust.Acceleration = Vector3.new(0, -4, 0)
	dust.Parent = anchor
	dust:Emit(12)

	tryImpactSound(anchor)
end

-- Pęknięcie kawałka przy twardym uderzeniu. Jedna generacja, floor rozmiaru — patrz Config.
local function fractureOnImpact(part: BasePart, entry: Entry)
	local size = part.Size
	local volume = size.X * size.Y * size.Z

	local pieces = Fracture.slice(
		size,
		math.max(size.X, size.Y, size.Z) * 0.55, -- target: ~połówki/trzecie części
		FRAC.MinChunkSize,
		IMP.FracturePieces,
		rng
	)
	if #pieces <= 1 then
		return -- za mały żeby sensownie pęknąć
	end

	local sourceCF = part.CFrame
	local velocity = part.AssemblyLinearVelocity * IMP.InheritVelocityFactor
	local gen = entry.generation + 1
	local parentFolder = DebrisService.getFolder()

	for _, piece in ipairs(pieces) do
		local p = Instance.new("Part")
		p.Name = "BlastChunk"
		p.Size = piece.size * FRAC.ChunkShrink
		local rj = math.rad(FRAC.ChunkRotJitter)
		p.CFrame = (sourceCF * CFrame.new(piece.offset)) * CFrame.Angles(
			rng:NextNumber(-rj, rj),
			rng:NextNumber(-rj, rj),
			rng:NextNumber(-rj, rj)
		)
		Utils.copyAppearance(part, p)
		p.Anchored = false
		p.CanCollide = true
		p.Parent = parentFolder
		DebrisService.register(p, gen)
		p.AssemblyLinearVelocity = velocity + Vector3.new(
			rng:NextNumber(-1, 1),
			rng:NextNumber(0, 0.6),
			rng:NextNumber(-1, 1)
		) * IMP.SpreadSpeed
		p.AssemblyAngularVelocity = Vector3.new(
			rng:NextNumber(-4, 4),
			rng:NextNumber(-4, 4),
			rng:NextNumber(-4, 4)
		)
	end

	spawnImpactDust(part.Position, volume)
	unregister(part, entry)
	part:Destroy()
end

-- ============================================================================
-- Skan (SleepCheckHz): przywracanie kolizji + usypianie + detekcja uderzeń
-- ============================================================================

local function restoreGroup(part: BasePart, entry: Entry)
	if entry.restoreAt == 0 then return end
	entry.restoreAt = 0
	if groupAvailable and part.Parent then
		part.CollisionGroup = "Default"
	end
end

-- ============================================================================
-- Podparcie uśpionego gruzu (fix "party anchorują się w powietrzu", 2026-09-13)
-- ============================================================================

-- Uśpiony kawałek to Anchored part POZA passem podparcia DestructionService (ten jawnie
-- pomija wszystko z rejestru gruzu). Bez własnego sprawdzenia floater wisi do końca rundy:
-- wystarczy, że podpora zostanie wysadzona, wycofana przez budżet albo zalana lawą.
-- Dlatego: (1) nie kotwiczymy kawałka, który nie ma nic pod sobą, (2) cyklicznie
-- re-weryfikujemy śpiące — jedno proste sprawdzenie łapie WSZYSTKIE przyczyny utraty
-- podparcia, bez budowania grafu "kto na kim leży".
local supportParams = RaycastParams.new()
supportParams.FilterType = Enum.RaycastFilterType.Exclude
supportParams.IgnoreWater = true
-- Dekoracja bez kolizji nie jest podporą — gracz i tak przez nią przeleci.
supportParams.RespectCanCollide = true

local function hasGroundSupport(part: BasePart): boolean
	-- Wywołania są sekwencyjne, bez yieldów. Zmieniamy tylko wykluczany kawałek.
	supportParams.FilterDescendantsInstances = { part }
	local reach = Utils.worldHalfY(part) + DBR.SleepGroundProbe
	return Workspace:Raycast(part.Position, Vector3.new(0, -reach, 0), supportParams) ~= nil
end

-- Obłoczek pary nad tonącym w lawie kawałkiem. Throttle jak przy dźwiękach uderzeń:
-- gdy lawa podchodzi pod usypisko, tonie naraz kilkadziesiąt partów.
local steamBudget = 0
local steamWindow = 0

local function trySteamPoof(position: Vector3)
	local now = os.clock()
	if now - steamWindow >= 1 then
		steamWindow = now
		steamBudget = 0
	end
	if steamBudget >= DBR.LavaSteamPerSecond then return end
	steamBudget += 1

	local anchor = Instance.new("Part")
	anchor.Name = "DebrisSteamFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	RobloxDebris:AddItem(anchor, 1.5)

	local steam = Instance.new("ParticleEmitter")
	steam.Texture = SMOKE_TEXTURE
	steam.Color = ColorSequence.new(Color3.fromRGB(230, 220, 210))
	steam.Size = NumberSequence.new(1.5, 4)
	steam.Transparency = NumberSequence.new(0.45, 1)
	steam.Lifetime = NumberRange.new(0.5, 1)
	steam.Rate = 0
	steam.Speed = NumberRange.new(4, 9)
	steam.SpreadAngle = Vector2.new(35, 35)
	steam.Parent = anchor
	steam:Emit(8)
end

local function scan()
	local now = os.clock()
	local lavaY = LavaService.getSurfaceY()
	local moving, total, persistent = 0, 0, 0
	-- Budżety na tick: raycasty podparcia i kasowanie partów rozkładamy w czasie,
	-- żeby zalanie usypiska lawą nie zrobiło jednoklatkowego spike'u.
	local supportBudget = DBR.SupportChecksPerTick
	local retireBudget = DBR.MaxRetiresPerTick
	-- Uderzenia zbierane do listy i przetwarzane PO pętli — fractureOnImpact rejestruje
	-- nowe party (dodaje klucze do registry), a dodawanie kluczy w trakcie pairs() to
	-- undefined behavior w Luau. (Kasowanie kluczy w trakcie iteracji jest legalne,
	-- więc retire() wołamy inline.)
	local impacts: { { part: BasePart, entry: Entry } } = {}

	for part, entry in pairs(registry) do
		if not part.Parent then
			unregister(part, entry)
			continue
		end

		if entry.restoreAt > 0 and now >= entry.restoreAt then
			restoreGroup(part, entry)
		end

		-- LAWA: kawałek schowany pod powierzchnią znika. Darmowe sprzątanie, które
		-- nasila się dokładnie wtedy, gdy gruzu jest najwięcej (późna faza rundy).
		if retireBudget > 0 and part.Position.Y + Utils.worldHalfY(part) < lavaY - DBR.LavaCullMargin then
			retireBudget -= 1
			trySteamPoof(Vector3.new(part.Position.X, lavaY, part.Position.Z))
			retire(part, entry)
			continue
		end

		if entry.asleep then
			-- Re-weryfikacja podparcia (round-robin — każdy śpiący co SupportRecheckInterval).
			if supportBudget > 0 and now - entry.supportCheckedAt >= DBR.SupportRecheckInterval then
				supportBudget -= 1
				entry.supportCheckedAt = now
				if not hasGroundSupport(part) then
					DebrisService.wake(part) -- podpora zniknęła — kawałek wraca do fizyki i spada
				end
			end
			if entry.asleep then
				if entry.expireAt > 0 and now >= entry.expireAt and retireBudget > 0 then
					retireBudget -= 1
					retire(part, entry)
					continue
				end
				total += 1
				if entry.persistent then persistent += 1 end
				continue
			end
		end

		-- Twardy sufit wieku drobnicy: kawałek, który z jakiegoś powodu nigdy nie usnął
		-- (toczy się, wisi zaklinowany), też ma zniknąć — inaczej zżera budżet na zawsze.
		if
			retireBudget > 0
			and not entry.persistent
			and now - entry.bornAt >= DBR.TempMaxAge
		then
			retireBudget -= 1
			retire(part, entry)
			continue
		end

		local velocity = part.AssemblyLinearVelocity
		local linear = velocity.Magnitude
		local angular = part.AssemblyAngularVelocity.Magnitude

		-- FALL-FRACTURE: twarde uderzenie = delta prędkości między tickami dużo większa
		-- niż to, co robi sama grawitacja (~39 stud/s przy 5Hz). Łapie lądowania i
		-- uderzenia w ściany; impuls kolejnej bomby też — celowo (gruz "dobity" pęka).
		-- Wyłącza się przy napiętym budżecie: mnożenie partów wypchnęłoby z rejestru
		-- świeży wybuch, a jego widać bardziej niż pęknięcie lecącej płyty.
		if
			IMP.FallFractureEnabled
			and #impacts < IMP.MaxImpactsPerTick
			and entry.generation < IMP.MaxGenerations
			and entry.lastVelocity ~= nil
			and (velocity - entry.lastVelocity :: Vector3).Magnitude >= IMP.ImpactDeltaV
			and totalCount < DBR.MaxTotalDebris * IMP.FractureBudgetHeadroom
			and part:IsA("Part")
			and part.Shape == Enum.PartType.Block
		then
			local s = part.Size
			if s.X * s.Y * s.Z >= IMP.MinFractureVolume then
				table.insert(impacts, { part = part, entry = entry })
				-- Oryginał nadal jest w rejestrze do fractureOnImpact. Jego unregister
				-- musi odjąć policzony part, także gdy podział nie stworzy resztek.
				moving += 1
				total += 1
				continue -- pęknie po pętli; sleep-logika bez znaczenia dla znikającego parta
			end
		end
		entry.lastVelocity = velocity

		if linear < DBR.SleepSpeed and angular < DBR.SleepSpeed then
			entry.stillSince = entry.stillSince or now
			if now - (entry.stillSince :: number) >= DBR.SleepTime then
				-- Kotwiczymy TYLKO z podparciem. Bez tego kawałek zaklinowany o ścianę
				-- albo wyhamowany w locie zostawał zamrożony w powietrzu na stałe.
				if hasGroundSupport(part) then
					-- Kolizje MUSZĄ wrócić zanim uśpimy — inaczej leżąca platforma na zawsze
					-- przenikałaby przez inny gruz.
					restoreGroup(part, entry)
					Utils.anchorAtRest(part) -- usypiany przy prędkości < SleepSpeed: bez zerowania = taśmociąg
					entry.asleep = true
					entry.supportCheckedAt = now
					-- Platformą zostaje tylko duży kawałek i tylko gdy jest wolne miejsce;
					-- reszta dostaje termin ważności i gaśnie sama.
					if entry.persistent and persistentCount < DBR.MaxPersistentDebris then
						persistentCount += 1
						entry.expireAt = 0
					else
						entry.persistent = false
						entry.expireAt = now + DBR.TempLifetimeAfterSleep
					end
					total += 1
					if entry.persistent then persistent += 1 end
					continue
				end
				-- Wisi bez podparcia: nie kotwiczymy i lekko go strącamy, żeby fizyka
				-- miała co rozwiązać zamiast trzymać go w miejscu tarciem.
				entry.stillSince = nil
				part.AssemblyLinearVelocity = velocity + Vector3.new(0, -4, 0)
			end
		else
			entry.stillSince = nil
		end
		moving += 1
		total += 1
	end

	-- Autorytatywne przeliczenie zamiast inkrementów, które potrafią zdryfować.
	-- Kawałki z impacts są jeszcze oryginałami; podział niżej aktualizuje liczniki
	-- przez te same register/unregister co pozostałe ścieżki.
	movingCount = moving
	totalCount = total
	persistentCount = persistent

	for _, imp in ipairs(impacts) do
		if imp.part.Parent then
			fractureOnImpact(imp.part, imp.entry)
		end
	end
end

-- ============================================================================
-- Cleanup + init
-- ============================================================================

local function clearAll()
	-- Cały gruz (w tym uśpione platformy) znika z końcem rundy. Remnants w Map sprząta
	-- MapService restore.
	local f = folder
	if f and f.Parent then
		f:ClearAllChildren()
	end
	table.clear(registry)
	movingCount = 0
	totalCount = 0
	persistentCount = 0
end

function DebrisService.init()
	if initialized then return end
	initialized = true

	ensureCollisionGroup()
	DebrisService.getFolder()

	local scanInterval = 1 / math.max(DBR.SleepCheckHz, 1)
	local scanAcc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		scanAcc += dt
		if scanAcc >= scanInterval then
			scanAcc = 0
			scan()
		end
	end)

	GameLoopService.RoundEnded:Connect(clearAll)
end

return DebrisService
