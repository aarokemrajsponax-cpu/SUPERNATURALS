-- Runs the owner's "admin abuse" events. The server does the physical part
-- (pushing, pulling, freezing, low gravity, growing players) and tells every
-- client what to draw. Only one event runs at a time, every event ends on its
-- own, and stopping an event always undoes what it changed.
--
-- Event state is published as ReplicatedStorage attributes so players who join
-- mid-event see it too; one-off moments (a meteor, a lightning strike) are sent
-- through Remotes.AdminEvent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminEvents = require(ReplicatedStorage.Shared.Config.AdminEvents)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminEvent = Remotes:WaitForChild("AdminEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Signal = Protocol.AdminSignal

local AdminEventService = {}

type Running = {
	id: string,
	token: {},
	cleanups: { () -> () },
}

local current: Running? = nil

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(vector: Vector3): Vector3?
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 1e-3 then flattened.Unit else nil
end

local function randomFlat(): Vector3
	local angle = math.random() * math.pi * 2
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

function AdminEventService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.damage = services.DamageService
	self.arenas = services.ArenaService
end

function AdminEventService:Start()
	ReplicatedStorage:SetAttribute(Attribute.AdminEvent, "")
end

-- Fighters an event may push around: anyone alive who isn't in a match and
-- hasn't made themselves immune
function AdminEventService:eligible(): { any }
	local matchService = self.services.MatchService
	local list = {}
	for _, fighter in self.characters:all() do
		local immune = fighter.player and fighter.player:GetAttribute(Attribute.Immune) == true
		if self.characters:isAlive(fighter) and not immune and matchService:getMatchOf(fighter) == nil then
			table.insert(list, fighter)
		end
	end
	return list
end

function AdminEventService:currentId(): string?
	return if current then current.id else nil
end

-- A point on the ground below `position`
function AdminEventService:ground(position: Vector3): Vector3
	local ignore = {}
	for _, fighter in self.characters:all() do
		table.insert(ignore, fighter.model)
	end
	groundParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 150, 0), Vector3.new(0, -400, 0), groundParams)
	return if result then result.Position else Vector3.new(position.X, 0, position.Z)
end

-- Somewhere near the lobby crowd: usually near a random player, sometimes anywhere around spawn
function AdminEventService:randomSpot(spread: number): Vector3
	local targets = self:eligible()
	local base
	if #targets > 0 and math.random() < 0.7 then
		base = targets[math.random(1, #targets)].root.Position
	else
		local angle = math.random() * math.pi * 2
		local distance = math.random() * 70
		base = self.arenas:lobbyCenter() + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	end
	local jitter = Vector3.new((math.random() - 0.5) * 2 * spread, 0, (math.random() - 0.5) * 2 * spread)
	return self:ground(base + jitter)
end

-- Pushes everyone within `radius` of `center` outward (stronger closer in)
function AdminEventService:blast(center: Vector3, radius: number, push: number, lift: number)
	for _, fighter in self:eligible() do
		local offset = fighter.root.Position - center
		local distance = offset.Magnitude
		if distance <= radius then
			local strength = 1 - (distance / radius) * 0.5
			self.damage:push(fighter, flat(offset) or randomFlat(), push * strength, lift * strength, 0.25)
		end
	end
end

-- Lifecycle ------------------------------------------------------------------------

function AdminEventService:start(id: string, owner: Player?): boolean
	local def = AdminEvents.Events[id]
	if not def then
		return false
	end
	self:stop()

	local running: Running = { id = id, token = {}, cleanups = {} }
	current = running
	local startedAt = now()
	local center = self:_centerFor(owner)

	ReplicatedStorage:SetAttribute(Attribute.AdminEventStartedAt, startedAt)
	ReplicatedStorage:SetAttribute(Attribute.AdminEventEndsAt, startedAt + def.duration)
	ReplicatedStorage:SetAttribute(Attribute.AdminEventCenter, center)
	ReplicatedStorage:SetAttribute(Attribute.AdminEvent, id)

	local context = {
		def = def,
		center = center,
		startedAt = startedAt,
		alive = function(): boolean
			return current == running
		end,
		onCleanup = function(callback: () -> ())
			table.insert(running.cleanups, callback)
		end,
	}
	local runner = (self :: any)["_run" .. id]
	if runner then
		task.spawn(function()
			local ok, err = pcall(runner, self, context)
			if not ok then
				warn(`[AdminEvents] {id} stopped early: {err}`)
			end
		end)
	end
	task.delay(def.duration, function()
		if current == running then
			self:stop()
		end
	end)
	return true
end

function AdminEventService:stop()
	local running = current
	if not running then
		return
	end
	current = nil
	for _, cleanup in running.cleanups do
		local ok, err = pcall(cleanup)
		if not ok then
			warn("[AdminEvents] cleanup failed: " .. tostring(err))
		end
	end
	ReplicatedStorage:SetAttribute(Attribute.AdminEvent, "")
end

-- Events centre on the owner if they're in the lobby, otherwise on spawn
function AdminEventService:_centerFor(owner: Player?): Vector3
	local fighter = owner and self.characters:getByPlayer(owner)
	if fighter and self.characters:isAlive(fighter) and self.services.MatchService:getMatchOf(fighter) == nil then
		return self:ground(fighter.root.Position)
	end
	return self:ground(self.arenas:lobbyCenter())
end

-- Repeats `step` every `interval` seconds while the event runs
local function every(context, interval: number, step: () -> ())
	while context.alive() do
		task.wait(interval)
		if not context.alive() then
			return
		end
		step()
	end
end

-- Events ----------------------------------------------------------------------------

function AdminEventService:_runMeteorShower(context)
	local def = context.def
	every(context, def.interval, function()
		local spot = self:randomSpot(14)
		AdminEvent:FireAllClients(Signal.Meteor, {
			position = spot,
			impactAt = now() + def.warning,
			size = 3 + math.random() * 3,
		})
		task.delay(def.warning, function()
			if context.alive() then
				self:blast(spot, def.radius, def.push, def.lift)
			end
		end)
	end)
end

function AdminEventService:_runThunderstorm(context)
	local def = context.def
	every(context, def.interval, function()
		local spot = self:randomSpot(6)
		AdminEvent:FireAllClients(Signal.Strike, { position = spot, impactAt = now() + def.warning })
		task.delay(def.warning, function()
			if context.alive() then
				self:blast(spot, def.radius, def.push, def.lift)
			end
		end)
	end)
end

function AdminEventService:_runBlackHole(context)
	local def = context.def
	local core = context.center + Vector3.new(0, 24, 0)
	local collapseAt = context.startedAt + def.collapseAt
	self:_scheduleBlackHoleBlast(context)
	every(context, 0.15, function()
		if now() >= collapseAt then
			return
		end
		for _, fighter in self:eligible() do
			local toCore = core - fighter.root.Position
			local distance = toCore.Magnitude
			if distance < def.pullRange and distance > 0.5 then
				local inward = toCore.Unit
				local swirl = Vector3.yAxis:Cross(inward)
				swirl = if swirl.Magnitude > 1e-3 then swirl.Unit else Vector3.zero
				local closeness = 1 - distance / def.pullRange
				local speed = def.pullSpeed * (0.6 + 0.4 * closeness)
				-- Near the core, hover in orbit instead of piling into the middle
				local inwardShare = if distance < 10 then 0.15 else 1
				self.damage:setVelocity(fighter, inward * speed * inwardShare + swirl * 22, 0.2)
			end
		end
	end)
end

function AdminEventService:_scheduleBlackHoleBlast(context)
	local def = context.def
	local core = context.center + Vector3.new(0, 24, 0)
	task.delay(def.collapseAt, function()
		if not context.alive() then
			return
		end
		AdminEvent:FireAllClients(Signal.BlackHoleBlast, { position = core })
		for _, fighter in self:eligible() do
			local offset = fighter.root.Position - core
			if offset.Magnitude < def.pullRange + 30 then
				self.damage:push(fighter, flat(offset) or randomFlat(), def.blast, def.blastLift, 0.3)
			end
		end
	end)
end

function AdminEventService:_runIceAge(context)
	local def = context.def
	local frozen: { [Model]: BasePart } = {}
	local function thawAll()
		for model, root in frozen do
			if root.Parent then
				root.Anchored = false
			end
			if model.Parent then
				model:SetAttribute(Attribute.Iced, nil)
			end
		end
		table.clear(frozen)
	end
	context.onCleanup(thawAll)
	for _, window in def.freezes do
		task.delay(window[1], function()
			if not context.alive() then
				return
			end
			for _, fighter in self:eligible() do
				if not frozen[fighter.model] then
					frozen[fighter.model] = fighter.root
					fighter.root.AssemblyLinearVelocity = Vector3.zero
					fighter.root.Anchored = true
					fighter.model:SetAttribute(Attribute.Iced, true)
				end
			end
		end)
		task.delay(window[2], function()
			if context.alive() then
				thawAll()
			end
		end)
	end
	-- Anyone pulled into a match while frozen thaws straight away
	every(context, 0.25, function()
		local matchService = self.services.MatchService
		for model, root in frozen do
			local fighter = self.characters:getFighter(model)
			if not fighter or matchService:getMatchOf(fighter) ~= nil then
				if root.Parent then
					root.Anchored = false
				end
				model:SetAttribute(Attribute.Iced, nil)
				frozen[model] = nil
			end
		end
	end)
end

function AdminEventService:_runLowGravity(context)
	local def = context.def
	local FORCE_NAME = "SNLowGravity"
	local affected: { [BasePart]: boolean } = {}
	local function remove(root: BasePart)
		for _, child in root:GetChildren() do
			if child.Name == FORCE_NAME or child.Name == FORCE_NAME .. "Force" then
				child:Destroy()
			end
		end
		affected[root] = nil
	end
	context.onCleanup(function()
		for root in affected do
			remove(root)
		end
	end)
	local function refresh()
		local eligibleRoots = {}
		for _, fighter in self:eligible() do
			eligibleRoots[fighter.root] = true
			local root = fighter.root
			local force = root:FindFirstChild(FORCE_NAME .. "Force") :: VectorForce?
			if not force then
				local attachment = Instance.new("Attachment")
				attachment.Name = FORCE_NAME
				attachment.Parent = root
				local newForce = Instance.new("VectorForce")
				newForce.Name = FORCE_NAME .. "Force"
				newForce.Attachment0 = attachment
				newForce.RelativeTo = Enum.ActuatorRelativeTo.World
				newForce.ApplyAtCenterOfMass = true
				newForce.Parent = root
				force = newForce
				affected[root] = true
			end
			-- Cancel most of gravity for the whole character
			local lift = root.AssemblyMass * workspace.Gravity * (1 - def.gravity)
			;(force :: VectorForce).Force = Vector3.new(0, lift, 0)
		end
		for root in affected do
			if not eligibleRoots[root] then
				remove(root)
			end
		end
	end
	refresh()
	every(context, 0.5, refresh)
end

function AdminEventService:_runGiantParty(context)
	local def = context.def
	local grown: { [Model]: boolean } = {}
	context.onCleanup(function()
		for model in grown do
			if model.Parent then
				pcall(model.ScaleTo, model, 1)
			end
		end
		table.clear(grown)
	end)
	local function refresh()
		local matchService = self.services.MatchService
		local eligibleModels = {}
		for _, fighter in self:eligible() do
			eligibleModels[fighter.model] = true
			if not grown[fighter.model] then
				if pcall(fighter.model.ScaleTo, fighter.model, def.scale) then
					grown[fighter.model] = true
				end
			end
		end
		for model in grown do
			local fighter = self.characters:getFighter(model)
			if not model.Parent or not fighter or matchService:getMatchOf(fighter) ~= nil then
				if model.Parent then
					pcall(model.ScaleTo, model, 1)
				end
				grown[model] = nil
			end
		end
	end
	refresh()
	every(context, 1, refresh)
end

return AdminEventService
