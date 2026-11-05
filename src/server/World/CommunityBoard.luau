-- The community goals board in the hub: a board on the Entrance wall beside the spawn, right of
-- the doorway (the Leaderboards board hangs on the left). It lists each like goal from
-- Config/Community.LikeGoals with a progress bar and the last count the owner entered. It is
-- display only: CommunityService owns the numbers and calls CommunityBoard.update when they
-- change. The board blocks no path (it is a flat plate on the wall cladding, nothing collides).
--
--   CommunityBoard.build(folder, radius)             builds the plate and draws the current state
--   CommunityBoard.update(likes, setAt, loaded)      redraws the goals and the last count
--   CommunityBoard.lineFor(goal)                     "1,000 likes: everyone gets the Supporter title"
--   CommunityBoard.countLine(likes, setAt, loaded)   "Last count: 640 likes, 4 Nov"
--
-- Sizes: the sign is 920 x 640 px (40 px per stud on a 23 x 16 stud plate); titles 40 px, lines
-- 28 px, bold Builder Sans, no glow or strokes. Text states the facts and promises nothing else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Community = require(ReplicatedStorage.Shared.Config.Community)

local CommunityBoard = {}

local FONT_SANS = "rbxasset://fonts/families/BuilderSans.json"
local PLATE = Color3.fromRGB(26, 24, 30)
local STEEL = Color3.fromRGB(138, 146, 156)
local AMBER = Color3.fromRGB(232, 162, 74)
local SAGE = Color3.fromRGB(134, 190, 128)
local TEXT = Color3.fromRGB(240, 234, 224)
local MUTED = Color3.fromRGB(190, 182, 170)
local TRACK = Color3.fromRGB(58, 52, 48)

local SIGN = Vector2.new(920, 640)
local LEFT, WIDTH = 20, 880
local TITLE_SIZE, LINE_SIZE = 40, 28

local state = { likes = 0, setAt = 0, loaded = false }
local goalLabels: { [string]: { line: TextLabel, fill: Frame } } = {}
local countLabel: TextLabel? = nil

local function commas(n: number): string
	local out = tostring(math.floor(n))
	while true do
		local replaced, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return out
end

function CommunityBoard.lineFor(goal): string
	return `{commas(goal.likes)} likes: everyone gets {goal.text}`
end

function CommunityBoard.countLine(likes: number, setAt: number, loaded: boolean): string
	if not loaded then
		return "Last count: loading"
	end
	if setAt <= 0 and likes <= 0 then
		return "No count entered yet"
	end
	local day = tonumber(os.date("!%d", setAt)) or 1
	local month = os.date("!%b", setAt)
	local noun = if likes == 1 then "like" else "likes"
	if setAt <= 0 then
		return `Last count: {commas(likes)} {noun}`
	end
	return `Last count: {commas(likes)} {noun}, {day} {month}`
end

local function render()
	for _, goal in Community.LikeGoals do
		local entry = goalLabels[goal.id]
		if entry then
			local reached = state.likes >= goal.likes
			local fraction = math.clamp(state.likes / goal.likes, 0, 1)
			entry.line.Text = CommunityBoard.lineFor(goal)
			entry.line.TextColor3 = if reached then SAGE else TEXT
			entry.fill.Size = UDim2.fromScale(fraction, 1)
			entry.fill.BackgroundColor3 = if reached then SAGE else AMBER
			entry.fill.Visible = fraction > 0
		end
	end
	if countLabel then
		countLabel.Text = CommunityBoard.countLine(state.likes, state.setAt, state.loaded)
	end
end

function CommunityBoard.update(likes: number, setAt: number, loaded: boolean?)
	state = { likes = likes, setAt = setAt, loaded = loaded ~= false }
	render()
end

local function text(parent: Instance, name: string, value: string, size: number, color: Color3, y: number, h: number): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromScale(LEFT / SIGN.X, y / SIGN.Y)
	item.Size = UDim2.fromScale(WIDTH / SIGN.X, h / SIGN.Y)
	item.Text = value
	item.FontFace = Font.new(FONT_SANS, Enum.FontWeight.Bold)
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

-- `radius` is the hub's apothem. The frame follows Hub's convention: -Z points at the Lantern.
function CommunityBoard.build(folder: Instance, radius: number?): Model
	local r = radius or 88
	local angle = math.rad(90)
	local c, s = math.cos(angle), math.sin(angle)
	local f = CFrame.fromMatrix(Vector3.new(c * r, 0, s * r), Vector3.new(s, 0, -c), Vector3.new(0, 1, 0), Vector3.new(c, 0, s))

	local model = Instance.new("Model")
	model.Name = "CommunityGoals"
	local function box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = material
		part.Color = color
		part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
		part.CFrame = f * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
		part.Parent = model
		return part
	end
	-- Plate on the cladding between x 11 and 34 (clear of the doorway's reveals at 8.2)
	local plate = box("Board", 11, 34, 5, 21, -1.3, -0.5, PLATE, Enum.Material.SmoothPlastic)
	box("BoardFrame", 10.7, 34.3, 20.7, 21, -1.4, -0.4, STEEL, Enum.Material.Metal)
	box("BoardFrame", 10.7, 34.3, 5, 5.3, -1.4, -0.4, STEEL, Enum.Material.Metal)
	box("BoardFrame", 10.7, 11, 5, 21, -1.4, -0.4, STEEL, Enum.Material.Metal)
	box("BoardFrame", 34, 34.3, 5, 21, -1.4, -0.4, STEEL, Enum.Material.Metal)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN.X / 23
	gui.LightInfluence = 0
	gui.Parent = plate

	text(gui, "Heading", "Community goals", TITLE_SIZE, TEXT, 20, 54)
	text(gui, "Subheading", "Every player gets each reward, liked or not.", LINE_SIZE, MUTED, 76, 38)
	goalLabels = {}
	for index, goal in Community.LikeGoals do
		local y = 136 + (index - 1) * 118
		local line = text(gui, "Goal_" .. goal.id, CommunityBoard.lineFor(goal), LINE_SIZE, TEXT, y, 40)
		local track = Instance.new("Frame")
		track.Name = "Track_" .. goal.id
		track.BorderSizePixel = 0
		track.BackgroundColor3 = TRACK
		track.Position = UDim2.fromScale(LEFT / SIGN.X, (y + 48) / SIGN.Y)
		track.Size = UDim2.fromScale(WIDTH / SIGN.X, 22 / SIGN.Y)
		track.Parent = gui
		local fill = Instance.new("Frame")
		fill.Name = "Fill_" .. goal.id
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = AMBER
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = track
		goalLabels[goal.id] = { line = line, fill = fill }
	end
	countLabel = text(gui, "Count", "", LINE_SIZE, AMBER, 506, 42)
	text(gui, "Note", "A like on the game page helps us reach the next goal.", LINE_SIZE, MUTED, 556, 42)
	render()

	model.Parent = folder
	return model
end

return CommunityBoard
