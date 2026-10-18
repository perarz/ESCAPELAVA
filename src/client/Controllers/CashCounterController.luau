--!strict
-- CashCounterController.luau (10.10) — licznik kasy: liczba, lecące banknoty, podskok.
--
-- Pomysł Kacpra: przy każdym ZAROBKU banknot (ta sama grafika co ikona licznika) wyskakuje na
-- środku ekranu i leci do licznika; licznik przy dolocie podskakuje, a liczba rośnie płynnie
-- do nowej sumy. Więcej pieniędzy = więcej banknotów (`Config.Cash.Fly.Notes`). Wydatek
-- (sklep) → liczba od razu spada, bez banknotów. Popup „+10$” usunięty (decyzja Kacpra).
--
-- JEDYNY, który pisze `CashLabel.Text` (do 10.10 robił to UIController co klatkę — dwa
-- miejsca zapisu rozjechałyby animację).
--
-- KONTRAKT (UI w Studio — tu tylko logika):
--   HUD.Cash … CashLabel (TextLabel) — liczba; cień `CashLabelShadow` kopiuje TextShadowController
--   HUD.Cash … Icon (ImageLabel)     — cel lotu banknotów
--   HUD.Cash … Pop (UIScale)         — podskok licznika (opcjonalny)
--   HUD.CashFlyTemplate (ImageLabel, Visible=false, AnchorPoint 0.5/0.5) — wzór banknotu
--   HUD.CashSparkTemplate (GuiObject, Visible=false, opcjonalny) — wzór iskierki (wybuch na środku ekranu)
--   HUD.CashRingTemplate (GuiObject, Visible=false, opcjonalny) — pierścień na środku; jego Size = rozmiar końcowy
--   HUD.CashFlashTemplate (ImageLabel, opcjonalny) — miękki błysk na środku; Size = rozmiar końcowy
--   HUD.CashRayTemplate (GuiObject, opcjonalny) — promień; Size.Y = długość, pionowo
--   HUD.CashTwinkleTemplate (GuiObject + UIScale, opcjonalny) — migocząca gwiazdka wokół środka
--   HUD.Cash … Glow (GuiObject, opcjonalny) — poświata za ikoną, błyska przy dolocie
--   HUD.Cash … CashLabelShine (TextLabel, opcjonalny) — połysk: kopia napisu NA WIERZCHU, jasna,
--     z `UIGradient` przezroczystości (wąski pas). Przy dolocie banknotu jeden przejazd `Offset.X`
--     −1 → 1 (decyzja Kacpra 10.10: połysk TYLKO przy zbieraniu). W spoczynku pas jest poza
--     napisem = niewidoczny. Osobna warstwa od 11.10: kolor `CashLabel` to pionowy gradient
--     (góra jaśniejsza, dół ciemniejszy), którego przesuwanie zepsułoby kolor. Tekst kopiuje `writeText`.
--   Bez wzoru albo ikony liczba dalej rośnie płynnie, tylko bez banknotów.
--
-- STAN: `balance` — ostatnia wartość z serwera; `pending` — ile z zarobków jeszcze leci
-- (banknoty w powietrzu); liczba zmierza do `balance - pending`. Dzięki temu wydatek w trakcie
-- lotu nie psuje animacji: cel od razu spada o wydatek, a doloty dokładają resztę.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local CFG = Config.Cash.Fly
local UI = Config.UI

local CashCounterController = {}

local localPlayer = Players.LocalPlayer

local known = false
local balance = 0
local pending = 0
local inFlight = 0
local shown = 0
local lastWritten: number? = nil
local tiltSign = 1

local hud: ScreenGui? = nil
local label: TextLabel? = nil
local icon: GuiObject? = nil
local pop: UIScale? = nil
local template: ImageLabel? = nil
local sparkTemplate: GuiObject? = nil
local ringTemplate: GuiObject? = nil
local flashTemplate: GuiObject? = nil
local rayTemplate: GuiObject? = nil
local twinkleTemplate: GuiObject? = nil
local glow: GuiObject? = nil
local shine: UIGradient? = nil
local shineLabel: TextLabel? = nil
local shining = false
local initialized = false

local function target(): number
	return balance - pending
end

local function writeText()
	local value = math.floor(shown + 0.5)
	if value == lastWritten or not label then return end
	lastWritten = value
	label.Text = tostring(value) .. "$"
	if shineLabel then
		shineLabel.Text = label.Text
	end
end

local function notesFor(amount: number): number
	for _, row in ipairs(CFG.Notes) do
		if amount >= row[1] then
			return row[2]
		end
	end
	return 1
end

-- Skala HUD-u z tego samego wzoru co HudScaleController — rozrzut startu jest w px projektu.
local function hudFactor(screen: ScreenGui): number
	return math.clamp(screen.AbsoluteSize.Y / UI.ReferenceHeight, UI.MinScale, UI.MaxScale)
end

-- Błysk poświaty za ikoną przy dolocie banknotu. Iskierki z ikony USUNIĘTE 10.10 wieczór
-- (Kacper: „nikt nie patrzy w róg podczas gry”) — efekty są na środku ekranu (`centerBurst`).
local function glowFlash()
	local g = glow
	if g then
		g.BackgroundTransparency = CFG.GlowAlpha
		TweenService:Create(g, TweenInfo.new(CFG.GlowTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end
end

-- Efekt zarobku na ŚRODKU ekranu, tam gdzie wyskakują banknoty (Kacper 10.10 wieczór: „nikt nie
-- patrzy w róg”, potem „ulepsz 5×”). Warstwy, każda z wzoru w HUD (brak wzoru = bez tej warstwy):
--   błysk `CashFlashTemplate` → promienie `CashRayTemplate` → dwa pierścienie `CashRingTemplate`
--   → iskierki `CashSparkTemplate` (wylot + opadanie) → gwiazdki `CashTwinkleTemplate` wokół.
-- Wszystko w JEDNYM kontenerze na środku: HudScaleController daje mu skalę raz, a w środku
-- pozycje są w px projektu (środek kontenera = (0, 0)). Więcej banknotów = więcej iskier/promieni.
local function fxClone(tpl: GuiObject, parent: Instance, name: string): GuiObject
	local c = tpl:Clone()
	c.Name = name
	c.Visible = true
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromOffset(0, 0)
	c.Parent = parent
	return c
end

local function centerBurst(notes: number)
	local screen = hud
	if not screen then return end
	local box = Instance.new("Frame")
	box.Name = "CashFX"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(0, 0)
	box.ZIndex = 0 -- pod banknotami (wyskakują w tym samym miejscu)
	box.Parent = screen
	local extra = notes - 1

	-- 1. Błysk: miękkie koło rośnie i gaśnie
	local flashTpl = flashTemplate
	if flashTpl and flashTpl:IsA("ImageLabel") then
		local flash = fxClone(flashTpl, box, "Flash") :: ImageLabel
		local full = flashTpl.Size
		flash.Size = UDim2.fromOffset(full.X.Offset * 0.35, full.Y.Offset * 0.35)
		TweenService:Create(flash, TweenInfo.new(CFG.FlashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = full, ImageTransparency = 1,
		}):Play()
	end

	-- 2. Promienie: wystrzeliwują z centrum jak gwiazda, wydłużają się i gasną
	local rayTpl = rayTemplate
	if rayTpl then
		local count = CFG.RayCount + CFG.RayPerNote * extra
		local len = rayTpl.Size.Y.Offset
		local width = rayTpl.Size.X.Offset
		local info = TweenInfo.new(CFG.RayTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local spin = math.random() * math.pi * 2
		for k = 1, count do
			local angle = spin + (k / count) * math.pi * 2 + (math.random() - 0.5) * 0.25
			local dir = Vector2.new(math.cos(angle), math.sin(angle))
			local l = len * (0.65 + math.random() * 0.55)
			local ray = fxClone(rayTpl, box, "Ray")
			-- Rotation obraca wokół środka paska; 0° = pionowo, więc +90° od kąta kierunku.
			ray.Rotation = math.deg(angle) + 90
			local p0 = dir * CFG.RayInner
			ray.Position = UDim2.fromOffset(p0.X, p0.Y)
			ray.Size = UDim2.fromOffset(width, l * 0.15)
			local p1 = dir * (CFG.RayInner + l * 0.75)
			TweenService:Create(ray, info, {
				Position = UDim2.fromOffset(p1.X, p1.Y),
				Size = UDim2.fromOffset(width * 0.35, l),
				BackgroundTransparency = 1,
			}):Play()
		end
	end

	-- 3. Pierścienie: drugi z opóźnieniem i większy
	local ringTpl = ringTemplate
	if ringTpl then
		for k = 0, 1 do
			task.delay(k * CFG.RingGap, function()
				if not box.Parent then return end
				local ring = fxClone(ringTpl, box, "Ring")
				local full = ringTpl.Size
				local mult = 1 + k * 0.45
				ring.Size = UDim2.fromOffset(0, 0)
				local info = TweenInfo.new(CFG.RingTime * (1 + k * 0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local stroke = ring:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Thickness *= (1 - k * 0.4)
					TweenService:Create(stroke, info, { Transparency = 1, Thickness = stroke.Thickness * 0.2 }):Play()
				end
				TweenService:Create(ring, info, {
					Size = UDim2.fromOffset(full.X.Offset * mult, full.Y.Offset * mult),
				}):Play()
			end)
		end
	end

	-- 4. Iskierki: szybki wylot, potem opadanie i znikanie
	local tpl = sparkTemplate
	if tpl then
		local count = CFG.SparkCount + CFG.SparkPerNote * extra
		local outInfo = TweenInfo.new(CFG.SparkTime * 0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		local fallInfo = TweenInfo.new(CFG.SparkTime * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for k = 1, count do
			local angle = (k / count) * math.pi * 2 + (math.random() - 0.5) * 0.5
			local dist = CFG.SparkDistance * (0.5 + math.random() * 0.7)
			local goal = Vector2.new(math.cos(angle), math.sin(angle)) * dist
			local size = CFG.SparkScaleMin + math.random() * (CFG.SparkScaleMax - CFG.SparkScaleMin)
			local spark = fxClone(tpl, box, "Spark")
			local w, h = tpl.Size.X.Offset * size, tpl.Size.Y.Offset * size
			spark.Size = UDim2.fromOffset(w, h)
			local out = TweenService:Create(spark, outInfo, {
				Position = UDim2.fromOffset(goal.X, goal.Y),
				Rotation = spark.Rotation + (math.random() * 2 - 1) * 200,
			})
			out.Completed:Once(function()
				if not spark.Parent then return end
				TweenService:Create(spark, fallInfo, {
					Position = UDim2.fromOffset(goal.X + (math.random() - 0.5) * 30, goal.Y + CFG.SparkFall * (0.6 + math.random() * 0.8)),
					Size = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
				}):Play()
			end)
			out:Play()
		end
	end

	-- 5. Gwiazdki: migoczą w losowych miejscach wokół środka, z opóźnieniem
	local twTpl = twinkleTemplate
	if twTpl then
		local count = CFG.TwinkleCount + extra
		for _ = 1, count do
			task.delay(math.random() * CFG.TwinkleSpread, function()
				if not box.Parent then return end
				local angle = math.random() * math.pi * 2
				local r = CFG.TwinkleMinRadius + math.random() * (CFG.TwinkleMaxRadius - CFG.TwinkleMinRadius)
				local tw = fxClone(twTpl, box, "Twinkle")
				tw.Position = UDim2.fromOffset(math.cos(angle) * r, math.sin(angle) * r)
				tw.Rotation = math.random() * 45
				local pop = tw:FindFirstChildOfClass("UIScale")
				if not pop then return end
				local peak = 0.6 + math.random() * 0.7
				pop.Scale = 0
				local half = CFG.TwinkleTime * 0.5
				local up = TweenService:Create(pop, TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = peak })
				up.Completed:Once(function()
					if not tw.Parent then return end
					TweenService:Create(pop, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
					TweenService:Create(tw, TweenInfo.new(half), { Rotation = tw.Rotation + 90 }):Play()
				end)
				up:Play()
			end)
		end
	end

	-- Sprzątanie całego wybuchu naraz — najdłuższa warstwa + zapas.
	local life = math.max(CFG.FlashTime, CFG.RayTime, CFG.RingGap + CFG.RingTime * 1.3, CFG.SparkTime,
		CFG.TwinkleSpread + CFG.TwinkleTime) + 0.1
	task.delay(life, function()
		box:Destroy()
	end)
end

local function bump()
	local p = pop
	if p then
		p.Scale = CFG.PopScale
		TweenService:Create(p, TweenInfo.new(CFG.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	-- Ikona „łapie” banknot: przechył i sprężysty powrót (na przemian w lewo / w prawo).
	local ic = icon
	if ic then
		tiltSign = -tiltSign
		ic.Rotation = CFG.IconTilt * tiltSign
		TweenService:Create(ic, TweenInfo.new(CFG.PopTime * 1.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	end
end

-- Jeden przejazd połysku. Kolejne banknoty tego samego zarobku (co `Stagger`) nie restartują
-- przejazdu w połowie — to by szarpało; następny zarobek po skończeniu da kolejny.
local function sweep()
	local g = shine
	if not g or shining then return end
	shining = true
	local y = g.Offset.Y
	g.Offset = Vector2.new(-1, y)
	local tween = TweenService:Create(g, TweenInfo.new(CFG.ShineTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Offset = Vector2.new(1, y),
	})
	tween.Completed:Once(function()
		g.Offset = Vector2.new(-1, y)
		shining = false
	end)
	tween:Play()
end

local function arrive(share: number)
	inFlight -= 1
	pending -= share
	-- Ostatni banknot zamyka rachunek — bez dryfu z dzielenia kwoty na banknoty.
	if inFlight <= 0 then
		inFlight = 0
		pending = 0
	end
	bump()
	glowFlash()
	sweep()
end

local function flyOne(delay: number, share: number)
	local screen, tpl, dest = hud, template, icon
	if not (screen and tpl and dest) then
		arrive(share)
		return
	end
	task.delay(delay, function()
		if not (screen.Parent and dest.Parent) then
			arrive(share)
			return
		end
		local origin = screen.AbsolutePosition
		local center = screen.AbsoluteSize * 0.5
		local factor = hudFactor(screen)
		local jitter = Vector2.new(math.random() * 2 - 1, math.random() * 2 - 1) * CFG.StartJitter * factor
		local start = center + jitter
		local goal = dest.AbsolutePosition + dest.AbsoluteSize * 0.5 - origin

		local note = tpl:Clone()
		note.Name = "CashFly"
		note.Visible = true
		note.AnchorPoint = Vector2.new(0.5, 0.5)
		note.Position = UDim2.fromOffset(start.X, start.Y)
		local fullSize = tpl.Size
		note.Size = UDim2.new(0, 0, 0, 0)
		note.Rotation = 0
		-- Do HUD-u, nie do licznika: HudScaleController dokłada mu tę samą skalę co reszcie
		-- HUD-u, a pozycje liczymy w pikselach ekranu.
		note.Parent = screen

		local appear = TweenService:Create(note, TweenInfo.new(CFG.AppearTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = fullSize,
		})
		appear:Play()
		task.wait(CFG.AppearTime + CFG.HoldTime)
		if not note.Parent then
			arrive(share)
			return
		end
		local endSize = UDim2.new(
			fullSize.X.Scale * CFG.EndScale, fullSize.X.Offset * CFG.EndScale,
			fullSize.Y.Scale * CFG.EndScale, fullSize.Y.Offset * CFG.EndScale
		)
		local fly = TweenService:Create(note, TweenInfo.new(CFG.FlyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(goal.X, goal.Y),
			Size = endSize,
			Rotation = (math.random() * 2 - 1) * CFG.Spin,
		})
		fly.Completed:Once(function()
			note:Destroy()
			arrive(share)
		end)
		fly:Play()
	end)
end

local function onCashChanged(newBalance: any, delta: any)
	if typeof(newBalance) ~= "number" then return end
	-- Pierwszy stan (wczytanie danych, dołączenie) — bez animacji, licznik po prostu pokazuje kwotę.
	if not known or typeof(delta) ~= "number" then
		known = true
		balance = newBalance
		pending = 0
		shown = newBalance
		writeText()
		return
	end
	balance = newBalance
	if delta > 0 then
		local n = notesFor(delta)
		centerBurst(n)
		pending += delta
		inFlight += n
		local share = delta / n
		for i = 1, n do
			flyOne((i - 1) * CFG.Stagger, share)
		end
	elseif delta < 0 then
		-- Wydatek (11.10): bez banknotów, liczba spada PŁYNNIE (step dogania nowy cel w dół tak
		-- samo jak w górę), a licznik chwieje się — wcześniej liczba skakała bez żadnego sygnału.
		-- Cel od razu spada o wydatek; doloty w locie dołożą swoje.
		local body = pop and pop.Parent
		if body and body:IsA("GuiObject") then
			body.Rotation = CFG.SpendTilt
			TweenService:Create(body, TweenInfo.new(CFG.SpendTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
				Rotation = 0,
			}):Play()
		end
	end
end

local function step(dt: number)
	local goal = target()
	if shown ~= goal then
		shown += (goal - shown) * (1 - math.exp(-CFG.CountRate * dt))
		if math.abs(goal - shown) < 0.5 then
			shown = goal
		end
		writeText()
	end
end

function CashCounterController.init()
	if initialized then return end
	initialized = true
	-- Listener PRZED czekaniem na HUD (hard rule 9): stan kasy przychodzi zaraz po wczytaniu danych.
	Remotes.CashChanged.OnClientEvent:Connect(onCashChanged)
	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local screen = playerGui:WaitForChild("HUD", 10)
		if not (screen and screen:IsA("ScreenGui")) then
			warn("[CashCounter] PlayerGui.HUD nie istnieje — licznik kasy nieaktywny")
			return
		end
		hud = screen
		local cash = screen:FindFirstChild("Cash")
		local root: Instance = cash or screen
		local l = root:FindFirstChild("CashLabel", true)
		label = if l and l:IsA("TextLabel") then l else nil
		local ic = root:FindFirstChild("Icon", true)
		icon = if ic and ic:IsA("GuiObject") then ic else nil
		local p = root:FindFirstChild("Pop", true)
		pop = if p and p:IsA("UIScale") then p else nil
		local t = screen:FindFirstChild("CashFlyTemplate")
		template = if t and t:IsA("ImageLabel") then t else nil
		local sp = screen:FindFirstChild("CashSparkTemplate")
		sparkTemplate = if sp and sp:IsA("GuiObject") then sp else nil
		local rg = screen:FindFirstChild("CashRingTemplate")
		ringTemplate = if rg and rg:IsA("GuiObject") then rg else nil
		local fl = screen:FindFirstChild("CashFlashTemplate")
		flashTemplate = if fl and fl:IsA("GuiObject") then fl else nil
		local ry = screen:FindFirstChild("CashRayTemplate")
		rayTemplate = if ry and ry:IsA("GuiObject") then ry else nil
		local tw = screen:FindFirstChild("CashTwinkleTemplate")
		twinkleTemplate = if tw and tw:IsA("GuiObject") then tw else nil
		local gl = root:FindFirstChild("Glow", true)
		glow = if gl and gl:IsA("GuiObject") then gl else nil
		if not label then
			warn("[CashCounter] brak HUD.Cash…CashLabel — licznik kasy nieaktywny")
		end
		local sl = root:FindFirstChild("CashLabelShine", true)
		shineLabel = if sl and sl:IsA("TextLabel") then sl else nil
		local g = shineLabel and shineLabel:FindFirstChildOfClass("UIGradient")
		if g then
			g.Offset = Vector2.new(-1, g.Offset.Y)
			shine = g
		end
		lastWritten = nil
		writeText()
	end)
end

return CashCounterController
