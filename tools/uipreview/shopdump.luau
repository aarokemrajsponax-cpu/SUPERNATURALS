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

local Monetization = world.require(world.find("ReplicatedStorage.Shared.Config.Monetization"))
local ShopWindow = world.require(world.find(CLIENT .. "UI.ShopWindow"))
local PriceFetcher = world.require(world.find(CLIENT .. "PriceFetcher"))
ShopWindow.register()
fireData("Profile", { currencies = { money = 12500, gems = 4200 }, selected = { power = "StrongDude", degree = 1 }, settings = {}, passes = { SyntaxPower = true } })
Monetization.Passes.CorruptionPower.id = 71
Monetization.Passes.SyntaxPower.id = 72
Monetization.Products.GemsSmall.id = 81
Monetization.Products.GemsMedium.id = 82
Monetization.Products.GemsLarge.id = 83
Engine.marketplace.prices[71] = 4999
Engine.marketplace.prices[72] = 7499
Engine.marketplace.prices[81] = 39
Engine.marketplace.prices[82] = 149
Engine.marketplace.prices[83] = 339
PriceFetcher.clear()
local function press(b) Engine.signalOf(b, "Activated"):Fire() end
local function find(root, name) for _, i in root:GetDescendants() do if i.Name == name then return i end end end
Shell.open("Shop")
task.wait(0.3)
for _, id in { "Powers", "GemPowers", "Gems", "Upgrades", "Cosmetics" } do
	press(find(gui, "Rail_" .. id))
	task.wait(0.4)
	press(find(gui, "Rail_" .. id))
	snap(`shop_{id}_{process.args[3] or "default"}`)
end
process.exit(0)
