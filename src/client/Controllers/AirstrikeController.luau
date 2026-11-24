--!strict
-- AirstrikeController.luau (24.11) — rakiety nalotu u klienta. Serwer (AirstrikeService) przysyła
-- całą salwę naraz (`AirstrikeRockets`: start, kierunek, chwila startu) i sam liczy lot; tu KOPIA
-- każdej rakiety leci po tej samej prostej z czasu serwera, a `AirstrikeRocketEnded` ją zdejmuje.
-- Wybuch, gruz i wstrząs rysują ExplosionFXController / DebrisFXController z BlastFX, jak przy bombie.
--
-- Czysta kosmetyka: bez kolizji, promieni i dotyku, `Locked` (lekcja 10 i pułapka próbkowania
-- kolorów przez DebrisFXController).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local SettingsState = require(script.Parent.SettingsState)

local CFG = Config.Airstrike

local AirstrikeController = {}

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Visual = {
	model: Model,
	origin: Vector3,
	dir: Vector3,
	at: number,
	deadline: number,
	started: boolean,
}
local visuals: { [number]: Visual } = {}
local warned = false
local initialized = false

local function makeMissile(): Model?
	local template = ReplicatedStorage:FindFirstChild(CFG.MissileModel)
	if not (template and template:IsA("Model") and template.PrimaryPart) then
		if not warned then
			warned = true
			warn(("[AirstrikeController] brak ReplicatedStorage.%s (Model z PrimaryPart) — rakiety bez wyglądu"):format(CFG.MissileModel))
		end
		return nil
	end
	local model = template:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Locked = true
			d.CastShadow = false
		end
	end
	local primary = model.PrimaryPart :: BasePart
	local tail = Vector3.new(0, 0, primary.Size.Z * 0.5)

	local a0 = Instance.new("Attachment")
	a0.Position = tail + Vector3.new(0, CFG.TrailWidth * 0.5, 0)
	a0.Parent = primary
	local a1 = Instance.new("Attachment")
	a1.Position = tail - Vector3.new(0, CFG.TrailWidth * 0.5, 0)
	a1.Parent = primary
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = CFG.TrailLifetime
	trail.Color = ColorSequence.new(CFG.TrailColor)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Parent = primary

	local tailAttachment = Instance.new("Attachment")
	tailAttachment.Position = tail
	tailAttachment.Parent = primary
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(CFG.SmokeColor)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Speed = NumberRange.new(0, 2)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.Rate = CFG.SmokeRate * (if SettingsState.get("graphics") == "low" then CFG.LowGraphicsSmokeFactor else 1)
	smoke.Parent = tailAttachment

	local light = Instance.new("PointLight")
	light.Color = CFG.LightColor
	light.Range = CFG.LightRange
	light.Brightness = CFG.LightBrightness
	light.Shadows = false
	light.Parent = tailAttachment

	if CFG.WhistleSoundId ~= "" then
		local whistle = Instance.new("Sound")
		whistle.SoundId = CFG.WhistleSoundId
		whistle.Volume = CFG.WhistleVolume
		whistle.RollOffMaxDistance = 350
		whistle.Parent = primary
	end
	return model
end

local function finish(id: number)
	local v = visuals[id]
	if not v then return end
	visuals[id] = nil
	-- Smuga i dym gasną po swoim czasie, a nie znikają razem z rakietą.
	for _, d in ipairs(v.model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("PointLight") then
			d.Enabled = false
		elseif d:IsA("Sound") then
			d:Stop()
		end
	end
	task.delay(1.5, function()
		v.model:Destroy()
	end)
end

local function update()
	if next(visuals) == nil then return end
	local now = Workspace:GetServerTimeNow()
	for id, v in pairs(visuals) do
		if now > v.deadline then
			finish(id)
			continue
		end
		local t = now - v.at
		if t < 0 then continue end
		local pos = v.origin + v.dir * (CFG.Speed * t)
		v.model:PivotTo(CFrame.lookAt(pos, pos + v.dir))
		if not v.started then
			-- Do sceny dopiero w chwili startu i po ustawieniu pozycji: smuga nie ciągnie się
			-- z miejsca, w którym stał szablon.
			v.started = true
			v.model.Parent = Workspace
			local whistle = v.model.PrimaryPart and v.model.PrimaryPart:FindFirstChildOfClass("Sound")
			if whistle then whistle:Play() end
		end
	end
end

local function clearAll()
	for id, v in pairs(visuals) do
		visuals[id] = nil
		v.model:Destroy()
	end
end

function AirstrikeController.init()
	if initialized then return end
	initialized = true

	Remotes.AirstrikeRockets.OnClientEvent:Connect(function(rockets: any)
		if type(rockets) ~= "table" then return end
		for _, r in ipairs(rockets) do
			if type(r) ~= "table" or type(r.id) ~= "number" or type(r.at) ~= "number"
				or typeof(r.origin) ~= "Vector3" or typeof(r.dir) ~= "Vector3" then
				continue
			end
			local model = makeMissile()
			if not model then return end
			visuals[r.id] = {
				model = model,
				origin = r.origin,
				dir = r.dir,
				at = r.at,
				deadline = r.at + CFG.MaxRange / CFG.Speed + CFG.VisualLinger,
				started = false,
			}
		end
	end)
	Remotes.AirstrikeRocketEnded.OnClientEvent:Connect(function(id: any)
		if type(id) == "number" then finish(id) end
	end)
	-- Runda się skończyła z rakietami w powietrzu: serwer je skasował razem z mapą.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
		if newState == "LOBBY" or newState == "PREPARING" then clearAll() end
	end)
	RunService.RenderStepped:Connect(update)
end

return AirstrikeController
