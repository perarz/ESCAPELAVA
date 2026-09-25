--!strict
-- ExplosionFXController.luau
-- Wizualia wybuchu — CAŁY render po stronie klienta (system destrukcji v2, etap 1).
-- Serwer wysyła jeden Remotes.BlastFX({center, radius, seed, ...}); każdy klient renderuje
-- lokalnie: kulę ognia, falę uderzeniową, błysk światła, dym, iskry, embery i pył przy
-- ziemi + ambientowy screen shake skalowany odległością od kamery.
-- Zero kosztu replikacji poza jednym eventem — im słabszy sprzęt, tym łatwiej to skalować.
-- Ilość cząsteczek skaluje tryb grafiki gracza (QualityController, 2026-09-23).
--
-- Kosmetyczne ODŁAMKI gruzu robi osobno DebrisFXController (ten sam event, ten sam seed).
-- Dźwięk: Config.Destruction.FX.ExplosionSoundId — puste do czasu assetu Kacpra (etap 5);
-- wpisanie id w Config wystarczy, wpięcie już jest.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Destructible = require(ReplicatedStorage.Shared.Modules.Destructible)
local MovementController = require(script.Parent.MovementController)
local QualityController = require(script.Parent.QualityController)

local ExplosionFXController = {}

local FX = Config.Destruction.FX

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function makeAnchor(position: Vector3, lifetime: number): Part
	local anchor = Instance.new("Part")
	anchor.Name = "BlastFXAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	Debris:AddItem(anchor, lifetime)
	return anchor
end

-- Kula ognia: mały jasny rdzeń rozdymający się błyskawicznie i gasnący.
local function fireballCore(center: Vector3, radius: number)
	local core = Instance.new("Part")
	core.Name = "BlastCore"
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 235, 170)
	core.Transparency = 0
	core.Size = Vector3.new(2, 2, 2)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CFrame = CFrame.new(center)
	core.Parent = Workspace
	Debris:AddItem(core, 0.3)
	TweenService:Create(core, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 0.9,
		Color = Color3.fromRGB(255, 140, 50),
		Transparency = 1,
	}):Play()
end

-- Fala uderzeniowa: półprzezroczysta kula lecąca do 2.2× promienia — czytelny zasięg.
local function shockwave(center: Vector3, radius: number)
	local wave = Instance.new("Part")
	wave.Name = "BlastShockwave"
	wave.Shape = Enum.PartType.Ball
	wave.Material = Enum.Material.Neon
	wave.Color = Color3.fromRGB(255, 190, 120)
	wave.Transparency = 0.3
	wave.Size = Vector3.new(4, 4, 4)
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CFrame = CFrame.new(center)
	wave.Parent = Workspace
	Debris:AddItem(wave, 0.6)
	TweenService:Create(wave, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2.2,
		Transparency = 1,
	}):Play()
end

-- Błysk PointLight z decayem — otoczenie "czuje" moc wybuchu.
local function flash(anchor: Part, radius: number)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Brightness = 15
	light.Range = radius * 2
	light.Parent = anchor
	task.spawn(function()
		local t0 = os.clock()
		local D = 0.3
		while light.Parent and os.clock() - t0 < D do
			light.Brightness = 15 * (1 - (os.clock() - t0) / D)
			task.wait()
		end
		if light.Parent then light:Destroy() end
	end)
end

-- Liczba cząsteczek × mnożnik trybu grafiki (Ziemniak: połowa). Nigdy zero — wybuch
-- bez ognia i dymu wyglądałby jak bug, nie jak oszczędzanie.
local function scaled(count: number): number
	return math.max(1, math.round(count * QualityController.profile().ParticleScale))
end

local function particles(anchor: Part, radius: number)
	-- Ogień: krótki gorący burst.
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = SPARK_TEXTURE
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 30))
	fire.Size = NumberSequence.new(1.2, 0.2)
	fire.Transparency = NumberSequence.new(0, 1)
	fire.Lifetime = NumberRange.new(0.25, 0.5)
	fire.Rate = 0
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Speed = NumberRange.new(40, 80)
	fire.LightEmission = 1
	fire.Parent = anchor
	-- Liczby zbite ~2× (2026-08-12): poprzednie wartości robiły zasłonę dymną, przez którą
	-- nie było widać dziury ani lecącego gruzu. Wybuch ma pokazywać zniszczenie, nie je kryć.
	fire:Emit(scaled(20))

	-- Dym: ciemny, duży, wolno gaśnie — zostaje po błysku jako "ciężar" wybuchu.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 62, 55), Color3.fromRGB(38, 38, 38))
	-- Mniejszy i rzadszy dym: kłąb o promieniu wybuchu zakrywał całą scenę razem z dziurą.
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.35, radius * 0.3),
		NumberSequenceKeypoint.new(1, radius * 0.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.9, 1.6)
	smoke.Rate = 0
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Speed = NumberRange.new(6, 16)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-70, 70)
	smoke.Parent = anchor
	smoke:Emit(scaled(18))

	-- Iskry: szybkie smugi.
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEXTURE
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90))
	sparks.Size = NumberSequence.new(0.7, 0.1)
	sparks.Transparency = NumberSequence.new(0, 1)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Rate = 0
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Speed = NumberRange.new(45, 75)
	sparks.LightEmission = 1
	sparks.Parent = anchor
	sparks:Emit(scaled(24))

	-- Embery z grawitacją: ogniste łuki opadające dłużej niż iskry.
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = SPARK_TEXTURE
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 150, 50), Color3.fromRGB(200, 60, 20))
	embers.Size = NumberSequence.new(0.5, 0.15)
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.8, 1.4)
	embers.Rate = 0
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Speed = NumberRange.new(30, 60)
	embers.Acceleration = Vector3.new(0, -70, 0)
	embers.LightEmission = 1
	embers.Parent = anchor
	embers:Emit(scaled(16))
end

-- Pierścień pyłu przy ziemi — wybuch "siada" na podłożu zamiast wisieć w powietrzu.
-- NIE pyli z partów chronionych (Locked / Map.Locked / ActiveCash): skoro serwer ich
-- nie tyka, nie mogą wyglądać na kruszone. Ta sama reguła co po stronie serwera
-- (Shared.Modules.Destructible) — jedno źródło prawdy dla obu stron.
local function groundDust(center: Vector3)
	local hit = Workspace:Raycast(center, Vector3.new(0, -60, 0))
	if not hit then return end
	if not Destructible.canSpawnFXFrom(hit.Instance, Destructible.buildContext()) then return end

	local anchor = makeAnchor(hit.Position + Vector3.new(0, 0.5, 0), 2.5)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(180, 165, 140), Color3.fromRGB(130, 120, 105))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.5),
		NumberSequenceKeypoint.new(0.5, 7),
		NumberSequenceKeypoint.new(1, 10),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.7, 1.2)
	dust.Rate = 0
	dust.SpreadAngle = Vector2.new(85, 85) -- nisko, na boki
	dust.Speed = NumberRange.new(16, 30)
	dust.Acceleration = Vector3.new(0, -4, 0)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-50, 50)
	dust.Parent = anchor
	dust:Emit(scaled(14))
end

-- Wspólny odtwarzacz 3D dla całego systemu destrukcji (etap 5). Puste id = cisza,
-- więc wszystko poniżej działa również zanim Kacper wybierze assety.
local function playSoundAt(soundId: string, position: Vector3, volume: number, maxDistance: number)
	if soundId == "" then return end
	local anchor = makeAnchor(position, 6)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = maxDistance
	sound.Parent = anchor
	sound:Play()
end
ExplosionFXController.playSoundAt = playSoundAt

-- (Ślady opalenia usunięte 2026-08-12 — raycast w dół z epicentrum kładł plamę na ziemi
-- także dla wybuchów w powietrzu, kilkadziesiąt studów pod bombą.)

-- Ambientowy shake dla WSZYSTKICH w pobliżu (nie tylko trafionych — tych mocniej trzęsie
-- BombHit). Skalowany odległością kamery od epicentrum.
local function ambientShake(center: Vector3)
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local distance = (camera.CFrame.Position - center).Magnitude
	local t = 1 - math.clamp(distance / FX.ShakeMaxDistance, 0, 1)
	if t <= 0 then return end
	MovementController.screenShake(t * FX.ShakeMax, FX.ShakeDuration)
end

-- Payload BlastFX to jedna tabela od v3 (2026-09-23) — kontrakt w Remotes.luau.
local function onBlastFX(blast: any)
	-- Walidacja — server jest zaufany, ale typy potrafi popsuć half-sync rojo.
	if typeof(blast) ~= "table" then return end
	local center = blast.center
	local radius = blast.radius
	local glassPanes = blast.glass
	if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" then return end

	-- Daleki wybuch (poza zasięgiem wzroku z sensownym detalem): tylko światło i fala,
	-- bez particli — oszczędność na słabym sprzęcie przy kilku bombach naraz. W trybie
	-- Ziemniak „daleko” zaczyna się bliżej (zasięg rysowania gruzu z profilu).
	local camera = Workspace.CurrentCamera
	local farDistance = math.min(250, QualityController.profile().FXDistance + 60)
	local far = camera and (camera.CFrame.Position - center).Magnitude > farDistance

	local anchor = makeAnchor(center, 3)
	fireballCore(center, radius)
	shockwave(center, radius)
	flash(anchor, radius)
	if not far then
		particles(anchor, radius)
		groundDust(center)
	end
	playSoundAt(FX.ExplosionSoundId, center, 1, 300)
	-- Brzęk szkła RAZ na wybuch, przy najbliższej stłuczonej tafli — nie raz na taflę
	-- (30 szyb = 30 nakładających się dźwięków w tej samej milisekundzie).
	if typeof(glassPanes) == "table" and #(glassPanes :: { any }) > 0 then
		local first = (glassPanes :: { any })[1]
		local pos = typeof(first) == "table" and typeof(first.cf) == "CFrame" and first.cf.Position or center
		playSoundAt(FX.GlassSoundId, pos, 0.8, 250)
	end
	ambientShake(center)
end

-- ============================================================================
-- Kolaps sekcji (etap 4/5): ostrzeżenie i samo zawalenie. Osobny remote, bo to nie
-- jest wybuch — dzieje się z opóźnieniem i w innym miejscu niż bomba.
-- ============================================================================

local function structureDust(position: Vector3, magnitude: number, collapse: boolean)
	local anchor = makeAnchor(position, collapse and 4 or 2.5)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(165, 155, 140), Color3.fromRGB(115, 108, 98))
	local scale = collapse and 14 or 5
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, scale * 0.3),
		NumberSequenceKeypoint.new(1, scale),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, collapse and 0.25 or 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(1.2, collapse and 2.8 or 1.8)
	dust.Rate = 0
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Speed = NumberRange.new(collapse and 12 or 2, collapse and 30 or 6)
	dust.Acceleration = Vector3.new(0, collapse and -8 or -2, 0)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Parent = anchor
	dust:Emit(scaled(collapse and math.floor(40 + 40 * magnitude) or 14))
end

local function onStructureFX(kind: any, position: any, magnitude: any)
	if typeof(kind) ~= "string" or typeof(position) ~= "Vector3" then return end
	local mag = typeof(magnitude) == "number" and math.clamp(magnitude, 0, 1) or 0.5

	local camera = Workspace.CurrentCamera
	local distance = camera and (camera.CFrame.Position - position).Magnitude or 0

	if kind == "collapse" then
		structureDust(position, mag, true)
		playSoundAt(FX.CollapseSoundId, position, 1, 400)
		local t = 1 - math.clamp(distance / FX.CollapseShakeDistance, 0, 1)
		if t > 0 then
			MovementController.screenShake(t * FX.CollapseShakeMax * (0.5 + 0.5 * mag), FX.CollapseShakeDuration)
		end
	elseif kind == "creak" then
		structureDust(position, mag, false)
		playSoundAt(FX.CreakSoundId, position, 0.7, 220)
		local t = 1 - math.clamp(distance / FX.CreakShakeDistance, 0, 1)
		if t > 0 then
			MovementController.screenShake(t * FX.CreakShakeMax, FX.CreakShakeDuration)
		end
	end
end

local initialized = false
function ExplosionFXController.init()
	if initialized then return end
	initialized = true
	Remotes.BlastFX.OnClientEvent:Connect(onBlastFX)
	Remotes.StructureFX.OnClientEvent:Connect(onStructureFX)
end

return ExplosionFXController
