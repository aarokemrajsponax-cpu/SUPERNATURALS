-- Builds the battleground chambers, the concourse and the training ground, hands
-- chambers out to matches, and answers "where do I spawn?" and "is this out of bounds?".
--
-- CHAMBERS (DECISIONS.md 8): twenty numbered slots (Chambers.Count) in a 4 x 5 grid far
-- east of the hub (Chambers.FirstCenter, 240 studs apart). A slot is empty until a match
-- reserves it. reserve() then builds a sealed chamber there on demand (a theme builder in
-- Server/Arenas wrapped by Arenas/Chamber: four walls, a ceiling, controlled light, side
-- ledges, and its own spectator gallery), and release() destroys it again, so only active
-- chambers exist. The Arena table of a slot keeps its identity for the whole session.
-- reserve() gives the lowest free number, nil when all twenty are busy. Part budget per
-- chamber: Chambers.PartBudget (700, theme plus shell). Nothing here runs per frame; the
-- concourse screens refresh on reserve/release and once a second while a chamber is busy.
--
-- CONCOURSE (World/Concourse): the hall behind the TEST CHAMBERS door. Gate screens show
-- FREE or IN MATCH from MatchService:_watchable() joined by Arena.slot. A Watch prompt sends
-- the player to that chamber's gallery and starts MatchService spectating; the gallery's
-- "Return to concourse" prompt stops spectating and brings them back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)

local ArenasFolder = script.Parent.Parent.Arenas
local Common = require(ArenasFolder.Common)
local Chamber = require(ArenasFolder.Chamber)
local TrainingHall = require(ArenasFolder.TrainingHall)
local Concourse = require(script.Parent.Parent.World.Concourse)

local ArenaService = {}

local ARENA = MatchConfig.Arena

ArenaService.Chambers = {
	Count = 20,
	PartBudget = 700,
	FirstCenter = Vector3.new(900, 0, -480),
	Columns = 4,
	Spacing = 240,
}
local CHAMBERS = ArenaService.Chambers

-- One builder per theme id in MatchConfig.ArenaOrder
local BUILDERS = {
	ProvingGrounds = require(ArenasFolder.ProvingGrounds),
	RuinedFortress = require(ArenasFolder.RuinedFortress),
	DigitalGrid = require(ArenasFolder.DigitalGrid),
	CorruptedWastes = require(ArenasFolder.CorruptedWastes),
	SoulFoundry = require(ArenasFolder.SoulFoundry),
}

export type Arena = {
	-- Theme id (a key of MatchConfig.Arenas) and its display name; kept after release so a
	-- rematch can ask for the same theme
	id: string,
	name: string,
	-- Chamber number, 1 to Chambers.Count
	slot: number,
	center: Vector3,
	floorY: number,
	-- nil while the chamber is not standing
	model: Model,
	spawns: { CFrame },
	inUse: boolean,
	-- Where the chamber's spectator gallery puts a watcher (nil while not standing)
	gallerySpawn: CFrame?,
	reservedAt: number,
}

local slots: { Arena } = {}
local arenaFolder: Folder
local trainingSpots: { CFrame } = {}
local trainingLayout: any = nil
local services: any = {}
local concourse: Concourse.Built? = nil
local ticking = false

-- A known theme id, or a random one for nil / "Random" / anything unknown
local function themeFor(arenaId: any): string
	if typeof(arenaId) == "string" and BUILDERS[arenaId] and MatchConfig.Arenas[arenaId] then
		return arenaId
	end
	local order = MatchConfig.ArenaOrder
	return order[math.random(1, #order)]
end

-- The same theme looks the same in every slot
local function seedOf(theme: string): number
	local seed = 17
	for index = 1, #theme do
		seed = (seed * 31 + string.byte(theme, index)) % 1000003
	end
	return seed
end

-- Concourse and gallery plumbing -------------------------------------------------------------

local function characterOf(player: Player)
	local characters = services.CharacterService
	local fighter = characters and characters:getByPlayer(player)
	if fighter and characters:isAlive(fighter) then
		return characters, fighter
	end
	return nil, nil
end

local function statuses(): { any }
	local list = {}
	local matches = if services.MatchService then services.MatchService:_watchable() else {}
	for _, arena in slots do
		local entry = { busy = arena.inUse }
		if arena.inUse then
			entry.elapsed = os.time() - arena.reservedAt
			for _, match in matches do
				if match.slot == arena.slot then
					entry.mode, entry.names, entry.phase = match.mode, match.names, match.phase
				end
			end
		end
		list[arena.slot] = entry
	end
	return list
end

local function refreshConcourse()
	if concourse then
		concourse.refresh(statuses())
	end
end

-- While any chamber is busy, refresh the clocks once a second (one delay chain)
local function startTicker()
	if ticking then
		return
	end
	ticking = true
	local function tick()
		refreshConcourse()
		for _, arena in slots do
			if arena.inUse then
				task.delay(1, tick)
				return
			end
		end
		ticking = false
	end
	task.delay(1, tick)
end

-- Take a player to the concourse (stop watching first)
function ArenaService:sendToConcourse(player: Player)
	if services.MatchService then
		services.MatchService:_stopSpectating(player)
	end
	local characters, fighter = characterOf(player)
	if characters then
		characters:teleport(fighter, self:concourseSpawn())
	end
end

-- Take a player to chamber `number`'s gallery and start spectating its match
function ArenaService:watchChamber(player: Player, number: number)
	local arena = slots[number]
	if not arena or not arena.inUse or not arena.gallerySpawn then
		return
	end
	local match
	for _, item in services.MatchService:_watchable() do
		if item.slot == number then
			match = item
		end
	end
	if not match then
		return
	end
	local characters, fighter = characterOf(player)
	if not characters then
		return
	end
	-- Spectate refuses fighters who are in a match; only move the ones that now watch
	if services.MatchService:spectate(player, match.id) then
		characters:teleport(fighter, arena.gallerySpawn)
	end
end

-- Building ---------------------------------------------------------------------------------------

local function buildTheme(arena: Arena, theme: string)
	local ctx = Common.context(theme, arena.center, seedOf(theme))
	-- Sealed rooms: no open-air terrain scenery
	ctx.terrain = nil
	BUILDERS[theme].build(ctx)
	local name = MatchConfig.Arenas[theme].name
	local gallerySpawn, returnPrompt = Chamber.build(ctx, theme, arena.slot, name)
	returnPrompt.Triggered:Connect(function(player: Player)
		ArenaService:sendToConcourse(player)
	end)
	ctx.model.Name = string.format("Chamber%02d_%s", arena.slot, theme)
	ctx.model:SetAttribute("Chamber", arena.slot)
	ctx.model.Parent = arenaFolder
	arena.id = theme
	arena.name = name
	arena.model = ctx.model
	arena.spawns = ctx.spawns
	arena.floorY = ctx.floorY
	arena.gallerySpawn = gallerySpawn
end

local function clear(arena: Arena)
	if arena.model then
		arena.model:Destroy()
		arena.model = nil :: any
	end
	arena.gallerySpawn = nil
end

-- Build a chamber as `theme`. A builder error falls back to the first theme so a match can
-- still start; if even that fails the slot is left empty and false is returned.
local function build(arena: Arena, theme: string): boolean
	local ok, err = pcall(buildTheme, arena, theme)
	if ok then
		return true
	end
	warn(`[ArenaService] building {theme} failed: {err}`)
	clear(arena)
	for _, stale in arenaFolder:GetChildren() do
		if stale:GetAttribute("Chamber") == arena.slot then
			stale:Destroy()
		end
	end
	local ok2, err2 = pcall(buildTheme, arena, MatchConfig.ArenaOrder[1])
	if not ok2 then
		warn(`[ArenaService] fallback chamber failed: {err2}`)
		clear(arena)
		return false
	end
	return true
end

local function newSlot(index: number): Arena
	local column, row = (index - 1) % CHAMBERS.Columns, (index - 1) // CHAMBERS.Columns
	local center = CHAMBERS.FirstCenter + Vector3.new(column * CHAMBERS.Spacing, 0, row * CHAMBERS.Spacing)
	local arena: Arena = {
		id = "",
		name = "",
		slot = index,
		center = center,
		floorY = center.Y + 1,
		model = nil :: any,
		spawns = {},
		inUse = false,
		gallerySpawn = nil,
		reservedAt = 0,
	}
	table.insert(slots, arena)
	return arena
end

function ArenaService:Init(allServices)
	services = allServices or {}
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arenas"
	arenaFolder.Parent = workspace
	for index = 1, CHAMBERS.Count do
		newSlot(index)
	end
end

function ArenaService:Start()
	local model, spots, layout = TrainingHall.build(MatchConfig.TrainingGround.Center)
	model.Parent = workspace
	trainingSpots = spots
	trainingLayout = layout
	local ok, result = pcall(Concourse.build, workspace, {
		watch = function(player: Player, number: number)
			ArenaService:watchChamber(player, number)
		end,
	})
	if ok then
		concourse = result
		refreshConcourse()
		-- Gate screens show names and mode as soon as a match registers or ends
		if services.MatchService and services.MatchService.onStarted then
			services.MatchService:onStarted(refreshConcourse)
			services.MatchService:onFinished(refreshConcourse)
		end
	else
		warn(`[ArenaService] the concourse did not build: {result}`)
	end
end

-- A free chamber of the asked theme (nil or "Random" picks one), built now, or nil if all
-- twenty are busy (or the build failed). The lowest free number is used.
function ArenaService:reserve(arenaId: string?): Arena?
	local theme = themeFor(arenaId)
	for _, arena in slots do
		if not arena.inUse then
			if not build(arena, theme) then
				return nil
			end
			arena.inUse = true
			arena.reservedAt = os.time()
			refreshConcourse()
			startTicker()
			return arena
		end
	end
	return nil
end

-- The match is over: the chamber is torn down and its number is free again
function ArenaService:release(arena: Arena)
	if not arena.inUse then
		return
	end
	arena.inUse = false
	clear(arena)
	refreshConcourse()
end

-- How many chambers are standing right now
function ArenaService:activeCount(): number
	local count = 0
	for _, arena in slots do
		if arena.inUse then
			count += 1
		end
	end
	return count
end

function ArenaService:getChamber(number: number): Arena?
	return slots[number]
end

function ArenaService:concourseSpawn(): CFrame
	local jitter = Vector3.new(math.random(-3, 3), 0, math.random(-6, 6))
	local base = if concourse then concourse.spawn else CFrame.new(Concourse.Center + Vector3.new(-96, 4, 0))
	return base + jitter
end

-- The spawn farthest from everyone in `others`
function ArenaService:pickSpawn(arena: Arena, others: { Vector3 }): CFrame
	local best, bestDistance = arena.spawns[1], -1
	for _, spawn in arena.spawns do
		local nearest = math.huge
		for _, position in others do
			nearest = math.min(nearest, (spawn.Position - position).Magnitude)
		end
		if nearest > bestDistance then
			best, bestDistance = spawn, nearest
		end
	end
	return best
end

function ArenaService:isOutOfBounds(arena: Arena, position: Vector3): boolean
	if position.Y < arena.floorY - ARENA.FallDepth then
		return true
	end
	local offset = position - arena.center
	local margin = 6
	return math.abs(offset.X) > ARENA.Size.X / 2 + margin or math.abs(offset.Z) > ARENA.Size.Z / 2 + margin
end

-- The nearest point inside the arena's walls (keeping `margin` studs from them),
-- at the same height. Teleports and knockback targets use it.
function ArenaService:clampInside(arena: Arena, position: Vector3, margin: number): Vector3
	local half = Vector3.new(ARENA.Size.X / 2 - margin, 0, ARENA.Size.Z / 2 - margin)
	local offset = position - arena.center
	return Vector3.new(
		arena.center.X + math.clamp(offset.X, -half.X, half.X),
		position.Y,
		arena.center.Z + math.clamp(offset.Z, -half.Z, half.Z)
	)
end

function ArenaService:contains(arena: Arena, position: Vector3, margin: number?): boolean
	local offset = position - arena.center
	local pad = margin or 0
	return math.abs(offset.X) <= ARENA.Size.X / 2 - pad and math.abs(offset.Z) <= ARENA.Size.Z / 2 - pad
end

function ArenaService:lobbySpawn(): CFrame
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local base = if spawnLocation then spawnLocation.CFrame else CFrame.new(0, 0, 0)
	local jitter = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	return CFrame.new(base.Position + Vector3.new(0, 4, 0) + jitter)
end

-- The middle of the lobby (the spawn point), used by admin events
function ArenaService:lobbyCenter(): Vector3
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	return if spawnLocation then spawnLocation.Position else Vector3.zero
end

function ArenaService:trainingSpawn(): CFrame
	local center = MatchConfig.TrainingGround.Center
	return CFrame.lookAt(center + Vector3.new(20, 4, 0), center + Vector3.new(0, 4, 0))
end

function ArenaService:trainingDummySpots(): { CFrame }
	return trainingSpots
end

-- The studio's practice bays: { { labels, spot, name } } (labels are the readout screen's text)
function ArenaService:trainingBays(): { any }
	return if trainingLayout then trainingLayout.bays else {}
end

-- The Training Studio layout: { bays, floors (sparring floors), platform, console, jeffery }
function ArenaService:trainingStudio(): any
	return trainingLayout
end

return ArenaService
