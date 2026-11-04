-- The Fighter Showcase (the "Powers" window): see every fighter before you pick one.
-- Left: eight fighter cards (role, owned or locked, exact price). Centre: a live 3D
-- preview of your character wearing the fighter's look for the chosen phase (drag to
-- rotate). Right: the dossier (fantasy, playstyle, difficulty, abilities with their exact
-- numbers, controls and slots, and a tab per phase with its evolve fee).
-- Nothing is bought or charged here. Picking a fighter for a match happens in Play;
-- a premium pass opens Roblox's own purchase prompt. Prices come from Config.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)
local Shell = require(script.Parent.Shell)
local Profile = require(script.Parent.Parent.Profile)
local PriceFetcher = require(script.Parent.Parent.PriceFetcher)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PowerRequest = Remotes:WaitForChild("PowerRequest") :: RemoteEvent

local Action = Protocol.PowerAction
local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local player = Players.LocalPlayer

local PowersWindow = {}

local LEFT_WIDTH = 280
local RIGHT_WIDTH = 372
local NARROW_BELOW = 860
local LINE = "  /  "

-- Shared helpers (the Play window uses them too) ------------------------------------------------

local function powerData(powerId: string): { [string]: any }
	return Profile.powerData(powerId)
end

local function isOwnerAccount(): boolean
	return player:GetAttribute(Attribute.IsOwner) == true
end

-- Does the player own this power outright (free powers always)?
local function owns(def): boolean
	if not def.premium then
		return true
	end
	if isOwnerAccount() then
		return true
	end
	local view = Profile.get()
	local passes = view and view.passes
	if typeof(passes) == "table" and passes[def.premium.pass] then
		return true
	end
	return powerData(def.id).owned == true
end

-- A running trial ticket for a premium fighter the player does not own: "Trial: 23 h left"
-- (hours rounded down; "Trial: under 1 h left" in the last hour). Nil when there is none.
-- The server holds the end time in profile.trials and ends the trial itself.
local function trialText(def): string?
	if not def.premium then
		return nil
	end
	local view = Profile.get()
	local trials = view and view.trials
	local endsAt = typeof(trials) == "table" and trials[def.id]
	if typeof(endsAt) ~= "number" then
		return nil
	end
	local left = endsAt - workspace:GetServerTimeNow()
	if left <= 0 then
		return nil
	end
	local hours = math.floor(left / 3600)
	if hours < 1 then
		return "Trial: under 1 h left"
	elseif hours >= 48 then
		return `Trial: {math.floor(hours / 24)} d {hours % 24} h left`
	end
	return `Trial: {hours} h left`
end

local function degreeOpen(def, degree: number): boolean
	return isOwnerAccount() or Powers.degreeUnlocked(def.id, degree, powerData(def.id))
end

local function savedLoadout(powerId: string, degree: number): { string }
	local view = Profile.get()
	local loadouts = view and view.loadouts
	local saved = typeof(loadouts) == "table" and loadouts[powerId]
	local list = typeof(saved) == "table" and saved[tostring(degree)]
	if typeof(list) == "table" then
		local ok, _, cleaned = Powers.validateLoadout(powerId, degree, list, powerData(powerId))
		if ok and cleaned then
			return cleaned
		end
	end
	return Powers.defaultLoadout(powerId, degree)
end

-- The fee to evolve into a phase (Money). Free for the owner and for Phase 1.
local function phaseFee(def, phase: number): number
	if phase <= 1 or isOwnerAccount() then
		return 0
	end
	return Selection.priceFor(def.id, phase, def.premium ~= nil)
end

local function feeText(fee: number): string
	return if fee <= 0 then "Free" else `{Components.formatNumber(fee)} Money`
end

-- The live price state of a premium fighter's pass, read from Roblox (never hard-coded).
-- Returns the state and the text to show ("R$ ...", "Available soon", "Price unavailable").
local onPriceChange: (() -> ())? = nil
local function passPrice(def): (any, string)
	local pass = def.premium and Monetization.Passes[def.premium.pass]
	local state = PriceFetcher.get("GamePass", pass and pass.id or 0, function()
		if onPriceChange then
			onPriceChange()
		end
	end)
	return state, PriceFetcher.describe(state)
end

-- A permanent unlock price ({ money } or { gems }) as text, and whether the player can pay it
local function unlockPriceText(price): string
	if price.gems then
		return `{Components.formatNumber(price.gems)} Gems`
	end
	return `{Components.formatNumber(price.money or 0)} Money`
end
local function canPay(price): boolean
	if isOwnerAccount() then
		return true
	end
	if price.gems then
		return Profile.currency("gems") >= price.gems
	end
	return Profile.currency("money") >= (price.money or 0)
end

-- The fighters this player can see: the released ones, or all of them for the owner (testing)
local function fighterIds(): { string }
	return if isOwnerAccount() then Powers.Order else Powers.released()
end

PowersWindow.helpers = {
	fighters = fighterIds,
	owns = owns,
	degreeOpen = degreeOpen,
	savedLoadout = savedLoadout,
	phaseFee = phaseFee,
	feeText = feeText,
	isOwner = isOwnerAccount,
}

-- Descriptions in the power definitions may hold em dashes; the interface never shows them
local function clean(text: string): string
	local out = string.gsub(text, " \u{2014} ", ", ")
	out = string.gsub(out, "\u{2014}", ", ")
	return out
end
PowersWindow.clean = clean

local function statsLine(ability, resourceName: string?): string
	local parts = {}
	if ability.kind == "Ultimate" then
		table.insert(parts, "Needs a full ultimate bar")
	else
		if (ability.cooldown or 0) > 0 then
			table.insert(parts, `{ability.cooldown}s cooldown`)
		end
		if (ability.cost or 0) > 0 then
			table.insert(parts, `{ability.cost} {resourceName or "energy"}`)
		end
	end
	if (ability.damage or 0) > 0 then
		table.insert(parts, `{ability.damage} damage`)
	end
	if (ability.range or 0) > 0 then
		table.insert(parts, `{ability.range} studs`)
	end
	if ability.defense == "Timing" then
		table.insert(parts, "Timing-bar defense")
	elseif ability.defense == "Prompt" then
		table.insert(parts, "Dodge or block prompt")
	elseif ability.defense == "Mash" then
		table.insert(parts, "Mash to escape")
	end
	return table.concat(parts, LINE)
end
PowersWindow.statsLine = statsLine

-- The 3D preview ----------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?)
	local item = make("Part", {
		Name = name,
		Size = size,
		CFrame = CFrame.new(offset),
		Color = color,
		Anchored = true,
		CanCollide = false,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	if shape then
		item.Shape = shape
	end
	return item
end

-- A plain stand-in figure for when the player has no character yet
local function dummy(color: Color3): Model
	local model = make("Model", { Name = "PreviewDummy" })
	local skin = Color3.fromRGB(214, 190, 164)
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), color)
	root.Transparency = 0
	part(model, "Head", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 4.7, 0), skin, Enum.PartType.Ball)
	part(model, "LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), color)
	part(model, "RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), color)
	part(model, "LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), Colors.Ink:Lerp(color, 0.3))
	part(model, "RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), Colors.Ink:Lerp(color, 0.3))
	model.PrimaryPart = root
	return model
end

-- The player's own character (a clone, with scripts and the Humanoid's name tag removed)
local function characterCopy(): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	for _, item in copy:GetDescendants() do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
		elseif item:IsA("Humanoid") then
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	if not copy.PrimaryPart then
		local root = copy:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			copy.PrimaryPart = root
		end
	end
	return if copy.PrimaryPart then copy else nil
end

local function powerModule(powerId: string): any?
	local ok, ClientPowers = pcall(function()
		return require(script.Parent.Parent.Powers)
	end)
	if not ok then
		return nil, nil
	end
	return ClientPowers.module(powerId), ClientPowers
end

-- The hall statue for a fighter, copied from the replicated world (the hub builds
-- "Statue_<PowerId>" under Workspace, and streaming is off, so it is always there once the
-- hub exists). Returns a clone standing on the floor point, facing +Z (toward the preview
-- camera), with its lights and scripts removed, or nil when the statue is not in the world.
local sourceCache: { [string]: Model } = {}

local function statueSource(powerId: string): Model?
	local cached = sourceCache[powerId]
	if cached and cached.Parent then
		return cached
	end
	local ok, found = pcall(function()
		return workspace:FindFirstChild("Statue_" .. powerId, true)
	end)
	if ok and found and found:IsA("Model") then
		sourceCache[powerId] = found
		return found
	end
	return nil
end

local function statueCopy(powerId: string): Model?
	local source = statueSource(powerId)
	if not source then
		return nil
	end
	local ok, copy = pcall(function()
		return source:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	for _, item in copy:GetDescendants() do
		if item:IsA("BaseScript") or item:IsA("Light") or item:IsA("ParticleEmitter") or item:IsA("Sound") or item:IsA("ProximityPrompt") or item:IsA("SurfaceGui") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
		end
	end
	local lights = copy:FindFirstChild("Lights")
	if lights then
		lights:Destroy()
	end
	-- The statue's pivot is the floor point under its plinth, facing -Z. Move every part so the
	-- floor point is the origin and the figure faces +Z (toward the preview camera), and note the
	-- top of the figure. Done part by part so it works in the stand-in engine as well.
	local okPivot, base = pcall(function()
		return copy:GetPivot()
	end)
	if not okPivot or typeof(base) ~= "CFrame" then
		return nil
	end
	local turn = CFrame.Angles(0, math.pi, 0)
	local inverse = base:Inverse()
	local top = 0
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			local moved = turn * inverse * item.CFrame
			item.CFrame = moved
			top = math.max(top, moved.Y + item.Size.Y / 2)
		end
	end
	pcall(function()
		copy.WorldPivot = CFrame.new()
	end)
	copy:SetAttribute("PreviewTop", top)
	return copy
end

type Preview = {
	frame: Frame,
	look: (powerId: string, phase: number) -> (),
	stop: () -> (),
	hasAppearance: () -> boolean,
	usingStatue: () -> boolean,
}

-- Builds the viewport inside `parent`. look(power, phase) puts the fighter's own hall statue on
-- the stage (the player's character, then a plain stand-in, only when the statue is missing);
-- it turns slowly, a drag turns it by hand. The camera frames the figure from its size.
local function buildPreview(parent: Instance): Preview
	local stage = make("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		Parent = parent,
	}, { Components.corner(Theme.Corner), Components.stroke(Colors.Stroke, 1, 0.6) })
	-- A soft glow behind the figure in the fighter's two colours (the stage itself is a gradient)
	local glow = make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 1, Parent = stage })
	Components.gradientFor(glow, Colors.Cyan, Colors.Purple, "Hover", 65)
	local viewport = make("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 156, 172),
		LightColor = Color3.fromRGB(255, 242, 224),
		LightDirection = Vector3.new(-0.45, -0.55, -0.7),
		ZIndex = 2,
		Parent = stage,
	})
	local world = make("WorldModel", { Parent = viewport })
	local camera = make("Camera", { FieldOfView = 32, Parent = viewport })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 20, 60), Vector3.new(0, 18, 0))
	viewport.CurrentCamera = camera

	local state = {
		model = nil :: Model?,
		cleanup = nil :: (() -> ())?,
		yaw = 0,
		dragging = false,
		clock = 0,
		powerId = "",
		statue = false,
		hasAppearance = false,
		tries = 0,
		turn = 0,
		low = 0,
		high = 30,
	}

	local function clear()
		if state.cleanup then
			pcall(state.cleanup)
			state.cleanup = nil
		end
		if state.model then
			state.model:Destroy()
			state.model = nil
		end
	end

	-- Points the camera so the figure (from `low` to `high` studs up) fills the stage
	local function frameCamera()
		local ok, size = pcall(function()
			return viewport.AbsoluteSize
		end)
		local aspect = if ok and size.Y > 0 then size.X / size.Y else 1
		local height = math.max(state.high - state.low, 4)
		local fov = math.rad(camera.FieldOfView)
		local byHeight = (height / 2) / math.tan(fov / 2)
		local byWidth = (height * 0.42 / aspect) / math.tan(fov / 2)
		local distance = math.max(byHeight, byWidth) * 1.08
		local middle = (state.low + state.high) / 2
		camera.CFrame = CFrame.lookAt(Vector3.new(0, middle + height * 0.06, distance), Vector3.new(0, middle, 0))
	end

	local function place()
		local model = state.model
		if not model then
			return
		end
		local breath = if state.statue then 0 else math.sin(state.clock * 1.6) * 0.06
		pcall(function()
			model:PivotTo(CFrame.new(0, breath, 0) * CFrame.Angles(0, math.rad(state.yaw) + state.turn, 0))
		end)
	end

	local function look(powerId: string, phase: number)
		clear()
		local def = Powers.get(powerId)
		if not def then
			return
		end
		if state.powerId ~= powerId then
			state.tries = 0
		end
		state.powerId = powerId
		local model = statueCopy(powerId)
		state.statue = model ~= nil
		if not model then
			model = characterCopy() or dummy(def.colors.primary)
		end
		state.turn = if state.statue then 0 else math.pi
		model.Name = "PreviewFighter"
		model:SetAttribute(Attribute.Power, powerId)
		model:SetAttribute(Attribute.Degree, phase)
		local count = Powers.degreeCount(powerId)
		model:SetAttribute(Attribute.Phase, math.clamp((phase - 1) / math.max(count - 1, 1), 0.05, 1))
		model.Parent = world
		state.model = model
		state.hasAppearance = false
		Components.gradientFor(glow, def.colors.primary, def.colors.secondary, "Hover", 65)

		if state.statue then
			-- Frame from the plinth's middle up to just over the crown
			local measured = model:GetAttribute("PreviewTop")
			local top = if typeof(measured) == "number" and measured > 4 then measured else 39
			state.low = top * 0.12
			-- Leave room above the crown for the name banner over the stage
			state.high = top + (top - state.low) * 0.24
		else
			state.low, state.high = -0.5, 6.5
			-- The player's own character can wear the power's look; a stand-in cannot
			local mod, ClientPowers = powerModule(powerId)
			if mod and ClientPowers and typeof(mod.appearance) == "function" and model:FindFirstChildOfClass("Humanoid") then
				local okKit, kit = pcall(ClientPowers.kit, model, powerId)
				if okKit then
					local ok, cleanup = pcall(mod.appearance, kit)
					if ok then
						state.hasAppearance = true
						if typeof(cleanup) == "function" then
							state.cleanup = cleanup
						end
					end
				end
			end
		end
		frameCamera()
		place()
	end

	-- The hub may not have replicated yet: look again a few times until the statue shows up
	local function retry()
		if state.statue or state.tries >= 8 or state.powerId == "" then
			return
		end
		state.tries += 1
		if statueSource(state.powerId) then
			look(state.powerId, (state.model and state.model:GetAttribute(Attribute.Degree)) or 1)
		end
	end

	-- Drag to rotate (mouse or touch)
	local dragFrom: number? = nil
	stage.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragFrom = input.Position.X
			state.dragging = true
		end
	end)
	local changed = UserInputService.InputChanged:Connect(function(input)
		if dragFrom and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			state.yaw += (input.Position.X - dragFrom) * 0.6
			dragFrom = input.Position.X
			place()
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragFrom = nil
			state.dragging = false
		end
	end)
	local sizeLink = viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(frameCamera)
	local sinceRetry = 0
	local beat = RunService.Heartbeat:Connect(function(dt)
		state.clock += dt
		if not state.dragging and state.model then
			-- A slow, steady turn: one full circle in about 24 seconds
			state.yaw += dt * 15
		end
		sinceRetry += dt
		if sinceRetry > 1 then
			sinceRetry = 0
			retry()
		end
		place()
	end)
	local function stop()
		beat:Disconnect()
		changed:Disconnect()
		ended:Disconnect()
		sizeLink:Disconnect()
		clear()
	end
	stage.Destroying:Connect(stop)
	return {
		frame = stage,
		look = look,
		stop = stop,
		hasAppearance = function()
			return state.hasAppearance
		end,
		usingStatue = function()
			return state.statue
		end,
	}
end

-- The ability demonstration: a top-down plan drawn from the ability's own numbers (range,
-- radius, arc, width, speed), with the fighter as a dot at the bottom and forward as up.
-- It plays on a loop. It shows how far and how wide an ability reaches, not its look, so it
-- works for every ability and never depends on a rig or on effects that need the world.
local PLAN_PX = 140
local PLAN_STUDS_MAX = 36

type Plan = {
	frame: Frame,
	show: (ability: any?, accent: Color3) -> string,
	stop: () -> (),
}

local function buildPlan(parent: Instance): Plan
	local frame = make("Frame", {
		Name = "Plan",
		Size = UDim2.fromOffset(PLAN_PX, PLAN_PX),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,
	}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Stroke, 1, 0.5) })
	-- Faint grid so distance reads: a line every 10 studs
	local groundY = PLAN_PX - 24
	local pxPerStud = (groundY - 14) / 24
	for step = 1, 3 do
		make("Frame", {
			Name = "GridLine",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(0, groundY - step * 10 * pxPerStud),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Colors.Stroke,
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			Parent = frame,
		})
	end
	local shape = make("Frame", {
		Name = "Reach",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(PLAN_PX / 2, groundY),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = frame,
	}, { make("UICorner", { Name = "ShapeCorner", CornerRadius = UDim.new(0, 4) }), Components.stroke(Colors.Cyan, 2, 0.1) })
	local runner = make("Frame", {
		Name = "Runner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(PLAN_PX / 2, groundY),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local fighter = make("Frame", {
		Name = "Fighter",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(PLAN_PX / 2, groundY),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), Components.stroke(Colors.Ink, 2, 0) })
	Components.text({
		Name = "Scale",
		Text = "10 studs a line",
		Style = "small",
		Color = Colors.TextMuted,
		AlignX = "Center",
		Position = UDim2.new(0, 0, 1, -20),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		ZIndex = 6,
		Parent = frame,
	})

	local current: { kind: string, reach: number, width: number, speed: number }? = nil
	local clock = 0
	local PERIOD = 2.2

	local function studs(value: number): number
		return math.max(value, 0) * pxPerStud
	end

	-- What the shape is, from the ability's fields
	local function describe(ability: any): ({ kind: string, reach: number, width: number, speed: number }, string)
		local kind = ability.kind or "Melee"
		local range = ability.range or 0
		local radius = ability.radius or 0
		local width = ability.width or 0
		local arc = ability.arc or 0
		if kind == "Projectile" then
			local reach = if range > 0 then range else math.min((ability.speed or 60) * (ability.lifetime or 0.5), 30)
			return { kind = "line", reach = reach, width = math.max(width, 2.5), speed = 1 }, `Flies about {math.floor(reach + 0.5)} studs ahead.`
		elseif kind == "Dash" or kind == "Teleport" then
			local reach = if range > 0 then range else 14
			return { kind = "move", reach = reach, width = 3, speed = 1 }, `Moves you about {math.floor(reach + 0.5)} studs ahead.`
		elseif kind == "Area" or kind == "Zone" or kind == "Construct" then
			local size = if radius > 0 then radius else (if range > 0 then range else 8)
			if ability.targeting == "point" and range > 0 then
				return { kind = "spot", reach = range, width = size * 2, speed = 1 }, `Lands up to {math.floor(range + 0.5)} studs away, about {math.floor(size * 2 + 0.5)} studs wide.`
			end
			return { kind = "ring", reach = size, width = size * 2, speed = 1 }, `Covers a circle about {math.floor(size * 2 + 0.5)} studs wide around the target.`
		elseif kind == "Buff" or kind == "Form" or kind == "Ultimate" and range <= 0 and radius <= 0 then
			return { kind = "self", reach = 6, width = 12, speed = 1 }, "Works on the fighter, so there is no reach to show."
		end
		-- Melee, Grab, Throw, Counter and the rest: a reach box in front
		local reach = if range > 0 then range else (if radius > 0 then radius else 6)
		local across = if arc > 0 and arc < 180 then 2 * reach * math.sin(math.rad(arc) / 2) else math.max(reach * 1.6, 4)
		if radius > 0 and range <= 0 then
			return { kind = "ring", reach = radius, width = radius * 2, speed = 1 }, `Hits all around, up to {math.floor(radius + 0.5)} studs out.`
		end
		return { kind = "box", reach = reach, width = across, speed = 1 }, `Reaches about {math.floor(reach + 0.5)} studs in front.`
	end

	local function show(ability: any?, accent: Color3): string
		shape.BackgroundColor3 = accent
		local stroke = shape:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = accent:Lerp(Colors.Text, 0.3)
		end
		if not ability then
			current = nil
			shape.Visible = false
			runner.Visible = false
			return ""
		end
		local info, line = describe(ability)
		current = info
		shape.Visible = true
		clock = 0
		return line
	end

	local function frameStep(dt: number)
		local info = current
		if not info then
			return
		end
		clock += dt
		local p = (clock % PERIOD) / PERIOD
		-- Grow over the first 60 percent, hold, then fade out
		local grow = math.clamp(p / 0.6, 0, 1)
		grow = 1 - (1 - grow) * (1 - grow)
		local fade = if p > 0.75 then (p - 0.75) / 0.25 else 0
		local corner = shape:FindFirstChild("ShapeCorner") :: UICorner
		local maxReach = math.min(info.reach, PLAN_STUDS_MAX)
		local scale = math.min(1, 24 / math.max(maxReach + (if info.kind == "spot" then info.width / 2 else 0), 24)) -- keep it on the plan
		local function px(value: number): number
			return studs(value) * scale
		end
		runner.Visible = false
		if info.kind == "box" then
			shape.AnchorPoint = Vector2.new(0.5, 1)
			shape.Position = UDim2.fromOffset(PLAN_PX / 2, groundY - 8)
			shape.Size = UDim2.fromOffset(math.max(px(info.width), 12), math.max(px(info.reach) * grow, 4))
			corner.CornerRadius = UDim.new(0, 6)
		elseif info.kind == "line" or info.kind == "move" then
			shape.AnchorPoint = Vector2.new(0.5, 1)
			shape.Position = UDim2.fromOffset(PLAN_PX / 2, groundY - 8)
			shape.Size = UDim2.fromOffset(math.max(px(info.width), 5), math.max(px(info.reach), 6))
			corner.CornerRadius = UDim.new(0, 3)
			runner.Visible = true
			runner.Position = UDim2.fromOffset(PLAN_PX / 2, groundY - 8 - px(info.reach) * grow)
		elseif info.kind == "spot" then
			local size = math.max(px(info.width) * grow, 6)
			shape.AnchorPoint = Vector2.new(0.5, 0.5)
			shape.Position = UDim2.fromOffset(PLAN_PX / 2, groundY - px(info.reach))
			shape.Size = UDim2.fromOffset(size, size)
			corner.CornerRadius = UDim.new(1, 0)
		else
			-- ring and self: a circle around the fighter
			local size = math.max(px(info.width) * grow, 8)
			shape.AnchorPoint = Vector2.new(0.5, 0.5)
			shape.Position = UDim2.fromOffset(PLAN_PX / 2, groundY)
			shape.Size = UDim2.fromOffset(size, size)
			corner.CornerRadius = UDim.new(1, 0)
		end
		shape.BackgroundTransparency = math.clamp(0.62 + fade * 0.38 - grow * 0.1, 0, 1)
		local stroke = shape:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = math.clamp(0.1 + fade * 0.9, 0, 1)
		end
	end

	local beat = RunService.Heartbeat:Connect(frameStep)
	local function stop()
		beat:Disconnect()
	end
	frame.Destroying:Connect(stop)
	return { frame = frame, show = show, stop = stop }
end

-- The window --------------------------------------------------------------------------------------

local function swatch(parent: Instance, color: Color3, order: number)
	make("Frame", {
		Name = "Swatch",
		LayoutOrder = order,
		Size = UDim2.fromOffset(28, 14),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Stroke, 1, 0.4) })
end

local function difficultyRow(parent: Instance, difficulty: number, accent: Color3, order: number)
	local row = make("Frame", { Name = "Difficulty", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = parent })
	Components.list(row, Space.XS, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	Components.text({ Text = "Difficulty", Style = "label", Color = Colors.TextMuted, Size = UDim2.fromOffset(84, 20), LayoutOrder = 0, Parent = row })
	for index = 1, 5 do
		make("Frame", {
			Name = "Pip",
			LayoutOrder = index,
			Size = UDim2.fromOffset(18, 8),
			BackgroundColor3 = if index <= difficulty then accent else Colors.Stroke,
			BackgroundTransparency = if index <= difficulty then 0 else 0.5,
			BorderSizePixel = 0,
			Parent = row,
		}, { Components.corner(Theme.TinyCorner) })
	end
	Components.text({ Text = `{difficulty} of 5`, Style = "number", Color = Colors.TextDim, Size = UDim2.fromOffset(60, 20), LayoutOrder = 9, Parent = row })
end

function PowersWindow.register()
	Shell.registerWindow("Powers", {
		title = "Fighters",
		label = "FIGHTERS",
		icon = "star",
		order = 2,
		size = Vector2.new(1160, 640),
		accent = Colors.Purple,
		build = function(body: Frame, api)
			local selectedPower = Powers.Default
			local selectedPhase = 1
			local cards: { [string]: any } = {}
			local pane = "preview"

			local fighterPane = make("Frame", { Name = "PowerListPane", BackgroundTransparency = 1, Parent = body })
			local list = Components.scroll({ Name = "PowerList", Size = UDim2.fromScale(1, 1), Padding = 2, Parent = fighterPane })
			Components.list(list, Space.S)
			local centre = make("Frame", { Name = "PreviewPane", BackgroundTransparency = 1, Parent = body })
			local right = make("Frame", { Name = "DossierPane", BackgroundTransparency = 1, Parent = body })
			local detail = Components.scroll({ Name = "PowerDetail", Size = UDim2.new(1, 0, 1, -(Theme.Size.Control + Space.M)), Padding = 2, Parent = right })
			Components.list(detail, Space.M)
			local actions = make("Frame", {
				Name = "PowerActions",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, Theme.Size.Control),
				BackgroundTransparency = 1,
				Parent = right,
			})
			Components.list(actions, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })

			-- Centre: the banner and the turning statue on the stage, and under it the "what this
			-- ability does" strip (its key, a plain description and the animated reach plan)
						local preview = buildPreview(centre)
			local banner = make("Frame", {
				Name = "Banner",
				Size = UDim2.new(1, 0, 0, 76),
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = preview.frame,
			})
			local bannerName = Components.text({
				Name = "FighterName",
				Style = "display",
				Text = "",
				Position = UDim2.fromOffset(Space.L, 8),
				Size = UDim2.new(1, -Space.L * 2, 0, 40),
				ZIndex = 7,
				Parent = banner,
			})
			local bannerRole = Components.text({
				Name = "FighterRole",
				Style = "strong",
				Text = "",
				Color = Colors.Text,
				Position = UDim2.fromOffset(Space.L, 46),
				Size = UDim2.new(1, -Space.L * 2, 0, 24),
				ZIndex = 7,
				Parent = banner,
			})
			local hint = Components.text({
				Name = "Hint",
				Style = "small",
				Text = "Drag to turn the statue",
				Color = Colors.Text,
				AlignX = "Center",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -Space.S),
				Size = UDim2.new(1, -Space.L * 2, 0, 22),
				ZIndex = 6,
				Parent = preview.frame,
			})
			make("UIStroke", { Thickness = Theme.TextShadow.StrokeThickness, Color = Colors.Ink, Transparency = Theme.TextShadow.StrokeTransparency, Parent = hint })
			Components.dropShadow(hint, 1, 0.5)

			-- "What this ability does": its key, a plain description and the animated reach plan.
			-- It sits in the dossier column, under the fighter's description (renderDossier keeps it).
			local strip = make("Frame", {
				Name = "AbilityStrip",
				LayoutOrder = 2,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Colors.Panel,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Parent = detail,
			}, { Components.corner(Theme.Corner), Components.stroke(Colors.Stroke, 1, 0.6), Components.padding(Space.M) })
			Components.list(strip, Space.S)
			Components.text({ Name = "StripTitle", Text = "Pick a key to see the ability", Style = "overline", LayoutOrder = 1, Wrap = true, Parent = strip })
			local keyRow = make("Frame", {
				Name = "AbilityKeys",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 44),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Parent = strip,
			})
			Components.list(keyRow, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Top, Wraps = true })
			local abilityName = Components.text({ Name = "AbilityName", Style = "strong", Text = "", LayoutOrder = 3, Wrap = true, Parent = strip })
			local abilityText = Components.text({ Name = "AbilityText", Style = "body", Text = "", Color = Colors.Text, LayoutOrder = 4, Wrap = true, Parent = strip })
			local planRow = make("Frame", {
				Name = "PlanRow",
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, PLAN_PX),
				BackgroundTransparency = 1,
				Parent = strip,
			})
			local plan = buildPlan(planRow)
			local planNote = Components.text({
				Name = "PlanNote",
				Style = "small",
				Text = "",
				Wrap = true,
				Position = UDim2.fromOffset(PLAN_PX + Space.M, 0),
				Size = UDim2.new(1, -(PLAN_PX + Space.M), 0, 0),
				Parent = planRow,
			})

			local demoIndex = 1
			local demoAbilities: { any } = {}
			local keyButtons: { TextButton } = {}
			-- Re-draws the strip for the chosen ability: key chips, its text and the reach plan
			local function showAbility(index: number)
				local def = Powers.get(selectedPower)
				if not def then
					return
				end
				demoIndex = math.clamp(index, 1, math.max(#demoAbilities, 1))
				local entry = demoAbilities[demoIndex]
				for chipIndex, chipButton in keyButtons do
					Components.setSelected(chipButton, chipIndex == demoIndex)
				end
				if not entry then
					abilityName.Text = "No abilities yet"
					abilityText.Text = ""
					planNote.Text = ""
					plan.show(nil, def.colors.primary)
					return
				end
				local ability = entry.ability
				abilityName.Text = if entry.key == "+" then `{ability.name} (not on a key yet: set it in Play)` else `Key {entry.key}: {ability.name}`
				local description = if typeof(ability.description) == "string" then clean(ability.description) else ""
				local reach = plan.show(ability, def.colors.primary:Lerp(Colors.Text, 0.15))
				abilityText.Text = description
				planNote.Text = `Top view: the dot is you, up is forward. {reach}`
			end

			-- The ability list for the chosen fighter and phase, each with its key
			local function rebuildStrip()
				for _, chipButton in keyButtons do
					chipButton:Destroy()
				end
				table.clear(keyButtons)
				table.clear(demoAbilities)
				local def = Powers.get(selectedPower)
				if not def then
					return
				end
				local loadout = savedLoadout(selectedPower, selectedPhase)
				local slotOf = {}
				for slot, abilityId in loadout do
					slotOf[abilityId] = slot
				end
				local ids = Powers.available(selectedPower, selectedPhase)
				local ultimate = Powers.ultimateOf(selectedPower, selectedPhase)
				if ultimate then
					table.insert(ids, ultimate)
				end
				for _, abilityId in ids do
					local ability = Powers.abilityFor(selectedPower, abilityId, selectedPhase)
					if ability then
						local key = if ability.kind == "Ultimate" then "R" elseif slotOf[abilityId] then tostring(slotOf[abilityId]) else "+"
						table.insert(demoAbilities, { id = abilityId, ability = ability, key = key })
					end
				end
				for index, entry in demoAbilities do
					local chipButton = Components.button(entry.key, {
						Name = "AbilityKey_" .. entry.id,
						Variant = "Secondary",
						KeepCase = true,
						Size = UDim2.fromOffset(44, 44),
						LayoutOrder = index,
						Parent = keyRow,
					}, function()
						showAbility(index)
					end)
					table.insert(keyButtons, chipButton)
				end
				showAbility(math.min(demoIndex, math.max(#demoAbilities, 1)))
			end

			local function showFighter(def)
				bannerName.Text = def.name
				bannerRole.Text = `{def.style}`
				Components.gradientFor(banner, def.colors.primary, def.colors.secondary, "Selected", 0)
				demoIndex = 1
				rebuildStrip()
			end

			-- Layout: three columns when wide, one pane at a time with a switcher when narrow
			local tabsHolder = make("Frame", { Name = "PaneTabs", Size = UDim2.new(1, 0, 0, Theme.Size.Control), BackgroundTransparency = 1, Visible = false, Parent = body })
			local paneTabs
			local function layout()
				local ok, size = pcall(function()
					return body.AbsoluteSize
				end)
				if not ok then
					-- No layout yet (a stand-in engine): estimate from the screen
					local view = workspace.CurrentCamera.ViewportSize
					size = Vector2.new(math.min(1120, view.X - 140), math.max(170, math.min(520, view.Y - 290)))
				end
				local w, h = size.X, size.Y
				if w <= 0 then
					return
				end
				if w >= NARROW_BELOW then
					tabsHolder.Visible = false
					fighterPane.Visible, centre.Visible, right.Visible = true, true, true
					local rightWidth = math.min(RIGHT_WIDTH, math.floor(w * 0.34))
					local middle = w - LEFT_WIDTH - rightWidth - Space.L * 2
					fighterPane.Position, fighterPane.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(LEFT_WIDTH, h)
					centre.Position, centre.Size = UDim2.fromOffset(LEFT_WIDTH + Space.L, 0), UDim2.fromOffset(middle, h)
					right.Position, right.Size = UDim2.fromOffset(w - rightWidth, 0), UDim2.fromOffset(rightWidth, h)
				else
					tabsHolder.Visible = true
					local top = Theme.Size.Control + Space.S
					for id, frame in { fighters = fighterPane, preview = centre, dossier = right } do
						frame.Visible = id == pane
						frame.Position, frame.Size = UDim2.fromOffset(0, top), UDim2.fromOffset(w, h - top)
					end
				end
			end
			paneTabs = Components.segmented(tabsHolder, {
				{ id = "fighters", label = "Fighters" },
				{ id = "preview", label = "Preview" },
				{ id = "dossier", label = "Dossier" },
			}, pane, function(id)
				pane = id
				layout()
			end)
			body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

			-- The dossier -----------------------------------------------------------------------
			local function section(order: number, title: string): Frame
				local frame = make("Frame", { Name = "Section_" .. order, LayoutOrder = order, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = detail })
				Components.list(frame, Space.S)
				Components.text({ Text = title, Style = "overline", Color = Colors.TextMuted, LayoutOrder = 0, Wrap = true, Parent = frame })
				return frame
			end

			local renderDossier
			local renderCards
			local function abilityRow(parent: Instance, order: number, def, ability, accent: Color3)
				local row = make("Frame", {
					Name = "Ability_" .. ability.id,
					LayoutOrder = order,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Colors.PanelLight,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					Parent = parent,
				}, {
					Components.corner(Theme.SmallCorner),
					Components.stroke(Colors.Stroke, 1, 0.8),
					Components.padding(Space.S, Space.S, Space.S, 52),
				})
				local tile = Components.iconTile(Icons.forAbility(ability), 36, accent)
				tile.Position = UDim2.fromOffset(-44, 0)
				tile.Parent = row
				Components.list(row, 2)
				local kind = if ability.kind == "Ultimate" then "Ultimate" else ability.kind or "Ability"
				Components.text({ Text = `{ability.name}`, Style = "strong", LayoutOrder = 1, Wrap = true, Parent = row })
				Components.text({ Text = kind, Style = "small", Color = accent, LayoutOrder = 2, Wrap = true, Parent = row })
				local numbers = statsLine(ability, def.resource and def.resource.name)
				if numbers ~= "" then
					Components.text({ Text = numbers, Style = "number", TextSize = 16, Color = Colors.TextDim, LayoutOrder = 3, Wrap = true, Parent = row })
				end
				local abilityOwned = ability.kind == "Ultimate" or not ability.price or Powers.abilityOwned(def.id, ability.id, powerData(def.id), selectedPhase) or isOwnerAccount()
				if not abilityOwned then
					local price = ability.price
					local buy = Components.button(`Unlock (permanent): {unlockPriceText(price)}`, { Name = "UnlockAbility", Variant = "Gold", Size = UDim2.new(1, 0, 0, Theme.Size.Control), LayoutOrder = 5, Parent = row }, function()
						Shell.confirm({
							title = `Unlock {ability.name}?`,
							body = "A permanent unlock for this ability.",
							price = price,
							confirmText = "Unlock",
							onConfirm = function()
								PowerRequest:FireServer(Action.UnlockAbility, def.id, ability.id)
								task.delay(0.8, function()
									if body.Parent then
										renderDossier()
									end
								end)
							end,
						})
					end)
					if def.premium and not owns(def) then
						Components.setDisabled(buy, true, `Unlock {def.name} first`)
					elseif not canPay(price) then
						Components.setDisabled(buy, true, `Need {unlockPriceText(price)}`)
					end
				end
				if typeof(ability.description) == "string" then
					Components.text({ Text = clean(ability.description), Style = "small", Color = Colors.TextDim, LayoutOrder = 4, Wrap = true, Parent = row })
				end
			end

			function renderDossier()
				for _, child in detail:GetChildren() do
					if not child:IsA("UIListLayout") and child ~= strip then
						child:Destroy()
					end
				end
				local def = Powers.get(selectedPower)
				if not def then
					return
				end
				local accent = def.colors.primary
				local count = Powers.degreeCount(selectedPower)
				local ownsIt = owns(def)
				local order = 0
				local function nextOrder()
					order += 1
					return order
				end

				-- Title block
				local head = make("Frame", { Name = "Head", LayoutOrder = nextOrder(), Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = detail })
				Components.list(head, Space.XS)
				if def.premium then
					Components.text({ Text = if ownsIt then "Premium fighter, owned" else (if trialText(def) then `Premium fighter. {trialText(def)}` else "Premium fighter"), Style = "overline", Color = Colors.Gold, LayoutOrder = 1, Wrap = true, Parent = head })
				end
				Components.text({ Text = "WHAT THIS FIGHTER DOES", Style = "overline", Color = Colors.TextMuted, LayoutOrder = 2, Wrap = true, Parent = head })
				Components.text({ Text = `{def.name}: {def.tagline}`, Style = "heading", TextSize = 22, Color = accent:Lerp(Colors.Text, 0.35), LayoutOrder = 3, Wrap = true, Parent = head })
				Components.text({ Text = clean(def.description), Style = "body", Color = Colors.Text, LayoutOrder = 4, Wrap = true, Parent = head })
				Components.text({ Text = `Role: {def.style}`, Style = "label", Color = Colors.Text, LayoutOrder = 5, Wrap = true, Parent = head })
				difficultyRow(head, def.difficulty or 3, accent, 6)
				-- The ability strip sits right under the head (LayoutOrder 2); the sections follow it
				order = 2

				-- Premium introduction: name and title, colour theme, aura, phases
				if def.premium then
					local intro = make("Frame", {
						Name = "PremiumIntro",
						LayoutOrder = nextOrder(),
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundColor3 = accent,
						BackgroundTransparency = 0.88,
						BorderSizePixel = 0,
						Parent = detail,
					}, {
						Components.corner(Theme.SmallCorner),
						Components.stroke(Colors.Gold, 1, 0.55),
						Components.padding(Space.M),
					})
					Components.list(intro, Space.S)
					Components.text({ Text = `{def.name}: {def.tagline}`, Style = "strong", Color = Colors.Gold, LayoutOrder = 1, Wrap = true, Parent = intro })
					local theme = make("Frame", { Name = "Theme", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = intro })
					Components.list(theme, Space.XS, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
					Components.text({ Text = "Colour theme", Style = "label", Color = Colors.TextMuted, Size = UDim2.fromOffset(110, 18), LayoutOrder = 0, Parent = theme })
					swatch(theme, def.colors.primary, 1)
					swatch(theme, def.colors.secondary, 2)
					swatch(theme, def.colors.accent, 3)
					local names = {}
					for index = 1, count do
						table.insert(names, `{index} {def.degrees[index].name}`)
					end
					Components.text({ Text = `Phases: {table.concat(names, LINE)}`, Style = "small", Color = Colors.TextDim, LayoutOrder = 3, Wrap = true, Parent = intro })
					Components.text({ Text = if preview.usingStatue() then "The preview shows this fighter's statue from the Hall of the Eight." elseif preview.hasAppearance() then "Its aura plays on the figure in the preview." else "Its look is shown on the figure in the preview.", Style = "small", Color = Colors.TextDim, LayoutOrder = 4, Wrap = true, Parent = intro })
					local _, priceLabel = passPrice(def)
					local how = if ownsIt then "You own this fighter. It works in every mode."
						else `Unlock with a one-time Robux pass: {priceLabel}. Free to try in Training and CPU Practice.`
					Components.text({ Text = how, Style = "small", Color = Colors.TextDim, LayoutOrder = 5, Wrap = true, Parent = intro })
					if not ownsIt and def.premium.gems then
						local price = { gems = def.premium.gems }
						local gem = Components.button(`Unlock (permanent): {unlockPriceText(price)}`, { Name = "UnlockWithGems", Variant = "Gold", Size = UDim2.new(1, 0, 0, Theme.Size.Control), LayoutOrder = 6, Parent = intro }, function()
							Shell.confirm({
								title = `Unlock {def.name} with Gems?`,
								body = `{def.name} becomes yours in every mode. Each phase still unlocks separately.`,
								price = price,
								confirmText = "Unlock",
								onConfirm = function()
									PowerRequest:FireServer(Action.UnlockPower, def.id)
									task.delay(0.8, function()
										if body.Parent then
											renderCards()
											renderDossier()
										end
									end)
								end,
							})
						end)
						if not canPay(price) then
							Components.setDisabled(gem, true, `Need {unlockPriceText(price)}`)
						end
					end
				end

				-- Phase tabs
				local phases = section(nextOrder(), "PHASES")
				local options = {}
				for index = 1, count do
					table.insert(options, { id = tostring(index), label = `Phase {index}` })
				end
				Components.segmented(phases, options, tostring(selectedPhase), function(id)
					selectedPhase = tonumber(id) or 1
					preview.look(selectedPower, selectedPhase)
					demoIndex = 1
					rebuildStrip()
					renderDossier()
				end, { LayoutOrder = 1, Name = "PhaseTabs" })
				local degreeDef = def.degrees[selectedPhase]
				local fee = phaseFee(def, selectedPhase)
				local money = Profile.currency("money")
				local open = degreeOpen(def, selectedPhase)
				local card = make("Frame", {
					Name = "PhaseCard",
					LayoutOrder = 2,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Colors.PanelLight,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					Parent = phases,
				}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Stroke, 1, 0.8), Components.padding(Space.M) })
				Components.list(card, Space.XS)
				Components.text({ Text = `Phase {selectedPhase}: {degreeDef.name}`, Style = "strong", LayoutOrder = 1, Wrap = true, Parent = card })
				Components.text({ Text = clean(degreeDef.description), Style = "small", Color = Colors.TextDim, LayoutOrder = 2, Wrap = true, Parent = card })
				local feeLine, feeColor
				if selectedPhase == 1 then
					feeLine, feeColor = "Evolve fee (this match): none. Every match starts here.", Colors.Success
				elseif fee <= 0 then
					feeLine, feeColor = "Evolve fee (this match): free for you.", Colors.Success
				elseif money >= fee then
					feeLine, feeColor = `Evolve fee (this match): {feeText(fee)}. You have {Components.formatNumber(money)}, enough.`, Colors.Success
				else
					feeLine, feeColor = `Evolve fee (this match): {feeText(fee)}. You have {Components.formatNumber(money)}, {Components.formatNumber(fee - money)} short.`, Colors.Warning
				end
				Components.text({ Text = feeLine, Style = "label", Color = feeColor, LayoutOrder = 3, Wrap = true, Parent = card })
				if open then
					Components.text({ Text = "Unlock (permanent): unlocked.", Style = "small", Color = Colors.TextDim, LayoutOrder = 4, Wrap = true, Parent = card })
				else
					local unlock = degreeDef.unlock
					local bits = {}
					if unlock and unlock.mastery then
						table.insert(bits, `reach mastery level {unlock.mastery}`)
					end
					local price = if unlock and unlock.money then { money = unlock.money } else nil
					if price then
						table.insert(bits, `pay {unlockPriceText(price)}`)
					end
					Components.text({ Text = `Unlock (permanent): {table.concat(bits, " or ")}.`, Style = "small", Color = Colors.Warning, LayoutOrder = 4, Wrap = true, Parent = card })
					if price then
						local previousOpen = degreeOpen(def, selectedPhase - 1)
						local affordable = canPay(price)
						local lock = Components.button(`Unlock Phase {selectedPhase}: {unlockPriceText(price)}`, { Name = "UnlockPhase", Variant = "Gold", Size = UDim2.new(1, 0, 0, Theme.Size.Control), LayoutOrder = 5, Parent = card }, function()
							Shell.confirm({
								title = `Unlock Phase {selectedPhase}, {degreeDef.name}?`,
								body = `A permanent unlock of {def.name}'s Phase {selectedPhase}. It is separate from the evolve fee, which is paid in a match.`,
								price = price,
								confirmText = "Unlock",
								onConfirm = function()
									PowerRequest:FireServer(Action.UnlockDegree, def.id, selectedPhase)
									task.delay(0.8, function()
										if body.Parent then
											renderCards()
											renderDossier()
										end
									end)
								end,
							})
						end)
						if not ownsIt then
							Components.setDisabled(lock, true, `Unlock {def.name} first`)
						elseif not previousOpen then
							Components.setDisabled(lock, true, `Unlock Phase {selectedPhase - 1} first`)
						elseif not affordable then
							Components.setDisabled(lock, true, `Need {unlockPriceText(price)}`)
						end
						local note = if not ownsIt then `Unlock {def.name} first.` elseif not previousOpen then `Unlock Phase {selectedPhase - 1} first.` elseif not affordable then `You do not have enough yet: you have {Components.formatNumber(Profile.currency("money"))} Money.` else "You can afford this."
						Components.text({ Text = note, Style = "small", Color = if affordable and previousOpen and ownsIt then Colors.Success else Colors.Warning, LayoutOrder = 6, Wrap = true, Parent = card })
					end
				end
				Components.text({
					Text = "Matches start in Phase 1; evolve during the fight with T once the meter is full. A fee lasts for that match only. Training is free.",
					Style = "small",
					Color = Colors.TextMuted,
					LayoutOrder = 7,
					Wrap = true,
					Parent = card,
				})

				-- Abilities with exact numbers
				local abilities = section(nextOrder(), `ABILITIES IN PHASE {selectedPhase}`)
				local ids = Powers.available(selectedPower, selectedPhase)
				local ult = Powers.ultimateOf(selectedPower, selectedPhase)
				if ult then
					table.insert(ids, ult)
				end
				for index, abilityId in ids do
					local ability = Powers.abilityFor(selectedPower, abilityId, selectedPhase)
					if ability then
						abilityRow(abilities, index, def, ability, accent)
					end
				end

				-- Controls and slots
				local controls = section(nextOrder(), "CONTROLS AND SLOTS")
				local slots = degreeDef.slots or 3
				Components.text({ Text = `{slots} ability slots in this phase, on keys 1 to {slots}. Pick which abilities fill them in Play.`, Style = "small", Color = Colors.TextDim, LayoutOrder = 1, Wrap = true, Parent = controls })
				local keys = Components.keyRow({
					{ key = "M1", label = "Light attack" },
					{ key = "E", label = "Heavy attack" },
					{ key = "F", label = "Block" },
					{ key = "Q", label = "Dodge" },
					{ key = "T", label = "Evolve" },
					{ key = "1-" .. slots, label = "Abilities" },
				}, { LayoutOrder = 2 })
				keys.Parent = controls

				-- Actions
				for _, child in actions:GetChildren() do
					if not child:IsA("UIListLayout") then
						child:Destroy()
					end
				end
				if def.premium and not ownsIt then
					local state, priceLabel = passPrice(def)
					local onSale = state.status == "ready"
					local label = if onSale then `Unlock: {priceLabel}` else priceLabel
					local buy = Components.button(label, { Name = "Unlock", Variant = "Primary", Size = UDim2.new(0.5, -Space.XS, 1, 0), Parent = actions }, function()
						PowerRequest:FireServer(Action.PromptPass, def.id)
					end)
					if not onSale then
						Components.setDisabled(buy, true, "The price is not available right now")
					end
				end
				Components.button("Choose in Play", { Name = "ChooseInPlay", Variant = if def.premium and not ownsIt then "Secondary" else "Primary", Size = if def.premium and not ownsIt then UDim2.new(0.5, -Space.XS, 1, 0) else UDim2.fromScale(1, 1), Parent = actions }, function()
					Shell.open("Play", { fighter = selectedPower })
				end)
			end

			-- The cards -------------------------------------------------------------------------------
			function renderCards()
				for _, entry in cards do
					entry.frame:Destroy()
				end
				table.clear(cards)
				local view = Profile.get()
				local equipped = view and view.selected
				for order, powerId in fighterIds() do
					local def = Powers.get(powerId)
					if def then
						local ownsIt = owns(def)
						local chip, chipColor = "FREE", Colors.TextMuted
						local price: any, priceText: string? = nil, nil
						if typeof(equipped) == "table" and equipped.power == powerId then
							chip, chipColor = "EQUIPPED", Colors.Success
						elseif def.premium then
							chip, chipColor = if ownsIt then "OWNED" elseif trialText(def) then "TRIAL" else "PREMIUM", Colors.Gold
						end
						if def.premium and not ownsIt then
							local _, priceLabel = passPrice(def)
							priceText = trialText(def) or priceLabel
						else
							priceText = if def.premium then "Owned" else "Free"
						end
						local frame, card = Components.storeCard({
							Name = def.name,
							LayoutOrder = order,
							Subtitle = def.style,
							Icon = Icons.sigil(powerId),
							Accent = def.colors.primary,
							Chip = chip,
							ChipColor = chipColor,
							Price = price,
							PriceText = priceText,
							Gradient = { def.colors.primary, def.colors.secondary },
							Premium = def.premium ~= nil,
							Locked = def.premium ~= nil and not ownsIt and trialText(def) == nil,
							Selected = powerId == selectedPower,
							Size = UDim2.new(1, -4, 0, 116),
							Width = LEFT_WIDTH - 12,
							onClick = function()
								selectedPower = powerId
								selectedPhase = 1
								demoIndex = 1
								for id, entry in cards do
									entry.card.setSelected(id == powerId)
								end
								preview.look(powerId, 1)
								showFighter(def)
								renderDossier()
								if (pcall(function() return body.AbsoluteSize.X end) and body.AbsoluteSize.X or NARROW_BELOW) < NARROW_BELOW then
									pane = "preview"
									paneTabs.set("preview", false)
									layout()
								end
							end,
						})
						frame.Name = "Card_" .. powerId
						frame.Parent = list
						cards[powerId] = { frame = frame, card = card }
					end
				end
			end

			local function refreshAll()
				renderCards()
				preview.look(selectedPower, selectedPhase)
				local selectedDef = Powers.get(selectedPower)
				if selectedDef then
					showFighter(selectedDef)
				end
				renderDossier()
				layout()
			end
			onPriceChange = function()
				if body.Parent then
					renderCards()
					renderDossier()
				end
			end
			local profileLink = Profile.changed:Connect(function()
				if body.Parent and Shell.isOpen("Powers") then
					renderCards()
					renderDossier()
				end
			end)
			refreshAll()
			body.Destroying:Connect(function()
				profileLink:Disconnect()
			end)
			body.Destroying:Connect(preview.stop)
			body.Destroying:Connect(plan.stop)

			return {
				onOpen = function(args)
					if typeof(args) == "table" and typeof(args.power) == "string" and Powers.get(args.power) and (Powers.isReleased(args.power) or isOwnerAccount()) then
						selectedPower = args.power
						selectedPhase = 1
					end
					PowerRequest:FireServer(Action.State)
					refreshAll()
				end,
				onClose = function() end,
				focus = function()
					return cards[selectedPower] and cards[selectedPower].frame
				end,
			}
		end,
	})
end

return PowersWindow
