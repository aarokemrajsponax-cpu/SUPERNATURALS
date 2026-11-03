-- Drives the Control Center with fixture answers and dumps Dashboard, events catalogue and custom creator.
-- Usage: lune run owner_dump.luau <place> <outdir> [WxH]
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

local function press(b) Engine.signalOf(b, "Activated"):Fire() end
local function find(root, name) for _, i in root:GetDescendants() do if i.Name == name then return i end end end
local CATEGORIES = { { id = "World", name = "World transformations" }, { id = "Environment", name = "Gravity and environment" }, { id = "Spectacle", name = "Spectacle and celebration" }, { id = "Christmas", name = "Christmas collection" } }
local NAMES = { "Golden World", "Neon Takeover", "Cosmic Atmosphere", "Starfield", "Aurora Sky", "Glowing Facility", "Dark Experimental Facility", "Digital Reality Distortion", "Holographic World", "Floating Energy Structures", "Meteor Shower Spectacle", "Massive Holographic Installation" }
local presets = {}
for i = 1, 90 do
	table.insert(presets, { id = `p_{i}`, name = NAMES[(i - 1) % #NAMES + 1] .. (if i > #NAMES then ` {i}` else ""), category = CATEGORIES[(i - 1) % 3 + 1].id, level = (i % 4) + 1,
		description = "Cyan holographic light, a soft glow and a lattice of light beams across the whole station.", duration = 900, tags = { "light", "glow", "night" }, effects = { "LightingTheme", "Weather" }, eventMode = false, ownerOnly = false })
end
local EFFECTS = {
	LightingTheme = { name = "LightingTheme", description = "Changes the light.", params = { theme = { type = "enum", options = { "golden", "neon" }, default = "golden" } } },
	Weather = { name = "Weather", description = "Falling particles over the whole station.", params = { kind = { type = "enum", options = { "rain", "snow" }, default = "rain" }, rate = { type = "number", min = 5, max = 100, default = 30, scales = true }, color = { type = "color", default = { 255, 255, 255 } } } },
}
local fixtures = {
	Catalogue = { ok = true, data = { categories = CATEGORIES, presets = presets, effects = EFFECTS } },
	State = { ok = true, data = { jobId = "abcdef1234567890", active = { { id = "e1", preset = "p_1", name = "Golden World", endsAt = os.time() + 754 }, { id = "e2", preset = "p_2", name = "Starfield", endsAt = os.time() + 95 } }, lastSync = os.time(), syncOk = true } },
	Servers = { ok = true, data = { { jobId = "abcdef1234567890", players = 12, events = { "e1", "e2" }, lastSync = os.time(), heartbeat = os.time(), current = true }, { jobId = "9f8e7d6c5b", players = 18, events = {}, lastSync = os.time() - 20, heartbeat = os.time() - 4, test = false } } },
	Audit = { ok = true, data = { entries = { { t = os.time() - 300, action = "remote:activate", scope = "here", outcome = "applied" }, { t = os.time() - 60, action = "remote:announce", scope = "all", outcome = "applied" }, { t = os.time() - 20, action = "remote:activate", scope = "here", outcome = "refused", reason = "performance_cap" } } } },
}
local served = #Engine.sent
local function serve()
	while served < #Engine.sent do
		served += 1
		local e = Engine.sent[served]
		if e.remote == "OverlordRequest" then
			Engine.signalOf(world.find("ReplicatedStorage.Remotes.OverlordEvent"), "OnClientEvent"):Fire("Result", e.args[1], fixtures[e.args[2]] or { ok = true, data = {} })
		end
	end
end
world.localPlayer:SetAttribute("SNIsOwner", true)
local OwnerController = world.require(world.find(CLIENT .. "Controllers.OwnerController"))
OwnerController:Start()
Engine.signalOf(world.localPlayer, "Attribute:SNIsOwner"):Fire()
task.wait(0.3)
Shell.open("OwnerCenter")
task.wait(0.2)
serve()
task.wait(0.2)
local tag = process.args[3] or "default"
snap("owner_dashboard_" .. tag)
press(find(gui, "Nav_world")); serve(); task.wait(0.2)
press(find(gui, "Card_p_4")); task.wait(0.2)
snap("owner_catalogue_" .. tag)
press(find(gui, "Nav_custom")); serve(); task.wait(0.2)
local page = find(gui, "Section_custom")
press(find(page, "AddEffect")); press(find(page, "Pick_Weather")); press(find(page, "Choose")); task.wait(0.2)
snap("owner_custom_" .. tag)
process.exit(0)
