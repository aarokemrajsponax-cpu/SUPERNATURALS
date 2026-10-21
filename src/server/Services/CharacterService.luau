-- Keeps a "fighter" record for every character that can fight: players and
-- NPCs (training dummies, and later CPU opponents). It owns each fighter's
-- combat state, turns that state into movement (walk speed, jumping), publishes
-- it to clients as attributes, and reports knockouts and spawns.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Attribute = Protocol.Attribute

local CharacterService = {}

export type Fighter = {
	id: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	npc: boolean,
	trainingDummy: boolean,
	displayName: string,
	state: FighterState.State,
	-- The combat numbers this fighter uses (Config/Combat changed by its power,
	-- degree and form). PowerService swaps it; everything else just reads it.
	combat: any,
	-- Walk speed multiplier from the owner panel's speed boost
	moveBoost: number,
	-- Walk speed multiplier from status effects (slows, hastes), set by StatusService
	statusSpeed: number,
	-- Rooted by a status: can still attack, can't walk
	rooted: boolean,
	-- Until when this fighter's own ability is moving it (dashes, charges)
	dashUntil: number,
	-- The power this fighter is using (PowerService's runtime record), if any
	power: any?,
	-- When the fighter was last teleported (positions can lag just after)
	teleportedAt: number,
	movementToken: number,
	connections: { RBXScriptConnection },
}

local byModel: { [Model]: Fighter } = {}
local byId: { [string]: Fighter } = {}
local byPlayer: { [Player]: Fighter } = {}

local knockoutListeners: { (Fighter, Fighter?) -> () } = {}
local spawnListeners: { (Fighter) -> () } = {}
local restoreListeners: { (Fighter) -> () } = {}
local unregisterListeners: { (Fighter) -> () } = {}
local spawnResolver: ((Player) -> CFrame?)? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Attributes can't hold infinities; "never" becomes 0
local function stamp(time: number): number
	if time ~= time or time == math.huge or time == -math.huge then
		return 0
	end
	return time
end

function CharacterService:Init(services)
	self.services = services
	Players.RespawnTime = Combat.RespawnTime
end

function CharacterService:Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:_onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(self._onCharacter, self, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local fighter = byPlayer[player]
		if fighter then
			self:unregister(fighter)
		end
	end)
end

function CharacterService:_onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	-- CharacterAdded can fire before the character is put in the world, so wait for that
	local deadline = os.clock() + 10
	while player.Character == character and not character:IsDescendantOf(workspace) and os.clock() < deadline do
		task.wait()
	end
	if not humanoid or not root or player.Character ~= character or not character:IsDescendantOf(workspace) then
		return
	end
	local previous = byPlayer[player]
	if previous then
		self:unregister(previous)
	end
	local fighter = self:register(character, {
		id = "Player:" .. player.UserId,
		displayName = player.DisplayName,
		player = player,
	})

	local destination = spawnResolver and spawnResolver(player)
	if destination then
		-- Wait a frame so Roblox finishes placing the character at its spawn
		-- first, then check once more in case the engine moved it back
		task.defer(function()
			if not character.Parent then
				return
			end
			self:teleport(fighter, destination)
			local stamp = fighter.teleportedAt
			task.wait(0.25)
			-- Only if nothing else has moved them since, and they still belong there
			local still = spawnResolver and spawnResolver(player)
			if
				character.Parent
				and byPlayer[player] == fighter
				and fighter.teleportedAt == stamp
				and still
				and (fighter.root.Position - still.Position).Magnitude > 12
			then
				self:teleport(fighter, still)
			end
		end)
	end
	for _, listener in spawnListeners do
		task.spawn(listener, fighter)
	end
end

-- Registers a character as a fighter. Players are registered automatically;
-- NPCs call this themselves.
function CharacterService:register(model: Model, info: { id: string, displayName: string, player: Player?, npc: boolean?, trainingDummy: boolean? }): Fighter
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	assert(humanoid and root, "fighters need a Humanoid and a HumanoidRootPart")

	local existing = byId[info.id]
	if existing then
		self:unregister(existing)
	end

	humanoid.MaxHealth = Combat.MaxHealth
	humanoid.Health = Combat.MaxHealth
	model:SetAttribute(Attribute.MaxHealth, Combat.MaxHealth)
	humanoid.UseJumpPower = false
	-- Clients draw their own name and health bars over fighters
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local fighter: Fighter = {
		id = info.id,
		model = model,
		humanoid = humanoid,
		root = root,
		player = info.player,
		npc = info.npc == true,
		trainingDummy = info.trainingDummy == true,
		displayName = info.displayName,
		state = FighterState.new(info.id, Combat, now()),
		combat = Combat,
		moveBoost = 1,
		statusSpeed = 1,
		rooted = false,
		dashUntil = 0,
		power = nil,
		teleportedAt = 0,
		movementToken = 0,
		connections = {},
	}
	byModel[model] = fighter
	byId[fighter.id] = fighter
	if info.player then
		byPlayer[info.player] = fighter
	end

	model:SetAttribute(Attribute.FighterId, fighter.id)
	model:SetAttribute(Attribute.DisplayName, fighter.displayName)
	model:SetAttribute(Attribute.MaxGuard, Combat.Block.MaxGuard)
	CollectionService:AddTag(model, Protocol.Tag.Fighter)

	table.insert(fighter.connections, humanoid.Died:Connect(function()
		self:_onDied(fighter)
	end))
	table.insert(fighter.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			self:unregister(fighter)
		end
	end))

	self:refresh(fighter)
	return fighter
end

function CharacterService:unregister(fighter: Fighter)
	if byId[fighter.id] ~= fighter then
		return
	end
	for _, connection in fighter.connections do
		connection:Disconnect()
	end
	table.clear(fighter.connections)
	-- Invalidates any pending movement refresh and cancels attacks in flight
	fighter.movementToken += 1
	FighterState.cancelAttack(fighter.state)
	byModel[fighter.model] = nil
	byId[fighter.id] = nil
	if fighter.player and byPlayer[fighter.player] == fighter then
		byPlayer[fighter.player] = nil
	end
	for _, listener in unregisterListeners do
		task.spawn(listener, fighter)
	end
end

-- Runs when a fighter stops existing (character removed, player left)
function CharacterService:onUnregistered(callback: (Fighter) -> ())
	table.insert(unregisterListeners, callback)
end

function CharacterService:_onDied(fighter: Fighter)
	if fighter.state.knockedOut then
		return
	end
	local creditedId = FighterState.knockOut(fighter.state, Combat, now())
	self:refresh(fighter)
	local credited = if creditedId then byId[creditedId] else nil
	for _, listener in knockoutListeners do
		task.spawn(listener, fighter, credited)
	end
end

-- Applies the fighter's state to its humanoid and publishes it to clients.
-- Call after anything changes a fighter's state.
function CharacterService:refresh(fighter: Fighter)
	if byId[fighter.id] ~= fighter then
		return
	end
	local state = fighter.state
	local time = now()
	local humanoid = fighter.humanoid

	local walkSpeed, jumpHeight, autoRotate = FighterState.movement(state, fighter.combat, time)
	if fighter.rooted then
		walkSpeed, jumpHeight = 0, 0
	end
	if humanoid.Health > 0 then
		humanoid.WalkSpeed = walkSpeed * fighter.moveBoost * fighter.statusSpeed
		humanoid.JumpHeight = jumpHeight
		humanoid.AutoRotate = autoRotate
	end

	local model = fighter.model
	model:SetAttribute(Attribute.Guard, state.guard)
	model:SetAttribute(Attribute.GuardUpdatedAt, stamp(state.guardChangedAt))
	model:SetAttribute(Attribute.Blocking, FighterState.isBlocking(state))
	model:SetAttribute(Attribute.StunnedUntil, stamp(state.stunUntil))
	model:SetAttribute(Attribute.HeavyReadyAt, stamp(state.heavyReadyAt))
	model:SetAttribute(Attribute.DodgeReadyAt, stamp(state.dodgeReadyAt))
	model:SetAttribute(Attribute.BusyUntil, stamp(FighterState.busyUntil(state)))
	model:SetAttribute(Attribute.ProtectedUntil, stamp(state.protectedUntil))

	-- Come back when a timed state (stun, attack, dodge) runs out. Only the
	-- newest scheduled refresh does anything.
	local nextChange = FighterState.nextMovementChange(state, time)
	fighter.movementToken += 1
	if nextChange then
		local token = fighter.movementToken
		task.delay(nextChange - time + 0.01, function()
			if fighter.movementToken == token then
				self:refresh(fighter)
			end
		end)
	end
end

-- Lookups ----------------------------------------------------------------------

function CharacterService:getFighter(model: Model): Fighter?
	return byModel[model]
end

function CharacterService:getById(id: string): Fighter?
	return byId[id]
end

function CharacterService:getByPlayer(player: Player): Fighter?
	return byPlayer[player]
end

function CharacterService:all(): { Fighter }
	local list = {}
	for _, fighter in byId do
		table.insert(list, fighter)
	end
	return list
end

function CharacterService:isAlive(fighter: Fighter): boolean
	return byId[fighter.id] == fighter
		and fighter.model.Parent ~= nil
		and fighter.root.Parent ~= nil
		and fighter.humanoid.Health > 0
		and not fighter.state.knockedOut
end

-- Hooks ------------------------------------------------------------------------

-- callback(victim, creditedFighterOrNil)
function CharacterService:onKnockout(callback: (Fighter, Fighter?) -> ())
	table.insert(knockoutListeners, callback)
end

function CharacterService:onSpawned(callback: (Fighter) -> ())
	table.insert(spawnListeners, callback)
end

-- Decides where a player's new character appears (nil = normal spawn)
function CharacterService:setSpawnResolver(resolver: (Player) -> CFrame?)
	spawnResolver = resolver
end

-- Actions ----------------------------------------------------------------------

function CharacterService:teleport(fighter: Fighter, destination: CFrame)
	-- Stand up first: a seated character would drag its (anchored) seat along
	local humanoid = fighter.humanoid
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	fighter.teleportedAt = now()
	fighter.root.AssemblyLinearVelocity = Vector3.zero
	fighter.root.AssemblyAngularVelocity = Vector3.zero
	fighter.model:PivotTo(destination)
end

-- Full health and a clean combat state (optionally with spawn protection)
function CharacterService:restore(fighter: Fighter, protection: number?)
	if fighter.humanoid.Health > 0 then
		fighter.humanoid.Health = fighter.humanoid.MaxHealth
	end
	FighterState.reset(fighter.state, fighter.combat, now(), protection)
	self:refresh(fighter)
	for _, listener in restoreListeners do
		task.spawn(listener, fighter)
	end
end

-- Runs after restore() (powers reset their resources, statuses are cleared)
function CharacterService:onRestored(callback: (Fighter) -> ())
	table.insert(restoreListeners, callback)
end

function CharacterService:setFrozen(fighter: Fighter, frozen: boolean)
	FighterState.setFrozen(fighter.state, frozen, fighter.combat, now())
	self:refresh(fighter)
end

-- Switches the fighter to new combat numbers (a power, degree or form change).
-- Health keeps the same share of the new maximum.
function CharacterService:setCombatProfile(fighter: Fighter, profile)
	if fighter.combat == profile then
		return
	end
	fighter.combat = profile
	local humanoid = fighter.humanoid
	local maxHealth = profile.MaxHealth or Combat.MaxHealth
	if humanoid.MaxHealth ~= maxHealth then
		local share = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = maxHealth
		if humanoid.Health > 0 then
			humanoid.Health = math.max(1, math.floor(maxHealth * share + 0.5))
		end
		fighter.model:SetAttribute(Attribute.MaxHealth, maxHealth)
	end
	fighter.model:SetAttribute(Attribute.MaxGuard, profile.Block.MaxGuard)
	self:refresh(fighter)
end

function CharacterService:heal(fighter: Fighter, amount: number)
	local humanoid = fighter.humanoid
	if amount > 0 and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

return CharacterService
