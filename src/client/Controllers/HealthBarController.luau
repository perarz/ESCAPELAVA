--!strict
-- HealthBarController.luau (15.11) — własny pasek zdrowia zamiast domyślnego Robloxa.
--
-- Decyzje Kacpra 15.11: lewy dół nad kasą, pasek + liczba „72 / 100”, widoczny tylko
-- w rundzie, efekty: ghost (jasny kawałek straconego HP chwilę stoi, potem zjeżdża), kolor
-- od HP (zielony → żółty → czerwony), potrząśnięcie przy trafieniu, pulsowanie przy niskim HP.
-- Domyślny pasek wyłącza init.client (`CoreGuiType.Health`).
--
-- „W rundzie” = gracz ma atrybut uczestnika (`Config.Spectate.ParticipantAttribute`) — serwer
-- ustawia go po teleporcie na mapę i zdejmuje przy śmierci i na koniec rundy. Jedno źródło
-- prawdy z SPECTATE, zamiast drugiej, własnej logiki stanów gry.
--
-- KONTRAKT UI (Studio): `HUD.Cash.HealthBar` (Visible=false, pokazuje kod). W ramce kasy, nie
--   luzem w HUD (15.11): skaluje się razem z kasą i zawsze stoi tuż nad nią — pozycji od dołu
--   ekranu UIScale nie skaluje, więc luzem rozjeżdżał się z kasą na każdym innym ekranie.
--   Body (Frame) — potrząśnięcie przesuwa jego Position; Body.Pulse (UIScale) — puls. NIE „Pop”:
--   CashCounterController szuka `Pop` rekurencyjnie w całej ramce Cash.
--   Body.Track (Frame) z `Ghost` i `Fill` (Frame, Size.X.Scale = ułamek HP; kolor Fill ustawia kod)
--   Body.HpLabel (TextLabel) — „72 / 100”; cień `HpLabelShadow` kopiuje TextShadowController.
-- Brak UI = gra działa, tylko bez paska.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.HealthBar
local PARTICIPANT = Config.Spectate.ParticipantAttribute

local HealthBarController = {}

local localPlayer = Players.LocalPlayer

type Ui = {
	root: GuiObject,
	body: GuiObject,
	pop: UIScale?,
	fill: GuiObject,
	ghost: GuiObject?,
	label: TextLabel?,
}
local ui: Ui? = nil

local humanoid: Humanoid? = nil
local humConns: { RBXScriptConnection } = {}
local lastHealth = 100
local fillFrac = 1
local ghostFrac = 1
local ghostHoldUntil = 0
local shakeStart = -math.huge
local shakeAmp = 0
local bodyBase = UDim2.new()
local shown = false
local hideToken = 0
local initialized = false

local function targetFrac(): number
	local hum = humanoid
	if not hum or hum.MaxHealth <= 0 then return 0 end
	return math.clamp(hum.Health / hum.MaxHealth, 0, 1)
end

local function colorFor(frac: number): Color3
	local stops = CFG.Colors
	if frac <= stops[1][1] then return stops[1][2] end
	for i = 2, #stops do
		local a, b = stops[i - 1], stops[i]
		if frac <= b[1] then
			return a[2]:Lerp(b[2], (frac - a[1]) / (b[1] - a[1]))
		end
	end
	return stops[#stops][2]
end

local function updateLabel()
	local u, hum = ui, humanoid
	if not (u and u.label and hum) then return end
	u.label.Text = ("%d / %d"):format(math.max(0, math.ceil(hum.Health)), math.floor(hum.MaxHealth + 0.5))
end

-- Bez animacji: nowa postać albo pokazanie paska — pasek ma od razu stać na prawdziwym HP.
local function snap()
	fillFrac = targetFrac()
	ghostFrac = fillFrac
	ghostHoldUntil = 0
	shakeAmp = 0
	updateLabel()
end

local function onHealthChanged(newHealth: number)
	local lost = lastHealth - newHealth
	lastHealth = newHealth
	updateLabel()
	if lost > 0 then
		-- Każde trafienie przedłuża postój ghosta: seria szybkich obrażeń (lawa, odłamki) czyta
		-- się jako jeden spadek zamiast poszarpanego zjeżdżania.
		ghostHoldUntil = os.clock() + CFG.GhostDelay
		if lost >= CFG.ShakeMinDamage then
			shakeAmp = CFG.ShakeMax * math.clamp(lost / CFG.ShakeFullDamage, 0.3, 1)
			shakeStart = os.clock()
		end
	end
end

local function bindCharacter(char: Model)
	for _, c in ipairs(humConns) do c:Disconnect() end
	table.clear(humConns)
	humanoid = nil
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 10)
		if not (hum and hum:IsA("Humanoid")) or localPlayer.Character ~= char then return end
		humanoid = hum
		lastHealth = hum.Health
		snap()
		table.insert(humConns, hum.HealthChanged:Connect(onHealthChanged))
		table.insert(humConns, hum:GetPropertyChangedSignal("MaxHealth"):Connect(updateLabel))
	end)
end

local function setShown(on: boolean)
	local u = ui
	hideToken += 1
	if on then
		shown = true
		snap()
		if u then u.root.Visible = true end
		return
	end
	local hum = humanoid
	-- Śmierć zdejmuje atrybut w tej samej chwili, co spadek HP do zera — pasek z zerem zostaje
	-- jeszcze moment, inaczej gracz nie zobaczyłby ostatniego trafienia.
	local delayHide = if hum and hum.Health <= 0 then CFG.HideDelayAfterDeath else 0
	local token = hideToken
	task.delay(delayHide, function()
		if token ~= hideToken then return end
		shown = false
		if ui then (ui :: Ui).root.Visible = false end
	end)
end

local function refreshShown()
	local on = localPlayer:GetAttribute(PARTICIPANT) == true
	if on ~= shown or (not on and hideToken == 0) then
		setShown(on)
	end
end

local function render(dt: number)
	local u = ui
	if not (u and shown) then return end
	local now = os.clock()
	local target = targetFrac()

	fillFrac += (target - fillFrac) * math.min(1, dt / CFG.FillTime)
	if math.abs(target - fillFrac) < 0.001 then fillFrac = target end
	if target >= ghostFrac then
		-- Leczenie: ghost pokazuje tylko STRACONE HP, więc idzie razem z wypełnieniem.
		ghostFrac = fillFrac
	elseif now >= ghostHoldUntil then
		ghostFrac += (fillFrac - ghostFrac) * math.min(1, dt / (CFG.GhostTime / 3))
	end
	ghostFrac = math.max(ghostFrac, fillFrac)

	u.fill.Size = UDim2.fromScale(fillFrac, 1)
	u.fill.Visible = fillFrac > 0.005
	if u.ghost then
		u.ghost.Size = UDim2.fromScale(ghostFrac, 1)
		u.ghost.Visible = ghostFrac > 0.005
	end

	local color = colorFor(fillFrac)
	local scale = 1
	if fillFrac > 0 and fillFrac < CFG.LowFraction then
		local wave = 0.5 + 0.5 * math.sin(now * CFG.PulseHz * math.pi * 2)
		scale = 1 + CFG.PulseScale * wave
		color = color:Lerp(Color3.new(1, 1, 1), 0.3 * wave)
	end
	u.fill.BackgroundColor3 = color
	if u.pop then u.pop.Scale = scale end

	local shakeT = (now - shakeStart) / CFG.ShakeTime
	if shakeT < 1 and shakeAmp > 0 then
		local a = shakeAmp * (1 - shakeT)
		u.body.Position = bodyBase + UDim2.fromOffset((math.random() * 2 - 1) * a, (math.random() * 2 - 1) * a)
	else
		u.body.Position = bodyBase
	end
end

function HealthBarController.init()
	if initialized then return end
	initialized = true

	-- Listenery przed każdym czekaniem (zasada pliku init.client i hard rule 9).
	localPlayer:GetAttributeChangedSignal(PARTICIPANT):Connect(refreshShown)
	localPlayer.CharacterAdded:Connect(bindCharacter)
	if localPlayer.Character then bindCharacter(localPlayer.Character) end
	RunService.RenderStepped:Connect(render)

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD")
		local cash = hud:WaitForChild("Cash", 5)
		local root = if cash then cash:WaitForChild("HealthBar", 5) else nil
		if not (root and root:IsA("GuiObject")) then
			warn("[HealthBarController] HUD.Cash.HealthBar nie istnieje — własny pasek zdrowia wyłączony")
			return
		end
		local body = root:FindFirstChild("Body")
		local fill = root:FindFirstChild("Fill", true)
		if not (body and body:IsA("GuiObject") and fill and fill:IsA("GuiObject")) then
			warn("[HealthBarController] HUD.HealthBar bez Body/Fill — pasek wyłączony")
			return
		end
		local ghost = root:FindFirstChild("Ghost", true)
		local label = root:FindFirstChild("HpLabel", true)
		local pop = body:FindFirstChild("Pulse")
		bodyBase = body.Position
		ui = {
			root = root,
			body = body,
			pop = if pop and pop:IsA("UIScale") then pop else nil,
			fill = fill,
			ghost = if ghost and ghost:IsA("GuiObject") then ghost else nil,
			label = if label and label:IsA("TextLabel") then label else nil,
		}
		root.Visible = false
		shown = false
		refreshShown()
	end)
end

return HealthBarController
