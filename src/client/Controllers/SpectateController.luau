--!strict
-- Spectating owns only the local camera and controls; PlayerService owns who is in the round.
-- Native Custom camera keeps Roblox's mouse/touch orbit and wall occlusion.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Shop = require(script.Parent.ShopController)

local Controller = {}
local CFG = Config.Spectate
local player = Players.LocalPlayer
local initialized = false
local active = false
local target: Player? = nil
local candidates: { Player } = {}
local gameState = "LOBBY"
local onMap = false
local gui: GuiObject? = nil
local openButton: GuiButton? = nil
local controlsFrame: GuiObject? = nil
local targetLabel: TextLabel? = nil
local controls: any = nil
local ownsControls = false
local savedFov: number? = nil
local playerConnections: { [Player]: { RBXScriptConnection } } = {}

local function livingHumanoid(who: Player): Humanoid?
	local character = who.Character
	if not character or not character:IsDescendantOf(Workspace) then return nil end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return hum
end

local function otherCameraOwner(): boolean
	return Shop.isOpen() or player:GetAttribute("CosmeticsOpen") == true
end

local function eligible(): boolean
	return not onMap and player:GetAttribute(CFG.ParticipantAttribute) ~= true
		and livingHumanoid(player) ~= nil and not otherCameraOwner()
end

local function roundVisible(): boolean
	return gameState == "ROUND" or gameState == "COUNTDOWN"
end

-- Kacper 09.11: w lobby i na ekranie ROUND OVER (FINISHING, RESETTING) przycisku nie ma wcale —
-- nie ma kogo oglądać, a wyszarzony SPECTATE tylko zajmował miejsce.
local HIDDEN_STATES = { LOBBY = true, FINISHING = true, RESETTING = true }

local function updateUI()
	local allowed = eligible() and not HIDDEN_STATES[gameState]
	if gui then gui.Visible = allowed end
	if openButton then
		openButton.Visible = not active
		local available = #candidates > 0 and roundVisible() and controls ~= nil
		openButton.Active = available
		openButton.Selectable = available
		local label = openButton:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = if available then "SPECTATE" else CFG.EmptyText
			local shadow = openButton:FindFirstChild("LabelShadow")
			if shadow and shadow:IsA("TextLabel") then shadow.Text = label.Text end
		end
	end
	if controlsFrame then controlsFrame.Visible = active end
	if targetLabel and target then
		targetLabel.Text = string.format(CFG.TargetFormat, target.DisplayName, table.find(candidates, target) or 1, #candidates)
		local shadow = controlsFrame and controlsFrame:FindFirstChild("TargetShadow")
		if shadow and shadow:IsA("TextLabel") then shadow.Text = targetLabel.Text end
	end
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then camera.CameraSubject = hum end
	camera.FieldOfView = savedFov or Config.Movement.BaseFOV
end

local function stop()
	if not active then return end
	active = false
	target = nil
	player:SetAttribute(CFG.ActiveAttribute, nil)
	player:SetAttribute(CFG.TargetAttribute, nil)
	-- Shop/cosmetics have already taken ownership when their notification reaches us.
	-- Restoring here would overwrite their camera or unfreeze their character.
	if not otherCameraOwner() then
		restoreCamera()
		if ownsControls and controls then controls:Enable() end
	else
		-- The cosmetics catalog may never enter its Scriptable fitting camera. Give
		-- Custom camera back its own subject without overwriting the menu's pose/FOV.
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if camera and hum then camera.CameraSubject = hum end
	end
	ownsControls = false
	savedFov = nil
	updateUI()
end

local function applyTarget()
	if not active or not target then return end
	local hum = livingHumanoid(target)
	local camera = Workspace.CurrentCamera
	if not hum or not camera then return end
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = hum
	camera.FieldOfView = Config.Movement.BaseFOV
	player:SetAttribute(CFG.TargetAttribute, target.UserId)
end

local function refresh()
	local previous = target
	local previousIndex = if previous then table.find(candidates, previous) else nil
	local nextCandidates: { Player } = {}
	if roundVisible() then
		for _, who in ipairs(Players:GetPlayers()) do
			if who ~= player and who:GetAttribute(CFG.ParticipantAttribute) == true and livingHumanoid(who) then
				table.insert(nextCandidates, who)
			end
		end
	end
	table.sort(nextCandidates, function(a, b) return a.UserId < b.UserId end)
	candidates = nextCandidates
	if active then
		if not eligible() or not roundVisible() or #candidates == 0 then
			stop()
		else
			if not previous or not table.find(candidates, previous) then
				target = candidates[math.min(previousIndex or 1, #candidates)]
			end
			-- Handles replacement Humanoid/CurrentCamera without resetting orbit CFrame.
			applyTarget()
		end
	end
	updateUI()
end

local function start()
	refresh()
	if active or not eligible() or not roundVisible() or #candidates == 0 or not controls then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	savedFov = camera.FieldOfView
	active = true
	target = candidates[1]
	player:SetAttribute(CFG.ActiveAttribute, true)
	controls:Disable()
	ownsControls = true
	local hum = livingHumanoid(player)
	if hum then hum:Move(Vector3.zero); hum.Jump = false end
	applyTarget()
	updateUI()
end

local function cycle(delta: number)
	refresh()
	if not active or #candidates == 0 then return end
	local index = if target then table.find(candidates, target) or 1 else 1
	target = candidates[((index - 1 + delta) % #candidates) + 1]
	applyTarget()
	updateUI()
end

local function watch(who: Player)
	if playerConnections[who] then return end
	playerConnections[who] = {
		who:GetAttributeChangedSignal(CFG.ParticipantAttribute):Connect(refresh),
		who.CharacterAdded:Connect(function() task.defer(refresh) end),
		who.CharacterRemoving:Connect(function()
			if who == player then stop() end
			task.defer(refresh)
		end),
	}
end

function Controller.init()
	if initialized then return end
	initialized = true
	player:SetAttribute(CFG.ActiveAttribute, nil)
	player:SetAttribute(CFG.TargetAttribute, nil)
	-- All state listeners precede UI/PlayerModule waits so ClientReady cannot outrun us.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "string" then return end
		gameState = state
		if state == "LOBBY" then onMap = false end
		refresh()
	end)
	Remotes.AliveChanged.OnClientEvent:Connect(function(alive: any)
		onMap = alive == true
		refresh()
	end)
	Shop.onOpenChanged(refresh)
	player:GetAttributeChangedSignal("CosmeticsOpen"):Connect(refresh)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if active then applyTarget() end
	end)
	Players.PlayerAdded:Connect(function(who) watch(who); refresh() end)
	Players.PlayerRemoving:Connect(function(who)
		local conns = playerConnections[who]
		if conns then for _, conn in ipairs(conns) do conn:Disconnect() end end
		playerConnections[who] = nil
		task.defer(refresh)
	end)
	for _, who in ipairs(Players:GetPlayers()) do watch(who) end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CFG.PollInterval then return end
		elapsed = 0
		refresh()
	end)
	task.spawn(function()
		local scripts = player:WaitForChild("PlayerScripts")
		local module = scripts:WaitForChild("PlayerModule", CFG.GuiWaitTimeout)
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(function() return (require(module) :: any):GetControls() end)
			if ok then controls = result end
		end
		refresh()
	end)
	local pg = player:WaitForChild("PlayerGui")
	local hud = pg:WaitForChild("HUD")
	local root = hud:WaitForChild(CFG.GuiName, CFG.GuiWaitTimeout)
	local open = root and root:FindFirstChild("Open")
	local panel = root and root:FindFirstChild("Controls")
	local previous = panel and panel:FindFirstChild("Previous")
	local nextButton = panel and panel:FindFirstChild("Next")
	local close = panel and panel:FindFirstChild("Close")
	local label = panel and panel:FindFirstChild("Target")
	if not (root and root:IsA("GuiObject") and open and open:IsA("GuiButton")
		and panel and panel:IsA("GuiObject") and previous and previous:IsA("GuiButton")
		and nextButton and nextButton:IsA("GuiButton") and close and close:IsA("GuiButton")
		and label and label:IsA("TextLabel")) then
		warn("[Spectate] missing HUD.Spectate controls")
		return
	end
	gui, openButton, controlsFrame, targetLabel = root, open, panel, label
	open.Activated:Connect(start)
	previous.Activated:Connect(function() cycle(-1) end)
	nextButton.Activated:Connect(function() cycle(1) end)
	close.Activated:Connect(stop)
	refresh()
end

return Controller
