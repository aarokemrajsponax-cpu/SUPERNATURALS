-- Checks a built place file:
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/place_check.luau build/game.rbxl
-- Verifies that the scripts and remotes exist with the right classes, and that
-- every require(...) in every script points at a module that really exists.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local path = process.args[1] or "build/game.rbxl"
if not fs.isFile(path) then
	print(`No place file at {path}. Build one first: rojo build default.project.json -o {path}`)
	process.exit(1)
end

local game = roblox.deserializePlace(fs.readFile(path))
local failures = 0
local function fail(message: string)
	failures += 1
	print("  FAIL " .. message)
end

local function find(root, dotted: string)
	local current = root
	for name in string.gmatch(dotted, "[^%.]+") do
		current = current and current:FindFirstChild(name)
	end
	return current
end

-- Required instances ------------------------------------------------------------
local expected = {
	{ "ReplicatedStorage", "Remotes.CombatRequest", "RemoteEvent" },
	{ "ReplicatedStorage", "Remotes.CombatEvent", "RemoteEvent" },
	{ "ReplicatedStorage", "Remotes.MatchRequest", "RemoteEvent" },
	{ "ReplicatedStorage", "Remotes.MatchEvent", "RemoteEvent" },
	{ "ReplicatedStorage", "Shared.Config", "ModuleScript" },
	{ "ReplicatedStorage", "Shared.Config.Combat", "ModuleScript" },
	{ "ReplicatedStorage", "Shared.Combat.FighterState", "ModuleScript" },
	{ "ServerScriptService", "Server.Bootstrap", "Script" },
	{ "ServerScriptService", "Server.Services.CombatService", "ModuleScript" },
	{ "ServerScriptService", "Server.Services.MatchService", "ModuleScript" },
	{ "StarterPlayer", "StarterPlayerScripts.Client.Bootstrap", "LocalScript" },
	{ "StarterPlayer", "StarterPlayerScripts.Client.Controllers.UIController", "ModuleScript" },
	{ "StarterPlayer", "StarterCharacterScripts.Health", "Script" },
}
for _, entry in expected do
	local instance = find(game:GetService(entry[1]), entry[2])
	if not instance then
		fail(`missing {entry[1]}.{entry[2]}`)
	elseif instance.ClassName ~= entry[3] then
		fail(`{entry[1]}.{entry[2]} is a {instance.ClassName}, expected {entry[3]}`)
	end
end

-- Bootstrap service lists match the modules that exist --------------------------
local function checkOrder(script, folder, label)
	if not script or not folder then
		return
	end
	local source = script.Source
	local block = string.match(source, "local ORDER = (%b{})")
	if not block then
		fail(label .. ": no ORDER list")
		return
	end
	for name in string.gmatch(block, '"([%w_]+)"') do
		local module = folder:FindFirstChild(name)
		if not module or module.ClassName ~= "ModuleScript" then
			fail(`{label} starts "{name}" but there's no such module`)
		end
	end
end
local serverRoot = find(game:GetService("ServerScriptService"), "Server")
local clientRoot = find(game:GetService("StarterPlayer"), "StarterPlayerScripts.Client")
checkOrder(serverRoot and serverRoot:FindFirstChild("Bootstrap"), serverRoot and serverRoot:FindFirstChild("Services"), "server Bootstrap")
checkOrder(clientRoot and clientRoot:FindFirstChild("Bootstrap"), clientRoot and clientRoot:FindFirstChild("Controllers"), "client Bootstrap")

-- Every static require resolves ---------------------------------------------------
-- Understands: script, .Parent, .Name, game:GetService("X") aliases declared as
-- `local X = game:GetService("X")`, and :WaitForChild("Name").
local checked = 0
for _, container in game:GetDescendants() do
	if container:IsA("LuaSourceContainer") then
		local source = container.Source
		local services = {}
		for alias, service in string.gmatch(source, 'local (%w+) = game:GetService%("(%w+)"%)') do
			services[alias] = service
		end
		local aliases = {}
		for alias, expression in string.gmatch(source, "local (%w+) = ([%w%.:_\"%(%)]+)\n") do
			aliases[alias] = expression
		end
		for wrapped in string.gmatch(source, "require(%b())") do
			local expression = string.sub(wrapped, 2, -2)
			-- Only resolve plain instance paths
			local cleaned = string.gsub(expression, ':WaitForChild%("([%w_]+)"%)', ".%1")
			if string.match(cleaned, "^[%w%._]+$") then
				local parts = string.split(cleaned, ".")
				local head = parts[1]
				local current
				if head == "script" then
					current = container
				elseif services[head] then
					current = game:GetService(services[head])
				elseif aliases[head] then
					local aliased = string.gsub(aliases[head], ':WaitForChild%("([%w_]+)"%)', ".%1")
					local inner = string.split(aliased, ".")
					if inner[1] == "script" then
						current = container
					elseif services[inner[1]] then
						current = game:GetService(services[inner[1]])
					end
					for i = 2, #inner do
						if not current then
							break
						end
						current = if inner[i] == "Parent" then current.Parent else current:FindFirstChild(inner[i])
					end
				end
				if current then
					for i = 2, #parts do
						local name = parts[i]
						if not current then
							break
						end
						current = if name == "Parent" then current.Parent else current:FindFirstChild(name)
					end
					checked += 1
					if not current then
						fail(`{container:GetFullName()}: require({expression}) points at nothing`)
					elseif current.ClassName ~= "ModuleScript" then
						fail(`{container:GetFullName()}: require({expression}) is a {current.ClassName}`)
					end
				end
			end
		end
	end
end

print(`checked {checked} requires`)
if failures == 0 then
	print("place check passed")
else
	print(`{failures} problems`)
end
process.exit(if failures == 0 then 0 else 1)
