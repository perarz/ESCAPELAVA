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
-- wracamy do poprzedniego typu, default camera dogoni gracza (MovementController snapuje).
-- FREEZE: PlayerModule:GetControls():Disable() — postać stoi, mimo że kamera odjechała.
--
-- SERVER AUTHORITY: klik KUP = tylko intent (Remotes.BuyItem). Serwer waliduje odległość
-- do NPC, kasę i inventory (ShopService). Klient nic nie przyznaje sam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local LoadoutState = require(script.Parent.LoadoutState)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)

local ShopController = {}

local CFG = Config.Shop
local localPlayer = Players.LocalPlayer

-- cf = gotowy kadr (pozycja kamery + kierunek na model). Liczony RAZ przy otwarciu
-- sklepu: ani markery, ani wystawa nie ruszają się w trakcie, więc nie ma czego śledzić.
type Entry = { id: string, def: any, cf: CFrame }
-- Model itemu znaleziony na wystawie, zanim dobierzemy mu kamerę.
type Display = { id: string, def: any, center: Vector3, size: Vector3 }

local isOpen = false
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
local elStatus: TextLabel? = nil
local btnBuy: TextButton? = nil
local btnPrev: TextButton? = nil
local btnNext: TextButton? = nil
local btnClose: TextButton? = nil

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

-- Trwający przejazd kamery między itemami. Trzymany, żeby zamknięcie sklepu mogło go
-- przerwać — inaczej przez resztę tweena pisał Camera.CFrame i szarpał kadr już po
-- oddaniu kamery graczowi (przegląd 29.09, B-20).
local activeTween: Tween? = nil

local function stopCameraTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function focusCamera(instant: boolean)
	local cam = Workspace.CurrentCamera
	local e = entries[index]
	if not cam or not e then return end
	local goal = e.cf
	stopCameraTween()
	if instant then
		cam.CFrame = goal
	else
		local tween = TweenService:Create(
			cam,
			TweenInfo.new(CFG.CameraTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = goal }
		)
		activeTween = tween
		tween:Play()
	end
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
	if elStatus then elStatus.Text = "" end

	local canAfford = currentCash >= (def.price or 0)
	if btnBuy then
		btnBuy.AutoButtonColor = canAfford
		btnBuy.BackgroundColor3 = canAfford and Color3.fromRGB(46, 160, 70) or Color3.fromRGB(70, 74, 82)
		btnBuy.Text = canAfford and "KUP" or "ZA MAŁO $"
	end
end

local function setIndex(newIndex: number, instant: boolean)
	if #entries == 0 then return end
	-- Zawijanie: przewijanie za ostatni item wraca na pierwszy i odwrotnie.
	index = ((newIndex - 1) % #entries) + 1
	focusCamera(instant)
	refreshUI()
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

-- Kadr awaryjny (item bez markera): odsuwamy się od modelu w stronę ŚRODKA sceny, czyli
-- do wnętrza pomieszczenia. Wystawa stoi przy ścianie, więc odsunięcie "byle w bok"
-- wsadziłoby kamerę w ścianę. Dystans rośnie z wielkością modelu — dystans dobrany pod
-- bombę ucinałby RPG.
local function autoCFrame(center: Vector3, size: Vector3, sceneCenter: Vector3): CFrame
	local away = center - sceneCenter
	away = Vector3.new(away.X, 0, away.Z)
	-- Model dokładnie w środku sceny → nie ma kierunku "na zewnątrz"; cofamy się wzdłuż Z.
	local dir = if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, 1)
	local dist = math.max(CFG.AutoCameraDistance, size.Magnitude * CFG.AutoCameraSizeFactor)
	return CFrame.lookAt(
		center + dir * dist + Vector3.new(0, CFG.AutoCameraHeight, 0),
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
	local sceneCenter = boundsOf(scene) or Vector3.zero

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
	local camsFolder = scene:FindFirstChild(CFG.CamerasFolder)
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
	else
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
			cf = autoCFrame(d.center, d.size, sceneCenter)
		end
		table.insert(entries, { id = d.id, def = d.def, cf = cf })
	end
end

local function closeShop()
	if not isOpen then return end
	isOpen = false
	if ui then ui.Enabled = false end
	setFrozen(false)
	stopCameraTween()
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = savedCamType or Enum.CameraType.Custom
	end
end

local function openShop()
	if isOpen then return end
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
	readCash()

	local cam = Workspace.CurrentCamera
	if cam then
		savedCamType = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end
	setFrozen(true)
	ui.Enabled = true
	setIndex(1, true)
end

local function tryBuy()
	local e = entries[index]
	if not e then return end
	if elStatus then
		elStatus.TextColor3 = Color3.fromRGB(210, 210, 215)
		elStatus.Text = "..."
	end
	Remotes.BuyItem:FireServer(e.id)
end

-- ============================================================================
-- Init
-- ============================================================================

local BUY_FAIL_TEXT = {
	not_enough_cash = "Za mało kasy",
	too_far = "Podejdź do sprzedawcy",
	unknown_item = "Nieznany przedmiot",
	inventory_full = "Ekwipunek pełny",
	invalid_payload = "Błąd",
	internal_error = "Błąd serwera",
}

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
		if not elStatus then return end
		if success then
			elStatus.TextColor3 = Color3.fromRGB(120, 220, 120)
			-- Loadout pełny → item leży w ekwipunku; mówimy o tym od razu (18.10). Serwer wysyła
			-- LoadoutChanged PRZED ShopResult, więc stan jest już aktualny.
			elStatus.Text = if LoadoutState.slotOf(itemId) then "Kupiono!" else Config.UI.Inventory.ShopFullText
		else
			elStatus.TextColor3 = Color3.fromRGB(235, 90, 80)
			elStatus.Text = (reason and BUY_FAIL_TEXT[reason]) or "Nie udało się"
		end
	end)

	-- Force-close: start rundy (teleport) lub respawn nie mogą zostawić zablokowanej kamery.
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: any)
		if newState ~= "LOBBY" and isOpen then
			closeShop()
		end
	end)
	localPlayer.CharacterAdded:Connect(function()
		if isOpen then
			closeShop()
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
		elStatus = gui:FindFirstChild("StatusLabel", true) :: TextLabel?
		btnBuy = gui:FindFirstChild("BuyButton", true) :: TextButton?
		btnPrev = gui:FindFirstChild("PrevButton", true) :: TextButton?
		btnNext = gui:FindFirstChild("NextButton", true) :: TextButton?
		btnClose = gui:FindFirstChild("CloseButton", true) :: TextButton?
		gui.Enabled = false

		if btnBuy then btnBuy.Activated:Connect(tryBuy) end
		if btnPrev then btnPrev.Activated:Connect(function() setIndex(index - 1, false) end) end
		if btnNext then btnNext.Activated:Connect(function() setIndex(index + 1, false) end) end
		if btnClose then btnClose.Activated:Connect(closeShop) end
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
