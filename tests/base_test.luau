-- Player Base Street, personal bases and the Vault (BaseService), run for real with simulated
-- players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/base_test.luau build/game.rbxl
-- A base is built on join and removed on leave; your own door opens; a friend's opens and a
-- non-friend's is refused (fake friend check); the display wall shows real profile data; decor
-- and toggle requests save and junk is refused; the Archive alcove opens only with every file;
-- the owner console exists only in the owner's base and a non-owner cannot trigger it; part
-- budgets hold.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl")
local Engine, task, Vector3, CFrame = api.Engine, api.task, api.Vector3, api.CFrame
local world = api.world
local services = api.services
local Data, Base, Lore = services.DataService, services.BaseService, services.LoreService
local Homes = world.require(world.find("ReplicatedStorage.Shared.Config.Homes"))
local Archive = world.require(world.find("ReplicatedStorage.Shared.Content.Archive"))
local OWNER_ID = 8722595934

local function joinLoaded(name: string, userId: number)
	local player = api.join(name, userId)
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

local function rootPos(player)
	return player.Character.HumanoidRootPart.Position
end

local function descendants(instance, class: string?)
	local list = {}
	for _, item in instance:GetDescendants() do
		if not class or item.ClassName == class then
			table.insert(list, item)
		end
	end
	return list
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

-- A prompt press the way a player would make it: stand beside it, then trigger
local function press(player, prompt)
	standAt(player, prompt.Parent.Position + Vector3.new(0, 0, 2))
	Engine.signalOf(prompt, "Triggered"):Fire(player)
	task.wait(0.45) -- the "Base" rate limit is about 3 a second
end

local friends = {}
Base.friendCheck = function(player, userId)
	return friends[player.UserId .. ":" .. userId] == true or friends[userId .. ":" .. player.UserId] == true
end

local street = world.workspace:FindFirstChild("BaseStreet")
local alice, bob, carol, owner
local function inBase(player, base): boolean
	local offset = rootPos(player) - base.origin
	return math.abs(offset.X) < 30 and math.abs(offset.Z) < 25 and offset.Y > -5
end

api.check("the street stands, within its part budget, with every door off", function()
	assert(street, "BaseStreet exists in Workspace")
	assert(countParts(street) <= Homes.StreetPartBudget, "street parts " .. countParts(street))
	for _, prompt in descendants(street, "ProximityPrompt") do
		assert(prompt:GetAttribute("Action") == nil, "no client-side Action on street prompts")
	end
	local live = 0
	for _, prompt in descendants(street, "ProximityPrompt") do
		if prompt.Enabled then
			live += 1
		end
	end
	assert(live == 1, "only the return prompt is live before anyone joins, got " .. live)
end)

api.check("a base is built for a player on join and its door shows their name", function()
	alice = joinLoaded("Alice", 801)
	local base = Base:baseOf(alice)
	assert(base and base.slot == 1, "slot 1")
	assert(base.built.model.Parent == world.workspace, "base is in the world")
	assert(countParts(base.built.home) <= Homes.HomePartBudget, "home parts " .. countParts(base.built.home))
	assert(countParts(base.built.vault) <= Homes.VaultPartBudget + 70, "vault parts " .. countParts(base.built.vault))
	local door = Base.street.doors[1]
	assert(string.find(door.label.Text, "ALICE", 1, true), "door label: " .. door.label.Text)
	assert(door.prompt.Enabled, "the door is live")
	assert(not Base.street.doors[2].prompt.Enabled, "a vacant door stays off")
	bob = joinLoaded("Bob", 802)
	local second = Base:baseOf(bob)
	assert(second.slot == 2 and second.origin ~= base.origin, "bob has a different base")
end)

api.check("your own door opens", function()
	local base = Base:baseOf(alice)
	press(alice, Base.street.doors[1].prompt)
	assert(inBase(alice, base), "alice is inside her base")
end)

api.check("a non-friend's door is refused with a polite message; a friend's opens", function()
	local aliceBase = Base:baseOf(alice)
	local mark = api.mark()
	press(bob, Base.street.doors[1].prompt)
	assert(not inBase(bob, aliceBase), "bob stays out")
	local sent = api.sentSince(mark, "MatchEvent", "Notice", bob)
	assert(#sent >= 1 and string.find(sent[1].text or sent[1][1] and sent[1][1].text or "", "Friends only", 1, true), "friends-only notice")
	friends["801:802"] = true
	press(bob, Base.street.doors[1].prompt)
	assert(not inBase(bob, aliceBase), "the earlier answer is cached for a while")
	-- A fresh pair is checked on its own
	carol = joinLoaded("Carol", 803)
	friends["801:803"] = true
	press(carol, Base.street.doors[1].prompt)
	assert(inBase(carol, aliceBase), "a friend gets in")
end)

api.check("a prompt used from far away is ignored", function()
	local base = Base:baseOf(alice)
	standAt(bob, Vector3.new(0, 4, 0))
	local prompt = Base.street.doors[2].prompt
	Engine.signalOf(prompt, "Triggered"):Fire(bob)
	task.wait(0.45)
	assert(not inBase(bob, Base:baseOf(bob)), "no teleport from the lobby")
	assert(base, "unused")
end)

api.check("the display wall shows real profile data", function()
	Data:update(alice, function(profile)
		profile.stats.wins = 12
		profile.stats.matches = 20
		profile.stats.bestStreak = 4
		profile.powers.Ghost = { xp = 800, degrees = {}, abilities = {}, owned = false }
		profile.cosmetics.owned.title_recruit = true
		profile.cosmetics.owned.aura_gold = true
		profile.cosmetics.equipped.title = "title_recruit"
	end)
	task.wait(0.1)
	local home = Base:baseOf(alice).built.home
	local function text(name: string): string
		local board = home:FindFirstChild(name, true)
		assert(board, name .. " exists")
		local parts = {}
		for _, label in descendants(board, "TextLabel") do
			table.insert(parts, label.Text)
		end
		return table.concat(parts, " | ")
	end
	local record = text("RecordBoard")
	assert(string.find(record, "Wins  12", 1, true), record)
	assert(string.find(record, "Recruit", 1, true), record)
	assert(string.find(record, "Best streak  4", 1, true), record)
	local mastery = text("MasteryBoard")
	assert(string.find(mastery, "The Ghost", 1, true) and string.find(mastery, "Lv 4", 1, true), mastery)
	local collection = text("CollectionBoard")
	assert(string.find(collection, "Cosmetics  1", 1, true) and string.find(collection, "Titles  1", 1, true), collection)
	-- Win trophies in the vault light up for earned milestones (1, 10)
	local vault = Base:baseOf(alice).built.vault
	local lit = 0
	for _, part in descendants(vault:FindFirstChild("Dynamic"), "Part") do
		if part.Name == "TrophyCup" and part:FindFirstChildOfClass("PointLight") then
			lit += 1
		end
	end
	assert(lit == 2, "two trophies earned, got " .. lit)
end)

api.check("decor and toggles save through validated requests; junk is refused", function()
	api.request("BaseRequest", alice, "Decor", "Midnight")
	task.wait(0.45)
	assert(Data:get(alice).base.theme == "Midnight", "theme saved in the profile")
	assert(Base:baseOf(alice).built.home:GetAttribute("Theme") == "Midnight", "base recoloured")
	local before = Data:get(alice).base.theme
	for _, junk in { "Plaid", 5, true, {}, "", "__index" } do
		api.request("BaseRequest", alice, "Decor", junk)
		task.wait(0.45)
	end
	api.request("BaseRequest", alice, "Decor")
	task.wait(0.45)
	assert(Data:get(alice).base.theme == before, "junk themes change nothing")
	api.request("BaseRequest", alice, "Toggle", "mastery", false)
	task.wait(0.45)
	assert(Data:get(alice).base.show.mastery == false, "toggle saved")
	for _, junk in { { "nope", true }, { "mastery", "yes" }, { 7, true }, { "cosmetics", 1 } } do
		api.request("BaseRequest", alice, "Toggle", junk[1], junk[2])
		task.wait(0.45)
	end
	assert(Data:get(alice).base.show.cosmetics == true and Data:get(alice).base.show.mastery == false, "junk toggles refused")
	assert(Data:get(alice).base.show.nope == nil, "no unknown keys saved")
	local mastery = Base:baseOf(alice).built.home:FindFirstChild("MasteryBoard", true)
	local all = {}
	for _, label in descendants(mastery, "TextLabel") do
		table.insert(all, label.Text)
	end
	assert(string.find(table.concat(all, "|"), "hidden by the owner", 1, true), "hidden board says so")
	-- Someone else's pad does nothing
	local pad = Base:baseOf(alice).built.prompts.PadTheme
	press(bob, pad)
	assert(Data:get(alice).base.theme == "Midnight" and Data:get(bob).base.theme == "Walnut", "pads are for the owner")
	-- The owner's own pad cycles the theme
	press(alice, pad)
	assert(Data:get(alice).base.theme == "Walnut", "pad cycles Midnight to Walnut")
end)

api.check("the saved theme survives a repair (junk in a profile falls back)", function()
	local Schema = world.require(world.find("ReplicatedStorage.Shared.Data.Schema"))
	local repaired = Schema.migrate({ base = { theme = "Evil", show = { mastery = "x", extra = true } } })
	repaired = repaired
	assert(repaired.base.theme == "Walnut" and repaired.base.show.mastery == true and repaired.base.show.extra == nil, "schema repairs the new fields")
end)

api.check("the vault lift is for the owner only; the alcove stays sealed until every file is found", function()
	local base = Base:baseOf(alice)
	local panel = base.built.alcovePanel
	assert(panel.CanCollide == true and base.built.vault:FindFirstChild("ArchiveAlcove"):GetAttribute("Open") == false, "sealed at first")
	-- A visitor cannot take the lift
	press(carol, base.built.prompts.LiftDown)
	assert(rootPos(carol).Y > -10, "carol stays upstairs")
	press(alice, base.built.prompts.LiftDown)
	assert(rootPos(alice).Y < -Homes.VaultDrop + 8, "alice is in her vault, y " .. rootPos(alice).Y)
	-- Nine files: still sealed
	local found = {}
	for index = 1, #Archive.FileOrder - 1 do
		found[Archive.FileOrder[index]] = true
	end
	Data:update(alice, function(profile)
		profile.lore.found = found
	end)
	task.wait(0.1)
	assert(Lore:foundCount(alice) == 9 and panel.CanCollide == true, "nine of ten keeps it sealed")
	Data:update(alice, function(profile)
		profile.lore.found[Archive.FileOrder[#Archive.FileOrder]] = true
	end)
	task.wait(0.1)
	assert(Lore:foundCount(alice) == #Archive.FileOrder, "all found")
	assert(panel.CanCollide == false and base.built.vault:FindFirstChild("ArchiveAlcove"):GetAttribute("Open") == true, "opens with all ten")
	-- The way back up
	press(alice, base.built.prompts.LiftUp)
	assert(rootPos(alice).Y > -10, "back in the home")
end)

api.check("premium fighters show only when owned; no Meme Vault door yet", function()
	local vault = Base:baseOf(alice).built.vault
	local function figures(): number
		local count = 0
		for _, part in descendants(vault:FindFirstChild("Dynamic"), "Part") do
			if part.Name == "FigureTorso" then
				count += 1
			end
		end
		return count
	end
	assert(figures() == 0, "none owned, none shown")
	Data:update(alice, function(profile)
		profile.powers.Syntax = { xp = 0, degrees = {}, abilities = {}, owned = true }
	end)
	task.wait(0.1)
	assert(figures() >= 1, "an owned premium fighter is displayed")
	local reserved = vault:FindFirstChild("Reserved")
	assert(reserved and reserved:FindFirstChildWhichIsA("Attachment", true), "the Meme Vault spot is documented by an anchor")
	assert(#descendants(reserved, "ProximityPrompt") == 0, "no dead door or button there")
end)

api.check("the owner console exists only in the owner's base and a non-owner cannot trigger it", function()
	assert(Base:baseOf(alice).built.prompts.Console == nil and Base:baseOf(alice).built.console == nil, "no console in an ordinary base")
	owner = joinLoaded("AJKR", OWNER_ID)
	local ownerBase = Base:baseOf(owner)
	assert(ownerBase.built.prompts.Console, "the owner's vault has the console")
	-- Owner uses it: the client is told to open the panel
	local mark = api.mark()
	press(owner, ownerBase.built.prompts.Console)
	assert(#api.sentSince(mark, "BaseEvent", "OpenConsole", owner) == 1, "owner gets OpenConsole")
	-- Someone else presses it (even standing beside it): nothing is sent
	friends[OWNER_ID .. ":801"] = true
	mark = api.mark()
	press(alice, ownerBase.built.prompts.Console)
	assert(#api.sentSince(mark, "BaseEvent", "OpenConsole", alice) == 0, "a non-owner gets nothing")
end)

api.check("a base is removed on leave, with visitors sent back to the street", function()
	local aliceBase = Base:baseOf(alice)
	local model = aliceBase.built.model
	standAt(carol, aliceBase.origin + Vector3.new(0, 4, 5))
	api.leave(alice)
	task.wait(0.3)
	assert(Base:baseOf(alice) == nil and model.Parent == nil, "base gone")
	assert(Base.street.doors[1].prompt.Enabled == false and string.find(Base.street.doors[1].label.Text, "VACANT", 1, true), "door vacant again")
	assert((rootPos(carol) - Homes.StreetCenter).Magnitude < 150, "carol was returned to the street")
	local again = joinLoaded("Alice", 801)
	assert(Base:baseOf(again).slot == 1, "the freed slot is reused")
	assert(Data:get(again).base.theme == "Walnut" or Homes.Themes[Data:get(again).base.theme], "profile intact")
end)

local failed = api.finish()
process.exit(if failed == 0 then 0 else 1)
