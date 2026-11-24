--!strict
-- TrainController.luau (24.11) — pociąg u klienta: skład, dach do jazdy, dudnienie i wstrząs.
-- Serwer (TrainService) mówi tylko, kiedy i w którą stronę (`TrainRun`); pozycję liczy każdy klient
-- z czasu serwera (TrainPath), więc u wszystkich jest w tym samym miejscu. Kogo uderzył — serwer.
--
-- JAZDA NA DACHU: jedyna część z kolizją to płyta `Roof`. Jest zakotwiczona i przesuwana PRZED
-- krokiem fizyki, a jej `AssemblyLinearVelocity` = prędkość jazdy — silnik traktuje to jak taśmę
-- i niesie stojącą postać. Reszta bryły nie ma kolizji: klient nie może utknąć w środku wagonu,
-- o uderzeniu rozstrzyga serwer. Dach jest JEDNOSTRONNY (Play 24.11: uderzony gracz zatrzymywał się
-- na nim od spodu zamiast lecieć) — trzyma tylko, gdy środek postaci jest nad nim, tą samą granicą,
-- którą serwer odróżnia pasażera od uderzonego (`RiderMargin`).
--
-- Lokalny folder `Workspace.LocalTrain` — płyta łapie promienie (kolizja), więc promień, którego
-- wynik idzie do serwera, musi go pomijać (BridgeController).
--
-- KONTRAKT STUDIO: `ReplicatedStorage.Train` (Model) z Modelami `Loco` i `Wagon`; każdy ma PrimaryPart,
-- pivot = środek torów na wierzchu szyn, −Z = przód, i część `Roof`. Brak = warn i pociąg niewidoczny.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local TrainPath = require(ReplicatedStorage.Shared.Modules.TrainPath)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local MovementController = require(script.Parent.MovementController)

local CFG = Config.Train

local TrainController = {}

local FOLDER_NAME = "LocalTrain"
local localPlayer = Players.LocalPlayer

type Car = { model: Model, roofs: { BasePart }, index: number, shown: boolean, done: boolean }
type Active = { run: TrainPath.Run, departAt: number, cars: { Car }, folder: Folder, horn: BasePart?, nextShake: number }
local active: Active? = nil
local initialized = false

local function clear()
	local current = active
	if not current then return end
	active = nil
	current.folder:Destroy()
	for _, car in ipairs(current.cars) do
		car.model:Destroy()
	end
	if current.horn then current.horn:Destroy() end
end

local function makeSound(parent: Instance, id: string, volume: number, looped: boolean): Sound?
	if id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = CFG.SoundDistance
	s.Parent = parent
	return s
end

local function makeCar(template: Model, index: number): Car
	local model = template:Clone()
	local roofs: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local isRoof = d.Name == CFG.RoofPartName
			d.Anchored = true
			d.CanCollide = isRoof
			d.CanQuery = isRoof -- bez kolizji da się wyłączyć; z kolizją silnik i tak liczy promienie
			d.CanTouch = false
			d.Locked = true
			if isRoof then table.insert(roofs, d) end
		end
	end
	return { model = model, roofs = roofs, index = index, shown = false, done = false }
end

local function start(reverse: boolean, departAt: number)
	clear()
	local run = TrainPath.get(reverse)
	local train = ReplicatedStorage:FindFirstChild(CFG.Model)
	local loco = train and train:FindFirstChild("Loco")
	local wagon = train and train:FindFirstChild("Wagon")
	if not (run and loco and loco:IsA("Model") and wagon and wagon:IsA("Model")) then
		warn(("[TrainController] brak tuneli albo ReplicatedStorage.%s z modelami Loco i Wagon"):format(CFG.Model))
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	local cars: { Car } = {}
	for i = 1, CFG.CarCount do
		table.insert(cars, makeCar(if i == 1 then loco else wagon, i))
	end
	if cars[1].model.PrimaryPart then
		local rumble = makeSound(cars[1].model.PrimaryPart, CFG.RumbleSoundId, CFG.RumbleVolume, true)
		if rumble then rumble.Playing = true end
	end
	local horn: BasePart? = nil
	if CFG.HornSoundId ~= "" then
		local anchor = Instance.new("Part")
		anchor.Name = "TrainHorn"
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(run.start)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Parent = Workspace
		local s = makeSound(anchor, CFG.HornSoundId, CFG.HornVolume, false)
		if s then s:Play() end
		horn = anchor
	end
	active = { run = run, departAt = departAt, cars = cars, folder = folder, horn = horn, nextShake = 0 }
end

local function shake(current: Active, nearest: number, now: number)
	if nearest > CFG.ShakeDistance or now < current.nextShake then return end
	current.nextShake = now + CFG.ShakeInterval
	MovementController.screenShake(CFG.ShakeMax * (1 - nearest / CFG.ShakeDistance), CFG.ShakeInterval * 1.5)
end

local function update()
	local current = active
	if not current then return end
	local now = Workspace:GetServerTimeNow()
	local run = current.run
	local head = TrainPath.headDistance(current.departAt, now)
	if TrainPath.finished(run, head) then
		clear()
		return
	end
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else run.start
	local velocity = run.dir * CFG.Speed
	local root = Utils.getRoot(localPlayer)
	local solid = root ~= nil and root.Position.Y - run.start.Y >= CFG.Height - CFG.RiderMargin
	local nearest = math.huge
	for _, car in ipairs(current.cars) do
		if car.done then continue end
		local center = TrainPath.carCenter(car.index, head)
		-- Wagon istnieje, dopóki choć kawałek wystaje z tunelu; reszta chowa się za czarną płytą.
		if center + CFG.CarLength * 0.5 < -CFG.VisibleMargin then continue end
		if center - CFG.CarLength * 0.5 > run.length + CFG.VisibleMargin then
			car.done = true
			car.model:Destroy()
			continue
		end
		local pos = run.start + run.dir * center
		car.model:PivotTo(CFrame.lookAt(pos, pos + run.dir))
		if not car.shown then
			car.shown = true
			car.model.Parent = current.folder
		end
		for _, roof in ipairs(car.roofs) do
			if roof.CanCollide ~= solid then roof.CanCollide = solid end
			roof.AssemblyLinearVelocity = velocity
		end
		nearest = math.min(nearest, (eye - pos).Magnitude)
	end
	shake(current, nearest, now)
end

function TrainController.init()
	if initialized then return end
	initialized = true

	Remotes.TrainRun.OnClientEvent:Connect(function(reverse: any, departAt: any)
		if type(reverse) ~= "boolean" or type(departAt) ~= "number" then return end
		start(reverse, departAt)
	end)
	Remotes.GameStateChanged.OnClientEvent:Connect(function(newState: string)
		-- Jak u serwera: koniec rundy zatrzymuje wydarzenie (dach nie może zostać w powietrzu).
		if newState ~= "ROUND" then clear() end
	end)
	RunService.PreSimulation:Connect(update)
end

return TrainController
