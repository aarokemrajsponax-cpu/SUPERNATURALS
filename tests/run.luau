-- Runs every tests/*.spec.luau file. From the repository root:
--   lune run tests/run.luau
-- Lune: https://github.com/lune-org/lune

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Harness = require("./harness")

if not fs.isDir("src") then
	print("Run this from the repository root: lune run tests/run.luau")
	process.exit(1)
end

local files = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") then
		table.insert(files, name)
	end
end
table.sort(files)

local totalPassed, totalFailed = 0, 0
for _, name in files do
	local path = "tests/" .. name
	local env = Harness.environment({ Harness = Harness })
	env.require = nil
	local spec = luau.load(fs.readFile(path), { debugName = path, environment = env })()
	local passed, failed = Harness.runSpec(name, spec)
	print(`{if failed == 0 then "ok  " else "FAIL"} {name}: {passed} passed, {failed} failed`)
	totalPassed += passed
	totalFailed += failed
end

print(`\n{totalPassed} passed, {totalFailed} failed`)
process.exit(if totalFailed == 0 then 0 else 1)
