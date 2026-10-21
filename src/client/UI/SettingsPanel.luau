-- A gear button that opens comfort settings: screen shake and reduced effects.

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Settings = require(script.Parent.Parent.Settings)

local Colors = Theme.Colors
local make = Components.make

local SettingsPanel = {}

local OPTIONS = {
	{ key = "cameraShake", label = "Screen shake" },
	{ key = "reducedEffects", label = "Reduced effects" },
}

function SettingsPanel.build(parent: Instance)
	local gear = Components.button("⚙", {
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(44, 44),
		Parent = parent,
	})
	local panel = Components.panel({
		Name = "Settings",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -68),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	Components.padding(12).Parent = panel
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })
	Components.label("SETTINGS", {
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Fonts.Title,
		MaxTextSize = 16,
		Parent = panel,
	})

	for order, option in OPTIONS do
		local toggle: TextButton
		local function render()
			local on = Settings.get(option.key) == true
			toggle.Text = `{option.label}:  {if on then "ON" else "OFF"}`
			toggle.TextColor3 = if on then Colors.Success else Colors.TextDim
		end
		toggle = Components.button("", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 38),
			Parent = panel,
		}, function()
			Settings.set(option.key, not Settings.get(option.key))
			render()
		end)
		render()
	end

	gear.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

return SettingsPanel
