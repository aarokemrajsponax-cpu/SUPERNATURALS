-- The Spectating Lounge's seasonal sets: small accents added to the finished room, so it
-- changes through the year without an architectural rebuild. Called by SeasonalDecor.build
-- after the outdoor set, with the lounge's own spot list (World/Lounge.spots(): the table
-- tops, the wall above the big screen, the counter, the door). Everything goes into the same
-- SeasonalDecor folder, so clearing a season clears its lounge accents too. Parts here are
-- decoration only: no collision on small items, no extra shadows, a handful of soft lights.
--   Thanksgiving  warm autumn: harvest pumpkins and candles on the tables, a leaf garland over
--                 the viewing wall, a wreath on the door, a few warm glows
--   Halloween     carved pumpkins on the tables, a string of orange lamps over the wall
--   Christmas     a garland with ornaments, presents on the tables, a wreath on the door
-- To add a season: add a function below keyed by the season id (Calendar ids, as in init.luau).

local LoungeSet = {}

local rgb = Color3.fromRGB
local M = Enum.Material

local LEAVES = { rgb(214, 92, 31), rgb(232, 140, 35), rgb(190, 50, 35), rgb(240, 190, 60), rgb(160, 60, 30) }
local SMALL = { CanCollide = false, CastShadow = false }

local function flame(model, Build, at: Vector3, color: Color3)
	Build.cylinder(model, 0.7, 0.5, CFrame.new(at + Vector3.new(0, 0.35, 0)), { Color = rgb(236, 226, 205), Material = M.SmoothPlastic, CanCollide = false })
	local spark = Build.ball(model, 0.22, CFrame.new(at + Vector3.new(0, 0.82, 0)), { Color = color, Material = M.Neon, CanCollide = false, CastShadow = false })
	Build.light(spark, color, 9, 0.8, false)
end

-- A row of round accents along the wall above the big screen
local function garland(folder, Build, spots, colors: { Color3 }, glow: boolean, seed: number)
	local model = Build.model(folder, "LoungeGarland")
	local rng = Random.new(seed)
	local top = spots.wallTop
	for index = 0, 26 do
		local x = -22 + index * (44 / 26)
		local sag = math.sin(index / 26 * math.pi) * -1.6
		local color = colors[(index % #colors) + 1]
		local props = if glow then { Color = color, Material = M.Neon, CanCollide = false, CastShadow = false } else { Color = color, Material = M.Fabric, CanCollide = false, CastShadow = false }
		Build.ball(model, rng:NextNumber(0.8, 1.2), CFrame.new(top + Vector3.new(x, sag, rng:NextNumber(-0.1, 0.2))), props)
	end
end

local function wreath(folder, Build, spots, colors: { Color3 }, radius: number)
	local model = Build.model(folder, "LoungeWreath")
	local center = spots.door + Vector3.new(0, 3.2, -0.6)
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2
		Build.ball(model, 0.95, CFrame.new(center + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)), {
			Color = colors[(index % #colors) + 1], Material = M.Fabric, CanCollide = false, CastShadow = false,
		})
	end
end

LoungeSet.Thanksgiving = function(folder, Build, spots)
	local model = Build.model(folder, "LoungeHarvest")
	for index, spot in spots.tables do
		local top = spot.position
		if index == 1 then
			Build.pumpkin(model, CFrame.new(top + Vector3.new(-1.1, 0, 0.6)), 0.34)
			Build.pumpkin(model, CFrame.new(top + Vector3.new(0.5, 0, -1.1)), 0.26, { color = rgb(225, 140, 40) })
			Build.pumpkin(model, CFrame.new(top + Vector3.new(1.4, 0, 1.0)), 0.2, { color = rgb(240, 225, 190) })
			flame(model, Build, top + Vector3.new(-0.3, 0, -0.2), rgb(255, 176, 70))
		else
			Build.pumpkin(model, CFrame.new(top + Vector3.new(0.3, 0, 0.2)), 0.26)
			flame(model, Build, top + Vector3.new(-0.5, 0, -0.3), rgb(255, 176, 70))
		end
	end
	-- Harvest on the counter: pumpkins and gourds along the marble
	for index = 1, 4 do
		Build.pumpkin(model, CFrame.new(spots.counterTop + Vector3.new(-0.6, 0.2, -9 + index * 4.2)), 0.3 + (index % 2) * 0.08, { color = LEAVES[index] })
	end
	garland(folder, Build, spots, LEAVES, false, 1123)
	wreath(folder, Build, spots, LEAVES, 2.7)
	-- Warm autumn glow: a few soft lights, no new light bars
	local glows = Build.model(folder, "LoungeAutumnGlow")
	for _, offset in { Vector3.new(-30, -7, 0), Vector3.new(30, -7, 0), Vector3.new(0, -7, -26), Vector3.new(0, -7, 22) } do
		local anchor = Build.part(glows, { Size = Vector3.new(0.4, 0.4, 0.4), CFrame = CFrame.new(spots.glass + offset), Transparency = 1, CanCollide = false, CastShadow = false })
		Build.light(anchor, rgb(255, 150, 60), 28, 0.5, false)
	end
end

LoungeSet.Halloween = function(folder, Build, spots)
	local model = Build.model(folder, "LoungeHalloween")
	for _, spot in spots.tables do
		Build.pumpkin(model, CFrame.new(spot.position + Vector3.new(0.3, 0, 0.2)), 0.3, { carved = true })
	end
	garland(folder, Build, spots, { rgb(255, 140, 40), rgb(150, 90, 220) }, true, 1031)
end

LoungeSet.Christmas = function(folder, Build, spots)
	local model = Build.model(folder, "LoungeChristmas")
	for index, spot in spots.tables do
		Build.present(model, CFrame.new(spot.position + Vector3.new(0.2, 0, 0.2)), Vector3.new(0.9, 0.7, 0.9), if index % 2 == 0 then rgb(196, 50, 50) else rgb(46, 110, 70), rgb(232, 196, 90))
	end
	garland(folder, Build, spots, { rgb(46, 110, 70), rgb(196, 50, 50), rgb(232, 196, 90) }, false, 1225)
	wreath(folder, Build, spots, { rgb(46, 110, 70), rgb(46, 110, 70), rgb(196, 50, 50) }, 2.7)
end

return LoungeSet
