-- Sound effects. Every id below was found in Roblox's Creator Store (toolbox search API) and
-- checked on 4 November 2026 through Roblox's asset API (economy.roblox.com/v2/assets/<id>/details)
-- as a public audio asset uploaded by ProSoundEffects, a professional sound library that licenses
-- its effects for Roblox. Names in the comments are Roblox's own. Playback is not checked here:
-- Vfx.sound plays nothing if a sound fails to load. nil means silent.
-- Music is separate: Config/AudioLibrary.

local Audio = {}

export type Sound = { Id: string, Volume: number, Pitch: number }

local function psfx(id: number, volume: number, pitch: number?): Sound
	return { Id = "rbxassetid://" .. tostring(id), Volume = volume, Pitch = pitch or 1 }
end

Audio.Sounds = {
	-- Swings and hits (combat)
	LightSwing = psfx(9120709477, 0.35, 1.1), -- Whoosh Fast Short Dull Several
	HeavySwing = psfx(9125959352, 0.45), -- Slowed Whip Swishes Whomping
	Hit = psfx(9117969717, 0.8), -- Punch Kit Beefy Hit 3
	HeavyHit = psfx(9113566123, 0.95), -- Boxing Hits 19
	Block = psfx(9116488438, 0.55, 1.2), -- Meaty Thud 2
	Parry = psfx(9119072660, 0.7), -- Shield Clang As Hit Metal Sword
	GuardBreak = psfx(9114591567, 0.75), -- Glass Breaks 4
	Dodge = psfx(9126014962, 0.3), -- Swish Sweeteners Short Hissing
	-- Aiming: a soft ping on confirm, a lower blip on cancel
	TargetConfirm = psfx(9113649171, 0.3), -- Button Click And Ring 1
	TargetCancel = psfx(9116731116, 0.25, 0.9), -- Metallic Beeps Quick Tones 8
	-- Match flow
	Countdown = psfx(9117060548, 0.45), -- Nasa Transmission Beep 4
	Knockout = psfx(9113421646, 0.7), -- Bell Rings 1
	Crowd = psfx(9120974911, 0.35), -- Wrestling Crowd 1
	-- Ability families, for the fighters' effects
	GroundSlam = psfx(9118617342, 0.9), -- Rock Impact Large Hit Scrape
	Explosion = psfx(9126050116, 0.8), -- Synth Blast Space Explosion Reverb
	EnergyBlast = psfx(9114314399, 0.7), -- Energy Blasts 4
	EnergyCharge = psfx(9117297453, 0.5), -- Phasey Synth Power Up High Pitched
	Laser = psfx(9116225257, 0.55), -- Laser Blast 101
	Electric = psfx(9114277757, 0.55), -- Electric Zaps 12
	Magic = psfx(9125647212, 0.55), -- Magic Whooshes Pass Bys Metallic
	Teleport = psfx(9114340693, 0.55), -- Energy Pass By Sci Fi Tonal Whoosh
	Glitch = psfx(9114622474, 0.5), -- Glowing Start And Stop Fluttery By
	Gavel = psfx(9114559389, 0.8), -- Gavel Hits Big Impacts Reverbed
	Fire = psfx(9114446852, 0.6), -- Fire Whoosh 15
	-- Interface and rewards
	UIClick = psfx(9113649170, 0.25), -- Button Click And Ring 2
	UIConfirm = psfx(9119103680, 0.3), -- Shortwave Bleep Beeps Telemetry
	Coin = psfx(9113849492, 0.4), -- Coins Or Keys Jingle 6
	LevelUp = psfx(9119816710, 0.5), -- Synth Power Up Multi Tone Wind Ups
	Notification = psfx(9126123087, 0.3), -- Tone Clusters Mostly High Pitch
	PageTurn = psfx(9118835414, 0.4), -- Scrapbook Open And Turn Pages 2 (the Archive book)
	-- Jeffery
	RobotBeep = psfx(9118272977, 0.35), -- Robot Kalimba Technical Beep
	RobotStep = psfx(9118250959, 0.25), -- Robot Footsteps On Concrete 27
}

return Audio
