--!strict
-- InventoryController.luau — panel ekwipunku: wybór 3 itemów (18.10, plan i decyzje Kacpra:
-- docs/ROADMAP.md → „PLAN: LOADOUT”). Stan czyta i zmienia przez LoadoutState; prawdę trzyma
-- serwer (LoadoutService) — tu jest tylko UI.
--
-- UKŁAD (19.10, decyzja Kacpra): GŁÓWNE OKNO (półka itemów + loadout) na środku; klik w item
-- wysuwa zza niego osobne okno DETAILS po prawej, a para zjeżdża razem na środek. Wygląd
-- klasyczny (czarne obrysy jak sloty paska, nagłówek w gradiencie licznika czasu, sloty loadoutu
-- = klony slotu paska na pasie lawy). Item w DETAILS = prawdziwy obiekt w świecie za oknem.
--
-- KONTRAKT NAZW (postawione przez MCP; opis: docs/STUDIO_CONTRACT.md → „Ekwipunek”):
--   StarterGui.Inventory (ScreenGui, ResetOnSpawn=false, IgnoreGuiInset)
--     Backdrop (cały ekran, atrybut NoHudScale) → Top/Bottom/Left/Right (TextButton) — ściemnienie
--       dookoła okna DETAILS.Window (ono pokazuje świat); klik NIE zamyka (19.10)
--     Panel.Body (UIScale Pop): CloseButton (UIScale Hover), Card:
--       Shelf.Grid (UIGridLayout) → ItemTemplate (Visible=false; UIScale Hover): SelectStroke,
--         Fill (+ Pattern1/2, Sweep), Rim, Sparkles.Star1..4 (UIScale Twinkle), Icon, ItemName,
--         Count, Price, SlotTag.Label — wzór kart: Config.UI.Inventory.CardStyles (23.10)
--       LavaPool.Band.Lava1/Lava2 (przesuwane), Loadout: Status, Slot1..3 (klon HUD.Hotbar.Slot1:
--         SelectStroke, Icon, ItemName, Count, Keybind + Empty „+”, UIScale Pop)
--     DetailsPanel.Body (UIScale Pop): CloseButton (UIScale Hover), Card: Header.ItemName / Count,
--       Window, Price, Desc, Stats.<Power|Range|Mobility>.Bar.Fill, LavaPool.Band.Lava1/Lava2,
--       ActionButton (Fill z UIGradient, Label, UIScale Hover)
--   StarterGui.HUD.SideButtons.InventoryButton (UIScale Pop) → Badge (UIScale Pop)
--
-- Sterowanie (decyzje Kacpra 18-19.10). Ekwipunek TYLKO W LOBBY: poza nim przycisk znika,
-- klawisz I nic nie robi, a otwarty panel sam się zamyka (serwer też odrzuca zmiany poza lobby).
--   * klik w item = pokaż go w DETAILS (wysuwa okno); ten sam item drugi raz albo X = schowaj.
--   * DETAILS → przycisk: ADD TO LOADOUT (wolny slot) / REMOVE (item już w loadoucie) /
--     SWAP INTO SLOT (pełny loadout → kliknij slot, który podmienić).
--   * slot: z itemem = pokaż go w DETAILS; pusty, gdy DETAILS otwarte = włóż tam pokazany item.
--   * przeciąganie: item → slot, slot ↔ slot (zamiana), slot poza sloty = wyjęcie; prawy klik slotu
--     = wyjęcie; 1/2/3 = item pod kursorem (albo pokazany w DETAILS) do tego slotu.

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
local ShopController = require(script.Parent.ShopController)

local InventoryController = {}

local CFG = Config.UI.Inventory
local SLOTS = Config.Loadout.Slots
local STAT_ROWS = { power = "Power", range = "Range", mobility = "Mobility" }
local BLACK = Color3.new(0, 0, 0)
local localPlayer = Players.LocalPlayer

local isOpen = false
local openToken = 0
local detailsOpen = false
local detailsToken = 0
local hoveredItem: string? = nil
local shownItem: string? = nil      -- item w DETAILS
local pickMode = false              -- SWAP: czekamy na klik w slot, który podmienić
local statusOverride: string? = nil
local statusToken = 0
-- Slot, do którego leci ikona: jego ikona pokaże się dopiero po przylocie (inaczej dwie ikony
-- naraz). Żeton — kolejna zmiana tego slotu unieważnia czekające lądowanie.
local landing: { [number]: number } = {}
local landingSeq = 0
-- Przeciągany przycisk: jego UIScale steruje przeciąganie, nie najechanie myszą.
local draggingButton: GuiButton? = nil

-- UI (nil, dopóki nie znalezione — każda funkcja to znosi)
local gui: ScreenGui? = nil
local backdrop: GuiObject? = nil
local backdropPieces: { [string]: GuiButton } = {}
local panel: GuiObject? = nil
local bodyFrame: GuiObject? = nil
local pop: UIScale? = nil
local detailsPanel: GuiObject? = nil
local detailsPop: UIScale? = nil
local details: Instance? = nil      -- DetailsPanel.Body.Card
local windowFrame: GuiObject? = nil
local actionButton: GuiButton? = nil
local statusLabel: TextLabel? = nil
local badge: GuiObject? = nil
local inventoryButton: GuiButton? = nil
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

-- Karta / przycisk rośnie pod kursorem (jeden UIScale na obiekt — dwa się nie sumują); karta
-- dodatkowo lekko się przechyla.
local function hookHover(btn: GuiButton, scaleName: string, tilt: number?)
	local scale = scaleOf(btn, scaleName)
	local info = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		if draggingButton == btn then return end
		TweenService:Create(scale, info, { Scale = CFG.HoverScale }):Play()
		if tilt then TweenService:Create(btn, info, { Rotation = tilt }):Play() end
	end)
	btn.MouseLeave:Connect(function()
		if draggingButton == btn then
			if tilt then TweenService:Create(btn, info, { Rotation = 0 }):Play() end
			return
		end
		TweenService:Create(scale, info, { Scale = 1 }):Play()
		if tilt then TweenService:Create(btn, info, { Rotation = 0 }):Play() end
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
			setText(statusLabel.Parent, "Status", if pickMode then CFG.PickSlotText else "")
		end
	end)
end

-- UKŁADY WSPÓŁRZĘDNYCH (19.10 — w Play item był za wysoko o pasek Robloxa, w Edit paska nie ma):
-- AbsolutePosition i InputObject.Position są w przestrzeni GUI (0 = POD paskiem Robloxa), a nasz
-- ScreenGui ma IgnoreGuiInset (0 = sam górny brzeg ekranu). Stąd: pozycja w naszym GUI = punkt
-- GUI − początek naszego GUI, a promień kamery z punktu GUI = ScreenPointToRay.
local function toLocal(p: Vector2): Vector2
	local root = gui
	if not root then return p end
	-- Początek naszego GUI w przestrzeni GUI (z paskiem i wycięciem w ekranie telefonu —
	-- DeviceSafeInsets). Gdyby silnik podał 0, a GUI ignoruje pasek — sam pasek.
	local origin = root.AbsolutePosition
	if origin.Magnitude < 0.5 and root.IgnoreGuiInset then
		origin = -GuiService:GetGuiInset()
	end
	return p - origin
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
-- WYSTAWA ITEMU W ŚWIECIE (19.10, prośba Kacpra: „kręcenie się itemu i real oświetlenie”).
-- ViewportFrame ma jedno proste światło (bez cieni i odblasków) — item wyglądał szaro. Dlatego item
-- jest prawdziwym obiektem w świecie: lokalna kopia (dziecko kamery = nikt inny jej nie widzi,
-- zero kolizji i zapytań — zasada 10), POMNIEJSZONA do `ShowcaseRadius`, żeby siedziała tuż przed
-- kamerą i nic ze świata nie weszło między nią a okno. Lampy jak na zdjęciach ikon, za itemem
-- ciemne tło ze studsami. Co klatkę ustawiana za `DetailsPanel…Window` (panel ma tam dziurę).
-- ============================================================================

local SHOWCASE_STUDS = "rbxassetid://6927295847"
local showcase: Model? = nil
local showcaseItem: Model? = nil
local showcaseBack: BasePart? = nil
local showcaseLamps: { { part: BasePart, offset: Vector3 } } = {}

local function findSceneModel(name: string): Instance?
	local scene = Workspace:FindFirstChild(Config.Shop.SceneName, true)
	local folder = scene and scene:FindFirstChild(Config.Shop.ItemsFolder)
	return folder and folder:FindFirstChild(name)
end

local function ghostPart(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function clearShowcase()
	if showcase then showcase:Destroy() end
	showcase, showcaseItem, showcaseBack = nil, nil, nil
	table.clear(showcaseLamps)
end

local function buildShowcase(itemId: string)
	clearShowcase()
	local cam = Workspace.CurrentCamera
	local def = ItemDefinitions.get(itemId)
	local source = def and def.sceneModel and findSceneModel(def.sceneModel)
	if not (cam and windowFrame and source) then return end
	local holder = Instance.new("Model")
	holder.Name = "InventoryShowcase"
	local item = Instance.new("Model")
	item.Name = "Item"
	local copy = source:Clone()
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Light") or d:IsA("ProximityPrompt") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	if copy:IsA("BasePart") then
		copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch = true, false, false, false
	end
	copy.Parent = item
	item.Parent = holder
	local cf, size = item:GetBoundingBox()
	item.WorldPivot = CFrame.new(cf.Position)
	item:ScaleTo(CFG.ShowcaseRadius / math.max(size.Magnitude / 2, 0.05))
	local R = CFG.ShowcaseRadius
	for _, l in ipairs(CFG.ShowcaseLights) do
		local p = ghostPart("Lamp", Vector3.new(0.02, 0.02, 0.02))
		p.Transparency = 1
		local light = Instance.new("PointLight")
		light.Brightness = l.brightness
		light.Range = l.range * R
		light.Color = l.color
		light.Shadows = l.shadows
		light.Parent = p
		p.Parent = holder
		table.insert(showcaseLamps, { part = p, offset = l.offset * R })
	end
	-- Tło: ciemne ze studsami jak panel; kamera widzi jego tylną ścianę (część patrzy jak kamera).
	local back = ghostPart("Back", Vector3.new(1, 1, 0.02))
	-- Neon = kolor bez wpływu świateł: tło zostaje równo ciemne, lampy oświetlają tylko item.
	back.Material = Enum.Material.Neon
	back.Color = CFG.ShowcaseBackColor
	local tex = Instance.new("Texture")
	tex.Texture = SHOWCASE_STUDS
	tex.Face = Enum.NormalId.Back
	tex.StudsPerTileU = R * 1.6
	tex.StudsPerTileV = R * 1.6
	tex.Color3 = CFG.ShowcaseBackColor
	tex.Transparency = 0.6
	tex.Parent = back
	back.Parent = holder
	holder.Parent = cam
	showcase, showcaseItem, showcaseBack = holder, item, back
end

-- Co klatkę PO kamerze: item na promieniu przez środek okna, w odległości, przy której zajmuje
-- `ShowcaseFill` wysokości okna. Obrót kamery = obrót wystawy, więc item nie pływa po ekranie.
local function placeShowcase(t: number)
	local cam = Workspace.CurrentCamera
	local win = windowFrame
	local item = showcaseItem
	if not (cam and win and item) then return end
	local pos, size = win.AbsolutePosition, win.AbsoluteSize
	local vp = cam.ViewportSize
	if size.Y < 2 or vp.Y < 2 then return end
	local centre = pos + size / 2
	local ray = cam:ScreenPointToRay(centre.X, centre.Y)
	local tanHalf = math.tan(math.rad(cam.FieldOfView / 2))
	local R = CFG.ShowcaseRadius
	local frac = size.Y / vp.Y
	local dist = R / (CFG.ShowcaseFill * frac * tanHalf)
	local base = CFrame.new(ray.Origin + ray.Direction * dist) * cam.CFrame.Rotation
	item:PivotTo(base * CFrame.Angles(math.rad(CFG.ModelTilt), 0, 0) * CFrame.Angles(0, t * CFG.ModelSpin, 0))
	for _, l in ipairs(showcaseLamps) do
		l.part.CFrame = base * CFrame.new(l.offset)
	end
	local back = showcaseBack
	if back then
		-- Tło na TYM SAMYM promieniu co item (okno jest z boku ekranu — przesunięcie wzdłuż osi
		-- kamery zjechałoby z okna i odsłoniło niebo).
		local far = dist + R * CFG.ShowcaseBackDepth
		-- odrobinę większe od okna (krawędź chowa czarna ramka okna), ale nie wystaje poza panel
		local h = 2 * far * tanHalf * frac * 1.05
		back.Size = Vector3.new(h * size.X / size.Y, h, 0.02)
		back.CFrame = CFrame.new(ray.Origin + ray.Direction * far) * cam.CFrame.Rotation
	end
end

-- Ściemnienie gry DOOKOŁA okna (cztery prostokąty), bo przez okno patrzymy na świat.
local function placeBackdropPiece(name: string, x: number, y: number, w: number, h: number)
	local piece = backdropPieces[name]
	if not piece then return end
	piece.Position = UDim2.fromOffset(x, y)
	piece.Size = UDim2.fromOffset(math.max(w, 0), math.max(h, 0))
end

local function layoutBackdrop()
	local root = gui
	if not root then return end
	local W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
	local x0, y0, x1, y1 = 0, 0, 0, 0
	local win = windowFrame
	if win and isOpen and detailsOpen and showcase then
		local tl = toLocal(win.AbsolutePosition)
		x0, y0 = tl.X, tl.Y
		x1, y1 = x0 + win.AbsoluteSize.X, y0 + win.AbsoluteSize.Y
	end
	-- Te same cztery prostokąty bez pięciu tymczasowych tabel co klatkę.
	placeBackdropPiece("Top", 0, 0, W, y0)
	placeBackdropPiece("Bottom", 0, y1, W, H - y1)
	placeBackdropPiece("Left", 0, y0, x0, y1 - y0)
	placeBackdropPiece("Right", x1, y0, W - x1, y1 - y0)
end

-- ============================================================================
-- DETAILS: zawartość i przycisk akcji
-- ============================================================================

local function paintAction()
	local btn = actionButton
	local id = shownItem
	if not btn then return end
	local loadout = LoadoutState.getLoadout()
	local inLoadout = id ~= nil and table.find(loadout, id) ~= nil
	local full = table.find(loadout, "") == nil
	local text, colors
	if inLoadout then
		text, colors = CFG.RemoveText, CFG.RemoveColors
	elseif full then
		text, colors = (if pickMode then CFG.PickSlotText else CFG.SwapText), CFG.SwapColors
	else
		text, colors = CFG.AddText, CFG.AddColors
	end
	setText(btn, "Label", text)
	local fill = btn:FindFirstChild("Fill")
	local grad = fill and fill:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(colors[1], colors[2])
	end
end

local function showDetails(itemId: string)
	if itemId ~= shownItem then pickMode = false end
	shownItem = itemId
	local def = ItemDefinitions.get(itemId)
	if not def or not details then return end
	local header = details:FindFirstChild("Header")
	local count = LoadoutState.getCount(itemId)
	setText(header, "ItemName", string.upper(def.name or itemId))
	setText(header, "Count", "x" .. tostring(count))
	setText(details, "Desc", def.desc or "")
	setVisible(details, "Price", count <= 0)
	setText(details, "Price", tostring(def.price) .. "$")
	-- nazwa i licznik podskakują razem z cieniami (ta sama kotwica = cień zostaje pod tekstem)
	if header then
		for _, n in ipairs({ "ItemName", "ItemNameShadow", "Count", "CountShadow" }) do
			local l = header:FindFirstChild(n)
			if l then popScale(l, "Pop", 1.18, 0.3) end
		end
	end
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
	paintAction()
	if isOpen and detailsOpen then buildShowcase(itemId) end
end

-- ============================================================================
-- Wysuwanie DETAILS: główne okno w lewo, DETAILS zza niego w prawo, para na środku
-- ============================================================================

-- Przesunięcia w px projektu × skala HUD (UIScale okna nie skaluje jego własnej pozycji).
local function hudScale(obj: GuiObject?): number
	local s = obj and obj:FindFirstChild("HudScale")
	return if s and s:IsA("UIScale") then s.Scale else 1
end

local function slideOffsets(open: boolean): (number, number)
	local p, d = panel, detailsPanel
	if not (p and d) then return 0, 0 end
	local mw = p.Size.X.Offset * hudScale(p)
	local dw = d.Size.X.Offset * hudScale(d)
	local gap = CFG.DetailsGap * hudScale(p)
	if open then
		return -(dw + gap) / 2, (mw + gap) / 2
	end
	-- schowane: DETAILS za głównym oknem (prawa krawędź równo z jego prawą krawędzią)
	return 0, (mw - dw) / 2
end

local function setDetails(open: boolean, instant: boolean?)
	local p, d = panel, detailsPanel
	if not (p and d) then return end
	if open == detailsOpen and not instant then return end
	detailsOpen = open
	detailsToken += 1
	local token = detailsToken
	local pX, dX = slideOffsets(open)
	local info = TweenInfo.new(CFG.DetailsSlideTime, if open then Enum.EasingStyle.Back else Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local function target(obj: GuiObject, x: number): UDim2
		return UDim2.new(obj.Position.X.Scale, x, obj.Position.Y.Scale, obj.Position.Y.Offset)
	end
	if open then
		if not d.Visible then
			local _, hiddenX = slideOffsets(false)
			d.Position = target(d, hiddenX)
			d.Visible = true
		end
		if shownItem then buildShowcase(shownItem) end
		if detailsPop and not instant then
			-- wysuwa się i lekko „wyskakuje” (Back), jak klocek wyjęty z pudełka
			detailsPop.Scale = 0.85
			TweenService:Create(detailsPop, info, { Scale = 1 }):Play()
		end
	else
		pickMode = false
		clearShowcase()
	end
	if instant then
		p.Position = target(p, pX)
		d.Position = target(d, dX)
		d.Visible = open
		return
	end
	TweenService:Create(p, info, { Position = target(p, pX) }):Play()
	TweenService:Create(d, info, { Position = target(d, dX) }):Play()
	if not open then
		task.delay(CFG.DetailsSlideTime, function()
			if token == detailsToken and not detailsOpen then d.Visible = false end
		end)
	end
end

-- ============================================================================
-- Odświeżanie kart i slotów
-- ============================================================================

-- ── Wzór kart (23.10) — opis i liczby: Config.UI.Inventory.CardStyles ──────────────────────

-- Paski z twardymi brzegami w jednym gradiencie przezroczystości. Pas = 4 punkty (jego dwa końce
-- i dwa brzegi przerwy), a Roblox przyjmuje najwyżej 20 punktów — stąd do 4 pasów na warstwę.
local function stripeSequence(count: number, width: number, alpha: number): NumberSequence
	local n = math.clamp(math.floor(count), 1, 4)
	local period = 1 / n
	local w = math.clamp(width, 0.05, 0.95) * period
	local e = 0.002
	local kps: { NumberSequenceKeypoint } = {}
	for i = 0, n - 1 do
		local a = i * period
		table.insert(kps, NumberSequenceKeypoint.new(a, alpha))
		table.insert(kps, NumberSequenceKeypoint.new(a + w, alpha))
		table.insert(kps, NumberSequenceKeypoint.new(a + w + e, 1))
		table.insert(kps, NumberSequenceKeypoint.new(a + period - e, 1))
	end
	table.insert(kps, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(kps)
end

type AnimatedCard = { sweep: UIGradient?, sweepEvery: number, stars: { UIScale }, phase: number }
local animatedCards: { AnimatedCard } = {}

-- Raz przy tworzeniu karty: wzór, ramka i które dodatki się ruszają. Kolor bazy zostaje
-- w `paintCard` (x0 = szara), wzór i dodatki są takie same przy x0 — widać, co warto kupić.
local function styleCard(tile: GuiButton, itemId: string)
	local style = (CFG.CardStyles :: any)[itemId]
	local fill = tile:FindFirstChild("Fill")
	local layers = if style and style.Layers then style.Layers else {}
	for i = 1, 2 do
		local frame = fill and fill:FindFirstChild("Pattern" .. i)
		local layer = layers[i]
		if frame and frame:IsA("GuiObject") then
			frame.Visible = layer ~= nil
			local g = frame:FindFirstChildOfClass("UIGradient")
			if layer and g then
				frame.BackgroundColor3 = layer.Color
				g.Rotation = layer.Rotation
				g.Offset = Vector2.new(layer.Offset or 0, 0)
				g.Transparency = stripeSequence(layer.Count, layer.Width, layer.Transparency)
			end
		end
	end

	local rim = tile:FindFirstChild("Rim")
	if rim and rim:IsA("GuiObject") then
		local colors = style and style.Rim
		rim.Visible = colors ~= nil
		local stroke = rim:FindFirstChildOfClass("UIStroke")
		local g = stroke and stroke:FindFirstChildOfClass("UIGradient")
		if colors and g then g.Color = ColorSequence.new(colors[1], colors[2]) end
	end

	-- Faza zależna od kolejności: dwie karty z błyskiem nie błyskają naraz.
	local card: AnimatedCard = { sweep = nil, sweepEvery = 0, stars = {}, phase = #animatedCards * 0.9 }
	local sweep = fill and fill:FindFirstChild("Sweep")
	if sweep and sweep:IsA("GuiObject") then
		sweep.Visible = style ~= nil and style.Sweep ~= nil
		if sweep.Visible then
			card.sweep = sweep:FindFirstChildOfClass("UIGradient")
			card.sweepEvery = style.Sweep
		end
	end
	local sparkles = tile:FindFirstChild("Sparkles")
	if sparkles and sparkles:IsA("GuiObject") then
		sparkles.Visible = style ~= nil and style.Sparkles == true
		if sparkles.Visible then
			for _, star in ipairs(sparkles:GetChildren()) do
				local s = star:FindFirstChild("Twinkle")
				if s and s:IsA("UIScale") then table.insert(card.stars, s) end
			end
		end
	end
	if card.sweep or #card.stars > 0 then
		table.insert(animatedCards, card)
	end
end

-- Błysk i iskierki liczone z zegara i tylko przy otwartym panelu: zamknięty ekwipunek nic nie
-- kosztuje, a nie ma tweenów, które trzeba by przerywać przy zamknięciu.
local function animateCards()
	if not isOpen then return end
	local now = os.clock()
	for _, card in ipairs(animatedCards) do
		local sweep = card.sweep
		if sweep then
			local t = ((now + card.phase) % card.sweepEvery) / CFG.CardSweepTime
			-- Pas błysku w gradiencie stoi na 0,5: przesunięcie ±1,2 chowa go za krawędzią karty.
			sweep.Offset = Vector2.new(if t < 1 then -1.2 + 2.4 * t else -1.2, 0)
		end
		for i, s in ipairs(card.stars) do
			local u = (now / CFG.CardSparklePeriod + i / #card.stars + card.phase) % 1
			-- Krótkie mignięcie na początku okresu, potem przerwa.
			s.Scale = if u < 0.35 then math.sin(u / 0.35 * math.pi) else 0
		end
	end
end

local function paintCard(tile: GuiButton, itemId: string)
	local def = ItemDefinitions.get(itemId)
	local count = LoadoutState.getCount(itemId)
	-- x0 = szara karta: od razu widać, czego brakuje, zanim ruszy runda.
	local color = if count > 0 then itemColor(itemId) else CFG.EmptyItemColor
	local fill = tile:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		fill.BackgroundColor3 = color
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

-- Slot jak w pasku: ten sam zapis napisów (x1 bez licznika, x0 widoczne).
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
			local was = tag.Visible and tag:GetAttribute("Slot")
			tag.Visible = slot ~= nil
			if slot then
				setText(tag, "Label", tostring(slot))
				if was ~= slot then popScale(tag, "Pop", 1.6, 0.35) end -- nowy numer = wskok
			end
			tag:SetAttribute("Slot", slot)
		end
		setSelected(tile, detailsOpen and itemId == shownItem)
	end
	for slot, btn in pairs(slotButtons) do
		local id = loadout[slot]
		paintSlot(btn, slot, if id ~= "" then id else nil)
		setSelected(btn, pickMode)
	end
	if statusLabel and not statusOverride then
		setText(statusLabel.Parent, "Status", if pickMode then CFG.PickSlotText else "")
	end
	if shownItem and details then
		setText(details:FindFirstChild("Header"), "Count", "x" .. tostring(LoadoutState.getCount(shownItem)))
		setVisible(details, "Price", LoadoutState.getCount(shownItem) <= 0)
	end
	paintAction()
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
	local a = toLocal(icon.AbsolutePosition + icon.AbsoluteSize / 2)
	local b = toLocal(to.AbsolutePosition + to.AbsoluteSize / 2)
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

-- Item → slot. Item już w innym slocie = zamiana miejscami (nic nie znika po cichu).
local function assign(itemId: string, slot: number, fromBtn: GuiObject?, quiet: boolean?)
	local loadout = LoadoutState.getLoadout()
	local was = table.find(loadout, itemId)
	if was == slot then return end
	if was then
		loadout[was] = loadout[slot]
	end
	loadout[slot] = itemId
	pickMode = false
	LoadoutState.set(loadout)
	if was and loadout[was] ~= "" then snapSlot(was) end
	if quiet then return end
	if fromBtn then
		flyIcon(fromBtn, slot)
	else
		snapSlot(slot)
	end
end

local function clearSlot(slot: number)
	local loadout = LoadoutState.getLoadout()
	if loadout[slot] == "" then return end
	loadout[slot] = ""
	landing[slot] = nil
	LoadoutState.set(loadout)
end

-- Przycisk w DETAILS: dodaj / wyjmij / podmień.
local function onAction()
	local id = shownItem
	if not id then return end
	local loadout = LoadoutState.getLoadout()
	local was = table.find(loadout, id)
	if was then
		clearSlot(was)
	else
		local free = table.find(loadout, "")
		if free then
			assign(id, free, tiles[id])
		else
			-- pełny loadout: teraz klik w slot = podmiana
			pickMode = not pickMode
			if pickMode then
				flashStatus(CFG.PickSlotText)
				for _, btn in pairs(slotButtons) do shake(btn) end
			end
		end
	end
	refresh()
end

local function clickItem(itemId: string)
	if detailsOpen and shownItem == itemId then
		setDetails(false)
		refresh()
		return
	end
	showDetails(itemId)
	setDetails(true)
	refresh()
end

local function clickSlot(slot: number)
	local id = LoadoutState.getLoadout()[slot]
	if pickMode and shownItem then
		assign(shownItem, slot, tiles[shownItem])
		refresh()
		return
	end
	if id ~= "" then
		showDetails(id)
		setDetails(true)
	elseif detailsOpen and shownItem then
		assign(shownItem, slot, tiles[shownItem])
	end
	refresh()
end

-- ============================================================================
-- Przeciąganie (mysz i dotyk)
-- ============================================================================

-- Przeciągana jest CAŁA karta / cały slot (19.10, prośba Kacpra): klon w GUI pod kursorem,
-- przechyla się w stronę ruchu; upuszczony na slot wskakuje do niego sprężyście, upuszczony obok
-- wraca sprężyście na miejsce (slot upuszczony obok = wyjęty — klon kurczy się i znika).
type Drag = {
	kind: "item" | "slot", itemId: string, slot: number?, from: GuiButton, start: Vector2,
	ghost: GuiObject?, grab: Vector2, tilt: number, lastX: number,
}
local drag: Drag? = nil
local suppressClick = false

-- Wskaźnik w przestrzeni GUI — tej samej co AbsolutePosition (trafienia w sloty).
local function pointer(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
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

local function beginPress(input: InputObject, kind: "item" | "slot", itemId: string, slot: number?, from: GuiButton)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if itemId == "" then return end
	local p = pointer(input)
	drag = { kind = kind, itemId = itemId, slot = slot, from = from, start = p, ghost = nil,
		grab = Vector2.zero, tilt = 0, lastX = p.X }
end

-- UIScale, którym oryginał „ustępuje” na czas przeciągania (karta: Hover, slot: Pop).
local function originScale(d: Drag): UIScale
	return scaleOf(d.from, if d.kind == "item" then "Hover" else "Pop")
end

local function startGhost(d: Drag, p: Vector2)
	if not gui then return end
	local from = d.from
	local ghost = from:Clone() :: GuiButton
	for _, c in ipairs(ghost:GetChildren()) do
		if c:IsA("UIScale") then c:Destroy() end
	end
	ghost:SetAttribute("NoHudScale", true) -- PRZED parentem: HudScale łapie ChildAdded
	ghost.Active = false
	ghost.AutoButtonColor = false
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Rotation = 0
	ghost.ZIndex = 50
	-- Klon żyje poza oknem, więc skalę HUD dostaje wprost (rozmiar jak oryginał na ekranie).
	local base = hudScale(panel)
	local sc = Instance.new("UIScale")
	sc.Name = "DragScale"
	sc.Scale = base
	sc.Parent = ghost
	-- chwyt w tym miejscu karty, za które złapano (karta nie przeskakuje środkiem pod kursor)
	d.grab = (from.AbsolutePosition + from.AbsoluteSize / 2) - p
	local lp = toLocal(p + d.grab)
	ghost.Position = UDim2.fromOffset(lp.X, lp.Y)
	ghost.Parent = gui
	d.ghost = ghost
	draggingButton = from
	TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = base * CFG.DragLift,
	}):Play()
	-- oryginał: mniejszy, „miejsce po wyjętym klocku”
	TweenService:Create(originScale(d), TweenInfo.new(0.15), { Scale = CFG.DragOriginScale }):Play()
	if d.kind == "slot" then
		local icon = from:FindFirstChild("Icon")
		if icon and icon:IsA("GuiObject") then icon.Visible = false end
	end
end

local function moveGhost(d: Drag, p: Vector2)
	local ghost = d.ghost
	if not ghost then return end
	local lp = toLocal(p + d.grab)
	ghost.Position = UDim2.fromOffset(lp.X, lp.Y)
	-- przechył w stronę ruchu (wygasa w kroku klatki, gdy kursor stoi)
	local target = math.clamp((p.X - d.lastX) * CFG.DragTiltPerPx, -CFG.DragTiltMax, CFG.DragTiltMax)
	d.tilt = d.tilt * 0.5 + target * 0.5
	d.lastX = p.X
end

local function endDrag(input: InputObject?)
	local d = drag
	drag = nil
	if not d then return end
	local ghost = d.ghost
	if not ghost then return end
	draggingButton = nil
	suppressClick = true
	task.defer(function() suppressClick = false end)
	local sc = ghost:FindFirstChild("DragScale") :: UIScale?
	local base = hudScale(panel)
	local origin = originScale(d)
	local function restoreOrigin()
		TweenService:Create(origin, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local drop = if input then slotAt(pointer(input)) else nil
	if drop and slotButtons[drop] then
		-- wskakuje do slotu: leci na środek slotu i sprężynuje; ikona slotu pokazuje się,
		-- gdy klon już tam jest (landing), a slot podskakuje
		local to = slotButtons[drop]
		landingSeq += 1
		local token = landingSeq
		landing[drop] = token
		assign(d.itemId, drop, nil, true)
		refresh()
		local c = toLocal(to.AbsolutePosition + to.AbsoluteSize / 2)
		local info = TweenInfo.new(CFG.DropTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		TweenService:Create(ghost, info, { Position = UDim2.fromOffset(c.X, c.Y), Rotation = 0 }):Play()
		if sc then
			TweenService:Create(sc, info, { Scale = base * to.Size.X.Offset / math.max(ghost.Size.X.Offset, 1) }):Play()
		end
		task.delay(CFG.DropTime * 0.55, function()
			ghost:Destroy()
			restoreOrigin()
			if landing[drop] == token then
				landing[drop] = nil
				refresh()
			end
			popScale(to, "Pop", 1.15, 0.3)
		end)
	elseif input and d.kind == "slot" and d.slot then
		-- slot upuszczony obok slotów = wyjęty z loadoutu: klon kurczy się i znika z obrotem
		clearSlot(d.slot)
		local info = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		TweenService:Create(ghost, info, { Rotation = ghost.Rotation + 35 }):Play()
		if sc then TweenService:Create(sc, info, { Scale = 0 }):Play() end
		task.delay(0.26, function()
			ghost:Destroy()
			restoreOrigin()
			refresh()
		end)
	else
		-- nigdzie: wraca sprężyście na swoje miejsce
		local c = toLocal(d.from.AbsolutePosition + d.from.AbsoluteSize / 2)
		local info = TweenInfo.new(CFG.ReturnTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		TweenService:Create(ghost, info, { Position = UDim2.fromOffset(c.X, c.Y), Rotation = 0 }):Play()
		if sc then TweenService:Create(sc, info, { Scale = base }):Play() end
		task.delay(CFG.ReturnTime * 0.6, function()
			ghost:Destroy()
			restoreOrigin()
			refresh()
		end)
	end
end

-- ============================================================================
-- Otwieranie / zamykanie
-- ============================================================================

-- Otwarcie: karty, potem sloty wskakują po kolei (skala 0 → 1, Back).
local function playIntro()
	local n = 0
	local function intro(obj: Instance, scaleName: string)
		n += 1
		local scale = scaleOf(obj, scaleName)
		scale.Scale = 0
		TweenService:Create(scale, TweenInfo.new(CFG.IntroTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false,
			CFG.IntroDelay + n * CFG.IntroStagger), { Scale = 1 }):Play()
	end
	for _, itemId in ipairs(ItemDefinitions.shopOrder) do
		local tile = tiles[itemId]
		if tile then intro(tile, "Hover") end
	end
	for slot = 1, SLOTS do
		local btn = slotButtons[slot]
		if btn then intro(btn, "Pop") end
	end
end

local function setOpen(open: boolean)
	if open == isOpen or not (panel and backdrop) then return end
	-- W sklepie ekwipunku nie ma (23.10, Kacper) — panel wchodziłby na panel sklepu.
	if open and (not LoadoutState.isLobby() or ShopController.isOpen() or Players.LocalPlayer:GetAttribute("CosmeticsOpen") == true) then return end
	isOpen = open
	openToken += 1
	local token = openToken
	local p = panel :: GuiObject
	local b = backdrop :: GuiObject
	local info = TweenInfo.new(CFG.OpenTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local back = TweenInfo.new(CFG.OpenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if open then
		if badge then badge.Visible = false end
		pickMode = false
		setDetails(false, true) -- start zawsze samym głównym oknem na środku
		p.Visible = true
		b.Visible = true
		layoutBackdrop()
		for _, piece in pairs(backdropPieces) do
			piece.BackgroundTransparency = 1
			TweenService:Create(piece, info, { BackgroundTransparency = CFG.BackdropTransparency }):Play()
		end
		if bodyFrame then
			bodyFrame.Position = UDim2.fromOffset(0, -CFG.OpenDrop)
			TweenService:Create(bodyFrame, back, { Position = UDim2.fromOffset(0, 0) }):Play()
		end
		if pop then
			pop.Scale = CFG.ClosedScale
			TweenService:Create(pop, back, { Scale = 1 }):Play()
		end
		refresh()
		playIntro()
	else
		endDrag(nil)
		hoveredItem = nil
		setDetails(false, true)
		for _, piece in pairs(backdropPieces) do
			TweenService:Create(piece, info, { BackgroundTransparency = 1 }):Play()
		end
		if pop then
			TweenService:Create(pop, info, { Scale = CFG.ClosedScale }):Play()
		end
		if bodyFrame then
			TweenService:Create(bodyFrame, TweenInfo.new(CFG.OpenTime * 0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(0, CFG.CloseDrop),
			}):Play()
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

local function findLava(card: Instance?)
	local pool = card and card:FindFirstChild("LavaPool")
	local band = pool and pool:FindFirstChild("Band")
	for i, speed in ipairs(CFG.LavaScroll) do
		local img = band and band:FindFirstChild("Lava" .. i)
		if img and img:IsA("ImageLabel") then
			table.insert(lavaLayers, { image = img, speed = speed })
		end
	end
end

local function hookUi(root: ScreenGui)
	gui = root
	local b = root:FindFirstChild("Backdrop")
	backdrop = if b and b:IsA("GuiObject") then b else nil
	for _, name in ipairs({ "Top", "Bottom", "Left", "Right" }) do
		local piece = b and b:FindFirstChild(name)
		if piece and piece:IsA("GuiButton") then
			-- 19.10 (Kacper): klik w tło NIE zamyka — tylko X albo I. Przycisk dalej łapie klik,
			-- żeby nie poleciał do gry (rzut bombą, strzał hakiem).
			backdropPieces[name] = piece
		end
	end
	local p = root:FindFirstChild("Panel")
	panel = if p and p:IsA("GuiObject") then p else nil
	local body = p and p:FindFirstChild("Body")
	bodyFrame = if body and body:IsA("GuiObject") then body else nil
	local pp = body and body:FindFirstChild("Pop")
	pop = if pp and pp:IsA("UIScale") then pp else nil
	local card = body and body:FindFirstChild("Card")
	local loadoutFrame = card and card:FindFirstChild("Loadout")
	local st = loadoutFrame and loadoutFrame:FindFirstChild("Status")
	statusLabel = if st and st:IsA("TextLabel") then st else nil
	findLava(card)

	local dp = root:FindFirstChild("DetailsPanel")
	detailsPanel = if dp and dp:IsA("GuiObject") then dp else nil
	local dbody = dp and dp:FindFirstChild("Body")
	local dpop = dbody and dbody:FindFirstChild("Pop")
	detailsPop = if dpop and dpop:IsA("UIScale") then dpop else nil
	details = dbody and dbody:FindFirstChild("Card")
	local win = details and details:FindFirstChild("Window")
	windowFrame = if win and win:IsA("GuiObject") then win else nil
	local act = details and details:FindFirstChild("ActionButton")
	actionButton = if act and act:IsA("GuiButton") then act else nil
	findLava(details)

	if not (panel and backdrop) then
		warn("[Inventory] brak Inventory.Panel / Backdrop — panel nieaktywny")
		return
	end
	-- Okna łapią kliknięcia — inaczej klik w puste miejsce przelatywałby do tła i zamykał.
	(panel :: GuiObject).Active = true
	if detailsPanel then (detailsPanel :: GuiObject).Active = true end
	local close = body and body:FindFirstChild("CloseButton")
	if close and close:IsA("GuiButton") then
		hookHover(close, "Hover")
		close.Activated:Connect(function() setOpen(false) end)
	end
	local dclose = dbody and dbody:FindFirstChild("CloseButton")
	if dclose and dclose:IsA("GuiButton") then
		hookHover(dclose, "Hover")
		dclose.Activated:Connect(function()
			setDetails(false)
			refresh()
		end)
	end
	if actionButton then
		hookHover(actionButton, "Hover")
		actionButton.Activated:Connect(function()
			popScale(actionButton :: GuiButton, "Hover", 0.9, 0.2)
			onAction()
		end)
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
			styleCard(tile, itemId)
			tile.Visible = true
			tile.Parent = grid
			tiles[itemId] = tile
			hookHover(tile, "Hover", CFG.HoverTilt)
			tile.MouseEnter:Connect(function() hoveredItem = itemId end)
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
				clearSlot(slot)
			end)
		end
	end
	setDetails(false, true)
	refresh()
end

-- Przycisk widać tylko w lobby i poza sklepem.
local function updateButton()
	if inventoryButton then
		inventoryButton.Visible = LoadoutState.isLobby() and not ShopController.isOpen() and Players.LocalPlayer:GetAttribute("CosmeticsOpen") ~= true
	end
end

local function hookButton(hud: Instance)
	local side = hud:WaitForChild("SideButtons")
	local btn = side:WaitForChild("InventoryButton")
	if not btn:IsA("GuiButton") then return end
	local bd = btn:FindFirstChild("Badge")
	badge = if bd and bd:IsA("GuiObject") then bd else nil
	inventoryButton = btn
	updateButton()
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
	Players.LocalPlayer:GetAttributeChangedSignal("CosmeticsOpen"):Connect(function()
		if Players.LocalPlayer:GetAttribute("CosmeticsOpen") == true then setOpen(false) end
		updateButton()
	end)

	-- Listenery stanu i klawiszy PRZED czekaniem na UI (zasada 9, paczka 3).
	LoadoutState.onChanged(function()
		updateBadge()
		-- poza lobby ekwipunku nie ma: przycisk znika, otwarty panel się zamyka
		local lobby = LoadoutState.isLobby()
		updateButton()
		if not lobby and isOpen then setOpen(false) end
		refresh()
	end)
	-- Sklep otwarty → przycisk znika, otwarty panel się zamyka; po wyjściu przycisk wraca.
	ShopController.onOpenChanged(function(shopOpen: boolean)
		updateButton()
		if shopOpen and isOpen then setOpen(false) end
	end)

	RunService.Heartbeat:Connect(animateCards)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == CFG.ToggleKey then
			setOpen(not isOpen)
			return
		end
		if not isOpen then return end
		local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 } :: any)[input.KeyCode]
		local id = hoveredItem or (if detailsOpen then shownItem else nil)
		if n and n <= SLOTS and id then
			assign(id, n, tiles[id])
			refresh()
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
		moveGhost(d, p)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not drag then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			endDrag(input)
		end
	end)

	-- Wystawa itemu, ściemnienie wokół okna i lawa — tylko przy otwartym panelu. Krok PO kamerze
	-- (i po jej drżeniu/przechyle z MovementController), inaczej item odstawałby od okna o klatkę.
	RunService:BindToRenderStep("InventoryShowcase", Enum.RenderPriority.Last.Value, function()
		if not isOpen then return end
		local t = os.clock()
		placeShowcase(t)
		layoutBackdrop()
		local d = drag
		if d and d.ghost then
			d.ghost.Rotation += (d.tilt - d.ghost.Rotation) * 0.25
			d.tilt *= 0.85
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
