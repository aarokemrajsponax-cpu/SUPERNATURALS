-- Finds each power's client module (how its abilities look) and builds the
-- small `kit` every effect function gets: the caster's model and root, the
-- power's colours and numbers, the effects library, poses, camera shake, and a
-- way to keep long-lasting effects alive until the server says stop.
--
-- A power's client module returns:
--   fx = { [fxName] = function(kit) ... end }          (server ctx:fx(name, data))
--   projectiles = { [visual] = function(kit) -> { update = (position, velocity, dt) -> (), finish = (position, reason) -> () } }
--   appearance = function(kit) -> cleanup?               (persistent look while equipped)
--   onCast = function(kit) ... end                        (optional: pose when any ability starts)
--   predict = { [abilityId] = function(kit) ... end }     (optional: instant pose for the local player)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Poser = require(script.Parent.Effects.Poser)
local Vfx = require(script.Parent.Effects.Vfx)

local Attribute = Protocol.Attribute
local player = Players.LocalPlayer

local ClientPowers = {}

local modules: { [string]: any } = {}
local failed: { [string]: boolean } = {}
local camera: any = nil

-- Lasting effects by key (so the server can stop them early)
local kept: { [string]: { () -> () } } = {}

function ClientPowers.init(controllers)
	camera = controllers.CameraController
end

function ClientPowers.module(powerId: string?): any?
	if not powerId then
		return nil
	end
	if modules[powerId] then
		return modules[powerId]
	end
	if failed[powerId] then
		return nil
	end
	local source = script:FindFirstChild(powerId)
	if not source then
		failed[powerId] = true
		return nil
	end
	local ok, result = pcall(require, source)
	if not ok then
		failed[powerId] = true
		warn(`[Powers] couldn't load {powerId} effects: {result}`)
		return nil
	end
	modules[powerId] = result
	return result
end

-- Stops (cleans up) every effect kept under `key`
function ClientPowers.stop(key: string)
	local list = kept[key]
	if not list then
		return
	end
	kept[key] = nil
	for _, cleanup in list do
		local ok, err = pcall(cleanup)
		if not ok then
			warn("[Powers] effect cleanup failed: " .. tostring(err))
		end
	end
end

local function distanceToViewer(position: Vector3): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else workspace.CurrentCamera.CFrame.Position
	return (position - from).Magnitude
end

function ClientPowers.kit(model: Model?, powerId: string, data: { [string]: any }?)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local def = Powers.get(powerId)
	local degree = if model then model:GetAttribute(Attribute.Degree) else nil
	local form = if model then model:GetAttribute(Attribute.Form) else nil
	local payload = data or {}
	local kit = {
		model = model,
		root = if root and root:IsA("BasePart") then root else nil,
		power = powerId,
		def = def,
		degree = if typeof(degree) == "number" then degree else 1,
		form = if typeof(form) == "string" then form else "",
		colors = if def then def.colors else { primary = Color3.new(1, 1, 1), secondary = Color3.new(0.5, 0.5, 0.5), accent = Color3.new(1, 1, 1) },
		isLocal = model ~= nil and model == player.Character,
		data = payload,
		Vfx = Vfx,
		Poser = Poser,
	}

	function kit.now(): number
		return workspace:GetServerTimeNow()
	end

	-- Numbers for one of this power's abilities at the caster's degree
	function kit.ability(abilityId: string)
		return Powers.abilityFor(powerId, abilityId, kit.degree)
	end

	-- Camera shake that fades with distance from the viewer
	function kit.shake(strength: number, duration: number, at: Vector3?)
		if not camera then
			return
		end
		local position = at or (if kit.root then kit.root.Position else nil)
		local falloff = if position then math.clamp(1 - distanceToViewer(position) / 90, 0, 1) else 1
		if kit.isLocal then
			falloff = math.max(falloff, 0.6)
		end
		if falloff > 0.05 then
			camera:shake(strength * falloff, duration)
		end
	end

	function kit.near(position: Vector3, radius: number): boolean
		return distanceToViewer(position) <= radius
	end

	-- Keeps a cleanup for a lasting effect: it runs when the effect's duration
	-- passes (data.duration) or the server stops it (data.key), whichever is first
	function kit.keep(cleanup: () -> ())
		local key = payload.key
		if typeof(key) ~= "string" then
			key = tostring(cleanup)
		end
		kept[key] = kept[key] or {}
		table.insert(kept[key], cleanup)
		local duration = payload.duration
		task.delay((if typeof(duration) == "number" then duration else 10) + 0.1, function()
			ClientPowers.stop(key)
		end)
	end

	-- The current value of one of the caster's attributes
	function kit.attribute(name: string): any
		return if model then model:GetAttribute(name) else nil
	end

	return kit
end

return ClientPowers
