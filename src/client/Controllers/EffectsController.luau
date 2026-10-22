-- Shows what the server says happened in combat: swings, hits, blocks, parries,
-- guard breaks and dodges, plus block shields and the health bars over other
-- fighters. Effects are cosmetic; the server already decided every outcome.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Poser = require(script.Parent.Parent.Effects.Poser)
local Vfx = require(script.Parent.Parent.Effects.Vfx)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Event = Protocol.CombatEvent
local Colors = Theme.Colors

local player = Players.LocalPlayer

local EffectsController = {}

local SLASH_TILT = { 0, 0, 25, 80 }
local SLASH_COLOR = Color3.fromRGB(220, 245, 255)
local HEAVY_COLOR = Color3.fromRGB(255, 140, 60)

-- When this client already showed its own attack, the server's echo is skipped
local predictedAt: { [string]: number } = {}

local shields: { [Model]: BasePart } = {}
local overheads: { [Model]: { gui: BillboardGui, setHealth: (number, Color3?) -> (), setGuard: (number, Color3?) -> (), status: TextLabel } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isLocal(model: Model?): boolean
	return model ~= nil and model == player.Character
end

-- Guard right now, worked out the same way as the server does
local function currentGuard(model: Model): number
	local guard = model:GetAttribute(Attribute.Guard) or Combat.Block.MaxGuard
	local updatedAt = model:GetAttribute(Attribute.GuardUpdatedAt) or 0
	local regen = now() - updatedAt - Combat.Block.GuardRegenDelay
	if updatedAt > 0 and regen > 0 then
		guard = math.min(Combat.Block.MaxGuard, guard + regen * Combat.Block.GuardRegenRate)
	end
	return guard
end
EffectsController.currentGuard = currentGuard

function EffectsController:Init(controllers)
	self.camera = controllers.CameraController
end

function EffectsController:Start()
	CombatEvent.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == Event.Attack then
			self:_onAttack(data)
		elseif kind == Event.Hit then
			self:_onHit(data)
		elseif kind == Event.Dodge then
			local fighter = data.fighter
			if typeof(fighter) == "Instance" and fighter:IsA("Model") and not isLocal(fighter) then
				self:_dodgeVisuals(fighter)
			end
		end
	end)

	for _, model in CollectionService:GetTagged(Protocol.Tag.Fighter) do
		self:_watchFighter(model)
	end
	CollectionService:GetInstanceAddedSignal(Protocol.Tag.Fighter):Connect(function(model)
		self:_watchFighter(model)
	end)

	RunService.RenderStepped:Connect(function()
		for model, shield in shields do
			local root = rootOf(model)
			if root and model.Parent then
				shield.CFrame = root.CFrame * CFrame.new(0, 0.4, -1.7)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.1)
			self:_updateOverheads()
		end
	end)
end

-- Attacks -----------------------------------------------------------------------

local function attackVisuals(model: Model, kind: string, step: number, startup: number, active: number, delay: number)
	local function run()
		local root = rootOf(model)
		if not root or not model.Parent then
			return
		end
		if kind == "Light" then
			Poser.play(model, "Light" .. step, startup, active + 0.05, 0.18)
			Vfx.sound("LightSwing", root)
			task.delay(startup, function()
				if root.Parent then
					Vfx.slash(root.CFrame, SLASH_COLOR, 4.2, SLASH_TILT[step] or 0, 0.12)
				end
			end)
		else
			Poser.play(model, "HeavyWindup", startup * 0.85, startup * 0.15, 0.05)
			Vfx.telegraph(root, Colors.Danger, startup)
			task.delay(startup, function()
				if root.Parent then
					Poser.play(model, "HeavyStrike", 0.06, active + 0.15, 0.3)
					Vfx.slash(root.CFrame, HEAVY_COLOR, 6, 0, 0.2)
					Vfx.sound("HeavySwing", root)
				end
			end)
		end
	end
	if delay > 0 then
		task.delay(delay, run)
	else
		run()
	end
end

-- Called by CombatController the moment the player presses attack, so their
-- own character reacts with no network delay
function EffectsController:predictAttack(model: Model, kind: string, step: number, def, delay: number)
	predictedAt[kind] = os.clock() + delay
	attackVisuals(model, kind, step, def.Startup, def.Active, delay)
end

function EffectsController:_onAttack(data)
	local model = data.attacker
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	if isLocal(model) and os.clock() - (predictedAt[data.kind] or -math.huge) < 0.6 then
		return
	end
	attackVisuals(model, data.kind, data.step, data.startup, data.active, 0)
end

-- Hits ----------------------------------------------------------------------------

function EffectsController:_onHit(data)
	local victim, attacker = data.victim, data.attacker
	if typeof(victim) ~= "Instance" or not victim:IsA("Model") or typeof(data.position) ~= "Vector3" then
		return
	end
	if typeof(attacker) ~= "Instance" or not attacker:IsA("Model") then
		attacker = nil
	end
	local position = data.position
	local involved = isLocal(victim) or isLocal(attacker)
	local result = data.result

	if result == "Hit" then
		local big = data.heavy or data.finisher
		Vfx.flash(victim, Color3.new(1, 1, 1))
		Vfx.sparks(position, if data.heavy then HEAVY_COLOR else Color3.fromRGB(255, 230, 150), if big then 28 else 14, if big then 32 else 22)
		Vfx.popup(position, tostring(math.floor(data.damage + 0.5)), if big then Colors.Gold else Colors.Text, if big then 1.3 else 1)
		Poser.play(victim, if big then "Stagger" else "Hurt", 0.05, 0.12, 0.25)
		Vfx.sound(if data.heavy then "HeavyHit" else "Hit", position)
		if big then
			Vfx.shockwave(position, HEAVY_COLOR, 2, 10, 0.3)
			Vfx.groundRing(position - Vector3.new(0, 2.8, 0), HEAVY_COLOR, 2, 14, 0.4)
		end
		if involved then
			self.camera:shake(if data.heavy then 2.2 else if big then 1.4 else 0.7, if data.heavy then 0.35 else 0.15)
			if data.heavy then
				self.camera:punch(6)
			end
		end
	elseif result == "Blocked" then
		Vfx.sparks(position, Colors.Guard, 10, 18)
		Vfx.popup(position, "BLOCK", Colors.Guard, 0.8)
		Vfx.sound("Block", position)
		local shield = shields[victim]
		if shield then
			Vfx.shockwave(shield.Position, Colors.Guard, 3, 6, 0.15)
		end
		if involved then
			self.camera:shake(0.4, 0.1)
		end
	elseif result == "GuardBreak" then
		Vfx.sparks(position, Colors.Guard, 30, 34)
		Vfx.shockwave(position, Colors.Guard, 3, 12, 0.35)
		Vfx.popup(position, "GUARD BREAK", Colors.Danger, 1.3)
		Poser.play(victim, "Stagger", 0.05, Combat.Block.GuardBreakStun * 0.7, 0.3)
		Vfx.sound("GuardBreak", position)
		if involved then
			self.camera:shake(1.8, 0.3)
		end
	elseif result == "Parried" then
		Vfx.shockwave(position, Colors.Gold, 2, 8, 0.25)
		Vfx.sparks(position, Colors.Gold, 24, 28)
		Vfx.popup(position, "PARRY!", Colors.Gold, 1.4)
		if attacker then
			Vfx.flash(attacker, Colors.Gold, 0.3)
			Poser.play(attacker, "Stagger", 0.05, Combat.Block.ParryStun * 0.7, 0.3)
		end
		Vfx.sound("Parry", position)
		if involved then
			self.camera:shake(1.2, 0.2)
			self.camera:punch(4)
		end
	elseif result == "Invulnerable" then
		Vfx.popup(position, "DODGE", Colors.TextDim, 0.8)
	elseif result == "Perfect" or result == "PerfectBlock" then
		-- A perfectly timed defense: the whole attack is negated
		Vfx.shockwave(position, Colors.Gold, 2, 12, 0.35)
		Vfx.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), 3, Colors.Gold, 0.25, 0.4, 9)
		Vfx.sparks(position, Colors.Gold, 30, 30)
		Vfx.popup(position, "PERFECT!", Colors.Gold, 1.5)
		Vfx.sound("Parry", position)
		if involved then
			self.camera:shake(1.2, 0.2)
			self.camera:punch(5)
		end
	elseif result == "Good" then
		Vfx.sparks(position, Colors.Cyan, 14, 22)
		Vfx.popup(position, "GOOD", Colors.Cyan, 1.1)
	elseif result == "Endured" then
		Vfx.sparks(position, Color3.fromRGB(200, 200, 210), 18, 20)
		Vfx.popup(position, "ENDURED", Color3.fromRGB(220, 220, 230), 1)
	elseif result == "Countered" then
		Vfx.shockwave(position, Colors.Purple, 2, 10, 0.3)
		Vfx.popup(position, "COUNTER!", Colors.Purple, 1.4)
		Vfx.sound("Parry", position)
	end
	if data.armored and result == "Hit" then
		Vfx.popup(position + Vector3.new(0, 1.5, 0), "ARMOR", Color3.fromRGB(200, 200, 210), 0.8)
	end
end

-- Dodges --------------------------------------------------------------------------

function EffectsController:_dodgeVisuals(model: Model)
	Vfx.afterimage(model, Colors.Cyan)
	Poser.play(model, "Dodge", 0.05, 0.12, 0.15)
	local root = rootOf(model)
	if root then
		Vfx.sound("Dodge", root)
		task.delay(0.09, function()
			if model.Parent then
				Vfx.afterimage(model, Colors.Purple)
			end
		end)
	end
end

function EffectsController:predictDodge(model: Model)
	self:_dodgeVisuals(model)
end

-- Blocking shields and overhead bars ---------------------------------------------

function EffectsController:_setShield(model: Model, on: boolean)
	local existing = shields[model]
	if on and not existing then
		local shield = Instance.new("Part")
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.one * 5.5
		shield.Anchored = true
		shield.CanCollide = false
		shield.CanQuery = false
		shield.CanTouch = false
		shield.CastShadow = false
		shield.Material = Enum.Material.ForceField
		shield.Color = Colors.Guard
		shield.Transparency = 0.2
		shield.Parent = workspace.CurrentCamera
		shields[model] = shield
		-- The local player's own block pose follows their button (CombatController)
		if not isLocal(model) then
			Poser.hold(model, "Block")
		end
	elseif not on and existing then
		existing:Destroy()
		shields[model] = nil
		if not isLocal(model) then
			Poser.release(model, "Block")
		end
	end
end

function EffectsController:_watchFighter(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local connections = {}
	local function refreshShield()
		self:_setShield(model, model:GetAttribute(Attribute.Blocking) == true and model.Parent ~= nil)
	end
	table.insert(connections, model:GetAttributeChangedSignal(Attribute.Blocking):Connect(refreshShield))
	refreshShield()

	if not isLocal(model) then
		self:_createOverhead(model)
	end

	table.insert(connections, model.AncestryChanged:Connect(function()
		if model:IsDescendantOf(workspace) then
			return
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		self:_setShield(model, false)
		local overhead = overheads[model]
		if overhead then
			overhead.gui:Destroy()
			overheads[model] = nil
		end
	end))
end

function EffectsController:_createOverhead(model: Model)
	if overheads[model] then
		return
	end
	local head = model:FindFirstChild("Head") or rootOf(model)
	if not head then
		return
	end
	local gui = Components.make("BillboardGui", {
		Name = "SNOverhead",
		Size = UDim2.fromOffset(150, 46),
		StudsOffset = Vector3.new(0, 2.6, 0),
		MaxDistance = 110,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Adornee = head,
	})
	local displayName = model:GetAttribute(Attribute.DisplayName)
	Components.label(if typeof(displayName) == "string" then displayName else model.Name, {
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.Fonts.Heading,
		TextColor3 = Colors.Text,
		TextStrokeTransparency = 0.4,
		MaxTextSize = 15,
		Parent = gui,
	})
	local healthBar, setHealth = Components.bar({
		Size = UDim2.new(1, 0, 0, 9),
		Position = UDim2.fromOffset(0, 18),
		Parent = gui,
	}, Colors.Health)
	local guardBar, setGuard = Components.bar({
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.fromOffset(0, 29),
		Parent = gui,
	}, Colors.Guard)
	local status = Components.label("", {
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, 34),
		Font = Theme.Fonts.Heading,
		TextColor3 = Colors.Gold,
		TextStrokeTransparency = 0.5,
		MaxTextSize = 11,
		Parent = gui,
	})
	gui.Parent = workspace.CurrentCamera
	overheads[model] = { gui = gui, setHealth = setHealth, setGuard = setGuard, status = status }
	local _ = healthBar
	local _ = guardBar
end

function EffectsController:_updateOverheads()
	local time = now()
	for model, overhead in overheads do
		-- The owner's invisibility hides their name and bars too
		local owner = Players:GetPlayerFromCharacter(model)
		overhead.gui.Enabled = not (owner and owner:GetAttribute(Attribute.Invisible) == true)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0
			overhead.setHealth(fraction, if fraction < 0.3 then Colors.HealthLow else Colors.Health)
		end
		local maxGuard = model:GetAttribute(Attribute.MaxGuard) or Combat.Block.MaxGuard
		overhead.setGuard(currentGuard(model) / math.max(1, maxGuard))
		-- Concealed fighters (the Ghost's veil) don't give themselves away with a name tag
		local concealed = time < (model:GetAttribute(Attribute.StatusPrefix .. "Concealed") or 0)
		if concealed then
			overhead.gui.Enabled = false
		end
		local text = ""
		local function active(statusId: string): boolean
			return time < (model:GetAttribute(Attribute.StatusPrefix .. statusId) or 0)
		end
		if active("Grabbed") then
			text = "GRABBED"
		elseif active("Freeze") then
			text = "FROZEN"
		elseif active("Trapped") then
			text = "TRAPPED"
		elseif time < (model:GetAttribute(Attribute.StunnedUntil) or 0) then
			text = "STUNNED"
		elseif active("Sealed") then
			text = "SEALED"
		elseif active("Root") then
			text = "ROOTED"
		elseif model:GetAttribute(Attribute.Blocking) then
			text = "GUARDING"
		elseif time < (model:GetAttribute(Attribute.ProtectedUntil) or 0) then
			text = "PROTECTED"
		elseif active("Mark") then
			text = "MARKED"
		elseif active("Slow") then
			text = "SLOWED"
		end
		overhead.status.Text = text
	end
end

return EffectsController
