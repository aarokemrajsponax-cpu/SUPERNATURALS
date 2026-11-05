-- Music by place: calm tracks in the hall and at home, piano and classical in the Spectating
-- Lounge, cinematic atmosphere in the Training Studio and the battleground concourse, and
-- driving electronic or rock in a fight. During a holiday a few of the season's tracks join
-- the calm playlists. Every track comes from Config/AudioLibrary (only ids verified as
-- Roblox's licensed library music). One Sound, crossfaded; a track that does not load in a
-- few seconds is skipped, and after several failures in a row the music stops quietly for
-- the session rather than retrying forever. Follows the Music volume setting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local AudioLibrary = require(ReplicatedStorage.Shared.Config.AudioLibrary)
local Match = require(ReplicatedStorage.Shared.Config.Match)
local Homes = require(ReplicatedStorage.Shared.Config.Homes)
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local Settings = require(script.Parent.Parent.Settings)
local Shell = require(script.Parent.Parent.UI.Shell)

local MusicController = {}

-- Which categories play where
-- (Retuned 4 Nov after the owner's playtest: energy in fights and the hall, calm where people chill)
local PLAYLISTS = {
	Hall = { "Electronic", "SciFi" },
	Lounge = { "Chill", "Pop", "Classical" },
	Bases = { "Chill", "Pop" },
	Training = { "Electronic", "Phonk" },
	Concourse = { "SciFi", "Cinematic", "Electronic" },
	Fight = { "Phonk", "Rock", "Electronic" },
}
-- Holiday tracks join the calm playlists; matched on Roblox's track names
local SEASON_WORDS = {
	Christmas = { "Christmas", "Winter" },
	NewYears = { "Winter" },
	Halloween = { "Halloween" },
	Easter = { "Easter" },
}
local CALM = { Hall = true, Lounge = true, Bases = true }

local BASE_VOLUME = 0.5
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
local LOAD_TIMEOUT = 8
local MAX_FAILURES = 4
local CHECK_EVERY = 1

-- Where the camera's subject is (rough zones; the hall is the default)
local LOUNGE_CENTER = Vector3.new(0, 0, 700)
local TRAINING_CENTER = Match.TrainingGround.Center
local CONCOURSE_X = 820

-- Inside a base whose owner chose a music style on the jukebox (attribute MusicStyle on the base
-- model, set by BaseService from a validated list), the zone reads "Bases:<Category>"
local function baseStyleAt(position: Vector3): string?
	local origin = Homes.BaseOrigin
	local slot = math.floor((position.X - origin.X + Homes.SlotSpacing / 2) / Homes.SlotSpacing) + 1
	if slot < 1 or slot > Homes.Slots or position.Z < origin.Z - 40 or position.Z > origin.Z + 60 then
		return nil
	end
	local model = workspace:FindFirstChild("Base_" .. slot)
	local style = model and model:GetAttribute("MusicStyle")
	return if typeof(style) == "string" and style ~= "" then style else nil
end

local function zoneAt(position: Vector3): string
	if Shell.getMode() == "Match" then
		return "Fight"
	end
	if (position - LOUNGE_CENTER).Magnitude < 160 then
		return "Lounge"
	end
	if (position - TRAINING_CENTER).Magnitude < 90 then
		return "Training"
	end
	-- Player Base Street and the homes beyond it are far out east
	local homes = Homes.BaseOrigin
	if (position - Homes.StreetCenter).Magnitude < 1400 or (position.X > homes.X - 400 and position.Z > homes.Z - 400) then
		local style = baseStyleAt(position)
		return if style then "Bases:" .. style else "Bases"
	end
	if position.X > CONCOURSE_X then
		return "Concourse"
	end
	return "Hall"
end

local function playlistFor(zone: string): { { [string]: any } }
	local list = {}
	local style = string.match(zone, "^Bases:(%a+)$")
	if style then
		zone = "Bases"
	end
	for _, category in if style then { style } else (PLAYLISTS[zone] or PLAYLISTS.Hall) do
		for _, track in AudioLibrary.inCategory(category) do
			table.insert(list, track)
		end
	end
	local season = Seasons.getActiveId()
	local words = season and SEASON_WORDS[season]
	if words and CALM[zone] then
		for _, track in AudioLibrary.inCategory("Seasonal") do
			for _, word in words do
				if string.find(track.name, word, 1, true) then
					table.insert(list, track)
					break
				end
			end
		end
	end
	return list
end

function MusicController:Start()
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Looped = false
	sound.Volume = 0
	sound.Parent = SoundService

	local zone = ""
	local queue: { { [string]: any } } = {}
	local failures = 0
	local stopped = false
	local token = 0

	-- A Sound property or call can fail (an engine without audio, a moderated asset): never let
	-- music break anything else
	local function loaded(): boolean
		local ok, value = pcall(function()
			return sound.IsLoaded
		end)
		return ok and value == true
	end

	local function target(): number
		local setting = Settings.get("musicVolume")
		return BASE_VOLUME * (if typeof(setting) == "number" and setting == setting then math.clamp(setting, 0, 1) else 0.5)
	end

	local function nextTrack(): { [string]: any }?
		if #queue == 0 then
			queue = playlistFor(zone)
			-- Shuffle so each visit sounds a little different
			for index = #queue, 2, -1 do
				local other = math.random(1, index)
				queue[index], queue[other] = queue[other], queue[index]
			end
		end
		return table.remove(queue)
	end

	local function play()
		if stopped then
			return
		end
		token += 1
		local mine = token
		local track = nextTrack()
		if not track then
			return
		end
		pcall(function()
			sound:Stop()
			sound.SoundId = AudioLibrary.uri(track)
			sound.Volume = 0
		end)
		local started = os.clock()
		task.spawn(function()
			while not loaded() and os.clock() - started < LOAD_TIMEOUT and mine == token do
				task.wait(0.25)
			end
			if mine ~= token then
				return
			end
			if not loaded() then
				failures += 1
				if failures >= MAX_FAILURES then
					stopped = true
					return
				end
				play()
				return
			end
			failures = 0
			pcall(function()
				sound:Play()
				TweenService:Create(sound, FADE, { Volume = target() }):Play()
			end)
		end)
	end

	pcall(function()
		sound.Ended:Connect(function()
			play()
		end)
	end)

	local function switchTo(newZone: string)
		if newZone == zone then
			return
		end
		zone = newZone
		queue = {}
		pcall(function()
			TweenService:Create(sound, FADE, { Volume = 0 }):Play()
		end)
		local mine = token
		task.delay(FADE.Time, function()
			if mine == token then
				play()
			end
		end)
	end

	Settings.changed:Connect(function(key)
		if key == "musicVolume" then
			pcall(function()
				if sound.IsPlaying then
					sound.Volume = target()
				end
			end)
		end
	end)

	task.spawn(function()
		local player = Players.LocalPlayer
		while not stopped do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local camera = workspace.CurrentCamera
			local position = if root and root:IsA("BasePart") then root.Position elseif camera then camera.CFrame.Position else Vector3.zero
			switchTo(zoneAt(position))
			task.wait(CHECK_EVERY)
		end
	end)
end

return MusicController
