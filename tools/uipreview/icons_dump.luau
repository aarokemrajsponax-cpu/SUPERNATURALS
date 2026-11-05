-- Dumps every drawn icon (src/client/UI/Icons.luau) large on a dark sheet, for render.py.
-- Usage: lune run tools/uipreview/icons_dump.luau <place> <outdir> [size=64] [name,name,...]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox") :: any
local Engine = require("../../tests/smoke/Engine")
local dump = require("./dumpcommon")

local world = Engine.load(process.args[1])
local outDir = process.args[2]
local size = tonumber(process.args[3]) or 64
local Icons = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.Icons"))

local names = {}
if process.args[4] then
	for name in string.gmatch(process.args[4], "[^,]+") do
		table.insert(names, name)
	end
else
	local defs = Icons.names and Icons.names() or { "swords", "star", "learn", "gear", "eye", "home", "bag", "play", "fight", "shield", "target", "ghost" }
	names = defs
end

local cell = size + 40
local perRow = 8
local rows = math.ceil(#names / perRow)
local gui = roblox.Instance.new("ScreenGui")
gui.Name = "SNInterface"
local sheet = roblox.Instance.new("Frame")
sheet.Name = "Sheet"
sheet.Size = roblox.UDim2.fromOffset(cell * perRow, cell * rows)
sheet.BackgroundColor3 = roblox.Color3.fromRGB(18, 24, 36)
sheet.BorderSizePixel = 0
sheet.Parent = gui
for i, name in names do
	if not Icons.has(name) then
		print("no icon", name)
		continue
	end
	local col, row = (i - 1) % perRow, (i - 1) // perRow
	local holder = roblox.Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Position = roblox.UDim2.fromOffset(col * cell, row * cell)
	holder.Size = roblox.UDim2.fromOffset(cell, cell)
	holder.Parent = sheet
	local icon = Icons.make(name, size, roblox.Color3.fromRGB(110, 225, 245))
	icon.AnchorPoint = roblox.Vector2.new(0.5, 0)
	icon.Position = roblox.UDim2.new(0.5, 0, 0, 6)
	icon.Parent = holder
	local label = roblox.Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = roblox.UDim2.new(0, 0, 1, -22)
	label.Size = roblox.UDim2.new(1, 0, 0, 18)
	label.Text = name
	label.TextSize = 14
	label.TextColor3 = roblox.Color3.fromRGB(200, 205, 215)
	label.FontFace = roblox.Font.new("rbxasset://fonts/families/BuilderSans.json")
	label.Parent = holder
end
local data = { viewport = { cell * perRow, cell * rows }, inset = 0, scale = 1, tree = dump(gui) }
fs.writeFile(`{outDir}/icons.json`, serde.encode("json", data))
print("dumped icons", #names)
process.exit(0)
