-- PLAYER BASE STREET: the indoor residential promenade behind the hub's PLAYER BASE STREET
-- door (DECISIONS.md 8; ArtDirection sections 2, 3, 6). Built once, far from the hub
-- (Homes.StreetCenter), a calm, warm-dim corridor of apartment doors. Plan, 200 x 24, 14 high:
--   floor     dark slate with a steel inlay and two fine lines; a warm timber runner
--   walls     ceramic-white lower band and walnut-toned upper band; 12 doors on the north wall
--             (slots 1-12) and 12 on the south wall (slots 13-24), one every 15 studs
--   each door steel frame, walnut leaf, a nameplate (slot number and the owner's name, or
--             VACANT), a thin status strip (green when lived in, dim when vacant), a sconce
--   west end  arrival: wing sign and a "Return to hub" prompt
--   east end  a small seating bay with planters and a bench
--   ceiling   concrete slab, steel ribs, warm light panels
-- A door's ProximityPrompt carries no "Action" attribute: BaseService connects to its
-- Triggered event on the server (own door opens; a friend's opens for friends only).
-- BaseStreet.setDoor(slot, ownerName?) is called when a base is created or removed (an event,
-- never a loop). Nothing here moves.
-- Part budget: Homes.StreetPartBudget (560); about 330 in practice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script.Parent.Parent.Arenas.Common)
local Homes = require(ReplicatedStorage.Shared.Config.Homes)

local BaseStreet = {}

BaseStreet.PartBudget = Homes.StreetPartBudget

local M = Common.M
local rgb = Common.rgb
local DECOR = Common.GHOST

local LENGTH, WIDTH, HEIGHT = 200, 24, 14
local PITCH = 15
local PER_SIDE = Homes.Slots // 2

local PERSONAL = rgb(95, 196, 138)
local VACANT = rgb(70, 76, 86)
local WARM = rgb(255, 200, 130)
local SLATE = rgb(46, 49, 55)
local STEEL = rgb(150, 156, 164)
local CERAMIC = rgb(222, 220, 212)
local WALNUT = rgb(96, 64, 42)
local PANEL = rgb(104, 76, 56)
local CONCRETE = rgb(78, 80, 86)

export type Door = { prompt: ProximityPrompt, label: TextLabel, strip: BasePart, front: CFrame }
export type Built = {
	model: Model,
	spawn: CFrame,
	doors: { [number]: Door },
	returnPrompt: ProximityPrompt,
	setDoor: (slot: number, ownerName: string?) -> (),
	doorFront: (slot: number) -> CFrame,
}

-- A world prompt (T / D-pad right: E, F, Q and the face buttons are combat keys). No Action
-- attribute: the server reads Triggered itself.
function BaseStreet.prompt(parent: Instance, actionText: string, objectText: string, distance: number?): ProximityPrompt
	local proximity = Instance.new("ProximityPrompt")
	proximity.ActionText = actionText
	proximity.ObjectText = objectText
	proximity.HoldDuration = 0
	proximity.MaxActivationDistance = distance or 10
	proximity.RequiresLineOfSight = false
	proximity.KeyboardKeyCode = Enum.KeyCode.T
	proximity.GamepadKeyCode = Enum.KeyCode.DPadRight
	proximity.Parent = parent
	return proximity
end

function BaseStreet.build(parent: Instance): Built
	local model = Instance.new("Model")
	model.Name = "BaseStreet"
	local c = Homes.StreetCenter
	local function block(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, extra: { [string]: any }?, facing: Vector3?): BasePart
		local at = c + offset
		local frame = if facing then CFrame.lookAt(at, at + facing) else CFrame.new(at)
		return Common.block(model, name, size, frame, color, material, extra)
	end
	local half = LENGTH / 2

	-- Shell
	block("Floor", Vector3.new(LENGTH + 4, 2, WIDTH + 4), Vector3.new(0, -1, 0), SLATE, M.Slate)
	block("Inlay", Vector3.new(LENGTH - 16, 0.12, 1.2), Vector3.new(0, 0.06, 0), STEEL, M.Metal, DECOR)
	block("Runner", Vector3.new(LENGTH - 24, 0.1, 5), Vector3.new(0, 0.05, 0), rgb(112, 72, 46), M.WoodPlanks, DECOR)
	for _, z in { -7, 7 } do
		block("Line", Vector3.new(LENGTH - 16, 0.1, 0.2), Vector3.new(0, 0.05, z), rgb(70, 74, 82), M.Metal, DECOR)
	end
	for _, side in { -1, 1 } do
		block("WallLow", Vector3.new(LENGTH + 4, 5, 2), Vector3.new(0, 2.5, side * (WIDTH / 2 + 1)), CERAMIC, M.SmoothPlastic)
		block("WallHigh", Vector3.new(LENGTH + 4, HEIGHT - 5, 2), Vector3.new(0, 5 + (HEIGHT - 5) / 2, side * (WIDTH / 2 + 1)), PANEL, M.Wood)
		block("Cap", Vector3.new(2, HEIGHT, WIDTH), Vector3.new(side * (half + 1), HEIGHT / 2, 0), PANEL, M.Wood)
		block("Skirting", Vector3.new(LENGTH, 0.5, 0.3), Vector3.new(0, 0.25, side * (WIDTH / 2 - 0.15)), STEEL, M.Metal, DECOR)
	end
	block("Ceiling", Vector3.new(LENGTH + 4, 1.5, WIDTH + 4), Vector3.new(0, HEIGHT + 0.75, 0), CONCRETE, M.Concrete)
	for i = 0, 10 do
		local x = -half + 10 + i * ((LENGTH - 20) / 10)
		block("Rib", Vector3.new(1.2, 1, WIDTH), Vector3.new(x, HEIGHT - 0.5, 0), STEEL, M.Metal, DECOR)
		local panel = block("LightPanel", Vector3.new(6, 0.2, 4), Vector3.new(x + 4, HEIGHT - 0.1, 0), rgb(255, 232, 196), M.Neon, DECOR)
		if i % 3 == 1 then
			Common.light(panel, WARM, 26, 0.9, false)
		end
	end
	for _, side in { -1, 1 } do
		block("Cove", Vector3.new(LENGTH - 8, 0.2, 0.3), Vector3.new(0, HEIGHT - 1.2, side * (WIDTH / 2 - 0.4)), rgb(232, 162, 74), M.Neon, DECOR)
	end

	-- Doors
	local doors: { [number]: Door } = {}
	local function doorFrame(slot: number): CFrame
		local index = (slot - 1) % PER_SIDE
		local side = if slot <= PER_SIDE then -1 else 1 -- north wall is -Z
		local x = -half + 18 + index * PITCH
		return CFrame.lookAt(c + Vector3.new(x, 0, side * (WIDTH / 2)), c + Vector3.new(x, 0, 0))
	end
	for slot = 1, Homes.Slots do
		local frame = doorFrame(slot)
		local function put(name: string, size: Vector3, local_: Vector3, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
			return Common.block(model, name, size, frame * CFrame.new(local_), color, material, extra)
		end
		-- frame.LookVector points into the street; local +Z points back into the wall
		put("JambL", Vector3.new(0.6, 9.4, 0.8), Vector3.new(-3, 4.7, -0.3), STEEL, M.Metal)
		put("JambR", Vector3.new(0.6, 9.4, 0.8), Vector3.new(3, 4.7, -0.3), STEEL, M.Metal)
		put("Lintel", Vector3.new(6.6, 0.6, 0.8), Vector3.new(0, 9.4, -0.3), STEEL, M.Metal)
		local leaf = put("Door" .. slot, Vector3.new(5.4, 9, 0.5), Vector3.new(0, 4.5, 0.05), WALNUT, M.Wood)
		put("Handle", Vector3.new(0.25, 1.6, 0.25), Vector3.new(2, 4.5, -0.3), rgb(184, 115, 63), M.Metal, DECOR)
		local strip = put("Status", Vector3.new(0.3, 7, 0.2), Vector3.new(-3.8, 4.5, -0.15), VACANT, M.Neon, DECOR)
		local plate = put("Plate", Vector3.new(6.4, 1.6, 0.3), Vector3.new(0, 11, -0.2), rgb(26, 28, 34), M.SmoothPlastic)
		local gui = Common.sign(plate, Enum.NormalId.Front, "VACANT", rgb(150, 156, 164), 40, 0)
		local label = gui:FindFirstChildWhichIsA("TextLabel") :: TextLabel
		label.Text = string.format("%02d  VACANT", slot)
		local sconce = put("Sconce", Vector3.new(0.5, 1.2, 0.5), Vector3.new(4.9, 7.5, -0.2), rgb(184, 115, 63), M.Metal, DECOR)
		if slot % 2 == 1 then
			Common.light(sconce, WARM, 12, 0.7, false)
		end
		local proximity = BaseStreet.prompt(leaf, "Open door", "Base " .. slot, Homes.PromptReach)
		proximity.Enabled = false
		doors[slot] = { prompt = proximity, label = label, strip = strip, front = frame * CFrame.new(0, 3.2, -6) }
	end

	-- West end: arrival and the way back
	block("EndSign", Vector3.new(12, 3, 0.4), Vector3.new(-half + 1.2, 9, 0), rgb(26, 28, 34), M.SmoothPlastic, nil, Vector3.new(1, 0, 0))
	local endSign = model:FindFirstChild("EndSign") :: BasePart
	local signGui = Common.sign(endSign, Enum.NormalId.Front, "PLAYER BASE STREET", rgb(242, 230, 208), 36, 0)
	signGui.Name = "WingSign"
	local back = block("ReturnPost", Vector3.new(1, 4, 3), Vector3.new(-half + 2, 2, 0), rgb(35, 39, 46), M.Metal, nil, Vector3.new(1, 0, 0))
	block("ReturnGlow", Vector3.new(0.2, 2.4, 2), Vector3.new(-half + 2.6, 2.6, 0), rgb(95, 196, 138), M.Neon, DECOR, Vector3.new(1, 0, 0))
	local returnPrompt = BaseStreet.prompt(back, "Return to hub", "Hub", 14)

	-- East end: a seating bay
	block("BayRug", Vector3.new(14, 0.1, 10), Vector3.new(half - 10, 0.05, 0), rgb(46, 52, 62), M.Fabric, DECOR)
	block("Bench", Vector3.new(10, 1.6, 2.4), Vector3.new(half - 3, 0.9, 0), rgb(150, 82, 44), M.Fabric)
	block("BenchBack", Vector3.new(10, 1.8, 0.5), Vector3.new(half - 1.9, 2.4, 0), rgb(130, 70, 38), M.Fabric)
	for _, z in { -8, 8 } do
		block("Planter", Vector3.new(3, 1.6, 3), Vector3.new(half - 4, 0.8, z), rgb(35, 39, 46), M.Metal)
		Common.ball(model, "Leaves", c + Vector3.new(half - 4, 3.2, z), 3.4, rgb(70, 124, 72), M.Grass, DECOR)
		Common.ball(model, "Leaves", c + Vector3.new(half - 4.6, 4.2, z + 0.5), 2.2, rgb(86, 142, 84), M.Grass, DECOR)
	end
	for _, x in { -40, 40 } do
		for _, z in { -9.5, 9.5 } do
			block("Planter", Vector3.new(2.4, 1.4, 2.4), Vector3.new(x, 0.7, z), rgb(35, 39, 46), M.Metal)
			Common.ball(model, "Leaves", c + Vector3.new(x, 2.8, z), 2.8, rgb(78, 132, 78), M.Grass, DECOR)
		end
	end

	model.Parent = parent

	local built = { model = model, doors = doors, returnPrompt = returnPrompt } :: any
	built.spawn = CFrame.lookAt(c + Vector3.new(-half + 8, 3.2, 0), c + Vector3.new(0, 3.2, 0))
	function built.doorFront(slot: number): CFrame
		return doors[slot].front
	end
	-- An occupied door shows the owner's name and lights its strip; a vacant one is dark and
	-- its prompt is off (only changed values are written)
	function built.setDoor(slot: number, ownerName: string?)
		local door = doors[slot]
		if not door then
			return
		end
		local text = if ownerName then string.format("%02d  %s", slot, string.upper(ownerName)) else string.format("%02d  VACANT", slot)
		if door.label.Text ~= text then
			door.label.Text = text
		end
		door.label.TextColor3 = if ownerName then rgb(242, 230, 208) else rgb(150, 156, 164)
		door.strip.Color = if ownerName then PERSONAL else VACANT
		door.prompt.Enabled = ownerName ~= nil
		door.prompt.ObjectText = if ownerName then ownerName .. "'s base" else "Base " .. slot
	end
	return built :: Built
end

return BaseStreet
