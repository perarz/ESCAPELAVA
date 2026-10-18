--!strict
-- LoadingScreen.client.luau — ReplicatedFirst
--
-- Czarny ekran z paskiem, który trzyma gracza, DOPÓKI świat naprawdę się nie załaduje.
-- Powstał ze zgłoszenia „jak wejdę do gry, to cienie i światła się w pełni nie ładują":
-- Roblox pokazuje grę, zanim tekstury, materiały i geometria dojadą do klienta, więc
-- pierwsze sekundy widać gołe kolory i doskakujące cienie.
--
-- DLACZEGO `ReplicatedFirst`, A NIE `StarterGui`:
-- skrypty z ReplicatedFirst startują PRZED resztą replikacji, więc czarny ekran zdąży się
-- pojawić, zanim gracz zobaczy niedoładowany świat. StarterGui dojeżdża za późno.
--
-- ⚠️ DLATEGO TEŻ NIE MA TU `require(Config)` — `ReplicatedStorage.Shared` w momencie
-- startu tego skryptu może jeszcze nie istnieć. Wszystkie liczby są lokalne, świadomie.
--
-- WYGLĄD NALEŻY DO KACPRA: jeśli w `ReplicatedFirst` położysz własne `ScreenGui`
-- o nazwie `LoadingScreen`, kod użyje jego zamiast budować swój. Napędza tylko nazwy:
--   `Fill`        (Frame)     — pasek postępu, kod ustawia `Size.X.Scale` 0..1
--   `StatusLabel` (TextLabel) — opcjonalny, kod wpisuje co teraz robi
--   `Percent`     (TextLabel) — opcjonalny, kod wpisuje "42%"
-- Poniższy ekran to PLACEHOLDER — brzydki z założenia, do podmiany.

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Twardy sufit na CAŁE ładowanie. Ekran ładowania, który potrafi zawisnąć na zawsze,
-- jest gorszy od niedoładowanego świata — po tym czasie wpuszczamy gracza bez względu
-- na wszystko.
local HARD_DEADLINE = 30

local PRELOAD_BATCH = 40      -- ile assetów na jedno wywołanie (pasek ma się ruszać)
local MAX_PRELOAD = 2500      -- sufit na liczbę assetów; mapa ma 25k partów, ale assetów garść
local SETTLE_FRAMES = 10      -- klatek po załadowaniu: tyle zajmuje zbudowanie cieni
local SETTLE_TIME = 0.5
local FADE_TIME = 0.6
local CHARACTER_TIMEOUT = 12
local STREAM_TIMEOUT = 10
-- Ile najdłużej czekamy na kasę, itemy i stan rundy w HUD (paczka 3, decyzja Kacpra 18.10:
-- „wszystko ma się załadować w tym UI”). Sygnał: lokalny atrybut `ClientStateReady` na
-- graczu, ustawiany przez `init.client`, gdy dojdą wszystkie trzy. Nazwa = kontrakt z tamtym
-- plikiem (tu nie ma `require`, patrz wyżej).
local STATE_TIMEOUT = 15
local STATE_ATTRIBUTE = "ClientStateReady"

-- Zdejmujemy domyślny ekran Robloxa OD RAZU, zanim cokolwiek innego zdąży się wydarzyć.
ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================================
-- GUI
-- ============================================================================

type Screen = {
	gui: ScreenGui,
	fill: Frame?,
	status: TextLabel?,
	percent: TextLabel?,
	fadeTargets: { GuiObject },
}

local function collectFadeTargets(root: Instance): { GuiObject }
	local out: { GuiObject } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then
			table.insert(out, d)
		end
	end
	return out
end

local function buildFallback(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.62)
	track.Size = UDim2.new(0, 340, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 44)
	track.BorderSizePixel = 0
	track.Parent = backdrop

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 90, 25)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local status = Instance.new("TextLabel")
	status.Name = "StatusLabel"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, 0, 0.62, 18)
	status.Size = UDim2.new(0, 340, 0, 18)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextColor3 = Color3.fromRGB(150, 150, 155)
	status.Text = ""
	status.Parent = backdrop

	return gui
end

local function setupScreen(): Screen
	local template = ReplicatedFirst:FindFirstChild("LoadingScreen")
	local gui: ScreenGui
	if template and template:IsA("ScreenGui") then
		gui = template:Clone()
	else
		gui = buildFallback()
	end

	-- Ma przykryć absolutnie wszystko, łącznie z paskiem systemowym Robloxa.
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2147483647
	gui.Enabled = true
	gui.Parent = playerGui

	return {
		gui = gui,
		fill = gui:FindFirstChild("Fill", true) :: Frame?,
		status = gui:FindFirstChild("StatusLabel", true) :: TextLabel?,
		percent = gui:FindFirstChild("Percent", true) :: TextLabel?,
		fadeTargets = collectFadeTargets(gui),
	}
end

local screen = setupScreen()

-- Postęp nigdy nie cofa się i nie skacze do tyłu — pasek, który drga, wygląda na zepsuty.
local shown = 0
local function setProgress(value: number, text: string?)
	shown = math.clamp(math.max(shown, value), 0, 1)
	if screen.fill then
		screen.fill.Size = UDim2.fromScale(shown, 1)
	end
	if screen.percent then
		screen.percent.Text = string.format("%d%%", math.floor(shown * 100))
	end
	if text and screen.status then
		screen.status.Text = text
	end
end

setProgress(0, "Łączenie...")

-- ============================================================================
-- Ładowanie
-- ============================================================================

local deadline = os.clock() + HARD_DEADLINE

-- Klasy, które NIOSĄ asset (obrazek, mesh, dźwięk). Przekazujemy PreloadAsync same
-- instancje — Roblox sam wyciąga z nich właściwości z contentem, więc nie trzeba
-- utrzymywać listy nazw pól.
local ASSET_CLASSES: { [string]: boolean } = {
	Decal = true,
	Texture = true,
	ImageLabel = true,
	ImageButton = true,
	Sound = true,
	MeshPart = true,
	SpecialMesh = true,
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	Sky = true,
	SurfaceAppearance = true,
	MaterialVariant = true,
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	Animation = true,
}

local function collectAssets(): { Instance }
	local assets: { Instance } = {}
	local seen: { [Instance]: boolean } = {}

	-- MaterialService jest tu NIEOCZYWISTY, ale kluczowy: cały wygląd mapy stoi na
	-- `MaterialVariant "Studs"` z ColorMapem. Bez jego wgrania 25 tysięcy partów przez
	-- chwilę po wejściu wygląda jak goły plastik.
	local roots: { Instance } = { Lighting, MaterialService, ReplicatedStorage, StarterGui, StarterPlayer, Workspace }
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if ASSET_CLASSES[d.ClassName] and not seen[d] then
				seen[d] = true
				table.insert(assets, d)
				if #assets >= MAX_PRELOAD then
					return assets
				end
			end
		end
	end
	return assets
end

local function preload(assets: { Instance }, fromProgress: number, toProgress: number)
	local count = #assets
	if count == 0 then
		setProgress(toProgress)
		return
	end
	for i = 1, count, PRELOAD_BATCH do
		local last = math.min(i + PRELOAD_BATCH - 1, count)
		local batch = table.move(assets, i, last, 1, {})
		-- pcall: pojedynczy uszkodzony/usunięty asset nie może wywalić całego ładowania.
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		setProgress(fromProgress + (toProgress - fromProgress) * (last / count),
			string.format("Wczytywanie zasobów... %d/%d", last, count))
		if os.clock() > deadline then
			break
		end
	end
	setProgress(toProgress)
end

local function waitForCharacter(): BasePart?
	local char = player.Character
	if not char then
		local limit = math.min(os.clock() + CHARACTER_TIMEOUT, deadline)
		while not player.Character and os.clock() < limit do
			task.wait(0.1)
		end
		char = player.Character
	end
	if not char then
		return nil
	end
	return char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
end

-- StreamingEnabled = true w tym miejscu: świat NIE przychodzi cały naraz, tylko dociąga
-- się wokół gracza. Bez tego czekania czarny ekran znikałby, zanim pod postacią w ogóle
-- pojawi się podłoga — czyli dokładnie ten objaw, który zgłosił Kacper.
local function waitForWorldAround(hrp: BasePart)
	if not Workspace.StreamingEnabled then
		return
	end

	-- Prośba do serwera o priorytet dla okolicy spawnu (jeśli API dostępne).
	pcall(function()
		(player :: any):RequestStreamingAround(hrp.Position)
	end)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hrp.Parent :: Instance }

	local limit = math.min(os.clock() + STREAM_TIMEOUT, deadline)
	while os.clock() < limit do
		-- Grunt pod postacią = region wokół gracza jest już u klienta.
		if Workspace:Raycast(hrp.Position, Vector3.new(0, -250, 0), params) then
			return
		end
		task.wait(0.1)
	end
end

local function waitForClientState()
	local limit = math.min(os.clock() + STATE_TIMEOUT, deadline)
	while not player:GetAttribute(STATE_ATTRIBUTE) and os.clock() < limit do
		task.wait(0.1)
	end
	if not player:GetAttribute(STATE_ATTRIBUTE) then
		warn("[LoadingScreen] stan gracza (kasa / itemy / runda) nie doszedł w limicie — wpuszczam")
	end
end

-- ---------------------------------------------------------------------------

-- Zejście ekranu. Jedno miejsce i jeden raz — woła je zwykły przebieg albo strażnik niżej.
local finished = false
local function finish()
	if finished then return end
	finished = true
	setProgress(1, "Gotowe")
	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, obj in ipairs(screen.fadeTargets) do
		if obj.BackgroundTransparency < 1 then
			TweenService:Create(obj, info, { BackgroundTransparency = 1 }):Play()
		end
		if obj:IsA("TextLabel") then
			TweenService:Create(obj, info, { TextTransparency = 1 }):Play()
		elseif obj:IsA("ImageLabel") then
			TweenService:Create(obj, info, { ImageTransparency = 1 }):Play()
		end
	end
	task.wait(FADE_TIME)
	screen.gui:Destroy()
end

-- STRAŻNIK HARD_DEADLINE: etapy sprawdzają `deadline` tylko MIĘDZY swoimi krokami, a
-- `game.Loaded:Wait()` i pojedyncze `PreloadAsync` potrafią wisieć bez limitu — wtedy czarny
-- ekran zostawał na zawsze, wbrew zasadzie z nagłówka (przegląd 29.09, B-27).
task.delay(math.max(deadline - os.clock(), 0), finish)

task.spawn(function()
	-- 1) Podstawowa replikacja
	setProgress(0.04, "Łączenie...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	setProgress(0.12, "Wczytywanie zasobów...")

	-- 2) Assety: tekstury, materiały, dźwięki, meshe
	local assets = collectAssets()
	preload(assets, 0.12, 0.68)

	-- 3) Postać i świat wokół niej
	setProgress(0.7, "Wczytywanie mapy...")
	local hrp = waitForCharacter()
	if hrp then
		waitForWorldAround(hrp)
	end
	setProgress(0.8, "Wczytywanie danych gracza...")
	waitForClientState()
	setProgress(0.88, "Oświetlenie...")

	-- 4) Cienie i oświetlenie potrzebują kilku klatek PO tym, jak geometria jest na
	--    miejscu — to jest ta część, której nie da się "poczekać" żadnym eventem.
	for _ = 1, SETTLE_FRAMES do
		RunService.RenderStepped:Wait()
	end
	task.wait(SETTLE_TIME)

	-- 5) Zejście (no-op, jeśli strażnik zdjął ekran wcześniej)
	finish()
end)
