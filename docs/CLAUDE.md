# Zasady kolaboracji w ESCAPE LAVA

Wspólne zasady dla agentów pracujących w repo. Punkt wejścia Codexa: główny `AGENTS.md` → `docs/AGENTS.md` → ten plik. Aktualizacja kontekstu: 23.10.2026. Bieżący stan: [STATUS](STATUS.md); nie utrzymywać tutaj drugiej kopii statusu.
**Wszystkie zasady są twarde. Łamanie = retry tej samej rozmowy.**

---

## Skala docelowa i jakość

ESCAPE LAVA celuje w **KILKUSET aktywnych graczy concurrent**. Roblox to multi-server (~30-50/serwer), więc setki active = dziesiątki serwerów jednocześnie. **Każda decyzja musi to wytrzymać.**

### Buduj jak architekt, nie zlepiarka

- **Plan przed kodem** — niefrywialna ficzura (>20 linii / nowy service) zaczyna się od planu: dependencies, owners, edge cases, kontrakt. Implementacja DOPIERO PO planie.
- **Single source of truth** dla każdego stanu. Stan w jednym miejscu, reszta przez API. Brak duplikatów które mogą się rozjechać.
- **Jasne ownership** — który service trzyma stan X, kto może go modyfikować, jak inni go widzą (read-only API vs event).
- **Kontrakty jawne** — `Remotes.luau` listuje wszystkie Remote'y z payload schema. Workspace structure spisana niżej. Każda nowa nazwa = update kontraktu.
- **Service ma jeden powód do zmiany** (Single Responsibility). BombService nie obsługuje monet. MapService nie wie o lawie.
- **Komentarze WHY, nie WHAT.** Kod czyta się sam. Komentarz tłumaczy decyzję, race condition, edge case, lekcję z poprzedniego buga.

### Antycypuj błędy ZANIM się wydarzą

Przed dostarczeniem ficzury, mentalnie przelataj:
- **Gracz dołącza w trakcie X** → state replikowany? (`replicateTo` pattern)
- **Gracz wychodzi w trakcie X** → orphan state? cleanup hook?
- **Character respawn / death w trakcie X** → cleanup? (`CharacterRemoving`)
- **DataStore offline / quota** → graceful fallback, nie crash
- **Network ownership** = klient → server set nie zadziała na character physics (zasada 12 niżej; przykład: PushService używa Remote → klient ustawia velocity)
- **BindableEvent deferred mode** → race na efektach listenerów (zasada 8)
- **Klient kłamie** → server validate WSZYSTKO (typecheck, distance, ownership, current state)
- **Race condition** dwa requesty równolegle → atomic ops, UpdateAsync, no read-then-write

### Wcielaj się w rolę gracza

PRZED skończeniem ficzury: "gdybym był graczem na żywym serwerze, czy to by mnie wkurzyło?"

- Rate limit blokujący ludzki click rate = WKURZA (przykład: usunięty BUY_RATE_LIMIT 0.5s)
- Double-click żeby coś zrobić = WKURZA (przykład: auto-reequip bomby po throw)
- Brak feedback'u = WKURZA (toast, sound, animation)
- Self-recovery z bad state = OK; nieskończony bad state = NIE
- Estetyka liczy się — `cleanupActiveBombs` przed restore zamiast pozwolić bombie zepsuć mapę

### Skala-specific zagrożenia

- **DataStore quota:** 60 + 10×graczy zapytań/min PER KEY. Batchuj, UpdateAsync, nie spamuj.
- **BindToClose ≤30s** — save'e szybkie i parallel (`task.spawn` per gracz).
- **Memory per serwer** — nie trzymaj historii rund, nie clone'uj per-tick.
- **RemoteEvent bandwidth** — minimalny payload. Nie wysyłaj całego inventory gdy zmienił się 1 slot.
- **Anti-cheat MOCNIEJSZE** niż w hobby projekcie — exploity będą.
- **Viral spike z TikToka** = nagły load — server boot szybki, snapshoty (jak MapService) na init nie request.
- **1-na-1000 bug** wydarzy się gwarantowanie kilka razy/min przy tej skali. Sklepane "u mnie działa" rozwiązanie zatopi 50-tego gracza.

---

## Podział ról

| Obszar | Kto robi |
|--------|----------|
| Geometria mapy (budynki, podłogi, dziury, ozdoby) | **Kacper** w Studio |
| Spawn points, lobby spot, item spawn points (jako obiekty w Workspace) | **Kacper** w Studio |
| ScreenGui / UI (ScreenGui, Frame'y, TextLabel'e, buttony) | **Kacper** w StarterGui |
| Skiny, modele postaci, particle, sound assety | **Kacper** w Studio |
| **Testy w Play — uruchamianie gry, weryfikacja na żywo** | **Kacper. ZAWSZE.** (zasada 2026-09-20, uzasadnienie niżej) |
| Logika gry (services, state machine, mechaniki) | **Codex** w kodzie |
| RemoteEventy, BindableEventy, kontrakty komunikacji | **Codex** w kodzie |
| Balansowanie liczb (Config.luau) | **Codex** + Kacper review |
| DataStore, anti-cheat, rate limiting | **Codex** |

---

## Co Codex **NIE robi** (zero tolerancji)

- ❌ **NIE tworzy placeholder budynków / mapy** w kodzie (PlaceholderMap, generated towers itp.).
- ❌ **NIE tworzy ScreenGui programmatic** (Instance.new("ScreenGui") + TextLabel'e).
- ❌ **NIE buduje "spawn points" ani lobby spot** w kodzie — czyta z Workspace gdzie Kacper je postawił.
- ❌ **NIE ingeruje w respawn / charakter spawning** bez pytania (Kacper mówi "respa już jest" = nie tyka).
- ❌ **NIE wybiera za Kacpra** sensible defaults gdy są decyzje architektoniczne do podjęcia — pyta.
- ❌ **NIE uruchamia Play (`start_stop_play`) i NIE testuje sam przez MCP** (zasada 2026-09-20). **Testy przeprowadza wyłącznie Kacper.** Codex dostarcza kod plus **konkretną listę do sprawdzenia** („zeskocz z dachu — ma zaboleć i wywrócić", „wejdź na drabinę — ma NIE wywrócić"), a nie własny werdykt „działa".
  - **Dlaczego — kupione drogo w sesjach 2026-09-16/19:** (a) `start_stop_play` z MCP **przerywa sesję Kacpra w środku** — kilka razy zatrzymałem mu Play dokładnie wtedy, gdy sam testował; (b) **automatyczny harness DWA RAZY dał fałszywy wynik**: raz mierzył HP już PO obrażeniach z poprzedniego upadku i pokazał „0 dmg", choć system działał poprawnie; raz czytał `LogService:GetLogHistory()` ze **starej** sesji Play i „potwierdził" błąd, którego w nowym kodzie już nie było. **Fałszywy wynik testu jest gorszy niż brak testu** — prowadzi do naprawiania rzeczy, która nie jest zepsuta, i do raportowania Kacprowi nieprawdy.
  - **Co MCP zostaje do robienia (to zostaje i jest cenne):** odczyty — `inspect_instance`, `search_game_tree`, `script_read`, pomiary geometrii, sprawdzenie czy Rojo dowiozło kod do Studio. To są **obserwacje, nie testy**, i wielokrotnie skróciły diagnozę: 86% tafli lawy zakryte geometrią, wysokość budynków 109, brak `Texture` na lawie, stara wersja pliku w Studio przy odłączonym Rojo.

## Co Codex **dostarcza** zamiast tego

- ✅ **Kontrakt nazw**: lista obiektów które kod oczekuje w Workspace / StarterGui (np. `Workspace.SpawnPoints/*` BasePart'y → kod weźmie ich `.Position`).
- ✅ **Logikę usług** czystą, bez UI / placeholder geometrii.
- ✅ **Pytania ZANIM** zacznie pisać kod dla nowej rzeczy lub zmieniać istniejącą logikę.

---

## Workflow: każda zmiana / nowa rzecz

1. **Codex zadaje 2-4 konkretne pytania** (przez AskUserQuestion gdy są wybory A/B/C) zanim zacznie pisać kod nowego ficzeru lub refactoruje istniejący.
2. **Kacper odpowiada** — wspólna wizja.
3. Dopiero wtedy Codex **pisze kod** i **dostarcza kontrakt nazw** dla rzeczy które Kacper ma postawić w Studio.
4. Kacper buduje to w Studio, testuje, daje feedback. Pętla.

Pytania mają być **konkretne** ("X czy Y?", "Jak nazwać Z?", "Czy chcesz tu A czy B?"). NIE "jak chcesz to zrobić".

---

## Hard coding rules (z lekcji Kaucji Simulator + ESCAPE LAVA Day 1-4)

1. **Zero `_G`** w komunikacji — tylko ModuleScripts i RemoteEvents.
2. **Server authority** na wszystkich ważnych akcjach (zakup, item, monety, stan gry).
3. **Distance checks** server-side na każdej interakcji wymagającej proximity.
4. **Rate limiting** na każdym RemoteEvent (per player).
5. **Config-driven** — wszystkie liczby w `src/shared/Modules/Config.luau`.
6. **Logowanie transakcji walutowych** z timestampem + powodem.
7. **Test w Studio PRZED publishem** każdej nowej fichy.
8. **BindableEvent w deferred mode** (default od 2023) — listenery NIE odpalają się sync z `:Fire()`, tylko na następnej klatce. Kod który `setState(X)` i od razu sprawdza stan listenerów (np. `aliveProvider() <= 0`) RACE'uje. Fix: `task.wait()` po Fire ZANIM polegasz na efektach listenerów, lub yield-first w pętlach (`task.wait` przed `endCheck()`, nie po).
8b. **`BindableFunction:Invoke` YIELDUJE** (lekcja 2026-09-16, kosztowała godzinę diagnozy). Siostra zasady 8: `Invoke` jest synchroniczne i **czeka, aż skrypt po drugiej stronie skończy** — a ragdoll toolboxa stawia constrainty przez kilka klatek. Wywołane wprost z pętli oddaje sterowanie, więc **Heartbeat wchodzi w tę samą pętlę drugi raz, zanim zdążysz zapisać stan**. Objaw był taki: upadek z 52.5 studa naliczał się DWA razy (55 + 55 dmg = śmierć zamiast 45 HP), mimo że blokada „jedno lądowanie = jedna kara" była w kodzie — tylko ustawiana PO wywołaniu ragdolla, czyli za późno. Dwa wnioski: (a) **stan musi być spójny PRZED każdym wywołaniem, które może oddać sterowanie**; (b) ragdolla wołamy przez `task.spawn`, bo nie ma nic do zwrócenia. Poprawione w `FallDamageService` i w `BombService` (tam `Invoke` w pętli po ofiarach wstrzymywał obsługę kolejnych trafionych).
9. **RemoteEvent NIE buforuje** — jeśli klient nie ma `OnClientEvent:Connect` w momencie `:FireAllClients`, event jest stracony. Klient musi podpiąć listenery PRZED `WaitForChild` (które yielduje). Plus serwer musi replikować aktualny state na `PlayerAdded` (`GameLoopService.replicateTo(player)`).
10. **HUD ScreenGui ResetOnSpawn=false** — domyślnie `true` → odświeża HUD przy każdym `LoadCharacter` (czyli przy starcie każdej rundy gracz traci listener Connect z poprzedniego HUD instance).
11. **Nowy R15 character rig** — Roblox zmienił charakter rig. Stare Motor6D już nie są default. Nowy character ma 14× BallSocketConstraint (LimitsEnabled, niskie kąty) + 15× AnimationConstraint (animation drivers) + 0 Motor6D. Custom ragdoll patternem destroy Motor6D NIE działa — trzeba disable AnimationConstraint + rozluźnić istniejące BallSocketConstraint upper angles. **W tym projekcie używamy toolbox ARTFVL Ragdoll** (folder w Workspace, kopiuje się do PlayerGui przy joinie) — działa, bo on dodaje altrootmotor (Motor6D HRP→UpperTorso) + osobne BallSocket constraints w `RagdollConstraints` folder. BombService wywołuje `PlayerGui.ragdoll.functions.ragdoll:Invoke(velocity)` BindableFunction, plus `variables.ragdoll.Value = false` po duration unragdolluje. Listener w toolbox `ragdollserver` script musi być uncommented (linia ~449).
12. **Network ownership** dla character — player character ma `NetworkOwner = LocalPlayer` (klient kontroluje physics). Server-side Motor6D destroy są nadpisywane klient prediction. Aby server wykonał ragdoll, trzeba `SetNetworkOwner(nil)` na każdą BasePart (tylko unanchored).
13. **DataStore** — używamy `UpdateAsync` (atomic, nie GetAsync+SetAsync race). Session lock per wejście gracza, retry exp backoff (6 prób load / 3 save), auto-save 60s, BindToClose force-save wszystkich graczy (max 30s). Studio wymaga "Enable Studio Access to API Services" w Game Settings → Security żeby działało.
14. **execute_luau MCP ma osobny module cache** — gdy testujesz przez execute_luau `require()` dostaje NOWĄ instancję modułu (osobne `cache` tabele, osobne BindableEvent). NIE polegaj na nim do server-side state inspection. Sposób na test: dodaj prints w services, restart Play, czytaj F9 logi. ⚠️ **UZUPEŁNIENIE 2026-09-21: ten cache TRZYMA SIĘ MIĘDZY WYWOŁANIAMI `execute_luau`.** Pierwszy `require` ładuje aktualne źródło, każdy następny zwraca TĘ SAMĄ tabelę — więc po synchronizacji Rojo `require(Config)` pokazuje STARE wartości i wygląda to jak „Rojo nie dowiozło”. **Do sprawdzania, czy kod dojechał, używać `script_grep` albo `.Source`, NIGDY `require`.** Kosztowało jedno podejście: `glassRadius` czytał się jako 60, choć na dysku było 35.
**26.10 — modele itemów:** Studs usunięte WYŁĄCZNIE z modeli Bomby, Blueprinta/Mostu, Haka, Napoju, RPG i C4 w ReplicatedStorage i na wystawie WeaponShopScene. Mapa, lobby, pozostałe sceny, gotówka i postać zachowują dotychczasowe Studs. Nie rozszerzać tej decyzji na otoczenie ani UI; narzędzia mapy nadal przywracają Studs.

15. **Wygląd nowego parta: `MaterialVariant` + `SurfaceType`** (lekcja 2026-09-13, dwa RÓŻNE mechanizmy, oba trzeba przenieść). (a) **`MaterialVariant` to osobna właściwość od `Material`** i na niej stoi cały look mapy: 25 233 z 25 332 partów w `Workspace.Map` ma `Material = Plastic` + `MaterialVariant = "Studs"` (MaterialVariant w `MaterialService`, BaseMaterial Plastic, ColorMap `rbxassetid://10509831729`). Skopiowanie samego `Material` daje GOŁY plastik — to był objaw „party po wybuchu zmieniają teksturę" (w folderze `BlastDebris` 65 z 70 kawałków nie miało wariantu; te 5, które miały, to `launchWhole`, bo tam part leci w całości). (b) **`Instance.new("Part")` ma legacy surface'y** `TopSurface=Studs` / `BottomSurface=Inlet` (WedgePart: Bottom=Inlet) — to GEOMETRYCZNE guzki, nie tekstura; mapa ma wszystkie 6 ścian `Smooth`, więc świeży part odstaje. Jedno miejsce, które o tym decyduje: **`Utils.copyAppearance(source, target)`** (kolor, materiał, wariant, transparency, reflectance, cień, surface'y) gdy part powstaje Z innego parta — gruz, remnanty, fall-fracture, kosmetyczne odłamki klienta (te próbkują wariant przez `Sample.variant`). `Utils.smoothSurfaces(part)` gdy oryginału nie ma. **Dotyczy KAŻDEJ nowej ficzury spawnującej party.** (c) **„KOLOR W GRZE ≠ KOLOR W PROPERTIES" — OBJAW POTWIERDZONY, PRZYCZYNA NIEUSTALONA** (2026-09-20, zgłoszenie „ręka ma kolor koszulki, a nie skóry"). Postać miała `Color` ustawiony poprawnie **i na serwerze, i na kliencie** — a w grze dłoń renderowała się w kolorze sąsiada (rękawa). Zmiana `Material` na inny natychmiast przywracała prawidłowy kolor. Widać to na **najmniejszych** częściach: dłoń i stopa mają 0.30 studa. ⚠️ **Nie szukać tego w logice, która kolor ustawia — dane są dobre.** Sprawdzone w Play: `Plastic` ❌, **`SmoothPlastic` ❌ (nie wracać — wygląda na oczywisty wybór i NIE działa)**, `Rock` ✅. Pierwsza hipoteza — globalne nadpisanie `MaterialService.Plastic = "Studs"`, którego mapa potrzebuje, a które łapie każdy part z `Material = Plastic` i pustym `MaterialVariant`, czyli też postać ze `StarterCharacter` — **jest NIEWYSTARCZAJĄCA**: w pomiarze 20.09 istniał dokładnie JEDEN wariant (`Studs`, `BaseMaterial = Plastic`; obecnie materiałów jest więcej), a pole `MaterialService.SmoothPlastic` przyjmuje wyłącznie wariant o `BaseMaterial = SmoothPlastic`, więc nadpisane być nie może — a jest zepsute. Zostają dwie możliwości: nadpisanie `Plastic` łapie całą rodzinę gładkiego plastiku, albo to wspólny kubełek renderowania, a zmiana materiału tylko wymusza przebudowę. **Rozstrzyga jeden test: wyczyścić `MaterialService.Plastic` i sprawdzić dłoń na `Plastic`.** Obejście w kodzie: `AppearanceDefinitions.BodyMaterial` — jedno miejsce. ⚠️ **45 pól nadpisań `MaterialService` jest NIEDOSTĘPNYCH do odczytu z MCP** (`lacking capability RobloxScript`, ta sama ściana co `Lighting.Technology`) — trzeba obejrzeć w Properties.

---

## Stack & struktura

- **Rojo 7.7.0-rc.1** (Aftman), VS Code, Luau, Roblox Studio.
- **Struktura repo** (sprawdzona 2026-10-23):
  - `src/server/Services/` — 33 serwisy; `src/client/Controllers/` — 37 modułów (kontrolery i helpery; stan 27.10) (opisy, pułapki i historia decyzji: **`docs/ARCHITECTURE.md`**)
  - `src/server/Structure/` — **NOWE 2026-09-24, destrukcja v4**: czyste moduły konstrukcji spoza `Services` (nie mają `init`): `StructureCore` (klasyfikacja, solver, odcisk geometrii — wspólne dla bake'u i gry), `StructureBake` (analiza budynku, podgląd kolorami, zapis danych), `BuildingState` (stan chunków jednego budynku, CAS), `CollapsePlanner` (grupy kolapsu), `Pieces` (geometria kawałków), `StructureTests` (scenariusze offline). W grze ładują je `StructuralService` i `CollapseService`; w Studio — skrypty `STRUCTURE_*.luau` z korzenia repo.
  - `src/shared/Modules/` — `Config` (WSZYSTKIE liczby), `ItemDefinitions`, `Remotes` (tworzy RemoteEventy w runtime — folderu `src/shared/Remotes` nie ma), `Utils`, `Destructible`, `Fracture`, `Shockwave`, `Dev`, `AppearanceDefinitions`, `GrappleArc`, `Ladders`
  - **`docs/`** — dokumentacja referencyjna, czytana na żądanie (mapa niżej). **`docs/PROJECT_CONTEXT.md`** — kontekst dla asystenta od planowania (perspektywa gracza, bez kodu); Nie kopiować statusu: aktualizować `docs/STATUS.md`, a kontekst gracza ma do niego odsyłać. `docs/DESTRUCTION_PLAN.md` — aktualne reguły v4 na początku i historia v2/v3/v4 niżej — czytać przed dotykaniem destrukcji.
  - **SKRYPTY NAPRAWCZE W KORZENIU REPO** (Command Bar w Studio, EDIT mode, potem Cmd+S) — nie są częścią gry, tylko narzędziami do przywracania kontraktu mapy po bulk-apply materiału:
    - `LAMPS_LIGHTS.luau` — 36 kloszy latarni na `Neon` + `SurfaceLight`; TRYB 2 usuwa światła, TRYB 3 zamienia na PointLight.
    - `TRAFFIC_LIGHTS.luau` — 150 żarówek sygnalizatorów na `Neon`; TRYB 2 cofa.
    - `WINDOWS_GLASS.luau` — 367 szyb na `Material = Glass`; TRYB 2 cofa.
    - `LIGHTING_REVERT.luau` — cofnięcie wartości `Lighting` do stanu sprzed 2026-09-16.
    - `STRUCTURE_BAKE.luau` (2026-09-24, destrukcja v4) — NIE naprawczy, tylko narzędzie: analiza konstrukcji budynku (raport / kolory / zapis danych do `ServerStorage.StructureData`). Logika w `src/server/Structure/` (te same moduły ładuje gra przez `StructuralService`). Wymaga `rojo serve`. Klonuje CAŁY folder `Structure` (hard rule 14 + `script.Parent`). ⚠️ Wklejać CAŁY plik — Command Bar nie pamięta zmiennych między uruchomieniami; w Play Command Bar działa po stronie klienta i nie widzi `ServerScriptService`.
    - `STRUCTURE_TEST.luau` (2026-09-24) — scenariusze solvera/plannera v4 na OrangeBuilding (obliczenia, mapa się nie zmienia) + kolory stanu po bombach w parter.
    - ⚠️ **Każdy z nich identyfikuje cel po ROZMIARZE albo przezroczystości, NIGDY po właściwości, którą naprawia** — pierwsza wersja `LAMPS_LIGHTS` szukała klosza po `Material == Neon` i znajdowała zero partów dokładnie wtedy, kiedy była potrzebna.
  - `src/replicatedfirst/` — **NOWE 2026-09-16**: `ReplicatedFirst` (ekran ładowania). ⚠️ Dodanie nowej gałęzi do `default.project.json` **wymaga RESTARTU `rojo serve`** — Rojo czyta plik projektu tylko przy starcie, więc sam plik `.luau` nigdy nie dojedzie do Studio, dopóki Kacper nie zrestartuje serwera. **Zmiana `$properties` w ISTNIEJĄCEJ gałęzi dojeżdża BEZ restartu** (zmierzone 2026-09-23: `StarterPlayer.DevCameraOcclusionMode` pojawił się w Studio od razu).
  - **`default.project.json` → `StarterPlayer.$properties` = źródło prawdy dla ustawień kamery i postaci**: zoom 8-15, `EnableMouseLockOption = false`, **`DevCameraOcclusionMode = Zoom`** (2026-09-23; w placu był `Invisicam` = x-ray). Ustawienie zmienione w Studio ręcznie Rojo nadpisze przy synchronizacji — zmieniać TUTAJ.

## 🗺️ MAPA DOKUMENTACJI — PRZECZYTAJ, ZANIM ZACZNIESZ

Do 2026-09-23 wszystko siedziało w tym pliku: 185 KB, ~58 tys. tokenów ładowanych na start KAŻDEJ sesji. Teraz tu jest rdzeń zasad (bieżący STATUS jest w osobnym `docs/STATUS.md`), a reszta w `docs/` — **te pliki NIE ładują się same**. Ich pominięcie to najprostsza droga do powtórzenia odrzuconego podejścia albo zepsucia kontraktu, więc:

| Zanim zaczniesz… | przeczytaj |
|---|---|
| zmieniać serwis, kontroler albo moduł | **`docs/ARCHITECTURE.md`** → opis TEGO pliku: pułapki, kolejność inicjalizacji, „nie wracać do…” |
| dotykać czegoś, co Kacper stawia w Studio (mapa, lobby, sklep, lawa, szyby, latarnie, HUD, modele itemów, Lighting, ustawienia kamery) | **`docs/STUDIO_CONTRACT.md`** — nazwy tam opisane są kontraktem; rozjazd kod ↔ plac psuje grę po cichu |
| planować nową ficzurę: item, loadout, skiny, wygląd, pancerze, balans rundy | **`docs/ROADMAP.md`** — wizja Kacpra, decyzje, plan etapów, rozdziały badań (rig, ślizg, wygląd) |
| proponować podejście, które „wygląda na oczywiste” | lista ⛔ poniżej, potem **`docs/HISTORY.md`** i odpowiedni plik — sporo „oczywistych” rozwiązań już sprawdzono i odrzucono |
| balansować liczby | `Config.luau` + **`docs/ARCHITECTURE.md`** → „Bieżąca konfiguracja” |
| debugować „to nie działa” | 📌 LEKCJE PROCESOWE poniżej — zanim cokolwiek zmienisz |
| naprawiać błędy z przeglądu kodu (paczki 1-9) | **`docs/REVIEW_2026-09-29.md`** — lista ~70 punktów (M-/A-/B-), decyzje Kacpra, plan paczek i ich stan |

**Odesłania w tekście** („przy `FallDamageService`”, „patrz kontrakt”, „w TODO”, „ŚLISKI MOVEMENT”, „TRZY PUŁAPKI”) prowadzą do: opisów serwisów i kontrolerów → `ARCHITECTURE`; kontraktu Studio → `STUDIO_CONTRACT`; TODO, wizji i planów → `ROADMAP`; starych sesji → `HISTORY`. Wystarczy wyszukać frazę.

**Aktualizując dokumentację**: zasady — tutaj; STATUS — `docs/STATUS.md`; testy — `docs/TESTY.md`; kontrakt i szczegóły — w odpowiednim pliku `docs/`. Nie kopiować treści między plikami: dwie kopie to dwie okazje, żeby się rozjechały (audyt 2026-09-23 znalazł w starym, jednym pliku 17 sprzeczności — m.in. dwa różne pomiary lawy naraz).

## Granice pracy Kacpra

- Maks 2-3h dziennie. **Nie pracuje do 2 w nocy.**
- Jeśli sesja przekracza 2h — Codex proponuje break i kontynuację jutro.
- Plan Day 1–7 z GDD jest historycznym podziałem prac, nie aktualnym kalendarzem wydania.

---

## Czego NIE implementujemy w v1.0 (GDD sekcja 13)

Voting mapy, lobby parkour, pożary, trzęsienia, blackout, bounty, steal monet, king zone, niewidzialne trapy, łamliwe podłogi, ruchome windy, ukryte tunele, lava geyser. **Każde "może dodam..."** → "to do PRZYSZŁOŚCI, nie v1.0".

---

## DESIGN: szybka i dynamiczna gra

ESCAPE LAVA ma być **szybkie i dynamiczne** — nie kontemplacyjne, nie 5+ minutowe rundy.

- **Runda projektowo 80 s, bez faz lawy**; osobno przygotowanie i odliczanie 3-2-1 (od 18.10). Obecnie 240 s testowo — patrz STATUS.
- **Lobby przerwa 25 s** (decyzja 19.10) — czas na zakup, wybór loadoutu i dołączenie ekipą; sklep skinów to dalszy kierunek.
- **Lawa płynnie przyspiesza 0 → 3,0 stud/s w produkcji** (bez faz, od 11.10).
- **Krótkie rundy = TikTok-friendly** — cały gameplay loop mieści się w 1-2 minutach (clip-friendly).

Każde "może rozszerzymy fazy", "może dodajmy więcej czasu" → **NIE**. Dynamika > kompleksowość. Jak gra wydaje się za szybka, najpierw test z prawdziwymi graczami zanim wydłużymy.

---

## Stan projektu i mapa kontekstu

Przed wznowieniem pracy przeczytaj [STATUS.md](STATUS.md). Kolejność i właściciele dokumentów są w [README.md](README.md). [DO_RELEASE.md](DO_RELEASE.md) jest checklistą wydania, [TESTY.md](TESTY.md) zawiera wyniki i przypadki do Play. Archiwum nie stanowi bieżących instrukcji. Gdy nazwa wskazana w starym odnośniku nie istnieje, wyszukaj ją w archiwum i porównaj z kodem.

## ⛔ Sprawdzone i odrzucone

> `LoadCharacterWithHumanoidDescription` · wyrównywanie skal postaci · przełączanie `CustomPhysicalProperties` HRP/Head · rozluźnianie limitów stawów · `AdjustSpeed` na animacji chodu · preset „Consistent Gameplay" · bramki raycastowe oprawy lawy (`isExposed` / `isLavaOpenAt`) · `SmoothPlastic` jako materiał ciała · **(destrukcja, 2026-09-23)** kawałki dziur i drobnica jako fizyka SERWERA · pass podparcia zrzucający wszystko „niepodparte” bez porównania przed/po · kasowanie pociętego parta i stawianie resztek od nowa (zamiast przycinania oryginału) · emiter pyłu tworzony na serwerze per ranny part · **kolizja lokalnego gruzu z postaciami** (także „grupa kolizji dla postaci” — zależy od czujnika podłogi Humanoida i kamery, których nie da się sprawdzić bez gry; gruz bez kolizji działa z definicji) · **(destrukcja v4, 2026-09-24)** oparcie na POZIOMYM elemencie zerujące zasięg (wieża „wisiała” na wsporniku sąsiedniej bryły — zasięg się dziedziczy, zeruje go tylko pion) · boczne trzymanie pionu przez strop (tylko belka, `LateralHoldsVertical`) · szerokość styku liczona z luzem (przypisywała podparcie sąsiednim polom stropu) · szacunek „1 bomba = 1 chunk” · natychmiastowe oddawanie klientom grup kolapsu ponad budżetem (serwer je kasował → znikały piętra) · dekoracje cięte jak ściany (pudła/szafki — padają w całości jako rekwizyt) · **(destrukcja v4, 2026-09-25)** kotwiczenie w miejscu grupy, która po odkotwiczeniu się nie ruszyła (zostawała w powietrzu — teraz siatka zaklinowania) · fragment kruszenia wyrzucany bez filtra nachodzeń · przygniecenie z prędkości BEZWZGLĘDNEJ bryły (raniło jeźdźca) · próg filtra nachodzeń dla styku z BOKU (każde nachodzenie z boku trzyma tarciem). · **(drabiny, 2026-10-08)** wspinanie silnika wymuszane `ChangeState(Climbing)` (puszczasz W → spadasz) · własny tryb drabiny z `LinearVelocity` (W/S/wiszenie/odskok — Kacper: „gówno”) · **(08.10)** półprzezroczysty ghost mostu z `Highlight` jako ratunkiem na tle lawy (znikał) · tryby grafiki Ziemniak/Pełny z wyborem gracza (zastąpione jednym profilem) · cała mapa kasowana i klonowana po każdej rundzie (`MapService` — teraz tylko naruszone jednostki) · `CanQuery = false` na przechodniej dekoracji (destrukcja jej nie widzi → wisi).
>

Rocket jump został wycofany 21.10; nie proponować go jako kolejnego etapu RPG. Nie podbijać kierunku kamery odrzutem RPG (bez celownika kamera służy do celowania). Własne kierunkowe animacje chodu/idle/skoku wycofane 11.10; aktywny jest oryginalny Animate i osobny gest F. Nie wracać do dodatkowych slotów za każdy item — loadout ma trzy.

## 📌 Lekcje procesowe

> 📌 **LEKCJE PROCESOWE — DROGO KUPIONE, CZYTAĆ PRZED DEBUGOWANIEM:**
> 1. **Najpierw ustal, CO DOKŁADNIE widzi człowiek.** „Ślizganie" = responsywność sterowania, nie ruch stóp; trzy zmiany i cztery pomiary poszły w rzecz, która nie była problemem.
> 2. **Przy „nie widać X" sprawdź najpierw, GDZIE X naprawdę jest**, zanim poprawisz, jak jest rysowane. Ghost mostu nie był maskowany — stawiał się pod lawą.
> 3. **Hipoteza spójna z objawem bywa nieprawdziwa.** Sortowanie przezroczystości i globalne nadpisanie `MaterialService` tłumaczyły objawy idealnie i oba były błędne.
> 4. **Przy trzeciej nieudanej próbie cofaj się, nie łataj.**
> 5. **Objaw „to nie działa" bywa niezsynchronizowanym kodem.** W tej sesji DWA RAZY zmiany nie dojechały do Studio, mimo że były na dysku. **Zanim ocenisz efekt — sprawdź `rojo serve` i Connected.** 2026-09-22 po raz trzeci: po restarcie Studio `rojo serve` nie chodził i wszystkie 5 zmienionych plików było w Studio STARYCH. 2026-09-25 po raz czwarty — Kacper był przekonany, że Rojo jest podpięte, a procesu nie było: **na starcie sesji `ps aux | grep rojo`** (stary kod zapisany w placu przechodzi sprawdzenie znacznika, więc znacznik trzeba brać z ZMIANY z tej sesji). **Sprawdzenie z MCP bez odpalania Play**: w Edit `pcall(loadstring, skrypt.Source)` — `nil` + komunikat = błąd składni; znacznik z nowej wersji w `.Source` = Rojo dowiozło. To obserwacja, nie test (zasada 2026-09-20). ⚠️ NIE przez `require` — hard rule 14. 2026-09-26 po raz piąty, INNY wariant: `rojo serve` chodził, Studio było Connected, Rojo miało nową wersję `BombService` u siebie (`curl localhost:34872/api/read/<rootInstanceId>`), a wtyczka jej NIE nałożyła (zapis z 19:09, po starcie Studio; w Output `… joined live editing session` — Team Create z kolegą, związek niesprawdzony). Naprawił Disconnect → Connect. 2026-09-27 po raz szósty, TEN SAM wariant: Rojo miało nowe `StructuralService` i `Config` (identyczne z dyskiem), Studio w Edit i połączone (port połączenia inny niż rano — wtyczka łączyła się od nowa), a zmiany nie weszły. Hipoteza NIESPRAWDZONA: po ponownym połączeniu wtyczka czeka na „Accept” w oknie zmian. **„Connected” nie znaczy „dojechało” — porównywać ZAWARTOŚĆ**: `#Source` + suma `h = (h*31 + bajt) % 2147483647` w Luau (Edit) i to samo w Pythonie na dysku; znacznik łapie tylko to, czego się spodziewasz.
> 6. **Kacper testował raz na pliku `AutoRecovery`, nie na swoim placu.** Studio raportuje się wtedy jako `<placeId>_AutoRecovery_0.rbxl` — `list_roblox_studios` to pokazuje. Przy „u mnie tego nie ma" sprawdzić nazwę instancji.
> 7. **Przy kolejnym feedbacku do TEJ SAMEJ mechaniki zbierz wszystkie dotychczasowe wymagania w jedną tabelę, ZANIM cokolwiek zmienisz.** Hak: trzy wersje lotu, każda naprawiała ostatnie zgłoszenie i łamała poprzednie (kierunek → dotarcie → łuk). Dopiero tabela „wersja × wymaganie" pokazała, że potrzebny jest INNY MODEL, a nie czwarte strojenie liczb. Pytanie kontrolne przed każdą poprawką: **czy to nie cofa czegoś, co Kacper już zaakceptował?**
> 8. **Plan oparty na zachowaniu silnika — sprawdź najpierw USTAWIENIE, które to zachowanie włącza.** Kamera zza ramienia zakładała, że kamera Robloxa zatrzymuje się na ścianach (tryb `Zoom`); sprawdziłem zakres zoomu, a nie tryb zasłaniania — plac miał `Invisicam`, i wyszedł x-ray. Przy kamerze: najpierw `StarterPlayer.DevCameraOcclusionMode`.
> 9. **Zanim zaczniesz stroić liczby przy „laguje”, przepuść algorytm przez NIETKNIĘTĄ mapę w Edit.** Log `spadło=472` wyglądał na balans budżetu gruzu („budżet wysycony”); symulacja passu podparcia na mapie BEZ żadnego wybuchu pokazała ~3500 partów „niepodpartych” z designu — czyli błąd reguły, nie liczba do przykręcenia. Pomiar w Edit to odczyt, nie test gry (zasada 2026-09-20), a daje odpowiedź w minutę.
> 10. **Wszystko, co istnieje tylko u jednego klienta, NIE MOŻE wpływać na grę — sprawdź KOLIZJE i PROMIENIE.** (2026-09-23, złapane przez Kacpra pytaniem, nie przeze mnie.) Lokalny gruz miał kolizję z postacią: w trybie Pełnym dało się stanąć na kawałku, którego gracz na Ziemniaku nie ma. Do tego pułapka silnika: **`CanQuery = false` działa TYLKO przy `CanCollide = false`** — z kolizją lokalny part łapał promienie klienta (celownik mostu!). Przy każdym lokalnym obiekcie pytanie kontrolne: czy ktoś może na nim stanąć, czy popycha, czy trafi w niego promień, którego wynik idzie do serwera?
> 11. **Przy zgłoszeniu z Play najpierw przeczytaj LOG TEJ SESJI (`get_console_output`), dopiero potem symuluj.** (2026-09-24.) „Górne piętra spadają za szybko” wyglądało na błąd solvera; symulacja w Edit pokazała, że logika jest dobra (piony 3. piętra padają dopiero przy ~93% zniszczonego parteru), a log `[Collapse]` z sesji Kacpra — że 16 z 25 grup poszło ponad budżetem do klientów i serwer je kasował. **Symulacja sprawdza LOGIKĘ, log sprawdza WYKONANIE** — potrzebne oba, a log jest tańszy. Pilnować, żeby log był z NOWEJ sesji (zasada 2026-09-20, punkt b).
> 12. **Logika offline ≠ fizyka w grze — przy destrukcji mierz WYKONANIE rejestratorem.** (2026-09-25.) Symulacja w Edit mówiła, że pod spadającymi grupami stoi coś tylko w 5 z 21 przypadków; w grze 21 z 25 grup nie ruszyło się ani o stud. Różnicę robiły rzeczy, których solver nie widzi: fragmenty i kikuty zostające w mapie, tarcie, 0,25 s kolizji przekazanych kawałków. Najtańszy pomiar: na serwerze Y korzenia każdej odkotwiczonej bryły przy starcie i przy osiadaniu („spadło X z Y”) — jedna liczba mówi więcej niż zrzuty ekranu. Log gry sam podaje teraz, co trzyma zaklinowaną grupę (część v4 + stan chunka).
> 13. Problemy z MCP diagnozować z logu bieżącej sesji. Obejście protokołu z 26.09 i jego historyczne ścieżki są w archiwum; nie zakładać jego obecności ani konieczności dziś. Nie zabijać cudzych procesów StudioMCP.
> 14. **Model z Humanoidem w Edit ≠ ten sam model w Play.** (27.10.) Kopia postaci w przymierzalni wyglądała w Edit idealnie z każdej strony, a w grze miała szparę pod głową: po wstawieniu do świata silnik odpala automatyczne skalowanie i przebudowę stawów (głowa 1,2 → 1,0 studa). Pomiar na kliencie w Play (zbudować model tą samą funkcją, wstawić, odczekać 0,5 s, zmierzyć) dał odpowiedź w minutę po godzinie zrzutów z Edit.
> 15. **Skrypt MCP, który PRZENOSI istniejący obiekt, przenosi go na samym końcu, do kontenera już wstawionego do placu.** (27.10.) Błąd w połowie skryptu zostawił zębatkę ustawień w ramce, która jeszcze nie była w HUD — zniknęła z placu. Odzyskane jednym `ChangeHistoryService:Undo()`: każde `execute_luau` ze zmianami to osobny krok „Assistant N” (odczyt kroku nie tworzy; `GetCanUndo()` podaje nazwę ostatniego).
