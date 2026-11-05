-- THE CONCOURSE: the Battlegrounds wing behind the hub's TEST CHAMBERS door
-- (DECISIONS.md 8, ArtDirection sections 3, 4, 6). A long, enclosed hall far from the hub
-- (Concourse.Center), reached by "Travel:Concourse" (MatchService teleports to
-- Concourse spawn, see ArenaService:concourseSpawn). Plan, 224 x 56 studs, 26 high:
--   floor     dark slate with a steel inlay down the middle and two fine lane lines
--   walls     ceramic-white lower band and charcoal upper band; gates 01-10 on the north
--             wall, 11-20 on the south wall, one every 20 studs
--   each gate a steel portal frame with a number plate above, a shuttered gate panel
--             carrying the Watch prompt, a thin status strip, and a status screen beside it
--             (FREE, or IN MATCH with the names, the mode and the elapsed time)
--   west end  the entrance: wing sign, terminals "Find a fight" (Window:Play, opens the Play
--             window on the client) and "Return to hub" (Travel:Lobby), a free-count screen
--   east end  a free-count screen and a hint on how to watch
--   ceiling   concrete slab, eleven steel ribs, ten light panels, two amber coves
-- Gate screens and Watch prompts are updated by Concourse.refresh(statuses), which
-- ArenaService calls when a chamber is reserved or released and once a second while any
-- chamber is busy (a task.delay chain, never a per-frame loop). Only changed text is written.
-- Part budget: 340 (about 270 in practice). Nothing here moves or is scripted.

local Common = require(script.Parent.Parent.Arenas.Common)

local Concourse = {}

Concourse.Center = Vector3.new(560, 0, 0)
Concourse.GateCount = 20
Concourse.PartBudget = 340

local M = Common.M
local rgb = Common.rgb

local LENGTH, WIDTH, HEIGHT = 220, 56, 26
local FLOOR_Y = 1

local COMBAT = rgb(224, 122, 58)
local FREE = rgb(95, 196, 138)
local WHITE = rgb(236, 232, 222)
local SLATE = rgb(46, 49, 55)
local STEEL = rgb(150, 156, 164)
local CERAMIC = rgb(222, 220, 212)
local CHARCOAL = rgb(92, 98, 108)
local SCREEN = rgb(16, 18, 22)

export type Status = {
	busy: boolean,
	mode: string?,
	names: { string }?,
	elapsed: number?,
	phase: string?,
}

export type Hooks = {
	-- A player pressed Watch at gate `number`
	watch: (player: Player, number: number) -> (),
}

export type Built = {
	model: Model,
	spawn: CFrame,
	refresh: (statuses: { Status }) -> (),
}

local DECOR = Common.GHOST

local function frameOf(position: Vector3, facing: Vector3?): CFrame
	if facing then
		return CFrame.lookAt(position, position + facing)
	end
	return CFrame.new(position)
end

local function label(parent: Instance, name: string, text: string, position: UDim2, size: UDim2, textSize: number, color: Color3, bold: boolean?): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.BackgroundTransparency = 1
	item.Position = position
	item.Size = size
	item.Text = text
	item.TextSize = textSize
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", if bold then Enum.FontWeight.Bold else Enum.FontWeight.Medium)
	item.Parent = parent
	return item
end

local function prompt(parent: Instance, actionText: string, objectText: string, distance: number, action: string?): ProximityPrompt
	local item = Instance.new("ProximityPrompt")
	item.ActionText = actionText
	item.ObjectText = objectText
	item.HoldDuration = 0
	item.MaxActivationDistance = distance
	item.RequiresLineOfSight = false
	-- E, F, Q and the gamepad face buttons are combat keys, so the world uses T / D-pad right
	item.KeyboardKeyCode = Enum.KeyCode.T
	item.GamepadKeyCode = Enum.KeyCode.DPadRight
	if action then
		item:SetAttribute("Action", action)
	end
	item.Parent = parent
	return item
end

local function shortNames(names: { string }?): string
	local text = table.concat(names or {}, ", ")
	if #text > 30 then
		text = string.sub(text, 1, 27) .. "..."
	end
	return text
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Concourse.build(parent: Instance, hooks: Hooks): Built
	local model = Instance.new("Model")
	model.Name = "Concourse"
	local c = Vector3.new(Concourse.Center.X, FLOOR_Y, Concourse.Center.Z)
	local function block(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, extra: { [string]: any }?, facing: Vector3?): BasePart
		return Common.block(model, name, size, frameOf(position, facing), color, material, extra)
	end

	-- Shell: floor, walls in two bands, ends, ceiling
	block("Floor", Vector3.new(LENGTH + 8, 4, WIDTH + 8), c - Vector3.new(0, 2, 0), SLATE, M.Slate)
	block("Inlay", Vector3.new(LENGTH - 20, 0.12, 2), c + Vector3.new(0, 0.06, 0), STEEL, M.Metal, DECOR)
	for _, z in { -10, 10 } do
		block("Lane", Vector3.new(LENGTH - 20, 0.1, 0.25), c + Vector3.new(0, 0.05, z), rgb(70, 74, 82), M.Metal, DECOR)
	end
	local halfL, halfW = LENGTH / 2, WIDTH / 2
	for _, sign in { 1, -1 } do
		block("Wall", Vector3.new(LENGTH + 8, 10, 4), c + Vector3.new(0, 4, sign * (halfW + 2)), CERAMIC, M.SmoothPlastic)
		block("Wall", Vector3.new(LENGTH + 8, HEIGHT - 9, 4), c + Vector3.new(0, 9 + (HEIGHT - 9) / 2, sign * (halfW + 2)), CHARCOAL, M.Concrete)
		block("Wall", Vector3.new(4, HEIGHT + 4, WIDTH + 8), c + Vector3.new(sign * (halfL + 2), HEIGHT / 2 - 2, 0), CHARCOAL, M.Concrete)
		-- Skirting along the long walls
		block("Skirting", Vector3.new(LENGTH, 1.2, 0.5), c + Vector3.new(0, 0.6, sign * (halfW - 0.25)), STEEL, M.Metal, DECOR)
	end
	block("Ceiling", Vector3.new(LENGTH + 8, 2, WIDTH + 8), c + Vector3.new(0, HEIGHT + 1, 0), rgb(70, 74, 82), M.Concrete)
	for step = -5, 5 do
		block("Rib", Vector3.new(2, 1.6, WIDTH), c + Vector3.new(step * 20, HEIGHT - 0.8, 0), STEEL, M.Metal, DECOR)
	end
	for step = -5, 4 do
		local panel = block("LightPanel", Vector3.new(14, 0.3, 3), c + Vector3.new(step * 20 + 10, HEIGHT - 0.2, 0), WHITE, M.Neon, DECOR)
		Common.surfaceLight(panel, Enum.NormalId.Bottom, rgb(255, 240, 222), 64, 1.5, 150)
	end
	for _, sign in { 1, -1 } do
		block("Cove", Vector3.new(LENGTH - 2, 0.3, 0.3), c + Vector3.new(0, HEIGHT - 2.2, sign * (halfW - 0.5)), COMBAT, M.Neon, DECOR)
	end

	-- Gates ----------------------------------------------------------------------------
	local gates = {}
	for number = 1, Concourse.GateCount do
		local north = number <= 10
		local index = (number - 1) % 10
		local x = -90 + index * 20
		local sideZ = if north then -halfW else halfW
		local facing = Vector3.new(0, 0, if north then 1 else -1)
		local inward = facing * 0.4
		local function place(depth: number, y: number, dx: number?): Vector3
			return c + Vector3.new(x + (dx or 0), y, sideZ) + facing * depth
		end
		local tag = string.format("%02d", number)

		-- Portal frame: two jambs and a lintel, proud of the wall
		for _, side in { -1, 1 } do
			block("GateJamb" .. tag, Vector3.new(1.2, 12, 1.6), place(0.8, 6, side * 4.6), STEEL, M.Metal, nil, facing)
		end
		block("GateLintel" .. tag, Vector3.new(10.4, 1.2, 1.6), place(0.8, 12.6), STEEL, M.Metal, nil, facing)
		-- The shuttered gate panel carries the Watch prompt
		local panel = block("Gate" .. tag, Vector3.new(8, 11.4, 0.4), place(0.2, 5.7) + inward * 0, rgb(30, 33, 38), M.Metal, nil, facing)
		for slat = 1, 5 do
			block("GateSlat" .. tag, Vector3.new(7.4, 0.15, 0.2), place(0.5, slat * 1.9), rgb(54, 58, 66), M.Metal, DECOR, facing)
		end
		local strip = block("GateStrip" .. tag, Vector3.new(7.4, 0.25, 0.2), place(0.5, 0.5), FREE, M.Neon, DECOR, facing)
		local watch = prompt(panel, "Watch", string.format("Chamber %02d", number), 12, nil)
		watch.Enabled = false
		watch.Triggered:Connect(function(player: Player)
			hooks.watch(player, number)
		end)

		-- Number plate above the gate
		local plate = block("GatePlate" .. tag, Vector3.new(6, 3, 0.4), place(0.2, 15.6), rgb(20, 22, 26), M.SmoothPlastic, DECOR, facing)
		Common.sign(plate, Enum.NormalId.Front, tag, WHITE, 40, 0)

		-- Status screen beside the gate, at eye height
		local screen = block("GateScreen" .. tag, Vector3.new(8, 5, 0.4), place(0.2, 6.5, 9.5), SCREEN, M.SmoothPlastic, DECOR, facing)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Status"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = screen
		local header = label(gui, "Header", string.format("CHAMBER %s", tag), UDim2.fromOffset(12, 6), UDim2.fromOffset(296, 28), 22, rgb(170, 176, 186), true)
		local state = label(gui, "State", "FREE", UDim2.fromOffset(12, 36), UDim2.fromOffset(296, 50), 40, FREE, true)
		local detail = label(gui, "Detail", "Open for a match", UDim2.fromOffset(12, 94), UDim2.fromOffset(296, 28), 22, WHITE, false)
		local people = label(gui, "People", "", UDim2.fromOffset(12, 124), UDim2.fromOffset(296, 28), 22, WHITE, false)
		local _ = header
		gates[number] = { strip = strip, watch = watch, state = state, detail = detail, people = people, last = "" }
	end

	-- West end: the entrance ----------------------------------------------------------------
	local west = c + Vector3.new(-halfL, 0, 0)
	local east = c + Vector3.new(halfL, 0, 0)
	local function endSign(origin: Vector3, direction: number, title: string, subtitle: string)
		local facing = Vector3.new(direction, 0, 0)
		local plate = block("WingSign", Vector3.new(30, 6, 0.5), origin + Vector3.new(0, 18, 0) + facing * 0.4, rgb(20, 22, 26), M.SmoothPlastic, DECOR, facing)
		Common.sign(plate, Enum.NormalId.Front, title, COMBAT, 40, 0)
		local small = block("WingSubtitle", Vector3.new(30, 2.6, 0.5), origin + Vector3.new(0, 13.6, 0) + facing * 0.4, rgb(20, 22, 26), M.SmoothPlastic, DECOR, facing)
		Common.sign(small, Enum.NormalId.Front, subtitle, WHITE, 40, 0)
	end
	endSign(west, 1, "TEST CHAMBERS", "Battleground concourse, chambers 01 to 20")
	endSign(east, -1, "CONCOURSE", "Busy gates have a Watch prompt")

	local summaries = {}
	local function summary(origin: Vector3, direction: number, dz: number)
		local facing = Vector3.new(direction, 0, 0)
		local screen = block("Summary", Vector3.new(10, 5, 0.4), origin + Vector3.new(0, 6.5, dz) + facing * 0.4, SCREEN, M.SmoothPlastic, DECOR, facing)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = screen
		label(gui, "Title", "CHAMBERS FREE", UDim2.fromOffset(14, 10), UDim2.fromOffset(372, 30), 24, rgb(170, 176, 186), true)
		local count = label(gui, "Count", "20 of 20", UDim2.fromOffset(14, 44), UDim2.fromOffset(372, 56), 46, FREE, true)
		label(gui, "Hint", "Green strip means free", UDim2.fromOffset(14, 128), UDim2.fromOffset(372, 28), 20, WHITE, false)
		table.insert(summaries, count)
	end
	summary(west, 1, 0)
	summary(east, -1, 0)

	-- Terminals at the west end: find a fight, and back to the hub
	local function terminal(name: string, dz: number, title: string, actionText: string, objectText: string, action: string)
		local facing = Vector3.new(1, 0, 0)
		local origin = west + Vector3.new(0.9, 0, dz)
		local body = block(name, Vector3.new(6, 6, 1.2), origin + Vector3.new(0, 3, 0), rgb(26, 30, 36), M.Metal, nil, facing)
		local screen = block(name .. "Screen", Vector3.new(5, 3, 0.2), origin + Vector3.new(0.7, 3.8, 0), SCREEN, M.SmoothPlastic, DECOR, facing)
		Common.sign(screen, Enum.NormalId.Front, title, WHITE, 40, 0)
		block(name .. "Strip", Vector3.new(5, 0.2, 0.2), origin + Vector3.new(0.7, 1.6, 0), COMBAT, M.Neon, DECOR, facing)
		prompt(body, actionText, objectText, 12, action)
	end
	terminal("FindFightTerminal", -14, "FIND A FIGHT", "Find a fight", "Matchmaking", "Window:Play")
	terminal("HubTerminal", 14, "RETURN TO HUB", "Return to hub", "Spawn", "Travel:Lobby")

	-- Benches down the middle, facing the gates
	for _, x in { -60, -20, 20, 60 } do
		block("Bench", Vector3.new(10, 1.2, 2.4), c + Vector3.new(x, 1.0, 0), rgb(34, 44, 62), M.Fabric)
		block("BenchBase", Vector3.new(9, 0.6, 1.6), c + Vector3.new(x, 0.3, 0), STEEL, M.Metal, DECOR)
	end

	local spawn = CFrame.lookAt(west + Vector3.new(14, 3, 0), west + Vector3.new(60, 3, 0))
	model.Parent = parent

	local freeLast = -1
	local function refresh(statuses: { Status })
		local free = 0
		for number, gate in gates do
			local status = statuses[number]
			local busy = status ~= nil and status.busy
			if not busy then
				free += 1
			end
			local key = if busy then `{status.mode}|{shortNames(status.names)}|{clock(status.elapsed or 0)}|{status.phase}` else "free"
			if key ~= gate.last then
				gate.last = key
				if busy then
					gate.state.Text = "IN MATCH"
					gate.state.TextColor3 = COMBAT
					gate.detail.Text = `{status.mode or "Match"}  {clock(status.elapsed or 0)}`
					gate.people.Text = shortNames(status.names)
					gate.strip.Color = COMBAT
				else
					gate.state.Text = "FREE"
					gate.state.TextColor3 = FREE
					gate.detail.Text = "Open for a match"
					gate.people.Text = ""
					gate.strip.Color = FREE
				end
				gate.watch.Enabled = busy
			end
		end
		if free ~= freeLast then
			freeLast = free
			for _, count in summaries do
				count.Text = `{free} of {Concourse.GateCount}`
			end
		end
	end

	return { model = model, spawn = spawn, refresh = refresh }
end

return Concourse
