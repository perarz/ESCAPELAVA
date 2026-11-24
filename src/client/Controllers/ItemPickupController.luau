--!strict
-- ItemPickupController.luau (13.11) — itemy leżące na mapie, strona klienta.
--
-- Serwer (ItemPickupService) stawia zakotwiczone modele w `Workspace.ActiveItemPickups` i sam
-- rozstrzyga podniesienie (prompt E). Tutaj tylko wygląd:
--   * kołysanie i obrót leżących itemów — lokalnie, faza z pozycji (każdy widzi to samo),
--     bez replikacji co klatkę;
--   * lot podniesionego itemu do gracza (u wszystkich, `Remotes.ItemPickedUp`);
--   * komunikat „+1 RPG” / „READY IN SLOT 2” albo „SAVED TO INVENTORY” u podnoszącego.
--
-- KONTRAKT UI (Studio): `HUD.PickupMessage` (Visible=false, pokazuje kod), w środku
--   `ItemLabel` (TextLabel) — „+1 RPG”, `InfoLabel` (TextLabel) — slot / inventory,
--   `Pop` (UIScale, opcjonalny) — wskok. Cienie `<Nazwa>Shadow` obsługuje TextShadowController.
--   Brak UI = itemy działają, tylko bez komunikatu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local LoadoutState = require(script.Parent.LoadoutState)
local SettingsState = require(script.Parent.SettingsState)
local ItemPickupFx = require(script.Parent.ItemPickupFx)

local CFG = Config.ItemPickup
local MSG = CFG.Message

local ItemPickupController = {}

local localPlayer = Players.LocalPlayer

-- center = środek bryły w chwili postawienia; offset = pivot względem środka (pivot modelu
-- z ręki bywa w uchwycie, a obracać ma się wokół środka). Liczone przy pierwszej klatce, a nie
-- w ChildAdded: przy streamingu części modelu mogą dojść chwilę po samym modelu.
-- burstFrom/burstAt (24.11): item wysypany ze skrzyni zrzutu leci łukiem na swoje miejsce.
type Tracked = {
	center: Vector3?, offset: CFrame?, phase: number, fx: ItemPickupFx.Handle?,
	burstFrom: Vector3?, burstAt: number,
}
local tracked: { [Model]: Tracked } = {}

local root: GuiObject? = nil
local itemLabel: TextLabel? = nil
local infoLabel: TextLabel? = nil
local pop: UIScale? = nil
local fadeTargets: { { inst: Instance, prop: string, base: number } } = {}
local fading: { Tween } = {}
local shownAt = 0
local initialized = false

-- ── Leżące itemy ─────────────────────────────────────────────────────────────

local function track(child: Instance)
	if not child:IsA("Model") then return end
	-- Faza z pozycji: deterministyczna, więc u wszystkich graczy item kołysze się tak samo.
	tracked[child] = { center = nil, offset = nil, phase = 0, fx = nil, burstFrom = nil, burstAt = 0 }
end

local lowGraphics = false
local outlineAcc = 0

local function untrack(model: Model)
	local info = tracked[model]
	if info and info.fx then ItemPickupFx.detach(info.fx) end
	tracked[model] = nil
end

-- Obrys tylko na najbliższych (limit Highlightów silnika) — przeliczane kilka razy na sekundę.
local function refreshOutlines(dt: number)
	outlineAcc += dt
	if outlineAcc < 1 / CFG.FX.OutlineUpdateHz then return end
	outlineAcc = 0
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local handles: { ItemPickupFx.Handle } = {}
	for _, info in pairs(tracked) do
		if info.fx then table.insert(handles, info.fx) end
	end
	ItemPickupFx.updateOutlines(handles, cam.CFrame.Position)
end

local function animate(dt: number)
	if next(tracked) == nil then return end
	local t = os.clock()
	for model, info in pairs(tracked) do
		if not model.Parent then
			untrack(model)
			continue
		end
		local center, offset = info.center, info.offset
		if not (center and offset) then
			if not model.PrimaryPart then continue end
			local box = model:GetBoundingBox()
			center = box.Position
			offset = CFrame.new(box.Position):Inverse() * model:GetPivot()
			info.center, info.offset = center, offset
			-- Faza z pozycji: deterministyczna, więc u wszystkich item kołysze się tak samo.
			info.phase = (box.Position.X * 0.37 + box.Position.Z * 0.61) % (math.pi * 2)
			local itemId = model:GetAttribute("ItemId")
			if type(itemId) == "string" then
				info.fx = ItemPickupFx.attach(model, itemId, box.Position, lowGraphics)
			end
			local from, at = model:GetAttribute("BurstFrom"), model:GetAttribute("BurstAt")
			if typeof(from) == "Vector3" and type(at) == "number" then
				info.burstFrom, info.burstAt = from, at
			end
		end
		local bob = math.sin(t * CFG.HoverFrequency * math.pi * 2 + info.phase) * CFG.HoverAmplitude
		local spin = CFrame.Angles(0, t * CFG.SpinSpeed + info.phase, 0)
		local pos = (center :: Vector3) + Vector3.new(0, bob, 0)
		local from = info.burstFrom
		if from then
			local a = (Workspace:GetServerTimeNow() - info.burstAt) / CFG.BurstTime
			if a >= 1 then
				info.burstFrom = nil
			else
				a = math.max(a, 0)
				pos = from:Lerp(pos, a) + Vector3.new(0, math.sin(a * math.pi) * CFG.BurstHeight, 0)
			end
		end
		model:PivotTo(CFrame.new(pos) * spin * (offset :: CFrame))
	end
	refreshOutlines(dt)
end

-- ── Lot do gracza ────────────────────────────────────────────────────────────

local function makeGhost(itemId: string): Model?
	local def = ItemDefinitions.get(itemId)
	local template = def and def.toolModel and ReplicatedStorage:FindFirstChild(def.toolModel)
	if not (template and template:IsA("Model")) then return nil end
	local ghost = template:Clone()
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	local _, size = ghost:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		ghost:ScaleTo(ghost:GetScale() * math.clamp((CFG.Sizes[itemId] or CFG.DisplaySize) / longest, CFG.MinScale, CFG.MaxScale))
	end
	return ghost
end

local function flyToPlayer(player: Player, itemId: string, fromPos: Vector3)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return end
	local ghost = makeGhost(itemId)
	if not ghost then return end
	local startScale = ghost:GetScale()
	local function place(pos: Vector3)
		local box = ghost:GetBoundingBox()
		ghost:PivotTo(ghost:GetPivot() + (pos - box.Position))
	end
	place(fromPos)
	ghost.Parent = Workspace

	local started = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - started) / CFG.FlyTime, 0, 1)
		-- Cel liczony co klatkę: gracz biegnie, item ma trafić w niego, nie w miejsce startu.
		local target = if hrp.Parent then hrp.Position else fromPos
		local eased = a * a
		ghost:ScaleTo(startScale * (1 - 0.7 * eased))
		place(fromPos:Lerp(target, eased) + Vector3.new(0, math.sin(a * math.pi) * 2, 0))
		if a >= 1 then
			if conn then conn:Disconnect() end
			ghost:Destroy()
		end
	end)
end

-- ── Komunikat u podnoszącego ─────────────────────────────────────────────────

local function collectFadeTargets(gui: Instance)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") then
			table.insert(fadeTargets, { inst = d, prop = "TextTransparency", base = d.TextTransparency })
		elseif d:IsA("ImageLabel") then
			table.insert(fadeTargets, { inst = d, prop = "ImageTransparency", base = d.ImageTransparency })
		elseif d:IsA("UIStroke") then
			table.insert(fadeTargets, { inst = d, prop = "Transparency", base = d.Transparency })
		end
	end
end

local function showMessage(itemId: string)
	local gui = root
	if not gui then return end
	local def = ItemDefinitions.get(itemId)
	local name = if def then string.upper(def.name) else string.upper(itemId)
	local slot = LoadoutState.slotOf(itemId)
	if itemLabel then itemLabel.Text = ("+1 %s"):format(name) end
	if infoLabel then
		infoLabel.Text = if slot then MSG.SlotText:format(slot) else MSG.InventoryText
	end

	for _, tw in ipairs(fading) do tw:Cancel() end
	table.clear(fading)
	for _, t in ipairs(fadeTargets) do
		(t.inst :: any)[t.prop] = t.base
	end
	gui.Visible = true
	if pop then
		pop.Scale = MSG.PopScale
		TweenService:Create(pop, TweenInfo.new(MSG.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	shownAt += 1
	local token = shownAt
	task.delay(MSG.ShowTime, function()
		if token ~= shownAt then return end
		local ti = TweenInfo.new(MSG.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, t in ipairs(fadeTargets) do
			local tw = TweenService:Create(t.inst, ti, { [t.prop] = 1 })
			table.insert(fading, tw)
			tw:Play()
		end
		task.delay(MSG.FadeTime, function()
			if token == shownAt then gui.Visible = false end
		end)
	end)
end

local function playSound()
	if CFG.SoundId == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = CFG.SoundId
	s.Volume = CFG.SoundVolume
	SoundService:PlayLocalSound(s)
	task.delay(3, function() s:Destroy() end)
end

function ItemPickupController.init()
	if initialized then return end
	initialized = true

	-- Listener PRZED każdym WaitForChild (hard rule 9).
	Remotes.ItemPickedUp.OnClientEvent:Connect(function(player: Player?, itemId: string?, fromPos: Vector3?)
		if typeof(player) ~= "Instance" or not (player :: Instance):IsA("Player") then return end
		if type(itemId) ~= "string" or typeof(fromPos) ~= "Vector3" then return end
		flyToPlayer(player :: Player, itemId, fromPos :: Vector3)
		if player == localPlayer then
			showMessage(itemId)
			playSound()
		end
	end)

	RunService.RenderStepped:Connect(animate)

	-- GRAPHICS LOW: mniej drobinek aury (obrys, światło i snop zostają — są tanie).
	local function applyQuality()
		lowGraphics = SettingsState.get("graphics") == "low"
		for _, info in pairs(tracked) do
			if info.fx then ItemPickupFx.setLowGraphics(info.fx, lowGraphics) end
		end
	end
	SettingsState.onChanged(applyQuality)
	applyQuality()

	task.spawn(function()
		local folder = Workspace:WaitForChild("ActiveItemPickups")
		for _, c in ipairs(folder:GetChildren()) do track(c) end
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(function(c)
			if c:IsA("Model") then untrack(c) end
		end)
	end)

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("HUD")
		local gui = hud:WaitForChild("PickupMessage", 5)
		if not (gui and gui:IsA("GuiObject")) then
			warn("[ItemPickupController] HUD.PickupMessage nie istnieje — komunikat podniesienia wyłączony")
			return
		end
		local i = gui:FindFirstChild("ItemLabel", true)
		local n = gui:FindFirstChild("InfoLabel", true)
		local p = gui:FindFirstChild("Pop", true)
		itemLabel = if i and i:IsA("TextLabel") then i else nil
		infoLabel = if n and n:IsA("TextLabel") then n else nil
		pop = if p and p:IsA("UIScale") then p else nil
		collectFadeTargets(gui)
		gui.Visible = false
		root = gui
	end)
end

return ItemPickupController
