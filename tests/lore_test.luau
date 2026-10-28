-- Recovered files and reading progress on the server (LoreService), run for
-- real with simulated players:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/lore_test.luau build/game.rbxl
-- FindLore refuses junk ids, unknown ids, players out of reach and files with
-- no tagged terminal; a first find pays Money once; finding every file pays
-- Gems once; ReadLore is validated; ProgressionService's own actions still
-- work beside it; and everything survives leaving and rejoining.

local process = require("@lune/process")
local World = require("./smoke/World")

local api = World.start(process.args[1] or "build/game.rbxl")
local Engine, task, Vector3, CFrame = api.Engine, api.task, api.Vector3, api.CFrame
local world = api.world
local services = api.services
local Data, Currency, Lore = services.DataService, services.CurrencyService, services.LoreService
local Archive = world.require(world.find("ReplicatedStorage.Shared.Content.Archive"))
local CollectionService = Engine.services.CollectionService
local TAG = Lore.Config.Tag

-- LoreService and ProgressionService both rate limit the "Progress" channel,
-- so requests are spaced out the way a real player's would be
local function send(player, ...)
	api.request("ProgressRequest", player, ...)
	task.wait(0.7)
end

local function joinLoaded(name: string, userId: number)
	local player = api.join(name, userId)
	api.waitFor(function()
		return Data:get(player) ~= nil
	end, 5, name .. "'s profile")
	return player
end

-- A recovered-file object far from the lobby (the lobby's own are left alone)
local nextSpot = 0
local function terminal(id: string, tagged: boolean?): any
	nextSpot += 1
	local part = world.Instance.new("Part")
	part.Name = "TestFile_" .. id
	part.Anchored = true
	part.CFrame = CFrame.new(2000 + nextSpot * 60, 4, 2000)
	part.Position = Vector3.new(2000 + nextSpot * 60, 4, 2000)
	part:SetAttribute("LoreId", id)
	part.Parent = world.workspace
	if tagged ~= false then
		CollectionService:AddTag(part, TAG)
	end
	return part
end

local function standAt(player, position)
	local root = player.Character.HumanoidRootPart
	root.CFrame = CFrame.new(position)
	root.Position = position
end

local function standNear(player, part, distance: number)
	standAt(player, part.Position + Vector3.new(distance, 0, 0))
end

local function lore(player)
	return Data:get(player).lore
end

local function toasts(player, since: number): { string }
	local list = {}
	for _, data in api.sentSince(since, "DataEvent", "Toast", player) do
		table.insert(list, data.text)
	end
	return list
end

local function countFound(player): number
	local count = 0
	for _ in lore(player).found do
		count += 1
	end
	return count
end

local alice = joinLoaded("Alice", 701)
local startMoney = Currency:balance(alice, "money")
local startGems = Currency:balance(alice, "gems")
local fieldNote = terminal("lantern_field_note")

api.check("FindLore refuses junk and unknown ids", function()
	standNear(alice, fieldNote, 3)
	for _, junk in { 42, true, { "lantern_field_note" }, "not_a_file", "before_you_read", "" } do
		send(alice, "FindLore", junk)
	end
	send(alice, "FindLore")
	assert(countFound(alice) == 0, "nothing was found")
	assert(Currency:balance(alice, "money") == startMoney, "nothing was paid")
end)

api.check("FindLore refuses a player out of reach", function()
	standNear(alice, fieldNote, Lore.Config.Reach + 6)
	send(alice, "FindLore", "lantern_field_note")
	standAt(alice, Vector3.new(0, 4, 0))
	send(alice, "FindLore", "lantern_field_note")
	assert(not lore(alice).found.lantern_field_note, "too far to pick it up")
	assert(Currency:balance(alice, "money") == startMoney, "nothing was paid")
end)

api.check("FindLore refuses a file with no tagged terminal", function()
	-- take the lobby's own door 09 note out of play, and leave an untagged one nearby
	for _, instance in CollectionService:GetTagged(TAG) do
		if instance:GetAttribute("LoreId") == "door_09_note" then
			CollectionService:RemoveTag(instance, TAG)
		end
	end
	local untagged = terminal("door_09_note", false)
	standNear(alice, untagged, 2)
	send(alice, "FindLore", "door_09_note")
	-- a tagged terminal for a different file doesn't count either
	standNear(alice, fieldNote, 2)
	send(alice, "FindLore", "door_09_note")
	assert(not lore(alice).found.door_09_note, "no terminal, no file")
	assert(Currency:balance(alice, "money") == startMoney, "nothing was paid")
	CollectionService:AddTag(untagged, TAG)
end)

api.check("a first find adds the file and pays once", function()
	standNear(alice, fieldNote, 6)
	local since = api.mark()
	send(alice, "FindLore", "lantern_field_note")
	assert(lore(alice).found.lantern_field_note == true, "file recovered")
	assert(Currency:balance(alice, "money") == startMoney + 25, "paid 25 Money")
	local said = toasts(alice, since)
	assert(table.find(said, "Recovered file added to the Archive: " .. Archive.Files.lantern_field_note.title), "toast: " .. table.concat(said, " | "))
	send(alice, "FindLore", "lantern_field_note")
	assert(Currency:balance(alice, "money") == startMoney + 25, "a second find pays nothing")
	assert(Currency:balance(alice, "gems") == startGems, "no gems yet")
end)

api.check("recovering every file pays the gems once", function()
	local since = api.mark()
	for _, id in Archive.FileOrder do
		if not lore(alice).found[id] then
			local part = if id == "door_09_note" then nil else terminal(id)
			if part then
				standNear(alice, part, 4)
			else
				standNear(alice, world.workspace:FindFirstChild("TestFile_door_09_note"), 4)
			end
			send(alice, "FindLore", id)
		end
	end
	assert(countFound(alice) == #Archive.FileOrder, "all " .. #Archive.FileOrder .. " found: " .. countFound(alice))
	assert(Currency:balance(alice, "money") == startMoney + 25 * #Archive.FileOrder, "25 Money per file")
	assert(Currency:balance(alice, "gems") == startGems + 100, "100 Gems for the set")
	assert(table.find(toasts(alice, since), "Every file recovered. The Archive is complete."), "completion toast")
	standNear(alice, fieldNote, 3)
	send(alice, "FindLore", "lantern_field_note")
	assert(Currency:balance(alice, "gems") == startGems + 100, "the gems are paid only once")
end)

api.check("ReadLore is validated", function()
	local bob = joinLoaded("Bob", 702)
	send(bob, "ReadLore", "lantern_field_note")
	assert(not lore(bob).read.lantern_field_note, "a file can't be read before it's found")
	for _, junk in { 7, "not_a_document", "", { "before_you_read" } } do
		send(bob, "ReadLore", junk)
	end
	for _, page in { -1, 1.5, 0 / 0, math.huge, 1000, "2" } do
		send(bob, "ReadLore", "before_you_read", page)
	end
	assert(next(lore(bob).read) == nil, "nothing marked read: " .. tostring(next(lore(bob).read)))
	send(bob, "ReadLore", "night_shift", 2)
	local saved = lore(bob)
	assert(saved.read.night_shift == true and saved.last == "night_shift" and saved.page == 2, "a chapter is read and remembered")
	send(alice, "ReadLore", "warden_boot", 0)
	assert(lore(alice).read.warden_boot == true, "a found file can be read")
	api.leave(bob)
end)

api.check("ProgressionService's own actions still work beside LoreService", function()
	send(alice, "Welcome")
	assert(Data:get(alice).tutorial.welcomed == true, "Welcome handled by ProgressionService")
	send(alice, "ReadLore", "cascade_report", 3)
	assert(lore(alice).last == "cascade_report" and lore(alice).page == 3, "lore still handled")
end)

api.check("found files and reading progress survive leaving and rejoining", function()
	local money = Currency:balance(alice, "money")
	local gems = Currency:balance(alice, "gems")
	api.leave(alice)
	task.wait(0.2)
	alice = joinLoaded("Alice", 701)
	local saved = lore(alice)
	assert(countFound(alice) == #Archive.FileOrder, "every file still found")
	assert(saved.read.warden_boot == true and saved.read.cascade_report == true, "read marks kept")
	assert(saved.last == "cascade_report" and saved.page == 3, "the last page is kept")
	assert(Currency:balance(alice, "money") == money and Currency:balance(alice, "gems") == gems, "balances kept")
	assert(Data:get(alice).tutorial.welcomed == true, "other progress kept")
end)

local failed = api.finish()
process.exit(if failed == 0 then 0 else 1)
