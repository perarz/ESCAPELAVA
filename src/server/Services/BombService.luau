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
--      fuse 2.5s → detonacja: DestructionService.detonate (geometria + VFX przez BlastFX)
--      + damage/knockback/ragdoll graczy (tutaj)
--
-- Destrukcja otoczenia i wizualia wybuchu = system v2 (DESTRUCTION_PLAN.md). Ten service
-- odpowiada za cykl życia ITEMU (equip → throw → fuse) i efekt na GRACZACH.
--   5. Klient klika ten sam slot ponownie → fires UnequipItem → BombService.unequip → destroy Tool

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local ItemDefinitions = require(ReplicatedStorage.Shared.Modules.ItemDefinitions)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)
local Utils = require(ReplicatedStorage.Shared.Modules.Utils)
local ItemService = require(script.Parent.ItemService)
local PlayerService = require(script.Parent.PlayerService)
local KillService = require(script.Parent.KillService)
local DestructionService = require(script.Parent.DestructionService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local RagdollService = require(script.Parent.RagdollService)
local GameLoopService = require(script.Parent.GameLoopService)
-- Ragdoll: toolbox ARTFVL — PlayerGui.ragdoll.functions.ragdoll BindableFunction

local BombService = {}

-- Track aktualnie equipped Tool per gracz
local equippedTools: { [Player]: Tool } = {}
-- Rate limit per gracz — anti-spam ThrowBomb. Klient MUSI mirrorować tę samą wartość
-- z Config.RateLimits.BombThrow, inaczej klient wysyła spam a server odrzuca.
local lastThrowAt: { [Player]: number } = {}
-- Rate limit EquipItem/UnequipItem — spam clickowanie hotbar = flicker Tool w rękach
-- innych klientów + bandwidth. Klient (HotbarController) też trzyma osobny debounce.
local lastEquipAt: { [Player]: number } = {}

local function log(player: Player, action: string, extra: string?)
	print(("[Bomb] %s %s%s"):format(player.Name, action, extra and (" — " .. extra) or ""))
end

local function destroyEquipped(player: Player)
	local tool = equippedTools[player]
	if tool then
		tool:Destroy()
		equippedTools[player] = nil
	end
end

-- Handle Toola z modelu Kacpra (`ItemDefinitions.<item>.toolModel` w ReplicatedStorage).
--
-- Tool wymaga, żeby dziecko o nazwie "Handle" było BasePartem — model wieloczęściowy trzeba
-- więc SPŁASZCZYĆ: największa bryła zostaje Handle (to ją Roblox przypina do dłoni przez
-- RightGrip), a reszta jedzie na weldach. Bez weldów lont i okucia zostałyby wisieć tam,
-- gdzie model stał w ReplicatedStorage. Party zbieram do listy PRZED przenoszeniem, bo
-- iterowanie po `GetDescendants()` w trakcie reparentingu jest niestabilne, a spłaszczenie
-- po descendantach (nie po dzieciach) działa też, gdyby Kacper zagnieździł części w folderze.
--
-- Zwraca part, który jest Handle. Brak modelu = stara kula z kodu (fallback, nic nie pada).
local function buildToolVisual(tool: Tool, modelName: string?): BasePart
	local template = if modelName then Utils.getAsset(modelName) else nil
	if template and template:IsA("Model") then
		local model = template:Clone()
		local primary = model.PrimaryPart or Utils.largestPart(model)
		if primary then
			primary.Name = "Handle"

			local parts: { BasePart } = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					-- Massless: przedmiot w dłoni nie może zmieniać fizyki postaci.
					-- Bez tego kilkanaście kilogramów bomby przechyla i spowalnia gracza.
					d.Massless = true
					table.insert(parts, d)
				end
			end

			-- Welds PRZED odkotwiczeniem i przed wejściem do świata (patrz Utils.weldModel).
			Utils.weldModel(model, primary)

			for _, p in ipairs(parts) do
				p.Parent = tool
			end
			-- Cokolwiek jeszcze siedziało w modelu (dźwięki, atrybuty-nośniki) idzie z nimi.
			for _, leftover in ipairs(model:GetChildren()) do
				leftover.Parent = tool
			end
			model:Destroy()
			return primary
		end
		model:Destroy()
		warn(("[Bomb] model %s nie ma ani jednego BasePart — używam kuli z kodu"):format(modelName :: string))
	elseif modelName then
		warn(("[Bomb] brak ReplicatedStorage.%s (Model) — używam kuli z kodu"):format(modelName))
	end

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
	return handle
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

	local def = ItemDefinitions.bomb
	local handle = buildToolVisual(tool, def.toolModel)

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

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function spawnLandingDust(position: Vector3)
	-- Chmura kurzu przy ziemi (jaśniejszy brąz niż smoke wybuchu). Anchored invisible Part
	-- jako emitter parent, burst 16 particli, Debris czyści po 1.5s.
	local anchor = Instance.new("Part")
	anchor.Name = "RagdollDustFX"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	Debris:AddItem(anchor, 1.5)

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = DUST_TEXTURE
	dust.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(185, 170, 145)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 128, 110)),
	})
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.4, 4),
		NumberSequenceKeypoint.new(1, 6),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Rate = 0
	dust.SpreadAngle = Vector2.new(75, 75)   -- głównie w bok, nisko przy ziemi
	dust.Speed = NumberRange.new(5, 11)
	dust.VelocityInheritance = 0
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Acceleration = Vector3.new(0, -3, 0)
	dust.LightEmission = 0
	dust.Parent = anchor
	dust:Emit(16)
end

local function monitorRagdollLanding(hrp: BasePart)
	-- Wykryj pierwsze zetknięcie z ziemią po wystrzeleniu ragdollem → dust.
	-- Server-side: character ma ownership klienta, ale velocity/pozycja replikują się —
	-- wystarczy do triggera. Poll ~12Hz, timeout 3s. Nad lawą (CanQuery=false) raycast
	-- nie trafi → brak dustu (poprawne, bo tam nie ma "lądowania").
	task.spawn(function()
		local char = hrp.Parent
		if not char then return end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		params.IgnoreWater = true

		local airborne = false
		local deadline = os.clock() + 3
		while os.clock() < deadline do
			task.wait(0.08)
			if not hrp.Parent then return end
			local speed = hrp.AssemblyLinearVelocity.Magnitude
			if speed > 25 then
				airborne = true
			elseif airborne and speed < 14 then
				local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -6, 0), params)
				if hit then
					spawnLandingDust(hit.Position + Vector3.new(0, 0.2, 0))
					return
				end
			end
		end
	end)
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
		-- Od tego miejsca gracz JEST w zasięgu — każde pominięcie logujemy z powodem
		-- (26.09: „czasem bomba nic mu nie robi” — bez tego nie wiadomo, który warunek).
		-- Tylko żywi w rundzie. Bez tego bomba rzucona blisko lobby zabijała spectatorów
		-- (do 26.09 zostawał po nich trup bez respawnu do następnej rundy).
		if not PlayerService.isAlive(p) then
			log(thrower, "miss", ("%s dist=%.1f — nie jest żywy w rundzie (aliveSet)"):format(p.Name, distance))
			continue
		end

		-- Linear falloff, ale z floor — średni dystans nadal dostaje push, nie 0
		local rawT = math.clamp(1 - distance / def.blastRadius, 0, 1)

		-- Osłona (etap 2): każda ściana między graczem a epicentrum tnie efekt. Destrukcja
		-- geometrii policzona już PRZED tą pętlą, więc zdmuchnięta ściana NIE osłania —
		-- została po niej dziura. Prawie-pełna osłona = brak trafienia (zero ragdolla
		-- i taga przez dwie ściany).
		local occlusion = DestructionService.computeOcclusion(blastCenter, hrp.Position)
		local effT = rawT * occlusion
		if effT < Config.Destruction.Occlusion.MinEffect then
			log(thrower, "miss", ("%s dist=%.1f — osłonięty (occ=%.2f, efekt %.3f < %.2f)"):format(
				p.Name, distance, occlusion, effT, Config.Destruction.Occlusion.MinEffect))
			continue
		end

		local damageT = effT  -- damage skaluje liniowo do 0
		-- Floor knockbacku liczony PRZED osłoną (floor jest dla otwartej przestrzeni),
		-- osłona tnie wynik — gracz za ścianą nie dostaje "gwarantowanego" odrzutu.
		local knockT = math.max(def.knockbackMinT or 0.35, rawT) * occlusion

		-- Tag attacker PRZED damage — jeśli ten hit kill'uje, credit thrower.
		-- Także jeśli tylko rani a target zginie w oknie X sekund (np. bomba wybije w lawę
		-- → ragdoll → lava kill), wciąż credit dla thrower.
		KillService.tag(hum, thrower, "bomb")

		-- 1. Damage server-side (klient nie może modyfikować HP — anti-cheat)
		hum:TakeDamage(hum.MaxHealth * def.damagePercent * damageT)

		-- Okno bezkarności dla anti-cheata: za chwilę poleci 450 stud/s z naszej winy.
		-- Bez tego detektor prędkości (mierzy realnie przebytą drogę) uznałby ofiarę
		-- własnego wybuchu za speedhackera.
		AntiCheatService.grantGrace(p)

		-- 2. Knockback velocity
		local horizontal = (hrp.Position - blastCenter)
		if horizontal.Magnitude < 0.01 then horizontal = Vector3.new(0, 0, 1) end
		local dir = (horizontal.Unit + Vector3.new(0, 0.6, 0)).Unit
		local velocity = dir * def.knockbackForce * knockT

		-- Ragdoll przez RagdollService — jedyny właściciel wywrotki i terminu wstawania.
		-- Wcześniej ten serwis planował własny `task.delay` na tym samym `BoolValue`,
		-- co FallDamageService, więc bomba potrafiła postawić gracza w środku ragdolla
		-- z upadku (i odwrotnie). Tutaj knockback podaje prędkość DOCELOWĄ — to jest
		-- cały sens odrzutu, więc pion ma zostać nadpisany.
		RagdollService.knock(p, velocity, def.ragdollDuration)

		-- Feedback na kliencie trafionego: screen shake + FOV punch skalowane efektywnym
		-- falloff'em (z osłoną — gracz za ścianą dostaje proporcjonalnie mniejszy wstrząs).
		Remotes.BombHit:FireClient(p, effT)

		-- Chmura kurzu gdy ragdoll wyląduje (server-side monitor pozycji + prędkości).
		monitorRagdollLanding(hrp)

		log(thrower, "hit", ("%s dist=%.1f rawT=%.2f occ=%.2f knockT=%.2f"):format(p.Name, distance, rawT, occlusion, knockT))
	end
end

-- `root` to Model (bomba Kacpra) albo pojedynczy Part (fallback), więc środek wybuchu
-- dostajemy osobno — z bryły niosącej fizykę, nie z roota, którego pozycja przy modelu
-- zależy od pivota.
local function detonate(root: Instance, center: Vector3, thrower: Player, def: any)
	if not root.Parent then return end

	-- Pocisk znika PRZED destrukcją (2026-09-23). Wcześniej był kasowany na końcu, więc
	-- wybuch łapał WŁASNĄ bombę w zasięgu i przy KAŻDYM rzucie drukował ostrzeżenie
	-- „N partów nie zostało pociętych — Anchored=false … BombProjectile” (zgłoszenie
	-- „często wyskakuje, że part jest niezanchorowany”). Do tego detonate potrafi teraz
	-- odczekać klatkę na budżet CPU, a bomba nie może wisieć w świecie po błysku.
	root:Destroy()

	-- Destrukcja PRZED damage: gdy bomba zdmuchnie ścianę, gracz za nią jest już odsłonięty
	-- w momencie liczenia obrażeń (occlusion polega na tej kolejności). VFX wybuchu
	-- odpala DestructionService (Remotes.BlastFX → klienci renderują).
	-- ⚠️ W xpcall: błąd w destrukcji NIE MOŻE anulować obrażeń graczy — bez tego jeden wyjątek
	-- w DestructionService zjadał całą resztę wybuchu. To jedna z dwóch możliwych przyczyn
	-- zgłoszenia Kacpra 26.09 „czasem bomba nic mu nie robi, 0 ragdolla, 0 dmg” (druga:
	-- warunki pominięcia niżej, logowane jako `miss`) — NIEPOTWIERDZONA, log rozstrzygnie.
	-- Błąd drukujemy głośno, z miejscem wystąpienia, żeby dało się go naprawić u źródła.
	local ok, err = xpcall(DestructionService.detonate, function(e: any): string
		return tostring(e) .. "\n" .. debug.traceback() -- ślad z MIEJSCA błędu, nie z tego wywołania
	end, center, def.destruction, thrower)
	if not ok then
		warn(("[Bomb] BŁĄD destrukcji przy wybuchu %s: %s"):format(tostring(center), tostring(err)))
	end

	applyDamageAndKnockback(center, thrower, def)

	log(thrower, "detonate", "pos=" .. tostring(center))
end

-- Wybuch bez pocisku (27.09 — auto, CarService): ta sama ścieżka co bomba — destrukcja
-- otoczenia PRZED obrażeniami (osłona), błąd destrukcji nie zjada obrażeń. `def` ma pola jak
-- ItemDefinitions.bomb. Bez sprawcy (nikt nie rzucał) tylko otoczenie: tag zabójstwa
-- i log potrzebują gracza.
function BombService.explodeAt(center: Vector3, def: any, attacker: Player?)
	local ok, err = xpcall(DestructionService.detonate, function(e: any): string
		return tostring(e) .. "\n" .. debug.traceback()
	end, center, def.destruction, attacker)
	if not ok then
		warn(("[Bomb] BŁĄD destrukcji przy wybuchu auta %s: %s"):format(tostring(center), tostring(err)))
	end
	if attacker and attacker.Parent then
		applyDamageAndKnockback(center, attacker, def)
		log(attacker, "car", "pos=" .. tostring(center))
	end
end

-- Lecąca bomba z modelu Kacpra (`ItemDefinitions.bomb.toolModel` — ten sam model, którym
-- gracz przed chwilą machał w ręce; to ma być ta sama bomba, nie dwa różne przedmioty).
--
-- Zwraca (root, primary): `root` to rzecz do skasowania i do Debris, `primary` niesie
-- fizykę, prędkość i VFX. Nazwa roota MUSI zostać "BombProjectile" — po niej MapService
-- sprząta bomby w locie przy restarcie mapy (szuka po nazwie wśród dzieci Workspace).
local function buildProjectile(cf: CFrame, def: any): (Instance, BasePart)
	local modelName = def.toolModel
	local template = if modelName then Utils.getAsset(modelName) else nil
	if template and template:IsA("Model") then
		local model = template:Clone()
		local primary = model.PrimaryPart or Utils.largestPart(model)
		if primary then
			model.Name = "BombProjectile"
			model.PrimaryPart = primary
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					-- Kolizja TYLKO na głównej bryle. Lont i okucia wystające poza kulę
					-- zaczepiałyby się o krawędzie i bomba stawałaby w losowych miejscach
					-- zamiast się toczyć — a tor rzutu to rzecz, którą gracz przewiduje.
					d.CanCollide = (d == primary)
					d.Massless = (d ~= primary)
				end
			end
			-- Pozycja PRZED weldami i przed wejściem do świata (patrz Utils.weldModel).
			Utils.setModelCenter(model, cf)
			Utils.weldModel(model, primary)
			return model, primary
		end
		model:Destroy()
		warn(("[Bomb] model %s nie ma ani jednego BasePart — lecę kulą z kodu"):format(modelName :: string))
	end

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
	bomb.CFrame = cf
	return bomb, bomb
end

function BombService.throw(player: Player, direction: any): (boolean, string?)
	-- Bomb tylko w ROUND (alive). Jeśli gracz zginie z bombą w ręku, throw nie zadziała.
	if not PlayerService.isAlive(player) then
		destroyEquipped(player)
		return false, "not_in_round"
	end

	-- Rate limit — anti-spam ThrowBomb (BEZ tego auto-re-equip + fast click = 10 bomb/s exploit).
	local now = os.clock()
	if now - (lastThrowAt[player] or 0) < Config.RateLimits.BombThrow * Config.RateLimits.ServerTolerance then
		return false, "cooldown"
	end

	-- Walidacja Tool equipped
	local tool = equippedTools[player]
	if not tool or not tool.Parent then
		return false, "not_equipped"
	end

	-- Walidacja direction (z klienta). `mag ~= mag` łapie NaN: porównania z NaN są zawsze
	-- fałszem, więc samo `< 0.01 or > 1000` go przepuszczało — a wektor NaN wchodził w CFrame
	-- pocisku i w odległości do wszystkich graczy (przegląd 29.09, A-4).
	if typeof(direction) ~= "Vector3" then return false, "invalid_direction" end
	local mag = direction.Magnitude
	if mag ~= mag or mag < 0.01 or mag > 1000 then
		return false, "invalid_direction"
	end
	local dir = direction.Unit

	-- Character check PRZED consume — jeśli player umarł/despawnował w milisekundzie
	-- kliknięcia, nie chcemy zabrać bomby bez rzutu.
	local hrp = Utils.getRoot(player)
	if not hrp then
		destroyEquipped(player)
		return false, "no_character"
	end

	-- Consume z inventory (atomic — jeśli się nie powiedzie, abort bez throw)
	if not ItemService.consume(player, "bomb", 1) then
		return false, "consume_failed"
	end

	-- Zaznacz rate limit DOPIERO po consume (jeśli wcześniej — spam odrzucony gdy player
	-- nie ma już bomb, ale timer i tak by szedł; teraz timer działa tylko na realny throw).
	lastThrowAt[player] = now

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

	-- CFrame, nie Position — setter Position rozwiązuje kolizje przesuwając part w górę
	-- (bomba "wyskakiwała" gdy spawn nachodził na geometrię). CFrame stawia dokładnie tu.
	local root, primary = buildProjectile(CFrame.new(spawnPos), def)
	root.Parent = Workspace

	-- Prędkość PO parentowaniu: przy modelu assembly powstaje dopiero w momencie wejścia
	-- do Workspace, a prędkość nadana wcześniej przepadłaby razem z nim.
	primary.AssemblyLinearVelocity = dir * def.throwSpeed
		+ Vector3.new(0, def.throwLift, 0)
		+ charVelocity

	-- KLUCZOWE: server-side physics authority. Bez tego Roblox daje ownership najbliższemu
	-- graczowi (= rzucającemu) → klient symuluje fizykę, server widzi opóźnione updaty,
	-- bomba "freeze'uje" przy lagach/drop pakietów. SetNetworkOwner(nil) = server symuluje.
	-- Wołane na ROOCIE ASSEMBLY, bo na zwykłym parcie zweldowanej bryły Roblox rzuca błąd.
	pcall(function() (primary.AssemblyRootPart or primary):SetNetworkOwner(nil) end)

	-- Prawie zero odbicia — default elasticity 0.5 robiła z bomby piłkę do kosza.
	primary.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, def.bounciness or 0.05, 1, 1)

	-- Tłumienie toczenia: kula toczy się w Robloxie bez końca (brak rolling resistance).
	-- Co Heartbeat wygaszamy prędkość, ALE tylko gdy bomba jest przy ziemi (raycast w dół)
	-- — w locie nie tykamy, żeby nie skracać rzutu (apex ma vY≈0, raycast to odróżnia).
	-- Server owns physics (SetNetworkOwner(nil) wyżej), więc damping replikuje się czysto.
	-- Pętla żyje max fuse+epsilon (root.Parent=nil po detonacji/cleanup → koniec).
	local dampParams = RaycastParams.new()
	dampParams.FilterType = Enum.RaycastFilterType.Exclude
	dampParams.FilterDescendantsInstances = { root }
	task.spawn(function()
		local damp = def.rollDamping or 1
		if damp >= 1 then return end
		-- "Przy ziemi" = powierzchnia tuż pod spodem. Zasięg sondy liczony z ROZMIARU bryły,
		-- nie wpisany na sztywno: model Kacpra ma promień ~1.07, a zaszyta w kodzie dwójka
		-- (pod kulę 3×3×3) sięgałaby prawie stud POD grunt i tłumiła bombę jeszcze w locie.
		local groundProbe = Vector3.new(0, -(primary.Size.Y * 0.5 + 0.5), 0)
		while root.Parent do
			if Workspace:Raycast(primary.Position, groundProbe, dampParams) then
				local v = primary.AssemblyLinearVelocity
				primary.AssemblyLinearVelocity = Vector3.new(v.X * damp, v.Y, v.Z * damp)
				primary.AssemblyAngularVelocity = primary.AssemblyAngularVelocity * damp
			end
			task.wait()
		end
	end)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 100, 30)
	light.Brightness = 2
	light.Range = 12
	light.Parent = primary

	-- ===== Fuse VFX: bomba wygląda na UZBROJONĄ (czytelny sygnał "uciekaj") =====
	-- Iskry palącego się lontu.
	local fuseSparks = Instance.new("ParticleEmitter")
	fuseSparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fuseSparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 30))
	fuseSparks.Size = NumberSequence.new(0.35, 0.05)
	fuseSparks.Lifetime = NumberRange.new(0.2, 0.45)
	fuseSparks.Rate = 14
	fuseSparks.Speed = NumberRange.new(3, 7)
	fuseSparks.SpreadAngle = Vector2.new(180, 180)
	fuseSparks.LightEmission = 1
	fuseSparks.Parent = primary

	-- Dymny ogon w locie (i podczas leżenia — bomba "się pali").
	local fuseSmoke = Instance.new("ParticleEmitter")
	fuseSmoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	fuseSmoke.Color = ColorSequence.new(Color3.fromRGB(130, 130, 130), Color3.fromRGB(80, 80, 80))
	fuseSmoke.Size = NumberSequence.new(0.6, 1.8)
	fuseSmoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	fuseSmoke.Lifetime = NumberRange.new(0.5, 0.8)
	fuseSmoke.Rate = 25
	fuseSmoke.Speed = NumberRange.new(0.5, 1.5)
	fuseSmoke.Parent = primary

	-- Migotanie światła: wolny puls → szybki strobo tuż przed wybuchem (klasyczny "tick").
	-- Pętla żyje max fuse (root.Parent=nil po detonacji → koniec). Server-side — replikuje się.
	task.spawn(function()
		local tStart = os.clock()
		local on = true
		while root.Parent do
			local frac = math.clamp((os.clock() - tStart) / def.fuse, 0, 1)
			on = not on
			light.Brightness = on and 6 or 1.2
			light.Color = on and Color3.fromRGB(255, 60, 30) or Color3.fromRGB(255, 120, 40)
			task.wait(0.34 - 0.28 * frac) -- 0.34s → 0.06s
		end
	end)

	local detonated = false

	-- Fuse jest single source of truth — bomba ZAWSZE wybucha po def.fuse sekundach,
	-- niezależnie od tego czy dotknęła czegoś. Bouncy po Workspace przez ten czas.
	-- (Touched event removed — wcześniej powodował natychmiastową detonację gdy klient
	-- rzucił przy sobie bo bomba dotknęła character'a/groundu zaraz po spawn.)
	task.delay(def.fuse, function()
		if detonated then return end
		detonated = true
		if root.Parent then
			-- Pozycja czytana TERAZ, nie w chwili rzutu — bomba przez te 2.5 s leciała,
			-- odbijała się i toczyła.
			detonate(root, primary.Position, player, def)
		end
	end)

	Debris:AddItem(root, 10)
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
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now

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
	local now = os.clock()
	if now - (lastEquipAt[player] or 0) < Config.RateLimits.EquipItem * Config.RateLimits.ServerTolerance then return end
	lastEquipAt[player] = now
	BombService.unequip(player)
end

local function onPlayerRemoving(player: Player)
	equippedTools[player] = nil
	lastThrowAt[player] = nil
	lastEquipAt[player] = nil
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

	-- ⚠️ SPRZĄTANIE NA KONIEC RUNDY (zgłoszenie 2026-09-21: „po rundzie dalej masz bombę
	-- w ręce, klikasz i nic nie leci, ale pasek cooldownu jedzie"). Ocalali NIE dostają
	-- nowej postaci po rundzie — są tylko teleportowani do lobby — więc Tool zostawał
	-- im w rękach, a `CharacterRemoving` (jedyny dotychczasowy cleanup) nigdy nie leciał.
	-- BridgeService robił to od początku; tu po prostu tego brakowało.
	GameLoopService.RoundEnded:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			BombService.unequip(player)
		end
	end)
end

return BombService
