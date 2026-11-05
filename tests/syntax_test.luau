-- Every Luau file in src/ and tests/ must compile. Most tests only load the scripts they exercise,
-- so a syntax error in a script nobody tests (for example a server script outside the Bootstrap
-- order) would otherwise reach Roblox, where the whole script fails to load.
-- Run: lune run tests/syntax_test.luau

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local checked, failed = 0, 0

local function walk(folder: string)
	for _, name in fs.readDir(folder) do
		local path = folder .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(name, -5) == ".luau" then
			checked += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print("FAIL " .. path)
				print("     " .. tostring(err))
			end
		end
	end
end

walk("src")
walk("tests")
walk("tools")

assert(checked > 100, "found the source files (run from the repo root)")
if failed == 0 then
	print(`ok   all {checked} Luau files compile`)
end
print(`\n{if failed == 0 then 1 else 0} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
