-- Jeffery's offline knowledge base: questions he can always answer, with no AI and no network.
-- Shared (JefferyChatService answers from it; the AI system prompt quotes it as reference).
--
-- Each entry: id, topic, patterns, answer. A pattern is a few content words in any order; the entry
-- matches when ALL words of one pattern appear in the question (plural endings and common stop
-- words are ignored). The score of a match is the number of words in the pattern, so a specific
-- pattern ("change fighter") beats a general one ("fighter"). The FIRST pattern of every entry is its
-- test question: tests/jeffery_chat_test.luau checks that it finds its own entry.
-- Answers: two or three short sentences, plain words, no emoji, no em dashes, nothing promised that
-- the game does not do. Controls follow the real bindings (InputController, AbilityController).

local Knowledge = {}

Knowledge.Entries = {} :: { { id: string, topic: string, patterns: { string }, answer: string } }

local function add(id: string, topic: string, patterns: { string }, answer: string)
	table.insert(Knowledge.Entries, { id = id, topic = topic, patterns = patterns, answer = answer })
end

-- The basics ----------------------------------------------------------------------------------
add("whatis", "The game", { "what supernaturals", "what game", "explain game", "what do", "new player", "beginner", "what goal" },
	"SUPERNATURALS is a superpower fighting game. Pick a fighter with its own power, train in the Training Studio, then fight in the Test Chambers. Open How to Play if you want the full guide.")
add("who", "Jeffery", { "who jeffery", "who you", "your name", "robot" },
	"I am Jeffery, the robot guide of this facility. I stay at my post in the hall and answer questions about the game.")
add("ai", "Jeffery", { "you ai", "you real", "you chatbot", "you human", "you bot" },
	"I am a robot guide. Most answers come from my built-in notes, and some may come from an AI helper if the owners switch one on. I cannot give items or change the game either way.")
add("hello", "Chat", { "hello", "hi", "hey", "good morning", "good evening", "sup" },
	"Hello! Ask me anything about SUPERNATURALS. Try: how do I move, what are phases, or where do I train.")
add("thanks", "Chat", { "thank", "thanks", "cheers", "appreciate" },
	"You are welcome! Ask again any time.")
add("bye", "Chat", { "bye", "goodbye", "see later", "gotta go" },
	"See you in the facility. Good luck out there!")
add("how_are_you", "Chat", { "how you", "you okay", "you feeling" },
	"All systems cheerful. Thank you for asking.")
add("joke", "Chat", { "joke", "funny", "make laugh" },
	"Why did the robot go to training? It needed to fix its attack-itude. I will see myself out.")
add("tutorial", "Help", { "replay tutorial", "tour again", "repeat tutorial", "tutorial", "show tour" },
	"Open How to Play and press Replay tutorial to take the tour again. The second visit pays no gift, but it is just as friendly.")

-- Controls ------------------------------------------------------------------------------------
add("move", "Controls", { "move", "walk", "wasd", "movement", "how go" },
	"Walk with W A S D on a keyboard, the left stick on a gamepad, or the left thumb stick on a phone. Jump with Space, the A button, or the jump button.")
add("jump", "Controls", { "jump", "hop", "leap" },
	"Jump with Space on a keyboard, A on a gamepad, or the jump button on a phone.")
add("sprint", "Controls", { "sprint", "run fast", "running", "shift", "faster" },
	"Hold Shift on a keyboard, press the left stick on a gamepad (L3), or hold Run on a phone to sprint. Sprinting uses stamina, so rest when it runs low.")
add("camera", "Controls", { "camera", "look around", "turn around", "rotate view", "mouse look" },
	"On a PC, hold the right mouse button and move the mouse. On a phone, drag the screen. On a gamepad, use the right stick.")
add("heavy", "Controls", { "heavy attack", "strong attack", "charge attack", "hard hit" },
	"Hold E on a keyboard, Y on a gamepad, or the heavy button on a phone. Heavy attacks hit harder but are slower, so use them when the other fighter is busy.")
add("block", "Controls", { "block", "guard", "defend", "protect" },
	"Hold F on a keyboard, L1 on a gamepad, or the block button on a phone. Blocking takes most of the damage, but a grab goes right through it.")
add("dodge", "Controls", { "dodge", "roll", "evade", "avoid hits" },
	"Press Q on a keyboard, B on a gamepad, or the dodge button on a phone. A dodge is a quick roll that slips past hits, and it costs stamina.")
add("grab", "Controls", { "grab", "throw", "break block", "grabbed", "escape grab" },
	"Press G on a keyboard, or L1 plus X on a gamepad, to grab. A grab beats a block. If you are grabbed, press the escape input quickly to break free.")
add("sweep", "Controls", { "sweep", "leg sweep", "knock down" },
	"Press C on a keyboard, or L1 plus Y on a gamepad, to sweep. A sweep knocks a standing fighter off their feet.")
add("light", "Controls", { "light attack", "attack", "punch", "hit enemy", "basic attack" },
	"Press the left mouse button on a PC, X on a gamepad, or the big attack button on a phone. Tap again to chain a few hits.")
add("abilities", "Controls", { "ability", "abilities", "skill", "special move", "use power" },
	"Your abilities sit on the bar at the bottom. Press 1, 2 or 3 on a keyboard, R1, R2 or L2 on a gamepad, or tap the button on a phone. They use energy and then recharge.")
add("ultimate", "Controls", { "ultimate", "ult", "big move", "super move", "finisher" },
	"Your ultimate is the biggest move. It charges as you fight. When its bar is full, press R on a keyboard, D-pad down on a gamepad, or the ultimate button on a phone.")
add("lockon", "Controls", { "lock on", "target", "aim", "lock enemy" },
	"Press Z or the middle mouse button on a keyboard, or R3 on a gamepad, to lock on to the nearest enemy so your attacks aim at it.")
add("stamina", "Controls", { "stamina", "winded", "tired", "out of breath" },
	"Stamina is used by sprinting and dodging. When it runs out you are winded for a moment. Stop sprinting and dodging and it comes back.")
add("energy", "Controls", { "energy", "cooldown", "resource", "recharge", "ability not working" },
	"Abilities cost energy and have a short cooldown. If one will not fire, check that its icon is not greyed out and that your energy bar has enough.")
add("taunt", "Controls", { "taunt", "emote", "dance" },
	"Press V on a keyboard, or View on a gamepad, to taunt. It does nothing but show off.")
add("pc", "Controls", { "pc controls", "keyboard", "mouse", "computer" },
	"On a PC: W A S D to move, left click to attack, E heavy, F block, Q dodge, G grab, C sweep, 1 to 3 abilities, R ultimate, T to evolve. How to Play shows them all.")
add("phone", "Controls", { "phone controls", "mobile", "touch", "tablet", "ipad", "iphone" },
	"On a phone, use the left thumb stick to walk, drag the right side of the screen to look, and tap the buttons at the bottom right to fight. How to Play has a Touch tab.")
add("gamepad", "Controls", { "gamepad controls", "controller", "xbox", "playstation", "gamepad" },
	"On a gamepad: left stick moves, right stick looks, X attacks, Y heavy, L1 blocks, B dodges, R1 R2 L2 are abilities and Start evolves. How to Play has a Gamepad tab.")
add("allcontrols", "Controls", { "all controls", "keybinds", "key binds", "controls", "buttons", "keys" },
	"Open How to Play from the LEARN button. It lists every control for keyboard, gamepad and touch.")
add("settings", "Controls", { "settings", "options", "volume", "music off", "sensitivity", "interface size", "reduce effects", "flashing" },
	"Open SETTINGS to change sound, camera sensitivity, interface size and visual effects. Turn on Reduced effects if the game feels slow or the flashes bother you.")

-- Fighters and phases ---------------------------------------------------------------------------
add("fighters", "Fighters", { "fighters", "characters", "how many fighters", "who play", "roster" },
	"There are eight fighters: Strong Dude, The Ghost, Animal Shapeshifter, Machine Master, The Grandmaster, and three premium fighters, Corruption, Syntax and Admin Powers. Open FIGHTERS to see them all.")
add("changefighter", "Fighters", { "change fighter", "switch fighter", "pick fighter", "choose fighter", "change character", "change power", "select fighter" },
	"Tap your player card at the top, or the FIGHTERS button. Pick a fighter, then a phase. You can switch before a match, not during one.")
add("strongdude", "Fighters", { "strong dude", "strongdude", "brawler" },
	"Strong Dude is a super-strong brawler who can take a beating. His big moves are slow and easy to read, so time them well.")
add("ghost", "Fighters", { "ghost", "ninja", "katana", "sword" },
	"The Ghost is a fast spectral swordsman with a katana. He vanishes, blinks and dashes, but he is fragile, so avoid long fights.")
add("shapeshifter", "Fighters", { "shapeshifter", "animal", "wolf", "hawk", "bear" },
	"The Animal Shapeshifter turns into a wolf, a hawk, a bear and more. Each animal fights its own way. Primal energy drains while you hold a form.")
add("machine", "Fighters", { "machine master", "gunner", "robot fighter", "blaster" },
	"Machine Master is a gunner with a blaster arm and blue soul fire. Strong at range, but his biggest attacks use fuel fast.")
add("grandmaster", "Fighters", { "grandmaster", "kung fu", "martial arts" },
	"The Grandmaster is a martial arts master with quick strings, counters and footwork. Every big technique has a tell you can learn to read.")
add("corruption", "Fighters", { "corruption", "eclipse" },
	"Corruption is a premium fighter that controls the middle of the arena with marks and fractured floors. It is fragile up close and trades safety for power.")
add("syntax", "Fighters", { "syntax", "coded bolts" },
	"Syntax is a premium long-range fighter who marks targets and rewrites the rules of the arena. It has low health and no melee, so keep your distance.")
add("adminfighter", "Fighters", { "admin power", "admin fighter", "admin", "get admin", "free admin", "admin right", "real admin" },
	"The Admin fighter is only a fighter with locks, walls and teleports. It never gives real admin rights, and I cannot give anyone admin.")
add("premium", "Fighters", { "premium fighter", "premium power", "unlock premium", "locked fighter", "how unlock" },
	"Corruption, Syntax and Admin Powers are premium. Open the MASTER SHOP or the fighter's page to see how to unlock them. The price is always shown before you confirm.")
add("trial", "Fighters", { "trial", "try fighter", "test fighter", "try before buy" },
	"You can try every fighter and every phase for free in the Training Studio. Nothing there is saved or charged.")
add("phases", "Phases", { "phase", "phases", "what phase", "meter", "degree" },
	"Phases are stronger forms of your fighter. A meter fills while you fight. When it is full, press T on a keyboard, Start on a gamepad, or the Evolve button on a phone.")
add("evolve", "Phases", { "evolve", "transform", "how evolve", "change phase" },
	"When your phase meter is full, press T on a keyboard, Start on a gamepad, or the Evolve button on a phone. You transform for a moment and come out stronger.")
add("phasecost", "Phases", { "unlock phase", "phase cost", "phase price", "phase locked", "phase 2" },
	"Phase 1 is open. Later phases unlock as you use a fighter, and evolving can cost Money. The price is shown first. In the Training Studio every phase is free to try.")
add("meterfill", "Phases", { "meter fill", "fill meter", "meter slow", "meter full" },
	"The phase meter fills when you land hits and also when you take them, so the fighter who is behind can catch up.")

-- Places ----------------------------------------------------------------------------------------
add("lobby", "Places", { "lobby", "hall", "hub", "spawn", "where am" },
	"The lobby is the big hall you spawn in. Fighting is off here, so look around. The doors around it lead to the Test Chambers, Training Studio, shop, fighters, lounge and bases.")
add("train", "Places", { "train", "training", "practice", "dummy", "where train" },
	"Walk through the TRAINING STUDIO door. Fighting is allowed, dummies are waiting, and every fighter and phase is free to try. Nothing is saved there.")
add("jefferypractice", "Places", { "practice jeffery", "spar", "fight jeffery", "sparring" },
	"You can practise a real fight against a sparring unit that looks like me. Open How to Play and press Practice with Jeffery. Nothing is saved or at stake.")
add("fight", "Places", { "find match", "start match", "queue", "test chambers", "play match", "fight player", "battle" },
	"Walk through the TEST CHAMBERS door, or press PLAY. Pick a mode, and the game finds opponents or a computer fighter for you.")
add("modes", "Places", { "modes", "game mode", "duel", "free for all", "ffa", "cpu practice" },
	"There are three modes. Duel is one against one. Free-for-All has three or four fighters. CPU Practice is a safe fight against the computer.")
add("arenas", "Places", { "arena", "maps", "battleground", "stage", "proving grounds", "digital grid", "soul foundry" },
	"Fights happen in arenas such as the Proving Grounds, Ruined Fortress, Digital Grid, Corrupted Wastes and Soul Foundry. Each one looks and feels different.")
add("win", "Places", { "how win", "score", "knockout", "sudden death", "who wins", "tie" },
	"Knock out opponents to score. When time runs out, the most knockouts wins. In a tie, sudden death decides it: the next knockout wins.")
add("lounge", "Places", { "lounge", "spectate", "watch match", "watch fights", "spectating" },
	"Walk through the SPECTATING LOUNGE door to watch live matches from the comfy seats.")
add("bases", "Places", { "base", "my base", "player base", "house", "plot", "home", "street" },
	"Walk through the PLAYER BASE STREET door to find your own base and visit friends' bases. Your base is yours to decorate as the game allows.")
add("jefferybase", "Places", { "jeffery base", "learn door", "how to play window", "where learn" },
	"My door is JEFFERY'S BASE. It opens How to Play. I also stand in the hall by it, so come and say hello.")
add("fightersroom", "Places", { "calibration", "calibration chamber", "fighter room", "meet fighters" },
	"The CALIBRATION CHAMBER door opens fighter selection, where you can look at every fighter and phase.")
add("archive", "Places", { "archive", "lore", "story", "book", "hidden file", "recovered file" },
	"The Archive is a lore book that stands in the hall. Hidden files are scattered around the facility. Finding them unlocks more of the story. I will not spoil where they are.")
add("secrets", "Places", { "secret", "easter egg", "hidden", "cheat code" },
	"There might be secrets. I am a very talkative robot, but I never tell those.")
add("events", "Places", { "event", "season", "halloween", "christmas", "holiday", "limited time" },
	"The facility changes with the seasons and special events. Check GIFTS and the season pass to see what is on now.")

-- Money, shop and rewards --------------------------------------------------------------------------
add("money", "Rewards", { "money", "how earn money", "get money", "coins", "cash" },
	"You earn Money from matches and from daily challenges. Money buys things in the shop and pays for some phases.")
add("gems", "Rewards", { "gems", "how earn gems", "get gems", "gem" },
	"You earn Gems by winning your first match each day, by levelling up a fighter, and from some daily challenges and gifts. You can also buy them in the shop.")
add("daily", "Rewards", { "daily challenge", "daily", "challenge", "daily quest" },
	"Daily challenges are small goals that reset each day. Finish one, claim it, and you get a reward. Open PLAY to see today's list.")
add("xp", "Rewards", { "level", "level up", "xp", "experience", "mastery" },
	"Every fighter levels up as you use it. Levels unlock abilities and phases, and each level reached gives a few Gems.")
add("shop", "Shop", { "shop", "buy", "store", "master shop", "purchase" },
	"Open the MASTER SHOP. Every price is shown before you confirm, and nothing is a mystery box or a countdown trick.")
add("robux", "Shop", { "robux", "real money", "pay", "spend", "free to play", "cost" },
	"The game is free to play and every fighter can be tried in training. The shop sells cosmetics and premium fighters, and you always see the price first.")
add("lootbox", "Shop", { "loot box", "lootbox", "mystery box", "random", "gamble", "crate" },
	"There are no mystery boxes here. You always know exactly what you are buying.")
add("refund", "Shop", { "refund", "money back", "wrong purchase", "bought by mistake" },
	"Roblox handles purchases and refunds. Please ask Roblox support about a refund.")
add("freestuff", "Shop", { "free robux", "free gems", "give me", "give items", "free money", "free stuff" },
	"I cannot give out items, Money, Gems or Robux. Those only come from playing, the gift calendar and the shop.")
add("gifts", "Rewards", { "gift", "calendar", "gifts", "daily reward", "login reward" },
	"GIFTS is the gift calendar. Open it on a new day to claim something. Missing a day is fine.")
add("locker", "Rewards", { "locker", "cosmetic", "outfit", "look", "skin", "equip" },
	"The LOCKER holds your cosmetics, titles and achievements. Pick what you want to wear or show off.")
add("pass", "Rewards", { "season pass", "pass", "battle pass", "tier", "premium track" },
	"The season pass has 30 tiers of cosmetics. You rise by playing matches, training and finishing daily challenges. The premium track adds more cosmetics and nothing that affects fighting.")
add("achievements", "Rewards", { "achievement", "achievements", "trophy", "badge" },
	"Achievements are goals for things like wins and perfect defenses. Open the LOCKER and look at its Achievements tab.")
add("titles", "Rewards", { "title", "titles", "recruit", "nameplate" },
	"Titles show next to your name. You get Recruit for finishing my tour. Founding Recruit goes to players who join before the end of 2026.")
add("founding", "Rewards", { "founding recruit", "founder", "founding" },
	"Founding Recruit is a title for players who first joined the facility before the end of 2026.")
add("welcomegift", "Rewards", { "welcome gift", "welcome reward", "tour reward", "starter reward", "like reward" },
	"Finish my tour and you get the Recruit title and some Money. It never depends on liking or favouriting the game. If you do enjoy it, a like on the game page helps us grow.")
add("likegoals", "Rewards", { "reward liking game", "community goal", "like goal", "reward favourite game", "reward favorite game", "reward thumbs", "reward liked game" },
	"Nobody gets a reward just for liking the game, and the game cannot see who liked it. Likes help us reach community goals instead. When the game reaches a goal, every player gets its reward, whether they liked it or not. The goals are on the board by the entrance.")
add("invite", "Social", { "invite friends", "invite", "play friends", "play with friends", "friends" },
	"Press PLAY and use the Invite friends button to send a friend a note. You can also visit friends' bases on Player Base Street.")

-- Problems and safety ----------------------------------------------------------------------------------
add("stuck", "Help", { "stuck", "cannot move", "trapped", "fell", "glitch" },
	"Try resetting your character: press Esc, then Reset Character. The ENTRANCE door in the hall also takes you back to the spawn.")
add("lag", "Help", { "lag", "slow", "fps", "freezing", "low performance" },
	"Open SETTINGS and turn on Reduced effects. Closing other apps and lowering your Roblox graphics also helps.")
add("report", "Help", { "report", "bug", "problem", "something wrong", "broken" },
	"For a bug, tell the team on the game page with what you pressed and what happened. For a rude player, press Esc and choose Report in the Roblox menu.")
add("cheater", "Help", { "report hacker", "report player", "report cheater", "cheater", "hacker", "exploit", "hacking", "rude player", "toxic", "mean" },
	"Press Esc and use Report in the Roblox menu for a rude player or someone cheating. The server checks every fight, so cheats do not work for long.")
add("lost", "Help", { "lost progress", "progress gone", "data lost", "missing item", "save" },
	"Your progress saves to your account automatically. If something is missing, tell the team on the game page with what happened.")
add("jeffery_cannot", "Help", { "ban player", "teleport player", "run command", "hack game", "make admin", "make owner", "kick player" },
	"I can only talk. I cannot give items, Money, Gems, admin rights, or change the game for anyone.")
add("sorry", "Chat", { "you wrong", "bad answer", "you dumb", "not helpful" },
	"Sorry about that. Open How to Play for the full guide, or try asking in other words.")

-- Matching --------------------------------------------------------------------------------------

local STOP = {}
for word in string.gmatch("a an the i me my we you your is am are do does did can could would should will to of in on at for with and or but it its this that these those how what where when why which who please tell about there be so if just want need get got let us some any", "%a+") do
	STOP[word] = true
end

-- Lower case, plural and common endings removed, so "dodging", "dodges" and "dodge" agree
local function stem(word: string): string
	if #word > 4 and string.sub(word, -3) == "ies" then
		word = string.sub(word, 1, -4) .. "y"
	elseif #word > 3 and string.sub(word, -1) == "s" and string.sub(word, -2) ~= "ss" then
		word = string.sub(word, 1, -2)
	end
	if #word > 5 and string.sub(word, -3) == "ing" then
		word = string.sub(word, 1, -4)
		if string.sub(word, -1) == string.sub(word, -2, -2) then
			word = string.sub(word, 1, -2)
		end
	end
	if #word > 3 and string.sub(word, -1) == "e" then
		word = string.sub(word, 1, -2)
	end
	return word
end

-- The content words of a text, stemmed. keepStops keeps even stop words (used for short patterns
-- made only of stop words, like "how you" or "hi").
function Knowledge.tokens(text: string, keepStops: boolean?): { string }
	local list = {}
	for word in string.gmatch(string.lower(text), "[%a%d]+") do
		if keepStops or not STOP[word] then
			table.insert(list, stem(word))
		end
	end
	return list
end

local compiled: { { entry: any, patterns: { { words: { string }, size: number, weak: boolean } } } }? = nil

local function compile()
	if compiled then
		return compiled
	end
	local list = {}
	for _, entry in Knowledge.Entries do
		local patterns = {}
		for _, text in entry.patterns do
			local words = Knowledge.tokens(text)
			local weak = false
			if #words == 0 then
				-- Only stop words ("how you", "who you"): usable, but any real word beats them
				words, weak = Knowledge.tokens(text, true), true
			end
			table.insert(patterns, { words = words, size = if weak then 0.4 else #words, weak = weak })
		end
		table.insert(list, { entry = entry, patterns = patterns })
	end
	compiled = list
	return list
end

-- The best entry for a question: (entry, score), or nil. Score = words of the best matching
-- pattern, plus 0.1 for each further pattern that also matches. Ties go to the earlier entry.
function Knowledge.match(text: string): (any?, number)
	local words = Knowledge.tokens(text)
	local set = {}
	for _, word in words do
		set[word] = true
	end
	local fullSet = {}
	for _, word in Knowledge.tokens(text, true) do
		fullSet[word] = true
	end
	local best, bestScore = nil, 0
	for _, item in compile() do
		local top, extra = 0, 0
		for _, pattern in item.patterns do
			local ok = #pattern.words > 0
			local have = if pattern.weak then fullSet else set
			for _, word in pattern.words do
				if not have[word] then
					ok = false
					break
				end
			end
			if ok then
				if pattern.size > top then
					extra += if top > 0 then 1 else 0
					top = pattern.size
				else
					extra += 1
				end
			end
		end
		local score = if top > 0 then top + 0.1 * extra else 0
		if score > bestScore then
			best, bestScore = item.entry, score
		end
	end
	return best, bestScore, #words
end

-- Sample questions shown as buttons in the Ask Jeffery panel
Knowledge.Suggestions = {
	"How do I move?",
	"What are phases?",
	"How do I change fighters?",
	"Where do I train?",
	"How do I earn Gems?",
	"What is the season pass?",
}

-- The facts as one block of text, for the AI provider's system prompt
function Knowledge.reference(): string
	local lines = {}
	for _, entry in Knowledge.Entries do
		table.insert(lines, `- {entry.topic}: {entry.answer}`)
	end
	return table.concat(lines, "\n")
end

return Knowledge
