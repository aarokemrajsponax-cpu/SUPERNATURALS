-- Draws the cosmetics other people can see: the aura (a soft ring of slow motes around the feet)
-- from the Player attribute SNCosmeticAura, the knockout effect (a short burst at the opponent
-- when its owner scores a knockout) from SNKnockout, and the gold lounge name of VIP players
-- (SNVip). Looks only; nothing here touches combat. Cheap on purpose: one emitter per aura,
-- a small pool of burst emitters, no per-frame work except a half-second lounge check, and
-- everything is off or much smaller when Settings.reducedEffects is on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Settings = require(script.Parent.Parent.Settings)
local Nameplates = require(script.Parent.NameplateController)

local Attribute = Protocol.Attribute
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchEvent = Remotes:WaitForChild("MatchEvent") :: RemoteEvent

local CosmeticFxController = {}

-- Most auras drawn at once (the local player's first), and bursts alive at once
local MAX_AURAS = 10
local BURST_POOL = 4
local BURST_SECONDS = 1.6
-- Particles per colour in a burst; a reduced-effects burst is a few motes only
local BURST_COUNT = 12
local BURST_COUNT_REDUCED = 4
-- The lounge floor (Config of src/server/World/Lounge: centre 0, 700; 100 x 76 studs)
local LOUNGE_MIN = Vector3.new(-54, -20, 658)
local LOUNGE_MAX = Vector3.new(54, 60, 742)
local GOLD = Color3.fromRGB(226, 184, 84)

type Aura = { part: Part, emitter: ParticleEmitter, id: string, connections: { RBXScriptConnection } }

local auras: { [Player]: Aura } = {}
local watchers: { [Player]: { RBXScriptConnection } } = {}
local bursts: { { part: Part, emitters: { ParticleEmitter }, busy: boolean } } = {}
local vipNames: { [Player]: Color3 } = {}
local folder: Folder? = nil

local function reduced(): boolean
	return Settings.get("reducedEffects") == true
end

local function container(): Instance
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "SNCosmeticFx"
	made.Parent = workspace
	folder = made
	return made
end

local function color3(rgb: any): Color3
	if typeof(rgb) == "table" and #rgb >= 3 then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return GOLD
end

-- A ColorSequence through the item's one or two colours
local function sequenceOf(item): ColorSequence
	local colors = item.colors
	local first = color3(colors and colors[1])
	local second = color3(colors and (colors[2] or colors[1]))
	return ColorSequence.new(first, second)
end

local function itemOf(id: any, kind: string): { [string]: any }?
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	local item = Cosmetics.get(id)
	if item and item.kind == kind then
		return item
	end
	return nil
end

-- Auras -------------------------------------------------------------------------------------

local function removeAura(player: Player)
	local aura = auras[player]
	if not aura then
		return
	end
	auras[player] = nil
	for _, connection in aura.connections do
		connection:Disconnect()
	end
	aura.part:Destroy()
end

local function countAuras(): number
	local count = 0
	for _ in auras do
		count += 1
	end
	return count
end

local function buildAura(player: Player, item, root: BasePart): Aura
	local part = Instance.new("Part")
	part.Name = "SNAura"
	part.Size = Vector3.new(0.2, 3.4, 3.4)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = root.CFrame * CFrame.new(0, -2.7, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Motes"
	emitter.Shape = Enum.ParticleEmitterShape.Cylinder
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.Rate = 7
	emitter.Lifetime = NumberRange.new(1.8, 2.6)
	emitter.Speed = NumberRange.new(0.3, 0.8)
	emitter.Acceleration = Vector3.new(0, 0.9, 0)
	emitter.Drag = 1.5
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.7, 0.6), NumberSequenceKeypoint.new(1, 1) })
	emitter.LightEmission = 0.4
	emitter.LightInfluence = 0.3
	emitter.Color = sequenceOf(item)
	emitter.Parent = part
	part.Parent = container()
	return { part = part, emitter = emitter, id = item.id, connections = {} }
end

-- Brings a player's aura in line with their attribute, character and the reduced-effects setting
local function refreshAura(player: Player)
	local item = itemOf(player:GetAttribute(Attribute.CosmeticAura), "aura")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local current = auras[player]
	if reduced() or not item or not root or not root:IsA("BasePart") then
		removeAura(player)
		return
	end
	if current and current.id == item.id and current.part.Parent then
		return
	end
	removeAura(player)
	if countAuras() >= MAX_AURAS and player ~= Players.LocalPlayer then
		return
	end
	local aura = buildAura(player, item, root)
	auras[player] = aura
	-- The aura goes with the character
	table.insert(aura.connections, character.AncestryChanged:Connect(function()
		if not character.Parent then
			removeAura(player)
		end
	end))
end

-- Knockout bursts --------------------------------------------------------------------------

local function newBurst()
	local part = Instance.new("Part")
	part.Name = "SNKnockoutFx"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = container()
	local emitters = {}
	for index = 1, 2 do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Burst" .. index
		emitter.Enabled = false
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(7, 13)
		emitter.Drag = 4
		emitter.Acceleration = Vector3.new(0, -3, 0)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.LightEmission = 0.5
		emitter.Parent = part
		table.insert(emitters, emitter)
	end
	return { part = part, emitters = emitters, busy = false }
end

local function takeBurst()
	for _, burst in bursts do
		if not burst.busy and burst.part.Parent then
			return burst
		end
	end
	if #bursts < BURST_POOL then
		local burst = newBurst()
		table.insert(bursts, burst)
		return burst
	end
	return nil
end

-- Plays `item`'s knockout effect at a world position
function CosmeticFxController.playKnockout(item, position: Vector3): boolean
	local burst = takeBurst()
	if not burst then
		return false
	end
	burst.busy = true
	burst.part.Position = position
	local count = if reduced() then BURST_COUNT_REDUCED else BURST_COUNT
	local colors = item.colors
	for index, emitter in burst.emitters do
		local rgb = if colors then (colors[index] or colors[1]) else nil
		local color = color3(rgb)
		emitter.Color = ColorSequence.new(color)
		-- A reduced burst keeps the first colour only
		if index == 1 or not reduced() then
			emitter:Emit(count)
		end
	end
	task.delay(BURST_SECONDS, function()
		burst.busy = false
	end)
	return true
end

-- The character of a fighter named in a Knockout event (display name), players first
local function characterNamed(name: string): Model?
	for _, player in Players:GetPlayers() do
		if (player.DisplayName == name or player.Name == name) and player.Character then
			return player.Character
		end
	end
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute(Attribute.DisplayName) == name then
			return descendant
		end
	end
	return nil
end

local function playerNamed(name: string): Player?
	for _, player in Players:GetPlayers() do
		if player.DisplayName == name or player.Name == name then
			return player
		end
	end
	return nil
end

local function onKnockout(data: any)
	if typeof(data) ~= "table" or typeof(data.victim) ~= "string" or typeof(data.credited) ~= "string" then
		return
	end
	local scorer = playerNamed(data.credited)
	local item = scorer and itemOf(scorer:GetAttribute(Attribute.Knockout), "knockout")
	if not item then
		return
	end
	local character = characterNamed(data.victim)
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if root and root:IsA("BasePart") then
		CosmeticFxController.playKnockout(item, root.Position + Vector3.new(0, 1.2, 0))
	end
end

-- Gold lounge names ------------------------------------------------------------------------

local function inLounge(position: Vector3): boolean
	return position.X >= LOUNGE_MIN.X and position.X <= LOUNGE_MAX.X
		and position.Y >= LOUNGE_MIN.Y and position.Y <= LOUNGE_MAX.Y
		and position.Z >= LOUNGE_MIN.Z and position.Z <= LOUNGE_MAX.Z
end

-- A VIP's name on their own nameplate turns gold while they are in the lounge (one name, never
-- a second label over the first)
local function setVipName(player: Player, show: boolean)
	local plate = Nameplates.plateOf(player)
	local label = plate and plate:FindFirstChild("Name", true)
	if not label or not label:IsA("TextLabel") then
		return
	end
	if show then
		if not vipNames[player] then
			vipNames[player] = label.TextColor3
		end
		label.TextColor3 = GOLD
	elseif vipNames[player] then
		label.TextColor3 = vipNames[player]
		vipNames[player] = nil
	end
end

local function updateVipNames()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local show = player:GetAttribute(Attribute.Vip) == true and root ~= nil and root:IsA("BasePart") and inLounge(root.Position)
		setVipName(player, show)
	end
end

-- Wiring ---------------------------------------------------------------------------------------

local function watch(player: Player)
	if watchers[player] then
		return
	end
	local connections = {}
	watchers[player] = connections
	table.insert(connections, player:GetAttributeChangedSignal(Attribute.CosmeticAura):Connect(function()
		refreshAura(player)
	end))
	table.insert(connections, player.CharacterAdded:Connect(function()
		task.defer(refreshAura, player)
	end))
	refreshAura(player)
end

local function unwatch(player: Player)
	removeAura(player)
	setVipName(player, false)
	local connections = watchers[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		watchers[player] = nil
	end
end

function CosmeticFxController:Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)
	Settings.changed:Connect(function(key)
		if key == "reducedEffects" then
			for _, player in Players:GetPlayers() do
				refreshAura(player)
			end
		end
	end)
	MatchEvent.OnClientEvent:Connect(function(kind, data)
		if kind == Protocol.MatchEvent.Knockout then
			onKnockout(data)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateVipNames()
		end
	end)
end

-- For tests: how many auras are drawn and bursts exist
function CosmeticFxController.debugCounts(): (number, number)
	return countAuras(), #bursts
end

return CosmeticFxController
