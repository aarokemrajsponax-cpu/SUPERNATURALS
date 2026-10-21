-- Builds the fight arenas and the training ground, hands arenas out to matches,
-- and answers "where do I spawn?" and "is this out of bounds?".
-- Arenas are built from parts in code; each match gets its own copy so several
-- matches can run at once without overlapping.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local ArenaService = {}

local ARENA = MatchConfig.Arena
local rgb = Color3.fromRGB

local PALETTE = {
	floor = rgb(32, 35, 46),
	floorInner = rgb(24, 26, 36),
	metal = rgb(55, 58, 72),
	cyan = rgb(70, 220, 255),
	purple = rgb(170, 90, 255),
}

export type Arena = {
	id: number,
	name: string,
	center: Vector3,
	floorY: number,
	model: Model,
	spawns: { CFrame },
	inUse: boolean,
}

local arenas: { Arena } = {}
local arenaFolder: Folder
local trainingSpots: { CFrame } = {}

local function part(parent: Instance, props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part")
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "ClassName" and key ~= "Size" and key ~= "CFrame" then
			instance[key] = value
		end
	end
	instance.Size = props.Size
	instance.CFrame = props.CFrame
	instance.Parent = parent
	return instance
end

-- A flat disc lying on the ground, centered on position
local function disc(parent: Instance, position: Vector3, diameter: number, thickness: number, props)
	local merged = table.clone(props)
	merged.Shape = Enum.PartType.Cylinder
	merged.Size = Vector3.new(thickness, diameter, diameter)
	merged.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, merged)
end

local function neon(color: Color3)
	return { Color = color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }
end

local function addLabel(parent: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	gui.Parent = parent
end

-- Objects Strong Dude can lift and throw. Weight 1 = light (crates, barrels),
-- 2 = heavy (boulders), 3 = enormous (a pillar section). They return to their
-- spot a few seconds after being thrown.
local THROWABLES = {
	{ name = "Crate", weight = 1, size = Vector3.new(3, 3, 3), color = rgb(150, 105, 60), material = Enum.Material.WoodPlanks },
	{ name = "Barrel", weight = 1, size = Vector3.new(3.2, 2.4, 2.4), color = rgb(120, 70, 45), material = Enum.Material.Wood, shape = Enum.PartType.Cylinder },
	{ name = "Boulder", weight = 2, size = Vector3.new(5, 4.4, 4.6), color = rgb(95, 92, 100), material = Enum.Material.Slate, shape = Enum.PartType.Ball },
	{ name = "Pillar", weight = 3, size = Vector3.new(9, 4.5, 4.5), color = rgb(70, 72, 88), material = Enum.Material.Concrete, shape = Enum.PartType.Cylinder },
}

local function addThrowable(parent: Instance, kind, position: Vector3, yaw: number)
	local prop = part(parent, {
		Name = kind.name,
		Shape = kind.shape or Enum.PartType.Block,
		Size = kind.size,
		CFrame = CFrame.new(position + Vector3.new(0, kind.size.Y / 2, 0)) * CFrame.Angles(0, yaw, if kind.shape == Enum.PartType.Cylinder then math.rad(90) else 0),
		Color = kind.color,
		Material = kind.material,
	})
	if kind.shape == Enum.PartType.Cylinder then
		-- Cylinders lie along X; stand barrels and pillars upright
		prop.CFrame = CFrame.new(position + Vector3.new(0, kind.size.X / 2, 0)) * CFrame.Angles(0, yaw, math.rad(90))
	end
	prop:SetAttribute("Weight", kind.weight)
	prop:SetAttribute("HomeCFrame", prop.CFrame)
	CollectionService:AddTag(prop, Protocol.Tag.Throwable)
	return prop
end

-- Spread around the arena (as a share of its half-size), the centre kept clear
local THROWABLE_SPOTS = {
	{ kind = 1, at = Vector3.new(-0.55, 0, 0.2) },
	{ kind = 2, at = Vector3.new(0.55, 0, -0.2) },
	{ kind = 3, at = Vector3.new(0.25, 0, 0.6) },
	{ kind = 1, at = Vector3.new(-0.25, 0, -0.62) },
	{ kind = 3, at = Vector3.new(-0.62, 0, -0.35) },
	{ kind = 2, at = Vector3.new(0.62, 0, 0.38) },
	{ kind = 4, at = Vector3.new(0.35, 0, -0.4) },
}

local function scatterThrowables(parent: Instance, top: Vector3, half: Vector3)
	for index, spot in THROWABLE_SPOTS do
		local position = top + Vector3.new(spot.at.X * half.X, 0, spot.at.Z * half.Z)
		addThrowable(parent, THROWABLES[spot.kind], position, index * 0.7)
	end
end

local function buildArena(id: number): Arena
	local center = ARENA.FirstCenter + Vector3.new(0, 0, (id - 1) * ARENA.Spacing)
	local size = ARENA.Size
	local half = Vector3.new(size.X / 2, 0, size.Z / 2)
	local model = Instance.new("Model")
	model.Name = "ProvingGrounds" .. id

	-- Floor: top surface sits 1 stud above the ground
	local floorY = center.Y + 1
	part(model, {
		Name = "Floor",
		Size = Vector3.new(size.X, 2, size.Z),
		CFrame = CFrame.new(center),
		Color = PALETTE.floor,
		Material = Enum.Material.Slate,
	})
	local top = Vector3.new(center.X, floorY, center.Z)
	disc(model, top + Vector3.new(0, 0.02, 0), 64, 0.05, neon(PALETTE.purple))
	disc(model, top + Vector3.new(0, 0.04, 0), 63, 0.05, { Color = PALETTE.floorInner, CanCollide = false })
	disc(model, top + Vector3.new(0, 0.06, 0), 20, 0.05, neon(PALETTE.cyan))
	disc(model, top + Vector3.new(0, 0.08, 0), 19, 0.05, { Color = PALETTE.floor, CanCollide = false })

	-- Glowing grid lines across the floor
	for i = -2, 2 do
		local alongZ = neon(PALETTE.cyan)
		alongZ.Name = "Grid"
		alongZ.Transparency = 0.55
		alongZ.Size = Vector3.new(0.25, 0.04, size.Z - 6)
		alongZ.CFrame = CFrame.new(top + Vector3.new(i * size.X / 5, 0.01, 0))
		part(model, alongZ)

		local alongX = table.clone(alongZ)
		alongX.Size = Vector3.new(size.X - 6, 0.04, 0.25)
		alongX.CFrame = CFrame.new(top + Vector3.new(0, 0.01, i * size.Z / 5))
		part(model, alongX)
	end

	-- Low rim with a glowing top, plus invisible walls that keep fighters in
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local alongX = side[2] ~= 0
		local length = if alongX then size.X else size.Z
		local offset = Vector3.new(side[1] * (half.X + 1), 0, side[2] * (half.Z + 1))
		local rimSize = if alongX then Vector3.new(length + 4, 3, 2) else Vector3.new(2, 3, length + 4)
		part(model, {
			Name = "Rim",
			Size = rimSize,
			CFrame = CFrame.new(top + offset + Vector3.new(0, 0.5, 0)),
			Color = PALETTE.metal,
			Material = Enum.Material.DiamondPlate,
		})
		local glow = neon(PALETTE.cyan)
		glow.Size = Vector3.new(rimSize.X + 0.05, 0.2, rimSize.Z + 0.05)
		glow.CFrame = CFrame.new(top + offset + Vector3.new(0, 2.1, 0))
		part(model, glow)
		local wallSize = if alongX then Vector3.new(length + 8, ARENA.WallHeight, 2) else Vector3.new(2, ARENA.WallHeight, length + 8)
		part(model, {
			Name = "Barrier",
			Size = wallSize,
			CFrame = CFrame.new(top + offset + Vector3.new(0, ARENA.WallHeight / 2, 0)),
			Transparency = 1,
			CastShadow = false,
		})
	end

	-- Corner pillars with glowing rings
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local base = top + Vector3.new(corner[1] * (half.X - 3), 0, corner[2] * (half.Z - 3))
		local pillar = part(model, {
			Name = "Pillar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(16, 4, 4),
			CFrame = CFrame.new(base + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PALETTE.metal,
			Material = Enum.Material.Metal,
		})
		for _, height in { 5, 11 } do
			disc(model, base + Vector3.new(0, height, 0), 4.3, 0.4, neon(PALETTE.purple))
		end
		disc(model, base + Vector3.new(0, 16.2, 0), 3, 0.5, neon(PALETTE.cyan))
		local light = Instance.new("PointLight")
		light.Color = PALETTE.cyan
		light.Range = 24
		light.Brightness = 1.5
		light.Parent = pillar
	end

	-- A sign floating over the far edge
	local sign = part(model, {
		Name = "Sign",
		Size = Vector3.new(30, 6, 0.5),
		CFrame = CFrame.lookAt(top + Vector3.new(0, 14, half.Z + 2), top + Vector3.new(0, 14, 0)),
		Color = PALETTE.floorInner,
		CanCollide = false,
	})
	addLabel(sign, Enum.NormalId.Front, "PROVING GROUNDS", PALETTE.cyan)

	-- Spawns: opposite corners first, so a duel starts across the arena
	local spawnOffsets = {
		Vector3.new(-1, 0, -1),
		Vector3.new(1, 0, 1),
		Vector3.new(1, 0, -1),
		Vector3.new(-1, 0, 1),
	}
	local spawns = {}
	for _, unit in spawnOffsets do
		local position = top + Vector3.new(unit.X * (half.X - 16), 3, unit.Z * (half.Z - 16))
		table.insert(spawns, CFrame.lookAt(position, Vector3.new(top.X, position.Y, top.Z)))
	end

	scatterThrowables(model, top, half)

	model.Parent = arenaFolder
	return {
		id = id,
		name = "Proving Grounds",
		center = center,
		floorY = floorY,
		model = model,
		spawns = spawns,
		inUse = false,
	}
end

local function buildTrainingGround()
	local center = MatchConfig.TrainingGround.Center
	local model = Instance.new("Model")
	model.Name = "TrainingGround"
	local top = center + Vector3.new(0, 0.5, 0)
	part(model, {
		Name = "Floor",
		Size = Vector3.new(34, 1, 44),
		CFrame = CFrame.new(center),
		Color = PALETTE.floor,
		Material = Enum.Material.Slate,
	})
	for _, side in { -1, 1 } do
		local edge = neon(PALETTE.cyan)
		edge.Size = Vector3.new(34, 0.1, 0.4)
		edge.CFrame = CFrame.new(top + Vector3.new(0, 0.05, side * 21.8))
		part(model, edge)
		local edge2 = neon(PALETTE.cyan)
		edge2.Size = Vector3.new(0.4, 0.1, 44)
		edge2.CFrame = CFrame.new(top + Vector3.new(side * 16.8, 0.05, 0))
		part(model, edge2)
	end
	local sign = part(model, {
		Name = "Sign",
		Size = Vector3.new(22, 5, 0.5),
		-- Faces toward the spawn (+X)
		CFrame = CFrame.lookAt(top + Vector3.new(-14, 8, 0), top + Vector3.new(10, 8, 0)),
		Color = PALETTE.floorInner,
		CanCollide = false,
	})
	addLabel(sign, Enum.NormalId.Front, "TRAINING GROUND", PALETTE.cyan)

	-- A few things to practise throwing
	addThrowable(model, THROWABLES[1], top + Vector3.new(10, 0, -16), 0.3)
	addThrowable(model, THROWABLES[2], top + Vector3.new(12, 0, 16), 1.1)
	addThrowable(model, THROWABLES[3], top + Vector3.new(4, 0, -18), 0.6)

	trainingSpots = {}
	for _, z in { -12, 0, 12 } do
		local position = top + Vector3.new(-4, 3, z)
		local spot = CFrame.lookAt(position, position + Vector3.new(1, 0, 0))
		table.insert(trainingSpots, spot)
		disc(model, Vector3.new(position.X, top.Y + 0.03, position.Z), 7, 0.05, neon(PALETTE.purple))
	end

	model.Parent = workspace
end

function ArenaService:Init()
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arenas"
	arenaFolder.Parent = workspace
end

function ArenaService:Start()
	buildTrainingGround()
	-- Build the first arena up front so the first match starts instantly
	table.insert(arenas, buildArena(1))
end

-- A free arena for a new match, or nil if all are busy
function ArenaService:reserve(): Arena?
	for _, arena in arenas do
		if not arena.inUse then
			arena.inUse = true
			return arena
		end
	end
	if #arenas >= ARENA.MaxSimultaneous then
		return nil
	end
	local arena = buildArena(#arenas + 1)
	table.insert(arenas, arena)
	arena.inUse = true
	return arena
end

function ArenaService:release(arena: Arena)
	arena.inUse = false
end

-- The spawn farthest from everyone in `others`
function ArenaService:pickSpawn(arena: Arena, others: { Vector3 }): CFrame
	local best, bestDistance = arena.spawns[1], -1
	for _, spawn in arena.spawns do
		local nearest = math.huge
		for _, position in others do
			nearest = math.min(nearest, (spawn.Position - position).Magnitude)
		end
		if nearest > bestDistance then
			best, bestDistance = spawn, nearest
		end
	end
	return best
end

function ArenaService:isOutOfBounds(arena: Arena, position: Vector3): boolean
	if position.Y < arena.floorY - ARENA.FallDepth then
		return true
	end
	local offset = position - arena.center
	local margin = 6
	return math.abs(offset.X) > ARENA.Size.X / 2 + margin or math.abs(offset.Z) > ARENA.Size.Z / 2 + margin
end

-- The nearest point inside the arena's walls (keeping `margin` studs from them),
-- at the same height. Teleports and knockback targets use it.
function ArenaService:clampInside(arena: Arena, position: Vector3, margin: number): Vector3
	local half = Vector3.new(ARENA.Size.X / 2 - margin, 0, ARENA.Size.Z / 2 - margin)
	local offset = position - arena.center
	return Vector3.new(
		arena.center.X + math.clamp(offset.X, -half.X, half.X),
		position.Y,
		arena.center.Z + math.clamp(offset.Z, -half.Z, half.Z)
	)
end

function ArenaService:contains(arena: Arena, position: Vector3, margin: number?): boolean
	local offset = position - arena.center
	local pad = margin or 0
	return math.abs(offset.X) <= ARENA.Size.X / 2 - pad and math.abs(offset.Z) <= ARENA.Size.Z / 2 - pad
end

function ArenaService:lobbySpawn(): CFrame
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local base = if spawnLocation then spawnLocation.CFrame else CFrame.new(0, 0, 0)
	local jitter = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	return CFrame.new(base.Position + Vector3.new(0, 4, 0) + jitter)
end

-- The middle of the lobby (the spawn point), used by admin events
function ArenaService:lobbyCenter(): Vector3
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawnLocation then spawnLocation.Position else Vector3.zero
end

function ArenaService:trainingSpawn(): CFrame
	local center = MatchConfig.TrainingGround.Center
	return CFrame.lookAt(center + Vector3.new(12, 4, 0), center + Vector3.new(0, 4, 0))
end

function ArenaService:trainingDummySpots(): { CFrame }
	return trainingSpots
end

return ArenaService
