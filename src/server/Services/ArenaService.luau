-- Builds the fight arenas and the training ground, hands arenas out to matches,
-- and answers "where do I spawn?" and "is this out of bounds?".
-- Arenas are built from parts (and terrain scenery) in code, one copy per slot
-- so several matches can run at once without overlapping. Each theme has its
-- own builder in Server/Arenas; a slot is rebuilt when a match asks for a
-- different theme than the one standing there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)

local ArenasFolder = script.Parent.Parent.Arenas
local Common = require(ArenasFolder.Common)
local TrainingHall = require(ArenasFolder.TrainingHall)

local ArenaService = {}

local ARENA = MatchConfig.Arena

-- One builder per theme id in MatchConfig.ArenaOrder
local BUILDERS = {
	ProvingGrounds = require(ArenasFolder.ProvingGrounds),
	RuinedFortress = require(ArenasFolder.RuinedFortress),
	DigitalGrid = require(ArenasFolder.DigitalGrid),
	CorruptedWastes = require(ArenasFolder.CorruptedWastes),
	SoulFoundry = require(ArenasFolder.SoulFoundry),
}

export type Arena = {
	-- Theme id (a key of MatchConfig.Arenas) and its display name
	id: string,
	name: string,
	-- Which slot it stands in (1 to MaxSimultaneous)
	slot: number,
	center: Vector3,
	floorY: number,
	model: Model,
	spawns: { CFrame },
	inUse: boolean,
}

local slots: { Arena } = {}
local arenaFolder: Folder
local trainingSpots: { CFrame } = {}

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

local function buildTheme(arena: Arena, theme: string)
	local ctx = Common.context(theme, arena.center, seedOf(theme))
	BUILDERS[theme].build(ctx)
	ctx.model.Name = theme .. arena.slot
	ctx.model.Parent = arenaFolder
	arena.id = theme
	arena.name = MatchConfig.Arenas[theme].name
	arena.model = ctx.model
	arena.spawns = ctx.spawns
	arena.floorY = ctx.floorY
end

-- (Re)build a slot as `theme`, clearing whatever the last theme left there.
-- A builder error falls back to the first theme so a match can still start.
local function rebuild(arena: Arena, theme: string)
	if arena.model then
		arena.model:Destroy()
	end
	Common.clearTerrain(arena.center)
	local ok, err = pcall(buildTheme, arena, theme)
	if not ok then
		warn(`[ArenaService] building {theme} failed: {err}`)
		local fallback = MatchConfig.ArenaOrder[1]
		local model = arenaFolder:FindFirstChild(theme .. arena.slot)
		if model then
			model:Destroy()
		end
		Common.clearTerrain(arena.center)
		buildTheme(arena, fallback)
	end
end

local function newSlot(index: number): Arena
	local center = ARENA.FirstCenter + Vector3.new(0, 0, (index - 1) * ARENA.Spacing)
	local arena: Arena = {
		id = "",
		name = "",
		slot = index,
		center = center,
		floorY = center.Y + 1,
		model = nil :: any,
		spawns = {},
		inUse = false,
	}
	table.insert(slots, arena)
	return arena
end

function ArenaService:Init()
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arenas"
	arenaFolder.Parent = workspace
end

function ArenaService:Start()
	local model, spots = TrainingHall.build(MatchConfig.TrainingGround.Center)
	model.Parent = workspace
	trainingSpots = spots
	-- Build the first arena up front so the first match starts instantly
	rebuild(newSlot(1), MatchConfig.ArenaOrder[1])
end

-- A free arena of the asked theme (nil or "Random" picks one), or nil if every
-- slot is busy. A free slot already showing that theme is used as it is;
-- otherwise a free slot is rebuilt, or a new slot is added.
function ArenaService:reserve(arenaId: string?): Arena?
	local theme = themeFor(arenaId)
	local free: Arena? = nil
	for _, arena in slots do
		if not arena.inUse then
			if arena.id == theme then
				arena.inUse = true
				return arena
			end
			free = free or arena
		end
	end
	if not free then
		if #slots >= ARENA.MaxSimultaneous then
			return nil
		end
		free = newSlot(#slots + 1)
	end
	local arena = free :: Arena
	rebuild(arena, theme)
	arena.inUse = true
	return arena
end

function ArenaService:release(arena: Arena)
	arena.inUse = false
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
	return CFrame.lookAt(center + Vector3.new(12, 4, 0), center + Vector3.new(0, 4, 0))
end

function ArenaService:trainingDummySpots(): { CFrame }
	return trainingSpots
end

return ArenaService
