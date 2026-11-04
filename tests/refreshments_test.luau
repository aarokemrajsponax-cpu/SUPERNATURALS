-- The Lounge refreshments counter (DECISIONS 23), on the real server services (stand-in engine):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/refreshments_test.luau build/game.rbxl
-- Money only (never Gems or Robux), server-validated, cooldown, no stacking, effects are temporary,
-- the experience boost never applies in Duel and never exceeds the cap, nothing touches combat stats.

local process = require("@lune/process")
local World = require("./smoke/World")

-- Capture the reward modifiers the services register (RefreshmentService's among them)
local modifiers = {}
local game = World.start(process.args[1] or "build/game.rbxl", function(setup)
	local Progression = setup.world.require(setup.world.find("ServerScriptService.Server.Services.ProgressionService"))
	local original = Progression.addRewardModifier
	Progression.addRewardModifier = function(self, modifier)
		table.insert(modifiers, modifier)
		return original(self, modifier)
	end
end)
local task, services, check, request = game.task, game.services, game.check, game.request
local world = game.world

local Config = world.require(world.find("ReplicatedStorage.Shared.Config.Refreshments"))
local Monetization = world.require(world.find("ReplicatedStorage.Shared.Config.Monetization"))
local Protocol = world.require(world.find("ReplicatedStorage.Shared.Protocol"))

local Data, Refreshments = services.DataService, services.RefreshmentService
local now = 1000
Refreshments.clock = function()
	return now
end

local function profile(player)
	return Data:get(player)
end
local function buy(player, id)
	task.wait(0.6) -- the request limiter refills over time
	local mark = game.mark()
	request("LoungeRequest", player, Protocol.LoungeAction.BuyRefreshment, id)
	task.wait(0.1)
	local replies = game.sentSince(mark, "DataEvent", "Lounge", player)
	for _, reply in replies do
		if reply.kind == "Bought" then
			return reply
		end
	end
	return nil
end

local alice = game.join("Alice", 9101)
game.waitFor(function()
	return profile(alice) ~= nil
end, 3, "profile")
profile(alice).currencies.money = 2000
profile(alice).currencies.gems = 77

check("the menu is original, priced in Money, and no item can be bought with Robux", function()
	assert(#Config.Items >= 5, "a real menu")
	local seen = {}
	for _, item in Config.Items do
		assert(not seen[item.id], "unique id")
		seen[item.id] = true
		assert(item.price > 0 and item.price <= 500 and item.seconds > 0 and item.seconds <= Config.MaxSeconds, "price and duration")
		assert(item.boost >= 0 and item.boost <= Config.MaxBoost, "boost within the cap")
		assert(#item.blurb > 20 and not string.find(item.blurb, "—", 1, true), "plain text")
		if item.boost > 0 then
			assert(string.find(item.blurb, "Not in Duels", 1, true), "the card says where it does not work")
		end
		assert(item.gems == nil and item.robux == nil and item.product == nil, "Money only")
	end
	for key, product in Monetization.Products do
		assert(not string.find(string.lower(product.name), "refresh") and product.refreshment == nil, "no refreshment product: " .. key)
	end
	assert(Config.BoostModes.Duel == nil and Config.BoostModes.FreeForAll and Config.BoostModes.Practice)
end)

check("buying takes Money only, validates the item, and gives a temporary effect", function()
	local money, gems = profile(alice).currencies.money, profile(alice).currencies.gems
	assert(buy(alice, "nonsense").ok == false and buy(alice, 5) and profile(alice).currencies.money == money, "unknown items are refused")
	now += 100
	local reply = buy(alice, "power_smoothie")
	assert(reply and reply.ok, "bought")
	assert(profile(alice).currencies.money == money - 200 and profile(alice).currencies.gems == gems, "200 Money, no Gems")
	assert(profile(alice).lounge.refreshments == 1)
	local effect = Refreshments:current(alice)
	assert(effect and effect.item.id == "power_smoothie" and effect.endsAt == now + 420, "runs for the stated time")
	local root = alice.Character and alice.Character:FindFirstChild("HumanoidRootPart")
	assert(root and root:FindFirstChildOfClass("PointLight") and root:FindFirstChildOfClass("ParticleEmitter"), "a glow and a spark trail")
	local state = Refreshments:state(alice)
	assert(state.active and state.active.id == "power_smoothie" and state.active.left == 420 and state.cooldownLeft == Config.Cooldown, "state shows time left and the cooldown")
end)

check("the boost works in casual modes, never in Duel, and is capped", function()
	assert(Refreshments:boostFor(alice, "Duel") == 0, "no boost in Duel")
	assert(Refreshments:boostFor(alice, "Ranked") == 0 and Refreshments:boostFor(alice, nil) == 0 and Refreshments:boostFor(alice, 7) == 0, "unknown modes get nothing")
	local casual = Refreshments:boostFor(alice, "FreeForAll")
	assert(casual == 0.1 and Refreshments:boostFor(alice, "Practice") == 0.1, "a small boost in casual modes")
	assert(casual <= Config.MaxBoost)
	-- The reward modifier registered with the progression service follows the same rule
	local found = false
	for _, modifier in modifiers do
		local ok, multiplier, label = pcall(modifier, alice, { modeName = "FreeForAll" }, {})
		if ok and label == "Refreshment" then
			found = true
			assert(multiplier == 1.1, "casual match: " .. tostring(multiplier))
			local duel, duelLabel = modifier(alice, { modeName = "Duel" }, {})
			assert(duel == nil and duelLabel == nil, "no bonus in a Duel")
		end
	end
	assert(found, "RefreshmentService registered a reward modifier")
end)

check("cooldown: nothing else can be bought straight away", function()
	local money = profile(alice).currencies.money
	local reply = buy(alice, "pulse_drink")
	assert(reply and reply.ok == false and string.find(reply.text, "moment", 1, true), "cooling down: " .. tostring(reply and reply.text))
	assert(profile(alice).currencies.money == money, "nothing taken")
	now += Config.Cooldown + 1
	local again = buy(alice, "power_smoothie")
	assert(again.ok == false and string.find(again.text, "already", 1, true), "the same item cannot be bought while it runs")
	assert(profile(alice).currencies.money == money)
end)

check("nothing stacks: a new item replaces the running one", function()
	local reply = buy(alice, "recharge_capsule")
	assert(reply.ok)
	local effect = Refreshments:current(alice)
	assert(effect.item.id == "recharge_capsule", "replaced")
	assert(Refreshments:boostFor(alice, "FreeForAll") == 0.05, "the new boost only, not the sum")
end)

check("not enough Money: refused and nothing taken", function()
	now += Config.Cooldown + 1
	profile(alice).currencies.money = 10
	local reply = buy(alice, "focus_bar")
	assert(reply.ok == false and profile(alice).currencies.money == 10 and Refreshments:current(alice).item.id == "recharge_capsule", "nothing changed")
	profile(alice).currencies.money = 2000
end)

check("effects are temporary: the boost and the look end on their own", function()
	now += 1000
	assert(Refreshments:current(alice) == nil and Refreshments:boostFor(alice, "FreeForAll") == 0, "ended by the clock")
	assert(Refreshments:state(alice).active == nil)
	-- A short-lived item, so the real timer that removes the look can run inside the test
	local item = Config.byId("pulse_drink")
	local seconds = item.seconds
	item.seconds = 1
	now += Config.Cooldown + 1
	local reply = buy(alice, "pulse_drink")
	item.seconds = seconds
	assert(reply and reply.ok, "bought a one second drink")
	local root = alice.Character:FindFirstChild("HumanoidRootPart")
	assert(root:FindFirstChildOfClass("PointLight") ~= nil, "glowing")
	task.wait(1.8)
	assert(root:FindFirstChildOfClass("PointLight") == nil and root:FindFirstChildOfClass("ParticleEmitter") == nil, "the glow is gone")
	assert(Refreshments:state(alice).active == nil, "nothing active")
end)

check("combat stats are untouched by any refreshment", function()
	local before = {}
	for key, value in profile(alice).stats do
		before[key] = value
	end
	local selected = profile(alice).selected.power
	for _, item in Config.Items do
		now += Config.Cooldown + 1
		buy(alice, item.id)
		now += item.seconds + 1
	end
	for key, value in profile(alice).stats do
		assert(before[key] == value, "stat unchanged: " .. key)
	end
	assert(profile(alice).selected.power == selected)
	for name in alice.Character:GetAttributes() do
		assert(not string.find(string.lower(name), "refresh"), "no combat attribute carries a refreshment: " .. name)
	end
end)

check("a player who leaves keeps nothing running", function()
	now += Config.Cooldown + 1
	buy(alice, "pulse_drink")
	assert(Refreshments:current(alice) ~= nil)
	game.leave(alice)
	assert(Refreshments:current(alice) == nil, "cleared with the player")
end)

process.exit(if game.finish() == 0 then 0 else 1)
