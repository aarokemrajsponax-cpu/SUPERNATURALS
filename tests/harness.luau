-- Loads game modules outside Roblox, the way Roblox would load them.
-- Modules use `require(script.Parent.Something)`; this harness fakes `script`
-- with paths into src/, following Rojo's layout (a folder's init.luau is the
-- folder's own module). Roblox data types come from Lune's roblox library.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local Harness = {}

-- Same mapping as default.project.json
local ROOTS = {
	Shared = "src/shared",
	Server = "src/server",
	Client = "src/client",
}

local RefMeta = {}
local cache: { [string]: any } = {}

-- File system lookups can't happen inside metamethods (they yield), so index
-- every file and folder under the roots once, up front.
local files: { [string]: boolean } = {}
local folders: { [string]: boolean } = {}
local function scan(path: string)
	folders[path] = true
	for _, name in fs.readDir(path) do
		local child = path .. "/" .. name
		if fs.isDir(child) then
			scan(child)
		else
			files[child] = true
		end
	end
end
for _, root in ROOTS do
	scan(root)
end

local function makeRef(path: string, isFolder: boolean)
	return setmetatable({ __path = path, __folder = isFolder }, RefMeta)
end

local function parentPath(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or ""
end

local function childRef(path: string, name: string)
	local base = path .. "/" .. name
	if files[base .. ".luau"] then
		return makeRef(base, false)
	elseif folders[base] then
		return makeRef(base, true)
	end
	return nil
end

RefMeta.__index = function(self, key: string)
	local path = rawget(self, "__path")
	if key == "Parent" then
		return makeRef(parentPath(path), true)
	elseif key == "Name" then
		return string.match(path, "([^/]+)$")
	end
	local child = rawget(self, "__folder") and childRef(path, key)
	if not child then
		error(`{key} is not a valid member of {path}`, 2)
	end
	return child
end

local loadModule

local function fakeRequire(target)
	if type(target) == "table" and getmetatable(target) == RefMeta then
		local path = rawget(target, "__path")
		local file = if rawget(target, "__folder") then path .. "/init.luau" else path .. ".luau"
		return loadModule(file, target)
	end
	error("tests can only require game modules through script references", 2)
end

local globals = {
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberRange = roblox.NumberRange,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	require = fakeRequire,
}

-- A fresh global environment holding the Roblox types plus `extra`.
-- (Values must be stored directly: Lune doesn't consult __index functions for globals.)
function Harness.environment(extra: { [string]: any })
	local env = {}
	for key, value in globals do
		env[key] = value
	end
	for key, value in extra do
		env[key] = value
	end
	return setmetatable(env, { __index = getfenv(0) })
end

function loadModule(file: string, scriptRef)
	if cache[file] ~= nil then
		return cache[file]
	end
	if not files[file] then
		error(`no module file at {file}`)
	end
	local env = Harness.environment({ script = scriptRef, require = fakeRequire })
	local chunk = luau.load(fs.readFile(file), { debugName = file, environment = env })
	local result = chunk()
	cache[file] = result
	return result
end

-- Load a game module by its path in the game, e.g. "Shared/Combat/FighterState"
function Harness.load(gamePath: string)
	local rootName, rest = string.match(gamePath, "^([^/]+)/?(.*)$")
	local root = ROOTS[rootName or ""]
	assert(root, `unknown root in {gamePath}`)
	local ref = makeRef(root, true)
	for name in string.gmatch(rest or "", "[^/]+") do
		ref = ref[name]
	end
	return fakeRequire(ref)
end

Harness.globals = globals

-- Tiny test framework ---------------------------------------------------------

export type T = {
	test: (name: string, fn: () -> ()) -> (),
	equal: (actual: any, expected: any, label: string?) -> (),
	truthy: (value: any, label: string?) -> (),
	near: (actual: number, expected: number, epsilon: number?, label: string?) -> (),
}

function Harness.runSpec(name: string, spec: (T) -> ()): (number, number)
	local passed, failed = 0, 0
	local currentFailures: { string } = {}

	local t = {} :: T
	function t.equal(actual, expected, label)
		if actual ~= expected then
			table.insert(currentFailures, `{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`)
		end
	end
	function t.truthy(value, label)
		if not value then
			table.insert(currentFailures, `{label or "value"}: expected truthy, got {tostring(value)}`)
		end
	end
	function t.near(actual, expected, epsilon, label)
		if math.abs(actual - expected) > (epsilon or 1e-6) then
			table.insert(currentFailures, `{label or "value"}: expected ~{expected}, got {actual}`)
		end
	end
	function t.test(testName, fn)
		currentFailures = {}
		local ok, err = pcall(fn)
		if not ok then
			table.insert(currentFailures, "error: " .. tostring(err))
		end
		if #currentFailures == 0 then
			passed += 1
		else
			failed += 1
			print(`  FAIL {name} > {testName}`)
			for _, message in currentFailures do
				print(`      {message}`)
			end
		end
	end

	spec(t)
	return passed, failed
end

return Harness
