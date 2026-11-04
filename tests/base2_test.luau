-- Hosting, the game room, base effects and the Fireworks Show (BaseService, GameRoomService,
-- World/GameRoom), run for real with simulated players on the stand-in engine:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/base2_test.luau build/game.rbxl
-- Access modes (and narrowing sends visitors out), ask-to-leave by the owner only, one heart per
-- visitor per UTC day, the host bonus once a day for friends after 60 s, the Power Meter score
-- from the server clock, the Reflex false start and timing, effects locked without the pass,
-- the Fireworks product granting one charge once per PurchaseId, jukebox, party mode, seats,
-- part budgets, and old profiles reading "Friends".

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any
local World = require("./smoke/World")

local PASS_ID, PRODUCT_ID = 7701, 7702
local api = World.start(process.args[1] or "build/game.rbxl", function(setup)
	local Monetization = setup.world.require(setup.world.find("ReplicatedStorage.Shared.Config.Monetization"))
	Monetization.Passes.BaseEffectsPack.id = PASS_ID
	Monetization.Products.FireworksShow.id = PRODUCT_ID
end)
local Engine, task, Vector3, CFrame = api.Engine, api.task, api.Vector3, api.CFrame
local world, services = api.world, api.services
local Data, Base, Room, Currency = services.DataService, services.BaseService, services.GameRoomService, services.CurrencyService
local Homes = world.require(world.find("ReplicatedStorage.Shared.Config.Homes"))
local Monetization = world.require(world.find("ReplicatedStorage.Shared.Config.Monetization"))
local Schema = world.require(world.find("ReplicatedStorage.Shared.Data.Schema"))
local Decision = roblox.Enum.ProductPurchaseDecision

local function joinLoaded(name: string, userId: number)
	local player = api.join(name, userId)
	player.DisplayName = name
	api.waitFor(function()
		return Data:get(player) ~= nil and Base:baseOf(player) ~= nil
	end, 5, name .. "'s base")
	return player
end

local function standAt(player, position)
	local root = player.Character.HumanoidRootPart
	root.CFrame = CFrame.new(position)
	root.Position = position
end

local function countParts(instance): number
	local count = 0
	for _, item in instance:GetDescendants() do
		if item:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local friends = {}
Base.friendCheck = function(player, userId)
	return friends[player.UserId .. ":" .. userId] == true or friends[userId .. ":" .. player.UserId] == true
end

-- A fake clock and calendar the services read
local clockNow, timeNow = 1000, 1_800_000_000
Base.clock = function()
	return clockNow
end
Base.now = function()
	return timeNow
end

local function inBase(player, base): boolean
	return Base:isInside(player, base)
end

local function money(player): number
	return Currency:balance(player, "money")
end

local function open(player, owner)
	Base.antiExploit:allow(player, "Base")
	return Base:enter(player, owner)
end

local alice = joinLoaded("Alice", 901) -- the host
local bob = joinLoaded("Bob", 902) -- alice's friend
local carol = joinLoaded("Carol", 903) -- a stranger
friends["901:902"] = true
local aliceBase = Base:baseOf(alice)
local street = Base.street

api.check("old profiles and new ones read Friends; the home and room are inside the budgets", function()
	assert(Data:get(alice).hosting.access == "Friends", "default access")
	local old = Schema.repair({ base = { access = "Everyone" } })
	assert(old.hosting.access == "Friends", "an old saved base.access of Everyone is ignored")
	local junk = Schema.repair({ hosting = { access = "Banana", jukebox = "Nope", fireworks = 9999, effects = { Aurora = true, Fake = true }, visitors = { { id = 1, name = "A" }, "x" } } })
	assert(junk.hosting.access == "Friends" and junk.hosting.jukebox == Homes.DefaultMusic, "junk falls back")
	assert(junk.hosting.fireworks == Homes.FireworksMaxCharges and junk.hosting.effects.Aurora and not junk.hosting.effects.Fake, "bounded and filtered")
	assert(#junk.hosting.visitors == 1, "bad visitor rows dropped")
	local home = countParts(aliceBase.built.home)
	local room = countParts(aliceBase.built.gameRoom.model)
	assert(home <= Homes.HomePartBudget, "home parts " .. home)
	assert(room <= Homes.GameRoomPartBudget, "game room parts " .. room)
	print("  parts: home " .. home .. ", game room " .. room)
end)

api.check("access modes: Friends, Everyone, Just me", function()
	assert(open(bob, alice) and inBase(bob, aliceBase), "a friend gets in")
	assert(not open(carol, alice) and not inBase(carol, aliceBase), "a stranger is refused in Friends mode")
	api.request("BaseRequest", alice, "SetAccess", "Everyone")
	task.wait(0.05)
	assert(Data:get(alice).hosting.access == "Everyone")
	assert(open(carol, alice) and inBase(carol, aliceBase), "open house lets a stranger in")
	api.request("BaseRequest", alice, "SetAccess", "Banana")
	api.request("BaseRequest", bob, "SetAccess", "Nobody") -- bob is not the owner of alice's base; it changes bob's own
	task.wait(0.05)
	assert(Data:get(alice).hosting.access == "Everyone", "junk and other people's requests do not change alice's access")
	assert(Data:get(bob).hosting.access == "Nobody", "a request only ever changes your own base")
	api.request("BaseRequest", bob, "SetAccess", "Friends")
end)

api.check("narrowing access returns visitors who are no longer allowed to the street", function()
	assert(inBase(carol, aliceBase) and inBase(bob, aliceBase))
	api.request("BaseRequest", alice, "SetAccess", "Friends")
	task.wait(0.2)
	assert(not inBase(carol, aliceBase), "the stranger is sent out")
	assert(inBase(bob, aliceBase), "the friend may stay")
	api.request("BaseRequest", alice, "SetAccess", "Nobody")
	task.wait(0.2)
	assert(not inBase(bob, aliceBase), "even friends are sent out in Just me")
	assert(not open(bob, alice), "and cannot come back")
	assert(open(alice, alice) and inBase(alice, aliceBase), "the owner always can")
	api.request("BaseRequest", alice, "SetAccess", "Friends")
	task.wait(0.05)
end)

api.check("only the owner can ask a visitor to leave, and the visitor is barred for a while", function()
	assert(open(bob, alice) and inBase(bob, aliceBase))
	standAt(carol, Vector3.new(0, 4, 0))
	api.request("BaseRequest", carol, "AskLeave", bob.UserId)
	api.request("BaseRequest", bob, "AskLeave", alice.UserId)
	task.wait(0.2)
	assert(inBase(bob, aliceBase) and inBase(alice, aliceBase), "nobody but the owner can ask")
	task.wait(0.5)
	api.request("BaseRequest", alice, "AskLeave", carol.UserId) -- carol is not in the base
	api.request("BaseRequest", alice, "AskLeave", "junk")
	task.wait(0.2)
	assert(inBase(bob, aliceBase), "a target who is not inside is refused, junk too")
	task.wait(3.1)
	api.request("BaseRequest", alice, "AskLeave", bob.UserId)
	task.wait(0.2)
	assert(not inBase(bob, aliceBase), "the owner's request sends bob out")
	assert(not open(bob, alice), "bob is barred for a while")
	clockNow += Homes.AskLeaveBar + 1
	assert(open(bob, alice) and inBase(bob, aliceBase), "and may return later")
end)

api.check("visitors board lists display names; one heart per visitor per UTC day", function()
	local hosting = Data:get(alice).hosting
	assert(#hosting.visitors >= 1 and hosting.visitors[#hosting.visitors].name == "Bob", "bob is on the board")
	local before = hosting.hearts
	task.wait(0.5)
	api.request("BaseRequest", bob, "Heart", alice.UserId)
	task.wait(0.1)
	assert(Data:get(alice).hosting.hearts == before + 1, "one heart")
	task.wait(0.4)
	api.request("BaseRequest", bob, "Heart", alice.UserId)
	task.wait(0.1)
	assert(Data:get(alice).hosting.hearts == before + 1, "a second heart the same day is refused")
	task.wait(0.4)
	api.request("BaseRequest", alice, "Heart", alice.UserId)
	api.request("BaseRequest", carol, "Heart", alice.UserId) -- carol is not inside
	task.wait(0.1)
	assert(Data:get(alice).hosting.hearts == before + 1, "owners cannot heart themselves; outsiders cannot heart")
	timeNow += 86400
	task.wait(0.4)
	api.request("BaseRequest", bob, "Heart", alice.UserId)
	task.wait(0.1)
	assert(Data:get(alice).hosting.hearts == before + 2, "the next UTC day allows another")
	for index = 1, 12 do
		Base:_recordVisitor(alice, index % 2 == 0 and bob or carol)
	end
	assert(#Data:get(alice).hosting.visitors <= Homes.VisitorsKept, "at most 8 visitors are kept")
end)

api.check("host bonus: once a UTC day, friends only, after 60 seconds", function()
	timeNow += 86400
	standAt(bob, Vector3.new(0, 4, 0))
	standAt(carol, Vector3.new(0, 4, 0))
	Base:_presenceTick()
	api.request("BaseRequest", alice, "SetAccess", "Everyone")
	task.wait(0.1)
	assert(open(carol, alice), "carol (not a friend) visits in open house")
	assert(open(bob, alice), "bob (a friend) visits")
	local start = money(alice)
	Base:_presenceTick()
	clockNow += 30
	Base:_presenceTick()
	assert(money(alice) == start, "nothing before 60 seconds")
	clockNow += 40
	Base:_presenceTick()
	assert(money(alice) == start + Homes.HostBonusMoney, "the friend earned the bonus, got " .. (money(alice) - start))
	clockNow += 100
	Base:_presenceTick()
	assert(money(alice) == start + Homes.HostBonusMoney, "only once per day")
	-- leaving and re-entering does not earn it again the same day
	standAt(bob, Vector3.new(0, 4, 0))
	Base:_presenceTick()
	assert(open(bob, alice))
	Base:_presenceTick()
	clockNow += 100
	Base:_presenceTick()
	assert(money(alice) == start + Homes.HostBonusMoney, "re-entering cannot farm it")
	timeNow += 86400
	clockNow += 100
	Base:_presenceTick()
	assert(money(alice) == start + 2 * Homes.HostBonusMoney, "a new UTC day pays once more")
	-- a stranger alone never pays
	standAt(bob, Vector3.new(0, 4, 0))
	Base:_presenceTick()
	timeNow += 86400
	clockNow += 100
	Base:_presenceTick()
	clockNow += 100
	Base:_presenceTick()
	assert(money(alice) == start + 2 * Homes.HostBonusMoney, "a non-friend alone earns nothing")
	api.request("BaseRequest", alice, "SetAccess", "Friends")
	task.wait(0.1)
end)

local meter, reflexPrompt
local function pressPrompt(player, prompt)
	standAt(player, prompt.Parent.Position + Vector3.new(0, 0, -2))
	Engine.signalOf(prompt, "Triggered"):Fire(player)
	task.wait(0.45)
end

api.check("Power Meter: the score comes from the server clock; a client cannot send one", function()
	meter = aliceBase.built.prompts.PowerMeter
	assert(meter, "the meter has a prompt")
	assert(open(bob, alice), "bob is in")
	local before = money(bob)
	pressPrompt(bob, meter) -- start
	assert(meter.ActionText == "Strike now")
	clockNow += 0.4 -- a quarter of the 1.6 s period: halfway up
	-- extra arguments are ignored: there is no way to name a score
	standAt(bob, meter.Parent.Position + Vector3.new(0, 0, -2))
	api.request("BaseRequest", bob, "Activity", "PowerMeter", 100)
	task.wait(0.1)
	local expected = Homes.powerMeterScore(0.4, Homes.PowerMeter.period)
	assert(expected == 50, "model: " .. expected)
	assert(Data:get(bob).hosting.bests.PowerMeter == 50, "server score 50, got " .. tostring(Data:get(bob).hosting.bests.PowerMeter))
	assert(money(bob) == before + Homes.Activities.PowerMeter.dailyMoney, "first play of the day pays")
	task.wait(0.4)
	pressPrompt(bob, meter)
	clockNow += 0.8 -- the top of the swing
	pressPrompt(bob, meter)
	assert(Data:get(bob).hosting.bests.PowerMeter == 100, "peak scores 100")
	assert(money(bob) == before + Homes.Activities.PowerMeter.dailyMoney, "no second reward the same day")
	pressPrompt(bob, meter)
	clockNow += 1.6 -- a full period is back at the bottom
	pressPrompt(bob, meter)
	assert(Data:get(bob).hosting.bests.PowerMeter == 100, "a worse score never replaces the best")
	-- one at a time
	pressPrompt(bob, meter)
	pressPrompt(carol, meter)
	assert(meter.ActionText == "Strike now", "carol's press did not end bob's run")
	pressPrompt(bob, meter)
	assert(Homes.powerMeterScore(0, 1.6) == 0 and Homes.powerMeterScore(0.8, 1.6) == 100 and Homes.powerMeterScore(1.6, 1.6) == 0)
	-- far away presses are ignored
	standAt(bob, Vector3.new(0, 4, 0))
	task.wait(0.4)
	api.request("BaseRequest", bob, "Activity", "PowerMeter", "press")
	task.wait(0.1)
	assert(meter.ActionText == "Start the needle", "a press from the other side of the base does nothing")
end)

api.check("Reflex cabinet: false start, server-timed reaction, personal best, one reward a day", function()
	reflexPrompt = aliceBase.built.prompts.Reflex
	Homes.Reflex.waitMin, Homes.Reflex.waitMax = 0.3, 0.35
	local before = money(bob)
	-- false start
	pressPrompt(bob, reflexPrompt) -- starts the wait
	assert(aliceBase.built.gameRoom.model:GetAttribute("ReflexState") == "wait", "waiting")
	pressPrompt(bob, reflexPrompt) -- too early
	assert(aliceBase.built.gameRoom.model:GetAttribute("ReflexState") == "false", "false start")
	assert(Data:get(bob).hosting.bests.Reflex == 0 and money(bob) == before, "a false start saves and pays nothing")
	-- a good run
	task.wait(1.6)
	pressPrompt(bob, reflexPrompt)
	task.wait(0.6) -- the wait ends and "go" is sent
	assert(aliceBase.built.gameRoom.model:GetAttribute("ReflexState") == "go", "go")
	clockNow += 0.4
	pressPrompt(bob, reflexPrompt)
	local best = Data:get(bob).hosting.bests.Reflex
	assert(best >= Homes.Reflex.minMs and best <= 400, "reaction measured on the server clock: " .. best)
	assert(money(bob) == before + Homes.Activities.Reflex.dailyMoney, "first valid play pays")
	-- a slower second run keeps the best and pays nothing
	pressPrompt(bob, reflexPrompt)
	task.wait(0.6)
	clockNow += 0.9
	pressPrompt(bob, reflexPrompt)
	assert(Data:get(bob).hosting.bests.Reflex == best, "a slower time does not replace the best")
	assert(money(bob) == before + Homes.Activities.Reflex.dailyMoney, "no second reward")
	-- an impossible time is raised to the human minimum
	pressPrompt(bob, reflexPrompt)
	task.wait(0.6)
	pressPrompt(bob, reflexPrompt)
	assert(Data:get(bob).hosting.bests.Reflex >= Homes.Reflex.minMs, "never below the minimum")
end)

api.check("the room's high score board lists the people present", function()
	Room:refreshBoard(aliceBase)
	local found = false
	for _, item in aliceBase.built.gameRoom.model:GetDescendants() do
		if item:IsA("TextLabel") and item.Text == "Bob" then
			found = true
		end
	end
	assert(found, "bob's name is on the board")
end)

api.check("jukebox: the owner picks a category; the base carries the attribute; others cannot", function()
	api.request("BaseRequest", alice, "Jukebox", "Rock")
	task.wait(0.1)
	assert(aliceBase.built.model:GetAttribute("MusicStyle") == "Rock", "attribute set")
	assert(Data:get(alice).hosting.jukebox == "Rock", "saved")
	for _, style in Homes.MusicStyles do
		assert(style == "Chill" or style == "Pop" or style == "Electronic" or style == "Classical" or style == "Phonk" or style == "Rock" or style == "Funny" or style == "SciFi")
	end
	task.wait(0.4)
	api.request("BaseRequest", alice, "Jukebox", "NotAStyle")
	api.request("BaseRequest", bob, "Jukebox", "Phonk")
	task.wait(0.1)
	assert(aliceBase.built.model:GetAttribute("MusicStyle") == "Rock", "junk and visitors change nothing")
	assert(Data:get(bob).hosting.jukebox == "Phonk" and Base:baseOf(bob).built.model:GetAttribute("MusicStyle") == "Phonk", "a request only ever changes your own base")
end)

api.check("party mode (free) cycles the room colours and restores them", function()
	local tile = nil
	for _, part in aliceBase.built.gameRoom.partyParts do
		tile = part
		break
	end
	local original = tile.Color
	task.wait(0.4)
	api.request("BaseRequest", alice, "Party", true)
	task.wait(0.1)
	assert(aliceBase.party == true and aliceBase.built.home:GetAttribute("Party") == true)
	Base:_animate()
	local first = tile.Color
	clockNow += 8
	Base:_animate()
	assert(tile.Color ~= first or first ~= original, "the colours move")
	task.wait(0.4)
	api.request("BaseRequest", alice, "Party", false)
	task.wait(0.1)
	assert(tile.Color == original, "colours are restored when the party ends")
end)

api.check("seats: sofas, armchair, beanbags and bench are Seat parts", function()
	local count = 0
	for _, item in aliceBase.built.model:GetDescendants() do
		if item.ClassName == "Seat" then
			count += 1
		end
	end
	assert(count >= 9, "seat count " .. count)
	assert(#aliceBase.built.seats == count)
end)

api.check("effects are locked without the Base Effects Pack and work with it", function()
	local function effectParts()
		local count = 0
		for _, item in aliceBase.built.model:GetDescendants() do
			if item.Name == "AuroraRibbon" or item.Name == "ShowBeam" or item.Name == "FireGlow" or item.Name == "SnowSource" or item.Name == "FireflySource" then
				count += 1
			end
		end
		return count
	end
	assert(Monetization.Passes.BaseEffectsPack.id == PASS_ID and Monetization.Passes.BaseEffectsPack.recommended == 199 and Monetization.Passes.BaseEffectsPack.robux == nil)
	task.wait(0.4)
	api.request("BaseRequest", alice, "Effect", "Aurora", true)
	task.wait(0.1)
	assert(effectParts() == 0 and Data:get(alice).hosting.effects.Aurora == nil, "locked without the pass")
	local ok, message = Base:setEffect(alice, "Aurora", true)
	assert(not ok and string.find(message, "Base Effects Pack", 1, true), "the reason names the pack")
	-- the pass is granted (the same record PurchaseService writes)
	Data:update(alice, function(data)
		data.passes.BaseEffectsPack = true
	end)
	for _, key in Homes.EffectOrder do
		task.wait(0.4)
		api.request("BaseRequest", alice, "Effect", key, true)
	end
	task.wait(0.1)
	assert(effectParts() >= 5, "all five effects now show: " .. effectParts())
	for _, key in Homes.EffectOrder do
		assert(Data:get(alice).hosting.effects[key] == true, key .. " saved")
	end
	task.wait(0.4)
	api.request("BaseRequest", alice, "Effect", "Nope", true)
	api.request("BaseRequest", alice, "Effect", "Aurora", "yes")
	task.wait(0.1)
	assert(Data:get(alice).hosting.effects.Nope == nil and Data:get(alice).hosting.effects.Aurora == true, "junk refused")
	clockNow += 3
	Base:_animate()
	task.wait(0.4)
	api.request("BaseRequest", alice, "Effect", "Aurora", false)
	task.wait(0.1)
	assert(Data:get(alice).hosting.effects.Aurora == nil, "effects switch off")
	assert(countParts(aliceBase.built.home) + 0 <= Homes.HomePartBudget + 40, "effects stay modest")
end)

api.check("Fireworks Show product: one saved charge per PurchaseId, idempotent; launching spends it", function()
	local product = Monetization.Products.FireworksShow
	assert(product.recommended == 25 and product.robux == nil and product.fireworks == 1 and product.benefit ~= "")
	local function receipt(id)
		return { PlayerId = alice.UserId, ProductId = PRODUCT_ID, PurchaseId = id, CurrencyType = roblox.Enum.CurrencyType.Robux, CurrencySpent = 25 }
	end
	assert(Data:get(alice).hosting.fireworks == 0)
	assert(Engine.deliverReceipt(receipt("fw-1")) == Decision.PurchaseGranted)
	assert(Data:get(alice).hosting.fireworks == 1, "one charge")
	assert(Engine.deliverReceipt(receipt("fw-1")) == Decision.PurchaseGranted)
	assert(Data:get(alice).hosting.fireworks == 1, "the repeated PurchaseId gave nothing more")
	assert(table.find(Data:get(alice).receipts, "fw-1"))
	assert(Engine.deliverReceipt(receipt("fw-2")) == Decision.PurchaseGranted and Data:get(alice).hosting.fireworks == 2, "a new purchase adds one")
	-- bob has no charges
	task.wait(0.4)
	api.request("BaseRequest", bob, "Fireworks")
	task.wait(0.1)
	assert(not Base:baseOf(bob).showing and Data:get(bob).hosting.fireworks == 0, "no charge, no show")
	Homes.FireworksSeconds, Homes.FireworksShotEvery = 1.2, 0.3
	api.request("BaseRequest", alice, "Fireworks")
	task.wait(0.15)
	assert(aliceBase.showing == true and Data:get(alice).hosting.fireworks == 1, "the show runs and spends one charge")
	assert(aliceBase.built.home:FindFirstChild("Fireworks") and #aliceBase.built.home.Fireworks:GetChildren() > 0, "mortar tubes stand while it runs")
	task.wait(0.4)
	api.request("BaseRequest", alice, "Fireworks")
	task.wait(0.1)
	assert(Data:get(alice).hosting.fireworks == 1, "a second show cannot start on top of the first")
	task.wait(1.6)
	assert(aliceBase.showing == false and #aliceBase.built.home.Fireworks:GetChildren() == 0, "the show ends and clears up")
end)

api.check("the panel state reaches the owner and reflects the real profile", function()
	local state = Base:panelState(alice)
	assert(state.access == "Friends" and state.jukebox == "Rock" and state.fireworks == 1 and state.ownsEffects == true)
	assert(#state.visitors >= 1 and state.hearts >= 2, "visitors and hearts")
	assert(Base:panelState(Base:baseOf(carol) and carol or carol) ~= nil)
	assert(state.bests.PowerMeter == 0 and typeof(state.effects.Aurora) == "boolean")
end)

api.finish()
