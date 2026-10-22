-- A running game for tests: loads the built place in the stand-in engine,
-- starts every server service in Bootstrap's order, and simulates what the
-- Roblox engine does between frames (deaths, respawns, Heartbeat). Test
-- scripts get helpers to join players, send requests and wait for results.

local roblox = require("@lune/roblox") :: any

local Engine = require("./Engine")

local World = {}

function World.start(placePath: string, configure: ((world: any) -> ())?)
	local world = Engine.load(placePath)
	local task = Engine.task
	local Vector3, CFrame = roblox.Vector3, Engine.CFrame

	local function find(path: string)
		return world.find(path)
	end
	local Combat = world.require(find("ReplicatedStorage.Shared.Config.Combat"))
	local MatchConfig = world.require(find("ReplicatedStorage.Shared.Config.Match"))
	-- Short timings so tests run in seconds
	Combat.RespawnTime = 0.3
	Combat.SpawnProtection = 0.1
	for _, mode in MatchConfig.Modes do
		mode.Countdown = 0.3
		mode.Duration = 10
		mode.ResultsDuration = 0.4
		mode.SuddenDeathDuration = 0.6
		mode.QueueFillDelay = 0.3
	end
	if configure then
		configure({ world = world, Combat = Combat, MatchConfig = MatchConfig })
	end

	-- Same services, same order as the real Bootstrap script
	local bootstrap = find("ServerScriptService.Server.Bootstrap")
	local order = {}
	local list = string.match(bootstrap.Source, "local ORDER = (%b{})")
	for name in string.gmatch(list or "", '"([%w_]+)"') do
		table.insert(order, name)
	end
	local services = {}
	for _, name in order do
		services[name] = world.require(find("ServerScriptService.Server.Services." .. name))
	end
	for _, name in order do
		if services[name].Init then
			services[name]:Init(services)
		end
	end
	for _, name in order do
		if services[name].Start then
			Engine.gameTask.spawn(services[name].Start, services[name])
		end
	end
	task.wait(0.2)

	local Characters = services.CharacterService
	local Players = world.services.Players
	local remotes = find("ReplicatedStorage.Remotes")

	local api = {
		world = world,
		Engine = Engine,
		task = task,
		services = services,
		Combat = Combat,
		MatchConfig = MatchConfig,
		order = order,
		Vector3 = Vector3,
		CFrame = CFrame,
	}

	function api.request(remote: string, player, ...)
		Engine.signalOf(remotes:FindFirstChild(remote), "OnServerEvent"):Fire(player, ...)
	end

	local respawnQueue = {}
	local function spawnCharacter(player)
		local character = Engine.character(player.Name)
		character.HumanoidRootPart.CFrame = CFrame.new(0, 4, 0)
		player.Character = character
		character.Parent = world.workspace
		Engine.signalOf(player, "CharacterAdded"):Fire(character)
		return character
	end

	-- The engine's work between frames
	local running = true
	task.spawn(function()
		local last = os.clock()
		while running do
			Engine.syncPositions(world.workspace)
			Engine.checkDeaths(world.workspace)
			local time = os.clock()
			Engine.signalOf(world.game:GetService("RunService"), "Heartbeat"):Fire(time - last)
			last = time
			for _, player in Engine.players do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health <= 0 and not respawnQueue[player.Name] then
					respawnQueue[player.Name] = true
					task.delay(Combat.RespawnTime, function()
						respawnQueue[player.Name] = nil
						if table.find(Engine.players, player) then
							character:Destroy()
							spawnCharacter(player)
						end
					end)
				end
			end
			task.wait(0.03)
		end
	end)

	function api.stop()
		running = false
	end

	local nextId = 100
	function api.join(name: string, userId: number?)
		nextId += 1
		local player = world.Instance.new("Player")
		player.Name = name
		player.DisplayName = name
		player.UserId = userId or nextId
		player.Parent = world.game:GetService("Players")
		table.insert(Engine.players, player)
		Players.PlayerAdded:Fire(player)
		spawnCharacter(player)
		task.wait(0.15)
		return player
	end

	function api.leave(player)
		local index = table.find(Engine.players, player)
		if index then
			table.remove(Engine.players, index)
		end
		Players.PlayerRemoving:Fire(player)
		if player.Character then
			player.Character:Destroy()
		end
		player.Parent = nil
	end

	function api.fighter(player)
		return Characters:getByPlayer(player)
	end

	-- Puts two fighters face to face `gap` studs apart (players or fighter records)
	function api.faceOff(a, b, gap: number)
		local fa = if a.root then a else api.fighter(a)
		local fb = if b.root then b else api.fighter(b)
		local base = fa.root.CFrame.Position
		local posB = base + Vector3.new(gap, 0, 0)
		fa.root.CFrame = CFrame.lookAt(base, posB)
		fb.root.CFrame = CFrame.lookAt(posB, base)
		Engine.syncPositions(world.workspace)
	end

	-- The newest message of `kind` a remote sent to `player` (nil player = to everyone)
	function api.lastSent(remote: string, kind: string, player)
		for index = #Engine.sent, 1, -1 do
			local entry = Engine.sent[index]
			if entry.remote == remote then
				if player and entry.kind == "FireClient" and entry.args[1] == player and entry.args[2] == kind then
					return entry.args[3], index
				elseif not player and entry.kind == "FireAllClients" and entry.args[1] == kind then
					return entry.args[2], index
				end
			end
		end
		return nil, 0
	end

	-- Every message since `fromIndex` matching remote/kind (and player if given)
	function api.sentSince(fromIndex: number, remote: string, kind: string, player)
		local found = {}
		for index = fromIndex + 1, #Engine.sent do
			local entry = Engine.sent[index]
			if entry.remote == remote then
				if player and entry.kind == "FireClient" and entry.args[1] == player and entry.args[2] == kind then
					table.insert(found, entry.args[3])
				elseif not player and entry.kind == "FireAllClients" and entry.args[1] == kind then
					table.insert(found, entry.args[2])
				end
			end
		end
		return found
	end

	function api.mark(): number
		return #Engine.sent
	end

	function api.waitFor(condition: () -> boolean, timeout: number, label: string)
		local started = os.clock()
		while not condition() do
			if os.clock() - started > timeout then
				error("timed out waiting for " .. label, 2)
			end
			task.wait(0.03)
		end
	end

	-- Flat ground at height y everywhere (for teleports and ground checks)
	function api.flatGround(y: number)
		Engine.raycast = function(origin, direction)
			if direction.Y < -0.5 and origin.Y >= y and origin.Y + direction.Y <= y then
				return { Position = Vector3.new(origin.X, y, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = nil, Material = roblox.Enum.Material.Plastic }
			end
			return nil
		end
	end

	-- A test runner that also fails when game code threw errors
	local passed, failed = 0, 0
	function api.check(name: string, fn: () -> ())
		local before = #Engine.errors
		local ok, err = pcall(fn)
		if ok and #Engine.errors > before then
			ok, err = false, "errors were thrown inside the game code (see above)"
		end
		if ok then
			passed += 1
			print("ok   " .. name)
		else
			failed += 1
			print("FAIL " .. name)
			print("     " .. tostring(err))
		end
	end

	function api.finish()
		running = false
		print(`\n{passed} passed, {failed} failed`)
		return failed
	end

	return api
end

return World
