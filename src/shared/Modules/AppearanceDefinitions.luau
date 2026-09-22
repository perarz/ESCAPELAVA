--!strict
-- AppearanceDefinitions.luau
-- Katalog WYGLĄDU postaci: palety kolorów, kroje i twarz. Odpowiednik ItemDefinitions,
-- ale dla kosmetyki — dlatego osobny plik, a nie sekcja w Configu: to nie są liczby
-- balansu, tylko treść, która będzie rosła razem ze sklepem ze skinami.
--
-- ⚠️ TO JEST CZYSTA KOSMETYKA — ZERO WPŁYWU NA ROZGRYWKĘ. Pancerze (które wpływają)
-- dostaną własny katalog i własny serwis; mieszanie tych dwóch rzeczy w jednym miejscu
-- skończyłoby się tym, że kiedyś ktoś przepuści bonus przez kanał, któremu ufamy klientowi.
--
-- DLACZEGO KOLORY, A NIE TEKSTURY KOSZULEK (decyzja 2026-09-21): `Shirt`/`Pants` trzeba
-- wgrać na Roblox — opłata za sztukę plus moderacja, która potrafi odrzucić. Kolor to
-- jedna wartość w kodzie: zero kosztu, zero czekania, działa natychmiast.
--
-- DLACZEGO KOLOR USTAWIAMY NA CZĘŚCIACH, A NIE PRZEZ `BodyColors`: `BodyColors`
-- i `HumanoidDescription` mają tylko SZEŚĆ pól kolorów (głowa, tors, L/P ręka, L/P noga)
-- — pozostałość po R6. Na R15 „kolor ręki" pokrywa UpperArm + LowerArm + Hand naraz,
-- więc połowy ramienia nie da się pomalować tą drogą. R15 ma za to 15 osobnych części,
-- każdą z własnym `Color` — i stąd bierze się cały krój ubrania poniżej.

local AppearanceDefinitions = {}

-- ============================================================================
-- TWARZ I RIG
-- ============================================================================

-- ⚠️ To jest id typu **Image** (AssetTypeId 1), bo wchodzi w `Decal.Texture` na dekalu
-- `face` w głowie. Odpowiadający mu Decal (13618859077) pasowałby do pola `Face`
-- w `HumanoidDescription`, ale tamta droga bywa wybredna co do typu assetu — a dekal
-- i tak ustawiamy ręcznie, więc nic nie tracimy. Zweryfikowane 2026-09-21: oba istnieją,
-- Decal jest darmowy, nazwa "default face".
AppearanceDefinitions.FaceTexture = "rbxassetid://13618859034"

-- ⚠️ MATERIAŁ CIAŁA — **NIGDY `Plastic` ANI `SmoothPlastic`** (lekcja 2026-09-20,
-- zgłoszenie „ręka ma kolor koszulki zamiast skóry").
--
-- OBJAW, i to on jest tu najważniejszy: **dane są POPRAWNE, rozjeżdża się OBRAZ.**
-- `Color` pokazuje kolor skóry i na serwerze, i na kliencie — a w grze dłoń renderuje się
-- w kolorze sąsiada, czyli rękawa. Zmiana `Material` na „inny" natychmiast przywraca
-- prawidłowy kolor. Nie szukać tego w logice losowania ani w `paint`; tam nie ma buga.
-- Widać to na NAJMNIEJSZYCH częściach: dłoń i stopa mają **0.30 studa** (12% ręki).
--
-- CO WIEMY NA PEWNO (sprawdzone w Play przez Kacpra):
--   `Plastic`        ❌ zły kolor
--   `SmoothPlastic`  ❌ zły kolor  ← NIE wracać, wygląda na „oczywisty" wybór i NIE działa
--   `Rock`           ✅ dobry kolor (ale widoczna faktura kamienia)
--
-- CZEGO NIE WIEMY — i czego NIE zgadywać drugi raz: mapa stoi na `MaterialVariant "Studs"`
-- podpiętym GLOBALNIE (`MaterialService.Plastic = "Studs"`), co łapie każdy part
-- z `Material = Plastic` i pustym `MaterialVariant` — czyli też postać ze `StarterCharacter`.
-- To była pierwsza hipoteza i **jest niewystarczająca**: w całym placu istnieje DOKŁADNIE
-- JEDEN wariant (`Studs`, `BaseMaterial = Plastic`), a pole `MaterialService.SmoothPlastic`
-- da się ustawić wyłącznie na wariant o `BaseMaterial = SmoothPlastic` — takiego nie ma,
-- więc SmoothPlastic nadpisany być NIE MOŻE, a mimo to jest zepsuty. Zostają dwie
-- możliwości: nadpisanie `Plastic` łapie całą rodzinę „gładkiego plastiku", albo to w ogóle
-- nie jest nadpisanie, tylko wspólny kubełek renderowania (zmiana materiału wymusza
-- przebudowę i dlatego „naprawia"). Rozstrzyga jeden test: wyczyścić `MaterialService.Plastic`
-- i zobaczyć, czy dłoń na `Plastic` robi się poprawna.
-- ⚠️ 45 pól nadpisań `MaterialService` jest NIEDOSTĘPNYCH do odczytu z MCP
--   (`lacking capability RobloxScript`) — trzeba obejrzeć w Properties.
--
-- ➜ To jest JEDYNE miejsce, w którym wybiera się materiał ciała. Kandydaci do sprawdzenia,
--   gdyby `Plaster` też okazał się zepsuty: `Concrete`, `Fabric`, `Sand`, `Slate`,
--   a w ostateczności `Rock` (wiadomo, że działa).
AppearanceDefinitions.BodyMaterial = Enum.Material.Plaster

-- ⛔ Skal postaci CELOWO tutaj nie ma. Wyrównywanie ich (`BodyHeightScale` itd.) zostało
-- sprawdzone 2026-09-21 i odrzucone: nasilało ślizg przy chodzeniu. Powód i koszt tej
-- decyzji opisany w nagłówku AppearanceService — nie przywracać bez rozwiązania ślizgu.


-- ============================================================================
-- PALETY
-- ============================================================================
-- W danych gracza zapisujemy **id** (string), nigdy `Color3` — DataStore przyjmuje
-- wyłącznie typy JSON-owalne, a przy okazji zmiana odcienia w palecie przemalowuje
-- wszystkich, którzy go mają, bez migracji zapisów.
--
-- ⚠️ PULA STARTOWA MA BYĆ CELOWO PRZECIĘTNA (zasada z 2026-09-16, powtórzona 2026-09-21):
-- jeśli losowe zestawy wyjdą ładniejsze niż płatne, sklep ze skinami umrze, zanim powstanie.
-- Rzeczy efektowne trzymamy na sprzedaż, tutaj zostają kolory spokojne.

export type Swatch = { id: string, name: string, color: Color3 }

AppearanceDefinitions.skin = {
	{ id = "light",  name = "Jasna",     color = Color3.fromRGB(255, 204, 153) },
	{ id = "tan",    name = "Opalona",   color = Color3.fromRGB(234, 184, 146) },
	{ id = "olive",  name = "Oliwkowa",  color = Color3.fromRGB(204, 164, 118) },
	{ id = "brown",  name = "Brązowa",   color = Color3.fromRGB(160, 116,  80) },
	{ id = "dark",   name = "Ciemna",    color = Color3.fromRGB(105,  74,  52) },
	{ id = "classic", name = "Klasyczna", color = Color3.fromRGB(245, 205,  48) },
} :: { Swatch }

AppearanceDefinitions.shirt = {
	{ id = "white",   name = "Biała",      color = Color3.fromRGB(238, 238, 238) },
	{ id = "grey",    name = "Szara",      color = Color3.fromRGB(150, 150, 155) },
	{ id = "black",   name = "Czarna",     color = Color3.fromRGB( 45,  45,  50) },
	{ id = "navy",    name = "Granatowa",  color = Color3.fromRGB( 40,  60, 100) },
	{ id = "red",     name = "Czerwona",   color = Color3.fromRGB(170,  60,  55) },
	{ id = "green",   name = "Zielona",    color = Color3.fromRGB( 75, 120,  75) },
	{ id = "mustard", name = "Musztardowa", color = Color3.fromRGB(200, 160,  60) },
	{ id = "teal",    name = "Morska",     color = Color3.fromRGB( 60, 120, 120) },
} :: { Swatch }

AppearanceDefinitions.pants = {
	{ id = "denim", name = "Dżins",    color = Color3.fromRGB( 60,  80, 115) },
	{ id = "black", name = "Czarne",   color = Color3.fromRGB( 40,  40,  45) },
	{ id = "grey",  name = "Szare",    color = Color3.fromRGB(100, 100, 105) },
	{ id = "khaki", name = "Khaki",    color = Color3.fromRGB(150, 130,  95) },
	{ id = "brown", name = "Brązowe",  color = Color3.fromRGB( 95,  70,  50) },
	{ id = "olive", name = "Oliwkowe", color = Color3.fromRGB( 85,  95,  65) },
} :: { Swatch }

-- Buty na razie JEDEN kolor dla wszystkich i NIE losowane — inaczej stopy zostałyby
-- w kolorze skóry, czyli każdy chodziłby boso. To jest gotowa przyszła kategoria sklepu
-- (`Foot` to osobne części R15), na razie celowo nieruszana.
AppearanceDefinitions.shoes = {
	{ id = "default", name = "Buty", color = Color3.fromRGB(58, 48, 42) },
} :: { Swatch }

-- ============================================================================
-- KRÓJ — skąd biorą się „warianty ubrań" bez ani jednego assetu
-- ============================================================================
-- Ta sama koszulka w dwóch krojach to dla gracza dwie różne rzeczy, a dla nas jedna
-- wartość w tabeli. Kroje są LOSOWANE razem z kolorami (decyzja Kacpra 2026-09-21),
-- bo dwukrotnie zwiększają różnorodność sylwetek na serwerze za darmo.
AppearanceDefinitions.sleeves = { "short", "long" }
AppearanceDefinitions.legs = { "long", "shorts" }

-- ============================================================================
-- CZĘŚCI R15 — co maluje który element ubrania
-- ============================================================================
-- Nazwy części są stałe dla R15. `Head`, `LeftHand`/`RightHand` celowo NIE występują
-- nigdzie poniżej: zostają w kolorze skóry (dłonie to przyszłe „rękawiczki").
AppearanceDefinitions.parts = {
	-- WSZYSTKIE 15 części. Malujemy je najpierw na kolor skóry, a ubranie nadpisuje
	-- wybrane — dzięki temu zmiana kroju (długi rękaw → krótki) sama odsłania przedramię,
	-- bez pamiętania, co trzeba „odmalować".
	all = {
		"Head",
		"UpperTorso", "LowerTorso",
		"LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	},
	-- Korpus + ramiona zawsze należą do koszulki.
	shirtCore = { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm" },
	-- Doklejane tylko przy długim rękawie; przy krótkim zostają w kolorze skóry.
	shirtSleeves = { "LeftLowerArm", "RightLowerArm" },
	-- Uda zawsze należą do spodni.
	pantsCore = { "LeftUpperLeg", "RightUpperLeg" },
	-- Doklejane tylko przy długich nogawkach; przy szortach zostają jako gołe łydki.
	pantsLower = { "LeftLowerLeg", "RightLowerLeg" },
	shoes = { "LeftFoot", "RightFoot" },
}

-- ============================================================================
-- API
-- ============================================================================

-- Kolor po id, z fallbackiem na pierwszy wpis palety. Fallback jest istotny: gracz ma
-- w zapisie id sprzed zmiany palety (usunięty kolor, literówka po refaktorze) i wtedy
-- ma dostać cokolwiek sensownego, a nie błąd w połowie spawnu.
function AppearanceDefinitions.colorOf(category: string, id: any): Color3
	local palette = (AppearanceDefinitions :: any)[category]
	if type(palette) == "table" then
		for _, swatch in ipairs(palette) do
			if swatch.id == id then
				return swatch.color
			end
		end
		if palette[1] then
			return palette[1].color
		end
	end
	return Color3.fromRGB(200, 200, 200)
end

function AppearanceDefinitions.isValid(category: string, id: any): boolean
	local palette = (AppearanceDefinitions :: any)[category]
	if type(palette) ~= "table" then return false end
	for _, swatch in ipairs(palette) do
		if swatch.id == id then return true end
	end
	return false
end

return AppearanceDefinitions
