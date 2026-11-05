-- Nameplate render (BillboardGui contents shown on a flat panel): lune run nameplate_dump.luau <place> <outdir> [WxH]
-- for render.py. Usage: lune run dump.luau <place> <outdir>
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Engine = require("../../tests/smoke/Engine")
local world = Engine.load(process.args[1])
local outDir = process.args[2]
local game = world.game
local roblox = require("@lune/roblox") :: any
local task = Engine.task

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."

local dump = require("./dumpcommon")

-- Bring the interface up like the game does
local Input = world.require(world.find(CLIENT .. "Controllers.InputController"))
local UIController = world.require(world.find(CLIENT .. "Controllers.UIController"))
local fakeInput = { Bindings = Input.Bindings, device = function()
	return "keyboard"
end }
local Abilities = world.require(world.find(CLIENT .. "Controllers.AbilityController"))
Abilities:Init({ PowerFxController = { predict = function() end }, InputController = fakeInput })
if process.args[3] then
	local w, h = string.match(process.args[3], "(%d+)x(%d+)")
	world.camera.ViewportSize = roblox.Vector2.new(tonumber(w), tonumber(h))
end
UIController:Init({
	AbilityController = Abilities,
	InputController = fakeInput,
	EffectsController = { currentGuard = function()
		return 70
	end },
})
-- A character so the HUD shows
local character = Engine.character("Tester")
character.Parent = world.workspace
pcall(function()
	world.localPlayer.Character = character
end)
character:SetAttribute("HeavyReadyAt", 1000 + 2.2)
character:SetAttribute("SNPower", "StrongDude")
character:SetAttribute("SNDegree", 1)
character:SetAttribute("SNLoadout", "Groundbreaker,TitanGrip,MeteorCharge")
character:SetAttribute("SNRes", 12)
character:SetAttribute("SNResMax", 100)
character:SetAttribute("SNUlt", 100)
character:SetAttribute("SNCD_TitanGrip", world.workspace:GetServerTimeNow() + 5)
UIController:Start()
local Shell = world.require(world.find(CLIENT .. "UI.Shell"))
local gui = world.localPlayer.PlayerGui:FindFirstChild("SNInterface")
local dataEvent = world.find("ReplicatedStorage.Remotes.DataEvent")
local matchEvent = world.find("ReplicatedStorage.Remotes.MatchEvent")
local function fireData(kind, data)
	Engine.signalOf(dataEvent, "OnClientEvent"):Fire(kind, data)
end
local function fireMatch(kind, data)
	Engine.signalOf(matchEvent, "OnClientEvent"):Fire(kind, data)
end
local function settle()
	task.wait(0.15)
	Engine.step(game, 30, 0.05)
	task.wait(0.15)
end

local function snap(name: string)
	settle()
	local camera = world.camera
	local inset = 58
	local data = {
		viewport = { camera.ViewportSize.X, camera.ViewportSize.Y },
		inset = inset,
		scale = gui:FindFirstChildOfClass("UIScale").Scale,
		tree = dump(gui),
	}
	fs.writeFile(`{outDir}/{name}.json`, serde.encode("json", data))
	print("dumped " .. name)
end

local Cosmetics = world.require(world.find("ReplicatedStorage.Shared.Config.Cosmetics"))
Cosmetics.add("plate_preview", { kind = "plate", name = "Amber Line", colors = { { 232, 162, 74 }, { 63, 214, 232 } }, source = "season", how = "x" })
local Nameplates = world.require(world.find(CLIENT .. "Controllers.NameplateController"))
local Instance, UDim2, Vector2, Color3 = world.Instance, roblox.UDim2, roblox.Vector2, roblox.Color3
local board = Instance.new("ScreenGui")
board.Name = "NameplatePreview"
board.Parent = world.localPlayer.PlayerGui
Instance.new("UIScale").Parent = board
local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromOffset(1280, 720)
backdrop.BackgroundColor3 = Color3.fromRGB(46, 58, 74)
backdrop.BorderSizePixel = 0
backdrop.Parent = board
local samples = {
	{ "Alice D", "Founding Recruit", "plate_preview" },
	{ "Marco", "Unbroken", "" },
	{ "Jun the Long Display Name", "Fully Mastered Specialist", "plate_preview" },
	{ "Priya", "", "" },
}
for index, sample in samples do
	local player = Instance.new("Player")
	player.DisplayName = sample[1]
	player:SetAttribute("SNTitle", sample[2])
	player:SetAttribute("SNPlate", sample[3])
	local plate = Nameplates.build(player, nil)
	local column = plate:FindFirstChild("Column")
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.fromOffset(240 + ((index - 1) % 2) * 480, 220 + math.floor((index - 1) / 2) * 200)
	column.Size = UDim2.fromOffset(220, plate.Size.Y.Offset)
	column.Parent = backdrop
end
gui = board
snap("nameplates")
process.exit(0)
