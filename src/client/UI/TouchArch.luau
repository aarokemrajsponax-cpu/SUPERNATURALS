-- The touch fight layout: where every thumb button goes. Pure arithmetic (no instances), so
-- the tests can check it at every screen size.
--
-- Picture the bottom-right corner. Roblox puts its jump button there. The big attack button
-- sits just left of it, and the rest of the actions form an arch over both, like a C turned
-- on its side: an inner ring of the four defence and heavy actions closest to the thumb,
-- then an outer ring of abilities and extras. Every number is in screen pixels, measured
-- from the bottom-right corner (so x and y are negative), the way the touch buttons are placed.
--
-- Guarantees (all checked in tests/smoke_hud.luau at 667x375, 844x390, 932x430, 1024x768, 1194x834):
--   * no button overlaps another, the jump button or the main button
--   * every button is at least MIN_SIZE and inside the screen with a margin
--   * the arch stays right of the thumbstick zone (the left THUMBSTICK_SHARE of the screen)
--   * priority decides who stays when a small screen runs out of room

local TouchArch = {}

TouchArch.MIN_SIZE = 56
TouchArch.GAP = 8
TouchArch.MARGIN = 8
-- Keep the arch clear of the top strip (kill feed, timer): buttons stay below this line
TouchArch.TOP_INSET = 52
-- The left share of the screen Roblox's thumbstick may use
TouchArch.THUMBSTICK_SHARE = 0.3
-- The share of the screen kept free beside the thumbstick for the vitals plate (health, guard,
-- stamina). Extra buttons that would crowd it are dropped, never the core ones.
TouchArch.VITALS_SHARE = 0.21

export type Item = { name: string, main: boolean? }
export type Slot = { x: number, y: number, size: number, ring: number }
export type Result = {
	slots: { [string]: Slot },
	dropped: { string },
	jump: { x: number, y: number, size: number },
	leftEdge: number, -- the arch's left-most pixel, from the left of the screen
	scale: number,
}

-- Roblox's jump button (PlayerModule TouchJump): centre from the bottom-right corner, diameter
function TouchArch.jumpFrame(viewportX: number, viewportY: number): (number, number, number)
	if math.min(viewportX, viewportY) <= 500 then
		return -60, -55, 70
	end
	return -110, -150, 120
end

function TouchArch.scale(viewportX: number, viewportY: number): number
	return if math.min(viewportX, viewportY) <= 500 then 1 else 1.3
end

-- items: in priority order, the main button first. Everything is placed on one of the rings
-- until the screen is full; whatever does not fit is listed in `dropped`.
function TouchArch.compute(viewportX: number, viewportY: number, items: { Item }): Result
	local scale = TouchArch.scale(viewportX, viewportY)
	local jx, jy, jsize = TouchArch.jumpFrame(viewportX, viewportY)
	local gap, margin = TouchArch.GAP, TouchArch.MARGIN
	local mainSize = math.floor(84 * scale + 0.5)
	local size = math.floor(TouchArch.MIN_SIZE * scale + 0.5)
	local result: Result = {
		slots = {},
		dropped = {},
		jump = { x = jx, y = jy, size = jsize },
		leftEdge = viewportX,
		scale = scale,
	}

	-- Work in screen coordinates (origin top-left), convert at the end
	local jumpX, jumpY = viewportX + jx, viewportY + jy
	local mainX, mainY = jumpX - (jsize / 2 + gap + mainSize / 2), jumpY
	local rest = {}
	for _, item in items do
		if item.main then
			result.slots[item.name] = { x = mainX - viewportX, y = mainY - viewportY, size = mainSize, ring = 0 }
		else
			table.insert(rest, item)
		end
	end
	result.leftEdge = math.min(result.leftEdge, mainX - mainSize / 2)

	-- The arch is centred between the main button and the jump button
	local centreX, centreY = (mainX + jumpX) / 2, mainY
	local reach = math.max((jumpX - mainX) / 2 + jsize / 2, (jumpX - mainX) / 2 + mainSize / 2)
	local left = viewportX * (TouchArch.THUMBSTICK_SHARE + TouchArch.VITALS_SHARE) + margin
	local placed = 0
	local ring = 1
	local radius = reach + gap + size / 2
	while placed < #rest and ring <= 3 do
		-- Candidate angles from the right end of the ring over the top to the left (and a little
		-- below the horizontal), kept only while the button stays on screen and right of the stick
		local step = (size + gap) / radius
		local usable = {}
		local angle = 0
		while angle <= math.rad(215) do
			local x = centreX + radius * math.cos(angle)
			local y = centreY - radius * math.sin(angle)
			local fits = x + size / 2 <= viewportX - margin
				and x - size / 2 >= left
				and y - size / 2 >= TouchArch.TOP_INSET
				and y + size / 2 <= viewportY - margin
			if fits then
				table.insert(usable, { x = x, y = y, angle = angle })
			end
			angle += step
			-- Angles that don't fit at the right end are skipped, but once we have started
			-- and then fall off the screen (left side or bottom), the ring is done
			if not fits and #usable > 0 then
				break
			end
		end
		for _, spot in usable do
			if placed >= #rest then
				break
			end
			placed += 1
			local item = rest[placed]
			result.slots[item.name] = { x = spot.x - viewportX, y = spot.y - viewportY, size = size, ring = ring }
			result.leftEdge = math.min(result.leftEdge, spot.x - size / 2)
		end
		ring += 1
		radius += size + gap
	end
	for index = placed + 1, #rest do
		table.insert(result.dropped, rest[index].name)
	end
	return result
end

-- Who gets a place first when the screen is small. The ultimate and the first three abilities
-- come right after the four fighting basics; then evolve, run, the Grandmaster's fourth to
-- sixth abilities, and last lock-on and sweep, which go first when a small screen is full.
TouchArch.MAIN = "SNLight"
TouchArch.ORDER = {
	"SNHeavy", "SNBlock", "SNDodge", "SNGrab",
	"Ability_1", "Ability_2", "Ability_3", "Ability_Ultimate",
	"SNEvolve", "SNSprint", "Ability_4", "Ability_5", "Ability_6", "SNLock", "SNSweep",
}

-- The items for the buttons that exist, in priority order, main button first
function TouchArch.items(exists: { [string]: boolean }): { Item }
	local list: { Item } = {}
	if exists[TouchArch.MAIN] then
		table.insert(list, { name = TouchArch.MAIN, main = true })
	end
	for _, name in TouchArch.ORDER do
		if exists[name] then
			table.insert(list, { name = name })
		end
	end
	return list
end

-- Shared between InputController (owns the touch layer and the layout) and AbilityBar (hands
-- its buttons over on touch)
TouchArch.state = {
	layer = nil :: Instance?,
	abilities = {} :: { { name: string, slot: any, frame: GuiObject } },
	relayout = nil :: (() -> ())?,
	-- The last computed layout (the Hud reads leftEdge to fit its vitals beside the arch)
	arch = nil :: Result?,
}

function TouchArch.setAbilityButtons(list: { { name: string, slot: any, frame: GuiObject } })
	TouchArch.state.abilities = list
	local relayout = TouchArch.state.relayout
	if relayout then
		relayout()
	end
end

return TouchArch
