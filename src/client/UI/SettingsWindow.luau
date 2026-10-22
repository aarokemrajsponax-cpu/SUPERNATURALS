-- The Settings window: comfort toggles on the left, audio, interface size and
-- camera sliders on the right. Everything reads and writes through
-- Client/Settings (which saves to the profile a second after the last change).
-- Camera sensitivity is only stored here; the camera controller reads it.

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
	return string.format("%.1f×", value)
end

-- Same limits as the server's sanitizer (Shared/Data/Schema.sanitizeSettings)
local SLIDERS = {
	{ section = "AUDIO", key = "musicVolume", label = "Music volume", min = 0, max = 1, step = 0.05, format = percent },
	{ section = "AUDIO", key = "sfxVolume", label = "Sound volume", min = 0, max = 1, step = 0.05, format = percent },
	-- Resizing everything mid-drag would move the slider under your finger,
	-- so the interface size applies when you let go
	{ section = "INTERFACE & CAMERA", key = "uiScale", label = "Interface size", min = 0.75, max = 1.25, step = 0.05, format = percent, live = false },
	{ section = "INTERFACE & CAMERA", key = "cameraSensitivity", label = "Camera sensitivity", min = 0.2, max = 2, step = 0.1, format = multiplier },
}

local function sectionHeader(parent: Instance, order: number, text: string)
	local header = make("Frame", {
		Name = "Section",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Components.text({ Text = text, Style = "Micro", Color = Colors.TextMuted, Size = UDim2.new(1, 0, 0, 16), Parent = header })
	Components.divider({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = header })
	return header
end

local function column(parent: Instance, name: string, position: UDim2): ScrollingFrame
	local frame = Components.scroll({
		Name = name,
		Position = position,
		Size = UDim2.new(0.5, -Space.S, 1, 0),
		Padding = 2,
		Parent = parent,
	})
	Components.list(frame, Space.S)
	return frame
end

function SettingsWindow.register()
	Shell.registerWindow("Settings", {
		title = "Settings",
		label = "SETTINGS",
		icon = "⚙️",
		order = 8,
		build = function(body: Frame)
			local left = column(body, "Comfort", UDim2.fromScale(0, 0))
			local right = column(body, "Sound", UDim2.new(0.5, Space.S, 0, 0))

			-- Setters so changes made elsewhere (like saved settings arriving) show up
			local setters: { [string]: (any) -> () } = {}

			sectionHeader(left, 1, "COMFORT")
			for order, option in TOGGLES do
				local _, set = Components.toggle(option.label, Settings.get(option.key) == true, function(on)
					Settings.set(option.key, on)
				end, {
					Name = "Toggle_" .. option.key,
					LayoutOrder = order + 1,
					Description = option.description,
					Parent = left,
				})
				setters[option.key] = function(value)
					set(value == true)
				end
			end
			Components.text({
				Name = "Note",
				Text = "Settings save to your profile automatically.",
				Style = "Caption",
				Color = Colors.TextMuted,
				Wrap = true,
				LayoutOrder = 20,
				Parent = left,
			})

			local section: string? = nil
			for order, option in SLIDERS do
				if option.section ~= section then
					section = option.section
					sectionHeader(right, order * 2 - 1, option.section)
				end
				local current = Settings.get(option.key)
				local _, set = Components.slider(option.label, option.min, option.max, option.step, if typeof(current) == "number" then current else option.min, function(value)
					Settings.set(option.key, value)
				end, {
					Name = "Slider_" .. option.key,
					LayoutOrder = order * 2,
					Format = option.format,
					Live = option.live ~= false,
					Parent = right,
				})
				setters[option.key] = function(value)
					if typeof(value) == "number" then
						set(value)
					end
				end
			end

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
