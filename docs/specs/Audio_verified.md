# Audio ids from the master prompt (P.S. 7.0), checked 3 November 2026

Every id was looked up in Roblox's public asset API (economy.roblox.com/v2/assets/<id>/details):
all 115 are audio assets. Tier A: uploaded by Roblox's licensed music partners (APMOfficial,
Monstercat) and public, so any experience may use them; these are in
src/shared/Config/AudioLibrary.luau. Tier B: public uploads by other accounts; Roblox lets any
experience play them, but who holds the music rights is not something the API can show, so
they stay out of the game unless the owner listens and decides (the master prompt bans
copyrighted or ripped music). Tier X: not public, cannot be used. Actual playback still needs
one listen in Studio (the API cannot check that).

| Tier | Category | Name (from Roblox) | Id | Creator |
|---|---|---|---|---|
| A | Classical / Piano / Orchestral | Chaos | 1843497734 | APMOfficial |
| A | Classical / Piano / Orchestral | Clair De Lune | 1838457617 | APMOfficial |
| A | Classical / Piano / Orchestral | Gymnopedie No. 1 | 9045766377 | APMOfficial |
| A | Classical / Piano / Orchestral | Hallelujah From Messiah | 1846627271 | APMOfficial |
| A | Classical / Piano / Orchestral | Kinderszenen - Traumerei | 1842155223 | APMOfficial |
| A | Classical / Piano / Orchestral | Morning Mood (f."peer Gynt Suite No.1") | 1846088038 | APMOfficial |
| A | Classical / Piano / Orchestral | Nocturne Opus 9 C | 1848028342 | APMOfficial |
| A | Classical / Piano / Orchestral | Nocturne in E-Flat Major, Op. 9, No. 2 | 9045765634 | APMOfficial |
| A | Classical / Piano / Orchestral | The Four Seasons - Spring (a) | 9045766074 | APMOfficial |
| A | Classical / Piano / Orchestral | Toreador From Carmen C | 1847795501 | APMOfficial |
| A | Classical / Piano / Orchestral | Turkish March | 1842150151 | APMOfficial |
| A | Electronic / EDM / Competitive | Dion Timmer - Shiawase | 5409360995 | Monstercat |
| A | Electronic / EDM / Competitive | Night Run | 9044545570 | APMOfficial |
| A | Electronic / EDM / Competitive | Nitro Fun - Easter Egg | 7024220835 | Monstercat |
| A | Electronic / EDM / Competitive | Nitro Fun feat. Danyka Nadeau - Safe & Sound | 7024233823 | Monstercat |
| A | Electronic / EDM / Competitive | Noisestorm - Crab Rave | 5410086218 | Monstercat |
| A | Electronic / EDM / Competitive | Stadium Rave (A) | 1846368080 | APMOfficial |
| A | Electronic / EDM / Competitive | Tender Tropical House | 1836105293 | APMOfficial |
| A | Electronic / EDM / Competitive | Tokyo Drift | 1837015626 | APMOfficial |
| A | Funny / Meme-Style | Cat Chase | 1839444520 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Bossa Me (a) | 1837768517 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Chill Jazz | 1845341094 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Drum And Bass | 1839019142 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Funky Fanfare | 1840511219 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Lo Fi Dreams Hip Hop | 9047050075 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Lo-fi Chill A | 9043887091 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Piano Bar Jazz (a) | 1841979451 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Poolside | 9046863253 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Retro Gamer (60) | 1837769001 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Sunset Chill (Bed Version) | 9046862941 | APMOfficial |
| A | Lo-Fi / Chill / Jazz | Tender Chillstep | 1836098504 | APMOfficial |
| A | Official Roblox documentation examples | Night Vision | 1837849285 | APMOfficial |
| A | Official Roblox documentation examples | Phantom At The Opera | 1843463175 | APMOfficial |
| A | Official Roblox documentation examples | Very Very Legendary A | 1848183670 | APMOfficial |
| A | Rock / Metal / Arena Energy | Everything | 1837014514 | APMOfficial |
| A | Rock / Metal / Arena Energy | Franche Info | 1835383046 | APMOfficial |
| A | Rock / Metal / Arena Energy | Full Force | 1842801942 | APMOfficial |
| A | Rock / Metal / Arena Energy | Invincible Champion | 1839612139 | APMOfficial |
| A | Rock / Metal / Arena Energy | Lazy Day Blues | 1840821490 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Frozen Planet | 1844634116 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Ghostly Night b | 1841592252 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Horror | 9039981149 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Horror Pantomime | 1836272467 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Mutronic Plague | 1837057495 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Sad End (Solo Piano) | 1838635121 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Seek & Destroy | 1845149698 | APMOfficial |
| A | Sci-Fi / Cinematic / Atmospheric | Sneeky | 1846531998 | APMOfficial |
| A | Seasonal | A Christmas Fantasy (a) | 1841343148 | APMOfficial |
| A | Seasonal | Christmas Tree | 1838667764 | APMOfficial |
| A | Seasonal | Classic Easter | 1836009208 | APMOfficial |
| A | Seasonal | Halloween Horrors Waltz | 1836009626 | APMOfficial |
| A | Seasonal | Winter Holidays | 9046740461 | APMOfficial |
| B | Electronic / EDM / Competitive | Candyland | 112791021679473 | DistrokidOfficial |
| B | Electronic / EDM / Competitive | Ghost Protocol | 140658568629873 | DistrokidOfficial |
| B | Electronic / EDM / Competitive | Hope | 99445078556609 | DistrokidOfficial |
| B | Electronic / EDM / Competitive | Infectious | 79451196298919 | DistrokidOfficial |
| B | Electronic / EDM / Competitive | Life | 111531789034719 | DistrokidOfficial |
| B | Funny / Meme-Style | Balloon Pop 3 (SFX) | 9113263649 | ProSoundEffects |
| B | Funny / Meme-Style | Brow###### | 185590931 | FlashyTheWonder |
| B | Funny / Meme-Style | CC collect 1 | 320118175 | zKevin |
| B | Funny / Meme-Style | ChestCloseSqueakSoundEffect | 152042590 | itachi5036 |
| B | Funny / Meme-Style | Click | 140910211 | Keyrut |
| B | Funny / Meme-Style | CollectCoin | 137478153 | FlashyTheWonder |
| B | Funny / Meme-Style | Computer Alarm Rapid Rizzy Beeps Constant 2 (SFX) | 9113865831 | ProSoundEffects |
| B | Funny / Meme-Style | Deny | 140910216 | Keyrut |
| B | Funny / Meme-Style | Funny Dance | 138915681911522 | DistrokidOfficial |
| B | Funny / Meme-Style | Ghost Wind Slow Build And Decay Swirling 2 (SFX) | 9114574159 | ProSoundEffects |
| B | Funny / Meme-Style | Goofy Song | 128598190743578 | DistrokidOfficial |
| B | Funny / Meme-Style | HitMarker | 160432334 | jimmy2602 |
| B | Funny / Meme-Style | Lamp Switch Pull Chain Slow Fast Pulls 15 (SFX) | 9116216027 | ProSoundEffects |
| B | Funny / Meme-Style | Mega Man 5 charge shot sound | 199077102 | Bad_atgames |
| B | Funny / Meme-Style | Power Throb Tonal Hum Slow Pulse Electrical  (SFX) | 9125784811 | ProSoundEffects |
| B | Funny / Meme-Style | Roblox MEME Song | 92535058455508 | DistrokidOfficial |
| B | Funny / Meme-Style | Robot Footsteps Walking Slowly Metal Surface (SFX) | 9125818616 | ProSoundEffects |
| B | Funny / Meme-Style | Sci Fi Transformation Synth Tones Slow Swirl (SFX) | 9125898973 | ProSoundEffects |
| B | Funny / Meme-Style | Silly Dance Meme XXI | 139413640343848 | DistrokidOfficial |
| B | Funny / Meme-Style | Sonic ScrewDriver Pop up sound [2010-2012] | 135878083 | InceptionTime |
| B | Funny / Meme-Style | Synth Tone Constant Big Pulsing Slow Low Pit (SFX) | 9126084278 | ProSoundEffects |
| B | Funny / Meme-Style | Thunder Distant Boom Thud Rapid Hits 20 (SFX) | 9120018172 | ProSoundEffects |
| B | Funny / Meme-Style | Time Wave Intense Fluttering Slow Down 1 (SFX) | 9120059060 | ProSoundEffects |
| B | Funny / Meme-Style | Time Wave Ripple Slow 2 (SFX) | 9120061266 | ProSoundEffects |
| B | Funny / Meme-Style | VVVVVV: "Jump" | 164188197 | Repotted |
| B | Funny / Meme-Style | Valve Squeak Slow Metal Squeaks Valve Turnin (SFX) | 9126152717 | ProSoundEffects |
| B | Funny / Meme-Style | Windows_Balloon (Windows 10) | 255881176 | Z9R |
| B | Funny / Meme-Style | hintmark | 150975887 | Aurarus |
| B | Funny / Meme-Style | menubeep | 150975800 | Aurarus |
| B | Lo-Fi / Chill / Jazz | Oceanic Lofi | 139031824972373 | DistrokidOfficial |
| B | Lo-Fi / Chill / Jazz | Spooky LoFi | 119338609842850 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | 67 KID PHONK | 125476440612900 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | AURA = ∞ (Brazilian Phonk/Funk Epic Aura Music) | 95131770144654 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Bouncy Trap House | 140158652733698 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Brainrot Gang Rap | 137248948744544 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | DRIFT NIGHT PHONK (Car Motion Edit) | 85735197482652 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | FUNK FESTA | 103409297553965 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Football Edit – Phonk Trap | 140504265985079 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Lost Phonk | 139266399633943 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | ROBLOX PHONK | 136932193331774 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Rat Dance Phonk | 119598380829349 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | SHADOW PHONK BRAZIL (Dark Atmosphere Edit) | 77701977147898 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Silly Cat Vibes | 137296865428573 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | TIKI TIKI FUNK (Sped Up) | 128510578554487 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | TOMA FUNK PHONK | 129098116998483 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | TUNG TUNG TUNG SAHUR FUNK RAP | 120968328156745 | DistrokidOfficial |
| B | Phonk / Bass / Rivalry | Tung Tung Tung Sahur Phonk | 128438366056581 | DistrokidOfficial |
| B | Rock / Metal / Arena Energy | Better Without You (Pop Rock) | 94895289573229 | DistrokidOfficial |
| B | Rock / Metal / Arena Energy | Boss Fight! | 78744747224727 | DistrokidOfficial |
| B | Rock / Metal / Arena Energy | Summer Never Said Goodbye (Soft Pop Rock) | 139763441568341 | DistrokidOfficial |
| B | Rock / Metal / Arena Energy | The Girl Who Never Quit (Arena Pop Rock) | 75504842694880 | DistrokidOfficial |
| B | Sci-Fi / Cinematic / Atmospheric | A RETRO SOUL (NOW, SLOP) | 116457974828068 | DistrokidOfficial |
| B | Sci-Fi / Cinematic / Atmospheric | CITY BUNCH | 138682282241619 | DistrokidOfficial |
| B | Sci-Fi / Cinematic / Atmospheric | Dark Fantasy - Slowed + Reverb | 134479750307568 | DistrokidOfficial |
| B | Sci-Fi / Cinematic / Atmospheric | Lobby in Slow Time | 138524894251708 | DistrokidOfficial |
| B | Sci-Fi / Cinematic / Atmospheric | Slow Breathing Aurora (Space Ambient) | 140041908508788 | DistrokidOfficial |
| B | Sci-Fi / Cinematic / Atmospheric | Slow Waves of Incoming Pixels | 138934492920017 | DistrokidOfficial |
| X | Sci-Fi / Cinematic / Atmospheric | The World Revolving | 89967120507744 | DistrokidOfficial |
