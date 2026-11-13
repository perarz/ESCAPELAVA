# COSMETICS — zastąpione listy testów (v4–v6e)

> Archiwum z 13.11.2026: listy przypadków dla wersji UI, które nadpisały się nawzajem. Nie są aktualnym testem; bieżący test: `TESTY.md` → „COSMETICS — aktualny test”. Zaznaczenia `[x]` (jeśli są) dotyczyły tamtych wersji.

## COSMETICS v6e — przebieralnia, 12.11 (MCP, Cmd+S wymagany)

- [ ] Klik w kartę → kamera wjeżdża do przebieralni: patrzy na postać na wprost (nie z góry), trochę wyżej niż wcześniej, cała postać w kadrze, nie zasłania jej BUY ani napisy.
- [ ] Ruszaj myszą po ekranie → kamera lekko krąży wokół postaci (postać zostaje na środku), płynnie, bez szarpania; przeciąganie postaci dalej ją obraca. Na telefonie kamera stoi.
- [ ] BUY: zielony od jasnego u góry do ciemnego u dołu, bez białego paska; EQUIP / UNEQUIP / szary jak dotąd. BACK: ciemny fiolet w tym samym stylu.
- [ ] BACK / Q → katalog, kamera nie zostaje w przebieralni; X zamyka i kamera wraca za postać.

## COSMETICS v6d — bez bieli, mniej ozdób, 11.11 (MCP, Cmd+S wymagany)

- [ ] Plakietki HALLOWEEN / EPIC / RARE, zielona tabliczka ceny i BUY: kolor przechodzi w ciemniejszy ton tego samego koloru, nigdzie biało-kolorowego połysku. Po BUY dalej przelatuje błysk, gdy stać Cię na przedmiot.
- [ ] Na kartach i w ramce postaci nie ma pasków; za przedmiotem delikatny okrągły półton.
- [ ] Rogi kart i ramki postaci: nic nie miga pod czarnym obrysem. Kolorowy LED biegnie cienką linią wewnątrz karty, przy krawędzi.

## COSMETICS v6c — katalog + przebieralnia ze sceną, 10.11 (MCP, Cmd+S wymagany) — zmienia v6

- [ ] E przy sprzedawcy: po lewej ramka tylko z Twoją postacią (bez nazwy i BUY), sama się obraca, da się ją przeciągać. Po prawej karty.
- [ ] Za przedmiotem na karcie okrągły półton z kropek w kolorze rzadkości, wyśrodkowany za przedmiotem. Brak „matrixowych” kropek u góry (paski usunięte w v6d).
- [ ] Klik w kartę → kamera jedzie do przebieralni (scena), postać na platformie z przedmiotem, nazwa / plakietka / cena / BUY / BACK jak dawniej. BACK albo Q → wraca katalog z kartami w tym samym miejscu przewinięcia, kamera wraca normalnie przy zamknięciu.
- [ ] Zakup w przebieralni działa jak wcześniej (kasa odlicza, UNLOCKED!, BUY → UNEQUIP); po BACK na karcie WEARING, a postać w ramce katalogu ma nowy przedmiot.
- [ ] (po imporcie nowej dyni) Dynia na głowie: bez dziur, z przodu (od twarzy postaci) czarna mina, z tyłu gładka; w karcie i w przebieralni też mina z przodu.

## COSMETICS v6 — przebieralnia od razu, 10.11 (MCP, Cmd+S wymagany) — zastępuje v5b

Przed Play: Rojo połączone (zmienione `CosmeticsController` i `Config`). Jeśli sklep się nie otwiera, a w Output jest `[Cosmetics] … needs Body.Dressing and Body.Shelf` — plac nie ma v6 (brak Cmd+S).

- [ ] E przy sprzedawcy: od razu jeden ekran — czarne tło, po lewej ramka z Twoją postacią (w Twoich kolorach i stroju), nad nią kasa, po prawej panel z kartami. Kamera świata się nie rusza, HUD znika.
- [ ] Ramka postaci: cała postać widoczna, głowa nie ucięta, napis PICK AN ITEM na dole. Po ~3 s postać sama się obraca; przeciągnij myszą / palcem → obraca się za ruchem.
- [ ] Panel kart: 3 prawdziwe karty + 9 COMING SOON (szare, „?” i kłódka). Kółko myszy / palec przewija TYLKO obszar kart po prawej; karty chowają się równo pod tytułem i nad dolnym marginesem.
- [ ] Karta: prawie kwadratowe rogi, gruby czarny obrys, po obrysie krąży jasny pas w kolorze rzadkości („LED”). Nazwa w lewym dolnym rogu, cena na zielonej tabliczce w prawym dolnym, bez czarnego paska na dole. Migające gwiazdki na dyni i kamizelce.
- [ ] **(v6b)** Brak półtonu w rogach i brak ramki/tła wokół panelu kart. U góry każdej karty i ramki postaci kropki półtonu w kolorze rzadkości, gęste przy górnej krawędzi i zanikające w dół, pod przedmiotem; na COMING SOON szare. Za mocne / za słabe → napisz (przezroczystość w placu, kolor `HalftoneLighten`).
- [ ] Najedź na kartę: lekko rośnie, przelatuje błysk, przedmiot się kołysze. Na telefonie dotyk nie zostawia karty powiększonej.
- [ ] Klik w kartę: postać w ramce od razu ją zakłada (plecak — postać odwraca się tyłem), nad nazwą plakietka rzadkości, pod ramką BUY z ceną. LED wybranej karty kręci się szybciej, LED ramki postaci ma kolor rzadkości.
- [ ] Klik w COMING SOON: karta drga, napis COMING SOON pod BUY, nic się nie kupuje.
- [ ] Za mało kasy: szary BUY i „NEED X$ MORE — SURVIVE N ROUNDS”; klik → drganie, NOT ENOUGH CASH. Wystarczy kasy: zielony BUY z połyskiem; zakup → kasa odlicza, UNLOCKED! na środku, na karcie zamiast ceny napis WEARING pod nazwą, BUY zmienia się na UNEQUIP.
- [ ] UNEQUIP → postać w ramce bez przedmiotu, przycisk EQUIP, na karcie OWNED. EQUIP → wraca.
- [ ] Przycisk COSMETICS w HUD (garderoba): tylko posiadane, bez COMING SOON; bez posiadanych — napis pustej garderoby.
- [ ] X i Q zamykają; HUD wraca, postać chodzi. Otwórz ponownie — nic nie zostaje powiększone ani obrócone.
- [ ] Zmień rozmiar okna / telefon pionowo: ramka na górze, karty pod nią, nic poza ekranem; poziomo na telefonie kolumny się mieszczą.

## COSMETICS v5b — przewijanie i tabliczka ceny, 10.11 (MCP, Cmd+S wymagany)

- [ ] Otwórz sklep przy sprzedawcy: na górze dynia na całą szerokość, pod nią u dołu ekranu wystaje górna część kart kamizelki i plecaka. Z prawej jasny, gruby pasek przewijania.
- [ ] Przewiń kółkiem myszy w dół → widać całe karty kamizelki i plecaka (te same rozmiary co wcześniej), dalej się nie da. Na telefonie przeciągnij palcem — przewija się, a puszczenie po przeciągnięciu nie otwiera przymierzalni.
- [ ] Najedź na dynię → lekko się powiększa, krawędzie nie są obcięte. Klik w każdą kartę dalej otwiera przymierzalnię.
- [ ] Cena na karcie: zielona tabliczka z czarnym obrysem i połyskiem, ikonka kasy wystaje z lewego brzegu, biały napis „500$”. Po zakupie / w garderobie: żółta WEARING, szara OWNED, bez ikonki. Tabliczka nie nachodzi na nazwę przedmiotu.
- [ ] Nazwy na małych kartach (KEVLAR VEST, SCHOOL BACKPACK) czytelne w 16:9 — jeśli łamią się na dwie małe linie, napisz.
- [ ] Plakietki HALLOWEEN / EPIC / RARE: delikatne studsy w środku i połysk na górze, jak przyciski INVENTORY / COSMETICS w HUD. Za słabo widać studsy → napisz (przezroczystość 0,75 w placu).
- [ ] Obrysy: X, BACK i BUY grubsze (jak przyciski w HUD), karty grubiej obrysowane niż wcześniej.
- [ ] Zmień rozmiar okna / obróć telefon: duża karta dalej na całą szerokość, przewijanie działa, nic nie wychodzi poza ekran.

## COSMETICS v5 — nowy wygląd sklepu, 09.11 (MCP, Cmd+S wymagany)

Katalog obejrzany na zrzucie z Edit (tymczasowe karty, potem usunięte). Przymierzalni, animacji i wibracji nie da się zobaczyć bez Play. Jeśli tło albo tytuł mają być inne, to są liczby w `Config.Cosmetics.UI` (`BackdropFlow*`) i kolory napisu `SignFlowColors`.

- [ ] Otwórz sklep przy sprzedawcy: tło ciemny fiolet → niebieski po skosie, ze studsami, wolno płynie (kolory przesuwają się, nic nie skacze); studsy dalej dryfują. Lawowej poświaty u dołu już nie ma.
- [ ] Napis COSMETICS: fiolet → niebieski → błękit płyną przez litery jak na napisie nad sprzedawcą, czytelny na tle (czarny obrys). Jeśli ginie w tle, napisz: wróci złoty albo tło będzie ciemniejsze.
- [ ] Karty: za dynią pomarańczowy sunburst, za kamizelką i plecakiem biały. Na dużej karcie kręci się cały czas, na małych tylko pod kursorem. Promienie nie wychodzą poza kartę.
- [ ] Lewy górny róg każdej karty: plakietka z czarnym obrysem — HALLOWEEN pomarańczowa, EPIC ciemnofioletowa, RARE ciemnoniebieska. Szerokość dopasowana do napisu (EPIC krótka), odcina się od karty. Starego małego napisu rzadkości nad nazwą już nie ma.
- [ ] Najedź na kartę → wyraźnie się powiększa (mniej niż przyciski), nie wchodzi na sąsiednią. Wciśnij → lekko się zapada. Puść poza kartą → wraca.
- [ ] X: najedź → powiększa się jak X w sklepie broni, klik → wciśnięcie i zamknięcie. Otwórz ponownie → X ma normalny rozmiar (nie zostaje powiększony).
- [ ] Kliknij kartę → przymierzalnia. Plakietka nad nazwą w tych samych kolorach co na karcie i dopasowana do napisu. BACK i BUY reagują na kursor i kliknięcie. Wróć BACK → kliknięta karta nie zostaje powiększona.
- [ ] Wystarczy kasy na przedmiot: co ~3,5 s po zielonym BUY przelatuje połysk. Przy EQUIP / UNEQUIP / za mało kasy połysku nie ma.
- [ ] Za mało kasy → klik w szary BUY: przycisk krótko drga, komunikat NOT ENOUGH CASH, kasa bez zmian.
- [ ] Zakup → UNLOCKED! jak dotąd (belki UNLOCKED! bez zmian), przedmiot od razu na postaci.
- [ ] **Telefon:** dotknięcie karty / przycisku nie zostawia go powiększonego; jest krótka wibracja przy kliknięciu, zakupie i odmowie (o ile telefon ją obsługuje).
- [ ] Garderoba (przycisk COSMETICS w HUD): te same karty z plakietkami, OWNED/WEARING zamiast ceny.
- [ ] Sklep broni bez zmian: napis SHOP nad sprzedawcą dalej płynie lawą, wibracje w sklepie działają jak wcześniej.

## COSMETICS — sklep v4 (27.10 wieczór), do sprawdzenia przez Kacpra

Wygląd obejrzany na zrzutach z Edit (katalog, przymierzalnia, UNLOCKED!). Kod zsynchronizowany i parsuje się. **Play nie był uruchamiany.** Przed testem Cmd+S.

- [ ] (27.10 późno) Tło katalogu: studsy powoli płyną po skosie w górę, lawowa poświata u dołu spokojnie jaśnieje i przygasa (~5 s). Nic nie skacze przy zawijaniu wzoru, krawędź ekranu nigdy nie jest pusta. W przymierzalni tła nie ma (widać scenę).
- [ ] (27.10 późno) Zębatka ustawień w prawym górnym rogu: nie wchodzi pod listę graczy ani pod przyciski Robloxa, klik otwiera i zamyka ustawienia, hover działa. W lewym pasku zostały INVENTORY i COSMETICS.
- [ ] (27.10 późno) Prawy dolny róg: półprzezroczysty napis „v0.8”, nie zasłania przycisku skoku na telefonie.
- [ ] (27.10 późno) Inventory: żółty nagłówek ma ostre górne rogi, czarny obrys idzie prosto do rogu; kreska pod nagłówkiem tej samej grubości co obrys; dół panelu bez zmian.

- [ ] Otwórz sklep przy NPC → ciemne studsy z lawową poświatą u dołu, złoty napis COSMETICS w jednej linii z kasą i X. Karty: dynia na ciemnym fiolecie z pomarańczowymi promieniami (HALLOWEEN), kamizelka fioletowa (EPIC), plecak niebieski (RARE). Ceny jako `500$` z ikoną kasy.
- [ ] Przymierzalnia, kamizelka założona → głowa siedzi na tułowiu bez szpary, także gdy postać się obraca. Sprawdź też plecak (ten sam podgląd).
- [ ] Duża karta dyni sama się lekko kołysze, a promienie się kręcą. Najedź myszą na kamizelkę lub plecak → zaczynają się kołysać, zjedź → płynnie wracają. Nic nie miga ani nie skacze.
- [ ] Kliknij produkt → przymierzalnia bez granatowego paska: rzadkość, duża nazwa i cena na scenie po lewej, duży BUY po prawej, BACK w prawym górnym rogu. Po ~3 s postać sama się powoli obraca. Przeciągnij → obrót zatrzymuje się na 3 s.
- [ ] Za mało kasy → szary BUY i napis `NEED X$ MORE — SURVIVE N ROUNDS` z poprawną liczbą (100$ za rundę). Kliknięcie → komunikat NOT ENOUGH CASH, kasa bez zmian.
- [ ] Wystarczy kasy → zielony BUY. Kliknij → kasa w rogu odlicza w dół, na środku wskakuje UNLOCKED! z nazwą w kolorze rzadkości, przedmiot jest od razu na postaci (także po zamknięciu sklepu), przycisk zmienia się na czerwony UNEQUIP, cena na WEARING.
- [ ] UNEQUIP → przycisk żółty EQUIP, cena OWNED, przedmiot znika z postaci. EQUIP → wraca.
- [ ] Garderoba (przycisk COSMETICS): tylko posiadane, z napisami OWNED/WEARING zamiast ceny.
- [ ] Wyjście w trakcie UNLOCKED! (BACK/X/start rundy) → przy kolejnym otwarciu popup nie wisi na ekranie.
- [ ] Telefon / wąskie okno: nazwy się nie nakładają na ceny, BUY i BACK dostępne, napis NEED… mieści się.
