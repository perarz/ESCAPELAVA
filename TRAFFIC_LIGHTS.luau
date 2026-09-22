-- ESCAPE LAVA — zarowki sygnalizatorow (Workspace.Map...OutsideDecorations.TrafficLights)
-- Wklej w Command Bar w Studio (EDIT mode, nie Play). ⚠️ Po uruchomieniu Cmd+S.
--
-- KONTRAKT: 25 modeli `TrafficLights`, kazdy po 12 partow = 2 glowice x 3 zarowki
-- plus szara konstrukcja (maszt, wysiegnik, podstawa, obudowy).
-- ZAROWKA = part `0.10x0.80x0.80`. Jest ich dokladnie 150 i wszystkie sa jednym
-- z trzech kolorow: czerwony (195,20,20), zolty (215,206,78), zielony (52,165,56).
--
-- ⚠️ PO CO TO ISTNIEJE (lekcja 2026-09-20): bulk-apply materialu mapy
-- (`Plastic` + `MaterialVariant = "Studs"`) zmiata `Material = Neon` z calej gałęzi
-- dekoracji naraz — poleglo na tym 36 kloszy latarni i 150 zarowek sygnalizatorow.
-- Objaw jest cichy: nic nie znika, rzeczy po prostu przestaja swiecic.
--
-- ⚠️ IDENTYFIKACJA IDZIE PO ROZMIARZE, NIE PO `Material == Neon` — czyli NIE po tej
-- wlasciwosci, ktora ten skrypt naprawia. Ta sama pulapka wylozyla wczesniejsza wersje
-- LAMPS_LIGHTS.luau: finder oparty na neonie znajdowal zero partow dokladnie wtedy,
-- kiedy byl potrzebny, i skrypt po cichu nie robil nic.
--
-- 💡 ŚWIADOMIE NIE DODAJEMY TU ZRODEL SWIATLA. 150 PointLightow to koszt, ktorego
-- dekoracja tla nie jest warta (latarnie maja 36 SurfaceLightow i to juz jest budzet).
-- Neon swieci sam z siebie — jest widoczny, ale nie oswietla otoczenia i nic nie kosztuje.

local ROOT = workspace.Map.Map.Map.OutsideDecorations.TrafficLights

local EXPECTED = 150
local BULB_SIZE = Vector3.new(0.10, 0.80, 0.80)
local ZNANE = {
	["195,20,20"] = "czerwony",
	["215,206,78"] = "zolty",
	["52,165,56"] = "zielony",
}

local function key(c)
	return ("%d,%d,%d"):format(math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5))
end

local function isBulb(p)
	return p:IsA("BasePart") and (p.Size - BULB_SIZE).Magnitude < 0.01
end

-- TRYB 1: przywroc Neon na zarowkach (idempotentne)
local function apply()
	local n, neon, cleared = 0, 0, 0
	local wg, obce = {}, {}
	for _, d in ipairs(ROOT:GetDescendants()) do
		if isBulb(d) then
			n += 1
			local k = key(d.Color)
			wg[k] = (wg[k] or 0) + 1
			if not ZNANE[k] then obce[k] = (obce[k] or 0) + 1 end
			if d.Material ~= Enum.Material.Neon then
				d.Material = Enum.Material.Neon
				neon += 1
			end
			-- Wariant `Studs` ma BaseMaterial = Plastic, wiec przy Neonie sie nie stosuje.
			-- Czyscimy mimo to: zostawiony wrocilby, gdyby part kiedys wrocil na Plastic.
			if d.MaterialVariant ~= "" then
				d.MaterialVariant = ""
				cleared += 1
			end
		end
	end
	print(("[TrafficLights] zarowki: %d | przywrocony Neon: %d | wyczyszczony MaterialVariant: %d"):format(n, neon, cleared))
	for k, c in pairs(wg) do
		print(("   (%s) %-9s x%d"):format(k, ZNANE[k] or "NIEZNANY", c))
	end
	if n ~= EXPECTED then
		warn(("[TrafficLights] znaleziono %d zarowek zamiast %d — sprawdz kontrakt rozmiaru %s")
			:format(n, EXPECTED, tostring(BULB_SIZE)))
	end
	for k, c in pairs(obce) do
		warn(("[TrafficLights] %d zarowek ma nieznany kolor (%s) — sprawdz, czy to na pewno zarowka"):format(c, k))
	end
end

-- TRYB 2: cofniecie — zarowki z powrotem jak reszta mapy
local function revert()
	local n = 0
	for _, d in ipairs(ROOT:GetDescendants()) do
		if isBulb(d) then
			d.Material = Enum.Material.Plastic
			d.MaterialVariant = "Studs"
			n += 1
		end
	end
	print(("[TrafficLights] cofniete do Plastic/Studs: %d"):format(n))
end

apply()
-- revert()
