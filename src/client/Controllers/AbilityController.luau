-- Turns ability presses into requests: keys 1-5 for the equipped abilities
-- and R for the ultimate (gamepad: R1, R2, L2, D-pad up/left, D-pad down for
-- the ultimate; touch: the ability buttons on the HUD). It works out where the
-- player is aiming, checks the obvious things locally (cooldown, cost, charge)
-- so a press that can't work shows why straight away, and shows the player's
-- own wind-up instantly. The server still decides everything.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityRequest = Remotes:WaitForChild("AbilityRequest") :: RemoteEvent
local AbilityEvent = Remotes:WaitForChild("AbilityEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local player = Players.LocalPlayer

local AbilityController = {}

AbilityController.Bindings = {
	{ slot = 1, name = "SNAbility1", inputs = { Enum.KeyCode.One, Enum.KeyCode.ButtonR1 }, keyText = "1", padText = "R1" },
	{ slot = 2, name = "SNAbility2", inputs = { Enum.KeyCode.Two, Enum.KeyCode.ButtonR2 }, keyText = "2", padText = "R2" },
	{ slot = 3, name = "SNAbility3", inputs = { Enum.KeyCode.Three, Enum.KeyCode.ButtonL2 }, keyText = "3", padText = "L2" },
	{ slot = 4, name = "SNAbility4", inputs = { Enum.KeyCode.Four, Enum.KeyCode.DPadUp }, keyText = "4", padText = "↑" },
	{ slot = 5, name = "SNAbility5", inputs = { Enum.KeyCode.Five, Enum.KeyCode.DPadLeft }, keyText = "5", padText = "←" },
	-- Only powers with a sixth slot (the Grandmaster at Degree IV) use this one
	{ slot = 6, name = "SNAbility6", inputs = { Enum.KeyCode.Six, Enum.KeyCode.DPadRight }, keyText = "6", padText = "→" },
	{ slot = "Ultimate", name = "SNUltimate", inputs = { Enum.KeyCode.R, Enum.KeyCode.DPadDown }, keyText = "R", padText = "↓" },
}

local rejectedEvent = Instance.new("BindableEvent")
-- Fires with (abilityId?, message) when a press can't work
AbilityController.rejected = rejectedEvent.Event

local MESSAGES = {
	cooldown = "Not ready yet",
	charge = "Ultimate isn't charged",
	sealed = "Your abilities are sealed!",
	frozen = "You're frozen",
	unavailable = "Can't use that right now",
	degree = "Your degree can't use that",
}

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function myCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

function AbilityController:Init(controllers)
	self.fx = controllers.PowerFxController
	self.input = controllers.InputController
	self.targeting = controllers.TargetingController
end

function AbilityController:Start()
	for _, binding in AbilityController.Bindings do
		ContextActionService:BindAction(binding.name, function(_, state)
			if state == Enum.UserInputState.Begin then
				self:use(binding.slot)
			end
			return Enum.ContextActionResult.Sink
		end, false, table.unpack(binding.inputs))
	end

	AbilityEvent.OnClientEvent:Connect(function(kind, data)
		if kind == Protocol.AbilityEvent.Rejected and typeof(data) == "table" then
			local reason = data.reason
			local message = MESSAGES[reason]
			if reason == "resource" then
				local character = player.Character
				local def = character and Powers.get(character:GetAttribute(Attribute.Power))
				message = `Not enough {if def and def.resource then def.resource.name else "energy"}`
			elseif typeof(reason) == "string" and not MESSAGES[reason] and string.find(reason, " ") then
				-- A power's own explanation ("Nothing light enough to lift nearby")
				message = reason
			end
			if message then
				rejectedEvent:Fire(data.ability, message)
			end
		end
	end)
end

-- What the local player has equipped: { { slot, abilityId, def } } in slot order,
-- then the ultimate. Read from their character, which the server keeps current.
function AbilityController:slots(): { { slot: any, abilityId: string, def: any } }
	local character = player.Character
	local list = {}
	if not character then
		return list
	end
	local powerId = character:GetAttribute(Attribute.Power)
	local degree = character:GetAttribute(Attribute.Degree)
	local loadout = character:GetAttribute(Attribute.Loadout)
	if typeof(powerId) ~= "string" or typeof(degree) ~= "number" then
		return list
	end
	if typeof(loadout) == "string" and loadout ~= "" then
		for index, abilityId in string.split(loadout, ",") do
			local def = Powers.abilityFor(powerId, abilityId, degree)
			if def then
				table.insert(list, { slot = index, abilityId = abilityId, def = def })
			end
		end
	end
	local ultimate = Powers.ultimateOf(powerId, degree)
	local ultimateDef = ultimate and Powers.abilityFor(powerId, ultimate, degree)
	if ultimate and ultimateDef then
		table.insert(list, { slot = "Ultimate", abilityId = ultimate, def = ultimateDef })
	end
	return list
end

-- Where the player is aiming: the camera's direction, and the point under the
-- mouse (keyboard) or the middle of the screen (gamepad, touch)
function AbilityController:aim(): { direction: Vector3, point: Vector3? }
	local camera = workspace.CurrentCamera
	local character = player.Character
	local ray
	local device = self.input and self.input.device() or "keyboard"
	if device == "keyboard" then
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	else
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end
	aimParams.FilterDescendantsInstances = if character then { character } else {}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 400, aimParams)
	local point = if result then result.Position else ray.Origin + ray.Direction * 400
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local direction = camera.CFrame.LookVector
	if root and root:IsA("BasePart") then
		local toPoint = point - root.Position
		if Vector3.new(toPoint.X, 0, toPoint.Z).Magnitude > 2 then
			direction = toPoint.Unit
		end
	end
	return { direction = direction, point = point }
end

local function attributeTime(character: Model, name: string): number
	local value = character:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- The equipped ability in a slot ("Ultimate" included) once the cheap local checks pass;
-- a press that can't work explains itself here and returns nil
function AbilityController:_ready(slot: any): (any?, Model?, Humanoid?, BasePart?)
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root then
		return nil
	end
	local entry = nil
	for _, candidate in self:slots() do
		if candidate.slot == slot then
			entry = candidate
		end
	end
	if not entry then
		return nil
	end
	local def = entry.def
	local time = serverNow()
	if time < attributeTime(character, Attribute.StunnedUntil) or humanoid.WalkSpeed <= 0 and time < attributeTime(character, Attribute.BusyUntil) then
		return nil
	end
	if time + Combat.Abilities.CooldownLeeway < attributeTime(character, Attribute.CooldownPrefix .. entry.abilityId) then
		rejectedEvent:Fire(entry.abilityId, MESSAGES.cooldown)
		return nil
	end
	if slot == "Ultimate" then
		if (character:GetAttribute(Attribute.Ultimate) or 0) < Combat.Ultimate.Max then
			rejectedEvent:Fire(entry.abilityId, MESSAGES.charge)
			return nil
		end
	elseif (character:GetAttribute(Attribute.Resource) or 0) + 0.5 < (def.cost or 0) then
		local powerDef = Powers.get(character:GetAttribute(Attribute.Power))
		rejectedEvent:Fire(entry.abilityId, `Not enough {if powerDef and powerDef.resource then powerDef.resource.name else "energy"}`)
		return nil
	end
	return entry, character, humanoid, root
end

-- Uses the ability in a slot (1-5) or "Ultimate". Point and teleport abilities enter
-- targeting mode first (or cast at the cursor with quick cast); everything else
-- fires at once toward the aim.
function AbilityController:use(slot: any)
	local entry = self:_ready(slot)
	if not entry then
		return
	end
	local mode = entry.def.targeting
	local targeting = self.targeting
	if targeting and (mode == "point" or mode == "teleport") then
		if targeting.quickCastOn() then
			local aim = targeting:quickAim(entry)
			if aim then
				self:cast(entry, aim)
				return
			end
		else
			targeting:begin(entry, function(aim)
				-- The world may have changed while aiming: check again, then cast
				if self:_ready(slot) then
					self:cast(entry, aim)
				end
			end)
			return
		end
	end
	self:cast(entry, self:aim())
end

-- Touch: a finger landing on a targeted ability's button starts an aim (drag, release
-- to cast; drag back onto the button to cancel). Returns true when it took the press.
function AbilityController:touchBegin(slot: any, input: InputObject, button: GuiObject): boolean
	local targeting = self.targeting
	if not targeting then
		return false
	end
	local found = nil
	for _, candidate in self:slots() do
		if candidate.slot == slot then
			found = candidate
		end
	end
	if not found or not found.def.targeting then
		return false
	end
	local entry = self:_ready(slot)
	if not entry then
		return true
	end
	return targeting:touchBegin(entry, input, button, function(aim)
		if self:_ready(slot) then
			self:cast(entry, aim)
		end
	end)
end

-- Sends the request with the given aim ({ direction, point? }) and shows the wind-up
function AbilityController:cast(entry: any, aim: { direction: Vector3, point: Vector3? })
	local character, humanoid, root = myCharacter()
	if not character or not humanoid or not root then
		return
	end
	local def = entry.def
	-- Turn to face the aim right away (the server uses the aim, not the facing)
	local flat = Vector3.new(aim.direction.X, 0, aim.direction.Z)
	if flat.Magnitude > 0.1 and not def.instant then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		humanoid.AutoRotate = false
		task.delay((def.startup or 0) + (def.active or 0) + 0.1, function()
			if humanoid.Parent and serverNow() >= attributeTime(character, Attribute.BusyUntil) - 0.05 then
				humanoid.AutoRotate = true
			end
		end)
	end
	AbilityRequest:FireServer(entry.abilityId, aim)
	if self.fx then
		self.fx:predict(character, character:GetAttribute(Attribute.Power), entry.abilityId)
	end
end

return AbilityController
