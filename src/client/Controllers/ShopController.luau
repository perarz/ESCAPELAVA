--!strict
-- ShopController.luau
-- SKLEP-NPC. Gracz podchodzi do sprzedawcy (ProximityPrompt) → tryb sklepu: kamera
-- przypina się (Scriptable) do markera SHOPCAMERA{N} i CELUJE w wystawiony model itemu,
-- postać zamrożona (sterowanie wyłączone), na dole StarterGui.ShopUI (KUP / cena / opis).
-- ◀▶ w UI, klawisze A/D i scroll przewijają itemy (kamera płynnie jedzie do następnego).
--
-- MAPOWANIE (kontrakt w Config.Shop): SHOPCAMERA{N} → ItemDefinitions.shopOrder[N].
-- Marker niesie tylko POZYCJĘ kamery — jego obrót jest nieistotny, bo kierunek liczymy
-- przez CFrame.lookAt na model itemu. Modelem jest NAJBLIŻSZY markerowi part z SHOPITEMS,
-- więc Kacper nie musi niczego nazywać ani parować ręcznie.
-- SKALOWANIE: dodanie itemu = kolejny SHOPCAMERA{N} + model obok. Zero kodu tutaj.
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
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)

local ShopController = {}

local CFG = Config.Shop
local localPlayer = Players.LocalPlayer

-- target = model itemu, w który kamera celuje (nil → patrzymy wzdłuż obrotu markera).
type Entry = { id: string, def: any, camPart: BasePart, target: BasePart? }

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

-- Kadr: kamera SIEDZI na markerze i PATRZY na model itemu. Obrót markera celowo ignorujemy
-- — marker niesie tylko pozycję (w mapie stoją nieobrócone), celowanie liczy kod.
local function goalCFrame(e: Entry): CFrame
	local target = e.target
	if target and target.Parent then
		local lookPoint = target.Position + Vector3.new(0, CFG.LookAtHeightOffset, 0)
		-- Degeneracja: marker dokładnie w punkcie celu → lookAt rzuca; wtedy obrót markera.
		if (lookPoint - e.camPart.Position).Magnitude > 0.05 then
			return CFrame.lookAt(e.camPart.Position, lookPoint)
		end
	end
	return e.camPart.CFrame
end

local function focusCamera(instant: boolean)
	local cam = Workspace.CurrentCamera
	local e = entries[index]
	if not cam or not e or not e.camPart.Parent then return end
	local goal = goalCFrame(e)
	if instant then
		cam.CFrame = goal
	else
		TweenService:Create(
			cam,
			TweenInfo.new(CFG.CameraTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = goal }
		):Play()
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

-- Model, w który celuje dany marker = NAJBLIŻSZY part z SHOPITEMS. Dzięki temu nie trzeba
-- parować nazw ani kolejności — marker stoi obok swojego itemu i to wystarcza.
local function nearestDisplay(camPart: BasePart, itemsFolder: Instance?): BasePart?
	if not itemsFolder then return nil end
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, d in ipairs(itemsFolder:GetDescendants()) do
		if d:IsA("BasePart") then
			local dist = (d.Position - camPart.Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = d
			end
		end
	end
	return best
end

local function buildEntries()
	table.clear(entries)
	local lobby = Workspace:FindFirstChild("Lobby")
	local cams = lobby and lobby:FindFirstChild(CFG.CamerasFolder)
	if not cams then
		warnOnce("cams", ("brak Workspace.Lobby.%s — sklep nieaktywny"):format(CFG.CamerasFolder))
		return
	end
	local itemsFolder = lobby and lobby:FindFirstChild(CFG.ItemsFolder)

	-- Marker SHOPCAMERA{N} ↔ N-ty item w shopOrder. Item bez markera po prostu nie pojawia
	-- się w sklepie (Kacper dostawia marker, gdy zrobi mu wystawę).
	for i, id in ipairs(ItemDefinitions.shopOrder) do
		local def = ItemDefinitions.get(id)
		local part = cams:FindFirstChild(CFG.CameraPrefix .. tostring(i))
		if def and part and part:IsA("BasePart") then
			table.insert(entries, {
				id = id,
				def = def,
				camPart = part,
				target = nearestDisplay(part, itemsFolder),
			})
		end
	end
end

local function closeShop()
	if not isOpen then return end
	isOpen = false
	if ui then ui.Enabled = false end
	setFrozen(false)
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
		warnOnce("empty", "brak part-kamer w SHOPCAMERAS nazwanych itemId (np. 'bomb') — nie ma co pokazać")
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

	-- UI refs (ShopUI ResetOnSpawn=false → persistuje).
	local pg = localPlayer:WaitForChild("PlayerGui")
	local gui = pg:WaitForChild("ShopUI", 15)
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

	-- ProximityPrompt na NPC (może dojechać z opóźnieniem — czekamy w tle).
	task.spawn(function()
		local lobby = Workspace:WaitForChild("Lobby", 20)
		local npc = lobby and lobby:WaitForChild(CFG.NpcName, 20)
		local prompt = npc and npc:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			prompt.Triggered:Connect(openShop)
		else
			warnOnce("prompt", ("brak ProximityPrompt na %s — sklep nie otworzy się promptem"):format(CFG.NpcName))
		end
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

	-- Affordability: initial z leaderstats + live z CashChanged.
	readCash()
	Remotes.CashChanged.OnClientEvent:Connect(function(balance: any)
		if type(balance) == "number" then
			currentCash = balance
			if isOpen then refreshUI() end
		end
	end)

	-- Feedback zakupu.
	Remotes.ShopResult.OnClientEvent:Connect(function(success: boolean, _itemId: string, reason: string?)
		if not elStatus then return end
		if success then
			elStatus.TextColor3 = Color3.fromRGB(120, 220, 120)
			elStatus.Text = "Kupiono!"
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
end

return ShopController
