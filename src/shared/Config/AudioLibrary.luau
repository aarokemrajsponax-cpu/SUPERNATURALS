-- Music the game may play: every track was checked on 3 November 2026 through Roblox's asset API
-- (economy.roblox.com/v2/assets/<id>/details) as a public audio asset uploaded by one of Roblox's
-- licensed music partners: APMOfficial, Monstercat or DistrokidOfficial (DistroKid's official
-- Roblox account for independent artists). Ids come from the owner's list (MASTER_REQUIREMENTS.md,
-- P.S. 7.0); docs/specs/Audio_verified.md records every id checked. Names are Roblox's own.
-- Playback is not checked here: MusicController skips a track that does not load.
-- Categories: Phonk, Rock and Electronic (fights, training), SciFi and Cinematic (the hall, the
-- concourse), Chill, Pop and Classical (the lounge, bases), Seasonal, Funny (meme events only).

local AudioLibrary = {}

AudioLibrary.Tracks = {
	{ id = 1837768517, name = "Bossa Me (a)", category = "Chill", creator = "APMOfficial" },
	{ id = 1845341094, name = "Chill Jazz", category = "Chill", creator = "APMOfficial" },
	{ id = 1839019142, name = "Drum And Bass", category = "Chill", creator = "APMOfficial" },
	{ id = 1840511219, name = "Funky Fanfare", category = "Chill", creator = "APMOfficial" },
	{ id = 9047050075, name = "Lo Fi Dreams Hip Hop", category = "Chill", creator = "APMOfficial" },
	{ id = 9043887091, name = "Lo-fi Chill A", category = "Chill", creator = "APMOfficial" },
	{ id = 139031824972373, name = "Oceanic Lofi", category = "Chill", creator = "DistrokidOfficial" },
	{ id = 1841979451, name = "Piano Bar Jazz (a)", category = "Chill", creator = "APMOfficial" },
	{ id = 9046863253, name = "Poolside", category = "Chill", creator = "APMOfficial" },
	{ id = 1837769001, name = "Retro Gamer (60)", category = "Chill", creator = "APMOfficial" },
	{ id = 119338609842850, name = "Spooky LoFi", category = "Chill", creator = "DistrokidOfficial" },
	{ id = 9046862941, name = "Sunset Chill (Bed Version)", category = "Chill", creator = "APMOfficial" },
	{ id = 1836098504, name = "Tender Chillstep", category = "Chill", creator = "APMOfficial" },
	{ id = 1837849285, name = "Night Vision", category = "Cinematic", creator = "APMOfficial" },
	{ id = 1843463175, name = "Phantom At The Opera", category = "Cinematic", creator = "APMOfficial" },
	{ id = 1848183670, name = "Very Very Legendary A", category = "Cinematic", creator = "APMOfficial" },
	{ id = 1843497734, name = "Chaos", category = "Classical", creator = "APMOfficial" },
	{ id = 1838457617, name = "Clair De Lune", category = "Classical", creator = "APMOfficial" },
	{ id = 9045766377, name = "Gymnopedie No. 1", category = "Classical", creator = "APMOfficial" },
	{ id = 1846627271, name = "Hallelujah From Messiah", category = "Classical", creator = "APMOfficial" },
	{ id = 1842155223, name = "Kinderszenen - Traumerei", category = "Classical", creator = "APMOfficial" },
	{ id = 1846088038, name = "Morning Mood (f.\"peer Gynt Suite No.1\")", category = "Classical", creator = "APMOfficial" },
	{ id = 1848028342, name = "Nocturne Opus 9 C", category = "Classical", creator = "APMOfficial" },
	{ id = 9045765634, name = "Nocturne in E-Flat Major, Op. 9, No. 2", category = "Classical", creator = "APMOfficial" },
	{ id = 9045766074, name = "The Four Seasons - Spring (a)", category = "Classical", creator = "APMOfficial" },
	{ id = 1847795501, name = "Toreador From Carmen C", category = "Classical", creator = "APMOfficial" },
	{ id = 1842150151, name = "Turkish March", category = "Classical", creator = "APMOfficial" },
	{ id = 112791021679473, name = "Candyland", category = "Electronic", creator = "DistrokidOfficial" },
	{ id = 5409360995, name = "Dion Timmer - Shiawase", category = "Electronic", creator = "Monstercat" },
	{ id = 140658568629873, name = "Ghost Protocol", category = "Electronic", creator = "DistrokidOfficial" },
	{ id = 99445078556609, name = "Hope", category = "Electronic", creator = "DistrokidOfficial" },
	{ id = 79451196298919, name = "Infectious", category = "Electronic", creator = "DistrokidOfficial" },
	{ id = 111531789034719, name = "Life", category = "Electronic", creator = "DistrokidOfficial" },
	{ id = 9044545570, name = "Night Run", category = "Electronic", creator = "APMOfficial" },
	{ id = 7024220835, name = "Nitro Fun - Easter Egg", category = "Electronic", creator = "Monstercat" },
	{ id = 7024233823, name = "Nitro Fun feat. Danyka Nadeau - Safe & Sound", category = "Electronic", creator = "Monstercat" },
	{ id = 5410086218, name = "Noisestorm - Crab Rave", category = "Electronic", creator = "Monstercat" },
	{ id = 1846368080, name = "Stadium Rave (A)", category = "Electronic", creator = "APMOfficial" },
	{ id = 1836105293, name = "Tender Tropical House", category = "Electronic", creator = "APMOfficial" },
	{ id = 1837015626, name = "Tokyo Drift", category = "Electronic", creator = "APMOfficial" },
	{ id = 125476440612900, name = "67 KID PHONK", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 137248948744544, name = "Brainrot Gang Rap", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 1839444520, name = "Cat Chase", category = "Funny", creator = "APMOfficial" },
	{ id = 138915681911522, name = "Funny Dance", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 128598190743578, name = "Goofy Song", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 119598380829349, name = "Rat Dance Phonk", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 92535058455508, name = "Roblox MEME Song", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 137296865428573, name = "Silly Cat Vibes", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 139413640343848, name = "Silly Dance Meme XXI", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 120968328156745, name = "TUNG TUNG TUNG SAHUR FUNK RAP", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 128438366056581, name = "Tung Tung Tung Sahur Phonk", category = "Funny", creator = "DistrokidOfficial" },
	{ id = 95131770144654, name = "AURA = ∞ (Brazilian Phonk/Funk Epic Aura Music)", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 140158652733698, name = "Bouncy Trap House", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 85735197482652, name = "DRIFT NIGHT PHONK (Car Motion Edit)", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 103409297553965, name = "FUNK FESTA", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 140504265985079, name = "Football Edit – Phonk Trap", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 139266399633943, name = "Lost Phonk", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 136932193331774, name = "ROBLOX PHONK", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 77701977147898, name = "SHADOW PHONK BRAZIL (Dark Atmosphere Edit)", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 128510578554487, name = "TIKI TIKI FUNK (Sped Up)", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 129098116998483, name = "TOMA FUNK PHONK", category = "Phonk", creator = "DistrokidOfficial" },
	{ id = 94895289573229, name = "Better Without You (Pop Rock)", category = "Pop", creator = "DistrokidOfficial" },
	{ id = 139763441568341, name = "Summer Never Said Goodbye (Soft Pop Rock)", category = "Pop", creator = "DistrokidOfficial" },
	{ id = 78744747224727, name = "Boss Fight!", category = "Rock", creator = "DistrokidOfficial" },
	{ id = 1837014514, name = "Everything", category = "Rock", creator = "APMOfficial" },
	{ id = 1835383046, name = "Franche Info", category = "Rock", creator = "APMOfficial" },
	{ id = 1842801942, name = "Full Force", category = "Rock", creator = "APMOfficial" },
	{ id = 1839612139, name = "Invincible Champion", category = "Rock", creator = "APMOfficial" },
	{ id = 1840821490, name = "Lazy Day Blues", category = "Rock", creator = "APMOfficial" },
	{ id = 75504842694880, name = "The Girl Who Never Quit (Arena Pop Rock)", category = "Rock", creator = "DistrokidOfficial" },
	{ id = 116457974828068, name = "A RETRO SOUL (NOW, SLOP)", category = "SciFi", creator = "DistrokidOfficial" },
	{ id = 138682282241619, name = "CITY BUNCH", category = "SciFi", creator = "DistrokidOfficial" },
	{ id = 134479750307568, name = "Dark Fantasy - Slowed + Reverb", category = "SciFi", creator = "DistrokidOfficial" },
	{ id = 1844634116, name = "Frozen Planet", category = "SciFi", creator = "APMOfficial" },
	{ id = 1841592252, name = "Ghostly Night b", category = "SciFi", creator = "APMOfficial" },
	{ id = 9039981149, name = "Horror", category = "SciFi", creator = "APMOfficial" },
	{ id = 1836272467, name = "Horror Pantomime", category = "SciFi", creator = "APMOfficial" },
	{ id = 138524894251708, name = "Lobby in Slow Time", category = "SciFi", creator = "DistrokidOfficial" },
	{ id = 1837057495, name = "Mutronic Plague", category = "SciFi", creator = "APMOfficial" },
	{ id = 1838635121, name = "Sad End (Solo Piano)", category = "SciFi", creator = "APMOfficial" },
	{ id = 1845149698, name = "Seek & Destroy", category = "SciFi", creator = "APMOfficial" },
	{ id = 140041908508788, name = "Slow Breathing Aurora (Space Ambient)", category = "SciFi", creator = "DistrokidOfficial" },
	{ id = 138934492920017, name = "Slow Waves of Incoming Pixels", category = "SciFi", creator = "DistrokidOfficial" },
	{ id = 1846531998, name = "Sneeky", category = "SciFi", creator = "APMOfficial" },
	{ id = 1841343148, name = "A Christmas Fantasy (a)", category = "Seasonal", creator = "APMOfficial" },
	{ id = 1838667764, name = "Christmas Tree", category = "Seasonal", creator = "APMOfficial" },
	{ id = 1836009208, name = "Classic Easter", category = "Seasonal", creator = "APMOfficial" },
	{ id = 1836009626, name = "Halloween Horrors Waltz", category = "Seasonal", creator = "APMOfficial" },
	{ id = 9046740461, name = "Winter Holidays", category = "Seasonal", creator = "APMOfficial" },
}

-- Tracks in one category, in the order above
function AudioLibrary.inCategory(category: string): { { [string]: any } }
	local list = {}
	for _, track in AudioLibrary.Tracks do
		if track.category == category then
			table.insert(list, track)
		end
	end
	return list
end

function AudioLibrary.uri(track: { id: number }): string
	return "rbxassetid://" .. tostring(track.id)
end

return AudioLibrary
