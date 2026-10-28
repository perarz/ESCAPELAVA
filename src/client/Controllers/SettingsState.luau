--!strict
-- SettingsState.luau — JEDNO miejsce po stronie klienta z ustawieniami gracza (26.10). Czyta
-- je MovementController (strona kamery, przechył i FOV), zmienia panel (SettingsController).
--
-- Prawdę trzyma serwer (SettingsService). Kliknięcie w panelu działa od razu (`set`), a
-- wysyłka idzie po `Config.Settings.SendDelay` z CAŁYM ostatnim stanem — szybkie klikanie nie
-- wpada w limit serwera. Do chwili wysyłki odpowiedzi serwera są pomijane (echo poprzedniej
-- zmiany cofnęłoby na moment świeże kliknięcie); po wysyłce wygrywa serwer. Jak LoadoutState.
--
-- `init` startuje przed `ClientReady` — listener musi stać, zanim serwer wyśle stan startowy.
--
-- „auto” (27.10, grafika) rozwiązuje `get`, bo tylko klient zna urządzenie — serwer zapisuje
-- surowe „auto”, a czytający (lawa, podświetlenie w panelu) zawsze dostają low / high.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Modules.Config)
local Remotes = require(ReplicatedStorage.Shared.Modules.Remotes)

local SettingsState = {}

local CFG = Config.Settings
local OPTIONS = CFG.Options

local values: { [string]: any } = {}
for key, opt in pairs(OPTIONS) do
	values[key] = opt.Default
end
local sendToken = 0
local sending = false
local listeners: { () -> () } = {}

local function allowed(key: string, value: any): boolean
	local opt = OPTIONS[key]
	return opt ~= nil and value ~= nil and table.find(opt.Values, value) ~= nil
end

local function notify()
	for _, cb in ipairs(listeners) do
		task.spawn(cb)
	end
end

-- Wywoływane przy każdej zmianie (kliknięcie albo stan z serwera).
function SettingsState.onChanged(cb: () -> ())
	table.insert(listeners, cb)
end

local function autoGraphics(): string
	-- Ta sama reguła co do 27.10 w LavaSurfaceController: telefon albo słaby suwak = low.
	local quality = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	local limit = OPTIONS.graphics.AutoLowQualityLevel
	local low = UserInputService.TouchEnabled or (quality > 0 and quality <= limit)
	return if low then "low" else "high"
end

function SettingsState.get(key: string): any
	local v = values[key]
	if v == "auto" and key == "graphics" then return autoGraphics() end
	return v
end

-- Zmiana z panelu. Nieznany klucz / wartość spoza Config.Settings.Options = nic.
function SettingsState.set(key: string, value: any): boolean
	if not allowed(key, value) then return false end
	if values[key] == value then return true end
	values[key] = value
	notify()
	sendToken += 1
	local token = sendToken
	sending = true
	task.delay(CFG.SendDelay, function()
		if token ~= sendToken then return end
		sending = false
		Remotes.SetSettings:FireServer(table.clone(values))
	end)
	return true
end

local initialized = false
function SettingsState.init()
	if initialized then return end
	initialized = true
	Remotes.SettingsChanged.OnClientEvent:Connect(function(raw: any)
		if sending or type(raw) ~= "table" then return end
		for key, opt in pairs(OPTIONS) do
			values[key] = if allowed(key, raw[key]) then raw[key] else opt.Default
		end
		notify()
	end)
end

return SettingsState
