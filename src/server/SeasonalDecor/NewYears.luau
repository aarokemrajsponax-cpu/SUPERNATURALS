-- New Year's: a glowing countdown stage with the new year, sweeping searchlights
-- and balloon bunches. The fireworks are launched by each player's client.

local rgb = Color3.fromRGB

local GOLD = rgb(255, 205, 90)
local BALLOONS = { rgb(255, 205, 90), rgb(220, 220, 235), rgb(250, 250, 250), rgb(30, 30, 40), rgb(200, 160, 60) }

local function newYear(): number
	local now = DateTime.now():ToUniversalTime()
	-- From July on we're counting down to next year
	return if now.Month >= 7 then now.Year + 1 else now.Year
end

local function addText(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	gradient.Rotation = 90
	gradient.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(120, 80, 20)
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = parent
end

local function stage(folder, Build, base: CFrame)
	local model = Build.model(folder, "CountdownStage")
	local glossy = { Color = rgb(15, 15, 20), Reflectance = 0.35 }
	local neon = { Color = GOLD, Material = Enum.Material.Neon, CanCollide = false }

	Build.cylinder(model, 0.6, 28, base * CFrame.new(0, 0.3, 0), glossy)
	Build.cylinder(model, 0.12, 28.6, base * CFrame.new(0, 0.06, 0), neon)

	local boardCenter = base * CFrame.new(0, 7.5, 0)
	local board = Build.part(model, Build.withShape(glossy, {
		Size = Vector3.new(22, 8, 0.6),
		CFrame = boardCenter,
		Material = Enum.Material.Glass,
	}))
	for _, y in { -4.15, 4.15 } do
		Build.part(model, Build.withShape(neon, { Size = Vector3.new(22.6, 0.3, 0.7), CFrame = boardCenter * CFrame.new(0, y, 0) }))
	end
	for _, x in { -11.15, 11.15 } do
		Build.part(model, Build.withShape(neon, { Size = Vector3.new(0.3, 8.6, 0.7), CFrame = boardCenter * CFrame.new(x, 0, 0) }))
	end
	for _, x in { -8, 8 } do
		Build.part(model, Build.withShape(glossy, { Size = Vector3.new(0.6, 3.2, 0.6), CFrame = base * CFrame.new(x, 2.2, 0.2) }))
	end
	Build.light(board, GOLD, 30, 2)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 2
	addText(gui, "HAPPY NEW YEAR", UDim2.fromScale(0.05, 0.06), UDim2.fromScale(0.9, 0.24), GOLD)
	addText(gui, tostring(newYear()), UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.64), GOLD)
	gui.Parent = board

	-- Glowing pillars on each side
	for _, x in { -14, 14 } do
		local pillar = Build.cylinder(model, 10, 0.8, base * CFrame.new(x, 5.6, 0), neon)
		Build.light(pillar, GOLD, 16, 1.5)
		Build.ball(model, 1.6, base * CFrame.new(x, 11.2, 0), neon)
	end
end

local function searchlight(folder, Build, base: CFrame, rng: Random)
	local model = Build.model(folder, "Searchlight")
	local metal = { Color = rgb(40, 40, 50), Material = Enum.Material.Metal }
	Build.cylinder(model, 1.6, 2.4, base * CFrame.new(0, 0.8, 0), metal)
	local head = Build.part(model, Build.withShape(metal, {
		Size = Vector3.new(1.6, 2.4, 1.6),
		CFrame = base * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(0, 0, math.rad(25)),
	}))

	local from = Instance.new("Attachment")
	from.Position = Vector3.new(0, 1.2, 0)
	from.Parent = head
	local to = Instance.new("Attachment")
	to.Position = Vector3.new(0, 160, 0)
	to.Parent = head

	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(rgb(230, 235, 255), rgb(190, 200, 255))
	beam.Transparency = NumberSequence.new(0.45, 1)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 1.4
	beam.Width1 = 14
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = head
	Build.tag(head, Build.Tags.Spin)
end

local function balloonBunch(folder, Build, base: CFrame, rng: Random)
	Build.part(folder, {
		Size = Vector3.new(0.7, 0.6, 0.7),
		CFrame = base * CFrame.new(0, 0.3, 0),
		Color = GOLD,
		Reflectance = 0.4,
	})
	local bunch = Build.model(folder, "Balloons")
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2
		local top = base * CFrame.new(math.cos(angle) * 1.3, rng:NextNumber(7, 9), math.sin(angle) * 1.3)
		Build.ellipsoid(bunch, Vector3.new(1.8, 2.2, 1.8), top, {
			Color = BALLOONS[rng:NextInteger(1, #BALLOONS)],
			Reflectance = 0.35,
			CanCollide = false,
		})
		Build.rod(bunch, base.Position, (top * CFrame.new(0, -1.1, 0)).Position, 0.05, {
			Color = rgb(240, 240, 240),
			CanCollide = false,
		})
	end
	Build.tag(bunch, Build.Tags.Bob)
end

return function(folder: Folder, Build)
	local rng = Random.new(101)
	local feature = Build.featureSpot()

	stage(folder, Build, feature)
	for _, offset in { Vector3.new(-20, 0, 4), Vector3.new(20, 0, 4), Vector3.new(-30, 0, -10), Vector3.new(30, 0, -10) } do
		searchlight(folder, Build, feature * CFrame.new(offset), rng)
	end
	for _, spot in Build.ring(8, 30, math.pi / 8, 3) do
		balloonBunch(folder, Build, spot, rng)
	end
end
