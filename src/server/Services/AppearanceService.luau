--!strict
-- AppearanceService.luau
-- Jedyny właściciel WYGLĄDU postaci. Woła spawn i przerabia postać na „naszą".
--
-- Po co: wszyscy mają wyglądać jak postacie z TEJ gry, a nie przynosić swoje avatary
-- (decyzja 2026-09-21). Jednolita baza jest warunkiem opłacalności przyszłych skinów —
-- w tłumie losowych avatarów kupiony skin ginie i nikt nie chce za niego zapłacić.
--
-- ⛔ **NIE UŻYWAĆ `LoadCharacterWithHumanoidDescription` — SPRAWDZONE I ODRZUCONE 2026-09-21.**
-- Pierwsza wersja tego serwisu tak robiła i Kacper zgłosił z Play trzy objawy naraz:
-- wrócił ślizg przy chodzeniu, animacje były „lekko inne", a twarz się zbugowała.
-- Przyczyna jest jedna: **opis buduje postać WYŁĄCZNIE z siebie**, więc puste pole
-- animacji nie znaczy „zostaw graczowi jego", tylko „użyj domyślnej" — a domyślne
-- animacje Robloxa są strojone pod `WalkSpeed` 16, my mamy 12, i stąd ślizg.
-- Twarz psuła się z tego samego źródła: opis bez pola `Face` nie tworzy dekala `face`,
-- więc kod robił własny, a świeży `Decal` na meshu głowy mapuje się inaczej niż ten,
-- który Roblox zakłada sam. Pilnowanie samych PÓL animacji było za słabe — problemem
-- jest sama metoda.
--
-- ✅ ZAMIAST TEGO: zwykły `LoadCharacter()` (gracz zachowuje swoje animacje) i przeróbka
-- postaci po spawnie. Mniej kodu, mniej rzeczy do zepsucia, a efekt wizualny ten sam:
--   1. zdejmujemy ubrania i akcesoria gracza (inaczej jego koszulka zasłoni nasze kolory)
--   2. malujemy 15 części R15 — najpierw skóra, potem ubranie (patrz AppearanceDefinitions:
--      `BodyColors` ma tylko 6 pól i nie umie krótkiego rękawa)
--   3. podmieniamy TEKSTURĘ istniejącego dekala `face` — nie tworzymy własnego
--
-- ⛔ **NIE WYRÓWNUJEMY SKAL POSTACI — SPRAWDZONE I ODRZUCONE 2026-09-21.** Była tu funkcja
-- `normalizeScale`, ustawiająca `BodyHeightScale`/`BodyTypeScale`/… na jednolite wartości.
-- Kacper zgłosił po teście, że **ślizg przy chodzeniu zrobił się JESZCZE WIĘKSZY** niż przy
-- wersji z opisem. Mechanizm: zmiana proporcji zmienia długość nóg, a długość kroku
-- w animacji zostaje ta sama — stopy przestają nadążać za podłożem. Reszta przeróbki
-- (kolory, zdjęcie ubrań, twarz) nie ma jak wpłynąć na chodzenie, więc to było jedyne
-- podejrzane miejsce i tak też się okazało.
-- **Koszt tej rezygnacji, świadomy**: gracze z różną skalą avatara mają minimalnie różny
-- dystans HRP→stopy, czyli nieco inny próg śmierci w lawie i liczenia upadku
-- (`FEET_OFFSET` / `HRP_TO_FEET` = 2.5). Różnica jest rzędu ułamka studa i NIE jest warta
-- psucia odczucia ruchu — a gdyby kiedyś zaczęła przeszkadzać, właściwym miejscem jest
-- Game Settings → Avatar → zakresy skal, nie przeskalowywanie postaci z kodu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppearanceDefinitions = require(ReplicatedStorage.Shared.Modules.AppearanceDefinitions)
local PlayerDataService = require(script.Parent.PlayerDataService)

local AppearanceService = {}


export type Appearance = {
	skin: string,
	shirt: string,
	pants: string,
	sleeves: string,
	legs: string,
}

-- Wygląd trzymany też w PAMIĘCI, nie tylko w zapisie. Powód: gdy DataStore jest
-- niedostępny (Studio bez API, awaria), zapis nie przejdzie — a bez cache gracz
-- losowałby się od nowa przy KAŻDYM respawnie i wyglądałby inaczej co rundę.
local cached: { [Player]: Appearance } = {}

local function pickId(palette: { AppearanceDefinitions.Swatch }): string
	return palette[math.random(#palette)].id
end

local function pickCut(options: { string }): string
	return options[math.random(#options)]
end

-- Uzupełnia braki i podmienia wartości, których nie ma już w paletach. Wywoływane także
-- na danych WCZYTANYCH: paleta żyje razem ze sklepem, więc zapis sprzed zmiany może
-- wskazywać na kolor, który zniknął — i wtedy gracz ma dostać losowy, a nie zepsuty spawn.
local function sanitize(raw: any): Appearance
	local a: any = if type(raw) == "table" then raw else {}
	return {
		skin = if AppearanceDefinitions.isValid("skin", a.skin) then a.skin else pickId(AppearanceDefinitions.skin),
		shirt = if AppearanceDefinitions.isValid("shirt", a.shirt) then a.shirt else pickId(AppearanceDefinitions.shirt),
		pants = if AppearanceDefinitions.isValid("pants", a.pants) then a.pants else pickId(AppearanceDefinitions.pants),
		sleeves = if table.find(AppearanceDefinitions.sleeves, a.sleeves) then a.sleeves else pickCut(AppearanceDefinitions.sleeves),
		legs = if table.find(AppearanceDefinitions.legs, a.legs) then a.legs else pickCut(AppearanceDefinitions.legs),
	}
end

-- Wygląd gracza: z zapisu, a przy pierwszym wejściu losowany i zapisywany NA STAŁE
-- (decyzja 2026-09-21). Losowanie co rundę odebrałoby graczowi tożsamość i nie byłoby
-- czego podmieniać przyszłemu sklepowi ze skinami.
function AppearanceService.get(player: Player): Appearance
	local hit = cached[player]
	if hit then
		return hit
	end

	local data = PlayerDataService.get(player)
	if not data then
		-- Dane jeszcze się nie wczytały (spawn przed końcem wczytania — PlayerService czeka
		-- na nie przed pierwszym spawnem, więc to tylko przypadek po limicie czasu). Losujemy
		-- na TO jedno życie, bez zapamiętania: do 29.09 losowy zestaw lądował w `cached`
		-- i przykrywał zapisany wygląd na całą sesję, a zapis się nie udawał — gracz miał
		-- nową postać przy każdym wejściu (przegląd 29.09, A-1). DataStore niedostępny
		-- (Studio bez API) tu nie trafia: wtedy są domyślne dane w pamięci, cache działa.
		return sanitize(nil)
	end
	local stored = data.appearance
	local appearance = sanitize(stored)
	cached[player] = appearance

	-- Zapisujemy tylko wtedy, gdy zapis realnie się zmienia — inaczej każdy spawn
	-- generowałby zapis do DataStore bez powodu (limit to 60 + 10×graczy na minutę).
	local needsSave = type(stored) ~= "table"
	if not needsSave and stored then
		for key, value in pairs(appearance :: any) do
			if (stored :: any)[key] ~= value then
				needsSave = true
				break
			end
		end
	end
	if needsSave then
		local ok = PlayerDataService.update(player, function(d)
			d.appearance = appearance
			return d
		end)
		if ok then
			print(("[Appearance] %s: skóra=%s koszulka=%s(%s) spodnie=%s(%s)"):format(
				player.Name, appearance.skin, appearance.shirt, appearance.sleeves,
				appearance.pants, appearance.legs))
		end
	end

	return appearance
end

-- Wyprowadza części ciała spod GLOBALNEGO nadpisania materiału z `MaterialService`
-- (`Plastic → "Studs"`, którego mapa potrzebuje, a postać nie). Powód i pełny opis objawu
-- przy `AppearanceDefinitions.BodyMaterial`. Musi lecieć przy KAŻDYM spawnie, bo świeża
-- postać przychodzi ze `StarterCharacter` z `Material = Plastic`.
local function applyBodyMaterial(character: Model)
	for _, name in ipairs(AppearanceDefinitions.parts.all) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Material = AppearanceDefinitions.BodyMaterial
		end
	end
end

local function paint(character: Model, names: { string }, color: Color3)
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = color
		end
	end
end

-- Zdejmuje z postaci wszystko, co gracz przyniósł ze swojego avatara. Bez tego jego
-- własna koszulka (tekstura `Shirt`) po prostu zasłoni kolory, które zaraz ustawimy,
-- a włosy zostaną mimo decyzji „łysa głowa na start".
local function stripPlayerLook(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory")
			or child:IsA("Shirt")
			or child:IsA("Pants")
			or child:IsA("ShirtGraphic")
			or child:IsA("BodyColors")
		then
			-- BodyColors leci razem z nimi: przemalowuje CZĘŚCI przy każdej swojej zmianie,
			-- więc zostawiony jest bombą zegarową — pierwsza rzecz, która go tknie,
			-- przywraca jednolitą skórę i całe ubranie znika.
			child:Destroy()
		end
	end
end

-- Twarz. ⚠️ TYLKO podmiana tekstury ISTNIEJĄCEGO dekala — NIGDY tworzenie własnego.
--
-- Dlaczego (zmierzone i obejrzane 2026-09-21): głowa w naszym rigu to **Dynamic Head** —
-- `MeshPart` z własnym `TextureID` i `FaceControls` (kontrolki mimiki). Taka głowa NIE
-- używa dekala `face`; ma twarz wprost w teksturze mesha. Świeżo utworzony `Decal`
-- mapuje się na jej UV zupełnie inaczej niż na klasyczną kostkę i wychodzi z tego czarna
-- plama z boku głowy — dokładnie to zgłosił Kacper jako „twarz zepsułeś".
-- Więc: jest dekal (klasyczna głowa) → podmieniamy teksturę. Nie ma → zostawiamy głowę
-- w spokoju, bo ma już własną twarz.
-- ➜ Gdybyśmy kiedyś chcieli narzucać KONKRETNĄ twarz wszystkim, właściwa droga to
--   klasyczna głowa w `StarterCharacter` (ta z dekalem), a nie tworzenie dekala z kodu.
local function applyFace(character: Model)
	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local face = head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face.Texture = AppearanceDefinitions.FaceTexture
	end
end

-- Przeróbka postaci na „naszą". Idempotentne — można wołać wielokrotnie.
function AppearanceService.applyToCharacter(character: Model, appearance: Appearance)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		-- Głośno, bo to nie usterka kodu tylko ustawienie placu: Game Settings → Avatar →
		-- Avatar Type musi być R15. Przy R6 nie ma czego malować (inne nazwy części),
		-- a przy okazji po cichu znika head tracking i rozjeżdża się próg lawy.
		warn(("[Appearance] %s ma rig %s zamiast R15 — wygląd pominięty. Sprawdź Game Settings → Avatar."):format(
			character.Name, tostring(humanoid.RigType)))
		return
	end

	stripPlayerLook(character)
	-- PRZED malowaniem: dopóki część siedzi na `Material = Plastic`, kolor, który zaraz
	-- ustawimy, i tak nie trafi na ekran.
	applyBodyMaterial(character)

	local P = AppearanceDefinitions.parts
	local skin = AppearanceDefinitions.colorOf("skin", appearance.skin)
	local shirt = AppearanceDefinitions.colorOf("shirt", appearance.shirt)
	local pants = AppearanceDefinitions.colorOf("pants", appearance.pants)
	local shoes = AppearanceDefinitions.colorOf("shoes", "default")

	-- Najpierw CAŁA postać w kolorze skóry, potem ubranie nadpisuje wybrane segmenty.
	-- Dzięki temu zmiana kroju sama odsłania przedramię czy łydkę i nie trzeba pamiętać,
	-- co „odmalować" po poprzednim zestawie.
	paint(character, P.all, skin)

	paint(character, P.shirtCore, shirt)
	if appearance.sleeves == "long" then
		paint(character, P.shirtSleeves, shirt)
	end

	paint(character, P.pantsCore, pants)
	if appearance.legs == "long" then
		paint(character, P.pantsLower, pants)
	end

	paint(character, P.shoes, shoes)
	applyFace(character)
end

-- Zamiennik `player:LoadCharacter()`. PlayerService woła TO w obu miejscach spawnu.
function AppearanceService.loadCharacter(player: Player)
	local appearance = AppearanceService.get(player)
	player:LoadCharacter()

	local character = player.Character
	if character then
		AppearanceService.applyToCharacter(character, appearance)
	end
end

local initialized = false
function AppearanceService.init()
	if initialized then return end
	initialized = true

	Players.PlayerRemoving:Connect(function(player)
		cached[player] = nil
	end)
end

return AppearanceService
