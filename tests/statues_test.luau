-- The eight lobby statues: every power in Statues.Order builds a figure, a plinth and an
-- engraved plate without errors, inside the part budget, and an unknown id or a bad base
-- still gives a non-empty model.
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/statues_test.luau build/game.rbxl
local process = require("@lune/process")

local World = require("./smoke/World")

local game = World.start(process.args[1] or "build/game.rbxl")
local check, world = game.check, game.world
local Statues = world.require(world.find("ServerScriptService.Server.World.Statues"))

local function count(root: any): number
	local n = 0
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

check("eight powers in the hall order", function()
	assert(#Statues.Order == 8, "expected eight powers")
end)

for _, id in Statues.Order do
	check("statue " .. id, function()
		local model = Statues.build(id, game.CFrame.new(0, 0, 0))
		assert(model:IsA("Model"), "a Model")
		local figure, plinth = model:FindFirstChild("Figure"), model:FindFirstChild("Pedestal")
		assert(figure and plinth, "figure and plinth")
		assert(model:GetAttribute("Fallback") ~= true, "carved, not the fallback figure")
		local n = count(figure)
		-- a veiled (unreleased) fighter is a few draped cloth parts, not a carved figure
		local low = if model:GetAttribute("Veiled") then 20 else 120
		assert(n >= low and n <= 220, `figure parts {n} outside {low}..220`)
		assert(count(model) <= 260, "total parts " .. count(model))
		assert(model:GetAttribute("BadParts") == 0 and model:GetAttribute("Stretched") == 0, "bad or stretched parts")
		assert(model:FindFirstChild("Cranium", true), "a head")
		local plate = plinth:FindFirstChild("Plate")
		assert(plate, "plate")
		local gui = plate:FindFirstChildWhichIsA("SurfaceGui")
		assert(gui, "plate text")
		local title, code = gui:FindFirstChild("Title"), gui:FindFirstChild("Codename")
		assert(title and title.Text ~= "" and code and code.Text ~= "", "plate title and codename")
		assert(plinth:FindFirstChild("LightRing"), "light ring")
		assert(plinth:FindFirstChild("SteelBand"), "steel band")
		local top = 0
		for _, item in figure:GetDescendants() do
			if item:IsA("BasePart") then
				assert(not item.CanCollide, "figure parts do not collide")
				top = math.max(top, item.CFrame.Position.Y)
			end
		end
		assert(top > 30, "figure stands about 30 studs above the plinth foot: " .. top)
	end)
end

check("unknown id and bad base still give a figure", function()
	local a = Statues.build("NoSuchPower", game.CFrame.new(5, 0, 5))
	assert(count(a:FindFirstChild("Figure")) > 20, "fallback figure present")
	local b = Statues.build("Ghost", nil :: any)
	assert(count(b:FindFirstChild("Figure")) > 20, "bad base tolerated")
end)

process.exit(if game.finish() == 0 then 0 else 1)
