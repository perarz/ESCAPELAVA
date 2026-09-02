--!strict
-- CooldownBarController.luau
-- Wizualizacja aktywnych cooldownów. Każde ID trackowane osobno → gdy push (4s)
-- i bomba (0.5s) są na cd równocześnie, są DWA niezależne paski (bug-safe).
--
-- API: CooldownBarController.trigger(id: string, duration: number) — klient woła
--      DOPIERO po lokalnym rate-limit checku (Config.RateLimits.*).
--
-- KONTRAKT STUDIO (Kacper stawia):
--   StarterGui.HUD.CooldownBars (Frame kontener — dowolna pozycja/rozmiar/styl)
--     ├── UIListLayout (dowolna Direction/Padding — kacper decyduje pion/poziom)
--     └── CooldownBarTemplate (Frame, Visible=false, styl paska)
--           └── Fill (Frame, Size=1,0,1,0, AnchorPoint=0,0) — kod skaluje X.Scale
--
-- Bez kontenera → warn raz, cooldownów brak (gameplay leci dalej, tylko wizualizacji nie ma).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CooldownBarController = {}

type Cooldown = {
	id: string,
	start: number,
	duration: number,
	bar: GuiObject,
	fill: GuiObject,
}

local active: { [string]: Cooldown } = {}
local container: Instance? = nil
local template: GuiObject? = nil
local warnedNoContainer = false
local warnedNoTemplate = false
local warnedNoFill = false

local function ensureUI(): boolean
	if container and template then return true end

	local player = Players.LocalPlayer
	local pgui = player:WaitForChild("PlayerGui")
	local hud = pgui:WaitForChild("HUD", 10)
	if not hud then return false end

	local ctr = hud:FindFirstChild("CooldownBars", true)
	if not ctr then
		if not warnedNoContainer then
			warnedNoContainer = true
			warn("[CooldownBar] StarterGui.HUD.CooldownBars nie istnieje — pasek cooldown niekaktywny. " ..
				"Postaw Frame o tej nazwie w StarterGui.HUD z UIListLayout + child CooldownBarTemplate.")
		end
		return false
	end

	local tpl = ctr:FindFirstChild("CooldownBarTemplate")
	if not tpl or not tpl:IsA("GuiObject") then
		if not warnedNoTemplate then
			warnedNoTemplate = true
			warn("[CooldownBar] CooldownBars.CooldownBarTemplate (Frame Visible=false) nie istnieje.")
		end
		return false
	end

	container = ctr
	template = tpl
	return true
end

local function createBar(): (GuiObject?, GuiObject?)
	if not ensureUI() then return nil, nil end
	local ctr = container :: Instance
	local tpl = template :: GuiObject

	local bar = tpl:Clone() :: GuiObject
	bar.Visible = true
	bar.Parent = ctr

	local fill = bar:FindFirstChild("Fill")
	if not fill or not fill:IsA("GuiObject") then
		if not warnedNoFill then
			warnedNoFill = true
			warn("[CooldownBar] CooldownBarTemplate.Fill (Frame Size=1,0,1,0) nie istnieje w template.")
		end
		bar:Destroy()
		return nil, nil
	end

	return bar, fill
end

function CooldownBarController.trigger(id: string, duration: number)
	if type(id) ~= "string" or type(duration) ~= "number" or duration <= 0 then return end

	local existing = active[id]
	if existing then
		existing.start = os.clock()
		existing.duration = duration
		existing.fill.Size = UDim2.fromScale(1, existing.fill.Size.Y.Scale)
		return
	end

	local bar, fill = createBar()
	if not bar or not fill then return end

	active[id] = {
		id = id,
		start = os.clock(),
		duration = duration,
		bar = bar :: GuiObject,
		fill = fill :: GuiObject,
	}
end

function CooldownBarController.init()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for id, cd in pairs(active) do
			local remaining = cd.duration - (now - cd.start)
			if remaining <= 0 then
				cd.bar:Destroy()
				active[id] = nil
			else
				-- Tylko X.Scale — Y zostaje jak Kacper ustawił w template (UICorner etc.)
				cd.fill.Size = UDim2.new(remaining / cd.duration, 0, cd.fill.Size.Y.Scale, cd.fill.Size.Y.Offset)
			end
		end
	end)
end

return CooldownBarController
