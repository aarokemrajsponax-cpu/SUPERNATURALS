-- NPC fighters: training dummies for practising on, and CPU opponents (whose
-- brain is CpuService). They use the same fighter records and combat rules as
-- players, so anything that works on a dummy works in a real fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local DummyService = {}

local rgb = Color3.fromRGB

local KINDS = {
	-- Stands still and takes hits
	PunchingBag = { name = "Punching Bag", behavior = "Idle", color = rgb(214, 150, 70) },
	-- Always blocks and turns to face you: practise heavies and guard breaks
	Guard = { name = "Guard Dummy", behavior = "Guard", color = rgb(80, 140, 230) },
	-- Faces you and blocks now and then: practise reading a defence
	Sparring = { name = "Sparring Dummy", behavior = "Spar", color = rgb(200, 70, 90) },
	-- A CPU opponent with a power (see CpuService)
	Cpu = { name = "CPU", behavior = "Cpu", color = rgb(120, 120, 140) },
}

local TRAINING_ORDER = { "PunchingBag", "Guard", "Sparring" }
local SIGHT_RANGE = 30
local RETRY_DELAY = 2
-- Training dummies knocked further than this from their spot walk back to it
local HOME_RANGE = 4
-- Guard and sparring dummies break throws and tech roll this often, so players
-- can practise both sides of the grab and knockdown games
local SPAR_RECOVERY = 0.5

export type Dummy = {
	id: string,
	kind: typeof(KINDS.PunchingBag),
	spawnAt: () -> CFrame,
	parent: Instance,
	training: boolean,
	active: boolean,
	model: Model?,
	fighter: any?,
	-- CPU opponents: which power and degree they play, and how well
	cpu: { power: string, degree: number, difficulty: string }?,
}

local dummies: { [string]: Dummy } = {}
local counter = 0
local folder: Folder

function DummyService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	self.arenas = services.ArenaService
	self.combat = services.CombatService
end

function DummyService:Start()
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = workspace

	self.characters:onKnockout(function(fighter)
		local dummy = dummies[fighter.id]
		if dummy and dummy.active and dummy.fighter == fighter then
			task.delay(Combat.RespawnTime, function()
				if dummy.active and dummy.fighter == fighter then
					self:_build(dummy)
				end
			end)
		end
	end)

	for index, spot in self.arenas:trainingDummySpots() do
		self:spawn(TRAINING_ORDER[index] or "PunchingBag", {
			spawnAt = function()
				return spot
			end,
			training = true,
		})
	end
end

-- A fresh fighter id for a dummy that will be spawned later
function DummyService:reserveId(): string
	counter += 1
	return "Npc:" .. counter
end

-- Creates a dummy that respawns at spawnAt() whenever it's knocked out, until despawned
-- options.cpu = { power, degree, difficulty } for a CPU opponent
function DummyService:spawn(kindName: string, options: { spawnAt: () -> CFrame, id: string?, training: boolean?, parent: Instance?, cpu: { power: string, degree: number, difficulty: string }? }): Dummy
	local dummy: Dummy = {
		id = options.id or self:reserveId(),
		kind = KINDS[kindName] or KINDS.PunchingBag,
		spawnAt = options.spawnAt,
		parent = options.parent or folder,
		training = options.training == true,
		active = true,
		model = nil,
		fighter = nil,
		cpu = options.cpu,
	}
	dummies[dummy.id] = dummy
	self:_build(dummy)
	return dummy
end

function DummyService:despawn(dummy: Dummy)
	dummy.active = false
	dummies[dummy.id] = nil
	if dummy.fighter then
		self.characters:unregister(dummy.fighter)
	end
	if dummy.model then
		dummy.model:Destroy()
		dummy.model = nil
	end
	dummy.fighter = nil
end

function DummyService:_build(dummy: Dummy)
	-- Retire the old body first, so nothing acts on it once it's gone
	if dummy.fighter then
		self.characters:unregister(dummy.fighter)
		dummy.fighter = nil
	end
	if dummy.model then
		dummy.model:Destroy()
		dummy.model = nil
	end
	local kind = dummy.kind
	local cpu = dummy.cpu
	local powerDef = if cpu then Powers.get(cpu.power) else nil
	local bodyColor = if powerDef then powerDef.colors.primary else kind.color
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = rgb(235, 235, 240)
	description.TorsoColor = bodyColor
	description.LeftArmColor = bodyColor
	description.RightArmColor = bodyColor
	description.LeftLegColor = if powerDef then powerDef.colors.secondary else rgb(60, 62, 75)
	description.RightLegColor = if powerDef then powerDef.colors.secondary else rgb(60, 62, 75)

	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn("[Dummies] Couldn't create a dummy, retrying: " .. tostring(result))
		task.delay(RETRY_DELAY, function()
			if dummy.active and dummy.model == nil then
				self:_build(dummy)
			end
		end)
		return
	end
	if not dummy.active then
		result:Destroy()
		return
	end

	local model = result :: Model
	local displayName = if powerDef and cpu then `{powerDef.name} CPU` else kind.name
	model.Name = displayName
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:PivotTo(dummy.spawnAt())
	model.Parent = dummy.parent

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	dummy.model = model
	dummy.fighter = self.characters:register(model, {
		id = dummy.id,
		displayName = displayName,
		npc = true,
		trainingDummy = dummy.training,
	})
	model:SetAttribute("DummyKind", kind.behavior)
	if cpu and powerDef then
		-- A CPU plays its power's default loadout for that degree
		self.services.PowerService:equip(dummy.fighter, cpu.power, cpu.degree, Powers.defaultLoadout(cpu.power, cpu.degree))
		model:SetAttribute("CpuDifficulty", cpu.difficulty)
		self.services.CpuService:run(dummy.fighter, cpu.difficulty)
		return
	end
	task.spawn(self._behave, self, dummy, dummy.fighter)
end

-- Dummies raise their block with "Held", so they never parry (CPU parries come later)
local function nearestPlayer(characters, fighter)
	local best, bestDistance = nil, SIGHT_RANGE
	for _, other in characters:all() do
		if not other.npc and characters:isAlive(other) then
			local distance = (other.root.Position - fighter.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function hasKnockback(root: BasePart): boolean
	return root:FindFirstChild("SNKnockback") ~= nil or root:FindFirstChild("SNPull") ~= nil
end

function DummyService:_behave(dummy: Dummy, fighter)
	local behavior = dummy.kind.behavior
	local nextDecision = 0
	local awaySince: number? = nil
	local techFor, rollFor = -1, -1
	while dummy.active and dummy.fighter == fighter and self.characters:isAlive(fighter) do
		task.wait(0.2)
		if not self.characters:isAlive(fighter) then
			break
		end
		local time = workspace:GetServerTimeNow()
		local state = fighter.state

		-- Training dummies knocked away come back to their spot after a moment
		if dummy.training then
			local home = dummy.spawnAt()
			local away = (fighter.root.Position - home.Position).Magnitude > HOME_RANGE
			if away and not FighterState.isStunned(state, time) and not hasKnockback(fighter.root) then
				awaySince = awaySince or time
				if time - (awaySince :: number) > 1.5 then
					fighter.root.AssemblyLinearVelocity = Vector3.zero
					fighter.model:PivotTo(home)
					awaySince = nil
				end
			else
				awaySince = nil
			end
		end
		if behavior == "Idle" then
			continue
		end

		-- Break a throw, or roll out of a knockdown (through the same rules as players)
		if FighterState.canTech(state, fighter.combat, time) and techFor ~= state.grabbedAt then
			techFor = state.grabbedAt
			if math.random() < SPAR_RECOVERY then
				self.combat:perform(fighter, Protocol.CombatAction.Grab)
			end
		elseif FighterState.isDowned(state, time) and rollFor ~= state.downedAt then
			rollFor = state.downedAt
			if math.random() < SPAR_RECOVERY then
				self.combat:perform(fighter, Protocol.CombatAction.Dodge)
			end
		end

		local target = nearestPlayer(self.characters, fighter)

		if target and not FighterState.isStunned(state, time) then
			local position = fighter.root.Position
			local aim = Vector3.new(target.root.Position.X, position.Y, target.root.Position.Z)
			if (aim - position).Magnitude > 0.5 then
				fighter.root.CFrame = CFrame.lookAt(position, aim)
			end
		end

		if behavior == "Guard" then
			if not FighterState.isBlocking(state) then
				self.combat:perform(fighter, Protocol.CombatAction.BlockStart, "Held")
			end
		elseif behavior == "Spar" and time >= nextDecision then
			if FighterState.isBlocking(state) then
				self.combat:perform(fighter, Protocol.CombatAction.BlockEnd)
				nextDecision = time + math.random(15, 30) / 10
			elseif target and math.random() < 0.5 then
				self.combat:perform(fighter, Protocol.CombatAction.BlockStart, "Held")
				nextDecision = time + 1.2
			else
				nextDecision = time + 1
			end
		end
	end
end

return DummyService
