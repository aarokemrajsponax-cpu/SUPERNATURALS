-- Jeffery's first-time tutorial, contextual hints and facial expressions. Shared by the server
-- (TutorialService decides what counts) and the client (dialogue and hint text).
-- Lines are short on purpose. No emoji, no em dashes.
-- Progress is remembered in profile.tutorial.done under these keys:
--   tut_step_<id>   a step was completed        tut_complete  the whole path was finished
--   tut_exited      the player left the path     tut_veteran   skipped automatically (3+ matches)
--   tut_reward      the welcome reward was paid  hint_<id>     a hint was shown

local Tutorial = {}

Tutorial.VeteranMatches = 3
Tutorial.Reward = { money = 250, title = "Recruit", titleId = "title_recruit" }

-- Distances the server checks
Tutorial.MoveDistance = 10
Tutorial.JumpSpeed = 12

-- Step events (the server only advances a step on its own event):
--   ack       the player pressed CONTINUE on a note-only step (welcome, camera)
--   move, jump, sprint, training (entered the hall), attack (landed a hit), block, dodge,
--   ability (used a non-basic ability), evolve (transformed), showcase (opened fighter selection),
--   win (won a match)
Tutorial.Steps = {
	{
		id = "welcome", event = "ack", face = "happy", title = "Welcome",
		lines = {
			"Hello, new recruit. I am Jeffery, your officially unofficial facility assistant.",
			"This is the training facility. Eight fighters, one hall, and a lot of people pressing buttons.",
			"The doors around the hall lead to fights, training, the shop and fighter selection. My own door is Jeffery's Base.",
		},
		goal = "Press Continue",
	},
	{
		id = "move", event = "move", face = "thinking", title = "Move",
		lines = { "Before you launch yourself into a wall, let us cover movement." },
		goal = "Walk a few steps",
		keys = { "move" },
	},
	{
		id = "jump", event = "jump", face = "excited", title = "Jump",
		lines = { "Good. Now jump. Gravity is a rule here, but a flexible one." },
		goal = "Jump once",
		keys = { "jump" },
	},
	{
		id = "sprint", event = "sprint", face = "excited", title = "Sprint",
		lines = { "Hold sprint and run. It uses stamina, so do not run everywhere." },
		goal = "Sprint for a moment",
		keys = { "SNSprint" },
	},
	{
		id = "camera", event = "ack", face = "thinking", title = "Camera",
		lines = { "Turn the camera and look around. I will wait. I am very patient." },
		goal = "Look around, then press Continue",
		keys = { "camera" },
	},
	{
		id = "training", event = "training", face = "happy", title = "Training",
		lines = { "Now the fun part. Go through the Training Studio door and I will meet you there." },
		goal = "Enter the Training Studio",
		guide = "Training",
	},
	{
		id = "attack", event = "attack", face = "excited", title = "Attack",
		lines = { "Here, fighting is allowed. Hit a dummy. It has no feelings, I checked." },
		goal = "Land a hit on a dummy",
		keys = { "SNLight" },
	},
	{
		id = "block", event = "block", face = "warning", title = "Block",
		lines = { "Blocking stops most of the damage. Hold it and look dignified." },
		goal = "Hold block",
		keys = { "SNBlock" },
	},
	{
		id = "dodge", event = "dodge", face = "excited", title = "Dodge",
		lines = { "Dodging is better than blocking when it works. Try one." },
		goal = "Dodge once",
		keys = { "SNDodge" },
	},
	{
		id = "ability", event = "ability", face = "excited", title = "Ability",
		lines = { "Your power has abilities on the bar at the bottom. Use one." },
		goal = "Use an ability",
		keys = { "ability" },
	},
	{
		id = "evolve", event = "evolve", face = "proud", title = "Evolve",
		lines = { "In training every phase is free to try. Evolve into the next one and see what changes." },
		goal = "Evolve a phase",
		keys = { "SNEvolve" },
	},
	{
		id = "showcase", event = "showcase", face = "happy", title = "Fighter Showcase",
		lines = { "Now meet the fighters. Open the Calibration Chamber door, or the Fighters button, to browse them." },
		goal = "Open the Fighter Showcase",
		guide = "Calibration",
	},
	{
		id = "win", event = "win", face = "proud", title = "Practice fight",
		lines = { "Final test. Open the Test Chambers door, pick a practice fight against the computer, and win." },
		goal = "Win a practice fight",
		guide = "Battle",
	},
}

Tutorial.Outro = {
	face = "victory",
	lines = {
		"Congratulations, recruit. You are now officially less likely to press random buttons and hope for the best.",
		"Your welcome reward is on the way. I will keep an eye on you. For safety. Mostly yours.",
	},
}

Tutorial.Exited = { face = "confused", lines = { "Tutorial paused. Open How to Play any time and I will pick it up again." } }

-- Key caps for steps that are not a single binding (per device)
Tutorial.ExtraKeys = {
	move = { keyboard = "W A S D", gamepad = "Left stick", touch = "Left thumb stick" },
	jump = { keyboard = "Space", gamepad = "A", touch = "Jump button" },
	camera = { keyboard = "Mouse", gamepad = "Right stick", touch = "Drag the screen" },
	ability = { keyboard = "1 2 3 4", gamepad = "D-pad", touch = "Ability buttons" },
}

-- Contextual hints: once each, remembered by the server, never during active combat.
-- `trigger` is what the server watches. The client queues a hint until combat is quiet.
Tutorial.Hints = {
	lobby = { trigger = "lobby", face = "happy", text = "This is the lobby. Fights are off here, so stretch your legs and use the doors." },
	training = { trigger = "training", face = "excited", text = "Training is free. Try any power and any phase on the dummies." },
	selection = { trigger = "window", face = "thinking", text = "Pick a fighter, then a phase. Phase 1 is open, the rest unlock as you play." },
	shop = { trigger = "window", face = "happy", text = "The shop sells what it says. No mystery boxes, no timers." },
	evolve_ready = { trigger = "evolve_ready", face = "excited", text = "Your phase meter is full. Press the evolve button to transform." },
	grab_suffered = { trigger = "grab", face = "warning", text = "You were grabbed. Press the escape input quickly to break free." },
	timing_bar = { trigger = "timing", face = "thinking", text = "That was a timing bar. Press the input when the marker is in the bright zone." },
	stamina_out = { trigger = "stamina", face = "disappointed", text = "Out of stamina. Stop sprinting and dodging for a moment and it comes back." },
	power_Corruption = { trigger = "power", face = "warning", text = "Corruption trades safety for power. Watch your own health." },
	power_Syntax = { trigger = "power", face = "thinking", text = "Syntax rewrites the rules of a fight. Read each ability before using it." },
	power_Admin = { trigger = "power", face = "proud", text = "The Admin fighter is only a fighter. It grants no real admin rights." },
}

-- Windows that may ask for a hint from the client (the server checks this list)
Tutorial.WindowHints = { Powers = "selection", Market = "shop" }

-- Facial expressions. eye = { width, height, y (fraction of the screen), tilt degrees, round }
-- mouth = { width, height, y, tilt, round }. Sizes are fractions of the screen.
Tutorial.Faces = {
	happy = { eye = { 0.15, 0.30, 0.38, 0, true }, mouth = { 0.34, 0.10, 0.72, 0, false } },
	confused = { eye = { 0.13, 0.28, 0.38, 8, true }, mouth = { 0.20, 0.06, 0.74, -10, false } },
	thinking = { eye = { 0.17, 0.16, 0.40, 0, false }, mouth = { 0.16, 0.06, 0.74, 0, false } },
	excited = { eye = { 0.19, 0.36, 0.36, 0, true }, mouth = { 0.30, 0.18, 0.70, 0, true } },
	warning = { eye = { 0.20, 0.14, 0.40, 14, false }, mouth = { 0.28, 0.06, 0.74, 0, false } },
	proud = { eye = { 0.18, 0.12, 0.40, -6, false }, mouth = { 0.36, 0.10, 0.72, 0, false } },
	disappointed = { eye = { 0.18, 0.10, 0.42, 12, false }, mouth = { 0.22, 0.06, 0.78, 8, false } },
	victory = { eye = { 0.20, 0.34, 0.36, 0, true }, mouth = { 0.42, 0.22, 0.68, 0, true } },
}
Tutorial.FaceNames = { "happy", "confused", "thinking", "excited", "warning", "proud", "disappointed", "victory" }
Tutorial.FaceColor = Color3.fromRGB(96, 226, 244)

function Tutorial.stepIndex(id: string): number?
	for index, step in Tutorial.Steps do
		if step.id == id then
			return index
		end
	end
	return nil
end

return Tutorial
