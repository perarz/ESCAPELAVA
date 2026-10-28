--!strict
-- LoadingScreen.client.luau — ReplicatedFirst
--
-- Ekran ładowania, który trzyma gracza, DOPÓKI świat naprawdę się nie załaduje.
-- Powstał ze zgłoszenia „jak wejdę do gry, to cienie i światła się w pełni nie ładują":
-- Roblox pokazuje grę, zanim tekstury, materiały i geometria dojadą do klienta, więc
-- pierwsze sekundy widać gołe kolory i doskakujące cienie.
--
-- DLACZEGO `ReplicatedFirst`, A NIE `StarterGui`:
-- skrypty z ReplicatedFirst startują PRZED resztą replikacji, więc ekran zdąży się
-- pojawić, zanim gracz zobaczy niedoładowany świat. StarterGui dojeżdża za późno.
--
-- ⚠️ DLATEGO TEŻ NIE MA TU `require(Config)` — `ReplicatedStorage.Shared` w momencie
-- startu tego skryptu może jeszcze nie istnieć. Wszystkie liczby są lokalne, świadomie.
--
-- WYGLĄD = obiekty w placu (20.10, zasada UI Kacpra): `ReplicatedFirst.LoadingGui` (ScreenGui).
-- `default.project.json` ma przy ReplicatedFirst `$ignoreUnknownInstances`, inaczej Rojo by go
-- skasował. Nazwa ≠ nazwa tego skryptu (`LoadingScreen`) — inaczej FindFirstChild trafiał w skrypt.
-- Kod napędza nazwy (opis: docs/STUDIO_CONTRACT.md → „Ekran ładowania”):
--   `Center` + UIScale `HudScale` — skala jak w HUD (px przy wysokości 1200)
--   `Fill` (Frame, Size.X.Scale 0..1), `Percent`, `StatusLabel` (+ `<Nazwa>Shadow`)
-- Bez `LoadingGui` zostaje domyślny ekran Robloxa — kod nie buduje UI sam.

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

local TEMPLATE_NAME = "LoadingGui"
local TEMPLATE_WAIT = 5
-- Skala jak `HudScaleController` (Config.UI.ReferenceHeight / MinScale / MaxScale) — kopia,
-- bo tu nie ma `require`. Zmieniając tamte, zmienić i te.
local REF_HEIGHT = 1200
local MIN_SCALE = 0.5
local MAX_SCALE = 2
local FILL_SPEED = 8          -- jak szybko pasek dogania postęp (1/s): płynnie, bez skoków

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Zawartość ReplicatedFirst przychodzi razem z tym skryptem, więc zwykle bez czekania.
local template = ReplicatedFirst:WaitForChild(TEMPLATE_NAME, TEMPLATE_WAIT)
if not (template and template:IsA("ScreenGui")) then
	warn("[LoadingScreen] brak ReplicatedFirst." .. TEMPLATE_NAME .. " — zostaje domyślny ekran Robloxa")
	return
end
-- Domyślny ekran Robloxa zdejmujemy dopiero, gdy mamy czym go zastąpić.
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ============================================================================
-- GUI
-- ============================================================================

type Screen = {
	gui: ScreenGui,
	fill: GuiObject?,
	status: TextLabel?,
	percent: TextLabel?,
	fadeTargets: { Instance },
}

local function collectFadeTargets(root: Instance): { Instance }
	local out: { Instance } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") or d:IsA("UIStroke") then
			table.insert(out, d)
		end
	end
	return out
end

local gui = (template :: ScreenGui):Clone()
-- Ma przykryć absolutnie wszystko, łącznie z paskiem systemowym Robloxa.
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2147483647
gui.Enabled = true
gui.Parent = playerGui

local screen: Screen = {
	gui = gui,
	fill = gui:FindFirstChild("Fill", true) :: GuiObject?,
	status = gui:FindFirstChild("StatusLabel", true) :: TextLabel?,
	percent = gui:FindFirstChild("Percent", true) :: TextLabel?,
	fadeTargets = collectFadeTargets(gui),
}

-- Skala środka jak w HUD (tło jest na cały ekran i skali nie potrzebuje).
local center = gui:FindFirstChild("Center")
local hudScale = center and center:FindFirstChild("HudScale") :: UIScale?

local function applyScale()
	if hudScale then
		hudScale.Scale = math.clamp(gui.AbsoluteSize.Y / REF_HEIGHT, MIN_SCALE, MAX_SCALE)
	end
end
applyScale()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)

local function setText(label: TextLabel?, text: string)
	if not label then return end
	label.Text = text
	local shadow = label.Parent and label.Parent:FindFirstChild(label.Name .. "Shadow")
	if shadow and shadow:IsA("TextLabel") then
		shadow.Text = text
	end
end

-- Postęp nigdy nie cofa się — pasek, który drga, wygląda na zepsuty. `target` to stan
-- ładowania, `shown` to to, co widać: dogania go płynnie co klatkę.
local target = 0
local shown = 0
local function setProgress(value: number, text: string?)
	target = math.clamp(math.max(target, value), 0, 1)
	if text then
		setText(screen.status, text)
	end
end

local function render(dt: number)
	shown += (target - shown) * (1 - math.exp(-FILL_SPEED * dt))
	if target - shown < 0.001 then shown = target end
	if screen.fill then
		screen.fill.Size = UDim2.fromScale(shown, 1)
		-- Za wąski pasek z zaokrągleniem rysuje się jak kropka.
		screen.fill.Visible = shown > 0.03
	end
	setText(screen.percent, string.format("%d%%", math.floor(shown * 100 + 0.5)))
end
RunService:BindToRenderStep("LoadingScreen", Enum.RenderPriority.Last.Value, render)

setProgress(0, "CONNECTING...")

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

	-- MaterialService zawiera Studs używane przez otoczenie oraz warianty lawy.
	-- Brak Studs od 26.10 dotyczy wyłącznie modeli itemów, nie mapy.
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
			string.format("LOADING ASSETS %d/%d", last, count))
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

-- Przy StreamingEnabled = true świat NIE przychodzi cały naraz, tylko dociąga się wokół
-- gracza — bez tego czekania ekran znikałby, zanim pod postacią pojawi się podłoga.
-- (Od 07.10 plac ma StreamingEnabled = false — wtedy funkcja od razu wraca.)
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
	setProgress(1, "READY!")
	-- Chwila, żeby pasek dobiegł do 100% i było to widać.
	local waitUntil = os.clock() + 0.4
	while shown < 0.995 and os.clock() < waitUntil do
		RunService.RenderStepped:Wait()
	end
	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, obj in ipairs(screen.fadeTargets) do
		if obj:IsA("UIStroke") then
			TweenService:Create(obj, info, { Transparency = 1 }):Play()
			continue
		end
		local g = obj :: GuiObject
		if g.BackgroundTransparency < 1 then
			TweenService:Create(g, info, { BackgroundTransparency = 1 }):Play()
		end
		if g:IsA("TextLabel") then
			TweenService:Create(g, info, { TextTransparency = 1 }):Play()
		elseif g:IsA("ImageLabel") then
			TweenService:Create(g, info, { ImageTransparency = 1 }):Play()
		end
	end
	task.wait(FADE_TIME)
	RunService:UnbindFromRenderStep("LoadingScreen")
	screen.gui:Destroy()
end

-- STRAŻNIK HARD_DEADLINE: etapy sprawdzają `deadline` tylko MIĘDZY swoimi krokami, a
-- `game.Loaded:Wait()` i pojedyncze `PreloadAsync` potrafią wisieć bez limitu — wtedy czarny
-- ekran zostawał na zawsze, wbrew zasadzie z nagłówka (przegląd 29.09, B-27).
task.delay(math.max(deadline - os.clock(), 0), finish)

task.spawn(function()
	-- 1) Podstawowa replikacja
	setProgress(0.04, "CONNECTING...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	setProgress(0.12, "LOADING ASSETS...")

	-- 2) Assety: tekstury, materiały, dźwięki, meshe
	local assets = collectAssets()
	preload(assets, 0.12, 0.68)

	-- 3) Postać i świat wokół niej
	setProgress(0.7, "LOADING MAP...")
	local hrp = waitForCharacter()
	if hrp then
		waitForWorldAround(hrp)
	end
	setProgress(0.8, "LOADING PLAYER...")
	waitForClientState()
	setProgress(0.88, "LIGHTING UP...")

	-- 4) Cienie i oświetlenie potrzebują kilku klatek PO tym, jak geometria jest na
	--    miejscu — to jest ta część, której nie da się "poczekać" żadnym eventem.
	for _ = 1, SETTLE_FRAMES do
		RunService.RenderStepped:Wait()
	end
	task.wait(SETTLE_TIME)

	-- 5) Zejście (no-op, jeśli strażnik zdjął ekran wcześniej)
	finish()
end)
