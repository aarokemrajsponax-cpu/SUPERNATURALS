-- Low Gravity: a teal, dreamy colour grade, glowing bubbles drifting upward,
-- and a comet trail behind every character as they bound around.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Common = require(script.Parent.Common)

local INVISIBLE = Protocol.Attribute.Invisible

local TEAL = Color3.fromRGB(120, 255, 220)

local function addTrail(character: Model): Trail?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local top = Instance.new("Attachment")
	top.Name = "SNMoonTrailTop"
	top.Position = Vector3.new(0, 1.2, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "SNMoonTrailBottom"
	bottom.Position = Vector3.new(0, -1.2, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "SNMoonTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.8
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(TEAL, Color3.fromRGB(140, 120, 255))
	trail.Transparency = NumberSequence.new(0.4, 1)
	trail.Parent = root
	return trail
end

return function(context)
	local _, ungrade = Common.colorGrade({ TintColor = Color3.fromRGB(215, 250, 245), Saturation = 0.2, Contrast = 0.05 })
	local stopBubbles = Common.sheet({
		color = ColorSequence.new(TEAL, Color3.fromRGB(170, 200, 255)),
		rate = 50,
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.9) }),
		speed = NumberRange.new(2, 4),
		lifetime = NumberRange.new(6, 9),
		height = -6,
		area = 120,
		lightEmission = 0.7,
		transparency = NumberSequence.new(0.45, 1),
		direction = Enum.NormalId.Top,
	})

	local trails: { Trail } = {}
	local current: { [Player]: Trail } = {}
	-- An invisible owner leaves no trail to give them away
	local function showIfVisible(player: Player)
		local trail = current[player]
		if trail then
			trail.Enabled = player:GetAttribute(INVISIBLE) ~= true
		end
	end
	local function decorate(player: Player)
		local character = player.Character
		if character then
			local trail = addTrail(character)
			if trail then
				table.insert(trails, trail)
				current[player] = trail
				showIfVisible(player)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		decorate(player)
	end
	local connections = {}
	for _, player in Players:GetPlayers() do
		table.insert(connections, player.CharacterAdded:Connect(function()
			task.wait(0.5)
			if context.running() then
				decorate(player)
			end
		end))
		table.insert(connections, player:GetAttributeChangedSignal(INVISIBLE):Connect(function()
			showIfVisible(player)
		end))
	end

	return function()
		ungrade()
		stopBubbles()
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, trail in trails do
			local root = trail.Parent
			trail:Destroy()
			if root then
				for _, name in { "SNMoonTrailTop", "SNMoonTrailBottom" } do
					local attachment = root:FindFirstChild(name)
					if attachment then
						attachment:Destroy()
					end
				end
			end
		end
	end
end
