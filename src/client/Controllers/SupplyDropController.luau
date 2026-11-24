--!strict
-- SupplyDropController.luau (24.11) — wygląd zrzutu zaopatrzenia. Skrzynię, jej miejsce, otwarcie
-- i loot prowadzi serwer (SupplyDropService); tutaj tylko obraz:
--   * opadanie na spadochronie z bujaniem, liczone z atrybutów modelu (`FromY`, `DropStart`,
--     `DropEnd`, `Land`) i czasu serwera — u każdego tak samo, także u dołączającego w trakcie;
--   * słup światła w miejscu lądowania (widać, dokąd biec, zanim skrzynia spadnie);
--   * kurz przy lądowaniu, składanie spadochronu, błysk przy otwarciu.
--
-- Model rusza się tylko u klienta i tylko w powietrzu (bez kolizji — włącza ją serwer po
-- lądowaniu), więc nikt nie stanie na czymś, czego inny nie ma (lekcja 10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ExplosionFXController = require(script.Parent.ExplosionFXController)
local SettingsState = require(script.Parent.SettingsState)

local CFG = Config.SupplyDrop

local SupplyDropController = {}

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

type Tracked = {
	dropStart: number?, -- który lot już rysujemy (nowa wartość = skrzynia spada dalej)
	settled: boolean,
	pillar: { Instance },
	conns: { RBXScriptConnection },
}
local tracked: { [Model]: Tracked } = {}
local initialized = false

local function particleCount(n: number): number
	return if SettingsState.get("graphics") == "low" then math.ceil(n * 0.5) else n
end

-- ── Efekty ───────────────────────────────────────────────────────────────────────────

local function burst(position: Vector3, texture: string, color: Color3, count: number, size: number, speed: number, emission: number)
	local anchor = Instance.new("Part")
	anchor.Name = "SupplyDropFX"
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Locked = true
	anchor.Transparency = 1
	anchor.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = emission
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(80, 80)
	e.Drag = 3
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = 0
	e.Parent = anchor
	e:Emit(particleCount(count))
	task.delay(1.2, function() anchor:Destroy() end)
end

-- Attachmenty w świecie, nie na modelu: skrzynia się buja, a słup ma stać prosto.
local function makePillar(at: Vector3): { Instance }
	local terrain = Workspace.Terrain
	local bottom = Instance.new("Attachment")
	bottom.Name = "SupplyDropBottom"
	bottom.WorldPosition = at
	bottom.Parent = terrain
	local top = Instance.new("Attachment")
	top.Name = "SupplyDropTop"
	top.WorldPosition = at + Vector3.new(0, CFG.BeamHeight, 0)
	top.Parent = terrain
	local beam = Instance.new("Beam")
	beam.Name = "SupplyDropBeam"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Color = ColorSequence.new(CFG.Color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = CFG.BeamWidth
	beam.Width1 = CFG.BeamWidth * 0.6
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, CFG.BeamTransparency),
		NumberSequenceKeypoint.new(0.8, math.min(1, CFG.BeamTransparency + 0.3)),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = terrain
	return { beam, bottom, top }
end

local function clearPillar(info: Tracked)
	for _, inst in ipairs(info.pillar) do inst:Destroy() end
	table.clear(info.pillar)
end

local function foldParachute(model: Model)
	local chute = model:FindFirstChild(CFG.ParachuteName)
	if not chute then return end
	local ti = TweenInfo.new(CFG.ParachuteFold, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in ipairs(chute:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, ti, {
				Transparency = 1,
				CFrame = d.CFrame - Vector3.new(0, 5, 0),
			}):Play()
		end
	end
end

local function playOpen(model: Model, info: Tracked)
	clearPillar(info)
	local land = model:GetAttribute("Land")
	local pos = if typeof(land) == "CFrame" then land.Position + Vector3.new(0, 1.5, 0) else model:GetPivot().Position
	burst(pos, SPARK_TEXTURE, CFG.Color, CFG.BurstCount, 0.6, 22, 1)
	burst(pos, SMOKE_TEXTURE, Color3.fromRGB(200, 190, 170), CFG.DustCount, 1.6, 12, 0)
	ExplosionFXController.playSoundAt(CFG.OpenSoundId, pos, CFG.SoundVolume, 120)
	-- Skrzynia gaśnie, zanim serwer ją skasuje (OpenLinger).
	local ti = TweenInfo.new(CFG.OpenLinger * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, ti, { Transparency = 1 }):Play()
		elseif d:IsA("PointLight") then
			TweenService:Create(d, ti, { Brightness = 0 }):Play()
		end
	end
end

-- ── Śledzenie skrzyń ─────────────────────────────────────────────────────────────────

local function untrack(model: Model)
	local info = tracked[model]
	if not info then return end
	tracked[model] = nil
	clearPillar(info)
	for _, c in ipairs(info.conns) do c:Disconnect() end
end

local function track(child: Instance)
	if not child:IsA("Model") or tracked[child] then return end
	local model = child
	local info: Tracked = { dropStart = nil, settled = false, pillar = {}, conns = {} }
	tracked[model] = info
	table.insert(info.conns, model:GetAttributeChangedSignal("Opened"):Connect(function()
		if model:GetAttribute("Opened") == true then playOpen(model, info) end
	end))
end

local function update()
	if next(tracked) == nil then return end
	local now = Workspace:GetServerTimeNow()
	for model, info in pairs(tracked) do
		if not model.Parent then
			untrack(model)
			continue
		end
		local land = model:GetAttribute("Land")
		local fromY = model:GetAttribute("FromY")
		local dropStart = model:GetAttribute("DropStart")
		local dropEnd = model:GetAttribute("DropEnd")
		if typeof(land) ~= "CFrame" or type(fromY) ~= "number" or type(dropStart) ~= "number" or type(dropEnd) ~= "number" then
			continue
		end
		if info.dropStart ~= dropStart then
			info.dropStart = dropStart
			info.settled = false
			clearPillar(info)
			if model:GetAttribute("Opened") ~= true then
				info.pillar = makePillar(land.Position)
				if model.PrimaryPart and not model.PrimaryPart:FindFirstChild("SupplyDropGlow") then
					local light = Instance.new("PointLight")
					light.Name = "SupplyDropGlow"
					light.Color = CFG.Color
					light.Range = CFG.LightRange
					light.Brightness = CFG.LightBrightness
					light.Shadows = false
					light.Parent = model.PrimaryPart
				end
			end
		end
		if info.settled then continue end

		local span = math.max(dropEnd - dropStart, 0.01)
		local t = (now - dropStart) / span
		if t < 1 then
			local clamped = math.max(t, 0)
			local y = fromY + (land.Position.Y - fromY) * clamped
			local sway = CFrame.identity
			if model:FindFirstChild(CFG.ParachuteName) then
				-- Bujanie gaśnie tuż nad dachem, żeby skrzynia siadała prosto.
				local amount = math.rad(CFG.SwayDegrees) * math.clamp((1 - clamped) * 6, 0, 1)
				local phase = now * math.pi * 2 * CFG.SwayHz
				sway = CFrame.Angles(math.sin(phase) * amount, 0, math.cos(phase * 0.8) * amount)
			end
			local p = land.Position
			model:PivotTo(CFrame.new(p.X, y, p.Z) * land.Rotation * sway)
		else
			info.settled = true
			model:PivotTo(land)
			-- Kurz tylko przy lądowaniu widzianym na żywo, nie u kogoś, kto dołączył później.
			if now - dropEnd < 1 then
				burst(land.Position + Vector3.new(0, 0.3, 0), SMOKE_TEXTURE, Color3.fromRGB(185, 170, 145), CFG.DustCount, 1.8, 14, 0)
				ExplosionFXController.playSoundAt(CFG.LandSoundId, land.Position, CFG.SoundVolume, 200)
				foldParachute(model)
			end
		end
	end
end

function SupplyDropController.init()
	if initialized then return end
	initialized = true

	RunService.RenderStepped:Connect(update)
	task.spawn(function()
		local folder = Workspace:WaitForChild(CFG.ActiveFolder)
		for _, c in ipairs(folder:GetChildren()) do track(c) end
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(function(c)
			if c:IsA("Model") then untrack(c) end
		end)
	end)
end

return SupplyDropController
