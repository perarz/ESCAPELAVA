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
	"GameStateChanged",   -- (stateName: string, payload: table?)
	"PhaseChanged",       -- (phaseName: string, phaseIndex: number, duration: number)
	"PlayerDied",         -- (player: Player, reason: string)
	"RoundEnded",         -- (survivors: {Player}, payload: table?)
	"CashChanged",        -- FireClient: (balance: number, delta: number?, reason: string?)
	"CashCollected",      -- FireAllClients: (player: Player, fromPosition: Vector3) — klient animuje pickup
	"InventoryChanged",   -- FireClient: (inventory: {[itemId: string] = count: number})
	"BuyItem",            -- klient→server: FireServer(itemId: string) — zakup w sklepie-NPC
	"ShopResult",         -- FireClient: (success: boolean, itemId: string, reason: string?)
	"EquipItem",          -- klient→server: FireServer(itemId: string) — dispatch po itemId,
	                      --   każdy service equipowalnego itemu słucha i reaguje na SWÓJ id
	                      --   (bomb→BombService, bridge_builder→BridgeService), reszta chowa swoje
	"UnequipItem",        -- klient→server: FireServer()
	"ThrowBomb",          -- klient→server: FireServer(direction: Vector3) — gdy ma BombTool equipped
	"Push",               -- klient→server: FireServer() — F key, server pickuje cel w stożku przed graczem
	"Pushed",             -- server→target client: FireClient(target, velocity: Vector3) — target aplikuje na swoim HRP
	"BuildBridge",        -- klient→server: FireServer(position: Vector3, rotationY: number)
	"BridgeBuildMode",    -- server→klient: FireClient(active: boolean) — enter/exit build mode
	"BridgeResult",       -- FireClient: (success: boolean, reason: string?) — feedback build
	"HeadAim",            -- klient→server: FireServer(yaw: number, pitch: number) — radianach, throttled ~10Hz
	                      -- server→klient: FireClient(sourcePlayer: Player, yaw: number, pitch: number) — broadcast do innych
	"RoundWon",           -- FireAllClients: (winners: {Player}, rewardPerPlayer: number) — banner "NAME WON $X"
	"PlayerKilled",       -- FireAllClients: (killer: Player, victim: Player, weapon: string, reward: number) — killfeed
	"AliveChanged",       -- FireClient: (isAlive: boolean) — server-side aliveSet zmiana (round spawn=true, death=false)
	                      --   `true` idzie PO teleporcie na mapę (07.10) — RoundTransitionController
	                      --   zdejmuje na nim ciemne przejście
	"BombHit",            -- FireClient: (intensity: number 0..1) — trafiony wybuchem: screen shake + FOV punch
	"BlastFX",            -- FireAllClients: (blast: {
	                      --     center: Vector3, radius: number, impulse: number, minT: number,
	                      --     seed: number,
	                      --     glass: {{cf: CFrame, size: Vector3, color: Color3}},
	                      --     cuts: {{cf: CFrame, size: Vector3, lc: Vector3, seed: number,
	                      --             hole: number, color: Color3, mat: Enum.Material,
	                      --             var: string, tr: number}} })
	                      --   Klienci renderują CAŁE VFX wybuchu lokalnie (ExplosionFXController)
	                      --   + odłamki z seed, odłamki szyb i KAWAŁKI DZIUR (DebrisFXController).
	                      --   `cuts` (v3, 2026-09-23): party pocięte przez wybuch — klient liczy
	                      --   z `Fracture.planHole(size, lc, hole, seed)` te same kawałki dziury,
	                      --   których serwer nie postawił, i animuje je u siebie. Dane parta są
	                      --   w payloadzie, nie jako referencja: przy StreamingEnabled klient
	                      --   może go nie mieć, a serwer i tak zaraz go przytnie.
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
	"SetGraphicsMode",    -- klient→server: FireServer(mode: "Potato" | "Full") — wybór trybu
	                      --   grafiki w ustawieniach. Serwer tylko ZAPISUJE (DataStore) i odsyła
	                      --   przez atrybut gracza `Config.Graphics.AttributeName`; nic w grze
	                      --   od tego nie zależy (SettingsService)
	"StructureFX",        -- FireAllClients: (kind: "creak"|"collapse", position: Vector3, magnitude: number)
	"CarFire",            -- FireAllClients: (cf: CFrame, size: Vector3, duration: number) — płonący
	                      --   wrak auta po wybuchu (27.09). Czysty efekt u klienta: ogień nie rani
	                      --   i się nie rozprzestrzenia (pożary jako mechanika poza v1.0)
	                      --   kolaps grupy budynku v4 (CollapseService: "collapse" przy starcie
	                      --   lotu grupy; "creak" dziś nieużywany). Klient robi pył, dźwięk i wstrząs
	"DevCommand",         -- klient→server: FireServer(command: string) — "skip" | "endRound".
	                      --   Server waliduje Dev.isDev(player); tryb dev = Config.Dev.Enabled
	"FireGrapple",        -- klient→server: FireServer(targetPos: Vector3) — punkt, w który
	                      --   gracz wycelował hakiem. Serwer bierze stąd WYŁĄCZNIE kierunek
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
