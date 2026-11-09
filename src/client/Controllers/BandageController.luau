--!strict
-- Server timestamps own the healing channel. This client only displays it, including on
-- remote characters, and restores its four arm joints before Animator's next evaluation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local RagdollState = require(script.Parent.RagdollState)
local ItemEquipController = require(script.Parent.ItemEquipController)
local ToolActivation = require(script.Parent.ToolActivation)

local Controller = {}
local CFG = Config.Bandage
local ANIM = CFG.Animation
local localPlayer = Players.LocalPlayer
local gameState = ""
local lastRequest = -math.huge
local initialized = false

type Joint = { motor: Motor6D, base: CFrame?, written: CFrame? }
type Channel = {
	character: Model, humanoid: Humanoid, tool: Tool, started: number, ends: number,
	joints: { [string]: Joint },
}
local channels: { [Player]: Channel } = {}
local connections: { [Player]: { RBXScriptConnection } } = {}
local cancelledStart: { [Player]: number } = {}
local progress: GuiObject? = nil
local progressFill: GuiObject? = nil
local JOINTS = { LeftShoulder = true, LeftElbow = true, RightShoulder = true, RightElbow = true }

local function restore(channel: Channel)
	for _, joint in pairs(channel.joints) do
		-- Animator may skip evaluation for distant characters; undo our own last write.
		if joint.base and joint.written and joint.motor.Parent and joint.motor.Transform == joint.written then
			joint.motor.Transform = joint.base
		end
		joint.base, joint.written = nil, nil
	end
end

local function clearProgress()
	if progress then progress:Destroy() end
	progress, progressFill = nil, nil
end

local function stop(who: Player, cancelled: boolean?)
	local channel = channels[who]
	if channel then
		restore(channel)
		if cancelled then cancelledStart[who] = channel.started end
	end
	channels[who] = nil
	if who == localPlayer then clearProgress() end
end

local function createProgress()
	clearProgress()
	local pg = localPlayer:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local container = hud and hud:FindFirstChild("CooldownBars", true)
	local template = container and container:FindFirstChild(CFG.ProgressTemplate)
	if not template or not template:IsA("GuiObject") then return end
	local clone = template:Clone()
	local fill = clone:FindFirstChild("Fill", true)
	if not fill or not fill:IsA("GuiObject") then clone:Destroy(); return end
	clone.Name = CFG.ProgressName
	clone.Visible = true
	for _, child in ipairs(clone:GetDescendants()) do
		if child:IsA("TextLabel") then child.Text = CFG.ProgressText end
	end
	fill.Size = UDim2.new(0, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
	clone.Parent = container
	progress, progressFill = clone, fill
end

local function heldBandage(character: Model): Tool?
	local tool = character:FindFirstChild(CFG.ToolName)
	return if tool and tool:IsA("Tool") then tool else nil
end

local function valid(channel: Channel, who: Player): boolean
	return who.Character == channel.character and channel.character.Parent ~= nil
		and channel.tool.Parent == channel.character and channel.humanoid.Health > 0
		and not RagdollState.isRagdolled(channel.humanoid)
end

local function synchronize(who: Player)
	local started = who:GetAttribute(CFG.StartAttribute)
	local ends = who:GetAttribute(CFG.EndAttribute)
	local now = Workspace:GetServerTimeNow()
	if typeof(started) ~= "number" or typeof(ends) ~= "number" or ends <= now or ends <= started then
		stop(who)
		if typeof(started) ~= "number" then cancelledStart[who] = nil end
		return
	end
	if cancelledStart[who] == started then return end
	local existing = channels[who]
	if existing and existing.started == started then
		existing.ends = ends
		return
	end
	local character = who.Character
	if not character then return end
	local tool = heldBandage(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	-- Retry on the next poll: attributes can arrive before the Tool or the character.
	if not tool or not hum or hum.Health <= 0 or RagdollState.isRagdolled(hum) then return end
	stop(who)
	local joints: { [string]: Joint } = {}
	for _, instance in ipairs(character:GetDescendants()) do
		if instance:IsA("Motor6D") and JOINTS[instance.Name] then
			joints[instance.Name] = { motor = instance, base = nil, written = nil }
		end
	end
	channels[who] = { character = character, humanoid = hum, tool = tool,
		started = started, ends = ends, joints = joints }
	if who == localPlayer then
		ItemEquipController.cancel()
		createProgress()
	end
end

local function angles(v: Vector3): CFrame
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local leftShoulder = angles(ANIM.LeftShoulder)
local leftElbow = angles(ANIM.LeftElbow)

local function smooth(value: number): number
	local x = math.clamp(value, 0, 1)
	return x * x * (3 - 2 * x)
end

local function update()
	local now = Workspace:GetServerTimeNow()
	for who, channel in pairs(channels) do
		if not valid(channel, who) then stop(who, true); continue end
		if now >= channel.ends then stop(who); continue end
		local duration = channel.ends - channel.started
		local elapsed = math.max(0, now - channel.started)
		local fraction = math.clamp(elapsed / duration, 0, 1)
		local weight = smooth(elapsed / ANIM.FadeIn) * smooth((channel.ends - now) / ANIM.FadeOut)
		-- The left arm stays offered across the body; the roll in the right hand makes
		-- repeated loops around it. Only arms are overlaid, so walking remains animated.
		local phase = fraction * math.pi * 2 * ANIM.WrapCycles
		local orbit = ANIM.ShoulderOrbit
		local rightShoulder = angles(ANIM.RightShoulder + Vector3.new(
			math.sin(phase) * orbit.X, math.cos(phase) * orbit.Y, math.cos(phase) * orbit.Z))
		local rightElbow = angles(ANIM.RightElbow + Vector3.new(math.sin(phase) * ANIM.ElbowOrbit, 0, 0))
		local poses = { LeftShoulder = leftShoulder, LeftElbow = leftElbow,
			RightShoulder = rightShoulder, RightElbow = rightElbow }
		for name, joint in pairs(channel.joints) do
			local motor = joint.motor
			if not motor.Parent or not motor.Enabled then stop(who, true); break end
			local base = motor.Transform
			local result = base:Lerp(poses[name], weight)
			joint.base, joint.written = base, result
			motor.Transform = result
		end
		if who == localPlayer and progressFill then
			progressFill.Size = UDim2.new(fraction, 0, progressFill.Size.Y.Scale, progressFill.Size.Y.Offset)
		end
	end
end

local function activate()
	if gameState ~= "ROUND" then return end
	local now = os.clock()
	if now - lastRequest < Config.RateLimits.Bandage or channels[localPlayer] then return end
	local character = localPlayer.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not heldBandage(character) or not hum or hum.Health <= 0
		or hum.Health >= hum.MaxHealth or RagdollState.isRagdolled(hum) then return end
	lastRequest = now
	ItemEquipController.cancel()
	Remotes.UseBandage:FireServer()
end

local function watch(who: Player)
	if connections[who] then return end
	connections[who] = {
		who:GetAttributeChangedSignal(CFG.StartAttribute):Connect(function() synchronize(who) end),
		who:GetAttributeChangedSignal(CFG.EndAttribute):Connect(function() synchronize(who) end),
		who.CharacterRemoving:Connect(function() stop(who, true) end),
	}
	synchronize(who)
end

function Controller.init()
	if initialized then return end
	initialized = true
	Remotes.GameStateChanged.OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "string" then return end
		gameState = state
		if state ~= "ROUND" then
			for who in pairs(channels) do stop(who, true) end
		end
	end)
	ToolActivation.bind(CFG.ToolName, activate)
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(who)
		stop(who)
		local list = connections[who]
		if list then for _, conn in ipairs(list) do conn:Disconnect() end end
		connections[who], cancelledStart[who] = nil, nil
	end)
	for _, who in ipairs(Players:GetPlayers()) do watch(who) end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CFG.CheckInterval then return end
		elapsed = 0
		for who in pairs(connections) do synchronize(who) end
	end)
	RunService.PreAnimation:Connect(function()
		for _, channel in pairs(channels) do restore(channel) end
	end)
	RunService.PreSimulation:Connect(update)
end

return Controller
