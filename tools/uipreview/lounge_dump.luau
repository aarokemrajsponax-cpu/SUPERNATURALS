-- Lounge window renders: lune run lounge_dump.luau <place> <outdir> [WxH]
-- for render.py. The Wheel window (free spin ready with paid spins on offer, a restricted player,
-- a result) and the Refreshments menu.
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

local WheelWindow = world.require(world.find(CLIENT .. "UI.WheelWindow"))
local RefreshmentsWindow = world.require(world.find(CLIENT .. "UI.RefreshmentsWindow"))
local size = process.args[3] or "default"
fireData("Profile", {
	currencies = { money = 150, gems = 40 },
	selected = { power = "StrongDude", degree = 1 },
	settings = {},
	passes = {},
	calendars = {},
	trials = {},
})
-- Wheel: free spin ready, paid spins offered (products not created yet: Available soon)
WheelWindow.onData({
	kind = "Wheel", freeReady = true, paidAllowed = true, credits = 2, spins = 7, last = { "money500", "gems10", "money200" },
	products = { LoungeSpin = { spins = 1, onSale = false }, LoungeSpin5 = { spins = 5, onSale = false } },
})
Shell.open("Wheel")
task.wait(0.4)
snap(`wheel_{size}`)
-- A spin that lands on prize 7 (Corruption trial)
WheelWindow.onData({
	kind = "Spin", ok = true, index = 7, prizeId = "trialCorruption", text = "You won a Corruption trial, 24 hours. It starts now.", converted = false, source = "free",
	wheel = { kind = "Wheel", freeReady = false, paidAllowed = true, credits = 2, spins = 8, last = { "trialCorruption", "money500", "gems10" }, products = { LoungeSpin = { spins = 1, onSale = false }, LoungeSpin5 = { spins = 5, onSale = false } } },
})
for _ = 1, 14 do
	task.wait(0.5)
	Engine.step(game, 20, 0.05)
end
snap(`wheel_result_{size}`)
-- A restricted player: no paid spin controls anywhere
WheelWindow.onData({ kind = "Wheel", freeReady = false, paidAllowed = false, credits = 0, spins = 3, last = { "money200" }, products = {} })
snap(`wheel_restricted_{size}`)
Shell.close()
-- Refreshments with a running effect
RefreshmentsWindow.onData({ kind = "Refreshments", cooldownLeft = 12, active = { id = "recharge_capsule", name = "Recharge Capsule", left = 214, boost = 0.05 } })
Shell.open("Refreshments")
task.wait(0.4)
snap(`refreshments_{size}`)
process.exit(0)
