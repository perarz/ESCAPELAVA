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
  - `src/server/Services/` — 25 serwisów; `src/client/Controllers/` — 20 kontrolerów (opisy, pułapki i historia decyzji: **`docs/ARCHITECTURE.md`**)
  - `src/shared/Modules/` — `Config` (WSZYSTKIE liczby), `ItemDefinitions`, `Remotes` (tworzy RemoteEventy w runtime — folderu `src/shared/Remotes` nie ma), `Utils`, `Destructible`, `Fracture`, `Dev`, `AppearanceDefinitions`, `GrappleArc`
  - **`docs/`** — dokumentacja referencyjna, czytana na żądanie (mapa niżej). **`PROJECT_CONTEXT.md`** — kontekst dla asystenta od planowania (perspektywa gracza, bez kodu); **aktualizować razem z tym plikiem**. `DESTRUCTION_PLAN.md` — plan destrukcji v2.
  - **SKRYPTY NAPRAWCZE W KORZENIU REPO** (Command Bar w Studio, EDIT mode, potem Cmd+S) — nie są częścią gry, tylko narzędziami do przywracania kontraktu mapy po bulk-apply materiału:
    - `LAMPS_LIGHTS.luau` — 36 kloszy latarni na `Neon` + `SurfaceLight`; TRYB 2 usuwa światła, TRYB 3 zamienia na PointLight.
    - `TRAFFIC_LIGHTS.luau` — 150 żarówek sygnalizatorów na `Neon`; TRYB 2 cofa.
    - `WINDOWS_GLASS.luau` — 367 szyb na `Material = Glass`; TRYB 2 cofa.
    - `LIGHTING_REVERT.luau` — cofnięcie wartości `Lighting` do stanu sprzed 2026-09-16.
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

## STATUS PROJEKTU (ostatnia aktualizacja 2026-09-23)

> 🔴 **PRZECZYTAJ NAJPIERW — STAN NA KONIEC SESJI 2026-09-22/23.** To jest aktualny punkt.
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
>    - 🔴 **X-RAY, który z tego wyszedł** („czemu dałeś mi x-raya, kamera ma się zatrzymywać na ścianie"): plac miał `StarterPlayer.DevCameraOcclusionMode = Invisicam` — tryb, w którym kamera Robloxa w ogóle NIE zatrzymuje się na ścianach, tylko robi je przezroczystymi. Przesunięcie w bok częściej stawiało ścianę między kamerą a postacią, więc wbudowany x-ray wyszedł na wierzch. **Naprawa**: `DevCameraOcclusionMode = Zoom` w `default.project.json` (repo jest źródłem prawdy dla ustawień kamery, obok zoomu i blokady myszy) + `keepLineOfSight` w `MovementController` — promień OD GŁOWY do kamery, bo `Zoom` pilnuje kamery tylko PRZED naszym przesunięciem i wygładzaniem. ⏳ Czeka na test razem z head trackingiem.
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
> - **`HUD.Hotbar.Slot3` NIE ISTNIEJE** (sprawdzone 22.09: tylko `Slot1`, `Slot2`). Hak jest TRZECIM itemem — działa z klawisza `3`, ale **nie widać go w pasku**. Fix po stronie Kacpra: skopiować `Slot2` → `Slot3`. `HotbarController` ma `if not btn then return end`, więc brak slotu niczego nie wywala — tylko ukrywa item. ⚠️ Każdy kolejny item = kolejny `SlotN`.
> - **Brak markera kamery przy haku** w `WeaponShopScene.ShopCameras` — kadr liczy się z bounding boxa. Marker postawiony obok `HandHook` przejmie kadr bez zmiany kodu (parowanie po odległości: `BombCamera` stoi 19.2 od haka, ale bliżej `Blueprint`u, więc go nie przejmuje — zmierzone 22.09).
> - ✅ **ŚLIZG ZNIKNĄŁ** (Kacper 23.09: „nie ślizga się przy chodzeniu") — po konwersji rigu. **Przyczyna NIE zmierzona** — nie przypisywać jej niczemu i nie ruszać (patrz „ŚLISKI MOVEMENT").
> - 🔴 **HEAD TRACKING NIE DZIAŁAŁ NIGDY** (Kacper 23.09: „nie działało od początku wprowadzenia") — ✅ przy nim w „Co jest GOTOWE" był fałszywy od zawsze, a hipoteza „wróci po konwersji rigu" była błędna. **Ustalone 23.09**: stawy SĄ znajdowane, obrót ginie. Brak stawów WYKLUCZONY dwiema drogami: w ~8 sesjach Play po restarcie Studio nie ma ani jednego `[HeadTrack] brak Motor6D` (kod drukuje go przy KAŻDEJ postaci, której nie obsłuży), a odczyt postaci w grze pokazał `Neck` (UpperTorso→Head) i `Waist` (LowerTorso→UpperTorso) jako `Motor6D`, `Enabled`, z `C0` BEZ rotacji. **Najpewniejszy mechanizm** (niezmierzony): `applyAim` mnoży `Motor6D.Transform` w `RenderStepped`, bo komentarz w kodzie zakłada, że animator działa w RenderStep z priorytetem `Character` i wystarczy być po nim — a `RenderPriority.Character` to tylko numer kolejki dla skryptów; animator nadpisuje `Transform` w całości we własnej fazie klatki. ➜ **Fix ZROBIONY 23.09, CZEKA NA TEST KACPRA**: `C0 = zapisaneC0 * obrót` — animator nie dotyka `C0`, więc fix nie zależy od dokładnego mechanizmu; oryginały `C0` są już zapisywane w `asyncCacheJoints` i nigdzie nieużywane. Do tego przywrócenie `C0` przy ragdollu/śmierci (`C0`, w odróżnieniu od `Transform`, nie resetuje się sam). ⚠️ Znaki obrotu sprawdzone RACHUNKIEM na osiach tego rigu (kamera w dół → głowa w dół, w lewo → w lewo), ale NIGDY okiem — obrót nie był dotąd widoczny. Odwrotnie w grze = zmienić znak w `applyAim`.
> - **Zaczep hakiem pod nogi zużywa sztukę za nic** (log 23.09: `dist=4.4 luk=0.01s` — klik w ziemię pod sobą daje lot o ~1 studa, a item schodzi). W trybie dev niewidoczne (99 sztuk), na produkcji to strata 40$ za misklik. **Odłożone przez Kacpra 23.09.** Fix: w `GrappleService` odrzucić PRZED `consume`, gdy lot (`goal − origin`) krótszy niż ~3 study.
> - **Diagnostyka destrukcji zgłasza sam pocisk bomby** przy KAŻDYM wybuchu („7 partów w zasięgu NIE zostało pociętych — `Anchored=false` … `Workspace.BombProjectile.Part`"). To bomba, która właśnie wybucha — szum zagłuszający prawdziwe ostrzeżenia o partach postawionych poza `Map`. **Odłożone przez Kacpra 23.09.**
> - **Pomiar obciążenia (log 23.09)**: jeden wybuch na dachu dał `spadło=472`, `gruz=260/260`, **`ms=80`** — ~5 klatek zacięcia z jednej bomby. Materiał do tematu „destrukcja pod obciążeniem" (NASTĘPNE KROKI); to balans, nie bug.
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
> `LoadCharacterWithHumanoidDescription` · wyrównywanie skal postaci · przełączanie `CustomPhysicalProperties` HRP/Head · rozluźnianie limitów stawów · `AdjustSpeed` na animacji chodu · preset „Consistent Gameplay" · bramki raycastowe oprawy lawy (`isExposed` / `isLavaOpenAt`) · `SmoothPlastic` jako materiał ciała.
>
> **➡️ NASTĘPNE KROKI**: najpierw **zaległe testy** (rig, ragdoll, head tracking, fall damage — patrz OTWARTE). Potem Kacper wybiera kierunek: **kolejne itemy z wystawy** (RPG / sticky bomb / energy drink — modele już stoją) albo **ścieżka wyglądu** ② przebieralnia → ③ sklep kosmetyczny → ④ pancerze (**wymagają fixu anti-cheata**, patrz „TRZY PUŁAPKI"). Równolegle: test destrukcji pod obciążeniem (`gruz=260/260` i `ms=59` na wybuch w logu — budżet wysycony).
>
> 📌 **LEKCJE PROCESOWE — DROGO KUPIONE, CZYTAĆ PRZED DEBUGOWANIEM:**
> 1. **Najpierw ustal, CO DOKŁADNIE widzi człowiek.** „Ślizganie" = responsywność sterowania, nie ruch stóp; trzy zmiany i cztery pomiary poszły w rzecz, która nie była problemem.
> 2. **Przy „nie widać X" sprawdź najpierw, GDZIE X naprawdę jest**, zanim poprawisz, jak jest rysowane. Ghost mostu nie był maskowany — stawiał się pod lawą.
> 3. **Hipoteza spójna z objawem bywa nieprawdziwa.** Sortowanie przezroczystości i globalne nadpisanie `MaterialService` tłumaczyły objawy idealnie i oba były błędne.
> 4. **Przy trzeciej nieudanej próbie cofaj się, nie łataj.**
> 5. **Objaw „to nie działa" bywa niezsynchronizowanym kodem.** W tej sesji DWA RAZY zmiany nie dojechały do Studio, mimo że były na dysku. **Zanim ocenisz efekt — sprawdź `rojo serve` i Connected.** 2026-09-22 po raz trzeci: po restarcie Studio `rojo serve` nie chodził i wszystkie 5 zmienionych plików było w Studio STARYCH. **Sprawdzenie z MCP bez odpalania Play**: w Edit `pcall(loadstring, skrypt.Source)` — `nil` + komunikat = błąd składni; znacznik z nowej wersji w `.Source` = Rojo dowiozło. To obserwacja, nie test (zasada 2026-09-20). ⚠️ NIE przez `require` — hard rule 14.
> 6. **Kacper testował raz na pliku `AutoRecovery`, nie na swoim placu.** Studio raportuje się wtedy jako `<placeId>_AutoRecovery_0.rbxl` — `list_roblox_studios` to pokazuje. Przy „u mnie tego nie ma" sprawdzić nazwę instancji.
> 7. **Przy kolejnym feedbacku do TEJ SAMEJ mechaniki zbierz wszystkie dotychczasowe wymagania w jedną tabelę, ZANIM cokolwiek zmienisz.** Hak: trzy wersje lotu, każda naprawiała ostatnie zgłoszenie i łamała poprzednie (kierunek → dotarcie → łuk). Dopiero tabela „wersja × wymaganie" pokazała, że potrzebny jest INNY MODEL, a nie czwarte strojenie liczb. Pytanie kontrolne przed każdą poprawką: **czy to nie cofa czegoś, co Kacper już zaakceptował?**
> 8. **Plan oparty na zachowaniu silnika — sprawdź najpierw USTAWIENIE, które to zachowanie włącza.** Kamera zza ramienia zakładała, że kamera Robloxa zatrzymuje się na ścianach (tryb `Zoom`); sprawdziłem zakres zoomu, a nie tryb zasłaniania — plac miał `Invisicam`, i wyszedł x-ray. Przy kamerze: najpierw `StarterPlayer.DevCameraOcclusionMode`.
>
