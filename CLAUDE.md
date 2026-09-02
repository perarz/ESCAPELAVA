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
9. **RemoteEvent NIE buforuje** — jeśli klient nie ma `OnClientEvent:Connect` w momencie `:FireAllClients`, event jest stracony. Klient musi podpiąć listenery PRZED `WaitForChild` (które yielduje). Plus serwer musi replikować aktualny state na `PlayerAdded` (`GameLoopService.replicateTo(player)`).
10. **HUD ScreenGui ResetOnSpawn=false** — domyślnie `true` → odświeża HUD przy każdym `LoadCharacter` (czyli przy starcie każdej rundy gracz traci listener Connect z poprzedniego HUD instance).
11. **Nowy R15 character rig** — Roblox zmienił charakter rig. Stare Motor6D już nie są default. Nowy character ma 14× BallSocketConstraint (LimitsEnabled, niskie kąty) + 15× AnimationConstraint (animation drivers) + 0 Motor6D. Custom ragdoll patternem destroy Motor6D NIE działa — trzeba disable AnimationConstraint + rozluźnić istniejące BallSocketConstraint upper angles. **W tym projekcie używamy toolbox ARTFVL Ragdoll** (folder w Workspace, kopiuje się do PlayerGui przy joinie) — działa, bo on dodaje altrootmotor (Motor6D HRP→UpperTorso) + osobne BallSocket constraints w `RagdollConstraints` folder. BombService wywołuje `PlayerGui.ragdoll.functions.ragdoll:Invoke(velocity)` BindableFunction, plus `variables.ragdoll.Value = false` po duration unragdolluje. Listener w toolbox `ragdollserver` script musi być uncommented (linia ~449).
12. **Network ownership** dla character — player character ma `NetworkOwner = LocalPlayer` (klient kontroluje physics). Server-side Motor6D destroy są nadpisywane klient prediction. Aby server wykonał ragdoll, trzeba `SetNetworkOwner(nil)` na każdą BasePart (tylko unanchored).
13. **DataStore** — używamy `UpdateAsync` (atomic, nie GetAsync+SetAsync race). Session lock (`data._sessionId`), retry exp backoff x3, auto-save 60s, BindToClose force-save wszystkich graczy (max 30s). Studio wymaga "Enable Studio Access to API Services" w Game Settings → Security żeby działało.
14. **execute_luau MCP ma osobny module cache** — gdy testujesz przez execute_luau `require()` dostaje NOWĄ instancję modułu (osobne `cache` tabele, osobne BindableEvent). NIE polegaj na nim do server-side state inspection. Sposób na test: dodaj prints w services, restart Play, czytaj F9 logi.

---

## Stack & struktura

- **Rojo 7.7.0-rc.1** (Aftman), VS Code, Luau, Roblox Studio.
- **Struktura repo** (zgodna z GDD sekcja 10):
  - `src/server/Services/` — services (GameLoop, Lava, Player, Shop, Coin, Item, ...)
  - `src/shared/Modules/` — Config, Utils, ItemDefinitions, ...
  - `src/shared/Remotes/` — pusty folder; RemoteEventy tworzy `Modules/Remotes.luau` runtime
  - `src/client/Controllers/` — controllers (UI, Input, Item, Sound, ...)
- **Workspace** struktura (po stronie Studio — Kacper buduje pod te nazwy):
  - `Workspace.Map` (Folder) — geometria mapy Downtown (budynki, dziury, ozdoby)
    - `Workspace.Map.Spawn` (BasePart, anchored) — round spawn target (kod tu teleportuje na start rundy); fallback gdy `Workspace.SpawnPoints` pusty
    - `Workspace.Map.Baseplate` (BasePart, anchored, **Locked=true** żeby destrukcja nie ruszała)
  - `Workspace.SpawnPoints` (Folder, opcjonalny) — BasePart'y dowolne nazwy; kod losuje pozycje na rundę (gdy postawisz wiele = multi-spawn)
  - `Workspace.Lobby` (Folder) — geometria wizualnego lobby
    - `Workspace.Lobby.Spawn` (BasePart, **anchored**) — lobby teleport target (przerwa + po śmierci); kod bierze `.Position + offset`
  - `Workspace.ItemSpawns` (Folder) — pickup points dla itemów na mapie (Day 4+)
  - `Workspace.Lava` (Folder)
    - `Workspace.Lava.LavaPart` (BasePart, anchored) — opcjonalny; LavaService preferuje istniejący Part (Kacper może edytować color/material/size w Studio i kod respektuje), animuje tylko Y. Brak → tworzy z Config.
  - `Workspace.Ragdoll Script, read the READ ME inside!` (Folder) — **toolbox ARTFVL ragdoll**, RagdollScriptMover przenosi `ragdoll` folder do StarterGui przy starcie; nie usuwać. Listener `variables_ragdoll:GetPropertyChangedSignal("Value")` w `ragdollserver` MUSI być uncommented dla auto-unragdoll.
- **StarterGui** struktura (po stronie Studio — Kacper buduje pod te nazwy):
  - `StarterGui.HUD` (ScreenGui, **ResetOnSpawn=false** — krytyczne!) — wszystkie labele bezpośrednio jako children HUD (UIController szuka rekurencyjnie `FindFirstChild(name, true)`)
    - `StateLabel` (TextLabel) — "LOBBY" / "GET READY" / "ROUND" / "ROUND OVER"
    - `TimerLabel` (TextLabel) — countdown całego stanu (w ROUND: cała runda, NIE per faza)
    - `CoinLabel` (TextLabel) — kasa gracza, format `tostring(coins) .. "$"` (aktualizuje się przez Remote `CoinsChanged`)
    - `StaminaLabel` (TextLabel) — licznik staminy, format `STAMINA: N` (0-100). Zastąpił pasek 2026-08-12; stary `StaminaBar`/`StaminaBarBG` kod chowa (Visible=false), a gdy brak labela — tworzy go w miejscu paska
    - `Hotbar` (Frame) — kontener slotów inventory
      - `Slot1` (TextButton, 84×84) — bomba (jedyny item w v1.0). Children: `ItemName`, `Count`, `Keybind` (TextLabele), `SelectStroke` (UIStroke)
      - W przyszłości Slot2/3/4/5 — HotbarController auto-mapuje pierwsze N item types z `ItemDefinitions.shopOrder`
    - `ShopButton` (ImageButton lub TextButton) — toggle ShopMenu, klient dodaje hover tween (size +10% + rotation -5°)
    - `ShopMenu` (Frame, Visible=false) — menu sklepu
      - `Offers` (ScrollingFrame) z `OfferTemplate` (Frame, hidden) — klient klonuje per oferta
      - `CloseButton` (TextButton), `StatusLabel` (TextLabel), `Title` (TextLabel)

---

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

## STATUS PROJEKTU (Day 1-6 w większości zrealizowane; ostatnia aktualizacja 2026-08-12)

> Ten STATUS odzwierciedla realny kod w `src/`. **CoinService został przemianowany na `CashService`** (wszystkie nazwy walutowe = Cash: `CashChanged`, `CashLabel`, leaderstat `Cash`).
>
> **Sesja 2026-08-11** zrobiła trzy rzeczy: (1) powrót licznika kasy do TextLabela, (2) pełny audyt kodu serwera — 3 błędy P0 (session lock, fałszywy sukces `ItemService`, pominięty `RoundEnded`), 4 optymalizacje skali i seria porządków, (3) **skasowanie całego systemu wybuchu bomby** (patrz niżej). Szczegóły przy opisach poszczególnych services.
>
> ⚠️ **SYSTEM DESTRUKCJI v2 — 2026-08-11.** Stary wybuch (BlastService) skasowany bez śladu na życzenie Kacpra; tego samego dnia zaprojektowany i zaimplementowane **wszystkie 5 etapów** wg `DESTRUCTION_PLAN.md` (CZYTAJ ten plik przed dotykaniem destrukcji). Rdzeń: `Fracture.luau` (cięcie boxów na nierówne kawałki, deterministyczne z seedem) + `DestructionService` (fala: blisko NISZCZY/fracture→dziura, średnio RANI/HP attribute, daleko PCHA) + `DebrisService` (rejestr gruzu: izolacja kolizji, usypianie→platformy, budżety) + klienckie `ExplosionFXController`/`DebrisFXController` (cały VFX wybuchu + kosmetyczne odłamki lokalnie, `Remotes.BlastFX` + seed). **Stan: etap 1 przetestowany w Play, etapy 2-5 (kategorie szkło/filar, occlusion, fall-fracture, crush damage, kolaps sekcji po filarach, scorch+audio) zaimplementowane i CZEKAJĄ NA TEST.** Doszły `StructureService`, `Destructible.luau`, `Dev.luau`. Ochrona: `Locked`, `Map.Locked`, `ActiveCash` nietykalne; mosty NISZCZALNE (sabotaż PvP działa od etapu 1).
>
> **Lekcja operacyjna z tej sesji:** gdy `rojo serve` padnie w trakcie edycji, Studio zostaje z **półzsynchronizowanym** plikiem i objawy wyglądają jak błąd w logice (u nas: lawa przestała zabijać, bo dojechało usunięcie `Touched`, ale nie dojechało wywołanie nowej funkcji). Przed diagnozą jakiegokolwiek "to nie działa" sprawdź `rojo serve` i porównaj kod w Studio z repo.

### Server services (`src/server/Services/`) — 22 services
- `GameLoopService` — state machine: LOBBY 15s → COUNTDOWN 5s → ROUND (Spawn 5s + Easy 20s + Mid 20s + Hard 20s + Endgame 15s = 80s) → POST_ROUND 10s → loop. **Dev API (2026-08-12)**: `devSkip()` (jednorazowy `skipRequested`, konsumowany przez najbliższy wait — jedno naciśnięcie = jedna pominięta faza/stan; działa w LOBBY/COUNTDOWN/fazach/POST_ROUND) i `devEndRound()` (`forceEndRound` → `shouldEndRound`, czyszczony na starcie i końcu rundy). Wołane WYŁĄCZNIE przez DevService po walidacji. `replicateTo(player)` dla nowych graczy. `RoundEnded` BindableEvent fired po końcu rundy (MapService, RewardsService, BridgeService, CashPickupService listenują). **Pętla faz ma własny `pcall`** (2026-08-11) — błąd w fazie NIE może pominąć `RoundEnded`, bo na nim wiszą restore mapy, nagrody i wszystkie cleanupy; wcześniej jeden wyjątek zostawiał świat w gruzach z `aliveSet` pełnym duchów.
- `LavaService` — preferuje `Workspace.Lava.LavaPart`, animuje Y. Speeds: 0/0.6/1.2/2.0/3.0. **⚠️ `Config.Lava.Enabled = false` od 2026-08-12 (testy destrukcji)** — part istnieje, ale lawa nie rośnie i nie zabija; głośny warn co boot. PRZYWRÓCIĆ przed testem rund. **Zabija przez POZYCJĘ, nie Touched** (2026-08-11): `killSubmerged` 10Hz porównuje `HRP.Y - 2.5` z powierzchnią lawy + granice XZ. `CanTouch=false`, bo Touched na parcie 361×6×388 ruszanym co klatkę odpalał się dla każdego stykającego się obiektu — przy destrukcji otoczenia to były tysiące wywołań/s od spadającego gruzu (destrukcja skasowana, ale rozwiązanie zostaje: jest tańsze i odporne na szybki ruch). Przy okazji znika błąd "Touched nie odpalił przy szybkim ruchu". **CanCollide=false** — lawa nie pcha klocków w górę (bez tego rozjebane parts robiły windy żeby wygrać). VFX (2026-07-05): embery+dym z powierzchni (emittery na LavaPart) + para/embery przy śmierci w lawie (`spawnDeathPoof`).
- `MapService` — snapshot Workspace.Map (poza `Locked`) przy bootcie → ServerStorage.MapSnapshot. Po RoundEnded: cleanup `BombProjectile` parts w Workspace, wait RESTORE_DELAY=0.5s (żeby survivor'zy zdążyli wylądować w lobby), destroy aktualne destructibles, clone snapshot back. Bez tego mapa zostawała rozjebana następnej rundy.
- `PlayerService` — `CharacterAutoLoads=false`, lobby/round teleport, distance check dla survivor'ów (POST_ROUND nie rusza martwych w lobby). `isAlive(player)`, `getAliveList()` API. `aliveSet` = single source prawdy (fires `Remotes.AliveChanged`). `onDeath` woła `KillService.processDeath` (credit kill$). Spawn rundy: `LoadCharacter` w **pcall per gracz** (błąd jednego nie przerywa pętli i nie zostawia reszty jako duchów w aliveSet) + **jedna klatka na fizykę dla wszystkich** zamiast jednej na gracza (przy 20 graczach spawn trwał ~20 klatek).
- `PlayerDataService` — DataStore wrapper. Combined state `{cash, inventory, wins, dailyStreak, lastClaimDay, _sessionId, _savedAt, _starterReceived}`. UpdateAsync, retry x3 exp backoff, **session lock po OBU stronach** (load czeka aż inny serwer zwolni klucz — max 3× po 2s, potem przejmuje z warnem gdy lock starszy niż 90s; save pomijany gdy klucz przejęty i wtedy loguje SKIP, nie "saved"), BindToClose force-save, auto-save 60s z losowym jitterem (żeby gracze z jednej fali nie zapisywali się w tej samej sekundzie). Studio loaded_default gdy API off. `subscribe(fn)` pub/sub (eventy: loaded/loaded_default/updated), `update(player, mutatorFn)` atomic.
- `CashService` — kasa per player (klucz `data.cash`), używa PlayerDataService. `add(p, amount, reason)` / `spend(p, amount, reason)` / `get(p)`. Każda transakcja logowana (timestamp + reason, hard rule #6). Fires `Remotes.CashChanged`.
- `ItemService` — inventory schema `{ [itemId] = count }` (unlimited stack). `give/consume/getCount/getInventory`. **Tryb dev (2026-08-12)**: gdy `Dev.hasInfiniteItems(player)`, `snapshot()` zwraca SYNTETYCZNE inventory (wszystkie itemy z `shopOrder` × `InfiniteItemCount`), a `consume` jest no-opem zwracającym `true`. Wstrzyknięte w jednym miejscu, więc hotbar/sklep/BombService/BridgeService widzą to samo automatycznie. **Nic nie idzie do DataStore** — prawdziwe `data.inventory` deva zostaje nietknięte i wraca po `Config.Dev.Enabled=false`. **`give`/`consume` zwracają realny wynik zapisu** (2026-08-11): gdy dane gracza nie są jeszcze załadowane, `update` nic nie zapisuje → `give` zwraca `false, "data_not_loaded"`. Wcześniej zwracało `true` bez względu na wszystko, więc caller był przekonany że gracz dostał item, a log drukował `total=0`. Użycie itemów NIE idzie przez ItemService — każdy item ma własny remote + service (ThrowBomb→BombService, BuildBridge→BridgeService); generic dispatcher UseItem wycięty jako dead code (2026-07-04).
- `ShopService` — server-authoritative buy. Bez rate limit (atomic `ItemService.give` + `CashService.spend` chronią przed exploitami). Alive check (sklep tylko poza ROUND lub spectator), atomic give→spend z undo. ShopResult feedback do klienta.
- `BombService` — Tool z Ball Handle, equip/unequip/throw flow. Throw: consume z inventory, spawn fizyczny projektyl, fuse 2.5s ZAWSZE. Detonacja: `DestructionService.detonate(center, def.destruction, thrower)` (geometria + BlastFX) **PRZED** `applyDamageAndKnockback` (occlusion polega na tej kolejności — zdmuchnięta ściana nie osłania). Efekt na graczach: **occlusion** (`computeOcclusion` — każda ściana ×0.45; `effT < MinEffect 0.05` = brak trafienia, zero taga/ragdolla przez 2 ściany), damage 50% MaxHealth × effT (radius 22) + knockback `force=450 × max(0.35, rawT) × occlusion` z lift (toolbox ragdoll) + kurz przy lądowaniu ragdolla. Taguje ofiary przez `KillService.tag(hum, attacker, "bomb")`, fires `Remotes.BombHit` (screen shake + FOV punch). **Auto-re-equip po throw** jeśli count>0. VFX lontu (migające światło puls → strobo, iskry, dymny ogon) — czytelny sygnał "uciekaj".
- `DestructionService` — **NOWY (2026-08-11, system v2 — DESTRUCTION_PLAN.md; etap 1+2)**. Skutki wybuchu na geometrii: kwalifikacja (destructible = `Workspace.Map` + `ActiveBridges`; chronione: `Locked`, `Map.Locked`, `ActiveCash`, Terrain, postacie), damage strukturalny z falloffem po dystansie do POWIERZCHNI parta (HP w attribute `DestrHP`; ranny part **ciemnieje + pyli** proporcjonalnie do utraconego HP — feedback), fracture Block partów przez `Fracture.slice` (kawałki w kuli → gruz z impulsem stożkiem; poza kulą → anchored remnants), non-Block (kule/cylindry/wedge/mesh) → `launchWhole`. **DZIURA (naprawione 2026-08-12)**: promień dziury NIE równa się promieniowi wybuchu — liczy się z modelu obrażeń `radius × (1 − hp/damage)` (floor `MinHoleRadius` 3.5), gdzie `hp` to stan RESZTKOWY. (2026-08-12 była próba sufitu `MaxHoleRadius` — **skasowana**, bo przycinała wyrwy w ścianach do odprysków i psuła odczucie wybuchu; górnym ogranicznikiem jest sam promień wybuchu. Nie wracać do tego bez wyraźnej prośby.) **Kształt nieregularny**: granica to nie kula, tylko promień modulowany szumem Perlina zależnym od kierunku (`HoleIrregularity` 0.42, `HoleNoiseScale` 0.14) — obrys waha się ~±23% wokół średniej, więc czyta się jako wyrwa, nie jako otwór wycięty cyrklem; cięcie sięga `hole × (1 + irregularity)`, żeby pas wybrzuszeń też był rozdrobniony. Plus jitter per wybuch (`ChunkSizeJitter` 0.22, `HoleRadiusJitter` 0.15) i losowy offset szumu — dwie bomby w tę samą ścianę dają RÓŻNE wzory. Bomba 24/160 w ścianie HP 100 → dziura r=9, czyli ~11% ściany 80×30 zamiast 80%; mocniejsza bomba = większa dziura bez żadnej osobnej gałki. Test "czy kawałek jest w dziurze" po ŚRODKU kawałka, nie po powierzchni — wielka płyta dotykająca epicentrum rogiem odlatywała CAŁA. **Kategorie (etap 2)**: tag `Pillar` → HP 300 (2-3 bomby), Material Glass → szyba (osobny pass `glassRadius` 60 — tłuką się nawet na sąsiednich budynkach, bez occlusion, zero gruzu serwerowego, payload najbliższych 40 tafli w BlastFX), `ActiveBridges` → HP 40 (deski w lawę), reszta → Wall 100. **Podparcie (etap 2, v2 po testach)**: sprawdzana PIONOWA KOLUMNA geometrii wokół epicentrum (XZ = radius×1.3, wysokość 400 — łapie piętra wysoko nad wybuchem), nie tylko świeże remnanty; KIERUNKOWO — sąsiad całkowicie powyżej parta go nie podpiera, kontakt boczny tak; BFS po krawędziach skierowanych; niepodparte party spadają jak gruz. `task.wait()` jedna klatka przed passem (świeże remnanty muszą wejść do broadphase). Mosty NIE wchodzą do sprawdzenia z bliskości (wiszą z designu); **platformy/ozdoby Kacpra które mają wisieć → `Locked=true` albo `Map.Locked`**, inaczej spadną przy bombie obok. Pełny kolaps sekcji (filary) = etap 4. **`computeOcclusion(center, targetPos)`** — publiczne API dla BombService: każda ściana ×0.45, szkło/przezroczyste nie osłania, latający gruz i postacie wykluczone. Budżety: `MaxChunksPerPart` 32, `MaxServerChunksPerBlast` 110, globalny soft-cap przez DebrisService. Fires `Remotes.BlastFX(center, radius, seed, glassPanes)` PRZED fizyką. Stats + `[Destr]` debug print (ms per wybuch). **Diagnostyka kontraktu mapy (2026-08-12)**: gdy wybuch obejmie party, których nie może pociąć, leci warn z powodem i przykładowymi ścieżkami — osobno „POZA `Workspace.Map`" i osobno „`Anchored=false`" (nieanchorowany part = gruz, nie konstrukcja: dostaje impuls, nie pęka). Powstało po tym, jak Kacper postawił party testowe w korzeniu Workspace i dostał ciszę zamiast informacji. Chronione (`Locked`) NIE są raportowane — ich pomijanie jest zamierzone.
- `StructureService` — **NOWY (2026-08-12, system v2 — etap 4)**. KOLAPS SEKCJI. Różnica wobec passu podparcia w DestructionService: tamten jest GEOMETRYCZNY ("czy part czegokolwiek dotyka"), ten KONSTRUKCYJNY ("czy piętro ma na czym stać"). Model: budynek = folder/model pod `Workspace.Map`; **pasmo** = filary (tag `Pillar`) o zbliżonym Y (klastrowanie sąsiadów, `BandTolerance` 10) = jedno piętro. `notifyPillarDestroyed(part, attackerId)` wołane przez DestructionService **przed** Destroy filara (po Destroy nie ma tagu ani pozycji): ≥`CreakThreshold` 0.5 martwych → **creak** (pył ze stropów + dźwięk + mikro-shake, cooldown 4s), ≥`CollapseThreshold` 0.75 → **kolaps** — wszystko powyżej `topY` pasma w tym budynku odkotwiczone, oddane DebrisService (dalej normalnie: izolacja, usypianie, fall-fracture, crush), cap `MaxPartsPerCollapse` 220, lekki rozrzut na boki. Próg 0.75 zamiast 1.0 celowo — "ostatni filar w rogu trzyma wieżowiec" wygląda jak bug. `rescan()` na init **i na każdym COUNTDOWN**, bo MapService podmienia geometrię na świeże klony po rundzie. Fires `Remotes.StructureFX`.
- `DebrisService` — **NOWY (2026-08-11, system v2; etap 1+3)**. Jedyny właściciel rejestru gruzu serwerowego (`Workspace.BlastDebris`): properties betonu (density 3, elasticity 0.05), izolacja kolizji gruz↔gruz 0.35s (collision group `BlastDebris`), `SetNetworkOwner(nil)`, usypianie (nieruchomy 0.6s → Anchored = chodliwa platforma; `wake` przy kolejnym wybuchu), globalny `MaxMovingDebris` 450 z gwarancją `MinChunksPerBlast` 40. **Etap 3 (2026-08-12)**: (a) **fall-fracture** — kawałek z twardym uderzeniem (delta prędkości ≥55 stud/s między tickami skanu; sama grawitacja robi ~39 przy 5Hz) pęka na 2-3 mniejsze + pył; JEDNA generacja max, floor objętości 18, cap 6 pęknięć/tick; uderzenia zbierane do listy i przetwarzane PO pętli pairs (dodawanie kluczy w trakcie iteracji = UB); (b) **crush damage** — szybki (≥24) i duży (≥8 studs³) kawałek przy kontakcie (dystans od POWIERZCHNI ≤2.5, velocity W gracza) rani `dmg = 70×volumeT×speedT` (floor 12), kill credit "crushed" przez `KillService.tag` z attribute `BlastAttackerId` (self-crush bez creditu), `AntiCheatService.grantGrace`, feedback przez reuse `Remotes.BombHit`, i-frames 0.7s/gracz. **Etap 5**: dźwięk uderzenia gruzu na anchorze pyłu (server-side instancja, zero nowych remote'ów) z throttlem `ImpactSoundsPerSecond` 6/s i rozstrojeniem PlaybackSpeed — przy kolapsie piętra ląduje naraz 200 kawałków. Cleanup całości na `RoundEnded`.
- `PushService` — F key PvP push. Cele: **wyłącznie gracze** (`Players:GetPlayers()` + `PlayerService.isAlive`), pchnięcie leci przez `Remotes.Pushed` do klienta ofiary. (Manekiny NPC były próbowane 2026-08-12 i **skasowane tego samego dnia** — dużo kodu, słabe działanie; nie wracać do tego pomysłu bez wyraźnej prośby. Push testuje się dwoma klientami: Test → Clients and Servers → Players 2.) Cooldown 4s/gracz (zużywa się NAWET przy missie), MAX_RANGE 7 stud, stożek ~70° (CONE_DOT=0.3). Target SERVER-SIDE. Fires `Remotes.Pushed` do target client (NetworkOwner workaround, zasada 12). Taguje przez `KillService.tag(hum, attacker, "push")` (credit gdy ofiara wpadnie w lawę w oknie).
- `CashPickupService` — **NOWY**. Cash rozsiane po mapie do zbierania. Spawn z `Workspace.Map.Locked.CashSpawns` (markery Kacpra), asset z `ReplicatedStorage.Cash`. Magnet pickup: heartbeat 10Hz szuka alive gracza w MagnetRange → atomic Collected flag → `CashService.add` + `Remotes.CashCollected` (klienci animują) → Destroy. Raycast skip gdy grunt pod lawą. **Cash zalany lawą kasowany w tym samym ticku** (porównanie Y) — wcześniej robił to osobny listener `LavaPart.Touched`, który przy gruzie z wybuchów odpalał się tysiące razy na sekundę dla wszystkiego, nie tylko dla cashu (destrukcja skasowana, ale rozwiązanie zostaje — było tańsze niezależnie od gruzu). Cleanup POST_ROUND.
- `BridgeService` — **NOWY**. Server-authoritative most (item `bridge_builder`). EquipItem → `BridgeBuildMode(true)` → klient ghost preview → `BuildBridge(anchorPos, rotationY)` → validate (alive, count>0, distance ≤ maxBuildDistance) → consume → spawn anchored Part w `Workspace.ActiveBridges`. Most ma być niszczalny przez wybuch (PvP sabotaż) — decyzja aktualna, ale **od 2026-08-11 nie ma jej czym wykonać** (destrukcja skasowana). Przy każdym spawnie wymuszamy `Locked = false`, żeby nowy system wybuchów zastał most gotowy do zniszczenia. Cleanup po RoundEnded.
- `HeadTrackingService` — relay aim głowy (yaw+pitch) klient X → wszyscy inni. Czysto kosmetyczne, ale walidowane: typecheck, clamp do max angles, rate limit **10Hz** (tyle ile klient realnie wysyła; było 15Hz "na zapas") + **dead zone 2°** — stojący gracz nie generuje żadnego ruchu sieciowego. Każdy przyjęty pakiet idzie `FireAllClients`, więc przy 20 graczach zapas kosztował tysiące wiadomości/s za sam kosmetyk. `Remotes.HeadAim`.
- `AntiCheatService` — detekcja speedhacka/teleportu przez **realnie przebytą odległość poziomą**, nie przez `Humanoid.WalkSpeed`. Zmierzone 2026-08-11: klient ustawia sobie WalkSpeed=100, serwer w tej samej chwili czyta 16 — właściwości Humanoida ustawione lokalnie NIE replikują się na serwer, więc stary cap nie wykrywał niczego. Co 2s próbka pozycji; prędkość > `SprintSpeed + SpeedTolerance` (8) przez `Strikes` (3) próbki z rzędu → `TakeDamage(MaxHealth)`. Serwerowe impulsy dają okno bezkarności: `AntiCheatService.grantGrace(player)` woła BombService (knockback) i PushService — bez tego własna bomba robiła z gracza "cheatera". `CharacterAdded` i każda zmiana stanu gry kasują próbki (teleport serwera to nie ruch gracza).
- `KillService` — **NOWY**. Tagowanie "kto ostatnio zaatakował humanoida" (attributes na Humanoid: KillAttackerId/KillWeapon/KillTagTime). `tag(hum, attacker, weapon)` + `processDeath(victim, hum)` → jeśli ofiara umiera w oknie `Rewards.KillCreditWindowSec` (5s) → `CashService.add(attacker, Rewards.Kill=25)` + `Remotes.PlayerKilled` (killfeed).
- `RewardsService` — **NOWY**. Survival bonus: WSZYSCY alive po Endgame dostają `Rewards.Win` (100$) + `data.wins += 1`. Fires `Remotes.RoundWon(winners, reward)` (banner). Listenuje `GameLoopService.RoundEnded`.
- `LeaderstatsService` — **NOWY**. Tab-leaderboard: `leaderstats/Cash` + `leaderstats/Wins` (IntValue). Read-only mirror PlayerDataService przez `subscribe` (loaded/loaded_default/updated). Tworzone dopiero po load (nie migają 0).
- `DevService` — **NOWY (2026-08-12, tryb testowy)**. Serwerowa strona `Config.Dev`: jedyne miejsce zamieniające `Remotes.DevCommand` ("skip" | "endRound") w akcję, każde wywołanie przez `Dev.isDev(player)` + cooldown 0.35s (server authority obowiązuje też w trybie testowym — ten sam kod pojedzie na produkcję). Gdy `Config.Dev.Enabled=false` NIE podpina nawet listenera. Głośny warn co boot. Nieskończone itemy NIE tutaj — są w `ItemService` (single source of truth ekwipunku).
- `DailyRewardsService` — **NOWY**. Daily login streak. Dzień = kalendarzowy UTC (`floor(os.time()/86400)`), CAŁA logika czasu server-side. Claim raz/dzień, pominięty dzień → reset streak do 1, dzień 8+ → ostatnia nagroda (500$) w kółko. `Remotes.ClaimDaily` / `DailyRewardsInfo`. Rewards `{50,75,100,150,200,300,500}`.

### Client controllers (`src/client/Controllers/`) — 20 controllers (+ helper ButtonFX)
- `UIController` — HUD update przez Heartbeat. Listenery PRZED `WaitForChild`. `FindFirstChild(name, true)` rekurencyjnie. TimerLabel w ROUND = czas **całej rundy** (1 licznik).
- `ShopController` — toggle menu, render oferty z `ItemDefinitions.shopOrder`, BuyItem fire. Hover FX kafelka przez `ButtonFX.applyTileHover` (obrót -4° + rozjaśnienie BG). CloseButton lookup rekursywny.
- `HotbarController` — mapuje pierwsze N item types z `shopOrder` które gracz ma → sloty 1-N. Click = equip/unequip (EquipItem). Klawisze 1-5. Equip FX: biały SelectStroke (animowany thickness) + pop slotu (UIScale 1.12→1 Back); hover = rozjaśnienie tła slotu.
- `ButtonFX` — **moduł-helper (2026-07-05, nie kontroler)**: `applyTileHover(tile)` — wspólny hover dla kafelków HUD (Shop/Daily/przyszłe). Rotation nie rusza UIListLayout.
- `ToolController` — Character.ChildAdded → BombTool → Tool.Activated → `ThrowBomb(direction)` z mouse.Hit.
- `PushController` — (1) F key → `Remotes.Push:FireServer()` z soft-cooldown 4s; (2) `Remotes.Pushed.OnClientEvent` → `HRP.AssemblyLinearVelocity` na siebie (klient owns physics) + screen shake (Config.Push.HitShake*).
- `CashController` — **NOWY**. Klient-side animacja cash: (1) idle hover+spin (deterministyczny seed z pozycji → wszyscy widzą to samo), (2) pickup po łuku Beziera na `Remotes.CashCollected` (P0=cash pos, P2=HRP, P1=midpoint+lift, EaseOut Back).
- `CashPopupController` — **NOWY**. Floating "+10$"/"-50$" nad CashLabel na `Remotes.CashChanged` z delta≠0. Stack max `Config.Cash.Popup.MaxSlots` (4), najstarszy wycieka. Kontrakt: `StarterGui.HUD.CashPopupTemplate` (TextLabel, Visible=false).
- `BridgeController` — **NOWY**. Build mode dla bridge_builder: ghost preview za myszą (raycast z kamery), R obraca 45°, LMB → `BuildBridge`. Aktywowany przez server (`BridgeBuildMode(true)`). Kursor = anchor = bliższa krawędź mostu.
- `MovementController` — **NOWY**. Centralny controller ruchu (5 etapów): WalkSpeed 12 + 3rd person camera zoom, sprint LeftShift + stamina, dynamic FOV (sprint +8°), smooth camera (elastic rotation + landing dip + `screenShake(intensity,duration)` API), head rotation (neck+waist za kamerą, replikacja 10Hz przez HeadTrackingService). **Stamina jako TEKST od 2026-08-12** (decyzja Kacpra — pasek usunięty): kontrakt `HUD.StaminaLabel` (TextLabel), kod ustawia tylko `.Text = "STAMINA: N"` (0-100, zapis wyłącznie przy zmianie wartości). Stary `StaminaBar`/`StaminaBarBG` jest CHOWANY (`Visible=false`, nie Destroy — element Kacpra wraca jednym kliknięciem); gdy brak `StaminaLabel`, kod tworzy go sam (wzorzec jak WinBannerController — default w kodzie, migrowalny do template'a). **Dwie pułapki naprawione po teście "nie widzę napisu"**: (1) label MUSI iść pod `hud`, nie pod kontener paska — u Kacpra pasek siedzi w `StaminaBarBG`, a ukryty rodzic chowa całe poddrzewo; (2) geometrię bierzemy z NAJWYŻSZEGO elementu paska (bezpośredniego dziecka HUD, walk-up przez `Parent`), bo wewnętrzny `StaminaBar` ma współrzędne względem rodzica (0.5/0.5) i nie mówi nic o miejscu na ekranie. Plus `UITextSizeConstraint` MaxTextSize 42 — bez capa `TextScaled` rozdmuchuje tekst do wysokości kontenera (108 px). Wszystko z `Config.Movement`. Odbiera `Remotes.BombHit` (shake + FOV punch). Lokalny kurz przy twardym lądowaniu (próg = MinFallHeightForDip).
- `CooldownBarController` — **NOWY**. Paski cooldownów per ID (push 4s + bomba 0.5s = dwa niezależne). `trigger(id, duration)`. Kontrakt: `StarterGui.HUD.CooldownBars` (Frame + UIListLayout + `CooldownBarTemplate` z `Fill` child).
- `WinBannerController` — **NOWY**. Banner "NICKNAME WON $100" po rundzie. `Remotes.RoundWon`. Tworzony dynamicznie w kodzie (default styling, migrowalny do template'a).
- `KillFeedController` — **NOWY**. Killfeed prawy górny róg. `Remotes.PlayerKilled` → wpis "killer killed victim" na kilka sekund.
- `HudVisibilityController` — **NOWY**. Chowa Shop + Daily Rewards przyciski gdy gracz AKTYWNIE GRA (state=ROUND i alive). `Remotes.AliveChanged`. Przy hide force-zamyka ShopMenu.
- `DailyRewardsController` — **NOWY**. Menu daily rewards: toggle z DailyRewardsButton, render 7 dni z template, CLAIM → `Remotes.ClaimDaily`. Countdown lokalny, stan z `DailyRewardsInfo`. Kontrakt: `StarterGui.HUD.DailyRewardsMenu` (CloseButton, StatusLabel, Days/DayTemplate).
- `LavaHeatController` — **NOWY (2026-07-05)**. "Żar" bliskości lawy: ColorCorrection tint+kontrast narasta im niżej nad lawą (Config.Lava.HeatEffect, Distance 22). Neutralny przy 0 — nie rusza designu lightingu Kacpra. Target 10Hz, lerp per-frame.
- `CashDigitsController` — **WYŁĄCZONY (2026-08-11: `Config.Cash.DigitDisplay.Enabled = false`)**. Wygenerowany sprite wyglądał źle, więc licznik kasy wrócił do zwykłego `HUD.CoinLabel` (TextLabel, FredokaOne + UIGradient + UIStroke, styl Kacpra) aktualizowanego przez `UIController`. Kontroler i sprite zostają jako martwy kod — jedna flaga przywraca cyfry-obrazki, gdyby powstał lepszy sprite. Opis mechanizmu: licznik kasy jako OBRAZKI cyfr (sprite strip 0-9+$, `Config.Cash.DigitDisplay.AssetId` = rbxassetid://74720156873015) — Roblox nie umie teksturować glifów fontu, a design wymaga studs W literach. Sprite generowany skryptem `gen_cash_digits.ps1` (GDI+: zielony gradient + siatka studs + kontur), wgrany przez MCP upload_image. Stan z leaderstats.Cash (IntValue — nie do przegapienia; CashChanged jako fast-path). CoinLabel ukryty (Visible=false), zostaje jako nośnik dla UIController. Kontener `HUD.CashDigits` — Kacper może postawić własny (pozycja z Studio).
- `ExplosionFXController` — **NOWY (2026-08-11, system v2; etap 1+4+5)**. CAŁE wizualia wybuchu lokalnie na `Remotes.BlastFX`: kula ognia, fala uderzeniowa, błysk PointLight, dym/iskry/embery, pył przy ziemi (raycast w dół), ambientowy screen shake skalowany odległością kamery (`MovementController.screenShake`). Daleki wybuch (>250 stud) = tylko światło+fala. **Etap 5**: ślad opalenia (`spawnScorch` — cienki cylinder na podłożu, FIFO cap 24, fade po 25s) + wspólny odtwarzacz 3D `playSoundAt` (rolloff InverseTapered); brzęk szkła gra RAZ na wybuch przy najbliższej tafli, nie raz na taflę. **Etap 4**: obsługa `Remotes.StructureFX` — `creak` (pył ze stropów, dźwięk, mikro-shake) i `collapse` (gęsty pył, rumble, mocny shake skalowany wielkością sekcji).
- `DebrisFXController` — **NOWY (2026-08-11, system v2)**. Kosmetyczne odłamki gruzu — LOKALNE party klienta (zero replikacji, zero fizyki serwera): ~150/wybuch (skalowane jakością grafiki), ten sam seed u wszystkich = identyczny wzór, kolory/materiały PRÓBKOWANE z geometrii wokół epicentrum, shrink+fade po ~5s, FIFO cap 500. Niska density — odłamek nie spycha własnego charactera. **Szkło (etap 2)**: odłamki szyb z payloadu `glassPanes` — 3-6 cienkich szklanych kawałków per tafla (skaluje z powierzchnią), wylatują normalną tafli OD wybuchu, fade po ~2.5s.
- `DevController` — **NOWY (2026-08-12, tryb testowy)**. Klawisze dev: `Config.Dev.SkipKey` (P) → skip fazy/stanu, `Config.Dev.EndRoundKey` (O) → koniec rundy. Fires `Remotes.DevCommand`. Listener podpinany TYLKO gdy `Dev.isDev(localPlayer)` — i tak nie daje uprawnień (server waliduje), chodzi o brak zbędnego ruchu sieciowego. Respektuje `gameProcessed` (pisanie "p" na czacie nie skipuje fazy).
- `HudScaleController` — **NOWY (2026-07-05)**. Skalowanie HUD: każdy top-level element HUD dostaje UIScale "HudScale" = viewportY / `Config.UI.ReferenceHeight` (1440). **Model projektowania UI**: Kacper projektuje W PIKSELACH przy 2560×1440 (jego monitor = skala 1.0); pozycje = AnchorPoint do krawędzi/rogu + px margines w Position (marginesy celowo NIE skalowane — element trzyma się krawędzi na każdym aspect ratio); rozmiary top-level w px; wnętrza scale-of-parent lub px (UIScale mnoży całe poddrzewo z tekstem). Zastąpił wcześniejsze podejście "czyste Scale" (dryfowało między aspect ratio, teksty capowane).

### Shared modules (`src/shared/Modules/`)
- `Config` — WSZYSTKIE liczby. Sekcje: **Dev** (⚠️ tryb testowy — `Enabled`, `Usernames`, `AllowInStudio`, `InfiniteItems`, klawisze), Game, Lava, UI, Spawn, **Cash** (pickup magnet, hover, popup, DigitDisplay), **Bridge**, **Movement** (walk/sprint, stamina, camera, HeadTrack), **Push** (MaxRange 7, ConeDot 0.3, Force 80, Lift 20), **RateLimits** (BombThrow 0.5, Push 4, BridgeBuild 0.5, EquipItem 0.15, DailyClaim 1), **DailyRewards**, **AntiCheat** (pomiar drogi, tolerancja, strikes, grace), **Rewards** (Win 100, Kill 25), **Destruction** (system v2: Categories HP — Wall 100/Glass 1/Pillar 140/Bridge 40 + PillarTag, DamageFeedback — darken/pył, Occlusion — PerWallFactor/MinEffect, Support — pass podparcia remnantów, **Collapse** (pasma filarów, progi creak/kolaps, capy), **Impact** (fall-fracture, crush damage), Fracture — target/min chunk/sufity, Shockwave — kąty/skalowanie rozmiarem, Debris — materiał/izolacja/usypianie/budżety, FX — client frags/szkło/scorch/shake + **5 slotów audio** (Explosion/Glass/Impact/Creak/Collapse, puste do czasu assetów Kacpra — wpisanie id wystarczy), Debug). `table.freeze` na wszystkim. Puste `Config.Round`/`Config.CooldownBar` usunięte (2026-08-11) — nic ich nie czytało.
- `ItemDefinitions` — `bomb` (price 50, fuse 2.5, blastRadius 22, damagePercent 0.5, knockbackForce 450, `destruction` = {radius 24, damage 160, impulse 95, minImpulseT 0.1, glassRadius 60} dla DestructionService) + `bridge_builder` (price 100, length 10, width 2, maxBuildDistance 20). `shopOrder = {"bomb", "bridge_builder"}`.
- `Destructible` — **NOWY (2026-08-12)**. Single source of truth CO wybuch może ruszyć: `buildContext()`, `isProtected(part, ctx)` (Locked / `Map.Locked` / `ActiveCash`), `isDestructible(part, ctx)` (`Map` / `ActiveBridges`), `canSpawnFXFrom(part, ctx)` (skrót dla klienta: + odsiewa Terrain i postacie). **Shared, bo odpowiedź musi być identyczna po obu stronach** — serwer decyduje co niszczy, klient z czego wolno rysować pył/odłamki. Powstał po feedbacku Kacpra: klient nie znał reguły i sypał pyłem oraz próbkował kolory z `Locked` partów, więc nietykalny Baseplate wyglądał, jakby się rozpadał. DestructionService korzysta z tego modułu (własne kopie usunięte).
- `Fracture` — **NOWY (2026-08-11, przepisany 2026-08-12)**. Czysta matematyka cięcia boxa na nierówne kawałki (deterministyczna z Random, zero Instance). `slice(size, target, min, maxChunks, rng, focus?)` — focus (kula DZIURY w local space): kawałki poza nią zostają DUŻE (anchored remnants). **Strategia priorytetowa**: w każdej iteracji tniemy NAJWIĘKSZY box wymagający cięcia, zamiast przechodzić stackiem LIFO. **Oś cięcia losowana z wagą ∝ długość²** (2026-08-12) — zawsze-najdłuższa oś dawała regularną kratę i identyczny wzór pęknięć co wybuch; waga kwadratowa sprawia, że długa oś zwykle wygrywa (kawałki nie robią się igłami), ale czasem tnie w poprzek. To jest różnica między dziurą a zniknięciem ściany — budżet ląduje tam, gdzie trafiła bomba, a kawałki w dziurze wychodzą RÓWNE. Poprzednio przy wyczerpanym budżecie zostawały 31-studowe płyty przy epicentrum (test Kacpra: "wysadzam ścianę i nie ma ściany"). Koszt O(maxChunks²) ≈ 2300 tanich operacji/part. `boxSurfaceDistance` = dystans do powierzchni boxa (współdzielony z DestructionService).
- `Dev` — **NOWY (2026-08-12)**. Single source of truth uprawnień dev: `isDev(player)` (Config.Dev.Usernames case-insensitive + każdy w Studio gdy `AllowInStudio`), `hasInfiniteItems(player)`, `isEnabled()`. Shared, bo pytają obie strony; klientowa kopia sprawdzenia to TYLKO oszczędność ruchu sieciowego — serwer waliduje niezależnie.
- `Remotes` — runtime folder w `ReplicatedStorage.Shared.Remotes`. Pełna lista (27, w tym **BlastFX**, **StructureFX**, **DevCommand**): GameStateChanged, PhaseChanged, PlayerDied, RoundEnded, **CashChanged**, **CashCollected**, InventoryChanged, BuyItem, ShopResult, EquipItem, UnequipItem, ThrowBomb, Push, Pushed, **BuildBridge**, **BridgeBuildMode**, **BridgeResult**, **HeadAim**, **RoundWon**, **PlayerKilled**, **AliveChanged**, **BombHit**, **BlastFX**, **ClaimDaily**, **DailyRewardsInfo**, **StructureFX**, **DevCommand**. (**Uwaga:** stare nazwy `CoinsChanged`/`UseItem`/`UseItemResult` już NIE istnieją.)
- `Utils` — `formatTime`, `getRoot`. Reszta helperów (`getHumanoid`, `getRingPositions`, `eachPlayer`) usunięta 2026-08-11 jako martwy kod; `getRoot` zastąpił trzy identyczne kopie lokalnego `getHRP` w Bomb/Push/Bridge.

### Co jest GOTOWE
- ✅ Day 1: GameLoop + Lava + HUD + lobby/round flow. Lava CanCollide=false.
- ✅ Day 3: DataStore (cash/inventory/wins/daily persist) + **Leaderstats** (Cash + Wins w Tab).
- ✅ Day 4: sklep + Hotbar + **bomba** (throw, VFX lontu, damage falloff, knockback, ragdoll toolbox ARTFVL, auto-re-equip — **bez wybuchu**, patrz ⚠️ wyżej) + **most** (bridge_builder, ghost preview).
- ✅ **Map restore** — MapService snapshot+restore po każdej rundzie.
- ✅ **PvP push** — F key, server-side target, velocity przez Pushed.
- ✅ **Cash pickupy** — cash na mapie, magnet pickup, pickup arc animacja.
- ✅ **Kill/Win rewards** — KillService (kill 25$ z tagowaniem) + RewardsService (survival 100$) + killfeed + win banner.
- ✅ **Movement system** — sprint+stamina, 3rd person, dynamic FOV, smooth camera, head tracking, landing dip, screen shake.
- ✅ **Anti-cheat** — detekcja po realnie przebytej drodze (WalkSpeed cap był atrapą, patrz AntiCheatService).
- ✅ **Daily rewards** — streak login UTC, menu, claim.
- ✅ **CooldownBar UI** + **HudVisibility** (chowa sklep w rundzie).
- ✅ **Audyt serwera** (2026-08-11) — naprawione: session lock przy loadzie (utrata postępu przy server hopie), `ItemService` meldujący fałszywy sukces, pominięcie `RoundEnded` przy błędzie rundy, dwa listenery `Touched` na lawie, bandwidth head-trackingu, spawn rundy bez izolacji błędu, jitter auto-save, `Locked` na mostach, kłamliwy log "saved".

### Co JESZCZE TODO
- ⏳ **SYSTEM DESTRUKCJI v2 — WSZYSTKIE 5 ETAPÓW ZAIMPLEMENTOWANE** (`DESTRUCTION_PLAN.md`), etapy 2-5 **CZEKAJĄ NA TEST W PLAY**. ① rdzeń (przetestowany OK) → ② kategorie + occlusion + pass podparcia v2 (kolumna, kierunkowy — fix na "wysadziłem dół i reszta wisi") → ③ fall-fracture + crush damage → ④ kolaps sekcji po filarach + creak → ⑤ scorch + 5 slotów audio + throttle dźwięków. **Zostaje: assety dźwiękowe Kacpra** (5 pól w `Config.Destruction.FX`, wpięcie gotowe) **i balans po testach pod obciążeniem**. Kontrakt mapy: panele zamiast kafli 6×6, tag `Pillar` na filary, szyby Material Glass, budynek = folder, wiszące platformy → `Locked`/`Map.Locked`.
- ❌ **PRZED LAUNCHEM — trzy ustawienia testowe do cofnięcia** (wszystkie warnują głośno co boot):
  - `Config.Lava.Phases` = **10 minut** (10/150/150/150/140) zamiast projektowych 80s (5/20/20/20/15) — wydłużone 2026-08-12 na testy destrukcji. `GameLoopService.warnIfRoundTooLong` krzyczy, dopóki runda > 180s. Przy powrocie do lawy pamiętać: przy tych czasach lawa urosłaby o ~990 stud i po ~3 min siedziałaby na `MaxY` do końca rundy.
  - `Config.Lava.Enabled = true` (wyłączona 2026-08-12 na testy destrukcji — nie rośnie, nie zabija). Bez tego gra nie ma lawy.
  - `Config.Dev.Enabled = false` (tryb testowy 2026-08-12: nieskończone itemy dla `Usernames`/Studio, klawisze P=skip fazy, O=koniec rundy). Zostawienie `true` = darmowe bomby dla wpisanych nicków na produkcji.
- ❌ Day 2: mapa Downtown (Kacper buduje w Studio) — 8-12 wieżowców z dziurami, `Workspace.SpawnPoints` z multi-spawn, `Workspace.Map.Locked.CashSpawns` markery.
- ❌ Studio assety pod nowy kod: `ReplicatedStorage.Cash` (model cash), `StarterGui.HUD.CashPopupTemplate`, `StarterGui.HUD.CooldownBars` (+ template + Fill), `StarterGui.HUD.DailyRewardsMenu` (+ DayTemplate), DailyRewardsButton — kod ma fallback/default gdy brak, ale styling Kacpra dopiero po postawieniu.
- ❌ Day 4 dokończyć: pozostałe itemy (hook, sabotage, shield) — system generic, dodaj do ItemDefinitions + handler jak Bomb/Bridge.
- ❌ Day 5: ShopService VIP gamepass, dev products (Robux purchases).
- ❌ Day 6 dokończyć: eventy (spadające kule, wiatr), więcej polish, particle/sound.
- ❌ Day 7: closed beta, test, launch, TikToki.
- ❌ **Skala kilkuset active** — audyt kodu zrobiony (2026-08-11), zostaje test POD OBCIĄŻENIEM: BindToClose z 20 graczami, realne zużycie budżetu DataStore. Koszt fizyki wybuchów wypada z listy do czasu, aż powstanie nowy system — wtedy wraca jako pierwsza rzecz do zmierzenia.

### Bieżąca konfiguracja (kluczowe liczby — reszta w `Config.luau`)
- Lobby 15s, runda **projektowo** 80s (5+20+20+20+15) — ⚠️ obecnie 600s na testy, patrz TODO.
- Bomb: fuse 2.5s, blastRadius 22, damage 50% liniowo do 0, knockbackForce 450 (min 0.35×), ragdollDuration 2s. Drop: bounciness 0.05 + rollDamping 0.90/klatkę przy ziemi (kula nie odjeżdża po rzucie; NIE freeze). **Destrukcja v2 — stan po cyklu nerf→buff→przywrócenie (2026-08-12)**: radius 24, damage strukturalny **160**, impulse 95, dziura z modelu obrażeń w zakresie `MinHoleRadius` 3.5 … promień wybuchu. Wall HP 100 → niszczy do ~9 stud, dziura r=9. Realnie: ściana 36×14 → odpada 22 kawałki (zostaje 26); ściana 80×30 → odpada 11 (zostaje 37); filar → odpada 4 (zostaje 10). Filar HP **140** = jedna bomba z bliska. **Lekcja z tego cyklu**: nerf przez sufit wyrwy (`MaxHoleRadius` 4) zamienił wybuchy w odpryski i został odrzucony — zasięg (`damage`) i wielkość wyrwy są sprzężone przez model obrażeń i nie należy ich rozdzielać sufitem. Budżety: 32 kawałki/part, 110/wybuch, 450 gruzu w ruchu globalnie (min 40/wybuch), klient +150 lokalnych odłamków.
- Bridge: length 10, maxBuildDistance 20, price 100.
- Movement: WalkSpeed 12, SprintSpeed 20, stamina max 5s, FOV 70→78.
- RateLimits: BombThrow 0.5s, Push 4s, BridgeBuild 0.5s, EquipItem 0.15s.
- Rewards: Win 100$, Kill 25$ (okno 5s). Cash pickup 10$/paczka. Daily 50→500$.
- AntiCheat: pomiar przebytej drogi co 2s, limit = SprintSpeed + 8, kara po 3 próbkach z rzędu, okno bezkarności 4s po serwerowym impulsie.
