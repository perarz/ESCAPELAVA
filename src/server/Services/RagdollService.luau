--!strict
-- RagdollService.luau
-- JEDYNY właściciel ragdolla po stronie serwera.
--
-- Powstał, bo BombService i FallDamageService niezależnie ustawiały ten sam `BoolValue`
-- (`PlayerGui.ragdoll.variables.ragdoll`) i każdy trzymał własny `task.delay` na wstawanie.
-- Dwa timery na jednej zmiennej to wyścig, w którym bomba stawia gracza w środku ragdolla
-- z upadku (i odwrotnie), a objawy są nie do odróżnienia od „ragdoll się buguje".
-- Jeden licznik generacji per gracz kończy ten wyścig: każde nowe zlecenie unieważnia
-- poprzednie, więc upadek w trakcie ragdolla z bomby PRZEDŁUŻA leżenie, zamiast walczyć.
--
-- ⚠️ SEMANTYKA PRĘDKOŚCI: `ragdollclient` robi `HumanoidRootPart.Velocity = velocity`,
-- czyli NADPISUJE. Knockback bomby podaje prędkość docelową (o to chodzi), ale upadek MUSI
-- zachować pion, inaczej wywrotka w locie zeruje spadanie i gracz zawisa — od tego jest
-- `dampHorizontal`.
--
-- ⛔ NIE RUSZAĆ TU FIZYKI POSTACI (2026-09-21, kosztowna lekcja). Była tu próba przełączania
-- `CustomPhysicalProperties` na `HumanoidRootPart`/`Head` (toolbox zeruje im tarcie i masę
-- przy każdym spawnie, co robi „śliski" ruch) razem ze strażnikiem pilnującym tych wartości
-- i rozluźnianiem limitów stawów. Ruch faktycznie zrobił się ostry — ale **ragdoll zaczął
-- trzepać** i trzy kolejne próby łatania tego nie pomogły. Wszystko cofnięte do stanu,
-- w którym wywrotka działa. Wniosek: warunki fizyczne, w jakich toolbox tworzy i prowadzi
-- swoje constrainty, muszą zostać nietknięte; ostrość ruchu trzeba załatwić GDZIE INDZIEJ,
-- nie zmieniając właściwości partów postaci.

local Players = game:GetService("Players")

local RagdollService = {}

-- Generacja zlecenia wstawania per gracz. Rośnie przy KAŻDYM `knock`, więc starsze
-- `task.delay` widzą nieaktualny numer i milczą.
local generation: { [Player]: number } = {}
local initialized = false

type RagdollFolder = {
	invoke: BindableFunction,
	flag: BoolValue?,
}

-- Ostrzegamy RAZ na gracza — inaczej przy 30 Hz sprawdzania upadku log by się zalał.
local warned: { [Player]: boolean } = {}

local function findRagdoll(player: Player): RagdollFolder?
	local gui = player:FindFirstChild("PlayerGui")
	local folder = gui and gui:FindFirstChild("ragdoll")
	if not folder then
		-- ⚠️ TO MUSI KRZYCZEĆ. Wcześniej wychodziło stąd ciche `nil` i ragdoll po prostu
		-- NIE DZIAŁAŁ dla tego gracza przez całą sesję, bez śladu w logach — zgłoszone
		-- 2026-09-21 jako „ragdoll działa tylko na kolegę, na mnie nie".
		if not warned[player] then
			warned[player] = true
			warn(("[Ragdoll] %s NIE MA PlayerGui.ragdoll — wywrotka dla niego nie zadziała. "
				.. "Folder trafia do StarterGui przy starcie serwera; jeśli gracz zaspawnował "
				.. "wcześniej, jego PlayerGui go nie dostał."):format(player.Name))
		end
		return nil
	end

	local functions = folder:FindFirstChild("functions")
	local fn = functions and functions:FindFirstChild("ragdoll")
	if not (fn and fn:IsA("BindableFunction")) then return nil end

	local variables = folder:FindFirstChild("variables")
	local flag = variables and variables:FindFirstChild("ragdoll")

	return {
		invoke = fn,
		flag = if flag and flag:IsA("BoolValue") then flag else nil,
	}
end

-- Prędkość dla wywrotki, która NIE zabija lotu: poziom tłumiony (biegnący przewraca
-- się do przodu), pion nietknięty (spadanie toczy się dalej).
function RagdollService.dampHorizontal(velocity: Vector3, factor: number): Vector3
	return Vector3.new(velocity.X * factor, velocity.Y, velocity.Z * factor)
end

-- Zaplanuj postawienie gracza na nogi za `delaySeconds`. Unieważnia wcześniejsze
-- zlecenia — dzięki temu upadek w trakcie ragdolla z bomby przedłuża leżenie,
-- zamiast walczyć z cudzym timerem.
function RagdollService.scheduleGetUp(player: Player, delaySeconds: number)
	local gen = (generation[player] or 0) + 1
	generation[player] = gen

	task.delay(delaySeconds, function()
		if generation[player] ~= gen then return end
		local rag = findRagdoll(player)
		if rag and rag.flag then
			rag.flag.Value = false
		end
	end)
end

-- Wywróć gracza. `velocity` jest USTAWIANA na HumanoidRootPart (patrz nagłówek).
-- `duration` nil = caller sam zaplanuje wstawanie (tak robi upadek: ragdoll leci
-- w powietrzu, a termin liczy się dopiero od lądowania).
function RagdollService.knock(player: Player, velocity: Vector3, duration: number?)
	local rag = findRagdoll(player)
	if not rag then return end

	-- `Invoke` YIELDUJE (hard rule 8b), więc nigdy nie wołamy go wprost z pętli wywołującej.
	task.spawn(function()
		pcall(function()
			rag.invoke:Invoke(velocity)
		end)
	end)

	if duration then
		RagdollService.scheduleGetUp(player, duration)
	end
end

-- ⚠️ KONIEC WYŚCIGU O FOLDER RAGDOLLA (2026-09-21, zgłoszenie „ragdoll działa tylko
-- na kolegę"). Toolbox ARTFVL ma w Workspace Script `RagdollScriptMover`, który DOPIERO
-- W TRAKCIE DZIAŁANIA SERWERA przenosi folder `ragdoll` do `StarterGui` i kasuje się sam.
-- A Roblox kopiuje `StarterGui` do `PlayerGui` w momencie SPAWNU POSTACI — więc kto zdążył
-- zaspawnować przed tym skryptem, nie dostawał folderu NIGDY. Trafiało to zwykle w hosta,
-- bo on wchodzi pierwszy. Robimy tę przeprowadzkę sami, zanim `PlayerService` kogokolwiek
-- postawi (kolejność w `init.server.luau` — RagdollService PRZED PlayerService).
local function ensureRagdollTemplate()
	local starterGui = game:GetService("StarterGui")
	if starterGui:FindFirstChild("ragdoll") then return end

	for _, child in ipairs(workspace:GetChildren()) do
		local folder = child:FindFirstChild("ragdoll")
		if folder then
			folder.Parent = starterGui
			-- Mover i tak kasuje swojego rodzica po przeniesieniu; robimy to za niego,
			-- bo inaczej jego `FindFirstChild("ragdoll")` zwróci nil i rzuci błędem.
			child:Destroy()
			print("[Ragdoll] folder przeniesiony do StarterGui przed spawnem graczy")
			return
		end
	end
	warn("[Ragdoll] NIE ZNALAZŁEM folderu `ragdoll` ani w StarterGui, ani w Workspace — "
		.. "wywrotka nie zadziała dla nikogo. Sprawdź, czy toolbox ARTFVL jest w miejscu.")
end

function RagdollService.init()
	if initialized then return end
	initialized = true

	ensureRagdollTemplate()

	Players.PlayerRemoving:Connect(function(player: Player)
		generation[player] = nil
		warned[player] = nil
	end)
end

return RagdollService
