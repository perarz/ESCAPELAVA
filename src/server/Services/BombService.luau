--!strict
-- BombService.luau
-- Bomba jako Roblox Tool. Equip = Tool w ręku gracza, Throw = consume inventory + spawn projectile.
--
-- Flow:
--   1. Klient klika hotbar slot z bombą → fires EquipItem(slot)
--   2. Server: BombService.equip → tworzy Tool z Handle (sphere) w Player.Backpack i auto-equipuje
--      na Character. Inventory NIE zmniejszane (gracz nadal "ma" bombę, tylko trzyma w ręku).
--   3. Klient klika LMB na Tool → Tool.Activated → klient fires ThrowBomb(direction)
--   4. Server: BombService.throw → consume z inventory, destroy Tool, spawn fizyczny projektyl,
--      fuse 2s LUB Touched → Explosion (damage 50%, knockback, ragdoll, joint destruction)
--   5. Klient klika ten sam slot ponownie → fires UnequipItem → BombService.unequip → destroy Tool

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local ItemService = require(script.Parent.ItemService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerService = require(script.Parent.PlayerService)
-- Ragdoll: toolbox ARTFVL — PlayerGui.ragdoll.functions.ragdoll BindableFunction

local BombService = {}

-- Track aktualnie equipped Tool per gracz
local equippedTools: { [Player]: Tool } = {}

local function log(player: Player, action: string, extra: string?)
	print(("[Bomb] %s %s%s"):format(player.Name, action, extra and (" — " .. extra) or ""))
end

local function getHRP(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	return nil
end

local function destroyEquipped(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

-- BombService.equip: tworzy Tool z Handle i auto-equipuje na character.
function BombService.equip(player: Player, itemId: any): (boolean, string?)
	if itemId ~= "bomb" then
		return false, "wrong_item"
	end

	if not PlayerService.isAlive(player) then
		return false, "not_in_round"
	end

	-- Sprawdź czy gracz ma bombę (nowy inventory schema: { [itemId] = count })
	if ItemService.getCount(player, "bomb") <= 0 then
		return false, "no_items"
	end

	destroyEquipped(player)

	local tool = Instance.new("Tool")
	tool.Name = "BombTool"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = false
	tool:SetAttribute("ItemId", "bomb")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Ball
	handle.Size = Vector3.new(2, 2, 2)
	handle.Color = Color3.fromRGB(30, 30, 35)
	handle.Material = Enum.Material.Metal
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	-- Pomarańczowa poświata żeby było widać że to bomba
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 100, 30)
	light.Brightness = 1.2
	light.Range = 6
	light.Parent = handle

	-- Parent do Character = auto-equip (Roblox standard). Jeśli brak character,
	-- ląduje w Backpack i gracz może go equipować ręcznie (mało prawdopodobne).
	local char = player.Character
	if char and char:FindFirstChild("Humanoid") then
		tool.Parent = char
	else
		tool.Parent = player:FindFirstChild("Backpack")
	end

	equippedTools[player] = tool
	log(player, "equip", "bomb (total=" .. ItemService.getCount(player, "bomb") .. ")")
	return true, nil
end

function BombService.unequip(player: Player): (boolean, string?)
	if not equippedTools[player] then
		return false, "not_equipped"
	end
	destroyEquipped(player)
	log(player, "unequip")
	return true, nil
end

-- Chronione przed wybuchem:
--   1. Cokolwiek pod Workspace.Map.Locked (Kacper wrzuca tam geometrię nieusuwalną)
--   2. Cokolwiek z property Locked=true (Studio default na Baseplate; LavaPart, Lobby.Spawn
--      też mają — bez tego bomba unanchorowała lawę i ona "wariowała")
--   3. Cokolwiek pod Workspace.ActiveCash (cash pickup'y — bomba nie powinna ich rozrzucać,
--      bo magnet by nadal działał ale ścieżka do nich byłaby random po świecie)
-- Reszta (Map.Tower, dowolne parts) → bomba rozwala.
local function isProtected(part: BasePart): boolean
	if part.Locked then return true end
	local map = Workspace:FindFirstChild("Map")
	if map then
		local locked = map:FindFirstChild("Locked")
		if locked and part:IsDescendantOf(locked) then return true end
	end
	local activeCash = Workspace:FindFirstChild("ActiveCash")
	if activeCash and part:IsDescendantOf(activeCash) then return true end
	return false
end

local function destroyJointsInRadius(center: Vector3, radius: number, impulseForce: number)
	-- Rozsypuje budynki: destroy joints + unanchor + impulse na każdy part.
	-- Skip protected (Baseplate, Lava, Lobby, SpawnPoints, humanoid character).
	local parts = Workspace:GetPartBoundsInRadius(center, radius)
	for _, part in ipairs(parts) do
		-- Skip humanoid (gracze)
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then continue end
		-- Skip protected
		if isProtected(part) then continue end

		-- Destroy joints które trzymają part w miejscu
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end

		-- Unanchor żeby spadał fizycznie
		part.Anchored = false

		-- Impulse od centrum w górę pod kątem
		local offset = part.Position - center
		if offset.Magnitude > 0.01 then
			local dir = (offset.Unit + Vector3.new(0, 0.4, 0)).Unit
			-- Falloff na siłę żeby bliżej epicentrum = mocniej wybijało
			local t = math.clamp(1 - offset.Magnitude / radius, 0, 1)
			pcall(function()
				part:ApplyImpulse(dir * impulseForce * t * part.AssemblyMass)
			end)
		end
	end
end

local function applyDamageAndKnockback(blastCenter: Vector3, thrower: Player, def: any)
	-- Damage server-side (authority). Ragdoll + knockback CLIENT-SIDE przez RemoteEvent
	-- bo character ma network ownership = klient. Server changes Motor6D są nadpisywane
	-- przez klient prediction — dlatego sztywno wyglądał ragdoll.
	-- W Studio damage'ujemy też rzucającego (testowanie); production: thrower exempt.
	local exemptThrower = not RunService:IsStudio()
	for _, p in ipairs(Players:GetPlayers()) do
		if exemptThrower and p == thrower then continue end
		local char = p.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or not hrp:IsA("BasePart") then continue end
		if hum.Health <= 0 then continue end

		local distance = (hrp.Position - blastCenter).Magnitude
		if distance > def.blastRadius then continue end

		-- Linear falloff, ale z floor — średni dystans nadal dostaje push, nie 0
		local rawT = math.clamp(1 - distance / def.blastRadius, 0, 1)
		local damageT = rawT  -- damage skaluje liniowo do 0
		local knockT = math.max(def.knockbackMinT or 0.35, rawT)  -- knockback ma floor

		-- 1. Damage server-side (klient nie może modyfikować HP — anti-cheat)
		hum:TakeDamage(hum.MaxHealth * def.damagePercent * damageT)

		-- 2. Knockback velocity
		local horizontal = (hrp.Position - blastCenter)
		if horizontal.Magnitude < 0.01 then horizontal = Vector3.new(0, 0, 1) end
		local dir = (horizontal.Unit + Vector3.new(0, 0.6, 0)).Unit
		local velocity = dir * def.knockbackForce * knockT

		local ragdollFolder = p:FindFirstChild("PlayerGui") and p.PlayerGui:FindFirstChild("ragdoll")
		if ragdollFolder then
			local fn = ragdollFolder:FindFirstChild("functions") and ragdollFolder.functions:FindFirstChild("ragdoll")
			local variableRagdoll = ragdollFolder:FindFirstChild("variables") and ragdollFolder.variables:FindFirstChild("ragdoll")
			if fn and fn:IsA("BindableFunction") then
				pcall(function() fn:Invoke(velocity) end)
				task.delay(def.ragdollDuration, function()
					if variableRagdoll and variableRagdoll:IsA("BoolValue") then
						variableRagdoll.Value = false
					end
				end)
			end
		end

		log(thrower, "hit", ("%s dist=%.1f rawT=%.2f knockT=%.2f"):format(p.Name, distance, rawT, knockT))
	end
end

local function spawnBlastVFX(position: Vector3, radius: number)
	-- Roblox default Explosion VFX (visual+sound). BlastPressure=0 → nie damage'uje
	-- humanoidów ani nie pcha partów (cały damage/knockback robimy custom w applyDamageAndKnockback).
	-- DestroyJointRadiusPercent=0 → nie zrywa jointów (custom destroyJointsInRadius już to robi).
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Visible = true
	explosion.Parent = Workspace

	-- Particle-based VFX zamiast brzydkiej żółtej kuli.
	-- Anchor invisible Part jako emitter parent, particles żyją 0.6s, Debris czyści.
	local anchor = Instance.new("Part")
	anchor.Name = "BlastFX"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	Debris:AddItem(anchor, 1.2)

	-- Smoke particles (gray/dark, large, slow fade-out)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 70, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 40, 40)),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, radius * 0.6),
		NumberSequenceKeypoint.new(1, radius * 0.9),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Rate = 0
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Speed = NumberRange.new(8, 18)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-90, 90)
	smoke.LightEmission = 0
	smoke.Parent = anchor
	smoke:Emit(35)

	-- Spark particles (orange, fast, short-lived)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80))
	sparks.Size = NumberSequence.new(0.6, 0.1)
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Rate = 0
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Speed = NumberRange.new(30, 55)
	sparks.LightEmission = 1
	sparks.Parent = anchor
	sparks:Emit(50)
end

local function detonate(bombPart: BasePart, thrower: Player, def: any)
	if not bombPart.Parent then return end
	local center = bombPart.Position

	spawnBlastVFX(center, def.blastRadius)

	if def.destroyJoints then
		destroyJointsInRadius(center, def.destructionRadius or def.blastRadius, def.destructionImpulse or 50)
	end

	applyDamageAndKnockback(center, thrower, def)

	log(thrower, "detonate", "pos=" .. tostring(center))
	bombPart:Destroy()
end

function BombService.throw(player: Player, direction: any): (boolean, string?)
	-- Bomb tylko w ROUND (alive). Jeśli gracz zginie z bombą w ręku, throw nie zadziała.
	if not PlayerService.isAlive(player) then
		destroyEquipped(player)
		return false, "not_in_round"
	end

	-- Walidacja Tool equipped
	local tool = equippedTools[player]
	if not tool or not tool.Parent then
		return false, "not_equipped"
	end

	-- Walidacja direction (z klienta)
	if typeof(direction) ~= "Vector3" then return false, "invalid_direction" end
	if direction.Magnitude < 0.01 or direction.Magnitude > 1000 then
		return false, "invalid_direction"
	end
	local dir = direction.Unit

	-- Consume z inventory (atomic — jeśli się nie powiedzie, abort bez throw)
	if not ItemService.consume(player, "bomb", 1) then
		return false, "consume_failed"
	end

	local hrp = getHRP(player)
	if not hrp then
		-- Niedobrze: consumed ale brak character. Refund nie ma w current API. v1.0 akceptujemy stratę.
		destroyEquipped(player)
		return false, "no_character"
	end

	local def = ItemDefinitions.bomb
	-- Spawn ZAWSZE nad HRP, w kierunku poziomym (X/Z z mouse dir), nigdy wzdłuż pełnego
	-- wektora rzutu. Dzięki temu jak gracz celuje w ziemię, bomba i tak spawnuje 2.5 nad
	-- nim — nie w podłodze. Charakter ma ~2 stud średnicy, bomba radius 1.5, offset 3.5
	-- horizontal = ~zero kontakt z thrower'em. CanCollide=true od razu → koniec przelatywania.
	local horizDir = Vector3.new(dir.X, 0, dir.Z)
	if horizDir.Magnitude < 0.1 then
		-- Gracz celuje pionowo (góra/dół) — użyj LookVector character'a jako fallback offset
		local lookH = hrp.CFrame.LookVector
		horizDir = Vector3.new(lookH.X, 0, lookH.Z)
	end
	horizDir = horizDir.Unit
	local spawnPos = hrp.Position + Vector3.new(0, 2.5, 0) + horizDir * 3.5
	local charVelocity = hrp.AssemblyLinearVelocity

	-- Destroy Tool — bomba "opuściła rękę"
	destroyEquipped(player)

	local bomb = Instance.new("Part")
	bomb.Name = "BombProjectile"
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(3, 3, 3)
	bomb.Color = Color3.fromRGB(30, 30, 35)
	bomb.Material = Enum.Material.Metal
	bomb.TopSurface = Enum.SurfaceType.Smooth
	bomb.BottomSurface = Enum.SurfaceType.Smooth
	bomb.CanCollide = true
	bomb.Anchored = false
	bomb.Position = spawnPos
	bomb.AssemblyLinearVelocity = dir * def.throwSpeed
		+ Vector3.new(0, def.throwLift, 0)
		+ charVelocity
	bomb.Parent = Workspace

	-- KLUCZOWE: server-side physics authority. Bez tego Roblox daje ownership najbliższemu
	-- graczowi (= rzucającemu) → klient symuluje fizykę, server widzi opóźnione updaty,
	-- bomba "freeze'uje" przy lagach/drop pakietów. SetNetworkOwner(nil) = server symuluje.
	pcall(function() bomb:SetNetworkOwner(nil) end)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 100, 30)
	light.Brightness = 2
	light.Range = 12
	light.Parent = bomb

	local detonated = false

	-- Fuse jest single source of truth — bomba ZAWSZE wybucha po def.fuse sekundach,
	-- niezależnie od tego czy dotknęła czegoś. Bouncy po Workspace przez ten czas.
	-- (Touched event removed — wcześniej powodował natychmiastową detonację gdy klient
	-- rzucił przy sobie bo bomba dotknęła character'a/groundu zaraz po spawn.)
	task.delay(def.fuse, function()
		if detonated then return end
		detonated = true
		if bomb.Parent then
			detonate(bomb, player, def)
		end
	end)

	Debris:AddItem(bomb, 10)
	log(player, "throw", "dir=" .. string.format("(%.2f,%.2f,%.2f)", dir.X, dir.Y, dir.Z))

	-- Auto-re-equip jeśli gracz ma jeszcze bomby — naturalne UX (jak grenat w FPS).
	-- Klient nadal trzyma selectedSlot=1, więc bez auto-re-equip pierwszy klik "1"
	-- traktuje go jako toggle-off (UnequipItem) zamiast equip. Z auto-re-equipem
	-- Tool po prostu wraca do ręki i klient nawet nie musi nic robić.
	-- Jeśli count=0, InventoryChanged → ensureSelectionValid wyczyści selection.
	if ItemService.getCount(player, "bomb") > 0 then
		BombService.equip(player, "bomb")
	end

	return true, nil
end

-- Hotkey Tool.Activated server side też się odpala, ale potrzebujemy directional aim
-- → klient fires ThrowBomb. Server tu obsługuje.
local function onThrowBomb(player: Player, direction: any)
	local ok, reason = BombService.throw(player, direction)
	if not ok then
		print(("[Bomb] throw FAIL %s — %s"):format(player.Name, tostring(reason)))
	end
end

local function onEquipItem(player: Player, itemId: any)
	-- Dispatch po itemId. W przyszłości: shield, bridge_builder, etc.
	if itemId == "bomb" then
		BombService.equip(player, "bomb")
	else
		-- Klient przełączył na inny item (np. bridge_builder) — jeśli mieliśmy bomb tool
		-- w ręku, schowaj go. Każdy service self-cleanups gdy klient zmienia equip;
		-- alternatywa byłaby centralnym "EquipmentManager" ale to overengineering dla 2 itemów.
		BombService.unequip(player)
	end
end

local function onUnequipItem(player: Player)
	BombService.unequip(player)
end

local function onPlayerRemoving(player: Player)
	equippedTools[player] = nil
end

local function onCharacterRemoving(player: Player)
	-- Death lub LoadCharacter — Tool ginie z Character. Cleanup track.
	equippedTools[player] = nil
end

local initialized = false
function BombService.init()
	if initialized then return end
	initialized = true

	Remotes.EquipItem.OnServerEvent:Connect(onEquipItem)
	Remotes.UnequipItem.OnServerEvent:Connect(onUnequipItem)
	Remotes.ThrowBomb.OnServerEvent:Connect(onThrowBomb)

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function() onCharacterRemoving(player) end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterRemoving:Connect(function() onCharacterRemoving(p) end)
	end
end

return BombService
