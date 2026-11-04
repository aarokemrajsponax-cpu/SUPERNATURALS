-- Jeffery's first-time tour, the optional "tell me more" talk, the welcome gift moment, contextual
-- hints and facial expressions. Shared by the server (TutorialService decides what counts) and the
-- client (dialogue and hint text). Lines are short on purpose and written for players who know
-- nothing. No emoji, no em dashes. Everything not in the tour lives in How to Play (LearnWindow).
--
-- Progress is remembered in profile.tutorial.done under these keys:
--   tut_step_<id>   a step was completed        tut_complete  the whole path was finished
--   tut_exited      the player left the path     tut_veteran   skipped automatically (3+ matches)
--   tut_reward      the welcome gift was paid    hint_<id>     a hint was shown
--
-- How a step stays in sync (server and client agree on this):
--   1. The server sends the step. The client shows Jeffery's lines and, when the lines end,
--      sends TutorialLine(stepId). Only then does the server start watching for the step's event
--      ("armed"); anything the player did while Jeffery was talking does not count.
--   2. Movement-style steps start from the position, state and camera at that moment.
--   3. Guide arrows on the floor (step.guide) appear only once the step is armed.
--   4. If the client never reports (it crashed), the server arms the step by itself after
--      Tutorial.ArmTimeout seconds so nobody is stuck.

local Tutorial = {}

Tutorial.VeteranMatches = 3
Tutorial.Reward = { money = 250, title = "Recruit", titleId = "title_recruit", foundingId = "title_founding", foundingTitle = "Founding Recruit" }

-- Seconds after a step is sent before the server arms it without the client's report
Tutorial.ArmTimeout = 25
-- The client sends TutorialReady (it is running and Jeffery is in the world) before the tour starts;
-- without it the tour starts anyway after this many seconds
Tutorial.ClientWait = 15
-- Seconds after a line finishes typing before an action step's panel closes by itself
Tutorial.AutoCloseSeconds = 4

-- Distances the server checks
Tutorial.MoveDistance = 10
Tutorial.JumpSpeed = 12
-- Degrees the camera must turn for the "look" step (checked on the client, which owns the camera)
Tutorial.LookDegrees = 35

-- Step events (the server only advances a step on its own event):
--   ack       the player pressed CONTINUE on a note-only step (welcome)
--   look      the client saw the camera turn (camera)
--   move, jump, sprint, training (entered the Training Studio), attack (landed a hit), block,
--   dodge, ability (used a non-basic ability), evolve (transformed), showcase (opened fighter
--   selection), win (won a match). jump, sprint, evolve, showcase and win are supported by the
--   server but are not part of the short tour; How to Play teaches them.
Tutorial.Steps = {
	{
		id = "welcome", event = "ack", face = "happy", title = "Welcome",
		lines = {
			"Hi! I am Jeffery, the robot guide of this facility.",
			"SUPERNATURALS is a superpower fighting game. You pick a fighter with its own power, train, then battle other players.",
			"I will show you the basics. It takes about two minutes, and you can stop any time.",
		},
		goal = "Press Continue",
	},
	{
		id = "move", event = "move", face = "thinking", title = "Walk",
		lines = {
			"First, walking. The keys for your device are on the card at the left.",
			"Walk a few steps. I will wait right here.",
		},
		goal = "Walk a few steps",
		keys = { "move" },
		autoClose = true,
	},
	{
		id = "camera", event = "look", face = "thinking", title = "Camera",
		lines = {
			"Now the camera. On a PC, hold the right mouse button and move the mouse. On a phone, drag the screen. On a gamepad, use the right stick.",
			"Turn around and look at the room.",
		},
		goal = "Turn the camera and look around",
		keys = { "camera" },
		autoClose = true,
	},
	{
		id = "training", event = "training", face = "happy", title = "Training Studio",
		lines = {
			"Time to practice. Follow the glowing arrows on the floor to the TRAINING STUDIO door and walk in.",
		},
		goal = "Walk into the Training Studio",
		guide = "Training",
		autoClose = true,
	},
	{
		id = "attack", event = "attack", face = "excited", title = "Attack",
		lines = {
			"This is the Training Studio. Fighting is allowed here and nothing you do is saved.",
			"A quick tap is a light attack. Holding the heavy button hits harder but slower. Hit a dummy now.",
		},
		goal = "Land a hit on a dummy",
		keys = { "SNLight", "SNHeavy" },
		autoClose = true,
	},
	{
		id = "block", event = "block", face = "warning", title = "Block",
		lines = { "Blocking takes most of the damage. Hold the block button for a moment." },
		goal = "Hold block",
		keys = { "SNBlock" },
		autoClose = true,
	},
	{
		id = "dodge", event = "dodge", face = "excited", title = "Dodge",
		lines = { "A dodge is a quick roll that slips past hits. It costs stamina. Try one." },
		goal = "Dodge once",
		keys = { "SNDodge" },
		autoClose = true,
	},
	{
		id = "ability", event = "ability", face = "excited", title = "Abilities",
		lines = {
			"Your fighter has abilities 1 to 3 on the bar at the bottom. They use energy and then recharge.",
			"The bar comes back when I stop talking. Use any one of them.",
		},
		goal = "Use an ability",
		keys = { "ability" },
		autoClose = true,
	},
}

-- After the last step: Jeffery asks whether the player wants the long version. Choosing "more"
-- plays Tutorial.More; either way the welcome gift moment follows.
Tutorial.Outro = {
	face = "proud",
	lines = {
		"That is all you need to start. Nice work!",
		"Do you want a quick tour of everything else, or would you rather play?",
	},
	choices = {
		{ id = "more", label = "Tell me more" },
		{ id = "gift", label = "Show my gift" },
	},
}

-- The optional branch (client only, no progress is tied to it). Every topic is also in How to Play.
Tutorial.More = {
	{
		face = "thinking",
		lines = {
			"Two more moves. Grab breaks through a block. Sweep knocks a standing fighter off their feet. Both are on the card in How to Play.",
			"Your ultimate is the big move. It charges as you fight, and a bar shows when it is ready.",
		},
	},
	{
		face = "excited",
		lines = {
			"Phases are stronger forms. A meter fills while you fight. When it is full, press T on a keyboard, Start on a gamepad, or the Evolve button on a phone.",
		},
	},
	{
		face = "happy",
		lines = {
			"To change fighters, tap your player card or the FIGHTERS button. Pick a fighter, then a phase.",
			"Train in the Training Studio. For real fights, walk through the TEST CHAMBERS door or press PLAY.",
		},
	},
	{
		face = "proud",
		lines = {
			"GIFTS is the gift calendar, with something new each day you visit. The LOCKER holds your titles, looks and achievements. The season pass is a 30 tier track of cosmetics you earn by playing.",
		},
	},
	{
		face = "happy",
		lines = {
			"You earn Money from matches and daily challenges. You earn Gems from your first win each day, fighter level ups and some challenges.",
			"Open How to Play any time, or just ask me a question. I will be right here at my post.",
		},
	},
}

-- The welcome gift moment shown when the tour finishes. The gift is already paid by the server and
-- never depends on liking or favouriting the game (Roblox cannot verify that).
Tutorial.Gift = {
	face = "victory",
	title = "Welcome gift",
	intro = "Thank you for finishing the tour. This is yours, no strings attached.",
	like = "If you enjoy SUPERNATURALS, a like on the game page helps us grow.",
	button = "Got it",
}

Tutorial.Exited = { face = "confused", lines = { "Tour stopped. Open How to Play or ask me a question any time." } }
Tutorial.ReplayDone = { face = "happy", lines = { "That was the tour again. No gift this time, but you keep the first one. Ask me anything you like." } }

-- Key caps for steps that are not a single binding (per device)
Tutorial.ExtraKeys = {
	move = { keyboard = "W A S D", gamepad = "Left stick", touch = "Left thumb stick" },
	jump = { keyboard = "Space", gamepad = "A", touch = "Jump button" },
	camera = { keyboard = "Right mouse", gamepad = "Right stick", touch = "Drag the screen" },
	ability = { keyboard = "1 2 3", gamepad = "R1 R2 L2", touch = "Ability buttons" },
	ultimate = { keyboard = "R", gamepad = "D-pad down", touch = "Ultimate button" },
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
