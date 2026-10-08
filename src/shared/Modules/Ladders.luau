--!strict
-- Ladders.luau (08.10) — „gdzie jest najbliższy szczebel drabiny”. Wspólne dla klienta
-- (LadderController: przyciąganie do drabiny) i serwera (FallDamageService: na drabinie licznik
-- upadku liczy się od nowa), żeby obie strony tak samo rozumiały, czym jest drabina.
--
-- Drabina = party z tagiem `Config.Ladder.Tag` (stawia je skrypt LADDERS_TAG.luau w Studio).
-- SZCZEBEL = otagowany part, którego najdłuższa oś jest pozioma, a dwie pozostałe cienkie;
-- szyny (pionowe) też mają tag, ale tu się nie liczą — z nich nie da się odczytać, z której
-- strony drabiny się stoi. Kawałki pocięte bombą tracą tag (copyAppearance go nie przenosi),
-- a spadające (niezakotwiczone) są pomijane — nie przyciągamy do lecącego gruzu.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local CFG = Config.Ladder
-- Grubość szczebla w dwóch krótszych osiach; szczeble na mapie mają 1×1 (zmierzone 08.10).
local MAX_RUNG_THICKNESS = 1.5

local Ladders = {}

export type Rung = {
	part: BasePart,
	along: Vector3,  -- pozioma oś szczebla (jednostkowa)
	halfLen: number,
	normal: Vector3, -- pozioma, od drabiny W STRONĘ zapytanego punktu
	front: number,   -- odległość punktu od płaszczyzny szczebla wzdłuż `normal`
	lateral: number, -- przesunięcie punktu wzdłuż `along` od środka szczebla
}

local tagged: { Instance } = {}
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local dirty = true
local listening = false

-- Lista otagowanych odświeżana leniwie: sygnały tylko zaznaczają, że się zmieniła (wybuch
-- kasuje szczeble po kilkanaście naraz — przebudowa raz, przy następnym zapytaniu).
local function refresh()
	if not listening then
		listening = true
		CollectionService:GetInstanceAddedSignal(CFG.Tag):Connect(function()
			dirty = true
		end)
		CollectionService:GetInstanceRemovedSignal(CFG.Tag):Connect(function()
			dirty = true
		end)
	end
	if not dirty then return end
	dirty = false
	tagged = CollectionService:GetTagged(CFG.Tag)
	params.FilterDescendantsInstances = tagged
end

local function rungAxis(part: BasePart): (Vector3?, number)
	local cf, s = part.CFrame, part.Size
	local axes = {
		{ dir = cf.RightVector, len = s.X },
		{ dir = cf.UpVector, len = s.Y },
		{ dir = cf.LookVector, len = s.Z },
	}
	table.sort(axes, function(a, b)
		return a.len > b.len
	end)
	local long = axes[1]
	if math.abs(long.dir.Y) > 0.3 or axes[2].len > MAX_RUNG_THICKNESS then
		return nil, 0
	end
	local flat = Vector3.new(long.dir.X, 0, long.dir.Z)
	if flat.Magnitude < 1e-3 then
		return nil, 0
	end
	return flat.Unit, long.len * 0.5
end

-- Najbliższy (w poziomie, przed płaszczyzną szczebli) szczebel w promieniu `radius` od
-- `position`, którego wysokość mieści się w [bandMin, bandMax]. Pasmo wysokości to „na
-- wysokości ciała” — bez niego postać stojąca na dachu nad drabiną byłaby ściągana z powrotem.
function Ladders.nearestRung(position: Vector3, bandMin: number, bandMax: number, radius: number): Rung?
	refresh()
	if #tagged == 0 then return nil end
	local best: Rung? = nil
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(position, radius, params)) do
		if not part.Anchored then continue end
		local y = part.Position.Y
		if y < bandMin or y > bandMax then continue end
		local along, halfLen = rungAxis(part)
		if not along then continue end
		local rel = position - part.Position
		local lateral = rel:Dot(along)
		if math.abs(lateral) > halfLen + CFG.LateralMargin then continue end
		local normal = Vector3.yAxis:Cross(along)
		local front = rel:Dot(normal)
		if front < 0 then
			normal = -normal
			front = -front
		end
		if not best or front < best.front then
			best = { part = part, along = along, halfLen = halfLen, normal = normal, front = front, lateral = lateral }
		end
	end
	return best
end

return Ladders
