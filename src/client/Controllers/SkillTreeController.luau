--!strict
-- SkillTreeController.luau (09.11) — drzewko umiejętności i rebirth u maga, strona gracza
-- (plan: docs/SKILLS_PLAN.md). Gracz podchodzi do maga w wieży (ProximityPrompt z SkillService),
-- kamera podjeżdża do maga, obok otwiera się StarterGui.SkillTree.
--
-- SERVER AUTHORITY: kliknięcie UNLOCK / REBIRTH to tylko prośba (Remotes.UnlockSkill, Remotes.Rebirth).
-- Stan drzewka przychodzi z serwera (Remotes.SkillsChanged) i tylko on decyduje, co jest kupione.
-- Klient liczy z niego WYGLĄD: które pole da się kliknąć i czego brakuje — żeby szary przycisk
-- od razu mówił dlaczego, bez pytania serwera. Animacja zakupu rusza dopiero po odpowiedzi.
--
-- KAMERA jak w sklepie: CameraType = Scriptable (MovementController sam wtedy odpuszcza),
-- tween jedzie po lokalnym `camBase`, a Camera.CFrame pisze jedna pętla co klatkę. Gracz nie jest
-- przenoszony — stoi przy magu z wyłączonym sterowaniem, a postacie graczy stojących przy magu
-- znikają z JEGO obrazu (inaczej stałyby w kadrze). Wszystko lokalne: nic tu nie ma kolizji
-- ani nie trafia do serwera (lekcja 10).
--
-- INNE PANELE: otwarte drzewko ustawia lokalny atrybut gracza `Config.Skills.OpenAttribute` —
-- czytają go ekwipunek, SKIP, spectate, ustawienia, sklep i kosmetyki (chowają przyciski, nie
-- otwierają się na drzewku).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local SkillDefinitions = require(ReplicatedStorage.Shared.Modules.SkillDefinitions)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local ShopController = require(script.Parent.ShopController)
local ShopFx = require(script.Parent.ShopFx)
local SkillTreeFx = require(script.Parent.SkillTreeFx)

local SkillTreeController = {}

local CFG = Config.Skills
local CAM = CFG.Camera
local TEXTS = CFG.Texts
local COLORS = CFG.Colors
local RENDER_STEP = "SkillTreeCamera"

local localPlayer = Players.LocalPlayer
local initialized = false

-- Stan z serwera (Remotes.SkillsChanged).
local owned: { [string]: boolean } = {}
local rebirths = 0
local cycle: { [string]: number } = {}
local currentCash = 0

local gui: ScreenGui? = nil
local isOpen = false
local selected = "start"
-- Prośba w drodze: "unlock" | "rebirth". Blokuje kolejne kliknięcia do odpowiedzi albo limitu czasu.
local pending: string? = nil
local pendingToken = 0
-- W trakcie rebirthu nowe (puste) drzewko przychodzi PRZED wynikiem; trzymamy stary obraz,
-- żeby sekwencja miała co gasić.
local holdRender = false
local prompts: { ProximityPrompt } = {}

-- ============================================================================
-- Stan → wygląd
-- ============================================================================

local function stateOf(node: SkillDefinitions.Node): SkillTreeFx.NodeState
	if owned[node.id] then return "owned" end
	if not SkillDefinitions.isUnlocked(node, rebirths) then return "sealed" end
	if node.requires and not owned[node.requires] then return "locked" end
	return "available"
end

local function allStates(): { [string]: SkillTreeFx.NodeState }
	local states: { [string]: SkillTreeFx.NodeState } = {}
	for _, node in ipairs(SkillDefinitions.nodes) do
		states[node.id] = stateOf(node)
	end
	return states
end

local function colorOf(node: SkillDefinitions.Node): Color3
	local branch = SkillDefinitions.branches[node.branch]
	return if branch then branch.color else SkillDefinitions.startColor
end

-- Czego brakuje do zakupu wybranego pola: nil = można kupować.
-- "owned" | "sealed" | "locked" | "requirement" | "cash"
local function blocker(node: SkillDefinitions.Node): string?
	local state = stateOf(node)
	if state ~= "available" then return state end
	local requirement = node.requirement
	if requirement and (cycle[requirement.stat] or 0) < requirement.count then return "requirement" end
	if currentCash < node.price then return "cash" end
	return nil
end

local function detailOf(node: SkillDefinitions.Node): SkillTreeFx.Detail
	local block = blocker(node)
	local requirement = node.requirement
	local detail: SkillTreeFx.Detail = {
		title = node.title,
		desc = node.desc,
		price = if block == "owned" then "" else tostring(node.price) .. "$",
		color = colorOf(node),
		buttonText = TEXTS.Unlock,
		buttonEnabled = block == nil,
	}
	if requirement and block ~= "owned" then
		local format = (TEXTS.Requirements :: any)[requirement.stat]
		detail.reqText = if format then format:format(requirement.count) else requirement.stat
		detail.reqHave = cycle[requirement.stat] or 0
		detail.reqNeed = requirement.count
	end
	if block == "owned" then
		detail.buttonText = TEXTS.Owned
	elseif block == "sealed" then
		detail.buttonText = TEXTS.BranchLocked:format(SkillDefinitions.rebirthOf(node))
	elseif block == "locked" then
		detail.buttonText = TEXTS.Locked
		local previous = node.requires and SkillDefinitions.get(node.requires)
		if previous and not requirement then
			-- Pole bez wymagania: w jego miejscu podpowiedź, co kupić najpierw (bez paska).
			detail.reqText = TEXTS.NeedPrevious:format(previous.title)
		end
	elseif block == "requirement" and requirement then
		local short = (TEXTS.RequirementShort :: any)[requirement.stat]
		if short then
			detail.buttonText = short:format(math.min(cycle[requirement.stat] or 0, requirement.count), requirement.count)
		end
	elseif block == "cash" then
		detail.buttonText = TEXTS.NoCash
	end
	return detail
end

local function refreshRebirth()
	local complete, have, need = SkillDefinitions.isComplete(owned, rebirths)
	SkillTreeFx.setRebirth(if complete then TEXTS.Rebirth else TEXTS.RebirthProgress:format(have, need), complete)
end

local function refreshDetails(animate: boolean)
	local node = SkillDefinitions.get(selected)
	if node then
		SkillTreeFx.select(node.id, detailOf(node), animate)
	end
end

local function refreshAll(animate: boolean)
	SkillTreeFx.render(allStates(), animate)
	SkillTreeFx.setBadge(TEXTS.RebirthBadge:format(rebirths), false)
	refreshRebirth()
	refreshDetails(false)
end

-- ============================================================================
-- Kasa — jak w sklepie: start z leaderstats, potem Remotes.CashChanged
-- ============================================================================

local function readCash()
	local stats = localPlayer:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		currentCash = cash.Value
	end
end

-- ============================================================================
-- Sterowanie, kamera, kadr
-- ============================================================================

local function getControls(): any
	local ok, controls = pcall(function()
		local ps = localPlayer:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if not pm then return nil end
		return (require(pm) :: any):GetControls()
	end)
	return if ok then controls else nil
end

local function setFrozen(frozen: boolean)
	local controls = getControls()
	if not controls then return end
	if frozen then controls:Disable() else controls:Enable() end
end

local function findMage(): Model?
	local tower = Workspace:FindFirstChild(CFG.TowerModelName)
	local mage = tower and tower:FindFirstChild(CFG.MageName, true)
	return if mage and mage:IsA("Model") then mage else nil
end

local function mageCenter(mage: Model): Vector3
	local box = mage:GetBoundingBox()
	return box.Position
end

-- Kadr: przed magiem, lekko z boku; przesunięcie kamery w prawo zostawia maga po lewej
-- stronie ekranu, a prawą oddaje panelowi.
local function cameraGoal(mage: Model): CFrame
	local center = mageCenter(mage)
	local look = mage:GetPivot().LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else -Vector3.zAxis
	local dir = CFrame.Angles(0, math.rad(CAM.Yaw), 0):VectorToWorldSpace(flat)
	local position = center + dir * CAM.Distance + Vector3.new(0, CAM.Height, 0)
	local target = center + Vector3.new(0, CAM.LookHeight, 0)
	return CFrame.lookAt(position, target) * CFrame.new(CAM.ShiftRight, 0, 0)
end

local camBase = Instance.new("CFrameValue")
local camTween: Tween? = nil
local savedCamType: Enum.CameraType? = nil
local mouseOffset = Vector2.zero
local cameraBound = false

-- Postacie przy magu, schowane u oglądającego. Zapamiętujemy, co schowaliśmy, i oddajemy
-- dokładnie to (LobbyVisibilityController robi podobnie z lobby — nie wchodzimy sobie w drogę,
-- bo on przełącza tylko przy kamerze nad mapą).
local hidden: { [Instance]: number } = {}
local hideCenter: Vector3? = nil
local lastScan = 0

local function hidePart(inst: Instance)
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		local target = inst :: any
		if hidden[inst] == nil then
			hidden[inst] = target.LocalTransparencyModifier
		end
		-- Co klatkę: moduł kamery Robloxa potrafi nadpisać modyfikator własnej postaci.
		target.LocalTransparencyModifier = 1
	end
end

local function scanCharacters()
	local center = hideCenter
	if not center then return end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart")
			and (root.Position - center).Magnitude <= CAM.HideRadius then
			for _, d in ipairs(character:GetDescendants()) do
				hidePart(d)
			end
		end
	end
end

local function restoreHidden()
	for inst, value in pairs(hidden) do
		if inst.Parent then
			local target = inst :: any
			if target.LocalTransparencyModifier == 1 then
				target.LocalTransparencyModifier = value
			end
		end
	end
	table.clear(hidden)
	hideCenter = nil
end

local function mouseTarget(cam: Camera): Vector2
	local last = UserInputService:GetLastInputType()
	if not UserInputService.MouseEnabled or last == Enum.UserInputType.Touch or last.Name:sub(1, 7) == "Gamepad" then
		return Vector2.zero
	end
	local point = UserInputService:GetMouseLocation()
	local size = cam.ViewportSize
	return Vector2.new(math.clamp(point.X / size.X * 2 - 1, -1, 1), math.clamp(point.Y / size.Y * 2 - 1, -1, 1))
end

local function cameraStep(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local parallax = CAM.Parallax
	mouseOffset = mouseOffset:Lerp(mouseTarget(cam), 1 - math.exp(-parallax.Rate * dt))
	cam.CFrame = camBase.Value * CFrame.Angles(
		-math.rad(parallax.PitchDegrees) * mouseOffset.Y,
		-math.rad(parallax.YawDegrees) * mouseOffset.X,
		0
	)
	-- Schowane części dostają modyfikator co klatkę, nowe postacie dochodzą co `HideRescan`.
	local now = os.clock()
	if now - lastScan >= CAM.HideRescan then
		lastScan = now
		scanCharacters()
	else
		for inst in pairs(hidden) do
			(inst :: any).LocalTransparencyModifier = 1
		end
	end
end

local function stopCamera()
	if cameraBound then
		RunService:UnbindFromRenderStep(RENDER_STEP)
		cameraBound = false
	end
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
end

-- Doświetlenie maga: przy wieży obraz jest przyciemniony (TowerAmbienceController). Lokalny
-- part bez kolizji i bez promieni, usuwany przy zamknięciu.
local fillPart: Part? = nil

local function setFill(position: Vector3?)
	if fillPart then
		fillPart:Destroy()
		fillPart = nil
	end
	if not position then return end
	local part = Instance.new("Part")
	part.Name = "SkillTreeFill"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Brightness = CAM.FillBrightness
	light.Range = CAM.FillRange
	light.Color = CAM.FillColor
	light.Shadows = false
	light.Parent = part
	part.Parent = Workspace
	fillPart = part
end

-- Błysk cząsteczek przy magu po rebirthie — czysty efekt u tego gracza.
local function mageBurst()
	local mage = findMage()
	if not mage then return end
	local part = Instance.new("Part")
	part.Name = "SkillTreeBurst"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(mageCenter(mage))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(CFG.Fx.MageBurstColor, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = part
	part.Parent = Workspace
	emitter:Emit(CFG.Fx.MageBurstCount)
	task.delay(2, function() part:Destroy() end)
end

-- ============================================================================
-- Otwieranie i zamykanie
-- ============================================================================

local function setPromptsEnabled(enabled: boolean)
	for _, prompt in ipairs(prompts) do
		if prompt.Parent then prompt.Enabled = enabled end
	end
end

local function clearPending()
	pending = nil
	pendingToken += 1
	holdRender = false
	SkillTreeFx.waiting(false)
end

-- `character` = postać, która właśnie się pojawiła (zamknięcie z CharacterAdded).
local function close(character: Model?)
	if not isOpen then return end
	isOpen = false
	clearPending()
	localPlayer:SetAttribute(CFG.OpenAttribute, false)
	SkillTreeFx.confirm(false)
	SkillTreeFx.close(function()
		if gui then gui.Enabled = false end
	end)
	setFrozen(false)
	stopCamera()
	restoreHidden()
	setFill(nil)
	setPromptsEnabled(true)
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = savedCamType or Enum.CameraType.Custom
		-- Jak w sklepie: start rundy podmienia postać przy kamerze skryptowej i Roblox nie
		-- przepina wtedy CameraSubject — robimy to sami, na aktualną postać.
		local char = character or localPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		elseif char then
			task.spawn(function()
				local h = char:WaitForChild("Humanoid", 5)
				if h and h:IsA("Humanoid") and not isOpen and localPlayer.Character == char then
					cam.CameraSubject = h
				end
			end)
		end
	end
end

local function open()
	if isOpen or not gui then return end
	if ShopController.isOpen() or localPlayer:GetAttribute("CosmeticsOpen") == true then return end
	local mage = findMage()
	local cam = Workspace.CurrentCamera
	if not mage or not cam then
		warn("[SkillTree] brak maga albo kamery — panel się nie otwiera")
		return
	end
	isOpen = true
	localPlayer:SetAttribute(CFG.OpenAttribute, true)
	readCash()

	savedCamType = cam.CameraType
	local goal = cameraGoal(mage)
	camBase.Value = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	stopCamera()
	local info = TweenInfo.new(CAM.TweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = TweenService:Create(camBase, info, { Value = goal })
	camTween = t
	t:Play()
	mouseOffset = Vector2.zero
	hideCenter = mageCenter(mage)
	lastScan = 0
	-- Po module kamery Robloxa (priorytet Camera), żeby nasz zapis był ostatni w klatce.
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, cameraStep)
	cameraBound = true
	setFill(goal.Position)

	setFrozen(true)
	setPromptsEnabled(false)
	gui.Enabled = true
	SkillTreeFx.clearStatus()
	refreshAll(false)
	SkillTreeFx.open()
end

-- ============================================================================
-- Kliknięcia
-- ============================================================================

local function startPending(kind: string)
	pending = kind
	pendingToken += 1
	local token = pendingToken
	-- Serwer po cichu odrzuca prośby ponad limit — bez tego panel czekałby w nieskończoność.
	task.delay(CFG.RequestTimeout, function()
		if token ~= pendingToken then return end
		clearPending()
		if isOpen then refreshAll(false) end
	end)
end

local function onNode(id: string)
	if not isOpen or pending or SkillTreeFx.confirmVisible() then return end
	if not SkillDefinitions.get(id) then return end
	local changed = id ~= selected
	selected = id
	SkillTreeFx.clearStatus()
	ShopFx.feedback("Press")
	refreshDetails(changed)
end

local function tryUnlock()
	if not isOpen or pending or SkillTreeFx.confirmVisible() then return end
	local node = SkillDefinitions.get(selected)
	if not node then return end
	ShopFx.feedback("Press")
	local block = blocker(node)
	if block then
		-- Klient wie, czego brakuje — odmowa od razu, bez pytania serwera.
		SkillTreeFx.failed(if block == "cash" or block == "requirement" then block else nil)
		return
	end
	startPending("unlock")
	SkillTreeFx.waiting(true)
	Remotes.UnlockSkill:FireServer(node.id)
end

-- Co da najbliższy rebirth: procent kasy, nowa odnoga, nowy item w sklepie.
local function rewardLines(nextRebirth: number): (string, string)
	local percent = math.round(CFG.RebirthCashBonus * 100)
	local extra: { string } = {}
	for _, branch in ipairs(SkillDefinitions.branchesAt(nextRebirth)) do
		table.insert(extra, TEXTS.ConfirmBranch:format(branch.title))
	end
	for _, itemId in ipairs(ItemDefinitions.shopOrder) do
		local def = ItemDefinitions.get(itemId)
		if def and (def :: any).requiresRebirth == nextRebirth then
			table.insert(extra, TEXTS.ConfirmItem)
			break
		end
	end
	return TEXTS.RewardCash:format(percent), table.concat(extra, " + ")
end

local function askRebirth()
	if not isOpen or pending or SkillTreeFx.confirmVisible() then return end
	ShopFx.feedback("Press")
	if not SkillDefinitions.isComplete(owned, rebirths) then
		SkillTreeFx.status(TEXTS.FailTexts.not_complete, COLORS.StatusFail)
		SkillTreeFx.failed(nil)
		return
	end
	local _, extra = rewardLines(rebirths + 1)
	SkillTreeFx.confirm(true, {
		Title = TEXTS.ConfirmTitle,
		Lose = TEXTS.ConfirmLose,
		Keep = TEXTS.ConfirmKeep,
		Gain = TEXTS.ConfirmGain:format(math.round(CFG.RebirthCashBonus * 100)),
		Extra = extra,
	})
end

local function confirmRebirth()
	if not isOpen or pending or not SkillTreeFx.confirmVisible() then return end
	ShopFx.feedback("Press")
	SkillTreeFx.confirm(false)
	startPending("rebirth")
	holdRender = true
	Remotes.Rebirth:FireServer()
end

local function cancelRebirth()
	ShopFx.feedback("Press")
	SkillTreeFx.confirm(false)
end

-- ============================================================================
-- Odpowiedzi serwera
-- ============================================================================

local function onSkillsChanged(ownedList: any, rebirthCount: any, stats: any)
	local newOwned: { [string]: boolean } = {}
	if type(ownedList) == "table" then
		for _, id in ipairs(ownedList) do
			if type(id) == "string" then newOwned[id] = true end
		end
	end
	owned = newOwned
	rebirths = if type(rebirthCount) == "number" then rebirthCount else 0
	local newCycle: { [string]: number } = {}
	local fromServer = if type(stats) == "table" then stats.cycle else nil
	if type(fromServer) == "table" then
		for _, stat in ipairs(SkillDefinitions.stats) do
			local value = fromServer[stat]
			newCycle[stat] = if type(value) == "number" then value else 0
		end
	end
	cycle = newCycle
	if isOpen and not holdRender then
		refreshAll(true)
	end
end

local function onSkillResult(success: any, action: any, id: any, reason: any)
	local wasRebirth = pending == "rebirth"
	clearPending()
	if not isOpen then return end
	if action == "unlock" then
		refreshAll(true)
		if success == true and type(id) == "string" then
			SkillTreeFx.bought(id)
			SkillTreeFx.status(TEXTS.Unlocked, COLORS.StatusOk)
		else
			local text = (type(reason) == "string" and (TEXTS.FailTexts :: any)[reason]) or TEXTS.FailDefault
			SkillTreeFx.status(text, COLORS.StatusFail)
			SkillTreeFx.failed(if reason == "not_enough_cash" then "cash"
				elseif reason == "requirement_not_met" then "requirement" else nil)
		end
	elseif action == "rebirth" then
		if success == true and wasRebirth then
			local cashLine, extra = rewardLines(rebirths)
			selected = "start"
			mageBurst()
			-- Do odsłonięcia nowego drzewka nic innego (kasa, statystyki) nie przerysowuje panelu.
			holdRender = true
			SkillTreeFx.rebirthSequence({
				Title = TEXTS.RewardTitle:format(rebirths),
				Line1 = cashLine,
				Line2 = extra,
			}, function()
				holdRender = false
				if not isOpen then return end
				SkillTreeFx.render(allStates(), true)
				SkillTreeFx.setBadge(TEXTS.RebirthBadge:format(rebirths), true)
				refreshRebirth()
				refreshDetails(true)
			end)
		else
			refreshAll(false)
			if success ~= true then
				local text = (type(reason) == "string" and (TEXTS.FailTexts :: any)[reason]) or TEXTS.FailDefault
				SkillTreeFx.status(text, COLORS.StatusFail)
				SkillTreeFx.failed(nil)
			end
		end
	end
end

-- ============================================================================
-- Init
-- ============================================================================

function SkillTreeController.isOpen(): boolean
	return isOpen
end

local function connectButton(root: Instance, name: string, callback: () -> ())
	local button = root:FindFirstChild(name, true)
	if button and button:IsA("GuiButton") then
		-- Owinięte: Activated podaje (InputObject, clickCount).
		button.Activated:Connect(function() callback() end)
	else
		warn(("[SkillTree] brak przycisku %s w StarterGui.SkillTree"):format(name))
	end
end

function SkillTreeController.init()
	if initialized then return end
	initialized = true
	localPlayer:SetAttribute(CFG.OpenAttribute, false)

	-- Listenery PRZED czekaniem na UI (zasada 9): stan drzewka przychodzi zaraz po `ClientReady`.
	Remotes.SkillsChanged.OnClientEvent:Connect(onSkillsChanged)
	Remotes.SkillResult.OnClientEvent:Connect(onSkillResult)
	readCash()
	Remotes.CashChanged.OnClientEvent:Connect(function(balance: any)
		if type(balance) == "number" then
			currentCash = balance
			if isOpen and not holdRender then refreshDetails(false) end
		end
	end)

	-- Nowa postać (start rundy, respawn) nie może zostać z zablokowaną kamerą i sterowaniem.
	localPlayer.CharacterAdded:Connect(function(character: Model)
		if isOpen then close(character) end
	end)
	localPlayer.CharacterRemoving:Connect(function()
		if isOpen then close() end
	end)
	-- Sklep albo kosmetyki otwarte inną drogą → drzewko ustępuje (nigdy dwa panele naraz).
	ShopController.onOpenChanged(function(shopOpen: boolean)
		if shopOpen and isOpen then close() end
	end)
	localPlayer:GetAttributeChangedSignal("CosmeticsOpen"):Connect(function()
		if localPlayer:GetAttribute("CosmeticsOpen") == true and isOpen then close() end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not isOpen or processed then return end
		if input.KeyCode == CFG.CloseKey then
			if SkillTreeFx.confirmVisible() then cancelRebirth() else close() end
		end
	end)

	-- Prompt tworzy SkillService, więc do klienta może dojechać po nas — szukamy po nazwie
	-- pod modelem wieży i słuchamy też nowych obiektów (jak sklep).
	task.spawn(function()
		local tower = Workspace:WaitForChild(CFG.TowerModelName, 30)
		if not tower then
			warn(("[SkillTree] brak Workspace.%s — drzewko nie otworzy się promptem"):format(CFG.TowerModelName))
			return
		end
		local function hook(inst: Instance)
			if not inst:IsA("ProximityPrompt") or inst.Name ~= CFG.PromptName then return end
			if table.find(prompts, inst) then return end
			table.insert(prompts, inst)
			inst.Triggered:Connect(function() open() end)
			if isOpen then inst.Enabled = false end
		end
		for _, d in ipairs(tower:GetDescendants()) do
			hook(d)
		end
		tower.DescendantAdded:Connect(hook)
		task.delay(20, function()
			if #prompts == 0 then
				warn(("[SkillTree] brak ProximityPrompt '%s' pod Workspace.%s"):format(CFG.PromptName, CFG.TowerModelName))
			end
		end)
	end)

	-- UI (ResetOnSpawn = false → zostaje między postaciami).
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local found = playerGui:WaitForChild("SkillTree", 30)
	if not (found and found:IsA("ScreenGui")) then
		warn("[SkillTree] brak StarterGui.SkillTree (ScreenGui) — drzewko nieaktywne")
		return
	end
	found.Enabled = false
	SkillTreeFx.bind(found, onNode)
	connectButton(found, "UnlockButton", tryUnlock)
	connectButton(found, "RebirthButton", askRebirth)
	connectButton(found, "CloseButton", function() ShopFx.feedback("Press"); close() end)
	connectButton(found, "ConfirmButton", confirmRebirth)
	connectButton(found, "CancelButton", cancelRebirth)
	gui = found
end

return SkillTreeController
