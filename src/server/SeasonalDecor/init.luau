-- Builds and removes the decorations for each holiday.
-- To add decorations for a new season, add a module next to this one and list it below.

local Build = require(script.Build)

local builders = {
	Halloween = require(script.Halloween),
	Thanksgiving = require(script.Thanksgiving),
	Christmas = require(script.Christmas),
	NewYears = require(script.NewYears),
	Valentines = require(script.Valentines),
	StPatricks = require(script.StPatricks),
	Easter = require(script.Easter),
}

local FOLDER_NAME = "SeasonalDecor"

local SeasonalDecor = {}

function SeasonalDecor.clear()
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

function SeasonalDecor.build(id: string)
	SeasonalDecor.clear()
	local builder = builders[id]
	if not builder then
		return
	end

	-- Build everything first, then add it to the world in one go
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	local ok, err = pcall(builder, folder, Build)
	if not ok then
		warn(`[Seasons] Couldn't finish the {id} decorations: {err}`)
	end
	folder.Parent = workspace
end

return SeasonalDecor
