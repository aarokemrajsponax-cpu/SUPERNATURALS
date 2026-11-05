-- Locker window renders (cosmetics and achievements tabs) and a nameplate: lune run locker_dump.luau <place> <outdir> [WxH]
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
Cosmetics.add("plate_preview", { kind = "plate", name = "Amber Line", colors = { { 232, 162, 74 }, { 63, 214, 232 } }, source = "season", how = "Reach tier 5 of the season pass." })
fireData("Profile", {
	currencies = { money = 2400, gems = 40 },
	selected = { power = "StrongDude", degree = 1 },
	settings = {},
	passes = {},
	stats = { wins = 37, matches = 80, knockouts = 140, bestStreak = 6, playSeconds = 5400, predictionsCorrect = 2 },
	powers = { Ghost = { xp = 3700 }, StrongDude = { xp = 900 } },
	lore = { found = { ajkr_first_entry = true, lantern_field_note = true, procurement_memo = true } },
	cosmetics = { owned = { title_recruit = true, title_founding = true, title_veteran = true, plate_preview = true }, equipped = { title = "title_founding", plate = "plate_preview" } },
	achievements = { done = { win_1 = true, win_10 = true, match_25 = true, streak_3 = true, streak_5 = true, lore_1 = true, mastery_5 = true }, progress = { cleanWins = 6, practiceRounds = 3, watched = 4, used_Ghost = 1, used_StrongDude = 1, used_Syntax = 1 } },
})
local function press(b) Engine.signalOf(b, "Activated"):Fire() end
local function find(root, name) for _, i in root:GetDescendants() do if i.Name == name then return i end end end
local size = process.args[3] or "default"
Shell.open("Locker")
task.wait(0.3)
snap(`locker_cosmetics_{size}`)
for _, item in find(gui, "Window_Locker"):GetDescendants() do
	if item:IsA("TextButton") and string.find(string.lower(item.Text), "achievements", 1, true) then
		press(item)
		break
	end
end
task.wait(0.3)
snap(`locker_achievements_{size}`)
process.exit(0)
