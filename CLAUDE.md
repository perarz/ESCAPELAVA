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

## STATUS PROJEKTU (Day 1+3+4 zrealizowane)

### Server services (`src/server/Services/`)
- `GameLoopService` — state machine: LOBBY 15s → COUNTDOWN 5s → ROUND (Spawn 5s + Easy 20s + Mid 20s + Hard 20s + Endgame 15s = 80s) → POST_ROUND 10s → loop. `replicateTo(player)` dla nowych graczy. `RoundEnded` BindableEvent fired po końcu rundy (MapService listenuje).
- `LavaService` — preferuje `Workspace.Lava.LavaPart`, animuje Y. Speeds ×2: 0/0.6/1.2/2.0/3.0. Touched zabija humanoidów. **CanCollide=false** — lawa nie pcha klocków w górę (bez tego rozjebane parts robiły windy żeby wygrać).
- `MapService` — snapshot Workspace.Map (poza `Locked`) przy bootcie → ServerStorage.MapSnapshot. Po RoundEnded: cleanup `BombProjectile` parts w Workspace (fuse closure aborts gdy parent=nil), wait RESTORE_DELAY=0.5s (żeby survivor'zy zdążyli wylądować w lobby), destroy aktualne destructibles, clone snapshot back. Bez tego mapa zostawała rozjebana następnej rundy.
- `PlayerService` — `CharacterAutoLoads=false`, lobby/round teleport, distance check dla survivor'ów (POST_ROUND nie rusza martwych w lobby). `isAlive(player)` API.
- `PlayerDataService` — DataStore wrapper. Combined state `{coins, inventory, _sessionId, _starterReceived}`. UpdateAsync, retry x3 exp backoff, session lock, BindToClose force-save, auto-save 60s. Studio loaded_default gdy API off.
- `CoinService` — kasa per player, używa PlayerDataService. `add/spend/get`. Starter pack +100$ jednorazowo + Studio bonus +1000$ per Play (RunService:IsStudio guard).
- `ItemService` — inventory schema `{ [itemId] = count }` (NOWY, unlimited stack). `give/consume/getCount/getInventory/use`. Dispatcher `use(player, itemId, direction)` woła handlery (registerUseHandler). Migration legacy slot-based.
- `ShopService` — server-authoritative buy. Bez rate limit (usunięty na request — atomic `ItemService.give` + `CoinService.spend` chronią przed exploitami). Alive check (sklep tylko poza ROUND lub spectator), atomic give→spend z undo. ShopResult feedback do klienta.
- `BombService` — Tool z Ball Handle, equip/unequip/throw flow. `equip(player, "bomb")` — sprawdza count > 0, tworzy Tool. Throw: consume z inventory, spawn fizyczny projektyl, fuse 2.5s ZAWSZE (Touched usunięty), Roblox Explosion VFX (BlastPressure=0, visual only) + smoke/sparks particles. Damage 50% MaxHealth z linear falloff (radius 22, min 0%) — w Studio także rzucający. Knockback `force=450 × max(0.35, 1-d/r)` z lift 0.6 vertical (toolbox ragdoll ustawia HRP.Velocity). Destrukcja środowiska radius=12, impulse=60 × t × mass — unanchor + ApplyImpulse. Protected: Baseplate, LavaPart, Locked parts, Folder children Lava/Lobby/SpawnPoints/ItemSpawns. **Auto-re-equip po throw** jeśli count>0 (UX jak grenat w FPS, eliminuje "klik 1 dwa razy żeby równać").
- `PushService` — F key PvP push. Cooldown 4s/gracz (zużywa się NAWET przy missie — anti-spam), MAX_RANGE 7 stud, stożek ~70° przed pusherem (CONE_DOT=0.3). Target wybierany SERVER-SIDE (anti-cheat). Velocity: `dir * 80 + Vector3.new(0, 20, 0)`. **Nie ustawia velocity bezpośrednio** — fires `Remotes.Pushed` do target client bo NetworkOwner=LocalPlayer nadpisuje server set (CLAUDE zasada 12).

### Client controllers (`src/client/Controllers/`)
- `UIController` — HUD update przez Heartbeat. Listenery PRZED `WaitForChild` (yieldy). `FindFirstChild(name, true)` rekurencyjnie szuka labelów (HUD może być przebudowany). TimerLabel w ROUND = czas pozostały **całej rundy** (1 licznik), nie aktualnej fazy.
- `ShopController` — toggle menu, render oferty z ItemDefinitions.shopOrder, BuyItem fire. Hover tween na ShopButton: AnchorPoint przesunięty na (0.5, 0.5) z kompensacją Position (`oldOffset + size * (0.5 - oldAnchor)`) żeby rotacja pivot'owała wokół centrum (przedtem text+icon "rozjeżdżały się" wokół top-left). CloseButton lookup rekursywny (`FindFirstChild("CloseButton", true)`) bo Kacper może go włożyć w header Frame; akceptuje GuiButton (Text/Image).
- `HotbarController` — mapuje pierwsze N item types z `ItemDefinitions.shopOrder` które gracz ma → sloty 1-N. Click slot = equip itemId (Remote EquipItem). Re-click = unequip. Klawisze 1-5 też select.
- `ToolController` — nasłuchuje na Character.ChildAdded → BombTool → Tool.Activated → fires ThrowBomb(direction) z mouse.Hit.
- `PushController` — dwie role: (1) F key → `Remotes.Push:FireServer()` z lokalnym soft-cooldown CLIENT_COOLDOWN=4s (match server, save RPC); (2) listener `Remotes.Pushed.OnClientEvent` → ustawia `HRP.AssemblyLinearVelocity` na siebie (klient owns physics — to jedyna droga).

### Shared modules (`src/shared/Modules/`)
- `Config` — game timings (LobbyDuration=15, lava phases), spawn fallbacks
- `ItemDefinitions` — bomb config (price 50, maxStack 9999, fuse 2.5, blastRadius 22, knockbackForce 450, knockbackMinT 0.35, destructionRadius 12, destructionImpulse 60). Plus `shopOrder = {"bomb"}` lista display.
- `Remotes` — runtime tworzy folder w ReplicatedStorage.Shared.Remotes. Lista: GameStateChanged, PhaseChanged, PlayerDied, RoundEnded, CoinsChanged, InventoryChanged, BuyItem, ShopResult, UseItem, UseItemResult, EquipItem, UnequipItem, ThrowBomb, Push (klient→server F press), Pushed (server→target client z velocity, klient sam aplikuje).
- `Utils` — formatTime, getRoot, getHumanoid, getRingPositions, eachPlayer.

### Co jest GOTOWE
- ✅ Day 1: GameLoop + Lava + HUD + lobby/round flow (rządzą countdownami, lawa rośnie, gracze respawn). Lava CanCollide=false (nie pcha klocków w górę).
- ✅ Day 3 (przyspieszone): DataStore + monety persistowane + leaderstats brak (TODO)
- ✅ Day 4 (przyspieszone): sklep (ShopMenu UI, hover tween wokół centrum, CloseButton w zagnieżdżonym Frame) + Hotbar UI + bomba (Tool throw, fuse, Explosion VFX, smoke/sparks, damage falloff, knockback z floor, destruction środowiska z protected parts, ragdoll przez toolbox ARTFVL, **auto-re-equip po throw**)
- ✅ **Map restore** — MapService snapshot+restore po każdej rundzie, cleanup `BombProjectile` przed restorem żeby fuse nie zepsuł świeżej mapy
- ✅ **PvP push** — F key, cooldown 4s, range 7, server-side target picking, velocity przez `Remotes.Pushed` do target client (network ownership workaround)

### Co JESZCZE TODO
- ❌ Day 2: mapa Downtown (Kacper buduje w Studio) — 8-12 wieżowców z dziurami, `Workspace.SpawnPoints` z multi-spawn
- ❌ Day 3 dokończyć: Leaderstats (Tab leaderboard), rate limiting na RemoteEventach gdzie pasuje (ThrowBomb, EquipItem, Push już ma — reszta przeglądnąć przy skali kilkuset)
- ❌ Day 4 dokończyć: pozostałe itemy (bridge_builder, hook, sabotage, shield) — system już generic, dodaj do ItemDefinitions + handlery jak BombService
- ❌ Day 5: ShopService VIP gamepass, dev products (Robux purchases)
- ❌ Day 6: eventy (spadające kule, wiatr), daily rewards, polish, particle/sound
- ❌ Day 7: closed beta, test, launch, TikToki
- ❌ **Skala kilkuset active** — audit DataStore quota (wiele writes/min), BindToClose performance test, edge cases under load, antycheat hardening

### Bieżąca konfiguracja (ostatnie tunings z tej sesji)
- Lobby: 15s
- Bomb fuse: 2.5s
- Bomb blastRadius: 22, damage 50% w epi liniowo do 0
- Bomb knockbackForce: 450 z `knockbackMinT=0.35` floor (mid-distance nadal pcha)
- Bomb destructionRadius: 12 (lokalna destrukcja, nie cały budynek), impulse 60
- Hotbar: tylko Slot1 (84×84), transparent backdrop (Frame BackgroundTransparency=1)
