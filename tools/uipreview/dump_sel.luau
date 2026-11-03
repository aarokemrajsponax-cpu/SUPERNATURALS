-- Drives the real interface into a few states and dumps the GUI tree as JSON
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

fireData("Profile", {
	currencies = { money = 12500, gems = 340 },
	selected = { power = "StrongDude", degree = 1 },
	settings = {},
})
fireData("Persistence", { saving = false })
Shell.registerWindow("Shop", { title = "Shop", icon = "🛒", order = 4, build = function(body)
	return {}
end })
for _, spec in {
	{ "Base", "🏠", 3, "BASE" },
	{ "Progress", "🏆", 5, "PROGRESS" },
	{ "Watch", "📺", 6, "WATCH" },
	{ "HowTo", "📖", 7, "HOW TO" },
} do
	Shell.registerWindow(spec[1], { title = spec[1], label = spec[4], icon = spec[2], order = spec[3], build = function()
		return {}
	end })
end
Shell.setNavBadge("Progress", "!")
fireMatch("Queue", { mode = "Duel", displayName = "Duel", queued = 1, needed = 2, max = 2 })
Shell.open("Play")
snap("sel_play")
Shell.open("Play", { mode = "Training" })
snap("sel_play_training")
Shell.open("Play", { mode = "Duel", fighter = "Corruption" })
snap("sel_play_premium")
Shell.open("Powers")
snap("sel_powers_strong")
local function press(name)
	local b = gui:FindFirstChild(name, true)
	if b then Engine.signalOf(b, "Activated"):Fire() end
end
press("Card_Corruption")
snap("sel_powers_corruption")
local tabs = {}
for _, b in gui:FindFirstChild("PhaseTabs", true):GetDescendants() do if b:IsA("TextButton") then table.insert(tabs, b) end end
if tabs[3] then Engine.signalOf(tabs[3], "Activated"):Fire() end
snap("sel_powers_corruption")
Shell.open("Settings")
snap("sel_settings")
Shell.close()
-- A match
Engine.signalOf(world.find("ReplicatedStorage.Remotes.DataEvent"), "OnClientEvent"):Fire("Profile", {
	currencies = { money = 5000, gems = 120 },
	selected = { power = "Syntax", degree = 1 },
	powers = { Syntax = { xp = 500, abilities = {} } },
	loadouts = {}, passes = {}, settings = {},
})
Engine.step(game, 3, 0.05)
local snapshot = {
	id = "m",
	mode = "FreeForAll",
	modeName = "Free-for-All",
	arena = "Proving Grounds",
	phase = "Active",
	phaseEndsAt = 1000 + 154,
	participants = {
		{ id = "Player:1", name = "Tester", score = 2, knockouts = 2, left = false, npc = false },
		{ id = "Player:2", name = "AVeryLongDisplayName_99", score = -1, knockouts = 0, left = false, npc = false },
		{ id = "Player:3", name = "Nova", score = 0, knockouts = 1, left = false, npc = false },
		{ id = "Player:4", name = "Quitter", score = 0, knockouts = 0, left = true, npc = false },
	},
}
fireMatch("State", snapshot)
fireMatch("Knockout", { victim = "Nova", credited = "Tester" })
fireMatch("Knockout", { victim = "AVeryLongDisplayName_99", credited = "Tester" })
fireMatch("Knockout", { victim = "Quitter" })
fireMatch("Notice", { text = "SUDDEN DEATH! Next knockout wins." })
Shell.toast("+25 💵 for a knockout", "reward")
Engine.step(game, 4, 0.05)
task.wait(0.1)
Engine.step(game, 4, 0.05)
print("slots", #Abilities:slots(), #Engine.errors, Engine.errors[1])
snap("match")

do
	local PromptController = world.require(world.find(CLIENT .. "Controllers.PromptController"))
	PromptController:Start()
	local part = roblox.Instance.new("Part")
	part.Parent = world.workspace
	local prompt = roblox.Instance.new("ProximityPrompt")
	prompt.ActionText = "Open the Powers window"
	prompt.ObjectText = "Statue of the Lantern"
	prompt.HoldDuration = 0.8
	prompt.KeyboardKeyCode = roblox.Enum.KeyCode.E
	prompt.Parent = part
	local service = game:GetService("ProximityPromptService")
	Engine.signalOf(service, "PromptShown"):Fire(prompt, roblox.Enum.ProximityPromptInputType.Keyboard)
	Engine.step(game, 6, 0.05)
	local sg = world.localPlayer.PlayerGui:FindFirstChild("SNPrompt")
	if sg then
		local holder = roblox.Instance.new("Frame")
		holder.Name = "PromptHolder"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = roblox.Vector2.new(0.5, 0.5)
		holder.Position = roblox.UDim2.fromScale(0.5, 0.5)
		holder.Size = roblox.UDim2.fromOffset(sg.Size.X.Offset, sg.Size.Y.Offset)
		holder.Parent = gui
		for _, c in sg:GetChildren() do c.Parent = holder end
		snap("prompt")
		holder:Destroy()
	else
		print("no prompt gui")
	end
end

fireMatch("Results", {
	reason = "TimeUp",
	draw = false,
	winners = { "Tester" },
	winnerIds = { "Player:1" },
	ranking = {
		{ id = "Player:1", name = "Tester", score = 2, knockouts = 2, deaths = 0, left = false },
		{ id = "Player:3", name = "Nova", score = 0, knockouts = 1, deaths = 1, left = false },
		{ id = "Player:2", name = "AVeryLongDisplayName_99", score = -1, knockouts = 0, deaths = 2, left = false },
		{ id = "Player:4", name = "Quitter", score = 0, knockouts = 0, deaths = 0, left = true },
	},
	returnsAt = 1000 + 30,
})
snap("results")
fireMatch("Ended", nil)

-- Phone
world.camera.ViewportSize = roblox.Vector2.new(844, 390)
Engine.signalOf(world.camera, "Property:ViewportSize"):Fire()
Shell.open("Play")
snap("phone_play")
Shell.close()
snap("phone_lobby")
process.exit(0)
