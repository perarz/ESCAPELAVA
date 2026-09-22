-- ESCAPE LAVA — latarnie uliczne (Workspace.Map...OutsideDecorations.Lamps)
-- Wklej w Command Bar w Studio (EDIT mode, nie Play), odkomentuj JEDEN tryb na dole.
-- ⚠️ Po uruchomieniu Cmd+S — zmiany w datamodelu Studio giną bez zapisu.
--
-- KONTRAKT: 36 modeli `Lamp`, w kazdym dokladnie jeden klosz `1x1x2` z `Material = Neon`
-- i dzieckiem `LampLight` (`SurfaceLight`, `Face = Bottom`). Klosze sa NIEOBROCONE
-- (zweryfikowane 36/36, max odchylenie 0.00 stopnia), wiec Bottom patrzy w dol wszedzie.
--
-- ⚠️ DLACZEGO KLOSZA NIE SZUKAMY PO `Material == Neon` (lekcja 2026-09-20):
-- poprzednia wersja tak robila i przestala dzialac w momencie, w ktorym byla POTRZEBNA.
-- Kacper zrobil bulk-apply materialu mapy i wszystkie 216 partow latarni dostaly
-- `Material = Plastic` + `MaterialVariant = "Studs"` — czyli neon zniknal, a finder
-- oparty na neonie znajdowal ZERO partow i skrypt naprawczy po cichu nic nie robil.
-- **Nie szukaj po wlasciwosci, ktora ten skrypt ma naprawiac.** Dlatego identyfikacja
-- idzie po ROZMIARZE (1x1x2 — dokladnie 36 sztuk, po jednym na model) i po obecnosci
-- `LampLight`; neon jest tylko trzecim, pomocniczym tropem.

local LAMPS = workspace.Map.Map.Map.OutsideDecorations.Lamps

local EXPECTED = 36
local GLASS_SIZE = Vector3.new(1, 1, 2)

local SETTINGS = {
	Color = Color3.fromRGB(255, 205, 130), -- cieply bursztyn; czysta zolc czyta sie chorobliwie
	Brightness = 2,                        -- ClockTime 15 = dzien, wiec potrzeba troche mocy
	Range = 26,                            -- klosz wisi 15 stud nad ulica; lampy stoja 25.5 od siebie
	Angle = 120,                           -- rozwarcie stozka SurfaceLight (0..180)
	Shadows = false,                       -- pod ShadowMap swiatla lokalne i tak nie rzucaja cieni
}

-- Kolor samego klosza. `nil` = NIE RUSZAJ (wyglad nalezy do Kacpra). Material Neon swieci
-- wlasnym `Color` na pelnej jasnosci, wiec obecne (160,148,60) da przygaszona zolc.
local GLASS_COLOR = nil

local function isGlass(part)
	if not part:IsA("BasePart") then return false end
	return (part.Size - GLASS_SIZE).Magnitude < 0.01
		or part:FindFirstChild("LampLight") ~= nil
		or part.Material == Enum.Material.Neon
end

local function eachGlass(fn)
	local n = 0
	for _, model in ipairs(LAMPS:GetChildren()) do
		for _, d in ipairs(model:GetDescendants()) do
			if isGlass(d) then
				n += 1
				fn(d)
			end
		end
	end
	-- Glosno, bo cicha porazka tego skryptu wyglada identycznie jak sukces.
	if n ~= EXPECTED then
		warn(("[Lamps] znaleziono %d kloszy zamiast %d — sprawdz kontrakt (rozmiar %s / dziecko LampLight)")
			:format(n, EXPECTED, tostring(GLASS_SIZE)))
	end
	return n
end

-- TRYB 1: pelna naprawa — material klosza + swiatlo. Idempotentne.
local function apply()
	local neon, cleared = 0, 0
	local n = eachGlass(function(part)
		if part.Material ~= Enum.Material.Neon then
			part.Material = Enum.Material.Neon
			neon += 1
		end
		-- Wariant `Studs` ma BaseMaterial = Plastic, wiec przy Neonie i tak sie nie stosuje.
		-- Czyscimy go mimo to: zostawiony wrocilby w chwili, w ktorej klosz kiedykolwiek
		-- wrocilby na Plastic, i bug odtworzylby sie sam.
		if part.MaterialVariant ~= "" then
			part.MaterialVariant = ""
			cleared += 1
		end
		if GLASS_COLOR then part.Color = GLASS_COLOR end

		local light = part:FindFirstChild("LampLight")
		if not light or not light:IsA("SurfaceLight") then
			if light then light:Destroy() end
			light = Instance.new("SurfaceLight")
			light.Name = "LampLight"
			light.Parent = part
		end
		light.Face = Enum.NormalId.Bottom
		for k, v in pairs(SETTINGS) do
			light[k] = v
		end
		light.Enabled = true
	end)
	print(("[Lamps] klosze: %d | przywrocony Neon: %d | wyczyszczony MaterialVariant: %d"):format(n, neon, cleared))
end

-- TRYB 2: usun same swiatla (klosz zostaje neonowy)
local function remove()
	local removed = 0
	eachGlass(function(part)
		local light = part:FindFirstChild("LampLight")
		if light then
			light:Destroy()
			removed += 1
		end
	end)
	print(("[Lamps] usuniete swiatla: %d"):format(removed))
end

-- TRYB 3: zamiana na PointLight (gdyby SurfaceLight nie pasowal)
-- ⚠️ PointLight swieci TEZ w gore, prosto w klosz nad neonem (part 3x1x7, 1 stud wyzej) —
-- a pod ShadowMap swiatlo lokalne nie rzuca cienia, wiec przez ten klosz przeswieci
-- zamiast sie na nim zatrzymac. SurfaceLight tej polowy po prostu nie emituje.
local function toPointLight()
	local n = eachGlass(function(part)
		local old = part:FindFirstChild("LampLight")
		if old then old:Destroy() end
		local light = Instance.new("PointLight")
		light.Name = "LampLight"
		light.Color = SETTINGS.Color
		light.Brightness = SETTINGS.Brightness
		light.Range = SETTINGS.Range
		light.Shadows = SETTINGS.Shadows
		light.Parent = part
	end)
	print(("[Lamps] zamienione na PointLight: %d"):format(n))
end

apply()
-- remove()
-- toPointLight()
