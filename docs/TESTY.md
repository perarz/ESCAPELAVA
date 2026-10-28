# CO PRZETESTOWAĆ

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

## COSMETICS — 26.10, do sprawdzenia przez Kacpra

- [ ] **UI v2:** katalog zakrywa cały ekran, bez starego małego okna/lobby za nim; X jak w Inventory; zakładki kategorii filtrują bez cyklicznego klikania. Zmień wielkość okna i orientację telefonu: nagłówek, ceny, X i przewijanie nadal dostępne. Neutralne manekiny przy brakującym imporcie są oznaczone jako niedostępne.

Warunek pełnego testu: import i dopasowanie trzech Accessory wg STUDIO_CONTRACT. Obecnie folder modeli jest pusty; blokada sprzedaży jest zamierzona. Kontrola Edit: 93 źródła server/client/shared zgodne z dyskiem i poprawna składnia; Rojo build oraz diff-check zaliczone. Obejrzano układ UI i kierunek kamery w Edit. **To nie test Play.**

- [ ] Podejdź do ClothesShop.NPC: prompt otwiera ciemny COSMETICS; ceny dynia 500 / kamizelka 750 / plecak 600. Bez modelu widoczny COMING SOON, bez pobrania kasy.
- [ ] Kliknij produkt po imporcie: podgląd twojej postaci na platformie, obrót w obie strony, widok plecaka od tyłu. Inny gracz nie widzi kopii i nie może na niej stanąć.
- [ ] BACK wraca do katalogu bez utraty przewinięcia. X / Q oddaje kamerę, światło i sterowanie. Inventory/sklep broni/ustawienia nie nakładają się na kosmetyki.
- [ ] BUY pobiera dokładną cenę tylko raz, także przy podwójnym kliknięciu. Od 27.10 (v4) od razu zakłada kupioną rzecz. Za mało kasy / zbyt daleko od NPC / początek rundy: brak zakupu i komunikat.
- [ ] EQUIP zakłada wyłącznie posiadany produkt; UNEQUIP zdejmuje. Dynia + kamizelka + plecak razem; zamiana w tej samej kategorii usuwa poprzednią rzecz. Przymierzanie i BACK nie zmieniają stroju.
- [ ] COSMETICS pod INVENTORY pokazuje tylko własne kosmetyki; pusty stan czytelny. Przycisk dostępny tylko w lobby, a filtr kategorii działa.
- [ ] Otwórz przebieralnię przed startem rundy; nie zostajesz bez sterowania ani ze starą kamerą po respawnie. Powtórz przy śmierci, wyjściu i ponownym wejściu do gry.
- [ ] Po ponownym wejściu zachowane zakupy, saldo i strój; po śmierci strój wraca. Brak duplikatów akcesoriów.
- [ ] Sprawdź dopasowanie wszystkich modeli przy chodzie, biegu, itemach, ragdollu i śmierci. Toolbox tworzy zawiasy akcesoriów tylko na starcie; szczególnie obejrzyj dodatki założone później. Żadnych zmian HP, ruchu, kolizji ani celowania.
- [ ] Telefon: pionowa siatka dwóch kolumn, pozioma trzech; przewijanie nie kupuje produktu, tekst/ceny/przyciski czytelne, obrót i zamykanie dostępne dotykiem.

Aktualizacja oczekiwań: **23.10.2026**. Zaznaczaj `[x]` dopiero po teście Kacpra. Jak coś nie działa — dopisz obok objaw i datę. Starsze zaliczenia nie są automatycznym testem późniejszych zmian. [STATUS](STATUS.md) / [DO_RELEASE](DO_RELEASE.md).
Po testach destrukcji skopiuj Claude'owi z Output linie `[Collapse]` i `[Destr]`.
Jak coś wisi w powietrzu — **nie zatrzymuj Play**, napisz Claude'owi: przeskanuje to na żywo.

**Zanim zaczniesz:** sprawdzić aktywny Rojo i porównać źródła testowanych plików ze Studio; samo „Connected” nie potwierdza synchronizacji. VS Code może uruchamiać Rojo automatycznie, ale nie zakładać, że na pewno działa.

---

## Pełny przegląd kodu — 26.10, NIEPRZETESTOWANE

Zakres i ograniczenia: [raport](CODE_REVIEW_2026-10-26.md). Te przypadki uzupełniają istniejące testy, nie kasują wcześniejszych oczekiwań.
- [ ] Bomba → hak → most → RPG → C4 → napój, szybkie przełączenia, ponowne wyciąganie i respawn: jeden item w ręce, jeden klik = jedna akcja, gesty/chwyt/odrzut jak wcześniej. C4 po RPG działa od pierwszego kliknięcia.
- [ ] Most → schowaj → koniec rundy: brak ghosta i blueprinta w lobby. Kolejna runda ponownie pozwala budować. Kontrolowane BuildBridge bez wybrania mostu i FireGrapple bez haka w ręce są odrzucane bez zużycia.
- [ ] Hak pod nogi i przy samej postaci: próba bez realnego lotu nie zabiera sztuki; zwykły lot po łuku, w górę/w dół i kolejny zaczep zachowują tempo i zakończenie. Test ilości z wyłączonym nieskończonym inventory deva.
- [ ] Wolniejsza sieć i respawn: sterowanie, BombHit i head tracking wstają poprawnie. Drugi gracz po śmierci nie dziedziczy poprzedniego skrętu głowy; RPG dostaje postawę również bez pierwszego ruchu kamerą. HUD i 3-2-1 kończą odliczanie wspólnie.
- [ ] Kilka zarobków + zakup podczas lotu banknotów + powtórna replikacja salda: licznik kończy na prawdziwej kwocie, bez podwójnego doliczenia. Dwóch graczy przy pickupie: zbiera najbliższy, dokładnie raz.
- [ ] Przy 9998 sztukach zakup daje 9999 i pobiera jedną cenę; następny zakup odrzucony, kasa i ilość bez zmian. Dla `give(count=2)` przy 9998 pełne odrzucenie, przy 9997 pełny sukces. Test z wyłączonym nieskończonym inventory.
- [ ] Ekwipunek: DETAILS, przesuwanie paneli, zmiana rozmiaru okna — brak dziur w ściemnionym tle i zmiany wyglądu cieni tekstu. Zwykłe otwieranie/zamykanie sklepu pozostaje poprawne.
- [ ] Stań na stropie i wysadź jego bok; powtórz na rumowisku i poza v4 — resztka pod stopami pozostaje. Kilka wybuchów w tych samych meblach nie robi podwójnych kopii ani nowej kolizji z postacią.
- [ ] Kilka bomb, beczek/aut i kolapsów tuż przed końcem rundy: po odbudowie brak zaległego wybuchu/uszkodzeń; nowe beczki nadal wybuchają. Gruz pęka i usypia jak wcześniej; grupy z graczem zachowują priorytet.
- [ ] Powtórz istniejące T1–T7 dwa razy pod rząd; obejrzyj również dotychczasowe C4, RPG i fall damage. Nie zaliczać na podstawie parsowania lub samego odczytu Edit.

## Przegląd itemów — 25.10, do sprawdzenia po optymalizacjach

Zakres zmian i weryfikacja bez Play: [raport](ITEM_REVIEW_2026-10-25.md).
- [ ] Wyciągnij bombę, C4 i RPG; RPG potrzymaj dłużej, strzel, użyj F i wejdź w ragdoll → gesty i chwyt zachowują wygląd, po przerwaniu wracają bez pozostawionej pozy.
- [ ] Szybko przełączaj bomba → RPG → C4 → bomba → w ręce zostaje tylko wybrany item; jeden klik wykonuje jedną akcję.
- [ ] Dwóch graczy rzuca po kilka C4 naraz → łapią mapę, przelatują przez postacie i dają się odpalić; po respawnie drugiego gracza jego nowa postać też jest pomijana przez lot C4.
- [ ] W lobby zmień loadout → zmiana działa. Próba wysłania `SetLoadout` poza lobby (kontrolowane wywołanie z klientowego Command Bar) → wybór serwera pozostaje poprzedni; przejście lobby → countdown nie przyjmuje spóźnionej zmiany.
- [ ] Kontrolowane żądania `FireRpg` i `ThrowC4` z NaN / nieskończonością → brak pocisku, zużycia i błędu; zwykły strzał/rzut nadal działa. Zużycie sprawdzać z wyłączonym nieskończonym inventory deva.

## 🧨 C4 (25.10) — RZUT DO TESTU
Pierwszy test Kacpra 25.10 (log): przyklejanie klikiem i odpalenie G dwóch ładunków działało. Drugi test (log): rzut „dalej i prościej” — 6 rzutów, wszystkie przyklejone, G odpala 3. Po nim prośba: **wysoki łuk jak granat + lekki zamach ręki** — zrobione 25.10, NIEPRZETESTOWANE. Liczby rzutu: `Config.C4` (ThrowSpeed, ThrowLift, Gravity, Spin), zamach: `Config.C4.Swing`, siła i cena: `ItemDefinitions.c4`. Z Output skopiuj Claude'owi linie `[C4]`.
- [ ] Sklep, ekwipunek i pasek → C4 ma ikonę (zielona kostka z czarnymi opaskami i czerwoną diodą, czarny obrys jak u bomby)
- [ ] Sklep → przewiń do kostki między hakiem a mostem → nagłówek „C4”, opis „Throw up to 3 sticky charges…”, 60$; kup → C4 w ekwipunku, dodaj do loadoutu
- [ ] Runda, C4 w ręce → kostka w dłoni (krzywo → `Config.C4.GripRotation`)
- [ ] Klik → ręka robi krótki zamach nad głową i wyrzut do przodu (~0,4 s), kostka zostaje w dłoni na następny rzut
- [ ] Klik na wprost → kostka leci WYSOKIM łukiem (wznosi się ~5 studów nad rękę), koziołkując, i przykleja się płasko tam, gdzie spadła; miga na czerwono; w HUD pojawia się przycisk detonatora
- [ ] Rzuć porównawczo bombą i C4 na wprost → C4 leci wyżej, a ląduje mniej więcej tak daleko jak bomba. Za nisko / za daleko → `Config.C4.ThrowLift` / `ThrowSpeed`
- [ ] Drugi gracz widzi zamach ręki rzucającego razem z wylotem kostki
- [ ] Zamach za mocny / za słaby / za wolny → `Config.C4.Swing` (ShoulderUp, ShoulderDown, Windup, Time)
- [ ] Lot ma być płynny (liczy go serwer, rysuje co klatkę). Jeśli kostka szarpie w locie — napisz, przejdę na rysowanie u klientów jak rakieta RPG
- [ ] Rzut pod nogi → przykleja się do podłogi obok; rzut w sufit / spód balkonu → wisi na suficie
- [ ] Stoisz twarzą przy ścianie i rzucasz → przykleja się do tej ściany, nie przelatuje na drugą stronę
- [ ] Rzut przez drugiego gracza → kostka przez niego przelatuje i przykleja się do ściany za nim
- [ ] Rzut w niebo / poza mapę → kostka po ~6 s znika bez wybuchu (log „ładunek poza mapą — znika”), C4 zużyte
- [ ] Biegnąc rzucasz do przodu → leci dalej niż na stojąco
- [ ] Rzuć 3 → czwarty klik nic nie rzuca, przycisk detonatora podskakuje
- [ ] **Błąd 25.10 (naprawiony, do sprawdzenia):** RPG → strzał → od razu 3 (C4) → klik → C4 leci od pierwszego kliknięcia, bez chowania i ponownego wyciągania; to samo bomba → C4 i hak → C4
- [ ] Jeden klik = jeden rzut (nie dwa naraz); klik w przycisk na HUD (pasek, DETONATE) nie rzuca
- [ ] Rzuć i wciśnij G, zanim doleci → wybucha w powietrzu, tam gdzie akurat jest
- [ ] Wciśnij **G** → wszystkie 3 wybuchają po kolei (szybki łańcuch), każdy jak bomba: dziura, odrzut, obrażenia; przycisk znika
- [ ] Przycisk detonatora: czerwony DETONATE po prawej, znaczek „G” w lewym rogu, „x1/x2/x3” w prawym — liczba zgadza się z ładunkami; klik myszą też odpala
- [ ] Na telefonie (emulator) → przycisk odpala tak samo, nie zasłania przycisku skoku, znaczka „G” nie ma
- [ ] Rzuć, schowaj C4 (wyciągnij hak), odleć, wciśnij G → wybuch daleko od ciebie
- [ ] Zużyj ostatnie C4 → kostka znika z ręki, slot x0, ale G dalej odpala przyklejone
- [ ] Stoisz przy własnym ładunku i odpalasz → ciebie też rani (jak bomba), kill za samobójstwo bez nagrody
- [ ] Zabij kogoś z C4 → „YOU KILLED” i nagroda jak za bombę
- [ ] **Zawalenie:** rzuć ładunek na ścianę/filar wyższego piętra, zwal budynek bombą od dołu → ładunek leci razem z kawałkiem; G w trakcie lotu → wybucha tam, gdzie akurat jest
- [ ] Rzuć ładunek na ścianę, rozwal ją OBOK bombą → ładunek spada i przykleja się niżej (na podłodze / gruzie), dalej da się go odpalić
- [ ] Rzuć ładunek na most → stoi na moście; most zniszczony/odrzucony → ładunek spada niżej
- [ ] Rzuć nisko i poczekaj na lawę → zalany ładunek dalej da się odpalić (wybuch pod lawą)
- [ ] Rzuć prosto w lawę → przelatuje przez taflę i przykleja się na dnie; G → wybuch pod lawą
- [ ] Zgiń z przyklejonymi ładunkami → znikają od razu, bez wybuchu; po respawnie brak przycisku
- [ ] Koniec rundy z przyklejonymi ładunkami → znikają bez wybuchu, mapa po odbudowie cała; po rundzie C4 nie ma w ręce
- [ ] Odpal 3 i zgiń od pierwszego wybuchu → pozostałe dwa i tak wybuchają (odpalone = odpalone)
- [ ] G w czacie (pisanie) → nic nie wybucha
- [ ] Drugi gracz widzi migające ładunki kolegi i wybuchy

## ☀️ SŁOŃCE MNIEJ RAZI (27.10) — NIEPRZETESTOWANE

Promienie słońca przyciszone (`SunRays` 0,483/1 → 0,2/0,6 w `default.project.json`); niebo, światło i cienie bez zmian.

- [ ] Spójrz w stronę słońca (lobby i z dachu na mapie) — nie oślepia, ale dalej widać lekkie promienie
- [ ] Reszta obrazu tak samo jasna jak wcześniej

## 🖼️ IKONY ITEMÓW BEZ STUDSÓW (27.10) — NIEPRZETESTOWANE

Te same ujęcia i obrys co 19–25.10, nowe zdjęcia modeli bez studsów (`output/inventory-icons-v3`).

- [ ] Pasek, ekwipunek i sklep pokazują nowe ikony wszystkich 6 itemów (bez kratki studsów na bombie, moście, haku, puszce, C4)
- [ ] Hak i puszka jaśniejsze niż wcześniej — czytelne na czarnym slocie i na kolorowych kartach

## 🌋 GRAPHICS LOW / HIGH + OPRAWA LAWY (27.10) — NIEPRZETESTOWANE

Najpierw Cmd+S (nowy wiersz w panelu). Na komputerze na start ma być HIGH, na telefonie LOW.

- [ ] Panel ustawień ma trzeci wiersz **GRAPHICS** z LOW / HIGH; świeci się zielono to, co faktycznie działa (komputer: HIGH)
- [ ] Przełącz na LOW w trakcie rundy → łuna, iskry/popiół i rozbryzgi znikają od razu, bąbli lawy jest mniej; HIGH → wracają
- [ ] Wyjdź i wejdź ponownie → wybór LOW/HIGH zapamiętany
- [ ] **Łuna:** gdy lawa wyjdzie ponad ulicę, ściany tuż nad lawą świecą czerwono-pomarańczowo; piętro wyżej **nie** świeci. Przy chodzeniu światło nie „jedzie” za Tobą i nie miga
- [ ] **Iskry i popiół:** od startu rundy w kanale trochę iskier, które **nie wylatują nad jezdnię**; im wyżej lawa, tym więcej; nad ulicą lecą najwyżej ~piętro, nie sypią się do pokoi wyżej
- [ ] **Wpadnięcie:** skocz z dachu do lawy → rozbryzg, dym i krótki błysk. Lawa podchodząca pod stopy, gdy stoisz → **bez** efektu. Wyskok i ponowne wpadnięcie zaraz potem → bez serii błysków
- [ ] Rozbryzg widać też, gdy wpada **kolega**; respawn / teleport do lobby nie robi rozbryzgu
- [ ] Śmierć w lawie dalej daje stary kłąb pary (widzą wszyscy)
- [ ] FPS na HIGH (komputer) i na telefonie po przełączeniu na HIGH — zgłoś, jeśli wyraźnie spada

## ⏭️ KONIEC RUNDY → OD RAZU LOBBY (26.10) — NIEPRZETESTOWANE

Faza „ROUND OVER” w lobby (10 s) usunięta: po rundzie zostaje krótki moment z wynikiem na mapie (3 s), ciemna zasłona, a potem od razu lobby z odliczaniem 25 s.

- [ ] Przeżyj rundę: po „YOU SURVIVED!” ekran ciemnieje, budzisz się w lobby, a na górze od razu jest **LOBBY** z czasem (nie „ROUND OVER”)
- [ ] Przy wyjściu z zasłony nie widać przeskoku z mapy do lobby (zasłona schodzi dopiero, gdy stoisz w lobby)
- [ ] Zgiń w rundzie: po śmierci lądujesz w lobby, po końcu rundy dalej LOBBY z odliczaniem, bez dodatkowego czekania
- [ ] Od razu po powrocie da się otworzyć ekwipunek / zmienić loadout i kupić w sklepie
- [ ] **Następna runda po wybuchach:** rozwal budynek bombami, poczekaj na następną rundę — budynek stoi cały i znowu normalnie się niszczy (budynki odbudowują się teraz po odtworzeniu mapy, a nie przy wejściu do lobby)
- [ ] Kasa z poprzedniej rundy nie leży w lobby ani na mapie; lawa jest na dole od startu lobby
- [ ] Ostatnie sekundy po rundzie („ROUND OVER” na mapie) nie migają już na czerwono — czerwony licznik tylko w lobby i rundzie

## ⚙️ PANEL USTAWIEŃ (26.10) — NIEPRZETESTOWANE
Najpierw **Cmd+S** w Studio — zębatka `HUD.SideButtons.SettingsButton` i `StarterGui.Settings` postawione przez MCP. Liczby i kolory: `Config.Settings`.
- [ ] Pod INVENTORY jest sama biała zębatka z czarnym obrysem (bez żółtego kafelka); najechanie lekko go powiększa, klik otwiera panel SETTINGS (wskakuje na środku), drugi klik albo X zamyka
- [ ] Zębatka jest też w rundzie (INVENTORY wtedy znika) i panel da się otworzyć; klik w przycisk panelu z C4/bombą w ręce NIE rzuca itemu
- [ ] CAMERA SIDE: klik LEFT → kamera płynnie przechodzi nad lewe ramię (postać po prawej stronie ekranu), LEFT zielony, RIGHT szary; RIGHT → z powrotem. Przy ścianie z lewej kamera nie wchodzi w ścianę
- [ ] Z RPG na PPM przy LEFT: celownik dalej na środku, rakieta leci w środek celownika
- [ ] CAMERA TILT & FOV → OFF: bieg w bok nie przechyla obrazu, sprint i energy drink nie rozszerzają widoku, wybuch/strzał RPG/pchnięcie nie „kopie” FOV; zoom celowania RPG na PPM dalej działa. ON → wszystko wraca
- [ ] Szybkie klikanie LEFT/RIGHT kilka razy → zostaje ostatni wybór, nic nie skacze z powrotem
- [ ] Wyjdź z gry i wejdź ponownie (Studio z dostępem do API albo serwer) → ustawienia takie same jak przed wyjściem
- [ ] Śmierć / start rundy z otwartym panelem → panel dalej działa, ustawienia bez zmian

## 🔢 ODLICZANIE 3-2-1 (26.10) — NIEPRZETESTOWANE
Najpierw **Cmd+S** w Studio — kolory cyfr zmienione przez MCP w `RoundCountdown.Digits`.
- [ ] Start rundy → 3 czerwona, 2 soczyście żółta (nie blada), 1 zielona, żywe kolory, studsy i czarny obrys jak dotąd, ostre (nie rozmyte)
- [ ] Cyfry wyraźnie mniejsze niż wcześniej (ok. połowa wysokości ekranu), dalej na środku
- [ ] Każda cyfra wskakuje duża i odbija się do normalnej wielkości. Za mocno / za słabo → `Config.RoundTransition.CountdownStartScale` (1,6) i `CountdownPopTime` (0,32)
- [ ] Na małym oknie / telefonie cyfry mieszczą się w ekranie

## 🛒 NOWY WYGLĄD SKLEPU (25.10) — NIEPRZETESTOWANE
Najpierw **Cmd+S** w Studio — panel `ShopUI` przebudowany przez MCP (stara wersja w `ServerStorage.ShopUI_Backup_2510`). Kod sklepu bez zmian.
- [ ] Podejdź do sprzedawcy, E → na dole zwarty panel: żółty nagłówek z samą nazwą (bez kasy), opis i paski cech po lewej, duża zielona cena nad zielonym BUY po prawej
- [ ] Ciemne strzałki < > stoją tuż przy bokach panelu (nie przy krawędziach ekranu); klik przewija item, A/D i scroll też
- [ ] Przewiń do RPG → opis mieści się w dwóch linijkach, nic nie wystaje poza panel
- [ ] Za mało kasy → szary przycisk „NOT ENOUGH $”, napis mieści się w przycisku
- [ ] Kup coś → pod przyciskiem „BOUGHT!” (albo „ADD IT IN INVENTORY”), z czarnym cieniem jak reszta napisów; kasa spada w HUD w lewym dolnym rogu
- [ ] Zmniejsz okno Studio / telefon w emulatorze → panel i strzałki maleją razem, strzałki dalej przyklejone do panelu
- [ ] Wygląd OK → usuń `ServerStorage.ShopUI_Backup_2510` i Cmd+S

## 🎯 RPG CELOWANIE NA PPM (24.10) — NIEPRZETESTOWANE
Najpierw **Cmd+S** w Studio — `HUD.Crosshair` postawiony przez MCP. Liczby: `Config.Rpg.Aim` (zoom, chód, obrót), wygląd celownika: `HUD.Crosshair` w Studio.
- [ ] Runda, RPG w ręce, trzymaj PPM → kamera lekko się przybliża, na środku 4 kreski z pustym środkiem (wskakują), kursor znika
- [ ] Z PPM ruszaj myszą → całe ciało obraca się za kamerą, chodzenie A/D to krok w bok (nie skręt), obraz nie przechyla się
- [ ] PPM + celuj w dach / w ziemię → tułów z wyrzutnią odchyla się w górę / w dół; drugi gracz widzi to samo
- [ ] **25.10 — RPG na barku:** wyciągasz RPG → tułów płynnie obraca się ~50° w prawo (bokiem do celu), głowa patrzy przed siebie; rura leży na PRAWYM BARKU obok głowy (tył za plecami, głowica przed twarzą), lufa prosto przed postać; lewa dłoń pod lufą przed piersią; nic nie wchodzi w głowę
- [ ] PPM + celuj w dach / w ziemię / w niebo → lufa idzie dokładnie za celownikiem (tułów pochyla się razem z wyrzutnią)
- [ ] PPM → zoom wyraźnie mocniejszy niż przedtem (za mocny / za słaby → `Config.Rpg.Aim.Profile.FOVOffset` i `PushIn`)
- [ ] Bieg i skok z RPG → tułów zostaje bokiem, nic nie przenika przez ciało; wyrzutnia nie wchodzi w biodra ani nogi
- [ ] Schowaj RPG (wyciągnij inny item) → tułów płynnie wraca przodem; po ragdollu i śmierci nic nie zostaje wykręcone
- [ ] Drugi gracz widzi postawę bokiem i lufę idącą w górę / w dół
- [ ] Strzał → rakieta wylatuje z lufy na barku (start 1 stud w prawo od środka postaci), nie z głowy; błysk i dym z wyrzutni
- [ ] Stań prawym bokiem tuż przy ścianie i strzel przed siebie → rakieta nie przelatuje przez ścianę obok
- [ ] Za wysoko / za nisko / za daleko w bok → `Config.Rpg.MuzzleHeight` / `MuzzleSide`; pozę rąk i obrót tułowia zmieniać tylko razem (`ItemEquip.HoldPoses.Rpg` + `WaistYawTools.RpgTool`)
- [ ] Za mocne wyginanie przy stromym celowaniu → `WaistPitchTools.RpgTool` (1 = lufa dokładnie w celownik)
- [ ] PPM + lewy klik → rakieta leci dokładnie w środek celownika (blisko i daleko, też w niebo), celownik krótko się rozszerza
- [ ] Bez PPM lewy klik → jak dotąd, w kursor
- [ ] Z PPM wolniejszy chód, Shift nie biega; puść PPM z wciśniętym Shift → bieg wraca od razu
- [ ] Puść PPM → kamera płynnie wraca, celownik znika, kursor wraca, postać znów skręca w stronę ruchu
- [ ] **(26.10) Kamera wyżej**: z PPM kamera przybliża się i lekko podnosi (postać trochę niżej na ekranie), rakieta dalej leci w środek celownika; pod niskim stropem kamera nie wchodzi w sufit. Za mało / za dużo → `Config.Rpg.Aim.Profile.Lift` (0,8)
- [ ] Celowanie się kończy samo: ostatnia rakieta, zmiana itemu (1-3), ragdoll od wybuchu, śmierć, koniec rundy — kursor zawsze wraca, postać po wstaniu z ragdolla obraca się normalnie
- [ ] PPM na drabinie z RPG → nie odrywa od drabiny
- [ ] RPG w ręce bez PPM, patrzysz w górę → tułów z wyrzutnią też idzie w górę (decyzja 24.10: dotyczy trzymania RPG)
- [ ] Pad: L2 = celowanie, R2 = strzał w celownik
- [ ] Za mocny / za słaby zoom, za wolny chód → `Config.Rpg.Aim.Profile`; pochylenie tułowia → `Config.Movement.HeadTrack.WaistPitchTools.RpgTool`

## RPG OBURĄCZ / WYCIĄGANIE (21.10) — NIEPRZETESTOWANE
- [ ] RPG: wyciąganie zza prawego ramienia trwa 0,7 s; lewa dłoń podchodzi pod lufę i zostaje tam w staniu, biegu i skoku
- [ ] Strzał od razu przerywa wyciąganie; przy zapasie rakiet obie ręce dalej trzymają RPG
- [ ] F z RPG: pełne pchnięcie, potem powrót do chwytu oburącz
- [ ] Ragdoll / drabina / siedzenie: ręce swobodne, po powrocie do zwykłego ruchu chwyt wraca
- [ ] Zmiana itemu, ostatnia rakieta i respawn: lewa ręka nie zostaje przy starej lufie; drugi gracz widzi chwyt oburącz
- [ ] Bomba, hak i blueprint: wyciąganie krótsze, 0,3 s

## 🃏 KARTY ITEMÓW W EKWIPUNKU (23.10) — NIEPRZETESTOWANE
Podgląd z Edit: `output/inventory-cards/podglad.jpg`. Studsy usunięte; wygląd per item w `Config.UI.Inventory.CardStyles`.
- [ ] Otwórz ekwipunek (I) → każda karta ma swój wzór: energy drink jasne paski, hak siatka, bomba czarna taśma + żółta ramka, RPG wojskowe pasy + ramka + błysk, most złota krata + złota ramka + błysk + migające iskierki
- [ ] Błysk co kilka sekund przelatuje po RPG i moście (nie naraz), iskierki na moście migają po kolei; nic nie wychodzi poza zaokrąglone rogi karty
- [ ] Najedź / przeciągnij kartę, przypisz do slotu → wzór i ramka jadą razem z kartą, napisy (cena, xN, nazwa, numer slotu) czytelne
- [ ] Item x0 → szara karta, ale wzór i ramka zostają (widać, że warto kupić)
- [ ] Plac: **Cmd+S** (wzór karty `ItemTemplate` zmieniony przez MCP)

## 🎥 SKLEP: KĄT, ŚWIATŁO, DŁUŻSZA ŚCIANA (23.10) — NIEPRZETESTOWANE
- [ ] Każdy item widać lekko z boku (~20°) i trochę z góry, nie płasko na wprost. Inny kąt → `Config.Shop.AutoCameraYaw` (0 = na wprost, minus = z drugiej strony), z góry → `AutoCameraPitch`
- [ ] Przewiń wszystkie 6 aktywnych itemów (także RPG i bombę na końcach; StickyBomb = C4 od 25.10) → w kadrze tylko półki, blat i podłoga, nigdzie szarej ściany ani sufitu
- [ ] Światło jasne, białe (nie łososiowe) — kolory itemów prawdziwe; RPG (kamera najdalej) nie jest ciemny, bomba nie jest prześwietlona
- [ ] **Stałe lampy** (8 w `WeaponShopScene.ShopLights`): przewijaj ◀▶ szybko → światło jest od razu na każdym itemie, nic się nie „doładowuje” po kilku sekundach; cała ściana równo oświetlona, także brzegi w kadrze RPG. Za ciemno / za jasno → SpotLighty w `ShopLights` (Brightness, Range, Angle)
- [ ] **Start rundy w sklepie**: otwórz sklep i czekaj, aż lobby się skończy (albo K) → sklep się zamyka, kamera jest przy TWOJEJ postaci na arenie, nie w lobby; to samo po śmierci z otwartym sklepem
- [ ] Zamknij sklep przyciskiem X i klawiszem Q → kamera normalnie za postacią
- [ ] **Ekwipunek w sklepie (23.10)**: w sklepie nie ma przycisku INVENTORY, klawisz ekwipunku nic nie robi; ekwipunek otwarty przed podejściem do sprzedawcy zamyka się przy wejściu do sklepu; po wyjściu przycisk wraca
- [ ] **Jasność sklepu (23.10)**: ustaw grafikę na NAJNIŻSZĄ (Esc → Settings → Graphics Quality) → sklep jasny od razu, itemy dobrze widać; potem na najwyższą → lampy dają plamy, nie jest płasko ani prześwietlone; po wyjściu ze sklepu lobby ma zwykłe światło (nie jaśniejsze). Za jasno / za ciemno → `Config.Shop.SceneAmbient`
- (23.10, potwierdzone przez Kacpra: „lampy ładują się po czasie” = jakość grafiki „Automatic” startuje nisko i rośnie; na ręcznie ustawionej wysokiej lampy są od razu)
- [ ] Plac: **Cmd+S** (ściana, itemy i lampy zmienione przez MCP)

## 💡 PANEL I ŚWIATŁO W SKLEPIE (21–23.10) — NIEPRZETESTOWANE
- [ ] **(21.10 wieczór) Nowy panel sklepu** (wygląd zmieniony 25.10 — sprawdzać według sekcji „NOWY WYGLĄD SKLEPU”; tu tylko działanie): cena, opis, paski POWER/RANGE/MOBILITY (dojeżdżają przy zmianie itemu), zielony BUY; za mało kasy → szary „NOT ENOUGH $”; po zakupie „BOUGHT!” albo „ADD IT IN INVENTORY”; strzałki < > i A/D przewijają; X zamyka; wszystko po angielsku (też podpowiedź przy sprzedawcy: „Shop”)
- [ ] **Kolejność**: sklep otwiera się na bombie (pierwszy z lewej), > idzie po ścianie w prawo: bomba → energy drink → most → hak → RPG, bez skakania tam i z powrotem
- [ ] Mały ekran / telefon: panel mniejszy razem z HUD, mieści się
- [ ] Itemy na ścianie stoją szerzej (co ~9 studów), kamera dalej — w kadrze widać item w całości z odstępem
- [ ] **(21.10) Kadry**: każdy item (bomba, most, hak, puszka, RPG) widać lekko z boku (yaw 20°) i z góry (pitch 12°), nie od dołu; podobnej wielkości na ekranie; kamera nie stoi za ścianą. Za blisko/daleko → `Config.Shop.AutoCameraFill`, kąt → `AutoCameraPitch`
- [ ] Zamknij sklep i otwórz ponownie → dalej działa; w scenie sklepu nie widać szarego klocka światła

23.10: lampa jadąca za kamerą usunięta — zastąpiły ją stałe `ShopLights`, test wyżej.

## 🛢️ BECZKI WYBUCHOWE (21.10) — NIEPRZETESTOWANE
Beczki: 9 na budowie (Construction), 4 przy ulicy.
- [ ] Bomba albo RPG tuż przy beczce → beczka wybucha od razu, rozlatuje się, chwilę płonie; wybuch WIĘKSZY niż bomba (większa dziura, dalej rzuca graczy)
- [ ] Beczki stojące obok siebie → wybuchają łańcuchowo
- [ ] F (pchnięcie) w beczkę przed sobą → od razu wybucha (pchający też obrywa, jeśli nie ucieknie)
- [ ] F, gdy gracz stoi bliżej niż beczka → zwykłe pchnięcie gracza, beczka zostaje
- [ ] Drugi gracz zginie od wybuchu beczki → „YOU KILLED” i 25$ dla tego, kto ją odpalił (bombą, RPG albo F)
- [ ] Pełne HP w samym środku wybuchu beczki → przeżywa z małą ilością HP (78% obrażeń)
- [ ] Następna runda → wszystkie beczki stoją z powrotem
- [ ] **(21.10) Zawalenie**: zawal budowę (Construction) pod beczkami (piętro ~45 i parter) → beczki SPADAJĄ w całości i wybuchają przy uderzeniu o ziemię/gruz (nie znikają, nie wiszą). Za szybko/za późno → `Config.Destruction.Cars.Fall`
- [ ] Beczka spadnie i się zaklinuje → wybucha najpóźniej po ~6 s
- [ ] Za mocno / za słabo → liczby w `Config.Destruction.Cars.Profiles.Barrels`

## ⚡ ENERGY DRINK (20.10 wieczór) — NIEPRZETESTOWANE
- [ ] **21.10 — poprawka picia:** na stojąco i w biegu wieczko podchodzi przed usta, puszka lekko się przechyla i ręka opada; nie przykłada puszki do prawego ucha. Sprawdzić też przy obrocie kamery.
**Najpierw:** Rojo w Studio połączone (Connect) i plac zapisany (Cmd+S) — puszka do ręki to nowy model w `ReplicatedStorage`.
- [ ] Sklep: jest „Energy Drink” za 25$, z ikoną puszki z błyskawicą; kupno działa
- [ ] Ekwipunek: karta fioletowa z ikoną, w DETAILS kręci się puszka; da się włożyć do loadoutu (zamiast innego itemu — sloty są 3)
- [ ] Wyciągnięcie w rundzie: puszka w dłoni stoi PIONOWO, wieczkiem do góry. Jeśli leży albo stoi do góry dnem → napisz, poprawię jedną liczbę (`Config.EnergyDrink.GripRotation`)
- [ ] Biegniesz z shiftem i klikasz → ręka podnosi puszkę do ust (~pół sekundy), bieg się NIE zatrzymuje
- [ ] **(21.10)** Po łyku przez 10 s: sprint bez końca; zwykły chód wyraźnie szybszy (+3), sprint bez zmian; kamera trochę szersza (+5 FOV); pasek staminy: obrys wyraźnie GRUBSZY, obrys i środek płynnie przechodzą przez różne odcienie ZŁOTA (każdy w innym momencie), w ostatnich 2 s szybciej; na KRAWĘDZIACH ekranu winieta jak czerwona przy obrażeniach, tylko złota, pulsuje (środek ekranu czysty; wchodzi i schodzi płynnie); widać pasek też, gdy stoisz; potem wszystko wraca do normy, także po śmierci
- [ ] Pijesz z pustą staminą (wyczerpany, sprint zablokowany) i trzymasz shift → od razu biegniesz dalej
- [ ] Drugi napój w trakcie działania → czas liczy się od nowa do 10 s (nie sumuje się)
- [ ] Ostatnia puszka: znika z ręki po łyku; z kilkoma sztukami puszka zostaje w ręce
- [ ] Drugi gracz (jeśli jest): widzi, jak pijesz (ręka do ust)
- [ ] Śmierć albo koniec rundy w trakcie działania → w lobby pasek normalny, bez kolorów
- [ ] Ruch ręki przy łyku wygląda głupio (za nisko / za wysoko / ręka w głowie) → opisz, stroję liczby w `Config.EnergyDrink.Sip`

## 🚀 RPG — STRZAŁ / WYBUCH / ODRZUT (20–21.10) — NIEPRZETESTOWANE
Strzał, wybuch, odrzut (21.10). Rocket jump zrobiony i usunięty 21.10 (Kacper: „po prostu jak bomba”). Zostaje dźwięk strzału.
- [ ] Sklep: „RPG” za 75$ z ikoną; ekwipunek: karta oliwkowa, w DETAILS kręci się wyrzutnia
- [ ] Wyciągnięcie: wyrzutnia w dłoni trzymana POZIOMO, głowicą do przodu, ręka na rękojeści pod lufą. Jeśli jest krzywo / tyłem → zrzut ekranu
- [ ] Klik → rakieta (zielona głowica) leci prosto tam, gdzie celujesz, szybko, z białą smugą, bez opadania
- [ ] Trafia ścianę / dach / ulicę → wybuch jak bomba, ale wyraźnie mniejsza dziura i mniejszy zasięg
- [ ] Trafia drugiego gracza → wybuch na nim, rani i odrzuca; zabójstwo = „YOU KILLED” i 25$
- [ ] **(21.10, rocket jump usunięty)** Strzał pod własne nogi → rani i wywraca jak każdego, bez wyrzutu w górę
- [ ] **(21.10) Wybuchy ranią KAŻDEGO, też odpalającego** — także na prawdziwym serwerze: własna bomba, RPG, beczka, auto. Śmierć od własnego wybuchu = bez nagrody; jeśli ktoś cię wcześniej trafił, zabójstwo zostaje dla niego
- [ ] Strzał w lawę → wybucha na tafli lawy, nie pod nią
- [ ] Strzał w niebo → rakieta znika daleko z wybuchem w powietrzu (~300 studów)
- [ ] 1 rakieta = 1 strzał: po strzale wyrzutnia znika z ręki (przy kilku sztukach zostaje)
- [ ] Koniec rundy (O) z rakietą w locie → nic nie wybucha na odbudowanej mapie
- [ ] W Output przy strzale `[Rpg] … strzał`, bez czerwonych błędów
- [ ] **(21.10) Odrzut, „mocno”**: u strzelca kamera NIE zmienia kierunku (celujesz dalej w to samo miejsce) — tylko krótko się trzęsie i oddala (zoom-out) i wraca; z przodu wyrzutni błysk ognia i dym, z tyłu kłąb dymu (backblast); ręka z wyrzutnią kopie do góry/do tyłu i wraca (~0,5 s)
- [ ] Drugi gracz widzi błysk, dym i kop ręki strzelca (kamera trzęsie się tylko u strzelca)
- [ ] Ostatnia rakieta (wyrzutnia znika z ręki) → błysk i dym dalej w dobrym miejscu, przy ramieniu
- [ ] Za mocno / za słabo / dym w złym miejscu → liczby w `Config.Rpg.Recoil`

## 🖥️ EKRAN ŁADOWANIA v2 + NAPIS SHOP WYŻEJ (20.10 wieczór) — NIEPRZETESTOWANE
- [ ] Wejście do gry: mały szary „LOADING...”, pod nim duże żółte „ESCAPE LAVA” (LAVA pomarańczowe), nowa czcionka (prostsza); pasek ciemnopomarańczowy ze studsami w wypełnieniu, puste tło paska bez studsów
- [ ] Na końcu wszystko płynnie znika (studsy też)
- [ ] Lobby: napis SHOP wyraźnie wyżej nad sprzedawcą niż wcześniej

## 🏆 „YOU SURVIVED!” + KASA (20.10) — NIEPRZETESTOWANE
- [ ] Przeżyj rundę (klawisz O = koniec rundy) → na środku, w miejscu komunikatu zabójstwa, wskakuje złote „YOU SURVIVED!”, pod nim zielone „+100$”; po ~2,5 s gaśnie, zanim ekran ściemnieje do lobby. Starego żółtego „NICK WON $100” nie ma
- [ ] Zgiń w rundzie (lawa) i poczekaj do końca → NIC się nie pokazuje (komunikat tylko dla ocalałych)
- [ ] Ekran telefonu / małe okno Studio → napis mniejszy razem z resztą HUD, nie wychodzi poza ekran
- [ ] Zabij kogoś tuż przed końcem rundy → „YOU KILLED” znika, gdy wskakuje „YOU SURVIVED!” (nie nakładają się)
- [ ] Licznik kasy w lewym dolnym rogu: żywszy gradient — jasna limonka u góry, ciemna zieleń na dole (jak banknoty w ikonie); połysk przy zbieraniu kasy dalej przejeżdża

## 🛒 NAPIS SHOP (19.10) — NIEPRZETESTOWANE
- [ ] Wysoko nad straganem wisi „SHOP” w kolorach lawy, kolory płyną przez napis w kółko (bez przeskoku); widać go przez ściany straganu; z mapy w trakcie rundy go nie widać; po śmierci w lobby znowu widać

## 🎒 EKWIPUNEK / LOADOUT (18.10) — NIEPRZETESTOWANE
- [ ] **(19.10) Lawa w panelach ma jedną warstwę** (płynie w jedną stronę)
- [ ] **(19.10) Dwa okna**: `I` → na środku samo okno INVENTORY + LOADOUT. Klik w item → okno odjeżdża w lewo, z prawej wysuwa się DETAILS (z nazwą, kręcącym się itemem, opisem, cechami), para stoi razem na środku. Klik w inny item = podmiana treści; ten sam item drugi raz albo mały X = DETAILS chowa się, okno wraca na środek
- [ ] DETAILS → **ADD TO LOADOUT** (zielony) wkłada item do wolnego slotu (ikona przelatuje); przy itemie z loadoutu przycisk to **REMOVE** (czerwony); przy pełnym loadoucie **SWAP INTO SLOT** (żółty) → sloty się trzęsą, napis „PICK A SLOT TO SWAP”, klik w slot = podmiana
- [ ] Klik w slot z itemem = pokazuje go w DETAILS; klik w pusty slot przy otwartym DETAILS = wkłada tam pokazany item
- [ ] **(19.10) Nowe ikony** (render z gry + czarny obrys) w pasku i w ekwipunku: bomba, most, hak czytelne
- [ ] **(19.10) Animacje**: po otwarciu karty i sloty wskakują po kolei; karta pod kursorem rośnie i lekko się przechyla; nazwa i licznik w DETAILS podskakują przy zmianie itemu; nowy numer slotu na karcie podskakuje; przy zamknięciu panel opada. Przycisk INVENTORY większy, bez „I”
- [ ] **(19.10, poprawka) Item w DETAILS mieści się w okienku** (nie wystaje nad ramkę, jest na środku); przeciągnięty klocek upuszczony na slot trafia w ten slot; lecąca ikona startuje z karty, nie wyżej. **Lobby trwa 25 s** (było 15)
- [ ] **(19.10) DETAILS = prawdziwy item**: w okienku DETAILS kręci się item z prawdziwym światłem (odblaski, cień), na ciemnym tle; zmienia się po wybraniu innej karty; nie przesuwa się względem okna, gdy kamera się rusza (bieg, obrót); nic ze świata nie wchodzi w okno; po zamknięciu panelu znika. Telefon: to samo
- [ ] **(19.10) Wygląd klasyczny**: czarny obrys na wszystkim, pomarańczowy nagłówek, karty itemów w kolorach (x0 szara z zieloną ceną), sloty loadoutu wyglądają jak pasek na dole i stoją na płynącej lawie; karta rośnie pod kursorem, ikona wpada do slotu z odbiciem; model w DETAILS się kręci
- [ ] `I` albo przycisk INVENTORY (lewa strona) → panel spada na miejsce, tło ciemnieje; `I` / X zamyka. **(20.10) Klik w ciemne tło NIE zamyka** (i nie rzuca bomby / nie strzela hakiem pod spodem); klik w puste miejsce panelu też nie
- [ ] Klik w kartę otwiera DETAILS: model 3D się kręci, opis, paski POWER / RANGE / MOBILITY dojeżdżają; sam hover nie zmienia wyboru
- [ ] ADD / REMOVE / SWAP w DETAILS zmienia loadout; sam klik karty pokazuje szczegóły, bez samoczynnego wkładania/wyjmowania
- [ ] **(19.10) Przeciąganie**: jedzie CAŁA karta / cały slot (lekko większa, przechyla się w stronę ruchu), miejsce po niej się kurczy. Upuszczona na slot — wskakuje do niego sprężyście, slot podskakuje. Upuszczona obok — wraca sprężyście na miejsce. Slot upuszczony obok slotów — kurczy się z obrotem i znika (wyjęty). Slot na slot = zamiana; prawy klik slotu = wyjęcie
- [ ] Najedź na item i wciśnij 2 → item w slocie 2, a pasek NIE wyciąga itemu
- [ ] Pasek na dole = sloty loadoutu, nic się nie przestawia, gdy skończą się bomby (slot „x0”, szary, w lobby pulsuje na czerwono; klik = potrząśnięcie)
- [ ] **(19.10) Ekwipunek tylko w lobby**: po starcie rundy przycisk INVENTORY znika, klawisz I nic nie robi, otwarty panel sam się zamyka; w lobby wszystko wraca
- [ ] Wyjmij hak z loadoutu → klawisz 3 / slot nie wyciąga haka (serwer też nie da)
- [ ] Pełny loadout + kup item spoza niego → sklep: „ADD IT IN INVENTORY”, na przycisku INVENTORY czerwone „!”
- [ ] Ustaw loadout, wyjdź, wejdź → ten sam układ
- [ ] Telefon: tap itemu = DETAILS; wybór przez ADD / REMOVE / SWAP, przeciąganie palcem działa

---

## 🖥️ EKRAN ŁADOWANIA (20.10) — NIEPRZETESTOWANE
- [ ] Wejście do gry: od razu czarne tło, napis ESCAPE LAVA i pasek pod nim (nie ma szarego ekranu Robloxa ani starego z małym pomarańczowym paskiem)
- [ ] Pasek rośnie płynnie (bez skoków w tył), procent liczy razem z nim, napisy po angielsku: CONNECTING → LOADING ASSETS → LOADING MAP → LOADING PLAYER → LIGHTING UP → READY!
- [ ] Na końcu pasek dobiega do 100% i cały ekran płynnie znika (z czarnymi obrysami — nie zostają same ramki na chwilę)
- [ ] Telefon / małe okno: napis i pasek mieszczą się, nic nie wystaje
- [ ] W Output **NIE MA** `[LoadingScreen] brak ReplicatedFirst.LoadingGui` — jeśli jest, plac nie był zapisany po zmianie (Cmd+S)

## 📱 START GRY NA WOLNYM TELEFONIE (paczka 3, 18.10) — NIEPRZETESTOWANE
- [ ] Wejdź do gry → ekran ładowania pokazuje „LOADING PLAYER...”, a po zejściu kasa, pasek itemów i czas są już prawidłowe (nie „0$”, nie pusty pasek)
- [ ] Wejdź w **trakcie rundy** → HUD od razu pokazuje ROUND i czas, nie „LOBBY”
- [ ] Kup coś, wyjdź, wejdź → kasa i itemy widać od razu po zejściu ekranu ładowania
- [ ] Studio: Network → wolna sieć (throttling), wejdź → to samo co wyżej
- [ ] Sklep: otwórz → kwota i „za mało kasy” się zgadzają
- [ ] Ruch, sprint, kamera, hak, most, bomba, pchnięcie, drabina działają jak wcześniej (kontrolery startują teraz równolegle)
- [ ] W Output **NIE MA**: `bez ClientReady`, `init padł`, `stan gracza … nie doszedł`. Jeśli są — wklej je Claude'owi

---

## 🎨 NOWE UI Z FIGMY (10.10)
- [ ] **(18.10) Pasek itemów**: wybrany slot NIE nachodzi na sąsiada (też w chwili wyciągnięcia); zmiana 1 → 2 → 3 płynna — stary slot opada razem z wjazdem nowego, ikona buja się lekko, bez szarpnięcia. Rzut bombą: slot nie podskakuje przy każdym rzucie
- [ ] Licznik kasy w lewym dolnym rogu: banknoty + zielona liczba z czarnym cieniem; zmienia się przy zbieraniu/wydawaniu
- [ ] Zbierz kasę z mapy → banknot wyskakuje na środku ekranu i leci do licznika, licznik podskakuje, liczba płynnie rośnie
- [ ] Zabójstwo (25$) → 3 banknoty, wygrana (100$) → 6, jeden po drugim
- [ ] Zakup w sklepie → liczba spada od razu, bez banknotów; zakup w trakcie lotu banknotów nie psuje licznika
- [ ] Wejście do gry → licznik od razu pokazuje stan, bez lecących banknotów
- [ ] Pasek: 3 sloty z IKONAMI (bomba, most, hak), mała angielska nazwa na dole, numer klawisza w lewym górnym rogu (bez kółka), liczba sztuk w prawym; wybrany → biała ramka
- [x] Pasek, ramka (poprawka 10.10): wybierz item → biała ramka; kliknij ten sam slot / klawisz drugi raz (schowaj) → ramka wraca do czarnej. Powtórz kilka razy na każdym slocie i po rzucie bombą — biała nie może zostać na schowanym slocie
- [ ] Czas na górze (Figma, 10.10): napis stanu biały z cieniem, po bokach czarne kreski zwężające się na zewnątrz; czas pod spodem żółto-pomarańczowy. Przejdź LOBBY → GET READY → ROUND → ROUND OVER — kreski zawsze tuż przy napisie, nic nie nachodzi; sprawdź mały i duży ekran (telefon)
- [ ] Licznik czasu przy samej górze ekranu (10.10 wieczór): w oknie Studio, na pełnym ekranie i na telefonie (emulator) zawsze ~4 px od górnej krawędzi, nic go nie zasłania; reszta HUD na miejscu (kasa, pasek, przyciski z boku)
- [ ] Kamera w ruchu (11.10): chodzenie → kamera spokojna (zero bujania); sprint po ziemi → lekkie, płynne drżenie, znika po puszczeniu shifta i w powietrzu; bieg w bok (A/D) → kamera lekko się przechyla w stronę ruchu i wraca; F (push) → krótkie szarpnięcie + mały zoom u popychającego, także przy pudle; nic z tego w ragdollu; kamera dalej nie wchodzi w ściany. Za mocne / za słabe → `Config.Movement.Camera.SprintShake.Amplitude`, `.Lean.MaxDegrees` (1,2° od 11.10), `Config.Push.PushShakeIntensity`
- [ ] Przełączanie itemów (11.10): hak → bomba → most → hak w różnej kolejności, także szybko — w ręce zawsze JEDEN przedmiot, w pasku podniesiony tylko jeden slot
- [ ] Runda bez faz: jedna płynna krzywa lawy. Testowo 240 s, prędkość 0→1; po przełączeniu na produkcję 80 s, 0→3. Brak dawnych komunikatów phase; dev skip w ROUND kończy rundę. Balans najwyższych dachów ocenić osobno z ludźmi
- [ ] Wyciąganie itemu (11.10): klik / klawisz → slot podskakuje, zostaje wyżej i trochę większy, ikona się buja; schowanie → opada; rzut bombą (auto-wyciągnięcie następnej) → slot NIE skacze przy każdym rzucie; zmiana itemu 1 → 2 → slot 1 opada, 2 wjeżdża
- [ ] Licznik czasu (11.10): przy zmianie LOBBY → GET READY → ROUND → ROUND OVER napis wskakuje; ostatnie 10 s lobby / odliczania / rundy → czas czerwony i podskakuje co sekundę, potem wraca do żółtego
- [ ] Zakup w sklepie (11.10): liczba kasy spada płynnie (nie skokiem), licznik krótko się chwieje
- [ ] Pasek staminy (11.10): pobiegnij w małym oknie Studio, na pełnym ekranie i w emulatorze telefonu, z kamerą blisko i daleko — obrys i odstęp wypełnienia od ramki zawsze w tych samych proporcjach (nie cienka nitka na dużym ekranie, nie gruby klocek na telefonie)
- [ ] Balans (10.10 wieczór): push co 2,5 s (pasek odnowienia krótszy niż wcześniej 4 s); bomba w epicentrum zabiera 60% HP (było 50%) — obrażenia maleją z dystansem/osłoną, sprawdzić odczucie; lawa buja się mniej (fala o połowę niższa)
- [ ] Zbieranie kasy (11.10): na środku ekranu za banknotami zielony błysk, promienie, dwa pierścienie i migoczące gwiazdki — BEZ iskierek; nic nie zostaje na ekranie po ~1 s; napis kasy: pionowy gradient (góra jaśniejsza), przy dolocie banknotu przejeżdża po nim jasny połysk
- [ ] Kasa: w spoczynku nieruchomy pionowy gradient (limonka u góry, ciemna zieleń u dołu); przy zarobku jeden płynny przejazd osobnej nakładki połysku, bez szarpania
- [ ] Licznik czasu: bez poświat, kreski ostre (nie rozmyte) w oknie i na pełnym ekranie
- [ ] Komunikat zabójstwa (Figma, 10.10, potrzebny drugi gracz): zabij kogoś (bomba / zepchnięcie do lawy) → na środku nad połową ekranu wskakuje „YOU KILLED <nick>” z czerwonym KILLED i czaszkami, pod spodem „+25$”; po ~2,5 s gaśnie. Zabity NIE widzi komunikatu, killfeedu w prawym górnym rogu już nie ma. Dwa zabójstwa szybko po sobie → drugi nick, komunikat od nowa, nie znika w połowie. Długi nick nie nachodzi na czaszki
- [ ] Sklep pokazuje angielskie nazwy (Bomb / Bridge / Grapple)
- [ ] Małe okno / telefon: wszystko się zmniejsza proporcjonalnie, nic nie wychodzi za ekran

## 🆕 NAJPIERW — ZMIANY Z 30.09-08.10

> **10.10:** potwierdzone ✅ gęsta lawa, mosty + ghost, jeden profil grafiki, drabiny. Eksplozje „raczej git, nie na 100%” — zostają do stałego testu T1-T7 niżej.

### 🌋 Gęsta lawa — ✅ Kacper 10.10: „gęsta lawa git”
- [x] Skok z dachu do głębokiej lawy → nie lecisz na dno, tylko wpadasz kilka studów i powoli opadasz
- [x] W lawie ruszasz się wyraźnie wolniej (jak w miodzie)
- [x] Trzymasz skok → powoli płyniesz w górę
- [x] Przy powierzchni trzymany skok wybija z lawy
- [x] Da się dopłynąć do brzegu (dach, gruz) i wyjść
- [x] Kamera pod powierzchnią → ekran pomarańczowy i rozmyty, nie widać ulicy na dnie
- [x] Opadniesz na dno pod lawą → **zero** obrażeń od upadku i brak wywrotki w locie
- [x] W lawie dalej boli (~7 s do śmierci z pełnym życiem)

### 🌉 Mosty — ✅ Kacper 10.10: „mosty git”
- [x] Celujesz w lawę → podgląd czerwony, klik nic nie robi, most nie znika z ekwipunku
- [x] Most między dwoma dachami leży i da się po nim przejść
- [x] Most wysunięty nad przepaść przechyla się i spada
- [x] Most postawiony na dachu przez murek/gzyms NIE wylatuje w powietrze
- [x] Bomba odrzuca cały most w jednym kawałku (nie rozpada się na deski)

### 🎨 Jeden profil grafiki (08.10) — ✅ Kacper 10.10: „jeden profil grafiki działa” (telefon niesprawdzony)
- [x] Gra startuje bez błędów (nie ma już trybów Ziemniak/Pełny ani klawisza G)
- [x] Wybuch: gruz i cząsteczki „pośrodku” — więcej niż dawny Ziemniak, mniej niż Pełny; meble się rozsypują; gruz leży ~10 s
- [ ] Na telefonie (jeśli możesz) kilka bomb naraz nie zacina

### 🧱 Twarde ruiny (08.10)
- [ ] Zawal kawałek budynku → część (~1/4) małych brył i fragmentów zostaje do końca rundy, twarda, w swoim kształcie — da się na nich stanąć
- [ ] Reszta dalej znika / jest gruzem bez kolizji; serwer nie laguje bardziej niż wcześniej
- [ ] Wklej z Output linie `[Collapse] … twarda ruina` i `kruszenie … małych twardych N`

### 💡 Latarnie i sygnalizatory (08.10)
- [ ] Bomba tuż przy latarni / sygnalizatorze → rozpada się na kawałki, nic nie wisi
- [ ] Bomba kilka studów dalej → przewraca się w całości (nie zostaje pół słupa ani sama głowica w powietrzu)

### ⏱️ Wyjście z Play w Studio (08.10, poprawione 19.10) — szybkość potwierdzona 20.10; poniżej szczegóły do sprawdzenia
- ❌ 19.10: poprawka z 08.10 nie działała — każde wyjście trwało ~27 s (log Studio)
- [ ] **(19.10)** Stop → Studio odwiesza się w ~1-2 s; w Output `BindToClose done po X s` z X poniżej 2
- [ ] Kup coś, Stop, Play → kasa i itemy zostały (zapis dalej działa)
- [ ] Jeśli dalej wisi: wklej linię `BindToClose: limit … minął — …` (mówi, co trzyma)

### 🚪 Drzwi (08.10)
- [ ] Zawal ścianę/strop przy drzwiach w PupleHotel i SandBuilding → drzwi spadają, nie wiszą
- [ ] Przez drzwi dalej da się przejść

### 🌉 Ghost mostu (08.10) — ✅ Kacper 10.10: „mosty git”
- [x] Celuj mostem w lawę (lawa w tle) → ghost WIDAĆ (pełny, zielony/czerwony, bez prześwitu)
- [x] Wejdź w budowanie, patrząc ukosem na ulicę → most stoi równo z ulicą (kąt co 45°), R obraca co 45°
- [x] Postawiony most stoi dokładnie tam i tak, jak pokazywał ghost

### 🪜 Drabiny (08.10, v3 — tylko łatwiejsze łapanie, reszta jak w zwykłym Robloxie) — ✅ Kacper 10.10: „drabiny sprawdzone”
- [x] Zwykły chód (bez sprintu) prosto na drabinę → łapie
- [x] Podejście lekko ukosem → łapie
- [x] Na górze wyjdź na dach → NIE pcha z powrotem na krawędź
- [x] Zejście po drabinie z góry na ziemię → zero obrażeń od upadku

### 🌆 Ładowanie mapy i przejście (07.10)
- [ ] Wejście do gry: ekran ładowania może trwać dłużej (cała mapa) — ile sekund? Na telefonie też
- [ ] Koniec odliczania: ekran płynnie ciemnieje, po ~1-2 s rozjaśnia się NA MAPIE, z cieniami i oświetleniem od razu (bez doskakiwania 10-20 s). Jeśli cienie dalej dochodzą → podnieść `Config.RoundTransition.SettleTime`
- [ ] Odliczanie przerwane (za mało graczy) → ekran nie zostaje ciemny
- [ ] Druga i trzecia runda: zburzony budynek wraca cały, nietknięte stoją; w Output linia `[Map] restored X/32 jednostek (...)` — X ≈ tyle, ile ruszyłeś (wkleić ją)
- [ ] Przyciemniony (ranny, nie przecięty) element wraca do normalnego koloru w następnej rundzie

### 💥 Destrukcja — poprawki
- [x] **Kebab**: końcówki filarków i narożny słupek nie wiszą, dach nie stoi na kawałku ściany (Kacper 01.10: „kebab git”)
- [ ] **Zielony**: zwal cały GreenBuilding → skrzynie, paczki i palety z górnych pięter NIE zostają w powietrzu
- [ ] **Kebab — dach**: czy dach potrafi jeszcze stać na jednym kawałku ściany w rogu (sprawdzić przy okazji)
- [ ] **Kolor gruzu (07.10)**: kawałki po wybuchu mają RÓŻNE odcienie szarego (od grafitu do jasnego popiołu), a nie jeden; dalej wyraźnie odróżniają się od mapy

---

## 💥 DESTRUKCJA — STAŁY TEST

Zawsze ta sama kolejność. 2 razy bez błędu pod rząd = destrukcja skończona.

- [ ] **T1** OrangeBuilding, parter — bomby w (−385, −145), potem (−365, −143), potem (−384, −121)
  → budynek kładzie się piętrami, nic nie wisi w powietrzu
- [ ] **T2** OrangeBuilding — bomba na piętrze Y 54, potem cała seria T1
  → gruz z góry spada razem z piętrem niżej
- [ ] **T3** Stań na piętrze Y 54, ktoś robi T1
  → jedziesz z piętrem, gruz NIE rani, na dole zwykły upadek
- [ ] **T4** GreenBuilding, parter koło (−250, −161) — 3 bomby co sekundę
  → wieżowiec składa się piętrami
- [ ] **T5** W trakcie T4 rzuć bombę w spadające piętro
  → tylko lekko je popycha
- [ ] **T6** Po T4 bomba w leżący gruz
  → robi dziurę, gruz lekko drga, nie wystrzeliwuje
- [ ] **T7** SandBuilding, parter koło (−157, 133) — 5 bomb w 3 sekundy
  → bez lagów
- [ ] Kurz przy zawalaniu wygląda dobrze (nie za mało)

**Nie może się stać:** blok wiszący w powietrzu dłużej niż sekundę · znikające piętro · śmierć od gruzu · wystrzelony blok.

## 💥 DESTRUKCJA — RESZTA

Budynki, które jeszcze nigdy nie były grane na nowej destrukcji:
- [ ] PurpleSchool
- [ ] OldBuilding1
- [ ] Construction
- [ ] PupleHotel
- [ ] SandBuilding (poza T7)
- [ ] OldBuilding2

Reszta:
- [x] Tory w budynku spadają z nim, reszta torów zostaje ✅ 01.10
- [ ] Wieszaki i drobne rzeczy przy bombie znikają w chmurze pyłu
- [ ] Meble dalej od bomby odlatują w całości, druga bomba je rozwala
- [ ] TV na szafce i deski rusztowania nie wiszą w powietrzu
- [ ] Auto przy bombie wybucha i płonie
- [ ] Auta tuż obok wybuchają po kolei
- [ ] Gruz leży płasko, nie sterczy

## 🧍 GRACZ I ZAPIS

- [ ] Wyjdź i wejdź → **ta sama postać** (w Studio pierwsze wejście od zera — nowy zapis)
- [ ] Kasa i itemy zostają po wyjściu
- [ ] 2 graczy w Studio, drugi wchodzi w trakcie odliczania → ląduje w lobby jako widz, runda się normalnie kończy
- [ ] Stop Play → w Output: `BindToClose done (zapisów w toku: 0)`

## 🛒 SKLEP I HOTBAR

- [ ] Szybkie klikanie KUP → każdy zakup przechodzi
- [ ] Następny item w sklepie i od razu Q → kamera wraca płynnie, bez starego tweena
- [ ] Trzymasz bombę, giniesz albo kończy się runda → jeden klik znowu ją daje
- [ ] Masz 1 bombę i most, rzucasz bombę → zaznaczenie nie skacze samo na most
- [ ] Rzucasz bomby tak szybko, jak pozwala pasek → każdy rzut wychodzi

## 🏃 RUCH

- [x] Pasek staminy jest dalej po śmierci ✅ 01.10
- [x] Przewrócony bombą (ragdoll) z Shiftem → stamina się nie zużywa ✅ 01.10
- [x] W ragdollu głowa nie wykręca się ✅ 01.10
- [x] Hak w ragdollu nie strzela ✅ 01.10
- [x] Ekran ładowania przy wejściu znika normalnie ✅ 01.10

## 📜 STARE ZALEGŁE

- [x] Obrażenia od upadku — 5 przypadków z 19.09 ✅ 01.10
  *dla Claude'a:* lista przy `FallDamageService` w `docs/ARCHITECTURE.md`


## Animacje ruchu — stan 23.10

Kierunkowy chód/idle/skok z 11.10 został **wycofany**. Nie publikować jego 15 klipów i nie wykonywać dawnych testów DirectionalLocomotion jako zaległości. Oryginalny Animate pozostaje aktywny; historia prób w archiwum TESTY. Osobny gest F poniżej nadal jest aktualny.

### Default + custom push R15 — 11.10

Aktywne: oryginalny Animate + `ReplicatedStorage.PushAnimations.Push_TwoHands_R15` (Action, 0.7 s, kontakt0.15, tylko 8 stawów górnej części ciała). `PushController` odtwarza na F, czyści track na respawn i przerywa przy śmierci/ragdollu/końcu rundy. `PushService` rezerwuje cooldown2.5 na próbę, po `Config.Push.Windup=0.15` ponownie sprawdza postać/rundę/zdrowie/ragdoll i wybiera cel. Remote Push bez payloadu; Pushed bez zmian. Koniec rundy unieważnia oczekujące próby. Config.Push.AnimationId=0, AnimationStudioPreview=true — lokalny podgląd, publikacja assetu nadal wymagana. Cofnięcie gestu AnimationEnabled=false, opóźnienia Windup=0. Szczegóły i lista prób Kacpra: `artifacts/animations/push_r15/README.md`. Kompilacja/synchronizacja i czysta logika sprawdzone, Play nieuruchamiany.

## Round transition / 3-2-1 — 18.10.2026 (do sprawdzenia przez Kacpra)

- Start: teleport pod czernią → mapa → wielkie 3,2,1 Fredoka/studs; ruch, F, bomba, hak i most dopiero po 1; lawa też startuje wtedy.
- Ostatnia śmierć: 3s bez znikania lawy/mapy; powrót martwego do lobby jak wcześniej; reset pod zasłoną.
- Wygrana po czasie: nagroda raz, przed resetem; zasłona schodzi w lobby.
- Dwie osoby: wspólne odliczanie i brak przewagi przy pierwszym spawnie.
- Dołączenie podczas odliczania: pozostała liczba, nie nowa pełna trójka; nowy gracz jest widzem do kolejnej rundy.
- Dev K z lobby: nadal pełne 3,2,1; K podczas countdown nie kończy następnej rundy.
- Telefon i szeroki ekran: cyfry mieszczą się w ekranie; następna runda i respawn nie dublują UI.

## Uzupełnienia po audycie 23.10 — DO TESTU, bez nowych zaliczeń

- [ ] **Sklep a start rundy:** zostaw otwarty sklep do końca lobby → panel zamyka się, kamera śledzi nową postać na arenie; nie zostaje przy starej postaci w lobby. Powtórz po śmierci/respawnie i ręcznym zamknięciu Q/X.
- [ ] **Stałe lampy:** szybko przewijaj bomba → RPG → napój i wracaj → prawidłowe światło od razu, bez czekania kilku sekund. W scenie brak widocznych nośników lamp.
- [ ] **Produkcja, gest F:** po publikacji animacji i wpisaniu ID sprawdzić gest na prawdziwym serwerze u siebie i drugiego gracza. Sam podgląd Studio z AnimationId=0 nie zalicza tego testu.
- [ ] **Produkcja, lawa:** jeśli EditableMesh jest niedostępne, widoczna pozostaje oryginalna tafla. Bez znikania lawy, obraz/fizyka i FPS do oceny także na telefonie.
- [ ] **Większa grupa:** po przygotowaniu multi-spawn sprawdzić czas wejścia wszystkich na mapę, brak spawnów w jednym miejscu/ścianie i wspólny start po 3-2-1.

Telefon i anty-cheat mają jeszcze braki kodu opisane w DO_RELEASE. Nie traktować powyższej listy jako informacji, że zostały już wdrożone. Wycofane scenariusze zachowano w [archiwum](archive/2026-10-23/TESTY.md).

- [ ] COSMETICS 27.10: wszystkie produkty razem bez kategorii; licznik kasy bez ramki po lewej, czytelny przy pasku Robloxa i na mniejszym ekranie; brak napisu THE CLOSET, tytuł wyśrodkowany; wybór produktu i garderoba nadal działają.

- [ ] COSMETICS 27.10: buy 500/750/600, equip all three, turn preview, walk/jump/ragdoll, unequip one preserving others, rejoin and verify ownership/outfit.

- [ ] Fitting revision: drag mouse/touch in scene, release outside area, alt-tab mid-drag; no rotation when buying/back/closing. HUD returns on close/round start/death. All three accessories visible with feet/head in camera; BUY/EQUIP/UNEQUIP still work.

- [ ] Fitting polish: X/BUY/BACK have no rectangular black backing; BUY changes to EQUIP/UNEQUIP visibly; whole body remains above purchase bar; original spotlights visible; lighting outside shop unchanged.

- [ ] COSMETICS 27.10: hover edge cards at top/bottom and narrower window without clipping; no Studs on tiles; preview readable front/back with original scene lamps; sign readable from lobby spawn.


### COSMETICS follow-up 27.10 — pending Kacper Play
- Open wardrobe: HUD-style wallet amount/icon; X on list, only BACK in fitting; BACK restores list.
- Try vest while looking up/down beforehand: head joins torso, vest lower; rotate 360 degrees and verify lamp stays fixed relative to scene.
- Buy changes wallet amount; close/reopen and respawn: no leftover preview/fill; normal HUD restored.
Static Edit review, source parse/sync and build are not Play acceptance.
