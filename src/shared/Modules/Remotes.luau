--!strict
-- Remotes.luau
-- Single source of truth dla wszystkich RemoteEventów.
-- Serwer tworzy je przy pierwszym require, klient czeka aż się pojawią.
--
-- Użycie:
--   local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
--   Remotes.GameStateChanged:FireAllClients(...)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"GameStateChanged",   -- (stateName: string, remainingSeconds: number, endsAtServerTime: number)
	                      -- LOBBY/PREPARING/COUNTDOWN/ROUND/FINISHING/RESETTING (od 26.10 bez POST_ROUND)
	"PlayerDied",         -- (player: Player, reason: string)
	"RoundEnded",         -- bez payloadu: cleanup po RESETTING, tuż przed LOBBY; wyniki idą przez RoundWon
	"ClientReady",        -- klient→server: FireServer() bez payloadu — klient podpiął listenery
	                      --   (paczka 3, 18.10). Serwer odsyła stan startowy: stan gry, kasę,
	                      --   inventory, loadout i ustawienia. Liczy się tylko pierwszy na sesję gracza
	"CashChanged",        -- FireClient: (balance: number, delta: number?, reason: string?)
	"CashCollected",      -- FireAllClients: (player: Player, fromPosition: Vector3) — klient animuje pickup
	"ItemPickedUp",       -- FireAllClients: (player: Player, itemId: string, fromPosition: Vector3) — 13.11,
	                      --   item z mapy podniesiony (E): wszyscy widzą lot do gracza, podnoszący
	                      --   dostaje komunikat „+1 X” (ItemPickupController). Item już jest w inventory.
	"RoundEvent",         -- FireAllClients: (kind: "SupplyDrop"|"Airstrike"|"Train"|"LowGravity", at: number) —
	                      --   24.11, wydarzenie w rundzie (RoundEventService): napis, odliczanie i syrena.
	                      --   `at` = czas serwera lądowania skrzyni / pierwszego uderzenia / wyjazdu pociągu /
	                      --   KOŃCA niskiej grawitacji. Celu nalotu NIE ma w payloadzie
	"TrainRun",           -- FireAllClients: (reverse: boolean, departAt: number) — 24.11, przejazd pociągu
	                      --   (false = West → East). Pozycję liczą z tego obie strony (TrainPath); trafienia serwer
	"AirstrikeRockets",   -- FireAllClients: (rockets: {{id: number, origin: Vector3, dir: Vector3, at: number}}) —
	                      --   24.11, cała salwa naraz; `at` = czas serwera startu. Klienci rysują rakiety po
	                      --   tej prostej (Config.Airstrike.Speed); lot i trafienie liczy serwer
	"AirstrikeRocketEnded", -- FireAllClients: (id: number) — rakieta trafiła; wybuch idzie przez BlastFX
	"InventoryChanged",   -- FireClient: (inventory: {[itemId: string] = count: number})
	"SetLoadout",         -- klient→server: FireServer(loadout: {string}) — 3 itemId, "" = pusty slot.
	                      --   Tylko w LOBBY; serwer czyści (istniejące, bez powtórzeń) — LoadoutService
	"LoadoutChanged",     -- FireClient: (loadout: {string}) — 3 itemId, "" = pusty (18.10)
	"SetSkipRound",       -- klient→server: FireServer(skip: boolean) — pomijanie rund (06.11).
	                      --   Odpowiedź przez atrybuty gracza (Config.RoundSkip) — RoundSkipService
	"SetSettings",        -- klient→server: FireServer(settings: {[key: string]: any}) — cały stan
	                      --   ustawień (26.10). Serwer zostawia tylko klucze i wartości z
	                      --   Config.Settings.Options, resztę ustawia domyślnie — SettingsService
	"SettingsChanged",    -- FireClient: (settings: {[key: string]: any}) — stan po wczytaniu,
	                      --   po ClientReady i po każdej prośbie SetSettings (także odrzuconej)
	"BuyItem",            -- klient→server: FireServer(itemId: string) — zakup w sklepie-NPC
	"ShopResult",         -- FireClient: (success: boolean, itemId: string, reason: string?)
	"BuyCosmetic",        -- client→server: (cosmeticId: string), LOBBY + proximity to ClothesShop NPC
	"SetCosmetic",        -- client→server: (category: string, cosmeticId: string), "" = unequip; LOBBY only
	"CosmeticsChanged",   -- FireClient: ({owned: {[id]: true}, equipped: {[category]: id}}), after load/ClientReady/change
	"CosmeticResult",     -- FireClient: (success: boolean, action: "buy"|"equip", id: string, reason: string?)
	"UnlockSkill",        -- klient→server: FireServer(nodeId: string) — zakup pola drzewka u maga
	                      --   (09.11, SkillService). Walidacja: pole, odnoga odblokowana, pole
	                      --   poprzednie, wymaganie, kasa, odległość do maga
	"Rebirth",            -- klient→server: FireServer() bez payloadu — rebirth u maga; tylko gdy
	                      --   kupione jest wszystko, co odblokowane. Zabiera samo drzewko
	"SkillResult",        -- FireClient: (success: boolean, action: "unlock"|"rebirth", id: string, reason: string?)
	                      --   `id` = pole przy "unlock", "" przy "rebirth". Zawsze PO SkillsChanged
	"SkillsChanged",      -- FireClient: (owned: {string}, rebirths: number,
	                      --     stats: { cycle: {kills, survived, played}, total: {kills, survived, played} })
	                      --   po wczytaniu, ClientReady, zakupie, rebirthie i zmianie statystyk.
	                      --   `cycle` = od ostatniego rebirthu (wymagania pól), `total` = od początku gry
	"EquipItem",          -- klient→server: FireServer(itemId: string) — dispatch po itemId,
	                      --   każdy service equipowalnego itemu słucha i reaguje na SWÓJ id
	                      --   (bomb→BombService, bridge_builder→BridgeService), reszta chowa swoje
	"UnequipItem",        -- klient→server: FireServer()
	"ThrowBomb",          -- klient→server: FireServer(direction: Vector3) — gdy ma BombTool equipped
	"Push",               -- klient→server: FireServer() — F key, server po Config.Push.Windup wybiera cel w stożku przed graczem
	"Pushed",             -- server→target client: FireClient(target, velocity: Vector3) — target aplikuje na swoim HRP
	"BuildBridge",        -- klient→server: FireServer(position: Vector3, rotationY: number)
	                      --   wymaga aktywnego trybu budowania serwera i mostu w loadoucie
	"BridgeBuildMode",    -- server→klient: FireClient(active: boolean) — enter/exit build mode
	"BridgeResult",       -- FireClient: (success: boolean, reason: string?) — feedback build
	"HeadAim",            -- klient→server: FireServer(yaw: number, pitch: number) — radianach, throttled ~10Hz
	                      -- server→klient: FireClient(sourcePlayer: Player, yaw: number, pitch: number) — broadcast do innych
	"RoundWon",           -- (winners: {Player}, reward: number) — „YOU SURVIVED! +X$” (WinMessageController).
	                      --   09.11: FireClient do KAŻDEGO ocalałego z JEGO kwotą po mnożniku drzewka
	                      --   (`winners` = on sam); bez ocalałych FireAllClients({}, 0)
	"PlayerKilled",       -- FireClient(zabójca): (killer: Player, victim: Player, weapon: string, reward: number) — komunikat „YOU KILLED”
	"AliveChanged",       -- FireClient: (isAlive: boolean) — server-side aliveSet zmiana (round spawn=true, death=false)
	                      --   `true` idzie PO teleporcie na mapę (07.10) — RoundTransitionController
	                      --   zdejmuje na nim ciemne przejście
	"BombHit",            -- FireClient: (intensity: number 0..1) — trafiony wybuchem: screen shake + FOV punch
	"FallImpact",         -- FireAllClients: (player: Player, damage: number 0..1, ground: Vector3) — 12.11,
	                      --   upadek, który zranił: kurz/odłamki w `ground` u wszystkich w pobliżu,
	                      --   czerwone krawędzie ekranu u `player` (FallImpactController)
	"BlastFX",            -- FireAllClients: (blast: {
	                      --     center: Vector3, radius: number, impulse: number, minT: number,
	                      --     seed: number,
	                      --     glass: {{cf: CFrame, size: Vector3, color: Color3}},
	                      --     cuts: {{cf: CFrame, size: Vector3, lc: Vector3, seed: number,
	                      --             hole: number, color: Color3, mat: Enum.Material,
	                      --             var: string, tr: number}},
	                      --     quiet: boolean? })
	                      --   `quiet` (09.11, FORCE z drzewka): dziura bez wybuchu — sam pył i gruz,
	                      --   bez ognia, fali, huku i wstrząsu.
	                      --   Klienci renderują CAŁE VFX wybuchu lokalnie (ExplosionFXController)
	                      --   + odłamki z seed, odłamki szyb i KAWAŁKI DZIUR (DebrisFXController).
	                      --   `cuts` (v3, 2026-09-23): party pocięte przez wybuch — klient liczy
	                      --   z `Fracture.planHole(size, lc, hole, seed)` te same kawałki dziury,
	                      --   których serwer nie postawił, i animuje je u siebie. Dane parta są
	                      --   w payloadzie, nie jako referencja: przy StreamingEnabled klient
	                      --   może go nie mieć, a serwer i tak zaraz go przytnie.
	"GlassFX",            -- FireAllClients: (fx: { from: Vector3, seed: number,
	                      --     glass: {{cf: CFrame, size: Vector3, color: Color3}} })
	                      --   09.11: szyba stłuczona BEZ wybuchu (push: F w szybę albo pchnięty gracz
	                      --   lecący w okno — DestructionService.shatterGlass). Klienci: odłamki od
	                      --   `from` (DebrisFXController) i brzęk (ExplosionFXController) — bez ognia i fali.
	"DebrisFall",         -- FireAllClients: (fall: { center: Vector3, radius: number,
	                      --     impulse: number, nLaunch: number, launch: {Instance},
	                      --     nDrop: number, drop: {Instance},
	                      --     nShatter: number, shatter: {Instance},
	                      --     vapor: { {cf: CFrame, size: Vector3} } })
	                      --   `shatter` (26.09): meble rozpadające się od razu, kawałki żyją
	                      --   `Props.ShatterLife`; `vapor` (26.09): rekwizyty, które zniknęły
	                      --   (wieszaki i drobne) — SAMO pudełko na obłok pyłu, serwer skasował
	                      --   instancję od razu, klient niczego nie kopiuje
	                      --   PRZEKAZANIE drobnicy (v3): meble i drobne party, które serwer
	                      --   skasuje za `Config.Destruction.Small.HandoffDelay`. Klient w tym
	                      --   czasie je KOPIUJE, chowa oryginał i animuje kopię (`launch` —
	                      --   odrzut od wybuchu, `drop` — upadek). Liczniki `nLaunch`/`nDrop`
	                      --   są osobno, bo referencja do parta, którego klient nie ma
	                      --   (StreamingEnabled), dojeżdża jako nil i robi dziurę w tablicy
	"StructureFX",        -- FireAllClients: (kind: "creak"|"collapse", position: Vector3, magnitude: number)
	"CarFire",            -- FireAllClients: (cf: CFrame, size: Vector3, duration: number) — płonący
	                      --   wrak auta po wybuchu (27.09). Czysty efekt u klienta: ogień nie rani
	                      --   i się nie rozprzestrzenia (pożary jako mechanika poza v1.0)
	                      --   kolaps grupy budynku v4 (CollapseService: "collapse" przy starcie
	                      --   lotu grupy; "creak" dziś nieużywany). Klient robi pył, dźwięk i wstrząs
	"DevCommand",         -- klient→server: FireServer(command: string) — "skip" | "endRound" |
	                      --   nazwa wydarzenia z Config.Dev.EventKeys (24.11).
	                      --   Server waliduje Dev.isDev(player); tryb dev = Config.Dev.Enabled
	"FireGrapple",        -- klient→server: FireServer(targetPos: Vector3) — punkt, w który
	                      --   gracz celuje z GrappleTool w ręce i hakiem w loadoucie;
	                      --   serwer bierze stąd WYŁĄCZNIE kierunek
	                      --   i strzela własnym raycastem z HRP; zaczep powstaje tam, gdzie
	                      --   trafi promień serwera, więc klient nie może skłamać o zasięgu
	"Grappled",           -- server→właściciel: FireClient(anchor: Vector3, goal: Vector3,
	                      --   maxTime: number) — DOKĄD lecieć i najdłużej jak długo. Lot prowadzi
	                      --   KLIENT, bo postać ma network ownership gracza i serwerowa siła na
	                      --   HRP zostałaby nadpisana (hard rule 12, jak Remotes.Pushed).
	                      --   `anchor` jest tu, bo strzelec rysuje SWOJĄ linę razem z lotem:
	                      --   wiązanie liny z lotem przez dwa różne remote'y byłoby wyścigiem
	                      --   (kolejność dostarczenia między remote'ami nie jest gwarantowana)
	"GrappleFX",          -- FireAllClients: (shooter: Player, anchor: Vector3, goal: Vector3,
	                      --   maxTime: number) — lina od ręki strzelca do punktu zaczepu przez
	                      --   cały lot. Czysta kosmetyka rysowana lokalnie; idzie do WSZYSTKICH,
	                      --   żeby inni widzieli, skąd kolegę ciągnie, a nie samo odlecenie.
	                      --   Strzelec IGNORUJE własny — swoją linę ma już z Remotes.Grappled
	"GrappleMiss",        -- FireAllClients: (shooter: Player, tip: Vector3) — pudło haka (02.11):
	                      --   lina wystrzeliwuje z ręki do `tip` (koniec zasięgu albo przeszkoda
	                      --   nie do złapania) i się zwija; postać stoi, sztuka nie schodzi.
	                      --   Tym razem także do strzelca — to jedyny odzew, że klik zadziałał
	"UseBandage",         -- client→server: FireServer() no payload. Held bandage, alive in ROUND.
	                      -- Server owns duration/heal; Player BandageStart/BandageEnd (server time)
	                      -- animate all clients. Clear on completion/cancel; consume only on success.
	"DrinkEnergy",        -- klient→server: FireServer() bez payloadu — łyk energy drinka trzymanego
	                      --   w ręce (20.10). Serwer odpowiada atrybutami gracza `EnergyStart` /
	                      --   `EnergyEnd` (czas serwera, Config.EnergyDrink), nie remote'em —
	                      --   widzą je wszyscy klienci, także ci, którzy dołączą w trakcie
	"FireRpg",            -- klient→server: FireServer(targetPos: Vector3) — punkt, w który celuje
	                      --   RPG (20.10). Serwer bierze stąd WYŁĄCZNIE kierunek; start lotu liczy
	                      --   sam z pozycji gracza, lot prowadzi własnymi promieniami
	"RocketFired",        -- FireAllClients: (id: number, shooter: Player, origin: Vector3,
	                      --   direction: Vector3, speed: number, firedAt: number, maxTime: number)
	                      --   — klienci rysują rakietę u siebie po tej prostej; `firedAt` to czas
	                      --   serwera, więc kopia nie spóźnia się o ping
	"RocketExploded",     -- FireAllClients: (id: number, position: Vector3?) — koniec lotu;
	                      --   `nil` = rakieta znikła bez wybuchu (koniec rundy). Sam wybuch
	                      --   (VFX, gruz) idzie zwykłą drogą bomby: Remotes.BlastFX
	"ThrowC4",            -- klient→server: FireServer(targetPos: Vector3) — punkt, w który celuje gracz
	                      --   z C4 w ręce (25.10). Serwer bierze stąd WYŁĄCZNIE kierunek rzutu; lot
	                      --   i miejsce przyklejenia liczy sam (promień co klatkę, Config.C4.Throw*)
	"DetonateC4",         -- klient→server: FireServer() bez payloadu — klawisz / przycisk detonatora.
	                      --   Odpowiedź: atrybut gracza Config.C4.CountAttribute (liczba ładunków)
	                      --   i zwykły wybuch bomby (Remotes.BlastFX)
}

local function getRemotesFolder(): Folder
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local folder = shared:FindFirstChild("Remotes")

	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = shared
		else
			folder = shared:WaitForChild("Remotes")
		end
	end

	return folder :: Folder
end

local function getOrCreateEvent(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if RunService:IsServer() then
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
		return event
	else
		return folder:WaitForChild(name, 10) :: RemoteEvent
	end
end

local Remotes = {}

local folder = getRemotesFolder()
for _, name in ipairs(REMOTE_NAMES) do
	Remotes[name] = getOrCreateEvent(folder, name)
end

return Remotes
