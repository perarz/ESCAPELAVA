# STATUS — ESCAPE LAVA

Aktualizacja **09.11.2026**. Ostatni pełny audyt 23.10: kod repo, lokalna historia Git, checklisty i odczyt Studio w Edit, bez Play, pomiaru FPS i publikacji ([audyt kontekstu](CONTEXT_AUDIT_2026-10-23.md)). Sekcje niżej idą od najnowszej; starszy wpis nie unieważnia nowszego.

## 08–09.11 — drzewko umiejętności i rebirth u maga: PLAN, kodu i panelu brak

Kacper chce dalszego rozwoju, „żeby gra się nie nudziła”. Pełny plan: [SKILLS_PLAN](SKILLS_PLAN.md). Ustalone:
- **Drzewko:** korzeń +5% szybkości, od niego odnogi po 2 poziomy. Poziom I kosztuje kasę, poziom II kasę i wymaganie (kille, przetrwane albo rozegrane rundy).
- **Odnogi:** SPEED, STAMINA, LAVA SKIN, TOUGHNESS, GREED i FORCE (F wybija małą dziurę w ścianie).
- **Rebirth:** zabiera tylko drzewko. W zamian daje +5% kasy na zawsze, a do 10. rebirthu także nowe odnogi i itemy w sklepie. Liczba rebirthów bez limitu.
- **Wygląd:** kamera na maga `TowerMage` i panel, efekty z ui-resources.com, ikony game-icons z czarnym obrysem i mikroanimacje (sekcja w planie).
- **Zasoby:** 14 obrazów wgranych 09.11 za zgodą Kacpra. ID są w planie i w `artifacts/ui-effects/ASSETS.md` (poza gitem, repo publiczne).

Otwarte:
- akceptacja liczb przez Kacpra;
- nagrody rebirthów 5–10;
- liczba rebirthów przy nicku;
- przed wydaniem drzewka podpis CC BY game-icons w opisie gry (DO_RELEASE).

Agent, który to wdraża, zaczyna od sekcji „Brief dla agenta wykonawczego” na końcu SKILLS_PLAN. Są tam: pytania do Kacpra przed kodem, gotowe miejsca w kodzie, mag w placu, ID zasobów i szkic testów.

Następny krok: podgląd panelu `StarterGui.SkillTree` przez MCP do oceny wyglądu. Kacper go zlecił 09.11 i przerwał aktualizacją kontekstu. Kod (etap 2) rusza dopiero po commicie drugiego agenta, bo dotyka tych samych plików (`Config`, `Remotes`, `MovementController`, `PlayerService`, `PushService`, pliki `init`).

## 09.11 (noc) — lobby oddalone od mapy, NIEPRZETESTOWANE, Cmd+S wymagany

Kacper: „oddal to lobby od mapy”. Wybrał ~500 studów od barier i zostawienie chowania lokalnego (sama odległość wyspy nie schowa — plac bez mgły). Przez MCP w Edit przesunięte o (+204, 0, +330) prosto od mapy, na tej samej wysokości: `Workspace.Lobby` (z `SpawnPoints`, straganami i napisami) i `Workspace.WizardTower`, czyli 3764 party i pivoty 265 modeli bez `PrimaryPart`. Pozycje docelowe liczone przed ruchem — każdy part sprawdzony, odchyłka 0. Środek wyspy (59, 451) → (263, 781), brzeg ~505 studów od barier (było ~110). Nic w lobby nie łączy się z partami spoza niego, terenu (Terrain) przy wyspie nie ma, Rojo nie zarządza `Workspace.Lobby`. Kod czyta pozycje z placu (spawny, stragany, mgła wieży, widok po spawnie), więc w logice nic się nie zmienia — tylko komentarze z pomiarami. Napisy: kamera z mapy najbliżej ~650 od SHOP i ~700 od COSMETICS (było ~285 / ~326), `MaxDistance` bez zmian. Cofnięcie: Ctrl+Z w Studio (krok „Assistant 57”), dopóki Studio jest otwarte. Testy: TESTY → „Lobby niewidoczne z mapy — 09.11”, dwa ostatnie punkty.

## 09.11 (noc) — napisy SHOP / COSMETICS bez migania, NIEPRZETESTOWANE, Cmd+S wymagany

Kacper: napis migał przy szybkim ruchu kamery. Przyczyna: `LobbySign` chował napis za ścianami promieniem kamera → napis co 0,1 s, a promień łapał słupy i krawędzie. Na prośbę Kacpra chowanie usunięte — widoczność wyłącznie ze stałego `MaxDistance`: SHOP 275 (przez MCP, wymaga Cmd+S), COSMETICS 250. Pomiar z 09.11: chodliwe lobby sięga 269 / 223 od napisów, kamera z mapy najbliżej ~285 / ~326. Skutek uboczny: w lobby napisy widać przez budynki (`AlwaysOnTop`). Kod zgodny ze Studio i parsuje się. Test: TESTY → „Lobby niewidoczne z mapy — 09.11”, pierwszy punkt.

## 09.11 (noc) — lobby niewidoczne z mapy, NIEPRZETESTOWANE

Kacper chciał, żeby z mapy nie było widać lobby; zamiast przenoszenia wybrał chowanie lokalne. Pomiar w Edit: wyspa lobby (koło ~370 studów) wisi na wysokości dachów, ~110 studów od barier, a plac nie ma mgły, chmur ani Atmosphere — przeniesiona byłaby widoczna gdzie indziej. Nowy `LobbyVisibilityController`: kamera nad obszarem gry (pudło barier w XZ + 30 studów, powyżej Y −50) → lobby (`Workspace.Lobby` + `WizardTower`) i postacie innych dalej niż 40 studów za barierą znikają z obrazu tego gracza (`LocalTransparencyModifier`, efekty wyłączone). Kolizja zostaje, więc obserwujący stoi dalej na wyspie. Liczby w `Config.LobbyHide`. Kod w Studio zgodny z dyskiem i parsuje się; plac bez zmian (Cmd+S niepotrzebny). Testy: TESTY → „Lobby niewidoczne z mapy — 09.11”.

## 09.11 (wieczór) — bariery: hak + czerwone pole siłowe, NIEPRZETESTOWANE

Decyzje Kacpra: bariery na skraju mapy (`Map.Locked.InvisableWalls`, 4 ściany) widać tylko z bliska, wzór = ForceField. Hak: trafienie w barierę = pudło (`GrappleService.isAnchorable`, `Utils.barrierFolder`). Wygląd lokalny (`BarrierController`): czerwone pole siłowe od 40 studów, pełne od 15, przezroczystość pulsuje 0,2–0,6 co 1,6 s. Plac bez zmian (Cmd+S niepotrzebny), kod w Studio zgodny z dyskiem i parsuje się. Testy: TESTY → „Bariery na skraju mapy — 09.11”.

## 09.11 (wieczór) — szyby pushem, NIEPRZETESTOWANE

Decyzje Kacpra: F w szybę ją tłucze, pchnięty gracz wylatuje przez okno, bliższe (szyba / gracz / beczka) wygrywa, jedna tafla. `PushService` liczy promienie od HRP serwera (tułów i głowa), szybę na torze pchniętego tłucze tuż przed jego dolotem; nowe `DestructionService.shatterGlass` + `Remotes.GlassFX` (same odłamki, bez wybuchu). Kod w Studio zgodny z dyskiem i parsuje się. Pomiar w Edit: promień sięga 304 z 343 okien; przy parapecie 4 studa (większość) pchnięty rozbija szybę, ale zatrzymuje go murek — wylatuje przez niskie okna. Dźwięk szkła dalej pusty (`GlassSoundId`). Testy: TESTY → „Szyby pushem — 09.11”. Kod tylko w skryptach — Cmd+S niepotrzebny dla tej zmiany.

## 09.11 (później) — drabina zamiast mostu, NIEPRZETESTOWANE, Cmd+S wymagany

Na prośbę Kacpra item mostu (`bridge_builder`, id bez zmian ze względu na zapisy) stawia **drabinę**: pochyloną o 75°, 16 studów, z fizyką jak most — oparta o ścianę stoi, bez oparcia przewraca się do przodu, a nad przepaścią kładzie jak most (decyzje Kacpra). Wspólny wzór ustawienia `LadderPlacement` (duch + serwer): ściana przed drabiną cofa stopę, aż wierzch się oprze. Pomiar w Edit na mapie (obserwacja, nie test): pochylenie, wysokość 15,6 i strona szczebli zgodne; potem 125 ścian z całej mapy × 2 odległości stopy = 250 ustawień, tymczasowe kopie usunięte. Pierwsza wersja (1 promień) zostawiała szynę w słupach i gzymsach → 6 promieni (środek i pod szynami, wzdłuż spodu i wierzchu), do 3 cofnięć, cofnięta stopa siada na krawężniku. Wynik końcowy: **234/250 bez nachodzeń**, wierzch oparty o coś w 156, koszt 0,011 ms. Zostało 16 przy nietypowej geometrii (balkony/dachy budynków ×10, fundament ×2, niewidzialna ściana na skraju mapy ×2, latarnia ×2) — tam część drabiny nie zderza się z tym jednym elementem (NoCollisionConstraint ze spawnu), reszta działa. Modele przez MCP: `ReplicatedStorage.Ladder`, `LadderTool` (dłoń + ikona z modelu), wystawa na kołkach blueprintu; stary blueprint z wystawy w `ServerStorage.RetiredItems`. Napis SHOP widać z 300 studów (było 90). Testy: TESTY → „Drabina zamiast mostu + napis SHOP — 09.11”.

## 09.11 — detonator C4 jako podpowiedź klawisza, NIEPRZETESTOWANE, Cmd+S wymagany

Na prośbę Kacpra czerwony przycisk DETONATE zastąpiła podpowiedź sterowania: biały cieniowany klawisz „G”, obok DETONATE i żółte „x3” (decyzje Kacpra: tylko PC, trochę niżej niż wcześniej, licznik za napisem, klawisz wciska się przy G). Telefon dostał okrągły czarny DETONATE w stylu SPRINT przy skoku (wcześniej używał czerwonego przycisku, który teraz jest tylko na PC). UI postawione przez MCP w Edit, kod (`C4Controller`, `TouchControlsController.nudge`, `Config.C4`) zgodny ze Studio i parsuje się. Kacper obejrzał detonator: „no spoko”. Potem: paski odnowienia grubszy obrys 3, zaokrąglone, cieniowane, niżej (Y 0,68); **sceny sklepu i przymierzalni przeniesione pod mapę** o (−350, −300, 0) razem z 11 luźnymi partami pokoi (STUDIO_CONTRACT → „Sklep-NPC i scena”). Reszta nietestowana w Play. Po teście Kacpra dwie poprawki: (1) kamera sklepu stała w miejscu z błędem `ShopController:155` — zmiana sortowania z 07.11 usunęła środek itemu, którego używa krążenie kamery; przywrócony, sortowanie po cenie bez zmian; (2) w sklepie był filtr „pod lawą”, bo kamera była pod taflą — próg `Config.Lava.Submerged.FloorY` (−50). Testy: TESTY → „Detonator C4, paski odnowienia, sceny pod mapą — 09.11”.

## 06.11 — punkt wznowienia (dzień premiery)

**06.11 — SPECTATE:** na zlecenie Kacpra dodano obserwowanie żywych uczestników z lobby: przycisk pod SKIP, poprzedni/następny, nazwa i X; natywna kamera Custom z obrotem. Serwer publikuje RoundParticipant, klient zarządza kamerą i blokadą ruchu. Kacper jawnie pozwolił agentowi samodzielnie uruchamiać/testować Play przy tym zadaniu (wyjątek od dotychczasowej zasady) i użyć subagentów. Test solo: start, oznaczenie uczestnika, ukrycie przycisku na mapie, powrót do lobby/NO PLAYERS; kontrolowany test klienta z dwoma zastępczymi celami: 18 asercji zaliczonych, również kliknięcia Open/Next. Naprawiono oddawanie CameraSubject przy otwarciu samego katalogu kosmetyków. Pełny multiplayer i fizyczny obrót myszą/dotykiem pozostają niepotwierdzone: narzędzie ruchu myszy raportowało Delta=0 (także na zwykłej kamerze), a sterowanie oknem Studio do wielu klientów miało timeout. Build i składnia przeszły. Testowe obiekty usunięte przez zakończenie Play; UI w Edit wymaga Cmd+S. Bez publikacji i commita. Szczegóły testów: TESTY → Spectate.

**06.11 — późniejsze potwierdzenie SKIP:** Kacper: „skip już działa”. Zakres wykonanych przypadków nie został wyszczególniony, więc nie zaliczamy automatycznie całej checklisty. Dodatkowy przegląd kodu: wybór rundy, brak nagrody za przetrwanie dla pomijających, dostęp do sklepów/loadoutu, respawn i cleanup. Odczyt Studio w Edit: 14 powiązanych modułów zgodnych z dyskiem i poprawnych składniowo; `SkipButton` ma `Fill`, `Label`, `Pop`, HUD ma `ResetOnSpawn=false`. Nie uruchamiano Play; przypadki z dwoma graczami i opóźnioną siecią nie zostały w tej kontroli zweryfikowane. Poniższe wcześniejsze oznaczenia SKIP jako całkowicie nieprzetestowanego zastępuje to potwierdzenie.

**Gdzie jesteśmy:** praca 05–06.11 poszła w sklep i pomijanie rundy. Ocena Kacpra po obejrzeniu: światło „git jest”, panel „takto spoko całkiem” i „no może być”. To ocena wyglądu, nie zaliczenie listy z TESTY. Logika pomijania rundy i pełna runda po dzisiejszych zmianach nie mają wyniku testu.

**Git:** kod i dokumentacja z 05–06.11 są w commicie po `f166687` na `main`, wypchniętym na `origin/main` na prośbę Kacpra, przed jego testem w Play, więc commit nie oznacza działania. Plac zapisuje się osobno przez Cmd+S. Kolejne commity tylko na prośbę, pliki dodawać jawnie.

**Plac:** odczyt 06.11 po restarcie Studio potwierdził zapis: arsenał, brak `ShopLights` i pyłu, `Panel.LavaPool`, `Panel.Dots`, `BuyButton.Sweep`, `RoundTimer.SkipButton`. Mini ramka `SkipButton.Fill` powstała po tym odczycie, więc jej Cmd+S jest niepotwierdzony. Kod w Studio zgodny z dyskiem (suma i parsowanie, ostatnio dla `Config` i `RoundSkipController`).

**Kolejność do premiery:**
1. Kacper: Cmd+S i test w Play: zwykła runda, SKIP z dwoma graczami, sklep, animacja F, kliknięcia po zmianie itemu (hak → napój, napój → RPG). Listy w [TESTY](TESTY.md).
2. Poprawki ze zgłoszeń, commit i push na prośbę.
3. Ustawienia produkcyjne i usunięcie tymczasowych logów: [DO_RELEASE](DO_RELEASE.md) → „Tuż przed publikacją”.
4. Test z kilkoma osobami na prawdziwym serwerze, także telefony.
5. Publikacja po akceptacji Kacpra.

Otwarte poza tą listą: dźwięki (ID poda Kacper), anty-cheat paczka 6 (niezrobiona; agent radził po premierze, decyzja Kacpra otwarta), limit graczy w ustawieniach miejsca.

**06.11 — pomijanie rundy, NIEPRZETESTOWANE, Cmd+S wymagany:** mini ramka SKIP pod licznikiem, po kliknięciu czerwone DON'T SKIP (decyzja Kacpra: przycisk zamiast pola startu, przełącznik do odkliknięcia). Pomijający stoi w lobby, nie zarabia, sklep, ekwipunek i kosmetyki działają mu przez całą rundę; gdy pomijają wszyscy, lobby odlicza od nowa. Opis: ARCHITECTURE → `RoundSkipService`; testy: TESTY → „Pomijanie rundy” (runda z pomijającym wymaga dwóch graczy).

**05.11 — tło sklepu: arsenał, NIEPRZETESTOWANE, Cmd+S wymagany:** brązowe listwy i ladę (`Decorations.Workshop`) zastąpił wojskowy magazyn `WeaponShopScene.Arsenal` (oliwkowe panele ze studsami, stalowe słupy, tablice za itemami, stalowa lada ze skrzyniami), decyzje Kacpra w jednej turze. Itemy nieruszone (pozycje sprawdzone odczytem), każdy dostał uchwyt, żeby nie lewitował. Zrzuty z Edit obejrzane, w grze jeszcze nie. **06.11 światło:** stare `ShopLights` usunięte, kontrast robią lampki nad itemami: tablica i item jasne, reszta ściany ciemna; słabe oświetlenie z góry trzyma widoczną podłogę, `Config.Shop.SceneAmbient` neutralne zamiast brązowego. Blat lady ciemna stal. **06.11 panel, NIEPRZETESTOWANE:** nowy `ShopFx`: wjazd panelu, reakcje przycisków, przejście przy zmianie itemu, efekt zakupu i błędu, wibracje, połysk BUY, 6 małych kropek nad ramką, płynący pas lawy na dole panelu; kamera lekko krąży za myszą. Dźwięki przygotowane, ale puste: ID poda Kacper (`Config.Shop.Fx.Feedback`). Opis: STUDIO_CONTRACT → „WeaponShopScene”; testy: TESTY → „arsenał”.

## TEST 31.10 — punkt wznowienia

Sesja testowa Kacpra: 4 rundy w Play, logi bez błędów naszego kodu (szum toolboxowego ragdolla, przestarzałych collision groups i asset `203785492` spoza placu — do zignorowania). **git:** kod z 31.10 w `8bcbb6f`, zmiany 01–03.11 w commicie po nim, wszystko na `main` i wypchnięte na `origin/main`; to podsumowanie dokumentacji — osobno, po nim.

**Sprawdzone przez Kacpra w Play:**
- **Zawalone piętra lecą dużymi bryłami** („spoko”). Przyczyna znikania: pass kikutów (`StructuralService.unsupportedStrips`) liczył chunk `Falling` jako martwy, więc kruszenie tuż po planie oddawało klientom całe górne piętra jako drobnicę, zanim ich grupa wystartowała (log: 25 grup `bez kawałków`). Teraz chunk `Falling` należy do swojej grupy. Po poprawce kolaps GreenBuilding: grupy po 14–21 kawałków; ~15 z 24 grup idzie ponad budżet (`MaxCost` 100) do klientów — budżetu nie ruszano.
- **Leżący gruz tnie się od RPG** („lepiej to wygląda”): osobny próg `Config.Structure.Damage.RubbleHoleThreshold` = 70 (RPG tnie z ~7 studów, dziura 2× szersza; C4 ~13). Wcześniej próg ściany 100 → RPG tylko budził bryłę. Przestrzelona bryła dzieli się na osobne (`CollapseService.splitApart`; decyzja „obie połówki odskakują”).
- **F nie pcha z RPG** („rpg git”). Potem decyzja: **F (pchnięcie i beczka) tylko z pustymi rękami** — `Config.Push.BlockWithToolInHand`, klient + serwer, PUSH na telefonie znika. Wersja „każdy item” jeszcze niesprawdzona.
- **Róg murku**: kolizja HRP przywrócona poza ragdollem i śmiercią (`MovementController.syncRootCollision`, tylko klient; toolbox ragdolla wyłączał ją w ragdollserver:245). Test A/B komendą: „git lepie”; wersja w kodzie niesprawdzona.

**Wdrożone, niesprawdzone:** więcej małego gruzu zostaje (`KeepSmallRubbleChance` 0,25 → 0,67).

**Otwarte:** napój — „klik pić → od razu inny item = nie wypije”. Serwer zalicza łyk przy kliknięciu, zwykły łyk działa (0,03 s), przyczyna nieustalona. Tymczasowe logi `[EnergyDrink] klik: …`, `puszka w ręce/schowana` i odmowy łyku na serwerze — usunąć po rozstrzygnięciu.

**02.11 po teście Kacpra — kliknięcia itemów, NIEPRZETESTOWANE:** `Utils.holdTool` (niżej) NIE pomogło: log 02.11 — hak → napój: `puszka w ręce` → zero linii `[EnergyDrink] klik` → `schowana` (2 z 2 razy). Ten sam błąd silnika zmierzono już 25.10 przy C4 (RPG → C4: klik dochodzi do świata, Tool w ręce, `Tool.Activated` nie przychodzi aż do ponownego wyciągnięcia) — C4 dostał wtedy obejście, reszta itemów nie. Poprawka: `ToolActivation` czyta klik na PC wprost z myszy (LPM / R2) dla WSZYSTKICH itemów, Activated zostaje dla dotyku, jeden klik = jedno użycie (dedup 0,1 s). Telefon bez tego obejścia — do sprawdzenia. Zsynchronizowane i parsuje się (odczyt Edit). `holdTool` zostaje jako porządek (nigdy dwa itemy w ręce). Tymczasowe logi `[Rpg] klik` / `[EnergyDrink] klik` — usunąć po teście.

**02.11 — hak zawsze strzela, NIEPRZETESTOWANE:** zgłoszenie „ktoś może klikać i nie wie o co chodzi”. Teraz klik poza zasięgiem, w niebo albo w coś nie do złapania = pudło: lina wylatuje jak najdalej (do 70 studów albo do przeszkody) i szybko się zwija, u wszystkich graczy (`Remotes.GrappleMiss`). Decyzje Kacpra: pudło nie zabiera sztuki, postać stoi. Klik w budynek dalej niż 70 zaczepia o to, co stoi na tej linii w zasięgu. Pasek odnowienia także po pudle. Zsynchronizowane i parsuje się (odczyt Edit).

**Wdrożone 02.11 (porządek, nie przyczyna):** RPG — „napiję się energy drinka i od razu RPG = nie strzela”. Log z Play 01.11 22:48: `[Rpg] … wyrzutnia w ręce` (serwer, 25.516) → `puszka schowana` (klient, 25.550) → **zero linii `[Rpg] klik`**, czyli `Tool.Activated` wyrzutni w ogóle nie odpala (to nie odmowa klienta ani serwera; winieta napoju i `Speedlines` mają `Active=false`, nie łapią kliknięć — sprawdzone w Edit 02.11). Przyczyna (hipoteza, niesprawdzona w Play): przy zmianie itemu serwer mógł dać nowy Tool, ZANIM serwis starego go zabrał (każdy serwis ma własny handler `EquipItem`, kolejność nie jest gwarantowana) → przez chwilę dwa Toole w postaci. Poprawka (decyzja Kacpra 02.11): **`Utils.holdTool`** — jedno miejsce, które przed podaniem itemu niszczy każdy inny Tool itemu w postaci; wszystkie 6 serwisów itemów woła je zamiast `tool.Parent = char` (w `C4Service` jedna linia). Po Disconnect → Connect w Rojo (wtyczka wcześniej nie nakładała zmian) wszystkie 7 plików zgodne z dyskiem (suma) i parsują się (odczyt Edit 02.11). Tymczasowe logi `[Rpg] klik: …`, `wyrzutnia w ręce` i odmowy strzału na serwerze (`RpgController`, `RpgService`) — usunąć po teście. Testy: [TESTY](TESTY.md) → „Napój → od razu RPG” i „Szybkie przełączanie”.

**Logi zostające (Debug):** `[Destr] … rumowisko cięte=X/Y (najbliżej D)` i strażnik `[Collapse] … bez kawałków — pomijam` (w rundach 3–4 zero takich linii).

Następny test: [TESTY](TESTY.md) → „31.10” (napój, F z każdym itemem, róg murku bez komendy, regresje ragdoll/drabina/hak/most).

**03.11 — napisy SHOP / COSMETICS, NIEPRZETESTOWANE, Cmd+S wymagany:** COSMETICS ma rozmiar SHOP i kolory przycisku COSMETICS z HUD (fiolet/niebieski, płynący gradient). Oba napisy znikają za ścianami — kod (`LobbySign`, promień kamera → napis), bo samo `AlwaysOnTop = false` dawało dach straganu obcinający litery (pomiar w Edit). Kod SHOP przeniesiony do tego samego pomocnika. 4 pliki zsynchronizowane i parsują się; bez zrzutu. Testy: [TESTY](TESTY.md) → „Napisy SHOP i COSMETICS”.

**03.11 — ekran ładowania i lina haka, NIEPRZETESTOWANE:** „ESCAPE LAVA” przestaje przeskakiwać — przyczyna zmierzona w Edit: Roblox rysuje tekst tylko w całych rozmiarach fontu (przy +2,5% szerokość 624 → 626 → 636 px), a korekta pozycji szła w całych pikselach, więc „oddychanie” skalą było widać jako skoki. Napis już nie rośnie, buja się jak dotąd; oddycha jasność obrysu. Obrys = płynąca lawa (UIGradient na klonie obrysu, kolory z szumu; najgorętszy (205, 45, 0) ciemniejszy od „LAVA”). Lina haka 0,12 → 0,2 (`Config.Grapple.RopeThickness`). Zsynchronizowane i parsuje się (odczyt Edit); bez zrzutu. Testy: [TESTY](TESTY.md) → „Tytuł ekranu ładowania”.

## WIEŻA MAGA — poprawki 02.11 (MCP, Cmd+S wymagany, bez zrzutów)

`Workspace.WizardTower`: 4 luźne świece z `Interior.Hall` wisiały 12–13 studów nad podłogą w studni schodów → przeniesione na stopnie pod nimi (r 5,9 od osi, przy wewnętrznej poręczy), każda na podstawku `CandleDish`. Waga na `Interior.WizardRoom.Counter` przebudowana na szalkową (20 części `Scale*`, belka przechylona 8°, odważnik na niższej szalce), 3 butelki przesunięte o 0,5 wzdłuż blatu; stara waga w `ServerStorage.WizardScale_Backup_0211`. Żyrandol `Interior.Hall.Chandelier` (= „lampa na schodach bez zaczepienia”, potwierdzone przez Kacpra i zrzutem): **prawdziwa przyczyna — błąd generatora wieży: walce z długością w osi Z** (`Cylinder` w Robloxie ma długość tylko w osi X, średnica = min(Y, Z)), więc druty piasta→pierścień rysowały się jako krążki 0,15 i pierścień wisiał w powietrzu. Druty przestawione na pręty (długość w X, gr. 0,2), 8 zamiast 4; fioletowa kula `Orb` podwieszona na pręcie `OrbRod` z nakładką `OrbCap`; łańcuch 0,35 z kołnierzem `ChainCollar` pod guzem `Floors.HallCeiling.Boss`, piasta 0,95. Ten sam błąd miały 32 płaskie części biurka i szyldu (okładka i strony książki, bieżnik, pióro, emblematy, gwiazdki, szyjki kolb) — zmienione na `Block`, wymiary bez zmian; po poprawce 0 takich walców w `WizardTower`. ⚠️ Przy kolejnych modelach z generatora sprawdzać `Cylinder` z Y ≠ Z.

**02.11 wieczorem — wieża na wzniesieniu (Kacper przeniósł ją sam):** kamienna ścieżka od podnóża do drzwi (dwa biegi schodów, podest, murki, 8 fioletowych latarenek), lekka mgła z cząsteczek wokół wieży i wzdłuż schodów, a w kodzie `TowerAmbienceController` — obraz lekko ciemnieje i chłodnieje tylko w promieniu ~40–75 studów od wieży (u gracza, płynnie). Opis w STUDIO_CONTRACT („Wieża maga — otoczenie”) i ARCHITECTURE. Zrzuty z Edit obejrzane (schody, latarnie po przygaszeniu, mgła po ręcznym `Emit`). Kod na dysku; sesja Play Kacpra z 02.11 wystartowała PRZED synchronizacją (na serwerze brak modułu) — przyciemnienie sprawdzić w nowym Play. Cmd+S wymagany.

**03.11 — poprawki Kacpra:** schody szersze (8) i nieregularne (kamienie o różnej wysokości/wysunięciu/skręcie, poszarpane brzegi, murki różnej wysokości z czapami, głazy), mgła ~2× gęstsza, a przy wieży u gracza ciemnieje też niebo (ekspozycja −0,55 + lokalna Atmosphere, usuwana po odejściu). Wartości atmosfery dobrane na podglądzie w Edit (pełna siła: ciemne fioletowe niebo, wieża czytelna); podgląd zdjęty, Lighting placu przywrócony (Exposure 0, brak Atmosphere). 3 pliki zsynchronizowane i parsują się. Play nietestowany, Cmd+S wymagany. **Potem 03.11 („słońce dalej razi”):** przy wieży tarcza słońca maleje do 0 i gaśnie `SunRays` (podgląd w Edit: ciemne fioletowe niebo bez tarczy i blasku; Lighting placu przywrócony — Exposure 0, SunAngularSize 21, SunRays 0,2, brak Atmosphere). Wszystkie lampy wieży dotykają czegoś poza sobą (odczyt).

## TELEFON — punkt wznowienia 28.10.2026 (premiera 6.11)

**02.11 — loadout palcem, NIEPRZETESTOWANE:** zgłoszenie „przeciągam item na slota, klinuje się i zostaje tam”; log Play bez błędu z `InventoryController`, czyli koniec dotyku nie dochodził przez `UserInputService.InputEnded` (podejrzenie: karty leżą w przewijanym `Card.Shelf.Grid`, które przejmuje dotyk). Poprawka: koniec dotyku łapany też ze stanu samego obiektu dotyku (End/Cancel), drugi palec nie podmienia przeciągania, lista nie przewija się pod przeciąganą kartą. Plik w Studio zgodny z dyskiem (suma) i parsuje się (odczyt Edit 02.11). Testy: [TESTY](TESTY.md) → „Telefon” → „Loadout palcem”.

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

Lobby **25 s**, w nim ramka SKIP pod licznikiem (06.11): kto ją kliknie, zostaje w lobby na kolejne rundy; przygotowanie i teleport pod zasłoną; **3-2-1** na mapie z blokadą ruchu/itemów; runda z płynnie przyspieszającą lawą, **bez faz**; **3 s FINISHING**, wypłata ocalałym, zasłona i cleanup/odbudowa, potem **od razu lobby** (10 s „ROUND OVER” w lobby usunięte 26.10). Produkcyjny cel rundy: **80 s**, obecnie **240 s testowo**.

Kod zawiera **7 itemów**: Bomb 50$, Bridge 100$, Grapple 40$, Energy Drink 25$, RPG 75$, **Bandage 40$**, **C4 60$** (25.10 — C4 = zaplanowana sticky bomb, decyzja Kacpra; przyklejanie, G i rzut z ikoną zadziałały w testach; 25.10 wieczorem wysoki łuk jak granat + zamach ręki — NIEPRZETESTOWANE; `ReplicatedStorage.C4` i `HUD.Detonator.DetonateButton` postawione przez MCP). Loadout to **3 stałe sloty**, ekwipunek jest dostępny wyłącznie w lobby, a pomijającemu rundę także w jej trakcie. Nowy item nie wymaga czwartego slotu.

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
- Nowy panel sklepu i automatyczne kadry; **23.10** wydłużona ściana/pokój, przesunięta wystawa, kąt kamery yaw 20° / pitch 12°, następnie ruchomą lampę zastąpiły stałe `ShopLights` (po jednej nad sześcioma modelami plus doświetlenie skrajów; 06.11 usunięte na rzecz lampek arsenału). Najnowszy kod przy zamknięciu sklepu po respawnie przypina kamerę do aktualnego Humanoida; test pozostaje otwarty. **25.10** panel `ShopUI` przebudowany przez MCP (węższy, ciemne strzałki przy panelu, cena nad BUY, bez kasy w nagłówku) — zrzut z Edit pokazany, ocena Kacpra i zapis Cmd+S niepotwierdzone; kopia starej wersji w `ServerStorage.ShopUI_Backup_2510`.
- **Panel ustawień (26.10)**: zębatka pod INVENTORY (zawsze widoczna) otwiera panel SETTINGS z dwiema opcjami — kamera nad prawym/lewym ramieniem i włącz/wyłącz przechył kamery + zmiany FOV; zapis na koncie gracza (`SettingsService`). Zębatka i panel postawione przez MCP (zapis Cmd+S niepotwierdzony), kod zsynchronizowany i parsuje się (odczyt Edit); w Play nietestowane. Oprawa lawy wstrzymana na rzecz panelu — decyzje w ROADMAP.
- **GRAPHICS LOW / HIGH + oprawa lawy (27.10)**: trzeci wiersz panelu ustawień (postawiony przez MCP, Cmd+S niepotwierdzony); start: telefon LOW, komputer HIGH. Na HIGH: łuna na ścianach tuż nad lawą, iskry i popiół rosnące z lawą, rozbryzg przy wpadnięciu (`LavaSplashController`). Tylko u klienta, bez kolizji. Kod zsynchronizowany i parsuje się (odczyt Edit); w Play nietestowane. Plan: ROADMAP.
- Oprawa lawy: fala lokalnej siatki i FX v5; zachowanie na urządzeniach i FPS nadal do sprawdzenia. Odczyt działania siatki w sesji 12.10 nie jest akceptacją wyglądu/FPS.

## Braki potwierdzone w kodzie / placu

- **Telefon:** 28.10 przyciski SPRINT/PUSH/BUILD/ROTATE/AIM/FIRE wdrożone (sekcja TELEFON na górze) — czekają na test Play na emulatorze i prawdziwym telefonie.
- **Anty-cheat:** obecny pomiar poziomy co 2 s, limit sprint +8, kara po 3 przekroczeniach. Pojedynczy teleport i lot w pionie nie są pokryte. Plan paczki 6 ma zamknięte decyzje: cofnięcie → powtarzane naruszenia: kill → kick, pion po ~1 s; potrzebuje wyjątków dla legalnej fizyki.
- **Skala:** spawn postaci nadal sekwencyjny; HeadAim od 02.11 tylko do graczy w promieniu 150 studów (kod, nietestowane — TESTY → „Ruch głowy”); bootstrap serwera bez izolacji błędów `init`. Odbudowa tylko naruszonych jednostek już istnieje, jej koszt wymaga testu.
- **Spawny rundy (02.11):** `Map.Locked.SpawnPoints` ma 6 punktów na chodnikach wokół basenów lawy (4 stare ze środka usunięte), lobby — 4 punkty w `Lobby.SpawnPoints` losowane przy każdym powrocie (nowy kod `PlayerService`; MCP, Cmd+S wymagany; szczegóły w STUDIO_CONTRACT). ⚠️ 02.11 wieczorem `rojo serve` nie działał — kod lobby i HeadAim był tylko na dysku. Przy więcej graczy niż punktów kilku dostaje ten sam punkt. Docelową liczbę graczy trzeba ustalić przed testem większej grupy. `Config.Game.MaxPlayers = 20` nie ustawia limitu miejsca Roblox; limit publikowanego serwera pozostaje do sprawdzenia.
- **Studio 23.10:** brak zapisanych modułów w `ServerStorage.StructureData` (0 dzieci/brak folderu); analiza budynków nadal wykonywana w grze. Przed bake sprawdzić zaokrąglenia i walidację rewizji.
- **Animacja F:** 05.11 opublikowana na koncie właściciela gry (`Config.Push.AnimationId = 128117097694041`, moderacja Approved), podgląd Studio wyłączony. Odtwarzanie w Play NIEPRZETESTOWANE; sama mechanika pchnięcia jest osobna.
- **Audio:** 5 pustych ID destrukcji, brak dźwięku strzału RPG, 4 puste ID panelu sklepu (`Config.Shop.Fx.Feedback`, ID poda Kacper); łyk opcjonalny.
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

Do premiery obowiązuje krótka kolejność z sekcji 06.11 na górze. Poniżej pełna lista.

1. Test Kacpra z TESTY, w tym T1–T7 dwukrotnie; naprawy tylko na podstawie konkretnych zgłoszeń i aktualnego logu.
2. Telefon, anty-cheat i przygotowanie większego serwera; test zapisu/obciążenia na rzeczywistym serwerze.
3. Test łuku i zamachu C4, postawy i zoomu RPG oraz animacji F, poprawka haka, audio i bake.
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


## 06.11 — Bandage: implementacja i test Play

Dodany siódmy item: biały zwój z czerwonym krzyżem, wystawa w sklepie, kafelek Inventory i ikona hotbara renderowana z modelu. Cena 40$, leczenie +35 HP po 3 s (maksymalnie MaxHealth). Loadout nadal ma 3 sloty. Gest bandażowania i pasek BANDAGING; można chodzić. Zmiana itemu, ragdoll, śmierć lub koniec rundy przerywają bez zużycia. Serwer rozlicza leczenie i sztukę; klient wyłącznie pokazuje animację.

Za zgodą Kacpra agent wykonał solo Play: 15 asercji integracyjnych zaliczonych na prawdziwych remotes i działających usługach, w tym spam, limit HP i anulowanie. Dane ekwipunku/loadoutu przywrócone przez fixture. Szczegóły i pozostałe testy: TESTY. Nowa poza rąk wymaga jeszcze wizualnej akceptacji w ruchu; test wieloosobowy i telefon pozostają otwarte. Studio wróciło do Edit. Model, wystawa i szablon paska wymagają Cmd+S; bez publikacji i commita.
