-- Player comfort settings. Kept for this session only for now; saving them
-- arrives with data persistence in a later milestone.

local Settings = {}

Settings.values = {
	cameraShake = true,
	reducedEffects = false,
}

local changed = Instance.new("BindableEvent")
Settings.changed = changed.Event

function Settings.get(key: string): any
	return Settings.values[key]
end

function Settings.set(key: string, value: any)
	Settings.values[key] = value
	changed:Fire(key, value)
end

return Settings
