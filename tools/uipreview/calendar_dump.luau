-- Gift calendar window renders: lune run calendar_dump.luau <place> <outdir> [WxH]
-- for render.py. Shows day 12 of the Harvest Calendar with some days claimed, and the window
-- between calendars.
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

local Calendars = world.require(world.find("ReplicatedStorage.Shared.Config.Calendars"))
local CalendarWindow = world.require(world.find(CLIENT .. "UI.CalendarWindow"))
local harvest = Calendars.List.harvest_2026
CalendarWindow.register()
local claimed = { ["1"] = true, ["2"] = true, ["3"] = true, ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true, ["10"] = true, ["12"] = true }
fireData("Profile", {
	currencies = { money = 2400, gems = 40 },
	selected = { power = "StrongDude", degree = 1 },
	settings = {},
	passes = {},
	calendars = { harvest_2026 = { claimed = claimed, perfect = false, milestones = { ["5"] = true } } },
	trials = {},
})
local size = process.args[3] or "default"
local function state(day)
	return {
		kind = "State",
		serverNow = harvest.startsAt + (day - 1) * 86400 + 3600 * 14,
		catchUp = 1,
		calendar = "harvest_2026",
		today = day,
		claimed = claimed,
		count = 9,
		perfect = false,
		milestones = { ["5"] = true },
	}
end
fireData("Calendar", state(12))
Shell.open("Calendar")
task.wait(0.4)
snap(`calendar_{size}`)
-- A day with two open gifts (yesterday missed, today ready)
fireData("Calendar", state(13))
snap(`calendar_open_{size}`)
Shell.close()
fireData("Calendar", { kind = "State", serverNow = harvest.startsAt - 5 * 86400, catchUp = 1, nextId = "harvest_2026", nextStartsAt = harvest.startsAt })
fireData("Profile", { currencies = { money = 0, gems = 0 }, selected = { power = "StrongDude", degree = 1 }, settings = {}, passes = {}, calendars = {}, trials = {} })
Shell.open("Calendar")
task.wait(0.4)
snap(`calendar_none_{size}`)
process.exit(0)
