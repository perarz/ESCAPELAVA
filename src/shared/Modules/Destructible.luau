--!strict
-- Destructible.luau
-- Single source of truth: CO wybuch może ruszyć, a czego nie tyka (system destrukcji v2).
--
-- Shared, bo odpowiedź musi być IDENTYCZNA po obu stronach:
--   serwer  — co realnie niszczy, tnie i pcha
--   klient  — z czego wolno rysować efekty zniszczenia (pył, odłamki)
-- Wcześniej klient nie miał tej wiedzy w ogóle i sypał pyłem oraz próbkował kolory
-- z partów oznaczonych jako nietykalne — Baseplate wyglądał, jakby się rozpadał, choć
-- wybuch go nie dotykał. Dwie kopie reguły to dwie okazje, żeby się rozjechały; stąd
-- jedno miejsce.
--
-- KONTRAKT MAPY (DESTRUCTION_PLAN.md):
--   nietykalne = `Locked = true` | pod `Workspace.Map.Locked` | pod `Workspace.ActiveCash`
--   niszczalne = pod `Workspace.Map` | pod `Workspace.ActiveBridges` (sabotaż PvP)

local Workspace = game:GetService("Workspace")

local Destructible = {}

-- Kontekst rozwiązywany RAZ na wybuch zamiast per part — przy ~150 kandydatach
-- oszczędza kilkaset FindFirstChild.
export type Context = {
	map: Instance?,
	lockedFolder: Instance?,
	activeCash: Instance?,
	activeBridges: Instance?,
}

function Destructible.buildContext(): Context
	local map = Workspace:FindFirstChild("Map")
	return {
		map = map,
		lockedFolder = map and map:FindFirstChild("Locked") or nil,
		activeCash = Workspace:FindFirstChild("ActiveCash"),
		activeBridges = Workspace:FindFirstChild("ActiveBridges"),
	}
end

-- Nietykalne dla wybuchu:
--   1. property Locked=true (Baseplate, LavaPart, Lobby.Spawn, platformy Kacpra które
--      mają wisieć w powietrzu z designu)
--   2. Workspace.Map.Locked (geometria nieusuwalna)
--   3. Workspace.ActiveCash (rozrzucony cash miałby magnet, ale lot do gracza przez pół mapy)
-- Mosty (ActiveBridges) CELOWO nie są chronione — sabotaż PvP.
function Destructible.isProtected(part: BasePart, ctx: Context): boolean
	if part.Locked then return true end
	if ctx.lockedFolder and part:IsDescendantOf(ctx.lockedFolder) then return true end
	if ctx.activeCash and part:IsDescendantOf(ctx.activeCash) then return true end
	return false
end

-- Co wolno NISZCZYĆ (fracture/launch): geometria mapy + mosty. Nic spoza tych korzeni —
-- wybuch nie może rozbierać lobby, ragdoll toolboxa ani niczego postawionego luzem.
function Destructible.isDestructible(part: BasePart, ctx: Context): boolean
	if ctx.map and part:IsDescendantOf(ctx.map) then return true end
	if ctx.activeBridges and part:IsDescendantOf(ctx.activeBridges) then return true end
	return false
end

-- Skrót dla strony klienckiej (FX): czy z tego parta wolno rysować efekty zniszczenia.
-- Terrain i postacie odpadają razem z chronionymi — nigdy nie są źródłem gruzu.
function Destructible.canSpawnFXFrom(part: BasePart, ctx: Context): boolean
	if part:IsA("Terrain") then return false end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then return false end
	if Destructible.isProtected(part, ctx) then return false end
	return true
end

return Destructible
