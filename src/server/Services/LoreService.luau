-- The Meridian Archive on the server: recovered files and reading progress.
-- Files are hidden around Meridian Station as objects tagged SNLoreTerminal
-- with a LoreId attribute; picking one up (ProgressAction.FindLore) adds it to
-- the player's Archive. The book tells us which document it showed
-- (ProgressAction.ReadLore) so "new" badges clear and the book reopens where
-- the player left off. Nothing the client says is trusted: the id must exist,
-- a real terminal for it must be within reach of the player's character, and
-- the profile must have loaded. The first find of each file pays Money, and
-- recovering every file pays Gems once.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Archive = require(ReplicatedStorage.Shared.Content.Archive)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Schema = require(ReplicatedStorage.Shared.Data.Schema)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Action = Protocol.ProgressAction

local LoreService = {}

-- Tunables for finding files (the story itself lives in Shared/Content/Archive)
LoreService.Config = {
	-- The tag and attribute the world puts on each recovered-file object
	Tag = "SNLoreTerminal",
	IdAttribute = "LoreId",
	-- How close (studs, from the character's root) a player must be to pick a file up
	Reach = 14,
	-- Paid the first time each file is found
	FileReward = { money = 25 },
	-- Paid once, when the last file is found
	CompleteReward = { gems = 100 },
}

-- Every document the book can show: chapters and recovered files
local documents: { [string]: boolean } = {}
for _, chapter in Archive.Chapters do
	documents[chapter.id] = true
end
for id in Archive.Files do
	documents[id] = true
end

local function toast(player: Player, text: string, kind: string)
	if player.Parent then
		DataEvent:FireClient(player, Protocol.DataEvent.Toast, { text = text, kind = kind })
	end
end

-- Where a tagged object is (parts, models and attachments all work)
local function positionOf(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function countFound(found: { [string]: boolean }): number
	local count = 0
	for _, id in Archive.FileOrder do
		if found[id] then
			count += 1
		end
	end
	return count
end

function LoreService:Init(services)
	self.data = services.DataService
	self.currency = services.CurrencyService
	self.antiExploit = services.AntiExploitService
end

function LoreService:Start()
	-- ProgressionService listens to the same remote; each service only takes
	-- its own actions (and only those count against this player's rate limit)
	ProgressRequest.OnServerEvent:Connect(function(player, action, first, second)
		if action ~= Action.FindLore and action ~= Action.ReadLore then
			return
		end
		if not self.antiExploit:allow(player, "Progress") then
			return
		end
		if action == Action.FindLore then
			self:find(player, first)
		else
			self:markRead(player, first, second)
		end
	end)
end

-- Is a real recovered-file object for `id` within reach of the player?
function LoreService:isNearTerminal(player: Player, id: string): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local config = LoreService.Config
	for _, instance in CollectionService:GetTagged(config.Tag) do
		if instance:GetAttribute(config.IdAttribute) == id then
			local position = positionOf(instance)
			if position and (position - root.Position).Magnitude <= config.Reach then
				return true
			end
		end
	end
	return false
end

-- How many files this player has recovered (0 before their profile loads)
function LoreService:foundCount(player: Player): number
	local profile = self.data:get(player)
	return if profile then countFound(profile.lore.found) else 0
end

-- A player picked up a recovered file. Returns (accepted, reason).
function LoreService:find(player: Player, id: any): (boolean, string?)
	if not Archive.isFile(id) then
		return false, "unknown file"
	end
	local profile = self.data:get(player)
	if not profile then
		return false, "profile not loaded"
	end
	if not self:isNearTerminal(player, id) then
		return false, "not near that file"
	end
	local file = Archive.Files[id]
	if profile.lore.found[id] then
		toast(player, `Already in the Archive: {file.title}`, "info")
		return false, "already found"
	end

	local isNew, complete = false, false
	self.data:update(player, function(current)
		if current.lore.found[id] then
			return
		end
		current.lore.found[id] = true
		isNew = true
		complete = countFound(current.lore.found) == #Archive.FileOrder
	end)
	if not isNew then
		return false, "already found"
	end

	local config = LoreService.Config
	self.currency:add(player, config.FileReward, "recovered file " .. id, { toast = false })
	toast(player, `Recovered file added to the Archive: {file.title}`, "reward")
	if complete then
		self.currency:add(player, config.CompleteReward, "every recovered file", { toast = false })
		toast(player, "Every file recovered. The Archive is complete.", "reward")
	end
	return true, nil
end

-- The book showed a document (a chapter, or a file the player has found).
-- `page` is how far into it they are, so the book can reopen there.
function LoreService:markRead(player: Player, id: any, page: any): (boolean, string?)
	if typeof(id) ~= "string" or not documents[id] then
		return false, "unknown document"
	end
	local maxPage = Schema.Config.MaxLorePage
	local at = 0
	if page ~= nil then
		if typeof(page) ~= "number" or page ~= page or page < 0 or page > maxPage or page ~= math.floor(page) then
			return false, "bad page"
		end
		at = page
	end
	local profile = self.data:get(player)
	if not profile then
		return false, "profile not loaded"
	end
	local lore = profile.lore
	if Archive.Files[id] and not lore.found[id] then
		return false, "file not found yet"
	end
	if lore.read[id] and lore.last == id and lore.page == at then
		return true, nil
	end
	local ok = self.data:update(player, function(current)
		current.lore.read[id] = true
		current.lore.last = id
		current.lore.page = at
	end)
	return ok, if ok then nil else "profile not loaded"
end

return LoreService
