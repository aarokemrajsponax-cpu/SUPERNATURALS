-- Renders the combat interface in three states: the lobby (no combat HUD), a match, and a
-- match with the touch arch. Usage: lune run hud_dump.luau <place> <outdir> <WxH> <keyboard|touch|gamepad>
-- Writes lobby.json, match.json (and match_training.json) for render.py. The touch buttons
-- live in their own ScreenGui, so they are moved into a scaled frame inside the dump.
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Engine = require("../../tests/smoke/Engine")
local world = Engine.load(process.args[1])
local outDir = process.args[2]
local game = world.game
local roblox = require("@lune/roblox") :: any
local task = Engine.task
local kind = process.args[4] or "keyboard"

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
local dump = require("./dumpcommon")

local UserInputService = game:GetService("UserInputService")
UserInputService.TouchEnabled = kind == "touch"
UserInputService.KeyboardEnabled = kind ~= "touch"
Engine.lastInputType = if kind == "touch" then roblox.Enum.UserInputType.Touch elseif kind == "gamepad" then roblox.Enum.UserInputType.Gamepad1 else roblox.Enum.UserInputType.Keyboard

local w, h = string.match(process.args[3] or "1280x720", "(%d+)x(%d+)")
world.camera.ViewportSize = roblox.Vector2.new(tonumber(w), tonumber(h))

local character = Engine.character("Tester")
character.Parent = world.workspace
pcall(function()
	world.localPlayer.Character = character
end)
table.insert(Engine.players, world.localPlayer)
character:SetAttribute("SNPower", "StrongDude")
character:SetAttribute("SNDegree", 1)
character:SetAttribute("SNLoadout", "Groundbreaker,TitanGrip,MeteorCharge")
character:SetAttribute("SNRes", 42)
character:SetAttribute("SNResMax", 100)
character:SetAttribute("SNUlt", 100)
character:SetAttribute("SNCD_TitanGrip", world.workspace:GetServerTimeNow() + 5)
character:SetAttribute("SNCombatContext", "Lobby")

local controllers: any = {
	AbilityController = world.require(world.find(CLIENT .. "Controllers.AbilityController")),
	PowerFxController = { predict = function() end },
}
local NAMES = { "CameraController", "EffectsController", "CombatController", "InputController" }
for _, name in NAMES do
	controllers[name] = world.require(world.find(CLIENT .. "Controllers." .. name))
end
controllers.AbilityController:Init(controllers)
for _, name in NAMES do
	if controllers[name].Init then
		controllers[name]:Init(controllers)
	end
end
for _, name in NAMES do
	task.spawn(controllers[name].Start, controllers[name])
end
task.wait(0.1)
local UIController = world.require(world.find(CLIENT .. "Controllers.UIController"))
UIController:Init(controllers)
UIController:Start()
local Shell = world.require(world.find(CLIENT .. "UI.Shell"))
local gui = world.localPlayer.PlayerGui:FindFirstChild("SNInterface")
local touchGui = world.localPlayer.PlayerGui:FindFirstChild("SNTouchControls")
local function fire(remote, ...)
	Engine.signalOf(world.find("ReplicatedStorage.Remotes." .. remote), "OnClientEvent"):Fire(...)
end
fire("DataEvent", "Profile", {
	currencies = { money = 12500, gems = 340 },
	selected = { power = "StrongDude", degree = 1 },
	settings = {},
})
for _, spec in {
	{ "Shop", "coin", 4, "SHOP" },
	{ "Powers", "bolt", 2, "POWERS" },
	{ "Base", "home", 3, "BASE" },
	{ "Progress", "trophy", 5, "PROGRESS" },
	{ "Watch", "eye", 6, "WATCH" },
	{ "HowTo", "book", 7, "HOW TO" },
} do
	Shell.registerWindow(spec[1], { title = spec[1], label = spec[4], icon = spec[2], order = spec[3], build = function()
		return {}
	end })
end

local function settle()
	for _ = 1, 4 do
		task.wait(0.1)
		Engine.step(game, 8, 0.05)
	end
end

local function snap(name: string)
	settle()
	local holder
	if touchGui and touchGui.Enabled then
		holder = roblox.Instance.new("Frame")
		holder.Name = "TouchControlsPreview"
		holder.BackgroundTransparency = 1
		holder.Size = roblox.UDim2.fromScale(1, 1)
		local fix = roblox.Instance.new("UIScale")
		fix.Scale = 1 / gui:FindFirstChildOfClass("UIScale").Scale
		fix.Parent = holder
		holder.Parent = gui
		for _, child in touchGui:GetChildren() do
			if child:IsA("GuiObject") then
				child.Parent = holder
			end
		end
	end
	local data = {
		viewport = { world.camera.ViewportSize.X, world.camera.ViewportSize.Y },
		inset = 0,
		scale = gui:FindFirstChildOfClass("UIScale").Scale,
		tree = dump(gui),
	}
	fs.writeFile(`{outDir}/{name}.json`, serde.encode("json", data))
	print("dumped " .. name)
	if holder then
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child.Parent = touchGui
			end
		end
		holder:Destroy()
	end
end

local tag = `{w}x{h}_{kind}`
Shell.setMode("Lobby")
snap(`hud_lobby_{tag}`)

-- A friend is here
world.localPlayer:SetAttribute("SNFriendBonus", 20)
Engine.signalOf(world.localPlayer, "Attribute:SNFriendBonus"):Fire()
snap(`hud_lobby_friend_{tag}`)
world.localPlayer:SetAttribute("SNFriendBonus", nil)
Engine.signalOf(world.localPlayer, "Attribute:SNFriendBonus"):Fire()

-- A match
character:SetAttribute("SNCombatContext", "Match")
Shell.setMode("Match")
fire("MatchEvent", "State", {
	id = "m", mode = "Duel", modeName = "Duel", arena = "Proving Grounds", phase = "Active", phaseEndsAt = 1000 + 154,
	participants = {
		{ id = "Player:1", name = "Tester", score = 2, knockouts = 2, left = false, npc = false },
		{ id = "Player:2", name = "Nova", score = 1, knockouts = 1, left = false, npc = false },
	},
})
snap(`hud_match_{tag}`)

-- Training
fire("MatchEvent", "Ended")
character:SetAttribute("SNCombatContext", "Training")
snap(`hud_training_{tag}`)
process.exit(0)
