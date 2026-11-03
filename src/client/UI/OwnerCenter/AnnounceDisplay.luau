-- Shows owner announcements to every player. The server sends ("Announce", { text, style, seconds })
-- on Remotes.OverlordEvent to every client on a targeted server. A banner is a solid strip under
-- the top bar with a plain sentence; a toast uses the Shell's toast. The client re-checks the
-- shape because it only trusts what it can safely draw.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Shell = require(script.Parent.Parent.Shell)

local Colors = Theme.Colors
local make = Components.make

local AnnounceDisplay = {}

local MAX_CHARS = 160
local TOP = 78
local gui: ScreenGui? = nil
local banner: Frame? = nil
local bannerText: TextLabel? = nil
local scale: UIScale? = nil
local token = 0

local function ensureBanner()
	if banner and banner.Parent then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = make("ScreenGui", { Name = "SNAnnounce", ResetOnSpawn = false, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
	scale = make("UIScale", { Parent = gui })
	banner = make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP),
		Size = UDim2.new(0.9, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, {
		make("UISizeConstraint", { MaxSize = Vector2.new(720, 400) }),
		Components.corner(Theme.SmallCorner),
		Components.stroke(Colors.Stroke, 1, 0.55),
		Components.padding(12, 16, 12, 20),
	})
	make("Frame", { Name = "Bar", Position = UDim2.fromOffset(-20, -12), Size = UDim2.new(0, 4, 1, 24), BackgroundColor3 = Colors.Accent, BorderSizePixel = 0, Parent = banner })
	bannerText = Components.text({ Name = "Text", Text = "", TextSize = 18, Weight = Theme.Faces.SemiBold, Color = Colors.Text, Wrap = true, Parent = banner })
end

-- Draws one announcement. Returns true when something was shown.
function AnnounceDisplay.show(data: any): boolean
	if typeof(data) ~= "table" or typeof(data.text) ~= "string" then
		return false
	end
	local text = string.gsub(data.text, "[%c]", " ")
	text = string.sub(text, 1, MAX_CHARS * 4)
	if (utf8.len(text) or 0) > MAX_CHARS then
		text = string.sub(text, 1, (utf8.offset(text, MAX_CHARS + 1) or MAX_CHARS + 1) - 1)
	end
	if not string.match(text, "%S") then
		return false
	end
	local seconds = if typeof(data.seconds) == "number" and data.seconds == data.seconds then math.clamp(data.seconds, 3, 15) else 6
	if data.style == "toast" then
		Shell.toast(text, "info")
		return true
	end
	ensureBanner()
	local frame, label = banner :: Frame, bannerText :: TextLabel
	local camera = workspace.CurrentCamera
	if scale and camera then
		scale.Scale = math.clamp(Shell.scale(), 0.5, 1.5)
	end
	label.Text = text
	frame.Visible = true
	token += 1
	local mine = token
	task.delay(seconds, function()
		if token == mine and frame.Parent then
			frame.Visible = false
		end
	end)
	return true
end

function AnnounceDisplay.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local event = remotes:WaitForChild("OverlordEvent") :: RemoteEvent
	event.OnClientEvent:Connect(function(kind, data)
		if kind == Protocol.OverlordSignal.Announce then
			AnnounceDisplay.show(data)
		end
	end)
end

return AnnounceDisplay
