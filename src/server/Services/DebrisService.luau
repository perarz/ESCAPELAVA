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
--   - CRUSH (etap 3): duży, szybki kawałek rani gracza; kill credit "crushed" dla tego,
--     kto go wystrzelił (attribute BlastAttackerId — kontrakt z DestructionService)
--   - sprzątanie całości na RoundEnded
--
-- Gruz żyje w Workspace.BlastDebris (POZA Workspace.Map) — MapService restore go nie widzi,
-- sprzątamy go sami. Anchored remnants ścian zostają w Map i sprząta je restore.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxDebris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Fracture = require(ReplicatedStorage.Shared.Modules.Fracture)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerService = require(script.Parent.PlayerService)
local KillService = require(script.Parent.KillService)
local AntiCheatService = require(script.Parent.AntiCheatService)

local DebrisService = {}

local DBR = Config.Destruction.Debris
local IMP = Config.Destruction.Impact
local FRAC = Config.Destruction.Fracture

-- Kontrakt z DestructionService: kto wystrzelił ten kawałek (UserId).
local ATTACKER_ATTR = "BlastAttackerId"

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Entry = {
	restoreAt: number,      -- os.clock() przywrócenia collision group; 0 = już przywrócona
	stillSince: number?,    -- od kiedy nieprzerwanie poniżej progu prędkości (nil = w ruchu)
	asleep: boolean,        -- true = zakotwiczony jako leżąca platforma
	generation: number,     -- 0 = z wybuchu; 1 = z fall-fracture (dalej NIE pęka)
	lastVelocity: Vector3?, -- prędkość z poprzedniego ticku skanu (detekcja uderzeń)
}

-- Klucz = instancja — dwa wybuchy w to samo miejsce w tej samej klatce nie robią duplikatów.
local registry: { [BasePart]: Entry } = {}
local movingCount = 0

-- I-frames graczy między trafieniami gruzem (crush).
local lastCrushAt: { [Player]: number } = {}

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

function DebrisService.isRegistered(part: BasePart): boolean
	return registry[part] ~= nil
end

-- Rejestruje ŚWIEŻY kawałek gruzu: właściwości betonu, izolacja kolizji, server authority.
-- Caller (DestructionService / fall-fracture) odpowiada za Parent, CFrame i prędkości.
function DebrisService.register(part: BasePart, generation: number?)
	if registry[part] then
		DebrisService.wake(part)
		return
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

	registry[part] = {
		restoreAt = restoreAt,
		stillSince = nil,
		asleep = false,
		generation = generation or 0,
		lastVelocity = nil,
	}
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
		movingCount += 1
	end
	entry.stillSince = nil

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
	local attackerId = part:GetAttribute(ATTACKER_ATTR)
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
		p.Color = part.Color
		p.Material = part.Material
		p.Transparency = part.Transparency
		p.CastShadow = part.CastShadow
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = false
		p.CanCollide = true
		if attackerId ~= nil then
			p:SetAttribute(ATTACKER_ATTR, attackerId)
		end
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
	registry[part] = nil
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

local function scan()
	local now = os.clock()
	local moving = 0
	-- Uderzenia zbierane do listy i przetwarzane PO pętli — fractureOnImpact rejestruje
	-- nowe party (dodaje klucze do registry), a dodawanie kluczy w trakcie pairs() to
	-- undefined behavior w Luau.
	local impacts: { { part: BasePart, entry: Entry } } = {}

	for part, entry in pairs(registry) do
		if not part.Parent then
			registry[part] = nil
			continue
		end

		if entry.restoreAt > 0 and now >= entry.restoreAt then
			restoreGroup(part, entry)
		end

		if entry.asleep then
			continue
		end

		local velocity = part.AssemblyLinearVelocity
		local linear = velocity.Magnitude
		local angular = part.AssemblyAngularVelocity.Magnitude

		-- FALL-FRACTURE: twarde uderzenie = delta prędkości między tickami dużo większa
		-- niż to, co robi sama grawitacja (~39 stud/s przy 5Hz). Łapie lądowania i
		-- uderzenia w ściany; impuls kolejnej bomby też — celowo (gruz "dobity" pęka).
		if
			IMP.FallFractureEnabled
			and #impacts < IMP.MaxImpactsPerTick
			and entry.generation < IMP.MaxGenerations
			and entry.lastVelocity ~= nil
			and (velocity - entry.lastVelocity :: Vector3).Magnitude >= IMP.ImpactDeltaV
			and part:IsA("Part")
			and part.Shape == Enum.PartType.Block
		then
			local s = part.Size
			if s.X * s.Y * s.Z >= IMP.MinFractureVolume then
				table.insert(impacts, { part = part, entry = entry })
				continue -- pęknie po pętli; sleep-logika bez znaczenia dla znikającego parta
			end
		end
		entry.lastVelocity = velocity

		if linear < DBR.SleepSpeed and angular < DBR.SleepSpeed then
			entry.stillSince = entry.stillSince or now
			if now - (entry.stillSince :: number) >= DBR.SleepTime then
				-- Kolizje MUSZĄ wrócić zanim uśpimy — inaczej leżąca platforma na zawsze
				-- przenikałaby przez inny gruz.
				restoreGroup(part, entry)
				part.Anchored = true
				entry.asleep = true
				continue
			end
		else
			entry.stillSince = nil
		end
		moving += 1
	end

	-- Autorytatywne przeliczenie zamiast inkrementów, które potrafią zdryfować.
	-- (Kawałki z impacts liczą się jako moving jeszcze jeden tick — nieszkodliwe.)
	movingCount = moving

	for _, imp in ipairs(impacts) do
		if imp.part.Parent then
			fractureOnImpact(imp.part, imp.entry)
		end
	end
end

-- ============================================================================
-- Crush (etap 3): duży, szybki gruz rani graczy. Kill credit "crushed".
-- ============================================================================

local function crushCheck()
	if not IMP.CrushEnabled then return end

	-- Groźne kawałki tego ticku: szybkie i wystarczająco duże. Zwykle to krótka lista
	-- (tuż po wybuchu), więc pętla gracze × kawałki jest tania.
	local dangerous: { BasePart } = {}
	for part, entry in pairs(registry) do
		if entry.asleep or not part.Parent then continue end
		if part.AssemblyLinearVelocity.Magnitude < IMP.CrushSpeed then continue end
		local s = part.Size
		if s.X * s.Y * s.Z < IMP.CrushMinVolume then continue end
		table.insert(dangerous, part)
	end
	if #dangerous == 0 then return end

	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerService.isAlive(player) then continue end
		if now - (lastCrushAt[player] or 0) < IMP.CrushCooldown then continue end
		local char = player.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or not hrp or not hrp:IsA("BasePart") then continue end

		for _, part in ipairs(dangerous) do
			if not part.Parent then continue end
			-- Kontakt: dystans od POWIERZCHNI kawałka (nie środka — wielka płyta ma
			-- środek daleko od krawędzi która właśnie miażdży).
			local localPos = part.CFrame:PointToObjectSpace(hrp.Position)
			if Fracture.boxSurfaceDistance(Vector3.zero, part.Size, localPos) > IMP.CrushContact then
				continue
			end
			-- Kawałek musi lecieć W gracza (spadający na głowę = velocity w dół, gracz
			-- pod spodem — dot dodatni). Odlatujący od gracza nie miażdży.
			local velocity = part.AssemblyLinearVelocity
			if velocity:Dot(hrp.Position - part.Position) <= 0 then continue end

			local s = part.Size
			local volumeT = math.clamp((s.X * s.Y * s.Z) / IMP.CrushVolumeForMax, 0, 1)
			local speedT = math.clamp(velocity.Magnitude / IMP.CrushSpeedForMax, 0, 1)
			local dmg = math.max(IMP.CrushMinDamage, IMP.CrushMaxDamage * volumeT * speedT)

			-- Kill credit dla tego, kto wystrzelił kawałek (chyba że to własny gruz —
			-- samozgniecenie bez creditu, ale damage zostaje: fizyka nie wybacza).
			local attackerId = part:GetAttribute(ATTACKER_ATTR)
			if typeof(attackerId) == "number" and attackerId ~= player.UserId then
				local attacker = Players:GetPlayerByUserId(attackerId :: number)
				if attacker then
					KillService.tag(hum, attacker, "crush")
				end
			end

			-- Gracz zaraz poleci od uderzenia — bez grace anti-cheat uznałby go za hackera.
			AntiCheatService.grantGrace(player)
			hum:TakeDamage(dmg)
			lastCrushAt[player] = now
			-- Feedback trafionego: reuse BombHit (shake + FOV punch), skala z siły zgniotu.
			Remotes.BombHit:FireClient(player, math.clamp(dmg / IMP.CrushMaxDamage, 0.25, 1) * 0.8)

			if Config.Destruction.Debug then
				print(("[Debris] crush %s dmg=%.0f vol=%.0f speed=%.0f"):format(
					player.Name, dmg, s.X * s.Y * s.Z, velocity.Magnitude))
			end
			break -- jeden zgniot na tick na gracza (cooldown i tak blokuje)
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
end

local function onPlayerRemoving(player: Player)
	lastCrushAt[player] = nil
end

function DebrisService.init()
	if initialized then return end
	initialized = true

	ensureCollisionGroup()
	DebrisService.getFolder()

	local scanInterval = 1 / math.max(DBR.SleepCheckHz, 1)
	local crushInterval = 1 / math.max(IMP.CrushCheckHz, 1)
	local scanAcc = 0
	local crushAcc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		scanAcc += dt
		if scanAcc >= scanInterval then
			scanAcc = 0
			scan()
		end
		crushAcc += dt
		if crushAcc >= crushInterval then
			crushAcc = 0
			crushCheck()
		end
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	GameLoopService.RoundEnded:Connect(clearAll)
end

return DebrisService
