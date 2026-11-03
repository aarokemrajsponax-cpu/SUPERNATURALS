-- THE SPECTATING LOUNGE: the facility's third home, behind the hub's SPECTATING LOUNGE door
-- (docs/ArtDirection.md sections 2, 3, 6; MASTER_REQUIREMENTS P.S. 13.0 and 16.0 section 2).
-- Reached with "Travel:Lounge" (MatchService teleports to LoungeService:spawnCFrame). It is
-- built from scratch from the design philosophy of reference image 15: deep navy and charcoal
-- surfaces, walnut wall panels with bronze reveals, warm amber coves, copper and bronze
-- accents, a dark reflective floor, a glass ceiling section, and cyan on screens only.
--
-- Plan, 100 x 76 studs, 24 high, centre Lounge.Center (x east, z south, local metres below):
--   north wall   the viewing wall: a big match screen (centre), the MATCHES list (left) and the
--                PREDICTION BOARD (right), each with a low console and Watch / Pick prompts
--   centre       seating cluster: round table, a three-seat sofa, two armchairs, two poufs, rug
--   x = -30, 30  two smaller clusters (table, sofa, two armchairs), facing the wall
--   west         THE FOUNDERS' ARCHIVE: three tall holographic chapter panels, four framed
--                exhibit images, four artifacts in glass cases, a lectern that opens the book
--   east         the refreshments counter shell (stools, back bar, menu panel), and a small
--                shop kiosk by the south-east corner that opens Window:Market
--   corners      two quiet corners (north-east, south-west) with armchairs, a table and a lamp
--   south wall   a sealed glass door with a "Return to hub" prompt; arrivals stand just inside
--   ceiling      slab with a glazed opening over the central cluster, an amber cove round it
--                and round the room, steel mullions
--
-- WHERE THINGS ARE ATTACHED (read this before extending the room)
--   Refreshments (a later system): Model "RefreshmentsCounter" holds the Part
--   "RefreshmentsAttachment" (invisible, anchored, in front of the counter). It carries the
--   attributes Station = "Refreshments" and Facing. Parent a ProximityPrompt or the menu logic
--   to it. The menu panel "RefreshmentsMenu" (SurfaceGui, label "Status") is a placeholder.
--   Founders' Archive images: Lounge.ExhibitImages below. Put the Roblox image asset id (a
--   number, from an upload the owner makes) next to each key. While an id is 0 the frame stays
--   empty, and only in Studio does it show a tasteful "Exhibit image pending" plate.
--   Seasonal decoration: Lounge.spots() gives world positions (tables, the wall, the counter)
--   for SeasonalDecor/LoungeSet.
--
-- Live screens are TextLabels inside SurfaceGuis. Lounge.refresh(view) is called by
-- LoungeService when a match event happens (never per frame), and it writes a label only when
-- its text actually changed. `view` is documented at refresh.
-- Prompts the client reads (WorldFxController) carry the attribute Action ("Window:Market",
-- "Window:Archive", "Travel:Lobby"). Watch and Pick prompts call the hooks instead.
-- Part budget: Lounge.PartBudget (about 480 in practice). Nothing here moves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Archive = require(ReplicatedStorage.Shared.Content.Archive)
local Common = require(script.Parent.Parent.Arenas.Common)

local Lounge = {}

Lounge.Center = Vector3.new(0, 0, 700)
Lounge.PartBudget = 620
Lounge.WatchPads = 4

-- Owner uploads: image asset ids for the four Founders' Archive frames (0 = not uploaded yet).
-- Subjects are limited to what the Archive canon supports.
Lounge.ExhibitImages = {
	KestrelValley = 0, -- Kestrel Valley before the station was built (Field Notes, Kestrel Valley)
	FirstLight = 0, -- the first activation of the energy systems (First Light)
	TheCascade = 0, -- the incident in the Programme Files (Incident Report: The Cascade)
	DoorInTheHill = 0, -- the door in the hill (The Door in the Hill)
}

local M = Common.M
local rgb = Common.rgb
local GHOST = Common.GHOST

local NAVY = rgb(14, 22, 36)
local NAVY_SOFT = rgb(40, 56, 84)
local CHARCOAL = rgb(30, 33, 38)
local GRAPHITE = rgb(35, 39, 46)
local FLOOR = rgb(26, 29, 35)
local SEAM = rgb(12, 13, 16)
local STEEL = rgb(138, 146, 156)
local WALNUT = rgb(72, 50, 38)
local COPPER = rgb(184, 115, 63)
local BRONZE = rgb(156, 122, 78)
local AMBER = rgb(232, 162, 74)
local EMBER = rgb(226, 124, 58)
local WARM = rgb(255, 214, 166)
local CYAN = rgb(63, 214, 232)
local TEXT = rgb(232, 238, 244)
local MUTED = rgb(150, 160, 172)
local COGNAC = rgb(128, 82, 54)
local SLATE_BLUE = rgb(62, 78, 108)
local MARBLE = rgb(34, 36, 42)
local IVORY = rgb(222, 214, 198)

local FONT = "rbxasset://fonts/families/BuilderSans.json"

-- Geometry (local studs). The interior is x in [-HX, HX], z in [-HZ, HZ]
local HX, HZ, HEIGHT = 50, 38, 24
local FLOOR_Y = 1

-- Table tops and other spots seasons may dress (local positions, y above the floor)
local TABLES = {
	{ name = "Centre", x = 0, z = -4, diameter = 6.4 },
	{ name = "West", x = -30, z = 8, diameter = 5 },
	{ name = "East", x = 30, z = 8, diameter = 5 },
	{ name = "SouthWest", x = -43, z = 31, diameter = 3.4 },
	{ name = "NorthEast", x = 44, z = -28.5, diameter = 3.4 },
}
local TABLE_TOP = 1.7

local function world(x: number, y: number, z: number): Vector3
	return Lounge.Center + Vector3.new(x, FLOOR_Y + y, z)
end

-- World positions the seasonal set decorates
function Lounge.spots()
	local tables = {}
	for _, spot in TABLES do
		table.insert(tables, { name = spot.name, position = world(spot.x, TABLE_TOP + 0.2, spot.z), diameter = spot.diameter })
	end
	return {
		tables = tables,
		wallTop = world(0, 17, -HZ + 1),
		counterTop = world(44, 3.8, -7),
		door = world(0, 11, HZ - 1),
		glass = world(0, HEIGHT, -6),
	}
end

-- Text helpers -------------------------------------------------------------------------------------

local function newLabel(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3, bold: boolean?, align: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(w, h)
	item.Text = text
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = align or Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.FontFace = Font.new(FONT, if bold then Enum.FontWeight.Bold else Enum.FontWeight.Medium)
	item.Parent = parent
	return item
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function setVisible(item: GuiObject?, visible: boolean)
	if item and item.Visible ~= visible then
		item.Visible = visible
	end
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function plural(count: number, one: string, many: string): string
	return `{count} {if count == 1 then one else many}`
end

local function clip(text: string, length: number): string
	if #text > length then
		return string.sub(text, 1, length - 3) .. "..."
	end
	return text
end

-- Removes the Archive's inline markup for a short excerpt: redactions stay hidden
local function plain(text: string): string
	text = string.gsub(text, "{{.-}}", "[redacted]")
	text = string.gsub(text, "%*", "")
	return text
end

local function excerptOf(id: string, limit: number): (string, string)
	for _, chapter in Archive.Chapters do
		if chapter.id == id then
			for _, block in chapter.blocks do
				if typeof(block) == "string" and #block > 40 then
					local text = plain(block)
					if #text > limit then
						local cut = string.sub(text, 1, limit)
						local stop = string.match(cut, "^(.*[%.%?!])%s") or string.match(cut, "^(.*)%s%S*$") or cut
						text = stop .. (if string.match(stop, "[%.%?!]$") then "" else "...")
					end
					return chapter.title, text
				end
			end
			-- Logs and printouts have no prose: use their first lines, spacing collapsed
			for _, block in chapter.blocks do
				if typeof(block) == "table" and block.lines then
					local picked = {}
					for _, line in block.lines do
						local text = string.gsub(plain(line), "%s+", " ")
						if #text > 4 and #picked < 3 then
							table.insert(picked, text)
						end
					end
					return chapter.title, clip(table.concat(picked, " / "), limit)
				end
			end
			return chapter.title, ""
		end
	end
	return id, ""
end

-- Build ----------------------------------------------------------------------------------------------

export type Hooks = {
	-- A player pressed Watch on pad `index` (1 to Lounge.WatchPads)
	watch: (player: Player, index: number) -> (),
	-- A player pressed Pick on the prediction board: side 1 (fighter A) or 2 (fighter B)
	predict: (player: Player, side: number) -> (),
}

export type Built = {
	model: Model,
	spawn: CFrame,
	refresh: (view: any) -> (),
}

function Lounge.build(parent: Instance, hooks: Hooks): Built
	local model = Instance.new("Model")
	model.Name = "Lounge"
	local c = Vector3.new(Lounge.Center.X, FLOOR_Y, Lounge.Center.Z)

	local function at(x: number, y: number, z: number): Vector3
		return c + Vector3.new(x, y, z)
	end
	local function block(group: Instance, name: string, size: Vector3, where: Vector3 | CFrame, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
		local frame = if typeof(where) == "CFrame" then where else CFrame.new(where)
		return Common.block(group, name, size, frame, color, material, extra)
	end
	local function group(name: string, parentGroup: Instance?): Model
		local item = Instance.new("Model")
		item.Name = name
		item.Parent = parentGroup or model
		return item
	end
	local function strip(parentGroup: Instance, name: string, size: Vector3, where: Vector3 | CFrame, color: Color3): BasePart
		return block(parentGroup, name, size, where, color, M.Neon, GHOST)
	end
	local function prompt(owner: Instance, actionText: string, objectText: string, distance: number, action: string?): ProximityPrompt
		local item = Instance.new("ProximityPrompt")
		item.ActionText = actionText
		item.ObjectText = objectText
		item.HoldDuration = 0
		item.MaxActivationDistance = distance
		item.RequiresLineOfSight = false
		-- E, F, Q and the gamepad face buttons are combat keys, so the world uses T / D-pad right
		item.KeyboardKeyCode = Enum.KeyCode.T
		item.GamepadKeyCode = Enum.KeyCode.DPadRight
		if action then
			item:SetAttribute("Action", action)
		end
		item.Parent = owner
		return item
	end
	local function lightOn(owner: BasePart, color: Color3, range: number, brightness: number)
		Common.light(owner, color, range, brightness, false)
	end

	-- Shell ----------------------------------------------------------------------------------------
	local shell = group("Shell")
	block(shell, "Floor", Vector3.new(HX * 2 + 8, 4, HZ * 2 + 8), at(0, -2, 0), FLOOR, M.Slate, { Reflectance = 0.12 })
	for index = -3, 3 do
		block(shell, "SeamX", Vector3.new(0.15, 0.06, HZ * 2), at(index * 14, 0.03, 0), SEAM, M.SmoothPlastic, GHOST)
	end
	for index = -2, 2 do
		block(shell, "SeamZ", Vector3.new(HX * 2, 0.06, 0.15), at(0, 0.03, index * 15), SEAM, M.SmoothPlastic, GHOST)
	end
	-- Steel and bronze inlay down the hall to the viewing wall
	block(shell, "InlaySteel", Vector3.new(1.2, 0.08, HZ * 2 - 6), at(0, 0.05, 0), STEEL, M.Metal, GHOST)
	block(shell, "InlayBronzeL", Vector3.new(0.2, 0.09, HZ * 2 - 6), at(-1.1, 0.06, 0), BRONZE, M.Metal, GHOST)
	block(shell, "InlayBronzeR", Vector3.new(0.2, 0.09, HZ * 2 - 6), at(1.1, 0.06, 0), BRONZE, M.Metal, GHOST)

	-- Walls: charcoal body, walnut panels with bronze reveals up to the rail, navy above
	local function wall(name: string, centre: Vector3, size: Vector3)
		block(shell, name, size, centre, NAVY, M.SmoothPlastic)
	end
	wall("WallNorth", at(0, HEIGHT / 2, -HZ - 1), Vector3.new(HX * 2 + 4, HEIGHT, 2))
	wall("WallSouth", at(0, HEIGHT / 2, HZ + 1), Vector3.new(HX * 2 + 4, HEIGHT, 2))
	wall("WallWest", at(-HX - 1, HEIGHT / 2, 0), Vector3.new(2, HEIGHT, HZ * 2))
	wall("WallEast", at(HX + 1, HEIGHT / 2, 0), Vector3.new(2, HEIGHT, HZ * 2))
	local panels = group("WallPanels", shell)
	local function panelRun(name: string, from: Vector3, to: Vector3, normal: Vector3, skip: ((number) -> boolean)?)
		local length = (to - from).Magnitude
		local direction = (to - from).Unit
		local count = math.floor(length / 8)
		for index = 0, count - 1 do
			local along = (index + 0.5) * length / count
			if not (skip and skip(along)) then
				local centre = from + direction * along + normal * 0.25 + Vector3.new(0, 7, 0)
				local frame = CFrame.lookAt(centre, centre + normal)
				block(panels, name, Vector3.new(length / count - 0.5, 12, 0.5), frame, WALNUT, M.WoodPlanks)
				block(panels, name .. "Reveal", Vector3.new(0.18, 12, 0.6), frame * CFrame.new(length / count / 2, 0, 0), BRONZE, M.Metal, GHOST)
			end
		end
	end
	-- the north wall is mostly screens, so its panels stand only at the ends
	panelRun("PanelN", at(-HX, 0, -HZ), at(HX, 0, -HZ), Vector3.new(0, 0, 1), function(along)
		return along > 22 and along < 78
	end)
	panelRun("PanelS", at(HX, 0, HZ), at(-HX, 0, HZ), Vector3.new(0, 0, -1), function(along)
		return along > 38 and along < 62
	end)
	panelRun("PanelW", at(-HX, 0, -HZ), at(-HX, 0, HZ), Vector3.new(1, 0, 0), function(along)
		return along > 8 and along < 68
	end)
	panelRun("PanelE", at(HX, 0, HZ), at(HX, 0, -HZ), Vector3.new(-1, 0, 0), function(along)
		return along > 10 and along < 62
	end)
	-- Bronze rail along every wall, and the dropped soffit with the amber cove under it
	block(shell, "RailN", Vector3.new(HX * 2, 0.35, 0.5), at(0, 13.4, -HZ + 0.3), BRONZE, M.Metal, GHOST)
	block(shell, "RailS", Vector3.new(HX * 2, 0.35, 0.5), at(0, 13.4, HZ - 0.3), BRONZE, M.Metal, GHOST)
	block(shell, "RailW", Vector3.new(0.5, 0.35, HZ * 2), at(-HX + 0.3, 13.4, 0), BRONZE, M.Metal, GHOST)
	block(shell, "RailE", Vector3.new(0.5, 0.35, HZ * 2), at(HX - 0.3, 13.4, 0), BRONZE, M.Metal, GHOST)
	block(shell, "SoffitN", Vector3.new(HX * 2, 2.4, 2.6), at(0, HEIGHT - 1.2, -HZ + 1.3), CHARCOAL, M.SmoothPlastic)
	block(shell, "SoffitS", Vector3.new(HX * 2, 2.4, 2.6), at(0, HEIGHT - 1.2, HZ - 1.3), CHARCOAL, M.SmoothPlastic)
	block(shell, "SoffitW", Vector3.new(2.6, 2.4, HZ * 2), at(-HX + 1.3, HEIGHT - 1.2, 0), CHARCOAL, M.SmoothPlastic)
	block(shell, "SoffitE", Vector3.new(2.6, 2.4, HZ * 2), at(HX - 1.3, HEIGHT - 1.2, 0), CHARCOAL, M.SmoothPlastic)
	local coves = group("Coves", shell)
	strip(coves, "CoveN", Vector3.new(HX * 2 - 6, 0.2, 0.2), at(0, HEIGHT - 2.5, -HZ + 2.7), AMBER)
	strip(coves, "CoveS", Vector3.new(HX * 2 - 6, 0.2, 0.2), at(0, HEIGHT - 2.5, HZ - 2.7), AMBER)
	strip(coves, "CoveW", Vector3.new(0.2, 0.2, HZ * 2 - 6), at(-HX + 2.7, HEIGHT - 2.5, 0), AMBER)
	strip(coves, "CoveE", Vector3.new(0.2, 0.2, HZ * 2 - 6), at(HX - 2.7, HEIGHT - 2.5, 0), AMBER)

	-- Ceiling: four slabs round a glazed opening, glass, steel mullions, an amber rim cove
	local OX, OZ0, OZ1 = 24, -26, 14
	local ceilingY = HEIGHT + 0.75
	block(shell, "CeilingN", Vector3.new(HX * 2 + 4, 1.5, OZ0 + HZ + 2), at(0, ceilingY, (OZ0 - HZ - 2) / 2), CHARCOAL, M.Concrete)
	block(shell, "CeilingS", Vector3.new(HX * 2 + 4, 1.5, HZ - OZ1 + 2), at(0, ceilingY, (OZ1 + HZ + 2) / 2), CHARCOAL, M.Concrete)
	block(shell, "CeilingW", Vector3.new(HX - OX + 2, 1.5, OZ1 - OZ0), at(-(HX + OX + 2) / 2, ceilingY, (OZ0 + OZ1) / 2), CHARCOAL, M.Concrete)
	block(shell, "CeilingE", Vector3.new(HX - OX + 2, 1.5, OZ1 - OZ0), at((HX + OX + 2) / 2, ceilingY, (OZ0 + OZ1) / 2), CHARCOAL, M.Concrete)
	local glassZ = (OZ0 + OZ1) / 2
	block(shell, "GlassCeiling", Vector3.new(OX * 2, 0.5, OZ1 - OZ0), at(0, ceilingY, glassZ), rgb(140, 190, 210), M.Glass, { Transparency = 0.7, Reflectance = 0.15, CanCollide = true, CastShadow = false })
	for index = -2, 2 do
		block(shell, "MullionZ", Vector3.new(0.5, 0.7, OZ1 - OZ0), at(index * 9.6, ceilingY, glassZ), STEEL, M.Metal, GHOST)
	end
	for index = 1, 3 do
		block(shell, "MullionX", Vector3.new(OX * 2, 0.7, 0.5), at(0, ceilingY, OZ0 + index * (OZ1 - OZ0) / 4), STEEL, M.Metal, GHOST)
	end
	strip(coves, "RimN", Vector3.new(OX * 2, 0.2, 0.2), at(0, HEIGHT - 0.2, OZ0 + 0.3), AMBER)
	strip(coves, "RimS", Vector3.new(OX * 2, 0.2, 0.2), at(0, HEIGHT - 0.2, OZ1 - 0.3), AMBER)
	strip(coves, "RimW", Vector3.new(0.2, 0.2, OZ1 - OZ0), at(-OX + 0.3, HEIGHT - 0.2, glassZ), AMBER)
	strip(coves, "RimE", Vector3.new(0.2, 0.2, OZ1 - OZ0), at(OX - 0.3, HEIGHT - 0.2, glassZ), AMBER)

	-- Warm light from the coves; a few small sources, no per-object glow
	local lights = group("Lights", shell)
	for index, spot in { { -36, -30 }, { 36, -30 }, { -36, 28 }, { 36, 28 }, { 0, -34 }, { 0, 32 }, { -40, 0 }, { 40, 0 } } do
		local lamp = block(lights, "CoveLight" .. index, Vector3.new(1, 0.4, 1), at(spot[1], HEIGHT - 3, spot[2]), AMBER, M.SmoothPlastic, GHOST)
		lamp.Transparency = 1
		lightOn(lamp, WARM, 30, 0.7)
	end

	-- Furniture ---------------------------------------------------------------------------------------
	local furniture = group("Furniture")
	local seatCount = 0

	local function glow(owner: Instance, size: Vector3, frame: CFrame)
		strip(owner, "Underglow", size, frame, EMBER)
	end

	-- A sofa with `seats` seats, front towards -Z of `where`
	local function sofa(name: string, where: CFrame, seats: number, color: Color3)
		local item = group(name, furniture)
		local width = seats * 3 + 1.8
		glow(item, Vector3.new(width - 0.6, 0.15, 3), where * CFrame.new(0, 0.1, 0))
		block(item, "Base", Vector3.new(width, 1.2, 3.6), where * CFrame.new(0, 0.85, 0), CHARCOAL, M.SmoothPlastic)
		block(item, "Back", Vector3.new(width, 2.4, 0.9), where * CFrame.new(0, 2.5, 1.35), color, M.Fabric)
		for side = -1, 1, 2 do
			block(item, "Arm", Vector3.new(0.9, 1.9, 3.6), where * CFrame.new(side * (width / 2 - 0.45), 1.95, 0), color, M.Fabric)
		end
		for index = 1, seats do
			local x = (index - (seats + 1) / 2) * 3
			seatCount += 1
			block(item, "Seat", Vector3.new(2.9, 0.7, 2.7), where * CFrame.new(x, 1.8, -0.3), color, M.Fabric, { ClassName = "Seat" })
			block(item, "BackCushion", Vector3.new(2.6, 1.5, 0.6), where * CFrame.new(x, 2.7, 0.65) * CFrame.Angles(math.rad(-8), 0, 0), color, M.Fabric, GHOST)
		end
		block(item, "Piping", Vector3.new(width - 1.8, 0.1, 0.1), where * CFrame.new(0, 2.16, -1.65), BRONZE, M.Metal, GHOST)
	end

	local function armchair(name: string, where: CFrame, color: Color3, parentGroup: Instance?)
		local item = group(name, parentGroup or furniture)
		glow(item, Vector3.new(2.8, 0.15, 2.8), where * CFrame.new(0, 0.1, 0))
		block(item, "Base", Vector3.new(3.4, 1.2, 3.4), where * CFrame.new(0, 0.85, 0), CHARCOAL, M.SmoothPlastic)
		block(item, "Back", Vector3.new(3.4, 2.4, 0.8), where * CFrame.new(0, 2.5, 1.3), color, M.Fabric)
		for side = -1, 1, 2 do
			block(item, "Arm", Vector3.new(0.7, 1.8, 3.4), where * CFrame.new(side * 1.35, 1.9, 0), color, M.Fabric)
		end
		seatCount += 1
		block(item, "Seat", Vector3.new(2.1, 0.7, 2.8), where * CFrame.new(0, 1.8, -0.1), color, M.Fabric, { ClassName = "Seat" })
	end

	local function pouf(name: string, position: Vector3, color: Color3)
		local item = group(name, furniture)
		block(item, "Base", Vector3.new(2.6, 0.5, 2.6), CFrame.new(position + Vector3.new(0, 0.25, 0)), CHARCOAL, M.SmoothPlastic)
		seatCount += 1
		block(item, "Seat", Vector3.new(2.6, 1.0, 2.6), CFrame.new(position + Vector3.new(0, 1, 0)), color, M.Fabric, { ClassName = "Seat" })
	end

	local function coffeeTable(spot: { name: string, x: number, z: number, diameter: number })
		local item = group("Table_" .. spot.name, furniture)
		local centre = at(spot.x, 0, spot.z)
		Common.cylinder(item, "Foot", CFrame.new(centre + Vector3.new(0, 0.15, 0)), 0.3, spot.diameter * 0.55, GRAPHITE, M.Metal)
		Common.cylinder(item, "Stem", CFrame.new(centre + Vector3.new(0, 0.85, 0)), 1.3, spot.diameter * 0.2, GRAPHITE, M.Metal)
		Common.cylinder(item, "Top", CFrame.new(centre + Vector3.new(0, TABLE_TOP - 0.2, 0)), 0.4, spot.diameter, MARBLE, M.Marble, { Reflectance = 0.2 })
		Common.cylinder(item, "Edge", CFrame.new(centre + Vector3.new(0, TABLE_TOP - 0.45, 0)), 0.12, spot.diameter + 0.1, COPPER, M.Metal, GHOST)
		if spot.diameter > 4 then
			Common.cylinder(item, "Vase", CFrame.new(centre + Vector3.new(0.6, TABLE_TOP + 0.5, 0.3)), 1.1, 0.7, rgb(150, 190, 205), M.Glass, { Transparency = 0.55, CanCollide = false })
		end
	end

	local function rug(name: string, x: number, z: number, diameter: number)
		local item = group(name, furniture)
		Common.cylinder(item, "RugRing", CFrame.new(at(x, 0.05, z)), 0.1, diameter + 0.8, BRONZE, M.Metal, GHOST)
		Common.cylinder(item, "Rug", CFrame.new(at(x, 0.09, z)), 0.1, diameter, NAVY_SOFT, M.Fabric, GHOST)
	end

	local function lamp(name: string, x: number, z: number)
		local item = group(name, furniture)
		Common.cylinder(item, "Foot", CFrame.new(at(x, 0.15, z)), 0.3, 1.6, GRAPHITE, M.Metal)
		Common.cylinder(item, "Pole", CFrame.new(at(x, 3.2, z)), 6, 0.25, STEEL, M.Metal)
		local shade = Common.cylinder(item, "Shade", CFrame.new(at(x, 6.5, z)), 1.4, 1.6, AMBER, M.Neon, { Transparency = 0.15, CanCollide = false, CastShadow = false })
		lightOn(shade, WARM, 18, 0.7)
	end

	local function planter(name: string, x: number, z: number)
		local item = group(name, furniture)
		Common.cylinder(item, "Pot", CFrame.new(at(x, 1.2, z)), 2.4, 2.4, CHARCOAL, M.Slate)
		Common.ball(item, "LeavesLow", at(x, 3.4, z), 3, rgb(40, 78, 62), M.Fabric, GHOST)
		Common.ball(item, "LeavesHigh", at(x + 0.3, 5, z - 0.2), 2.4, rgb(48, 92, 70), M.Fabric, GHOST)
	end

	local face = function(x: number, z: number, targetX: number, targetZ: number): CFrame
		return CFrame.lookAt(at(x, 0, z), at(targetX, 0, targetZ))
	end

	-- Centre cluster: sofa behind, armchairs at the sides, two poufs, the round table, a rug
	rug("Rug_Centre", 0, -4, 28)
	coffeeTable(TABLES[1])
	sofa("Sofa_Centre", face(0, 5, 0, -4), 3, SLATE_BLUE)
	armchair("Chair_CentreWest", face(-9, -4, 0, -4), COGNAC)
	armchair("Chair_CentreEast", face(9, -4, 0, -4), COGNAC)
	pouf("Pouf_CentreA", at(-3, 0, -10.5), SLATE_BLUE)
	pouf("Pouf_CentreB", at(3, 0, -10.5), SLATE_BLUE)
	-- Side clusters
	for _, side in { -1, 1 } do
		local x = side * 30
		rug("Rug_Side" .. side, x, 9, 18)
		coffeeTable(TABLES[if side < 0 then 2 else 3])
		sofa("Sofa_Side" .. side, face(x, 15.5, x, 8), 2, SLATE_BLUE)
		armchair("Chair_SideA" .. side, face(x - 7, 8, x, 8), COGNAC)
		armchair("Chair_SideB" .. side, face(x + 7, 8, x, 8), COGNAC)
	end

	-- Quiet corners: south-west and north-east
	rug("Rug_SouthWest", -43, 31, 11)
	coffeeTable(TABLES[4])
	armchair("Chair_SouthWestA", face(-43, 26.4, -43, 31), COGNAC)
	armchair("Chair_SouthWestB", face(-38.2, 31, -43, 31), COGNAC)
	lamp("Lamp_SouthWest", -47, 27)
	planter("Planter_SouthWest", -47, 35)
	rug("Rug_NorthEast", 44, -28.5, 11)
	coffeeTable(TABLES[5])
	armchair("Chair_NorthEastA", face(39.4, -28.5, 44, -28.5), COGNAC)
	armchair("Chair_NorthEastB", face(44, -33.4, 44, -28.5), COGNAC)
	lamp("Lamp_NorthEast", 47.5, -25)
	planter("Planter_NorthEast", 48, -35)
	lamp("Lamp_SouthDoorW", -12, 33)
	lamp("Lamp_SouthDoorE", 12, 33)

	-- Low bookshelf wall unit on the south-west wall: shelving with a few objects
	do
		local shelf = group("Shelving", furniture)
		block(shelf, "Frame", Vector3.new(1.4, 7, 9), at(-HX + 1, 3.5, 20), CHARCOAL, M.SmoothPlastic)
		for level = 1, 3 do
			block(shelf, "Shelf", Vector3.new(1.2, 0.25, 8.6), at(-HX + 1.1, level * 1.9 + 0.2, 20), WALNUT, M.WoodPlanks)
			block(shelf, "Books", Vector3.new(0.9, 1.1, 2.6), at(-HX + 1.1, level * 1.9 + 0.9, 17.5 + level), NAVY_SOFT, M.Fabric, GHOST)
			block(shelf, "Object", Vector3.new(0.7, 0.9, 0.9), at(-HX + 1.1, level * 1.9 + 0.8, 22.5), BRONZE, M.Metal, GHOST)
		end
	end

	-- The viewing wall ---------------------------------------------------------------------------------
	local viewing = group("ViewingWall")
	local wallFace = -HZ + 0.6
	local inward = Vector3.new(0, 0, 1)
	local screens: { [string]: any } = {}

	-- A screen set into the wall: housing, bronze bezel, the glass face with its SurfaceGui
	local function screen(name: string, x: number, y: number, width: number, height: number, ppsw: number): Frame
		local frame = CFrame.lookAt(at(x, y, wallFace), at(x, y, wallFace) + inward)
		local item = group(name, viewing)
		block(item, "Housing", Vector3.new(width + 3.2, height + 3, 1.2), frame, CHARCOAL, M.SmoothPlastic)
		block(item, "BezelTop", Vector3.new(width + 3.2, 0.3, 0.3), frame * CFrame.new(0, (height + 3) / 2, 0.6), BRONZE, M.Metal, GHOST)
		block(item, "BezelBottom", Vector3.new(width + 3.2, 0.3, 0.3), frame * CFrame.new(0, -(height + 3) / 2, 0.6), BRONZE, M.Metal, GHOST)
		local glass = block(item, "Face", Vector3.new(width, height, 0.3), frame * CFrame.new(0, 0, 0.7), rgb(8, 12, 18), M.SmoothPlastic, { CastShadow = false })
		local gui = Instance.new("SurfaceGui")
		gui.Name = name .. "Gui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ppsw
		gui.LightInfluence = 0
		gui.Parent = glass
		local root = Instance.new("Frame")
		root.Name = "Root"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundColor3 = rgb(9, 14, 22)
		root.BorderSizePixel = 0
		root.Parent = gui
		Common.surfaceLight(glass, Enum.NormalId.Front, CYAN, 22, 0.35, 120)
		return root
	end

	-- Amber pilasters between the screens (the bent light of the reference, kept straight)
	for _, x in { -21.6, 21.6, -45.5, 45.5 } do
		strip(viewing, "Pilaster", Vector3.new(0.25, 17, 0.4), at(x, 10, wallFace + 0.1), AMBER)
	end
	block(viewing, "WallBase", Vector3.new(HX * 2, 1.2, 1.4), at(0, 0.6, -HZ + 0.8), CHARCOAL, M.SmoothPlastic)

	-- Big screen
	local main = screen("MainScreen", 0, 11, 36, 13, 24)
	local liveFrame = Instance.new("Frame")
	liveFrame.Name = "Live"
	liveFrame.BackgroundTransparency = 1
	liveFrame.Size = UDim2.fromScale(1, 1)
	liveFrame.Parent = main
	screens.mainHeader = newLabel(liveFrame, "Header", "LIVE MATCH", 0.03, 0.05, 0.5, 0.14, 26, CYAN, true)
	screens.mainSub = newLabel(liveFrame, "Sub", "", 0.4, 0.05, 0.57, 0.14, 22, MUTED, false, Enum.TextXAlignment.Right)
	screens.nameA = newLabel(liveFrame, "NameA", "", 0.03, 0.24, 0.42, 0.24, 46, TEXT, true)
	screens.powerA = newLabel(liveFrame, "PowerA", "", 0.03, 0.48, 0.42, 0.12, 24, AMBER, true)
	newLabel(liveFrame, "Versus", "VS", 0.44, 0.28, 0.12, 0.26, 36, MUTED, true, Enum.TextXAlignment.Center)
	screens.nameB = newLabel(liveFrame, "NameB", "", 0.55, 0.24, 0.42, 0.24, 46, TEXT, true, Enum.TextXAlignment.Right)
	screens.powerB = newLabel(liveFrame, "PowerB", "", 0.55, 0.48, 0.42, 0.12, 24, AMBER, true, Enum.TextXAlignment.Right)
	screens.mainFooter = newLabel(liveFrame, "Footer", "", 0.03, 0.74, 0.94, 0.16, 26, TEXT, false)
	local idleFrame = Instance.new("Frame")
	idleFrame.Name = "Idle"
	idleFrame.BackgroundTransparency = 1
	idleFrame.Size = UDim2.fromScale(1, 1)
	idleFrame.Parent = main
	screens.idleTitle = newLabel(idleFrame, "Title", "NO MATCH IN PROGRESS", 0.03, 0.08, 0.94, 0.2, 38, CYAN, true)
	screens.idleLines = newLabel(idleFrame, "Lines", "", 0.03, 0.32, 0.94, 0.6, 26, TEXT, false)
	screens.idleLines.TextWrapped = true
	screens.idleLines.TextYAlignment = Enum.TextYAlignment.Top
	screens.idleLines.TextTruncate = Enum.TextTruncate.None
	screens.liveFrame, screens.idleFrame = liveFrame, idleFrame

	-- Match list (left): four rows with Watch pads below
	local list = screen("ListScreen", -31, 10.5, 13, 9.5, 32)
	newLabel(list, "Header", "MATCHES", 0.05, 0.03, 0.6, 0.12, 22, CYAN, true)
	screens.listCount = newLabel(list, "Count", "", 0.5, 0.03, 0.45, 0.12, 16, MUTED, false, Enum.TextXAlignment.Right)
	screens.rows = {}
	for index = 1, Lounge.WatchPads do
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0.04, 0.17 + (index - 1) * 0.185)
		row.Size = UDim2.fromScale(0.92, 0.17)
		row.Parent = list
		newLabel(row, "Index", tostring(index), 0, 0, 0.09, 1, 22, AMBER, true)
		local title = newLabel(row, "Title", "", 0.1, 0, 0.9, 0.55, 19, TEXT, true)
		local detail = newLabel(row, "Detail", "", 0.1, 0.52, 0.9, 0.45, 15, MUTED, false)
		screens.rows[index] = { frame = row, title = title, detail = detail }
	end
	screens.listIdle = newLabel(list, "Idle", "", 0.05, 0.17, 0.9, 0.75, 18, TEXT, false)
	screens.listIdle.TextWrapped = true
	screens.listIdle.TextYAlignment = Enum.TextYAlignment.Top
	screens.listIdle.TextTruncate = Enum.TextTruncate.None
	screens.listMore = newLabel(list, "More", "", 0.05, 0.91, 0.9, 0.08, 14, MUTED, false)

	-- Prediction board (right)
	local board = screen("BoardScreen", 31, 10.5, 13, 9.5, 32)
	newLabel(board, "Header", "PREDICTION BOARD", 0.05, 0.03, 0.9, 0.12, 21, CYAN, true)
	screens.boardMatch = newLabel(board, "Match", "", 0.05, 0.16, 0.9, 0.11, 19, TEXT, true)
	screens.boardNameA = newLabel(board, "NameA", "", 0.05, 0.29, 0.62, 0.1, 17, TEXT, true)
	screens.boardPctA = newLabel(board, "PercentA", "", 0.6, 0.29, 0.35, 0.1, 17, AMBER, true, Enum.TextXAlignment.Right)
	local trackA = Instance.new("Frame")
	trackA.Name = "TrackA"
	trackA.Position = UDim2.fromScale(0.05, 0.4)
	trackA.Size = UDim2.fromScale(0.9, 0.04)
	trackA.BackgroundColor3 = rgb(30, 40, 56)
	trackA.BorderSizePixel = 0
	trackA.Parent = board
	screens.barA = Instance.new("Frame")
	screens.barA.Name = "Fill"
	screens.barA.Size = UDim2.fromScale(0, 1)
	screens.barA.BackgroundColor3 = AMBER
	screens.barA.BorderSizePixel = 0
	screens.barA.Parent = trackA
	screens.boardNameB = newLabel(board, "NameB", "", 0.05, 0.47, 0.62, 0.1, 17, TEXT, true)
	screens.boardPctB = newLabel(board, "PercentB", "", 0.6, 0.47, 0.35, 0.1, 17, AMBER, true, Enum.TextXAlignment.Right)
	local trackB = trackA:Clone()
	trackB.Name = "TrackB"
	trackB.Position = UDim2.fromScale(0.05, 0.58)
	trackB.Parent = board
	screens.barB = trackB:FindFirstChild("Fill")
	screens.boardStatus = newLabel(board, "Status", "", 0.05, 0.64, 0.9, 0.2, 17, TEXT, true)
	screens.boardStatus.TextWrapped = true
	screens.boardStatus.TextTruncate = Enum.TextTruncate.None
	screens.boardFooter = newLabel(board, "Footer", "Free to pick. Nothing is won, spent or paid.", 0.05, 0.86, 0.9, 0.1, 14, MUTED, false)

	-- Consoles with the prompts
	local function console(name: string, x: number, width: number)
		block(viewing, name, Vector3.new(width, 1.3, 2.6), at(x, 0.65, -HZ + 2.6), GRAPHITE, M.SmoothPlastic)
		block(viewing, name .. "Trim", Vector3.new(width, 0.12, 0.2), at(x, 1.3, -HZ + 3.8), COPPER, M.Metal, GHOST)
	end
	console("ListConsole", -31, 13.6)
	console("BoardConsole", 31, 9)
	local pads = {}
	for index = 1, Lounge.WatchPads do
		local pad = block(viewing, "WatchPad" .. index, Vector3.new(2.4, 0.3, 1.6), at(-31 + (index - 2.5) * 3.1, 1.45, -HZ + 2.7), BRONZE, M.Metal)
		pad:SetAttribute("Index", index)
		local watch = prompt(pad, "Watch", "", 12, nil)
		watch.Enabled = false
		watch.Triggered:Connect(function(player: Player)
			hooks.watch(player, index)
		end)
		local number = Common.sign(pad, Enum.NormalId.Top, tostring(index), TEXT, 24, 0)
		number.Name = "Number"
		pads[index] = watch
	end
	local picks = {}
	for side = 1, 2 do
		local pad = block(viewing, "PickPad" .. side, Vector3.new(3.4, 0.3, 1.6), at(31 + (side - 1.5) * 4.2, 1.45, -HZ + 2.7), BRONZE, M.Metal)
		pad:SetAttribute("Side", side)
		local pick = prompt(pad, "Pick", "", 12, nil)
		pick.Enabled = false
		pick.Triggered:Connect(function(player: Player)
			hooks.predict(player, side)
		end)
		local letter = Common.sign(pad, Enum.NormalId.Top, if side == 1 then "A" else "B", TEXT, 24, 0)
		letter.Name = "Letter"
		picks[side] = pick
	end

	-- Refreshments counter shell (the logic is attached later, see the header) ------------------------------
	local counter = group("RefreshmentsCounter")
	block(counter, "Body", Vector3.new(3.2, 3.6, 26), at(44, 1.8, -7), CHARCOAL, M.SmoothPlastic)
	block(counter, "Front", Vector3.new(0.3, 3.2, 25), at(42.3, 1.8, -7), WALNUT, M.WoodPlanks)
	block(counter, "Top", Vector3.new(4.4, 0.4, 27), at(43.8, 3.8, -7), MARBLE, M.Marble, { Reflectance = 0.2 })
	block(counter, "TopTrim", Vector3.new(0.2, 0.2, 27), at(41.7, 3.6, -7), COPPER, M.Metal, GHOST)
	glow(counter, Vector3.new(0.2, 0.15, 24), CFrame.new(at(42.0, 0.15, -7)))
	for index = 1, 4 do
		local z = -17 + (index - 1) * 6.4
		local stool = group("Stool" .. index, counter)
		block(stool, "Post", Vector3.new(0.5, 2.2, 0.5), at(39.2, 1.1, z), STEEL, M.Metal)
		seatCount += 1
		block(stool, "Seat", Vector3.new(2.2, 0.7, 2.2), at(39.2, 2.6, z), COGNAC, M.Fabric, { ClassName = "Seat" })
		block(stool, "Foot", Vector3.new(1.6, 0.2, 1.6), at(39.2, 0.1, z), GRAPHITE, M.Metal)
	end
	-- Back bar: two shelves with display jars, and the holographic menu panel
	block(counter, "BackBar", Vector3.new(1.2, 8, 25), at(49.4, 4, -7), CHARCOAL, M.SmoothPlastic)
	for level = 1, 2 do
		block(counter, "Shelf", Vector3.new(1.4, 0.25, 24), at(48.6, 3.6 + level * 2.8, -7), WALNUT, M.WoodPlanks)
		for jar = 1, 5 do
			local z = -17 + jar * 3.7 + level
			local colour = if (jar + level) % 2 == 0 then rgb(214, 150, 70) else rgb(160, 190, 205)
			Common.cylinder(counter, "Jar", CFrame.new(at(48.6, 3.6 + level * 2.8 + 0.9, z)), 1.4, 0.9, colour, M.Glass, { Transparency = 0.35, CanCollide = false })
		end
	end
	strip(counter, "ShelfLight", Vector3.new(0.2, 0.15, 24), at(48.9, 9.5, -7), AMBER)
	local menuFace = block(counter, "RefreshmentsMenu", Vector3.new(14, 4, 0.3), CFrame.lookAt(at(49, 13, -7), at(49, 13, -7) + Vector3.new(-1, 0, 0)), rgb(8, 12, 18), M.SmoothPlastic, { CastShadow = false })
	local menuGui = Instance.new("SurfaceGui")
	menuGui.Name = "MenuGui"
	menuGui.Face = Enum.NormalId.Front
	menuGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	menuGui.PixelsPerStud = 32
	menuGui.LightInfluence = 0
	menuGui.Parent = menuFace
	newLabel(menuGui, "Title", "REFRESHMENTS", 0.04, 0.08, 0.92, 0.38, 40, CYAN, true)
	newLabel(menuGui, "Status", "Counter opens soon", 0.04, 0.52, 0.92, 0.34, 28, TEXT, false)
	local attach = block(counter, "RefreshmentsAttachment", Vector3.new(1, 1, 1), CFrame.lookAt(at(41, 1.5, -7), at(41, 1.5, -7) + Vector3.new(-1, 0, 0)), CHARCOAL, M.SmoothPlastic, GHOST)
	attach.Transparency = 1
	attach:SetAttribute("Station", "Refreshments")
	attach:SetAttribute("Facing", "West")

	-- Shop kiosk by the south-east corner
	local kiosk = group("ShopKiosk")
	local kioskFrame = CFrame.lookAt(at(44, 0, 26), at(43, 0, 26))
	block(kiosk, "Base", Vector3.new(3.4, 0.6, 3.4), kioskFrame * CFrame.new(0, 0.3, 0), GRAPHITE, M.Metal)
	block(kiosk, "Column", Vector3.new(2.6, 5, 2.6), kioskFrame * CFrame.new(0, 3.1, 0), CHARCOAL, M.SmoothPlastic)
	local kioskFace = block(kiosk, "Face", Vector3.new(2.2, 3.2, 0.2), kioskFrame * CFrame.new(0, 3.5, -1.35), rgb(8, 12, 18), M.SmoothPlastic, { CastShadow = false })
	local kioskGui = Instance.new("SurfaceGui")
	kioskGui.Name = "KioskGui"
	kioskGui.Face = Enum.NormalId.Front
	kioskGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	kioskGui.PixelsPerStud = 60
	kioskGui.LightInfluence = 0
	kioskGui.Parent = kioskFace
	newLabel(kioskGui, "Title", "MASTER SHOP", 0.06, 0.1, 0.88, 0.3, 24, CYAN, true)
	newLabel(kioskGui, "Body", "Powers, cosmetics and passes", 0.06, 0.45, 0.88, 0.4, 18, TEXT, false).TextWrapped = true
	block(kiosk, "Canopy", Vector3.new(3.8, 0.3, 3.8), kioskFrame * CFrame.new(0, 5.8, 0), BRONZE, M.Metal)
	strip(kiosk, "CanopyGlow", Vector3.new(3.4, 0.15, 3.4), kioskFrame * CFrame.new(0, 5.6, 0), AMBER)
	local kioskPad = block(kiosk, "Pad", Vector3.new(2.2, 0.2, 1.4), kioskFrame * CFrame.new(0, 0.7, -2.3), BRONZE, M.Metal)
	prompt(kioskPad, "Open the shop", "Master Shop", 10, "Window:Market")

	-- The Founders' Archive ------------------------------------------------------------------------------------
	local archive = group("FoundersArchive")
	local PANEL_X = -46
	block(archive, "Plinth", Vector3.new(8, 0.5, 70), at(-47, 0.25, 0), GRAPHITE, M.Slate, GHOST)
	strip(archive, "FloorLine", Vector3.new(0.2, 0.08, 66), at(-42.6, 0.52, 0), AMBER)
	local panelIds = { "field_note_kestrel", "varga_journal", "long_quiet" }
	for index, chapterId in panelIds do
		local z = (index - 2) * 16
		local title, excerpt = excerptOf(chapterId, 150)
		local where = CFrame.lookAt(at(PANEL_X, 8.5, z), at(PANEL_X, 8.5, z) + Vector3.new(1, 0, 0))
		local item = group("ChapterPanel_" .. chapterId, archive)
		block(item, "Emitter", Vector3.new(7.6, 0.6, 1.4), CFrame.new(at(PANEL_X, 0.8, z)), BRONZE, M.Metal)
		strip(item, "EmitterLine", Vector3.new(7.2, 0.12, 0.3), CFrame.new(at(PANEL_X + 0.1, 1.15, z)), CYAN)
		local slab = block(item, "Holo", Vector3.new(7.4, 12.6, 0.3), where, rgb(10, 24, 36), M.Glass, { Transparency = 0.35, CanCollide = false, CastShadow = false })
		local gui = Instance.new("SurfaceGui")
		gui.Name = "ChapterGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Parent = slab
		newLabel(gui, "Eyebrow", `CHAPTER {index}`, 0.08, 0.04, 0.84, 0.05, 18, CYAN, true)
		local heading = newLabel(gui, "Title", title, 0.08, 0.1, 0.84, 0.2, 34, TEXT, true)
		heading.TextWrapped = true
		heading.TextTruncate = Enum.TextTruncate.None
		heading.TextYAlignment = Enum.TextYAlignment.Top
		local body = newLabel(gui, "Excerpt", excerpt, 0.08, 0.33, 0.84, 0.55, 22, MUTED, false)
		body.TextWrapped = true
		body.TextTruncate = Enum.TextTruncate.None
		body.TextYAlignment = Enum.TextYAlignment.Top
		newLabel(gui, "Source", "The Meridian Archive", 0.08, 0.92, 0.84, 0.05, 16, AMBER, true)
	end

	-- Exhibit image frames on the wall: the owner uploads the pictures (see Lounge.ExhibitImages)
	local frames = {
		{ key = "KestrelValley", z = -24, caption = "Kestrel Valley, before the station" },
		{ key = "FirstLight", z = -8, caption = "First Light" },
		{ key = "TheCascade", z = 8, caption = "The Cascade" },
		{ key = "DoorInTheHill", z = 24, caption = "The door in the hill" },
	}
	local studio = RunService:IsStudio()
	for _, entry in frames do
		local item = group("ExhibitFrame_" .. entry.key, archive)
		local look = CFrame.lookAt(at(-HX + 0.9, 9.5, entry.z), at(-HX + 0.9, 9.5, entry.z) + Vector3.new(1, 0, 0))
		block(item, "Mat", Vector3.new(5.6, 7.4, 0.5), look, CHARCOAL, M.SmoothPlastic)
		block(item, "FrameBronze", Vector3.new(5.9, 7.7, 0.3), look * CFrame.new(0, 0, 0.1), BRONZE, M.Metal, GHOST)
		local picture = block(item, "Picture", Vector3.new(4.8, 6.6, 0.2), look * CFrame.new(0, 0, -0.35), rgb(14, 20, 30), M.SmoothPlastic, { CastShadow = false })
		picture:SetAttribute("ImageKey", entry.key)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PictureGui"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.LightInfluence = 0.4
		gui.Parent = picture
		local id = Lounge.ExhibitImages[entry.key] or 0
		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundColor3 = rgb(14, 20, 30)
		image.BorderSizePixel = 0
		image.Image = if id > 0 then `rbxassetid://{id}` else ""
		image.Parent = gui
		local plate = newLabel(gui, "Pending", "Exhibit image pending", 0.08, 0.4, 0.84, 0.2, 22, MUTED, true, Enum.TextXAlignment.Center)
		plate.TextWrapped = true
		plate.TextTruncate = Enum.TextTruncate.None
		plate.Visible = id == 0 and studio
		local plaque = block(item, "Plaque", Vector3.new(4.4, 0.8, 0.2), look * CFrame.new(0, -4.5, 0.1), BRONZE, M.Metal)
		Common.sign(plaque, Enum.NormalId.Front, entry.caption, rgb(24, 18, 12), 40, 1)
	end

	-- Artifacts in glass cases, lit from above
	local artifacts = {
		{ name = "TapeReel", z = -24 },
		{ name = "StaffBadge", z = -8 },
		{ name = "SealedFolder", z = 8 },
		{ name = "LanternShard", z = 24 },
	}
	for _, entry in artifacts do
		local item = group("Artifact_" .. entry.name, archive)
		local x = -44
		block(item, "Stand", Vector3.new(3.4, 3, 3.4), at(x, 1.5, entry.z), CHARCOAL, M.SmoothPlastic)
		block(item, "StandTrim", Vector3.new(3.6, 0.2, 3.6), at(x, 3.05, entry.z), BRONZE, M.Metal, GHOST)
		block(item, "Case", Vector3.new(3, 3, 3), at(x, 4.6, entry.z), rgb(150, 190, 205), M.Glass, { Transparency = 0.8, CanCollide = false, CastShadow = false })
		local centre = at(x, 3.7, entry.z)
		if entry.name == "TapeReel" then
			Common.cylinder(item, "ReelA", CFrame.new(centre + Vector3.new(-0.7, 0.9, 0)) * CFrame.Angles(math.rad(90), 0, 0), 0.25, 1.6, rgb(60, 62, 68), M.Metal, GHOST)
			Common.cylinder(item, "ReelB", CFrame.new(centre + Vector3.new(0.7, 0.9, 0)) * CFrame.Angles(math.rad(90), 0, 0), 0.25, 1.6, rgb(60, 62, 68), M.Metal, GHOST)
			block(item, "Tape", Vector3.new(1.6, 0.05, 0.1), CFrame.new(centre + Vector3.new(0, 0.15, 0)), rgb(70, 46, 30), M.Fabric, GHOST)
		elseif entry.name == "StaffBadge" then
			block(item, "Card", Vector3.new(1.3, 1.9, 0.12), CFrame.new(centre + Vector3.new(0, 1, 0)) * CFrame.Angles(math.rad(-12), 0, 0), IVORY, M.SmoothPlastic, GHOST)
			block(item, "Clip", Vector3.new(0.4, 0.3, 0.16), CFrame.new(centre + Vector3.new(0, 2.05, 0.05)), STEEL, M.Metal, GHOST)
		elseif entry.name == "SealedFolder" then
			block(item, "Folder", Vector3.new(1.9, 0.25, 2.3), CFrame.new(centre + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, math.rad(15), 0), rgb(120, 98, 64), M.Fabric, GHOST)
			block(item, "Strap", Vector3.new(0.2, 0.3, 2.34), CFrame.new(centre + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, math.rad(15), 0), COPPER, M.Metal, GHOST)
		else
			local shard = Common.ball(item, "Shard", centre + Vector3.new(0, 1.1, 0), 0.9, AMBER, M.Neon, { CanCollide = false, CastShadow = false })
			shard.Transparency = 0.25
			Common.cylinder(item, "Ring", CFrame.new(centre + Vector3.new(0, 1.1, 0)), 0.1, 1.7, BRONZE, M.Metal, GHOST)
		end
		local spot = block(item, "Spot", Vector3.new(1.2, 0.4, 1.2), at(x, HEIGHT - 3.2, entry.z), CHARCOAL, M.Metal, GHOST)
		Common.spotLight(spot, Enum.NormalId.Bottom, WARM, 26, 2.2, 38, false)
	end
	-- Lectern: the book opens the Archive window
	do
		local look = CFrame.lookAt(at(-39.5, 0, 0), at(-39.5, 0, 0) + Vector3.new(1, 0, 0))
		local lectern = group("Lectern", archive)
		block(lectern, "Column", Vector3.new(1.6, 3.2, 2.6), look * CFrame.new(0, 1.6, 0), WALNUT, M.WoodPlanks)
		block(lectern, "Desk", Vector3.new(2.4, 0.3, 3.2), look * CFrame.new(0.1, 3.4, 0) * CFrame.Angles(0, 0, math.rad(12)), BRONZE, M.Metal)
		local book = block(lectern, "Book", Vector3.new(1.8, 0.3, 2.6), look * CFrame.new(0.15, 3.75, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(70, 36, 30), M.Fabric)
		block(lectern, "Pages", Vector3.new(1.6, 0.15, 2.4), look * CFrame.new(0.15, 3.95, 0) * CFrame.Angles(0, 0, math.rad(12)), IVORY, M.SmoothPlastic, GHOST)
		prompt(book, "Read the Archive", "The Meridian Archive", 10, "Window:Archive")
	end

	-- Entrance: a sealed glass door with a return prompt ---------------------------------------------------------
	local door = group("Entrance")
	local doorFrame = CFrame.lookAt(at(0, 0, HZ - 0.4), at(0, 0, HZ - 0.4) + Vector3.new(0, 0, -1))
	block(door, "Glass", Vector3.new(8, 10.4, 0.4), doorFrame * CFrame.new(0, 5.2, 0), rgb(120, 170, 190), M.Glass, { Transparency = 0.5, Reflectance = 0.1, CastShadow = false })
	block(door, "FrameLeft", Vector3.new(0.5, 11, 0.7), doorFrame * CFrame.new(-4.2, 5.5, 0), BRONZE, M.Metal)
	block(door, "FrameRight", Vector3.new(0.5, 11, 0.7), doorFrame * CFrame.new(4.2, 5.5, 0), BRONZE, M.Metal)
	block(door, "FrameTop", Vector3.new(8.9, 0.5, 0.7), doorFrame * CFrame.new(0, 11, 0), BRONZE, M.Metal)
	local doorPad = block(door, "Pad", Vector3.new(4, 0.2, 1.6), doorFrame * CFrame.new(0, 0.12, -1.6), BRONZE, M.Metal)
	local sign = block(door, "Sign", Vector3.new(6, 1.4, 0.2), doorFrame * CFrame.new(0, 12.2, -0.1), CHARCOAL, M.SmoothPlastic)
	Common.sign(sign, Enum.NormalId.Front, "HUB", CYAN, 40, 0)
	prompt(doorPad, "Return to hub", "Hub", 10, "Travel:Lobby")

	-- Finish ---------------------------------------------------------------------------------------------------------
	local spawnFrame = CFrame.lookAt(at(0, 3, HZ - 6), at(0, 3, -HZ))
	local lastView: any = nil

	-- view = {
	--   matches = { { id, mode, arena, phase, names, watchers, fighters = {{name, power}}, elapsed = number?,
	--                 tally = { counts, total }, predictionOpen } },   -- running matches, oldest first
	--   recent = { { text = string } },          -- finished matches, newest first (already trimmed)
	--   queues = { [modeName] = count },        -- players waiting for a match
	--   board = { kind = "idle" | "open" | "closed" | "result", matchLine, aName, bName, pctA, pctB, status },
	-- }
	local function refresh(view: any)
		lastView = view
		local matches = view.matches or {}
		local first = matches[1]
		setVisible(screens.liveFrame, first ~= nil)
		setVisible(screens.idleFrame, first == nil)
		if first then
			local a, b = first.fighters[1], first.fighters[2]
			setText(screens.mainSub, `{first.mode} on {first.arena}`)
			setText(screens.nameA, if a then clip(a.name, 16) else "")
			setText(screens.powerA, if a then a.power else "")
			setText(screens.nameB, if b then clip(b.name, 16) else "")
			setText(screens.powerB, if b then b.power else "")
			local time = if first.elapsed then `Elapsed {clock(first.elapsed)}` else "Starting"
			local more = if #matches > 1 then `   {#matches - 1} more live` else ""
			setText(screens.mainFooter, `{time}    {plural(first.watchers, "spectator", "spectators")}{more}`)
		else
			setText(screens.idleTitle, "NO MATCH IN PROGRESS")
			local lines = {}
			if view.recent and #view.recent > 0 then
				table.insert(lines, "Recent results")
				for _, entry in view.recent do
					table.insert(lines, entry.text)
				end
			else
				table.insert(lines, "Upcoming and training")
				local waiting = {}
				for modeName, count in view.queues or {} do
					table.insert(waiting, `{plural(count, "player is", "players are")} queued for {modeName}`)
				end
				table.sort(waiting)
				if #waiting > 0 then
					for _, line in waiting do
						table.insert(lines, line)
					end
				else
					table.insert(lines, "Nobody is queued right now")
				end
				table.insert(lines, "Practise on dummies in the Training Studio")
				table.insert(lines, "Start a match from the Play window")
			end
			setText(screens.idleLines, table.concat(lines, "\n"))
		end

		-- List and Watch pads
		setText(screens.listCount, if #matches > 0 then `{#matches} live` else "")
		for index = 1, Lounge.WatchPads do
			local row, entry = screens.rows[index], matches[index]
			setVisible(row.frame, entry ~= nil)
			if entry then
				setText(row.title, clip(table.concat(entry.names, " vs "), 24))
				local time = if entry.elapsed then clock(entry.elapsed) else "starting"
				setText(row.detail, `{entry.mode}  {time}  {plural(entry.watchers, "watching", "watching")}`)
			end
			local pad = pads[index]
			if pad.Enabled ~= (entry ~= nil) then
				pad.Enabled = entry ~= nil
			end
			local objectText = if entry then clip(table.concat(entry.names, " vs "), 30) else ""
			if pad.ObjectText ~= objectText then
				pad.ObjectText = objectText
			end
		end
		setVisible(screens.listIdle, #matches == 0)
		if #matches == 0 then
			local lines = { "No live matches." }
			if view.recent and view.recent[1] then
				table.insert(lines, "Last: " .. clip(view.recent[1].text, 34))
			end
			table.insert(lines, "Matches appear here when they start.")
			setText(screens.listIdle, table.concat(lines, "\n"))
		end
		setText(screens.listMore, if #matches > Lounge.WatchPads then `{#matches - Lounge.WatchPads} more in the Watch window` else "")

		-- Prediction board
		local state = view.board or { kind = "idle" }
		setText(screens.boardMatch, state.matchLine or "")
		setText(screens.boardNameA, clip(state.aName or "", 18))
		setText(screens.boardNameB, clip(state.bName or "", 18))
		local shown = state.kind ~= "idle"
		setText(screens.boardPctA, if shown and state.pctA then `{state.pctA}%` else "")
		setText(screens.boardPctB, if shown and state.pctB then `{state.pctB}%` else "")
		local widthA = if shown and state.pctA then state.pctA / 100 else 0
		local widthB = if shown and state.pctB then state.pctB / 100 else 0
		if screens.barA.Size.X.Scale ~= widthA then
			screens.barA.Size = UDim2.fromScale(widthA, 1)
		end
		if screens.barB.Size.X.Scale ~= widthB then
			screens.barB.Size = UDim2.fromScale(widthB, 1)
		end
		setText(screens.boardStatus, state.status or "No match to predict yet.")
		for side = 1, 2 do
			local open = state.kind == "open"
			local pick = picks[side]
			if pick.Enabled ~= open then
				pick.Enabled = open
			end
			local name = if side == 1 then state.aName else state.bName
			local objectText = if open and name then clip(name, 20) else ""
			if pick.ObjectText ~= objectText then
				pick.ObjectText = objectText
			end
		end
	end
	refresh({ matches = {}, recent = {}, queues = {}, board = { kind = "idle", status = "No match to predict yet." } })

	model:SetAttribute("Seats", seatCount)
	model.Parent = parent
	return {
		model = model,
		spawn = spawnFrame,
		refresh = refresh,
	}
end

return Lounge
