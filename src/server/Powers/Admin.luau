-- Admin Powers (PROGRAMME WARDEN) on the server: commands that control space.
-- Short teleports, freeze and jail commands, a force field that throws back a
-- well-timed attacker, speed, flight and a decoy; walls, gravity and a bounded
-- fling at Degree 2; a lockdown ring, a gravity field, a teleport strike
-- sequence and an area command at Degree 3; and the Ban Hammer ultimate.
-- Numbers come from Shared/Powers/Admin.luau (scaled by degree).
--
-- Every command here is a combat effect inside the match and nothing else: it
-- only ever acts on fighters the match lets Admin hurt, through the same hit,
-- status and construct services as every other power, and everything it makes
-- ends on its own and with its owner. It never touches real moderation,
-- accounts, inventories or progression.
--
-- Targeted commands lock onto one opponent during the wind-up (a sigil marks
-- them), and only execute if that opponent is still in reach and in sight and
-- the hit lands: dodging, blocking or breaking line of sight answers them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

local Admin = {}
local abilities = {}
Admin.abilities = abilities

local services: any = nil

-- How much farther than its range a locked target can step during the wind-up
-- and still be executed
local REACH_SLACK = 4
-- An aimed point picks the enemy standing this close to it
local POINT_PICK = 7
-- How long before each sequence strike Admin appears beside its target
local BLINK_LEAD = 0.14
-- Where sequence strikes arrive from: degrees around the target, from Admin's side
local STRIKE_SIDES = { 0, 125, -125 }
-- How far from the target a sequence strike arrives
local STRIKE_GAP = 3.5
-- Share of a throw's air time it keeps travelling sideways (keeping flings inside the walls)
local AIR_CARRY = 0.6
-- Fighters this close to a new wall's line are moved to the nearer side first
local WALL_CLEARANCE = 1.8

-- Construct palette: command gold, containment crimson, warm white, graphite steel
local GOLD = Color3.fromRGB(236, 188, 86)
local CRIMSON = Color3.fromRGB(168, 32, 48)
local WHITE = Color3.fromRGB(250, 243, 228)
local GRAPHITE = Color3.fromRGB(46, 48, 54)
local STEEL = Color3.fromRGB(112, 116, 124)

local UP = Vector3.new(0, 1, 0)

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true

function Admin.init(allServices)
	services = allServices
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Raycasts ignore every fighter (and, when asked, the caster's own constructs:
-- the station's walls never stand in the way of its own commands)
local function ignoreList(owner): { Instance }
	local list: { Instance } = {}
	for _, fighter in services.CharacterService:all() do
		table.insert(list, fighter.model)
	end
	if owner then
		for _, construct in services.ConstructService:ofOwner(owner) do
			table.insert(list, construct.model)
		end
	end
	return list
end

-- The floor under a point (just below it when there's none)
local function floorAt(position: Vector3): Vector3
	worldParams.FilterDescendantsInstances = ignoreList(nil)
	local result = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -16, 0), worldParams)
	return if result then result.Position else position - Vector3.new(0, 3, 0)
end

local function canSee(ctx, from: Vector3, to: Vector3): boolean
	worldParams.FilterDescendantsInstances = ignoreList(ctx.fighter)
	return workspace:Raycast(from, to - from, worldParams) == nil
end

-- How far along `direction` there's open space (walls stop decoys and drifts)
local function openDistance(from: Vector3, direction: Vector3, distance: number): number
	worldParams.FilterDescendantsInstances = ignoreList(nil)
	local result = workspace:Raycast(from, direction * distance, worldParams)
	return if result then math.max(0, (result.Position - from).Magnitude - 2) else distance
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function awayFrom(center: Vector3, target): Vector3?
	return Hitbox.flatDirection(target.root.Position - center)
end

local function turned(direction: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(direction)
end

-- Did a command's hit land (a guard broken by it counts)?
local function landed(outcome): boolean
	return outcome ~= nil and (outcome.result == "Hit" or outcome.result == "GuardBreak")
end

-- Connected at all (blocked hits still keep a strike sequence going)
local function connected(outcome): boolean
	return outcome ~= nil and (outcome.result == "Hit" or outcome.result == "Blocked" or outcome.result == "GuardBreak")
end

-- Statuses ----------------------------------------------------------------------------

-- Applies a status without weakening one that's already stronger (a lower
-- magnitude is stronger for Slow, a higher one for Haste)
local function stronger(ctx, target, statusId: string, duration: number, magnitude: number, lowerIsStronger: boolean?)
	local current = services.StatusService:get(target, statusId)
	if current then
		magnitude = if lowerIsStronger then math.min(current.magnitude, magnitude) else math.max(current.magnitude, magnitude)
	end
	return ctx:status(target, statusId, duration, { magnitude = magnitude })
end

-- Gravity is set up when it starts, so a different strength replaces it cleanly
local function setGravity(ctx, target, duration: number, magnitude: number)
	local current = services.StatusService:get(target, "Gravity")
	if current and math.abs(current.magnitude - magnitude) > 0.01 then
		ctx:clearStatus(target, "Gravity")
	end
	return ctx:status(target, "Gravity", duration, { magnitude = magnitude })
end

-- A status with a lasting effect that ends with it (time, used up, cleared) or
-- with Admin's reset, whichever comes first
local function statusWithFx(ctx, target, statusId: string, duration: number, magnitude: number?, fxName: string, fxData: { [string]: any })
	local stop = ctx:lastingFx(fxName, duration, fxData)
	ctx:own(stop)
	ctx:status(target, statusId, duration, {
		magnitude = magnitude,
		data = {
			onEnd = function()
				stop()
			end,
		},
	})
	return stop
end

-- Knockback that keeps the landing spot inside the arena's walls
local function bounded(target, direction: Vector3, spec: { [string]: any }): { [string]: any }
	local knockback = spec.knockback or 0
	if knockback <= 0 then
		return spec
	end
	local scale = target.combat and target.combat.KnockbackTaken or 1
	local airTime = 2 * (spec.launch or 0) * scale / math.max(1, workspace.Gravity)
	local travel = knockback * scale * (Combat.KnockbackDuration + airTime * AIR_CARRY)
	if travel < 1 then
		return spec
	end
	local from = target.root.Position
	local landing = from + direction * travel
	local match = services.MatchService:getMatchOf(target)
	if not match or not match.arena then
		return spec
	end
	local inside = services.ArenaService:clampInside(match.arena, landing, spec.wallMargin or 4)
	local room = flatDistance(inside, from)
	if room >= travel - 0.5 then
		return spec
	end
	local copy = table.clone(spec)
	copy.knockback = knockback * math.clamp(room / travel, 0.2, 1)
	return copy
end

-- Moves a fighter standing where a wall is about to rise to the nearer side of it
local function stepAside(ctx, fighter, desired: Vector3)
	ctx:teleport(Vector3.new(desired.X, fighter.root.Position.Y, desired.Z), { who = fighter, maxDistance = 8 })
end

-- Commands ----------------------------------------------------------------------------

-- Who a command is aimed at: the enemy standing near the aimed point if there
-- is one, otherwise the nearest one in front. Always in range and in sight.
local function pickTarget(ctx, range: number, arc: number?)
	local origin = ctx:origin()
	local best, bestScore = nil, math.huge
	for _, target in ctx:enemies() do
		local position = target.root.Position
		local distance = (position - origin).Magnitude
		if distance <= range and canSee(ctx, origin, position) then
			local score = math.huge
			if ctx.point and (position - ctx.point).Magnitude <= POINT_PICK then
				-- The one they aimed at wins over anyone merely closer
				score = (position - ctx.point).Magnitude - 1000
			else
				local flat = Hitbox.flatDirection(position - origin)
				local inFront = arc == nil
					or flat == nil
					or math.deg(math.acos(math.clamp(flat:Dot(ctx.direction), -1, 1))) <= arc / 2
				if inFront then
					score = distance
				end
			end
			if score < bestScore then
				best, bestScore = target, score
			end
		end
	end
	return best
end

local function stillInReach(ctx, target, range: number): boolean
	return services.CharacterService:isAlive(target)
		and ctx:isEnemy(target)
		and (target.root.Position - ctx:origin()).Magnitude <= range + REACH_SLACK
		and canSee(ctx, ctx:origin(), target.root.Position)
end

-- A targeted command: lock on, mark the target through the wind-up, then
-- execute as a hit if they're still in reach. Returns the target and the hit's
-- outcome, or nothing when there was no one to command or they got away.
-- `specFor(target, direction)` can change the hit's numbers at the last moment.
local function command(ctx, castFx: string, specFor: ((any, Vector3) -> { [string]: any })?)
	local def = ctx.def
	local target = pickTarget(ctx, def.range, def.arc)
	if not target then
		ctx:fx("CommandFizzle", { command = def.command, reason = "NoTarget" })
		ctx:refund(0.5)
		ctx:finish()
		return nil, nil
	end
	ctx:telegraph({ target }, ctx:activeAt())
	ctx:fx(castFx, { target = target.model, duration = def.startup, command = def.command, name = target.model.Name })
	if not ctx:waitActive() then
		return nil, nil
	end
	if not stillInReach(ctx, target, def.range) then
		ctx:fx("CommandFizzle", { command = def.command, target = target.model, reason = "Lost" })
		return nil, nil
	end
	local direction = awayFrom(ctx:origin(), target) or ctx.direction
	local spec = if specFor then specFor(target, direction) else nil
	ctx:fx("CommandExecute", { command = def.command, target = target.model, from = ctx:origin(), to = target.root.Position })
	local outcome = ctx:hit(target, spec, { direction = direction })
	if not landed(outcome) then
		ctx:fx("CommandDenied", { command = def.command, target = target.model, result = if outcome then outcome.result else "None" })
	end
	return target, outcome
end

-- Degree 1: Moderator ----------------------------------------------------------------------

function abilities.Teleport(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local origin = ctx:origin()
	local desired: Vector3
	if me.npc then
		-- CPUs use it to get out: back the way they came
		desired = origin - ctx.direction * def.range
	elseif ctx.point then
		desired = ctx.point + Vector3.new(0, 3, 0)
	else
		desired = origin + ctx.direction * def.range
	end
	-- The doorway opens where they'll arrive, so everyone can read it
	local preview = services.PowerService:safeSpot(me, desired, def.range)
	if not preview then
		ctx:fx("TeleportFail", { position = origin })
		ctx:refund(0.75)
		ctx:finish()
		return
	end
	ctx:fx("TeleportOpen", { from = origin, to = preview, duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local from = ctx:origin()
	local facing = Hitbox.flatDirection(preview - from) or ctx.direction
	local ok, where = ctx:teleport(preview, { maxDistance = def.range, facing = facing })
	if not ok or not where then
		ctx:fx("TeleportFail", { position = from })
		ctx:refund(0.75)
		return
	end
	ctx:fx("TeleportArrive", { from = from, to = where })
end

function abilities.FreezeCommand(ctx)
	local def = ctx.def
	local target, outcome = command(ctx, "FreezeCast")
	if target and landed(outcome) and services.CharacterService:isAlive(target) then
		statusWithFx(ctx, target, "Freeze", def.freeze, nil, "FreezeLock", { target = target.model })
	end
end

function abilities.ForceField(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local window = def.startup + def.active
	statusWithFx(ctx, me, "Shield", def.duration, def.shield, "ForceField", { shield = def.shield, window = window })
	-- Raised right before a real attack lands, the field throws the attacker back
	ctx:openCounter(window, function(_, _, opts)
		return opts.kind ~= "Status" and opts.kind ~= "Zone"
	end, function(attacker)
		task.spawn(function()
			local offset = attacker.root.Position - me.root.Position
			ctx:fx("ForceFieldRepel", { target = attacker.model, position = me.root.Position })
			if offset.Magnitude <= def.counterRange then
				ctx:hit(attacker, def.counter, { direction = Hitbox.flatDirection(offset) or ctx.direction, noDefense = true })
			end
		end)
		return { negate = true, result = "Countered" }
	end)
	ctx:waitUntil(ctx:now() + window)
end

function abilities.SpeedCommand(ctx)
	local def = ctx.def
	if not ctx:waitActive() then
		return
	end
	local stop = ctx:lastingFx("SpeedUp", def.duration, { haste = def.haste })
	ctx:own(stop)
	stronger(ctx, ctx.fighter, "Haste", def.duration, def.haste)
end

function abilities.Fly(ctx)
	local def = ctx.def
	local me = ctx.fighter
	ctx:fx("FlyWindup", { duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	ctx:dash(UP * def.lift + ctx.direction * def.drift, 0.3)
	ctx:clearStatus(me, "Gravity")
	statusWithFx(ctx, me, "Gravity", def.duration, def.gravity, "Flight", { duration = def.duration })
	stronger(ctx, me, "Haste", def.duration, def.haste)
end

function abilities.Clone(ctx)
	local def = ctx.def
	local me = ctx.fighter
	if not ctx:waitActive() then
		return
	end
	-- The decoy runs straight ahead until something solid stops it. It's only a
	-- picture: it can't hit, block or be hit.
	local start = ctx:origin()
	local distance = openDistance(start, ctx.direction, def.distance)
	local finish = floorAt(start + ctx.direction * distance) + Vector3.new(0, 3, 0)
	ctx:fx("CloneDecoy", { from = start, to = finish, run = def.run, direction = ctx.direction })
	statusWithFx(ctx, me, "Concealed", def.conceal, def.concealAmount, "CloneFade", { duration = def.conceal })
	stronger(ctx, me, "Haste", def.conceal, def.haste)
end

-- Degree 2: Administrator -------------------------------------------------------------------

local function newPart(model: Model, name: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material, transparency: number, collides: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.CanCollide = collides
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- A security wall: graphite posts and sill, a glass panel with a gold grid, a
-- crimson status light on each post and a small sign
local function buildWall(model: Model, frame: CFrame, width: number, height: number)
	local half = height / 2
	local panel = newPart(model, "Panel", frame, Vector3.new(width - 0.7, height - 0.5, 0.22), WHITE, Enum.Material.Glass, 0.6, true)
	model.PrimaryPart = panel
	newPart(model, "Sill", frame * CFrame.new(0, -half + 0.18, 0), Vector3.new(width, 0.36, 0.9), GRAPHITE, Enum.Material.Metal, 0, true)
	newPart(model, "SillLine", frame * CFrame.new(0, -half + 0.39, 0), Vector3.new(width - 0.8, 0.06, 0.3), GOLD, Enum.Material.Neon, 0.1, false)
	newPart(model, "Rail", frame * CFrame.new(0, half - 0.1, 0), Vector3.new(width - 0.4, 0.2, 0.4), STEEL, Enum.Material.Metal, 0, true)
	-- The grid: verticals about every two studs, three horizontals
	local columns = math.max(2, math.floor(width / 2.2))
	for index = 1, columns - 1 do
		local x = -width / 2 + 0.35 + (width - 0.7) * index / columns
		newPart(model, "Grid", frame * CFrame.new(x, 0, 0), Vector3.new(0.06, height - 0.6, 0.26), GOLD, Enum.Material.Neon, 0.45, false)
	end
	for index = 1, 3 do
		local y = -half + 0.25 + (height - 0.5) * index / 4
		newPart(model, "Grid", frame * CFrame.new(0, y, 0), Vector3.new(width - 0.8, 0.06, 0.26), GOLD, Enum.Material.Neon, 0.45, false)
	end
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + 0.05)
		newPart(model, "Post", frame * CFrame.new(x, 0.1, 0), Vector3.new(0.55, height + 0.2, 0.95), GRAPHITE, Enum.Material.Metal, 0, true)
		newPart(model, "Cap", frame * CFrame.new(x, half + 0.28, 0), Vector3.new(0.7, 0.16, 1.05), GOLD, Enum.Material.Metal, 0, false)
		local lamp = newPart(model, "Lamp", frame * CFrame.new(x, half - 0.9, -0.5), Vector3.new(0.3, 0.9, 0.08), CRIMSON, Enum.Material.Neon, 0, false)
		if side == 1 then
			local light = Instance.new("PointLight")
			light.Color = CRIMSON
			light.Range = 8
			light.Brightness = 0.8
			light.Parent = lamp
		end
	end
	-- Station signage on the panel, both sides
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sign = Instance.new("SurfaceGui")
		sign.Name = "Sign"
		sign.Face = face
		sign.LightInfluence = 0
		sign.PixelsPerStud = 40
		sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -12)
		label.Size = UDim2.new(1, -40, 0, 34)
		label.Font = Enum.Font.Code
		label.Text = "WARDEN  ·  SECTOR SEALED"
		label.TextColor3 = GOLD
		label.TextSize = 26
		label.TextTransparency = 0.15
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = sign
		sign.Parent = panel
	end
end

-- Moves anyone standing where a wall is about to rise to its nearer side
local function clearWall(ctx, frame: CFrame, width: number, height: number)
	for _, fighter in services.CharacterService:all() do
		if services.CharacterService:isAlive(fighter) then
			local localPosition = frame:PointToObjectSpace(fighter.root.Position)
			if math.abs(localPosition.X) <= width / 2 + 1 and math.abs(localPosition.Z) <= WALL_CLEARANCE and math.abs(localPosition.Y) <= height then
				local side = if localPosition.Z >= 0 then 1 else -1
				stepAside(ctx, fighter, (frame * CFrame.new(localPosition.X, 0, side * (WALL_CLEARANCE + 1.2))).Position)
			end
		end
	end
end

function abilities.Barrier(ctx)
	local def = ctx.def
	local facing = ctx.direction
	local base = floorAt(ctx:origin() + facing * def.distance)
	local center = base + UP * (def.height / 2)
	local frame = CFrame.lookAt(center, center + facing)
	ctx:fx("BarrierCast", { position = base, direction = facing, width = def.width, height = def.height, duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	clearWall(ctx, frame, def.width, def.height)
	local construct
	construct = ctx:construct({
		name = "Barrier",
		duration = def.duration,
		health = def.health,
		limit = def.limit,
		build = function(model)
			buildWall(model, frame, def.width, def.height)
		end,
		onEnd = function(_, reason)
			ctx:fx("BarrierDown", { position = center, direction = facing, width = def.width, height = def.height, reason = reason })
		end,
	})
	ctx:fx("BarrierUp", {
		model = construct.model,
		position = base,
		direction = facing,
		width = def.width,
		height = def.height,
		duration = def.duration,
	})
end

-- A containment cell: a floor plate, a crimson floor ring, bars and a gold crown ring
local function buildCell(model: Model, floor: Vector3, radius: number, height: number)
	local plate = newPart(model, "Plate", CFrame.new(floor + UP * 0.1) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.2, radius * 2 + 0.6, radius * 2 + 0.6), GRAPHITE, Enum.Material.Metal, 0, false)
	plate.Shape = Enum.PartType.Cylinder
	model.PrimaryPart = plate
	local bars = 8
	for index = 0, bars - 1 do
		local angle = index / bars * math.pi * 2
		local spot = floor + Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius)
		newPart(model, "Bar", CFrame.new(spot), Vector3.new(0.24, height, 0.24), STEEL, Enum.Material.Metal, 0, true)
		-- Ring pieces between this bar and the next, at the top and on the floor
		local nextAngle = (index + 1) / bars * math.pi * 2
		local a = floor + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local b = floor + Vector3.new(math.cos(nextAngle) * radius, 0, math.sin(nextAngle) * radius)
		local middle = (a + b) / 2
		local length = (b - a).Magnitude + 0.2
		local along = CFrame.lookAt(middle, b)
		newPart(model, "Crown", along + UP * height, Vector3.new(0.34, 0.3, length), GOLD, Enum.Material.Metal, 0, false)
		newPart(model, "FloorRing", along + UP * 0.24, Vector3.new(0.18, 0.06, length), CRIMSON, Enum.Material.Neon, 0.05, false)
	end
	local light = Instance.new("PointLight")
	light.Color = CRIMSON
	light.Range = radius * 2.5
	light.Brightness = 0.9
	light.Parent = plate
end

function abilities.Jail(ctx)
	local def = ctx.def
	local target, outcome = command(ctx, "JailCast")
	if not target or not landed(outcome) or not services.CharacterService:isAlive(target) then
		return
	end
	local me = ctx.fighter
	local floor = floorAt(target.root.Position)
	local height = 6.5
	local released = false
	local cell
	-- Opens the cell and frees whoever's inside (time, mashed out, shot apart, Admin gone)
	local function release(reason: string)
		if released then
			return
		end
		released = true
		local trap = services.StatusService:get(target, "Trapped")
		if trap and trap.sourceId == me.id then
			ctx:clearStatus(target, "Trapped")
		end
		if cell and cell.alive then
			services.ConstructService:destroy(cell, reason)
		end
	end
	cell = ctx:construct({
		name = "Jail",
		duration = def.duration,
		health = def.health,
		limit = 1,
		build = function(model)
			buildCell(model, floor, def.cellRadius, height)
		end,
		onEnd = function(_, reason)
			ctx:fx("JailOpen", { position = floor, radius = def.cellRadius, height = height, reason = reason, target = target.model })
			release(reason)
		end,
	})
	ctx:status(target, "Trapped", def.duration, { data = { center = floor, radius = def.cellRadius - 1 } })
	ctx:fx("JailLock", { model = cell.model, position = floor, radius = def.cellRadius, height = height, target = target.model, duration = def.duration })
	-- Mashing breaks the lock. The cast is long over; this runs beside the fight.
	task.spawn(function()
		local result = services.DefenseService:grab(target, me, {
			hold = def.duration,
			presses = def.escapePresses,
			ability = def.id,
			power = ctx.power,
			label = def.name,
			holding = function()
				return cell.alive and not released
			end,
		})
		release(if result == "Escaped" then "Escaped" else "Expired")
	end)
end

function abilities.GravityCommand(ctx)
	local def = ctx.def
	local target, outcome = command(ctx, "GravityCast")
	if not target or not landed(outcome) or not services.CharacterService:isAlive(target) then
		return
	end
	local airborne = FighterState.isAirborne(target.state, now()) or services.CombatService:isInAir(target)
	if airborne then
		-- Caught in the air: left floating, slow to come down
		setGravity(ctx, target, def.floatDuration, def.float)
		local stop = ctx:lastingFx("GravityFloat", def.floatDuration, { target = target.model, magnitude = def.float })
		ctx:own(stop)
	else
		setGravity(ctx, target, def.duration, def.heavy)
		stronger(ctx, target, "Slow", def.duration, def.slow, true)
		local stop = ctx:lastingFx("GravityHeavy", def.duration, { target = target.model, magnitude = def.heavy })
		ctx:own(stop)
	end
end

function abilities.Fling(ctx)
	local target, outcome = command(ctx, "FlingCast", function(target, direction)
		return bounded(target, direction, ctx.def)
	end)
	if target and connected(outcome) then
		ctx:fx("FlingThrow", { target = target.model, direction = awayFrom(ctx:origin(), target) or ctx.direction })
	end
end

-- Degree 3: System Authority ----------------------------------------------------------------

-- The lockdown ring: glass panels with a gold grid line, graphite posts with
-- gold caps, and crimson beacons on every fourth post
local function buildRing(model: Model, center: Vector3, radius: number, height: number, segments: number)
	local step = math.pi * 2 / segments
	local panelLength = 2 * radius * math.sin(step / 2)
	for index = 0, segments - 1 do
		local angle = index * step
		local post = center + Vector3.new(math.cos(angle) * radius, height / 2, math.sin(angle) * radius)
		local postPart = newPart(model, "Post", CFrame.new(post), Vector3.new(0.7, height + 0.3, 0.7), GRAPHITE, Enum.Material.Metal, 0, true)
		if index == 0 then
			model.PrimaryPart = postPart
		end
		newPart(model, "Cap", CFrame.new(post + UP * (height / 2 + 0.25)), Vector3.new(0.85, 0.2, 0.85), GOLD, Enum.Material.Metal, 0, false)
		local mid = angle + step / 2
		local panelCenter = center + Vector3.new(math.cos(mid) * radius * math.cos(step / 2), height / 2, math.sin(mid) * radius * math.cos(step / 2))
		local outward = Vector3.new(math.cos(mid), 0, math.sin(mid))
		local frame = CFrame.lookAt(panelCenter, panelCenter + outward)
		newPart(model, "Panel", frame, Vector3.new(panelLength - 0.6, height - 0.3, 0.22), WHITE, Enum.Material.Glass, 0.62, true)
		newPart(model, "Grid", frame * CFrame.new(0, height * 0.18, 0), Vector3.new(panelLength - 0.7, 0.07, 0.26), GOLD, Enum.Material.Neon, 0.35, false)
		newPart(model, "Grid", frame * CFrame.new(0, -height / 2 + 0.35, 0), Vector3.new(panelLength - 0.7, 0.07, 0.26), GOLD, Enum.Material.Neon, 0.5, false)
		if index % 4 == 0 then
			local beacon = newPart(model, "Beacon", CFrame.new(post + UP * (height / 2 + 0.6)), Vector3.new(0.5, 0.5, 0.5), CRIMSON, Enum.Material.Neon, 0, false)
			local light = Instance.new("PointLight")
			light.Color = CRIMSON
			light.Range = 12
			light.Brightness = 1
			light.Parent = beacon
		end
	end
end

-- Anyone standing on the ring's line steps to the side they're already closer to
local function clearRing(ctx, center: Vector3, radius: number)
	for _, fighter in services.CharacterService:all() do
		if services.CharacterService:isAlive(fighter) then
			local offset = fighter.root.Position - center
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			if math.abs(distance - radius) <= WALL_CLEARANCE and distance > 0.01 then
				local inside = distance < radius
				local goal = center + flat.Unit * (if inside then radius - (WALL_CLEARANCE + 1.2) else radius + (WALL_CLEARANCE + 1.2))
				stepAside(ctx, fighter, goal)
			end
		end
	end
end

function abilities.ArenaBarrier(ctx)
	local def = ctx.def
	local center = floorAt(ctx:origin())
	ctx:fx("LockdownCast", { position = center, radius = def.radius, segments = def.segments, duration = def.startup })
	if not ctx:waitActive() then
		ctx:fx("LockdownFizzle", { position = center, radius = def.radius })
		return
	end
	clearRing(ctx, center, def.radius)
	local construct = ctx:construct({
		name = "Lockdown",
		duration = def.duration,
		limit = 1,
		build = function(model)
			buildRing(model, center, def.radius, def.height, def.segments)
		end,
		onEnd = function(_, reason)
			ctx:fx("LockdownEnd", { position = center, radius = def.radius, height = def.height, segments = def.segments, reason = reason })
		end,
	})
	ctx:fx("LockdownUp", {
		model = construct.model,
		position = center,
		radius = def.radius,
		height = def.height,
		segments = def.segments,
		duration = def.duration,
	})
end

-- Where an aimed field or hammer lands: the aimed point within range, else ahead
local function aimedFloor(ctx, range: number, fallback: number): Vector3
	local origin = ctx:origin()
	local spot = ctx.point or (origin + ctx.direction * fallback)
	local flat = Vector3.new(spot.X - origin.X, 0, spot.Z - origin.Z)
	if flat.Magnitude > range then
		flat = flat.Unit * range
	end
	-- Not through walls
	local direction = Hitbox.flatDirection(flat)
	if direction then
		flat = direction * math.min(flat.Magnitude, openDistance(origin, direction, flat.Magnitude) + 1)
	end
	return floorAt(origin + flat)
end

function abilities.GravityField(ctx)
	local def = ctx.def
	local center = aimedFloor(ctx, def.range, 12)
	ctx:fx("GravityFieldCast", { position = center, radius = def.radius, duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	ctx:zone({
		center = center,
		radius = def.radius,
		duration = def.duration,
		tick = 0.25,
		clearance = 7,
		fx = "GravityField",
		fxData = { heavy = def.heavy },
		onTick = function(targets)
			for _, target in targets do
				-- Short refreshes: stepping out ends it within a moment
				setGravity(ctx, target, 0.45, def.heavy)
				stronger(ctx, target, "Slow", 0.45, def.slow, true)
			end
		end,
	})
end

function abilities.TeleportSequence(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local origin = ctx:origin()
	-- Everyone in reach and in sight, nearest first
	local found = {}
	for _, target in ctx:enemies() do
		local distance = (target.root.Position - origin).Magnitude
		if distance <= def.range and canSee(ctx, origin, target.root.Position) then
			table.insert(found, { target = target, distance = distance })
		end
	end
	if #found == 0 then
		ctx:fx("CommandFizzle", { command = def.command, reason = "NoTarget" })
		ctx:refund(0.5)
		ctx:finish()
		return
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	-- One strike per enemy, or the same enemy from several sides
	local count = math.min(#found, def.strikes)
	local plan = {}
	for index = 1, def.strikes do
		plan[index] = found[(index - 1) % count + 1].target
	end
	-- Each strike has its own prompt, shown in turn
	local first = ctx:activeAt()
	local stopped = false
	local cues: { [number]: string } = {}
	for index, target in plan do
		local impactAt = first + (index - 1) * def.interval
		local function send()
			if not stopped and ctx:alive() and services.CharacterService:isAlive(target) then
				cues[index] = services.DefenseService:prompt(target, me, { impactAt = impactAt, ability = def.id, power = ctx.power, label = def.name })
			end
		end
		local showIn = impactAt - Combat.Defense.PromptLead - ctx:now()
		if showIn <= 0 then
			send()
		else
			task.delay(showIn, send)
		end
	end
	ctx:onCleanup(function()
		stopped = true
	end)
	local models = {}
	for _, entry in found do
		table.insert(models, entry.target.model)
	end
	ctx:fx("SequenceStart", { duration = def.startup, targets = models })
	if not ctx:waitActive() then
		stopped = true
		return
	end
	for index, target in plan do
		local impactAt = first + (index - 1) * def.interval
		if not ctx:waitUntil(impactAt - BLINK_LEAD) then
			break
		end
		if not services.CharacterService:isAlive(target) or not ctx:isEnemy(target) then
			continue
		end
		-- Arrive beside them, from a different side each time
		local toMe = Hitbox.flatDirection(ctx:origin() - target.root.Position) or -ctx.direction
		local side = turned(toMe, STRIKE_SIDES[(index - 1) % #STRIKE_SIDES + 1])
		local desired = target.root.Position + side * STRIKE_GAP
		local from = ctx:origin()
		local ok, where = ctx:teleport(desired, { maxDistance = def.range + 8, facing = target.root.Position - desired })
		if ok and where then
			ctx:fx("SequenceBlink", { from = from, to = where, target = target.model, index = index })
		end
		if not ctx:waitUntil(impactAt) then
			break
		end
		local outcome = nil
		if (target.root.Position - ctx:origin()).Magnitude <= def.reach then
			outcome = ctx:hit(target, nil, { direction = awayFrom(ctx:origin(), target) or ctx.direction, cueId = cues[index] })
		end
		ctx:fx("SequenceStrike", { target = target.model, position = target.root.Position, index = index, landed = landed(outcome) })
		if not connected(outcome) then
			-- A dodged (or missed) strike breaks the sequence and leaves Admin open
			stopped = true
			ctx:fx("SequenceBroken", { position = ctx:origin() })
			ctx:finish()
			ctx:extendRecovery(0.3)
			return
		end
	end
	stopped = true
	if ctx:alive() then
		ctx:fx("SequenceEnd", { position = ctx:origin() })
		ctx:finish()
	end
end

function abilities.AreaCommand(ctx)
	local def = ctx.def
	ctx:telegraph(ctx:inSphere(ctx:origin(), def.radius + 3), ctx:activeAt())
	ctx:fx("AreaCast", { position = floorAt(ctx:origin()), radius = def.radius, duration = def.startup })
	if not ctx:waitActive() then
		return
	end
	local center = ctx:origin()
	local caught = {}
	for _, target in ctx:inSphere(center, def.radius) do
		if canSee(ctx, center, target.root.Position) then
			local outcome = ctx:hit(target, nil, { direction = awayFrom(center, target) or ctx.direction })
			if landed(outcome) and services.CharacterService:isAlive(target) then
				stronger(ctx, target, "Slow", def.duration, def.slow, true)
				table.insert(caught, target.model)
			end
		end
	end
	ctx:fx("AreaExecute", { position = floorAt(center), radius = def.radius, targets = caught, duration = def.duration })
end

-- Ultimate ------------------------------------------------------------------------------------

function abilities.BanHammer(ctx)
	local def = ctx.def
	local me = ctx.fighter
	local origin = ctx:origin()
	local floor = aimedFloor(ctx, def.range, 10)
	-- The hammer swings along this line; everyone draws it the same way
	local facing = Hitbox.flatDirection(floor - origin) or ctx.direction
	-- Everyone who could be caught gets the timing bar
	ctx:telegraph(ctx:inSphere(floor, def.pullRadius + 4, 8), ctx:activeAt())
	local stopWindup = ctx:lastingFx("BanHammerWindup", def.startup + 0.25, {
		position = floor,
		facing = facing,
		reach = def.hammerReach,
		radius = def.radius,
		pullRadius = def.pullRadius,
		startup = def.startup,
	})
	ctx:onCleanup(stopWindup)

	-- The leap: up, and part of the way toward the ring
	local toward = Vector3.new(floor.X - origin.X, 0, floor.Z - origin.Z)
	local drift = if toward.Magnitude > 0.5 then toward.Unit * math.min(toward.Magnitude, 10) / 0.35 else Vector3.zero
	ctx:dash(UP * def.leap + drift, 0.35)
	setGravity(ctx, me, def.startup, def.hang)
	ctx:onCleanup(function()
		local hang = services.StatusService:get(me, "Gravity")
		if hang and hang.sourceId == me.id then
			ctx:clearStatus(me, "Gravity")
		end
	end)

	-- The pull: gravity tugs everyone near the ring toward its centre in pulses.
	-- Walking straight out still beats it; standing still doesn't.
	local pulling = true
	ctx:onCleanup(function()
		pulling = false
	end)
	task.spawn(function()
		while pulling and ctx:now() < ctx:activeAt() - 0.1 and ctx:alive() do
			for _, target in ctx:inSphere(floor, def.pullRadius, 8) do
				local direction = Hitbox.flatDirection(floor - target.root.Position)
				local distance = flatDistance(floor, target.root.Position)
				if direction and distance > 1.5 then
					ctx:push(target, direction, math.min(def.pull, distance / def.pullTime), 0, def.pullTime)
				end
			end
			task.wait(def.pullEvery)
		end
	end)

	if not ctx:waitActive() then
		pulling = false
		ctx:fx("BanHammerFizzle", { position = floor })
		return
	end
	pulling = false

	ctx:stopDash()
	local hang = services.StatusService:get(me, "Gravity")
	if hang and hang.sourceId == me.id then
		ctx:clearStatus(me, "Gravity")
	end
	local from = ctx:origin()
	-- Down it comes: Admin lands holding the grip and the head strikes the ring's centre
	ctx:teleport(floor - facing * def.hammerReach + UP * 3, { maxDistance = def.range + 12, facing = facing })
	ctx:fx("BanHammerSlam", { position = floor, facing = facing, reach = def.hammerReach, radius = def.radius, from = from })
	for _, target in ctx:inSphere(floor, def.radius, 6) do
		local direction = awayFrom(floor, target) or ctx.direction
		ctx:hit(target, bounded(target, direction, def), { direction = direction, origin = floor })
	end
end

-- Hooks ---------------------------------------------------------------------------------------

-- Pressure breaks its concentration: every hit that hurts Admin costs Authority
function Admin.onHurt(_, _, outcome, _, runtime)
	local loss = runtime.def.resource and runtime.def.resource.lossOnHurt
	if loss and (outcome.dealt or 0) > 0 then
		runtime.resource = math.max(0, runtime.resource - loss)
	end
end

return Admin
