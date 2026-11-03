-- Music the game may play: only tracks verified on 3 November 2026 through Roblox's asset API as
-- audio uploaded by Roblox's licensed music partners (APMOfficial, Monstercat) and public. Ids come
-- from the owner's list (MASTER_REQUIREMENTS.md, P.S. 7.0); see docs/specs/Audio_verified.md for every
-- id that was checked and why the others are not here. Names are Roblox's own. Playback is not
-- checked here: the sound system must handle a track that fails to load (skip it, keep silent).
-- Categories: Chill (lobby, lounge), Classical (lounge, Archive), Electronic and Rock (battle),
-- SciFi and Cinematic (ambience, tension), Seasonal, Funny (light moments).

local AudioLibrary = {}

AudioLibrary.Tracks = {
	{ id = 1837768517, name = "Bossa Me (a)", category = "Chill", creator = "APMOfficial" },
	{ id = 1845341094, name = "Chill Jazz", category = "Chill", creator = "APMOfficial" },
	{ id = 1839019142, name = "Drum And Bass", category = "Chill", creator = "APMOfficial" },
	{ id = 1840511219, name = "Funky Fanfare", category = "Chill", creator = "APMOfficial" },
	{ id = 9047050075, name = "Lo Fi Dreams Hip Hop", category = "Chill", creator = "APMOfficial" },
	{ id = 9043887091, name = "Lo-fi Chill A", category = "Chill", creator = "APMOfficial" },
	{ id = 1841979451, name = "Piano Bar Jazz (a)", category = "Chill", creator = "APMOfficial" },
	{ id = 9046863253, name = "Poolside", category = "Chill", creator = "APMOfficial" },
	{ id = 1837769001, name = "Retro Gamer (60)", category = "Chill", creator = "APMOfficial" },
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
	{ id = 5409360995, name = "Dion Timmer - Shiawase", category = "Electronic", creator = "Monstercat" },
	{ id = 9044545570, name = "Night Run", category = "Electronic", creator = "APMOfficial" },
	{ id = 7024220835, name = "Nitro Fun - Easter Egg", category = "Electronic", creator = "Monstercat" },
	{ id = 7024233823, name = "Nitro Fun feat. Danyka Nadeau - Safe & Sound", category = "Electronic", creator = "Monstercat" },
	{ id = 5410086218, name = "Noisestorm - Crab Rave", category = "Electronic", creator = "Monstercat" },
	{ id = 1846368080, name = "Stadium Rave (A)", category = "Electronic", creator = "APMOfficial" },
	{ id = 1836105293, name = "Tender Tropical House", category = "Electronic", creator = "APMOfficial" },
	{ id = 1837015626, name = "Tokyo Drift", category = "Electronic", creator = "APMOfficial" },
	{ id = 1839444520, name = "Cat Chase", category = "Funny", creator = "APMOfficial" },
	{ id = 1837014514, name = "Everything", category = "Rock", creator = "APMOfficial" },
	{ id = 1835383046, name = "Franche Info", category = "Rock", creator = "APMOfficial" },
	{ id = 1842801942, name = "Full Force", category = "Rock", creator = "APMOfficial" },
	{ id = 1839612139, name = "Invincible Champion", category = "Rock", creator = "APMOfficial" },
	{ id = 1840821490, name = "Lazy Day Blues", category = "Rock", creator = "APMOfficial" },
	{ id = 1844634116, name = "Frozen Planet", category = "SciFi", creator = "APMOfficial" },
	{ id = 1841592252, name = "Ghostly Night b", category = "SciFi", creator = "APMOfficial" },
	{ id = 9039981149, name = "Horror", category = "SciFi", creator = "APMOfficial" },
	{ id = 1836272467, name = "Horror Pantomime", category = "SciFi", creator = "APMOfficial" },
	{ id = 1837057495, name = "Mutronic Plague", category = "SciFi", creator = "APMOfficial" },
	{ id = 1838635121, name = "Sad End (Solo Piano)", category = "SciFi", creator = "APMOfficial" },
	{ id = 1845149698, name = "Seek & Destroy", category = "SciFi", creator = "APMOfficial" },
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
