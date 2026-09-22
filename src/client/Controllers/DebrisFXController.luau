--!strict
-- DebrisFXController.luau
-- Kosmetyczne odłamki gruzu — LOKALNE party klienta (system destrukcji v2, etap 1).
-- To jest druga połowa "hybrydowego gruzu" z DESTRUCTION_PLAN.md: serwer symuluje tylko
-- duże, znaczące kawałki (DebrisService), a drobnicę spawnuje każdy klient u siebie
-- z Remotes.BlastFX(center, radius, seed):
--   - zero replikacji (party tworzone client-side nie idą do sieci)
--   - zero kosztu fizyki serwera
--   - ten sam seed u wszystkich → wszyscy widzą TEN SAM wzór odłamków
--   - liczba skalowana jakością grafiki klienta (telefon spawnuje mniej)
-- Odłamki żyją ~FragLifetime sekund, potem shrink+fade i Destroy — nie zaśmiecają sceny.
--
-- Kolory/materiały odłamków są PRÓBKOWANE z geometrii wokół epicentrum — gruz wygląda
-- jak budynek, który właśnie pękł, a nie jak szare klocki znikąd.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Destructible = require(ReplicatedStorage.Shared.Modules.Destructible)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)

local DebrisFXController = {}

local FX = Config.Destruction.FX

-- Niska gęstość: odłamek kolidujący z własnym characterem ledwo go muska zamiast spychać.
-- (Party lokalne kolidują z lokalnie symulowanym characterem — z cudzymi nie, bo tamte
-- pozycje są replikowane, nie symulowane u nas.)
local FRAG_PROPERTIES = PhysicalProperties.new(FX.FragDensity, 0.7, 0.1, 1, 1)

local FALLBACK_COLOR = Color3.fromRGB(132, 126, 118)
local FALLBACK_MATERIAL = Enum.Material.Concrete

-- Aktywne lokalne odłamki (FIFO) — twardy sufit MaxLocalFrags, najstarsze wypadają od razu.
local activeFrags: { BasePart } = {}

local function qualityMultiplier(): number
	local ok, quality = pcall(function()
		return (UserSettings() :: any):GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or quality == Enum.SavedQualitySetting.Automatic then
		return 1
	end
	local v = (quality :: Enum.SavedQualitySetting).Value
	if v <= 3 then
		return 0.35
	elseif v <= 6 then
		return 0.65
	end
	return 1
end

type Sample = { color: Color3, material: Enum.Material, variant: string }

-- Próbkuj wygląd otoczenia: do 6 partów wokół epicentrum.
-- Party CHRONIONE (Locked / Map.Locked / ActiveCash) są pomijane — odłamek w kolorze
-- nietykalnego Baseplate wyglądał, jakby wybuch właśnie go rozwalił, choć serwer go
-- nie tyka. Reguła ta sama co po stronie serwera (Shared.Modules.Destructible).
local function sampleSurroundings(center: Vector3, radius: number): { Sample }
	local samples: { Sample } = {}
	local ctx = Destructible.buildContext()
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(center, math.min(radius, 30))) do
		if part.Transparency > 0.6 then continue end
		if not Destructible.canSpawnFXFrom(part, ctx) then continue end
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

local function retireFrag(frag: BasePart, fadeTime: number)
	if not frag.Parent then return end
	local tween = TweenService:Create(frag, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad), {
		Size = frag.Size * 0.1,
		Transparency = 1,
	})
	tween.Completed:Connect(function()
		frag:Destroy()
	end)
	tween:Play()
end

local function enforceCap()
	while #activeFrags > FX.MaxLocalFrags do
		local oldest = table.remove(activeFrags, 1) :: BasePart
		if oldest.Parent then
			oldest:Destroy()
		end
	end
end

local function spawnFrag(rng: Random, center: Vector3, radius: number, samples: { Sample })
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
	frag.Color = sample.color
	frag.Material = sample.material
	frag.MaterialVariant = sample.variant
	-- Gładko, a nie jak chce `Instance.new`: odłamek ma 0.4-1.5 studa, więc domyślny
	-- stud bywa większy niż jego ściana i drobnica wygląda jak sypiące się klocki LEGO.
	Utils.smoothSurfaces(frag)
	frag.CustomPhysicalProperties = FRAG_PROPERTIES
	frag.CanCollide = true
	frag.CanQuery = false
	frag.CanTouch = false
	frag.CastShadow = false
	frag.Anchored = false

	-- Spawn w powłoce wokół epicentrum, z biasem w górę (gruz "wyrywa się" z podłoża).
	local dir = Vector3.new(
		rng:NextNumber(-1, 1),
		rng:NextNumber(0.1, 1),
		rng:NextNumber(-1, 1)
	)
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
	frag.AssemblyLinearVelocity = launch * rng:NextNumber(FX.FragMinSpeed, FX.FragMaxSpeed)
	frag.AssemblyAngularVelocity = Vector3.new(
		rng:NextNumber(-20, 20),
		rng:NextNumber(-20, 20),
		rng:NextNumber(-20, 20)
	)

	frag.Parent = Workspace
	table.insert(activeFrags, frag)

	-- Rozjitterowany lifetime = odłamki znikają falami, nie wszystkie w jednej klatce.
	task.delay(FX.FragLifetime * rng:NextNumber(0.7, 1.3), function()
		retireFrag(frag, FX.FragFadeTime)
	end)
end

-- ============================================================================
-- Szkło (etap 2): odłamki szyb z payloadu BlastFX. Server tłucze party, my renderujemy
-- lokalnie kilka cienkich, szklanych kawałków wylatujących ze szyby OD wybuchu.
-- ============================================================================

local function spawnGlassShards(rng: Random, center: Vector3, panes: { any })
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
			math.round(area / FX.ShardAreaPerShard),
			FX.ShardsPerPaneMin,
			FX.ShardsPerPaneMax
		)
		-- Udział tej tafli w budżecie całego wybuchu, proporcjonalnie do jej powierzchni.
		local share = math.round(FX.ShardsPerBlastMax * area / totalArea)
		count = math.clamp(math.min(count, share), FX.ShardsPerPaneMin, FX.ShardsPerPaneMax)

		-- ⚠️ ROZMIAR ODŁAMKA ROŚNIE Z TAFLĄ. Bez tego wielka szyba dostaje tę samą drobnicę
		-- co mała i „znika" zamiast się rozpaść — to był zgłoszony objaw. „Komórka" mówi,
		-- ile powierzchni przypada na jeden kawałek; odnosimy ją do typowej szyby.
		local cell = math.sqrt(area / math.max(count, 1))
		local scale = math.clamp(cell / FX.ShardCellRef, 1, FX.ShardScaleMax)

		for _ = 1, count do
			-- `WedgePart`, nie `Part`: klin zbiega się do krawędzi, czyli ma ostry koniec.
			-- Zwykły prostopadłościan o dwóch podobnych bokach czytał się jak kwadratowa
			-- płytka i całość wyglądała jak konfetti, nie jak tłuczone szkło.
			local shard = Instance.new("WedgePart")
			shard.Name = "LocalGlassShard"
			-- X = grubość tafli, Y = szerokość u podstawy, Z = DŁUGOŚĆ drzazgi.
			-- Długość i szerokość z ROZŁĄCZNYCH zakresów — to one robią „ostry", nie kształt
			-- sam w sobie: przy zbliżonych wartościach klin dalej wygląda jak kostka.
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
			shard.CustomPhysicalProperties = FRAG_PROPERTIES
			shard.CanCollide = true
			shard.CanQuery = false
			shard.CanTouch = false
			shard.CastShadow = false
			shard.Anchored = false
			-- Duży kawał szkła ma OPADAĆ, nie odlatywać jak iskra — inaczej wielka tafla
			-- znowu „znika", tylko szybciej. Dzielimy przez pierwiastek ze skali, żeby
			-- małe odłamki zachowały dotychczasową żywość.
			local slow = math.sqrt(scale)
			shard.AssemblyLinearVelocity = normal * (rng:NextNumber(6, 16) / slow)
				+ Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1, 4), rng:NextNumber(-3, 3)) / slow
			shard.AssemblyAngularVelocity = Vector3.new(
				rng:NextNumber(-25, 25) / scale,
				rng:NextNumber(-25, 25) / scale,
				rng:NextNumber(-25, 25) / scale
			)
			shard.Parent = Workspace
			table.insert(activeFrags, shard)

			task.delay(FX.ShardLifetime * rng:NextNumber(0.7, 1.2), function()
				retireFrag(shard, FX.FragFadeTime)
			end)
		end
	end
end

local function onBlastFX(center: Vector3, radius: number, seed: number, glassPanes: any?)
	if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" or typeof(seed) ~= "number" then
		return
	end

	-- Daleki wybuch — odłamków i tak nie widać, szkoda fizyki klienta.
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - center).Magnitude > 200 then return end

	-- Ten sam seed na każdym kliencie = identyczny wzór odłamków u wszystkich.
	local rng = Random.new(seed)

	local count = math.floor(FX.ClientFrags * qualityMultiplier())
	if count > 0 then
		local samples = sampleSurroundings(center, radius)
		for _ = 1, count do
			spawnFrag(rng, center, radius, samples)
		end
	end

	if typeof(glassPanes) == "table" then
		spawnGlassShards(rng, center, glassPanes :: { any })
	end

	enforceCap()
end

local initialized = false
function DebrisFXController.init()
	if initialized then return end
	initialized = true
	Remotes.BlastFX.OnClientEvent:Connect(onBlastFX)
end

return DebrisFXController
