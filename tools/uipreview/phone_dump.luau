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

-- Opens every registered window in turn (the ones the other dumps do not cover) and dumps each.
-- Usage: lune run phone_dump.luau <place> <outdir> <WxH> [Id,Id,...]
fireData("Profile", {
	currencies = { money = 2400, gems = 40 },
	selected = { power = "StrongDude", degree = 1 },
	settings = {},
	passes = {},
	stats = { wins = 37, matches = 80, knockouts = 140, bestStreak = 6, playSeconds = 5400 },
	powers = { Ghost = { xp = 3700 }, StrongDude = { xp = 900 } },
	lore = { found = { ajkr_first_entry = true, lantern_field_note = true, procurement_memo = true } },
	cosmetics = { owned = {}, equipped = {} },
	achievements = { done = {}, progress = {} },
})
fireData("Persistence", { saving = false })
local ids = if process.args[4] then string.split(process.args[4], ",") else { "Watch", "Practice", "Archive", "AskJeffery", "Learn", "Settings", "Locker", "Powers", "Play", "Shop", "SeasonPass", "Calendar" }
for _, id in ids do
	if Shell.hasWindow(id) then
		Shell.open(id)
		snap("win_" .. id)
		Shell.close()
	else
		print("no window " .. id)
	end
end
