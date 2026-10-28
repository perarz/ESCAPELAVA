# STATUS — ESCAPE LAVA

Stan sprawdzony **23.10.2026**: kod repo, lokalna historia Git, checklisty i odczyt Studio w Edit. Audyt nie obejmował Play, pomiaru FPS ani publikacji. Szczegóły rozbieżności: [audyt kontekstu](CONTEXT_AUDIT_2026-10-23.md).

## TELEFON — punkt wznowienia 28.10.2026 (premiera 6.11)

Przyciski dotykowe wdrożone według decyzji Kacpra z 28.10 (plan: [ROADMAP](ROADMAP.md) → „Sterowanie na telefonie”). Okrągłe przyciski w stylu slotów przy skoku Robloxa: **SPRINT** (trzymanie), **PUSH**, w trybie mostu **BUILD/ROTATE** (dotknij miejsce → duch staje, BUILD stawia), z RPG **AIM** (przełącznik) i **FIRE**. Bomba, hak, napój i C4 już wcześniej działały dotknięciem ekranu. Nowy `TouchControlsController` + podpięcia w Movement/Push/Bridge/Rpg, bez zmian na serwerze. `HUD.TouchControls` postawiony przez MCP, `HUD.Detonator` przesunięty z Y 0,55 na 0,40 (zwolnił miejsce nad skokiem). 7 plików zsynchronizowanych z Studio (suma zgodna z dyskiem) i parsuje się; zrzut układu z atrapą skoku: `artifacts/touch/touch_controls_preview_2810.jpg`. **Play nietestowany, Cmd+S wymagany.** Testy: [TESTY](TESTY.md) → „Telefon”.

## COSMETICS — punkt wznowienia 27.10.2026

**28.10 — przycisk HUD Cosmetics:** przezroczystość `Fill.Studs` zmieniona z 0,9 na 0,25 jak w Inventory. Potwierdzone odczytem Edit; wymagany Cmd+S. Do sprawdzenia w Play: widoczność wzoru na przycisku.

Bieżący zakres rozmowy: dopracowanie sklepu i garderoby. Kacper zezwolił agentowi również na edycję ich UI w Studio. Poniższy stan zastępuje starsze wpisy o brakującym imporcie, studsach kafli, prostym liczniku i jednoczesnym BACK/X.

**27.10 wieczór — sklep v4 („item shop”, decyzje Kacpra):** układ zostaje (przewijany katalog → przymierzalnia), wygląd przerobiony, bo poprzedni był „AI slop”. **Rzadkość** zamiast kolorów kategorii: dynia HALLOWEEN (ciemny fiolet + pomarańczowe promienie), kamizelka EPIC, plecak RARE; LEGENDARY/COMMON czekają na kolejne przedmioty (`CosmeticDefinitions.rarity`, kolory w `Config.Cosmetics.UI.Rarities`). **Kup = od razu załóż** (serwer zapisuje kasę, własność i strój w jednym zapisie). Karty pokazują sam przedmiot, duży; duża karta stale się kołysze, reszta po najechaniu. Przymierzalnia bez granatowego paska: rzadkość, nazwa, cena, „NEED X$ MORE — SURVIVE N ROUNDS”, duży BUY jak w sklepie broni, samoobracanie po 3 s. Zakup: odliczanie kasy + UNLOCKED! na środku. Kopia poprzedniego UI: `ServerStorage.CosmeticsUI_v3_2710`; zapis budowy: `artifacts/cosmetics/shop_v4_ui.luau`. Zrzuty z Edit obejrzane, 5 plików zsynchronizowanych i parsuje się. **Play nietestowany, Cmd+S wymagany.** `rojo build` pada na starym `src/shared/Modules/init.meta.json` (Tags jako SharedString, plik z września) — niezwiązane z tą zmianą, `rojo serve` działa. Testy: [TESTY](TESTY.md) → „sklep v4”. **Później 27.10:** tło katalogu lekko animowane (studsy płyną po skosie, poświata lawy oddycha; `Config.Cosmetics.UI.Backdrop*`), szpara pod głową w przymierzalni naprawiona (patrz niżej), a żółty nagłówek Inventory ma ostre górne rogi (zmiana w placu, opis i cofnięcie w STUDIO_CONTRACT). Do tego zębatka ustawień w prawym górnym rogu (`HUD.SettingsCorner`) i półprzezroczysty numer wersji w prawym dolnym (`HUD.Version`, numer w `Config.UI.Version` = "0.8"). Zrzuty z Edit obejrzane, kod zsynchronizowany; **Cmd+S wymagany**, Play tych zmian nietestowany.

- Wszystkie trzy akcesoria są zaimportowane: dynia 500$, kamizelka 750$, plecak 600$. Własność i wyposażenie mają zapis; kosmetyki nie dają bonusów do gry.
- Pełnoekranowy, ciemny katalog z pionowym przewijaniem i różnymi rozmiarami kafli; bez zakładek kategorii i studsów na kaflach. Marginesy i mniejszy hover poprawione. Kategorie nadal służą do składania stroju.
- Przymierzalnia używa lokalnej kopii gracza w istniejącej scenie; obrót przeciąganiem myszy/dotykiem. W niej tylko BACK do listy, X tylko na liście. Portfel skopiowany z HUD (ikona + zielona kwota), widoczny w obu widokach.
- Szpara między głową a tułowiem w przymierzalni (na postaci w grze jej nie ma) — **przyczyna zmierzona w Play 27.10**: po wstawieniu kopii do świata automatyczne skalowanie Humanoida zmniejszało dynamiczną głowę z 1,2 do 1,0 studa i przebudowywało stawy → szpara 0,09 studa. W Edit to się nie dzieje, dlatego statyczne sprawdzenie wyglądało dobrze. Poprawka: `CosmeticsPreview` wyłącza `AutomaticScalingEnabled` w kopii (pomiar: szpara −0,015 jak w szablonie). Do potwierdzenia okiem Kacpra w nowym Play.
- Kamizelka obniżona o 0,18 studa przez attachment assetu. Dodatkowe lokalne światło jest teraz przypięte do nieruchomej platformy, poza obracaną postacią; sprzątane przy wyjściu. Dwa oryginalne reflektory Kacpra zachowane.
- Napis nad stoiskiem: wysokość 24 study, zasięg 300, AlwaysOnTop i jawny Adornee. Spawn oddalony o ok. 106,5 studa (stary limit 80). Zrzut Edit nie renderował napisu — widoczność ze spawna nadal do potwierdzenia.
- Ostatnia kontrola: składnia i synchronizacja CosmeticsController/CosmeticsPreview, Rojo build, diff-check oraz statyczny podgląd Edit. Tymczasowa postać/światło usunięte, GUI zamknięte, HUD i FOV przywrócone. **Nie uruchamiano Play; Cmd+S i publikacja niepotwierdzone.**

Następny krok: test Kacpra — głowa po przymierzeniu kamizelki, jej wysokość, obrót przy nieruchomym świetle, BACK/lista/X, kwota po zakupie, napis ze spawna. Prośba „zaktualizuj kontekst” nie jest potwierdzeniem tych testów. Szczegóły obiektów w [STUDIO_CONTRACT](STUDIO_CONTRACT.md), przypadki w [TESTY](TESTY.md).

## Gra obecnie

`LOBBY → PREPARING → COUNTDOWN → ROUND → FINISHING → RESETTING → LOBBY` (26.10: bez POST_ROUND — po zasłonie od razu lobby; NIEPRZETESTOWANE).

Lobby **25 s**; przygotowanie i teleport pod zasłoną; **3-2-1** na mapie z blokadą ruchu/itemów; runda z płynnie przyspieszającą lawą, **bez faz**; **3 s FINISHING**, wypłata ocalałym, zasłona i cleanup/odbudowa, potem **od razu lobby** (10 s „ROUND OVER” w lobby usunięte 26.10). Produkcyjny cel rundy: **80 s**, obecnie **240 s testowo**.

Kod zawiera **6 itemów**: Bomb 50$, Bridge 100$, Grapple 40$, Energy Drink 25$, RPG 75$, **C4 60$** (25.10 — C4 = zaplanowana sticky bomb, decyzja Kacpra; przyklejanie, G i rzut z ikoną zadziałały w testach; 25.10 wieczorem wysoki łuk jak granat + zamach ręki — NIEPRZETESTOWANE; `ReplicatedStorage.C4` i `HUD.Detonator.DetonateButton` postawione przez MCP). Loadout to **3 stałe sloty**, ekwipunek jest dostępny wyłącznie w lobby. Nowy item nie wymaga czwartego slotu.

Destrukcja v4 obejmuje **wszystkie 10 budynków**; starszy pass podparcia działa poza nimi. Fizyka dużych brył zostaje. **Gruz nie zadaje obrażeń**; lokalne odłamki nie mają kolizji ani wpływu na promienie. Obrażenia od upadku pozostają. Jeden profil `Config.Graphics.Profile`, bez trybów Potato/Full i ich panelu.

Nagrody: przetrwanie 100$, kill 25$, pickup 10$, kasa startowa 100$. Wybuchy bomby/RPG/auta/beczki ranią także odpalającego; samobójstwo nie daje nagrody. Rocket jump wycofany 21.10 — nie jest zadaniem do zrobienia.

## Potwierdzone w dotychczasowych testach Kacpra

- Sklep-NPC i spawn w lobby (wcześniejsza wersja sklepu), rig R15 na Motor6D i ragdoll, zapis kasy w Studio.
- Hak po łuku, kamera zza prawego ramienia bez x-ray i head tracking (22–23.09).
- Poprawki 25–26.09: kolaps fizyką, brak taśmociągu, respawn po śmierci, hak w ragdollu, próba 5 wybuchów (26.09).
- Tory, pasek staminy po śmierci, ragdoll/ruch głowy i **5 zaległych przypadków fall damage** (01.10, zaznaczone w TESTY).
- Drabiny, gęsta lawa, mosty i ghost, jeden profil grafiki (10.10).
- Ramka slotu (10.10), ikony v2 pierwszych trzech itemów (19.10), szybkie wyjście z Play (20.10).

Te potwierdzenia dotyczą wskazanych wersji. Nie zaliczają automatycznie późniejszych zmian ani całej obecnej gry.

## Zaimplementowane, pełna akceptacja pozostaje otwarta

Listy przypadków są w [TESTY](TESTY.md); nie oznaczać ich jako zaliczonych na podstawie kompilacji lub odczytu Edit.

- Destrukcja całego miasta, zaklinowania, osierocone dekoracje, twarde ruiny, auta; stały test **T1–T7 dwa razy pod rząd** nadal nie ma zapisanego kompletu zaliczeń.
- Start klienta z `ClientReady` (18.10), zapis/loadout i obsługa panelu Inventory, hotbar ze stałymi slotami, pełny przebieg rundy i ekran ładowania v2.
- RPG i odrzut, energy drink i gest picia, wyciąganie itemów, chwyt RPG oburącz i poprawki jego ułożenia (20–21.10).
- **RPG celowanie na PPM (24.10)**: zoom, ciało i tułów w stronę celu, celownik `HUD.Crosshair` (postawiony przez MCP, wygląd zaakceptowany na zrzucie; zapis Cmd+S niepotwierdzony — sprawdzić, czy jest w placu), chód wolniej bez sprintu. Kod zsynchronizowany z Studio i parsuje się (odczyt Edit); w Play nietestowane. **25.10**: RPG na prawym barku (nowa poza rąk z IK + tułów bokiem −50°), lufa w kierunku lotu rakiety, rakieta startuje z lufy (`Rpg.MuzzleSide` 1,0), pochylenie całe na talii, mocniejszy zoom (FOV −18, PushIn 3) — NIEPRZETESTOWANE.
- Beczki wybuchowe, zapłon od F, łańcuchy i wybuch przy upadku (21.10).
- Nowy panel sklepu i automatyczne kadry; **23.10** wydłużona ściana/pokój, przesunięta wystawa, kąt kamery yaw 20° / pitch 12°, następnie ruchomą lampę zastąpiły stałe `ShopLights` (po jednej nad sześcioma modelami plus doświetlenie skrajów). Najnowszy kod przy zamknięciu sklepu po respawnie przypina kamerę do aktualnego Humanoida; test pozostaje otwarty. **25.10** panel `ShopUI` przebudowany przez MCP (węższy, ciemne strzałki przy panelu, cena nad BUY, bez kasy w nagłówku) — zrzut z Edit pokazany, ocena Kacpra i zapis Cmd+S niepotwierdzone; kopia starej wersji w `ServerStorage.ShopUI_Backup_2510`.
- **Panel ustawień (26.10)**: zębatka pod INVENTORY (zawsze widoczna) otwiera panel SETTINGS z dwiema opcjami — kamera nad prawym/lewym ramieniem i włącz/wyłącz przechył kamery + zmiany FOV; zapis na koncie gracza (`SettingsService`). Zębatka i panel postawione przez MCP (zapis Cmd+S niepotwierdzony), kod zsynchronizowany i parsuje się (odczyt Edit); w Play nietestowane. Oprawa lawy wstrzymana na rzecz panelu — decyzje w ROADMAP.
- **GRAPHICS LOW / HIGH + oprawa lawy (27.10)**: trzeci wiersz panelu ustawień (postawiony przez MCP, Cmd+S niepotwierdzony); start: telefon LOW, komputer HIGH. Na HIGH: łuna na ścianach tuż nad lawą, iskry i popiół rosnące z lawą, rozbryzg przy wpadnięciu (`LavaSplashController`). Tylko u klienta, bez kolizji. Kod zsynchronizowany i parsuje się (odczyt Edit); w Play nietestowane. Plan: ROADMAP.
- Oprawa lawy: fala lokalnej siatki i FX v5; zachowanie na urządzeniach i FPS nadal do sprawdzenia. Odczyt działania siatki w sesji 12.10 nie jest akceptacją wyglądu/FPS.

## Braki potwierdzone w kodzie / placu

- **Telefon:** 28.10 przyciski SPRINT/PUSH/BUILD/ROTATE/AIM/FIRE wdrożone (sekcja TELEFON na górze) — czekają na test Play na emulatorze i prawdziwym telefonie.
- **Anty-cheat:** obecny pomiar poziomy co 2 s, limit sprint +8, kara po 3 przekroczeniach. Pojedynczy teleport i lot w pionie nie są pokryte. Plan paczki 6 ma zamknięte decyzje: cofnięcie → powtarzane naruszenia: kill → kick, pion po ~1 s; potrzebuje wyjątków dla legalnej fizyki.
- **Skala:** spawn postaci nadal sekwencyjny; HeadAim nadal do wszystkich; bootstrap serwera bez izolacji błędów `init`. Odbudowa tylko naruszonych jednostek już istnieje, jej koszt wymaga testu.
- **Studio 23.10:** `Workspace.SpawnPoints` ma **0 dzieci** — kod korzysta z fallbacku. Rozmieszczenie multi-spawn i docelową liczbę graczy trzeba przygotować/ustalić przed testem większej grupy. `Config.Game.MaxPlayers = 20` nie ustawia limitu miejsca Roblox; limit publikowanego serwera pozostaje do sprawdzenia.
- **Studio 23.10:** brak zapisanych modułów w `ServerStorage.StructureData` (0 dzieci/brak folderu); analiza budynków nadal wykonywana w grze. Przed bake sprawdzić zaokrąglenia i walidację rewizji.
- **Animacja F:** `Config.Push.AnimationId = 0`, podgląd Studio włączony. Publikacja assetu potrzebna dla tego gestu poza Studio; sama mechanika pchnięcia jest osobna.
- **Audio:** 5 pustych ID destrukcji, brak dźwięku strzału RPG; łyk opcjonalny.
- **Hak pod nogi:** 26.10 serwer ocenia gotowy łuk przed zużyciem, z tym samym minimalnym czasem co klient. Zmiana i pozostałe poprawki po pełnym przeglądzie czekają na Play — patrz [raport](CODE_REVIEW_2026-10-26.md).
- **Dev:** uprawnienia nadal po nicku. Przejście na UserId pozostaje otwarte; przed wydaniem dev musi być wyłączony.

## Stan repo i Studio

**27.10 — import dyni zakończony:** `ReplicatedStorage.Cosmetics.HalloweenPumpkin` zawiera 4 MeshParty i HatAttachment (0,0.445,0) względem Handle, 3 weldy, prawidłowe kolory, brak kolizji/masy i SmoothPlastic. Rozmiar ok. 1.90 × 1.91 × 1.92 studa. Mocowanie obejrzane na nieruchomej kopii StarterCharacter w Edit; kopia podglądu usunięta. Oryginał importu zachowany w `ServerStorage.HalloweenPumpkin_Imported_2710`. Cena 500, katalog i zakup korzystają z istniejącej definicji. Kamizelka i plecak czekają na import użytkownika; Play i zapis Cmd+S niepotwierdzone.

**27.10 — uproszczenie COSMETICS na prośbę Kacpra:** usunięto Wallet, napis ESCAPE LAVA / THE CLOSET, zakładki i etykiety kategorii. Wszystkie produkty we wspólnym katalogu (garderoba nadal tylko posiadane). Sam licznik kasy po lewej, poniżej kontrolek Robloxa; główny tytuł wyśrodkowany. Kategorie wyposażenia i zapis pozostają bez zmian. Kopia UI: `ServerStorage.CosmeticsUI_v2_2710`; skrypt zmiany: `artifacts/cosmetics/simplify_ui.luau`. Build i kontrola Edit, bez testu Play. Wymagany Cmd+S.

**26.10 — poprawka wyglądu COSMETICS:** po odrzuceniu pierwszego małego panelu przebudowano sklep na pełny ekran, dodano bezpośrednie zakładki kategorii i większą asymetryczną wystawę. X jest kopią przycisku Inventory. Układ obejrzany w Edit, bez Play; import modeli nadal pozostaje otwarty. Szczegóły w [planie](COSMETICS_PLAN.md).

**26.10 — COSMETICS:** przygotowano kod sklepu/garderoby, zapis własności i stroju, bezpieczny zakup, lokalną przebieralnię i katalog. Po osobnej zgodzie Kacpra postawiono UI, przycisk pod Inventory i napis nad ClothesShop.NPC; układ obejrzano w Edit. **Brakuje importu trzech FBX** — kafelki pokazują COMING SOON, zakup niedostępnego modelu jest blokowany. Ceny 500/750/600 zaakceptowane. [Plan i realizacja](COSMETICS_PLAN.md), [kontrakt](STUDIO_CONTRACT.md), testy w TESTY. Potrzebny Cmd+S; bez Play i publikacji.

**27.10 — ikony itemów v3:** wszystkie 6 ikon wyrenderowane od nowa z modeli bez studsów (te same ujęcia, światło i obrys co v2), wgrane i podpięte w `ItemDefinitions`; pliki i ID w `output/inventory-icons-v3/README.txt`. Studio zdjęciowe usunięte, ustawienia przywrócone. Play nietestowany.

**26.10 — wygląd modeli itemów:** Studs usunięte tylko z 156 części modeli itemów w ReplicatedStorage i na wystawie. Wygląd otoczenia przywrócony na podstawie historii Studio. Zakres: [kontrakt Studio](STUDIO_CONTRACT.md). Potrzebny zapis Cmd+S; publikacji nie potwierdzono.

**25.10 — częściowy przegląd itemów:** wdrożone optymalizacje gestów i filtrów lotu C4 oraz poprawki walidacji/loadoutu/przełączania. Zakres, weryfikacja Edit i propozycje dalszych porządków: [raport przeglądu](ITEM_REVIEW_2026-10-25.md). Play pozostaje otwarte w [TESTY](TESTY.md); nie traktować tej kontroli jako akceptacji rozgrywki.

**26.10 — pełny przegląd kodu:** przejrzane całe `src/` i 9 narzędzi korzenia; poprawki i porządki w 33 plikach src oraz 2 narzędziach. Pokrycie, kontrola składni/synchronizacji i pozostawione ryzyka: [pełny raport](CODE_REVIEW_2026-10-26.md). Testy Play i pomiary wydajności pozostają otwarte.

**28.10 — git:** cała praca 21–27.10 (C4, COSMETICS, ustawienia, GRAPHICS LOW/HIGH i oprawa lawy, przegląd kodu, dokumentacja) zacommitowana na `main` i wypchnięta na `origin/main` (na prośbę Kacpra). Nadal NIEPRZETESTOWANE w Play. Lokalna gałąź `marketing/kampania-2` została na `0d6c63c` (bez własnych commitów).

Studio: `ESCAPE LAVA`, placeId **107369017875577**, Edit. Przy pierwszym odczycie 23.10 sumy `Config` i `ShopController` zgadzały się z dyskiem. W trakcie audytu pojawiły się dalsze robocze zmiany sklepu (stałe ShopLights, CameraSubject po respawnie); pierwszy pomiar nie potwierdza synchronizacji tych nowszych zmian. UI, modele i zmiany sceny wymagają zapisu placu **Cmd+S**; odczyt nie potwierdza zapisu na dysku ani publikacji.

`artifacts/`, `output/`, `.codex/`, główny `AGENTS.md` i `docs/AGENTS.md` były nieśledzone. Nie dodawać ich zbiorczo do commita. **`marketing/` celowo poza gitem: repo `perarz/ESCAPELAVA` jest PUBLICZNE**, a plan kampanii zawiera konta (także te „bez marki”), budżet i creatorów. Commit/push na prośbę Kacpra.

## Kolejność dalszych prac

1. Test Kacpra z TESTY, w tym T1–T7 dwukrotnie; naprawy tylko na podstawie konkretnych zgłoszeń i aktualnego logu.
2. Telefon, anty-cheat i przygotowanie większego serwera; test zapisu/obciążenia na rzeczywistym serwerze.
3. Test łuku i zamachu C4 oraz postawy i zoomu RPG, poprawka haka, audio, publikacja animacji F i bake.
4. Ustawienia produkcyjne oraz pełny test z ekipą na PC i telefonach. Szczegółowa lista: [DO_RELEASE](DO_RELEASE.md).

To porządek pracy wynikający z istniejącej listy; nie oznacza zatwierdzenia nowego zakresu ani zmiany designu.

27.10: All three cosmetics imported into ReplicatedStorage.Cosmetics (500/750/600). Static outfit inspected front/back in Edit; temporary mannequin removed. Play purchase/save/movement checks pending. Cmd+S required.

27.10 fitting revision: full-screen scene, hidden catalog header and HUD while cosmetics is open (HUD restored on close), bottom purchase strip, BACK/X. TurnLeft/TurnRight removed; Fitting.RotateArea handles mouse/touch drag, global release and window focus cleanup. Camera framed from character bounds. Removed native rectangular GUI borders and card Orbit. Backup: ServerStorage.CosmeticsBeforeFitting_2710. Edit screenshot checked, source parse/sync and Rojo build passed; Play interaction not tested.

27.10 camera/strokes follow-up: CosmeticsPreview now removes runtime-only BaseParts before posing the rig, restores template PivotOffset and uses HumanoidRootPart as PrimaryPart. This prevents ragdoll helpers from distorting bounds; live camera result still needs confirmation. COSMETICS text strokes: black Miter, 5 for TextSize >=32, otherwise 3; button borders 4, ActionBar border 4. Source parse/sync and build passed; no Play test. Cmd+S required.

27.10 fitting polish: rectangular black corners fixed (border Miter -> Round, text retains Miter); X/BUY/BACK rebuilt with separate surface and label. Higher/wider camera checked in Edit with original scene lights. Ambient override removed. Two original lights found enabled outside ClothesShopScene; neither deleted nor replaced. Screenshot review, source sync/parse, build/diff checks complete; Play interaction remains unconfirmed. Cmd+S required.

27.10: removed cosmetic card Studs and catalog footer slogan; added 24px internal scroll padding, 28px gaps, reduced hover to 1.015. Reviewed largest tile enlarged in Edit. Local preview-only PointLight fill added (brightness 2/range 16), original lamps untouched; lighting reviewed in Edit. Sign raised to world offset Y=9, max distance 300, AlwaysOnTop=true; spawn-to-sign distance measured 106.5 (old limit 80). Source parse/sync/build passed, Play pending. Cmd+S required.

27.10 sign follow-up: explicitly assigned CosmeticsSign.Adornee to NPC.Head. Enabled/labels/300-stud range verified by Edit read, but the Edit capture did not render the BillboardGui (AbsoluteSize 0); actual spawn visibility still requires Kacper's Play check.

27.10 cosmetics follow-up: fitting shows BACK only; catalog shows X. HUD Cash visual cloned into cosmetics, replaces plain Balance; visible in both views. Vest anchor raised by 0.18 locally to lower worn geometry by 0.18 studs. Preview strips inherited JointInstances and resets Bone.Transform so live neck/waist pose cannot conflict with restored body pose. Fill anchored to stationary platform and cleaned up separately. Static Edit review shows joined neck (attachment gap 0.000015 stud), lower vest, separate wallet/BACK; not proof of live fix. Both sources parsed/synced, Rojo build and diff check passed. Play pending; Cmd+S required.

27.10: Removed only the 200 front rim triangles from HalloweenPumpkin.FaceBlack; 456 rear-face triangles remain. Mesh baked into DataModel content via CreateDataModelContentAsync, applied to existing MeshPart with original size/CFrame. Four parts and HatAttachment preserved. Edit front view inspected, temporary preview removed. Backup: ServerStorage.HalloweenPumpkin_BeforeRimRemoval_2710. Cmd+S required; Play not tested. Local build.py no longer creates front rims; existing FBX/blend/previews are older and have NOT been regenerated.

27.10 CORRECTION after user report: the Studio EditableMesh rim edit was rejected as broken. Restored FaceBlack from HalloweenPumpkin_BeforeRimRemoval_2710 using original MeshId 99943081561875, original Size and CFrame. Do NOT reuse opaque DataModel mesh edit. Blender original opened and only front black rim vertices deleted; rear face remains 456 triangles. Saved HalloweenPumpkin_no-rims.blend and HalloweenPumpkin_no-rims.fbx, plus PumpkinBackFace.fbx (only changed mesh). front_no-rims.png rendered and inspected. Studio currently has ORIGINAL model with rims; corrected FBX NOT imported yet. CUA import blocked by ScreenCaptureKit error -3811 after initial timeout. Next: import corrected FBX through Studio, fit using same shared origin/attachment; do not blindly copy old FaceBlack Size because removing front geometry changes its bounding box. Verify front/back before replacing asset. Cmd+S remains unconfirmed.

27.10: Na prosbe Kacpra napis CosmeticsSign podniesiony 3x: StudsOffsetWorldSpace.Y z 9 do 27. Pozostale ustawienia zachowane. Odczyt Edit potwierdzony; Cmd+S wymagany.

27.10: Ostateczna wysokość CosmeticsSign.StudsOffsetWorldSpace.Y = 24 (zamiast 27), ustawiona i potwierdzona odczytem Edit. Cmd+S wymagany.
