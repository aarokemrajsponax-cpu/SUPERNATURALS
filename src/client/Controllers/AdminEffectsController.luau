-- Draws the owner's admin abuse for everyone: running events, announcements,
-- player auras, the owner's crown and title, and players frozen in ice.
-- Everything here is cosmetic; the server already decided who gets pushed,
-- frozen or grown.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AdminEvents = require(ReplicatedStorage.Shared.Config.AdminEvents)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Common = require(script.Parent.Parent.Effects.AdminEvents.Common)
local Components = require(script.Parent.Parent.UI.Components)
local Theme = require(script.Parent.Parent.UI.Theme)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminEvent = Remotes:WaitForChild("AdminEvent") :: RemoteEvent

local Attribute = Protocol.Attribute
local Signal = Protocol.AdminSignal
local Colors = Theme.Colors
local make = Components.make

local player = Players.LocalPlayer
local renderers = script.Parent.Parent.Effects.AdminEvents

local AdminEffectsController = {}

local GOLD = Color3.fromRGB(255, 210, 90)

function AdminEffectsController:Init(controllers)
	self.camera = controllers.CameraController
end

function AdminEffectsController:Start()
	self.gui = make("ScreenGui", {
		Name = "SNAdminHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local uiScale = make("UIScale", { Parent = self.gui, Scale = 1 })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.2)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	self:_watchEvents()
	self:_watchPlayers()
	self:_watchIce()
end

-- Events -------------------------------------------------------------------------------

function AdminEffectsController:_watchEvents()
	local handlers: { [string]: (any) -> () } = {}
	local stopCurrent: (() -> ())? = nil
	local runningToken: {}? = nil
	local liveChip: Frame? = nil

	local function stop()
		runningToken = nil
		table.clear(handlers)
		if stopCurrent then
			local ok, err = pcall(stopCurrent)
			if not ok then
				warn("[AdminEvents] couldn't stop event visuals: " .. tostring(err))
			end
			stopCurrent = nil
		end
		if liveChip then
			liveChip:Destroy()
			liveChip = nil
		end
	end

	local function start(id: string)
		stop()
		local def = AdminEvents.Events[id]
		local module = renderers:FindFirstChild(id)
		if not def or not module then
			return
		end
		local token = {}
		runningToken = token
		local context = {
			def = def,
			center = ReplicatedStorage:GetAttribute(Attribute.AdminEventCenter) or Vector3.zero,
			startedAt = ReplicatedStorage:GetAttribute(Attribute.AdminEventStartedAt) or workspace:GetServerTimeNow(),
			endsAt = ReplicatedStorage:GetAttribute(Attribute.AdminEventEndsAt) or workspace:GetServerTimeNow() + def.duration,
			running = function(): boolean
				return runningToken == token
			end,
			on = function(kind: string, handler: (any) -> ())
				handlers[kind] = handler
			end,
			shake = function(strength: number, duration: number)
				self.camera:shake(strength, duration)
			end,
		}
		local ok, result = pcall(function()
			return require(module)(context)
		end)
		if ok and typeof(result) == "function" then
			stopCurrent = result
		elseif not ok then
			warn(`[AdminEvents] couldn't start {id} visuals: {result}`)
		end
		self:_titleCard(def)
		liveChip = self:_liveChip(def, context.endsAt)
	end

	-- The server sets AdminEventRun last, after the event's other attributes,
	-- and it changes on every start (even of the same event again)
	local function sync()
		local run = ReplicatedStorage:GetAttribute(Attribute.AdminEventRun)
		local id = ReplicatedStorage:GetAttribute(Attribute.AdminEvent)
		if typeof(run) == "string" and run ~= "" and typeof(id) == "string" and id ~= "" then
			start(id)
		else
			stop()
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal(Attribute.AdminEventRun):Connect(sync)
	sync()

	AdminEvent.OnClientEvent:Connect(function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == Signal.Announce then
			self:_announcement(data)
			return
		end
		local handler = handlers[kind]
		if handler then
			task.spawn(handler, data)
		end
	end)
end

-- A big title card when an event starts
function AdminEffectsController:_titleCard(def)
	local card = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(560, 120),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = self.gui,
	}, {
		Components.corner(UDim.new(0, 18)),
		make("UIGradient", { Color = ColorSequence.new(def.colors[1], def.colors[2]), Rotation = 15 }),
		make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 0.2 }),
	})
	local scale = make("UIScale", { Scale = 0.4, Parent = card })
	Components.label(def.icon, {
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.fromOffset(16, 15),
		MaxTextSize = 70,
		Parent = card,
	})
	Components.label(string.upper(def.name), {
		Size = UDim2.new(1, -130, 0, 52),
		Position = UDim2.fromOffset(115, 16),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		MaxTextSize = 46,
		Parent = card,
	})
	Components.label("ADMIN EVENT · " .. def.description, {
		Size = UDim2.new(1, -130, 0, 34),
		Position = UDim2.fromOffset(115, 70),
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextStrokeTransparency = 0.6,
		MaxTextSize = 16,
		Parent = card,
	})
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(3.2, function()
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.4, function()
			card:Destroy()
		end)
	end)
	Common.confetti(workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.LookVector * 14 + Vector3.new(0, 6, 0), 50, { def.colors[1], def.colors[2], Color3.new(1, 1, 1) })
end

-- A small "LIVE" chip with the time left
function AdminEffectsController:_liveChip(def, endsAt: number): Frame
	local chip = Components.panel({
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(250, 40),
		Parent = self.gui,
	})
	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = def.colors[1]
		stroke.Transparency = 0
	end
	local dot = make("Frame", {
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.new(0, 12, 0.5, -5),
		BackgroundColor3 = Colors.Danger,
		Parent = chip,
	}, { Components.corner(UDim.new(1, 0)) })
	local text = Components.label("", {
		Size = UDim2.new(1, -36, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		Parent = chip,
	})
	task.spawn(function()
		while chip.Parent do
			local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
			text.Text = `LIVE  {def.icon} {def.name}  ·  {left}s`
			dot.BackgroundTransparency = if dot.BackgroundTransparency == 0 then 0.6 else 0
			task.wait(0.5)
		end
	end)
	return chip
end

-- A golden announcement banner from the owner
function AdminEffectsController:_announcement(data)
	if typeof(data.text) ~= "string" or data.text == "" then
		return
	end
	local banner = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -160),
		Size = UDim2.fromOffset(620, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(30, 22, 10),
		Parent = self.gui,
	}, {
		Components.corner(UDim.new(0, 16)),
		make("UIStroke", { Color = GOLD, Thickness = 2.5 }),
		make("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(255, 235, 180), Color3.fromRGB(200, 150, 60)),
			Rotation = 90,
		}),
		Components.padding(14),
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Components.label(`👑  ANNOUNCEMENT  ·  {data.from or "Owner"}`, {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Fonts.Title,
		TextColor3 = GOLD,
		MaxTextSize = 16,
		Parent = banner,
	})
	local message = Components.label(data.text, {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 22,
		TextWrapped = true,
		Font = Theme.Fonts.Heading,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = banner,
	})
	local shimmer = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.5, GOLD),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		}),
		Parent = message,
	})
	local connection = RunService.RenderStepped:Connect(function()
		shimmer.Offset = Vector2.new(math.sin(os.clock() * 1.5) * 0.6, 0)
	end)
	TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 120) }):Play()
	task.delay(7, function()
		local out = TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -200) })
		out.Completed:Once(function()
			connection:Disconnect()
			banner:Destroy()
		end)
		out:Play()
	end)
end

-- Auras, crowns and titles ------------------------------------------------------------

local function weldTo(part: BasePart, anchor: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
end

local function auraEmitters(volume: BasePart, kind: string)
	local colors = AdminEvents.Auras[kind]
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.LightEmission = if kind == "Void" then 0.2 else 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Transparency = NumberSequence.new(0.1, 1)
	sparkle.Lifetime = NumberRange.new(0.9, 1.6)
	sparkle.Speed = NumberRange.new(1.5, 3.5)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.SpreadAngle = Vector2.new(20, 20)
	sparkle.Rate = if Common.reduced() then 10 else 28
	if kind == "Rainbow" then
		local keys = {}
		for index, color in Common.Rainbow do
			table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#Common.Rainbow - 1), color))
		end
		sparkle.Color = ColorSequence.new(keys)
	else
		sparkle.Color = ColorSequence.new(colors[1], colors[2])
	end
	sparkle.Parent = volume

	if kind == "Void" then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(colors[1], colors[2])
		smoke.Size = NumberSequence.new(1.2, 2.6)
		smoke.Transparency = NumberSequence.new(0.55, 1)
		smoke.Lifetime = NumberRange.new(1.2, 2)
		smoke.Speed = NumberRange.new(0.5, 1.5)
		smoke.Rate = 14
		smoke.Parent = volume
	elseif kind == "Frost" then
		sparkle.Acceleration = Vector3.new(0, -4, 0)
	end
	local light = Instance.new("PointLight")
	light.Color = colors[1]
	light.Range = 12
	light.Brightness = if kind == "Void" then 1 else 2
	light.Parent = volume
end

local function buildCrown(head: BasePart): Model
	local crown = Instance.new("Model")
	crown.Name = "SNCrown"
	local scale = head.Size.Y / 1.2
	local base = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.18 * scale, 0)
	local gold = { Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.45 }
	local radius = 0.62 * scale
	local gems = { Color3.fromRGB(255, 50, 70), Color3.fromRGB(70, 140, 255), Color3.fromRGB(80, 230, 120), Color3.fromRGB(190, 80, 255), Color3.fromRGB(255, 50, 70) }
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		local piece = Common.part({
			Size = Vector3.new(0.42 * scale, 0.32 * scale, 0.1 * scale),
			CFrame = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius),
			Color = gold.Color,
			Material = gold.Material,
			Reflectance = gold.Reflectance,
			Parent = crown,
		})
		weldTo(piece, head)
	end
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2
		local spike = Common.part({
			Size = Vector3.new(0.14 * scale, 0.5 * scale, 0.14 * scale),
			CFrame = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.38 * scale, -radius),
			Color = gold.Color,
			Material = gold.Material,
			Reflectance = gold.Reflectance,
			Parent = crown,
		})
		weldTo(spike, head)
		local gem = Common.part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.22 * scale,
			CFrame = spike.CFrame * CFrame.new(0, 0.3 * scale, 0),
			Color = gems[i + 1],
			Parent = crown,
		})
		weldTo(gem, head)
	end
	local jewel = Common.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.3 * scale,
		CFrame = base * CFrame.new(0, 0, -radius - 0.06 * scale),
		Color = Color3.fromRGB(255, 40, 60),
		Parent = crown,
	})
	weldTo(jewel, head)
	local glint = Instance.new("ParticleEmitter")
	glint.Color = ColorSequence.new(Color3.new(1, 1, 1), GOLD)
	glint.LightEmission = 1
	glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	glint.Lifetime = NumberRange.new(0.4, 0.8)
	glint.Speed = NumberRange.new(0.5, 1)
	glint.Rate = 5
	glint.Parent = jewel
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = jewel
	-- Inside the character (locally) so the welds carry it along with the head
	crown.Parent = head.Parent
	return crown
end

local function buildTitle(head: BasePart): BillboardGui
	local gui = make("BillboardGui", {
		Name = "SNOwnerTitle",
		Size = UDim2.fromOffset(170, 30),
		StudsOffset = Vector3.new(0, 4.2, 0),
		MaxDistance = 140,
		LightInfluence = 0,
		Adornee = head,
		Parent = workspace.CurrentCamera,
	})
	local label = Components.label("👑  OWNER", {
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
		MaxTextSize = 22,
		Parent = gui,
	})
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 170, 40)),
		Rotation = 90,
		Parent = label,
	})
	return gui
end

-- Roblox only draws about 30 Highlights at once, and the panel can give
-- everyone an aura; past this many, auras keep their sparkles but no outline
local MAX_OUTLINES = 6

function AdminEffectsController:_watchPlayers()
	type Decor = { cleanup: { Instance }, connections: { RBXScriptConnection }, outlined: boolean }
	local decorations: { [Player]: Decor } = {}
	local refreshers: { [Player]: () -> () } = {}
	local outlines = 0

	local function clear(target: Player)
		local decor = decorations[target]
		if decor then
			for _, item in decor.cleanup do
				item:Destroy()
			end
			for _, connection in decor.connections do
				connection:Disconnect()
			end
			if decor.outlined then
				outlines -= 1
			end
			decorations[target] = nil
		end
	end

	local function render(target: Player)
		clear(target)
		local character = target.Character
		local head = character and character:FindFirstChild("Head")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not head or not root or not head:IsA("BasePart") or not root:IsA("BasePart") then
			return
		end
		local decor: Decor = { cleanup = {}, connections = {}, outlined = false }
		decorations[target] = decor
		local invisible = target:GetAttribute(Attribute.Invisible) == true

		-- Giant and tiny resize the body; build everything again at the new size
		local refresh = refreshers[target]
		if refresh then
			table.insert(decor.connections, head:GetPropertyChangedSignal("Size"):Connect(refresh))
			table.insert(decor.connections, root:GetPropertyChangedSignal("Size"):Connect(refresh))
		end

		local aura = target:GetAttribute(Attribute.Aura)
		if typeof(aura) == "string" and AdminEvents.Auras[aura] and not invisible then
			local bodyScale = root.Size.Y / 2
			local volume = Common.part({ Size = Vector3.new(4, 5.5, 4) * bodyScale, CFrame = root.CFrame, Transparency = 1, Parent = character })
			weldTo(volume, root)
			auraEmitters(volume, aura)
			table.insert(decor.cleanup, volume)
			if outlines < MAX_OUTLINES then
				outlines += 1
				decor.outlined = true
				local outline = make("Highlight", {
					Adornee = character,
					FillTransparency = 1,
					OutlineTransparency = 0.25,
					OutlineColor = AdminEvents.Auras[aura][1],
					DepthMode = Enum.HighlightDepthMode.Occluded,
					Parent = workspace.CurrentCamera,
				})
				table.insert(decor.cleanup, outline)
				if aura == "Rainbow" then
					table.insert(decor.connections, RunService.RenderStepped:Connect(function()
						outline.OutlineColor = Common.hue(0)
					end))
				end
			end
		end

		if target:GetAttribute(Attribute.IsOwner) and target:GetAttribute(Attribute.Crown) and not invisible then
			table.insert(decor.cleanup, buildCrown(head))
			table.insert(decor.cleanup, buildTitle(head))
		end
	end

	local function watch(target: Player)
		-- Many changes can arrive together (a resize changes every part); draw once
		local pending = false
		local function refresh()
			if pending then
				return
			end
			pending = true
			task.defer(function()
				pending = false
				if target.Parent then
					render(target)
				end
			end)
		end
		refreshers[target] = refresh
		target.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 5)
			character:WaitForChild("HumanoidRootPart", 5)
			refresh()
		end)
		for _, name in { Attribute.Aura, Attribute.Crown, Attribute.IsOwner, Attribute.Invisible } do
			target:GetAttributeChangedSignal(name):Connect(refresh)
		end
		if target.Character then
			refresh()
		end
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(target)
		clear(target)
		refreshers[target] = nil
	end)
	for _, target in Players:GetPlayers() do
		watch(target)
	end
end

-- Ice blocks ---------------------------------------------------------------------------

local ICE = Color3.fromRGB(175, 228, 255)

local function iceBlock(model: Model): { BasePart }
	local size = model:GetExtentsSize() + Vector3.new(1.2, 0.8, 1.2)
	local pivot = model:GetPivot()
	local parts = {}
	local block = Common.part({ Size = size, CFrame = pivot, Color = ICE, Material = Enum.Material.Glass, Transparency = 0.45, Reflectance = 0.3 })
	table.insert(parts, block)
	table.insert(parts, Common.part({ Size = size * 1.04, CFrame = pivot, Color = Color3.fromRGB(220, 245, 255), Material = Enum.Material.ForceField }))
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local crystal = Common.part({
			Size = Vector3.new(0.45, 1.6 + math.random(), 0.45),
			CFrame = pivot
				* CFrame.new(math.cos(angle) * size.X * 0.3, size.Y / 2 + 0.4, math.sin(angle) * size.Z * 0.3)
				* CFrame.Angles(math.rad(math.random(-25, 25)), angle, math.rad(math.random(-25, 25))),
			Color = Color3.fromRGB(210, 245, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.25,
		})
		table.insert(parts, crystal)
	end
	local glitter = Instance.new("ParticleEmitter")
	glitter.Color = ColorSequence.new(Color3.new(1, 1, 1), ICE)
	glitter.LightEmission = 1
	glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	glitter.Lifetime = NumberRange.new(0.6, 1.2)
	glitter.Speed = NumberRange.new(0.5, 1.5)
	glitter.Rate = 12
	glitter.Parent = block
	local light = Instance.new("PointLight")
	light.Color = ICE
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = block
	return parts
end

local function shatter(parts: { BasePart })
	local center = parts[1] and parts[1].Position
	for _, part in parts do
		part:Destroy()
	end
	if not center then
		return
	end
	for _ = 1, if Common.reduced() then 6 else 16 do
		local shard = Common.part({
			Size = Vector3.new(0.3 + math.random() * 0.6, 0.3 + math.random() * 0.9, 0.2 + math.random() * 0.4),
			CFrame = CFrame.new(center + Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 4, (math.random() - 0.5) * 3)),
			Color = ICE,
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			Anchored = false,
		})
		shard.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 40, 15 + math.random() * 20, (math.random() - 0.5) * 40)
		Common.fadeOut(shard, 1.4, { Transparency = 1 })
	end
end

function AdminEffectsController:_watchIce()
	local blocks: { [Model]: { BasePart } } = {}
	local watched: { [Model]: { RBXScriptConnection } } = {}

	local function hidden(model: Model): boolean
		local owner = Players:GetPlayerFromCharacter(model)
		return owner ~= nil and owner:GetAttribute(Attribute.Invisible) == true
	end
	local function removeBlock(model: Model, burst: boolean)
		local existing = blocks[model]
		if not existing then
			return
		end
		blocks[model] = nil
		if burst then
			shatter(existing)
		else
			for _, part in existing do
				part:Destroy()
			end
		end
	end
	local function refresh(model: Model)
		local iced = model:GetAttribute(Attribute.Iced) == true and model:IsDescendantOf(workspace)
		-- An invisible owner stays invisible, ice and all
		if iced and hidden(model) then
			removeBlock(model, false)
		elseif iced and not blocks[model] then
			blocks[model] = iceBlock(model)
		elseif not iced then
			removeBlock(model, true)
		end
	end
	local function unwatch(model: Model)
		local connections = watched[model]
		if connections then
			watched[model] = nil
			for _, connection in connections do
				connection:Disconnect()
			end
		end
		removeBlock(model, false)
	end
	local function watch(model: Instance)
		if not model:IsA("Model") or watched[model] then
			return
		end
		local connections = {}
		watched[model] = connections
		table.insert(connections, model:GetAttributeChangedSignal(Attribute.Iced):Connect(function()
			refresh(model)
		end))
		table.insert(connections, model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				unwatch(model)
			end
		end))
		local owner = Players:GetPlayerFromCharacter(model)
		if owner then
			table.insert(connections, owner:GetAttributeChangedSignal(Attribute.Invisible):Connect(function()
				refresh(model)
			end))
		end
		refresh(model)
	end
	for _, model in CollectionService:GetTagged(Protocol.Tag.Fighter) do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal(Protocol.Tag.Fighter):Connect(watch)
end

return AdminEffectsController
