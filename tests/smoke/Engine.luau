-- A tiny stand-in for the Roblox engine, so game code can be *run* outside
-- Studio. Lune's roblox library gives real Instances with the real property
-- list (setting a misspelled property or a wrong value type errors, just like
-- Roblox); this file adds the engine methods, events and datatypes Lune lacks.
-- Signals really fire, tweens really finish (instantly applying their goal),
-- and frames can be stepped by hand.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any
local task = require("@lune/task")

local Engine = {}

local Instance = roblox.Instance

-- Errors thrown inside task.spawn / task.delay / signal callbacks are collected
-- here (as they would be printed in Roblox's output) so tests can fail on them
Engine.errors = {}
local function keepMessage(err)
	return debug.traceback(tostring(err), 2)
end

local function guarded(callback)
	return function(...)
		local ok, err = xpcall(callback, keepMessage, ...)
		if not ok then
			table.insert(Engine.errors, err)
			print("  ERROR in scheduled code: " .. tostring(err))
		end
	end
end
local gameTask = {
	spawn = function(callback, ...)
		if type(callback) == "thread" then
			return task.spawn(callback, ...)
		end
		return task.spawn(guarded(callback), ...)
	end,
	defer = function(callback, ...)
		if type(callback) == "thread" then
			return task.defer(callback, ...)
		end
		return task.defer(guarded(callback), ...)
	end,
	delay = function(seconds, callback, ...)
		return task.delay(seconds, guarded(callback), ...)
	end,
	wait = task.wait,
	cancel = task.cancel,
}
Engine.gameTask = gameTask

-- Signals -------------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ listeners = {} }, Signal)
end

function Signal:Connect(callback)
	local entry = { callback = callback, connected = true }
	table.insert(self.listeners, entry)
	return {
		Connected = true,
		Disconnect = function(connection)
			entry.connected = false
			connection.Connected = false
		end,
	}
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, entry in table.clone(self.listeners) do
		if entry.connected then
			-- Like Roblox: one listener erroring doesn't stop the others
			local ok, err = xpcall(entry.callback, keepMessage, ...)
			if not ok then
				table.insert(Engine.errors, err)
				print("  ERROR in event listener: " .. tostring(err))
			end
		end
	end
end

Engine.Signal = Signal

-- Lune can hand out a different wrapper object each time it returns the same
-- Instance, so signals are matched by equality (==) rather than table identity
local registry: { { owner: any, signals: { [string]: any } } } = {}
local function signalOf(instance, name: string)
	local perInstance
	for _, entry in registry do
		if rawequal(entry.owner, instance) or (typeof(instance) == "Instance" and typeof(entry.owner) == "Instance" and entry.owner == instance) then
			perInstance = entry.signals
			break
		end
	end
	if not perInstance then
		perInstance = {}
		table.insert(registry, { owner = instance, signals = perInstance })
	end
	local signal = perInstance[name]
	if not signal then
		signal = Signal.new()
		perInstance[name] = signal
	end
	return signal
end
Engine.signalOf = signalOf

local function event(className: string, name: string)
	roblox.implementProperty(className, name, function(self)
		return signalOf(self, name)
	end)
end

for _, spec in {
	{ "Instance", { "AncestryChanged", "ChildAdded", "ChildRemoved", "Destroying", "AttributeChanged" } },
	{ "GuiObject", { "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" } },
	{ "GuiButton", { "Activated", "MouseButton1Click" } },
	{ "TextBox", { "FocusLost", "Focused" } },
	{ "Humanoid", { "Died", "HealthChanged" } },
	{ "Players", { "PlayerAdded", "PlayerRemoving" } },
	{ "Player", { "CharacterAdded", "CharacterRemoving" } },
	{ "RunService", { "Heartbeat", "RenderStepped", "Stepped" } },
	{ "RemoteEvent", { "OnServerEvent", "OnClientEvent" } },
	{ "BindableEvent", { "Event" } },
	{ "UserInputService", { "InputBegan", "InputEnded", "WindowFocusReleased", "LastInputTypeChanged" } },
	{ "TweenBase", { "Completed" } },
} do
	for _, name in spec[2] do
		event(spec[1], name)
	end
end

roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
	return signalOf(self, "Attribute:" .. name)
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, name)
	return signalOf(self, "Property:" .. name)
end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)
roblox.implementMethod("BindableEvent", "Fire", function(self, ...)
	signalOf(self, "Event"):Fire(...)
end)

-- Remote calls are recorded so tests can inspect what would be sent
Engine.sent = {}
local function record(kind)
	return function(self, ...)
		table.insert(Engine.sent, { remote = self.Name, kind = kind, args = table.pack(...) })
	end
end
roblox.implementMethod("RemoteEvent", "FireServer", record("FireServer"))
roblox.implementMethod("RemoteEvent", "FireClient", record("FireClient"))
roblox.implementMethod("RemoteEvent", "FireAllClients", record("FireAllClients"))

-- Engine methods ---------------------------------------------------------------------------

local pivots = setmetatable({}, { __mode = "k" })
roblox.implementMethod("Model", "GetPivot", function(self)
	local primary = self.PrimaryPart or self:FindFirstChild("HumanoidRootPart")
	if primary then
		return primary.CFrame
	end
	return pivots[self] or self.WorldPivot
end)
roblox.implementMethod("Model", "PivotTo", function(self, cframe)
	local primary = self.PrimaryPart or self:FindFirstChild("HumanoidRootPart")
	if primary then
		primary.CFrame = cframe
	end
	pivots[self] = cframe
end)
roblox.implementMethod("Model", "GetExtentsSize", function()
	return roblox.Vector3.new(4, 5, 2)
end)
roblox.implementMethod("Model", "ScaleTo", function() end)
roblox.implementMethod("BasePart", "GetPivot", function(self)
	return self.CFrame
end)
roblox.implementMethod("BasePart", "PivotTo", function(self, cframe)
	self.CFrame = cframe
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("Humanoid", "ChangeState", function() end)
roblox.implementMethod("Humanoid", "MoveTo", function() end)

-- Services ------------------------------------------------------------------------------
-- Lune's own CollectionService/Players methods can't be replaced, so game code
-- gets stand-in service objects for those two (see Engine.load).

local tags: { [string]: { any } } = {}
local function fakeCollectionService()
	local service = {}
	function service.AddTag(_, instance, tag)
		tags[tag] = tags[tag] or {}
		if not table.find(tags[tag], instance) then
			table.insert(tags[tag], instance)
		end
		signalOf(service, "Tag:" .. tag):Fire(instance)
	end
	function service.RemoveTag(_, instance, tag)
		local list = tags[tag]
		local index = list and table.find(list, instance)
		if index then
			table.remove(list, index)
		end
	end
	function service.HasTag(_, instance, tag)
		return table.find(tags[tag] or {}, instance) ~= nil
	end
	function service.GetTagged(_, tag)
		return table.clone(tags[tag] or {})
	end
	function service.GetInstanceAddedSignal(_, tag)
		return signalOf(service, "Tag:" .. tag)
	end
	function service.GetInstanceRemovedSignal(_, tag)
		return signalOf(service, "TagRemoved:" .. tag)
	end
	return service
end

roblox.implementMethod("Debris", "AddItem", function(_, instance, lifetime)
	task.delay(lifetime or 10, function()
		pcall(function()
			instance:Destroy()
		end)
	end)
end)

-- Tweens finish after their duration and apply their goal (fast-forwarded by Engine.speed)
Engine.speed = 50
roblox.implementMethod("TweenService", "Create", function(_, instance, info, goal)
	local completed = Signal.new()
	local tween = { Completed = completed, PlaybackState = "Begin", Instance = instance }
	local cancelled = false
	function tween.Play()
		task.delay((info.Time or 0) / Engine.speed, function()
			if cancelled then
				return
			end
			for key, value in goal do
				pcall(function()
					instance[key] = value
				end)
			end
			completed:Fire("Completed")
		end)
	end
	function tween.Cancel()
		cancelled = true
	end
	function tween.Pause() end
	return setmetatable(tween, {
		__index = function(_, key)
			error(`{key} is not a valid member of Tween (smoke engine)`)
		end,
	})
end)

Engine.players = {}
local function fakePlayers(localPlayer)
	local service = { LocalPlayer = localPlayer, RespawnTime = 5 }
	service.PlayerAdded = Signal.new()
	service.PlayerRemoving = Signal.new()
	function service.GetPlayers()
		return table.clone(Engine.players)
	end
	function service.GetPlayerFromCharacter(_, character)
		for _, player in Engine.players do
			if player.Character == character then
				return player
			end
		end
		return nil
	end
	function service.GetPlayerByUserId(_, id)
		for _, player in Engine.players do
			if player.UserId == id then
				return player
			end
		end
		return nil
	end
	function service.GetUserThumbnailAsync()
		return "rbxasset://textures/ui/GuiImagePlaceholder.png", true
	end
	function service.GetUserIdFromNameAsync()
		return 1
	end
	function service.CreateHumanoidModelFromDescription(_, description, rigType)
		assert(typeof(description) == "Instance" and description.ClassName == "HumanoidDescription", "needs a HumanoidDescription")
		local model = Engine.character("Dummy")
		local _ = rigType
		return model
	end
	return service
end

-- A minimal R15-like character: root, torso, head, arm and a Humanoid
local makeInstance
function Engine.character(name: string)
	local model = makeInstance("Model")
	model.Name = name
	for _, partName in { "HumanoidRootPart", "UpperTorso", "Head", "RightUpperArm" } do
		local part = makeInstance("Part")
		part.Name = partName
		part.Parent = model
	end
	local humanoid = makeInstance("Humanoid")
	humanoid.Parent = model
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
	return model
end
roblox.implementMethod("Player", "Kick", function() end)

local renderSteps = {}
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, _priority, callback)
	renderSteps[name] = callback
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
	renderSteps[name] = nil
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)
roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("RunService", "IsClient", function()
	return true
end)

roblox.implementMethod("ContextActionService", "BindAction", function() end)
roblox.implementMethod("ContextActionService", "UnbindAction", function() end)
roblox.implementMethod("ContextActionService", "SetTitle", function() end)
roblox.implementMethod("ContextActionService", "SetPosition", function() end)
roblox.implementMethod("UserInputService", "GetLastInputType", function()
	return roblox.Enum.UserInputType.Keyboard
end)
roblox.implementMethod("UserInputService", "IsKeyDown", function()
	return false
end)
roblox.implementMethod("UserInputService", "IsGamepadButtonDown", function()
	return false
end)
roblox.implementMethod("HttpService", "GenerateGUID", function()
	return "00000000-0000-0000-0000-000000000000"
end)

local startClock = os.clock()
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return 1000 + (os.clock() - startClock)
end)
-- Tests can give the world simple ground: Engine.raycast(origin, direction, params)
-- returns { Position, Normal, Instance, Material } or nil. By default nothing is hit.
Engine.raycast = nil :: ((Vector3, Vector3, any) -> any)?
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
	if Engine.raycast then
		return Engine.raycast(origin, direction, params)
	end
	return nil
end)
roblox.implementMethod("Workspace", "Spherecast", function(_, origin, _radius, direction, params)
	if Engine.raycast then
		return Engine.raycast(origin, direction, params)
	end
	return nil
end)
roblox.implementMethod("Workspace", "Blockcast", function(_, cframe, _size, direction, params)
	if Engine.raycast then
		return Engine.raycast(cframe.Position, direction, params)
	end
	return nil
end)
roblox.implementMethod("Workspace", "GetPartBoundsInBox", function()
	return {}
end)
roblox.implementMethod("Workspace", "GetPartBoundsInRadius", function()
	return {}
end)
roblox.implementMethod("Workspace", "GetPartsInPart", function()
	return {}
end)
roblox.implementMethod("Player", "GetNetworkPing", function()
	return 0.05
end)
roblox.implementMethod("Camera", "ViewportPointToRay", function(self, x, y)
	local cframe = self.CFrame
	return { Origin = cframe.Position, Direction = cframe.LookVector }
end)
roblox.implementMethod("UserInputService", "GetMouseLocation", function()
	return roblox.Vector2.new(640, 360)
end)
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function()
	return nil
end)

-- Datatypes Lune doesn't have ---------------------------------------------------------------

local TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delayTime)
		return { Time = time or 1, EasingStyle = style, EasingDirection = direction, RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delayTime or 0 }
	end,
}

local RaycastParams = {
	new = function()
		return { FilterType = nil, FilterDescendantsInstances = {}, RespectCanCollide = false, IgnoreWater = false }
	end,
}

local OverlapParams = {
	new = function()
		return { FilterType = nil, FilterDescendantsInstances = {}, RespectCanCollide = false, MaxParts = 0 }
	end,
}

local Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local function nextUnit()
			state = (state * 48271) % 2147483647
			return state / 2147483647
		end
		return {
			NextNumber = function(_, min, max)
				min, max = min or 0, max or 1
				return min + (max - min) * nextUnit()
			end,
			NextInteger = function(_, min, max)
				return min + math.floor(nextUnit() * (max - min + 1))
			end,
		}
	end,
}

local DateTime = {
	now = function()
		return {
			UnixTimestamp = os.time(),
			ToUniversalTime = function()
				return { Year = 2026, Month = 10, Day = 21, Hour = 12, Minute = 0, Second = 0, Millisecond = 0 }
			end,
		}
	end,
}

-- Building a game -------------------------------------------------------------------------

function Engine.load(placePath: string)
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local workspace = game:GetService("Workspace")

	local camera = Instance.new("Camera")
	camera.Name = "Camera"
	camera.CFrame = roblox.CFrame.new(0, 10, 20)
	camera.FieldOfView = 70
	pcall(function()
		camera.ViewportSize = roblox.Vector2.new(1280, 720)
	end)
	camera.Parent = workspace
	workspace.CurrentCamera = camera

	-- Lighting values a real place always has
	local lighting = game:GetService("Lighting")
	for key, value in {
		ClockTime = 14,
		Brightness = 2,
		Ambient = roblox.Color3.fromRGB(70, 70, 70),
		OutdoorAmbient = roblox.Color3.fromRGB(128, 128, 128),
		ColorShift_Top = roblox.Color3.new(0, 0, 0),
		ColorShift_Bottom = roblox.Color3.new(0, 0, 0),
		ExposureCompensation = 0,
	} do
		lighting[key] = value
	end

	local localPlayer = Instance.new("Player")
	localPlayer.Name = "XxxXxxX_77797"
	localPlayer.DisplayName = "Tester"
	pcall(function()
		localPlayer.UserId = 1
	end)
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = localPlayer
	table.insert(Engine.players, localPlayer)

	local fakeServices = {
		Players = fakePlayers(localPlayer),
		CollectionService = fakeCollectionService(),
	}
	Engine.services = fakeServices
	-- `game` for game code: the real place, with the stand-in services swapped in
	local gameProxy = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_, name)
					return fakeServices[name] or game:GetService(name)
				end
			elseif key == "CreatorId" then
				return 0
			elseif key == "CreatorType" then
				return roblox.Enum.CreatorType.User
			end
			local value = game[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(game, ...)
				end
			end
			return value
		end,
	})

	-- New instances get the values a fresh Roblox instance would have, for
	-- properties Lune can't work out on its own (it errors when reading them)
	local DEFAULTS = {
		{ "BasePart", { Position = roblox.Vector3.zero, AssemblyLinearVelocity = roblox.Vector3.zero, AssemblyAngularVelocity = roblox.Vector3.zero, AssemblyMass = 10 } },
		{ "Model", { WorldPivot = roblox.CFrame.new() } },
		{ "Humanoid", { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpHeight = 7.2 } },
	}
	local function withDefaults(instance)
		for _, entry in DEFAULTS do
			if instance:IsA(entry[1]) then
				for key, value in entry[2] do
					pcall(function()
						instance[key] = value
					end)
				end
			end
		end
		return instance
	end
	local InstanceShim = {
		new = function(className, parent)
			local instance = withDefaults(Instance.new(className))
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	}
	makeInstance = InstanceShim.new

	local cache = {}
	local env
	local function requireModule(module)
		if typeof(module) ~= "Instance" or module.ClassName ~= "ModuleScript" then
			error("require expects a ModuleScript, got " .. tostring(module), 2)
		end
		-- Keyed by path: Lune may hand out a new wrapper for the same ModuleScript,
		-- and Roblox always returns the same table for the same module
		local key = module:GetFullName()
		if cache[key] ~= nil then
			return cache[key]
		end
		local moduleEnv = setmetatable({ script = module }, { __index = env })
		for key, value in env do
			moduleEnv[key] = value
		end
		moduleEnv.script = module
		local chunk = luau.load(module.Source, { debugName = module:GetFullName(), environment = moduleEnv })
		local result = chunk()
		cache[key] = result
		return result
	end

	env = {
		game = gameProxy,
		workspace = workspace,
		Instance = InstanceShim,
		task = gameTask,
		require = requireModule,
		TweenInfo = TweenInfo,
		RaycastParams = RaycastParams,
		OverlapParams = OverlapParams,
		Random = Random,
		DateTime = DateTime,
		typeof = typeof,
		warn = function(...)
			print("  warn:", ...)
		end,
	}
	for _, name in {
		"Vector3", "Vector2", "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "NumberSequence",
		"NumberSequenceKeypoint", "NumberRange", "UDim", "UDim2", "Enum", "Rect", "Font", "BrickColor",
	} do
		env[name] = roblox[name]
	end
	setmetatable(env, { __index = getfenv(0) })

	return {
		game = game,
		Instance = InstanceShim,
		services = fakeServices,
		workspace = workspace,
		camera = camera,
		localPlayer = localPlayer,
		require = requireModule,
		find = function(path: string)
			local current = game
			for name in string.gmatch(path, "[^%.]+") do
				current = if current == game then game:GetService(name) else current:FindFirstChild(name)
				if not current then
					error("nothing at " .. path)
				end
			end
			return current
		end,
	}
end

-- Roblox derives BasePart.Position from CFrame; Lune stores them separately,
-- so tests call this to copy each part's CFrame position into Position
function Engine.syncPositions(root)
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			pcall(function()
				item.Position = item.CFrame.Position
			end)
		end
	end
end

-- Roblox fires Humanoid.Died when health reaches 0; Lune doesn't, so tests call this
local diedFired = setmetatable({}, { __mode = "k" })
function Engine.checkDeaths(root)
	for _, item in root:GetDescendants() do
		if item:IsA("Humanoid") then
			local already = false
			for done in diedFired do
				if done == item then
					already = true
				end
			end
			if not already and item.Health <= 0 then
				diedFired[item] = true
				signalOf(item, "Died"):Fire()
			end
		end
	end
end

-- Fires every frame-based signal `frames` times with the given step
function Engine.step(game, frames: number, dt: number?)
	local runService = game:GetService("RunService")
	for _ = 1, frames do
		for _, callback in renderSteps do
			callback(dt or 1 / 60)
		end
		signalOf(runService, "RenderStepped"):Fire(dt or 1 / 60)
		signalOf(runService, "Heartbeat"):Fire(dt or 1 / 60)
		signalOf(runService, "Stepped"):Fire(0, dt or 1 / 60)
	end
end

Engine.task = task

return Engine
