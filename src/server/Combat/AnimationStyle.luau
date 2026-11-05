-- Gives a fighter's R15 character the movement style (Roblox animation pack) of its power by
-- setting the animation ids inside the character's Animate script. The server calls this when a
-- character spawns with a power and whenever the fighter changes. Missing Animate, R6 rigs and
-- unknown fighters are skipped silently. Combat poses (Poser) are separate and layer on top.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(ReplicatedStorage.Shared.Config.Animations)

local AnimationStyle = {}

AnimationStyle.WaitForAnimate = 6
-- The attribute clients watch to stop the old style's tracks
AnimationStyle.Attribute = Animations.StyleAttribute

-- Which key picks the pack: Jeffery's sparring unit wears the Robot pack whatever power it plays
function AnimationStyle.keyOf(model: Model, powerId: string?): string?
	if model:GetAttribute("Look") == "Jeffery" then
		return "Jeffery"
	end
	return powerId
end

local originals: { [Instance]: { [string]: string } } = setmetatable({}, { __mode = "k" }) :: any

local function slotInstance(animate: Instance, slot: string): Instance?
	local target = Animations.Targets[slot]
	local folder = animate:FindFirstChild(target[1])
	local value = folder and folder:FindFirstChild(target[2])
	if value and value:IsA("Animation") then
		return value
	end
	return nil
end

-- Writes the pack (nil restores the character's own animations). Returns true if anything changed.
local function write(animate: Instance, packName: string?, model: Model): boolean
	local pack = packName and Animations.Packs[packName]
	local saved = originals[model]
	if not pack and not saved then
		return false
	end
	if not saved then
		saved = {}
		originals[model] = saved
	end
	local changed = false
	for _, slot in Animations.Slots do
		local animation = slotInstance(animate, slot)
		if animation then
			if saved[slot] == nil then
				saved[slot] = animation.AnimationId
			end
			local wanted = if pack then Animations.idOf(pack[slot]) else saved[slot]
			if animation.AnimationId ~= wanted then
				animation.AnimationId = wanted
				changed = true
			end
		end
	end
	if not pack then
		originals[model] = nil
	end
	return changed
end

-- Stops the tracks the old style is playing and restarts Animate so the new style shows at
-- once (Animate keeps its Animation objects and would otherwise keep playing the old track)
local function refresh(model: Model, animate: Instance)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		pcall(function()
			for _, track in animator:GetPlayingAnimationTracks() do
				local animation = track.Animation
				if animation and animation:IsDescendantOf(animate) then
					track:Stop(0)
				end
			end
		end)
	end
	pcall(function()
		(animate :: any).Disabled = true
		task.wait(0.1)
		if animate.Parent then
			(animate :: any).Disabled = false
		end
	end)
end

-- Applies the style for a fighter. Safe to call often; yields briefly, so call it in a task.
-- waitForAnimate: players' characters get Animate a moment after they spawn; NPCs may never have one
function AnimationStyle.apply(model: Model, powerId: string?, waitForAnimate: boolean?)
	if not model or not model.Parent then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local animate = model:FindFirstChild("Animate")
	if not animate and waitForAnimate then
		animate = model:WaitForChild("Animate", AnimationStyle.WaitForAnimate)
	end
	if not animate or not model.Parent then
		return
	end
	-- Read the key late: Jeffery's unit is dressed right after it is equipped
	local packName = Animations.packFor(AnimationStyle.keyOf(model, powerId))
	-- The attribute goes first: the owner's client stops its old tracks when it changes, then the
	-- new ids and the Animate restart arrive
	local previous = model:GetAttribute(AnimationStyle.Attribute)
	if previous ~= (packName or "") then
		model:SetAttribute(AnimationStyle.Attribute, packName or "")
	end
	if write(animate, packName, model) then
		refresh(model, animate)
	end
end

-- Starts apply() in its own thread (never blocks the caller)
function AnimationStyle.queue(model: Model, powerId: string?, waitForAnimate: boolean?)
	task.defer(function()
		local ok, err = pcall(AnimationStyle.apply, model, powerId, waitForAnimate)
		if not ok then
			warn("[AnimationStyle] " .. tostring(err))
		end
	end)
end

return AnimationStyle
