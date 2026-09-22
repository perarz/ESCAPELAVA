--!strict
-- Utils.luau
-- Drobne helpery używane w serwisach i kontrolerach.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = {}

-- "M:SS" — np. 125 → "2:05"
function Utils.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local m = math.floor(s / 60)
	local sec = s % 60
	return string.format("%d:%02d", m, sec)
end

-- Zwraca HumanoidRootPart jeśli postać istnieje i jest spawned, inaczej nil.
function Utils.getRoot(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- SurfaceType nowego parta: `Instance.new("Part")` ma LEGACY defaulty
-- TopSurface=Studs / BottomSurface=Inlet (a WedgePart Bottom=Inlet). To GUZKI
-- geometryczne, nie tekstura (studsy mapy robi MaterialVariant — patrz copyAppearance).
-- Mapa ma wszystkie 6 ścian Smooth, więc part bez jawnych surface'ów od niej odstaje.
local FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

-- Kopiuje wygląd krawędzi z oryginału. Używane wszędzie, gdzie part POWSTAJE Z innego
-- parta (gruz, remnant po pęknięciu) — wtedy kawałek dziedziczy styl budowniczego,
-- niezależnie od tego, czy Kacper buduje na Smooth czy na Studs.
function Utils.copySurfaces(source: BasePart, target: BasePart)
	for _, face in ipairs(FACES) do
		(target :: any)[face] = (source :: any)[face]
	end
end

-- Wszystkie ściany gładkie — dla partów, które nie mają oryginału do dziedziczenia.
function Utils.smoothSurfaces(part: BasePart)
	for _, face in ipairs(FACES) do
		(part :: any)[face] = Enum.SurfaceType.Smooth
	end
end

-- Połowa wysokości parta W ŚWIECIE (uwzględnia obrót) — górna krawędź to
-- `Position.Y + worldHalfY`, dolna `Position.Y - worldHalfY`. Potrzebne wszędzie, gdzie
-- pytamy "co jest nad/pod czym": pass podparcia, usypianie gruzu, kasowanie w lawie.
function Utils.worldHalfY(part: BasePart): number
	local cf = part.CFrame
	local s = part.Size * 0.5
	return math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z
end

-- Pełny wygląd parta: kolor, materiał, WARIANT materiału, przezroczystość, odbicie,
-- cień, surface'y. Jedyne miejsce, które o tym decyduje — gruz, remnanty i kawałki
-- z fall-fracture mają wyglądać dokładnie jak part, z którego powstały.
--
-- `MaterialVariant` to osobna właściwość od `Material` i JEST kluczowa w tym projekcie:
-- cała mapa Kacpra to Material=Plastic + MaterialVariant="Studs" (MaterialVariant
-- w MaterialService z teksturą studsów). Skopiowanie samego `Material` daje gładki
-- plastik — stąd "party po wybuchu zmieniają teksturę". Ustawiane PO `Material`,
-- bo wariant ma sens tylko przy zgodnym BaseMaterial.
function Utils.copyAppearance(source: BasePart, target: BasePart)
	target.Color = source.Color
	target.Material = source.Material
	target.MaterialVariant = source.MaterialVariant
	target.Transparency = source.Transparency
	target.Reflectance = source.Reflectance
	target.CastShadow = source.CastShadow
	Utils.copySurfaces(source, target)
end

-- ============================================================================
-- MODELE-ASSETY Z ReplicatedStorage (bomba w ręce, blueprint, most)
-- ============================================================================
-- Kacper wrzuca gotowe modele, kod ma się do nich dostosować — nie odwrotnie. Te helpery
-- są SHARED, bo wymiary muszą wyjść IDENTYCZNE na serwerze i u klienta: serwer stawia most,
-- klient rysuje jego ghost, i gdyby liczyły inaczej, podgląd kłamałby o tym, co powstanie.

-- Rozmiar assetu = bounding box modelu (w przestrzeni jego pivota). Wynik cache'owany:
-- to stała, a `GetBoundingBox` na kilkunastu partach wołane co klatkę przy ghoście byłoby
-- czystym marnotrawstwem. Cache trzyma też "pudło" (false), żeby nie szukać w kółko.
local assetSizeCache: { [string]: Vector3 | boolean } = {}

function Utils.getAsset(name: string): Instance?
	local inst = ReplicatedStorage:FindFirstChild(name)
	return inst
end

function Utils.assetSize(name: string): Vector3?
	local cached = assetSizeCache[name]
	if cached ~= nil then
		return if typeof(cached) == "Vector3" then cached else nil
	end
	local inst = ReplicatedStorage:FindFirstChild(name)
	local size: Vector3? = nil
	if inst and inst:IsA("Model") then
		local _cf, s = inst:GetBoundingBox()
		size = s
	elseif inst and inst:IsA("BasePart") then
		size = inst.Size
	end
	assetSizeCache[name] = size or false
	return size
end

-- Największy part objętościowo — kandydat na Handle Toola i na PrimaryPart projektyla.
-- Objętość, a nie pierwszy z brzegu: w bombie największa bryła to kula, do której reszta
-- (lont, okucia) jest tylko doczepiona — i to ona ma nieść fizykę oraz siedzieć w dłoni.
function Utils.largestPart(model: Instance): BasePart?
	local best: BasePart? = nil
	local bestVol = -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if vol > bestVol then
				bestVol = vol
				best = d
			end
		end
	end
	return best
end

-- Środek bounding boxa modelu ląduje dokładnie w `cf`. NIE `PivotTo(cf)`: pivot bywa
-- ustawiony gdziekolwiek (róg, punkt obrotu), a my pozycjonujemy to, co widać — inaczej
-- most postawiony „w kursorze" wylądowałby obok niego o połowę swojej długości.
function Utils.setModelCenter(model: Model, cf: CFrame)
	local bbCF = model:GetBoundingBox()
	local pivot = model:GetPivot()
	-- Gdzie jest środek bbox względem pivota → tyle samo kompensujemy w drugą stronę.
	model:PivotTo(cf * pivot:ToObjectSpace(bbCF):Inverse())
end

-- Zamienia model w JEDNĄ bryłę fizyczną: wszystko przyspawane do `primary`.
-- ⚠️ KOLEJNOŚĆ MA ZNACZENIE i jest źródłem klasycznego buga „model rozpadł się w locie":
-- welds tworzymy, gdy party stoją jeszcze na swoich miejscach i są ZAKOTWICZONE, a dopiero
-- potem je odkotwiczamy i wpuszczamy do Workspace. Odwrotna kolejność daje jedną klatkę,
-- w której części są luźne — i rozjeżdżają się, zanim weld zdąży je złapać.
-- Wołać PO ustawieniu pozycji modelu, PRZED parentowaniem do Workspace.
function Utils.weldModel(model: Instance, primary: BasePart)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = d
			weld.Parent = primary
		end
	end
	-- Odkotwiczenie dopiero po spięciu całości.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
end

return Utils
