# CLAUDE.md — zasady kolaboracji w ESCAPE LAVA

Plik czytany automatycznie przez Claude Code na start każdej sesji w tym katalogu.
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
| Logika gry (services, state machine, mechaniki) | **Claude** w kodzie |
| RemoteEventy, BindableEventy, kontrakty komunikacji | **Claude** w kodzie |
| Balansowanie liczb (Config.luau) | **Claude** + Kacper review |
| DataStore, anti-cheat, rate limiting | **Claude** |

---

## Co Claude **NIE robi** (zero tolerancji)

- ❌ **NIE tworzy placeholder budynków / mapy** w kodzie (PlaceholderMap, generated towers itp.).
- ❌ **NIE tworzy ScreenGui programmatic** (Instance.new("ScreenGui") + TextLabel'e).
- ❌ **NIE buduje "spawn points" ani lobby spot** w kodzie — czyta z Workspace gdzie Kacper je postawił.
- ❌ **NIE ingeruje w respawn / charakter spawning** bez pytania (Kacper mówi "respa już jest" = nie tyka).
- ❌ **NIE wybiera za Kacpra** sensible defaults gdy są decyzje architektoniczne do podjęcia — pyta.
- ❌ **NIE uruchamia Play (`start_stop_play`) i NIE testuje sam przez MCP** (zasada 2026-09-20). **Testy przeprowadza wyłącznie Kacper.** Claude dostarcza kod plus **konkretną listę do sprawdzenia** („zeskocz z dachu — ma zaboleć i wywrócić", „wejdź na drabinę — ma NIE wywrócić"), a nie własny werdykt „działa".
  - **Dlaczego — kupione drogo w sesjach 2026-09-16/19:** (a) `start_stop_play` z MCP **przerywa sesję Kacpra w środku** — kilka razy zatrzymałem mu Play dokładnie wtedy, gdy sam testował; (b) **automatyczny harness DWA RAZY dał fałszywy wynik**: raz mierzył HP już PO obrażeniach z poprzedniego upadku i pokazał „0 dmg", choć system działał poprawnie; raz czytał `LogService:GetLogHistory()` ze **starej** sesji Play i „potwierdził" błąd, którego w nowym kodzie już nie było. **Fałszywy wynik testu jest gorszy niż brak testu** — prowadzi do naprawiania rzeczy, która nie jest zepsuta, i do raportowania Kacprowi nieprawdy.
  - **Co MCP zostaje do robienia (to zostaje i jest cenne):** odczyty — `inspect_instance`, `search_game_tree`, `script_read`, pomiary geometrii, sprawdzenie czy Rojo dowiozło kod do Studio. To są **obserwacje, nie testy**, i wielokrotnie skróciły diagnozę: 86% tafli lawy zakryte geometrią, wysokość budynków 109, brak `Texture` na lawie, stara wersja pliku w Studio przy odłączonym Rojo.

## Co Claude **dostarcza** zamiast tego

- ✅ **Kontrakt nazw**: lista obiektów które kod oczekuje w Workspace / StarterGui (np. `Workspace.SpawnPoints/*` BasePart'y → kod weźmie ich `.Position`).
- ✅ **Logikę usług** czystą, bez UI / placeholder geometrii.
- ✅ **Pytania ZANIM** zacznie pisać kod dla nowej rzeczy lub zmieniać istniejącą logikę.

---

## Workflow: każda zmiana / nowa rzecz

1. **Claude zadaje 2-4 konkretne pytania** (przez AskUserQuestion gdy są wybory A/B/C) zanim zacznie pisać kod nowego ficzeru lub refactoruje istniejący.
2. **Kacper odpowiada** — wspólna wizja.
3. Dopiero wtedy Claude **pisze kod** i **dostarcza kontrakt nazw** dla rzeczy które Kacper ma postawić w Studio.
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
13. **DataStore** — używamy `UpdateAsync` (atomic, nie GetAsync+SetAsync race). Session lock (`data._sessionId`), retry exp backoff x3, auto-save 60s, BindToClose force-save wszystkich graczy (max 30s). Studio wymaga "Enable Studio Access to API Services" w Game Settings → Security żeby działało.
14. **execute_luau MCP ma osobny module cache** — gdy testujesz przez execute_luau `require()` dostaje NOWĄ instancję modułu (osobne `cache` tabele, osobne BindableEvent). NIE polegaj na nim do server-side state inspection. Sposób na test: dodaj prints w services, restart Play, czytaj F9 logi. ⚠️ **UZUPEŁNIENIE 2026-09-21: ten cache TRZYMA SIĘ MIĘDZY WYWOŁANIAMI `execute_luau`.** Pierwszy `require` ładuje aktualne źródło, każdy następny zwraca TĘ SAMĄ tabelę — więc po synchronizacji Rojo `require(Config)` pokazuje STARE wartości i wygląda to jak „Rojo nie dowiozło”. **Do sprawdzania, czy kod dojechał, używać `script_grep` albo `.Source`, NIGDY `require`.** Kosztowało jedno podejście: `glassRadius` czytał się jako 60, choć na dysku było 35.
15. **Wygląd nowego parta: `MaterialVariant` + `SurfaceType`** (lekcja 2026-09-13, dwa RÓŻNE mechanizmy, oba trzeba przenieść). (a) **`MaterialVariant` to osobna właściwość od `Material`** i na niej stoi cały look mapy: 25 233 z 25 332 partów w `Workspace.Map` ma `Material = Plastic` + `MaterialVariant = "Studs"` (MaterialVariant w `MaterialService`, BaseMaterial Plastic, ColorMap `rbxassetid://10509831729`). Skopiowanie samego `Material` daje GOŁY plastik — to był objaw „party po wybuchu zmieniają teksturę" (w folderze `BlastDebris` 65 z 70 kawałków nie miało wariantu; te 5, które miały, to `launchWhole`, bo tam part leci w całości). (b) **`Instance.new("Part")` ma legacy surface'y** `TopSurface=Studs` / `BottomSurface=Inlet` (WedgePart: Bottom=Inlet) — to GEOMETRYCZNE guzki, nie tekstura; mapa ma wszystkie 6 ścian `Smooth`, więc świeży part odstaje. Jedno miejsce, które o tym decyduje: **`Utils.copyAppearance(source, target)`** (kolor, materiał, wariant, transparency, reflectance, cień, surface'y) gdy part powstaje Z innego parta — gruz, remnanty, fall-fracture, kosmetyczne odłamki klienta (te próbkują wariant przez `Sample.variant`). `Utils.smoothSurfaces(part)` gdy oryginału nie ma. **Dotyczy KAŻDEJ nowej ficzury spawnującej party.** (c) **„KOLOR W GRZE ≠ KOLOR W PROPERTIES" — OBJAW POTWIERDZONY, PRZYCZYNA NIEUSTALONA** (2026-09-20, zgłoszenie „ręka ma kolor koszulki, a nie skóry"). Postać miała `Color` ustawiony poprawnie **i na serwerze, i na kliencie** — a w grze dłoń renderowała się w kolorze sąsiada (rękawa). Zmiana `Material` na inny natychmiast przywracała prawidłowy kolor. Widać to na **najmniejszych** częściach: dłoń i stopa mają 0.30 studa. ⚠️ **Nie szukać tego w logice, która kolor ustawia — dane są dobre.** Sprawdzone w Play: `Plastic` ❌, **`SmoothPlastic` ❌ (nie wracać — wygląda na oczywisty wybór i NIE działa)**, `Rock` ✅. Pierwsza hipoteza — globalne nadpisanie `MaterialService.Plastic = "Studs"`, którego mapa potrzebuje, a które łapie każdy part z `Material = Plastic` i pustym `MaterialVariant`, czyli też postać ze `StarterCharacter` — **jest NIEWYSTARCZAJĄCA**: w placu istnieje dokładnie JEDEN wariant (`Studs`, `BaseMaterial = Plastic`), a pole `MaterialService.SmoothPlastic` przyjmuje wyłącznie wariant o `BaseMaterial = SmoothPlastic`, więc nadpisane być nie może — a jest zepsute. Zostają dwie możliwości: nadpisanie `Plastic` łapie całą rodzinę gładkiego plastiku, albo to wspólny kubełek renderowania, a zmiana materiału tylko wymusza przebudowę. **Rozstrzyga jeden test: wyczyścić `MaterialService.Plastic` i sprawdzić dłoń na `Plastic`.** Obejście w kodzie: `AppearanceDefinitions.BodyMaterial` — jedno miejsce. ⚠️ **45 pól nadpisań `MaterialService` jest NIEDOSTĘPNYCH do odczytu z MCP** (`lacking capability RobloxScript`, ta sama ściana co `Lighting.Technology`) — trzeba obejrzeć w Properties.

---

## Stack & struktura

- **Rojo 7.7.0-rc.1** (Aftman), VS Code, Luau, Roblox Studio.
- **Struktura repo** (stan 2026-09-23):
  - `src/server/Services/` — 27 serwisów; `src/client/Controllers/` — 21 kontrolerów (opisy, pułapki i historia decyzji: **`docs/ARCHITECTURE.md`**)
  - `src/server/Structure/` — **NOWE 2026-09-24, destrukcja v4**: czyste moduły konstrukcji spoza `Services` (nie mają `init`): `StructureCore` (klasyfikacja, solver, odcisk geometrii — wspólne dla bake'u i gry), `StructureBake` (analiza budynku, podgląd kolorami, zapis danych), `BuildingState` (stan chunków jednego budynku, CAS), `CollapsePlanner` (grupy kolapsu), `Pieces` (geometria kawałków), `StructureTests` (scenariusze offline). W grze ładują je `StructuralService` i `CollapseService`; w Studio — skrypty `STRUCTURE_*.luau` z korzenia repo.
  - `src/shared/Modules/` — `Config` (WSZYSTKIE liczby), `ItemDefinitions`, `Remotes` (tworzy RemoteEventy w runtime — folderu `src/shared/Remotes` nie ma), `Utils`, `Destructible`, `Fracture`, `Shockwave`, `Dev`, `AppearanceDefinitions`, `GrappleArc`
  - **`docs/`** — dokumentacja referencyjna, czytana na żądanie (mapa niżej). **`PROJECT_CONTEXT.md`** — kontekst dla asystenta od planowania (perspektywa gracza, bez kodu); **aktualizować razem z tym plikiem**. `DESTRUCTION_PLAN.md` — plan destrukcji v2 + **rozdział v3 (2026-09-23)** — czytać przed dotykaniem destrukcji.
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

Do 2026-09-23 wszystko siedziało w tym pliku: 185 KB, ~58 tys. tokenów ładowanych na start KAŻDEJ sesji. Teraz tu jest rdzeń (zasady, STATUS, lekcje, lista „nie proponować ponownie”), a reszta w `docs/` — **te pliki NIE ładują się same**. Ich pominięcie to najprostsza droga do powtórzenia odrzuconego podejścia albo zepsucia kontraktu, więc:

| Zanim zaczniesz… | przeczytaj |
|---|---|
| zmieniać serwis, kontroler albo moduł | **`docs/ARCHITECTURE.md`** → opis TEGO pliku: pułapki, kolejność inicjalizacji, „nie wracać do…” |
| dotykać czegoś, co Kacper stawia w Studio (mapa, lobby, sklep, lawa, szyby, latarnie, HUD, modele itemów, Lighting, ustawienia kamery) | **`docs/STUDIO_CONTRACT.md`** — nazwy tam opisane są kontraktem; rozjazd kod ↔ plac psuje grę po cichu |
| planować nową ficzurę: item, loadout, skiny, wygląd, pancerze, balans rundy | **`docs/ROADMAP.md`** — wizja Kacpra, decyzje, plan etapów, rozdziały badań (rig, ślizg, wygląd) |
| proponować podejście, które „wygląda na oczywiste” | lista ⛔ w STATUS niżej, potem **`docs/HISTORY.md`** i odpowiedni plik — sporo „oczywistych” rozwiązań już sprawdzono i odrzucono |
| balansować liczby | `Config.luau` + **`docs/ARCHITECTURE.md`** → „Bieżąca konfiguracja” |
| debugować „to nie działa” | 📌 LEKCJE PROCESOWE w STATUS niżej — zanim cokolwiek zmienisz |

**Odesłania w tekście** („przy `FallDamageService`”, „patrz kontrakt”, „w TODO”, „ŚLISKI MOVEMENT”, „TRZY PUŁAPKI”) prowadzą do: opisów serwisów i kontrolerów → `ARCHITECTURE`; kontraktu Studio → `STUDIO_CONTRACT`; TODO, wizji i planów → `ROADMAP`; starych sesji → `HISTORY`. Wystarczy wyszukać frazę.

**Aktualizując dokumentację**: STATUS i zasady — tutaj; wszystko inne — w odpowiednim pliku `docs/`. Nie kopiować treści między plikami: dwie kopie to dwie okazje, żeby się rozjechały (audyt 2026-09-23 znalazł w starym, jednym pliku 17 sprzeczności — m.in. dwa różne pomiary lawy naraz).

## Granice pracy Kacpra

- Maks 2-3h dziennie. **Nie pracuje do 2 w nocy.**
- Jeśli sesja przekracza 2h — Claude proponuje break i kontynuację jutro.
- Plan dni z GDD sekcja 11 (Day 1 fundament → Day 7 launch).

---

## Czego NIE implementujemy w v1.0 (GDD sekcja 13)

Voting mapy, lobby parkour, pożary, trzęsienia, blackout, bounty, steal monet, king zone, niewidzialne trapy, łamliwe podłogi, ruchome windy, ukryte tunele, lava geyser. **Każde "może dodam..."** → "to do PRZYSZŁOŚCI, nie v1.0".

---

## DESIGN: szybka i dynamiczna gra

ESCAPE LAVA ma być **szybkie i dynamiczne** — nie kontemplacyjne, nie 5+ minutowe rundy.

- **Runda ~80s total** (Spawn 5s + Easy 20s + Mid 20s + Hard 20s + Endgame 15s).
- **Lobby przerwa 30s** — wystarczy żeby kupić item, zmienić skin, dołączyć ekipą.
- **Lawa szybka od początku** — 0.6 stud/s w Easy, 3.0 w Endgame.
- **Krótkie fazy = TikTok-friendly** — cały gameplay loop mieści się w 1-2 minutach (clip-friendly).

Każde "może rozszerzymy fazy", "może dodajmy więcej czasu" → **NIE**. Dynamika > kompleksowość. Jak gra wydaje się za szybka, najpierw test z prawdziwymi graczami zanim wydłużymy.

---

## STATUS PROJEKTU (ostatnia aktualizacja 2026-09-26)

> 🧭 **START NASTĘPNEJ SESJI (stan na koniec 2026-09-26)**: (1) `ps aux | grep rojo` — chodzi `rojo serve` uruchomiony przez rozszerzenie VS Code (PID był 4260, port 34872, cwd = repo); jeśli go nie ma, uruchomić w zakładce terminala; (2) ✅ ZROBIONE 26.09 wieczorem (MCP wrócił, lekcja 13): wszystkie 14 zmienionych skryptów jest w Studio identycznych z dyskiem (rozmiar + suma kontrolna) i się kompiluje (`loadstring`); `BombService` dojechał dopiero po Disconnect → Connect we wtyczce Rojo (lekcja 5, wariant piąty); po ponownym połączeniu zmiany dojeżdżają na bieżąco (respawn z 26.09 dojechał sam), ale po każdej zmianie kodu dalej porównywać zawartość, zanim Kacper przetestuje; (3) zebrać wynik testu Kacpra z kolegą (lista niżej) + linie `[Bomb] … miss` / `[Bomb] BŁĄD destrukcji` z Output; (4) ✅ decyzja Kacpra 26.09: **„zawsze odradzaj”** — zrobione, NIEPRZETESTOWANE: każda śmierć, także poza rundą (reset w lobby, spectator), → lobby po `DeathRagdollTime`; timer ma żeton (`respawnPending`), a `spawnBusy` szereguje spawny jednego gracza (śmierć w lobby tuż przed startem rundy) — opis przy `PlayerService` w `ARCHITECTURE`; (5) ✅ commit `b37e4b6` (25.09 + 26.09), respawn osobnym commitem (`46cf072`); (6) **listwy i drabina (26.09 wieczór, decyzje Kacpra: bomba wycina tylko trafiony odcinek; listwa zostaje, póki dotyka czegoś stojącego)** — zrobione, sprawdzone offline na kopii budynku, NIEPRZETESTOWANE w Play; opis, wyniki i lista testu: `DESTRUCTION_PLAN.md` → „Listwy i drabina (26.09)”; (7) **przygniecenie jadącego (26.09 wieczór)** — zgłoszenie Kacpra „czasem mało spadniesz, a liczy jako śmierć” = `CollapseService.crushCheck`: strop, na którym jedziesz, uderzając o ziemię, leciał względem gracza w górę z pełną prędkością upadku → „przygniecenie” do 100 dmg. Decyzja Kacpra: bryła POD graczem nie przygniata (`isUnder`: najbliższy punkt bryły niżej niż środek postaci — działa też na leżącego w ragdollu), jazdę liczy zwykły fall damage, strop spadający NA gracza dalej rani; zastępuje decyzję z 25.09 o połowie obrażeń za jazdę. NIEPRZETESTOWANE — test: zjedź na spadającym stropie do ziemi → żyjesz, jeśli z niego nie spadłeś; stań pod walącym się stropem → dalej boli.
>
> ✅ **2026-09-26 (wieczór) — Kacper w Play: „wszystkie testy pomyślnie poszły”** — dotyczy WSZYSTKICH zmian z 26.09: hak w ragdollu, respawn (śmierć pod mapą i poza rundą), bomba bez efektu (objaw się nie powtórzył), drabina i długie listwy, brak przygniecenia przy jeździe na stropie; **faza F: 5 wybuchów wytrzymuje, także na serwerze**. Punkty 🧭 (2)-(7) niżej są przez to zamknięte.
>
> 🐛 **2026-09-26 — test Kacpra z kolegą (2 graczy), trzy zgłoszenia → poprawki ✅ POTWIERDZONE w Play 26.09 wieczorem:**
> - **Hak w ragdollu wystrzeliwał w kosmos** — serwer i klient nie blokowały strzału w ragdollu, a klient przerywał lot tylko przy `PlatformStand`, którego toolbox NIE ustawia (zwiotcza przez `ChangeState(Physics)`). → `RagdollService.isRagdolled` (flaga toolboxa), `GrappleService` odrzuca strzał przed zużyciem, `GrappleController.isRagdolled` (flaga + stan Physics + PlatformStand) blokuje strzał, start lotu i przerywa lot.
> - **Martwy kolega „pod mapą”, bez respawnu do następnej rundy** — MOJA regresja z 25.09 (ragdoll po śmierci): timer odradzał tylko, gdy `Character` był dalej tą samą martwą postacią, a koniec rundy martwych pomijał (wywnioskowane z kodu). → odradzamy, chyba że gracz ma już inną ŻYWĄ postać; koniec rundy odradza martwych bez czekającego timera (`respawnPending`).
> - **„Czasem bomba kolegi nic mi nie robi, 0 ragdolla, 0 dmg”** — przyczyna NIEUSTALONA (bez logu). Kandydaci: wyjątek w `DestructionService.detonate` zjadał obrażenia (→ teraz `xpcall`, błąd drukowany z miejscem), gracz poza `aliveSet`, osłona (m.in. leżące rumowisko v4 liczy się jak ściana). → log `[Bomb] … miss — <gracz> … <powód>` dla każdego gracza w zasięgu, którego bomba pominęła.
> - **Lista dla Kacpra (test z kolegą)**: ragdoll + klik hakiem → nic nie leci i licznik haka nie spada; bomba w trakcie lotu hakiem → lot się przerywa bez wystrzelenia; śmierć pod mapą / w lawie → po ~2 s lobby; bomby jeden w drugiego → przy „nic nie zrobiła” wkleić `[Bomb] … miss` albo `[Bomb] BŁĄD destrukcji` z Output; **reset w lobby** (w przerwie i jako spectator w trakcie rundy) → ~2 s ragdollu i odrodzenie w lobby; reset w ostatnich ~2 s odliczania → start rundy na mapie, NIE w lobby.
> - 🔧 **26.09 rano: `Config.luau` miał literówkę `MaxY = 250ś`** (Lava, nie moja) — błąd składni całego Configa = cała gra leży; poprawione na `250` (górny limit lawy; przy `0` lawa nie mogła wyjść ponad Y=0).
>
> ✅ **2026-09-26 — Kacper po teście w Play: „wszystko git działa teraz”** (dotyczy zmian z 25.09: kolaps spada fizyką, taśma, cięcie rumowiska, posiekany ciemnoszary gruz, brak trzęsienia, 2 s ragdollu po śmierci, mniej zaklinowań). Otwarte punkty destrukcji — „➡️ NASTĘPNE KROKI” niżej.
>
> 🔬 **SESJA 2026-09-25: TEST DYMNY v4 (Claude przez MCP, za zgodą Kacpra: „możesz testować Play, ale nie za dużo”) ZNALAZŁ, ŻE GRUPY KOLAPSU NIE SPADAJĄ — 4 z 25 spadało fizyką, 21 „osiadało” W MIEJSCU po 0,7 s, wieża stała nad zburzonym parterem.** Poprawki 25.09 wdrożone i sprawdzone tą samą serią 6 bomb (obserwacja, nie werdykt): **14 z 24 spada fizyką, 9 zaklinowanych idzie przez siatkę bezpieczeństwa do klientów**, jazda na spadającym dachu i stropie działa w Studio. **CZEKA NA TEST KACPRA W PLAY** (lista w OTWARTE). Pełny opis, tabela przebiegów i przyczyny: **`DESTRUCTION_PLAN.md` → „v4 → Test dymny 25.09”**.
> - **Przyczyny (zmierzone rejestratorem brył + symulacją w Edit + logiem `ZAKLINOWANA … trzyma:`)**: fragment skruszonego elementu bez filtra nachodzeń klinował się i był usypiany w miejscu; kikuty przeciętych (`Severed`) słupów/belek zostawały zakotwiczone pod tym, co miało spaść; pion na stojącej belce spadał tylko przez dziedziczenie zasięgu; tarcie od sąsiada nachodzącego z boku o setne studa; kolizja przekazywanych kawałków trwała 0,25 s.
> - **Decyzje Kacpra 25.09**: ~~jeździec = **połowa obrażeń** za pełną wysokość, wysokość z **prędkości przy uderzeniu** (ΔV²/2g)~~ — **ZASTĄPIONE 26.09**: jazdę liczy zwykły fall damage, bryła pod graczem nie przygniata (`CollapseService.isUnder`); zaklinowana grupa → **do klientów**; pion na stojącej belce za daleko od słupa → **belka pęka** (przeciążenie w `StructureCore.solve`); kikuty **spadają z tym, co trzymają**.
> - **Przy okazji naprawione**: przygniecenie liczone z prędkości WZGLĘDNEJ (jeździec dostał 59 dmg od kikuta lecącego razem z nim).
> - **Commit `c9a06aa`** zabezpieczył całą zaległą pracę 23-24.09 (v3 + tryby grafiki + v4 A-D). Zmiany 25.09 i 26.09 — niezacommitowane, patrz git status.
> - ⚠️ **`rojo serve` NIE CHODZIŁ** na starcie sesji (lekcja 5, czwarty raz) — uruchomiony w zakładce terminala „rojo serve”, Kacper kliknął Connect.
> - **Test Kacpra po teście dymnym (25.09 wieczór)**: (1) „taśma” — zakotwiczony part ZACHOWUJE prędkość (zmierzone na silniku), osiadłe rumowisko działało jak taśmociąg → ✅ `Utils.anchorAtRest`, do sprawdzenia; (2) „bomba nie rozwala party” = **leżące po zawaleniu** — rumowisko v4 i gruz serwera nigdy nie były cięte, tylko pchane → decyzja Kacpra: **tnie jak ścianę** → ✅ `CollapseService.cutRubble` (test dymny: 3 bomby → 5/6/4 przecięte kawałki, zero błędów; taśma: 47 osiadłych kawałków z prędkością 0,000); gruz `DebrisService` dalej tylko pchany; (3) drabina — szyny 1×66×1 odpadają w całości, szczeble zostają w powietrzu; cała drabina doczepiona do jednego kawałka stropu → wymaganie „naruszone party mają spadać”, DO ZROBIENIA. **Druga runda próśb Kacpra (25.09 noc, wszystko ✅ i sprawdzone testem dymnym, 0 błędów)**: (4) duże przekazane party (zaklinowane stropy, szyny) klient SIECZE na kawałki zamiast jednego kloca bez kolizji, a cały lokalny gruz budynku jest ciemnoszary („żeby było widać, że debris”); (5) wyłączone trzęsienie kamery przy kolapsie (`CollapseShakeMax = 0`); (6) **po śmierci ~2 s ragdollu** (`Config.Game.DeathRagdollTime`, `PlayerService.onDeath` czeka zamiast od razu ładować lobby; ciało przewraca toolbox) — „umieram i nie wiem od czego” to najpewniej przygniecenie przez obudzone rumowisko → (7) `Collapse.WakeImpulseFactor` 0,3 (decyzja Kacpra: „mniejszy odrzut dla wszystkich”); (8) **zaklinowania 11 → 4** — fragment kruszenia bez kolizji ze wszystkim, czego dotyka przy starcie (`filterContacts`); log zaklinowania wypisuje teraz każdy styk (POD/NAD/BOK). Zostały 4, opis w `DESTRUCTION_PLAN.md` → „v4 → Test Kacpra 25.09”. Plan obu: `DESTRUCTION_PLAN.md` → „v4 → Test Kacpra 25.09”.
>
> 🏗️ **STAN NA KONIEC SESJI 2026-09-24: DESTRUKCJA v4 — FAZY A-D NAPISANE, ORANGEBUILDING W GRZE NA v4, POPRAWKI PO PIERWSZYM TEŚCIE CZEKAJĄ NA PONOWNY TEST KACPRA W PLAY.** To jest odpowiedź na „CAŁA DESTRUKCJA DO NAPRAWY” z 23.09. Wszystkie decyzje Kacpra, model, kontrakt 1-15, fazy i test akceptacyjny: **`DESTRUCTION_PLAN.md` → „v4”** (czytać PRZED dotknięciem destrukcji).
> - **Model w skrócie**: graf konstrukcji (chunk ≠ part: Slab/Beam/Wall/Column/Block; listwy, ramy, szyby = doczepione do właściciela), interfejsy podparcia Bearing/Lateral/Continuity z szerokością, solver Dijkstry po „zasięgu od ostatniej pionowej podpory” (`MaxSpan`), dziura = prostokąt „okna” (≤ 4 pasy resztek, 45 → 6 nowych partów na bombę), osłabianie SUMUJE się (decyzja Kacpra) i kruszy element, `CollapsePlanner` dzieli spadający obszar na grupy, `CollapseService` wykonuje je prawdziwą fizyką serwera w jednej puli budżetu (kolejka od dołu, czekanie do 1,5 s), duże bryły osiadają i zostają platformą do końca rundy, małe znikają po 4 s. Dekoracje (`Decorations`) = REKWIZYTY: padają W CAŁOŚCI.
> - **Kod**: `src/server/Structure/` (6 modułów) + `StructuralService` (JEDYNY właściciel stanu budynków v4) + `CollapseService` (wykonawca) + zmiany w `DestructionService`, `DebrisService.applyCrush`, `Fracture.planWindow`, `Destructible.propOf`, `DebrisFXController`. `StructureService` i `Config.Destruction.Collapse` USUNIĘTE. Tylko **OrangeBuilding** (`Config.Structure.Buildings`) — reszta mapy dalej na v3. Dane konstrukcji liczone przy starcie rundy (`AnalyzeIfMissing`), NIE zapisane w placu.
> - **Test Kacpra 24.09**: „takto wszystko działa raczej” + 4 usterki → przyczyny ZMIERZONE, poprawki wdrożone, **NIEPRZETESTOWANE**: (1) górne piętra znikały — grupy ponad budżetem oddawane klientom od razu (log `[Collapse]`: 16 z 25), teraz czekają w kolejce; (2) szyby lewitowały — bake pomijał szkło, teraz pasażer ściany (`BakeVersion` 2); (3) przenikalne party lewitowały — gruz klienta lądował na ruchomej bryle, teraz ignoruje ruchome i sprawdza podłoże; (4) pudła/szafki pobugowane — szły ścieżką ścian, teraz rekwizyty w całości. Tabela: `DESTRUCTION_PLAN.md` → „v4”.
> - **Następne**: ponowny test tych 4 poprawek → **faza E: RiderTracker** (jeździec na spadającym piętrze: ~~obrażenia 0,5 × przejechana wysokość~~ — od 26.09 zwykły fall damage, decyzja Kacpra; zostaje grace anty-cheata) → F (5 wybuchów w 3 s, budżet, MicroProfiler) → G (2 klientów, opóźnienie, Ziemniak/Pełny, streaming) → zapis danych bake'u (TRYB 3) → migracja kolejnych budynków → usunięcie passu podparcia v3.
>
> 📜 Bloki niżej (23.09) opisują **v3** — kod, który dalej działa na reszcie mapy, dopóki budynki nie przejdą na v4. Ich „znane na start” (filary `Pillar`, martwy `StructureService`) są już NIEAKTUALNE — v4 je zastąpił.
>
> 📜 **HISTORIA: STAN NA KONIEC SESJI 2026-09-23 (wieczór) — v3.**
>
> 🧨 **DECYZJA KACPRA NA KONIEC SESJI 23.09: CAŁA DESTRUKCJA JEST DO NAPRAWY** (➜ realizowane jako v4 od 24.09 — blok 🏗️ wyżej). Opis v3 niżej to STAN KODU, nie zamknięty temat — w destrukcji nic nie jest „działające”, dopóki Kacper nie potwierdzi tego w Play. **Następna sesja o destrukcji zaczyna się od pytania do Kacpra, co konkretnie jest do naprawy** (i/lub od jego testu v3 — lista w `DESTRUCTION_PLAN.md` → „v3 → Jak testować”), zebrania WSZYSTKICH zgłoszeń w jedną tabelę (lekcja 7) i dopiero potem planu. Nie zgadywać zakresu naprawy. Znane na start (fakty, nie hipotezy):
> - v3 **nie był uruchomiony w Play** — ani na telefonie, ani z kolegami; sprawdzone tylko: kompilacja 15 skryptów, zgodność pól `Config`/remote'ów, czysta matematyka (plan dziury, kładzenie płasko, kierunek przewracania).
> - **Przenikanie przez podłogę**: mechanizm (kasowanie wielkiej płyty docierało przed resztkami) jest WYWNIOSKOWANY z kodu i pomiarów, nie zaobserwowany. Przycięcie oryginału chroni tylko graczy stojących na resztce-oryginale; dwóch graczy na różnych resztkach tej samej płyty dalej zależy od replikacji.
> - **Kolaps sekcji martwy**: na mapie 0 partów z tagiem `Pillar`, a `StructureService` uznaje całe miasto za jeden „budynek” (zgłoszone jako osobne zadanie — naprawić PRZED tagowaniem filarów).
> - **Lokalny gruz bez kolizji** zamiast prawdziwej fizyki: odbicie raz + kładzenie płasko + sterta z mapy wysokości, meble przewracane animacją — wygląd DO OCENY przez Kacpra.
> - **Żadna liczba nie jest strojona** (progi drobnicy `Config.Destruction.Small`, profile `Config.Graphics.Profiles`, budżety) + **5 pustych slotów audio** (`Config.Destruction.FX`).
>
> 💥 **SESJA 2026-09-23 (wieczór) — DESTRUKCJA v3: „serwer trzyma stan gry, klient animuje resztę” + TRYBY GRAFIKI.** Zgłoszenie Kacpra po teście na telefonach z kolegami: *4 bomby naraz = lagi*, *przenikanie przez podłogę, choć w tym miejscu nie ma dziury*, *„part niezanchorowany, nie został pocięty” co chwilę*, *wieszaki w zielonym budynku rozlatują się i znikają*. **ZAIMPLEMENTOWANE, NIEPRZETESTOWANE** — kod dojechał do Studio i się kompiluje (15 plików), czysta matematyka planu dziury sprawdzona (300 losowych prób: zero rozjazdów). Pełny opis: `DESTRUCTION_PLAN.md` → „v3”.
> - **Przyczyny ZMIERZONE na mapie (Edit, bez Play)**: (1) pass podparcia uznawał **~3500 partów** za niepodparte JUŻ PRZED wybuchem (zielony budynek 1724 — prawie wszystkie wieszaki; cienkie party < 0.5 nie miały podparcia z boku, rzeczy wiszące nie liczyły się jako podparte) — każda bomba w promieniu kolumny zrzucała je hurtem jako fizykę serwera, a limit 260 natychmiast je kasował = „znikają” (stąd `spadło=472` z dachu); (2) do 110 kawałków dziury na wybuch było fizyką SERWERA replikowaną do każdego gracza; (3) każdy ranny part dostawał serwerowy emiter pyłu (338 z jednej bomby w zielonym); (4) **78% partów mapy (20 376) to drobnica**, a system traktował ją jak ściany; (5) podłogi to wielkie pojedyncze party (57×57×0.5) — wybuch kasował oryginał i stawiał resztki jako NOWE party; pod obciążeniem kasowanie docierało do telefonu przed resztkami → gracz spadał pod podłogę.
> - **Co zrobione**: dziura liczona z seeda (`Fracture.planHole`, wspólne) — serwer stawia tylko resztki (**scalone: 30.2 → 11.6 nowego parta na pocięty part**), kawałki dziury animuje klient; **oryginał parta jest PRZYCINANY, nie kasowany** (zostaje resztką, na której stoją gracze); drobnica bez HP, pada **cały mebel** (decyzja Kacpra), przekazywana klientom (`Remotes.DebrisFall`), serwer kasuje po 0.25 s; podparcie liczone **przed i po** — spada tylko to, co podparcie straciło; gruz serwera tylko z dużych płyt (≤ 30 na wybuch, one ranią — decyzja Kacpra); budżet CPU 6 ms/klatkę dla wszystkich wybuchów; pocisk bomby znika przed wybuchem (koniec fałszywego ostrzeżenia). **Tryby grafiki** Ziemniak / Pełny (`Config.Graphics`, `QualityController`, `SettingsService`): gruz leży 3 s / 20 s (decyzja Kacpra), telefon startuje w Ziemniaku; wybór z **ustawień** (decyzja Kacpra) zapisywany w DataStore; w dev klawisz **G** przełącza tryb.
> - ⚠️ **Świadome zmiany w rozgrywce**: drobny gruz z dziury nie rani (crush) i nie zostaje platformą; drobnica (wieszaki, krzesła) pęka do 12 studów, ściany do 9; mosty graczy padają w całości (model = mebel).
> - 🔴 **POPRAWKA TEGO SAMEGO WIECZORU (pytanie Kacpra: „dwie osoby z innymi ustawieniami widzą inne party i mogą chodzić po innym gruzie”)**: pierwsza wersja dawała lokalnemu gruzowi kolizję z postacią — w Pełnym dało się stanąć na kawałku, którego inni nie mieli. **Teraz lokalny gruz NIE MA KOLIZJI w ogóle** (`CanCollide`/`CanQuery`/`CanTouch = false`): leci fizyką silnika bez zderzeń, odbicie/lądowanie/stertę liczy `DebrisFXController` promieniem omijającym postacie; meble się przewracają (animacja), w Pełnym potem rozsypują. Tryb grafiki zmienia WYŁĄCZNIE obraz. Grupy kolizji gruzu klienckiego usunięte.
>
> 🪝 **SESJA 2026-09-22/23 — COMMIT ZALEGŁEJ PRACY + TRZECI ITEM: HAK.**
> 1. **Commit `55b7d84` zabezpieczył DZIEWIĘĆ DNI pracy** (13-22.09, 5121 linii w 35 plikach), która leżała poza gitem. Jeden commit, nie kilka: `Config.luau` i `CLAUDE.md` przeplatały wszystkie obszary, więc podział po hunkach dałby stany pośrednie, które nigdy nie istniały.
> 2. **HAK (`grapple`, 40$, zużywalny)** — celujesz, trafiasz w zasięgu 70, lecisz PO ŁUKU do tego punktu i kończysz trochę nad nim. **Przetestowany przez Kacpra w Play** — odczucie lotu zaakceptowane 22.09, a 23.09: „testy grappling hooka — działa" (lista przypadków brzegowych przeszła).
>    - **Model lotu przeszedł CZTERY wersje**; każda z pierwszych trzech spełniała jedno wymaganie kosztem innego. Historia przy `Config.Grapple`, skrót przy `GrappleService`. **Nie wracać do balistyki ani do liny po prostej.**
>    - Decyzje Kacpra: **zużywalny** jak bomba (nie „na rundę z cooldownem"), **jedno kliknięcie** bez trzymania, **zjazd hakiem w dół boli jak skok z punktu startu** (wbrew mojej rekomendacji — wyłączona jest tylko wywrotka w połowie lotu).
> 3. **SZÓSTKA ITEMÓW WYBRANA — odczytana z wystawy w Studio, nie powiedziana słownie.** `WeaponShopScene.Decorations` ma modele `Bomb`, `Blueprint`, `HandHook`, `Rpg`, `StickyBomb`, `EnergyDrink` (+ `Workshop` — stół warsztatowy, dekoracja, nie item). Poza bombą, mostem i hakiem zostają: **RPG, sticky bomb, energy drink**. Żaden nie nagradza kempingu na szczycie — obawa z listy propozycji (mina, ściana) odpada.
> 4. **Endgame** — decyzja Kacpra: **rozstrzygamy po teście z ludźmi**, nie z arkusza. 🔴 **Podjęta na nieaktualnym pomiarze** („lawa kończy 3 study pod dachem") — korekta 23.09: lawa startuje z Y ≈ 2.5, zalewa najwyższy dach ~5 s przed końcem i kończy 14 studów nad nim; przez 7-sekundowe ranienie gracz z pełnym HP na dwóch najwyższych dachach przeżywa **zanurzony**. Szczegóły przy „WNIOSEK DESIGNOWY" w ROADMAP.
> 5. **Twarz ZAMKNIĘTA wizualnie** — Kacper: „twarz działa". Głowa w `StarterCharacter` to dynamiczna głowa (`MeshPart` + `FaceControls`) BEZ dekala `face` (sprawdzone 22.09), więc `applyFace` nic nie robi, a widać twarz wbudowaną w głowę. Pytanie „czy twarze mają być towarem w sklepie" wraca dopiero przy etapie ③ — wtedy potrzebna klasyczna głowa.
> 6. **KAMERA ZZA RAMIENIA (23.09, prośba Kacpra: „kamera lekko w lewo od gracza")** — `Config.Movement.Camera.ShoulderOffset`, Kacper porównał obie strony w Play: **„prawa zostaje"** — `Side = 1.5`, kamera nad prawym ramieniem, postać po LEWEJ stronie ekranu (jak w Fortnite).
>    - 🔴 **X-RAY, który z tego wyszedł** („czemu dałeś mi x-raya, kamera ma się zatrzymywać na ścianie"): plac miał `StarterPlayer.DevCameraOcclusionMode = Invisicam` — tryb, w którym kamera Robloxa w ogóle NIE zatrzymuje się na ścianach, tylko robi je przezroczystymi. Przesunięcie w bok częściej stawiało ścianę między kamerą a postacią, więc wbudowany x-ray wyszedł na wierzch. **Naprawa**: `DevCameraOcclusionMode = Zoom` w `default.project.json` (repo jest źródłem prawdy dla ustawień kamery, obok zoomu i blokady myszy) + `keepLineOfSight` w `MovementController` — promień OD GŁOWY do kamery, bo `Zoom` pilnuje kamery tylko PRZED naszym przesunięciem i wygładzaniem. ✅ **Potwierdzone przez Kacpra w Play 23.09** — kamera staje na ścianach, x-raya nie ma.
>
> **✅ DZIAŁA I POTWIERDZONE W PLAY:**
> 1. **Sklep-NPC, spawn w lobby, modele itemów Kacpra** (bomba / blueprint / most z 12 desek). Most jest większy niż dawne 10×2 i **tak ma być**.
> 2. **🦴 RIG NA `Motor6D`** — `StarterPlayer.StarterCharacter` + konwersja `AnimationConstraint` → `Motor6D`. W grze `Motor6D=16`, `AnimationConstraint=0`, `BallSocket=10`. **To naprawiło ragdoll.** Backup: `ServerStorage.StarterCharacter_BACKUP`.
> 3. **`AppearanceService` (etap ① wyglądu)** — losuje raz i zapisuje skórę/koszulkę/spodnie + krój rękawa i nogawki, maluje 15 części R15.
> 4. **DataStore DZIAŁA w Studio** (`Enable Studio Access to API Services` włączone) — zweryfikowane: cash przeniósł się między sesjami Play. Stary zapis „wygląd nie zapisuje się w Studio" jest **nieaktualny**.
> 5. **Destrukcja: szkło wreszcie żyje** — `[Destr] ... szkło=47` w logu, wcześniej zawsze `szkło=0`.
> 6. **Lawa rani zamiast zabijać na miejscu**, oprawa lawy zapala się dopiero nad ulicami, ghost mostu stoi na lawie. Wszystko zsynchronizowane i uruchomione bez błędów składni.
>
> **🗺️ ASSETY MAPY DOPROWADZONE DO KONTRAKTU (2026-09-21, wszystko zmierzone):**
> - **36 kloszy latarni** + **150 żarówek sygnalizatorów** na `Material = Neon` (skrypty `LAMPS_LIGHTS.luau`, `TRAFFIC_LIGHTS.luau`).
> - **367 szyb** na `Material = Glass` (`WINDOWS_GLASS.luau`). Rozpoznawane **po podpisie `Transparency 0.60` + `Color (170,170,170)`**, nie po nazwie rodzica.
> - 🚨 **Wszystko to zmiótł wcześniej bulk-apply materiału mapy** (`Plastic` + `Studs` na całą gałąź). Objaw jest CICHY: rzeczy przestają świecić, a szyby przestają się tłuc. Dlatego **każdy skrypt naprawczy szuka celu po ROZMIARZE albo przezroczystości — NIGDY po właściwości, którą naprawia.**
>
> **⏳ OTWARTE — CZEKA NA KACPRA:**
> - 🔴 **TEST DESTRUKCJI v4 NA ORANGEBUILDING (Kacper w Play)** — lista do sprawdzenia: (1) parter zburzony w ~70% → wyższe piętra spadają bryłami po niższych, nie znikają i **nie wiszą nad zburzonym parterem**; (2) czy któraś bryła „wisi” chwilę i potem nagle znika albo spada animacją (to siatka zaklinowania — log `[Collapse] … ZAKLINOWANA … trzyma:` podaje przyczynę, zebrać go); (3) kikuty słupów spadają razem ze stropem, pień na podłodze zostaje; (4) szyby spadają ze swoją ścianą; (5) gruz leżący na stropie spada dalej, gdy strop się zawali; (6) pudło/szafka/wieszak przy bombie → pada cały mebel; (7) dziura w stropie sama niczego nie zrzuca; (8) stań na piętrze, zburz pod nim → jedziesz i da się zeskoczyć (obrażenia na razie jak zwykły upadek — faza E); (9) ile bomb kładzie budynek (cel ~8). Potem faza E. Reszta mapy (v3) dalej nie przetestowana na telefonach — to wraca przy migracji budynków.
> - **Zaklinowania, które zostały (przebieg 7 testu dymnego)**: 3 × fragment kruszenia pod grupą, 2 × „nic pod spodem” (bomba 1, przyczyna nieustalona), 2 × kikut WŁASNEGO parta grupy (przypadek brzegowy `takePieces`), 1 × pas ściany zaczynający się w grubości stropu, 1 × prawidłowe rumowisko. Tory `OutsideDecorations.Railway` wchodzą w strop OrangeBuilding na Y 54. Siatka je łapie; poprawiać po teście Kacpra, na podstawie logu.
> - **Panel ustawień** — kontrakt w `docs/STUDIO_CONTRACT.md` → „Ustawienia” (`Settings` + `GraphicsPotato`/`GraphicsFull` + `SettingsButton` w HUD). Bez niego tryb dobiera się automatycznie.
> - ✅ ~~Filarów z tagiem `Pillar` na mapie jest 0~~ — nieaktualne: `StructureService` usunięty 24.09, kolaps budynków robi v4 z grafu konstrukcji (tagi niepotrzebne). Budynek v4 = model wymieniony w `Config.Structure.Buildings`, nie „dziecko `Workspace.Map`”.
> - **`HUD.Hotbar.Slot3` NIE ISTNIEJE** (sprawdzone 22.09: tylko `Slot1`, `Slot2`). Hak jest TRZECIM itemem — działa z klawisza `3`, ale **nie widać go w pasku**. Fix po stronie Kacpra: skopiować `Slot2` → `Slot3`. `HotbarController` ma `if not btn then return end`, więc brak slotu niczego nie wywala — tylko ukrywa item. ⚠️ Każdy kolejny item = kolejny `SlotN`.
> - **Brak markera kamery przy haku** w `WeaponShopScene.ShopCameras` — kadr liczy się z bounding boxa. Marker postawiony obok `HandHook` przejmie kadr bez zmiany kodu (parowanie po odległości: `BombCamera` stoi 19.2 od haka, ale bliżej `Blueprint`u, więc go nie przejmuje — zmierzone 22.09).
> - ✅ **ŚLIZG ZNIKNĄŁ** (Kacper 23.09: „nie ślizga się przy chodzeniu") — po konwersji rigu. **Przyczyna NIE zmierzona** — nie przypisywać jej niczemu i nie ruszać (patrz „ŚLISKI MOVEMENT").
> - ✅ **HEAD TRACKING NAPRAWIONY I POTWIERDZONY 23.09** (Kacper: „oba działa") — **wcześniej NIE DZIAŁAŁ NIGDY** (Kacper: „nie działało od początku wprowadzenia") — ✅ przy nim w „Co jest GOTOWE" był fałszywy od zawsze, a hipoteza „wróci po konwersji rigu" była błędna. **Ustalone 23.09**: stawy SĄ znajdowane, obrót ginie. Brak stawów WYKLUCZONY dwiema drogami: w ~8 sesjach Play po restarcie Studio nie ma ani jednego `[HeadTrack] brak Motor6D` (kod drukuje go przy KAŻDEJ postaci, której nie obsłuży), a odczyt postaci w grze pokazał `Neck` (UpperTorso→Head) i `Waist` (LowerTorso→UpperTorso) jako `Motor6D`, `Enabled`, z `C0` BEZ rotacji. **Najpewniejszy mechanizm** (niezmierzony): `applyAim` mnoży `Motor6D.Transform` w `RenderStepped`, bo komentarz w kodzie zakłada, że animator działa w RenderStep z priorytetem `Character` i wystarczy być po nim — a `RenderPriority.Character` to tylko numer kolejki dla skryptów; animator nadpisuje `Transform` w całości we własnej fazie klatki. ➜ **Fix ZROBIONY i POTWIERDZONY w Play 23.09**: `C0 = zapisaneC0 * obrót` — animator nie dotyka `C0`, więc fix nie zależy od dokładnego mechanizmu; oryginały `C0` są już zapisywane w `asyncCacheJoints` i nigdzie nieużywane. Do tego przywrócenie `C0` przy ragdollu/śmierci (`C0`, w odróżnieniu od `Transform`, nie resetuje się sam). Znaki obrotu policzone rachunkiem na osiach tego rigu (kamera w dół → głowa w dół, w lewo → w lewo) i potwierdzone okiem 23.09.
> - **Zaczep hakiem pod nogi zużywa sztukę za nic** (log 23.09: `dist=4.4 luk=0.01s` — klik w ziemię pod sobą daje lot o ~1 studa, a item schodzi). W trybie dev niewidoczne (99 sztuk), na produkcji to strata 40$ za misklik. **Odłożone przez Kacpra 23.09.** Fix: w `GrappleService` odrzucić PRZED `consume`, gdy lot (`goal − origin`) krótszy niż ~3 study.
> - ✅ ~~Diagnostyka destrukcji zgłasza sam pocisk bomby~~ — naprawione w v3 (pocisk znika przed wybuchem; ostrzeżenie tylko dla partów W `Map`, każdy raz na sesję).
> - ~~Pomiar obciążenia: `spadło=472`, `gruz=260/260`, `ms=80`~~ — przyczyna znaleziona i usunięta w v3 (patrz sesja wyżej). ⚠️ Nowy log `[Destr]` mierzy **czysty CPU** (`cpu=`), bez klatki czekania — stare `ms=` ją wliczało, liczb nie porównywać 1:1.
> - **Fall damage z 19.09 — 5 przypadków NADAL nieprzetestowanych** (lista przy `FallDamageService`).
> - **Latarnie świecą 11 studów POD ulicę** (`Range 26`, wiszą 15 nad jezdnią) — zmierzone, Kacper odłożył decyzję. Fix to jedna liczba.
> - **Szyby automatów / samochodów / przystanku** (23 + 64 + 9) celowo NIE są szkłem — do decyzji.
> - **`Config.Destruction.FX` ma 5 PUSTYCH slotów audio** (Explosion/Glass/Impact/Creak/Collapse). Wpięcie gotowe, brakuje id.
>
> **🔴 TRZY FLAGI TESTOWE DO COFNIĘCIA PRZED LAUNCHEM** (wszystkie warnują co boot):
> - `Config.Lava.Phases` — **240 s** (15/60/60/60/45) i prędkości **0.20/0.40/0.65/1.00**. Produkcyjne: 80 s (5/20/20/20/15) i 0.6/1.2/2.0/3.0. ⚠️ Czasy i prędkości **przeskalowane odwrotnie**, żeby całkowity przyrost został ~120 studów — nie zmieniać jednego bez drugiego.
> - `Config.Dev.Enabled = true` **oraz `Config.Dev.InfiniteItemsForAll = true`** — drugie daje nieskończone itemy KAŻDEMU, nie tylko nickom z `Usernames`.
> - `Config.Game.MinPlayers = 1`.
>
> **⛔ SPRAWDZONE I ODRZUCONE — NIE PROPONOWAĆ PONOWNIE** (opisy w `docs/` — wyszukaj nazwę):
> `LoadCharacterWithHumanoidDescription` · wyrównywanie skal postaci · przełączanie `CustomPhysicalProperties` HRP/Head · rozluźnianie limitów stawów · `AdjustSpeed` na animacji chodu · preset „Consistent Gameplay" · bramki raycastowe oprawy lawy (`isExposed` / `isLavaOpenAt`) · `SmoothPlastic` jako materiał ciała · **(destrukcja, 2026-09-23)** kawałki dziur i drobnica jako fizyka SERWERA · pass podparcia zrzucający wszystko „niepodparte” bez porównania przed/po · kasowanie pociętego parta i stawianie resztek od nowa (zamiast przycinania oryginału) · emiter pyłu tworzony na serwerze per ranny part · **kolizja lokalnego gruzu z postaciami** (także „grupa kolizji dla postaci” — zależy od czujnika podłogi Humanoida i kamery, których nie da się sprawdzić bez gry; gruz bez kolizji działa z definicji) · **(destrukcja v4, 2026-09-24)** oparcie na POZIOMYM elemencie zerujące zasięg (wieża „wisiała” na wsporniku sąsiedniej bryły — zasięg się dziedziczy, zeruje go tylko pion) · boczne trzymanie pionu przez strop (tylko belka, `LateralHoldsVertical`) · szerokość styku liczona z luzem (przypisywała podparcie sąsiednim polom stropu) · szacunek „1 bomba = 1 chunk” · natychmiastowe oddawanie klientom grup kolapsu ponad budżetem (serwer je kasował → znikały piętra) · dekoracje cięte jak ściany (pudła/szafki — padają w całości jako rekwizyt) · **(destrukcja v4, 2026-09-25)** kotwiczenie w miejscu grupy, która po odkotwiczeniu się nie ruszyła (zostawała w powietrzu — teraz siatka zaklinowania) · fragment kruszenia wyrzucany bez filtra nachodzeń · przygniecenie z prędkości BEZWZGLĘDNEJ bryły (raniło jeźdźca) · próg filtra nachodzeń dla styku z BOKU (każde nachodzenie z boku trzyma tarciem).
>
> **➡️ NASTĘPNE KROKI**: najpierw **sprawdzenie poprawek z 26.09** (hak w ragdollu, respawn po śmierci pod mapą i poza rundą, bomba bez efektu — blok 🧭/🐛 na górze STATUS; commit już jest); zmiany z 25.09 Kacper potwierdził w Play 26.09 („wszystko git działa”); potem **test drabiny i długich listew** (✅ zrobione 26.09 wieczór — lista w `DESTRUCTION_PLAN.md` → „Listwy i drabina (26.09)”) i reszta zaklinowań (filarek na krawędzi przeciętej belki — zmierzyć szerokość styku) — plan w `DESTRUCTION_PLAN.md` → „v4 → Test Kacpra 25.09”, potem **test destrukcji v4 na OrangeBuilding** (Kacper w Play, lista w OTWARTE; wyniki + log `ZAKLINOWANA` dopisać do tabeli w `DESTRUCTION_PLAN.md` → „v4” — lekcja 7), potem **faza E: RiderTracker** — obrażenia jeźdźca SKASOWANE decyzją Kacpra 26.09 (zwykły fall damage, bryła pod graczem nie przygniata — już w kodzie); zostaje sprawdzić, czy jazda na przewracającej się bryle nie wyzwala anty-cheata (limit prędkości POZIOMEJ), F (obciążenie), G (sieć), zapis bake'u, migracja kolejnych budynków (GreenBuilding) i usunięcie passu podparcia v3 — szczegóły: blok 🏗️ na górze STATUS i `DESTRUCTION_PLAN.md` → „v4 → Fazy”. Potem **zaległe testy fall damage** (5 przypadków — patrz OTWARTE; od 26.09 `FallDamageService` liczy też jazdę na walącym się budynku, więc RiderTracker go NIE zawiesza). Potem Kacper wybiera kierunek: **kolejne itemy z wystawy** (RPG / sticky bomb / energy drink — modele już stoją) albo **ścieżka wyglądu** ② przebieralnia → ③ sklep kosmetyczny → ④ pancerze (**wymagają fixu anti-cheata**, patrz „TRZY PUŁAPKI"). Strojenie liczb (`Config.Structure.Damage`, `Config.Structure.Collapse`, `Config.Graphics.Profiles`, `Config.Destruction.Small`) — po testach, gałkami, nie logiką.
>
> 📌 **LEKCJE PROCESOWE — DROGO KUPIONE, CZYTAĆ PRZED DEBUGOWANIEM:**
> 1. **Najpierw ustal, CO DOKŁADNIE widzi człowiek.** „Ślizganie" = responsywność sterowania, nie ruch stóp; trzy zmiany i cztery pomiary poszły w rzecz, która nie była problemem.
> 2. **Przy „nie widać X" sprawdź najpierw, GDZIE X naprawdę jest**, zanim poprawisz, jak jest rysowane. Ghost mostu nie był maskowany — stawiał się pod lawą.
> 3. **Hipoteza spójna z objawem bywa nieprawdziwa.** Sortowanie przezroczystości i globalne nadpisanie `MaterialService` tłumaczyły objawy idealnie i oba były błędne.
> 4. **Przy trzeciej nieudanej próbie cofaj się, nie łataj.**
> 5. **Objaw „to nie działa" bywa niezsynchronizowanym kodem.** W tej sesji DWA RAZY zmiany nie dojechały do Studio, mimo że były na dysku. **Zanim ocenisz efekt — sprawdź `rojo serve` i Connected.** 2026-09-22 po raz trzeci: po restarcie Studio `rojo serve` nie chodził i wszystkie 5 zmienionych plików było w Studio STARYCH. 2026-09-25 po raz czwarty — Kacper był przekonany, że Rojo jest podpięte, a procesu nie było: **na starcie sesji `ps aux | grep rojo`** (stary kod zapisany w placu przechodzi sprawdzenie znacznika, więc znacznik trzeba brać z ZMIANY z tej sesji). **Sprawdzenie z MCP bez odpalania Play**: w Edit `pcall(loadstring, skrypt.Source)` — `nil` + komunikat = błąd składni; znacznik z nowej wersji w `.Source` = Rojo dowiozło. To obserwacja, nie test (zasada 2026-09-20). ⚠️ NIE przez `require` — hard rule 14. 2026-09-26 po raz piąty, INNY wariant: `rojo serve` chodził, Studio było Connected, Rojo miało nową wersję `BombService` u siebie (`curl localhost:34872/api/read/<rootInstanceId>`), a wtyczka jej NIE nałożyła (zapis z 19:09, po starcie Studio; w Output `… joined live editing session` — Team Create z kolegą, związek niesprawdzony). Naprawił Disconnect → Connect. **„Connected” nie znaczy „dojechało” — porównywać ZAWARTOŚĆ**: `#Source` + suma `h = (h*31 + bajt) % 2147483647` w Luau (Edit) i to samo w Pythonie na dysku; znacznik łapie tylko to, czego się spodziewasz.
> 6. **Kacper testował raz na pliku `AutoRecovery`, nie na swoim placu.** Studio raportuje się wtedy jako `<placeId>_AutoRecovery_0.rbxl` — `list_roblox_studios` to pokazuje. Przy „u mnie tego nie ma" sprawdzić nazwę instancji.
> 7. **Przy kolejnym feedbacku do TEJ SAMEJ mechaniki zbierz wszystkie dotychczasowe wymagania w jedną tabelę, ZANIM cokolwiek zmienisz.** Hak: trzy wersje lotu, każda naprawiała ostatnie zgłoszenie i łamała poprzednie (kierunek → dotarcie → łuk). Dopiero tabela „wersja × wymaganie" pokazała, że potrzebny jest INNY MODEL, a nie czwarte strojenie liczb. Pytanie kontrolne przed każdą poprawką: **czy to nie cofa czegoś, co Kacper już zaakceptował?**
> 8. **Plan oparty na zachowaniu silnika — sprawdź najpierw USTAWIENIE, które to zachowanie włącza.** Kamera zza ramienia zakładała, że kamera Robloxa zatrzymuje się na ścianach (tryb `Zoom`); sprawdziłem zakres zoomu, a nie tryb zasłaniania — plac miał `Invisicam`, i wyszedł x-ray. Przy kamerze: najpierw `StarterPlayer.DevCameraOcclusionMode`.
> 9. **Zanim zaczniesz stroić liczby przy „laguje”, przepuść algorytm przez NIETKNIĘTĄ mapę w Edit.** Log `spadło=472` wyglądał na balans budżetu gruzu („budżet wysycony”); symulacja passu podparcia na mapie BEZ żadnego wybuchu pokazała ~3500 partów „niepodpartych” z designu — czyli błąd reguły, nie liczba do przykręcenia. Pomiar w Edit to odczyt, nie test gry (zasada 2026-09-20), a daje odpowiedź w minutę.
> 10. **Wszystko, co istnieje tylko u jednego klienta, NIE MOŻE wpływać na grę — sprawdź KOLIZJE i PROMIENIE.** (2026-09-23, złapane przez Kacpra pytaniem, nie przeze mnie.) Lokalny gruz miał kolizję z postacią: w trybie Pełnym dało się stanąć na kawałku, którego gracz na Ziemniaku nie ma. Do tego pułapka silnika: **`CanQuery = false` działa TYLKO przy `CanCollide = false`** — z kolizją lokalny part łapał promienie klienta (celownik mostu!). Przy każdym lokalnym obiekcie pytanie kontrolne: czy ktoś może na nim stanąć, czy popycha, czy trafi w niego promień, którego wynik idzie do serwera?
> 11. **Przy zgłoszeniu z Play najpierw przeczytaj LOG TEJ SESJI (`get_console_output`), dopiero potem symuluj.** (2026-09-24.) „Górne piętra spadają za szybko” wyglądało na błąd solvera; symulacja w Edit pokazała, że logika jest dobra (piony 3. piętra padają dopiero przy ~93% zniszczonego parteru), a log `[Collapse]` z sesji Kacpra — że 16 z 25 grup poszło ponad budżetem do klientów i serwer je kasował. **Symulacja sprawdza LOGIKĘ, log sprawdza WYKONANIE** — potrzebne oba, a log jest tańszy. Pilnować, żeby log był z NOWEJ sesji (zasada 2026-09-20, punkt b).
> 12. **Logika offline ≠ fizyka w grze — przy destrukcji mierz WYKONANIE rejestratorem.** (2026-09-25.) Symulacja w Edit mówiła, że pod spadającymi grupami stoi coś tylko w 5 z 21 przypadków; w grze 21 z 25 grup nie ruszyło się ani o stud. Różnicę robiły rzeczy, których solver nie widzi: fragmenty i kikuty zostające w mapie, tarcie, 0,25 s kolizji przekazanych kawałków. Najtańszy pomiar: na serwerze Y korzenia każdej odkotwiczonej bryły przy starcie i przy osiadaniu („spadło X z Y”) — jedna liczba mówi więcej niż zrzuty ekranu. Log gry sam podaje teraz, co trzyma zaklinowaną grupę (część v4 + stan chunka).
> 13. **„Nie ma MCP” (`Roblox_Studio` połączony, ale `tool_count: 0`) = NAJPIERW przeczytaj log MCP tej sesji, dopiero potem zgaduj.** (2026-09-26 — ~30 min rano poszło w złą hipotezę, wieczorem log dał odpowiedź w minutę.) Log: `~/Library/Caches/claude-cli-nodejs/-Users-kacper-escapelava/mcp-logs-Roblox-Studio/<najnowszy>.jsonl`.
>     - **Przyczyna 26.09 (ZMIERZONA)**: Claude Code zaktualizował się sam 26.09 o 13:57 (2.1.280 → **2.1.281**) i negocjuje ze StudioMCP nowy protokół MCP `2026-07-28` („modern”); lista narzędzi StudioMCP nie ma pól `ttlMs` / `cacheScope`, których ten protokół wymaga, więc klient ją odrzuca (`Failed to fetch tools: Invalid result for tools/list … ttlMs … cacheScope`). 25.09 było `2025-11-25` („legacy”) i 115 wywołań narzędzi. **Samo Studio jest sprawne** — ręczna próba (`initialize` + `tools/list` na StudioMCP) zwróciła 28 narzędzi.
>     - **Obejście**: `.claude/settings.local.json` (poza gitem) → `"env": { "MCP_PROTOCOL_NEGOTIATION": "legacy" }` — oficjalny wyłącznik z notatek wydania Claude Code (drugi: `MCP_SDK_GENERATION=v1`). Działa po ponownym połączeniu `Roblox_Studio` (Kacper: `/mcp` → Reconnect) albo w nowej sesji — ✅ potwierdzone 26.09 wieczorem: nowa sesja wynegocjowała `2025-11-25`, narzędzia działają. **Usunąć, gdy Roblox albo Anthropic naprawią zgodność** — dziś trzyma cały projekt na starym protokole MCP.
>     - ⛔ **Poranna diagnoza 26.09 była BŁĘDNA (lekcja 3 po raz kolejny)**: „dwa procesy `StudioMCP`, Studio łączy się tylko z jednym”. Tak to działa z założenia: pierwszy `StudioMCP` wystawia hub na `127.0.0.1:13469`, Studio i każdy kolejny `StudioMCP` łączą się z nim jako klienci (zmierzone `lsof`) — kilka sesji Claude może korzystać ze Studio naraz. **Nie zabijać cudzych `StudioMCP`**, bo zabicie pierwszego rozłącza wszystkich.
>
