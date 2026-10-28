-- Temporary physical things powers create: barriers, walls, cages, deployed
-- devices, interface fields. They're real parts (so they block movement and
-- projectiles for everyone), each with a lifetime, optional health, and a cap
-- per owner. All of an owner's constructs disappear when they're knocked out,
-- leave, or their match ends.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)

local ConstructService = {}

-- Most constructs one fighter can have at once (each ability can set a lower cap)
local MAX_PER_OWNER = 6

export type Spec = {
	-- Kind of construct, used for per-kind caps ("Barrier", "Cage", "Turret"...)
	name: string,
	power: string?,
	ability: string?,
	duration: number,
	-- Builds the look: return a Model or BasePart (parts are anchored for you).
	-- Simple specs can give cframe/size/color/material/transparency instead.
	build: ((model: Model) -> ())?,
	cframe: CFrame?,
	size: Vector3?,
	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	-- Blocks walking (default true)
	collides: boolean?,
	-- Projectiles that touch it take this much off its health (nil = unbreakable)
	health: number?,
	-- At most this many of this kind per owner (the oldest goes)
	limit: number?,
	onEnd: ((construct: any, reason: string) -> ())?,
}

local folder: Folder
local constructs: { [string]: any } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

function ConstructService:Init(services)
	self.services = services
	self.characters = services.CharacterService
	folder = Instance.new("Folder")
	folder.Name = "SNConstructs"
	folder.Parent = workspace
end

function ConstructService:Start()
	local function clear(fighter)
		self:clearOwner(fighter)
	end
	self.characters:onKnockout(clear)
	self.characters:onUnregistered(clear)
end

local function ofOwner(ownerId: string, name: string?): { any }
	local list = {}
	for _, construct in constructs do
		if construct.ownerId == ownerId and (name == nil or construct.spec.name == name) then
			table.insert(list, construct)
		end
	end
	table.sort(list, function(a, b)
		return a.createdAt < b.createdAt
	end)
	return list
end

function ConstructService:create(owner, spec: Spec)
	-- Respect the caps: replace the oldest instead of piling up
	local sameKind = ofOwner(owner.id, spec.name)
	local limit = math.min(spec.limit or MAX_PER_OWNER, MAX_PER_OWNER)
	while #sameKind >= limit do
		self:destroy(table.remove(sameKind, 1), "Replaced")
	end
	local all = ofOwner(owner.id)
	while #all >= MAX_PER_OWNER do
		self:destroy(table.remove(all, 1), "Replaced")
	end

	local model = Instance.new("Model")
	model.Name = "SN" .. spec.name
	if spec.build then
		spec.build(model)
	else
		local part = Instance.new("Part")
		part.Name = "Body"
		part.Size = spec.size or Vector3.new(8, 8, 1)
		part.CFrame = spec.cframe or CFrame.new()
		part.Color = spec.color or Color3.new(1, 1, 1)
		part.Material = spec.material or Enum.Material.ForceField
		part.Transparency = spec.transparency or 0.2
		part.Parent = model
	end
	local collides = spec.collides ~= false
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = collides and item.CanCollide
			item.CanQuery = true
			item.CanTouch = false
			item.CastShadow = false
		end
	end
	local id = HttpService:GenerateGUID(false)
	local construct = {
		id = id,
		owner = owner,
		ownerId = owner.id,
		spec = spec,
		model = model,
		createdAt = now(),
		endsAt = now() + spec.duration,
		health = spec.health,
		alive = true,
	}
	model:SetAttribute("ConstructId", id)
	model:SetAttribute("Owner", owner.id)
	model:SetAttribute("EndsAt", construct.endsAt)
	if spec.power then
		model:SetAttribute("Power", spec.power)
	end
	CollectionService:AddTag(model, Protocol.Tag.Construct)
	model.Parent = folder
	constructs[id] = construct
	task.delay(spec.duration, function()
		self:destroy(construct, "Expired")
	end)
	return construct
end

function ConstructService:destroy(construct, reason: string)
	if not construct or not construct.alive then
		return
	end
	construct.alive = false
	constructs[construct.id] = nil
	if construct.spec.onEnd then
		task.spawn(construct.spec.onEnd, construct, reason)
	end
	construct.model:Destroy()
end

function ConstructService:damage(construct, amount: number)
	if not construct.alive or construct.health == nil then
		return
	end
	construct.health -= amount
	construct.model:SetAttribute("Health", construct.health)
	if construct.health <= 0 then
		self:destroy(construct, "Broken")
	end
end

-- Which construct (if any) an instance belongs to
function ConstructService:fromInstance(instance: Instance?)
	local current = instance
	while current and current ~= folder do
		local id = current:GetAttribute("ConstructId")
		if typeof(id) == "string" then
			return constructs[id]
		end
		current = current.Parent
	end
	return nil
end

-- ProjectileService calls this when a projectile ends against a part
function ConstructService:projectileHit(instance: Instance?, projectile)
	local construct = self:fromInstance(instance)
	if construct and construct.ownerId ~= projectile.ownerId then
		self:damage(construct, projectile.spec.hit.Damage or 0)
	end
end

function ConstructService:ofOwner(owner, name: string?): { any }
	return ofOwner(owner.id, name)
end

function ConstructService:clearOwner(fighter)
	for _, construct in ofOwner(fighter.id) do
		self:destroy(construct, "OwnerGone")
	end
end

return ConstructService
