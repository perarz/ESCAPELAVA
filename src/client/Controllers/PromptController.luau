--!strict
-- PromptController.luau (15.11) — własny wygląd WSZYSTKICH ProximityPromptów (decyzja Kacpra:
-- „custom prompt przy podnoszeniu”, potem „wszędzie”: itemy, sklep, przebieralnia, mag).
--
-- Jak: każdy prompt w Workspace dostaje lokalnie `Style = Custom` (to tylko rysowanie po stronie
-- klienta — serwer, zasięg, klawisz i `Triggered` działają bez zmian), a na `PromptShown`
-- klonujemy szablon ze Studio i przypinamy go do rodzica promptu.
--
-- KONTRAKT UI (Studio): `StarterGui.PromptTemplate` (BillboardGui, Enabled=false — wzór, kod
-- klonuje). W środku `Body` (+ `Pop` UIScale): `Title` (+ `TitleShadow`) = ObjectText,
-- `Row.Keybind` (klawisz jak „G” przy C4: `Body` bok, `Face` ścianka z `Label`),
-- `Row.ActionBox.Action` (+ `ActionShadow`) = ActionText, `Hit` (TextButton — klik/dotyk).
-- Cienie kopiuje TextShadowController. Brak szablonu = zostaje domyślny prompt Robloxa.
--
-- Kolor tytułu: atrybut `TitleColor` (Color3) na prompcie, ustawiany lokalnie przez tego, kto
-- wie, czym prompt jest (ItemPickupFx: kolor rzadkości). Bez atrybutu — biały.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)

local CFG = Config.Prompt
local KEY = Config.C4.KeyPress -- ten sam klawisz co podpowiedź detonatora, to samo wciskanie

local PromptController = {}

local localPlayer = Players.LocalPlayer

type Shown = {
	gui: BillboardGui,
	pop: UIScale?,
	face: GuiObject?,
	body: GuiObject?,
	facePos: UDim2,
	bodyPos: UDim2,
	bodySize: UDim2,
}
local shown: { [ProximityPrompt]: Shown } = {}
local template: BillboardGui? = nil
local initialized = false

local function makeCustom(inst: Instance)
	if inst:IsA("ProximityPrompt") and template then
		inst.Style = Enum.ProximityPromptStyle.Custom
	end
end

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string?
	if inputType == Enum.ProximityPromptInputType.Keyboard then
		return prompt.KeyboardKeyCode.Name
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	return nil -- dotyk: bez klawisza, klik w cały prompt
end

local function setKeyDown(s: Shown, down: boolean)
	local face, body = s.face, s.body
	if not (face and body) then return end
	local d = if down then KEY.Depth else 0
	local info = if down
		then TweenInfo.new(KEY.DownTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else TweenInfo.new(KEY.UpTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(face, info, { Position = s.facePos + UDim2.fromOffset(0, d) }):Play()
	TweenService:Create(body, info, {
		Position = s.bodyPos + UDim2.fromOffset(0, d),
		Size = s.bodySize - UDim2.fromOffset(0, d),
	}):Play()
end

local function hide(prompt: ProximityPrompt)
	local s = shown[prompt]
	if not s then return end
	shown[prompt] = nil
	local gui = s.gui
	if s.pop then
		local tw = TweenService:Create(s.pop, TweenInfo.new(CFG.HideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		tw.Completed:Connect(function() gui:Destroy() end)
		tw:Play()
	else
		gui:Destroy()
	end
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local tpl = template
	if not tpl or prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	hide(prompt)
	local adornee = prompt.Parent
	if not (adornee and (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model"))) then return end

	local gui = tpl:Clone()
	gui.Name = "Prompt"
	gui.Adornee = adornee :: any
	gui.Enabled = true
	-- Rozmiar BillboardGui w pikselach nie zależy od ekranu — bez tego na telefonie prompt
	-- zajmowałby pół wysokości. Ta sama skala co HUD (HudScaleController, Config.UI).
	local cam = Workspace.CurrentCamera
	local viewY = if cam then cam.ViewportSize.Y else Config.UI.ReferenceHeight
	local hudScale = math.clamp(viewY / Config.UI.ReferenceHeight, Config.UI.MinScale, Config.UI.MaxScale)
	gui.Size = UDim2.fromOffset(tpl.Size.X.Offset * hudScale, tpl.Size.Y.Offset * hudScale)
	-- UIScale na samym BillboardGui (Body ma już własny `Pop` — dwa UIScale na jednym obiekcie
	-- się nie mnożą, działa tylko jeden).
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Scale = hudScale
	fit.Parent = gui

	local title = gui:FindFirstChild("Title", true)
	if title and title:IsA("TextLabel") then
		title.Text = string.upper(prompt.ObjectText)
		title.Visible = prompt.ObjectText ~= ""
		local c = prompt:GetAttribute("TitleColor")
		title.TextColor3 = if typeof(c) == "Color3" then c else Color3.new(1, 1, 1)
	end
	local action = gui:FindFirstChild("Action", true)
	if action and action:IsA("TextLabel") then
		action.Text = string.upper(prompt.ActionText)
	end
	local key = keyText(prompt, inputType)
	local keybind = gui:FindFirstChild("Keybind", true)
	if keybind and keybind:IsA("GuiObject") then
		keybind.Visible = key ~= nil
		local label = keybind:FindFirstChild("Label", true)
		if key and label and label:IsA("TextLabel") then label.Text = key end
	end

	local face = keybind and keybind:FindFirstChild("Face")
	local body = keybind and keybind:FindFirstChild("Body")
	local p = gui:FindFirstChild("Pop", true)
	local s: Shown = {
		gui = gui,
		pop = if p and p:IsA("UIScale") then p else nil,
		face = if face and face:IsA("GuiObject") then face else nil,
		body = if body and body:IsA("GuiObject") then body else nil,
		facePos = if face and face:IsA("GuiObject") then face.Position else UDim2.new(),
		bodyPos = if body and body:IsA("GuiObject") then body.Position else UDim2.new(),
		bodySize = if body and body:IsA("GuiObject") then body.Size else UDim2.new(),
	}
	shown[prompt] = s

	-- Dotyk w prompt = naciśnięcie klawisza (serwer dostaje zwykłe Triggered). TYLKO na dotyku:
	-- na PC prompt wisi nad itemem zawsze na wierzchu, a klik myszą to rzut / strzał — gdyby
	-- przycisk łapał klik, walka obok leżącego itemu kończyłaby się podniesieniem zamiast rzutu.
	local hit = gui:FindFirstChild("Hit", true)
	if hit and hit:IsA("GuiButton") then
		hit.Visible = inputType == Enum.ProximityPromptInputType.Touch
	end
	if hit and hit:IsA("GuiButton") and inputType == Enum.ProximityPromptInputType.Touch then
		hit.Activated:Connect(function()
			prompt:InputHoldBegin()
			task.delay(KEY.TapHold, function() prompt:InputHoldEnd() end)
		end)
	end

	if s.pop then
		s.pop.Scale = CFG.ShowFromScale
		TweenService:Create(s.pop, TweenInfo.new(CFG.ShowTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function PromptController.init()
	if initialized then return end
	initialized = true

	-- Listenery najpierw (prompt może się pokazać, zanim szablon dojedzie — wtedy zostaje domyślny).
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then setKeyDown(s, true) end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then setKeyDown(s, false) end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s and s.pop then
			s.pop.Scale = CFG.TriggerPop
			TweenService:Create(s.pop, TweenInfo.new(CFG.ShowTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui")
		local tpl = playerGui:WaitForChild("PromptTemplate", 10)
		if not (tpl and tpl:IsA("BillboardGui")) then
			warn("[PromptController] PlayerGui.PromptTemplate nie istnieje — zostają domyślne prompty Robloxa")
			return
		end
		tpl.Enabled = false
		template = tpl
		for _, d in ipairs(Workspace:GetDescendants()) do makeCustom(d) end
		Workspace.DescendantAdded:Connect(makeCustom)
	end)
end

return PromptController
