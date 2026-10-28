--!strict
-- RpgController.luau (20.10) — kliencka strona RPG. Dwie role:
--   1. Tool.Activated na `RpgTool` → FireRpg(punkt, w który celuje mysz)
--   2. Remotes.RocketFired → KOPIA rakiety u siebie, lecąca po tej samej prostej co rakieta
--      serwera; Remotes.RocketExploded → kopia znika (wybuch rysuje ExplosionFXController z BlastFX)
--   3. (24.10) Celowanie na PPM / L2: zoom, ciało w stronę celu (MovementController.setAim)
--      i celownik `HUD.Crosshair`; strzał z celowania leci w środek celownika.
--
-- Kopia to czysta kosmetyka: zero kolizji, zapytań i dotyku (lekcja 10 — nic, co istnieje tylko
-- u jednego klienta, nie może wpływać na grę) i `Locked = true` (bez tego DebrisFXController
-- próbkuje z niej kolory — pułapka liny haka). Pozycję liczymy z CZASU SERWERA (`firedAt`),
-- więc kopia nie spóźnia się o ping i znika tam, gdzie wybucha prawdziwa.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local RagdollState = require(script.Parent.RagdollState)
local ItemEquipController = require(script.Parent.ItemEquipController)
local CooldownBarController = require(script.Parent.CooldownBarController)
local MovementController = require(script.Parent.MovementController)

local ToolActivation = require(script.Parent.ToolActivation)

local RpgController = {}

local CFG = Config.Rpg
local TOOL_NAME = "RpgTool"
local localPlayer = Players.LocalPlayer
local lastFireAt = 0

-- Ten sam gate co hak i bomba (serwer i tak odrzuci strzał poza rundą).
local gameState = ""
Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
	gameState = newState
end)

type Visual = {
	part: BasePart,
	origin: Vector3,
	dir: Vector3,
	speed: number,
	firedAt: number,
	deadline: number,
	align: CFrame,
}

local visuals: { [number]: Visual } = {}

-- ── Wzór rakiety ─────────────────────────────────────────────────────────────────────
-- Głowica z modelu wyrzutni. `align` obraca kopię tak, żeby jej czubek (kierunek od środka
-- wyrzutni do głowicy, liczony raz z modelu) patrzył w stronę lotu.
local rocketTemplate: BasePart? = nil
local rocketAlign = CFrame.identity
local templateTried = false

local function loadTemplate()
	if templateTried then return end
	templateTried = true
	local def = ItemDefinitions.get("rpg")
	local model = def and def.toolModel and ReplicatedStorage:FindFirstChild(def.toolModel)
	if not (model and model:IsA("Model")) then
		warn("[RpgController] brak modelu wyrzutni w ReplicatedStorage — rakieta bez wyglądu")
		return
	end
	local part = model:FindFirstChild(CFG.RocketPartName, true)
	if not (part and part:IsA("BasePart")) then
		warn(("[RpgController] model %s nie ma części %s — rakieta bez wyglądu")
			:format(model.Name, CFG.RocketPartName))
		return
	end
	local forward = part.Position - model:GetBoundingBox().Position
	if forward.Magnitude < 1e-3 then
		forward = part.CFrame.LookVector
	end
	local tipLocal = part.CFrame:VectorToObjectSpace(forward.Unit)
	-- Obrót, którego −Z to czubek w układzie części; jego odwrotność kładzie czubek na −Z lotu.
	rocketAlign = CFrame.lookAt(Vector3.zero, tipLocal):Inverse()
	rocketTemplate = part
end

local function makeRocket(): BasePart?
	loadTemplate()
	local template = rocketTemplate
	if not template then return nil end
	local part = template:Clone()
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("JointInstance") or c:IsA("WeldConstraint") then c:Destroy() end
	end
	part.Name = "RpgRocket"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Locked = true
	part.Massless = true

	-- Smuga: dwa punkty w poprzek rakiety, Trail między nimi.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, CFG.TrailWidth * 0.5, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -CFG.TrailWidth * 0.5, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = CFG.TrailLifetime
	trail.Color = ColorSequence.new(CFG.TrailColor)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 0.3
	trail.FaceCamera = true
	trail.Parent = part
	return part
end

local function removeVisual(id: number)
	local v = visuals[id]
	if not v then return end
	visuals[id] = nil
	-- Smuga gaśnie po swoim Lifetime, a nie znika razem z rakietą.
	v.part.Transparency = 1
	task.delay(CFG.TrailLifetime, function()
		v.part:Destroy()
	end)
end

local function placeVisual(v: Visual, now: number)
	local t = math.max(0, now - v.firedAt)
	local pos = v.origin + v.dir * (v.speed * t)
	v.part.CFrame = CFrame.lookAt(pos, pos + v.dir) * v.align
end

local function update()
	if next(visuals) == nil then return end
	local now = Workspace:GetServerTimeNow()
	for id, v in pairs(visuals) do
		if now > v.deadline then
			removeVisual(id)
		else
			placeVisual(v, now)
		end
	end
end

-- ── Odrzut (21.10) ───────────────────────────────────────────────────────────────────
-- Kacper: szarpnięcie kamery + błysk z przodu i dym z tyłu + wyrzutnia w ręce, „mocno”.
-- Kamera tylko u strzelca; reszta u wszystkich, bo RocketFired dostaje każdy klient. Sam
-- efekt, zero wpływu na grę: części bez kolizji/zapytań/dotyku, `Locked` (lekcja 10).
local RC = CFG.Recoil
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"

local function fxAnchor(pos: Vector3, life: number): Attachment
	local p = Instance.new("Part")
	p.Name = "RpgRecoilFX"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Locked = true
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(pos)
	local a = Instance.new("Attachment")
	a.Parent = p
	p.Parent = Workspace
	task.delay(life, function() p:Destroy() end)
	return a
end

local function burst(at: Attachment, texture: string, color: Color3, count: number, size: number,
	life: number, speed: number, dir: Vector3, emission: number)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = emission
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Drag = 4
	e.Rate = 0
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Rotation = NumberRange.new(0, 360)
	-- Kierunek emisji = oś Y attachmentu.
	at.CFrame = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(-math.pi / 2, 0, 0)
	e.Parent = at
	e:Emit(count)
end

local function muzzleOf(shooter: Player, origin: Vector3, dir: Vector3): (Vector3, Vector3)
	local char = shooter.Character
	local tool = char and char:FindFirstChild(TOOL_NAME)
	local head = tool and tool:FindFirstChild(CFG.RocketPartName, true)
	if head and head:IsA("BasePart") then
		local front = head.Position + dir * (head.Size.Magnitude * 0.5)
		return front, front - dir * RC.LauncherLength
	end
	-- Ostatnia rakieta: wyrzutnia mogła już zniknąć z ręki — liczymy od startu lotu.
	return origin + dir * 2, origin - dir * (RC.LauncherLength - 2)
end

local function playMuzzle(shooter: Player, origin: Vector3, dir: Vector3)
	local front, back = muzzleOf(shooter, origin, dir)
	local life = RC.SmokeLifetime + 0.2
	local fa = fxAnchor(front, life)
	burst(fa, FIRE_TEXTURE, RC.FlashColor, 6, RC.FlashSize, RC.FlashTime * 2, 6, dir, 1)
	local light = Instance.new("PointLight")
	light.Color = RC.FlashColor
	light.Range = RC.FlashLight
	light.Brightness = 6
	light.Parent = fa.Parent
	task.delay(RC.FlashTime, function() light:Destroy() end)
	burst(fxAnchor(front, life), SMOKE_TEXTURE, RC.SmokeColor, RC.FrontSmoke, RC.SmokeSize,
		RC.SmokeLifetime, RC.SmokeSpeed * 0.5, dir, 0)
	local ba = fxAnchor(back, life)
	burst(ba, FIRE_TEXTURE, RC.FlashColor, 4, RC.FlashSize * 0.8, RC.FlashTime * 2, 8, -dir, 1)
	burst(fxAnchor(back, life), SMOKE_TEXTURE, RC.SmokeColor, RC.BackSmoke, RC.SmokeSize * 1.2,
		RC.SmokeLifetime, RC.SmokeSpeed, -dir, 0)
end

-- Kop ręki: ta sama technika co gest łyku / ItemEquipController — nakładka na
-- `Motor6D.Transform` zdejmowana w PreAnimation i kładziona po Animatorze w PreSimulation.
-- Tu DODAWANA do pozy chodu (base * obrót), bo wyrzutnia zostaje w ręce.
type Kick = { started: number, shoulder: Motor6D, elbow: Motor6D, written: { [Motor6D]: { base: CFrame?, w: CFrame? } } }
local kicks: { [Player]: Kick } = {}

local function restoreKick(k: Kick)
	for motor, rec in pairs(k.written) do
		if motor.Parent and rec.base and rec.w and motor.Transform == rec.w then motor.Transform = rec.base end
		rec.base, rec.w = nil, nil
	end
end

local function startKick(shooter: Player)
	local char = shooter.Character
	if not char then return end
	local sh, el
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			if d.Name == "RightShoulder" then sh = d elseif d.Name == "RightElbow" then el = d end
		end
	end
	if not (sh and el) then return end
	local old = kicks[shooter]
	if old then restoreKick(old) end
	kicks[shooter] = { started = os.clock(), shoulder = sh, elbow = el, written = { [sh] = {}, [el] = {} } }
end

local function updateKicks()
	if next(kicks) == nil then return end
	local now = os.clock()
	for player, k in pairs(kicks) do
		local t = now - k.started
		if t >= RC.ArmTime or not k.shoulder.Parent or not k.shoulder.Enabled
			or not k.elbow.Parent or not k.elbow.Enabled then
			restoreKick(k)
			kicks[player] = nil
			continue
		end
		-- Szybkie wychylenie, potem spokojny powrót.
		local w = if t < RC.ArmAttack then t / RC.ArmAttack
			else (1 - (t - RC.ArmAttack) / (RC.ArmTime - RC.ArmAttack)) ^ 2
		-- Rekordy żyją tyle co gest, zamiast powstawać po trzy tabele na klatkę.
		for motor, rec in pairs(k.written) do
			local deg = if motor == k.shoulder then RC.ArmShoulder else RC.ArmElbow
			local base = motor.Transform
			local result = base * CFrame.Angles(math.rad(deg * w), 0, 0)
			rec.base, rec.w = base, result
			motor.Transform = result
		end
	end
end

-- ── Celowanie (24.10) ────────────────────────────────────────────────────────────────
-- Stan liczony CO KLATKĘ z warunków (trzymany PPM/L2 + RPG w ręce + żywy, bez ragdolla,
-- runda), a nie z osobnych zdarzeń: zdjęcie wyrzutni, ostatnia rakieta, ragdoll, śmierć
-- i koniec rundy kończą celowanie same, bez listy hooków, z której łatwo coś wypaść.
local AIM = CFG.Aim
local aimHeld = false
local aiming = false
local crosshair: GuiObject? = nil
local crosshairPop: UIScale? = nil
local crosshairWarned = false
local popTween: Tween? = nil
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function isAimInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.ButtonL2
end

-- Celownik stawia Kacper w Studio (`HUD.Crosshair`, kontrakt w STUDIO_CONTRACT). Brak = celowanie
-- działa dalej, strzał leci w środek ekranu — tylko bez kresek.
local function getCrosshair(): GuiObject?
	if crosshair and crosshair.Parent then return crosshair end
	local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local found = hud and hud:FindFirstChild(AIM.CrosshairName)
	if not (found and found:IsA("GuiObject")) then
		if not crosshairWarned then
			crosshairWarned = true
			warn(("[RpgController] brak HUD.%s — celowanie bez celownika"):format(AIM.CrosshairName))
		end
		return nil
	end
	crosshair = found
	local body = found:FindFirstChild("Body")
	local pop = body and body:FindFirstChild("Pop")
	crosshairPop = if pop and pop:IsA("UIScale") then pop else nil
	return found
end

local function popCrosshair(from: number, style: Enum.EasingStyle)
	local scale = crosshairPop
	if not scale then return end
	if popTween then popTween:Cancel() end
	scale.Scale = from
	popTween = TweenService:Create(scale, TweenInfo.new(AIM.PopTime, style, Enum.EasingDirection.Out), { Scale = 1 })
	popTween:Play()
end

local function canAim(): boolean
	if gameState ~= "" and gameState ~= "ROUND" then return false end
	local char = localPlayer.Character
	if not (char and char:FindFirstChild(TOOL_NAME)) then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not RagdollState.isRagdolled(hum)
end

local function setAiming(on: boolean)
	if on == aiming then return end
	aiming = on
	MovementController.setAim(if on then AIM.Profile else nil)
	-- Kursor zostaje tam, gdzie wciśnięto PPM (kamera Robloxa blokuje go w miejscu) — przy
	-- celowaniu chowamy go, celuje się celownikiem.
	UserInputService.MouseIconEnabled = not on
	local ch = getCrosshair()
	if ch then
		ch.Visible = on
		if on then popCrosshair(AIM.ShowPop, Enum.EasingStyle.Back) end
	end
end

-- Punkt pod środkiem celownika. Promień z punktu GUI = `ScreenPointToRay` (UI_RULES: dwa
-- układy współrzędnych); bez celownika — środek ekranu.
local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local ch = crosshair
	local ray = if ch and ch.Parent
		then camera:ScreenPointToRay(ch.AbsolutePosition.X + ch.AbsoluteSize.X * 0.5,
			ch.AbsolutePosition.Y + ch.AbsoluteSize.Y * 0.5)
		else camera:ViewportPointToRay(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
	-- Promień startuje na wysokości postaci, nie przy kamerze: to, co stoi między kamerą
	-- a plecami (szyba, kolega za tobą), nie jest celem — rakieta i tak startuje z ramienia.
	local char = localPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local skip = if root and root:IsA("BasePart")
		then math.max(0, (root.Position - ray.Origin):Dot(ray.Direction)) else 0
	local origin = ray.Origin + ray.Direction * skip
	aimParams.FilterDescendantsInstances = if char then { char } else {}
	local hit = Workspace:Raycast(origin, ray.Direction * AIM.RayLength, aimParams)
	return if hit then hit.Position else origin + ray.Direction * AIM.RayLength
end

-- ── Strzał ───────────────────────────────────────────────────────────────────────────
local function onActivated()
	if gameState ~= "" and gameState ~= "ROUND" then return end
	local now = os.clock()
	if now - lastFireAt < Config.RateLimits.Rpg then return end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or RagdollState.isRagdolled(hum) then return end

	-- Z celowania w środek celownika, bez — w kursor (decyzja 24.10).
	local target: Vector3?
	if aiming then
		target = aimPoint()
	else
		local mouse = localPlayer:GetMouse()
		target = mouse.Hit and mouse.Hit.Position
	end
	if not target then return end

	lastFireAt = now
	ItemEquipController.cancel()
	Remotes.FireRpg:FireServer(target)
end



local initialized = false
function RpgController.init()
	if initialized then return end
	initialized = true

	ToolActivation.bind("RpgTool", onActivated)

	Remotes.RocketFired.OnClientEvent:Connect(function(id, shooter, origin, dir, speed, firedAt, maxTime)
		if type(id) ~= "number" or typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3"
			or type(speed) ~= "number" or type(firedAt) ~= "number" or type(maxTime) ~= "number" then
			return
		end
		if shooter == localPlayer then
			-- Pasek odnowienia dopiero po potwierdzeniu — odrzucony strzał go nie zapala.
			CooldownBarController.trigger("rpg", Config.RateLimits.Rpg)
			if RC.CameraKick > 0 then
				MovementController.cameraKick(RC.CameraKick, RC.CameraKickDecay)
			end
			MovementController.screenShake(RC.Shake, RC.ShakeTime)
			MovementController.fovKick(RC.FOVKick)
			if aiming then
				popCrosshair(AIM.FirePop, Enum.EasingStyle.Quad)
			end
		end
		if typeof(shooter) == "Instance" and shooter:IsA("Player") then
			playMuzzle(shooter, origin, dir)
			startKick(shooter)
		end
		local part = makeRocket()
		if not part then return end
		local v: Visual = {
			part = part,
			origin = origin,
			dir = dir,
			speed = speed,
			firedAt = firedAt,
			deadline = firedAt + maxTime + CFG.VisualLinger,
			align = rocketAlign,
		}
		-- Pozycja PRZED wstawieniem do świata — inaczej jedna klatka rakiety we wzorze.
		placeVisual(v, Workspace:GetServerTimeNow())
		part.Parent = Workspace
		visuals[id] = v
	end)

	Remotes.RocketExploded.OnClientEvent:Connect(function(id, _position)
		if type(id) ~= "number" then return end
		removeVisual(id)
	end)

	-- Celowanie: PPM nad przyciskiem GUI albo w czacie się nie liczy; puszczenie — zawsze.
	-- Alt-tab gubi InputEnded, stąd WindowFocusReleased (jak sprint w MovementController).
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and isAimInput(input) then aimHeld = true end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isAimInput(input) then aimHeld = false end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		aimHeld = false
	end)

	RunService.RenderStepped:Connect(function()
		setAiming(aimHeld and canAim())
		update()
	end)
	RunService.PreAnimation:Connect(function()
		for _, k in pairs(kicks) do restoreKick(k) end
	end)
	RunService.PreSimulation:Connect(updateKicks)
	Players.PlayerRemoving:Connect(function(p)
		local k = kicks[p]
		if k then restoreKick(k) end
		kicks[p] = nil
	end)
end

return RpgController
