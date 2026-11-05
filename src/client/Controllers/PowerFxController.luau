-- Draws powers for everyone: ability effects the server announces, ability
-- wind-up poses, projectiles in flight, and each fighter's persistent power look
-- (Machine Master's fuel cell, Corruption's spreading black, an animal form...).
-- Everything here is cosmetic; the server already decided what happened.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local ClientPowers = require(script.Parent.Parent.Powers)
local Poser = require(script.Parent.Parent.Effects.Poser)
local Vfx = require(script.Parent.Parent.Effects.Vfx)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Event = Protocol.AbilityEvent

local PowerFxController = {}

type Flying = {
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	t0: number,
	endsAt: number,
	handle: { update: (Vector3, Vector3, number) -> (), finish: (Vector3, string) -> () },
}

local flying: { [string]: Flying } = {}
-- When the local player already showed their own cast, the server's echo is skipped
local predicted: { [string]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isModel(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Model")
end

-- Runs a power module function safely; a broken effect never breaks the game
local function run(label: string, callback, ...)
	local ok, err = pcall(callback, ...)
	if not ok then
		warn(`[PowerFx] {label} failed: {err}`)
	end
	return ok
end

function PowerFxController:Init(controllers)
	ClientPowers.init(controllers)
end

function PowerFxController:Start()
	AbilityEvent.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == Event.Fx then
			self:_onFx(data)
		elseif kind == Event.Cast then
			self:_onCast(data)
		elseif kind == Event.ProjectileSpawn then
			self:_onProjectileSpawn(data)
		elseif kind == Event.ProjectileUpdate then
			self:_onProjectileUpdate(data)
		elseif kind == Event.ProjectileEnd then
			self:_onProjectileEnd(data)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		self:_stepProjectiles(dt)
	end)

	for _, model in CollectionService:GetTagged(Protocol.Tag.Fighter) do
		self:_watchAppearance(model)
	end
	CollectionService:GetInstanceAddedSignal(Protocol.Tag.Fighter):Connect(function(model)
		self:_watchAppearance(model)
	end)
end

-- Effects ------------------------------------------------------------------------------

function PowerFxController:_onFx(data)
	if data.power == "Common" then
		if data.fx == "Stop" and typeof(data.data) == "table" and typeof(data.data.key) == "string" then
			ClientPowers.stop(data.data.key)
		end
		return
	end
	if typeof(data.power) ~= "string" or typeof(data.fx) ~= "string" then
		return
	end
	local module = ClientPowers.module(data.power)
	local handler = module and module.fx and module.fx[data.fx]
	if not handler then
		return
	end
	local model = if isModel(data.fighter) then data.fighter else nil
	local payload = if typeof(data.data) == "table" then data.data else {}
	run(`{data.power}.{data.fx}`, handler, ClientPowers.kit(model, data.power, payload))
end

-- Generic wind-up look when a power module doesn't draw its own
local function defaultCast(kit)
	local root = kit.root
	if not root then
		return
	end
	local startup = kit.data.startup or 0
	Poser.play(kit.model, "Cast", math.min(0.12, startup), math.max(0.1, startup), 0.2)
	Vfx.glow(root, kit.colors.primary, 10, 2, math.max(0.3, startup))
	if startup >= 0.35 then
		Vfx.telegraph(root, kit.colors.primary, startup)
	end
end

function PowerFxController:_onCast(data)
	if not isModel(data.fighter) or typeof(data.power) ~= "string" or typeof(data.ability) ~= "string" then
		return
	end
	local model = data.fighter
	local key = data.ability
	if model == game:GetService("Players").LocalPlayer.Character and os.clock() - (predicted[key] or -math.huge) < 0.5 then
		return
	end
	local module = ClientPowers.module(data.power)
	local kit = ClientPowers.kit(model, data.power, data)
	if module and module.onCast then
		run(`{data.power}.onCast`, module.onCast, kit)
	elseif not data.basic then
		defaultCast(kit)
	end
end

-- The local player's own cast, shown the moment they press (AbilityController)
function PowerFxController:predict(model: Model, powerId: string, abilityId: string)
	predicted[abilityId] = os.clock()
	local module = ClientPowers.module(powerId)
	local def = Powers.abilityFor(powerId, abilityId, model:GetAttribute(Attribute.Degree) or 1)
	local kit = ClientPowers.kit(model, powerId, {
		ability = abilityId,
		startup = if def then def.startup or 0 else 0,
		active = if def then def.active or 0 else 0,
		predicted = true,
	})
	local custom = module and module.predict and module.predict[abilityId]
	if custom then
		run(`{powerId}.predict.{abilityId}`, custom, kit)
	elseif module and module.onCast then
		run(`{powerId}.onCast`, module.onCast, kit)
	else
		defaultCast(kit)
	end
end

-- Projectiles ----------------------------------------------------------------------------

-- A glowing orb with a trail, for projectiles without a drawing of their own
local function defaultProjectile(kit)
	local color = kit.colors.primary
	local radius = kit.data.radius or 1
	local orb = Vfx.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * math.clamp(radius * 1.4, 0.6, 8),
		Color = color,
		Transparency = 0.05,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	light.Parent = orb
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, radius * 0.5, 0)
	top.Parent = orb
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -radius * 0.5, 0)
	bottom.Parent = orb
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(color, kit.colors.secondary)
	trail.LightEmission = 1
	trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = orb
	return {
		update = function(position: Vector3, velocity: Vector3)
			orb.CFrame = if velocity.Magnitude > 0.1 then CFrame.lookAt(position, position + velocity) else CFrame.new(position)
		end,
		finish = function(position: Vector3, reason: string)
			if reason ~= "Destroyed" then
				Vfx.sparks(position, color, 16, 24)
				Vfx.shockwave(position, color, radius, radius * 4, 0.25)
			end
			orb:Destroy()
		end,
	}
end

function PowerFxController:_onProjectileSpawn(data)
	if typeof(data.id) ~= "string" or typeof(data.origin) ~= "Vector3" or typeof(data.velocity) ~= "Vector3" then
		return
	end
	local powerId = if typeof(data.power) == "string" then data.power else ""
	local model = if isModel(data.owner) then data.owner else nil
	local payload = if typeof(data.data) == "table" then table.clone(data.data) else {}
	payload.radius = data.radius
	payload.ability = data.ability
	payload.visual = data.visual
	local kit = ClientPowers.kit(model, powerId, payload)
	local module = ClientPowers.module(powerId)
	local builder = module and module.projectiles and module.projectiles[data.visual]
	local handle = nil
	if builder then
		local ok, result = pcall(builder, kit)
		if ok and typeof(result) == "table" then
			handle = result
		elseif not ok then
			warn(`[PowerFx] {powerId} projectile {data.visual} failed: {result}`)
		end
	end
	handle = handle or defaultProjectile(kit)
	flying[data.id] = {
		origin = data.origin,
		velocity = data.velocity,
		gravity = if typeof(data.gravity) == "number" then data.gravity else 0,
		t0 = if typeof(data.t0) == "number" then data.t0 else now(),
		endsAt = now() + (if typeof(data.lifetime) == "number" then data.lifetime else 4) + 0.5,
		handle = handle,
	}
	-- Show it right where it starts this frame
	run("projectile update", handle.update, data.origin, data.velocity, 0)
end

function PowerFxController:_onProjectileUpdate(data)
	local projectile = flying[data.id]
	if not projectile or typeof(data.origin) ~= "Vector3" or typeof(data.velocity) ~= "Vector3" then
		return
	end
	projectile.origin = data.origin
	projectile.velocity = data.velocity
	projectile.gravity = if typeof(data.gravity) == "number" then data.gravity else projectile.gravity
	projectile.t0 = if typeof(data.t0) == "number" then data.t0 else now()
	projectile.endsAt = now() + (if typeof(data.lifetime) == "number" then data.lifetime else 3) + 0.5
	if data.redirected then
		Vfx.text3d(data.origin + Vector3.new(0, 2, 0), "REDIRECTED", Color3.fromRGB(120, 255, 170), 1, 0.9)
		Vfx.sparks(data.origin, Color3.fromRGB(120, 255, 170), 20, 26)
	end
end

function PowerFxController:_onProjectileEnd(data)
	local projectile = flying[data.id]
	if not projectile then
		return
	end
	flying[data.id] = nil
	local position = if typeof(data.position) == "Vector3" then data.position else projectile.origin
	run("projectile finish", projectile.handle.finish, position, if typeof(data.reason) == "string" then data.reason else "Expired")
end

function PowerFxController:_stepProjectiles(dt: number)
	local time = now()
	for id, projectile in flying do
		if time > projectile.endsAt then
			flying[id] = nil
			run("projectile finish", projectile.handle.finish, projectile.origin, "Expired")
			continue
		end
		local t = math.max(0, time - projectile.t0)
		local gravity = Vector3.new(0, -projectile.gravity, 0)
		local position = projectile.origin + projectile.velocity * t + gravity * (0.5 * t * t)
		local velocity = projectile.velocity + gravity * t
		local ok = run("projectile update", projectile.handle.update, position, velocity, dt)
		if not ok then
			flying[id] = nil
		end
	end
end

-- Persistent looks ------------------------------------------------------------------------

function PowerFxController:_watchAppearance(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local cleanup: (() -> ())? = nil
	local shownFor = ""
	local function clear()
		if cleanup then
			run("appearance cleanup", cleanup)
			cleanup = nil
		end
	end
	local function refresh()
		local powerId = model:GetAttribute(Attribute.Power)
		local degree = model:GetAttribute(Attribute.Degree)
		local form = model:GetAttribute(Attribute.Form)
		local signature = `{powerId}/{degree}/{form}`
		if signature == shownFor or not model.Parent then
			return
		end
		shownFor = signature
		clear()
		if typeof(powerId) ~= "string" then
			return
		end
		local module = ClientPowers.module(powerId)
		if module and module.appearance then
			local ok, result = pcall(module.appearance, ClientPowers.kit(model, powerId, {}))
			if ok and typeof(result) == "function" then
				cleanup = result
			elseif not ok then
				warn(`[PowerFx] {powerId} appearance failed: {result}`)
			end
		end
	end
	local connections = {}
	for _, name in { Attribute.Power, Attribute.Degree, Attribute.Form } do
		table.insert(connections, model:GetAttributeChangedSignal(name):Connect(function()
			task.defer(refresh)
		end))
	end
	table.insert(connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			for _, connection in connections do
				connection:Disconnect()
			end
			clear()
		end
	end))
	refresh()
end

return PowerFxController
