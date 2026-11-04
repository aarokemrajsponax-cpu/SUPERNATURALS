-- Movement styles: Roblox's own catalog animation packs (listed in Roblox's "Catalog animations"
-- documentation, type Animation, creator Roblox). Each fighter's character gets one pack by
-- setting the values inside its Animate script. Nothing else is invented here.
-- Slots, in order: Run, Walk, Jump, Idle1, Idle2, Fall, Swim, SwimIdle, Climb.

local Animations = {}

-- The attribute on a character naming its current pack ("" for none); clients watch it
Animations.StyleAttribute = "SNAnimStyle"

Animations.Slots = { "Run", "Walk", "Jump", "Idle1", "Idle2", "Fall", "Swim", "SwimIdle", "Climb" }

local function pack(ids: { number })
	local out = {}
	for index, slot in Animations.Slots do
		out[slot] = ids[index]
	end
	return out
end

Animations.Packs = {
	Superhero = pack({ 616117076, 616122287, 616115533, 616111295, 616113536, 616108001, 616119360, 616120861, 616104706 }),
	Ninja = pack({ 656118852, 656121766, 656117878, 656117400, 656118341, 656115606, 656119721, 656121397, 656114359 }),
	Robot = pack({ 616091570, 616095330, 616090535, 616088211, 616089559, 616087089, 616092998, 616094091, 616086039 }),
	Mage = pack({ 707861613, 707897309, 707853694, 707742142, 707855907, 707829716, 707876443, 707894699, 707826056 }),
	Vampire = pack({ 1083462077, 1083473930, 1083455352, 1083445855, 1083450166, 1083443587, 1083464683, 1083467779, 1083439238 }),
	Levitation = pack({ 616010382, 616013216, 616008936, 616006778, 616008087, 616005863, 616011509, 616012453, 616003713 }),
	Knight = pack({ 657564596, 657552124, 658409194, 657595757, 657568135, 657600338, 657560551, 657557095, 658360781 }),
	Werewolf = pack({ 1083216690, 1083178339, 1083218792, 1083195517, 1083214717, 1083189019, 1083222527, 1083225406, 1083182000 }),
}

-- Fighter (power id, or "Jeffery" for his sparring unit) -> pack. The Shapeshifter's Werewolf
-- pack is held for a later update: HeldPacks fighters keep their character's own animations.
Animations.ForFighter = {
	StrongDude = "Superhero",
	Ghost = "Ninja",
	MachineMaster = "Robot",
	Grandmaster = "Mage",
	Corruption = "Vampire",
	Syntax = "Levitation",
	Admin = "Knight",
	Shapeshifter = "Werewolf",
	Jeffery = "Robot",
}
Animations.Held = { Shapeshifter = true }

-- Animate script slot -> the folder name and value name inside it
Animations.Targets = {
	Run = { "run", "RunAnim" },
	Walk = { "walk", "WalkAnim" },
	Jump = { "jump", "JumpAnim" },
	Idle1 = { "idle", "Animation1" },
	Idle2 = { "idle", "Animation2" },
	Fall = { "fall", "FallAnim" },
	Swim = { "swim", "Swim" },
	SwimIdle = { "swimidle", "SwimIdle" },
	Climb = { "climb", "ClimbAnim" },
}

-- The pack a fighter plays, or nil (unknown fighter or held)
function Animations.packFor(fighterKey: string?): string?
	if not fighterKey or Animations.Held[fighterKey] then
		return nil
	end
	return Animations.ForFighter[fighterKey]
end

function Animations.idOf(assetId: number): string
	return `rbxassetid://{assetId}`
end

return Animations
