--!strict
-- FallDamageService.luau
-- Obrażenia i ragdoll za upadek z wysokości.
--
-- DECYZJE (ustalone z Kacprem):
--   • bezpiecznie do `SafeHeight`, śmierć od `LethalHeight`, liniowo pomiędzy
--   • upadek MOŻE zabić — dzięki temu push jest bronią także z dala od lawy
--   • ragdoll od `SafeHeight × RagdollHeightMultiplier`, odpalany JUŻ W LOCIE
--   • tylko w ROUND — w lobby nikt nie ginie od wygłupów przy sklepie
--
-- ============================ MODEL ============================
-- Gracz jest w jednym z dwóch stanów: NA ZIEMI albo W LOCIE. Cała mechanika to trzy
-- zdania:
--   • NA ZIEMI  → szczyt lotu = bieżąca wysokość stóp (następny upadek liczy się stąd),
--   • W LOCIE   → szczyt rośnie razem z graczem; prognoza „szczyt − grunt pode mną"
--                 mówi, jak groźny będzie ten upadek, zanim jeszcze się skończy,
--   • LOT → ZIEMIA = JEDEN upadek: obrażenia naliczane dokładnie raz, w momencie
--                 przejścia. „Raz" wynika ze struktury (przejście zdarza się raz),
--                 a nie z żadnego licznika czasu.
--
-- ⚠️ Była tu kiedyś blokada `LandingCooldown` (0.8 s nietykalności po naliczonym
-- upadku) — dodana, gdy ten sam upadek liczył się dwa razy. Prawdziwą przyczyną był
-- wtedy yieldujący `BindableFunction:Invoke` (hard rule 8b), naprawiony kolejnością
-- zapisu stanu, a blokada została i **zaczęła gubić prawdziwe upadki**: ustawiała się
-- przy KAŻDYM zaliczonym lądowaniu, także takim bez obrażeń. Zgłoszenie Kacpra
-- „spadam na tory, dostaję trochę, spadam niżej i już nic" to dokładnie ona.
-- Lekcja: bezpiecznik nałożony na objaw przeżywa przyczynę i zaczyna szkodzić.
--
-- ============================ POMIAR ============================
-- Serwerowy i nieufny wobec klienta: postać ma network ownership klienta, więc
-- `Humanoid.FloorMaterial` i stany humanoida ustawione lokalnie NIE są wiarygodne
-- (ta sama lekcja co WalkSpeed w AntiCheatService). Wszystko liczymy z pozycji HRP
-- i jednego raycastu w dół. `MovementController` liczy sobie własną wysokość spadku,
-- ale to wyłącznie kosmetyka (dip kamery, kurz) i nic stąd tego nie czyta.
--
-- KREDYT ZA ZABÓJSTWO: świadomie NIE tagujemy tu nikogo. Jeśli ofiara jest w oknie
-- 5 s po pushu albo bombie, `KillService.processDeath` sam przypisze zabójstwo —
-- czyli „zepchnąłem go z dachu" działa bez ani jednej linijki w tym serwisie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local GameLoopService = require(script.Parent.GameLoopService)
local PlayerService = require(script.Parent.PlayerService)
local RagdollService = require(script.Parent.RagdollService)

local FallDamageService = {}

local CFG = Config.FallDamage

-- Odległość HumanoidRootPart → stopy w R15. Ta sama stała co `FEET_OFFSET`
-- w LavaService, dostrojona do tego samego riga. Spadek mierzymy STOPAMI, bo gracz
-- myśli w kategoriach „z jakiej wysokości zeskoczyłem", a nie „gdzie był mój tułów".
local HRP_TO_FEET = 2.5

type Track = {
	peakY: number,         -- najwyższa pozycja STÓP od oderwania się od gruntu
	airborne: boolean,
	airTime: number,       -- sekundy w locie (odsiewa schodki, krawężniki, odbicia)
	lastHrpY: number,      -- pozycja HRP w poprzednim ticku — patrz `probe`
	ragdollFired: boolean, -- czy ten lot już wywrócił gracza
}

local tracks: { [Player]: Track } = {}
local initialized = false

local rayParams = RaycastParams.new()
rayParams.IgnoreWater = true
rayParams.FilterType = Enum.RaycastFilterType.Exclude
-- Bufor filtra reużywany między wywołaniami: przy 30 Hz i 20 graczach to 600 wywołań/s,
-- a każde tworzyło nową tablicę `{ char }` tylko po to, żeby ją od razu wyrzucić.
local filterBuffer: { Instance } = table.create(1)

-- JEDEN raycast odpowiada na oba pytania: „czy wylądowałem" i „jak wysoko jeszcze spadnę".
--
-- ⚠️ KLUCZOWA RZECZ: promień startuje z pozycji z POPRZEDNIEGO ticku, nie z obecnej.
-- Pokrywa więc odcinek, który gracz FAKTYCZNIE przeleciał, zamiast zgadywać, dokąd
-- doleci. Poprzednia wersja sięgała w dół o przewidywany dystans i przez to uznawała
-- za lądowanie każdy dach, nad którym gracz PRZELATYWAŁ — zgłoszenie Kacpra „bomba
-- mnie wyrzuca, spadam z budynku i nie ma obrażeń" brało się właśnie stąd: wyrzucony
-- gracz mijał dach, kod meldował lądowanie, zerował szczyt, a prawdziwy upadek
-- startował już od nowa.
-- Odcinek przebyty + `GroundProbe` = ani jednego fałszywego lądowania (nie da się
-- „wylądować" na czymś, czego się nie dotknęło), ani jednego przegapionego przy dużej
-- prędkości (przy 126 stud/s i 30 Hz to 4.2 studa na tick — sonda pokrywa je w całości).
--
-- W locie promień jest przedłużany do `PredictReach`, bo wtedy ten sam raycast podaje
-- grunt daleko w dole, czyli całą przyszłą wysokość upadku — znaną od pierwszej klatki
-- lotu, zamiast dopiero przy uderzeniu.
local function probe(char: Model, hrp: BasePart, track: Track): (number?, boolean)
	local pos = hrp.Position
	local hrpY = pos.Y
	-- Start z wyżej położonego z dwóch punktów: przy locie w górę (wyrzut bombą)
	-- to bieżąca pozycja, przy spadaniu — poprzednia.
	local originY = math.max(track.lastHrpY, hrpY)
	local travelled = originY - hrpY
	local tail = if track.airborne then CFG.PredictReach else CFG.GroundProbe

	filterBuffer[1] = char
	rayParams.FilterDescendantsInstances = filterBuffer

	local hit = Workspace:Raycast(
		Vector3.new(pos.X, originY, pos.Z),
		Vector3.new(0, -(travelled + tail), 0),
		rayParams
	)
	if not hit then
		return nil, false
	end

	local groundY = hit.Position.Y
	-- Lądowanie = grunt jest w zasięgu stóp TERAZ. Trafienie głębiej to grunt, do którego
	-- gracz dopiero leci — cenna informacja dla prognozy, ale nie lądowanie.
	local landed = groundY >= hrpY - CFG.GroundProbe
	return groundY, landed
end

local function ragdollThreshold(): number
	return CFG.SafeHeight * CFG.RagdollHeightMultiplier
end

local function applyFall(player: Player, hum: Humanoid, hrp: BasePart, drop: number, alreadyRagdolled: boolean)
	-- Termin wstawania ustawiamy PRZED progiem obrażeń: gracz wywrócony w locie mógł
	-- wylądować wyżej, niż zapowiadała prognoza (zdryfował na półkę), i wtedy upadek jest
	-- nieszkodliwy, ale ragdoll już trwa. Bez tego leżałby do bezpiecznika 8 s.
	if alreadyRagdolled and hum.Health > 0 then
		RagdollService.scheduleGetUp(player, CFG.RagdollDuration)
	end

	if drop <= CFG.SafeHeight then return end

	local span = math.max(1, CFG.LethalHeight - CFG.SafeHeight)
	local t = math.clamp((drop - CFG.SafeHeight) / span, 0, 1)
	hum:TakeDamage(hum.MaxHealth * t)

	-- Feedback reużywa `BombHit` zamiast nowego Remote'a: klient ma na nim wstrząs ekranu
	-- i szarpnięcie FOV skalowane siłą, a DebrisService (przygniecenie gruzem) robi
	-- dokładnie to samo. Jeden kontrakt mniej do utrzymania.
	Remotes.BombHit:FireClient(player, t)

	-- Ragdoll przy samym lądowaniu tylko wtedy, gdy nie poleciał już w locie (upadek tuż
	-- nad progiem) i tylko gdy gracz PRZEŻYŁ: martwym zajmuje się PlayerService.onDeath,
	-- a dwa systemy szarpiące tę samą postać to gotowy błąd „zwłoki wstają".
	if not alreadyRagdolled and hum.Health > 0 and drop >= ragdollThreshold() then
		RagdollService.knock(player, RagdollService.dampHorizontal(hrp.AssemblyLinearVelocity, CFG.RagdollTumble), CFG.RagdollDuration)
	end

	if CFG.Debug then
		print(("[Fall] %s spadł %.1f stud → %.0f dmg (HP %.0f)"):format(
			player.Name, drop, hum.MaxHealth * t, hum.Health))
	end
end

-- Czy wywrócić gracza JESZCZE W LOCIE?
--
-- Sens: toolbox ARTFVL steruje ragdollem przez `remoteragdoll.OnClientInvoke`, czyli
-- serwer → klient, więc od decyzji do zwiotczenia mija pełna droga w obie strony
-- (~0.1 s w Studio, więcej z pingiem). Odpalając w locie dajemy mu na to cały lot.
--
-- ⚠️ „W POWIETRZU" ≠ „SPADAM". Brak gruntu pod stopami mają też: wspinaczka po ścianie,
-- drabina, wyrzut w górę po wybuchu i stanie na wąskiej półce nad przepaścią — a prognoza
-- rośnie wtedy RAZEM z graczem i w końcu przebija próg, mimo że lot jest w drugą stronę
-- (zgłoszenie „jak się wspinam, to mi się ragdoll włącza"). Dlatego prognoza to tylko
-- jeden z trzech warunków; dwa pozostałe potwierdzają, że gracz realnie opada.
local function shouldRagdollMidair(track: Track, hrp: BasePart, feetY: number, groundY: number?): boolean
	if track.ragdollFired or not groundY then return false end
	if track.airTime < CFG.PreRagdollMinAirTime then return false end
	if track.peakY - feetY < CFG.PreRagdollMinDrop then return false end
	if math.max(0, -hrp.AssemblyLinearVelocity.Y) < CFG.PreRagdollMinSpeed then return false end
	-- Prognoza jest pewna w jedną stronę: może jeszcze urosnąć (gracz zleci niżej),
	-- ale nie zmaleje. Przekroczenie progu w locie znaczy, że upadek NA PEWNO zasłuży.
	return (track.peakY - groundY) >= ragdollThreshold()
end

local function tick(dt: number)
	for _, player in ipairs(PlayerService.getAliveList()) do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (char and hum and hrp and hrp:IsA("BasePart")) or hum.Health <= 0 then
			continue
		end

		local hrpY = hrp.Position.Y
		local feetY = hrpY - HRP_TO_FEET

		local track = tracks[player]
		if not track then
			track = {
				peakY = feetY,
				airborne = false,
				airTime = 0,
				lastHrpY = hrpY,
				ragdollFired = false,
			}
			tracks[player] = track
		end

		local groundY, landed = probe(char, hrp, track)

		if landed then
			-- ⚠️ STAN AKTUALIZUJEMY ZANIM cokolwiek wywołamy (hard rule 8b): `applyFall`
			-- schodzi do ragdolla, a wszystko, co może oddać sterowanie, musi zastać
			-- spójny stan — inaczej Heartbeat wejdzie tu ponownie z `airborne = true`
			-- i tym samym szczytem, czyli naliczy ten sam upadek drugi raz.
			local qualifies = track.airborne and track.airTime >= CFG.MinAirTime
			local drop = track.peakY - (groundY :: number)
			local wasRagdolled = track.ragdollFired

			track.airborne = false
			track.airTime = 0
			track.peakY = feetY
			track.ragdollFired = false

			if qualifies then
				applyFall(player, hum, hrp, drop, wasRagdolled)
			end
		else
			if not track.airborne then
				track.airborne = true
				track.airTime = 0
				track.peakY = feetY
			end
			track.airTime += dt
			if feetY > track.peakY then
				-- Szczyt, nie punkt oderwania: gracz wyrzucony bombą w górę ma liczone
				-- dopiero to, co spadnie Z APOGEUM.
				track.peakY = feetY
			end

			if hum.Health > 0 and shouldRagdollMidair(track, hrp, feetY, groundY) then
				track.ragdollFired = true
				RagdollService.knock(player, RagdollService.dampHorizontal(hrp.AssemblyLinearVelocity, CFG.RagdollTumble))
				-- Bezpiecznik na wypadek, gdyby gracz nigdy nie wylądował (lawa, przepaść).
				-- Przy lądowaniu `applyFall` przestawi termin na pełny `RagdollDuration`.
				RagdollService.scheduleGetUp(player, CFG.RagdollAirSafety)
			end
		end

		track.lastHrpY = hrpY
	end
end

function FallDamageService.init()
	if initialized then return end
	initialized = true

	if not CFG.Enabled then
		warn("[Fall] WYŁĄCZONE (Config.FallDamage.Enabled=false) — upadki nie ranią.")
		return
	end

	local acc = 0
	local interval = 1 / math.max(CFG.CheckHz, 1)
	RunService.Heartbeat:Connect(function(dt: number)
		-- Poza rundą nie mierzymy NIC: w lobby gracze skaczą po sklepie, a przerwa
		-- między rundami to nie jest moment na ginięcie.
		if GameLoopService.getState() ~= GameLoopService.STATE.ROUND then
			if next(tracks) then
				table.clear(tracks)
			end
			return
		end
		acc += dt
		if acc < interval then return end
		tick(acc)
		acc = 0
	end)

	-- Każdy teleport i respawn MUSI czyścić pomiar, inaczej serwerowy skok pozycji
	-- (lobby → spawn rundy, POST_ROUND → lobby) policzyłby się jako upadek z kilkuset
	-- studów. Ta sama zasada co w AntiCheatService: ruch wykonany przez serwer to nie
	-- jest ruch gracza.
	GameLoopService.StateChanged:Connect(function()
		table.clear(tracks)
	end)

	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			tracks[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		tracks[player] = nil
	end)
end

return FallDamageService
