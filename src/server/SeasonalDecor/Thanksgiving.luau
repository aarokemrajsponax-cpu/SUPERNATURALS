-- Thanksgiving: Harvest Week, the facility's own autumn exhibition inside the atrium (World/Hub.luau).
-- No farm, no outdoor props. Four glass vitrines on steel plinths stand beside the Entrance and
-- Player Base Street gates against the wall (a copper wheat sheaf, an amber glass gourd lantern,
-- a brass cornucopia frame, a copper leaf spray), each with a label plate; eight slim banners hang
-- from the ceiling ribs at the octagon corners; a few amber flecks drift under the dome; and a
-- Harvest Week sign in the gate-sign style sits on the Entrance wall.
-- Everything is parts, anchored, with no textures or asset ids. Only the plinths collide.
-- The warm look of the atrium itself (amber key, copper bounce) comes from the season theme in
-- shared/Seasons plus the soft lamps placed here.

local rgb = Color3.fromRGB
local M = Enum.Material

-- Hub geometry (World/Hub.luau): apothem 88, local -Z points to the Lantern, +Z out, +X lateral
local R = 88

local NAVY = rgb(14, 22, 36)
local GRAPHITE = rgb(35, 39, 46)
local STEEL = rgb(138, 146, 156)
local AMBER = rgb(232, 162, 74)
local COPPER = rgb(184, 115, 63)
local BRONZE = rgb(156, 122, 78)
local DEEP_AMBER = rgb(150, 86, 30)
local DEEP_COPPER = rgb(128, 76, 46)
local TEXT = rgb(232, 238, 244)
local MUTED = rgb(150, 160, 172)
local INK = rgb(14, 20, 30)
local FONT_SANS = "rbxasset://fonts/families/BuilderSans.json"
local FONT_DISPLAY = "rbxasset://fonts/families/Michroma.json"

local GHOST = { CanCollide = false, CastShadow = false }
local SOFT = { CanCollide = false }

-- Frame at distance r from the middle along angle (degrees from +X towards +Z), like Hub.frameAt
local function frameAt(angle: number, r: number): CFrame
	local radians = math.rad(angle)
	local c, s = math.cos(radians), math.sin(radians)
	return CFrame.fromMatrix(Vector3.new(c * r, 0, s * r), Vector3.new(s, 0, -c), Vector3.new(0, 1, 0), Vector3.new(c, 0, s))
end

local function merge(base, extra)
	local out = table.clone(base)
	for key, value in extra do
		out[key] = value
	end
	return out
end

-- A box centred at (x, y, z) in frame f
local function box(Build, parent, f: CFrame, x, y, z, sx, sy, sz, color: Color3, material, extra)
	return Build.part(parent, merge(extra or SOFT, { Size = Vector3.new(sx, sy, sz), CFrame = f * CFrame.new(x, y, z), Color = color, Material = material }))
end

local function textLabel(parent: Instance, text: string, font: Font, size: number, color: Color3, pos: UDim2, area: UDim2, yAlign: Enum.TextYAlignment, xAlign: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Position = pos
	item.Size = area
	item.Text = text
	item.FontFace = font
	item.TextSize = size
	item.TextColor3 = color
	item.TextWrapped = true
	item.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	item.TextYAlignment = yAlign
	item.Parent = parent
	return item
end

local function surfaceGui(part: BasePart, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = part
	return gui
end

-- Exhibits. Each sits on the plinth top at the origin of `f` (y = top of the plinth). -----------

local function wheatSheaf(Build, model, f: CFrame)
	Build.cylinder(model, 0.12, 2.2, f * CFrame.new(0, 0.06, 0), { Color = BRONZE, Material = M.Metal, CanCollide = false })
	local height = 4.4
	for i = 1, 9 do
		local yaw = i * math.rad(40)
		local lean = if i % 3 == 0 then 0.1 else 0.24
		local dir = Vector3.new(math.sin(yaw) * math.sin(lean), math.cos(lean), math.cos(yaw) * math.sin(lean))
		local from = f * Vector3.new(0, 0.12, 0)
		local to = f * (Vector3.new(0, 0.12, 0) + dir * height)
		Build.rod(model, from, to, 0.07, { Color = if i % 2 == 0 then COPPER else BRONZE, Material = M.Metal, CanCollide = false, CastShadow = false })
		local headDir = (to - from).Unit
		Build.ellipsoid(model, Vector3.new(0.3, 0.3, 1.05), CFrame.lookAt(to - headDir * 0.2, to + headDir), { Color = if i % 2 == 0 then AMBER else COPPER, Material = M.Metal, CanCollide = false, CastShadow = false })
	end
	Build.cylinder(model, 0.35, 0.95, f * CFrame.new(0, 1.35, 0), { Color = BRONZE, Material = M.Metal, CanCollide = false, CastShadow = false })
end

local function gourdLantern(Build, model, f: CFrame)
	Build.cylinder(model, 0.25, 1.9, f * CFrame.new(0, 0.125, 0), { Color = BRONZE, Material = M.Metal, CanCollide = false })
	local center = f * CFrame.new(0, 1.65, 0)
	for i = 0, 2 do
		Build.ellipsoid(model, Vector3.new(2.5, 2.7, 1.5), center * CFrame.Angles(0, math.rad(i * 60), 0), {
			Color = AMBER,
			Material = M.Glass,
			Transparency = 0.4,
			Reflectance = 0.1,
			CanCollide = false,
			CastShadow = false,
		})
	end
	local core = Build.ball(model, 0.9, center, { Color = rgb(255, 196, 110), Material = M.Neon, CanCollide = false, CastShadow = false })
	Build.light(core, rgb(255, 184, 100), 14, 0.8, false)
	Build.cylinder(model, 0.5, 0.3, f * CFrame.new(0, 3.2, 0) * CFrame.Angles(0.15, 0, 0.1), { Color = BRONZE, Material = M.Metal, CanCollide = false, CastShadow = false })
	Build.cylinder(model, 0.12, 1.0, f * CFrame.new(0, 2.95, 0), { Color = COPPER, Material = M.Metal, CanCollide = false, CastShadow = false })
end

local function cornucopia(Build, model, f: CFrame)
	-- A horn drawn as a bronze lattice: stations along a curve in the local X/Y plane, four rods round each
	local stations = {}
	local count = 7
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local position = Vector3.new(-1.7 + 3.1 * t, 0.5 + 3.2 * t ^ 1.7, 0)
		local ahead = Vector3.new(-1.7 + 3.1 * math.min(t + 0.02, 1), 0.5 + 3.2 * math.min(t + 0.02, 1) ^ 1.7, 0)
		local tangent = (ahead - position).Unit
		if i == count - 1 then
			tangent = stations[i].tangent
		end
		table.insert(stations, { position = position, tangent = tangent, radius = 0.1 + 0.95 * t ^ 1.2 })
	end
	local function ringPoint(station, k: number): Vector3
		local b1 = Vector3.new(0, 0, 1)
		local b2 = station.tangent:Cross(b1)
		local phi = k * math.pi / 2 + 0.4
		return f * (station.position + (b1 * math.cos(phi) + b2 * math.sin(phi)) * station.radius)
	end
	local thin = { Color = BRONZE, Material = M.Metal, CanCollide = false, CastShadow = false }
	for i = 1, count - 1 do
		for k = 0, 3 do
			Build.rod(model, ringPoint(stations[i], k), ringPoint(stations[i + 1], k), 0.07, thin)
		end
	end
	local mouth = stations[count]
	for k = 0, 3 do
		Build.rod(model, ringPoint(mouth, k), ringPoint(mouth, (k + 1) % 4), 0.08, { Color = COPPER, Material = M.Metal, CanCollide = false, CastShadow = false })
	end
	-- Amber glass spilling from the mouth, and three copper leaves
	local glassBalls = { { 0.1, 0.1, 0.2, 0.7 }, { -0.35, -0.1, -0.3, 0.6 }, { 0.5, -0.2, 0.3, 0.55 }, { 0.15, -0.55, -0.1, 0.5 } }
	for _, ball in glassBalls do
		Build.ball(model, ball[4], CFrame.new(f * (mouth.position + Vector3.new(ball[1], ball[2], ball[3]))), { Color = AMBER, Material = M.Glass, Transparency = 0.3, CanCollide = false, CastShadow = false })
	end
	for i, dir in { Vector3.new(0.9, 0.3, 0.5), Vector3.new(1, -0.1, -0.5), Vector3.new(0.6, 0.6, 0) } do
		local at = f * (mouth.position + Vector3.new(0.4, 0.1, 0) + dir * 0.4)
		Build.ellipsoid(model, Vector3.new(0.45, 0.08, 1.4), CFrame.lookAt(at, at + f:VectorToWorldSpace(dir)), { Color = if i == 2 then BRONZE else COPPER, Material = M.Metal, CanCollide = false, CastShadow = false })
	end
	-- Foot
	Build.cylinder(model, 0.25, 1.4, f * CFrame.new(-1.2, 0.125, 0), { Color = BRONZE, Material = M.Metal, CanCollide = false })
end

local function leafSpray(Build, model, f: CFrame)
	Build.cylinder(model, 0.12, 2.0, f * CFrame.new(0, 0.06, 0), { Color = BRONZE, Material = M.Metal, CanCollide = false })
	local top = Vector3.new(0.2, 4.4, 0)
	Build.rod(model, f * Vector3.new(0, 0.1, 0), f * top, 0.1, { Color = BRONZE, Material = M.Metal, CanCollide = false, CastShadow = false })
	local colors = { COPPER, AMBER, BRONZE }
	for i = 1, 6 do
		local y = 1.2 + i * 0.5
		local side = if i % 2 == 0 then 1 else -1
		local dir = Vector3.new(side * 0.8, 0.55, if i % 3 == 0 then 0.3 else -0.2).Unit
		local base = Vector3.new(0.2 * y / 4.4, y, 0)
		local mid = f * (base + dir * 0.8)
		Build.ellipsoid(model, Vector3.new(0.7, 0.07, 1.7), CFrame.lookAt(mid, mid + f:VectorToWorldSpace(dir)), { Color = colors[i % 3 + 1], Material = M.Metal, CanCollide = false, CastShadow = false })
	end
	local tip = f * (top + Vector3.new(0, 0.5, 0))
	Build.ellipsoid(model, Vector3.new(0.7, 0.07, 1.7), CFrame.lookAt(tip, tip + Vector3.new(0, 1, 0)), { Color = AMBER, Material = M.Metal, CanCollide = false, CastShadow = false })
end

local EXHIBITS = {
	wheat = { build = wheatSheaf, title = "COPPER WHEAT" },
	gourd = { build = gourdLantern, title = "EMBER GOURD" },
	horn = { build = cornucopia, title = "BRASS CORNUCOPIA" },
	spray = { build = leafSpray, title = "LEAF SPRAY" },
}

-- A vitrine against the wall beside a gate: steel plinth, label plate, glass case with a warm cap.
local function vitrine(Build, folder, angle: number, lateral: number, exhibit)
	local model = Build.model(folder, "Vitrine_" .. exhibit.title)
	local f = frameAt(angle, R) * CFrame.new(lateral, 0, -3.0) -- 5 wide, 4.4 deep, backed on the wall
	-- Plinth: graphite body (the only collidable piece), steel foot and cap, a copper reveal
	box(Build, model, f, 0, 1.3, 0, 4.8, 2.6, 4.2, GRAPHITE, M.Metal, { CanCollide = true })
	box(Build, model, f, 0, 0.12, 0, 5.2, 0.24, 4.6, STEEL, M.Metal, merge(SOFT, { CastShadow = false }))
	box(Build, model, f, 0, 2.72, 0, 5.1, 0.26, 4.5, STEEL, M.Metal, SOFT)
	box(Build, model, f, 0, 2.2, -2.12, 4.4, 0.08, 0.06, COPPER, M.Metal, GHOST)
	-- Label plate in the facility sign style
	local plate = box(Build, model, f, 0, 1.3, -2.14, 4.2, 1.1, 0.08, NAVY, M.SmoothPlastic, GHOST)
	local gui = surfaceGui(plate, 60)
	textLabel(gui, exhibit.title, Font.new(FONT_DISPLAY), 18, TEXT, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.42), Enum.TextYAlignment.Bottom)
	textLabel(gui, "Harvest Week exhibit", Font.new(FONT_SANS, Enum.FontWeight.Medium), 16, MUTED, UDim2.fromScale(0.05, 0.58), UDim2.fromScale(0.9, 0.3), Enum.TextYAlignment.Top)
	box(Build, model, f, -2.0, 1.3, -2.19, 0.06, 0.8, 0.02, AMBER, M.Neon, GHOST)

	-- Glass case
	local top = 2.85
	box(Build, model, f, 0, top + 3.2, 0, 4.4, 6.4, 3.8, rgb(255, 214, 160), M.Glass, { CanCollide = false, CastShadow = false, Transparency = 0.93 })
	box(Build, model, f, 0, top + 3.2, 1.85, 4.4, 6.4, 0.1, rgb(20, 24, 32), M.SmoothPlastic, GHOST)
	for _, x in { -2.2, 2.2 } do
		for _, z in { -1.9, 1.9 } do
			box(Build, model, f, x, top + 3.2, z, 0.16, 6.4, 0.16, STEEL, M.Metal, GHOST)
		end
	end
	box(Build, model, f, 0, top + 6.5, 0, 4.7, 0.25, 4.1, STEEL, M.Metal, GHOST)
	local glow = box(Build, model, f, 0, top + 6.34, 0, 3.6, 0.06, 3.0, AMBER, M.Neon, merge(GHOST, { Transparency = 0.25 }))
	Build.light(glow, rgb(255, 190, 120), 18, 0.9, false)

	exhibit.build(Build, model, f * CFrame.new(0, top + 0.02, 0))
end

-- A tall slim banner under a ceiling rib, with a leaf drawn from a rotated square and fine veins.
local function banner(Build, folder, angle: number, deep: Color3, leaf: Color3)
	local model = Build.model(folder, "Banner")
	local f = frameAt(angle, 82)
	local vein = rgb(96, 62, 30)
	box(Build, model, f, 0, 44.1, 0, 4.8, 0.2, 0.2, BRONZE, M.Metal, GHOST).Shape = Enum.PartType.Cylinder
	for _, x in { -1.4, 1.4 } do
		box(Build, model, f, x, 44.35, 0, 0.06, 0.4, 0.06, STEEL, M.Metal, GHOST)
	end
	box(Build, model, f, 0, 35.6, 0, 4.2, 16.9, 0.1, deep, M.Fabric, GHOST)
	for _, x in { -1.95, 1.95 } do
		box(Build, model, f, x, 35.6, -0.07, 0.1, 16.9, 0.05, BRONZE, M.Metal, GHOST)
	end
	box(Build, model, f, 0, 27.1, -0.05, 4.5, 0.22, 0.3, BRONZE, M.Metal, GHOST)
	-- Leaf: a square turned 45 degrees, a central vein with a short stem, four side veins
	local leafPart = box(Build, model, f, 0, 38.6, -0.1, 2.5, 2.5, 0.05, leaf, M.Metal, GHOST)
	leafPart.CFrame = leafPart.CFrame * CFrame.Angles(0, 0, math.pi / 4)
	box(Build, model, f, 0, 37.2, -0.14, 0.1, 4.2, 0.03, vein, M.Metal, GHOST)
	for _, y in { 38.2, 39.0 } do
		for _, side in { -1, 1 } do
			local v = box(Build, model, f, side * 0.36, y, -0.14, 0.07, 0.9, 0.03, vein, M.Metal, GHOST)
			v.CFrame = v.CFrame * CFrame.Angles(0, 0, side * math.rad(-48))
		end
	end
end

-- Harvest Week sign, same face as the gate signs: wayfinding tile, Michroma title, sans subtitle
local function harvestSign(Build, folder)
	local model = Build.model(folder, "HarvestWeekSign")
	local f = frameAt(90, R) * CFrame.new(26, 0, 0)
	local plate = box(Build, model, f, 0, 12.5, -0.5, 15, 5, 0.4, NAVY, M.SmoothPlastic, { CastShadow = false })
	box(Build, model, f, 0, 9.85, -0.6, 15.4, 0.3, 0.5, STEEL, M.Metal, GHOST)
	box(Build, model, f, 0, 15.15, -0.6, 15.4, 0.3, 0.5, STEEL, M.Metal, GHOST)
	local px = Vector2.new(720, 240)
	local gui = surfaceGui(plate, 48)
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.BorderSizePixel = 0
	tile.BackgroundColor3 = AMBER
	tile.Position = UDim2.fromScale(28 / px.X, 40 / px.Y)
	tile.Size = UDim2.fromScale(136 / px.X, 160 / px.Y)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 6)
	round.Parent = tile
	tile.Parent = gui
	textLabel(tile, "HW", Font.new(FONT_DISPLAY), 40, INK, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextYAlignment.Center, Enum.TextXAlignment.Center)
	textLabel(gui, "HARVEST WEEK", Font.new(FONT_DISPLAY), 38, TEXT, UDim2.fromScale(196 / px.X, 28 / px.Y), UDim2.fromScale(496 / px.X, 104 / px.Y), Enum.TextYAlignment.Bottom)
	local dash = Instance.new("Frame")
	dash.BorderSizePixel = 0
	dash.BackgroundColor3 = AMBER
	dash.Position = UDim2.fromScale(196 / px.X, 146 / px.Y)
	dash.Size = UDim2.fromScale(56 / px.X, 4 / px.Y)
	dash.Parent = gui
	textLabel(gui, "Autumn look and Thanksgiving events", Font.new(FONT_SANS, Enum.FontWeight.Medium), 26, MUTED, UDim2.fromScale(196 / px.X, 162 / px.Y), UDim2.fromScale(496 / px.X, 56 / px.Y), Enum.TextYAlignment.Top)
	local lamp = box(Build, model, f, 0, 16.2, -1.2, 0.4, 0.4, 0.4, AMBER, M.Neon, merge(GHOST, { Transparency = 1 }))
	Build.light(lamp, rgb(255, 196, 130), 16, 0.7, false)
end

-- A slow drift of amber flecks from under the glass roof. No texture is set.
local function drift(Build, folder)
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		local holder = Build.part(folder, {
			Name = "LeafDrift",
			Size = Vector3.new(26, 0.5, 26),
			CFrame = CFrame.new(math.cos(angle) * 30, 68, math.sin(angle) * 30),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 1.5
		emitter.Lifetime = NumberRange.new(20, 26)
		emitter.Speed = NumberRange.new(1.5, 2.5)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.Acceleration = Vector3.new(0.3, 0, 0.2)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Size = NumberSequence.new(0.5)
		emitter.Color = ColorSequence.new(AMBER, COPPER)
		emitter.LightEmission = 0.35
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.35), NumberSequenceKeypoint.new(0.85, 0.45), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = holder
	end
end

return function(folder: Folder, Build)
	-- Vitrines beside the Entrance (90) and Player Base Street (-90) gates, clear of the doorways
	vitrine(Build, folder, 90, -13, EXHIBITS.wheat)
	vitrine(Build, folder, 90, 13, EXHIBITS.gourd)
	vitrine(Build, folder, -90, -13, EXHIBITS.horn)
	vitrine(Build, folder, -90, 13, EXHIBITS.spray)

	-- Banners at the eight corners, alternating deep amber and copper
	for index = 0, 7 do
		if index % 2 == 0 then
			banner(Build, folder, 22.5 + index * 45, DEEP_AMBER, rgb(238, 178, 94))
		else
			banner(Build, folder, 22.5 + index * 45, DEEP_COPPER, rgb(222, 168, 112))
		end
		-- Copper bounce: a soft lamp above each corner
		local f = frameAt(22.5 + index * 45, 76)
		local holder = Build.part(folder, { Name = "CopperBounce", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = f * CFrame.new(0, 34, 0), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
		Build.light(holder, rgb(224, 140, 78), 38, 0.5, false)
	end

	harvestSign(Build, folder)
	drift(Build, folder)
end
