-- Exports a built scene (parts, lights, particles, beams, terrain fills and the
-- lighting setup) as JSON for render3d.py, so builds can be looked at without
-- Studio. It starts the real server services in the stand-in engine, so the
-- lobby, arenas and bases are built by the same code the game runs.
--
-- Usage (from the repository root):
--   lune run tools/preview/dump3d.luau <place.rbxl> <scene> <out.json> [setup.luau]
-- Scenes:
--   nexus             the lobby around the origin
--   training          the training ground
--   arena:<id>        reserves an arena of that theme (or "arena" for the default)
--   path:<a.b.c>      any instance by path after the server started (e.g. path:Workspace.Nexus)
--   setup             runs setup.luau: it gets `api` (tests/smoke/World) and returns the
--                     instance(s) to export, optionally with { cameras = {...} }
-- Lighting always comes from the place, after the services started.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox") :: any
local Vector3 = roblox.Vector3

local World = require("../../tests/smoke/World")

local placePath, scene, outPath, setupPath = process.args[1], process.args[2], process.args[3], process.args[4]
assert(placePath and scene and outPath, "usage: dump3d.luau <place.rbxl> <scene> <out.json> [setup.luau]")

local api = World.start(placePath)
local world = api.world
local services = api.services
local Engine = api.Engine
local workspace = world.workspace

local function get(item, prop)
	local ok, value = pcall(function()
		return item[prop]
	end)
	return if ok then value else nil
end

local function rgb(c)
	if typeof(c) ~= "Color3" then
		return nil
	end
	return { c.R, c.G, c.B }
end

local function cf(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function v3(v)
	return { v.X, v.Y, v.Z }
end

local function enumName(v)
	return if typeof(v) == "EnumItem" then v.Name else nil
end

-- Where a light, emitter or attachment sits in the world
local function worldPosition(item): Vector3?
	local parent = item.Parent
	if not parent then
		return nil
	end
	if parent:IsA("Attachment") then
		local part = parent.Parent
		if part and part:IsA("BasePart") then
			return (part.CFrame * parent.CFrame).Position
		end
		return nil
	elseif parent:IsA("BasePart") then
		return parent.CFrame.Position
	end
	return nil
end

local function attachmentPosition(attachment): Vector3?
	if not attachment or not attachment:IsA("Attachment") then
		return nil
	end
	local part = attachment.Parent
	if part and part:IsA("BasePart") then
		return (part.CFrame * attachment.CFrame).Position
	end
	return nil
end

local function sequenceColor(sequence)
	if typeof(sequence) == "ColorSequence" then
		return rgb(sequence.Keypoints[1].Value)
	elseif typeof(sequence) == "Color3" then
		return rgb(sequence)
	end
	return { 1, 1, 1 }
end

local function sequenceNumber(sequence, default)
	if typeof(sequence) == "NumberSequence" then
		return sequence.Keypoints[1].Value
	elseif type(sequence) == "number" then
		return sequence
	end
	return default
end

local out = { parts = {}, lights = {}, particles = {}, beams = {}, terrain = {}, texts = {}, cameras = {} }

local function exportPart(part)
	local transparency = get(part, "Transparency") or 0
	if transparency >= 0.98 then
		return
	end
	local shape = "Block"
	if part:IsA("WedgePart") then
		shape = "Wedge"
	elseif part:IsA("CornerWedgePart") then
		shape = "CornerWedge"
	elseif part:IsA("Part") then
		shape = enumName(get(part, "Shape")) or "Block"
	elseif part:IsA("MeshPart") then
		shape = "Block"
	end
	table.insert(out.parts, {
		name = part.Name,
		shape = shape,
		cf = cf(part.CFrame),
		size = v3(part.Size),
		color = rgb(part.Color),
		material = enumName(part.Material) or "Plastic",
		transparency = transparency,
		reflectance = get(part, "Reflectance") or 0,
		shadow = get(part, "CastShadow") ~= false,
	})
end

local function export(root)
	local items = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(items, root)
	end
	for _, item in items do
		if item:IsA("BasePart") then
			if item:IsA("Terrain") then
				continue
			end
			exportPart(item)
		elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			local position = worldPosition(item)
			if position and get(item, "Enabled") ~= false then
				local entry: any = {
					kind = item.ClassName,
					position = v3(position),
					color = rgb(item.Color),
					brightness = get(item, "Brightness") or 1,
					range = get(item, "Range") or 8,
					shadows = get(item, "Shadows") == true,
				}
				local parent = item.Parent
				if parent:IsA("BasePart") and not item:IsA("PointLight") then
					entry.face = enumName(get(item, "Face"))
					entry.angle = get(item, "Angle")
					entry.cf = cf(parent.CFrame)
					entry.size = v3(parent.Size)
				end
				table.insert(out.lights, entry)
			end
		elseif item:IsA("ParticleEmitter") then
			local position = worldPosition(item)
			if position and get(item, "Enabled") ~= false then
				table.insert(out.particles, {
					position = v3(position),
					color = sequenceColor(get(item, "Color")),
					size = sequenceNumber(get(item, "Size"), 1),
					rate = get(item, "Rate") or 5,
					lightEmission = get(item, "LightEmission") or 0,
					transparency = sequenceNumber(get(item, "Transparency"), 0),
				})
			end
		elseif item:IsA("Beam") then
			local a, b = attachmentPosition(get(item, "Attachment0")), attachmentPosition(get(item, "Attachment1"))
			if a and b and get(item, "Enabled") ~= false then
				table.insert(out.beams, {
					a = v3(a),
					b = v3(b),
					color = sequenceColor(get(item, "Color")),
					width = ((get(item, "Width0") or 1) + (get(item, "Width1") or 1)) / 2,
					lightEmission = get(item, "LightEmission") or 0,
					transparency = sequenceNumber(get(item, "Transparency"), 0),
				})
			end
		elseif (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" then
			-- Signs: SurfaceGui / BillboardGui text, placed at their part or attachment
			local gui = item:FindFirstAncestorWhichIsA("SurfaceGui") or item:FindFirstAncestorWhichIsA("BillboardGui")
			if gui then
				local adornee = get(gui, "Adornee") or gui.Parent
				local position = nil
				if adornee and adornee:IsA("BasePart") then
					position = adornee.CFrame.Position
				elseif adornee and adornee:IsA("Attachment") then
					position = attachmentPosition(adornee)
				end
				if position then
					table.insert(out.texts, { text = item.Text, position = v3(position), color = rgb(item.TextColor3) })
				end
			end
		end
	end
end

-- Pick the scene ---------------------------------------------------------------------

local roots = {}
if scene == "nexus" then
	table.insert(roots, workspace:FindFirstChild("Nexus") or workspace)
elseif scene == "training" then
	local found = nil
	for _, item in workspace:GetDescendants() do
		if string.find(item.Name, "Training") and (item:IsA("Model") or item:IsA("Folder")) then
			found = item
			break
		end
	end
	table.insert(roots, found or error("no training ground found"))
elseif string.sub(scene, 1, 5) == "arena" then
	local id = string.match(scene, "^arena:(.+)$")
	local arena = services.ArenaService:reserve(id)
	assert(arena, "no free arena slot")
	table.insert(roots, arena.model)
	-- Look from a spawn toward the centre, and from high above a corner
	if arena.spawns and arena.spawns[1] and arena.center then
		local spawn = arena.spawns[1].Position
		local center = arena.center
		table.insert(out.cameras, { name = "spawn", position = v3(spawn + Vector3.new(0, 6, 0) + (spawn - center).Unit * 8), target = v3(center + Vector3.new(0, 3, 0)), fov = 70 })
	end
elseif string.sub(scene, 1, 5) == "path:" then
	table.insert(roots, world.find(string.sub(scene, 6)))
elseif scene == "setup" then
	assert(setupPath, "the setup scene needs a setup.luau path")
	local env = setmetatable({ api = api, Vector3 = roblox.Vector3, CFrame = roblox.CFrame, Color3 = roblox.Color3, Enum = roblox.Enum, Instance = world.Instance, workspace = workspace }, { __index = getfenv(0) })
	local chunk = luau.load(fs.readFile(setupPath), { debugName = setupPath, environment = env })
	local result = chunk()
	if typeof(result) == "Instance" then
		table.insert(roots, result)
	elseif type(result) == "table" then
		for _, item in result.roots or result do
			if typeof(item) == "Instance" then
				table.insert(roots, item)
			end
		end
		for _, camera in result.cameras or {} do
			table.insert(out.cameras, { name = camera.name, position = v3(camera.position), target = v3(camera.target), fov = camera.fov or 70 })
		end
	end
else
	error("unknown scene " .. scene)
end

-- Let anything that builds over a few frames finish
api.task.wait(0.3)
for _, root in roots do
	export(root)
end

for _, op in Engine.terrainOps do
	local entry: any = { kind = op.kind, material = enumName(op.material) or "Grass" }
	if op.cframe then
		entry.cf = cf(op.cframe)
	end
	if op.size then
		entry.size = v3(op.size)
	end
	if op.center then
		entry.center = v3(op.center)
	end
	entry.radius = op.radius
	entry.height = op.height
	table.insert(out.terrain, entry)
end
out.terrainColors = {}
for name, color in Engine.terrainColors do
	out.terrainColors[name] = rgb(color)
end
local terrain = workspace:FindFirstChildOfClass("Terrain")
if terrain then
	out.water = { color = rgb(get(terrain, "WaterColor")), transparency = get(terrain, "WaterTransparency"), reflectance = get(terrain, "WaterReflectance") }
end

-- Lighting and post effects
local lighting = world.game:GetService("Lighting")
out.lighting = {
	ambient = rgb(get(lighting, "Ambient")),
	outdoorAmbient = rgb(get(lighting, "OutdoorAmbient")),
	brightness = get(lighting, "Brightness"),
	clockTime = get(lighting, "ClockTime"),
	latitude = get(lighting, "GeographicLatitude") or 41.7,
	exposure = get(lighting, "ExposureCompensation") or 0,
	colorShiftTop = rgb(get(lighting, "ColorShift_Top")),
	diffuseScale = get(lighting, "EnvironmentDiffuseScale") or 0,
	specularScale = get(lighting, "EnvironmentSpecularScale") or 0,
	fogColor = rgb(get(lighting, "FogColor")),
	fogEnd = get(lighting, "FogEnd") or 100000,
	fogStart = get(lighting, "FogStart") or 0,
}
for _, effect in lighting:GetChildren() do
	if effect:IsA("Atmosphere") then
		out.atmosphere = { density = effect.Density, offset = effect.Offset, color = rgb(effect.Color), decay = rgb(effect.Decay), glare = effect.Glare, haze = effect.Haze }
	elseif effect:IsA("BloomEffect") and effect.Enabled then
		out.bloom = { intensity = effect.Intensity, size = effect.Size, threshold = effect.Threshold }
	elseif effect:IsA("ColorCorrectionEffect") and effect.Enabled then
		out.colorCorrection = out.colorCorrection or {}
		table.insert(out.colorCorrection, { brightness = effect.Brightness, contrast = effect.Contrast, saturation = effect.Saturation, tint = rgb(effect.TintColor) })
	elseif effect:IsA("SunRaysEffect") and effect.Enabled then
		out.sunRays = { intensity = effect.Intensity, spread = effect.Spread }
	end
end

fs.writeFile(outPath, serde.encode("json", out))
print(`exported {#out.parts} parts, {#out.lights} lights, {#out.particles} emitters, {#out.beams} beams, {#out.terrain} terrain fills to {outPath}`)
api.stop()
process.exit(0)
