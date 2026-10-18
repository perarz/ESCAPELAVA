--!strict
-- RoundTransitionController.luau (07.10)
-- Ciemne przejście przy teleporcie z lobby na mapę.
--
-- Zgłoszenie Kacpra: po teleporcie budynki są, ale cienie i właściwe oświetlenie dochodzą
-- 10-20 s. Silnik buduje oświetlenie wokół KAMERY, a ta przez całą przerwę stała w lobby
-- ~640 studów od mapy. Dwie poprawki idą razem: streaming wyłączony (cała mapa jest u
-- klienta od wejścia — `default.project.json`) i ta zasłona: ekran ściemnia się pod koniec
-- odliczania lobby (od 11.10 — wcześniej odliczania GET READY, które usunięto), a rozjaśnia,
-- gdy gracz STOI już na mapie i silnik miał `SettleTime` na
-- oświetlenie. Świat renderuje się POD zasłoną, więc ten czas pracuje na wygląd.
--
-- Sygnał „stoisz na mapie” = `Remotes.AliveChanged(true)`, wysyłany przez serwer PO
-- `PivotTo` (PlayerService.sendEveryoneToRound). Nie zgadujemy z pozycji postaci.
--
-- WYGLĄD NALEŻY DO KACPRA: `StarterGui.RoundTransition` (ScreenGui) — jeśli istnieje, kod
-- go użyje i będzie ściemniał/rozjaśniał wszystkie jego elementy (ich przezroczystość z
-- Properties = stan „w pełni widoczny”). Bez niego: czarny prostokąt (placeholder, jak
-- ekran ładowania).
--
-- Przypadki brzegowe:
--   - odliczanie lobby przerwane (za mało graczy → LOBBY od nowa) → żeton unieważnia
--     zaplanowane ściemnienie, zasłona schodzi;
--   - dev skip lobby → ROUND bez ściemnienia → runRoundEntry zaciemnia od razu;
--   - gracz dołącza w trakcie rundy → widzi ROUND bez LOBBY przed nim → nic nie robimy
--     (zakrywa go ekran ładowania);
--   - gracz nie trafił do rundy (dołączał w odliczaniu) → brak sygnału przez
--     `SpawnSignalTimeout` → zasłona schodzi;
--   - wszystko ma twardy sufit `MaxHold` — wiszący czarny ekran jest gorszy od cieni.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CFG = Config.RoundTransition

local RoundTransitionController = {}

local player = Players.LocalPlayer

type Target = { obj: GuiObject, bg: number, text: number?, image: number? }

local gui: ScreenGui? = nil
local targets: { Target } = {}
local alpha = 0 -- 0 = niewidoczna, 1 = w pełni zakrywa
local fadeToken = 0 -- nowy fade unieważnia poprzedni
local flowToken = 0 -- nowy stan gry unieważnia poprzednią sekwencję
local lastState = ""
local aliveAt = -math.huge

local function ensureGui(): boolean
	if gui and gui.Parent then return true end
	local pgui = player:FindFirstChildOfClass("PlayerGui")
	if not pgui then return false end

	local sg = pgui:FindFirstChild("RoundTransition")
	if sg and sg:IsA("ScreenGui") then
		-- Kopia ze StarterGui odświeżyłaby się przy LoadCharacter na starcie rundy — czyli
		-- w środku przejścia (hard rule 10).
		sg.ResetOnSpawn = false
	else
		local fallback = Instance.new("ScreenGui")
		fallback.Name = "RoundTransition"
		fallback.ResetOnSpawn = false
		local frame = Instance.new("Frame")
		frame.Name = "Curtain"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.Parent = fallback
		fallback.Parent = pgui
		sg = fallback
	end
	local screen = sg :: ScreenGui
	screen.IgnoreGuiInset = true
	-- Pod ekranem ładowania (ReplicatedFirst, int32 max), nad całym HUD-em.
	screen.DisplayOrder = 2147483000

	targets = {}
	for _, d in ipairs(screen:GetDescendants()) do
		if d:IsA("GuiObject") then
			local t: Target = { obj = d, bg = d.BackgroundTransparency }
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				t.text = d.TextTransparency
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
				t.image = d.ImageTransparency
			end
			table.insert(targets, t)
		end
	end
	gui = screen
	return true
end

local function apply(a: number)
	alpha = a
	local screen = gui
	if not screen then return end
	screen.Enabled = a > 0
	for _, t in ipairs(targets) do
		-- Przezroczystość z Properties to stan a = 1; a = 0 → w pełni przezroczyste.
		t.obj.BackgroundTransparency = 1 - (1 - t.bg) * a
		if t.text then
			(t.obj :: any).TextTransparency = 1 - (1 - t.text) * a
		end
		if t.image then
			(t.obj :: any).ImageTransparency = 1 - (1 - t.image) * a
		end
	end
end

-- Liniowo od bieżącej wartości — przerwany fade nie skacze.
local function fadeTo(target: number, duration: number)
	if not ensureGui() then return end
	fadeToken += 1
	local token = fadeToken
	local from = alpha
	if duration <= 0 or from == target then
		apply(target)
		return
	end
	local started = os.clock()
	task.spawn(function()
		while token == fadeToken do
			local k = math.clamp((os.clock() - started) / duration, 0, 1)
			apply(from + (target - from) * k)
			if k >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function groundUnder(char: Model): boolean
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	return Workspace:Raycast(hrp.Position, Vector3.new(0, -60, 0), params) ~= nil
end

-- Start rundy: zakryj (jeśli odliczanie nie zdążyło), poczekaj na teleport i oświetlenie.
local function runRoundEntry(token: number)
	local roundAt = os.clock()
	local deadline = roundAt + CFG.MaxHold
	fadeTo(1, 0)

	local signalDeadline = math.min(roundAt + CFG.SpawnSignalTimeout, deadline)
	-- `aliveAt` ≥ chwila ROUND minus margines: sygnał mógł przyjść tuż przed tym wątkiem.
	while aliveAt < roundAt - 0.5 and os.clock() < signalDeadline do
		task.wait(0.05)
		if token ~= flowToken then return end
	end
	if aliveAt >= roundAt - 0.5 then
		-- Grunt pod nogami: przy wyłączonym streamingu jest od razu; to tylko bezpiecznik,
		-- gdyby streaming wrócił — nie odsłaniamy gracza nad pustką.
		while os.clock() < deadline do
			local char = player.Character
			if char and groundUnder(char) then break end
			task.wait(0.05)
			if token ~= flowToken then return end
		end
		local settleEnd = math.min(os.clock() + CFG.SettleTime, deadline)
		while os.clock() < settleEnd do
			task.wait(0.05)
			if token ~= flowToken then return end
		end
	end
	if token ~= flowToken then return end
	fadeTo(0, CFG.FadeOutTime)
end

local function onState(newState: string, duration: number?)
	flowToken += 1
	local token = flowToken
	local previous = lastState
	lastState = newState

	if newState == "LOBBY" and (duration or 0) > 0 then
		-- Lobby z odliczaniem: ściemnianie tak, żeby skończyło się razem z nim. Zasłona z
		-- poprzedniej rundy (gdyby jeszcze wisiała) najpierw schodzi.
		if alpha > 0 then
			fadeTo(0, CFG.FadeOutTime)
		end
		local lead = math.max((duration or 0) - CFG.FadeInTime, 0)
		task.delay(lead, function()
			if token == flowToken then
				fadeTo(1, CFG.FadeInTime)
			end
		end)
	elseif newState == "ROUND" and previous == "LOBBY" then
		task.spawn(runRoundEntry, token)
	elseif alpha > 0 then
		-- Odliczanie przerwane albo inny stan — nie zostawiamy ciemnego ekranu.
		fadeTo(0, CFG.FadeOutTime)
	end
end

local initialized = false
function RoundTransitionController.init()
	if initialized then return end
	initialized = true

	-- Listenery od razu (hard rule 9) — GUI dopiero, gdy będzie potrzebne.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: any, duration: any)
		if typeof(newState) ~= "string" then return end
		onState(newState, if typeof(duration) == "number" then duration else nil)
	end)
	Remotes.AliveChanged.OnClientEvent:Connect(function(isAlive: any)
		if isAlive == true then
			aliveAt = os.clock()
		end
	end)
end

return RoundTransitionController
