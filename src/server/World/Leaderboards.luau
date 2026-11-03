-- The leaderboard in the hub: top 10 for Wins and Best streak, a board on the Entrance wall
-- beside the spawn (clear of every gate and statue). Numbers live in two OrderedDataStores.
--
--   Leaderboards.build(folder, radius)   builds the board and starts the read loop
--   Leaderboards.submit(userId, wins, bestStreak, persistent)   called when a player's stats may
--       have changed; a player is written at most once per WriteGap seconds, only when a number
--       went up, and only if their own progress is being saved
--   Leaderboards.refresh()               reads both boards now and redraws the sign
--
-- Everything that touches the DataStore is pcall'd. When no read ever worked the board says
-- "Leaderboard unavailable"; after a good read it keeps showing the last good numbers.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Leaderboards = {}

Leaderboards.Config = {
	Top = 10,
	WriteGap = 60, -- seconds between writes for one player
	ReadGap = 120, -- seconds between reads of the boards
	FlushGap = 15, -- how often held-back writes are retried
	NameLength = 18,
	Boards = {
		{ id = "wins", title = "Wins", store = "SN_Wins_v1" },
		{ id = "streak", title = "Best streak", store = "SN_BestStreak_v1" },
	},
}

local FONT_SANS = "rbxasset://fonts/families/BuilderSans.json"
local FONT_DISPLAY = "rbxasset://fonts/families/Michroma.json"
local FONT_MONO = "rbxasset://fonts/families/RobotoMono.json"
local NAVY = Color3.fromRGB(14, 22, 36)
local STEEL = Color3.fromRGB(138, 146, 156)
local AMBER = Color3.fromRGB(232, 162, 74)
local TEXT = Color3.fromRGB(232, 238, 244)
local MUTED = Color3.fromRGB(150, 160, 172)

-- Data ---------------------------------------------------------------------------------------------

-- provider(storeName) -> an OrderedDataStore-like (UpdateAsync, GetSortedAsync); replaceable for tests
local provider: (string) -> any = function(name)
	return DataStoreService:GetOrderedDataStore(name)
end
local clock: () -> number = os.clock
local stores: { [string]: any } = {}

function Leaderboards.setProvider(newProvider: ((string) -> any)?, newClock: (() -> number)?)
	provider = newProvider or function(name)
		return DataStoreService:GetOrderedDataStore(name)
	end
	clock = newClock or os.clock
	table.clear(stores)
end

local function storeOf(name: string): any?
	if stores[name] == nil then
		local ok, store = pcall(provider, name)
		if not ok or store == nil then
			return nil
		end
		stores[name] = store
	end
	return stores[name]
end

-- Writes --------------------------------------------------------------------------------------------

type Entry = { wins: number, streak: number, writtenWins: number, writtenStreak: number, lastWrite: number, persistent: boolean }
local entries: { [number]: Entry } = {}
Leaderboards.writes = 0 -- completed store writes (for tests)
Leaderboards.failures = 0

local function validNumber(value: any): number?
	if typeof(value) == "number" and value == value and value >= 0 and value < 1e9 then
		return math.floor(value)
	end
	return nil
end

local function write(userId: number, entry: Entry): boolean
	local allOk = true
	for _, board in Leaderboards.Config.Boards do
		local value = if board.id == "wins" then entry.wins else entry.streak
		local written = if board.id == "wins" then entry.writtenWins else entry.writtenStreak
		if value > written then
			local store = storeOf(board.store)
			local ok = false
			if store then
				ok = pcall(function()
					store:UpdateAsync(tostring(userId), function(old)
						return math.max(validNumber(old) or 0, value)
					end)
				end)
			end
			if ok then
				Leaderboards.writes += 1
				if board.id == "wins" then
					entry.writtenWins = value
				else
					entry.writtenStreak = value
				end
			else
				Leaderboards.failures += 1
				allOk = false
			end
		end
	end
	entry.lastWrite = clock()
	return allOk
end

local function dirty(entry: Entry): boolean
	return entry.persistent and (entry.wins > entry.writtenWins or entry.streak > entry.writtenStreak)
end

function Leaderboards.submit(userId: number, wins: number, bestStreak: number, persistent: boolean?)
	local w, s = validNumber(wins), validNumber(bestStreak)
	if typeof(userId) ~= "number" or not w or not s then
		return
	end
	local entry = entries[userId]
	if not entry then
		entry = { wins = 0, streak = 0, writtenWins = 0, writtenStreak = 0, lastWrite = -math.huge, persistent = true }
		entries[userId] = entry
	end
	entry.persistent = persistent ~= false
	entry.wins = math.max(entry.wins, w)
	entry.streak = math.max(entry.streak, s)
	if dirty(entry) and clock() - entry.lastWrite >= Leaderboards.Config.WriteGap then
		task.spawn(write, userId, entry)
	end
end

-- Retries writes that were held back by the gap (or that failed)
function Leaderboards.flush()
	for userId, entry in entries do
		if dirty(entry) and clock() - entry.lastWrite >= Leaderboards.Config.WriteGap then
			write(userId, entry)
		end
	end
end

function Leaderboards.forget(userId: number)
	local entry = entries[userId]
	if entry and dirty(entry) then
		write(userId, entry)
	end
	entries[userId] = nil
end

-- Reads ---------------------------------------------------------------------------------------------

local names: { [number]: string } = {}
local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local text = if ok and typeof(name) == "string" and name ~= "" then name else "Player"
	if ok then
		names[userId] = text
	end
	return string.sub(text, 1, Leaderboards.Config.NameLength)
end

-- Last good rows per board: { { userId, name, value } }
local latest: { [string]: { { userId: number, name: string, value: number } } } = {}
local everRead = false

local rowLabels: { [string]: { { name: TextLabel, value: TextLabel } } } = {}
local notice: TextLabel? = nil

local function render()
	for _, board in Leaderboards.Config.Boards do
		local rows = latest[board.id] or {}
		for index, row in rowLabels[board.id] or {} do
			local data = rows[index]
			row.name.Text = if data then `{index}  {data.name}` else ""
			row.value.Text = if data then tostring(data.value) else ""
		end
	end
	if notice then
		notice.Visible = not everRead
	end
end

-- Reads both boards. Returns true when every board answered.
function Leaderboards.refresh(): boolean
	local all = true
	for _, board in Leaderboards.Config.Boards do
		local store = storeOf(board.store)
		local ok, page = false, nil
		if store then
			ok, page = pcall(function()
				return store:GetSortedAsync(false, Leaderboards.Config.Top):GetCurrentPage()
			end)
		end
		if ok and typeof(page) == "table" then
			local rows = {}
			for _, item in page do
				local userId = tonumber(item.key)
				local value = validNumber(item.value)
				if userId and value and value > 0 and #rows < Leaderboards.Config.Top then
					table.insert(rows, { userId = userId, name = nameOf(userId), value = value })
				end
			end
			latest[board.id] = rows
			everRead = true
		else
			all = false
		end
	end
	render()
	return all
end

function Leaderboards.rows(boardId: string)
	return latest[boardId] or {}
end

function Leaderboards.available(): boolean
	return everRead
end

-- The sign ------------------------------------------------------------------------------------------

local SIGN = Vector2.new(460, 320) -- pixels of the board face

local function text(parent: Instance, name: string, value: string, font: string, size: number, color: Color3, x: number, y: number, w: number, h: number, align: Enum.TextXAlignment): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Position = UDim2.fromScale(x / SIGN.X, y / SIGN.Y)
	item.Size = UDim2.fromScale(w / SIGN.X, h / SIGN.Y)
	item.Text = value
	item.FontFace = Font.new(font, Enum.FontWeight.Regular)
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = align
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Parent = parent
	return item
end

-- The board hangs on the Entrance wall (the wall behind the spawn), left of the doorway.
-- `radius` is the hub's apothem. The frame follows Hub's convention: -Z points at the Lantern.
function Leaderboards.build(folder: Instance, radius: number?): Model
	local r = radius or 88
	local angle = math.rad(90)
	local c, s = math.cos(angle), math.sin(angle)
	local f = CFrame.fromMatrix(Vector3.new(c * r, 0, s * r), Vector3.new(s, 0, -c), Vector3.new(0, 1, 0), Vector3.new(c, 0, s))

	local model = Instance.new("Model")
	model.Name = "Leaderboards"
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
	-- Plate on the cladding between x -34 and -11 (clear of the doorway's reveals at 8.2)
	local plate = box("Board", -34, -11, 5, 21, -1.3, -0.5, NAVY, Enum.Material.SmoothPlastic)
	box("BoardFrame", -34.3, -10.7, 20.7, 21, -1.4, -0.4, STEEL, Enum.Material.Metal)
	box("BoardFrame", -34.3, -10.7, 5, 5.3, -1.4, -0.4, STEEL, Enum.Material.Metal)
	box("BoardFrame", -34.3, -34, 5, 21, -1.4, -0.4, STEEL, Enum.Material.Metal)
	box("BoardFrame", -11, -10.7, 5, 21, -1.4, -0.4, STEEL, Enum.Material.Metal)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN.X / 23
	gui.LightInfluence = 0
	gui.Parent = plate

	text(gui, "Heading", "LEADERBOARD", FONT_DISPLAY, 22, TEXT, 18, 8, 300, 30, Enum.TextXAlignment.Left)
	local dash = Instance.new("Frame")
	dash.Name = "Dash"
	dash.BorderSizePixel = 0
	dash.BackgroundColor3 = AMBER
	dash.Position = UDim2.fromScale(18 / SIGN.X, 42 / SIGN.Y)
	dash.Size = UDim2.fromScale(44 / SIGN.X, 3 / SIGN.Y)
	dash.Parent = gui

	rowLabels = {}
	for index, board in Leaderboards.Config.Boards do
		local x0 = 18 + (index - 1) * 220
		text(gui, "Title_" .. board.id, board.title, FONT_SANS, 17, AMBER, x0, 50, 200, 22, Enum.TextXAlignment.Left)
		rowLabels[board.id] = {}
		for row = 1, Leaderboards.Config.Top do
			local y = 74 + (row - 1) * 24
			local nameLabel = text(gui, `Name_{board.id}_{row}`, "", FONT_SANS, 15, TEXT, x0, y, 150, 22, Enum.TextXAlignment.Left)
			local valueLabel = text(gui, `Value_{board.id}_{row}`, "", FONT_MONO, 15, MUTED, x0 + 148, y, 52, 22, Enum.TextXAlignment.Right)
			rowLabels[board.id][row] = { name = nameLabel, value = valueLabel }
		end
	end
	local unavailable = text(gui, "Unavailable", "Leaderboard unavailable", FONT_SANS, 18, MUTED, 18, 120, 424, 40, Enum.TextXAlignment.Left)
	notice = unavailable
	everRead = false
	render()

	model.Parent = folder
	Leaderboards._start()
	return model
end

local started = false
function Leaderboards._start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		-- The first read happens a moment after the server starts, then every ReadGap
		task.wait(5)
		local sinceRead = Leaderboards.Config.ReadGap
		while true do
			if sinceRead >= Leaderboards.Config.ReadGap then
				sinceRead = 0
				pcall(Leaderboards.refresh)
			end
			pcall(Leaderboards.flush)
			task.wait(Leaderboards.Config.FlushGap)
			sinceRead += Leaderboards.Config.FlushGap
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pcall(Leaderboards.forget, player.UserId)
	end)
end

return Leaderboards
