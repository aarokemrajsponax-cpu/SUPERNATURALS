-- The Phase meter: a slim glass plate above the ability bar. It fills as you fight, names the
-- next phase and its fee, and when the meter is full it says so with a key cap: "Meter full:
-- press T to evolve (20 Money)". Everything shown comes from the character's attributes (the
-- server writes them) and the profile's Money; pressing the key sends Evolve and the server
-- decides. Hidden when there is nothing to evolve into.

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
function PhaseMeter.describe(attributes: { [string]: any }, money: number, device: string?): { visible: boolean, share: number, full: boolean, title: string, detail: string, affordable: boolean }
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
	-- The words for the device in hand: a key, a gamepad button or the touch button
	local press = if device == "touch" then "tap Evolve" elseif device == "gamepad" then "press Start" else "press T"
	local detail
	if not full then
		detail = `Fight to fill the meter. Costs {cost}.`
	elseif not affordable then
		detail = `Meter full. Need {cost}. You have {Components.formatNumber(money)}.`
	else
		detail = if fee <= 0 then `Meter full: {press} to evolve (free)` else `Meter full: {press} to evolve ({cost})`
	end
	return { visible = true, share = share, full = full, title = `Next phase: {nextName}`, detail = detail, affordable = affordable }
end

-- Builds the meter inside `parent` (the HUD column) and keeps it current
function PhaseMeter.mount(parent: Instance, device: (() -> string)?)
	local frame = Components.panel({
		Name = "PhaseMeter",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	Components.padding(Space.S, Space.M, Space.S, Space.M).Parent = frame
	Components.list(frame, Space.XS)
	local top = make("Frame", { Name = "Top", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = frame })
	local title = Components.text({ Name = "Title", Text = "", Style = "label", Size = UDim2.new(1, -44, 1, 0), Parent = top })
	local percent = Components.text({ Name = "Percent", Text = "", Style = "number", TextSize = 16, AlignX = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(40, 22), Parent = top })
	local track = make("Frame", {
		Name = "Track",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Stroke, 1, 0.6) })
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Cyan,
		BorderSizePixel = 0,
		Parent = track,
	}, { Components.corner(Theme.TinyCorner) })
	-- The ready cue: a T key cap beside the sentence, shown only when the meter is full
	local cue = make("Frame", { Name = "Cue", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = frame })
	local cap = Components.keycap("T", { Height = 26 })
	cap.AnchorPoint = Vector2.new(0, 0.5)
	cap.Position = UDim2.fromScale(0, 0.5)
	cap.Parent = cue
	local detail = Components.text({ Name = "Detail", Text = "", Style = "caption", Wrap = false, Size = UDim2.new(1, 0, 1, 0), Parent = cue })

	local lastKey = ""
	local function refresh()
		local character = player.Character
		local kind = if device then device() else "keyboard"
		local info = if character then PhaseMeter.describe(character:GetAttributes(), Profile.currency("money"), kind) else nil
		if not info or not info.visible then
			frame.Visible = false
			lastKey = ""
			return
		end
		local key = `{info.title}|{info.detail}|{math.floor(info.share * 100)}|{info.affordable}|{kind}`
		if key == lastKey then
			return
		end
		lastKey = key
		frame.Visible = true
		title.Text = info.title
		percent.Text = `{math.floor(info.share * 100)}%`
		detail.Text = info.detail
		local ready = info.full and info.affordable
		local showCap = ready and kind == "keyboard"
		cap.Visible = showCap
		detail.Position = UDim2.fromOffset(if showCap then 38 else 0, 0)
		detail.Size = UDim2.new(1, if showCap then -38 else 0, 1, 0)
		detail.TextColor3 = if ready then Colors.Text elseif info.full then Colors.Warning else Colors.TextDim
		local color = if info.full then (if info.affordable then Colors.Accent else Colors.Warning) else Colors.Cyan
		fill.BackgroundColor3 = color
		fill.Size = UDim2.fromScale(info.share, 1)
		if stroke then
			stroke.Color = if ready then Colors.Accent else Colors.Stroke
			stroke.Transparency = if ready then 0.2 else 0.5
		end
	end
	-- Ten times a second is plenty for a meter that fills over a fight
	local elapsed = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			if frame.Parent and frame.Parent.Parent and (frame.Parent :: any).Visible ~= false then
				refresh()
			end
		end
	end)
	frame.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return { frame = frame, refresh = refresh }
end

return PhaseMeter
