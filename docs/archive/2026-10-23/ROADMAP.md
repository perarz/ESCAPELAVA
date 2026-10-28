> ARCHIWUM sprzed audytu 23.10.2026. To zapis historyczny, nie bieżące instrukcje ani lista zadań. Aktualne dokumenty są dwa poziomy wyżej.

# ROADMAPA — co gotowe, co dalej, plany i decyzje designowe

> Wydzielone z CLAUDE.md 2026-09-23. Aktualny STATUS i następne kroki są w **CLAUDE.md**.
> Czytaj przed planowaniem nowej ficzury: itemy, loadout, skiny, system wyglądu i pancerzy, balans rundy. Są tu też długie rozdziały badań (rig na Motor6D, „śliski movement”, losowy wygląd) — decyzje na przyszłość wynikają z tego, co już sprawdzono i odrzucono.

## Co jest GOTOWE
- ✅ Day 1: GameLoop + Lava + HUD + lobby/round flow. Lava CanCollide=false.
- ✅ Day 3: DataStore (cash/inventory/wins persist) + **Leaderstats** (Cash + Wins w Tab).
- ✅ Day 4: sklep + Hotbar + **bomba** (throw, VFX lontu, damage falloff, knockback, ragdoll toolbox ARTFVL, auto-re-equip — **bez wybuchu**, patrz ⚠️ wyżej) + **most** (bridge_builder, ghost preview).
- ✅ **Map restore** — MapService snapshot+restore po każdej rundzie.
- ✅ **PvP push** — F key, server-side target, velocity przez Pushed.
- ✅ **Cash pickupy** — cash na mapie, magnet pickup, pickup arc animacja.
- ✅ **Kill/Win rewards** — KillService (kill 25$ z tagowaniem) + RewardsService (survival 100$) + killfeed + win banner.
- ✅ **Movement system** — sprint+stamina, 3rd person, dynamic FOV, smooth camera, landing dip, screen shake, **head tracking** (✅ od 23.09 — wcześniej nie działał nigdy, choć figurował tu jako gotowy), **kamera zza ramienia** (✅ 23.09, prawe ramię, staje na ścianach).
- ✅ **Anti-cheat** — detekcja po realnie przebytej drodze (WalkSpeed cap był atrapą, patrz AntiCheatService).
- ✅ **CooldownBar UI**.
- ✅ **Sklep-NPC** (2026-09-12) — podejście do sprzedawcy, kamera jadąca po wystawie, dolny panel z ceną/opisem, zakup walidowany dystansem. **Przetestowany w Play.**
- ✅ **Hak** (2026-09-22/23) — trzeci item: celujesz, trafiasz, lecisz po łuku do punktu, lądujesz trochę nad nim. **Przetestowany przez Kacpra w Play** (odczucie lotu 22.09, przypadki brzegowe 23.09). ⚠️ Nie widać go w pasku, dopóki nie powstanie `Slot3`.
- ✅ **Pasek staminy 3D** (2026-09-12) — BillboardGui obok postaci, tylko przy sprincie/regeneracji, elastic pop, kolor HSV niebieski→żółty→czerwony. **Przetestowany w Play.**
- ✅ **Audyt serwera** (2026-08-11) — naprawione: session lock przy loadzie (utrata postępu przy server hopie), `ItemService` meldujący fałszywy sukces, pominięcie `RoundEnded` przy błędzie rundy, dwa listenery `Touched` na lawie, bandwidth head-trackingu, spawn rundy bez izolacji błędu, jitter auto-save, `Locked` na mostach, kłamliwy log "saved".

## Co JESZCZE TODO
- 🧨 **SYSTEM DESTRUKCJI — CAŁY DO NAPRAWY (decyzja Kacpra 2026-09-23).** Po teście na telefonach z kolegami (lagi przy 4 bombach, przenikanie przez podłogę, znikające wieszaki) tego samego wieczoru powstała **v3** (`docs/DESTRUCTION_PLAN.md` → „v3”: serwer trzyma stan gry, drobny gruz i meble animuje klient bez kolizji, tryby grafiki Ziemniak/Pełny) — **nieprzetestowana w Play**. Kacper zapowiedział, że naprawy wymaga CAŁA destrukcja: start od jego listy usterek + testu v3, potem plan. Znane otwarte punkty: STATUS w CLAUDE.md (🧨).
- ⏳ (historia) **SYSTEM DESTRUKCJI v2 — WSZYSTKIE 5 ETAPÓW ZAIMPLEMENTOWANE** (`docs/DESTRUCTION_PLAN.md`), etapy 2-5 **CZEKAJĄ NA TEST W PLAY**. ① rdzeń (przetestowany OK) → ② kategorie + occlusion + pass podparcia v2 (kolumna, kierunkowy — fix na "wysadziłem dół i reszta wisi") → ③ fall-fracture + crush damage → ④ kolaps sekcji po filarach + creak → ⑤ 5 slotów audio + throttle dźwięków (ślady opalenia ZROBIONE I SKASOWANE 2026-08-12 — raycast w dół kładł plamę kilkadziesiąt studów pod wybuchem w powietrzu; nie wracać bez pomysłu na wybuchy nie przy ziemi). **Zostaje: assety dźwiękowe Kacpra** (5 pól w `Config.Destruction.FX`, wpięcie gotowe) **i balans po testach pod obciążeniem**. Kontrakt mapy: panele zamiast kafli 6×6, tag `Pillar` na filary, szyby Material Glass, budynek = folder, wiszące platformy → `Locked`/`Map.Locked`.
- 🧩 **WIZJA KACPRA NA DALSZY CIĄG (ustalona 2026-09-12, jeszcze NIE zaimplementowana):**
  - **Loadout: hotbar 3 sloty + ekwipunek** — gracz posiada dowolnie dużo typów itemów, ale **equipuje maks 3 z docelowych 6**. Cel: wymusić wybór (mobilność vs ofensywa vs utility) zamiast brania samej mobilności; C(6,3)=20 kombinacji. Wymaga: nowego pola w danych gracza (wybrany loadout), UI ekwipunku, zmiany `HotbarController` (dziś pokazuje pierwsze N posiadanych typów). ➜ **PLAN GOTOWY 30.09 — „PLAN: LOADOUT” na końcu tego pliku** (czeka na decyzję: gdzie mieszka wybór).
  - **Drugie stoisko — SKINY** (osobny NPC): wchodzisz, kamera przesuwa się na Twoją postać w "przebieralni", przewijasz skiny, na dole KUP. ⚠️ To NIE jest "drugi sklep" tylko **nowy system**: posiadanie skinów w DataStore + zakładanie na postać przy respawnie + assety Kacpra. Robić DOPIERO po loadoucie.
  - **Daily Rewards od nowa jako UI** (stare skasowane — patrz STATUS).
  - **Docelowo 6 itemów — WYBRANE (odczytane z wystawy w Studio 2026-09-22): bomba, most, hak ✅, RPG, sticky bomb, energy drink.** Zostają RPG, sticky bomb i energy drink. Lista propozycji z 2026-09-16 poniżej zostaje jako zapas. Pełna dziesiątka: **hak** (przyciąga do ściany/dachu), **lotnia** (szybowanie — kontra na push i knockback), **trampolina** (stawiana, działa też dla wrogów), **mina proximity**, **sticky bomb z detonatorem** (klei się też do gracza), **kontrolowana rozbiórka** (ładunek na filar → `StructureService` zrzuca piętro; najmocniejszy moment na TikToka), **stawiana ściana** (jedyny item wprost grający z istniejącym occlusion ×0.45), **zastygacz** (chwilowa skorupa na lawie = wyspa ratunkowa), **granat grawitacyjny** (wciąga; kill liczy się przez 5-sekundowe okno `KillService`), **zamiana miejsc** (teleport-swap z wrogiem — przewaga pozycyjna zamiast obrażeniowej).
    **Rekomendacja Claude'a do szóstki**: bomb + bridge_builder + **hak, lotnia, stawiana ściana, kontrolowana rozbiórka**.
    ⚠️ **Filtr przy wyborze**: uważać na itemy nagradzające KEMPING na szczycie (mina, ściana). Przy obecnych liczbach lawa kończy rundę ~2.75 studa pod najwyższym dachem, więc szczyt jest bezpieczny — te itemy by go jeszcze wzmocniły. Jeśli `Endgame` pójdzie z 3.0 na ~3.2 i lawa zaleje wszystko, problem znika.
  - 🧍 **JEDNOLITY RIG + LOSOWY WYGLĄD STARTOWY (ustalone 2026-09-20 wieczorem, DO ZROBIENIA JUTRO).**
    Kacper: „chcę, żeby każdy miał R15 i zaczynał z tym samym rigiem, ale każdemu losuje
    losową koszulkę, spodnie, fryzurę i twarz".
    - ⛔ **`LoadCharacterWithHumanoidDescription` SPRAWDZONE I ODRZUCONE (2026-09-21) —
      NIE WRACAĆ.** Pierwsza wersja `AppearanceService` tak działała; Kacper przetestował
      w Play i zgłosił TRZY objawy naraz: **wrócił ślizg przy chodzeniu, animacje „lekko
      inne", twarz zbugowana**. Przyczyna jest jedna: **opis buduje postać WYŁĄCZNIE
      z siebie**, więc puste pole animacji nie znaczy „zostaw graczowi jego", tylko „użyj
      domyślnej" — a domyślne animacje Robloxa są strojone pod `WalkSpeed` 16, my mamy 12.
      Twarz psuła się z tego samego źródła: opis bez pola `Face` nie tworzy dekala `face`,
      więc kod robił własny, a świeży `Decal` na meshu głowy mapuje się inaczej niż ten,
      który Roblox zakłada sam. ⚠️ **Pilnowanie samych PÓL animacji (reguła z 2026-09-20)
      było ZA SŁABE — problemem jest sama metoda, nie jej pola.**
    - ✅ **Mechanizm docelowy**: zwykły `player:LoadCharacter()` (gracz zachowuje swoje
      animacje) + przeróbka postaci po spawnie: zdjęcie `Shirt`/`Pants`/`ShirtGraphic`/
      `Accessory`/`BodyColors` gracza → pomalowanie 15 części R15 → podmiana **tekstury
      istniejącego** dekala `face`. Mniej kodu niż wersja z opisem.
    - ⛔ **WYRÓWNYWANIE SKAL POSTACI TEŻ SPRAWDZONE I ODRZUCONE (2026-09-21).** Druga wersja
      ustawiała `BodyHeightScale`/`BodyTypeScale`/… na jednolite wartości przez NumberValue
      w Humanoidzie. Kacper przetestował: **ślizg zrobił się JESZCZE WIĘKSZY** niż przy
      wersji z opisem (twarz przy tym już działała). Mechanizm: zmiana proporcji zmienia
      długość nóg, a długość kroku w animacji zostaje ta sama — stopy przestają nadążać
      za podłożem. **Koszt rezygnacji, świadomy**: gracze z różną skalą avatara mają
      minimalnie różny dystans HRP→stopy, czyli nieco inny próg śmierci w lawie i liczenia
      upadku (`FEET_OFFSET` / `HRP_TO_FEET` = 2.5) — różnica rzędu ułamka studa, nie warta
      psucia odczucia ruchu. Gdyby kiedyś zaczęła przeszkadzać, właściwym miejscem są
      **zakresy skal w Game Settings → Avatar**, a nie przeskalowywanie postaci z kodu.
    - 📏 **ŚLIZG PRZY CHODZENIU — ZMIERZONY W PLAY 2026-09-21, TO NIE JEST BUG NASZEGO KODU.**
      Kacper zgłaszał go trzy razy z rzędu jako „coraz większy" po kolejnych moich zmianach,
      więc przy jego zgodzie na testy zmierzyłem to zamiast dalej zgadywać. **Miara**:
      prędkość stopy PODPOROWEJ względem świata (idealnie 0; średnia z 30% najwolniejszych
      próbek w cyklu kroku).
      **Wyniki — ślizg trzyma się 7% ruchu NIEZALEŻNIE OD WSZYSTKIEGO:**
      | warunek | ślizg |
      |---|---|
      | WalkSpeed 12 (nasz) | 0.81 stud/s = 7% |
      | WalkSpeed 14 / 16 / 18 (wymuszone) | 1.10 / 1.39 / 1.49 = 8% / 9% / 8% |
      | skala wzrostu avatara 1.072 vs 1.0 | 0.73 vs 0.78 = 6% vs 7% |
      | z przeróbką wyglądu | 0.77 = 7% |
      **Co to wyklucza**: (a) `WalkSpeed` 12 — przy 16 jest procentowo GORZEJ, więc
      podnoszenie prędkości NIC nie da; (b) skalę postaci; (c) `MovementController`
      (ustawia stabilne 12, snap przy różnicy <0.05, nie oscyluje); (d) całą przeróbkę
      wyglądu — kolory, zdjęcie ubrań i tekstura twarzy nie mają jak wpłynąć na fizykę.
      ⚠️ **Korekta tempa animacji POGARSZA sprawę**: wymuszenie `AdjustSpeed(12/16 = 0.75)`
      na `WalkAnim`/`RunAnim` podniosło ślizg z 1.22 na 2.81 stud/s. Powód: R15 miesza
      `walk` i `run` WAGAMI (przy 12 wychodzi ~71% run / 29% walk), a ten blend już
      odpowiada realnej prędkości — spowalnianie go rozjeżdża. **Nie wracać do tego pomysłu.**
      **Wniosek**: ~7% to baseline Robloxa dla R15. Najprawdopodobniej ślizg był w grze
      od zawsze, a przeróbka wyglądu go **UWIDOCZNIŁA** — jednolity kolor nóg pokazuje ruch
      stóp o wiele wyraźniej niż wzorzyste spodnie z avatara gracza. Do potwierdzenia przez
      porównanie obok siebie.
      ⚠️ **ALE TO NIE BYŁO TO, O CO CHODZIŁO KACPROWI.** Doprecyzował: „movement nie sharp,
      taki śliski" — czyli nie ruch stóp w animacji, tylko **responsywność sterowania**.
      To zupełnie inne zjawisko i miało inną, realną przyczynę — patrz niżej. **Lekcja:
      zanim zacznę mierzyć, upewnić się, że mierzę to, co człowiek faktycznie widzi.**
      Trzy zmiany i cztery pomiary poszły w rzecz, która nie była problemem.

- 🦴 **NOWY RIG R15 (bez `Motor6D`) — ŹRÓDŁO TRZEPANIA RAGDOLLA I MARTWEGO HEAD TRACKINGU (2026-09-21).**
  Kacper trafił w to intuicyjnie („wina tego, że jest wymuszony R15 i mam inne animacje niż
  default"); pomiar na jego postaci potwierdził:
  ```
  Motor6D = 1  |  AnimationConstraint = 15  |  BallSocketConstraint = 24
  ```
  Ten jedyny `Motor6D` to **altrootmotor dokładany przez sam toolbox** — rig nie ma ani
  jednego własnego. Na ciele działają więc **DWA zestawy stawów naraz**: 14 `BallSocket`
  rigu (limity pod animację: kolano 5°, kostka 10°, łokieć 20°) i 10 od toolboxa.
  **To jest najbardziej prawdopodobna przyczyna trzepania** — i tłumaczy, czemu trzy próby
  łatania po stronie fizyki i limitów nic nie dały.
  **Przy okazji potwierdzone: HEAD TRACKING NIE DZIAŁA** (`[HeadTrack] brak Motor6D
  Neck/Waist, Head aim skip` w logach). W CLAUDE.md figurował jako gotowy — po cichu
  nie działa na tym rigu, bo `MovementController` obraca `Neck` i `Waist`, a te istnieją
  tylko jako `Motor6D`.
  ⚠️ `Workspace.AvatarJointUpgrade` **nie istnieje** w tej wersji Studio — rigu nie da się
  przełączyć z kodu ani z tej właściwości.
  ✅ **DECYZJA KACPRA (2026-09-21): wymuszamy stary rig przez `StarterPlayer.StarterCharacter`.**
  Kroki po jego stronie: Avatar → Rig Builder → R15 (Block) → przemianować na
  `StarterCharacter` → wrzucić do `StarterPlayer` → **`LoadCharacterAppearance = false`**
  (inaczej Roblox dokleja graczom ich ubrania i akcesoria na wierzch naszego rigu).
  Efekt uboczny, który jest ZALETĄ: to samo daje **jednolitą bazę postaci**, o którą chodzi
  w całym systemie wyglądu.
  ⚠️ **DO ZWERYFIKOWANIA po wstawieniu**: czy Rig Builder w tej wersji Studio faktycznie
  tworzy rig z `Motor6D` (bywał aktualizowany). Sprawdzić `Motor6D >= 14` na postaci.
  ✅ **WYKONANE 2026-09-21: `StarterCharacter` + KONWERSJA RIGU NA `Motor6D`.**
  ⚠️ **Rig Builder w tej wersji Studio tworzy NOWY rig** (0 `Motor6D`, 15 `AnimationConstraint`,
  14 `BallSocket`) — samo wstawienie `StarterCharacter` NIE wystarczyło. Rig został
  przekonwertowany kodem: każdy `AnimationConstraint` spina te same dwa `Attachment` co
  `Motor6D`, więc dało się je przepisać jeden do jednego (`Part0/Part1` = rodzice attachmentów,
  `C0/C1` = ich `CFrame`, nazwa stawu = nazwa attachmentu bez sufiksu `RigAttachment`,
  Motor6D ląduje w części będącej `Part1`). Usunięto też 14 własnych `BallSocketConstraint`
  rigu — stary R15 ich nie ma, a to one biły się z constraintami toolboxa.
  **Wynik zmierzony w grze**: `Motor6D = 16` (15 rigu + altrootmotor toolboxa),
  `AnimationConstraint = 0`, **`BallSocket = 10` zamiast 24** — czyli JEDEN zestaw stawów
  zamiast dwóch. `Neck` i `Waist` obecne, ragdoll wchodzi w `Physics` i wraca do `Running`,
  `LoadCharacterAppearance = false` (gracz nie przynosi ubrań).
  💾 **Kopia zapasowa oryginalnego rigu: `ServerStorage.StarterCharacter_BACKUP`** — gdyby
  konwersja okazała się zła, wystarczy ją przenieść z powrotem do `StarterPlayer`.
  ⚠️ **To zmiana w datamodelu Studio — ginie bez Cmd+S.**
  ✅ **OCENIONE przez Kacpra (21-23.09)**: ragdoll przestał trzepać, ślizg zniknął. ✅ Głowa podąża
  za kamerą od 23.09 — ale NIE dzięki rigowi: head tracking nie działał nigdy (obrót pisany do
  `Transform`, który nadpisuje animator), naprawiony przez `C0`.
  ~~`AppearanceService` wyłączony flagą na czas testów~~ — flaga zdjęta, **w kodzie jej nie ma**
  (sprawdzone 2026-09-22).
  ✅ **ETAP ① SYSTEMU WYGLĄDU DZIAŁA (2026-09-21, zweryfikowane w grze).** Po konwersji rigu
  postać spawnuje się z: `Motor6D = 16`, `BallSocket = 10`, zero elementów avatara gracza,
  twarz na dekalu, kolory nałożone na części. Przykładowy wylosowany zestaw odczytany
  z żywej postaci: głowa/przedramię/dłoń/łydka = skóra brązowa (160,116,80), tors = koszulka
  czarna (45,45,50), udo = spodnie czarne (40,40,45), stopa = buty (58,48,42) — czyli
  **krótki rękaw i szorty**, bo przedramię i łydka zostały w kolorze skóry.
  ⚠️ **NIEAKTUALNE — stan faktyczny 2026-09-22**: `applyFace` dekala `face` **NIE tworzy**
  (tylko podmienia teksturę istniejącego) i tak ma zostać — na dynamicznej głowie świeży dekal
  wychodzi czarną plamą. Głowa w `StarterCharacter` to `MeshPart` z `FaceControls`, bez dekala,
  z twarzą wbudowaną — i Kacper potwierdził 22.09: „twarz działa". Ten akapit twierdził kiedyś,
  że `applyFace` MUSI dekal tworzyć; kod poszedł inną drogą, dokumentacja nie.
  ⚠️ **NIE wołać `AppearanceService.get()` przez `execute_luau`** — hard rule 14: osobny cache
  modułów sprawia, że dostajesz świeżą instancję z pustym `cached`, która **wylosuje nowy
  zestaw i może go graczowi ZAPISAĆ**. Do weryfikacji czytać wyłącznie kolory części postaci.

- 🧊⛔ **„ŚLISKI MOVEMENT" — PRÓBA NAPRAWY COFNIĘTA W CAŁOŚCI (2026-09-21). NIE POWTARZAĆ TĄ DROGĄ.**
  ✅ **2026-09-23: USTĄPIŁO** — Kacper: „nie ślizga się przy chodzeniu". Stało się po konwersji rigu na `Motor6D` (21.09), ale **przyczyna NIE jest zmierzona**: hipoteza z tabeli niżej (zerowe `CustomPhysicalProperties` HRP/Head od toolboxa) nie została ani potwierdzona, ani obalona. Nie ruszać. Jeśli wróci — zacząć od pomiaru, nie od tej hipotezy.
  **Co jest faktem** (zmierzone w Play, wyniki powtórzone w kontroli): toolbox ARTFVL ustawia
  `CustomPhysicalProperties(0,0,0,0,0)` — zerowe tarcie i gęstość — na `HumanoidRootPart`
  i `Head`, i robi to **przy KAŻDYM spawnie**, nie tylko na czas leżenia. To realnie psuje
  ostrość ruchu:
  | stan HRP/Head | rozpęd do 10 st/s | wybieg po puszczeniu | czas do stopu |
  |---|---|---|---|
  | zerowe (jak jest teraz) | 0.32 s | **1.16 studa** | 0.20 s |
  | domyślne | **0.07 s** | **0.08 studa** | **0.03 s** |
  **Co poszło nie tak**: przełączanie tych właściwości (domyślne poza ragdollem, zerowe na
  czas leżenia) + strażnik pilnujący wartości + rozluźnianie limitów stawów **sprawiło, że
  ragdoll zaczął TRZEPAĆ**. Kacper zgłosił to trzy razy z rzędu; trzy kolejne próby łatania
  (znacznik na wyścig ze strażnikiem, `LOOSE_ANGLE` na sztywne stawy rigu, pomiary odbić
  i szarpania) **nie pomogły**. Wszystko cofnięte — `RagdollService` jest z powrotem w wersji
  sprzed 2026-09-21: ruch jest znowu śliski, ale **wywrotka działa**.
  🚨 **WNIOSEK: nie ruszać `CustomPhysicalProperties` ani limitów stawów postaci.** Toolbox
  tworzy i prowadzi swoje constrainty w świecie, w którym HRP i głowa nie mają masy — zmiana
  tych warunków rozstraja mu fizykę tak, że nie da się tego nadrobić od zewnątrz. Ostrość
  ruchu, jeśli wrócimy do tematu, trzeba załatwić **gdzie indziej** (parametry Humanoida /
  `MovementController`), przy nietkniętych właściwościach partów.
  ⚠️ **Czego NIE dało się zmierzyć**: „trzepanie" jako liczba. Cztery metryki (szarpanie HRP,
  odbicia od ziemi, szarpanie kończyn, rozrzut) dały wyniki rozrzucone bez wzorca — to jest
  rzecz do oceny OKIEM. Nie szukać tu metryki, pytać Kacpra.
  📌 **Lekcja procesowa**: gdy Kacper napisał „ślizganie", zacząłem mierzyć ślizg STOPY
  w animacji, a chodziło o RESPONSYWNOŚĆ sterowania. Trzy zmiany i cztery pomiary poszły
  w rzecz, która nie była problemem. **Najpierw ustalić, co dokładnie widzi człowiek.**

    - **TO NIE JEST OSOBNA FICZURA, TYLKO PIERWSZY KROK SYSTEMU SKINÓW.** Wygląd zapisujemy
      jako `appearance = { shirt, pants, hair, face }` w `PlayerDataService`; losowanie
      startowe wypełnia te pola z darmowej puli, a przyszły sklep skinów podmienia pojedyncze
      pole. Zero przepisywania później. Zaczep na „dostał już zestaw" jest gotowy:
      `_starterReceived`.
    - ⚠️ **Startowa pula MUSI być celowo przeciętna.** 2026-09-16 zapisaliśmy, że jednolita
      baza jest warunkiem opłacalności skinów („przy losowych avatarach kupiony skin ginie
      w tłumie"). Losowanie czterech elementów częściowo w to uderza — ratuje to fakt, że
      pula jest NASZA i spójna stylistycznie. Jeśli losowe zestawy wyjdą ładniejsze niż
      płatne, sklep skinów umrze, zanim powstanie.
    - **Pułapki do obsłużenia w kodzie**: (a) `HumanoidDescription` budować RAZ per gracz
      przy wejściu i reużywać — nie tworzyć instancji przy każdym spawnie rundy; (b) assety
      dorzucić do preloadu w `ReplicatedFirst/LoadingScreen` (już preloaduje mapę), bo przy
      20 graczach spawnujących naraz dociąganie ubrań wydłuża start rundy; (c) każdy
      `LoadCharacterWithHumanoidDescription` w `pcall` z fallbackiem na gołą postać — asset
      bywa usunięty lub zmoderowany, a spawn nie może przez to paść.
    - ⚠️ **DO SPRAWDZENIA W PLAY**: czy fryzura (Accessory na głowie) przeżywa ragdoll ARTFVL —
      toolbox grzebie w constraintach postaci. Tego nie da się przewidzieć z kodu.
    - ⛔ **PRESET „CONSISTENT GAMEPLAY" ODRZUCONY — NIE PROPONOWAĆ PONOWNIE** (2026-09-20).
      Zaproponowałem go jako „bezpieczniejszy", Kacper przetestował i zgłosił DWA objawy:
      **ragdoll po bombie zaczął się buglować** i **przy chodzeniu pojawił się minimalny
      ślizg**. Zostajemy przy jego ustawieniu (**Avatar Type R15 + preset Player Choice**).
      **Powód, dla którego to nic nie kosztuje**: jednolity rig wymusza KOD — `HumanoidDescription`
      ustawia skale przy każdym spawnie — więc preset nie dawał nic ponad to, a płaciło się
      za niego fizyką. **Jedyne pole, które MUSI zostać, to `Avatar Type = R15`**, bo tego
      `HumanoidDescription` nie potrafi zmienić (R6 = po cichu znika head tracking, bo `Waist`
      istnieje tylko w R15, i rozjeżdża się `FEET_OFFSET` 2.5 pod progiem śmierci w lawie).
      **PRZYCZYNA USTALONA**: Kacper doprecyzował, że przestawiał **ANIMACJE, nie rig** — rig
      był R15 przez cały czas. Czyli oba objawy pochodzą z `Animation = Standard`.
      Mechanizm: przy `Player Choice` gracz chodzi WŁASNYM pakietem animacji, a `Standard`
      daje domyślny zestaw Robloxa, strojony pod `WalkSpeed 16` — a my mamy **12**, więc stopy
      przebierają szybciej, niż postać się przesuwa, i to czyta się jako ślizg. Ragdoll dokłada
      się do tego, bo ARTFVL wyłącza skrypt `Animate` i przełącza humanoida w stan fizyczny.
      `Collision = Outer Box` NIE był winowajcą — ta hipoteza padła, nie wracać do niej.
      - 🚨 **TWARDA REGUŁA DLA KODU AVATARA: `HumanoidDescription` NIE USTAWIA PÓL ANIMACJI**
        (`WalkAnimation`, `RunAnimation`, `IdleAnimation`, `JumpAnimation`, `FallAnimation`,
        `ClimbAnimation`, `SwimAnimation` zostają puste/0). Wypełnienie ich wymusza wszystkim
        standardowy zestaw, czyli **przywraca dokładnie ten ślizg** — tyle że z kodu i bez
        możliwości cofnięcia w Game Settings. Losujemy ubranie, fryzurę, twarz i kolor ciała;
        animacje zostają czyje były.
      - Gdybyśmy KIEDYŚ chcieli jednolitych animacji (dla spójności wyglądu), warunkiem
        wstępnym jest naprawa tempa: skalowanie prędkości animacji chodu do rzeczywistego
        `WalkSpeed`, a nie powrót do presetów w Game Settings.
    - **ROBOTA KACPRA, ZANIM RUSZYMY**: lista asset id — po 6-10 koszulek, spodni, fryzur
      i twarzy. **Bez niej nie ma czego losować** (można je też wyszukać z MCP przez
      `search_asset` z `priceFilter="free"`).
    - **DECYZJE KACPRA (2026-09-20, rozstrzygnięte):**
      - **Losowanie RAZ, przy pierwszym wejściu, zapisane na stałe.** Gracz zostaje przy
        swoim zestawie; to jedyny wariant, w którym sklep skinów ma sens (podmienia
        pojedyncze pole zapisanego wyglądu, zamiast walczyć z losowaniem co respawn).
      - **Kolor ciała TEŻ losowany z puli** (wbrew mojej rekomendacji „jeden dla wszystkich" —
        decyzja Kacpra, uszanować). ⚠️ Ryzyko, które z tego wynika: losowa karnacja × losowe
        ubranie = część zestawów wyjdzie brzydka, a nie mamy nad tym kontroli. Jeśli tak się
        stanie, tańszym ratunkiem jest ZAWĘŻENIE puli kolorów niż powrót do jednego koloru.
  - 👕 **SYSTEM WYGLĄDU I PANCERZY — PLAN USTALONY 2026-09-21 (jeszcze NIE zaimplementowany).**
    Sesja planowania z Kacprem; decyzje poniżej są jego, także te podjęte wbrew mojej
    rekomendacji (zaznaczone) — nie podważać ich przy implementacji.
    - **DECYZJE:**
      1. **Jednolita baza od gry**, nie avatar gracza. Kontrolujemy każdy element, więc
         wszystko jest sprzedawalne, a kupiony skin widać w tłumie.
      2. **Losujemy wygląd startowy RAZ**, zapisujemy na stałe; zmiana później w lobby.
         Powód: gra ma być szybka i clip-friendly, a kreator postaci przed pierwszą rundą
         to bariera, na której część graczy odpada.
      3. **Pancerze DAJĄ realny bonus** (⚠️ wbrew mojej rekomendacji „czysta kosmetyka"
         z 2026-09-16 — Kacper świadomie zdecydował inaczej, po przedstawieniu ryzyka
         pay-to-win i rozmycia loadoutu).
      4. **Pancerz to WYMIANA, nie dodatek**: mniej obrażeń, ale wolniej (garnek ~-20% dmg /
         -8% prędkości). **To jest mechanizm, który ratuje decyzję 3**: w grze, w której
         lawa goni, szybkość jest walutą przetrwania, więc gracz bez pancerza nie jest
         gorszy — jest szybszy. Balansuje się samo, bez tabelek.
      5. **Dwa sloty: głowa + tors** (⚠️ wbrew mojej rekomendacji jednego slotu). Spójne
         z 4, bo **kary też się sumują** — pełny pancerz to wyraźnie wolniejszy gracz.
         ⚠️ Pilnować sufitu: 2 × 25% = 50% redukcji to za dużo, celować w **12-15% per
         pancerz**.
      6. **Pancerze i kosmetyka za TĘ SAMĄ kasę co itemy** (⚠️ wbrew mojej rekomendacji
         osobnej waluty). Ryzyko „bomba czy czapka" rozbraja się przez to, że **pancerz
         jest zakupem JEDNORAZOWYM i drogim** (rząd 500$, nie 50$): konkurencja z bombami
         jest chwilowa („zbieram przez kilka rund"), nie przy każdym respawnie. **Nigdy nie
         robić pancerzy zużywalnymi** — wtedy gracze przestaliby kupować bomby na stałe.
      7. **Kolor skóry losowany, zmiana ZA DARMO** w przebieralni. Darmowa, bo karanie kasą
         za coś, co sami wylosowaliśmy, czyta się jako niesprawiedliwe.
      8. **Kolory zamiast tekstur na start.** Powód: tekstury trzeba wgrać na Roblox (opłata
         za sztukę + moderacja, czasem odrzucenie), a kolor to jedna wartość w kodzie. Układa
         też ekonomię sklepu: **kolory tanie, tekstury drogie** — tekstury dołożyć później,
         kontrakt się nie zmieni.
      9. **Wygląd startowy (2026-09-21)**: twarz `rbxassetid://13618859077` („default face",
         darmowa, ⚠️ asset typu **Decal**, nie Face — ustawiać przez dekal `face` w głowie,
         bo pole `Face` w `HumanoidDescription` bywa wybredne co do typu), **łysa głowa**
         (brak `HairAccessory`), reszta to losowane kolory. **Fryzury i inne twarze WYŁĄCZNIE
         do kupienia** — nie ma ich w puli startowej.
         ➜ **Znaczy to, że etap ① nie ma ŻADNEJ blokady po stronie assetów.**
    - 🎨 **JAK ROBIMY „KOSZULKĘ" I „SPODNIE" BEZ TEKSTUR (rozwiązane 2026-09-21).**
      Pytanie Kacpra: „czy da się, żeby koszulka to był tors + połowa ramion, a nogi inny
      kolor — bo na R15 nie mogę tego znaleźć".
      **Nie znalazł, bo tego tam NIE MA**: `BodyColors` i `HumanoidDescription` mają tylko
      **6 pól kolorów** (głowa, tors, L/P ręka, L/P noga) — pozostałość po R6. Na R15 jeden
      „kolor ręki" pokrywa `UpperArm` + `LowerArm` + `Hand` naraz, więc połowy ramienia nie
      da się pomalować tą drogą.
      **ROZWIĄZANIE: ustawiać `Color` BEZPOŚREDNIO na 15 częściach R15**, po spawnie,
      pomijając `BodyColors`. Daje to pełną kontrolę nad każdym segmentem, a przy okazji
      **sześć kategorii towaru z jednej mechaniki, bez ani jednego assetu**:
      - `UpperTorso` + `LowerTorso` + oba `UpperArm` → koszulka **krótki rękaw**
      - dołożyć oba `LowerArm` → koszulka **długi rękaw** (ten sam towar, inny zestaw części)
      - `Hand` osobno → **rękawiczki**
      - oba `UpperLeg` + `LowerLeg` → **długie spodnie**; tylko `UpperLeg` → **szorty**
      - `Foot` osobno → **buty**
      ⚠️ **Dwie pułapki**: (a) `BodyColors` w postaci trzeba USUNĄĆ albo ustawić na kolor
      skóry — przy pierwszej zmianie nadpisze kolory części i wszystko wróci do jednolitego;
      (b) stosować po **KAŻDYM** spawnie, bo start rundy to nowy `LoadCharacter`.
    - 🚨 **TRZY PUŁAPKI WYKRYTE PRZY PLANOWANIU — obsłużyć przy implementacji:**
      1. **KARA PRĘDKOŚCI JEST DZIŚ NIEEGZEKWOWALNA.** `MovementController` ustawia
         `WalkSpeed` u KLIENTA, a `AntiCheatService` sprawdza tylko próg `SprintSpeed + 8`.
         Cheater w pełnym pancerzu po prostu nie zastosuje kary u siebie, zmieści się
         w limicie i dostanie redukcję obrażeń za darmo. **Fix musi wejść RAZEM z pancerzami**:
         limit anti-cheata liczony per gracz, przeskalowany o jego karę prędkości.
      2. **PANCERZ NIE MOŻE CHRONIĆ PRZED LAWĄ.** Lawa to jedyna niepodważalna zasada gry —
         moment śmierci musi być czytelny dla wszystkich. Redukcja działa na bombę, gruz
         i ewentualnie upadek; kontakt z lawą zabija zawsze.
      3. **WYGLĄD I EKWIPUNEK TO DWA OSOBNE ZBIORY DANYCH**, nawet jeśli w lobby będą jednym
         stoiskiem. Kosmetyka nie wpływa na grę (można jej ufać), pancerz wpływa — więc
         serwer musi być jedynym źródłem prawdy o tym, co gracz nosi, i sam stosować
         redukcję w `BombService` / `DebrisService` / `FallDamageService`. Klient nigdy
         o tym nie decyduje, inaczej pierwszy exploiter chodzi z 90% redukcji.
    - **AKCESORIA A RAGDOLL — SPRAWDZONE W KODZIE TOOLBOXA (2026-09-21), DZIAŁAJĄ**:
      `ragdollserver.makeaccessoryjoints()` przechodzi po akcesoriach postaci, **zeruje masę**
      ich `Handle` (`CustomPhysicalProperties(0,0,0,0,0)` — garnek nie ciągnie głowy w dół)
      i spina je `HingeConstraint` z `LimitsEnabled`, `UpperAngle = LowerAngle = 0`, czyli
      sztywno. Czapki nie odlatują i nie szarpią postacią.
      ⚠️ **ALE: akcesorium MUSI mieć `Attachment` w swoim `Handle`.** W toolboxie jest błąd —
      sprawdzenie `if attachment1` stoi PO użyciu `attachment1.Name`, więc akcesorium bez
      Attachment (typowe dla starych modeli przyklejanych Weldem) **wywala cały skrypt
      ragdolla w połowie**, a nie tylko psuje czapkę. Kod ma to odsiewać przy zakładaniu.
      **Dla Kacpra znaczy to: garnek i kamizelki muszą być prawdziwymi `Accessory`
      z Attachmentem, nie modelem przyspawanym do głowy.**
    - **SZKIC ARCHITEKTURY** (do doprecyzowania przed kodem):
      - dane gracza: `appearance = { skin, shirt, pants, face, hair }` (kosmetyka) +
        `equipment = { head, torso }` (pancerze) + `owned = { [id] = true }`
      - katalogi shared, ROZDZIELONE: kosmetyka osobno, pancerze osobno (patrz pułapka 3)
      - serwis wyglądu: buduje `HumanoidDescription`, losuje start, stawia postać
        (zastępuje `LoadCharacter` w `PlayerService`, w dwóch miejscach)
      - serwis pancerzy: zakłada `Accessory` przy spawnie + **API mnożników obrażeń
        i prędkości** czytane przez BombService/DebrisService/FallDamageService/AntiCheat
      - stoisko w lobby: wzorzec sprawdzony na sklepie broni (NPC + `ProximityPrompt` +
        markery kamer + scena)
    - **KOLEJNOŚĆ PRAC** (każdy etap sam w sobie daje widoczny efekt): ① jednolita baza
      + losowanie startowe (bez sklepu) → ② przebieralnia: darmowa zmiana tego, co się ma →
      ③ sklep kosmetyczny za kasę → ④ **pancerze** (mechanika + fix anti-cheata) — celowo
      NA KOŃCU, bo to jedyny etap dotykający balansu i bezpieczeństwa.
    - **ROBOTA KACPRA**: (a) modele pancerzy jako prawdziwe `Accessory` z Attachmentem;
      (b) asset id twarzy i fryzur (albo zgoda, żebym wyszukał darmowe przez `search_asset`);
      (c) stoisko w lobby wg kontraktu `SKINNPC` / `SKINPODIUM` / `SKINCAMERA`.

  - **AVATAR: zostajemy przy R15** (decyzja 2026-09-16, po rozważeniu R6). Cel Kacpra to **kwadratowy kształt**, a nie konkretny rig — i R15 to daje przez `HumanoidDescription`: `BodyTypeScale = 0` + `ProportionScale = 0` (wyłącza proporcje Rthro) oraz `HeightScale`/`WidthScale`/`DepthScale`/`HeadScale` na sztywne 1. **R6 odrzucony**, bo kosztowałby trzy rzeczy: (a) head tracking przestałby działać — `MovementController` obraca `Neck` + `Waist`, a Waist istnieje tylko w R15 (w kodzie jest ścieżka, która przy R6 PO CICHU pomija head tracking); (b) `LavaService.FEET_OFFSET = 2.5` jest dostrojony do R15 (w R6 bliżej 3) — próg śmierci w lawie byłby przesunięty; (c) ragdoll toolbox ARTFVL był z bólem dostrajany pod rig R15 i wymagałby ponownego testu. **Bonus z ujednolicenia skali**: dziś gracze z różną skalą avatara mają różny dystans HRP→stopy, więc próg śmierci jest dla każdego minimalnie inny — wymuszenie skali 1 to naprawia. **Wejście w kod**: `PlayerService` woła spawn w dwóch miejscach — od 2026-09-21 przez `AppearanceService.loadCharacter(player)`. ⚠️ NIE przez `LoadCharacterWithHumanoidDescription` (sprawdzone i odrzucone, patrz wyżej).
  - **SKINY: w v1.0 CZYSTO KOSMETYCZNE.** Kacper pytał o bonusy do gry na ubraniach — odradzone z dwóch powodów: to pay-to-win, jeśli pójdzie za Robuxy, i **rozmywa własny design loadoutu** (cały sens 3 z 6 polega na tym, że wybór itemów jest JEDYNĄ osią mocy; druga oś na ubraniach każe balansować dwa systemy przeciwko sobie). Argument ZA jednolitą bazą, którego Kacper nie miał na liście: przy losowych avatarach kupiony skin ginie w tłumie — dopiero jednolita baza sprawia, że skin widać, co jest warunkiem, żeby ktokolwiek chciał za niego zapłacić. Przy R15 „ubranie" to dalej `Shirt` + `Pants`, czyli **dwa asset id na skin**. **Darmowy skin startowy** — `PlayerDataService` ma już pole `_starterReceived`, więc to tanie: uczy mechaniki i sklep nie wygląda na pusty.
  - **ROBOTA DLA BUILDERA (ustalone 2026-09-16)** — obecny sklep można oddać do dopieszczenia **od razu**: kontrakt jest odporny na zmiany wyglądu, a dodanie itemu to model + marker obok. Nazwy nie do ruszenia (stan 2026-09-20): stragan `WeaponsShop` z modelem `NPC` w środku, scena `WeaponShopScene` z folderami `Decorations` i `ShopCameras`, nazwy modeli itemów zgodne z `sceneModel` — oraz w `ShopUI`: `ItemName`, `Price`, `Description`, `StatusLabel`, `BuyButton`, `CloseButton`, `PrevButton`, `NextButton`. **Stoisko skinów też może powstać równolegle**, mimo że kod jest daleko w kolejce — proponowany kontrakt: `Workspace.Lobby.SKINNPC` (Model z PrimaryPart + `ProximityPrompt`, party zanchorowane), `SKINPODIUM` (BasePart — miejsce, na którym STAJE gracz), `SKINCAMERA` (BasePart, anchored, Transparency 1). Wokół podium musi być czysta przestrzeń i nieprzesłonięta linia widzenia od markera kamery. Stoiska budować jako **powtarzalny moduł** — trzecie (loadout) prawdopodobnie dojdzie.
    ⚠️ **DECYZJA DO PODJĘCIA PRZED ODDANIEM ROBOTY BUILDEROWI: gdzie mieszka UI wyboru loadoutu** (ten sam NPC co sklep / trzecie stoisko / HUD). To jedyna rzecz, która może kazać mu coś przerabiać.
- 🔬 **WNIOSEK DESIGNOWY DO ROZSTRZYGNIĘCIA (analiza 2026-09-08) — "wszyscy pójdą na najwyższy budynek":**
  Przy projektowych prędkościach lawa w 80-sekundowej rundzie urasta tylko o **~121 studów** (0.6×20 + 1.2×20 + 2.0×20 + 3.0×15), startując z `Y=-5` — czyli dochodzi do **~Y116**, a `MaxY=250` NIGDY nie jest osiągane. **Każde piętro powyżej ~Y116 jest z definicji bezpieczne od lawy**, więc kemping na szczycie jest darmowy, a jedyną presją na górze są inni gracze (bomby/push/kolaps). Do decyzji przed launchem: albo lawa musi realnie dogonić szczyt najwyższej wieży w endgame, albo kilka wież ma być podobnej wysokości (rozproszenie + sens mostów), albo szczyt ma być świadomą pułapką (tłum + bomby + kolaps sekcji). **Bez rozstrzygnięcia tego mapa Downtown może być "ładna, ale rozwiązana".**
  >
  > 📐 **POMIAR NA GOTOWEJ MAPIE (2026-09-14) — problem jest znacznie mniejszy, niż wynikało z analizy.** Tamta liczyła od `Config.Lava.StartY = -5`; realny part Kacpra startuje z **Y = -14.75**, a najwyższy punkt budynków to **Y = 109.0** (`PupleHotel`, 22 878 partów w `Buildings`, X -524..-107, Z -262..190). Do zalania WSZYSTKIEGO brakuje **124 studów**, a projektowe fazy dają **121** (12+24+40+45). Czyli lawa kończy rundę **~2.75 studa pod najwyższym dachem** — najwyższy budynek jest bezpieczny, ale dosłownie o włos i dopiero w ostatnich sekundach. To już jest napięty endgame, a nie darmowy kemping; podniesienie `Endgame` z 3.0 na ~3.2 stud/s zalewa także szczyt. **Do decyzji zostaje kierunek, nie skala problemu.** **2026-09-22: Kacper — rozstrzygamy po teście z ludźmi** (czy ktokolwiek w ogóle dochodzi na szczyt), nie z arkusza.
  >
  > 🔴 **KOREKTA 2026-09-23 — POMIAR POWYŻEJ JEST NIEAKTUALNY, a decyzja z 22.09 zapadła na jego podstawie.** Liczył start lawy od **Y −14.75**; stos został potem przeniesiony i startuje z **Y ≈ 2.5** (log + pomiar 23.09). Dachy bez zmian: PupleHotel **109**, GreenBuilding **106**, CyanOffice 98, PurpleSchool 93, SandBuilding 92. Przy produkcyjnych fazach (+121): lawa dochodzi do PupleHotel po **~10 s Endgame, czyli ~5 s przed końcem rundy**, i kończy na **~123.5 — 14 studów NAD najwyższym dachem**. Ponieważ lawa RANI 7 s zamiast zabijać, gracz z pełnym życiem na PupleHotel (~5 s w lawie) albo GreenBuilding (~6 s) **przeżywa rundę, stojąc całkowicie zanurzony**; na CyanOffice i niżej już nie. ➜ Pytanie designowe NIE brzmi „czy szczyt jest za bezpieczny", tylko **„czy przetrwanie pod powierzchnią lawy jest OK"**. Kacper poinformowany 23.09. Test testowymi fazami (240 s) daje to samo — przyrost ~120 jest sprzężony celowo.
  >
  > ⚠️ Przy okazji: obrys lawy (X -540..-112, Z -261..196) nie pokrywa dwóch budynków na krawędzi — `SandBuilding` i `OldBuilding2` wystają ~5 studów poza lawę po +X. `killSubmerged` sprawdza granice XZ, więc tam byłby pasek bezpiecznego gruntu. Poszerzenie partu lawy o ~15 studów po X to robota na 10 sekund w Studio.
- ❌ **PRZED LAUNCHEM — trzy ustawienia testowe do cofnięcia** (wszystkie warnują głośno co boot):
  - (11.10: fazy USUNIĘTE — `Config.Lava.RoundDuration` 240 s, lawa płynnie 0 → 1.0 stud/s, ten sam przyrost ~120; produkcja 80 s, 0 → 3.0. Historia niżej.) `Config.Lava.Phases` = **240 s** (15/60/60/60/45) z prędkościami 0/0.20/0.40/0.65/1.00 — skrócone z 10 minut 2026-09-21 na testy z ludźmi. Produkcyjne: 80 s (5/20/20/20/15) i 0.6/1.2/2.0/3.0. ⚠️ **CZASY ×3 I PRĘDKOŚCI ÷3 SĄ SPRZĘŻONE** — tak dobrane, żeby całkowity przyrost został ~120 studów (koniec rundy na Y 122.5, czyli lawa zalewa najwyższy dach na Y 109). Zmiana jednego bez drugiego albo topi mapę w połowie rundy, albo sprawia, że lawa nikogo nie dogania. `GameLoopService.warnIfRoundTooLong` krzyczy, dopóki runda > 180 s.
  - ✅ `Config.Lava.Enabled` — **COFNIĘTE 2026-09-21, lawa znowu rośnie i rani.** Chwilowy override „wszystkie fazy 0.1 stud/s" z tego samego dnia **już nie obowiązuje** — stan faktyczny (sprawdzony 2026-09-23): fazy 15/60/60/60/45 s przy 0/0.20/0.40/0.65/1.00 stud/s (patrz punkt wyżej).
  - `Config.Dev.Enabled = false` (tryb testowy 2026-08-12: nieskończone itemy, klawisze **K**=skip fazy, O=koniec rundy) **ORAZ `Config.Dev.InfiniteItemsForAll = false`** (2026-09-21 — to drugie daje nieskończone itemy **KAŻDEMU graczowi**, nie tylko nickom z `Usernames`; powstało na testy z kolegami). Zostawienie obu na `true` = darmowe bomby dla całego serwera na produkcji. ⚠️ Klawisze K/O celowo NIE są objęte `InfiniteItemsForAll` — sterowanie rundą zostaje przy `Usernames`, żeby przypadkowe O nie kończyło rundy wszystkim.
  - `Config.Game.MinPlayers = 2` (dziś 1, żeby dało się testować solo).
- 🌋 **OPRAWA LAWY — ZAIMPLEMENTOWANA, CZEKA NA KACPRA I NA TEST** (2026-09-16):
  - **Blokada: Kacper ma wrzucić `Texture` na warstwy w `Workspace.Lava`** (Face Top, skala przez `StudsPerTileU/V`; po jednej na warstwę albo kilka na jednej). Bez tego `LavaSurfaceController` warnuje i powierzchnia stoi. Strojenie tempa per warstwa przez atrybuty `ScrollU`/`ScrollV`/`PulseAmount`/`PulsePeriod` — w Studio, bez wchodzenia w kod, również w trakcie Play.
  - **Nieprzetestowane w Play**: przewijanie warstw, bąble, 4 światła, para na linii zalania, falowanie tafli. Przy pierwszym teście patrzeć na FPS (światła) i na to, czy para nie sypie się za gęsto.
  - Ustawić part lawy na docelowej wysokości startowej — kod bierze ją z partu.
- ❌ Day 2: mapa Downtown (Kacper buduje w Studio) — 8-12 wieżowców z dziurami, `Workspace.SpawnPoints` z multi-spawn, `Workspace.Map.Locked.CashSpawns` markery.
- ❌ Studio assety pod nowy kod: `ReplicatedStorage.Cash` (model cash), `StarterGui.HUD.CashPopupTemplate`, `StarterGui.HUD.CooldownBars` (+ template + Fill) — kod ma fallback/default gdy brak, ale styling Kacpra dopiero po postawieniu. **Do przestylowania (stoją placeholdery Claude'a):** `StarterGui.ShopUI` (panel sklepu) i `ReplicatedStorage.StaminaBar` (pasek 3D) — kod szuka w nich nazw z kontraktu, więc wygląd można zmienić dowolnie, byle nazwy zostały.
- ❌ Day 4 dokończyć: pozostałe itemy z wybranej szóstki — **RPG, sticky bomb, energy drink** (modele już na wystawie). Hak ✅ 2026-09-22. **20.10: energy drink zrobiony (10 s staminy bez końca, 25$), RPG etap 1 (strzał + wybuch ~70% bomby, 75$; etap 2 = rocket jump bez obrażeń także przy lądowaniu + efekty) — oba czekają na test (`docs/TESTY.md`). Zostaje sticky bomb.** Od 18.10 loadout = 3 sloty, więc nowy item NIE wymaga nowego `SlotN`. Wzorzec: definicja + `shopOrder` + własny remote i serwis (jak Bomb/Bridge/Grapple); sklep i hotbar biorą item automatycznie. ⚠️ Każdy kolejny item = kolejny `SlotN` w HUD po stronie Kacpra.
- ❌ Day 5: ShopService VIP gamepass, dev products (Robux purchases).
- ❌ Day 6 dokończyć: eventy (spadające kule, wiatr), więcej polish, particle/sound.
- ❌ Day 7: closed beta, test, launch, TikToki.
- ❌ **Skala kilkuset active** — audyt kodu zrobiony (2026-08-11), zostaje test POD OBCIĄŻENIEM: BindToClose z 20 graczami, realne zużycie budżetu DataStore. Koszt fizyki wybuchów wypada z listy do czasu, aż powstanie nowy system — wtedy wraca jako pierwsza rzecz do zmierzenia.

---

## PLAN: LOADOUT — 3 itemy na rundę (napisany 30.09, kod PO teście destrukcji)

**Co to znaczy dla gry**: dziś pasek itemów sam się przestawia — masz bombę i most, bomby się kończą, most przeskakuje na klawisz 1. W środku ucieczki przed lawą naciskasz „2" i nie dzieje się nic albo wychodzi nie ten item. Po tej zmianie **Twoje trzy itemy siedzą na klawiszach 1-2-3 i nigdy się nie ruszają** — nawet gdy skończy Ci się amunicja (slot zostaje wyszarzony). Przy okazji to jest oś balansu: masz sześć itemów, na rundę bierzesz trzy, więc musisz wybrać między mobilnością a ofensywą.

### ✅ DECYZJA KACPRA (30.09): loadout mieszka w EKWIPUNKU
Osobny panel „Ekwipunek", nie zakładka w sklepie i nie trzecie stoisko. Widzisz w nim wszystko, co posiadasz, i wybierasz trzy rzeczy na rundę. **Dobra strona tej decyzji**: nie dokładamy graczowi wycieczki do trzeciego NPC w 30-sekundowej przerwie — ekwipunek otwierasz, gdzie stoisz. **To odblokowuje robotę buildera** (patrz wyżej: to była jedyna rzecz, która mogła kazać mu coś przerabiać — stoisko loadoutu NIE powstaje).

**Otwieranie**: przycisk w HUD **oraz** klawisz `I`.
*Dlaczego `I`, a nie `E` czy `Tab`*: `E` to domyślny klawisz `ProximityPrompt`, czyli kolidowałby ze sklepem, przy którym gracz stoi w lobby; `Tab` należy do wbudowanej listy graczy. Zajęte są już 1-2-3 (hotbar), `F` (push), `R` (obrót mostu), `Shift` (sprint), `Q` (wyjście ze sklepu), `G` (dev).

**W trakcie rundy panel się otwiera, ale tylko do podglądu** — zmiana loadoutu działa wyłącznie w lobby (uzasadnienie w zasadach niżej). Zamiast blokować otwieranie, pokazujemy komunikat: łatwiej zrozumieć „nie teraz" niż przycisk, który nie reaguje.

### 🎨 KONTRAKT NAZW DLA STUDIO (do postawienia przez Kacpra)
```
StarterGui.HUD.InventoryButton      (TextButton — otwiera panel)
StarterGui.Inventory                (ScreenGui, ⚠️ ResetOnSpawn = FALSE)
  └── Panel                         (Frame)
      ├── LoadoutSlots              (Frame)
      │   └── Slot1, Slot2, Slot3   (TextButton)
      │       ├── ItemName          (TextLabel)
      │       └── Count             (TextLabel — "x3")
      ├── OwnedList                 (ScrollingFrame — lista posiadanych)
      │   └── ItemTemplate          (TextButton, Visible = false — wzór wiersza)
      │       ├── ItemName          (TextLabel)
      │       ├── Count             (TextLabel)
      │       └── SelectStroke      (UIStroke, Thickness = 0)
      ├── StatusLabel               (TextLabel — "loadout zmieniasz tylko w lobby")
      └── CloseButton               (TextButton)
```
⚠️ **`ResetOnSpawn = false` jest obowiązkowe** (hard rule 10). Domyślne `true` odświeża ScreenGui przy każdym `LoadCharacter`, czyli na starcie KAŻDEJ rundy gracz traci listenery z poprzedniej instancji panelu — dokładnie ten błąd zjadł już HUD w tym projekcie.
Kod znosi brak każdego elementu (jak `HotbarController` znosi brak `Slot3`): panel bez `OwnedList` po prostu nie pokaże listy, zamiast wywalić klienta.

### Zasady (te same przy każdej opcji)
- **Trzy sloty, stałe.** Klawisze 1-2-3 to Twoje trzy wybrane itemy. Slot zostaje na miejscu przy zero sztuk — wyszarzony, „x0". Koniec przeskakiwania.
- **Masz mniej niż 3 typy?** Loadout to po prostu to, co masz. Nowy gracz nie widzi pustego ekranu.
- **Kupujesz nowy item, a masz wolny slot** → wskakuje sam. Nowy gracz nigdy nie musi wchodzić w loadout, żeby zagrać.
- **Kupujesz, a wszystkie 3 zajęte** → item leży w ekwipunku, z komunikatem „masz już 3 itemy — zmień loadout". Nie podmieniamy nic za gracza.
- ~~**Zmiana tylko w lobby.**~~ ~~ZMIENIONE 19.10: loadout zmieniasz w każdej chwili, też w rundzie.~~ **OSTATECZNIE 19.10 (Kacper: „usuń inventory podczas rundy”): ekwipunek TYLKO W LOBBY** — poza lobby przycisk INVENTORY znika, klawisz I nic nie robi, otwarty panel sam się zamyka, serwer odrzuca `SetLoadout`.
- **Loadout się zapisuje** — wracasz na serwer ze swoim układem.

### Co robi kod (*dla Claude'a*)
1. **Dane gracza**: nowe pole `loadout = { itemId, itemId, itemId }` w `PlayerDataService`. Celowo BRAK w defaultach (ta sama konwencja co `appearance` i `settings`): nieobecne = „jeszcze nie wybrano" → serwis wypełnia pierwszymi posiadanymi z `ItemDefinitions.shopOrder`. Stare zapisy wchodzą tą samą ścieżką, bez migracji.
2. **Nowy serwis `LoadoutService`** — jedyny właściciel tego stanu (zasada single source of truth): waliduje wybór (istniejący itemId, bez duplikatów, maks 3, tylko w `LOBBY`), zapisuje, replikuje. Rate limit jak przy `BuyItem`.
3. **🔴 Serwer musi pilnować equipa.** Dziś `EquipItem` sprawdza tylko, czy gracz ma item w inventory. Bez zmiany oszust equipuje wszystkie 6 i cały sens loadoutu pada. Warunek: `itemId` musi być w loadoucie gracza.
4. **`HotbarController`**: `rebuildSlotMapping` przestaje upychać „pierwsze N posiadanych" (linie 44-56) i czyta loadout. Sloty 4-5 przestają być używane — ale kod ma zostać na N slotów, bo `Slot3` w HUD jeszcze nie istnieje (patrz `docs/DO_RELEASE.md`).
5. **Kontrakt**: `Remotes.luau` `+ "SetLoadout"` (klient→serwer, `FireServer({itemId})`) i `+ "LoadoutChanged"` (serwer→klient). Wysyłka loadoutu wchodzi do handshake'u z paczki 3.
5b. **Nowy `InventoryController`** — panel z kontraktu wyżej, klawisz `I`, przycisk w HUD. Listenery podpięte w części synchronicznej (zasada z paczki 3), szukanie UI w `task.spawn`.
6. **Zależność**: paczka 3 (start klienta) powinna wejść PIERWSZA — inaczej dokładamy czwarty stan, który na wolnym telefonie może nie dojechać.

### Kolejność
Najpierw skończona destrukcja, potem paczka 3, potem loadout, potem brakujące itemy (RPG, sticky bomb, energy drink). **Loadout przed itemami** — bo przy sześciu itemach i dzisiejszym upychaniu slotów pasek staje się nieużywalny, a każdy nowy item pogarsza problem.

### ✅ DECYZJE KACPRA 18.10 + PLAN WYKONANIA (zastępuje kontrakt nazw wyżej)
- **Wygląd**: styl HUD (Figma niedostępna — wtyczka bez logowania): czarne tło z gradientem przezroczystości (`Fill`), ramki 7, zaokrąglenia 22, Fredoka, biały tekst z obrysem i cieniem. Napisy po angielsku (INVENTORY / LOADOUT / DETAILS — jak ROUND, YOU KILLED); opisy itemów z `ItemDefinitions.desc` — od 18.10 po angielsku (Fredoka nie ma polskich znaków).
- **Układ**: duży panel na środku, ściemnione tło; lewo siatka WSZYSTKICH itemów gry (też x0 — widać, co istnieje i ile kosztuje), prawo DETAILS, dół 3 sloty LOADOUT.
- **Sterowanie** (⚠️ zmienione 19.10: klik w item = podgląd w wysuwanym oknie DETAILS, do loadoutu przycisk ADD / REMOVE / SWAP w DETAILS; reszta niżej bez zmian): ~~klik itemu = wkłada do wybranego slotu (albo pierwszego wolnego; klik itemu już w loadoucie = wyjmuje)~~; przeciąganie item → slot, slot ↔ slot (zamiana), slot poza panel = wyjęcie. PC: najechanie na item + `1/2/3` = do tego slotu. Otwieranie `I` + przycisk w HUD (`SideButtons`), zamknięcie `I`, X albo klik w tło.
- **Dodatki (wszystkie 4)**: obracający się model 3D w DETAILS (`ViewportFrame`, klon modelu z wystawy sklepu), paski cech POWER / RANGE / MOBILITY (`ItemDefinitions.<id>.stats`, 0-5), ostrzeżenie x0 (slot paska pulsuje na czerwono w lobby), zapis loadoutu w danych gracza.
- **Od Claude'a (luki i usprawnienia)**: serwer pilnuje equipa w 3 serwisach (`LoadoutService.canEquip`); kropka „!” na przycisku INVENTORY po kupnie itemu, który nie zmieścił się w loadoucie; sklep po zakupie mówi „ADD IT IN INVENTORY”, gdy loadout pełny; ikona przelatuje z siatki do slotu; klient zbiera szybkie zmiany i wysyła ostatnią (0,25 s), serwer i tak jest jedynym źródłem prawdy; nieznane itemy w zapisie są czyszczone; loadout w handshake'u paczki 3 i w czekaniu ekranu ładowania; klawisze 1-3 w otwartym panelu nie wyciągają itemów.
- **Kod**: `LoadoutService` (serwer, jedyny właściciel `data.loadout` = 3 napisy, `""` = pusty slot), `LoadoutState` (klient, jedno miejsce stanu dla paska i panelu), `InventoryController`, zmiany w `HotbarController`, `ShopService`, `ShopController`, `Bomb/Bridge/GrappleService`, `HudScaleController` (skaluje też ScreenGui `Inventory`). Remote'y `SetLoadout` / `LoadoutChanged`.
