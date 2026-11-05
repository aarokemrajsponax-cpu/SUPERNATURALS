-- The Settings window: comfort toggles on the left, audio, interface size and
-- camera sliders on the right. Everything reads and writes through
-- Client/Settings (which saves to the profile a second after the last change).
-- Camera sensitivity is only stored here; the camera controller reads it.
-- "Hold to lock on" switches Settings.lockOnMode between "toggle" and "hold".

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Settings = require(script.Parent.Parent.Settings)

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local SettingsWindow = {}

local TOGGLES = {
	{ key = "cameraShake", label = "Screen shake", description = "Shake the camera on big hits" },
	{ key = "reducedEffects", label = "Reduced effects", description = "Fewer particles and smaller effects" },
	{ key = "intenseEffects", label = "Intense flashes", description = "Full-screen flashes and color shifts" },
	{ key = "damageNumbers", label = "Damage numbers", description = "Show numbers when hits land" },
}

local function percent(value: number): string
	return `{math.floor(value * 100 + 0.5)}%`
end

local function multiplier(value: number): string
	return string.format("%.1fx", value)
end

-- Same limits as the server's sanitizer (Shared/Data/Schema.sanitizeSettings)
local SLIDERS = {
	{ section = "AUDIO", key = "musicVolume", label = "Music volume", min = 0, max = 1, step = 0.05, format = percent },
	{ section = "AUDIO", key = "sfxVolume", label = "Sound volume", min = 0, max = 1, step = 0.05, format = percent },
	-- Resizing everything mid-drag would move the slider under your finger,
	-- so the interface size applies when you let go
	{ section = "INTERFACE AND CAMERA", key = "uiScale", label = "Interface size", min = 0.75, max = 1.25, step = 0.05, format = percent, live = false },
	{ section = "INTERFACE AND CAMERA", key = "cameraSensitivity", label = "Camera sensitivity", min = 0.2, max = 2, step = 0.1, format = multiplier },
}

function SettingsWindow.register()
	Shell.registerWindow("Settings", {
		title = "Settings",
		label = "SETTINGS",
		icon = "gear",
		order = 8,
		build = function(body: Frame)
			-- One scrolling column of groups. Every row is label on the left, control on the right.
			local column = Components.scroll({ Name = "SettingsColumn", Padding = 2, Parent = body })
			Components.list(column, Space.L)

			-- Setters so changes made elsewhere (like saved settings arriving) show up
			local setters: { [string]: (any) -> () } = {}

			local function group(order: number, title: string): Frame
				local _, rows = Components.section(column, title, { Name = "Group_" .. title, LayoutOrder = order })
				return rows
			end

			local comfort = group(1, "COMFORT")
			for order, option in TOGGLES do
				local _, set = Components.toggle(option.label, Settings.get(option.key) == true, function(on)
					Settings.set(option.key, on)
				end, {
					Name = "Toggle_" .. option.key,
					LayoutOrder = order,
					Description = option.description,
					Grouped = true,
					Parent = comfort,
				})
				setters[option.key] = function(value)
					set(value == true)
				end
			end
			-- Lock-on is stored as "toggle" or "hold"
			local _, setLockMode = Components.toggle("Hold to lock on", Settings.get("lockOnMode") == "hold", function(on)
				Settings.set("lockOnMode", if on then "hold" else "toggle")
			end, {
				Name = "Toggle_lockOnMode",
				LayoutOrder = #TOGGLES + 1,
				Description = "Off: press once to lock on, tap to switch",
				Grouped = true,
				Parent = comfort,
			})
			setters.lockOnMode = function(value)
				setLockMode(value == "hold")
			end
			local _, setQuickCast = Components.toggle("Quick cast", Settings.get("quickCast") == true, function(on)
				Settings.set("quickCast", on)
			end, {
				Name = "Toggle_quickCast",
				LayoutOrder = #TOGGLES + 2,
				Description = "Aimed abilities cast at your cursor straight away, without the aiming step",
				Grouped = true,
				Parent = comfort,
			})
			setters.quickCast = function(value)
				setQuickCast(value == true)
			end

			local guidance = group(2, "GUIDANCE")
			local _, setHints = Components.toggle("Hints", Settings.get("hints") ~= false, function(on)
				Settings.set("hints", on)
			end, {
				Name = "Toggle_hints",
				Description = "Short tips and button prompts while you play",
				Grouped = true,
				Parent = guidance,
			})
			setters.hints = function(value)
				setHints(value ~= false)
			end

			local groups: { [string]: Frame } = {}
			local sectionOrder = 3
			for order, option in SLIDERS do
				local rows = groups[option.section]
				if not rows then
					rows = group(sectionOrder, option.section)
					groups[option.section] = rows
					sectionOrder += 1
				end
				local current = Settings.get(option.key)
				local _, set = Components.slider(option.label, option.min, option.max, option.step, if typeof(current) == "number" then current else option.min, function(value)
					Settings.set(option.key, value)
				end, {
					Name = "Slider_" .. option.key,
					LayoutOrder = order,
					Format = option.format,
					Live = option.live ~= false,
					Grouped = true,
					Parent = rows,
				})
				setters[option.key] = function(value)
					if typeof(value) == "number" then
						set(value)
					end
				end
			end
			Components.text({
				Name = "Note",
				Text = "Settings save to your profile automatically.",
				Style = "caption",
				Color = Colors.TextMuted,
				Wrap = true,
				LayoutOrder = 99,
				Parent = column,
			})

			Settings.changed:Connect(function(key, value)
				local set = setters[key]
				if set then
					set(value)
				end
			end)

			return {
				onOpen = function()
					-- Show the latest values every time the window opens
					for key, set in setters do
						set(Settings.get(key))
					end
				end,
			}
		end,
	})
end

return SettingsWindow
