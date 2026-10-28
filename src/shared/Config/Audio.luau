-- Sound placeholders. These point at sounds built into Roblox (rbxasset://), so they
-- work without uploading anything, but they are stand-ins: swap in proper combat
-- sounds from the Creator Store by replacing the ids below. nil means silent.

local Audio = {}

Audio.Sounds = {
	LightSwing = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.35, Pitch = 1.6 },
	HeavySwing = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.5, Pitch = 0.8 },
	Hit = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.9, Pitch = 1.5 },
	HeavyHit = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Pitch = 0.8 },
	Block = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.5, Pitch = 2.2 },
	Parry = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.7, Pitch = 1.2 },
	GuardBreak = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.8, Pitch = 0.6 },
	Dodge = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.25, Pitch = 2.2 },
	Countdown = nil :: { Id: string, Volume: number, Pitch: number }?,
	Knockout = nil :: { Id: string, Volume: number, Pitch: number }?,
}

return Audio
