-- Where the combat interface belongs. One rule, read from one place: the server decides where
-- a fighter stands (PowerService:combatContext) and publishes it on the character as
-- Attribute.CombatContext. The combat HUD, the ability buttons and the touch arch show only in
-- a fight (Match), in the Training Studio and CPU practice (Training, Npc) and for the owner's
-- showcase; in the lobby, hub, lounge, bases and corridors the screen shows only the lobby
-- essentials. The Shell's "Match" mode counts as a fight too, so the HUD is already there when
-- the first match state arrives, before the attribute does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)

local CombatView = {}

local Context = Protocol.CombatContext

local SHOWS_HUD = {
	[Context.Match] = true,
	[Context.Training] = true,
	[Context.Npc] = true,
	[Context.Showcase] = true,
}

-- The context on a character, "Lobby" when there is none yet
function CombatView.context(character: Instance?): string
	local value = if character then character:GetAttribute(Protocol.Attribute.CombatContext) else nil
	return if typeof(value) == "string" then value else Context.Lobby
end

-- Does this character get the combat interface? shellMode is Shell.getMode()
function CombatView.active(character: Instance?, shellMode: string?): boolean
	if shellMode == "Match" then
		return true
	end
	return SHOWS_HUD[CombatView.context(character)] == true
end

-- Is this character practising (the Training Studio, CPU practice) rather than in a match?
function CombatView.practising(character: Instance?): boolean
	local context = CombatView.context(character)
	return context == Context.Training or context == Context.Npc
end

return CombatView
