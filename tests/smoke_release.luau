-- Client side of the release switch (Powers.Unreleased): the Fighter Showcase and the Play window
-- list seven fighters for a player and all eight for the owner (IsOwner attribute).
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_release.luau build/game.rbxl
-- The server side is in tests/release_test.luau.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local Powers = t.shared("Powers")
local Protocol = t.shared("Protocol")
local ui = t.startUI({
	currencies = { money = 12000, gems = 6666 },
	selected = { power = "StrongDude", degree = 1 },
	powers = { StrongDude = { xp = 500 } },
	loadouts = {},
	passes = {},
	settings = {},
})
local Shell, gui = ui.Shell, ui.gui
t.setScreen(1280, 720)

local function cards(): number
	local n = 0
	for _, card in t.findNamed(gui, "PowerList"):GetChildren() do
		if card:IsA("TextButton") then
			n += 1
		end
	end
	return n
end

local function playFighters(): number
	local n = 0
	for _, item in t.findNamed(gui, "FighterGrid"):GetChildren() do
		if item:IsA("TextButton") then
			n += 1
		end
	end
	return n
end

t.check("the switch is on for the Shapeshifter and the helpers agree", function()
	assert(Powers.Unreleased.Shapeshifter == true)
	assert(#Powers.Order == 8 and #Powers.released() == 7)
	assert(not Powers.isReleased("Shapeshifter") and Powers.isReleased("StrongDude"))
	assert(table.find(Powers.released(), "Shapeshifter") == nil)
end)

t.check("a player sees seven fighters in the Showcase and the Play window", function()
	Shell.open("Powers")
	assert(cards() == 7, `Showcase lists {cards()}`)
	assert(not t.findNamed(gui, "Card_Shapeshifter"), "no Shapeshifter card")
	Shell.close()
	Shell.open("Play")
	assert(playFighters() == 7, `Play lists {playFighters()}`)
	assert(not t.findNamed(gui, "Fighter_Shapeshifter"), "no Shapeshifter button")
	Shell.close()
end)

t.check("the owner sees all eight", function()
	t.world.localPlayer:SetAttribute(Protocol.Attribute.IsOwner, true)
	Shell.open("Powers")
	assert(cards() == 8, `Showcase lists {cards()}`)
	assert(t.findNamed(gui, "Card_Shapeshifter"), "Shapeshifter card for the owner")
	Shell.close()
	Shell.open("Play")
	assert(playFighters() == 8, `Play lists {playFighters()}`)
	Shell.close()
end)

t.finish()
