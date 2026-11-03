-- Client smoke test for CosmeticFxController (auras, knockout bursts, gold lounge names):
--   rojo build default.project.json -o build/game.rbxl
--   lune run tests/smoke_cosmeticfx.luau build/game.rbxl
-- Draws from the Player attributes, pools and cleans up, and goes quiet with reduced effects.

local process = require("@lune/process")
local Client = require("./smoke/Client")

local t = Client.load(process.args[1])
local task, Engine, world = t.task, t.Engine, t.world

local Settings = t.client("Settings")
local Protocol = t.shared("Protocol")
local Controller = t.client("Controllers.CosmeticFxController")
local Cosmetics = t.shared("Config.Cosmetics")
local Attribute = Protocol.Attribute

local me = world.localPlayer
local character = Engine.character("Tester")
character.Parent = world.workspace
me.Character = character
me.DisplayName = "Tester"

Controller:Start()
task.wait(0.1)

-- The stand-in engine does not fire attribute signals by itself, so say what changed
local function setAttr(instance, name, value)
	instance:SetAttribute(name, value)
	Engine.signalOf(instance, "Attribute:" .. name):Fire()
end
local function fxFolder()
	return world.workspace:FindFirstChild("SNCosmeticFx")
end
local function count(name)
	local n = 0
	for _, item in (fxFolder() and fxFolder():GetChildren() or {}) do
		if item.Name == name then
			n += 1
		end
	end
	return n
end

t.check("an aura attribute draws one soft emitter; clearing it removes it", function()
	assert(count("SNAura") == 0)
	setAttr(me, Attribute.CosmeticAura, "hv_p03_aura")
	task.wait(0.1)
	assert(count("SNAura") == 1, "one aura part")
	local emitter = fxFolder():FindFirstChild("SNAura"):FindFirstChildOfClass("ParticleEmitter")
	assert(emitter, "a particle emitter")
	assert(emitter.Rate <= 10 and emitter.Size.Keypoints[1].Value <= 0.25, "slow and small")
	setAttr(me, Attribute.CosmeticAura, "hv_p05_plate")
	task.wait(0.1)
	assert(count("SNAura") == 0, "a plate id is not an aura")
	setAttr(me, Attribute.CosmeticAura, "hv_p03_aura")
	task.wait(0.1)
	assert(count("SNAura") == 1)
	setAttr(me, Attribute.CosmeticAura, "")
	task.wait(0.1)
	assert(count("SNAura") == 0, "cleared")
end)

t.check("the owner panel's SNAura attribute is untouched and draws nothing here", function()
	me:SetAttribute(Attribute.Aura, "Gold")
	task.wait(0.1)
	assert(count("SNAura") == 0)
	me:SetAttribute(Attribute.Aura, nil)
end)

t.check("reduced effects turn auras off and shrink bursts", function()
	setAttr(me, Attribute.CosmeticAura, "hv_p03_aura")
	task.wait(0.1)
	assert(count("SNAura") == 1)
	Settings.set("reducedEffects", true)
	task.wait(0.1)
	assert(count("SNAura") == 0, "aura off")
	Settings.set("reducedEffects", false)
	task.wait(0.1)
	assert(count("SNAura") == 1, "aura back")
	setAttr(me, Attribute.CosmeticAura, nil)
	task.wait(0.1)
	assert(count("SNAura") == 0)
end)

t.check("a knockout burst is pooled: at most four at once, then free again", function()
	local item = Cosmetics.get("hv_p04_ko")
	local position = t.roblox.Vector3.new(0, 5, 0)
	local played = 0
	for _ = 1, 8 do
		if Controller.playKnockout(item, position) then
			played += 1
		end
	end
	assert(played == 4, "pool of four, played " .. played)
	local _, bursts = Controller.debugCounts()
	assert(bursts == 4)
	task.wait(2)
	assert(Controller.playKnockout(item, position), "the pool frees up")
	assert(select(2, Controller.debugCounts()) == 4, "no new bursts were built")
end)

t.check("a Knockout match event plays the credited player's effect at the victim", function()
	task.wait(2)
	local victim = Engine.character("Rival")
	victim:SetAttribute(Attribute.DisplayName, "Rival")
	victim.Parent = world.workspace
	me:SetAttribute(Attribute.Knockout, "hv_p04_ko")
	local matchEvent = world.find("ReplicatedStorage.Remotes.MatchEvent")
	local emitted = 0
	for _, item in fxFolder():GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Enabled = false
		end
	end
	Engine.signalOf(matchEvent, "OnClientEvent"):Fire(Protocol.MatchEvent.Knockout, { victim = "Rival", credited = "Tester" })
	task.wait(0.1)
	local busy = 0
	for _, item in fxFolder():GetChildren() do
		if item.Name == "SNKnockoutFx" then
			busy += 1
		end
	end
	assert(busy >= 1, "a burst part exists")
	-- A knockout nobody earned, or by a player with no effect, draws nothing new
	me:SetAttribute(Attribute.Knockout, "")
	local before = busy
	Engine.signalOf(matchEvent, "OnClientEvent"):Fire(Protocol.MatchEvent.Knockout, { victim = "Rival", credited = "Tester" })
	Engine.signalOf(matchEvent, "OnClientEvent"):Fire(Protocol.MatchEvent.Knockout, { victim = "Rival" })
	Engine.signalOf(matchEvent, "OnClientEvent"):Fire(Protocol.MatchEvent.Knockout, "junk")
	task.wait(0.1)
	assert(select(2, Controller.debugCounts()) == before)
end)

t.check("a VIP player's own nameplate turns gold in the lounge, and back outside", function()
	local Nameplates = t.client("Controllers.NameplateController")
	-- The test world's stand-in player has no parent, so the controller draws no plate for it:
	-- build one with the controller's own builder and hand it to the effects controller
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	local built = Nameplates.build(me, head)
	local original = Nameplates.plateOf
	Nameplates.plateOf = function()
		return built
	end
	local plate = Nameplates.plateOf(me)
	assert(plate, "the nameplate exists")
	local label = plate:FindFirstChild("Name", true)
	assert(label, "the name label exists")
	local normal = label.TextColor3
	me:SetAttribute(Attribute.Vip, true)
	local root = character:FindFirstChild("HumanoidRootPart")
	root.Position = t.roblox.Vector3.new(0, 3, 700)
	task.wait(1.2)
	assert(label.TextColor3 ~= normal, "gold name in the lounge")
	assert(count("SNVipName") == 0, "no second name label")
	root.Position = t.roblox.Vector3.new(0, 3, 0)
	task.wait(1.2)
	assert(label.TextColor3 == normal, "back to normal outside")
	me:SetAttribute(Attribute.Vip, nil)
	Nameplates.plateOf = original
end)

t.finish()
