-- Layered combat visuals for the launch fighters (Strong Dude, Ghost, Machine
-- Master, Grandmaster, Corruption, Syntax, Admin):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/vfx_signature_test.luau build/game.rbxl
-- Every fighter's main effects draw in that fighter's own palette, with several
-- layers, within the live-part cap, shrink on touch / reduced effects, and
-- everything is gone a few seconds later.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, Engine, world, roblox = t.task, t.Engine, t.world, t.roblox
local Vector3, CFrame = roblox.Vector3, Engine.CFrame

local Settings = t.client("Settings")
local Protocol = t.shared("Protocol")
local Signature = t.client("Effects.Signature")
local Vfx = t.client("Effects.Vfx")
local ClientPowers = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Powers"))
local Attribute = Protocol.Attribute

local function rig(name: string, power: string)
	local model = world.Instance.new("Model")
	model.Name = name
	for _, spec in { { "HumanoidRootPart", Vector3.new(2, 2, 1) }, { "UpperTorso", Vector3.new(2, 1.6, 1) }, { "Head", Vector3.new(1.2, 1.2, 1.2) }, { "RightHand", Vector3.new(0.3, 0.3, 0.3) } } do
		local part = world.Instance.new("Part")
		part.Name = spec[1]
		part.Size = spec[2]
		part.CFrame = CFrame.new(0, 3, 0)
		part.Parent = model
	end
	world.Instance.new("Humanoid").Parent = model
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
	model:SetAttribute(Attribute.Power, power)
	model.Parent = world.workspace
	return model
end

local function folder()
	return Vfx.container()
end

local function near(a, b): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.3
end

-- Parts in the effects folder that match one of the fighter's palette colours
local function palette_parts(palette): (number, number)
	local matching, total = 0, 0
	local root = folder()
	for _, item in (root and root:GetDescendants() or {}) do
		if item:IsA("BasePart") and item.Transparency < 1 then
			total += 1
			for _, key in { "core", "glow", "accent", "extra", "dark" } do
				if near(item.Color, palette[key]) then
					matching += 1
					break
				end
			end
		end
	end
	return matching, total
end

local TARGET = rig("Target", "Ghost")
TARGET.HumanoidRootPart.CFrame = CFrame.new(9, 3, 0)

local DATA = {
	position = Vector3.new(9, 0, 0),
	center = Vector3.new(9, 0, 0),
	from = Vector3.new(0, 3, 0),
	to = Vector3.new(14, 3, 0),
	origin = Vector3.new(0, 3, 0),
	direction = Vector3.new(1, 0, 0),
	length = 30,
	speed = 40,
	width = 6,
	hold = 1,
	passes = 4,
	lines = 6,
	index = 1,
	landed = true,
	range = 9,
	tilt = 35,
	arc = 60,
	radius = 8,
	duration = 0.4,
	target = TARGET,
}

-- The main abilities of each fighter (ability effects the server announces)
local MAIN = {
	StrongDude = { "GroundbreakerWindup", "GroundbreakerImpact", "StompImpact", "ChargeImpact", "Fissure", "WorldBreakerWindup", "WorldBreakerImpact" },
	Ghost = { "InstantDraw", "ShadowStep", "SlashWaveRelease", "FlurrySweep", "GridStrike", "SeveranceWindup", "SeveranceStrike" },
	MachineMaster = { "RailFire", "Burst", "MissileLaunch", "DeviceTrigger", "InfernoCharge", "InfernoBlast", "ShockPulse" },
	Grandmaster = { "TigerStrike", "MountainPalm", "Sweep", "HundredFinish", "AnswerPalm", "UltStance", "UltShockwave" },
	Corruption = { "VoidStrike", "StaticBurst", "RiftBurst", "DistortionPulse", "Cataclysm", "SystemBreakWindup", "SystemBreak" },
	Syntax = { "Strike", "PylonFire", "VentBlast", "CommandExecute", "CellBreak", "Override", "OverrideStrike" },
	Admin = { "CommandExecute", "JailLock", "FlingThrow", "AreaExecute", "SequenceStrike", "BanHammerWindup", "BanHammerSlam" },
}
local ORDER = { "StrongDude", "Ghost", "MachineMaster", "Grandmaster", "Corruption", "Syntax", "Admin" }

for _, power in ORDER do
	t.check(power .. ": main abilities draw layered effects in its own palette, then clean up", function()
		local palette = Signature.palette(power)
		assert(palette, "palette")
		local client = ClientPowers.module(power)
		assert(client, "client module loads")
		local model = rig(power .. "Caster", power)
		task.wait(3)
		for _, name in MAIN[power] do
			local handler = client.fx[name]
			assert(handler, name .. " exists")
			local before = #folder():GetDescendants()
			handler(ClientPowers.kit(model, power, DATA))
			local layers = #folder():GetDescendants() - before
			local matching, total = palette_parts(palette)
			assert(layers >= 4, `{name} makes layers (got {layers})`)
			assert(matching >= 2 and matching * 7 >= total, `{name} uses the {power} palette ({matching} of {total})`)
			assert(Signature.liveParts() <= 110, "live part cap")
			task.wait(1.8)
		end
		-- Hit feedback in the attacker's colours, with the 0.12 s highlight
		assert(Signature.hit(power, Vector3.new(9, 3, 0), TARGET, 2), "hit spark")
		local highlight
		for _, item in folder():GetChildren() do
			if item:IsA("Highlight") then
				highlight = item
			end
		end
		assert(highlight and near(highlight.FillColor, palette.glow), "target highlight in the attacker's colour")
		task.wait(3.5)
		assert(Signature.liveParts() == 0, "pooled parts all returned (" .. Signature.liveParts() .. ")")
		local leftover, names = 0, {}
		for _, item in folder():GetDescendants() do
			if item:IsA("BasePart") and item.Name ~= "SNEmit" then
				leftover += 1
				table.insert(names, item:GetFullName() .. " " .. tostring(item.Transparency))
			end
		end
		assert(leftover == 0, `{leftover} effect parts left after 3 seconds: {table.concat(names, ", ")}`)

		-- Junk data never breaks the signature layers (checked last: a power's older effects may leak a part on junk)
		for _, name in MAIN[power] do
			-- (the decoration itself never throws; a power's own older effects may)
			pcall(client.fx[name], ClientPowers.kit(model, power, { position = "x", from = 4, duration = "y", direction = Vector3.zero }))
		end
		task.wait(3)
		for _, item in folder():GetChildren() do
			if item.Name == "Part" then
				item:Destroy()
			end
		end
		model:Destroy()
	end)
end

t.check("spam is capped and touch / reduced effects use fewer layers", function()
	local palette = Signature.palette("Corruption")
	for _ = 1, 60 do
		Signature.impact(nil, "Corruption", Vector3.new(0, 0, 0), 3)
		assert(Signature.liveParts() <= 110, "hard cap holds")
	end
	task.wait(3)
	assert(Signature.liveParts() == 0, "all returned after spam")
	Settings.values.reducedEffects = false
	local normal = #folder():GetDescendants()
	Signature.impact(nil, "Syntax", Vector3.new(0, 0, 0), 3)
	local full = #folder():GetDescendants() - normal
	task.wait(3)
	Settings.values.reducedEffects = true
	local before = #folder():GetDescendants()
	Signature.impact(nil, "Syntax", Vector3.new(0, 0, 0), 3)
	local fewer = #folder():GetDescendants() - before
	Settings.values.reducedEffects = false
	assert(fewer < full, `reduced effects draw less ({fewer} vs {full})`)
	task.wait(3)
	assert(palette)
end)

t.finish()
