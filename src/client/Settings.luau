-- Player comfort settings. They start from the defaults below, switch to the
-- saved values once the profile arrives, and changes are sent to the server
-- (a second after the last change) so they're saved with the profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profile = require(script.Parent.Profile)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SettingsRequest = Remotes:WaitForChild("SettingsRequest") :: RemoteEvent

local Settings = {}

-- Keep in sync with the server's sanitizer (Shared/Data/Schema.luau)
Settings.values = {
	cameraShake = true,
	-- Fewer particles and smaller effects
	reducedEffects = false,
	-- Full-screen flashes and colour shifts from big attacks
	intenseEffects = true,
	musicVolume = 0.5,
	sfxVolume = 0.8,
	uiScale = 1,
	cameraSensitivity = 1,
	damageNumbers = true,
	-- Lock-on: "toggle" (press to lock, tap to switch, hold to let go) or
	-- "hold" (locked while the button is held)
	lockOnMode = "toggle",
}

local changed = Instance.new("BindableEvent")
-- Fires with (key, value)
Settings.changed = changed.Event

function Settings.get(key: string): any
	return Settings.values[key]
end

local sendToken = 0
local function scheduleSave()
	sendToken += 1
	local token = sendToken
	task.delay(1, function()
		if token == sendToken then
			SettingsRequest:FireServer(table.clone(Settings.values))
		end
	end)
end

function Settings.set(key: string, value: any)
	if Settings.values[key] == value then
		return
	end
	Settings.values[key] = value
	changed:Fire(key, value)
	scheduleSave()
end

-- Saved settings win over the defaults (only keys we know, with the right type)
local loaded = false
Profile.whenReady(function(view)
	if loaded then
		return
	end
	loaded = true
	local saved = view.settings
	if typeof(saved) ~= "table" then
		return
	end
	for key, default in Settings.values do
		local value = saved[key]
		if value ~= nil and typeof(value) == typeof(default) and value ~= Settings.values[key] then
			Settings.values[key] = value
			changed:Fire(key, value)
		end
	end
end)

return Settings
