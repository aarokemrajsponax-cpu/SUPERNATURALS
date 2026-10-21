-- Runs real game code against the stand-in engine (tests/smoke/Engine.luau):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke.luau build/game.rbxl
-- Covers: arenas, every holiday's decorations, every UI screen (including the
-- owner panel), every admin event's visuals, and the client's combat-event
-- handling. Any invalid property, wrong value type or runtime error fails.

local process = require("@lune/process")

local Engine = require("./smoke/Engine")

local placePath = process.args[1] or "build/game.rbxl"
local world = Engine.load(placePath)
local game = world.game
local task = Engine.task
local roblox = require("@lune/roblox") :: any
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3

local passed, failed = 0, 0
local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("ok   " .. name)
	else
		failed += 1
		print("FAIL " .. name)
		print("     " .. tostring(err))
	end
end

local function count(root, className: string): number
	local total = 0
	for _, item in root:GetDescendants() do
		if item:IsA(className) then
			total += 1
		end
	end
	return total
end

-- Server: arenas ----------------------------------------------------------------------
local services = {}
check("ArenaService builds the training ground and arenas", function()
	local ArenaService = world.require(world.find("ServerScriptService.Server.Services.ArenaService"))
	services.ArenaService = ArenaService
	ArenaService:Init(services)
	ArenaService:Start()
	local first = ArenaService:reserve()
	local second = ArenaService:reserve()
	assert(first and second and first ~= second, "two arenas for two matches")
	assert(#first.spawns == 4, "four spawns")
	ArenaService:release(first)
	assert(ArenaService:reserve() == first, "released arenas are reused")
	assert(ArenaService:isOutOfBounds(first, first.center + Vector3.new(0, -50, 0)), "falling is out of bounds")
	assert(not ArenaService:isOutOfBounds(first, first.center + Vector3.new(0, 3, 0)), "the middle is in bounds")
	print(`     arenas: {count(world.workspace.Arenas, "BasePart")} parts, training ground: {count(world.workspace.TrainingGround, "BasePart")} parts`)
end)

-- Server: seasonal decorations --------------------------------------------------------------
check("every holiday's decorations build without errors", function()
	local SeasonalDecor = world.require(world.find("ServerScriptService.Server.SeasonalDecor"))
	for _, id in { "Halloween", "Thanksgiving", "Christmas", "NewYears", "Valentines", "StPatricks", "Easter" } do
		SeasonalDecor.build(id)
		local folder = world.workspace:FindFirstChild("SeasonalDecor")
		assert(folder, id .. " made no folder")
		local parts = count(folder, "BasePart")
		assert(parts > 20, `{id} only made {parts} parts`)
		print(`     {id}: {parts} parts`)
		SeasonalDecor.clear()
	end
end)

-- Client: UI ----------------------------------------------------------------------------------
local screen = world.Instance.new("ScreenGui")
screen.Parent = world.localPlayer.PlayerGui

check("HUD builds and updates", function()
	local Hud = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.Hud"))
	local Input = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Controllers.InputController"))
	local hud = Hud.build(screen, Input.Bindings, function()
		return "keyboard"
	end, function()
		return 50
	end)
	hud.update()
end)

check("fight menu builds, queues and shows the queue pill", function()
	local Menu = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.Menu"))
	local queued
	local menu = Menu.build(screen, {
		queue = function(mode)
			queued = mode
		end,
		leaveQueue = function() end,
		travel = function() end,
	})
	menu.setQueue({ mode = "Duel", displayName = "Duel", queued = 1, needed = 2, max = 2 })
	menu.update()
	menu.setQueue({ mode = "FreeForAll", displayName = "Free-for-All", queued = 3, needed = 3, max = 4, startsAt = 1010 })
	menu.update()
	menu.setQueue(nil)
	menu.setAllowed(false)
	menu.setAllowed(true)
	local _ = queued
end)

check("match HUD: countdown, fight, knockouts, results, clear", function()
	local MatchHud = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.MatchHud"))
	local hud = MatchHud.build(screen, function() end)
	local snapshot = {
		id = "m",
		mode = "Duel",
		modeName = "Duel",
		arena = "Proving Grounds",
		phase = "Countdown",
		phaseEndsAt = 1005,
		participants = {
			{ id = "Player:0", name = "Tester", score = 0, knockouts = 0, left = false, npc = false },
			{ id = "Npc:1", name = "Sparring Dummy", score = 0, knockouts = 0, left = false, npc = true },
		},
	}
	hud.setState(snapshot)
	hud.update()
	local active = table.clone(snapshot)
	active.phase = "Active"
	active.phaseEndsAt = 1180
	hud.setState(active)
	hud.update()
	hud.addKnockout({ victim = "Sparring Dummy", credited = "Tester" })
	hud.addKnockout({ victim = "Tester" })
	local sudden = table.clone(active)
	sudden.phase = "SuddenDeath"
	hud.setState(sudden)
	hud.update()
	hud.showResults({
		reason = "TimeUp",
		draw = false,
		winners = { "Tester" },
		winnerIds = { "Player:0" },
		ranking = {
			{ id = "Player:0", name = "Tester", score = 1, knockouts = 1, deaths = 0, left = false },
			{ id = "Npc:1", name = "Sparring Dummy", score = -1, knockouts = 0, deaths = 1, left = false },
		},
		returnsAt = 1200,
	})
	hud.update()
	hud.clear()
end)

check("settings panel builds", function()
	local SettingsPanel = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.SettingsPanel"))
	SettingsPanel.build(screen)
end)

check("owner panel builds, opens, and every tab renders", function()
	local OwnerPanel = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.UI.OwnerPanel"))
	local sent = {}
	OwnerPanel.build(screen, function(action, first, second)
		table.insert(sent, { action, first, second })
	end)
	OwnerPanel.setOpen(true)
	Engine.step(game, 3)
	OwnerPanel.toggle()
	local window = screen:FindFirstChild("OwnerPanel")
	assert(window, "panel window exists")
	local buttons = count(window, "TextButton")
	assert(buttons > 40, `only {buttons} buttons in the owner panel`)
	-- Press every button once (danger buttons need two presses, which also works)
	for _, item in window:GetDescendants() do
		if item:IsA("TextButton") then
			Engine.signalOf(item, "Activated"):Fire()
		end
	end
	print(`     owner panel: {buttons} buttons, {#sent} requests sent by pressing them`)
	assert(#sent > 20, "pressing the buttons sends requests")
end)

-- Client: effects ---------------------------------------------------------------------------
check("every admin event's visuals start, animate and stop", function()
	local AdminEvents = world.require(world.find("ReplicatedStorage.Shared.Config.AdminEvents"))
	local folder = world.find("StarterPlayer.StarterPlayerScripts.Client.Effects.AdminEvents")
	for _, id in AdminEvents.Order do
		local handlers = {}
		local running = true
		local context = {
			def = AdminEvents.Events[id],
			center = Vector3.new(0, 0, 0),
			startedAt = 1000,
			endsAt = 1030,
			running = function()
				return running
			end,
			on = function(kind, handler)
				handlers[kind] = handler
			end,
			shake = function() end,
		}
		local stop = world.require(folder:FindFirstChild(id))(context)
		Engine.step(game, 5)
		for kind, handler in handlers do
			local now = 1000
			handler({ position = Vector3.new(3, 0, 4), impactAt = now + 0.01, size = 4 })
			if kind then
				task.wait(0.05)
			end
		end
		Engine.step(game, 5)
		assert(typeof(stop) == "function", id .. " must return a stop function")
		running = false
		stop()
		Engine.step(game, 2)
	end
	task.wait(0.2)
end)

check("Vfx helpers all run", function()
	local Vfx = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Effects.Vfx"))
	local model = world.Instance.new("Model")
	local root = world.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = model
	local arm = world.Instance.new("Part")
	arm.Name = "RightUpperArm"
	arm.Parent = model
	model.Parent = world.workspace
	Vfx.sparks(Vector3.zero, Color3.new(1, 1, 1), 10)
	Vfx.shockwave(Vector3.zero, Color3.new(1, 0, 0), 1, 5, 0.2)
	Vfx.groundRing(Vector3.zero, Color3.new(1, 0, 0), 1, 5, 0.2)
	Vfx.slash(CFrame.new(), Color3.new(1, 1, 1), 4, 25, 0.1)
	Vfx.popup(Vector3.zero, "12", Color3.new(1, 1, 1), 1)
	Vfx.flash(model, Color3.new(1, 1, 1))
	Vfx.afterimage(model, Color3.new(0, 1, 1))
	Vfx.telegraph(root, Color3.new(1, 0, 0), 0.3)
	for _, name in { "LightSwing", "HeavySwing", "Hit", "HeavyHit", "Block", "Parry", "GuardBreak", "Dodge", "Countdown" } do
		Vfx.sound(name, root)
	end
	task.wait(0.1)
end)

check("client combat effects handle every server event", function()
	local controllers = {}
	for _, name in { "CameraController", "EffectsController", "AdminEffectsController" } do
		controllers[name] = world.require(world.find("StarterPlayer.StarterPlayerScripts.Client.Controllers." .. name))
	end
	for _, controller in controllers do
		if controller.Init then
			controller:Init(controllers)
		end
	end
	for _, controller in controllers do
		if controller.Start then
			task.spawn(controller.Start, controller)
		end
	end
	task.wait(0.05)

	-- Two fighters in the world
	local function fighter(name: string, x: number)
		local model = world.Instance.new("Model")
		model.Name = name
		local root = world.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(x, 3, 0)
		root.Parent = model
		local head = world.Instance.new("Part")
		head.Name = "Head"
		head.Parent = model
		local humanoid = world.Instance.new("Humanoid")
		humanoid.Parent = model
		model:SetAttribute("DisplayName", name)
		model:SetAttribute("Guard", 60)
		model:SetAttribute("GuardUpdatedAt", 999)
		model.Parent = world.workspace
		world.services.CollectionService:AddTag(model, "SNFighter")
		return model
	end
	local a = fighter("Alpha", 0)
	local b = fighter("Bravo", 4)
	b:SetAttribute("Blocking", true)
	Engine.signalOf(b, "Attribute:Blocking"):Fire()

	local combatEvent = world.find("ReplicatedStorage.Remotes.CombatEvent")
	local fire = function(kind, data)
		Engine.signalOf(combatEvent, "OnClientEvent"):Fire(kind, data)
	end
	for step = 1, 4 do
		fire("Attack", { attacker = a, kind = "Light", step = step, startup = 0.1, active = 0.1 })
	end
	fire("Attack", { attacker = a, kind = "Heavy", step = 1, startup = 0.5, active = 0.14 })
	for _, result in { "Hit", "Blocked", "GuardBreak", "Parried", "Invulnerable" } do
		fire("Hit", { attacker = a, victim = b, result = result, damage = 7, position = Vector3.new(4, 3, 0), heavy = result == "Hit", finisher = true, comboCapped = false })
	end
	fire("Dodge", { fighter = b, direction = Vector3.new(1, 0, 0) })
	fire("Hit", { attacker = "junk", victim = 5, result = "Hit" }) -- malformed data is ignored
	Engine.step(game, 10)
	task.wait(0.4)

	-- Admin visuals for everyone: announcement, an event, ice, auras
	local adminEvent = world.find("ReplicatedStorage.Remotes.AdminEvent")
	Engine.signalOf(adminEvent, "OnClientEvent"):Fire("Announce", { text = "Hello everyone!", from = "Owner" })
	local replicated = game:GetService("ReplicatedStorage")
	replicated:SetAttribute("AdminEventCenter", Vector3.zero)
	replicated:SetAttribute("AdminEventStartedAt", 1000)
	replicated:SetAttribute("AdminEventEndsAt", 1030)
	replicated:SetAttribute("AdminEvent", "MeteorShower")
	Engine.signalOf(replicated, "Attribute:AdminEvent"):Fire()
	Engine.signalOf(adminEvent, "OnClientEvent"):Fire("Meteor", { position = Vector3.new(2, 0, 2), impactAt = 1000, size = 4 })
	Engine.step(game, 5)
	replicated:SetAttribute("AdminEvent", "")
	Engine.signalOf(replicated, "Attribute:AdminEvent"):Fire()
	a:SetAttribute("SNIced", true)
	Engine.signalOf(a, "Attribute:SNIced"):Fire()
	a:SetAttribute("SNIced", nil)
	Engine.signalOf(a, "Attribute:SNIced"):Fire()
	task.wait(0.3)
end)

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
