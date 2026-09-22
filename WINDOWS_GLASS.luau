-- ESCAPE LAVA — szyby na `Material = Glass` (Workspace.Map)
-- Wklej w Command Bar w Studio (EDIT mode, nie Play). ⚠️ Po uruchomieniu Cmd+S.
--
-- CO TO WLACZA: `DestructionService.shatterGlass` rozpoznaje szybe **wylacznie po
-- `Material == Enum.Material.Glass`** — NIE po tagu, NIE po nazwie, NIE po przezroczystosci.
-- Dopoki szyby byly na `Plastic`, caly pass szkla chodzil na sucho (`szklo=0` w logach)
-- i szyby liczyly sie jako zwykla sciana Wall HP 100.
-- Po zmianie: gina od SAMEJ fali w `glassRadius` = 60 stud (glowny promien bomby to 24),
-- PRZEZ sciany (bez occlusion), bez sprawdzania HP, zero gruzu serwerowego. Klient
-- dostaje `glassPanes` w `BlastFX` i sypie 3-6 szklanymi odlamkami na tafle.
--
-- ⚠️ TAG NIE ISTNIEJE DLA SZKLA. Jedyny tag w systemie destrukcji to `Pillar` (filary).
--
-- ============================================================================
-- IDENTYFIKACJA PO **PODPISIE**, NIE PO NAZWIE RODZICA (poprawka 2026-09-21)
-- ============================================================================
-- Pierwsza wersja szukala szyb po rodzicu (`Window` / `Windows` / `WindowPlanks`)
-- i **przegapila 50 sztuk**, bo Kacper ma tafle wrzucone luzem w modele `Building`,
-- `Model` i `Entrance`. Objaw byl taki, ze czesc okien dalej wygladala na studsy
-- i nie tluka sie przy wybuchu — a skrypt meldowal sukces.
-- Wszystkie 367 szyb na tej mapie maja JEDNOLITY podpis, zweryfikowany pomiarem:
--     Transparency = 0.60   +   Color = (170, 170, 170)
-- i zaden inny przezroczysty part go nie ma. Dlatego liczy sie podpis, a nie miejsce
-- w drzewie — przenoszenie tafli miedzy folderami niczego nie psuje.
--
-- ⛔ CO PODPIS CELOWO OMIJA (zweryfikowane, nie ruszac bez decyzji Kacpra):
--     szyby automatow  `VendingMachine`  T=0.80             23 szt.
--     szyby samochodow `Car1`            T=0.85, Locked      64 szt. (Locked = chronione
--                                                            przed destrukcja z zalozenia)
--     szyby przystanku `BusStop`         T=0.75, czarne       9 szt.

local map = workspace.Map

local EXPECTED = 367
local T_PANE, T_TOL = 0.60, 0.06
local COL, COL_TOL = 170, 6

local function isPane(d)
	if not d:IsA("BasePart") then return false end
	if d.Parent and d.Parent.Name == "VendingMachine" then return false end
	if math.abs(d.Transparency - T_PANE) > T_TOL then return false end
	local c = d.Color
	return math.abs(c.R * 255 - COL) < COL_TOL
		and math.abs(c.G * 255 - COL) < COL_TOL
		and math.abs(c.B * 255 - COL) < COL_TOL
end

-- TRYB 1: wlacz szklo (idempotentne)
local function apply()
	local n, zmienione, cleared = 0, 0, 0
	local budynki = {}
	for _, d in ipairs(map:GetDescendants()) do
		if isPane(d) then
			n += 1
			local x = d
			while x and x.Parent and x.Parent.Name ~= "Buildings" do x = x.Parent end
			local b = x and x.Name or "(poza Buildings)"
			budynki[b] = (budynki[b] or 0) + 1

			if d.Material ~= Enum.Material.Glass then
				d.Material = Enum.Material.Glass
				zmienione += 1
			end
			-- Wariant `Studs` ma BaseMaterial = Plastic, wiec przy Glass sie nie stosuje.
			-- Czyscimy mimo to: zostawiony wrocilby, gdyby part kiedys wrocil na Plastic.
			if d.MaterialVariant ~= "" then
				d.MaterialVariant = ""
				cleared += 1
			end
		end
	end
	print(("[Windows] szyby: %d | ustawione na Glass: %d | wyczyszczony MaterialVariant: %d"):format(n, zmienione, cleared))
	for b, c in pairs(budynki) do print(("   %-22s %d"):format(b, c)) end
	if n ~= EXPECTED then
		warn(("[Windows] znaleziono %d szyb zamiast %d — podpis to Transparency %.2f (+-%.2f) i kolor %d,%d,%d")
			:format(n, EXPECTED, T_PANE, T_TOL, COL, COL, COL))
	end
end

-- TRYB 2: cofniecie — szyby z powrotem jak reszta mapy (znowu beda zwykla sciana)
local function revert()
	local n = 0
	for _, d in ipairs(map:GetDescendants()) do
		if isPane(d) or (d:IsA("BasePart") and d.Material == Enum.Material.Glass) then
			d.Material = Enum.Material.Plastic
			d.MaterialVariant = "Studs"
			n += 1
		end
	end
	print(("[Windows] cofniete do Plastic/Studs: %d"):format(n))
end

apply()
-- revert()
