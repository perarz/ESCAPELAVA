> ARCHIWUM sprzed audytu 23.10.2026. To zapis historyczny, nie bieżące instrukcje ani lista zadań. Aktualne dokumenty są dwa poziomy wyżej.

# docs/DESTRUCTION_PLAN.md — system destrukcji v2 ("topka Roblox") → v3

> Plan zatwierdzony 2026-08-11 (decyzje Kacpra niżej). Stary system (BlastService) skasowany
> bez śladu — NIE odtwarzamy go, budujemy wg tego dokumentu. Implementacja etapami,
> każdy etap grywalny i testowany w Play zanim zaczniemy następny.
>
> 🏗️ **2026-09-25: v4 — fazy A-D NAPISANE, OrangeBuilding w grze na v4; test dymny 25.09 znalazł
> i częściowo naprawił „grupy kolapsu nie spadają” (4 → 14 z 24 spada fizyką, reszta przez siatkę
> bezpieczeństwa do klientów); całość CZEKA NA TEST KACPRA W PLAY; potem faza E (RiderTracker).** Rozdział „v4” na samym końcu
> pliku jest AKTUALNY: zastępuje pass podparcia v3 (dla budynków z danymi) i usunięty `StructureService`.
> Rozdziały v2/v3 zostają jako historia i opis kodu, który dalej działa na reszcie mapy.
>
> 🧨 **2026-09-23: CAŁA DESTRUKCJA DO NAPRAWY (decyzja Kacpra)** — stan i start naprawy: rozdział „v3” na końcu + STATUS w CLAUDE.md.
> 🔴 **2026-09-23: v3 — przeczytaj rozdział „v3” na KOŃCU tego pliku.** Zmienia on kilka
> zasad z v2 opisanych niżej (kawałki dziur nie są już gruzem serwera, drobnica ma własne
> reguły, podparcie liczone „przed i po”, pocięty part jest przycinany, nie kasowany).
> Rozdziały v2 zostają jako historia decyzji — tam, gdzie się rozjeżdżają, rację ma v3.

## Decyzje designowe (zatwierdzone)

| Decyzja | Wybór |
|---|---|
| Kolaps sekcji budynku (filary padły → piętra lecą) | TAK — etap 4, architektura pod to od dnia 1 |
| Gruz przygniata graczy (dmg/kill + credit "crushed") | TAK |
| Życie gruzu | HYBRYDA: duże kawałki = platformy do końca rundy; małe odłamki klienckie znikają ~5s |
| Oznaczanie kategorii | AUTO z materiału (Glass = szkło, reszta = ściana) + tag `Pillar` tylko na filary |

## Filozofia: iluzja, nie symulacja

1. **Hybrydowy gruz** — serwer trzyma TYLKO duże, znaczące kawałki (platformy, gameplay).
   Małe odłamki spawnuje KLIENT lokalnie z `(center, seed)` — zero replikacji, zero fizyki
   serwera, liczba skalowana jakością grafiki klienta. Pył/drobiny = particle.
2. **Pękanie tylko w promieniu** — ściana trafiona bombą dostaje DZIURĘ (kawałki w zasięgu
   → gruz), reszta panelu zostaje jako 2-4 większe anchored party. Nie zamieniamy całych
   ścian w gruz.
3. **Cięcie boxów, nie meshy** — part tnie się na 4-12 nierównych prostopadłościanów
   (losowe płaszczyzny cięcia 30-70%, lekki obrót przy spawnie, czasem WedgePart na
   krawędzi dla poszarpania). ZERO CSG (SubtractAsync = wolne, zawodne, zabija serwer).
   Deterministyczne z seedem — klient generuje identyczny wzór dla swoich odłamków.
4. **VFX wybuchu po stronie klienta** — serwer fire'uje jeden remote `BlastFX(center,
   radius, seed)`, każdy klient renderuje błysk/falę/dym/odłamki lokalnie. Tanio w sieci,
   skalowalne per jakość grafiki.

## Architektura (ownership)

| Moduł | Odpowiada za | Stan który trzyma |
|---|---|---|
| `shared/Modules/Fracture.luau` | czysta matematyka cięcia boxa na nierówne kawałki, deterministyczna (seed) | brak (pure functions) — używana przez serwer I klienta |
| `server/DestructionService` | wejście `detonate(center, params, attacker)`: kategorie, HP, falloff dmg, co pęka / co się pcha, occlusion dmg graczy | HP uszkodzonych partów (attribute na parcie) |
| `server/DebrisService` | cykl życia gruzu serwerowego: collision group, usypianie (kotwiczenie), fall-fracture (1 generacja), crush damage, sufity budżetu | rejestr gruzu (instancja → entry), licznik w ruchu |
| `server/StructureService` (etap 4) | graf podpór per budynek (precompute na snapshotcie), kolaps sekcji, creak warning | graf podpór, stan filarów per budynek |
| `client/ExplosionFXController` | wizualia wybuchu: błysk, fala, dym, pył, scorch decal, dźwięk | brak |
| `client/DebrisFXController` | kosmetyczne odłamki z seeda (fade ~5s), odłamki szkła, kurz przy uderzeniach | lokalne odłamki (cap per jakość grafiki) |

BombService woła `DestructionService.detonate(...)` — tak jak wołał BlastService.
Damage/knockback/ragdoll graczy ZOSTAJE w BombService (działa, nie ruszamy), ale kolejność:
**destrukcja geometrii → occlusion raycast → damage graczy** (ściana która przetrwała osłania).

Nowe Remotes: `BlastFX` (center, radius, seed — jeden event napędza całą stronę kliencką).
Etap 4 dołoży `StructureCreak`. Update listy w `Remotes.luau` + CLAUDE.md przy implementacji.

## Kategorie partów

Rozpoznawanie (w tej kolejności):
1. tag `Pillar` (CollectionService, Tag Editor) → **Filar**
2. `Material == Glass` → **Szkło**
3. descendant `Workspace.ActiveBridges` → **Most**
4. wszystko inne destructible pod `Workspace.Map` → **Ściana** (default)

Chronione bez zmian: `Locked=true`, `Workspace.Map.Locked`, `Workspace.ActiveCash`,
Terrain, party postaci. Mosty NIE są chronione (sabotaż PvP wraca).

| Kategoria | HP | Zachowanie |
|---|---|---|
| Szkło | 1 | pada od samej fali w DUŻYM promieniu (osobny `glassRadius`, ~3× promień ścian — "szyby sypią się na sąsiednich blokach"). Server: destroy part + event. Klient: brzęk + particle + 3-6 lokalnych odłamków. ZERO gruzu serwerowego |
| Ściana | ~100 | bliski wybuch niszczy (fracture → dziura), średni rani (HP attribute + rysy/pył), daleki nic |
| Filar | ~300 | wymaga 2-3 bomb. Feedback obowiązkowy: tiery pęknięć przy 33%/66% (przyciemnienie + rysy + pył) — bez tego mechanika niewidzialna i "bomba nie działa" |
| Most | ~40 | pęka na 2-4 deski z impulsem — deski lecą w lawę |

HP w `Config.Destruction.Categories`, damage bomby w `ItemDefinitions.bomb.destruction`
(`radius`, `damage`, `glassRadius`, `impulse`). Falloff po dystansie do POWIERZCHNI parta
(lekcja ze starego systemu — dystans do środka to był bug #1).

## Fala uderzeniowa (push)

Wszystko już-nieanchorowane w promieniu (gruz, bomby, deski) dostaje impuls. Matematyka
przeniesiona ze skasowanego systemu (była dobra, problem był gdzie indziej):
- stożek "na zewnątrz i w górę", kąt stromy w epicentrum → płaski na krawędzi, jitter
- nigdy w dół (floor Y)
- prędkość skalowana rozmiarem (kafel wystrzeliwuje, płyta się osuwa)
- świeże kawałki z fracture dostają impuls od razu przy spawnie

## Gruz serwerowy (DebrisService)

Sprawdzone lekcje, które ZOSTAJĄ:
- okno izolacji kolizji ~0.35s (gruz nie koliduje sam ze sobą tuż po wybuchu — inaczej
  solver zjada pęd ciasno stojącym kawałkom)
- właściwości betonu: density 3, friction wysokie, elasticity ~0.05 (bez tego "gumowe LEGO")
- `SetNetworkOwner(nil)` na każdym kawałku (exploiter nie może flingować gruzem)
- usypianie: kawałek nieruchomy przez ~0.6s → Anchored (chodliwe platformy za zero fizyki);
  kolejny wybuch budzi
- dwa przebiegi przy fracture (najpierw wszystkie joints/anchored, potem prędkości)

Nowe:
- **fall-fracture**: kawałek spadający szybko, który nagle wyhamował (delta prędkości
  między tickami skanu) → pęka na 2-3 + kurz. TWARDY LIMIT: jedna generacja, floor
  rozmiaru ~1.5-2 stud. Bez limitu liczba partów rośnie wykładniczo
- **crush damage**: skan per żywy gracz (10Hz) po liście gruzu W RUCHU: kawałek szybki
  (>~25 stud/s), duży (próg objętości), blisko i leci W gracza → dmg skalowany
  objętość×prędkość. Kawałek nosi attribute `BlastAttackerId` (kto go wystrzelił) →
  `KillService.tag(hum, attacker, "crush")` → killfeed "crushed". AntiCheat grace jak
  przy knockbacku
- małe kawałki z fall-fracture poniżej floora rozmiaru → nie spawnujemy, tylko kurz

## Sufity budżetu (Config, do strojenia z licznikiem ms)

| Gałka | Start | Po co |
|---|---|---|
| MaxServerChunksPerBlast | ~48 | jeden wybuch nie wyprodukuje więcej kawałków serwerowych (najbliższe pierwsze) |
| MaxMovingDebris | ~300 | globalny soft-cap gruzu w ruchu; MinPerBlast gwarantuje że bomba nigdy nie robi "nic" |
| MinChunkSize | ~1.5-2 stud | poniżej nie tniemy — kurz zamiast partów |
| ClientFragsPerBlast | ~60-150 | odłamki lokalne, skalowane jakością grafiki klienta |
| SmallFragLifetime | ~5s | fade odłamków klienckich |

## Kolaps sekcji (etap 4 — szkic, doprecyzujemy po etapie 1-3)

- Budynek = folder pod `Workspace.Map`. Na snapshotcie StructureService buduje graf:
  które party są NAD którym filarem (pasma Y per piętro).
- Wszystkie filary pasma martwe → sekcja powyżej: odkotwiczenie + lekki impuls → grawitacja
  robi show → standardowy cykl gruzu (izolacja/usypianie/cap). Duże party zostają fizyczne,
  drobnica → klient FX.
- Creak warning przy >50% filarów pasma: pył ze stropów + dźwięk trzeszczenia + mikro-shake.
  Telegraf + dramaturgia + clip-friendly.
- Attribution: kto dobił ostatni filar, ten dostaje credit za crushe z kolapsu.

## Kontrakt dla Kacpra (mapa w Studio) — ZMIANA zasad budowania!

1. Budynek = **folder** pod `Workspace.Map` (nazwa dowolna, np. `Tower1`).
2. Wszystko `Anchored = true`, geometria budynków ze zwykłych **Part** (prostopadłościany).
   **Union i MeshPart NIE pękają** — system je tylko pchnie/zniszczy w całości. Ozdoby
   z meshy OK, konstrukcja z Part.
3. **Ściany/stropy mogą być dużymi panelami** — kafelkowanie 6×6 już NIEPOTRZEBNE, system
   tnie w runtime tam gdzie trafi bomba. Mniej partów = lepszy baseline FPS, mniej roboty.
4. Szyby: `Material = Glass`. Nic więcej.
5. Filary/nośne: tag `Pillar` (Tag Editor). Tylko to wymaga klikania.
6. Nietykalne jak dotąd: `Locked = true` albo pod `Workspace.Map.Locked`.
7. WedgePart/CornerWedge: nie pękają (lecą w całości) — używać z głową w konstrukcji.

## Etapy implementacji (każdy = test w Play przed następnym)

1. **Rdzeń** — ✅ **ZAIMPLEMENTOWANY 2026-08-11, czeka na test w Play.**
   `Fracture.luau` + `DestructionService` (damage/HP → fracture z dziurami / launchWhole /
   ranny attribute; push z dedupe po assembly) + `DebrisService` (izolacja/usypianie/capy/
   RoundEnded cleanup) + `Remotes.BlastFX` + `ExplosionFXController` (kula ognia, fala,
   błysk, dym/iskry/embery, pył przy ziemi, ambient shake) + `DebrisFXController`
   (~150 lokalnych odłamków z seeda, próbkowane kolory otoczenia, fade ~5s).
   Limity ustawione HOJNIE (decyzja Kacpra: "dużo fragmentów, najwyżej będę hamował") —
   strojenie po teście przez Config.Destruction, nie przez logikę.
2. **Kategorie** — ✅ **ZAIMPLEMENTOWANY 2026-08-11, czeka na test w Play.**
   Szyby: Material Glass, osobny pass `glassRadius` 60 (tłuką się na sąsiednich budynkach,
   bez occlusion), server tylko niszczy — odłamki renderują klienci z payloadu BlastFX.
   Filary: tag `Pillar`, HP 300; feedback obrażeń dla WSZYSTKICH kategorii (part ciemnieje
   proporcjonalnie do utraconego HP + pył przy trafieniu). Mosty: HP 40, deski w lawę.
   Occlusion graczy: każda ściana między graczem a bombą ×0.45 dmg/knock; prawie-pełna
   osłona = brak trafienia (zero ragdolla przez 2 ściany); szkło nie osłania.
   BONUS z feedbacku etapów 1-2 ("większe party wiszą anchored po wybuchu", "wysadziłem
   dół i reszta wisi"): **pass podparcia v2** — sprawdzana pionowa KOLUMNA geometrii wokół
   epicentrum (całą wysokość wieży, nie kula), kierunkowo (sąsiad całkowicie powyżej nie
   podpiera — "wiszenie na niebie" nie istnieje, kontakt boczny podpiera). Niepodparte
   party spadają jak gruz. Kontrakt: wiszące z designu platformy → Locked / Map.Locked;
   mosty graczy nie wchodzą do sprawdzenia (wiszą z designu), tylko ich połamane kawałki.
   Structural lite; pełny kolaps sekcji po filarach = etap 4.
3. **Gruz zaawansowany** — ✅ **ZAIMPLEMENTOWANY 2026-08-12, czeka na test w Play.**
   Fall-fracture: twarde uderzenie = delta prędkości ≥55 stud/s między tickami skanu 5Hz
   (grawitacja sama robi ~39 — próg wyżej); kawałek pęka na 2-3 + pył; JEDNA generacja,
   floor objętości, cap 6/tick. Impuls drugiej bomby też robi deltę → "dobity" gruz pęka
   dalej (celowe). Crush: kawałek ≥24 stud/s i ≥8 studs³ przy kontakcie (dystans od
   powierzchni, velocity w gracza) rani 12-70 HP wg objętość×prędkość; kill credit
   "crushed" z attribute BlastAttackerId (self-crush bez creditu); grace anti-cheat;
   i-frames 0.7s; feedback = reuse BombHit (shake). Gałki: Config.Destruction.Impact.
   UWAGA testowa: Config.Lava.Enabled = false (2026-08-12) — lawa nie rośnie i nie
   zabija na czas testów destrukcji. PRZYWRÓCIĆ przed testem rund.
4. **Kolaps** — ✅ **ZAIMPLEMENTOWANY 2026-08-12, czeka na test w Play.**
   `StructureService`: budynek = folder/model pod Map, pasmo = filary o zbliżonym Y
   (klastrowanie, BandTolerance 10). Filar ginie → `notifyPillarDestroyed` PRZED Destroy.
   50% martwych filarów pasma → creak (pył ze stropów, dźwięk, mikro-shake, cooldown 4s);
   75% → KOLAPS: wszystko powyżej pasma w tym budynku odkotwiczone i oddane DebrisService
   (dalej: izolacja, usypianie, fall-fracture, crush). Cap 220 partów/kolaps.
   Próg 0.75 zamiast 1.0 CELOWO — ostatni filar w rogu trzymający wieżowiec wygląda jak bug.
   `rescan()` na init i na każdym COUNTDOWN (MapService podmienia geometrię po rundzie —
   stare referencje są martwe).
5. **Polish** — ✅ **ZAIMPLEMENTOWANY 2026-08-12** (poza assetami dźwiękowymi).
   Scorch: ciemny krąg na podłożu po wybuchu, FIFO cap 24, fade po 25s, klient-side.
   Audio: 5 slotów w `Config.Destruction.FX` (Explosion/Glass/Impact/Creak/Collapse) —
   **puste do czasu assetów Kacpra, wpisanie `rbxassetid://...` wystarczy**, wpięcie gotowe.
   Szkło gra RAZ na wybuch (nie raz na taflę); uderzenia gruzu throttlowane do 6/s
   z rozstrojeniem PlaybackSpeed (kolaps piętra = 200 lądowań naraz).
   ZOSTAJE: assety Kacpra, balans HP/promieni po testach, `Debug=false` przed launchem,
   test obciążeniowy (kilka bomb naraz + kolaps, ms/wybuch, mikroprofiler).

## Edge cases (checklist przed każdym etapem)

- Gracz dołącza w trakcie: kawałki serwerowe replikują się same; odłamki klienckie są
  efemeryczne (nowy klient ich nie widzi — OK). Dziury = stan serwera → widoczne.
- Gracz wychodzi: attribution po UserId (attribute), nie po referencji Player.
- RoundEnded: MapService restore czyści geometrię, DebrisService czyści rejestr,
  StructureService resetuje stan filarów (HP wraca ze snapshotem — za darmo).
- Dwa wybuchy w to samo miejsce w tej samej klatce: rejestr po instancji, nie po tablicy.
- Wybuch podczas restore mapy: guard na stan rundy.
- Part zniknął między przebiegami: check `Parent` przed każdą operacją.

## Ryzyka (uczciwie)

- **Burst fizyki**: 300 kawałków w ruchu + 15 ragdolli naraz — nieznane do zmierzenia.
  Mitygacja: wszystkie sufity w Config + licznik ms per wybuch od etapu 1; kręcimy gałkami,
  nie logiką.
- **Spike replikacji**: ~50-100 nowych instancji na wybuch do 15 klientów. Akceptowalne
  sporadycznie; dlatego drobnica jest kliencka. Mierzymy.
- **Kolaps worst-case** (największy budynek 8 pięter): dedykowany test w etapie 4; jeśli
  za drogo — kolaps sekcjami po pół piętra zamiast całości naraz.
- **Duży panel cięty adaptacyjnie**: target wielkości kawałka ~3-4 stud w promieniu wybuchu,
  poza promieniem większe płyty — cięcie nie może produkować 100 kawałków z jednej ściany.

---

## v3 (2026-09-23) — „serwer trzyma stan gry, klient animuje resztę” + tryby grafiki

> 🧨 **STAN: ZAIMPLEMENTOWANE, NIEPRZETESTOWANE — a Kacper na koniec sesji 23.09: „cała destrukcja
> będzie do naprawy”.** Ten rozdział opisuje KOD, nie potwierdzone działanie. Naprawę zaczynamy od
> listy usterek Kacpra i jego testu (niżej „Jak testować”), zebranych w jedną tabelę — nie od zgadywania.

### Zgłoszenie (test Kacpra na telefonach, na serwerach z kolegami)
„4 bomby w jednym momencie i lagi”, „przenikanie przez podłogę, mimo że w tym miejscu nie ma
dziury (wybuch obok → dziura w podłodze, ale ja przenikam)”, „często wyskakuje, że part jest
niezanchorowany i nie został pocięty”, „w zielonym budynku z wieszakami wszystko się rozpierdala,
znikają, bugi — lepiej jakby padały trochę chaotycznie”. Plus pomysł: dwa tryby grafiki.

### Przyczyny — ZMIERZONE na mapie w Edit (bez Play)
1. **Pass podparcia v2 zrzucał party, których wybuch nie dotknął.** Symulacja na nietkniętej mapie:
   **~3500 partów „niepodpartych” bez żadnego wybuchu** (zielony 1724 — prawie same wieszaki,
   hotel 590, szkoła 426, Sand 379, Cyan 336). Dwa powody: tolerancja „całkowicie powyżej” 0.5
   odbierała partom cieńszym niż 0.5 podparcie z boku; rzeczy WISZĄCE nie liczą się jako podparte
   przez to, na czym wiszą. Każda bomba w promieniu kolumny (~31 studów) robiła z nich gruz
   serwera, limit 260 kasował nadwyżkę natychmiast = **„wieszaki znikają”**, a każda rejestracja
   ponad limitem sortowała cały rejestr = skok CPU (`spadło=472`, `ms=80` z logu).
2. **Kawałki dziur (do 110/wybuch) były fizyką SERWERA** — każdy replikował pozycję do każdego
   gracza przez kilka sekund. 4 bomby = kilkaset ruchomych partów w łączu telefonu.
3. **Każdy ranny part dostawał serwerowy emiter pyłu** — jedna bomba w zielonym: 338 emiterów.
4. **78% partów mapy (20 376 z 26 039) to drobnica** (objętość < 4 albo bok < 2.8), a system
   traktował ją jak ściany (HP, ciemnienie, pył, gruz serwera, graf podparcia).
5. **Podłogi to wielkie pojedyncze party** (57×57×0.5, największa 7200 std²). Wybuch tnie CAŁY
   part, któremu przekroczy HP — także ten, na którym gracz stoi 40 studów dalej. v2 kasował
   oryginał i stawiał resztki jako NOWE party; pod obciążeniem kasowanie docierało do telefonu
   przed resztkami → gracz przez chwilę stał na niczym i spadał, a resztka pojawiała się nad nim.
   ⚠️ Mechanizm wywnioskowany z kodu i pomiarów, NIE zaobserwowany bezpośrednio — patrz testy.
6. **Komunikat „nie został pocięty”** = własny pocisk bomby w zasięgu (w całej mapie jest jeden
   niezanchorowany part — chroniony `Spawn`).

### Decyzje Kacpra (2026-09-23)
| Pytanie | Wybór |
|---|---|
| Jak gracz wybiera tryb grafiki | **w ustawieniach** (panel w UI) |
| Wieszaki, krzesła, skrzynie | **cały mebel pada** (blisko bomby lekko odrzucony, dalej pada chaotycznie) |
| Drobny gruz jako efekt klienta | **OK — ranią i zostają platformą tylko duże płyty** |
| Jak długo gruz leży | **Ziemniak 3 s, Pełny 20 s** |

### Architektura v3 (ownership)
| Kto | Co robi |
|---|---|
| `Fracture.planHole` (shared) | JEDEN plan dziury z seeda. Serwer bierze resztki (SCALONE po drzewie podziałów: 30.2 → 11.6 nowego parta na pocięty part), klient kawałki dziury. Sprawdzone 300 próbami: deterministyczny, objętość zachowana, zero nakładania |
| `Shockwave` (shared) | matematyka wyrzutu — ta sama dla gruzu serwera i kawałków u klienta |
| `Destructible.isSmall` / `assemblyOf` (shared) | drobnica i MEBEL (Model z samej drobnicy, ≤18 studów, ≤200 partów, bez Locked) |
| `DestructionService` | plan → graf „przed” → `BlastFX` + `DebrisFall` → zastosowanie → graf „po” (osobny wątek). Przycina pocięty part zamiast kasować. Budżet CPU 6 ms/klatkę dla wszystkich wybuchów |
| `DebrisService` | już tylko DUŻY gruz serwera (≤30/wybuch) |
| `SettingsService` | zapis trybu grafiki (`data.settings.graphics`) + atrybut gracza |
| `QualityController` (klient) | tryb: zapis → wybór w sesji → automat (telefon/konsola Ziemniak, PC Pełny); panel ustawień z kontraktu; dev: klawisz G |
| `DebrisFXController` (klient) | jedna pula lokalnego gruzu: odłamki, szkło, kawałki dziur, przejęte meble; sufity i czasy z profilu trybu. **Gruz BEZ KOLIZJI** — lądowanie i stertę liczy własnym promieniem; meble się przewracają (animacja), w Pełnym rozsypują |
| `ExplosionFXController` (klient) | cząsteczki × `ParticleScale` profilu |

Nowe remote'y: `DebrisFall` (przekazanie drobnicy: klient kopiuje i animuje, serwer kasuje po
0.25 s) i `SetGraphicsMode`. `BlastFX` niesie jedną tabelę z planami dziur (`cuts`).

### Zasady v3 (zmieniają v2)
- **Drobnica**: bez HP; próg jednorazowy `Categories.Small.HP` 80 → pęka do 12 studów; mosty
  (`Bridge.HP` 40) do 18. Najbliższa część mebla decyduje: odrzut (obrażenia ≥ `LaunchDamage` 120,
  czyli do ~6 studów, z `LaunchSpeedFactor` 0.35 impulsu bomby) albo upadek (lekki losowy ruch).
- **Konstrukcja**: jak v2 (HP, dziura z modelu obrażeń, ciemnienie — bez pyłu na serwerze).
- **Dziura**: serwer stawia resztki, klient animuje kawałki. **Oryginał parta zostaje** — przycięty
  do resztki, na której stoi najwięcej graczy; reszta resztek powstaje PRZED przycięciem.
- **Podparcie**: graf konstrukcji liczony przed i po; spada tylko to, co podparcie straciło.
  Tolerancja „nad” ≤ połowa grubości parta. Drobnica poza grafem; drobnica na tym, co znika
  (dziura, wyrzucona bryła, spadająca płyta), pada razem z tym.
- **Gruz serwera**: tylko płyty bez podparcia i bryły ≥ `PlatformMinVolume` 45 wyrzucone w całości,
  ≤ `MaxServerPiecesPerBlast` 30 na wybuch (największe pierwsze), reszta → `DebrisFall`.
  Crush i platformy działają tylko dla nich.
- 🔴 **Lokalny gruz NIE MA KOLIZJI** (poprawka tego samego wieczoru, pytanie Kacpra: „dwie osoby
  z innymi ustawieniami widzą inne party i mogą chodzić po innym gruzie”). `CanCollide`, `CanQuery`
  i `CanTouch` = false (Roblox honoruje `CanQuery = false` TYLKO przy `CanCollide = false` — z kolizją
  gruz łapał promienie klienta, w tym celownik mostu). Leci fizyką silnika bez zderzeń; odbicia,
  lądowanie płasko i stertę liczy klient promieniem, który omija postacie. Nikt nie stanie na gruzie
  i nikogo nie popchnie — tryb grafiki zmienia WYŁĄCZNIE obraz. Meble się przewracają (zakotwiczona
  animacja od wybuchu), w Pełnym potem rozsypują na części.

### Jak testować (Kacper)
1. **Zielony budynek, wieszaki**: bomba między wieszakami. Wieszaki przewracają się i rozsypują
   CAŁE (nic nie wisi w powietrzu), blisko bomby lekko odlatują. Nie znikają od razu: leżą
   3 s (Ziemniak) albo 20 s (Pełny), potem gasną. Brak skoku lagów.
2. **Dach / budynek obok, NIC nie trafione bezpośrednio**: dekoracje kilka pięter wyżej
   i dalej ZOSTAJĄ na miejscu. W v2 zrzucały je wszystkie bomby w okolicy.
3. **Przenikanie**: stań na dużej podłodze, rzuć bombę ~12-15 studów obok (dziura ma powstać,
   ale nie pod tobą). Nie wolno ci spaść. Ten sam test w Studio z opóźnieniem sieci
   (File → Studio Settings → Network → **Incoming Replication Lag** 0.3-0.5 s) i w
   Test → Clients and Servers z 2 graczami, obaj na tej samej podłodze.
4. **4 bomby naraz** (koledzy, telefon): lagi dużo mniejsze niż w teście sprzed 23.09. W logu
   `[Destr]` sprawdź `cpu=` (czysty czas serwera, cel: kilka ms) i `klatek=`.
5. **Tryby**: klawisz **G** (dev) przełącza Ziemniak ↔ Pełny — w F9 widać `[Quality] tryb
   grafiki: …`. W Ziemniaku wyraźnie mniej kawałków i mebel pada jako jedna bryła; w Pełnym
   pobojowisko zostaje ~20 s. Na telefonie bez klikania ma być Ziemniak.
6. **Komunikat „nie został pocięty”** nie pojawia się przy zwykłym rzucie.
7. **Dziury w ścianach wyglądają jak wcześniej**: wyrwa nieregularna, kawałki lecą, resztka ściany
   stoi; ściana z dziurą przy ziemi nie „wisi”, jeśli pod nią nic nie zostało.
8. **Mosty graczy**: bomba przy moście zrzuca cały most (deski lecą w lawę).
9. **Gruz przenika graczy**: w trybie Pełnym wejdź w stertę gruzu i w leżący mebel — przechodzisz
   przez nie, nic cię nie popycha ani nie podnosi. Drugi gracz na Ziemniaku nie widzi, żebyś
   „wisiał” nad podłogą. Postaw most, celując w gruz — ghost ma trafić w podłogę pod gruzem.

### Ryzyka (uczciwie)
- Kolejność „remote przed skasowaniem” zakłada, że klient dostanie `DebrisFall` przed usunięciem
  partów (0.25 s zapasu). Przy ekstremalnym lagu mebel zniknie bez animacji — gra dalej działa.
- Przycięcie oryginału chroni gracza, który stoi na resztce-oryginale. Dwóch graczy na RÓŻNYCH
  resztkach tej samej płyty: drugi dalej zależy od szybkości replikacji (mniejszej niż w v2,
  bo nowych partów jest o ~62% mniej, a gruzu serwera prawie wcale). Jeśli test 3 z dwoma
  graczami dalej przenika — kolejny krok to lokalna prognoza resztek u klienta z tego samego planu.
- Plan dziury po obu stronach liczy się z tych samych liczb, ale różne procesory mogą w skrajnych
  przypadkach dać inną ostatnią cyfrę — kawałek z samej granicy dziury poleci „z resztki”. Rzadkie
  i czysto wizualne.

---

## v4 (2026-09-24) — graf konstrukcji + plan kolapsu + budżet fizyki

> 🏗️ **STAN NA 25.09 (wieczór): A-D napisane; poprawki z 24.09 + poprawki z testu dymnego 25.09
> (niżej, „Test dymny 25.09”) CZEKAJĄ NA TEST KACPRA W PLAY; potem faza E (RiderTracker).**
> Architektura uzgodniona w debacie Claude ↔ drugi czat
> 23-24.09 (decyzje Kacpra niżej). ⚠️ Liczby P0 poniżej sprzed `BakeVersion` 2 — od kiedy szkło jest
> pasażerem, doczepionych jest **193 (w tym 18 szyb)**, nie 175.
> **Faza P0 — `StructureBake` NAPISANY i sprawdzony na OrangeBuilding w Edit (24.09, odczyt, bez Play):**
> `src/server/Structure/StructureBake.luau` + `STRUCTURE_BAKE.luau` (Command Bar) + `Config.Structure`.
> Wynik: 278 partów → 228 chunków, 1131 interfejsów, 175 listew doczepionych (0 bez właściciela),
> 158 nachodzących par; **nietknięty budynek stoi (0 spadających)**; jeden / dwa / wszystkie 6 słupów
> podcięte przy ziemi → 0 spada (trzymają filarki); cały parter pod wieżą → spada 111 ze 113 chunków
> wieży; cały parter → 175 (pełna kaskada); zachłanny szacunek: **~6 bomb** (cel ~8); jeden solve
> 0,03-0,25 ms, analiza 11-15 ms. **Podgląd kolorami obejrzany przez Kacpra 24.09: „wszystko git”**
> (cały budynek zielony; ramy okien, drabina i klocki to listwy/ozdoby — od tej poprawki rysowane
> na jasnoniebiesko, wcześniej wyglądały na „wycięte”). Zapis danych (TRYB 3) celowo NIE uruchomiony:
> dane potrzebne dopiero runtime'owi (faza B/C), a każda zmiana reguł bake'u i tak wymusi ponowny zapis.
>
> **Fazy B/C — NAPISANE i sprawdzone offline na OrangeBuilding (24.09, Edit, obliczenia, bez Play):**
> `StructureCore` (wspólne: klasyfikacja, solver, odcisk), `BuildingState` (stan budynku: dziury
> zwężają interfejsy i przecinają przekroje, osłabianie SUMUJE się — decyzja Kacpra 24.09, CAS,
> rewizja, przyczyna, jeden flush na paczkę wybuchów), `CollapsePlanner` (grupy kolapsu),
> `Fracture.planWindow` (dziura-prostokąt), `StructureTests` + `STRUCTURE_TEST.luau`. Wyniki:
> nietknięty stoi ✅ · dziura w stropie nic nie zrzuca ✅ · słup: 1. bomba obok osłabia (93 obr.),
> 2. kruszy ✅ · bomby w parter: wieża leży po **6** (cel ~8) ✅ · 2 bomby w jednej klatce = ten
> sam wynik co po kolei ✅ · bomba w spadającą grupę nic nie zmienia ✅ · ostatni kolaps: 5 grup,
> największa 13 chunków / rzut 39, przyczyna = ostatni zamachowiec + 4 asysty · całość 276 ms.
> ⚠️ Do oceny w Play: 3 bomby w rzędzie na stropie (~21 studów od siebie) sumą osłabień kruszą
> 27 nośnych elementów między nimi i zrzucają 6 chunków (same dziury: 8 przeciętych belek, nic
> nie spada) — gałka `Config.Structure.Damage.StructuralPowerFactor` / `HP`.
>
> **Faza D — NAPISANA 24.09, CZEKA NA TEST KACPRA W PLAY** (kompiluje się, dojechała do Studio;
> geometria wykonawcy sprawdzona offline: odejmowanie pudełek bez straty objętości, pełny kolaps
> wieży = 21 grup, 48 kawałków w locie, max 7 w grupie, 17 nowych instancji z podziału).
> OrangeBuilding idzie w grze ścieżką v4, reszta mapy dalej v3:
> `StructuralService` (stan + kawałki + dziury-prostokąty; dane liczone przy starcie rundy, gdy nie
> ma zapisanych — `Config.Structure.AnalyzeIfMissing`), `CollapseService` (budżet, kolejka od jeźdźców,
> podział kawałków po granicy grupy, spawanie, NoCollision dla nachodzących par, fizyka serwera,
> osiadanie → platforma do końca rundy / małe znikają po 4 s, lawa, przygniecenie przez
> `DebrisService.applyCrush`, kruszenie osłabionych, budzenie leżących brył wybuchem), `Pieces`
> (geometria kawałków), klient: kawałki dziury wypełniają prostokąt (`win`). Martwy `StructureService`
> i `Config.Destruction.Collapse` USUNIĘTE.
> **Test Kacpra 24.09 + poprawki (przyczyny zmierzone, poprawki NIEPRZETESTOWANE w Play):**
> | Zgłoszenie | Przyczyna | Poprawka |
> |---|---|---|
> | górne piętra „za szybko”, na 3. piętrze nie ma ścian | log `[Collapse]`: kolaps wieży = 25 grup, **16 ponad budżetem** → oddane klientom → serwer je kasował, u gracza znikały. Solver NIE był winny (symulacja: piony 3. piętra padają dopiero przy ~93% zniszczonego parteru) | `MaxCost` 60 → 100; grupa bez budżetu CZEKA w kolejce do `MaxQueueWait` 1,5 s (grupy osiadają w ~1 s), kolejka od dołu = piętra wyżej spadają po niższych |
> | szyby lewitują | bake pomijał szkło — nie było pasażerem ściany | szkło = pasażer (`StructureCore.classify` → Trim), `BakeVersion` 2 |
> | przenikalne party lewitują | gruz KLIENTA lądował promieniem na RUCHOMEJ bryle kolapsu albo leżał na stropie, który potem spadł; listwy skruszonego elementu zostawały | klient: lądowanie ignoruje ruchome party, sterta tylko nad podłożem, leżący gruz i meble sprawdzają podłoże (`FX.RestChecksPerFrame`) i spadają dalej; serwer: listwy/szyby skruszonego elementu i nad dziurą v4 spadają |
> | pudła, szafki „pobugowane” | 1474 duże party dekoracji szły ścieżką ścian (poszarpane dziury), drobne części tego samego mebla odpadały osobno | REKWIZYTY (`Destructible.propOf`, `Config.Destruction.Props`): wszystko w `Decorations` pada W CAŁOŚCI (najwyższy Model ≤ 24 studów); 18 316 partów w 1021 meblach, poza regułą 65 (dywany, płoty, szyny drabin) |
>
>
> **Test dymny 25.09 (Claude przez MCP, za zgodą Kacpra — obserwacja, nie werdykt).** Seria 6 bomb
> z zachłannego planu bake'u (te same punkty co `STRUCTURE_TEST` S6: pocisk z `ThrowBomb` klienta
> przestawiany na serwerze w punkt i kotwiczony), postać na dachu wieży, na serwerze rejestrator:
> każda odkotwiczona bryła OrangeBuilding — Y korzenia przy starcie i przy osiadaniu — plus stopy
> gracza i to, co pod nimi. Liczba grup na bombę zgodna z symulacją w Edit (2, 2, 2, 4, 6, 5).
> | Przebieg | Zmiana | Spadło fizyką | Zaklinowane | Uwagi |
> |---|---|---|---|---|
> | 1-2 | (stan z 24.09) | **4 z 25** | 21 osiadło W MIEJSCU po 0,7 s | wieża stała nad zburzonym parterem, dach pod graczem odkotwiczony 0,8 s, ruch 0,06 studa |
> | 5 | filtr fragmentów + przeciążenie + siatka | 7 | 12 → klienci | log podpór za zgrubny |
> | 6 | + kikuty + filtr styku z boku | 13 | 10 → klienci | dach z graczem zjechał 7 studów i został platformą; jazda na stropie 20 studów, do 47 stud/s |
> | 7 | + natychmiastowe zdjęcie kolizji przy przekazaniu + przygniecenie względne | **14 z 24** | 9 → klienci, 1 w miejscu | przygniecenie 49 dmg — prawidłowe (grupa spadła na stojącego gracza) |
> Przyczyny zmierzone (rejestrator + symulacja w Edit + log `[Collapse] … ZAKLINOWANA … trzyma:`):
> - **fragment skruszonego elementu** wyrzucany BEZ filtra nachodzeń klinował się w słupie/stropie,
>   DebrisService usypiał go w miejscu, a to, co przez skruszenie straciło podparcie, leżało na nim
>   (symulacja: 11 z 21 grup leży na skruszonym) → `filterOverlaps` wspólny dla grup i fragmentów;
> - **kikuty przeciętych chunków** (dziura ~18 w chunku ~20-22: solver `Severed`, a pasy nad i pod
>   dziurą zostają zakotwiczone) — na takim kikucie wisiał m.in. dach → kikut INNEGO parta, którego
>   styk z grupą leży w zniszczonym chunku, leci z grupą (decyzja Kacpra: „spadają z tym, co trzymają”);
> - **pion na stojącym poziomie** spadający tylko przez dziedziczenie zasięgu → PRZECIĄŻENIE w solverze:
>   poziom pod takim pionem pęka (decyzja Kacpra; scenariusze S1-S8 bez zmian, szacunek dalej 6 bomb);
> - **tarcie z boku**: sąsiad nachodzący o setne studa trzymał grupę → styk z boku filtrowany zawsze;
> - **kolizja przekazywanych kawałków przez 0,25 s** (opóźnienie kasowania v3) → zdejmowana od razu;
> - **przygniecenie jeźdźca przez własną bryłę** (59 dmg: kikut nad HRP „leciał na niego”) → prędkość
>   WZGLĘDNA gracz ↔ kawałek.
> **Siatka bezpieczeństwa** (decyzja Kacpra): grupa, która po `JamCheckTime` 0,4 s przesunęła się
> < 1 stud i obróciła < 3°, idzie do klientów (kolizja od razu), pozostałe czekające dostają nowe okno;
> log mówi, co ją trzymało (część v4 + STAN chunka). **Zostało (przebieg 7)**: 3 × fragment kruszenia
> dalej pod grupą, 2 × „nic pod spodem” (bomba 1 — przyczyna nieustalona), 2 × kikut własnego parta
> grupy (przypadek brzegowy `takePieces`), 1 × stojący strop (pas ściany zaczynający się w grubości
> stropu), 1 × prawidłowe rumowisko pod spodem. Tory `OutsideDecorations.Railway` wchodzą w strop
> OrangeBuilding na Y 54 i też potrafią trzymać bryłę.
> Jeździec w Studio: szczelina stopy ↔ bryła na serwerze 0,3-2 studa przy 20-47 stud/s, bez ragdolla
> w locie i bez obrażeń z upadku — opóźnienie na prawdziwym serwerze będzie większe (faza E/G).
>
> **Test Kacpra 25.09 (po teście dymnym) — zgłoszenia, przyczyny, decyzje:**
> | Zgłoszenie | Przyczyna (zmierzona) | Decyzja / stan |
> |---|---|---|
> | „na niektórych partach jak stoję, przesuwają mnie jak na taśmie” | zakotwiczony part ZACHOWUJE prędkość (pomiar na silniku: po 0,5 s dalej 1,2 stud/s i 0,6 rad/s); rumowisko kotwiczone przy < 1,5 stud/s, gruz usypiany tak samo = taśmociąg | ✅ `Utils.anchorAtRest` (zeruje obie prędkości) w `CollapseService.settle`/`jam` i usypianiu `DebrisService` — test dymny: 47 osiadłych kawałków, prędkość 0,000 |
> | „rzucam bombę, a party już się nie rozwalają na mniejsze” — **leżące po zawaleniu** | leżące bryły v4 (`rubbleOf`) i gruz serwera NIGDY nie są cięte — wybuch tylko budzi i pcha (duże bryły ledwo drgną) | **bomba tnie leżącą bryłę jak ścianę** — ✅ `CollapseService.cutRubble` (test dymny: 3 bomby w rumowisko → 5, 6, 4 przecięte kawałki, 8-13 ms CPU, zero błędów). ⚠️ Gruz `DebrisService` (fragmenty kruszenia, v3) dalej tylko pchany |
> | drabina: „przy bombie te po bokach odpadają, a środek (szczeble) zostaje zbugowany” | szyna (1×66×1) to listwa → łamana jak drobnica → oddawana klientom W CAŁOŚCI; szczeble dotykają tylko szyn i nic nie sprawdza, czy po zniknięciu szyn mają na czym wisieć. Do tego bake doczepia CAŁĄ drabinę (2 szyny + 30 z 32 szczebli) do jednego kawałka stropu 3. piętra (ch181), bo szyny przez niego przechodzą, a szczeble dziedziczą właściciela po szynach | wymaganie Kacpra: **„naruszone party mają spadać”** — nic nie wisi. DO ZROBIENIA (plan niżej) |
> | „skoro part i tak nie ma kolizji, to go posiekaj, a nie takie duże kloce, przez które da się przechodzić” + „zmień kolor na ciemny szary, żeby było widać, że to debris” | przekazany klientom POJEDYNCZY duży part (zaklinowany strop 22×33, szyna 66, grupa ponad budżetem) leciał jednym klocem bez kolizji i leżał 3-20 s | ✅ `DebrisFXController.spawnFall` siecze part dłuższy niż `FX.HandoffSliceAbove` (4) na kawałki `Fracture.TargetChunkSize` (w budżecie trybu); cały lokalny gruz budynku (kawałki dziur, posiekane bryły, odłamki) ciemnoszary `FX.LocalDebrisColor` z rozrzutem jasności; meble i szkło bez zmian. Test: 0 błędów, szczyt 1698 kawałków w Pełnym (limit 2000) |
| „usuń te wibracje przy niszczeniu filarów” | trzęsienie kamery `StructureFX "collapse"` — v4 wysyła je przy KAŻDEJ spadającej grupie | ✅ `FX.CollapseShakeMax` / `CreakShakeMax` = 0 (pył i dźwięk zostają, wstrząs od wybuchu też) |
| „party się bugują” = wiszą chwilę, potem znikają | siatka zaklinowania. Nowy log (`holdersOf`: KAŻDY styk bez filtra — POD/NAD/BOK z głębokością, rodzaj chunków grupy) pokazał: 4 z 11 zaklinowań = filarek leżący na FRAGMENCIE skruszonej ściany pod sobą (fragment miał filtr tylko z tym, na co nachodził, i startował w górę) | ✅ `filterContacts`: fragment kruszenia bez kolizji ze wszystkim, czego dotyka przy starcie → **zaklinowań 11 → 4** (19 z 21 grup osiada fizyką). Zostały: 2 × filarek na krawędzi sąsiedniego, CAŁEGO kawałka przeciętej belki (hipoteza: styk węższy niż `MinInterfaceWidth` — solver nie liczy go jako podpory, fizyka tak; do zmierzenia szerokości styku), 1 × bryła w szczelinie 0,02-0,03 między stojącymi stropami (przyczyna niepewna), 1 × bryła na wcześniejszym rumowisku (prawidłowe) |
| (decyzja Kacpra 25.09) odrzut obudzonego rumowiska | obudzona bryła leciała 72 stud/s na 45 studów i zabijała | ✅ `Collapse.WakeImpulseFactor` 0,3 |
>
> **Zrobione 25.09 (wieczór): cięcie rumowiska** — `CollapseService.cutRubble` (ta sama dziura-prostokąt i próg co konstrukcja, payload `cuts` z `win`, oryginał zostaje resztką pod graczami — `Pieces.pickReuse`, wspólne ze `StructuralService`; potem spawy grupy od nowa — `reweld`, i zwykłe `wakeRubble`). Log `[Destr] … rumowisko cięte=N`.
> **Obserwacja z testu dymnego (nie zgłoszona przez Kacpra, do decyzji)**: obudzona leżąca bryła (4:23) przeleciała ~45 studów z prędkością 72 stud/s i zabiła gracza przygnieceniem — impuls fali dla obudzonego rumowiska jest za duży jak na ciężkie płyty („latające płyty”).
> **26.09 (test Kacpra z kolegą, dotyczy destrukcji)**: „czasem bomba kolegi nic mi nie robi, 0 ragdolla, 0 dmg” — przyczyna NIEUSTALONA. Jedna z możliwych: wyjątek w `DestructionService.detonate` zjadał obrażenia graczy (były liczone PO destrukcji, bez zabezpieczenia) → `BombService` woła destrukcję w `xpcall` i drukuje `[Bomb] BŁĄD destrukcji …` ze śladem; druga: osłona — leżące rumowisko v4 (od 25.09 jest go więcej i jest cięte) liczy się w `computeOcclusion` jak ściana (×0,45 za bryłę, poniżej `MinEffect` 0,05 = brak trafienia) → log `[Bomb] … miss — <gracz> … osłonięty (occ=…)`. Rozstrzygnie log z następnego testu. W teście 26.09 wieczorem objaw się NIE powtórzył (Kacper: wszystkie testy pomyślnie) — przyczyna dalej nieustalona, log `[Bomb] … miss` zostaje na wypadek powrotu. Faza F (26.09): 5 wybuchów wytrzymuje, także na serwerze.
>
> **Plan na następną sesję (przed kodem: szczegóły + ewentualne pytania):**
> 1. Fragmenty kruszenia v4 są dziś gruzem `DebrisService` (tylko pchane, osobny budżet) — przenieść do `CollapseService`, żeby też się cięły.
> 2. **Drabina / długie listwy** — (a) bake: listwa w łańcuchu dostaje właściciela z NAJBLIŻSZEGO chunka, nie z pierwszego ogniwa (drabina rozłożona na piętra); (b) listwa dłuższa niż chunk trafiona bombą → wycinany odcinek, nie cała; (c) po zabraniu listwy — listwy, które straciły ostatni styk, spadają (łańcuch, „nic nie wisi”).
> 3. Potem faza E (RiderTracker) — od 26.09 BEZ własnych obrażeń jeźdźca (decyzja Kacpra: zwykły fall damage; przygniecenie od bryły pod graczem wyłączone w `CollapseService.crushCheck` → `isUnder`). Zostaje grace anty-cheata, jeśli test pokaże, że jazda go wyzwala.
>
> **Listwy i drabina (26.09) — decyzje Kacpra, pomiar, plan (spisany PRZED kodem; realizuje punkt 2 wyżej):**
> - **Decyzje**: (1) bomba w długą listwę wycina **tylko trafiony odcinek**; (2) listwa **zostaje, póki dotyka czegoś stojącego** — konstrukcji albo listwy, która sama się trzyma; traci ostatnie oparcie → spada. To zastępuje punkt 2a (właściciel z najbliższego chunka) — o spadaniu listwy decyduje oparcie, nie właściciel.
> - **Pomiar (Edit, OrangeBuilding)**: 296 partów, 193 listwy/ozdoby, 583 styki z udziałem listwy; PEŁNY pass podparcia listew = **0,15 ms** — można go puszczać po każdym wybuchu i każdym kolapsie bez optymalizacji. Szyny drabiny (#12, #17, 1×66×1, Y 9–75) dotykają TYLKO dwóch stropów (Y 30 i Y 52) + 33 szczebli 6×1×1 (każdy dotyka obu szyn); bake doczepia całą drabinę do ch181 (strop Y 52).
> - **Dlaczego dziś wisi / spada za dużo**: listwa spada trzema drogami i żadna nie pyta o pozostałe oparcia — trafienie (cała listwa do klientów), kruszenie/kolaps właściciela (wszystkie listwy chunka), `dropResting` (każda listwa dotykająca spadającego kawałka, w całości). Szczebli nie zrzuca nic, bo ich właścicielem jest strop, a nie szyna.
> - **Model**:
>   - bake: `TrimLinks` — pary stykających się partów, z których co najmniej jeden nie jest konstrukcją (te same styki co `attach`); `BakeVersion` 3.
>   - `StructuralService.takeUnsupportedStrips(rec)` — BFS po DZISIEJSZYCH kawałkach (pudełka z luzem `ContactPadding`): start = kawałki listew dotykające kawałka konstrukcji, dalej przez styki listwa↔listwa. Niepodparte → zwolnione z budynku i zwrócone. Listwa niepodparta już w NIETKNIĘTYM budynku (projekt) nigdy nie spada z tego passu — ⛔ „zrzucanie niepodpartych bez porównania przed/po”.
>   - `StructuralService.cutStrip` — listwa, która nie jest drobnicą (`Part`, kształt Block, nie szkło): odcinek wzdłuż najdłuższej osi, na którym obrażenia ≥ próg drobnicy — półdługość √(R² − d⊥²), R = promień × (1 − próg / obrażenia), d⊥ = odległość epicentrum od listwy w przekroju; końcówka krótsza niż `Damage.MinStrip` idzie z odcinkiem. Resztki zostają (oryginał tam, gdzie stoją gracze — `Pieces.pickReuse`), odcinek → klienci. Drobnica i reszta ozdób (szkło poza passem szyb, MeshPart, klin) — w całości, jak dziś. Mebel z drobnych części dalej pada cały: `assemblyOf` zwraca model tylko, gdy WSZYSTKIE jego party są drobnicą.
>   - Kolejność w wybuchu: dziury v4 → cięcia listew → drobnica (zwalnia swoje kawałki z budynku OD RAZU, żeby do skasowania nie liczyła się jako oparcie) → pass podparcia → klienci (`force`, bez odrzutu). `looseUnit` pomija listwy v4 — decyduje o nich pass (dotyczy też `dropResting`).
>   - `CollapseService`: kruszenie → pass zamiast `attachmentsOf`; start grupy → pass: niepodparte listwy z `followers` grupy lecą z nią (spawane), pozostałe niepodparte → klienci.
> - **Ograniczenie (świadome)**: listwa dotykająca wyłącznie geometrii spoza budynku v4 jest „niepodparta w projekcie” — pass jej nie zrzuci.
> - **✅ Zrobione 26.09 (wieczór) i POTWIERDZONE przez Kacpra w Play tego samego wieczoru („wszystkie testy pomyślnie poszły”).** Kod: `StructureBake` (`TrimLinks`, `BakeVersion` 3), `StructuralService` (`cutStrip`, `isCuttableStrip`, `takeUnsupportedStrips(Near)`, `releaseInstance`; `attachmentsOf` usunięty), `DestructionService` (`stripHits` → cięcie po dziurach v4, pass po drobnicy, `looseUnit` pomija party v4; log `[Destr] … listwy cięte=N bez oparcia=N`), `CollapseService` (`crumble`, `takeFollowers` → `ride`/`drop`). **Sprawdzenie offline** (kopia budynku BEZ rodzica, prawdziwy kod ze Studio, mapa nietknięta, bez Play): start — 0 niepodpartych, 0 „wiszących w projekcie”, pass 0,34 ms; bomba Y 41 (R 7) → z szyn wycięte 35,7-46,3 i 34,2-47,8, 7 szczebli w całości, pass nic nie zrzuca (dół na stropie Y 30, góra na Y 52); bomba Y 64 → spadają czubki szyn 69-75 i jedyny wiszący na nich szczebel; bez stropu Y 52 → nic nie spada; bez obu stropów → obie szyny + 32 szczeble. Uwaga: szczebel 6×1×1 NIE jest drobnicą (`isSmall` = false), więc też jest cięty — przy bombie z boku może zostać krótki kikut szczebla przy jednej szynie (to „tylko trafiony odcinek”).
> - **Test dla Kacpra**: (1) bomba w dół drabiny → odpada trafiony odcinek szyn i szczeble w nim, reszta drabiny stoi; (2) bomba w środek (między Y 31 a Y 52) → dół zostaje na stropie Y 30, góra na Y 52, spadają szczeble z przerwy; (3) bomba nad stropem Y 52 → odcięta góra szyn spada razem ze swoimi szczeblami; (4) zburzony strop Y 52 → drabina stoi na stropie Y 30; zburzone oba → spada cała, żaden szczebel nie wisi; (5) długa listwa trafiona przy końcu → odpada tylko koniec; (6) regresja: ramy okien i szyby spadają ze swoją ścianą, meble ze spadającego stropu dalej spadają.
>
> **Migracja GreenBuildingu + tory (26.09 noc) — pomiar, decyzje Kacpra, plan (spisany PRZED kodem):**
> - **Pomiar (Edit, kopie budynków)**: GreenBuilding 685 partów (Building; 2972 w Decorations/Lights = rekwizyty), analiza 19 ms. Nietknięty budynek NIE STOI: **250 z 284 chunków czerwonych** — piętra leżą na belkach krawędziowych **1×2**, a klasyfikacja bierze je za listwy (`TrimMaxWidth` = 2 włącznie). Próg 1,9 → 15/400 czerwonych; ten sam próg globalnie psuje OrangeBuilding (0 → 4 czerwone). Pozostałe 15 = **tunel torów**: tory (`OutsideDecorations.Railway`, 132 party, szyny 437,5 studa wzdłuż X na Z −133 i −145,5, Y ≈ 54,5 — NIE `Locked`, dziś cięte przez v3) przechodzą przez GreenBuilding i OrangeBuilding; w GreenBuildingu leżą na belkach tunelu, które niczego z konstrukcji nie dotykają; w OrangeBuildingu na stropie 23,5×1×59. Odrzucone: „każda listwa niosąca konstrukcję → belka” (wciąga setki prętów 0,5×0,5 i robi je czerwonymi); „pilastry 1×1×91 → słupy” (13 czerwonych zostaje).
> - **Decyzje Kacpra**: próg listwy **osobno dla budynku** (GreenBuilding 1,9, OrangeBuilding bez zmian); tunel torów **spada z budynkiem** (jak listwy); w OrangeBuildingu strop pod torami dalej zniszczalny, a **kawałek torów nad budynkiem ma spaść razem z nim — „tylko ten kawałek torów, nie całe”** (to samo w GreenBuildingu).
> - **Model**:
>   - `Config.Structure.Buildings[id]` = `true` albo tabela: `TrimMaxWidth`, `DemoteUnsupported`, `Guests`. `StructureCore.buildingConfig` — jedno miejsce nakładania ustawień (bake i gra).
>   - `DemoteUnsupported` (bake): element konstrukcji czerwony w NIETKNIĘTYM budynku → listwa; analiza od nowa (poziomy, chunki, interfejsy), aż nic nie jest czerwone (max 5 przebiegów); lista w `Demoted` (dane + raport). Odcisk geometrii liczony PRZED degradacją — to odcisk mapy, nie klasyfikacji; gra nakłada `Demoted` na zapisane dane.
>   - `Guests` (tylko gra, `StructuralService.rebuild`): party wskazanych folderów w obrysie budynku stają się jego listwami (`Trim`, styki z budynkiem liczone na pudełkach). Part wystający poza obrys (szyna) dzielony na granicy — środek jest gościem, końce zostają poza v4. Dzielenie idempotentne: `StructuralService.init` rusza przed `MapService.init`, więc migawka mapy ma już podzielone szyny. Tor dzielony między dwa budynki: drugi zastaje część pierwszego jako `owners` i ją pomija.
> - **✅ Zrobione 26.09 (noc), NIEPRZETESTOWANE w Play.** Kod: `Config.Structure.Buildings` (tabele), `StructureCore.buildingConfig`, `StructureBake.analyze` (próg budynku, pętla degradacji, `Demoted` w danych i raporcie, odcisk przed degradacją), `StructuralService` (`spanInside`, `addGuests`, `Demoted` z zapisanych danych, log `[Structure] … +N gości, M zdegradowanych … wiszących w projekcie K`). **Sprawdzenie offline** (kopie obu budynków i torów bez rodzica, świeży klon `Config` — hard rule 14, mapa nietknięta): rebuild obu 34 ms; szyny 132 → 148 partów, środki dokładnie w obrysach; **drugi rebuild 148 → 148** (idempotencja); oba budynki: kolaps WŁ, 0 wiszących w projekcie; OrangeBuilding 14 gości, GreenBuilding 12; zburzony strop pod torami w Orange → spada 14 kawałków torów i nic więcej; Green bez konstrukcji od Y 40 → tunel z torami zostaje (wisi na pilastrach opartych niżej — reguła „póki dotyka czegoś stojącego”); Green bez całej konstrukcji → spada 12 kawałków torów. **Dwa błędy złapane przez ten test PRZED grą**: (a) pass podparcia miał własną, ciaśniejszą definicję styku (szczelina ≤ 1 × luz) niż bake (`Core.intersect`, ≤ 2 × luz) — podkłady leżą 0,2 nad belkami i wszystkie wyszły „wiszące w projekcie”; teraz pass bierze `Core.intersect`; (b) oś +Z parta to −LookVector — z LookVector szyna była cięta w lustrzanym miejscu (środek poza budynkiem), co psuło też idempotencję.
> - **Test dla Kacpra**: (1) GreenBuilding w ogóle stoi i się wali (bomby w parter → piętra spadają, meble i wieszaki padają w całości); (2) zburz strop pod torami w OrangeBuildingu → spada kawałek torów nad budynkiem, tory poza budynkiem zostają; (3) to samo w GreenBuildingu (tunel + kawałek torów); (4) bomba w tory w budynku → wycięty odcinek, jak listwa; (5) OrangeBuilding poza torami bez zmian.
>
> **Auta (27.09 wieczór) — zgłoszenie, przyczyna, decyzja Kacpra, zmiany:** „napraw, żeby auta wybuchały, bo teraz nie reagują”. **Przyczyna**: 8 aut `OutsideDecorations.Cars.Car1` (98 partów, bbox 10×7×20, 72 części to drobnica) ma WSZYSTKIE party `Locked` = kontrakt „wybuch nie tyka” (`Destructible.isProtected`) — bomba pomijała je w całości; samo zdjęcie blokady rozsypałoby auto na drobne części (za duże na rekwizyt). **Decyzja Kacpra: „wybucha + ogień”.** **Zmiany**: `Destructible.carOf` (model = dziecko folderu z `Cars.Folders`, bez sprawdzania Locked); `DestructionService` zbiera auta PRZED ochroną (najbliższa część), auto w zasięgu DZIURY → `CarService.ignite` (log `[Destr] … auta=N`); `CarService` (NOWY): każde auto raz, razem z bombą (`Cars.Delay` 0 — pierwsza wersja 0,35 s: Kacper „wygląda jak bug”; klatkę później przez task.delay) — rozpad u klientów (`DestructionService.shatterToClients` → lista `shatter`), `Remotes.CarFire` (płonący wrak `Cars.FireTime` 6 s — płomienie, dym, światło; SAM efekt, nie rani i nie rozprzestrzenia się: pożary jako mechanika są poza v1.0), wybuch przez `BombService.explodeAt` (NOWE API: ta sama ścieżka co bomba — destrukcja przed obrażeniami, xpcall; `Cars.Blast`: gracze r 16 / 40% HP / odrzut 380, otoczenie r 18 / dmg 130 → dziura ~4 studa, więc łańcuch tylko dla aut tuż obok); wybuch i rozpad wstrzyknięte w init.server (cykl BombService → DestructionService → CarService). Sprawdzone w Studio: 8 plików dojechało i się kompiluje, rozpoznane 8 aut (784 party), `CarStand` z OrangeBuilding to nie auto. **Test**: (1) bomba przy aucie → auto wybucha razem z nią, rozlatuje się, płonie ~6 s; (2) gracz obok auta dostaje obrażenia i odrzut, kill dla rzucającego; (3) dwa auta obok siebie → łańcuch; (4) auto dalej niż zasięg dziury → nic; (5) ogień nie rani.
>
> **SandBuilding — CAŁE MIASTO NA v4 (27.09):** czerwony był ŚRODEK stropu 44×0,5×73 (chunk 14,7×18,2), nie róg: najkrótsza droga do pionu przez sąsiednie pola 25,8 > `MaxSpan.Slab` 24 (brak 1,8 studa). Ustawienia budynku: `TrimMaxThickness` 0,4 (ściany 0,5 niosą), `TrimMaxWidth` 1,9, `MaxSpan = { Slab = 27 }` → 0 czerwonych bez degradacji (~20 listew → belki), szacunek 8 bomb (cel ~8). `StructureCore.buildingConfig` nakłada też `TrimMaxThickness` i `MaxSpan`; **solver w grze (`BuildingState`) dostaje ustawienia budynku** — inaczej liczyłby ogólnym 24 i budynek, który w bake'u stoi, w grze miałby czerwone chunki; raport `stress` też. Sprawdzone offline (kopie wszystkich 10 budynków + tory, prawdziwy `rebuild`): wszystkie stoją w solverze gry, kolaps WŁ, 0 czerwonych na starcie, 0 wiszących w projekcie; rebuild 179 ms w 9 klatkach. W Play nieprzetestowane. **v3 zostaje już tylko poza budynkami** (ulice, tory poza budynkami, samochody, latarnie).
>
> **Migracja — druga tura (27.09):** decyzja Kacpra: „reszta budynków na v4”. Pomiar pokazał, że degradacja nie zawsze dotyczy drobiazgów: w SandBuildingu zrobiłaby listwę z CAŁYCH stropów 44×0,5×73 i 44×0,5×64 (każdy ma 1 czerwony róg z 12 chunków — róg oparty o element 0,5×3×44, który przy progu grubości 0,6 jest listwą), w OldBuilding1 z progiem 1,9 — ze stropu 32×30 (bez progu tylko 5 paneli 1×6×3). Strop-listwa nie spada fizyką, tylko znika spod nóg jako gruz u klientów. **Przeniesione**: PurpleSchool (1,9 + degradacja: ozdobne słupki na dachu 4×18×4 / 4×14×4 z czapkami, 2 klocki), OldBuilding1 (degradacja 5 paneli), Construction (1 element 7×3×1), PupleHotel (8 paneli, 2 belki 8×1×13). **SandBuilding czeka**: nawet z progami 0,4 (grubość) i 1,9 (szerokość) zostaje 1 czerwony róg stropu 44×0,5×73 — do zbadania, dlaczego (MaxSpan? wspornik?), zanim degradacja zrobi listwę z całego stropu. Rekwizyty (decyzja Kacpra): znikają + drobiazgi (ToiletPapers, Products, Paintings, Mirrors), dywany (Carpets), beczki (Barrels); spójnie z wcześniejszymi — TVs/Tvs, TrashBin, Painting, Carpet; drzwi zostają meblami. Rebuild rozłożony na klatki (1 budynek na klatkę, do ~34 ms) — dziewięć budynków w jednej klatce to ~150 ms przycięcia.
>
> **Ciemny gruz (27.09) — zgłoszenie, przyczyny z logu, zmiany:** Kacper po teście: „za bardzo się sypią z całego parta, mimo że nie powinny taki zasięg i tak padać”, „przy niedużym parcie powstaje z niego za dużo odpadu”. **Log sesji (CyanOffice)**: (1) grupy `Block×1, kawałków 1` — panele 3×6×1 i 1×6×3 stojące na belce tuż nad fundamentem — po zniszczeniu belki opadały o < `JamMinMove` na `Map.Locked.Foundation`, siatka uznawała je za ZAKLINOWANE i oddawała klientom do posiekania, choć po prostu wylądowały (jedyny styk: `POD Workspace.Map.Locked.Foundation`); (2) liczba kawałków zależała tylko od `Fracture.TargetChunkSize` (3,2): klocek 8×8×8 → ~27, strop 22×33 → 48 (`MaxChunksPerPart`). **Zmiany**: `CollapseService.groundUnder` — grupa, która nie ruszyła, ale LEŻY pod spodem na czymś pewnym (geometria mapy spoza v4, teren, osiadłe rumowisko, uśpiony gruz), osiada zamiast iść do klientów (log `wylądowała … na:`); u klienta `pieceCap` — ~1 kawałek na `FX.DebrisPieceVolume` (12) studów³, najwyżej `FX.DebrisMaxPieces` (16) na bryłę albo dziurę v4 (duża bryła → większe kawałki); dziury v3 bez zmian (serwer liczy je tym samym ziarnem). Zgodność z 25.09 („posiekaj duże kloce”): duże przekazane party dalej są siekane, tylko na mniej, większych kawałków. NIEPRZETESTOWANE w Play. Test: (1) zburz belkę pod panelem w CyanOffice → panel osiada (małe znikają po 4 s jak dotąd), nie sypie się; (2) dziura w ścianie i zaklinowany strop → wyraźnie mniej, większych kawałków; (3) mały part → 1-3 kawałki.
>
> **Leżący gruz (27.09 wieczór)**: Kacper — „jak party odpadną, zawsze stoją góra do góry, dziwne, spiczaste, na całej mapie — zmień, losowo albo coś”. Przyczyna: `DebrisFXController.land` obracał kawałek do normalnej osią NAJBLIŻSZĄ normalnej (najmniejszy obrót), a odłamki ze ścian lecą zwykle pionowo — lądowały na sztorc. Teraz ściana, na której kawałek leży, jest losowana z wagą (pole ściany)^`FX.RestFaceExponent` (3; jak w prawdziwym upadku — najczęściej największa), a obrót wokół normalnej jest losowy. Pomiar rozkładu (10 000 losowań): płytka 3,2×3,2×1 płasko 94%, pręt 1×1×6 na końcu 0,2%, płyta 1×6×3 na największej ścianie 95%, sześcian równo. Kosmetyka u klienta (gruz bez kolizji) — każdy gracz widzi inne ułożenie, na grę nie wpływa. NIEPRZETESTOWANE w Play.
>
> **STAŁY TEST AKCEPTACYJNY DESTRUKCJI (29.09)** — ta sama seria za każdym razem, żeby było widać, czy poprawka czegoś nie zepsuła (losowe granie tego nie pokazuje). Współrzędne z mapy (odczyt w Edit 29.09): OrangeBuilding X −431…−298, Z −180…−55, stropy Y 31/54/75; GreenBuilding X −293…−207, Z −195…−128, stropy co ~15 od 9 do 102; SandBuilding X −208…−107, Z 84…182, stropy 25…89; CyanOffice X −365…−304, Z −252…−202. Bomby kłaść na podłodze danego poziomu (rzut z bliska).
> | # | Scenariusz | Ma się stać | Nie może się stać |
> |---|---|---|---|
> | T1 | OrangeBuilding, parter: bomby w (−385, −145), potem (−365, −143), potem (−384, −121) — seria z 28.09 | wyższe piętra spadają bryłami po niższych, cały budynek się kładzie | bryła wisząca > 1 s nad zburzonym parterem; nagłe zniknięcie piętra |
> | T2 | OrangeBuilding: najpierw bomba na stropie Y 54 w środku, potem seria T1 | góra spada na strop 31 i tam leży; po T1 leżące rumowisko spada RAZEM ze stropem 31 (M-1) | rumowisko zostające w powietrzu na wysokości ~31 |
> | T3 | Stań na stropie Y 54 OrangeBuildingu, drugi gracz (albo Ty z dołu) robi T1 | jedziesz ze stropem, na dole zwykły fall damage | obrażenia „od gruzu”, śmierć od bryły, która się nie rusza |
> | T4 | GreenBuilding, parter (Y ~9) przy środku (−250, −161): 3 bomby w odstępie ~1 s | wieżowiec składa się piętrami | zaklinowane piętra, lewitujące płyty, lag |
> | T5 | W trakcie T4 rzuć bombę w spadające piętro | leci dalej w dół, lekko popchnięte | wystrzelone piętro (M-2) |
> | T6 | Po T4: bomba w leżące rumowisko | dziura w bryle, bryła drga / lekko odskakuje | wystrzelenie bryły z belki (M-4) |
> | T7 | SandBuilding, parter przy środku (−157, 133): 5 bomb w ~3 s | płynnie, bez przycięcia serwera | lag, znikające piętra |
> **Zaliczone** = T1-T7 bez żadnego „nie może się stać”. Po każdym przebiegu wkleić z Output linie `[Collapse]` (`ZAKLINOWANA`, `ODBLOKOWANA`, `bez oparcia`) i `[Destr]`. **Dwa przebiegi zaliczone z rzędu = destrukcja ZAMROŻONA**: od tego momentu tylko poprawki zgłoszonych błędów, każda nowa ficzura destrukcji → po launchu (decyzja do potwierdzenia przez Kacpra).
>
> **Paczka 5 (29.09) — ✅ ZROBIONE 29.09 (w Studio, suma kontrolna zgodna, kompiluje się), NIEPRZETESTOWANE w Play. PLAN spisany PRZED kodem (przegląd kodu 29.09: `docs/REVIEW_2026-09-29.md`, punkty M-1…M-8).** Zgłoszenie Kacpra 29.09: „lewitujące bloki, party bugują się w sobie, zabijają mnie party, które się nawet nie ruszają”. Zaproponowałem uproszczenie (kolaps jako kruszenie u klientów, bez fizyki serwera) — **Kacper: fizyka ZOSTAJE, naprawiamy; obrażenia od gruzu USUWAMY CAŁKIEM; gruz serwera (`DebrisService`) ZOSTAJE.**
> Tabela wymagań (lekcja 7) — każda poprawka sprawdzona, czy nie cofa zaakceptowanego:
> | Decyzja Kacpra | Skąd | Paczka 5 |
> |---|---|---|
> | gracz jedzie razem z piętrem; fizyka bardzo ważna | 24.09 | bez zmian |
> | utrata podparcia natychmiast | 24.09 | bez zmian (M-1 dokłada natychmiastowe budzenie rumowiska) |
> | duże bryły zostają platformą do końca rundy | 24.09 | zostają, ale TYLKO dopóki mają na czym leżeć (M-1: bez oparcia spadają fizyką — decyzja 29.09) |
> | kaskada pełna, aż do dachu | 24.09 | M-1 to domyka (rumowisko na niższym piętrze spada razem z nim) |
> | zaklinowana grupa → do klientów (po odblokowaniu) | 25.09/28.09 | bez zmian; M-6 tylko zawęża, komu przesuwa się okno |
> | „mniejszy odrzut dla wszystkich” — obudzona bryła ×0,3 | 25.09 | M-2 rozciąga to na bryłę W LOCIE (decyzja 29.09) |
> | bryła pod graczem nie przygniata; jazda = zwykły fall damage | 26.09 | przygniecenie znika całkiem (decyzja 29.09) — fall damage bez zmian |
> | bryła oparta o krawędź, której solver nie liczy, „spada od razu” (filtr przy starcie) | 28.09 | bez zmian; M-3 tylko przestaje liczyć LISTWĘ jako grunt przy lądowaniu (listwa „niczego nie niesie” — ta sama zasada co filtr) |
> | rumowisko cięte bombą jak ściana | 25.09 | bez zmian; M-4 zakłada filtr nachodzeń przy budzeniu |
> **Zmiany (kod)**: (1) **usunięcie przygniecenia** — `CollapseService.crushCheck`/`isUnder`, `DebrisService.crushCheck`/`applyCrush`/`lastCrushAt`, klucze `Config.Structure.Collapse.Crush*` i `Config.Destruction.Impact.Crush*`; zabójstwa „crush” znikają z kill feedu. (2) **M-1 rumowisko bez oparcia** — jeden predykat „co trzyma bryłę” (zakotwiczone, z kolizją, nie w locie, nie w drodze do klientów; z budynku v4 tylko KONSTRUKCJA w chunku nie-`Falling`, listwa nie) dla lądowania (`groundUnder`) i dla osiadłych brył; sprawdzanie osiadłych po kolei (limit na klatkę, jak `DebrisService`) + od razu, gdy coś pod nimi zniknie (start grupy, cięcie, zatonięcie w lawie, zniknięcie małej bryły); bez oparcia → `wakeRubble` BEZ impulsu (budżet; bez miejsca czeka jak grupa w kolejce, po `MaxQueueWait` do klientów). (3) **M-2** — kawałek grupy w locie trafiony bombą nie idzie do zwykłego `push` (pełny impuls CAŁEJ spawanej bryle z rozmiaru trafionego kikuta), tylko do CollapseService: impuls ×`WakeImpulseFactor`, rozmiar z korzenia, DODANY do bieżącej prędkości (spadające piętro nie staje w powietrzu), raz na bryłę na wybuch. (4) **M-4** — ~~filtr nachodzących par przy budzeniu~~ **ZMIANA przy implementacji**: pudełka świata OBRÓCONEGO rumowiska nie odróżniają „wbita w belkę” od „leży na belce” — filtr puściłby bryłę przez to, na czym leży. Zamiast tego limit prędkości: przez `WakeClampTime` (0,5 s) prędkość w bok i w górę przycinana do nadanej wybuchem + `WakeSpeedMargin`, obrót do nadanego + `WakeSpinMargin`; w dół bez limitu (grawitacja) — `wakeGroup` + `clampWakes`. (5) **M-5** — styk na granicy chunków rozstrzygany po pudełku TRAFIONEGO kawałka (chunk z największą częścią wspólną), nie po kolejności listy. (6) **M-6** — zaklinowanie przesuwa okno tylko grupom, które go dotykały. **Odłożone**: M-7 (koszt budżetu z faktycznych kawałków — zmienia, ile grup trafia do klientów; dopiero po teście).
> **Test (Kacper, po `rojo serve` + Connect)**: (1) bomba 1 zawala górę na piętro niżej, bomba 2 w parter pod tym piętrem → leżące wyżej rumowisko spada RAZEM z piętrem, nic nie zostaje w powietrzu; (2) stań obok walącego się piętra i pod spadającymi bryłami → zero obrażeń od gruzu (ranią tylko bomba, lawa, upadek); (3) rzuć bombę w spadające piętro → leci dalej w dół, lekko popchnięte, nie wystrzelone; (4) bomba w leżące rumowisko wbite w belkę → drga, nie wystrzeliwuje; (5) Output: wkleić linie `[Collapse] … ZAKLINOWANA` / `ODBLOKOWANA` / `bez oparcia` (nowa) — porównanie z 10/38 z 28.09.
>
> **Osierocone: TV na szafce, deski rusztowania (28.09) — zgłoszenie, pomiar, decyzje Kacpra, zmiany:** „zostają np. TV w dużym budynku (Sand) — TV zostaje w powietrzu, czy na rusztowaniu deski”. **Pomiar (Play, odczyt na serwerze)**: wszystkie 6 TV w SandBuildingu dotyka WYŁĄCZNIE szafki `TVStands` (nie podłogi); na całej mapie 295 rekwizytów dotyka tylko innych rekwizytów (produkty na półkach 36, kosze PupleHotel 21, TV, łóżka, stoły, beczki, paczki, szczeble drabin). „Przyczepione” (`collectAttachedTo`) zbierało tylko to, co dotyka SPADAJĄCEJ KONSTRUKCJI — szafka szła, TV zostawał; tak samo przy rozpadzie i odepchnięciu szafki. Deski `Construction.Decorations.WoodPlanks` (2×0,5×38-40, leżą na belkach 42×1×3) są ponad `Props.MaxSize` 24 → nie rekwizyt, nie drobnica, a bake pomija `Decorations` — nic ich nigdy nie zrzucało (37 takich dużych dekoracji: dywany, lada, `CarStand`, `Others`, szyny drabin). **Decyzje Kacpra**: rzecz stojąca na meblu **spada razem z nim**; duża dekoracja **zostaje, póki dotyka czegoś stojącego** (jak listwy v4 z 26.09). **Zmiana — jedna reguła** (`DestructionService.dropOrphans`, wołane w `sendHandoff`, więc na każdej ścieżce: wybuch, podparcie v3, kolaps v4, kruszenie, auta): skupisko stykających się luźnych rzeczy (rekwizyty, drobnica, duże dekoracje) spada, gdy żadna jego część nie dotyka niczego zakotwiczonego, kolidującego i nieodchodzącego; łańcuchowo (paczka na paczce). Odepchnięty mebel → to, co na nim stało, spada u klientów. Duże dekoracje przy dziurach sprawdzane klatkę po wybuchu (resztki muszą wejść do broadphase). `settleLater` przekazuje klientom PO odkotwiczeniu płyt serwera. Limity `Props.OrphanMaxCluster` 40 / `OrphanMaxJudged` 200 — ponad limit rzecz zostaje (jak przed poprawką). Log: `osierocone=N` w `[Destr]`, `[Destr] osierocone po dziurach: N`. ⚠️ TV należy do `Props.Vaporize`, więc osierocony TV **znika z obłokiem** (decyzja 26.09: „drobne ZAWSZE znikają, także spadające”), nie spada animacją — łóżka, stoły, paczki, beczki... spadają. **NIEPRZETESTOWANE w Play.** Test: (1) SandBuilding — zawal piętro pod TV albo wysadź szafkę obok (odepchnięcie) → TV nie wisi; (2) półki z produktami — zburz półkę → produkty nie wiszą; (3) Construction — zburz obie belki pod deską → deska spada; zburz JEDNĄ → deska zostaje (trzyma druga); (4) dywan na ocalałej podłodze zostaje; (5) drabiny (szczeble) zachowują się jak 26.09.
>
> **Fragmenty kruszenia jako rumowisko (28.09) — decyzje Kacpra, zmiana:** realizuje punkt 1 „Planu na następną sesję” (25.09). Do 28.09 fragment skruszonego elementu (≥ `FragmentMinVolume` 45) był gruzem `DebrisService`: bomba go tylko pchała, osobny budżet (260), leżał do końca rundy (≥ 45 = platforma), pękał przy twardym uderzeniu. **Decyzje Kacpra**: czas życia **jak rumowisko** (< `SmallRubbleVolume` 300 znika po `SmallRubbleLifetime` 4 s, większy zostaje platformą); budżet **wspólny z kolapsem**, bez miejsca → animacja u klientów. **Zmiana** (`CollapseService.newFragment`/`launchFragment`): fragment = jednoelementowa grupa (`fragment = true`, `chunkIds` puste, koszt 2), zostaje w mapie (nie w `BlastDebris`), osiada jak grupa, leżący jest cięty (`cutRubble`) i budzony (`wakeRubble`), gaśnie w lawie, przygniecenie liczy `crushCheck` (prędkość względna; fragment 45 studs³ zadaje 20 = `CrushMinDamage`, wcześniej `DebrisService` min. 12). Filtr kontaktów (`filterContacts`) trafia do `a.filters` i znika przy osiadaniu. Znika fall-fracture fragmentów (pękanie przy uderzeniu). Log: `[Collapse] … kruszenie chN — fragmentów fizyką X, u klientów Y (budżet …)`. Kod w Studio (suma kontrolna zgodna z dyskiem), kompiluje się. **NIEPRZETESTOWANE w Play.** Test: (1) bomba w ścianę budynku v4 tak, żeby się skruszyła → kawałki ściany wylatują i leżą; (2) druga bomba w leżący duży kawałek → jest cięty, nie tylko pchany; (3) małe kawałki znikają po ~4 s; (4) kawałek w twarz → boli (~20); (5) duże zawalenie + kruszenie naraz → bez przycięć.
>
> **Zaklinowania — przyczyny z logu 28.09, decyzja Kacpra, zmiany (28.09):** log OrangeBuildingu z 28.09 (runda 1): **10 z 38 grup zaklinowanych** → wszystkie szły do klientów (wisiały 0,4-2,6 s i znikały jako ciemny gruz). ⚠️ Moja pierwsza diagnoza („bryły blokują się o siebie w locie, wyłączyć kolizję między grupami”) była NIEPRECYZYJNA: „grupa w locie” w 5 z 10 to głównie ŁAŃCUCHY (5:154 leży na 5:29 — przyczyną jest dolna). Tabela zaklinowań (holder = co trzymało wg logu):
> | Grupa | Ruch / czas | Trzymało (log) | Wniosek |
> |---|---|---|---|
> | 1:58 Column | 0,02 / 0,48 s | 4 × BOK 0.00 (słup, listwy), 2 × NAD — **log ucięty na 6** | POD nieznane; ta sama grupa w obu rundach (deterministyczne) |
> | 2:73 Beam×4 Slab | 0,02 / 0,48 s | BOK 0.00 × 4 (Intact), **POD listwa**, NAD — ucięty | leży na listwie |
> | 5:2 Beam×4 Column×5 Slab | 0,01 / 0,41 s | 5 × BOK 0.00 Intact, NAD — ucięty | styk ściana w ścianę z resztą partów |
> | 5:143 Wall | 0,03 / 0,83 s | BOK -0.02 Slab, **POD Beam Intact** | leży na belce, której solver nie liczy (styk < MinInterfaceWidth) |
> | 5:22 Column×2 | 0,16 / 1,27 s | BOK 3-4 rumowisko 5:74, BOK 0.4-0.5 meble (GarageShelf), BOK 3.62 Slab — ucięty | wciśnięta w rumowisko i meble |
> | 5:151 Wall×3 | 0,01 / 1,71 s | BOK -0.01/0.02 Slab Intact, BOK 0.03 grupa w locie 5:154 | styk z boku ze stojącymi stropami + sąsiednią grupą |
> | 5:154 Wall×3 | 0,05 / 2,15 s | **POD grupa w locie 5:29** + BOK Intact — ucięty | ŁAŃCUCH (leży na 5:29) |
> | 5:29 Beam Column×5 | **0,00 / 2,61 s** | 4 × BOK 0.00 Intact, BOK grupa 5:199, NAD listwa — ucięty | nic pod spodem w logu; spoina WYKLUCZONA (0 spoin w placu); najpewniej podpora od spodu poza limitem logu |
> | 6:70 Beam×10 Column×2 Slab×2 | 0,18 / 0,44 s | **POD grupy w locie 6:80, 6:71**, **POD 3 × attached** — ucięty | łańcuch + ozdoby pod spodem |
> | 6:135 Wall | 0,39 / 0,83 s | BOK 3.57 / 0.43 grupy w locie, NAD grupa | wciśnięta między spadające grupy |
> **Przyczyny (wnioski z logu + kodu, NIE pomiar w grze)**: (1) styk „BOK 0.00” — kawałek odcięty po granicy chunka dotyka reszty parta całą ścianą; czy dostanie filtr, rozstrzygało zaokrąglenie (filtr tylko przy nachodzeniu > 0), a obrót startowy (`Spin`) wciska grupę w sąsiadów; (2) oparcie od spodu o krawędź / listwę, którego solver nie liczy (za wąskie, listwa nie niesie) — filtr celowo go pomijał („na tym grupy mają lądować”); (3) ~~spoiny z placu~~ — **WYKLUCZONE pomiarem 28.09**: w 10 budynkach 0 `WeldConstraint`/`JointInstance` (hipoteza pasowała do „ruch 0.00 w 2.61 s” idealnie — lekcja 3); usuwanie spoin przy starcie zostaje jako zabezpieczenie (v3 robi to samo); (4) łańcuchy — każde zaklinowanie przesuwało okno pozostałych o `JamCheckTime` (kaskada do 2,6 s); (5) log ucięty na 6 styków w kolejności silnika — przy 6 z 10 podpora od spodu mogła się nie zmieścić. **Decyzja Kacpra 28.09**: bryła oparta o krawędź, której solver nie liczy — **„spada od razu”** (może na moment przeniknąć przez róg belki). **Zmiany** (`CollapseService`): (a) start grupy: `cutExternalJoints` (spoiny z otoczeniem, też fragmenty kruszenia — zabezpieczenie, dziś 0 spoin) + `filterAtRelease` — filtr także przy DOTYKU (`ReleaseContactPad` 0,05): ze stojącą częścią budynku v4 (konstrukcja nie-`Falling`, listwa, ozdoba) z każdej strony, z inną spadającą grupą (w locie albo w kolejce) tylko z boku; reszta świata bez zmian; (b) siatka dwustopniowa: najpierw **ODBLOKOWANIE** (spoiny + filtr ze wszystkim, czego dotyka, poza spadającą grupą pod/nad nią; pchnięcie w dół; nowe okno), dopiero drugie utknięcie → klienci; (c) grupa leżąca na spadającej (w locie albo w kolejce) CZEKA (`restsOnFalling`, sufit `MaxFallTime`) — koniec kaskady; (d) `groundUnder`: pomija styki z filtrem; stojąca konstrukcja pod spodem = lądowanie, gdy grupa opadła ≥ `LandMinDrop` 0,1; (e) log: `holdersOf` — POD najpierw, `JamLogMax` 8 + „(+N)”, „PRZYSPAWANA do zakotwiczonego” (`IsGrounded`); `leci (… spoiny N …)`; `ODBLOKOWANA (… spoiny, filtry), trzymało: …`; `ZAKLINOWANA mimo odblokowania`. Kod w Studio (suma kontrolna zgodna z dyskiem), kompiluje się. **NIEPRZETESTOWANE w Play.** Test: (1) ta sama seria bomb w OrangeBuilding co 28.09 (parter od strony -385/-145, potem -365/-143, -384/-121) → policzyć w logu `ZAKLINOWANA` (było 10 na 38) i `ODBLOKOWANA`; (2) nic nie wisi dłużej niż ~0,5 s; (3) stań na kawałku piętra, zburz pod nim — jedziesz i nie przenikasz przez podłogę; (4) szukać przenikania brył przez STOJĄCE stropy/belki (ryzyko reguły „spada od razu” — powinien być najwyżej róg); (5) wkleić linie `ODBLOKOWANA … trzymało:` i `ZAKLINOWANA mimo odblokowania` — pokazują, co jeszcze trzyma bryły (POD jest teraz na początku listy).
>
> **Migracja kolejnych budynków (27.09) — pomiar i decyzje Kacpra:** pomiar w Edit wszystkich 8 pozostałych (czerwone chunki nietkniętego budynku przy regułach ogólnych → potrzebne ustawienia): OrangeKebab 0, CyanOffice 0, OldBuilding2 4 → próg 1,9 = 0, PurpleSchool 183/325 (belki 1×2) → 1,9 + degradacja 6, OldBuilding1 5 → 1,9 + degr. 2, Construction 1 → degr. 1, SandBuilding 9 → degr. 9, PupleHotel 10 → degr. 10; żaden nie przecina torów. **Decyzja: najpierw 3 bez poprawek** (OrangeKebab, CyanOffice, OldBuilding2 z progiem 1,9); reszta po teście GreenBuildingu w Play. Sprawdzone offline (kopie 5 budynków v4 + tory, bez Play): wszystkie stoją, kolaps WŁ, 0 wiszących w projekcie, rebuild 80 ms (przycięcie na starcie odliczania — do usunięcia zapisem danych bake'u). Rekwizyty: `Chairs` dopisane do `Vaporize` (decyzja Kacpra: wszystkie krzesła znikają); biurka CyanOffice (`OfficeDesks`, 48 × ~109 partów) zostają meblami (decyzja Kacpra) — w Ziemniaku animuje się ~1 rozpadające biurko na wybuch, reszta znika bez animacji. Test: bomby w OrangeKebab, CyanOffice (biurka odpychane, druga bomba je rozwala; krzesła i rośliny znikają) i OldBuilding2 — piętra spadają bryłami, nic nie wisi; płynność startu rundy.
>
> **Rekwizyty: wieszaki i meble (26.09 noc) — pomiar, decyzje Kacpra, plan (spisany PRZED kodem):**
> - **Zgłoszenie**: „w green building jest w chuj cloth hangerów” — trafione wieszaki są kopiowane i animowane u każdego gracza (przewracanie, w Pełnym rozsypywanie) i dziwnie to wygląda; meble rozlatują się od jednej bomby. **Pomiar**: GreenBuilding.Decorations — wieszaków 37, ale **1958 partów** (do 66 na sztukę); skrzynie 8 × 25 partów, siedzenia 4 × 65. Bomba 160/24: dziura do ~9 studów, rekwizyty łamały się do ~12.
> - **Decyzje**: (1) wieszaki + drobne (lista folderów `Config.Destruction.Props.Vaporize`: ClothingHangers, Plants, Packages, TrashBins, Chair, TV) w zasięgu **dziury** znikają od razu z obłokiem pyłu, zero kawałków; (2) reszta rekwizytów = **meble**: w zasięgu dziury rozpad od razu na kawałki, które znikają po ~1,5 s; dalej (obrażenia ≥ `PushHP`) **odepchnięcie w całości prawdziwą fizyką serwera** (da się na nim stanąć; limit `MaxPushPerBlast` na wybuch, ponad limit mebel zostaje), **drugie trafienie → rozpad**.
> - **Model**: `Destructible.propCategory` (vaporize / furniture po nazwie folderu kategorii; nil = nie rekwizyt); `PropService` (NOWY, jedyny właściciel stanu odepchniętych mebli): pamięć trafień, spawy do największej części, `SetNetworkOwner(nil)`, po `PushSettleTime` bezruchu (albo `PushMaxTime`) kotwiczony tam, gdzie leży — NIE przez DebrisService (rozłupuje kawałki przy uderzeniu i liczy przygniecenie); `DestructionService`: rekwizyty zbierane per jednostka (najbliższa część decyduje), decyzja z `holeRadius`; `handOff` kieruje KAŻDY znikający rekwizyt (także z dziur i z kolapsu — `dropResting`) do listy `vapor` (tylko pudełko; serwer kasuje od razu, klient niczego nie kopiuje), rozpad do `shatter`; `Remotes.DebrisFall` + `vapor`/`shatter`; klient (`DebrisFXController`): obłok pyłu / części lecą od wybuchu i żyją `ShatterLife` w obu trybach.
> - **✅ Zrobione 26.09 (noc), NIEPRZETESTOWANE w Play.** Kod: `Config.Destruction.Props` (Vaporize, PushHP, MaxPushPerBlast, PushSettleTime, PushMaxTime, ShatterLife, VaporDust), `Destructible.propCategory`, `PropService` (NOWY), `DestructionService` (`propHits` per jednostka, decyzja po `holeRadius`, `handOff` → `vapor`, `shatterOff`, odepchnięcie na końcu etapu 4, log `[Destr] … rekwizyty: znikło=N rozpad=N odepchnięte=N`), `Remotes.DebrisFall` (+`shatter`, `vapor`), `DebrisFXController` (`spawnVapor`, `spawnShatter`). Sprawdzone w Studio: 7 plików dojechało i się kompiluje; kategorie na prawdziwych rekwizytach — znikają: 37 wieszaków, 12 roślin, 10 paczek, 2 kosze, krzesło, TV; meble: skrzynie, palety, komody, półki, automaty, siedzenia, deski w oknach. Uwaga: drabina `Leader` (97 studów) nie jest rekwizytem w całości (MaxSize 24) — jej 48 szczebli to osobne „meble”. Odepchnięcia i obłoku nie da się sprawdzić bez Play.
> - **Test dla Kacpra**: (1) bomba między wieszakami → w promieniu dziury znikają z obłokiem, dalej stoją; (2) skrzynia blisko bomby → rozpada się, kawałki znikają po ~1,5 s; (3) skrzynia dalej → odlatuje w całości, można na nią wskoczyć, sama się zatrzymuje; druga bomba → rozpad; (4) strop z meblami spada → wieszaki znikają z obłokiem, meble przewracają się jak dziś; (5) kilka bomb w sklepie z wieszakami — płynność na telefonie (Ziemniak).
>
> ⚠️ Świadome braki fazy D: obrażenia jeźdźca to zwykły upadek (0,5 i grace = faza E — RiderTracker),
> krawędź dziury prosta (bez poszarpanej wargi), meble ze spadającego stropu padają animacją u klientów
> (nie jadą z bryłą), fragmenty L3 idą przez budżet DebrisService (osobny od budżetu kolapsu — do
> scalenia), klient dalej wyłącza lokalnie kolizję przekazanych mebli (kontrakt pkt 13, do poprawy).
> Reszta niezaimplementowana;
> w grze dalej działa v3. Kod zaczyna się od jednego budynku (OrangeBuilding), reszta mapy jedzie
> na v3, dopóki budynek nie ma danych.

### Dlaczego v4 (zmierzone w Edit, bez Play)
- v3 liczy podparcie przy KAŻDYM wybuchu od nowa z geometrii w kolumnie wokół epicentrum — nie zna
  pięter ani słupów; kolaps sekcji (`StructureService`) martwy: 0 partów z tagiem `Pillar`.
- Cięcie: bomba leżąca na podłodze tnie średnio 12,7 partu konstrukcji i stawia **45 nowych partów
  (max 149)** — 200 losowych prób. Model „okna” (dziura = prostokąt, resztki ≤ 4 pasy): **6,0 (max 16)**.
  Matematyka planu ~1 ms — koszt to nowe instancje, nie obliczenia.
- Mapa: 10 budynków; konstrukcja większa niż drobnica to 2 666 partów, z czego tylko ~1 000 to płyty
  i ściany — reszta to listwy/belki (500), płaskie pasy: gzymsy, parapety, balkony (733), pionowe
  obramowania (463). Ściany przez wiele pięter: GreenBuilding 24 ściany po 92 studach.
- OrangeBuilding (prototyp): rama — 6 słupów 5×5×67 przez całą wysokość, belki obwodowe na każdym
  poziomie, filarki 3×5×12 między oknami; stropy Y≈30 / 52-54 / 74; **158 par partów konstrukcji
  na siebie nachodzi (125 o > 0,5 studa)** — odkotwiczony part nachodzący na stojący silnik
  gwałtownie wypycha, więc kolaps MUSI filtrować te pary (NoCollisionConstraint z listy z bake'u).
- `StreamingEnabled = true`.

### Decyzje Kacpra (24.09)
| Pytanie | Wybór |
|---|---|
| Gracz na spadającym piętrze | **jedzie razem z nim** (fizyka serwera z kolizją z graczem) |
| Utrata podparcia | **natychmiast, bez ostrzeżenia** — dozwolone tylko techniczne rozłożenie na kilka klatek |
| Dokładność dziury | **wizualnie dokładna, kolizja uproszczona** — krawędź widoczna ≤ ~1 stud od kolizji |
| Gruz po kolapsie | drobny: kilka sekund; **duże elementy po zatrzymaniu zostają do końca rundy** |
| Ściany jako fizyczne fragmenty | **tak** |
| Kaskada | **pełna, aż do dachu** |
| Fizyka | **bardzo ważna** — domyślnie prawdziwa fizyka; animacja tylko jako degradacja |
| Wybuchy w jednym miejscu | realnie **4-5 w kilka sekund** |
| Low-end | **średnie telefony** |
| Priorytet | balans / wydajność z zachowanym „wow” |
| Ile bomb kładzie budynek | **~8 dobrze rozmieszczonych** (cel strojenia, nie twarda liczba) |
| Jeździec przy lądowaniu | ~~**0,5 × przejechana wysokość** (`RideImpactFactor`)~~ — od 26.09 zwykły fall damage (wiersz „(26.09)” niżej) |
| Prototyp | **OrangeBuilding** |
| Reset mapy (`MapService`) | bez zmian — najpierw pomiar w MicroProfilerze |
| Charakter | **„sandbox i naturalnie, nie sztucznie”** |
| (25.09) Jeździec: co znaczy 0,5 | ~~**połowa obrażeń** za pełną wysokość (nie połowa wysokości)~~ — zastąpione 26.09 |
| (25.09) Wysokość jazdy | ~~**z prędkości przy uderzeniu** (ΔV²/2g hamowania bryły), nie z różnicy Y~~ — zastąpione 26.09 |
| (26.09) Jazda na walącym się budynku | **zwykły fall damage** — osobnych obrażeń jeźdźca nie liczymy („czasem mało spadniesz, a liczy jako śmierć”); bryła POD graczem nigdy nie przygniata (`CollapseService.isUnder`), bryła spadająca NA gracza dalej rani |
| (25.09) Zaklinowana grupa | **do klientów** (kolizja od razu), log co trzymało |
| (25.09) Pion na stojącej belce, za daleko od słupa | **belka pęka pod nim** (przeciążenie) |
| (25.09) Kikuty przeciętego słupa/belki | **spadają z tym, co trzymają**; pień, którego nic nie rusza, zostaje |

### Architektura
```
EXPLOSION → DestructionService
   ├─ GeometryDamage → cięcie „okna” (kolizja, ≤ 4 pasy na part, sufit na wybuch)
   └─ StructuralDamage → StructuralService (stan chunków, CAS, dirty)
                            → Solver (raz na klatkę na brudny budynek)
                            → Planner → CollapsePlan (grupy, głębokość, zawias — same fakty)
                            → PhysicsDirector → ExecutionPlan (L3/L2/L1/L0, klatka, budżet)
                            → DebrisService (settle → Anchored, czas życia, crush)
KLIENT: VFX, pył, gruz bez kolizji, kopie mebli, poszarpana warga dziur — ilość wg trybu grafiki
```
| Moduł | Rola |
|---|---|
| `StructureBake` (Studio, Command Bar) | klasyfikacja, chunki, interfejsy, TRIM, nachodzenia, kolory, statystyki, „nietknięty = 0 spadających” |
| `ServerStorage.StructureData.<Budynek>` | dane z bake'u (w placu, poza Rojo, nie replikowane) + `BakeVersion`, `GeometryHash`, `MapRevision` |
| `StructuralService` (nowy) | JEDYNY właściciel stanu chunków; indeks SID→Part po każdym resecie mapy |
| `CollapseService` / PhysicsDirector (nowy) | grupy → spawanie, NoCollision dla nachodzących par, odkotwiczenie, budżet |
| `DebrisService` (zostaje) | cykl życia fizyki serwera |
| `RiderTracker` (nowy) | kto jedzie na spadającej grupie; ~~obrażenia od upadku~~ (26.09: liczy je zwykły `FallDamageService`) i grace anty-cheata |
| usuwane | `StructureService`, pass podparcia w `DestructionService`, HP per part, resztki `planHole` na serwerze, `Categories.Pillar`, `Config.Destruction.Collapse/Support`, fall-fracture dla brył kolapsu |

### Model (skrót — pełna wersja w debacie 24.09)
- **Chunk** = logiczny kawałek konstrukcji (Slab / Wall / Column / Beam / Block): stropy dzielone
  do ~20 studów z liniami cięcia przyciąganymi do belek/ścian/słupów, pionowe elementy dzielone
  na pasma po poziomach stropów. Chunk ≠ part: słup 67 studów to jeden part i 3 chunki.
- **Interfejs** = „A podpiera B przez odcinek o szerokości W”: `Bearing` (A pod B), `Lateral`
  (pion trzyma poziom z boku), `Continuity` (ten sam element / to samo ułożenie; nalicza przęsło).
  ⚠️ Z boku pion trzyma tylko BELKA (węzeł ramy), strop nie (`LateralHoldsVertical`). I KLUCZOWE:
  oparcie na poziomym elemencie DZIEDZICZY jego zasięg (zeruje go tylko pion) — bez tego podparcie
  „prało się” przez oparcie i wieża stała na wsporniku stropu sąsiedniej bryły (złapane na
  OrangeBuilding 24.09: cały parter pod wieżą zniszczony, a wieża nie spadała).
- **Solver**: Dijkstra po „zasięgu” = odległość od ostatniej prawdziwej podpory; spada chunk bez
  zasięgu ≤ `MaxSpan`. Cięcie przez cały przekrój nośny (słup 5×5 vs dziura 18×18) = `Severed`.
  **Przeciążenie (25.09)**: poziom, na którym (Bearing) stoi spadający pion, pęka i spada razem
  z nim — inaczej fizycznie dalej by go trzymał (iteracja do punktu stałego w `StructureCore.solve`).
- **TRIM/Other** nie są węzłami: `AttachedTo` właściciela, idą z nim (Follow / Cosmetic / Destroy).
- **Brak niewidzialnych awarii**: interfejs traci szerokość tylko, gdy znika materiał; podpora
  „zniszczona” strukturalnie kruszy się (znika jej geometria).
- **CollapsePlan** (logika) ≠ **ExecutionPlan** (poziom fizyki, czas, koszt). Poziom nie zmienia
  wyniku strukturalnego (Falling → Settled zawsze), tylko to, jak element leci.
- **Budżet**: jedna pula kosztu (1 + prymitywy z kolizją w locie), priorytety P0 (jeździec) … P4,
  rezerwa dla P0, zwrot dokładnie raz przy Settled/Retired.
- **Przyczyna**: `CauseRef {CauseId, AttackerUserId, Seq, Time}`; kolaps przypisany zdarzeniu
  o najwyższym `Seq` na granicy spadającego obszaru — nigdy kolejności u klientów.
- **Stan dla klientów**: replikowany folder `ReplicatedStorage.StructureState.<Budynek>`
  (Revision, Enabled, dziury do wargi, aktywne grupy) — nie protokół „daj snapshot”.

### Kontrakt (niezmienniki)
1. Serwer zna dokładny stan. 2. Każda zmiana ma `Revision`. 3. Każdy kolaps ma `CollapseId`.
4. Każde zniszczenie ma `CauseId`. 5. Członkostwo grup deterministyczne. 6. Każdy obiekt fizyki
ma rezerwację budżetu. 7. Każdy dynamiczny obiekt ma settle/cleanup. 8. Klient dostaje dość stanu,
żeby odtworzyć tę samą rozgrywkę. 9. Tryb grafiki NIGDY nie zmienia geometrii gry. 10. Nic nie
skanuje 10 budynków co klatkę. 11. Stan konstrukcji nie przeczy widocznej geometrii. 12. Solver
nie yielduje; przejścia stanów przez jedną funkcję CAS. 13. **Klient nigdy nie zmienia
`CanCollide/CanQuery/CanTouch/Anchored` instancji serwera** — ⚠️ v3 łamie to w `hideLocally`
(meble tracą kolizję u klienta do 0,25 s przed skasowaniem), do poprawy. 14. Rezerwacja budżetu
zwalniana dokładnie raz. 15. Nic nie wisi w powietrzu: gruz leżący na spadającej grupie jest budzony.

### Zakres v1 (świadomie odchudzony — dokładamy dopiero, gdy test pokaże potrzebę)
- **Robimy**: bake, solver, planner grup, fizyka L2 (spawane grupy, pasażerowie bez kolizji w locie),
  NoCollision dla nachodzących par, RiderTracker (0,5), jedna pula budżetu, cięcie okna.
- **Odkładamy**: L1 (animacja — tylko jeśli test jeźdźca z opóźnieniem nie przejdzie), zawias
  na krawędzi urwania, L0, wywłaszczanie budżetu, warga dziur dla spóźnionych klientów.

### Fazy (każda = test przed następną)
A `StructureBake` (0 czerwonych) → B solver offline (nietknięty, 1 dziura, kilka dziur, ściana,
częściowa i pełna utrata podparcia, pełna kaskada) → C CollapsePlan bez fizyki → D jedna grupa +
fizyka + gracz na niej → E RiderTracker (jazda, zeskok, zatrzymanie niżej, obrażenia) → F 5 wybuchów
w 3 s (jeden flush, budżet) → G 2 klientów, opóźnienie replikacji, Ziemniak vs Pełny, streaming.
Dopiero potem pozostałe budynki.

### Test akceptacyjny
~8 bomb kładzie budynek · dziura w stropie nie zabija stropu · parter może zrzucić wszystko do dachu ·
bomba w trakcie kolapsu nie psuje stanu · da się jechać na spadającym fragmencie i z niego zeskoczyć ·
obrażenia od upadku poprawne · duże elementy zostają platformami · drobny gruz znika · Ziemniak
i Pełny = ta sama kolizja · 5 wybuchów w 3 s bez niekontrolowanego wzrostu fizyki · 2 klientów widzi
ten sam wynik · spóźniony klient dostaje aktualny stan · nietknięty budynek nigdy sam nie spada ·
produkcja bez czerwonych chunków.

---

## Kikuty bez oparcia (30.09) — NIEPRZETESTOWANE

**Zgłoszenie Kacpra (test w Play)**: „w kebabie zawsze zostają jakieś lewitujące elementy ściany” → dopytane: „kawałek ściany przy dachu i na nim trzyma się dach”.

**Zmierzone na żywym serwerze** (OrangeKebab po 5 bombach, Play Kacpra, tylko odczyt): trzy górne końcówki filarków między oknami (5×1,9×1 na Y 20, każda dokładnie w miejscu swojego filarka) bez niczego pod spodem i z boku; górna część narożnego słupka (listwa 2×4,8×2) przyczepiona tylko do nich; spadnięta płyta sufitu 19×19 osiadła NA jednej z nich jako platforma. W logu zero zaklinowań — to nie fizyka.

**Przyczyna**: dziura przebija filarek na wylot → chunk `Destroyed` (Severed), pas nad dziurą zostaje zakotwiczony. Kikut spadał tylko w `CollapseService.takePieces`, czyli gdy obok ruszała grupa kolapsu. Pas nad filarkiem się SKRUSZYŁ (inna ścieżka) → kikut nie miał kto zabrać. Do tego pass listew liczył każdy zakotwiczony kawałek konstrukcji jako oparcie, także kikut — narożny słupek i kikuty trzymały się nawzajem.

**Decyzja Kacpra**: kikut bez oparcia ma spaść. Wariant: „zostaje, póki dotyka czegoś stojącego” — ta sama reguła co listwy (26.09), więc pień na podłodze i kikut wiszący pod stojącym stropem zostają (decyzja 25.09 bez zmian).

**Zmiana** (`StructuralService.unsupportedStrips`, jedno miejsce — wybuch, kruszenie i start grupy wołają je już dziś): kikut = zakotwiczony kawałek konstrukcji, który nie leży w żadnym żywym chunku swojego parta. Oparcie kikuta: stojący kawałek konstrukcji (także pień tego samego parta), styk z gruntem jego chunka, albo listwa/kikut, które same mają oparcie. Kikut NIE jest oparciem dla listwy. Sąsiedzi kikutów (`stubLinks`: interfejsy + linki zwrotne listew, także torów) i grunt (`groundFaces`) liczone przy budowie budynku.

**Odłożone decyzją Kacpra („najpierw kikuty, dach potem”)**: w pierwszej sesji 3/4 dachu kebaba stały na JEDNYM panelu 1×15×5 w rogu — `MaxSpan.Slab` 24 przy dachu 2×2 chunki po ~19 = jeden panel trzyma trzy ćwiartki. Reguła skaluje się z rozmiarem chunka, nie budynku, więc małe budynki obrywają najbardziej. Do sprawdzenia po teście kikutów; kandydat: `OrangeKebab = { MaxSpan = { Slab = … } }`.

**Test**: kebab jak w zgłoszeniu (bomby w parter przy filarkach między oknami) → po skruszeniu pasa nad oknem górne końcówki filarków i narożny słupek spadają; spadający dach nie zatrzymuje się w powietrzu. Kontrola: pień filarka/słupa stojący na podłodze zostaje.

## Rekwizyty na piętrze ponad budżetem (30.09) — NIEPRZETESTOWANE

**Zgłoszenie Kacpra**: „zielony budynek wysoki — pudła zostają po osunięciu całego budynku”.

**Z logu tej sesji**: 9. bomba → kolaps #6 = 25 grup, **14 „ponad budżet — upadek u klientów”** (wszystkie P2, czyli górne piętra daleko od gracza). Skrzynie (`Crates`), paczki i palety GreenBuildingu stoją WYŁĄCZNIE na Y 71-94 — na tych piętrach.

**Przyczyna**: start lotu (`CollapseService.launch`) woła `deps.dropResting` („drobnica i meble na tym, co spada — do klientów”), a grupa ponad budżetem (`degrade`) nie. To samo w `dropToClients` (osiadła bryła bez oparcia i bez budżetu — mogło na niej wylądować coś później, np. mebel odepchnięty bombą).

**Zmiana**: `dropResting` w obu, PO `handOffNow` — oddane kawałki są już w `pendingParts`, więc nie liczą się jako oparcie dla dużych dekoracji (w `launch` to samo daje odkotwiczenie).

**Test**: GreenBuilding — zwal cały budynek (seria w parter) → na górnych piętrach nie zostają w powietrzu skrzynie, paczki ani palety.


> **Twarde ruiny (08.10) — pomysł i decyzje Kacpra, NIEPRZETESTOWANE.** Zgłoszenie: po zawaleniu „wszystko to no-collide ruiny”. Log testu 08.10: wszystkie małe bryły (< `SmallRubbleVolume`) znikały po 4 s, ~2/3 fragmentów kruszenia szło do klientów bez kolizji. Decyzje: **25%** (z zakresu Kacpra 20-30%) obu rodzajów zostaje twarde do końca rundy — `Config.Structure.Collapse.KeepSmallRubbleChance` (mała bryła nie znika; losowane raz, przy pierwszym osiadaniu) i `SolidFragmentChance` (mały fragment ≥ `SolidFragmentMinVolume` 8 spada fizyką serwera zamiast u klientów, w tym samym budżecie `MaxCost`). Gruz z dziur bomby NIE (istnieje tylko u klienta — ⛔ fizyka serwera dla kawałków dziur, 23.09). Log: `osiadła … (mała — twarda ruina do końca rundy)`, `kruszenie … (w tym małych twardych N)`.
