-- The Nexus: the lobby everyone spawns into. A round stone plaza with
-- glowing inlaid rings, a raised dais with a floating crystal and a beam of
-- light, statues of the seven powers, lanterns, benches, spirit trees, sky
-- islands, and five gateways: Battle Gate (fight), Training Hall, Homes
-- (your base), Market (shop) and the Watch screen (spectate).
-- Holiday decorations and the luxury car sit in the plaza too, so the spots
-- they use (SeasonalDecor/Build.luau KEEP_CLEAR) are left open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)

local Nexus = {}

local rgb = Color3.fromRGB

local STONE = rgb(198, 190, 180)
local STONE_DARK = rgb(120, 114, 108)
local MARBLE = rgb(236, 232, 226)
local GOLD = rgb(255, 205, 110)
local CYAN = rgb(90, 225, 255)
local VIOLET = rgb(170, 110, 255)
local WOOD = rgb(110, 76, 52)
local IRON = rgb(52, 50, 58)

Nexus.Radius = 64

-- The gateways: where they stand (angle in degrees from +X, toward +Z), what
-- they do, and their colour. The statues stand on the north side behind the car.
Nexus.Gates = {
	{ id = "Battle", name = "BATTLE GATE", icon = "⚔️", angle = 0, color = rgb(255, 110, 90), action = "Window:Play", prompt = "Find a fight" },
	{ id = "Training", name = "TRAINING HALL", icon = "🎯", angle = 180, color = CYAN, action = "Travel:Training", prompt = "Go to training" },
	{ id = "Homes", name = "HOMES", icon = "🏠", angle = 45, color = rgb(255, 190, 120), action = "Base:Home", prompt = "Go to your base" },
	{ id = "Market", name = "MARKET", icon = "🛍️", angle = 135, color = GOLD, action = "Window:Shop", prompt = "Open the shop" },
	{ id = "Watch", name = "ARENA VIEW", icon = "📺", angle = 90, color = VIOLET, action = "Window:Watch", prompt = "Watch a match" },
}

local function part(parent: Instance, props: { [string]: any }): BasePart
	local instance = Instance.new(props.ClassName or "Part")
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "ClassName" and key ~= "Size" and key ~= "CFrame" then
			(instance :: any)[key] = value
		end
	end
	instance.Size = props.Size
	instance.CFrame = props.CFrame
	instance.Parent = parent
	return instance
end

-- A flat disc lying on the ground with its top at `top`
local function disc(parent: Instance, center: Vector3, diameter: number, thickness: number, props: { [string]: any }): BasePart
	local merged = table.clone(props)
	merged.Shape = Enum.PartType.Cylinder
	merged.Size = Vector3.new(thickness, diameter, diameter)
	merged.CFrame = CFrame.new(center - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, merged)
end

-- A standing cylinder from `base` up `height`
local function column(parent: Instance, base: Vector3, height: number, diameter: number, props: { [string]: any }): BasePart
	local merged = table.clone(props)
	merged.Shape = Enum.PartType.Cylinder
	merged.Size = Vector3.new(height, diameter, diameter)
	merged.CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, merged)
end

local function ball(parent: Instance, center: Vector3, diameter: number, props: { [string]: any }): BasePart
	local merged = table.clone(props)
	merged.Shape = Enum.PartType.Ball
	merged.Size = Vector3.one * diameter
	merged.CFrame = CFrame.new(center)
	return part(parent, merged)
end

local function light(parent: Instance, color: Color3, range: number, brightness: number, shadows: boolean?)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = shadows == true
	point.Parent = parent
	return point
end

local function sign(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, pixelsPerStud: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	gui.Parent = parent
	return gui
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	for key, value in props do
		(particles :: any)[key] = value
	end
	particles.Parent = parent
	return particles
end

local function polar(angle: number, radius: number, y: number?): Vector3
	local radians = math.rad(angle)
	return Vector3.new(math.cos(radians) * radius, y or 0, math.sin(radians) * radius)
end

-- Ground ---------------------------------------------------------------------------------

local function buildGround(folder: Instance)
	-- Grass terrain around the plaza (the arenas float further out, so it stops short of them)
	local terrain = workspace.Terrain
	local ok = pcall(function()
		terrain:FillBlock(CFrame.new(-40, -6, 0), Vector3.new(600, 12, 640), Enum.Material.Grass)
		-- Soft hills at the edges
		local random = Random.new(11)
		for index = 1, 10 do
			local angle = index / 10 * 360 + random:NextNumber(-12, 12)
			local distance = random:NextNumber(220, 290)
			local position = polar(angle, distance, -18)
			if position.X < 260 then
				terrain:FillBall(position, random:NextNumber(30, 48), Enum.Material.Grass)
			end
		end
		-- A small pond with a stone rim, south-west of the plaza
		terrain:FillBlock(CFrame.new(-118, -2.5, 118), Vector3.new(44, 5, 36), Enum.Material.Water)
	end)
	if not ok then
		-- No terrain (or it failed): a plain grass slab instead
		part(folder, {
			Name = "Ground",
			Size = Vector3.new(600, 2, 640),
			CFrame = CFrame.new(-40, -1, 0),
			Color = rgb(96, 150, 78),
			Material = Enum.Material.Grass,
		})
	end
	-- Stones around the pond
	local random = Random.new(5)
	for index = 1, 22 do
		local angle = index / 22 * math.pi * 2
		local position = Vector3.new(-118 + math.cos(angle) * 23, 0.3, 118 + math.sin(angle) * 19)
		ball(folder, position, random:NextNumber(2.2, 3.6), { Color = STONE_DARK, Material = Enum.Material.Slate })
	end
end

-- Plaza ---------------------------------------------------------------------------------

local function buildPlaza(folder: Instance)
	local radius = Nexus.Radius
	disc(folder, Vector3.new(0, 0.1, 0), radius * 2, 1.2, { Name = "Plaza", Color = STONE, Material = Enum.Material.Pavement })
	-- Curb ring around the edge
	local segments = 36
	for index = 0, segments - 1 do
		local angle = index / segments * 360
		local position = polar(angle, radius + 0.4, 0.45)
		part(folder, {
			Name = "Curb",
			Size = Vector3.new(1.4, 0.9, 2 * math.pi * (radius + 0.4) / segments + 0.15),
			CFrame = CFrame.lookAt(position, position + polar(angle + 90, 1)) * CFrame.Angles(0, math.rad(90), 0),
			Color = STONE_DARK,
			Material = Enum.Material.Slate,
		})
	end
	-- Inlaid rings: gold and cyan light set into the stone
	for _, ring in { { 24, GOLD }, { 46, CYAN }, { 47, GOLD } } do
		disc(folder, Vector3.new(0, 0.13, 0), ring[1] * 2 + 0.6, 0.05, { Color = ring[2], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		disc(folder, Vector3.new(0, 0.15, 0), ring[1] * 2 - 0.6, 0.05, { Color = STONE, Material = Enum.Material.Pavement, CanCollide = false, CastShadow = false })
	end
	-- Rune tiles between the rings
	for index = 0, 11 do
		local angle = index / 12 * 360 + 15
		local position = polar(angle, 35.5, 0.16)
		local tile = part(folder, {
			Name = "Rune",
			Size = Vector3.new(3, 0.06, 3),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(-angle + 45), 0),
			Color = if index % 2 == 0 then VIOLET else CYAN,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Transparency = 0.25,
		})
		tile:SetAttribute("Pulse", index)
	end
	-- Radial paving lines
	for index = 0, 15 do
		local angle = index / 16 * 360
		local mid = polar(angle, 55.5, 0.15)
		part(folder, {
			Name = "Seam",
			Size = Vector3.new(0.18, 0.05, 15),
			CFrame = CFrame.lookAt(mid, polar(angle, 70, 0.15)),
			Color = STONE_DARK,
			Material = Enum.Material.Slate,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

local function buildDais(folder: Instance): BasePart
	-- Three marble steps
	for index, step in { { 22, 0.7 }, { 17, 1.4 }, { 12, 2.1 } } do
		disc(folder, Vector3.new(0, step[2], 0), step[1], 0.7, {
			Name = "DaisStep" .. index,
			Color = if index == 3 then MARBLE else rgb(214, 208, 200),
			Material = Enum.Material.Marble,
		})
		disc(folder, Vector3.new(0, step[2] + 0.01, 0), step[1] + 0.25, 0.08, { Color = GOLD, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Transparency = 0.2 })
		disc(folder, Vector3.new(0, step[2] + 0.02, 0), step[1] - 0.2, 0.08, { Color = if index == 3 then MARBLE else rgb(214, 208, 200), Material = Enum.Material.Marble, CanCollide = false, CastShadow = false })
	end
	-- The floating crystal: a glass diamond with a glowing core, and a beam of light above it
	local crystalAt = Vector3.new(0, 14, 0)
	local diamond = CFrame.new(crystalAt) * CFrame.Angles(math.rad(45), 0, math.rad(35.264))
	local crystal = part(folder, {
		Name = "NexusCrystal",
		Size = Vector3.one * 6,
		CFrame = diamond,
		Color = rgb(150, 200, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Reflectance = 0.25,
		CanCollide = false,
	})
	part(folder, {
		Name = "NexusCore",
		Size = Vector3.one * 3.4,
		CFrame = diamond,
		Color = CYAN,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	light(crystal, CYAN, 46, 3, true)
	emitter(crystal, {
		Color = ColorSequence.new(CYAN, VIOLET),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 12,
	})
	local beam = column(folder, crystalAt + Vector3.new(0, 4, 0), 260, 1.6, {
		Name = "NexusBeam",
		Color = rgb(170, 230, 255),
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	beam:SetAttribute("Decor", true)
	-- Four small pylons around the dais
	for index = 0, 3 do
		local base = polar(index * 90 + 45, 13.5, 0.7)
		column(folder, base, 4.5, 1.2, { Name = "Pylon", Color = MARBLE, Material = Enum.Material.Marble })
		local cap = ball(folder, base + Vector3.new(0, 5.1, 0), 1.3, { Name = "PylonLight", Color = GOLD, Material = Enum.Material.Neon, CanCollide = false })
		light(cap, GOLD, 14, 1.2)
	end
	-- Spawn on top of the dais (invisible: the dais is the visible part)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NexusSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	spawn.CFrame = CFrame.new(0, 2.25, 0)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = folder
	return spawn
end

-- Gateways ---------------------------------------------------------------------------------

local function buildGate(folder: Instance, gate)
	local model = Instance.new("Model")
	model.Name = "Gate_" .. gate.id
	local distance = Nexus.Radius + 4
	local center = polar(gate.angle, distance, 0)
	-- Faces the plaza centre
	local frame = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	local width, height = 16, 18
	-- Base step
	part(model, {
		Name = "Step",
		Size = Vector3.new(width + 8, 0.8, 8),
		CFrame = frame * CFrame.new(0, 0.4, 0),
		Color = STONE_DARK,
		Material = Enum.Material.Slate,
	})
	for _, side in { -1, 1 } do
		local pillarBase = frame * CFrame.new(side * (width / 2 + 1.5), 0.8, 0)
		part(model, {
			Name = "Pillar",
			Size = Vector3.new(3, height, 3),
			CFrame = pillarBase * CFrame.new(0, height / 2, 0),
			Color = STONE,
			Material = Enum.Material.Limestone,
		})
		-- Gold bands and a lit brazier on top
		for _, y in { 2, height - 2 } do
			part(model, {
				Name = "Band",
				Size = Vector3.new(3.3, 0.5, 3.3),
				CFrame = pillarBase * CFrame.new(0, y, 0),
				Color = GOLD,
				Material = Enum.Material.Metal,
				Reflectance = 0.2,
			})
		end
		local bowl = part(model, {
			Name = "Brazier",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 3.2, 3.2),
			CFrame = pillarBase * CFrame.new(0, height + 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = IRON,
			Material = Enum.Material.Metal,
		})
		local flame = ball(model, (pillarBase * CFrame.new(0, height + 1.5, 0)).Position, 1.6, {
			Name = "Flame",
			Color = gate.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		light(flame, gate.color, 22, 2)
		emitter(flame, {
			Color = ColorSequence.new(Color3.new(1, 1, 1), gate.color),
			LightEmission = 1,
			LightInfluence = 0,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new(0.1, 1),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(0, 6, 0),
			Rate = 18,
		})
		local _ = bowl
	end
	-- Lintel with the gate's name, and a keystone gem
	local lintel = part(model, {
		Name = "Lintel",
		Size = Vector3.new(width + 7, 3.2, 3.4),
		CFrame = frame * CFrame.new(0, height + 0.8 - 1.6, 0),
		Color = STONE,
		Material = Enum.Material.Limestone,
	})
	sign(lintel, Enum.NormalId.Back, `{gate.icon}  {gate.name}`, Color3.new(1, 1, 1), 36)
	sign(lintel, Enum.NormalId.Front, `{gate.icon}  {gate.name}`, Color3.new(1, 1, 1), 36)
	part(model, {
		Name = "Keystone",
		Size = Vector3.new(2, 2, 0.6),
		CFrame = frame * CFrame.new(0, height + 2.6, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Color = gate.color,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	-- The swirling portal surface
	local portal = part(model, {
		Name = "PortalSurface",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, height - 2, width - 1),
		CFrame = frame * CFrame.new(0, 0.8 + (height - 2) / 2 + 0.5, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = gate.color,
		Material = Enum.Material.ForceField,
		Transparency = 0.1,
		CanCollide = false,
		CastShadow = false,
	})
	portal:SetAttribute("Spin", true)
	emitter(portal, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), gate.color),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 14,
	})
	light(portal, gate.color, 18, 1.5)
	-- What the gate does (WorldService and the client react to the prompt)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatePrompt"
	prompt.ActionText = gate.prompt
	prompt.ObjectText = gate.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	-- E, F, Q and the gamepad face buttons are combat keys, so the gates use T / D-pad right
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.DPadRight
	prompt:SetAttribute("Action", gate.action)
	prompt.Parent = portal
	model.Parent = folder
	return model
end

-- Statues of the seven powers ------------------------------------------------------------

local function figure(model: Model, base: CFrame, def)
	local primary, secondary, accent = def.colors.primary, def.colors.secondary, def.colors.accent or def.colors.primary
	local body = { Color = primary, Material = Enum.Material.Marble }
	local dark = { Color = secondary, Material = Enum.Material.Marble }
	local glow = { Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }
	local function piece(size: Vector3, offset: CFrame, props)
		local merged = table.clone(props)
		merged.Size = size
		merged.CFrame = base * offset
		return part(model, merged)
	end
	-- Legs, torso, arms, head: a heroic stance
	piece(Vector3.new(1.1, 3.4, 1.1), CFrame.new(-0.7, 1.7, 0) * CFrame.Angles(0, 0, math.rad(-6)), dark)
	piece(Vector3.new(1.1, 3.4, 1.1), CFrame.new(0.7, 1.7, 0) * CFrame.Angles(0, 0, math.rad(6)), dark)
	piece(Vector3.new(2.6, 3, 1.4), CFrame.new(0, 4.9, 0), body)
	piece(Vector3.new(0.9, 3, 0.9), CFrame.new(-1.8, 4.8, 0) * CFrame.Angles(0, 0, math.rad(-14)), body)
	piece(Vector3.new(0.9, 3, 0.9), CFrame.new(1.8, 4.8, 0) * CFrame.Angles(0, 0, math.rad(14)), body)
	local head = ball(model, (base * CFrame.new(0, 7.2, 0)).Position, 1.7, body)
	local _ = head
	-- Each power's signature
	local id = def.id
	if id == "StrongDude" then
		ball(model, (base * CFrame.new(-2.3, 3.2, -0.4)).Position, 1.5, glow)
		ball(model, (base * CFrame.new(2.3, 3.2, -0.4)).Position, 1.5, glow)
	elseif id == "Ghost" then
		piece(Vector3.new(0.2, 5.5, 0.35), CFrame.new(2.3, 5.6, -0.6) * CFrame.Angles(math.rad(-20), 0, math.rad(-20)), { Color = rgb(235, 240, 255), Material = Enum.Material.Neon, CanCollide = false })
		piece(Vector3.new(3, 4.5, 0.15), CFrame.new(0, 4.6, 0.8), { Color = rgb(40, 40, 50), Material = Enum.Material.Fabric })
	elseif id == "Shapeshifter" then
		piece(Vector3.new(0.5, 1.2, 0.5), CFrame.new(-0.55, 8.2, 0) * CFrame.Angles(0, 0, math.rad(-15)), dark)
		piece(Vector3.new(0.5, 1.2, 0.5), CFrame.new(0.55, 8.2, 0) * CFrame.Angles(0, 0, math.rad(15)), dark)
		piece(Vector3.new(1, 0.9, 1.6), CFrame.new(0, 6.9, -0.9), dark)
	elseif id == "MachineMaster" then
		piece(Vector3.new(2, 3.2, 1.2), CFrame.new(0, 5, 1.2), { Color = rgb(70, 75, 90), Material = Enum.Material.DiamondPlate })
		piece(Vector3.new(1.2, 1.2, 3), CFrame.new(1.9, 4.3, -1.1), { Color = rgb(70, 75, 90), Material = Enum.Material.Metal })
		ball(model, (base * CFrame.new(1.9, 4.3, -2.8)).Position, 0.9, glow)
	elseif id == "Corruption" then
		for index = 1, 5 do
			local angle = index / 5 * math.pi * 2
			piece(Vector3.new(0.5, 0.9, 0.2), CFrame.new(math.cos(angle) * 1.8, 7.6 + math.sin(angle * 2) * 0.4, math.sin(angle) * 1.8) * CFrame.Angles(angle, angle, 0), glow)
		end
	elseif id == "Syntax" then
		piece(Vector3.new(2.6, 1.8, 0.1), CFrame.new(0, 5.2, -2.2) * CFrame.Angles(math.rad(-10), 0, 0), { Color = accent, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false })
		piece(Vector3.new(1.4, 1, 0.1), CFrame.new(-2.4, 6.3, -1.4) * CFrame.Angles(0, math.rad(30), 0), { Color = accent, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false })
	elseif id == "Admin" then
		for index = 1, 5 do
			local angle = index / 5 * math.pi * 2
			piece(Vector3.new(0.3, 0.8, 0.3), CFrame.new(math.cos(angle) * 0.7, 8.3, math.sin(angle) * 0.7), { Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.3 })
		end
		piece(Vector3.new(0.4, 4.5, 0.4), CFrame.new(2.3, 4.6, -0.4), { Color = GOLD, Material = Enum.Material.Metal })
		piece(Vector3.new(1.8, 1.2, 1.2), CFrame.new(2.3, 7, -0.4), { Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.3 })
	end
end

local function buildStatues(folder: Instance)
	local angles = { -150, -130, -110, -90, -70, -50, -30 }
	for index, powerId in Powers.Order do
		local def = Powers.get(powerId)
		local angle = angles[index]
		if angle then
			local model = Instance.new("Model")
			model.Name = "Statue_" .. powerId
			local position = polar(angle, 55, 0)
			local base = CFrame.lookAt(position, Vector3.new(0, 0, 0))
			-- Pedestal with a nameplate facing the plaza
			local pedestal = part(model, {
				Name = "Pedestal",
				Size = Vector3.new(6, 2.4, 6),
				CFrame = base * CFrame.new(0, 1.2, 0),
				Color = rgb(70, 66, 74),
				Material = Enum.Material.Slate,
			})
			part(model, {
				Name = "Trim",
				Size = Vector3.new(6.3, 0.3, 6.3),
				CFrame = base * CFrame.new(0, 2.45, 0),
				Color = if def and def.premium then GOLD else rgb(180, 180, 190),
				Material = Enum.Material.Metal,
				Reflectance = 0.2,
			})
			if def then
				sign(pedestal, Enum.NormalId.Front, `{def.icon} {def.name}`, if def.premium then GOLD else Color3.new(1, 1, 1), 50)
				figure(model, base * CFrame.new(0, 2.6, 0), def)
				local glowPad = disc(model, (base * CFrame.new(0, 2.62, 0)).Position, 5.5, 0.05, { Color = def.colors.primary, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Transparency = 0.5 })
				light(glowPad, def.colors.primary, 12, 1)
			end
			model.Parent = folder
		end
	end
end

-- Lanterns, benches, trees and sky islands ------------------------------------------------

local function nearGate(angle: number, within: number): boolean
	for _, gate in Nexus.Gates do
		local difference = math.abs(((angle - gate.angle + 180) % 360) - 180)
		if difference < within then
			return true
		end
	end
	return false
end

local function buildLanterns(folder: Instance)
	for index = 0, 19 do
		local angle = index / 20 * 360 + 9
		if not nearGate(angle, 11) then
			local base = polar(angle, Nexus.Radius - 3, 0.7)
			column(folder, base, 9, 0.6, { Name = "LampPost", Color = IRON, Material = Enum.Material.Metal })
			part(folder, {
				Name = "LampArm",
				Size = Vector3.new(0.3, 0.3, 2.2),
				CFrame = CFrame.lookAt(base + Vector3.new(0, 9, 0), Vector3.new(0, base.Y + 9, 0)) * CFrame.new(0, 0, -1),
				Color = IRON,
				Material = Enum.Material.Metal,
			})
			local lanternAt = base + (Vector3.new(0, 0, 0) - base).Unit * 2 * Vector3.new(1, 0, 1) + Vector3.new(0, 8.3, 0)
			local glass = part(folder, {
				Name = "Lantern",
				Size = Vector3.new(1.3, 1.7, 1.3),
				CFrame = CFrame.new(lanternAt),
				Color = rgb(255, 220, 160),
				Material = Enum.Material.Glass,
				Transparency = 0.35,
				CanCollide = false,
			})
			part(folder, {
				Name = "LanternCore",
				Size = Vector3.new(0.6, 0.9, 0.6),
				CFrame = CFrame.new(lanternAt),
				Color = rgb(255, 196, 110),
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
			light(glass, rgb(255, 190, 120), 20, 1.4)
		end
	end
end

local function buildBenches(folder: Instance)
	for _, angle in { -165, -15, 25, 155, -125, -55 } do
		local position = polar(angle, 41.5, 0)
		local frame = CFrame.lookAt(position, Vector3.new(0, 0, 0))
		for _, side in { -1, 1 } do
			part(folder, { Name = "BenchLeg", Size = Vector3.new(0.5, 1.3, 1.6), CFrame = frame * CFrame.new(side * 2.3, 0.65, 0), Color = IRON, Material = Enum.Material.Metal })
		end
		part(folder, { Name = "BenchSeat", Size = Vector3.new(5.6, 0.35, 1.8), CFrame = frame * CFrame.new(0, 1.4, 0), Color = WOOD, Material = Enum.Material.Wood })
		part(folder, { Name = "BenchBack", Size = Vector3.new(5.6, 1.2, 0.3), CFrame = frame * CFrame.new(0, 2.2, 0.85) * CFrame.Angles(math.rad(-10), 0, 0), Color = WOOD, Material = Enum.Material.Wood })
	end
end

local function tree(folder: Instance, base: Vector3, height: number, leaves: Color3, random: Random)
	local model = Instance.new("Model")
	model.Name = "SpiritTree"
	local lean = CFrame.Angles(math.rad(random:NextNumber(-6, 6)), 0, math.rad(random:NextNumber(-6, 6)))
	local trunkTop = (CFrame.new(base) * lean * CFrame.new(0, height, 0)).Position
	local trunk = part(model, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 1.6, 1.6),
		CFrame = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(96, 70, 56),
		Material = Enum.Material.Wood,
	})
	local _ = trunk
	-- Branches and a crown of leaf clusters
	for index = 1, 5 do
		local angle = index / 5 * math.pi * 2 + random:NextNumber(0, 0.6)
		local offset = Vector3.new(math.cos(angle) * random:NextNumber(2.2, 3.6), random:NextNumber(-1, 2), math.sin(angle) * random:NextNumber(2.2, 3.6))
		ball(model, trunkTop + offset, random:NextNumber(5, 7.5), { Name = "Leaves", Color = leaves, Material = Enum.Material.LeafyGrass, CanCollide = false })
	end
	ball(model, trunkTop + Vector3.new(0, 2.6, 0), 7.5, { Name = "Leaves", Color = leaves:Lerp(Color3.new(1, 1, 1), 0.12), Material = Enum.Material.LeafyGrass, CanCollide = false })
	-- A few glowing spirit fruits
	for _ = 1, 3 do
		local fruit = ball(model, trunkTop + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(-2.5, 0), random:NextNumber(-3, 3)), 0.6, {
			Name = "SpiritFruit",
			Color = CYAN,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
		fruit:SetAttribute("Bob", true)
	end
	model.Parent = folder
end

local function buildTrees(folder: Instance)
	local random = Random.new(42)
	local palettes = { rgb(255, 170, 205), rgb(120, 205, 170), rgb(180, 150, 255), rgb(255, 196, 150) }
	local placed = 0
	local attempts = 0
	while placed < 22 and attempts < 200 do
		attempts += 1
		local angle = random:NextNumber(0, 360)
		local distance = random:NextNumber(Nexus.Radius + 14, 150)
		local base = polar(angle, distance, 0)
		-- Keep the walkways to the training ground and toward the arenas clear, and the pond
		local onPath = math.abs(base.Z) < 14 and (base.X < -60 or base.X > 60)
		local inPond = (base - Vector3.new(-118, 0, 118)).Magnitude < 32
		local inTraining = base.X < -60 and base.X > -125 and math.abs(base.Z) < 34
		if not nearGate(angle, 9) and not onPath and not inPond and not inTraining then
			tree(folder, base, random:NextNumber(9, 14), palettes[random:NextInteger(1, #palettes)], random)
			placed += 1
		end
	end
end

local function buildPaths(folder: Instance)
	-- Stone path west to the training hall
	for index = 0, 5 do
		local x = -Nexus.Radius - 1 - index * 1.6
		part(folder, {
			Name = "PathStone",
			Size = Vector3.new(1.4, 0.4, 10),
			CFrame = CFrame.new(x, 0.05, 0),
			Color = STONE,
			Material = Enum.Material.Pavement,
		})
	end
end

local function buildSkyIslands(folder: Instance)
	local random = Random.new(9)
	for index = 1, 7 do
		local angle = index / 7 * 360 + random:NextNumber(-15, 15)
		local center = polar(angle, random:NextNumber(190, 260), random:NextNumber(70, 130))
		if center.X < 280 then
			local model = Instance.new("Model")
			model.Name = "SkyIsland"
			local size = random:NextNumber(14, 24)
			disc(model, center, size, 2, { Name = "Top", Color = rgb(110, 170, 90), Material = Enum.Material.Grass })
			for layer = 1, 3 do
				ball(model, center - Vector3.new(0, layer * size * 0.18, 0), size * (1 - layer * 0.22), { Name = "Rock", Color = rgb(110, 100, 104), Material = Enum.Material.Slate })
			end
			tree(model, center, random:NextNumber(5, 8), rgb(255, 170, 205), random)
			model.Parent = folder
		end
	end
end

-- Builds the whole lobby into `folder`. Returns the spawn location.
function Nexus.build(folder: Instance): SpawnLocation
	buildGround(folder)
	buildPlaza(folder)
	local spawn = buildDais(folder)
	for _, gate in Nexus.Gates do
		buildGate(folder, gate)
	end
	buildStatues(folder)
	buildLanterns(folder)
	buildBenches(folder)
	buildTrees(folder)
	buildPaths(folder)
	buildSkyIslands(folder)
	return spawn :: SpawnLocation
end

return Nexus
