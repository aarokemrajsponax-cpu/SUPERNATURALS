-- The Fighter Showcase (the "Powers" window): see every fighter before you pick one.
-- Left: eight fighter cards (role, owned or locked, exact price). Centre: a live 3D
-- preview of your character wearing the fighter's look for the chosen phase (drag to
-- rotate). Right: the dossier (fantasy, playstyle, difficulty, abilities with their exact
-- numbers, controls and slots, and a tab per phase with its evolve fee).
-- Nothing is bought or charged here. Picking a fighter for a match happens in Play;
-- a premium pass opens Roblox's own purchase prompt. Prices come from Config.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Selection = require(ReplicatedStorage.Shared.Config.Selection)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)
local Shell = require(script.Parent.Shell)
local Profile = require(script.Parent.Parent.Profile)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PowerRequest = Remotes:WaitForChild("PowerRequest") :: RemoteEvent

local Action = Protocol.PowerAction
local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local player = Players.LocalPlayer

local PowersWindow = {}

local LEFT_WIDTH = 252
local RIGHT_WIDTH = 352
local NARROW_BELOW = 860
local LINE = "  /  "

-- Shared helpers (the Play window uses them too) ------------------------------------------------

local function powerData(powerId: string): { [string]: any }
	return Profile.powerData(powerId)
end

local function isOwnerAccount(): boolean
	return player:GetAttribute(Attribute.IsOwner) == true
end

-- Does the player own this power outright (free powers always)?
local function owns(def): boolean
	if not def.premium then
		return true
	end
	if isOwnerAccount() then
		return true
	end
	local view = Profile.get()
	local passes = view and view.passes
	if typeof(passes) == "table" and passes[def.premium.pass] then
		return true
	end
	return powerData(def.id).owned == true
end

local function degreeOpen(def, degree: number): boolean
	return isOwnerAccount() or Powers.degreeUnlocked(def.id, degree, powerData(def.id))
end

local function savedLoadout(powerId: string, degree: number): { string }
	local view = Profile.get()
	local loadouts = view and view.loadouts
	local saved = typeof(loadouts) == "table" and loadouts[powerId]
	local list = typeof(saved) == "table" and saved[tostring(degree)]
	if typeof(list) == "table" then
		local ok, _, cleaned = Powers.validateLoadout(powerId, degree, list, powerData(powerId))
		if ok and cleaned then
			return cleaned
		end
	end
	return Powers.defaultLoadout(powerId, degree)
end

-- The fee to evolve into a phase (Money). Free for the owner and for Phase 1.
local function phaseFee(def, phase: number): number
	if phase <= 1 or isOwnerAccount() then
		return 0
	end
	return Selection.priceFor(def.id, phase, def.premium ~= nil)
end

local function feeText(fee: number): string
	return if fee <= 0 then "Free" else `{Components.formatNumber(fee)} Money`
end

-- A pass's Robux price and whether it is on sale (an id of 0 means not yet)
local function passInfo(def): (number?, boolean)
	local pass = def.premium and Monetization.Passes[def.premium.pass]
	if not pass then
		return nil, false
	end
	return pass.robux or def.premium.robux, typeof(pass.id) == "number" and pass.id > 0
end

PowersWindow.helpers = {
	owns = owns,
	degreeOpen = degreeOpen,
	savedLoadout = savedLoadout,
	phaseFee = phaseFee,
	feeText = feeText,
	isOwner = isOwnerAccount,
}

local function statsLine(ability, resourceName: string?): string
	local parts = {}
	if ability.kind == "Ultimate" then
		table.insert(parts, "Needs a full ultimate bar")
	else
		if (ability.cooldown or 0) > 0 then
			table.insert(parts, `{ability.cooldown}s cooldown`)
		end
		if (ability.cost or 0) > 0 then
			table.insert(parts, `{ability.cost} {resourceName or "energy"}`)
		end
	end
	if (ability.damage or 0) > 0 then
		table.insert(parts, `{ability.damage} damage`)
	end
	if (ability.range or 0) > 0 then
		table.insert(parts, `{ability.range} studs`)
	end
	if ability.defense == "Timing" then
		table.insert(parts, "Timing-bar defense")
	elseif ability.defense == "Prompt" then
		table.insert(parts, "Dodge or block prompt")
	elseif ability.defense == "Mash" then
		table.insert(parts, "Mash to escape")
	end
	return table.concat(parts, LINE)
end
PowersWindow.statsLine = statsLine

-- The 3D preview ----------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?)
	local item = make("Part", {
		Name = name,
		Size = size,
		CFrame = CFrame.new(offset),
		Color = color,
		Anchored = true,
		CanCollide = false,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	if shape then
		item.Shape = shape
	end
	return item
end

-- A plain stand-in figure for when the player has no character yet
local function dummy(color: Color3): Model
	local model = make("Model", { Name = "PreviewDummy" })
	local skin = Color3.fromRGB(214, 190, 164)
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), color)
	root.Transparency = 0
	part(model, "Head", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 4.7, 0), skin, Enum.PartType.Ball)
	part(model, "LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), color)
	part(model, "RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), color)
	part(model, "LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), Colors.Ink:Lerp(color, 0.3))
	part(model, "RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), Colors.Ink:Lerp(color, 0.3))
	model.PrimaryPart = root
	return model
end

-- The player's own character (a clone, with scripts and the Humanoid's name tag removed)
local function characterCopy(): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	if not ok or not copy then
		return nil
	end
	for _, item in copy:GetDescendants() do
		if item:IsA("BaseScript") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
		elseif item:IsA("Humanoid") then
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	if not copy.PrimaryPart then
		local root = copy:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			copy.PrimaryPart = root
		end
	end
	return if copy.PrimaryPart then copy else nil
end

local function powerModule(powerId: string): any?
	local ok, ClientPowers = pcall(function()
		return require(script.Parent.Parent.Powers)
	end)
	if not ok then
		return nil, nil
	end
	return ClientPowers.module(powerId), ClientPowers
end

type Preview = {
	frame: Frame,
	look: (powerId: string, phase: number) -> (),
	demo: (abilityId: string?) -> boolean,
	stop: () -> (),
	hasAppearance: () -> boolean,
}

-- Builds the viewport inside `parent`. look(power, phase) rebuilds the figure with the power's
-- appearance applied; drag rotates; it idles with a slow turn and a breath.
local function buildPreview(parent: Instance): Preview
	local stage = make("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		Parent = parent,
	}, { Components.corner(Theme.Corner), Components.stroke(Colors.Stroke, 1, 0.6) })
	-- The plinth: a flat disc in the fighter's colour under the figure
	local plinth = make("Frame", {
		Name = "Plinth",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.62, 0.07),
		BackgroundColor3 = Colors.Cyan,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = stage,
	}, { make("UICorner", { CornerRadius = UDim.new(0.5, 0) }), Components.stroke(Colors.Cyan, 1, 0.5) })
	local viewport = make("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(120, 130, 150),
		LightColor = Color3.fromRGB(255, 244, 230),
		LightDirection = Vector3.new(-0.4, -0.7, -0.6),
		ZIndex = 2,
		Parent = stage,
	})
	local world = make("WorldModel", { Parent = viewport })
	local camera = make("Camera", { FieldOfView = 34, Parent = viewport })
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 4.6, 12), Vector3.new(0, 3.2, 0))
	viewport.CurrentCamera = camera

	local state = {
		model = nil :: Model?,
		cleanup = nil :: (() -> ())?,
		yaw = 0,
		dragging = false,
		lunge = 0,
		clock = 0,
		powerId = "",
		hasAppearance = false,
		kit = nil :: any,
		mod = nil :: any,
	}

	local function clear()
		if state.cleanup then
			pcall(state.cleanup)
			state.cleanup = nil
		end
		if state.model then
			state.model:Destroy()
			state.model = nil
		end
	end

	local function place()
		local model = state.model
		if not model then
			return
		end
		local breath = math.sin(state.clock * 1.6) * 0.06
		local lunge = math.sin(math.clamp(state.lunge, 0, 1) * math.pi) * 1.8
		local frame = CFrame.new(0, breath, lunge) * CFrame.Angles(0, math.rad(state.yaw), 0)
		pcall(function()
			model:PivotTo(frame)
		end)
	end

	local function look(powerId: string, phase: number)
		clear()
		local def = Powers.get(powerId)
		if not def then
			return
		end
		state.powerId = powerId
		local model = characterCopy() or dummy(def.colors.primary)
		model.Name = "PreviewFighter"
		model:SetAttribute(Attribute.Power, powerId)
		model:SetAttribute(Attribute.Degree, phase)
		local count = Powers.degreeCount(powerId)
		model:SetAttribute(Attribute.Phase, math.clamp((phase - 1) / math.max(count - 1, 1), 0.05, 1))
		model.Parent = world
		state.model = model
		stage.Name = "Stage"
		plinth.BackgroundColor3 = def.colors.primary
		plinth:FindFirstChildOfClass("UIStroke").Color = def.colors.primary
		viewport.LightColor = Color3.fromRGB(255, 244, 230):Lerp(def.colors.primary, 0.18)
		viewport.Ambient = Color3.fromRGB(110, 120, 140):Lerp(def.colors.primary, 0.22)

		local mod, ClientPowers = powerModule(powerId)
		state.mod = mod
		state.hasAppearance = mod ~= nil and typeof(mod.appearance) == "function"
		if mod and ClientPowers then
			local okKit, kit = pcall(ClientPowers.kit, model, powerId)
			if okKit then
				state.kit = kit
				if state.hasAppearance then
					local ok, cleanup = pcall(mod.appearance, kit)
					if ok and typeof(cleanup) == "function" then
						state.cleanup = cleanup
					end
				end
			end
		end
		place()
	end

	local function demo(abilityId: string?): boolean
		state.lunge = 0.001
		local mod, kit = state.mod, state.kit
		local predicted = false
		if mod and kit and abilityId and typeof(mod.predict) == "table" and typeof(mod.predict[abilityId]) == "function" then
			predicted = pcall(mod.predict[abilityId], kit)
		end
		return predicted
	end

	-- Drag to rotate (mouse or touch)
	local dragFrom: number? = nil
	stage.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragFrom = input.Position.X
			state.dragging = true
		end
	end)
	local changed = UserInputService.InputChanged:Connect(function(input)
		if dragFrom and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			state.yaw += (input.Position.X - dragFrom) * 0.6
			dragFrom = input.Position.X
			place()
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragFrom = nil
			state.dragging = false
		end
	end)
	local beat = RunService.Heartbeat:Connect(function(dt)
		state.clock += dt
		if not state.dragging and state.model then
			state.yaw += dt * 14
		end
		if state.lunge > 0 then
			state.lunge += dt * 1.4
			if state.lunge >= 1 then
				state.lunge = 0
			end
		end
		place()
	end)
	local function stop()
		beat:Disconnect()
		changed:Disconnect()
		ended:Disconnect()
		clear()
	end
	stage.Destroying:Connect(stop)
	return {
		frame = stage,
		look = look,
		demo = demo,
		stop = stop,
		hasAppearance = function()
			return state.hasAppearance
		end,
	}
end

-- The window --------------------------------------------------------------------------------------

local function swatch(parent: Instance, color: Color3, order: number)
	make("Frame", {
		Name = "Swatch",
		LayoutOrder = order,
		Size = UDim2.fromOffset(28, 14),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Components.corner(Theme.TinyCorner), Components.stroke(Colors.Stroke, 1, 0.4) })
end

local function difficultyRow(parent: Instance, difficulty: number, accent: Color3, order: number)
	local row = make("Frame", { Name = "Difficulty", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = parent })
	Components.list(row, Space.XS, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
	Components.text({ Text = "Difficulty", Style = "label", Color = Colors.TextMuted, Size = UDim2.fromOffset(84, 20), LayoutOrder = 0, Parent = row })
	for index = 1, 5 do
		make("Frame", {
			Name = "Pip",
			LayoutOrder = index,
			Size = UDim2.fromOffset(18, 8),
			BackgroundColor3 = if index <= difficulty then accent else Colors.Stroke,
			BackgroundTransparency = if index <= difficulty then 0 else 0.5,
			BorderSizePixel = 0,
			Parent = row,
		}, { Components.corner(Theme.TinyCorner) })
	end
	Components.text({ Text = `{difficulty} of 5`, Style = "number", Color = Colors.TextDim, Size = UDim2.fromOffset(60, 20), LayoutOrder = 9, Parent = row })
end

function PowersWindow.register()
	Shell.registerWindow("Powers", {
		title = "Fighters",
		label = "FIGHTERS",
		icon = "star",
		order = 2,
		size = Vector2.new(1160, 640),
		accent = Colors.Purple,
		build = function(body: Frame, api)
			local selectedPower = Powers.Default
			local selectedPhase = 1
			local cards: { [string]: any } = {}
			local pane = "preview"

			local fighters = make("Frame", { Name = "PowerListPane", BackgroundTransparency = 1, Parent = body })
			local list = Components.scroll({ Name = "PowerList", Size = UDim2.fromScale(1, 1), Padding = 2, Parent = fighters })
			Components.list(list, Space.S)
			local centre = make("Frame", { Name = "PreviewPane", BackgroundTransparency = 1, Parent = body })
			local right = make("Frame", { Name = "DossierPane", BackgroundTransparency = 1, Parent = body })
			local detail = Components.scroll({ Name = "PowerDetail", Size = UDim2.new(1, 0, 1, -(Theme.Size.Control + Space.M)), Padding = 2, Parent = right })
			Components.list(detail, Space.M)
			local actions = make("Frame", {
				Name = "PowerActions",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, Theme.Size.Control),
				BackgroundTransparency = 1,
				Parent = right,
			})
			Components.list(actions, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })

			-- Centre: the stage, a caption under it, and the demo button
			local stageHolder = make("Frame", { Name = "StageHolder", Size = UDim2.new(1, 0, 1, -(Theme.Size.Control + Space.M + 52)), BackgroundTransparency = 1, Parent = centre })
			local preview = buildPreview(stageHolder)
			local caption = Components.text({
				Name = "Caption",
				Style = "caption",
				Color = Colors.TextDim,
				Wrap = true,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -(Theme.Size.Control + Space.M)),
				Size = UDim2.new(1, 0, 0, 44),
				Parent = centre,
			})
			local demoIndex = 0
			local demoButton = Components.button("Show an ability", {
				Name = "Demo",
				Variant = "Secondary",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, Theme.Size.Control),
				Parent = centre,
			}, function()
				local def = Powers.get(selectedPower)
				local ids = Powers.available(selectedPower, selectedPhase)
				local ult = Powers.ultimateOf(selectedPower, selectedPhase)
				if ult then
					table.insert(ids, ult)
				end
				if #ids == 0 then
					return
				end
				demoIndex = demoIndex % #ids + 1
				local ability = Powers.abilityFor(selectedPower, ids[demoIndex], selectedPhase)
				preview.demo(ids[demoIndex])
				caption.Text = `Demonstration: {ability and ability.name or ids[demoIndex]}. {def.name} in Phase {selectedPhase}. Drag the figure to turn it.`
			end)

			-- Layout: three columns when wide, one pane at a time with a switcher when narrow
			local tabsHolder = make("Frame", { Name = "PaneTabs", Size = UDim2.new(1, 0, 0, Theme.Size.Control), BackgroundTransparency = 1, Visible = false, Parent = body })
			local paneTabs
			local function layout()
				local ok, size = pcall(function()
					return body.AbsoluteSize
				end)
				if not ok then
					-- No layout yet (a stand-in engine): estimate from the screen
					local view = workspace.CurrentCamera.ViewportSize
					size = Vector2.new(math.min(1120, view.X - 140), math.min(560, view.Y - 140))
				end
				local w, h = size.X, size.Y
				if w <= 0 then
					return
				end
				if w >= NARROW_BELOW then
					tabsHolder.Visible = false
					fighters.Visible, centre.Visible, right.Visible = true, true, true
					local rightWidth = math.min(RIGHT_WIDTH, math.floor(w * 0.34))
					local middle = w - LEFT_WIDTH - rightWidth - Space.L * 2
					fighters.Position, fighters.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(LEFT_WIDTH, h)
					centre.Position, centre.Size = UDim2.fromOffset(LEFT_WIDTH + Space.L, 0), UDim2.fromOffset(middle, h)
					right.Position, right.Size = UDim2.fromOffset(w - rightWidth, 0), UDim2.fromOffset(rightWidth, h)
				else
					tabsHolder.Visible = true
					local top = Theme.Size.Control + Space.S
					for id, frame in { fighters = fighters, preview = centre, dossier = right } do
						frame.Visible = id == pane
						frame.Position, frame.Size = UDim2.fromOffset(0, top), UDim2.fromOffset(w, h - top)
					end
				end
			end
			paneTabs = Components.segmented(tabsHolder, {
				{ id = "fighters", label = "Fighters" },
				{ id = "preview", label = "Preview" },
				{ id = "dossier", label = "Dossier" },
			}, pane, function(id)
				pane = id
				layout()
			end)
			body:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

			-- The dossier -----------------------------------------------------------------------
			local function section(order: number, title: string): Frame
				local frame = make("Frame", { Name = "Section_" .. order, LayoutOrder = order, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = detail })
				Components.list(frame, Space.S)
				Components.text({ Text = title, Style = "overline", Color = Colors.TextMuted, LayoutOrder = 0, Wrap = true, Parent = frame })
				return frame
			end

			local function abilityRow(parent: Instance, order: number, def, ability, accent: Color3)
				local row = make("Frame", {
					Name = "Ability_" .. ability.id,
					LayoutOrder = order,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Colors.PanelLight,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					Parent = parent,
				}, {
					Components.corner(Theme.SmallCorner),
					Components.stroke(Colors.Stroke, 1, 0.8),
					Components.padding(Space.S, Space.S, Space.S, 52),
				})
				local tile = Components.iconTile(Icons.forAbility(ability), 36, accent)
				tile.Position = UDim2.fromOffset(-44, 0)
				tile.Parent = row
				Components.list(row, 2)
				local kind = if ability.kind == "Ultimate" then "Ultimate" else ability.kind or "Ability"
				Components.text({ Text = `{ability.name}`, Style = "strong", LayoutOrder = 1, Wrap = true, Parent = row })
				Components.text({ Text = kind, Style = "caption", Color = accent, LayoutOrder = 2, Wrap = true, Parent = row })
				local numbers = statsLine(ability, def.resource and def.resource.name)
				if numbers ~= "" then
					Components.text({ Text = numbers, Style = "number", TextSize = 14, Color = Colors.TextDim, LayoutOrder = 3, Wrap = true, Parent = row })
				end
				if typeof(ability.description) == "string" then
					Components.text({ Text = ability.description, Style = "caption", Color = Colors.TextMuted, LayoutOrder = 4, Wrap = true, Parent = row })
				end
			end

			local renderDossier
			function renderDossier()
				for _, child in detail:GetChildren() do
					if not child:IsA("UIListLayout") then
						child:Destroy()
					end
				end
				local def = Powers.get(selectedPower)
				if not def then
					return
				end
				local accent = def.colors.primary
				local count = Powers.degreeCount(selectedPower)
				local ownsIt = owns(def)
				local order = 0
				local function nextOrder()
					order += 1
					return order
				end

				-- Title block
				local head = make("Frame", { Name = "Head", LayoutOrder = nextOrder(), Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = detail })
				Components.list(head, Space.XS)
				if def.premium then
					Components.text({ Text = if ownsIt then "Premium fighter, owned" else "Premium fighter", Style = "overline", Color = Colors.Gold, LayoutOrder = 1, Wrap = true, Parent = head })
				end
				Components.text({ Text = def.name, Style = "title", Track = true, TextSize = 20, LayoutOrder = 2, Wrap = true, Parent = head })
				Components.text({ Text = def.tagline, Style = "strong", Color = accent, LayoutOrder = 3, Wrap = true, Parent = head })
				Components.text({ Text = def.description, Style = "body", Color = Colors.TextDim, LayoutOrder = 4, Wrap = true, Parent = head })
				Components.text({ Text = `Playstyle: {def.style}`, Style = "label", Color = Colors.Text, LayoutOrder = 5, Wrap = true, Parent = head })
				difficultyRow(head, def.difficulty or 3, accent, 6)

				-- Premium introduction: name and title, colour theme, aura, phases
				if def.premium then
					local intro = make("Frame", {
						Name = "PremiumIntro",
						LayoutOrder = nextOrder(),
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundColor3 = accent,
						BackgroundTransparency = 0.88,
						BorderSizePixel = 0,
						Parent = detail,
					}, {
						Components.corner(Theme.SmallCorner),
						Components.stroke(Colors.Gold, 1, 0.55),
						Components.padding(Space.M),
					})
					Components.list(intro, Space.S)
					Components.text({ Text = `{def.name}: {def.tagline}`, Style = "strong", Color = Colors.Gold, LayoutOrder = 1, Wrap = true, Parent = intro })
					local theme = make("Frame", { Name = "Theme", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = intro })
					Components.list(theme, Space.XS, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
					Components.text({ Text = "Colour theme", Style = "label", Color = Colors.TextMuted, Size = UDim2.fromOffset(110, 18), LayoutOrder = 0, Parent = theme })
					swatch(theme, def.colors.primary, 1)
					swatch(theme, def.colors.secondary, 2)
					swatch(theme, def.colors.accent, 3)
					local names = {}
					for index = 1, count do
						table.insert(names, `{index} {def.degrees[index].name}`)
					end
					Components.text({ Text = `Phases: {table.concat(names, LINE)}`, Style = "caption", Color = Colors.TextDim, LayoutOrder = 3, Wrap = true, Parent = intro })
					Components.text({ Text = if preview.hasAppearance() then "Its aura plays on the figure in the preview." else "Its look is shown on the figure in the preview.", Style = "caption", Color = Colors.TextDim, LayoutOrder = 4, Wrap = true, Parent = intro })
					local robux, onSale = passInfo(def)
					local how = if ownsIt then "You own this fighter. It works in every mode."
						else if robux then `Unlock with a one-time Robux pass: R$ {Components.formatNumber(robux)}.{if onSale then "" else " Available soon."} Free to try in Training and CPU Practice.`
						else "Unlocked with a pass. Free to try in Training and CPU Practice."
					Components.text({ Text = how, Style = "caption", Color = Colors.TextDim, LayoutOrder = 5, Wrap = true, Parent = intro })
				end

				-- Phase tabs
				local phases = section(nextOrder(), "PHASES")
				local options = {}
				for index = 1, count do
					table.insert(options, { id = tostring(index), label = `Phase {index}` })
				end
				Components.segmented(phases, options, tostring(selectedPhase), function(id)
					selectedPhase = tonumber(id) or 1
					preview.look(selectedPower, selectedPhase)
					demoIndex = 0
					caption.Text = `{def.name}, Phase {selectedPhase}: {def.degrees[selectedPhase].name}.`
					renderDossier()
				end, { LayoutOrder = 1, Name = "PhaseTabs" })
				local degreeDef = def.degrees[selectedPhase]
				local fee = phaseFee(def, selectedPhase)
				local money = Profile.currency("money")
				local open = degreeOpen(def, selectedPhase)
				local card = make("Frame", {
					Name = "PhaseCard",
					LayoutOrder = 2,
					Size = UDim2.fromScale(1, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Colors.PanelLight,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					Parent = phases,
				}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Stroke, 1, 0.8), Components.padding(Space.M) })
				Components.list(card, Space.XS)
				Components.text({ Text = `Phase {selectedPhase}: {degreeDef.name}`, Style = "strong", LayoutOrder = 1, Wrap = true, Parent = card })
				Components.text({ Text = degreeDef.description, Style = "caption", Color = Colors.TextDim, LayoutOrder = 2, Wrap = true, Parent = card })
				local feeLine, feeColor
				if selectedPhase == 1 then
					feeLine, feeColor = "Evolve fee: none. Every match starts here.", Colors.Success
				elseif fee <= 0 then
					feeLine, feeColor = "Evolve fee: free for you.", Colors.Success
				elseif money >= fee then
					feeLine, feeColor = `Evolve fee: {feeText(fee)}. You have {Components.formatNumber(money)}, enough.`, Colors.Success
				else
					feeLine, feeColor = `Evolve fee: {feeText(fee)}. You have {Components.formatNumber(money)}, {Components.formatNumber(fee - money)} short.`, Colors.Warning
				end
				Components.text({ Text = feeLine, Style = "label", Color = feeColor, LayoutOrder = 3, Wrap = true, Parent = card })
				local unlockLine
				if open then
					unlockLine = "Unlocked."
				else
					local unlock = degreeDef.unlock
					local bits = {}
					if unlock and unlock.mastery then
						table.insert(bits, `reach mastery level {unlock.mastery}`)
					end
					if unlock and unlock.money then
						table.insert(bits, `pay {Components.formatNumber(unlock.money)} Money`)
					end
					unlockLine = `Locked: {table.concat(bits, " or ")}.`
				end
				Components.text({ Text = unlockLine, Style = "caption", Color = if open then Colors.TextDim else Colors.Warning, LayoutOrder = 4, Wrap = true, Parent = card })
				Components.text({
					Text = "Matches start in Phase 1; evolve during the fight with T once the meter is full. A fee lasts for that match only. Training is free.",
					Style = "caption",
					Color = Colors.TextMuted,
					LayoutOrder = 5,
					Wrap = true,
					Parent = card,
				})

				-- Abilities with exact numbers
				local abilities = section(nextOrder(), `ABILITIES IN PHASE {selectedPhase}`)
				local ids = Powers.available(selectedPower, selectedPhase)
				local ult = Powers.ultimateOf(selectedPower, selectedPhase)
				if ult then
					table.insert(ids, ult)
				end
				for index, abilityId in ids do
					local ability = Powers.abilityFor(selectedPower, abilityId, selectedPhase)
					if ability then
						abilityRow(abilities, index, def, ability, accent)
					end
				end

				-- Controls and slots
				local controls = section(nextOrder(), "CONTROLS AND SLOTS")
				local slots = degreeDef.slots or 3
				Components.text({ Text = `{slots} ability slots in this phase, on keys 1 to {slots}. Pick which abilities fill them in Play.`, Style = "caption", Color = Colors.TextDim, LayoutOrder = 1, Wrap = true, Parent = controls })
				local keys = Components.keyRow({
					{ key = "M1", label = "Light attack" },
					{ key = "E", label = "Heavy attack" },
					{ key = "F", label = "Block" },
					{ key = "Q", label = "Dodge" },
					{ key = "T", label = "Evolve" },
					{ key = "1-" .. slots, label = "Abilities" },
				}, { LayoutOrder = 2 })
				keys.Parent = controls

				-- Actions
				for _, child in actions:GetChildren() do
					if not child:IsA("UIListLayout") then
						child:Destroy()
					end
				end
				local robux, onSale = passInfo(def)
				if def.premium and not ownsIt then
					local label = if onSale then `Unlock: R$ {Components.formatNumber(robux or 0)}` else "Available soon"
					local buy = Components.button(label, { Name = "Unlock", Variant = "Primary", Size = UDim2.new(0.5, -Space.XS, 1, 0), Parent = actions }, function()
						PowerRequest:FireServer(Action.PromptPass, def.id)
					end)
					if not onSale then
						Components.setDisabled(buy, true, "This pass is not on sale yet")
					end
				end
				Components.button("Choose in Play", { Name = "ChooseInPlay", Variant = if def.premium and not ownsIt then "Secondary" else "Primary", Size = if def.premium and not ownsIt then UDim2.new(0.5, -Space.XS, 1, 0) else UDim2.fromScale(1, 1), Parent = actions }, function()
					Shell.open("Play", { fighter = selectedPower })
				end)
			end

			-- The cards -------------------------------------------------------------------------------
			local function renderCards()
				for _, entry in cards do
					entry.frame:Destroy()
				end
				table.clear(cards)
				local view = Profile.get()
				local equipped = view and view.selected
				for order, powerId in Powers.Order do
					local def = Powers.get(powerId)
					if def then
						local ownsIt = owns(def)
						local chip, chipColor = "FREE", Colors.TextMuted
						local price: any, priceText: string? = nil, nil
						if typeof(equipped) == "table" and equipped.power == powerId then
							chip, chipColor = "EQUIPPED", Colors.Success
						elseif def.premium then
							chip, chipColor = if ownsIt then "OWNED" else "PREMIUM", Colors.Gold
						end
						if def.premium and not ownsIt then
							local robux = passInfo(def)
							price = if robux then { robux = robux } else nil
							priceText = if robux then nil else "Available soon"
						else
							priceText = if def.premium then "Owned" else "Free"
						end
						local frame, card = Components.storeCard({
							Name = def.name,
							LayoutOrder = order,
							Subtitle = def.style,
							Icon = Icons.sigil(powerId),
							Accent = def.colors.primary,
							Chip = chip,
							ChipColor = chipColor,
							Price = price,
							PriceText = priceText,
							Premium = def.premium ~= nil,
							Locked = def.premium ~= nil and not ownsIt,
							Selected = powerId == selectedPower,
							Size = UDim2.new(1, -4, 0, 96),
							onClick = function()
								selectedPower = powerId
								selectedPhase = 1
								demoIndex = 0
								for id, entry in cards do
									entry.card.setSelected(id == powerId)
								end
								preview.look(powerId, 1)
								caption.Text = `{def.name}: {def.tagline}. Drag the figure to turn it.`
								renderDossier()
								if (pcall(function() return body.AbsoluteSize.X end) and body.AbsoluteSize.X or NARROW_BELOW) < NARROW_BELOW then
									pane = "preview"
									paneTabs.set("preview", false)
									layout()
								end
							end,
						})
						frame.Name = "Fighter_" .. powerId
						frame.Parent = list
						cards[powerId] = { frame = frame, card = card }
					end
				end
			end

			local function refreshAll()
				renderCards()
				preview.look(selectedPower, selectedPhase)
				renderDossier()
				layout()
			end
			refreshAll()
			body.Destroying:Connect(preview.stop)

			return {
				onOpen = function(args)
					if typeof(args) == "table" and typeof(args.power) == "string" and Powers.get(args.power) then
						selectedPower = args.power
						selectedPhase = 1
					end
					PowerRequest:FireServer(Action.State)
					refreshAll()
				end,
				onClose = function() end,
				focus = function()
					return cards[selectedPower] and cards[selectedPower].frame
				end,
			}
		end,
	})
end

return PowersWindow
