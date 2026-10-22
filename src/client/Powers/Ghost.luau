-- How the Ghost looks: ink-black mist, pale white light and a faint cyan
-- edge. A katana built from parts (handle, guard, curved blade) sits in his
-- right hand whenever he's attacking and fades away a few seconds after
-- (the server's Phase attribute, plus an instant local draw when he swings),
-- white slash trails that show exactly where each cut reaches, dark
-- afterimages on every dash, teleport and dodge, the grid and Spectral Severance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Ghost = {}

local rgb = Color3.fromRGB
local INK = rgb(12, 12, 18)
local SHADE = rgb(48, 50, 64)
local PALE = rgb(235, 242, 255)
local CYAN = rgb(140, 230, 255)
local STEEL = rgb(205, 214, 228)
local WRAP = rgb(26, 24, 34)
local GUARD_METAL = rgb(58, 60, 74)

local PHASE = Protocol.Attribute.Phase
local CONCEALED = Protocol.Attribute.StatusPrefix .. "Concealed"
-- Set on this client only: the katana was drawn here before the server said so
local LOCAL_DRAW = "SNGhostDrawnLocal"
-- Katana abilities show the blade the instant they're pressed
local KATANA_ABILITIES = {
	InstantDraw = true,
	SpectralCounter = true,
	SlashWave = true,
	SlashFlurry = true,
	FollowThrough = true,
	ConvergingGrid = true,
	SpectralSeverance = true,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function vec(value: any): Vector3?
	return if typeof(value) == "Vector3" then value else nil
end

local function num(value: any, fallback: number): number
	return if typeof(value) == "number" and value == value then value else fallback
end

local function sheatheAfter(kit): number
	local katana = kit.def and kit.def.katana
	return if katana then katana.sheatheAfter else 3
end

-- Shows the blade on this client right away (the server's Phase follows)
local function markDrawn(kit)
	if kit.model then
		kit.model:SetAttribute(LOCAL_DRAW, now() + sheatheAfter(kit))
	end
end

-- Poses -------------------------------------------------------------------------------

local Poser = require(script.Parent.Parent.Effects.Poser)
-- Iaido: hand on the hilt at the hip, body turned away
Poser.register("GhostIaido", { RightShoulder = { 20, 0, 35 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 30, 0, -20 }, LeftElbow = { 60, 0, 0 }, Torso = { 12, -30, 0 }, RightHip = { 25, 0, 0 } })
-- The draw-cut's follow-through, blade swept across
Poser.register("GhostCut", { RightShoulder = { 95, 0, -75 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -20, 0, 20 }, Torso = { 0, 45, 0 } })
Poser.register("GhostDash", { Torso = { 30, 0, 0 }, RightShoulder = { -50, 0, 25 }, LeftShoulder = { -50, 0, -25 }, Neck = { -20, 0, 0 } })
Poser.register("GhostVeil", { Torso = { 14, 0, 0 }, RightShoulder = { 40, 0, 50 }, LeftShoulder = { 40, 0, -50 }, Neck = { 20, 0, 0 } })
Poser.register("GhostCounter", { RightShoulder = { 15, 0, 25 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 70, 0, -10 }, LeftElbow = { 40, 0, 0 }, Torso = { 0, -20, 0 } })

local FLURRY_POSES = { "SlashLeft", "SlashRight", "SlashUp", "SlashDown", "SlashLeft" }

local function pose(kit, name: string, inTime: number, hold: number, outTime: number)
	if kit.model then
		kit.Poser.play(kit.model, name, inTime, hold, outTime)
	end
end

-- Shapes -------------------------------------------------------------------------------

local function chest(kit): CFrame?
	return if kit.root then kit.root.CFrame * CFrame.new(0, 0.6, 0) else nil
end

local function groundUnder(kit): Vector3
	return if kit.root then kit.root.Position - Vector3.new(0, 2.9, 0) else Vector3.zero
end

-- A solid-looking arc of light: the exact reach of a cut (radius, spread in
-- degrees, tilt 0 = flat, 90 = vertical), fading over `duration`
local function arcTrail(kit, origin: CFrame, radius: number, spread: number, tilt: number, color: Color3, thickness: number, duration: number)
	local segments = if kit.Vfx.reduced() then 6 else 12
	local frame = origin * CFrame.Angles(0, 0, math.rad(tilt))
	local spreadRad = math.rad(spread)
	for index = 0, segments - 1 do
		local angle = -spreadRad / 2 + spreadRad * (index + 0.5) / segments
		local length = radius * spreadRad / segments * 1.15
		-- Thickest in the middle of the cut, tapering at both ends
		local taper = 1 - math.abs(angle) / math.max(spreadRad, 1e-3)
		local piece = kit.Vfx.part({
			Size = Vector3.new(length, thickness * (0.35 + taper), thickness * 0.6),
			CFrame = frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius),
			Color = color,
			Transparency = 0.05,
		})
		kit.Vfx.fade(piece, duration, { Transparency = 1, Size = Vector3.new(length * 1.15, 0.03, 0.03) })
	end
end

-- Ink smoke at a point (vanishing, arriving, the veil)
local function inkSmoke(kit, position: Vector3, count: number, spread: number)
	kit.Vfx.burst(position, {
		colors = ColorSequence.new(INK, SHADE),
		lightEmission = 0,
		texture = "rbxasset://textures/particles/smoke_main.dds",
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) }),
		transparency = NumberSequence.new(0.25, 1),
		lifetime = NumberRange.new(0.5, 0.9),
		speed = NumberRange.new(spread * 0.6, spread * 1.4),
		spread = Vector2.new(180, 180),
		drag = 5,
		acceleration = Vector3.new(0, 3, 0),
		count = count,
	})
end

-- Pale wisps rising (spirit energy)
local function wisps(kit, position: Vector3, count: number)
	kit.Vfx.burst(position, {
		colors = ColorSequence.new(PALE, CYAN),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		transparency = NumberSequence.new(0.1, 1),
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(3, 8),
		spread = Vector2.new(60, 60),
		acceleration = Vector3.new(0, 6, 0),
		count = count,
	})
end

local function afterimage(kit, cframe: CFrame?, color: Color3, duration: number)
	if kit.model then
		kit.Vfx.ghostAt(kit.model, cframe, color, duration, Enum.Material.ForceField)
	end
end

-- A streak of shadow and light between two points (teleports, dashes)
local function streak(kit, from: Vector3, to: Vector3)
	kit.Vfx.beam(from, to, INK, 0.5, 0.25, Enum.Material.SmoothPlastic)
	kit.Vfx.beam(from, to, PALE, 0.12, 0.2)
end

local function modelOf(value: any): Model?
	return if typeof(value) == "Instance" and value:IsA("Model") then value else nil
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Wind-ups (the local player's own presses are shown instantly) --------------------------

Ghost.predict = {
	InstantDraw = function(kit)
		markDrawn(kit)
		pose(kit, "GhostIaido", 0.05, math.max(0.05, kit.data.startup), 0.05)
	end,
	SpectralDash = function(kit)
		pose(kit, "GhostDash", 0.04, 0.25, 0.15)
	end,
	PhantomVeil = function(kit)
		pose(kit, "GhostVeil", 0.06, 0.15, 0.2)
	end,
	SpectralCounter = function(kit)
		markDrawn(kit)
		pose(kit, "GhostCounter", 0.04, 0.4, 0.15)
	end,
	ShadowStep = function(kit)
		pose(kit, "GhostVeil", 0.05, 0.15, 0.15)
	end,
	SlashWave = function(kit)
		markDrawn(kit)
		pose(kit, "SlashRight", 0.08, math.max(0.05, kit.data.startup - 0.08), 0.05)
	end,
	SlashFlurry = function(kit)
		markDrawn(kit)
		pose(kit, "GhostIaido", 0.05, math.max(0.05, kit.data.startup), 0.05)
	end,
	FollowThrough = function(kit)
		markDrawn(kit)
		pose(kit, "GhostDash", 0.03, 0.3, 0.15)
	end,
	ConvergingGrid = function(kit)
		markDrawn(kit)
		pose(kit, "Raise", 0.12, math.max(0.1, kit.data.startup - 0.12), 0.1)
	end,
	SpectralSeverance = function(kit)
		markDrawn(kit)
		pose(kit, "GhostIaido", 0.15, math.max(0.1, kit.data.startup), 0.05)
	end,
}

-- Any cast: katana moves show the blade at once (the effects below do the rest)
function Ghost.onCast(kit)
	if KATANA_ABILITIES[kit.data.ability] then
		markDrawn(kit)
	end
end

local fx = {}
Ghost.fx = fx

-- Phantom Veil -------------------------------------------------------------------------

function fx.VeilWindup(kit)
	pose(kit, "GhostVeil", 0.06, num(kit.data.duration, 0.1) + 0.1, 0.2)
	if kit.root then
		inkSmoke(kit, kit.root.Position - Vector3.new(0, 1.5, 0), 8, 4)
	end
end

function fx.Veil(kit)
	local root = kit.root
	if not root then
		return
	end
	inkSmoke(kit, root.Position, 18, 7)
	wisps(kit, root.Position, 10)
	kit.Vfx.groundRing(groundUnder(kit) + Vector3.new(0, 0.1, 0), SHADE, 2, 12, 0.5)
	afterimage(kit, nil, INK, 0.6)
	kit.Vfx.sound("Dodge", root)
end

function fx.VeilBreak(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	kit.Vfx.flash(model, PALE, 0.25)
	wisps(kit, root.Position, 8)
end

-- Movement ---------------------------------------------------------------------------------

function fx.SpectralDash(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	local duration = num(kit.data.duration, 0.3)
	pose(kit, "GhostDash", 0.04, duration, 0.15)
	kit.Vfx.sound("Dodge", root)
	local running = true
	kit.keep(function()
		running = false
	end)
	-- A trail of dark afterimages (bounded: one every 0.04s for the dash)
	task.spawn(function()
		local started = os.clock()
		local index = 0
		while running and root.Parent and os.clock() - started < duration + 0.05 do
			index += 1
			afterimage(kit, nil, if index % 3 == 0 then PALE else INK, 0.35)
			task.wait(0.04)
		end
		if root.Parent then
			inkSmoke(kit, root.Position, 6, 3)
		end
	end)
end

function fx.PhaseDodge(kit)
	local root = kit.root
	if not root then
		return
	end
	afterimage(kit, nil, INK, 0.45)
	inkSmoke(kit, root.Position, 6, 3)
end

-- Instant Draw -----------------------------------------------------------------------------

function fx.InstantDrawWindup(kit)
	markDrawn(kit)
	local duration = num(kit.data.duration, 0.12)
	pose(kit, "GhostIaido", 0.04, duration, 0.04)
	local root = kit.root
	if root then
		-- A glint at the guard: the only tell before the cut
		kit.Vfx.orb(root.Position + root.CFrame.RightVector * 0.9 - Vector3.new(0, 0.4, 0), PALE, 0.3, 1.6, duration + 0.05)
		kit.Vfx.sound("Parry", root)
	end
end

function fx.InstantDraw(kit)
	local origin, direction = vec(kit.data.origin), vec(kit.data.direction)
	if not origin or not direction or direction.Magnitude < 0.01 then
		return
	end
	local range = num(kit.data.range, 10)
	pose(kit, "GhostCut", 0.03, 0.18, 0.25)
	local height = Vector3.new(0, 0.6, 0)
	local reach = origin + height + direction.Unit * range
	-- One straight, blinding cut along its exact reach
	kit.Vfx.beam(origin + height + direction.Unit, reach, PALE, 0.28, 0.22)
	kit.Vfx.beam(origin + height + direction.Unit, reach, CYAN, 0.08, 0.3)
	arcTrail(kit, CFrame.lookAt(origin + height, origin + height + direction), range * 0.55, 70, 8, PALE, 0.3, 0.2)
	kit.Vfx.glow(reach, PALE, 14, 3, 0.25)
	kit.Vfx.sound("HeavySwing", origin)
	if kit.data.landed then
		kit.Vfx.sparks(origin + height + direction.Unit * (range * 0.6), PALE, 20, 30)
	end
	if kit.data.ambush then
		kit.Vfx.popup(origin + height + direction.Unit * 3, "AMBUSH!", CYAN, 1.1)
	end
	kit.shake(0.8, 0.12, origin)
end

-- Spectral Counter ---------------------------------------------------------------------------

function fx.CounterStance(kit)
	local model, root = kit.model, kit.root
	if not model or not root then
		return
	end
	markDrawn(kit)
	local duration = num(kit.data.duration, 0.43)
	pose(kit, "GhostCounter", 0.04, duration, 0.15)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = INK
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = PALE
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = workspace.CurrentCamera
	kit.Vfx.ring(CFrame.new(groundUnder(kit) + Vector3.new(0, 0.15, 0)) * CFrame.Angles(math.rad(90), 0, 0), 2.5, CYAN, 0.12, duration, 4.5)
	kit.keep(function()
		highlight:Destroy()
	end)
end

function fx.CounterWhiff(kit)
	if kit.root then
		inkSmoke(kit, kit.root.Position, 4, 2)
	end
end

function fx.CounterStrike(kit)
	local from, to = vec(kit.data.from), vec(kit.data.to)
	if not from or not to then
		return
	end
	local direction = vec(kit.data.direction) or Vector3.new(0, 0, -1)
	-- Where he was is left as an afterimage; he is already behind them
	if kit.root then
		afterimage(kit, CFrame.new(from) * kit.root.CFrame.Rotation, INK, 0.5)
	end
	streak(kit, from, to)
	pose(kit, "SlashLeft", 0.03, 0.2, 0.25)
	local frame = CFrame.lookAt(to + Vector3.new(0, 0.6, 0), to + Vector3.new(0, 0.6, 0) + direction)
	arcTrail(kit, frame, 4.5, 120, -20, PALE, 0.35, 0.25)
	arcTrail(kit, frame, 4.2, 100, 25, CYAN, 0.15, 0.3)
	local target = rootOf(modelOf(kit.data.target))
	if target then
		kit.Vfx.sparks(target.Position, PALE, 24, 30)
	end
	kit.Vfx.sound("Parry", to)
	kit.shake(1.2, 0.18, to)
end

function fx.CounterEvade(kit)
	local from, to = vec(kit.data.from), vec(kit.data.to)
	if not from or not to then
		return
	end
	if kit.root then
		afterimage(kit, CFrame.new(from) * kit.root.CFrame.Rotation, INK, 0.5)
	end
	inkSmoke(kit, to, 8, 3)
	kit.Vfx.popup(to + Vector3.new(0, 1.5, 0), "PHASED", CYAN, 1)
end

-- Shadow Step ---------------------------------------------------------------------------------

function fx.ShadowStepMark(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local duration = num(kit.data.duration, 0.15)
	pose(kit, "GhostVeil", 0.05, duration, 0.15)
	-- A pool of shadow where he'll appear: the tell for whoever is standing there
	local pool = kit.Vfx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 1, 1),
		CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = INK,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
	})
	kit.Vfx.fade(pool, duration + 0.35, { Size = Vector3.new(0.12, 6, 6), Transparency = 1 })
	inkSmoke(kit, position + Vector3.new(0, 0.5, 0), 6, 2)
	if kit.root then
		inkSmoke(kit, kit.root.Position, 8, 3)
	end
end

function fx.ShadowStep(kit)
	local from, to = vec(kit.data.from), vec(kit.data.to)
	if not from or not to then
		return
	end
	if kit.root then
		afterimage(kit, CFrame.new(from) * kit.root.CFrame.Rotation, INK, 0.45)
	end
	inkSmoke(kit, from, 12, 5)
	streak(kit, from, to)
	inkSmoke(kit, to, 14, 6)
	wisps(kit, to, 8)
	kit.Vfx.groundRing(to - Vector3.new(0, 2.8, 0), PALE, 1, 9, 0.35)
	kit.Vfx.sound("Dodge", to)
end

function fx.ShadowStepFail(kit)
	local position = vec(kit.data.position)
	if position then
		inkSmoke(kit, position, 6, 2)
		kit.Vfx.popup(position + Vector3.new(0, 1.5, 0), "BLOCKED", SHADE, 0.9)
	end
end

function fx.ShadowSlash(kit)
	local position = vec(kit.data.position)
	if not position then
		return
	end
	local radius = num(kit.data.radius, 6)
	pose(kit, "SlashLeft", 0.03, 0.15, 0.2)
	-- A full circle of cuts around the landing spot (its exact radius)
	for turn = 0, 2 do
		local frame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.rad(turn * 120), 0)
		arcTrail(kit, frame, radius, 120, turn * 6, PALE, 0.3, 0.25)
	end
	kit.Vfx.sound("LightSwing", position)
end

-- Slash Wave ----------------------------------------------------------------------------------

function fx.SlashWaveWindup(kit)
	markDrawn(kit)
	local duration = num(kit.data.duration, 0.2)
	pose(kit, "SlashRight", 0.08, math.max(0.04, duration - 0.08), 0.05)
	if kit.root then
		kit.Vfx.glow(kit.root, CYAN, 10, 2, duration + 0.1)
	end
end

function fx.SlashWaveRelease(kit)
	pose(kit, "SlashLeft", 0.04, 0.18, 0.25)
	if kit.root then
		kit.Vfx.sound("HeavySwing", kit.root)
	end
end

Ghost.projectiles = {}

-- A white crescent of energy flying with its arc forward and a ribbon trail
-- that leaves its path visible behind it
function Ghost.projectiles.SlashWave(kit)
	local reduced = kit.Vfx.reduced()
	local halfWidth = num(kit.data.width, 4.3) / 2
	local radius = halfWidth / math.sin(math.rad(70))
	local tilt = math.rad(num(kit.data.tilt, 0))
	local count = if reduced then 5 else 9
	local pieces = {}
	for index = 1, count do
		local angle = math.rad(-70 + 140 * (index - 0.5) / count)
		local taper = 1 - math.abs(angle) / math.rad(70)
		local length = radius * math.rad(140) / count * 1.2
		local core = kit.Vfx.part({
			Size = Vector3.new(length, 0.12 + 0.3 * taper, 0.12 + 0.3 * taper),
			Color = PALE,
			Transparency = 0.02,
		})
		table.insert(pieces, { part = core, angle = angle, back = 0 })
		if not reduced and index % 2 == 1 then
			local glow = kit.Vfx.part({
				Size = Vector3.new(length * 1.1, 0.06, 0.5 + 0.4 * taper),
				Color = CYAN,
				Material = Enum.Material.ForceField,
				Transparency = 0.2,
			})
			table.insert(pieces, { part = glow, angle = angle, back = 0.25 })
		end
	end
	local middle = pieces[math.ceil(#pieces / 2)].part
	local light = Instance.new("PointLight")
	light.Color = PALE
	light.Range = 12
	light.Brightness = 2
	light.Parent = middle
	-- The trail between the crescent's tips
	local first, last = pieces[1].part, pieces[#pieces].part
	local tipA = Instance.new("Attachment")
	tipA.Parent = first
	local tipB = Instance.new("Attachment")
	tipB.Parent = last
	local trail = Instance.new("Trail")
	trail.Attachment0 = tipA
	trail.Attachment1 = tipB
	trail.Color = ColorSequence.new(PALE, CYAN)
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.LightEmission = 1
	trail.Lifetime = if reduced then 0.15 else 0.3
	trail.Parent = first

	return {
		update = function(position: Vector3, velocity: Vector3)
			local forward = if velocity.Magnitude > 0.1 then velocity.Unit else Vector3.new(0, 0, -1)
			local frame = CFrame.lookAt(position, position + forward) * CFrame.Angles(0, 0, tilt) * CFrame.new(0, 0, radius * 0.7)
			for _, piece in pieces do
				piece.part.CFrame = frame * CFrame.Angles(0, piece.angle, 0) * CFrame.new(0, 0, -radius + piece.back)
			end
		end,
		finish = function(position: Vector3, reason: string)
			for _, piece in pieces do
				piece.part:Destroy()
			end
			if reason == "Destroyed" then
				return
			end
			kit.Vfx.sparks(position, PALE, if reason == "Intercepted" then 26 else 16, 28)
			kit.Vfx.slash(CFrame.new(position), PALE, 2.5, math.deg(tilt), 0.2)
			kit.Vfx.shockwave(position, CYAN, 1, halfWidth * 2.2, 0.25)
			kit.Vfx.sound("Hit", position)
		end,
	}
end

-- Slash Flurry ----------------------------------------------------------------------------------

function fx.FlurryWindup(kit)
	markDrawn(kit)
	pose(kit, "GhostIaido", 0.04, num(kit.data.duration, 0.15), 0.03)
end

function fx.FlurrySweep(kit)
	local origin = chest(kit)
	if not origin then
		return
	end
	local index = math.floor(num(kit.data.index, 1))
	local range = num(kit.data.range, 8)
	local arc = num(kit.data.arc, 120)
	local tilt = num(kit.data.tilt, 0)
	pose(kit, FLURRY_POSES[(index - 1) % #FLURRY_POSES + 1], 0.03, 0.06, 0.1)
	-- The white arc is the cut's real reach and angle; the cyan echo is only a trail
	arcTrail(kit, origin, range, arc, tilt, PALE, 0.32, 0.22)
	arcTrail(kit, origin * CFrame.Angles(0, 0, math.rad(4)), range * 0.9, arc * 0.9, tilt, CYAN, 0.12, 0.32)
	kit.Vfx.sound("LightSwing", origin.Position)
	if kit.data.final then
		kit.Vfx.glow(origin.Position + origin.LookVector * 3, PALE, 12, 2, 0.25)
		kit.shake(0.7, 0.12, origin.Position)
	end
end

-- Follow Through ------------------------------------------------------------------------------

function fx.FollowWindup(kit)
	markDrawn(kit)
	pose(kit, "GhostDash", 0.03, num(kit.data.duration, 0.05) + 0.3, 0.15)
end

function fx.FollowDash(kit)
	local from, direction = vec(kit.data.from), vec(kit.data.direction)
	local root = kit.root
	if not from or not direction or not root then
		return
	end
	local distance = num(kit.data.distance, 10)
	local duration = num(kit.data.duration, 0.2)
	streak(kit, from, from + direction * distance)
	local running = true
	kit.keep(function()
		running = false
	end)
	task.spawn(function()
		local started = os.clock()
		while running and root.Parent and os.clock() - started < duration + 0.05 do
			afterimage(kit, nil, INK, 0.3)
			task.wait(0.04)
		end
	end)
	kit.Vfx.sound("Dodge", root)
end

function fx.FollowStrike(kit)
	local position, direction = vec(kit.data.position), vec(kit.data.direction)
	if not position or not direction then
		return
	end
	pose(kit, "GhostCut", 0.03, 0.15, 0.25)
	local frame = CFrame.lookAt(position + Vector3.new(0, 0.6, 0), position + Vector3.new(0, 0.6, 0) + direction)
	-- An X of two cuts
	arcTrail(kit, frame * CFrame.new(0, 0, 2), 3.5, 110, 45, PALE, 0.32, 0.25)
	arcTrail(kit, frame * CFrame.new(0, 0, 2), 3.5, 110, -45, PALE, 0.32, 0.25)
	kit.Vfx.sparks(position, PALE, 20, 26)
	kit.Vfx.sound("HeavySwing", position)
	kit.shake(1, 0.15, position)
end

-- Converging Grid --------------------------------------------------------------------------------

-- The grid's slash lines: pairs of parallel lines from `lines / 2` angles,
-- spread across the circle so they cross into a lattice over its middle
local function gridLines(center: Vector3, radius: number, lines: number, yaw: number): { { Vector3 } }
	local list = {}
	local orientations = math.max(2, math.floor(lines / 2))
	for index = 0, lines - 1 do
		local orientation = index % orientations
		local side = if index < orientations then -1 else 1
		local angle = yaw + math.pi * orientation / orientations
		local along = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local across = Vector3.new(along.Z, 0, -along.X)
		local offset = across * side * radius * 0.35
		local reach = radius * 1.35
		table.insert(list, { center + offset - along * reach, center + offset + along * reach })
	end
	return list
end

function fx.GridMark(kit)
	local center = vec(kit.data.center)
	if not center then
		return
	end
	local radius = num(kit.data.radius, 8)
	local duration = num(kit.data.duration, 0.8)
	local lines = math.clamp(math.floor(num(kit.data.lines, 6)), 2, 12)
	markDrawn(kit)
	pose(kit, "Raise", 0.12, math.max(0.1, duration - 0.12), 0.1)
	local lift = Vector3.new(0, 0.12, 0)
	-- The exact edge of the area, and faint previews of where every slash will run
	kit.Vfx.ring(CFrame.new(center + lift) * CFrame.Angles(math.rad(90), 0, 0), radius, PALE, 0.18, duration + 0.1)
	local disc = kit.Vfx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = INK,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.55,
	})
	kit.Vfx.fade(disc, duration + 0.3, { Transparency = 1 })
	for _, line in gridLines(center + lift, radius, lines, num(kit.data.yaw, 0)) do
		local preview = kit.Vfx.beam(line[1], line[2], PALE, 0.06, duration + 0.1)
		if preview then
			preview.Transparency = 0.5
		end
	end
	if kit.root then
		kit.Vfx.telegraph(kit.root, PALE, duration)
	end
	kit.Vfx.sound("Parry", center)
end

function fx.GridStrike(kit)
	local center = vec(kit.data.center)
	if not center then
		return
	end
	local radius = num(kit.data.radius, 8)
	local lines = math.clamp(math.floor(num(kit.data.lines, 6)), 2, 12)
	local height = Vector3.new(0, 1.2, 0)
	for _, line in gridLines(center + height, radius, lines, num(kit.data.yaw, 0)) do
		kit.Vfx.beam(line[1], line[2], PALE, 0.35, 0.35)
		kit.Vfx.beam(line[1], line[2], CYAN, 0.1, 0.45)
	end
	kit.Vfx.orb(center + height, PALE, 1, radius * 1.2, 0.3)
	kit.Vfx.groundRing(center + Vector3.new(0, 0.1, 0), PALE, radius * 2, radius * 2.4, 0.4)
	kit.Vfx.sparks(center + height, PALE, 30, 34)
	kit.Vfx.sound("HeavySwing", center)
	kit.shake(1.6, 0.25, center)
end

function fx.GridFizzle(kit)
	local center = vec(kit.data.center)
	if center then
		inkSmoke(kit, center + Vector3.new(0, 1, 0), 8, 3)
	end
end

-- Spectral Severance -------------------------------------------------------------------------------

function fx.SeveranceWindup(kit)
	local model, root = kit.model, kit.root
	local anchor = vec(kit.data.anchor)
	if not model or not root or not anchor then
		return
	end
	markDrawn(kit)
	local duration = num(kit.data.duration, 0.8)
	local passes = math.clamp(math.floor(num(kit.data.passes, 2)), 1, 6)
	pose(kit, "GhostIaido", 0.15, duration, 0.05)
	kit.Vfx.telegraph(root, PALE, duration)
	-- Afterimages gather around the target, one for every cut to come
	local count = passes * 2
	for index = 1, count do
		local angle = math.pi * 2 * index / count
		local spot = anchor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 7
		afterimage(kit, CFrame.lookAt(spot, Vector3.new(anchor.X, spot.Y, anchor.Z)), if index % 2 == 0 then PALE else INK, duration + 0.4)
	end
	local pool = kit.Vfx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 4, 4),
		CFrame = CFrame.new(anchor - Vector3.new(0, 2.85, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = INK,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.2,
	})
	kit.Vfx.fade(pool, duration + 0.6, { Size = Vector3.new(0.1, 16, 16), Transparency = 1 })
	kit.Vfx.glow(root, CYAN, 18, 3, duration)
	kit.shake(0.5, duration, root.Position)
end

function fx.SeverancePass(kit)
	local from, to = vec(kit.data.from), vec(kit.data.to)
	if not from or not to or (to - from).Magnitude < 0.1 then
		return
	end
	afterimage(kit, CFrame.lookAt(from, to), INK, 0.4)
	kit.Vfx.beam(from + Vector3.new(0, 0.6, 0), to + Vector3.new(0, 0.6, 0), PALE, 0.3, 0.3)
	kit.Vfx.beam(from + Vector3.new(0, 0.6, 0), to + Vector3.new(0, 0.6, 0), INK, 0.6, 0.2, Enum.Material.SmoothPlastic)
	kit.Vfx.sparks((from + to) / 2, PALE, 12, 26)
	kit.Vfx.sound("LightSwing", (from + to) / 2)
end

function fx.SeveranceStrike(kit)
	local from, to, direction = vec(kit.data.from), vec(kit.data.to), vec(kit.data.direction)
	if not from or not to or not direction then
		return
	end
	local range = num(kit.data.range, 7)
	if kit.root then
		afterimage(kit, CFrame.new(from) * kit.root.CFrame.Rotation, PALE, 0.6)
	end
	if (to - from).Magnitude > 0.5 then
		streak(kit, from, to)
	end
	pose(kit, "GhostCut", 0.03, 0.4, 0.4)
	local frame = CFrame.lookAt(to + Vector3.new(0, 0.6, 0), to + Vector3.new(0, 0.6, 0) + direction)
	arcTrail(kit, frame, range, 140, 20, PALE, 0.5, 0.45)
	arcTrail(kit, frame, range * 0.95, 130, -20, PALE, 0.4, 0.45)
	arcTrail(kit, frame, range * 0.85, 120, 0, CYAN, 0.2, 0.55)
	kit.Vfx.glow(to + direction * 3, PALE, 30, 5, 0.5)
	kit.Vfx.shockwave(to + direction * 3, PALE, 2, range * 2.4, 0.4)
	kit.Vfx.screenFlash(PALE, 0.4, 0.35)
	kit.Vfx.sound("HeavySwing", to)
	kit.Vfx.sound("Parry", to)
	kit.shake(3, 0.4, to)
end

function fx.SeveranceFizzle(kit)
	if kit.root then
		inkSmoke(kit, kit.root.Position, 10, 4)
	end
end

-- Persistent look -------------------------------------------------------------------------------------

local HAND_NAMES = { "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm" }

local function findPart(model: Model, names: { string }): BasePart?
	for _, name in names do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- Katana pieces in grip space: the fist closes at the origin, the blade runs
-- along -Z (forward when the arm hangs, upright in a raised swing) with a
-- slight curve toward the spine
local KATANA = {
	{ name = "Tsuka", size = Vector3.new(0.2, 0.22, 1.15), at = CFrame.new(0, 0, 0.12), color = WRAP, material = Enum.Material.Fabric },
	{ name = "Kashira", size = Vector3.new(0.24, 0.26, 0.1), at = CFrame.new(0, 0, 0.72), color = GUARD_METAL, material = Enum.Material.Metal },
	{ name = "Tsuba", size = Vector3.new(0.08, 0.62, 0.62), at = CFrame.new(0, 0, -0.48) * CFrame.Angles(0, math.rad(90), 0), color = GUARD_METAL, material = Enum.Material.Metal, cylinder = true },
	{ name = "Habaki", size = Vector3.new(0.1, 0.28, 0.14), at = CFrame.new(0, 0, -0.6), color = rgb(180, 170, 140), material = Enum.Material.Metal },
	{ name = "Blade", size = Vector3.new(0.06, 0.24, 2.1), at = CFrame.new(0, 0, -1.72), color = STEEL, material = Enum.Material.Metal, blade = true },
	{ name = "Edge", size = Vector3.new(0.07, 0.05, 2.1), at = CFrame.new(0, -0.1, -1.72), color = CYAN, material = Enum.Material.Neon, edge = true },
	{ name = "BladeTip", size = Vector3.new(0.06, 0.2, 1.2), at = CFrame.new(0, 0, -2.77) * CFrame.Angles(math.rad(5), 0, 0) * CFrame.new(0, 0, -0.6), color = STEEL, material = Enum.Material.Metal, blade = true },
	{ name = "EdgeTip", size = Vector3.new(0.07, 0.05, 1.2), at = CFrame.new(0, 0, -2.77) * CFrame.Angles(math.rad(5), 0, 0) * CFrame.new(0, -0.08, -0.6), color = CYAN, material = Enum.Material.Neon, edge = true },
	{ name = "Kissaki", size = Vector3.new(0.05, 0.12, 0.3), at = CFrame.new(0, 0, -2.77) * CFrame.Angles(math.rad(5), 0, 0) * CFrame.new(0, 0.03, -1.32) * CFrame.Angles(math.rad(14), 0, 0), color = STEEL, material = Enum.Material.Metal, blade = true },
}

type Katana = {
	parts: { { part: BasePart, base: number } },
	trail: Trail,
	light: PointLight,
	blade: BasePart,
}

local function buildKatana(model: Model, container: Instance, degree: number): Katana?
	local hand = findPart(model, HAND_NAMES)
	if not hand then
		return nil
	end
	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local grip = if gripAttachment and gripAttachment:IsA("Attachment")
		then CFrame.new(gripAttachment.Position)
		else CFrame.new(0, -hand.Size.Y / 2 + 0.1, 0)
	local katana = { parts = {} } :: any
	for _, spec in KATANA do
		local part = Instance.new("Part")
		part.Name = "SNGhostKatana" .. spec.name
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		if spec.cylinder then
			part.Shape = Enum.PartType.Cylinder
		end
		part.Size = spec.size
		part.Color = spec.color
		-- At the apex the whole blade is spectral light
		part.Material = if spec.blade and degree >= 3 then Enum.Material.Neon else spec.material
		if spec.blade and degree >= 3 then
			part.Color = PALE
		end
		local offset = grip * spec.at
		part.CFrame = hand.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0 = hand
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part
		part.Transparency = 1
		part.Parent = container
		table.insert(katana.parts, { part = part, base = if spec.edge then 0.1 else 0 })
		if spec.name == "Blade" then
			katana.blade = part
		end
	end
	local blade = katana.blade :: BasePart
	-- White slash trail along the blade while it's drawn
	local base = Instance.new("Attachment")
	base.Position = Vector3.new(0, 0, 1)
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Position = Vector3.new(0, 0.1, -2.3)
	tip.Parent = blade
	local trail = Instance.new("Trail")
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Color = ColorSequence.new(PALE, CYAN)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission = 1
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = blade
	katana.trail = trail
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = if degree >= 3 then 7 else 4
	light.Brightness = if degree >= 2 then 1 else 0.5
	light.Shadows = false
	light.Enabled = false
	light.Parent = blade
	katana.light = light
	return katana
end

-- A soft emitter on the torso (dark mist at every degree, white wisps at the apex)
local function aura(kit, torso: BasePart, created: { Instance }, color: ColorSequence, rate: number, glowing: boolean)
	local attachment = Instance.new("Attachment")
	attachment.Name = "SNGhostAura"
	attachment.Parent = torso
	table.insert(created, attachment)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = color
	emitter.LightEmission = if glowing then 1 else 0
	emitter.LightInfluence = if glowing then 0 else 1
	if not glowing then
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	end
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if glowing then 0.25 else 0.8), NumberSequenceKeypoint.new(1, if glowing then 0 else 1.8) })
	emitter.Transparency = NumberSequence.new(if glowing then 0.3 else 0.65, 1)
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(0.4, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Rate = if kit.Vfx.reduced() then math.max(1, math.floor(rate / 3)) else rate
	emitter.Parent = attachment
	return emitter
end

-- Two faint cyan eye points (Shadow Step and up)
local function eyes(head: BasePart, container: Instance)
	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "SNGhostEye"
		eye.Size = Vector3.new(0.14, 0.06, 0.05)
		eye.Material = Enum.Material.Neon
		eye.Color = CYAN
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.CastShadow = false
		eye.Massless = true
		local offset = CFrame.new(side * math.min(0.2, head.Size.X * 0.18), head.Size.Y * 0.08, -head.Size.Z / 2 - 0.01)
		eye.CFrame = head.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0 = head
		weld.Part1 = eye
		weld.C0 = offset
		weld.Parent = eye
		eye.Parent = container
	end
end

function Ghost.appearance(kit)
	local model = kit.model
	if not model then
		return nil
	end
	local created: { Instance } = {}
	local connections: { RBXScriptConnection } = {}
	local alive = true
	local degree = kit.degree

	local torso = findPart(model, { "UpperTorso", "Torso", "HumanoidRootPart" })
	if torso then
		aura(kit, torso, created, ColorSequence.new(INK, SHADE), if degree >= 3 then 5 else 3, false)
		if degree >= 3 then
			aura(kit, torso, created, ColorSequence.new(PALE, CYAN), 6, true)
		end
	end
	-- Katana and eyes live in their own model inside the character, so body
	-- afterimages (which copy the character's direct parts) never copy a sheathed blade
	local container = Instance.new("Model")
	container.Name = "SNGhostLook"
	container.Parent = model
	table.insert(created, container)
	local head = findPart(model, { "Head" })
	if head and degree >= 2 then
		eyes(head, container)
	end

	local katana = buildKatana(model, container, degree)
	local shown = false
	local recheck = 0

	local function drawnNow(): boolean
		local phase = model:GetAttribute(PHASE)
		local localUntil = model:GetAttribute(LOCAL_DRAW)
		return (typeof(phase) == "number" and phase >= 0.5) or (typeof(localUntil) == "number" and localUntil > now())
	end

	local function veiled(): boolean
		local endsAt = model:GetAttribute(CONCEALED)
		return typeof(endsAt) == "number" and endsAt > now()
	end

	local function refresh()
		if not alive or not katana then
			return
		end
		local want = drawnNow()
		local hidden = veiled()
		if want ~= shown then
			shown = want
			local blade = katana.blade
			if blade.Parent then
				if want then
					-- Instant Draw: a flash at the guard as the blade appears
					kit.Vfx.sparks(blade.Position, PALE, 10, 14)
				else
					-- Sheathed into nothing: the blade dissolves into wisps
					wisps(kit, blade.Position, 6)
				end
			end
		end
		for _, entry in katana.parts do
			entry.part.Transparency = if not shown then 1 elseif hidden then math.max(entry.base, 0.85) else entry.base
		end
		katana.trail.Enabled = shown and not hidden
		katana.light.Enabled = shown and not hidden
		-- Come back when this client's own draw runs out
		local localUntil = model:GetAttribute(LOCAL_DRAW)
		if typeof(localUntil) == "number" and localUntil > now() then
			recheck += 1
			local token = recheck
			task.delay(localUntil - now() + 0.05, function()
				if token == recheck then
					refresh()
				end
			end)
		end
	end

	for _, name in { PHASE, LOCAL_DRAW, CONCEALED } do
		table.insert(connections, model:GetAttributeChangedSignal(name):Connect(refresh))
	end

	-- Basic swings: the blade appears with the swing (no waiting for the
	-- server), and every cut leaves a white trail as far as the katana reaches
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local combatEvent = remotes and remotes:FindFirstChild("CombatEvent")
	if combatEvent and combatEvent:IsA("RemoteEvent") then
		table.insert(connections, combatEvent.OnClientEvent:Connect(function(kind, data)
			if kind ~= Protocol.CombatEvent.Attack or typeof(data) ~= "table" or data.attacker ~= model then
				return
			end
			markDrawn(kit)
			local startup = num(data.startup, 0.1)
			local step = math.floor(num(data.step, 1))
			local heavy = data.kind == "Heavy"
			task.delay(startup, function()
				local origin = alive and chest(kit)
				if origin then
					arcTrail(kit, origin, if heavy then 8 else 6.5, if heavy then 90 else 115, if heavy then 0 else ({ 20, -20, 35, 75 })[(step - 1) % 4 + 1], PALE, if heavy then 0.4 else 0.25, if heavy then 0.25 else 0.16)
				end
			end)
		end))
	end

	refresh()

	return function()
		alive = false
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, item in created do
			item:Destroy()
		end
		if model.Parent then
			model:SetAttribute(LOCAL_DRAW, nil)
		end
	end
end

return Ghost
