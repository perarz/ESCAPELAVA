--!strict
-- ItemPickupFx.luau (15.11) — wygląd leżących itemów zależnie od rzadkości. Helper, nie kontroler
-- (nie ma init): woła go ItemPickupController przy postawieniu i zdjęciu itemu.
--
-- Decyzje Kacpra 15.11: aura (drobinki) + światło dla wszystkich, siła rośnie z rzadkością;
-- obrys; snop światła w górę tylko przy najlepszych (EPIC, LEGENDARY). Rzadkości i kolory jak
-- w COSMETICS (`Config.Cosmetics.UI.Rarities[...].Accent`) — jedna paleta w całej grze.
--
-- Wszystko lokalne i bez fizyki: emitery, światło i obrys wiszą na częściach modelu, snop to Beam
-- na Attachmentach w Terrain. Nic tu nie ma kolizji ani nie łapie promieni (lekcja 10).
--
-- OBRYS: Roblox rysuje najwyżej 31 Highlightów naraz, a itemów w rundzie jest 27 (plus duch
-- drabiny), więc obrys dostaje tylko `OutlineMax` najbliższych w `OutlineDistance`. DepthMode
-- Occluded — obrys nie świeci przez ściany, bo to zdradzałoby itemy schowane w budynkach.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.ItemPickup.FX
local RARITIES = Config.Cosmetics.UI.Rarities

local ItemPickupFx = {}

export type Handle = {
	model: Model,
	center: Vector3,
	tier: any,
	color: Color3,
	emitter: ParticleEmitter?,
	highlight: Highlight?,
	pillar: { Instance },
}

local function tierOf(itemId: string): (any, Color3)
	local name = CFG.Rarity[itemId] or "Common"
	local tier = CFG.Tiers[name] or CFG.Tiers.Common
	local rarity = RARITIES[name] or RARITIES.Common
	return tier, rarity.Accent
end

-- center = środek bryły (ten sam, wokół którego kontroler kręci model).
function ItemPickupFx.attach(model: Model, itemId: string, center: Vector3, lowGraphics: boolean): Handle?
	local primary = model.PrimaryPart
	if not primary then return nil end
	local tier, color = tierOf(itemId)
	local handle: Handle = { model = model, center = center, tier = tier, color = color, emitter = nil, highlight = nil, pillar = {} }

	-- Nazwa w prompcie w kolorze rzadkości (PromptController czyta `TitleColor`; lokalnie).
	local prompt = primary:FindFirstChildWhichIsA("ProximityPrompt")
	if prompt then prompt:SetAttribute("TitleColor", color) end

	-- Aura: drobinki z bryły największej części modelu, w górę.
	local e = Instance.new("ParticleEmitter")
	e.Name = "PickupAura"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, CFG.ParticleSize), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = CFG.ParticleLifetime
	e.Speed = CFG.ParticleSpeed
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, CFG.ParticleRise, 0)
	e.Rate = tier.Particles * (if lowGraphics then CFG.LowGraphicsParticleFactor else 1)
	e.Parent = primary
	handle.emitter = e

	local light = Instance.new("PointLight")
	light.Name = "PickupGlow"
	light.Color = color
	light.Brightness = tier.LightBrightness
	light.Range = tier.LightRange
	light.Shadows = false
	light.Parent = primary

	if tier.Pillar then
		-- Attachmenty w świecie, nie na modelu: model się kręci, a snop ma stać prosto.
		-- 15.11 (Kacper: „nie przez sufit”): snop kończy się pod pierwszym stropem nad itemem —
		-- inaczej przebijał piętra i świecił w pokojach wyżej. Pod gołym niebem pełna wysokość.
		local terrain = Workspace.Terrain
		local bottomPos = center - Vector3.new(0, Config.ItemPickup.HeightOffset, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		params.RespectCanCollide = true
		local ceiling = Workspace:Raycast(center, Vector3.new(0, CFG.PillarHeight, 0), params)
		local topY = if ceiling then ceiling.Position.Y - 0.1 else bottomPos.Y + CFG.PillarHeight
		local bottom = Instance.new("Attachment")
		bottom.Name = "PickupPillarBottom"
		bottom.WorldPosition = bottomPos
		bottom.Parent = terrain
		local top = Instance.new("Attachment")
		top.Name = "PickupPillarTop"
		top.WorldPosition = Vector3.new(bottomPos.X, topY, bottomPos.Z)
		top.Parent = terrain
		local beam = Instance.new("Beam")
		beam.Name = "PickupPillar"
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = CFG.PillarWidth
		beam.Width1 = CFG.PillarWidth * 0.4
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, CFG.PillarTransparency),
			NumberSequenceKeypoint.new(0.7, math.min(1, CFG.PillarTransparency + 0.35)),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = terrain
		handle.pillar = { beam, bottom, top }
	end
	return handle
end

function ItemPickupFx.setLowGraphics(handle: Handle, low: boolean)
	if handle.emitter then
		handle.emitter.Rate = handle.tier.Particles * (if low then CFG.LowGraphicsParticleFactor else 1)
	end
end

local function setOutline(handle: Handle, on: boolean)
	if on and not handle.highlight then
		local h = Instance.new("Highlight")
		h.Name = "PickupOutline"
		h.Adornee = handle.model
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.FillTransparency = 1
		h.OutlineColor = handle.color
		h.OutlineTransparency = handle.tier.Outline
		h.Parent = handle.model
		handle.highlight = h
	elseif not on and handle.highlight then
		handle.highlight:Destroy()
		handle.highlight = nil
	end
end

-- Obrys tylko na `OutlineMax` najbliższych w zasięgu (limit silnika 31 Highlightów na klienta).
function ItemPickupFx.updateOutlines(handles: { Handle }, from: Vector3)
	local maxDistSq = CFG.OutlineDistance * CFG.OutlineDistance
	local inRange: { { h: Handle, d: number } } = {}
	for _, h in ipairs(handles) do
		local d = (h.center - from).Magnitude ^ 2
		if d <= maxDistSq then
			table.insert(inRange, { h = h, d = d })
		else
			setOutline(h, false)
		end
	end
	table.sort(inRange, function(a, b) return a.d < b.d end)
	for i, entry in ipairs(inRange) do
		setOutline(entry.h, i <= CFG.OutlineMax)
	end
end

function ItemPickupFx.detach(handle: Handle)
	for _, inst in ipairs(handle.pillar) do
		inst:Destroy()
	end
	table.clear(handle.pillar)
	if handle.highlight then
		handle.highlight:Destroy()
		handle.highlight = nil
	end
	-- Emiter i światło giną razem z modelem (serwer go niszczy).
end

return ItemPickupFx
