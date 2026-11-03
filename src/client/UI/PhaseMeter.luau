-- The Phase meter: a slim bar above the ability bar that fills as you fight, names the next
-- phase and its fee, says whether you can afford it, and tells you the key. Everything shown
-- comes from the character's attributes (the server writes them) and the profile's Money;
-- pressing the key sends Evolve and the server decides. Hidden when there is nothing to
-- evolve into. Styling is deliberately plain: the interface pass owns the final look.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Profile = require(script.Parent.Parent.Profile)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make
local player = Players.LocalPlayer

local PhaseMeter = {}

local WIDTH = 300

-- What the meter should say for a character's attributes and the player's Money. Pure, so
-- the tests can call it without a screen.
function PhaseMeter.describe(attributes: { [string]: any }, money: number): { visible: boolean, share: number, full: boolean, title: string, detail: string, affordable: boolean }
	local nextName = attributes[Attribute.PhaseNext]
	local fee = attributes[Attribute.PhaseFee]
	local meter = attributes[Attribute.PhaseMeter]
	local max = Selection.Phase.MeterMax
	if typeof(nextName) ~= "string" or typeof(fee) ~= "number" then
		return { visible = false, share = 0, full = false, title = "", detail = "", affordable = false }
	end
	local share = math.clamp((if typeof(meter) == "number" then meter else 0) / max, 0, 1)
	local full = share >= 1
	local affordable = money >= fee
	local cost = if fee <= 0 then "Free" else `{Components.formatNumber(fee)} Money`
	local detail
	if not full then
		detail = `Fight to fill the meter. Costs {cost}.`
	elseif not affordable then
		detail = `Need {cost}. You have {Components.formatNumber(money)}.`
	else
		detail = "Press T to evolve."
	end
	return { visible = true, share = share, full = full, title = `Next phase: {nextName}`, detail = detail, affordable = affordable }
end

-- Builds the meter inside `parent` (the HUD column) and keeps it current
function PhaseMeter.mount(parent: Instance)
	local frame = Components.panel({
		Name = "PhaseMeter",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	Components.padding(Space.S, Space.M, Space.S, Space.M).Parent = frame
	Components.list(frame, Space.XS)
	local title = Components.text({ Name = "Title", Text = "", Style = "label", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = frame })
	local track = make("Frame", {
		Name = "Track",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Components.corner(Theme.TinyCorner) })
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Cyan,
		BorderSizePixel = 0,
		Parent = track,
	}, { Components.corner(Theme.TinyCorner) })
	local detail = Components.text({ Name = "Detail", Text = "", Style = "body", Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, Parent = frame })

	local lastKey = ""
	local function refresh()
		local character = player.Character
		local info = if character then PhaseMeter.describe(character:GetAttributes(), Profile.currency("money")) else nil
		if not info or not info.visible then
			frame.Visible = false
			lastKey = ""
			return
		end
		local key = `{info.title}|{info.detail}|{math.floor(info.share * 100)}`
		if key == lastKey then
			return
		end
		lastKey = key
		frame.Visible = true
		title.Text = info.title
		detail.Text = info.detail
		fill.Size = UDim2.fromScale(info.share, 1)
		fill.BackgroundColor3 = if info.full then (if info.affordable then Colors.Success else Colors.Warning) else Colors.Cyan
	end
	local connection = RunService.Heartbeat:Connect(refresh)
	frame.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return { frame = frame, refresh = refresh }
end

return PhaseMeter
