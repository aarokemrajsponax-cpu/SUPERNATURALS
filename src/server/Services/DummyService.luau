-- NPC fighters: training dummies for practising on, and CPU opponents (whose
-- brain is CpuService). They use the same fighter records and combat rules as
-- players, so anything that works on a dummy works in a real fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local FighterState = require(ReplicatedStorage.Shared.Combat.FighterState)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Practice = require(ReplicatedStorage.Shared.Config.Practice)
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

local TRAINING_ORDER = { "PunchingBag", "Guard", "Sparring", "PunchingBag", "Guard" }
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
	-- CPU opponents: which power and degree they play, and how well. profile, abilities and look
	-- are optional (Jeffery's practice unit: a CpuService profile, abilities on or off, "Jeffery")
	cpu: { power: string, degree: number, difficulty: string, profile: string?, abilities: boolean?, look: string? }?,
	-- Training readout (bays only): real hit numbers, see _record. labels = the bay screen's text
	readout: Readout?,
}

export type Readout = {
	last: number,
	lastResult: string,
	combo: number,
	best: number,
	comboAt: number,
	attacker: string?,
	hits: { { at: number, damage: number } },
	labels: { last: TextLabel?, combo: TextLabel?, dps: TextLabel?, note: TextLabel? }?,
	shown: { [string]: string },
}

local dummies: { [string]: Dummy } = {}
local counter = 0
local folder: Folder

local function newReadout(labels): Readout
	return { last = 0, lastResult = "", combo = 0, best = 0, comboAt = -math.huge, attacker = nil, hits = {}, labels = labels, shown = {} }
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Damage dealt in the last Practice.DpsWindow seconds, per second
local function dpsOf(readout: Readout, time: number): number
	local total = 0
	for index = #readout.hits, 1, -1 do
		local hit = readout.hits[index]
		if time - hit.at > Practice.DpsWindow then
			table.remove(readout.hits, index)
		else
			total += hit.damage
		end
	end
	return total / Practice.DpsWindow
end

local function setText(readout: Readout, key: string, text: string)
	local labels = readout.labels
	local label = labels and labels[key]
	if label and readout.shown[key] ~= text then
		readout.shown[key] = text
		label.Text = text
	end
end

-- The numbers a bay screen shows (also what tests read): { last, lastResult, combo, best, dps }
function DummyService:readoutFor(dummy: Dummy)
	local readout = dummy.readout
	if not readout then
		return nil
	end
	local time = now()
	return {
		last = readout.last,
		lastResult = readout.lastResult,
		combo = if time - readout.comboAt <= Practice.ComboGap then readout.combo else 0,
		best = readout.best,
		dps = dpsOf(readout, time),
	}
end

function DummyService:_refresh(dummy: Dummy)
	local readout = dummy.readout
	if not readout then
		return
	end
	local numbers = self:readoutFor(dummy)
	setText(readout, "last", if readout.last > 0 then string.format("%.1f", readout.last) .. (if readout.lastResult == "Hit" then "" else " " .. string.lower(readout.lastResult)) else "-")
	setText(readout, "combo", tostring(numbers.combo))
	setText(readout, "dps", string.format("%.1f", numbers.dps))
	setText(readout, "note", if readout.best > 0 then `Best combo {readout.best}` else "Hit the dummy to start")
end

-- A real hit on a bay dummy: only resolved hits that dealt damage count, never requests or guesses
function DummyService:_record(attacker, target, outcome)
	local dummy = dummies[target.id]
	local readout = dummy and dummy.readout
	if not dummy or not readout or dummy.cpu or not attacker or attacker == target or not outcome then
		return
	end
	local dealt = outcome.dealt or 0
	if dealt <= 0 then
		return
	end
	local time = now()
	if outcome.result == "Hit" then
		if readout.attacker == attacker.id and time - readout.comboAt <= Practice.ComboGap then
			readout.combo += 1
		else
			readout.combo = 1
		end
		readout.attacker = attacker.id
		readout.comboAt = time
		readout.best = math.max(readout.best, readout.combo)
		table.insert(readout.hits, { at = time, damage = dealt })
	end
	readout.last = dealt
	readout.lastResult = outcome.result
	self:_refresh(dummy)
end

-- The bay dummies (training, not CPU), in bay order
function DummyService:bayDummies(): { Dummy }
	local list = {}
	for _, dummy in dummies do
		if dummy.training and dummy.readout and not dummy.cpu then
			table.insert(list, dummy)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

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

	self.combat:onHit(function(attacker, target, outcome)
		self:_record(attacker, target, outcome)
	end)
	local bays = self.arenas:trainingBays()
	for index, spot in self.arenas:trainingDummySpots() do
		self:spawn(TRAINING_ORDER[index] or "PunchingBag", {
			spawnAt = function()
				return spot
			end,
			training = true,
			labels = bays[index] and bays[index].labels or nil,
		})
	end
	-- Readouts fade (the combo count falls to 0, DPS decays) without a new hit
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, dummy in dummies do
				if dummy.readout then
					self:_refresh(dummy)
				end
			end
		end
	end)
end

-- A fresh fighter id for a dummy that will be spawned later
function DummyService:reserveId(): string
	counter += 1
	return "Npc:" .. counter
end

-- Creates a dummy that respawns at spawnAt() whenever it's knocked out, until despawned
-- options.cpu = { power, degree, difficulty } for a CPU opponent
function DummyService:spawn(kindName: string, options: { spawnAt: () -> CFrame, id: string?, training: boolean?, parent: Instance?, cpu: { power: string, degree: number, difficulty: string, profile: string?, abilities: boolean?, look: string? }?, labels: any? }): Dummy
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
		readout = if options.labels then newReadout(options.labels) else nil,
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
	local displayName = if cpu and cpu.look == "Jeffery" then "Jeffery" elseif powerDef and cpu then `{powerDef.name} CPU` else kind.name
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
	if dummy.training and not cpu then
		self:_dress(model, kind)
	end
	if cpu and powerDef then
		-- A CPU plays its power's default loadout for that degree
		self.services.PowerService:equip(dummy.fighter, cpu.power, cpu.degree, Powers.defaultLoadout(cpu.power, cpu.degree))
		model:SetAttribute("CpuDifficulty", cpu.difficulty)
		if cpu.look == "Jeffery" then
			require(script.Parent.Parent.World.Jeffery).dress(model)
			model:SetAttribute("Practice", true)
		end
		self.services.CpuService:run(dummy.fighter, cpu.difficulty, cpu.profile, { abilities = cpu.abilities })
		return
	end
	task.spawn(self._behave, self, dummy, dummy.fighter)
end

-- Welds a small prop to a body part
local function attach(model: Model, partName: string, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local base = model:FindFirstChild(partName)
	if not base or not base:IsA("BasePart") then
		return
	end
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.Color = color
	piece.Material = material
	if shape then
		piece.Shape = shape
	end
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CFrame = base.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = piece
	weld.Parent = piece
	piece.Parent = model
end

-- Bay dummies get a look of their own: a painted chest target, plus a cap on the punching bag,
-- a plate on the guard's forearm and a headband on the sparring dummy
function DummyService:_dress(model: Model, kind)
	local ring = rgb(236, 232, 220)
	attach(model, "UpperTorso", "ChestTarget", Vector3.new(0.12, 1.5, 1.5), CFrame.new(0, 0.1, -0.55) * CFrame.Angles(0, math.rad(90), 0), rgb(214, 70, 56), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	attach(model, "UpperTorso", "ChestCentre", Vector3.new(0.14, 0.6, 0.6), CFrame.new(0, 0.1, -0.58) * CFrame.Angles(0, math.rad(90), 0), ring, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	if kind.behavior == "Idle" then
		attach(model, "Head", "Cap", Vector3.new(1.35, 0.4, 1.35), CFrame.new(0, 0.62, 0), kind.color, Enum.Material.Fabric)
	elseif kind.behavior == "Guard" then
		attach(model, "LeftLowerArm", "ForearmPlate", Vector3.new(0.3, 1.1, 0.9), CFrame.new(0.32, 0, 0), rgb(150, 160, 176), Enum.Material.Metal)
	else
		attach(model, "Head", "Headband", Vector3.new(1.3, 0.22, 1.3), CFrame.new(0, 0.28, 0), kind.color, Enum.Material.Fabric)
	end
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
