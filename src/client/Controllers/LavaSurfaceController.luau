--!strict
-- LavaSurfaceController.luau
-- Oprawa lawy po stronie klienta: przewijanie warstw tekstury + bąble + światło + para.
--
-- PODZIAŁ RÓL (decyzja 2026-09-14): teksturę daje Kacper, kod jej NIE tworzy i nie
-- podmienia — tylko animuje to, co znajdzie na parcie lawy. Wcześniej kod próbował
-- generować wygląd powierzchni sam (siatka kafli ze studsami, potem trójkąty, potem
-- własne wygenerowane tekstury) i wszystkie te podejścia zostały odrzucone; wniosek:
-- wygląd należy do Kacpra, ruch i efekty do kodu.
--
-- KONTRAKT STUDIO:
--   `Workspace.Lava` → dowolnie wiele partów (STOS WARSTW, 2026-09-16: nieprzezroczysty
--   spód + półprzezroczyste warstwy nad nim = głębia + prawdziwa paralaksa przy ruchu
--   kamery). Kod sortuje je po górnej ścianie; najwyższa jest POWIERZCHNIĄ i od niej
--   liczą się bąble, para i światło.
--   Na każdym parcie → dziecko typu **`Texture`** (NIE `Decal` — Decal nie ma
--   `OffsetStuds`, więc nie da się go przewijać), `Face = Top`.
--   Tekstury są numerowane od góry w dół, przez cały stos; każda kolejna dostaje inną
--   prędkość, żeby warstwy nie sunęły identycznie.
--   Opcjonalne ATRYBUTY na każdej warstwie (nadpisują domyślne z Config):
--     `ScrollU`, `ScrollV`  — study/s przewijania (ujemne = w drugą stronę)
--     `PulseAmount`         — o ile waha się Transparency (0 = bez pulsowania)
--     `PulsePeriod`         — sekundy pełnego cyklu pulsowania
--   Warstwy można dodawać i usuwać W TRAKCIE Play — kontroler nasłuchuje zmian dzieci.
--
-- WSZYSTKO LOKALNIE U KLIENTA — ten sam wzorzec co DebrisFXController: zero replikacji,
-- zero fizyki serwera, więc przy dziesiątkach serwerów kosztuje to serwer dokładnie zero.
-- Falowanie tafli NIE jest tutaj — part lawy jest serwerowy, więc klienckie ruszanie Y
-- zostałoby nadpisane przez replikację; robi to `LavaService.startPositionLoop`.
--
-- Wszystkie tworzone party mają `Locked = true`: bez tego `Destructible.canSpawnFXFrom`
-- je przepuszcza i DebrisFXController próbkuje z nich kolory, czyli bomba przy lawie
-- sypie pomarańczowymi odłamkami "z bąbla".

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local LavaSurfaceController = {}

local SURF = Config.Lava.Surface
local FX = Config.Lava.FX

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type Layer = {
	texture: Texture,
	scrollU: number,
	scrollV: number,
	baseTransparency: number, -- to, co ustawił Kacper — pulsowanie waha się WOKÓŁ tego
	pulseAmount: number,
	pulsePeriod: number,
}

type Light = {
	part: BasePart,
	light: PointLight,
	x: number,
	z: number,
	driftX: number,
	driftZ: number,
	age: number,     -- sekundy w bieżącym cyklu
	life: number,    -- długość cyklu (losowana, żeby światła nie mrugały zgodnie)
	retry: number,   -- przerwa po nieudanej próbie znalezienia odsłoniętej lawy
	active: boolean,
}

local initialized = false
local layers: { Layer } = {}
local lights: { Light } = {}
-- Cały stos, posortowany od góry; `lavaSurface` to warstwa wierzchnia (ta widoczna).
local lavaParts: { BasePart } = {}
local lavaSurface: BasePart? = nil
local stackConns: { RBXScriptConnection } = {}
local effectsFolder: Folder? = nil
local rng = Random.new()

-- Wspólne parametry raycastów wszystkich efektów (filtr ustawiany w `collectStack`):
-- pomijają CAŁY stos lawy i własne efekty, więc promień widzi wyłącznie mapę.
local fxRayParams = RaycastParams.new()

-- Granice tafli — party ruszają się tylko w Y, więc X/Z i rozmiary są stałe.
-- Liczone z SUMY warstw, bo wierzchnia bywa mniejsza od spodniej, a efekty mają
-- pokrywać całą widoczną lawę.
local centerX, centerZ, halfX, halfZ = 0, 0, 0, 0

local surfaceGlow: SurfaceLight? = nil
local glowTarget = 0

local bubbleTimer = 0
local bubbleActive = 0
local steamAcc = 0
local steamBudget = 0
local steamWindow = 0

-- ============================================================================
-- Wspólne
-- ============================================================================

local function surfaceY(): number
	local part = lavaSurface
	if not part then return 0 end
	return part.Position.Y + part.Size.Y * 0.5
end

-- Jeden wspólny LOD dla wszystkich efektów: lawa bywa widoczna przez pół mapy, a bąbel
-- z 400 studów to kilka pikseli. Sprawdzamy PRZED spawnem, żeby nie płacić za nic.
local function inRange(pos: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then return true end
	return (camera.CFrame.Position - pos).Magnitude <= FX.Distance
end

-- ============================================================================
-- JEDYNA BRAMKA OPRAWY: WYSOKOŚĆ TAFLI (2026-09-21, decyzja Kacpra)
-- ============================================================================
-- Dopóki lawa siedzi w kanale pod ulicami, oprawa jest wyłączona W CAŁOŚCI: bąble, para,
-- wędrujące światła i stała poświata. Embery i dym gasi `LavaService` po TEJ SAMEJ liczbie
-- (`Config.Lava.FX.MinSurfaceY`), więc nie ma czego replikować ani synchronizować.
--
-- ⚠️ ZASTĄPIŁO DWIE BRAMKI RAYCASTOWE (`isExposed` + `isLavaOpenAt`) — nie przywracać ich.
-- Powód, dla którego tamte nie mogły zadziałać, jest strukturalny, nie do dostrojenia:
--   (1) **Raycast, który w nic nie trafił, jest DWUZNACZNY** — znaczy „otwarte niebo" albo
--       „geometria jeszcze się nie wczytała". Przy `StreamingEnabled = true` po wejściu na
--       mapę przez ~15 s nie ma jeszcze ulic, więc kod uznawał lawę za odsłoniętą i zapalał
--       poświatę prześwitującą przez niedoładowaną podłogę. To był zgłoszony bug.
--   (2) **Particle w Robloxie nie kolidują z geometrią** — ember wypuszczony z tafli na Y 2.5
--       przelatuje przez jezdnię na Y 9 i wynurza się nad ulicą. Żadna bramka „czy nad tym
--       punktem coś jest" tego nie naprawi, bo problem jest w TORZE LOTU, nie w miejscu emisji.
--   (3) Zmierzone: 88% tafli jest zakryte, a prześwit w kanale ma 6.0 studa — przy takim
--       suficie KAŻDY sensowny zasięg światła i tak przebijał strop (nawet 10 przebijało
--       w 83% miejsc). Bramka odsłonięcia była więc prawie zawsze „nie", czyli cały ten
--       aparat raycastów istniał po to, żeby trzymać efekty wyłączone.
-- Porównanie dwóch LICZB nie ma jak się pomylić, jest poprawne od pierwszej klatki
-- i kosztuje zero raycastów.
-- ⚠️ HISTEREZA, nie goły próg: tafla FALUJE (`Wobble.Amplitude` 0.9), więc przy średnim
-- poziomie blisko progu samo falowanie przełączałoby oprawę co ~1.75 s — bąble i para
-- mrugałyby, a poświata pompowała. Między progami trzymamy poprzedni stan.
-- Ta sama reguła po stronie serwera (`LavaService.refreshSurfaceFX`), z tej samej liczby.
local fxOn = false
local function fxAllowed(y: number): boolean
	local h = FX.MinSurfaceHysteresis or 0
	if y >= FX.MinSurfaceY + h then
		fxOn = true
	elseif y <= FX.MinSurfaceY - h then
		fxOn = false
	end
	return fxOn
end

local function getFolder(): Folder
	local f = effectsFolder
	if f and f.Parent then return f end
	local new = Instance.new("Folder")
	new.Name = "LavaFX"
	new.Parent = Workspace
	effectsFolder = new
	return new
end

-- Losuje punkt na tafli PRZY KAMERZE. Losowanie po całej tafli 513×457 trafiało w większość
-- powierzchni, której gracz i tak nie widzi — stąd promień `spread` wokół kamery.
-- ⚠️ Nie ma tu już żadnego filtrowania: o tym, czy efekty w ogóle lecą, decyduje JEDNA
-- bramka wysokości (`fxAllowed`) sprawdzana raz na klatkę w `update`, a nie sprawdzanie
-- każdego punktu z osobna. Parametr `tries` został jako jedno losowanie — zostawiony
-- w sygnaturze, żeby nie ruszać trzech wywołań i pól `*Tries` w Configu.
local function pickPointNearCamera(spread: number, _tries: number?): Vector3?
	local y = surfaceY()
	local camera = Workspace.CurrentCamera
	local cx = if camera then camera.CFrame.Position.X else centerX
	local cz = if camera then camera.CFrame.Position.Z else centerZ
	local ang = rng:NextNumber(0, math.pi * 2)
	-- pierwiastek z losowej = równomiernie po KOLE, nie zagęszczenie w środku
	local dist = math.sqrt(rng:NextNumber()) * spread
	local x = math.clamp(cx + math.cos(ang) * dist, centerX - halfX, centerX + halfX)
	local z = math.clamp(cz + math.sin(ang) * dist, centerZ - halfZ, centerZ + halfZ)
	return Vector3.new(x, y, z)
end

-- ============================================================================
-- Warstwy tekstury
-- ============================================================================

local function readNumber(inst: Instance, name: string, fallback: number): number
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else fallback
end

-- Kolejne warstwy dostają prędkość przemnożoną przez inny mnożnik — jedna przewijana
-- tekstura czyta się jak przesuwana tapeta, dopiero dwie sunące różnie wyglądają jak
-- coś płynącego. Ujemny mnożnik = ruch w przeciwną stronę.
local function layerMultiplier(index: number): number
	local m = SURF.LayerMultipliers
	return m[(index - 1) % #m + 1]
end

-- Tekstury zbierane z CAŁEGO stosu, w kolejności od warstwy wierzchniej w dół — dzięki
-- temu numeracja (a więc i mnożniki prędkości) jest stabilna niezależnie od tego, czy
-- Kacper trzyma dwie tekstury na jednym parcie, czy po jednej na trzech warstwach.
local function rebuildLayers()
	table.clear(layers)
	local index = 0
	for _, lava in ipairs(lavaParts) do
		for _, child in ipairs(lava:GetChildren()) do
			if child:IsA("Decal") and not child:IsA("Texture") then
				warn(("[LavaSurface] '%s' to Decal — Decal nie ma OffsetStuds, więc nie da się go przewijać. Użyj Texture."):format(child.Name))
				continue
			end
			if not child:IsA("Texture") then continue end

			index += 1
			local mult = layerMultiplier(index)
			table.insert(layers, {
				texture = child,
				scrollU = readNumber(child, "ScrollU", SURF.DefaultScrollU * mult),
				scrollV = readNumber(child, "ScrollV", SURF.DefaultScrollV * mult),
				baseTransparency = child.Transparency,
				pulseAmount = readNumber(child, "PulseAmount", SURF.DefaultPulseAmount),
				pulsePeriod = math.max(0.1, readNumber(child, "PulsePeriod", SURF.DefaultPulsePeriod)),
			})
		end
	end

	if #layers == 0 then
		warn("[LavaSurface] żaden part w Workspace.Lava nie ma dziecka Texture — powierzchnia zostaje nieruchoma. Kontrakt w CLAUDE.md.")
	end
end

local function scrollLayers(now: number)
	for _, layer in ipairs(layers) do
		local tex = layer.texture
		if not tex.Parent then continue end

		-- Offset zawijany modulo rozmiaru kafla: bez tego po długiej sesji liczba rośnie
		-- do wartości, przy których float gubi precyzję i przewijanie zaczyna skakać.
		local tileU = if tex.StudsPerTileU > 0 then tex.StudsPerTileU else 1
		local tileV = if tex.StudsPerTileV > 0 then tex.StudsPerTileV else 1
		tex.OffsetStudsU = (now * layer.scrollU) % tileU
		tex.OffsetStudsV = (now * layer.scrollV) % tileV

		if layer.pulseAmount > 0 then
			local t = math.sin(now * (math.pi * 2) / layer.pulsePeriod)
			tex.Transparency = math.clamp(layer.baseTransparency - t * layer.pulseAmount, 0, 1)
		end
	end
end

-- ============================================================================
-- Bąble
-- ============================================================================

local function popBubble(position: Vector3, size: number)
	local anchor = Instance.new("Part")
	anchor.Name = "LavaBubblePop"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Locked = true
	anchor.Parent = getFolder()
	Debris:AddItem(anchor, 1.4)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEXTURE
	sparks.Color = ColorSequence.new(FX.BubbleColor)
	sparks.Size = NumberSequence.new(0.35 * size, 0.1)
	sparks.Transparency = NumberSequence.new(0.1, 1)
	sparks.Lifetime = NumberRange.new(0.35, 0.8)
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(6, 16)
	sparks.SpreadAngle = Vector2.new(50, 50)
	sparks.Parent = anchor
	sparks:Emit(FX.BubbleSparks)

	-- Krople lawy: cięższe od iskier, lecą po łuku i gasną w locie. Particle, a nie
	-- party — dziesiątki fizycznych kropel na sekundę to koszt bez obrazu.
	if FX.BubbleGlobs > 0 then
		local globs = Instance.new("ParticleEmitter")
		globs.Texture = SPARK_TEXTURE
		globs.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), FX.BubbleColor)
		globs.Size = NumberSequence.new(0.9 * size, 0.2)
		globs.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		globs.Lifetime = NumberRange.new(0.6, 1.1)
		globs.Rate = 0
		globs.Speed = NumberRange.new(9, 20)
		globs.SpreadAngle = Vector2.new(35, 35)
		globs.Acceleration = Vector3.new(0, -FX.BubbleGlobGravity, 0)
		globs.LightEmission = 0.8
		globs.Parent = anchor
		globs:Emit(FX.BubbleGlobs)
	end
end

local function spawnBubble()
	if bubbleActive >= FX.BubbleMaxActive then return end

	local pos = pickPointNearCamera(FX.BubbleSpread, FX.BubbleTries)
	if not pos or not inRange(pos) then return end

	local size = rng:NextNumber(FX.BubbleSizeMin, FX.BubbleSizeMax)
	local part = Instance.new("Part")
	part.Name = "LavaBubble"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * size
	-- Start: kula schowana pod powierzchnią, czubek tuż pod nią. Wypycha się w górę,
	-- więc z boku widać rosnącą kopułę, a nie kulę pojawiającą się znikąd.
	part.Position = Vector3.new(pos.X, pos.Y - size * 0.6, pos.Z)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Neon
	part.Color = FX.BubbleColor
	part.Parent = getFolder()

	bubbleActive += 1

	local topY = pos.Y - size * 0.5 + FX.BubbleRise
	local tween = TweenService:Create(
		part,
		TweenInfo.new(FX.BubbleRiseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = Vector3.new(pos.X, topY, pos.Z) }
	)
	tween.Completed:Connect(function()
		bubbleActive -= 1
		if part.Parent then
			popBubble(Vector3.new(pos.X, topY + size * 0.4, pos.Z), size)
			part:Destroy()
		end
	end)
	tween:Play()
end

-- ============================================================================
-- Światło znad lawy
-- ============================================================================

local function buildLights()
	if not FX.LightsEnabled or FX.LightCount <= 0 then return end

	for _ = 1, FX.LightCount do
		local part = Instance.new("Part")
		part.Name = "LavaLight"
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Locked = true
		part.Parent = getFolder()

		local light = Instance.new("PointLight")
		light.Color = FX.LightColor
		light.Range = FX.LightRange
		-- Start od zera: pierwsze miejsce światło dostanie dopiero w `moveLights`,
		-- po znalezieniu odsłoniętego kawałka lawy.
		light.Brightness = 0
		-- Cienie z dynamicznych świateł to najdroższa część renderu — a tu chodzi
		-- wyłącznie o ciepłą poświatę, nie o rysunek cieni.
		light.Shadows = false
		light.Parent = part

		local dir = rng:NextNumber(0, math.pi * 2)
		table.insert(lights, {
			part = part,
			light = light,
			x = 0,
			z = 0,
			driftX = math.cos(dir) * FX.LightDrift,
			driftZ = math.sin(dir) * FX.LightDrift,
			age = 0,
			life = FX.LightLifetime * rng:NextNumber(0.7, 1.3),
			retry = rng:NextNumber(0, FX.LightRetry),
			active = false,
		})
	end
end

-- Losuje ODSŁONIĘTY punkt lawy w pobliżu kamery. "W pobliżu", bo światło ma dogrzewać
-- to, co gracz widzi — światło na drugim końcu tafli nie robi nic poza kosztem.
-- Obwiednia jasności: rozjaśnij → świeć → zgaś. Przestawienie światła następuje dopiero
-- przy jasności 0, więc gracz nigdy nie widzi, jak przeskakuje ono w nowe miejsce.
local function fadeEnvelope(age: number, life: number, fade: number): number
	if fade <= 0 then return 1 end
	if age < fade then return age / fade end
	if age > life - fade then return math.max(0, (life - age) / fade) end
	return 1
end

-- Gasi wszystkie światła i zeruje ich cykl — wołane, dopóki lawa siedzi w kanale.
-- Gasimy przez `Brightness = 0`, a nie kasując party: gdy lawa wyjdzie na ulice, cykl ma
-- ruszyć od razu, bez odbudowywania obiektów.
local function killLights()
	for _, l in ipairs(lights) do
		l.active = false
		l.light.Brightness = 0
	end
end

local function moveLights(dt: number, y: number)
	for _, l in ipairs(lights) do
		if l.retry > 0 then
			l.retry -= dt
			continue
		end

		if not l.active then
			local spot = pickPointNearCamera(FX.LightSpread, FX.LightPlacementTries)
			if not spot then
				-- W pobliżu nie ma odsłoniętej lawy (gracz w lobby, na dachu, w środku
				-- budynku) — nie świecimy wcale i próbujemy za chwilę.
				l.retry = FX.LightRetry
				continue
			end
			l.x, l.z = spot.X, spot.Z
			l.age = 0
			l.active = true
		end

		l.age += dt
		if l.age >= l.life then
			l.active = false
			l.light.Brightness = 0
			l.life = FX.LightLifetime * rng:NextNumber(0.7, 1.3)
			continue
		end

		l.x += l.driftX * dt
		l.z += l.driftZ * dt

		-- ⚠️ BYŁO TU re-sprawdzanie raz na sekundę, czy dryf nie wywiózł światła pod jezdnię.
		-- Zbędne: światła zapalają się WYŁĄCZNIE wtedy, gdy cała tafla jest już nad ulicami,
		-- więc nie ma pod co dodryfować. Zniknęło razem z `isExposed`/`isLavaOpenAt`.
		l.part.Position = Vector3.new(l.x, y + FX.LightHeight, l.z)
		l.light.Brightness = FX.LightBrightness * fadeEnvelope(l.age, l.life, FX.LightFade)
	end
end

-- ============================================================================
-- Para na styku z mapą
-- ============================================================================

local function spawnSteam(position: Vector3)
	local now = os.clock()
	if now - steamWindow >= 1 then
		steamWindow = now
		steamBudget = 0
	end
	if steamBudget >= FX.SteamPerSecond then return end
	steamBudget += 1

	local anchor = Instance.new("Part")
	anchor.Name = "LavaSteam"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Locked = true
	anchor.Parent = getFolder()
	Debris:AddItem(anchor, FX.SteamLifetime + 1)

	local steam = Instance.new("ParticleEmitter")
	steam.Texture = SMOKE_TEXTURE
	steam.Color = ColorSequence.new(Color3.fromRGB(236, 226, 214))
	steam.Size = NumberSequence.new(2, 7)
	steam.Transparency = NumberSequence.new(0.5, 1)
	steam.Lifetime = NumberRange.new(FX.SteamLifetime * 0.6, FX.SteamLifetime)
	steam.Rate = 0
	steam.Speed = NumberRange.new(3, 7)
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.Parent = anchor
	steam:Emit(6)
end

-- Szukamy LINII ZALANIA: punktów, pod którymi tuż poniżej powierzchni jest geometria
-- mapy. Raycast w DÓŁ, nie w bok — gdy lawa podchodzi pod ulicę czy strop, to właśnie
-- tam jest styk, który widać. Kosztem całego efektu jest `SteamSamples` raycastów
-- na tick przy `SteamCheckHz`.
local function steamTick()
	local y = surfaceY()
	local reach = FX.SteamProbeDepth + 1
	for _ = 1, FX.SteamSamples do
		-- Punkt losowany już jako ODSŁONIĘTY i w pobliżu gracza — promień w dół sprawdza
		-- tylko, czy tuż pod powierzchnią jest geometria, czyli czy to linia zalania.
		local pos = pickPointNearCamera(FX.SteamSpread, FX.SteamTries)
		if pos and inRange(pos) then
			local origin = Vector3.new(pos.X, y + 1, pos.Z)
			local hit = Workspace:Raycast(origin, Vector3.new(0, -reach, 0), fxRayParams)
			if hit then
				spawnSteam(Vector3.new(pos.X, y, pos.Z))
			end
		end
	end
end

-- ============================================================================
-- Pętla
-- ============================================================================

local function update(dt: number)
	local part = lavaSurface
	if not part or not part.Parent then return end

	local now = os.clock()
	local y = surfaceY()

	-- JEDNA BRAMKA NA WSZYSTKO: dopóki lawa siedzi w kanale pod ulicami, oprawa nie leci.
	-- Przewijanie tekstury zostaje — to sama tafla, widać ją tylko tam, gdzie widać lawę.
	local allowed = fxAllowed(y)

	scrollLayers(now)
	if allowed then
		moveLights(dt, y)
	else
		killLights()
	end

	-- Stała poświata. Narasta i gaśnie PŁYNNIE (`SurfaceGlowFade`), bo skok jasności na
	-- całej mapie byłby widoczny — dlatego nie wyłączamy jej twardo razem z resztą oprawy,
	-- tylko sprowadzamy cel do zera i pozwalamy dojechać.
	local sl = surfaceGlow
	if sl and sl.Parent then
		glowTarget = if allowed then FX.SurfaceGlowBrightness else 0
		local step = FX.SurfaceGlowFade * dt
		sl.Brightness += math.clamp(glowTarget - sl.Brightness, -step, step)
	end

	if allowed and FX.BubblesEnabled then
		bubbleTimer -= dt
		if bubbleTimer <= 0 then
			-- Odstęp losowany ±50%, żeby bąble nie tykały jak metronom.
			bubbleTimer = FX.BubbleInterval * rng:NextNumber(0.5, 1.5)
			spawnBubble()
		end
	end

	if allowed and FX.SteamEnabled then
		steamAcc += dt
		local interval = 1 / math.max(FX.SteamCheckHz, 1)
		if steamAcc >= interval then
			steamAcc = 0
			steamTick()
		end
	end
end

-- ============================================================================
-- Stos warstw
-- ============================================================================

-- Zbiera party lawy z folderu i przelicza wszystko, co od nich zależy. Wołane na starcie
-- i przy KAŻDEJ zmianie w folderze — Kacper dokłada i zabiera warstwy w trakcie Play.
local function collectStack(folder: Instance): boolean
	for _, conn in ipairs(stackConns) do
		conn:Disconnect()
	end
	table.clear(stackConns)
	table.clear(lavaParts)

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(lavaParts, child)
		end
	end
	if #lavaParts == 0 then
		lavaSurface = nil
		return false
	end

	-- Sortowanie po GÓRNEJ ŚCIANIE, nie po środku: warstwy mają różne grubości, więc
	-- środek partu kłamie o tym, która z nich jest widoczną powierzchnią.
	table.sort(lavaParts, function(a, b)
		return (a.Position.Y + a.Size.Y * 0.5) > (b.Position.Y + b.Size.Y * 0.5)
	end)
	lavaSurface = lavaParts[1]

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, part in ipairs(lavaParts) do
		minX = math.min(minX, part.Position.X - part.Size.X * 0.5)
		maxX = math.max(maxX, part.Position.X + part.Size.X * 0.5)
		minZ = math.min(minZ, part.Position.Z - part.Size.Z * 0.5)
		maxZ = math.max(maxZ, part.Position.Z + part.Size.Z * 0.5)
		table.insert(stackConns, part.ChildAdded:Connect(rebuildLayers))
		table.insert(stackConns, part.ChildRemoved:Connect(rebuildLayers))
	end
	centerX, centerZ = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
	halfX, halfZ = (maxX - minX) * 0.5, (maxZ - minZ) * 0.5

	-- Raycasty efektów muszą pomijać CAŁY stos, nie tylko warstwę wierzchnią: promienie
	-- startują z powierzchni, więc warstwa pod spodem (para) albo nad nią (odsłonięcie)
	-- trafiałaby się zawsze.
	local filter: { Instance } = { getFolder() }
	for _, part in ipairs(lavaParts) do
		table.insert(filter, part)
	end
	fxRayParams.FilterType = Enum.RaycastFilterType.Exclude
	fxRayParams.FilterDescendantsInstances = filter
	fxRayParams.IgnoreWater = true

	-- STAŁA POŚWIATA: światło idzie z samej tafli, więc świeci nieprzerwanie — niezależnie
	-- od cyklu wędrujących PointLightów, które z definicji gasną i wracają.
	-- Lokalne (jak reszta oprawy), więc serwer nie replikuje ani jednej właściwości.
	local surface = lavaSurface
	if surface and FX.SurfaceGlowEnabled then
		local glow = surface:FindFirstChild("LavaGlow")
		if not glow then
			glow = Instance.new("SurfaceLight")
			glow.Name = "LavaGlow"
			glow.Parent = surface
		end
		local sl = glow :: SurfaceLight
		sl.Face = Enum.NormalId.Top
		sl.Color = FX.SurfaceGlowColor
		sl.Range = FX.SurfaceGlowRange
		sl.Angle = FX.SurfaceGlowAngle
		-- Cienie z tak wielkiego źródła to najdroższa możliwa opcja, a chodzi o poświatę.
		sl.Shadows = false
		-- Jasność prowadzi `update` — dopóki lawa siedzi w kanale, poświata jest wygaszona,
		-- bo przy ShadowMap przebijałaby jezdnię nad sobą.
		sl.Brightness = 0
		surfaceGlow = sl
	end

	rebuildLayers()
	return true
end

-- ============================================================================
-- Init
-- ============================================================================

function LavaSurfaceController.init()
	if initialized then return end
	initialized = true

	if not SURF.Enabled then return end

	-- WaitForChild yielduje, a party lawy mogą powstać dopiero w LavaService.init()
	-- (fallback) — dlatego czekamy w osobnym wątku i nie blokujemy bootstrapu reszty
	-- kontrolerów.
	task.spawn(function()
		local lavaFolder = Workspace:WaitForChild("Lava", 30)
		if not lavaFolder then
			warn("[LavaSurface] brak Workspace.Lava — oprawa lawy wyłączona")
			return
		end

		if not collectStack(lavaFolder) then
			-- Folder bywa pusty przez chwilę po starcie serwera (LavaService dopiero
			-- tworzy fallback), więc czekamy na pierwszy part zamiast od razu rezygnować.
			local deadline = os.clock() + 30
			repeat
				lavaFolder.ChildAdded:Wait()
			until collectStack(lavaFolder) or os.clock() > deadline
		end

		if not lavaSurface then
			warn("[LavaSurface] brak partów w Workspace.Lava — oprawa lawy wyłączona")
			return
		end

		buildLights()

		-- Kacper stroi wygląd w Studio, często w trakcie Play: dołożona warstwa albo
		-- nowa tekstura mają zadziałać bez restartu. Nasłuch jest na FOLDERZE (doszedł
		-- cały part) — `collectStack` dokłada nasłuch na każdym parcie (doszła tekstura).
		lavaFolder.ChildAdded:Connect(function()
			collectStack(lavaFolder)
		end)
		lavaFolder.ChildRemoved:Connect(function()
			collectStack(lavaFolder)
		end)

		RunService.RenderStepped:Connect(update)
	end)
end

return LavaSurfaceController
