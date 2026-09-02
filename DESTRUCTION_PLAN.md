# DESTRUCTION_PLAN.md — system destrukcji v2 ("topka Roblox")

> Plan zatwierdzony 2026-08-11 (decyzje Kacpra niżej). Stary system (BlastService) skasowany
> bez śladu — NIE odtwarzamy go, budujemy wg tego dokumentu. Implementacja etapami,
> każdy etap grywalny i testowany w Play zanim zaczniemy następny.

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
