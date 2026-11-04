-- Movement styles (Roblox animation packs set inside the Animate script):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/animation_test.luau build/game.rbxl
-- Every fighter's character gets its pack's ids on spawn and when the fighter changes; a missing
-- Animate, an R6 rig or a held fighter is left alone.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl")
local Engine, task, world, services, check = api.Engine, api.task, api.world, api.services, api.check
local Animations = world.require(world.find("ReplicatedStorage.Shared.Config.Animations"))
local AnimationStyle = world.require(world.find("ServerScriptService.Server.Combat.AnimationStyle"))
local Powers = world.require(world.find("ReplicatedStorage.Shared.Powers"))
local roblox = require("@lune/roblox") :: any
local Instance, Enum = roblox.Instance, roblox.Enum
api.flatGround(0)

local DEFAULT = "rbxassetid://1"

-- The default Animate script's layout: folders (StringValues) holding Animation values
local function addAnimate(model)
	local animate = Instance.new("LocalScript")
	animate.Name = "Animate"
	for _, slot in Animations.Slots do
		local target = Animations.Targets[slot]
		local folder = animate:FindFirstChild(target[1])
		if not folder then
			folder = Instance.new("StringValue")
			folder.Name = target[1]
			folder.Parent = animate
		end
		local animation = Instance.new("Animation")
		animation.Name = target[2]
		animation.AnimationId = DEFAULT
		animation.Parent = folder
	end
	animate.Parent = model
	return animate
end

local function idsOf(animate)
	local out = {}
	for _, slot in Animations.Slots do
		local target = Animations.Targets[slot]
		out[slot] = animate[target[1]][target[2]].AnimationId
	end
	return out
end

local function expectPack(animate, packName, label)
	local pack = Animations.Packs[packName]
	local ids = idsOf(animate)
	for _, slot in Animations.Slots do
		assert(ids[slot] == "rbxassetid://" .. pack[slot], `{label}: {slot} is {ids[slot]}, wanted {pack[slot]}`)
	end
end

-- Characters of joined players are R15 with an Animate script
local makeCharacter = Engine.character
Engine.character = function(name)
	local model = makeCharacter(name)
	model:FindFirstChildOfClass("Humanoid").RigType = Enum.HumanoidRigType.R15
	addAnimate(model)
	return model
end

check("the pack table has the nine slots for each of the eight packs, from the documented ids", function()
	local count = 0
	for _, pack in Animations.Packs do
		count += 1
		for _, slot in Animations.Slots do
			assert(type(pack[slot]) == "number" and pack[slot] > 0, "an id for " .. slot)
		end
	end
	assert(count == 8, "eight packs")
	assert(Animations.Packs.Superhero.Run == 616117076 and Animations.Packs.Werewolf.Climb == 1083182000, "ids as documented")
	assert(Animations.Packs.Knight.Jump == 658409194 and Animations.Packs.Mage.Idle2 == 707855907, "ids as documented")
end)

check("each fighter maps to its pack", function()
	local want = { StrongDude = "Superhero", Ghost = "Ninja", MachineMaster = "Robot", Grandmaster = "Mage", Corruption = "Vampire", Syntax = "Levitation", Admin = "Knight", Jeffery = "Robot" }
	for fighter, pack in want do
		assert(Animations.packFor(fighter) == pack, fighter)
	end
	assert(Animations.packFor("Shapeshifter") == nil, "the Werewolf pack is held for a later update")
	assert(Animations.packFor("Nobody") == nil and Animations.packFor(nil) == nil, "unknown fighters")
end)

check("a character gets its fighter's pack on spawn and again when the fighter changes", function()
	local player = api.join("Styler", 5001)
	local fighter = api.fighter(player)
	local animate = fighter.model:FindFirstChild("Animate")
	assert(animate, "the test character has Animate")
	local first = fighter.model:GetAttribute("SNPower")
	task.wait(0.4)
	assert(first ~= nil, "joins with a power")
	if Animations.packFor(first) then
		expectPack(animate, Animations.packFor(first), "on spawn " .. first)
	end
	for _, powerId in { "StrongDude", "Ghost", "MachineMaster", "Grandmaster", "Corruption", "Syntax", "Admin" } do
		services.PowerService:equip(fighter, powerId, 1, Powers.defaultLoadout(powerId, 1))
		task.wait(0.4)
		expectPack(animate, Animations.packFor(powerId), powerId)
		assert(fighter.model:GetAttribute(AnimationStyle.Attribute) == Animations.packFor(powerId), "style attribute for " .. powerId)
	end
end)

check("the held Shapeshifter keeps the character's own animations", function()
	local player = api.join("Shifty", 5002)
	local fighter = api.fighter(player)
	local animate = fighter.model.Animate
	services.PowerService:equip(fighter, "Shapeshifter", 1, Powers.defaultLoadout("Shapeshifter", 1))
	task.wait(0.4)
	for slot, id in idsOf(animate) do
		assert(id == DEFAULT, slot .. " untouched: " .. id)
	end
	-- Coming from a styled fighter restores the original animations
	services.PowerService:equip(fighter, "Ghost", 1, Powers.defaultLoadout("Ghost", 1))
	task.wait(0.4)
	expectPack(animate, "Ninja", "Ghost")
	services.PowerService:equip(fighter, "Shapeshifter", 1, Powers.defaultLoadout("Shapeshifter", 1))
	task.wait(0.4)
	for slot, id in idsOf(animate) do
		assert(id == DEFAULT, slot .. " restored: " .. id)
	end
end)

check("Jeffery's sparring unit wears the Robot pack whatever power it plays", function()
	local model = Engine.character("Unit")
	model.Parent = world.workspace
	model:SetAttribute("Look", "Jeffery")
	AnimationStyle.apply(model, "StrongDude", false)
	expectPack(model.Animate, "Robot", "Jeffery's unit")
end)

check("missing Animate, R6 rigs and odd models are harmless", function()
	local bare = makeCharacter("Bare")
	bare:FindFirstChildOfClass("Humanoid").RigType = Enum.HumanoidRigType.R15
	bare.Parent = world.workspace
	AnimationStyle.apply(bare, "Ghost", false)
	AnimationStyle.apply(bare, "Ghost", true)
	local r6 = makeCharacter("R6")
	r6:FindFirstChildOfClass("Humanoid").RigType = Enum.HumanoidRigType.R6
	r6.Parent = world.workspace
	local animate = addAnimate(r6)
	AnimationStyle.apply(r6, "Ghost", true)
	for slot, id in idsOf(animate) do
		assert(id == DEFAULT, "R6 " .. slot .. " untouched")
	end
	-- An Animate with some slots missing still gets the slots it has
	local partial = Engine.character("Partial")
	partial.Parent = world.workspace
	partial.Animate.run:Destroy()
	AnimationStyle.apply(partial, "Ghost", false)
	assert(partial.Animate.walk.WalkAnim.AnimationId == "rbxassetid://" .. Animations.Packs.Ninja.Walk, "walk set")
	AnimationStyle.apply(nil :: any, "Ghost", false)
	-- Applying twice changes nothing more
	AnimationStyle.apply(partial, "Ghost", false)
	assert(partial.Animate.walk.WalkAnim.AnimationId == "rbxassetid://" .. Animations.Packs.Ninja.Walk, "idempotent")
end)

local failed = api.finish()
process.exit(if failed == 0 then 0 else 1)
