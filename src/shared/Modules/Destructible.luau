--!strict
-- Destructible.luau
-- Single source of truth: CO wybuch może ruszyć, a czego nie tyka (system destrukcji v2).
--
-- Shared, bo odpowiedź musi być IDENTYCZNA po obu stronach:
--   serwer  — co realnie niszczy, tnie i pcha
--   klient  — z czego wolno rysować efekty zniszczenia (pył, odłamki)
-- Wcześniej klient nie miał tej wiedzy w ogóle i sypał pyłem oraz próbkował kolory
-- z partów oznaczonych jako nietykalne — Baseplate wyglądał, jakby się rozpadał, choć
-- wybuch go nie dotykał. Dwie kopie reguły to dwie okazje, żeby się rozjechały; stąd
-- jedno miejsce.
--
-- KONTRAKT MAPY (DESTRUCTION_PLAN.md):
--   nietykalne = `Locked = true` | pod `Workspace.Map.Locked` | pod `Workspace.ActiveCash`
--   niszczalne = pod `Workspace.Map` | pod `Workspace.ActiveBridges` (sabotaż PvP)
--   drobnica   = mała objętość albo za krótki na cięcie (`Config.Destruction.Small`, v3)
--   mebel      = Model z samej drobnicy, do ~18 studów — pada w CAŁOŚCI (`assemblyOf`)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local SMALL = Config.Destruction.Small

local Destructible = {}

-- Kontekst rozwiązywany RAZ na wybuch zamiast per part — przy ~150 kandydatach
-- oszczędza kilkaset FindFirstChild.
export type Context = {
	map: Instance?,
	lockedFolder: Instance?,
	activeCash: Instance?,
	activeBridges: Instance?,
}

function Destructible.buildContext(): Context
	local map = Workspace:FindFirstChild("Map")
	return {
		map = map,
		lockedFolder = map and map:FindFirstChild("Locked") or nil,
		activeCash = Workspace:FindFirstChild("ActiveCash"),
		activeBridges = Workspace:FindFirstChild("ActiveBridges"),
	}
end

-- Nietykalne dla wybuchu:
--   1. property Locked=true (Baseplate, LavaPart, Lobby.Spawn, platformy Kacpra które
--      mają wisieć w powietrzu z designu)
--   2. Workspace.Map.Locked (geometria nieusuwalna)
--   3. Workspace.ActiveCash (rozrzucony cash miałby magnet, ale lot do gracza przez pół mapy)
-- Mosty (ActiveBridges) CELOWO nie są chronione — sabotaż PvP.
function Destructible.isProtected(part: BasePart, ctx: Context): boolean
	if part.Locked then return true end
	if ctx.lockedFolder and part:IsDescendantOf(ctx.lockedFolder) then return true end
	if ctx.activeCash and part:IsDescendantOf(ctx.activeCash) then return true end
	return false
end

-- Co wolno NISZCZYĆ (fracture/launch): geometria mapy + mosty. Nic spoza tych korzeni —
-- wybuch nie może rozbierać lobby, ragdoll toolboxa ani niczego postawionego luzem.
function Destructible.isDestructible(part: BasePart, ctx: Context): boolean
	if ctx.map and part:IsDescendantOf(ctx.map) then return true end
	if ctx.activeBridges and part:IsDescendantOf(ctx.activeBridges) then return true end
	return false
end

-- Skrót dla strony klienckiej (FX): czy z tego parta wolno rysować efekty zniszczenia.
-- Terrain i postacie odpadają razem z chronionymi — nigdy nie są źródłem gruzu.
function Destructible.canSpawnFXFrom(part: BasePart, ctx: Context): boolean
	if part:IsA("Terrain") then return false end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return false end
	if Destructible.isProtected(part, ctx) then return false end
	return true
end

-- ============================================================================
-- DROBNICA i MEBLE (v3, 2026-09-23)
-- ============================================================================

-- Drobnica: mała objętość ALBO za krótka, żeby ją przeciąć na dwa kawałki. Nie ma HP,
-- nie pęka na kawałki, nie jest gruzem serwera i nie bierze udziału w grafie podparcia —
-- serwer przekazuje ją klientom do animacji. Zmierzone: 78% partów mapy to drobnica.
function Destructible.isSmall(part: BasePart): boolean
	local s = part.Size
	return s.X * s.Y * s.Z < SMALL.MaxVolume or math.max(s.X, s.Y, s.Z) < SMALL.MinCutSize
end

-- Werdykt per Model trzymany do końca życia modelu. Słabe klucze: MapService po rundzie
-- podmienia mapę na świeże klony, stare modele znikają i same wypadają z cache.
local assemblyVerdict: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Czy model może paść jako JEDEN mebel. Warunki (każdy z powodem):
--   * sama drobnica — model z dużą bryłą (automat, lada, schody) bywa elementem
--     rozgrywki, na którym się stoi; ten pęka jak ściany, nie znika w całości
--   * wszystko zakotwiczone — model z luźnymi częściami to fizyka, nie statyczny mebel
--   * nic chronionego — Locked to kontrakt „nigdy nie ruszać” (np. szyby samochodów)
--   * bez Humanoida i w limitach rozmiaru/liczby — „Map” opakowujący całe miasto to też Model
local function qualifies(model: Model, ctx: Context): boolean
	local cached = assemblyVerdict[model]
	if cached ~= nil then return cached end

	local ok = true
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") then
			ok = false
			break
		end
		if d:IsA("BasePart") then
			count += 1
			if count > SMALL.AssemblyMaxParts
				or not d.Anchored
				or not Destructible.isSmall(d)
				or Destructible.isProtected(d, ctx)
			then
				ok = false
				break
			end
		end
	end
	if ok and count == 0 then
		ok = false
	end
	if ok then
		local _, size = model:GetBoundingBox()
		if math.max(size.X, size.Y, size.Z) > SMALL.AssemblyMaxSize then
			ok = false
		end
	end

	assemblyVerdict[model] = ok
	return ok
end

-- ============================================================================
-- REKWIZYTY (2026-09-24) — wszystko w folderze dekoracji budynku
-- ============================================================================
-- Rekwizyt NIGDY nie jest cięty jak ściana: pada albo odlatuje w całości (cały mebel).
-- Powód (test 24.09): szafki, szafy, regały, łóżka, sofy, automaty i pudła mają duże party,
-- więc szły ścieżką ścian — dostawały poszarpane dziury, a ich drobne części (uchwyty,
-- półki) odpadały osobno. Wynik: „pobugowane” pół-meble.

local PROPS = Config.Destruction.Props
local propVerdict: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function propQualifies(model: Model, ctx: Context): boolean
	local cached = propVerdict[model]
	if cached ~= nil then return cached end
	local ok = true
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Humanoid") then
			ok = false
			break
		end
		if d:IsA("BasePart") then
			count += 1
			if count > PROPS.MaxParts or not d.Anchored or Destructible.isProtected(d, ctx) then
				ok = false
				break
			end
		end
	end
	if ok and count == 0 then
		ok = false
	end
	if ok then
		local _, size = model:GetBoundingBox()
		ok = math.max(size.X, size.Y, size.Z) <= PROPS.MaxSize
	end
	propVerdict[model] = ok
	return ok
end

-- Jednostka-rekwizyt dla parta: najwyższy kwalifikujący się Model pod folderem dekoracji,
-- albo sam part (gdy mieści się w MaxSize). nil = to nie rekwizyt (poza dekoracjami albo za
-- duży — dywan 63×63, płot 53 — taki zostaje przy zwykłych regułach).
function Destructible.propOf(part: BasePart, ctx: Context): Instance?
	local node = part.Parent
	local inProps = false
	while node and node ~= Workspace and node ~= ctx.map do
		if PROPS.Folders[node.Name] then
			inProps = true
			break
		end
		node = node.Parent
	end
	if not inProps then
		return nil
	end
	local best: Instance? = nil
	node = part.Parent
	while node and not PROPS.Folders[node.Name] do
		if node:IsA("Model") then
			if propQualifies(node, ctx) then
				best = node
			else
				break
			end
		end
		node = node.Parent
	end
	if best then
		return best
	end
	local s = part.Size
	if math.max(s.X, s.Y, s.Z) <= PROPS.MaxSize then
		return part
	end
	return nil
end

-- Kategoria rekwizytu (26.09, decyzje Kacpra): "vaporize" — znika z obłokiem (wieszaki
-- i drobne), "furniture" — mebel (odpychany, rozpada się od drugiego trafienia), nil — to nie
-- rekwizyt. Po nazwie folderu między jednostką a folderem dekoracji, więc Kacper przenosi
-- kategorię między grupami samą listą `Props.Vaporize`.
function Destructible.propCategory(unit: Instance): string?
	local node: Instance? = unit
	local vaporize = false
	while node and node ~= Workspace do
		if PROPS.Folders[node.Name] then
			return if vaporize then "vaporize" else "furniture"
		end
		if PROPS.Vaporize[node.Name] then
			vaporize = true
		end
		node = node.Parent
	end
	return nil
end

-- Jednostka, która pada razem z tym partem: NAJWIĘKSZY kwalifikujący się Model nad nim
-- (ubranie → wieszak z całym stojakiem), albo sam part, gdy żaden model się nie nadaje.
-- Idziemy w górę przez foldery; pierwszy model, który się NIE nadaje, kończy szukanie —
-- przodek ma bbox i liczbę partów co najmniej takie same, więc też by się nie nadał.
function Destructible.assemblyOf(part: BasePart, ctx: Context): Instance
	local best: Instance = part
	local node = part.Parent
	while node and node ~= Workspace and node ~= ctx.map do
		if node:IsA("Model") then
			if qualifies(node, ctx) then
				best = node
			else
				break
			end
		end
		node = node.Parent
	end
	return best
end

return Destructible
