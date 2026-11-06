--!strict
-- ShopController.luau
-- SKLEP-NPC. Gracz podchodzi do sprzedawcy (ProximityPrompt) → tryb sklepu: kamera
-- przeskakuje (Scriptable) do SCENY SKLEPU i celuje w wystawiony model itemu, postać
-- zostaje przy sprzedawcy (sterowanie wyłączone), na dole StarterGui.ShopUI.
-- ◀▶ w UI, klawisze A/D i scroll przewijają itemy (kamera płynnie jedzie do następnego).
--
-- GRACZ NIE JEST TELEPORTOWANY do sceny (decyzja 2026-09-20) — jedzie sama kamera.
-- Dlatego scena może stać dowolnie daleko od lobby, kilku graczy może kupować naraz
-- bez wchodzenia sobie w kadr, a start rundy nie musi nikogo stamtąd wyciągać.
--
-- KONTRAKT (nazwy w Config.Shop):
--   Workspace.<SceneName>.<ItemsFolder>.<def.sceneModel>  — model itemu na wystawie
--   Workspace.<SceneName>.<CamerasFolder>/*               — markery pozycji kamery
--
-- PAROWANIE MARKERA Z ITEMEM IDZIE PO ODLEGŁOŚCI, NIE PO NAZWIE. Marker należy do tego
-- modelu, któremu jest najbliższy — tak jak dawniej SHOPCAMERA{N} celowała w najbliższy
-- part z SHOPITEMS. Dzięki temu dodanie itemu to postawienie modelu i markera obok niego,
-- a pomyłka w nazwie markera niczego nie psuje (w Studio nazwy BombCamera/BlueprintCamera
-- są dziś zamienione względem pozycji i kadry mimo to wychodzą poprawnie).
-- Item BEZ markera dostaje kadr policzony z bounding boxa — sklep nigdy nie jest pusty
-- tylko dlatego, że ktoś nie zdążył postawić markera.
--
-- KAMERA: ustawiamy CameraType=Scriptable — MovementController SAM wtedy wyłącza swoje
-- rotation-smoothing i shake (sprawdza CameraType), więc nie ma konfliktu kamer. Na wyjściu
-- wracamy do poprzedniego typu i przepinamy CameraSubject na AKTUALNĄ postać (start rundy
-- podmienia postać w trakcie zakupów), default camera dogoni gracza (MovementController snapuje).
-- Od 06.11 tween jedzie po lokalnym `camBase`, a Camera.CFrame pisze jedna pętla co klatkę
-- (`camBase` + lekkie krążenie za myszą) — dwaj piszący do kamery by się szarpali.
-- FREEZE: PlayerModule:GetControls():Disable() — postać stoi, mimo że kamera odjechała.
--
-- SERVER AUTHORITY: klik KUP = tylko intent (Remotes.BuyItem). Serwer waliduje odległość
-- do NPC, kasę i inventory (ShopService). Klient nic nie przyznaje sam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local LoadoutState = require(script.Parent.LoadoutState)
local SparkleBurst = require(script.Parent.SparkleBurst)
local LobbySign = require(script.Parent.LobbySign)
local ShopFx = require(script.Parent.ShopFx)
local RoundSkipState = require(script.Parent.RoundSkipState)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)

local ShopController = {}

local CFG = Config.Shop
local localPlayer = Players.LocalPlayer

-- cf = gotowy kadr (pozycja kamery + kierunek na model). Liczony RAZ przy otwarciu
-- sklepu: ani markery, ani wystawa nie ruszają się w trakcie, więc nie ma czego śledzić.
type Entry = { id: string, def: any, cf: CFrame, center: Vector3 }
-- Model itemu znaleziony na wystawie, zanim dobierzemy mu kamerę.
type Display = { id: string, def: any, center: Vector3, size: Vector3 }

local isOpen = false
-- Kto chce wiedzieć, że sklep się otworzył/zamknął (23.10: ekwipunek chowa się na czas zakupów).
local openListeners: { (boolean) -> () } = {}
local entries: { Entry } = {}
local index = 1
local savedCamType: Enum.CameraType? = nil
local currentCash = 0
local initialized = false

-- UI refs
local ui: ScreenGui? = nil
local elItemName: TextLabel? = nil
local elPrice: TextLabel? = nil
local elDesc: TextLabel? = nil
local btnBuy: TextButton? = nil
local btnPrev: TextButton? = nil
local btnNext: TextButton? = nil
local btnClose: TextButton? = nil
local elCash: TextLabel? = nil       -- 21.10: kasa gracza w panelu (`ShopCash`, opcjonalny)
local buySparkles: Instance? = nil   -- 01.11: `Panel.BuySparkles` — błysk gwiazdek po udanym zakupie
local elStats: Instance? = nil       -- 21.10: `Stats.<Power|Range|Mobility>.Bar.Fill` jak w ekwipunku
-- Tablica, nie słownik: paski ruszają jeden po drugim, więc kolejność ma znaczenie (06.11).
local STAT_ROWS = {
	{ key = "power", row = "Power" },
	{ key = "range", row = "Range" },
	{ key = "mobility", row = "Mobility" },
}

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if warned[key] then return end
	warned[key] = true
	warn("[Shop] " .. msg)
end

-- ============================================================================
-- Kasa (affordability) — z leaderstats + live update z CashChanged
-- ============================================================================

local function readCash()
	local ls = localPlayer:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		currentCash = cash.Value
	end
end

-- ============================================================================
-- Freeze sterowania
-- ============================================================================

local function getControls(): any
	local ok, controls = pcall(function()
		local ps = localPlayer:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if not pm then return nil end
		return (require(pm) :: any):GetControls()
	end)
	if ok then return controls end
	return nil
end

local function setFrozen(frozen: boolean)
	local controls = getControls()
	if not controls then return end
	if frozen then
		controls:Disable()
	else
		controls:Enable()
	end
end

-- ============================================================================
-- Kamera
-- ============================================================================

-- Kadr bez krążenia za myszą i odległość do oglądanego itemu (środek krążenia). Lokalne wartości
-- poza placem: tween przesuwa je, a na kamerę przenosi je `cameraLoop`.
local camBase = Instance.new("CFrameValue")
local camOrbit = Instance.new("NumberValue")
local activeTweens: { Tween } = {}

local function stopCameraTween()
	for _, tween in ipairs(activeTweens) do tween:Cancel() end
	table.clear(activeTweens)
end

local function focusCamera(instant: boolean)
	local e = entries[index]
	if not e then return end
	local goal = e.cf
	local orbit = (goal.Position - e.center).Magnitude
	stopCameraTween()
	if instant then
		camBase.Value = goal
		camOrbit.Value = orbit
	else
		local info = TweenInfo.new(CFG.CameraTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		activeTweens = {
			TweenService:Create(camBase, info, { Value = goal }),
			TweenService:Create(camOrbit, info, { Value = orbit }),
		}
		for _, tween in ipairs(activeTweens) do tween:Play() end
	end
end

local cameraConn: RBXScriptConnection? = nil
local mouseOffset = Vector2.zero

-- Gdzie jest kursor względem środka ekranu (-1…1). Na dotyku i padzie kursora nie ma, więc kamera
-- wraca na środek zamiast krążyć wokół ostatniego palca.
local function mouseTarget(cam: Camera): Vector2
	local last = UserInputService:GetLastInputType()
	if not UserInputService.MouseEnabled or last == Enum.UserInputType.Touch or last.Name:sub(1, 7) == "Gamepad" then
		return Vector2.zero
	end
	local at = UserInputService:GetMouseLocation()
	local size = cam.ViewportSize
	return Vector2.new(math.clamp(at.X / size.X * 2 - 1, -1, 1), math.clamp(at.Y / size.Y * 2 - 1, -1, 1))
end

local function stopCameraLoop()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
end

local function startCameraLoop()
	stopCameraLoop()
	mouseOffset = Vector2.zero
	local parallax = CFG.CameraParallax
	cameraConn = RunService.RenderStepped:Connect(function(dt: number)
		local cam = Workspace.CurrentCamera
		if not cam then return end
		mouseOffset = mouseOffset:Lerp(mouseTarget(cam), 1 - math.exp(-parallax.Rate * dt))
		-- Krążenie wokół itemu: item zostaje na środku kadru, przesuwa się tło.
		local pitch = math.rad(parallax.PitchDegrees) * mouseOffset.Y
		local yaw = math.rad(parallax.YawDegrees) * mouseOffset.X
		cam.CFrame = camBase.Value
			* CFrame.new(0, 0, -camOrbit.Value)
			* CFrame.Angles(pitch, yaw, 0)
			* CFrame.new(0, 0, camOrbit.Value)
	end)
end

-- ============================================================================
-- UI
-- ============================================================================

local function refreshUI()
	local e = entries[index]
	if not e then return end
	local def = e.def
	if elItemName then elItemName.Text = tostring(def.name or e.id) end
	if elPrice then elPrice.Text = tostring(def.price or 0) .. "$" end
	if elDesc then elDesc.Text = tostring(def.desc or "") end
	if elCash then elCash.Text = tostring(currentCash) .. "$" end

	-- Paski cech (21.10) — jak w ekwipunku: pasek = StatMax studsów, wartość = świecące studsy.
	local invCfg = Config.UI.Inventory
	local statValues = (def :: any).stats or {}
	for i, stat in ipairs(STAT_ROWS) do
		local row = elStats and elStats:FindFirstChild(stat.row)
		local bar = row and row:FindFirstChild("Bar")
		local fill = bar and bar:FindFirstChild("Fill")
		if fill and fill:IsA("GuiObject") then
			local v = math.clamp((tonumber(statValues[stat.key]) or 0) / invCfg.StatMax, 0, 1)
			fill.Visible = v > 0
			local info = TweenInfo.new(
				invCfg.StatTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, (i - 1) * CFG.Fx.StatStagger
			)
			TweenService:Create(fill, info, { Size = UDim2.fromScale(v, 1) }):Play()
		end
	end

	local canAfford = currentCash >= (def.price or 0)
	ShopFx.setCanAfford(canAfford)
	if btnBuy then
		btnBuy.AutoButtonColor = canAfford
		local text = if canAfford then CFG.BuyText else CFG.NoCashText
		-- Nowy przycisk (21.10): napis w `Label`, kolor w gradiencie `Fill` (jak ADD w ekwipunku).
		local label = btnBuy:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = text
		else
			btnBuy.Text = text
		end
		local fill = btnBuy:FindFirstChild("Fill")
		local grad = fill and fill:FindFirstChildOfClass("UIGradient")
		local colors = if canAfford then CFG.BuyColors else CFG.NoCashColors
		if grad then
			grad.Color = ColorSequence.new(colors[1], colors[2])
		else
			btnBuy.BackgroundColor3 = colors[1]
		end
	end
end

local function setIndex(newIndex: number, instant: boolean)
	if #entries == 0 then return end
	-- Kierunek przed zawinięciem: ◀ na pierwszym itemie to nadal „w lewo”.
	local direction = if instant then 0 elseif newIndex > index then 1 else -1
	-- Zawijanie: przewijanie za ostatni item wraca na pierwszy i odwrotnie.
	index = ((newIndex - 1) % #entries) + 1
	focusCamera(instant)
	-- Czyszczone tutaj, nie w refreshUI: CashChanged odświeża panel zaraz po zakupie (06.11).
	ShopFx.clearStatus()
	refreshUI()
	ShopFx.itemChanged(index, direction)
end

-- Paski cech rosną od zera przy otwarciu sklepu (06.11).
local function resetStatBars()
	for _, stat in ipairs(STAT_ROWS) do
		local row = elStats and elStats:FindFirstChild(stat.row)
		local bar = row and row:FindFirstChild("Bar")
		local fill = bar and bar:FindFirstChild("Fill")
		if fill and fill:IsA("GuiObject") then
			fill.Size = UDim2.fromScale(0, 1)
		end
	end
end

-- ============================================================================
-- Open / close
-- ============================================================================

-- Środek i rozmiar modelu bierzemy z BOUNDING BOXA, nie z pivota: pivot modelu bywa
-- ustawiony gdziekolwiek (róg podstawki, punkt obrotu), a kamera ma celować w to, co widać.
local function boundsOf(inst: Instance): (Vector3?, Vector3?)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position, size
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

-- Kadr (21.10): kamera NAPRZECIW itemu, w głąb pomieszczenia. Wystawa stoi wzdłuż dłuższego
-- boku sceny, więc „w głąb” = krótsza pozioma oś sceny, zwrócona do jej środka. Do 21.10 kamera
-- szła OD środka sceny (wbrew opisowi) i lądowała za ścianą wystawy. Odległość z wielkości
-- itemu i FOV: item zajmuje `AutoCameraFill` ekranu — puszka i RPG wyglądają podobnie duże.
local function roomDirection(center: Vector3, sceneCF: CFrame, sceneSize: Vector3): Vector3
	local axis = if sceneSize.X < sceneSize.Z then sceneCF.RightVector else sceneCF.LookVector
	axis = Vector3.new(axis.X, 0, axis.Z)
	if axis.Magnitude < 1e-3 then axis = Vector3.xAxis end
	axis = axis.Unit
	local toCenter = sceneCF.Position - center
	if axis:Dot(toCenter) < 0 then axis = -axis end
	return axis
end

local function autoCFrame(center: Vector3, size: Vector3, sceneCF: CFrame, sceneSize: Vector3): CFrame
	-- 23.10 (Kacper: „lekki kąt do itema”): kierunek obrócony w poziomie o AutoCameraYaw —
	-- item widać trochę z boku, nie płasko na wprost. Ten sam obrót dla wszystkich kadrów,
	-- więc sortowanie po RightVector niżej dalej idzie wzdłuż ściany.
	local dir = CFrame.Angles(0, math.rad(CFG.AutoCameraYaw), 0)
		:VectorToWorldSpace(roomDirection(center, sceneCF, sceneSize))
	local cam = Workspace.CurrentCamera
	local halfFov = math.rad((if cam then cam.FieldOfView else 70) * 0.5)
	local radius = size.Magnitude * 0.5
	local dist = math.max(CFG.AutoCameraMinDistance, radius / math.tan(halfFov) / CFG.AutoCameraFill)
	local lift = dist * math.tan(math.rad(CFG.AutoCameraPitch))
	return CFrame.lookAt(
		center + dir * dist + Vector3.new(0, lift, 0),
		center + Vector3.new(0, CFG.LookAtHeightOffset, 0)
	)
end

local function buildEntries()
	table.clear(entries)

	local scene = Workspace:FindFirstChild(CFG.SceneName)
	if not scene then
		warnOnce("scene", ("brak Workspace.%s — sklep nieaktywny"):format(CFG.SceneName))
		return
	end
	local itemsFolder = scene:FindFirstChild(CFG.ItemsFolder)
	if not itemsFolder then
		warnOnce("items", ("brak Workspace.%s.%s — nie ma czego pokazać"):format(
			CFG.SceneName, CFG.ItemsFolder))
		return
	end
	local sceneCF, sceneSize = scene:GetBoundingBox()

	-- 1. Modele itemów ze sklepu. Item bez modelu wypada z listy — z warnem, nie z błędem:
	--    brak jednej dekoracji nie może zamknąć całego sklepu.
	local displays: { Display } = {}
	for _, id in ipairs(ItemDefinitions.shopOrder) do
		local def = ItemDefinitions.get(id)
		local modelName = def and def.sceneModel
		if not modelName then
			warnOnce("def_" .. id, ("item %s nie ma pola sceneModel — pomijam w sklepie"):format(id))
		else
			local model = itemsFolder:FindFirstChild(modelName)
			if not model then
				warnOnce("model_" .. id, ("brak modelu %s.%s.%s — item %s pominięty"):format(
					CFG.SceneName, CFG.ItemsFolder, modelName, id))
			else
				local center, size = boundsOf(model)
				if center and size then
					table.insert(displays, { id = id, def = def, center = center, size = size })
				end
			end
		end
	end
	if #displays == 0 then return end

	-- 2. Marker należy do modelu, któremu jest NAJBLIŻSZY — nie do tego, jak się nazywa.
	--    Reguła działa w obie strony (dwa markery przy jednym modelu → wygrywa bliższy),
	--    więc nie da się jej rozjechać literówką ani zamienioną nazwą.
	local markerFor: { [number]: BasePart } = {}
	local markerDist: { [number]: number } = {}
	local camsFolder = if CFG.UseCameraMarkers then scene:FindFirstChild(CFG.CamerasFolder) else nil
	if camsFolder then
		for _, part in ipairs(camsFolder:GetChildren()) do
			if part:IsA("BasePart") then
				local bestIdx: number? = nil
				local bestDist = math.huge
				for i, d in ipairs(displays) do
					local dist = (part.Position - d.center).Magnitude
					if dist < bestDist then
						bestDist = dist
						bestIdx = i
					end
				end
				if bestIdx and bestDist < (markerDist[bestIdx] or math.huge) then
					markerFor[bestIdx] = part
					markerDist[bestIdx] = bestDist
				end
			end
		end
	elseif CFG.UseCameraMarkers then
		warnOnce("cams", ("brak Workspace.%s.%s — kadry liczone automatycznie"):format(
			CFG.SceneName, CFG.CamerasFolder))
	end

	-- 3. Kadr. Marker niesie wyłącznie POZYCJĘ — kierunek zawsze liczy lookAt na model,
	--    więc obrót markera w Studio nie ma znaczenia i nie trzeba go ustawiać.
	for i, d in ipairs(displays) do
		local lookAt = d.center + Vector3.new(0, CFG.LookAtHeightOffset, 0)
		local marker = markerFor[i]
		local cf: CFrame
		if marker and (lookAt - marker.Position).Magnitude > 0.05 then
			cf = CFrame.lookAt(marker.Position, lookAt)
		else
			cf = autoCFrame(d.center, d.size, sceneCF, sceneSize)
		end
		table.insert(entries, { id = d.id, def = d.def, cf = cf, center = d.center })
	end

	-- Kolejność = tak, jak itemy wiszą na ścianie, od lewej (21.10, Kacper: „zła kolejność”):
	-- do tej pory szła z `shopOrder`, więc ◀▶ skakało po ścianie tam i z powrotem. „W prawo”
	-- = prawa strona kadru, a wszystkie kadry patrzą w tę samą ścianę.
	local right = entries[1] and entries[1].cf.RightVector or Vector3.xAxis
	table.sort(entries, function(a, b)
		return a.center:Dot(right) < b.center:Dot(right)
	end)
end

-- Światło sceny: stałe lampki w placu (`<SceneName>.Arsenal.Wall`), kod ich nie dotyka. Do 23.10
-- jedna lampa jechała za kamerą — po każdym przewinięciu oświetlenie doganiało ją kilka sekund
-- (Kacper: „mija kilka sekund, zanim załadują się w nowym miejscu”).
--
-- Jasność na czas zakupów (23.10). Plamy światła lamp Roblox rysuje dopiero na wyższej jakości
-- grafiki, a „Automatic” startuje nisko i podnosi się po chwili — stąd „lampy ładują się po
-- czasie”, a na najniższej jakości sklep zawsze wyglądał słabo (Kacper potwierdził zmianą jakości
-- w ustawieniach; w Edit na poziomie 3 plam nie ma wcale). `Lighting.Ambient` działa na KAŻDEJ
-- jakości od pierwszej klatki, więc u oglądającego podnosimy go na czas sklepu, a lampy dokładają
-- plamy, kiedy silnik pozwoli. Nikt inny w grze nie pisze `Ambient` (23.10), więc zapamiętanie
-- i oddanie wartości wystarcza.
local savedAmbient: Color3? = nil

local function setShopAmbient(on: boolean)
	if on then
		savedAmbient = savedAmbient or Lighting.Ambient
		Lighting.Ambient = CFG.SceneAmbient
	elseif savedAmbient then
		Lighting.Ambient = savedAmbient
		savedAmbient = nil
	end
end

local function notifyOpen()
	for _, cb in ipairs(openListeners) do
		task.spawn(cb, isOpen)
	end
end

-- `character` = postać, która właśnie się pojawiła (zamknięcie z CharacterAdded).
local function closeShop(character: Model?)
	if not isOpen then return end
	isOpen = false
	notifyOpen()
	ShopFx.close(function()
		if ui then ui.Enabled = false end
	end)
	setFrozen(false)
	stopCameraLoop()
	stopCameraTween()
	setShopAmbient(false)
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = savedCamType or Enum.CameraType.Custom
		-- Start rundy przy otwartym sklepie (23.10, Kacper: „kamera w lobby, ciało na arenie”):
		-- serwer robi LoadCharacter, a nowa postać przychodzi, gdy kamera jest jeszcze
		-- Scriptable — Roblox nie przepina wtedy CameraSubject, więc po oddaniu kamery
		-- śledziłaby starą, skasowaną postać w lobby. Przepinamy ją sami na aktualną.
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

local function openShop()
	if isOpen then return end
	if localPlayer:GetAttribute("CosmeticsOpen") == true then return end
	if not ui then
		warnOnce("ui", "brak StarterGui.ShopUI — sklep nieaktywny")
		return
	end
	buildEntries()
	if #entries == 0 then
		warnOnce("empty", "żaden item ze shopOrder nie ma modelu na wystawie — nie ma co pokazać")
		return
	end
	isOpen = true
	notifyOpen()
	readCash()

	local cam = Workspace.CurrentCamera
	if cam then
		savedCamType = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end
	setFrozen(true)
	setShopAmbient(true)
	ui.Enabled = true
	resetStatBars()
	ShopFx.open(#entries)
	setIndex(1, true)
	startCameraLoop()
end

local function tryBuy()
	local e = entries[index]
	if not e then return end
	ShopFx.setStatus("...", Color3.fromRGB(210, 210, 215), false)
	Remotes.BuyItem:FireServer(e.id)
end

-- Przewijanie i zakup tylko przy otwartym sklepie: panel zjeżdża jeszcze chwilę po zamknięciu,
-- a kliknięcie strzałki w tym czasie ruszyłoby wartości kamery i treść panelu.
local function stepItem(delta: number)
	if isOpen then setIndex(index + delta, false) end
end

function ShopController.isOpen(): boolean
	return isOpen
end

-- `cb(open)` przy każdym otwarciu i zamknięciu sklepu.
function ShopController.onOpenChanged(cb: (boolean) -> ())
	table.insert(openListeners, cb)
end

-- ============================================================================
-- Init
-- ============================================================================


function ShopController.init()
	if initialized then return end
	initialized = true

	-- Listenery PRZED czekaniem na ShopUI (zasada 9, paczka 3): stan kasy przychodzi zaraz po
	-- `ClientReady`, a na wolnym telefonie ShopUI może jeszcze nie istnieć.
	-- Affordability: initial z leaderstats + live z CashChanged.
	readCash()
	Remotes.CashChanged.OnClientEvent:Connect(function(balance: any)
		if type(balance) == "number" then
			currentCash = balance
			if isOpen then refreshUI() end
		end
	end)

	-- Feedback zakupu.
	Remotes.ShopResult.OnClientEvent:Connect(function(success: boolean, itemId: string, reason: string?)
		if success then
			-- Loadout pełny → item leży w ekwipunku; mówimy o tym od razu (18.10). Serwer wysyła
			-- LoadoutChanged PRZED ShopResult, więc stan jest już aktualny.
			local text = if LoadoutState.slotOf(itemId) then CFG.BoughtText else Config.UI.Inventory.ShopFullText
			ShopFx.setStatus(text, Color3.fromRGB(120, 220, 120), true)
			ShopFx.bought()
			SparkleBurst.play(buySparkles)
		else
			local text = (reason and (CFG.FailTexts :: any)[reason]) or CFG.FailDefault
			ShopFx.setStatus(text, Color3.fromRGB(235, 90, 80), true)
			ShopFx.failed()
		end
	end)

	-- Force-close: start rundy (teleport) lub respawn nie mogą zostawić zablokowanej kamery.
	-- Pomijający rundę stoi w lobby i kupuje dalej (06.11).
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: any)
		if newState ~= "LOBBY" and isOpen and not RoundSkipState.isSittingOut() then
			closeShop()
		end
	end)
	localPlayer.CharacterAdded:Connect(function(character: Model)
		if isOpen then
			closeShop(character)
		end
	end)

	-- UI refs (ShopUI ResetOnSpawn=false → persistuje).
	local pg = localPlayer:WaitForChild("PlayerGui")
	local gui = pg:WaitForChild("ShopUI")
	if gui and gui:IsA("ScreenGui") then
		ui = gui
		elItemName = gui:FindFirstChild("ItemName", true) :: TextLabel?
		elPrice = gui:FindFirstChild("Price", true) :: TextLabel?
		elDesc = gui:FindFirstChild("Description", true) :: TextLabel?
		btnBuy = gui:FindFirstChild("BuyButton", true) :: TextButton?
		btnPrev = gui:FindFirstChild("PrevButton", true) :: TextButton?
		btnNext = gui:FindFirstChild("NextButton", true) :: TextButton?
		btnClose = gui:FindFirstChild("CloseButton", true) :: TextButton?
		local cashLabel = gui:FindFirstChild("ShopCash", true)
		elCash = if cashLabel and cashLabel:IsA("TextLabel") then cashLabel else nil
		elStats = gui:FindFirstChild("Stats", true)
		buySparkles = gui:FindFirstChild("BuySparkles", true)
		gui.Enabled = false
		ShopFx.bind(gui)

		if btnBuy then btnBuy.Activated:Connect(function() if isOpen then tryBuy() end end) end
		if btnPrev then btnPrev.Activated:Connect(function() stepItem(-1) end) end
		if btnNext then btnNext.Activated:Connect(function() stepItem(1) end) end
		-- Owinięte: Activated podaje (InputObject, clickCount), a closeShop bierze postać.
		if btnClose then btnClose.Activated:Connect(function() closeShop() end) end
	else
		warnOnce("ui", "brak StarterGui.ShopUI (ScreenGui) — sklep nieaktywny")
	end

	-- Prompt tworzy ShopService (albo Kacper stawia własny o tej samej nazwie), więc do
	-- klienta może dojechać PO nas — jednorazowe sprawdzenie by go przegapiło. Szukamy po
	-- NAZWIE, nie po ścieżce: klient nie musi wiedzieć, gdzie w dekoracjach siedzi NPC,
	-- a przyszłe stoisko skinów dostanie własną nazwę promptu i się nie pomyli z tym.
	task.spawn(function()
		local lobby = Workspace:WaitForChild("Lobby", 30)
		if not lobby then
			warnOnce("lobby", "brak Workspace.Lobby — sklep nie otworzy się promptem")
			return
		end
		-- Napis SHOP nad sprzedawcą: lawa płynie przez litery, za ścianami napis znika (LobbySign).
		local sign = lobby:FindFirstChild(CFG.SignName, true)
		local label = sign and sign:FindFirstChild("Label", true)
		local grad = label and label:FindFirstChild("Lava")
		if sign and sign:IsA("BillboardGui") and grad and grad:IsA("UIGradient") then
			local own = lobby:FindFirstChild(CFG.ShopModelName, true) or sign.Parent :: Instance
			LobbySign.start(sign, grad, own, CFG.SignFlowColors, CFG.SignFlowSpeed, CFG.SignFlowSpan)
		end
		local hooked = false
		local function hook(inst: Instance)
			if hooked or not inst:IsA("ProximityPrompt") or inst.Name ~= CFG.PromptName then
				return
			end
			hooked = true
			inst.Triggered:Connect(openShop)
		end
		for _, d in ipairs(lobby:GetDescendants()) do
			hook(d)
		end
		lobby.DescendantAdded:Connect(hook)
		task.delay(20, function()
			if not hooked then
				warnOnce("prompt", ("brak ProximityPrompt '%s' pod Workspace.Lobby — sklep nie otworzy się promptem"):format(
					CFG.PromptName))
			end
		end)
	end)

	-- Klawisze (A/D scroll, Q wyjście) + scroll myszy — tylko gdy sklep otwarty.
	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if not isOpen or gp then return end
		if input.KeyCode == CFG.PrevKey then
			setIndex(index - 1, false)
		elseif input.KeyCode == CFG.NextKey then
			setIndex(index + 1, false)
		elseif input.KeyCode == CFG.CloseKey then
			closeShop()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
		if not isOpen or gp then return end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			-- Scroll w górę (Z>0) = poprzedni item.
			setIndex(index - (if input.Position.Z > 0 then 1 else -1), false)
		end
	end)
end

return ShopController
