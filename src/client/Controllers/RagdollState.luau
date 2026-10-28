--!strict
-- RagdollState.luau — JEDNO miejsce po stronie klienta, które mówi „ta postać leży jako ragdoll”.
-- Nie kontroler (bez init): wołają go MovementController (sprint, kamera, obracanie głowy)
-- i GrappleController (blokada haka).
--
-- Przegląd 29.09 (B-4): MovementController sprawdzał tylko `PlatformStand`, a toolbox ARTFVL
-- zwiotcza postać przez `ChangeState(Physics)`, nie przez PlatformStand (ustalone 26.09 przy
-- haku). W ragdollu dalej działał więc sprint (stamina, FOV), a obracanie głowy pisało `C0`
-- co klatkę i walczyło z fizyką ciała. Trzy sygnały, bo każdy dociera w innym momencie: flaga
-- toolboxa (ustawia ją serwer, replikuje się przez PlayerGui — tylko dla NASZEJ postaci), stan
-- Physics i PlatformStand. Serwer ma własne źródło: RagdollService.isRagdolled.

local Players = game:GetService("Players")

local RagdollState = {}

local localPlayer = Players.LocalPlayer

local function toolboxFlag(): boolean
	local gui = localPlayer:FindFirstChild("PlayerGui")
	local folder = gui and gui:FindFirstChild("ragdoll")
	local vars = folder and folder:FindFirstChild("variables")
	local flag = vars and vars:FindFirstChild("ragdoll")
	return flag ~= nil and flag:IsA("BoolValue") and (flag :: BoolValue).Value
end

function RagdollState.isRagdolled(hum: Humanoid): boolean
	if hum.PlatformStand or hum:GetState() == Enum.HumanoidStateType.Physics then
		return true
	end
	-- Flaga toolboxa istnieje tylko w NASZYM PlayerGui — cudzej postaci jej nie sprawdzimy.
	local char = hum.Parent
	if char and char == localPlayer.Character then
		return toolboxFlag()
	end
	return false
end

return RagdollState
