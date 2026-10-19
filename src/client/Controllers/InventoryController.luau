--!strict
-- InventoryController.luau — panel ekwipunku: wybór 3 itemów na rundę (18.10, plan i decyzje
-- Kacpra: docs/ROADMAP.md → „PLAN: LOADOUT”). Stan czyta i zmienia przez LoadoutState; prawdę
-- trzyma serwer (LoadoutService) — tu jest tylko UI.
--
-- WYGLĄD (19.10, trzecia wersja — Kacper: „bardziej klasycznie, czarny obrys wszędzie, ma
-- pasować do reszty UI”): czarne obrysy jak sloty paska, nagłówek w gradiencie licznika czasu,
-- karty itemów w kolorze itemu ze studsami, sloty loadoutu = klony slotu paska (gracz widzi
-- w panelu dokładnie to, co potem w pasku) na pasie płynącej lawy.
--
-- KONTRAKT NAZW (postawione przez MCP; opis: docs/STUDIO_CONTRACT.md → „Ekwipunek”):
--   StarterGui.Inventory (ScreenGui, ResetOnSpawn=false, IgnoreGuiInset)
--     Backdrop (TextButton, cały ekran, atrybut NoHudScale) — klik = zamknij
--     Panel.Body (UIScale Pop): CloseButton (UIScale Hover), Card:
--       Shelf.Grid (UIGridLayout) → ItemTemplate (Visible=false; UIScale Hover): SelectStroke,
--         Fill (+ Studs), Icon, ItemName, Count, Price, SlotTag.Label
--       Details: Viewport, ItemName, Count, Desc, Stats.<Power|Range|Mobility>.Bar.Fill
--       LavaPool.Band.Lava1/Lava2 (przesuwane), Loadout: Status, Slot1..3 (klon HUD.Hotbar.Slot1:
--         SelectStroke, Icon, ItemName, Count, Keybind + Empty „+”, UIScale Pop)
--   StarterGui.HUD.SideButtons.InventoryButton (UIScale Pop) → Badge (UIScale Pop)
--
-- Sterowanie (decyzja Kacpra: klik + przeciąganie):
--   * klik itemu: wkłada do slotu-celu (kliknięty slot) albo pierwszego wolnego; klik itemu, który
--     już jest w loadoucie, wyjmuje go. Na dotyku pierwszy tap tylko pokazuje DETAILS (bez hovera
--     tap = „co to jest?”), drugi zmienia loadout.
--   * przeciąganie: item → slot, slot ↔ slot (zamiana), slot poza sloty = wyjęcie.
--   * PC: najechanie na item + 1/2/3 = do tego slotu (wtedy pasek NIE wyciąga itemu).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local LoadoutState = require(script.Parent.LoadoutState)

local InventoryController = {}

local CFG = Config.UI.Inventory
local SLOTS = Config.Loadout.Slots
local STAT_ROWS = { power = "Power", range = "Range", mobility = "Mobility" }
local BLACK = Color3.new(0, 0, 0)
local localPlayer = Players.LocalPlayer

local isOpen = false
local openToken = 0
local hoveredItem: string? = nil
local shownItem: string? = nil      -- item w DETAILS
local targetSlot: number? = nil     -- slot wybrany kliknięciem (następny item idzie tam)
local statusOverride: string? = nil
local statusToken = 0
-- Slot, do którego leci ikona: jego ikona pokaże się dopiero po przylocie (inaczej dwie ikony
-- naraz). Żeton — kolejna zmiana tego slotu unieważnia czekające lądowanie.
local landing: { [number]: number } = {}
local landingSeq = 0

-- UI (nil, dopóki nie znalezione — każda funkcja to znosi)
local gui: ScreenGui? = nil
local backdrop: GuiButton? = nil
local panel: GuiObject? = nil
local bodyFrame: GuiObject? = nil
local pop: UIScale? = nil
local statusLabel: TextLabel? = nil
local details: Instance? = nil
local viewport: ViewportFrame? = nil
local badge: GuiObject? = nil
local tiles: { [string]: GuiButton } = {}
local slotButtons: { [number]: GuiButton } = {}
local slotIconBase: { [number]: UDim2 } = {}
local lavaLayers: { { image: ImageLabel, speed: number } } = {}

-- Badge „!”: item kupiony, ale nie zmieścił się w loadoucie (znika po otwarciu panelu).
local lastCounts: { [string]: number } = {}
local countsKnown = false

local function setText(parent: Instance?, name: string, text: string)
	if not parent then return end
	local l = parent:FindFirstChild(name)
	if l and (l:IsA("TextLabel") or l:IsA("TextButton")) then
		l.Text = text
	end
	-- Cień kopiuje TextShadowController, ale klon tworzony w tej klatce dostaje tekst dopiero
	-- po jego podpięciu — ustawiamy od razu, żeby nie mignął pusty.
	local sh = parent:FindFirstChild(name .. "Shadow")
	if sh and (sh:IsA("TextLabel") or sh:IsA("TextButton")) then
		sh.Text = text
	end
end

local function setVisible(parent: Instance, name: string, visible: boolean)
	for _, n in ipairs({ name, name .. "Shadow" }) do
		local o = parent:FindFirstChild(n)
		if o and o:IsA("GuiObject") then o.Visible = visible end
	end
end

local function scaleOf(obj: Instance, name: string): UIScale
	local s = obj:FindFirstChild(name)
	if s and s:IsA("UIScale") then return s end
	local created = Instance.new("UIScale")
	created.Name = name
	created.Parent = obj
	return created
end

local function popScale(obj: Instance, name: string, from: number, time: number)
	local scale = scaleOf(obj, name)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function shake(obj: GuiObject?)
	if not obj then return end
	obj.Rotation = 0
	TweenService:Create(obj, TweenInfo.new(0.06, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), {
		Rotation = 5,
	}):Play()
end

-- Obrys jak w pasku: czarny, a biały = „to jest wybrane”.
local function setSelected(btn: Instance, on: boolean)
	local stroke = btn:FindFirstChild("SelectStroke")
	if stroke and stroke:IsA("UIStroke") then
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Color = if on then CFG.SelectedColor else BLACK,
		}):Play()
	end
end

-- Karta / przycisk rośnie pod kursorem (jeden UIScale na obiekt — dwa się nie sumują).
local function hookHover(btn: GuiButton, scaleName: string)
	local scale = scaleOf(btn, scaleName)
	local info = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, info, { Scale = CFG.HoverScale }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
end

local function flashStatus(text: string)
	statusOverride = text
	statusToken += 1
	local token = statusToken
	if statusLabel then
		setText(statusLabel.Parent, "Status", text)
		popScale(statusLabel, "Pop", 1.25, 0.3)
	end
	task.delay(2.2, function()
		if token ~= statusToken then return end
		statusOverride = nil
		if statusLabel then
			setText(statusLabel.Parent, "Status", if LoadoutState.isLobby() then "" else CFG.LockedText)
		end
	end)
end

local function itemColor(itemId: string): Color3
	return (CFG.ItemColors :: any)[itemId] or CFG.DefaultItemColor
end

local function iconOf(itemId: string?): string
	local def = itemId and ItemDefinitions.get(itemId)
	local image = def and def.icon
	return if typeof(image) == "string" then image else ""
end

-- ============================================================================
-- DETAILS: model 3D, opis, cechy (studsy)
-- ============================================================================

local spinModel: Model? = nil
local spinCamera: Camera? = nil

local function findSceneModel(name: string): Instance?
	local scene = Workspace:FindFirstChild(Config.Shop.SceneName, true)
	local folder = scene and scene:FindFirstChild(Config.Shop.ItemsFolder)
	return folder and folder:FindFirstChild(name)
end

local function setViewportModel(itemId: string)
	if not viewport then return end
	viewport:ClearAllChildren()
	spinModel = nil
	local def = ItemDefinitions.get(itemId)
	local source = def and def.sceneModel and findSceneModel(def.sceneModel)
	if not source then return end
	-- Model z wystawy sklepu: kopia bez skryptów i świateł, sama geometria.
	local model = Instance.new("Model")
	local copy = source:Clone()
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Light") or d:IsA("ProximityPrompt") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	copy.Parent = model
	model.Parent = viewport
	local cf, size = model:GetBoundingBox()
	-- Środek modelu w zerze, orientacja jak na wystawie — obrót wokół własnej osi.
	model.WorldPivot = CFrame.new(cf.Position)
	model:PivotTo(CFrame.new())
	local radius = math.max(size.Magnitude / 2, 0.5)
	local cam = spinCamera or Instance.new("Camera")
	spinCamera = cam
	cam.FieldOfView = 30
	local tilt = math.rad(CFG.ModelTilt)
	local dist = radius * CFG.ModelFill / math.tan(math.rad(cam.FieldOfView / 2))
	-- Celujemy nad środek modelu → model w kadrze siada niżej, na cieniu pod ViewportFrame.
	local look = Vector3.new(0, size.Y * CFG.ModelLookUp, 0)
	cam.CFrame = CFrame.lookAt(look + Vector3.new(0, math.sin(tilt) * dist, math.cos(tilt) * dist), look)
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	spinModel = model
end

local function showDetails(itemId: string?)
	if not itemId or itemId == shownItem then return end
	shownItem = itemId
	local def = ItemDefinitions.get(itemId)
	if not def or not details then return end
	setText(details, "ItemName", string.upper(def.name or itemId))
	setText(details, "Count", "x" .. tostring(LoadoutState.getCount(itemId)))
	setText(details, "Desc", def.desc or "")
	local stats = details:FindFirstChild("Stats")
	local statValues = (def :: any).stats or {}
	for key, rowName in pairs(STAT_ROWS) do
		local row = stats and stats:FindFirstChild(rowName)
		local bar = row and row:FindFirstChild("Bar")
		local fill = bar and bar:FindFirstChild("Fill")
		if fill and fill:IsA("GuiObject") then
			-- Pasek ma dokładnie StatMax studsów, więc wartość = liczba świecących studsów.
			local v = math.clamp((tonumber(statValues[key]) or 0) / CFG.StatMax, 0, 1)
			fill.Visible = v > 0
			TweenService:Create(fill, TweenInfo.new(CFG.StatTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(v, 1),
			}):Play()
		end
	end
	setViewportModel(itemId)
end

-- ============================================================================
-- Odświeżanie kart i slotów
-- ============================================================================

local function paintCard(tile: GuiButton, itemId: string)
	local def = ItemDefinitions.get(itemId)
	local count = LoadoutState.getCount(itemId)
	-- x0 = szara karta: od razu widać, czego brakuje, zanim ruszy runda.
	local color = if count > 0 then itemColor(itemId) else CFG.EmptyItemColor
	local fill = tile:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		fill.BackgroundColor3 = color
		local studs = fill:FindFirstChild("Studs")
		if studs and studs:IsA("ImageLabel") then studs.ImageColor3 = color end
	end
	local icon = tile:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = iconOf(itemId)
		icon.ImageTransparency = if count > 0 then 0 else 0.45
	end
	setText(tile, "ItemName", if def then def.name else itemId)
	setText(tile, "Count", "x" .. tostring(count))
	setVisible(tile, "Price", count <= 0 and def ~= nil)
	if def then setText(tile, "Price", tostring(def.price) .. "$") end
end

-- Slot jak w pasku: ten sam kod napisów (x1 bez licznika, x0 widoczne).
local function paintSlot(btn: GuiButton, slot: number, itemId: string?)
	local def = itemId and ItemDefinitions.get(itemId)
	local count = if itemId then LoadoutState.getCount(itemId) else 0
	local icon = btn:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = iconOf(itemId)
		icon.Visible = icon.Image ~= "" and landing[slot] == nil
		icon.ImageTransparency = if count > 0 then 0 else 0.6
	end
	setText(btn, "ItemName", if def then def.name else "")
	setText(btn, "Count", if not def or count == 1 then "" else "x" .. tostring(count))
	setVisible(btn, "Empty", def == nil)
end

local function refresh()
	local loadout = LoadoutState.getLoadout()
	for itemId, tile in pairs(tiles) do
		paintCard(tile, itemId)
		local tag = tile:FindFirstChild("SlotTag")
		local slot = table.find(loadout, itemId)
		if tag and tag:IsA("GuiObject") then
			tag.Visible = slot ~= nil
			if slot then setText(tag, "Label", tostring(slot)) end
		end
		setSelected(tile, itemId == shownItem)
	end
	for slot, btn in pairs(slotButtons) do
		local id = loadout[slot]
		paintSlot(btn, slot, if id ~= "" then id else nil)
		setSelected(btn, slot == targetSlot)
	end
	if statusLabel and not statusOverride then
		setText(statusLabel.Parent, "Status", if LoadoutState.isLobby() then "" else CFG.LockedText)
	end
end

-- ============================================================================
-- Zmiany loadoutu
-- ============================================================================

-- Ikona wpada do slotu z góry i odbija się, slot podskakuje.
local function snapSlot(slot: number)
	local btn = slotButtons[slot]
	if not btn then return end
	local icon = btn:FindFirstChild("Icon")
	local base = slotIconBase[slot]
	if icon and icon:IsA("GuiObject") and base then
		icon.Position = base - UDim2.fromOffset(0, CFG.SnapDrop)
		TweenService:Create(icon, TweenInfo.new(CFG.SnapTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
			Position = base,
		}):Play()
	end
	popScale(btn, "Pop", 1.12, 0.3)
end

-- Ikona przelatuje z półki do slotu — widać, GDZIE poszedł item.
local function flyIcon(fromBtn: GuiObject, toSlot: number)
	local to = slotButtons[toSlot]
	local icon = fromBtn:FindFirstChild("Icon")
	if not (gui and to and icon and icon:IsA("ImageLabel") and icon.Image ~= "") then
		snapSlot(toSlot)
		return
	end
	landingSeq += 1
	local token = landingSeq
	landing[toSlot] = token
	refresh()
	local ghost = Instance.new("ImageLabel")
	ghost:SetAttribute("NoHudScale", true) -- PRZED parentem: HudScale łapie ChildAdded
	ghost.BackgroundTransparency = 1
	ghost.Image = icon.Image
	ghost.ScaleType = Enum.ScaleType.Fit
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.ZIndex = 50
	local a = icon.AbsolutePosition + icon.AbsoluteSize / 2
	local b = to.AbsolutePosition + to.AbsoluteSize / 2
	ghost.Position = UDim2.fromOffset(a.X, a.Y)
	ghost.Size = UDim2.fromOffset(icon.AbsoluteSize.X, icon.AbsoluteSize.Y)
	ghost.Parent = gui
	local tween = TweenService:Create(ghost, TweenInfo.new(CFG.FlyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		Position = UDim2.fromOffset(b.X, b.Y - CFG.SnapDrop),
	})
	tween.Completed:Connect(function()
		ghost:Destroy()
		if landing[toSlot] ~= token then return end
		landing[toSlot] = nil
		refresh()
		snapSlot(toSlot)
	end)
	tween:Play()
end

local function commit(newLoadout: { string }): boolean
	if not LoadoutState.set(newLoadout) then
		flashStatus(CFG.LockedText)
		return false
	end
	return true
end

-- Item → slot. Item już w innym slocie = zamiana miejscami (nic nie znika po cichu).
local function assign(itemId: string, slot: number, fromBtn: GuiObject?)
	local loadout = LoadoutState.getLoadout()
	local was = table.find(loadout, itemId)
	if was == slot then return end
	if was then
		loadout[was] = loadout[slot]
	end
	loadout[slot] = itemId
	targetSlot = nil
	if commit(loadout) then
		if fromBtn then
			flyIcon(fromBtn, slot)
		else
			snapSlot(slot)
		end
		if was and loadout[was] ~= "" then snapSlot(was) end
	end
end

local function clearSlot(slot: number)
	local loadout = LoadoutState.getLoadout()
	if loadout[slot] == "" then return end
	loadout[slot] = ""
	landing[slot] = nil
	commit(loadout)
end

local function clickItem(itemId: string)
	local touch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	if touch and shownItem ~= itemId then
		showDetails(itemId)
		refresh()
		return
	end
	showDetails(itemId)
	if not LoadoutState.isLobby() then
		flashStatus(CFG.LockedText)
		refresh()
		return
	end
	local loadout = LoadoutState.getLoadout()
	local was = table.find(loadout, itemId)
	if was then
		if targetSlot and targetSlot ~= was then
			assign(itemId, targetSlot, tiles[itemId])
		else
			clearSlot(was)
		end
		return
	end
	local slot = targetSlot or table.find(loadout, "")
	if not slot then
		flashStatus(CFG.FullText)
		for _, btn in pairs(slotButtons) do shake(btn) end
		return
	end
	assign(itemId, slot, tiles[itemId])
end

local function clickSlot(slot: number)
	local id = LoadoutState.getLoadout()[slot]
	if id ~= "" then showDetails(id) end
	if not LoadoutState.isLobby() then
		flashStatus(CFG.LockedText)
		return
	end
	targetSlot = if targetSlot == slot then nil else slot
	refresh()
end

-- ============================================================================
-- Przeciąganie (mysz i dotyk)
-- ============================================================================

type Drag = { kind: "item" | "slot", itemId: string, slot: number?, from: GuiObject, start: Vector2, ghost: ImageLabel? }
local drag: Drag? = nil
local suppressClick = false

-- Pozycja wskaźnika w układzie GUI z IgnoreGuiInset (InputObject.Position jest bez paska Robloxa).
local function pointer(input: InputObject): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(input.Position.X, input.Position.Y) + inset
end

local function slotAt(p: Vector2): number?
	for slot, btn in pairs(slotButtons) do
		local a, s = btn.AbsolutePosition, btn.AbsoluteSize
		if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then
			return slot
		end
	end
	return nil
end

local function beginPress(input: InputObject, kind: "item" | "slot", itemId: string, slot: number?, from: GuiObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if itemId == "" then return end
	drag = { kind = kind, itemId = itemId, slot = slot, from = from, start = pointer(input), ghost = nil }
end

local function startGhost(d: Drag, p: Vector2)
	local icon = d.from:FindFirstChild("Icon")
	if not (gui and icon and icon:IsA("ImageLabel") and icon.Image ~= "") then return end
	local ghost = Instance.new("ImageLabel")
	ghost:SetAttribute("NoHudScale", true)
	ghost.BackgroundTransparency = 1
	ghost.Image = icon.Image
	ghost.ScaleType = Enum.ScaleType.Fit
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(icon.AbsoluteSize.X * 1.2, icon.AbsoluteSize.Y * 1.2)
	ghost.Position = UDim2.fromOffset(p.X, p.Y)
	ghost.ZIndex = 50
	ghost.Rotation = -10
	ghost.Parent = gui
	d.ghost = ghost
	icon.ImageTransparency = 0.7
end

local function endDrag(input: InputObject?)
	local d = drag
	drag = nil
	if not d or not d.ghost then return end
	d.ghost:Destroy()
	suppressClick = true
	task.defer(function() suppressClick = false end)
	if not input then refresh() return end
	if not LoadoutState.isLobby() then
		flashStatus(CFG.LockedText)
		refresh()
		return
	end
	local drop = slotAt(pointer(input))
	if drop then
		assign(d.itemId, drop, nil)
	elseif d.kind == "slot" and d.slot then
		clearSlot(d.slot) -- slot upuszczony poza sloty = wyjęty z loadoutu
	end
	refresh()
end

-- ============================================================================
-- Otwieranie / zamykanie
-- ============================================================================

local function setOpen(open: boolean)
	if open == isOpen or not (panel and backdrop) then return end
	isOpen = open
	openToken += 1
	local token = openToken
	local p = panel :: GuiObject
	local b = backdrop :: GuiButton
	local info = TweenInfo.new(CFG.OpenTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local back = TweenInfo.new(CFG.OpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if open then
		if badge then badge.Visible = false end
		targetSlot = nil
		p.Visible = true
		b.Visible = true
		b.BackgroundTransparency = 1
		TweenService:Create(b, info, { BackgroundTransparency = CFG.BackdropTransparency }):Play()
		if bodyFrame then
			bodyFrame.Position = UDim2.fromOffset(0, -CFG.OpenDrop)
			TweenService:Create(bodyFrame, back, { Position = UDim2.fromOffset(0, 0) }):Play()
		end
		if pop then
			pop.Scale = CFG.ClosedScale
			TweenService:Create(pop, back, { Scale = 1 }):Play()
		end
		if not shownItem then
			local first = LoadoutState.getLoadout()[1]
			showDetails(if first ~= "" then first else ItemDefinitions.shopOrder[1])
		else
			local again = shownItem
			shownItem = nil
			showDetails(again) -- przelicz licznik i model (mogły się zmienić)
		end
		refresh()
	else
		endDrag(nil)
		hoveredItem = nil
		TweenService:Create(b, info, { BackgroundTransparency = 1 }):Play()
		if pop then
			TweenService:Create(pop, info, { Scale = CFG.ClosedScale }):Play()
		end
		task.delay(CFG.OpenTime * 0.6, function()
			if token ~= openToken then return end
			p.Visible = false
			b.Visible = false
		end)
	end
end

-- Klawisze 1-3 należą do panelu, gdy jest otwarty (HotbarController pyta tutaj).
function InventoryController.capturesHotkeys(): boolean
	return isOpen
end

function InventoryController.isOpen(): boolean
	return isOpen
end

-- ============================================================================
-- Init
-- ============================================================================

local function updateBadge()
	-- Nowe sztuki itemu spoza loadoutu przy pełnym loadoucie = „masz coś, czego nie używasz”.
	local loadout = LoadoutState.getLoadout()
	local full = table.find(loadout, "") == nil
	local show = false
	for _, id in ipairs(ItemDefinitions.shopOrder) do
		local n = LoadoutState.getCount(id)
		if countsKnown and n > (lastCounts[id] or 0) and full and not table.find(loadout, id) then
			show = true
		end
		lastCounts[id] = n
	end
	countsKnown = true
	if show and badge and not isOpen then
		badge.Visible = true
		popScale(badge, "Pop", 1.6, 0.4)
	end
end

local function hookUi(root: ScreenGui)
	gui = root
	local b = root:FindFirstChild("Backdrop")
	backdrop = if b and b:IsA("GuiButton") then b else nil
	local p = root:FindFirstChild("Panel")
	panel = if p and p:IsA("GuiObject") then p else nil
	local body = p and p:FindFirstChild("Body")
	bodyFrame = if body and body:IsA("GuiObject") then body else nil
	local pp = body and body:FindFirstChild("Pop")
	pop = if pp and pp:IsA("UIScale") then pp else nil
	local card = body and body:FindFirstChild("Card")
	details = card and card:FindFirstChild("Details")
	local vp = details and details:FindFirstChild("Viewport")
	viewport = if vp and vp:IsA("ViewportFrame") then vp else nil
	local loadoutFrame = card and card:FindFirstChild("Loadout")
	local st = loadoutFrame and loadoutFrame:FindFirstChild("Status")
	statusLabel = if st and st:IsA("TextLabel") then st else nil
	local pool = card and card:FindFirstChild("LavaPool")
	local band = pool and pool:FindFirstChild("Band")
	for i, speed in ipairs(CFG.LavaScroll) do
		local img = band and band:FindFirstChild("Lava" .. i)
		if img and img:IsA("ImageLabel") then
			table.insert(lavaLayers, { image = img, speed = speed })
		end
	end
	if not (panel and backdrop) then
		warn("[Inventory] brak Inventory.Panel / Backdrop — panel nieaktywny")
		return
	end
	-- Panel łapie kliknięcia — inaczej klik w puste miejsce panelu przelatywałby do tła i zamykał.
	(panel :: GuiObject).Active = true
	if backdrop then backdrop.Activated:Connect(function() setOpen(false) end) end
	local close = body and body:FindFirstChild("CloseButton")
	if close and close:IsA("GuiButton") then
		hookHover(close, "Hover")
		close.Activated:Connect(function() setOpen(false) end)
	end

	-- Karty: jedna na każdy item gry (też x0 — szara, z ceną; widać, co istnieje).
	local shelf = card and card:FindFirstChild("Shelf")
	local grid = shelf and shelf:FindFirstChild("Grid")
	local template = grid and grid:FindFirstChild("ItemTemplate")
	if template and template:IsA("GuiButton") then
		for order, itemId in ipairs(ItemDefinitions.shopOrder) do
			local tile = template:Clone()
			tile.Name = itemId
			tile.LayoutOrder = order
			tile.Visible = true
			tile.Parent = grid
			tiles[itemId] = tile
			hookHover(tile, "Hover")
			tile.MouseEnter:Connect(function()
				hoveredItem = itemId
				showDetails(itemId)
				refresh()
			end)
			tile.MouseLeave:Connect(function()
				if hoveredItem == itemId then hoveredItem = nil end
			end)
			tile.InputBegan:Connect(function(input)
				beginPress(input, "item", itemId, nil, tile)
			end)
			tile.Activated:Connect(function()
				if suppressClick or (drag and drag.ghost) then return end
				clickItem(itemId)
			end)
		end
	else
		warn("[Inventory] brak Card.Shelf.Grid.ItemTemplate — lista itemów nieaktywna")
	end

	for slot = 1, SLOTS do
		local btn = loadoutFrame and loadoutFrame:FindFirstChild("Slot" .. slot)
		if btn and btn:IsA("GuiButton") then
			slotButtons[slot] = btn
			local icon = btn:FindFirstChild("Icon")
			if icon and icon:IsA("GuiObject") then slotIconBase[slot] = icon.Position end
			btn.InputBegan:Connect(function(input)
				beginPress(input, "slot", LoadoutState.getLoadout()[slot], slot, btn)
			end)
			btn.Activated:Connect(function()
				if suppressClick or (drag and drag.ghost) then return end
				clickSlot(slot)
			end)
			-- PC: prawy klik = wyjmij ze slotu
			btn.MouseButton2Click:Connect(function()
				if LoadoutState.isLobby() then clearSlot(slot) else flashStatus(CFG.LockedText) end
			end)
		end
	end
	refresh()
end

local function hookButton(hud: Instance)
	local side = hud:WaitForChild("SideButtons")
	local btn = side:WaitForChild("InventoryButton")
	if not btn:IsA("GuiButton") then return end
	local bd = btn:FindFirstChild("Badge")
	badge = if bd and bd:IsA("GuiObject") then bd else nil
	hookHover(btn, "Pop")
	btn.Activated:Connect(function()
		popScale(btn, "Pop", 0.9, 0.25)
		setOpen(not isOpen)
	end)
end

local initialized = false
function InventoryController.init()
	if initialized then return end
	initialized = true

	-- Listenery stanu i klawiszy PRZED czekaniem na UI (zasada 9, paczka 3).
	LoadoutState.onChanged(function()
		updateBadge()
		if isOpen then
			-- zmiana z zewnątrz (zakup, start rundy) — licznik w DETAILS też
			local again = shownItem
			if again then setText(details, "Count", "x" .. tostring(LoadoutState.getCount(again))) end
		end
		refresh()
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == CFG.ToggleKey then
			setOpen(not isOpen)
			return
		end
		if not isOpen then return end
		local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 } :: any)[input.KeyCode]
		if n and n <= SLOTS and hoveredItem then
			if LoadoutState.isLobby() then
				assign(hoveredItem, n, tiles[hoveredItem])
			else
				flashStatus(CFG.LockedText)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local d = drag
		if not d then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local p = pointer(input)
		if not d.ghost and (p - d.start).Magnitude >= CFG.DragThreshold then
			startGhost(d, p)
		end
		if d.ghost then
			d.ghost.Position = UDim2.fromOffset(p.X, p.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not drag then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			endDrag(input)
		end
	end)

	-- Model w DETAILS i lawa pod loadoutem ruszają się tylko przy otwartym panelu.
	RunService.RenderStepped:Connect(function()
		if not isOpen then return end
		local t = os.clock()
		if spinModel then
			spinModel:PivotTo(CFrame.Angles(0, t * CFG.ModelSpin, 0))
		end
		-- Lawa płynie: obraz jest o jeden kafelek szerszy od okna, przesuw modulo kafelek = bez szwu.
		for _, layer in ipairs(lavaLayers) do
			local tile = layer.image.TileSize.X.Offset
			if tile > 0 then
				layer.image.Position = UDim2.fromOffset(-((t * layer.speed) % tile), 0)
			end
		end
	end)

	task.spawn(function()
		local pg = localPlayer:WaitForChild("PlayerGui")
		task.spawn(function()
			hookButton(pg:WaitForChild("HUD"))
		end)
		local root = pg:WaitForChild("Inventory")
		if root:IsA("ScreenGui") then
			hookUi(root)
		end
	end)
end

return InventoryController
