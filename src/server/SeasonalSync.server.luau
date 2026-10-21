-- Seasonal Sync: switches the game's lighting and decorations to match the
-- current holiday, and checks every minute so live servers change over on time.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Seasons = require(ReplicatedStorage.Shared.Seasons)
local SeasonalDecor = require(script.Parent.SeasonalDecor)

local CHECK_INTERVAL = 60

local LIGHTING_PROPERTIES = {
	"ClockTime",
	"Brightness",
	"Ambient",
	"OutdoorAmbient",
	"ColorShift_Top",
	"ColorShift_Bottom",
	"ExposureCompensation",
}
local ATMOSPHERE_PROPERTIES = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }
local EFFECTS = {
	colorCorrection = "ColorCorrectionEffect",
	bloom = "BloomEffect",
	sunRays = "SunRaysEffect",
}

-- Remember how the place looked so we can put it back when a holiday ends
local originalLighting = {}
for _, name in LIGHTING_PROPERTIES do
	originalLighting[name] = Lighting[name]
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local ownsAtmosphere = false
local originalAtmosphere = {}
if atmosphere then
	for _, name in ATMOSPHERE_PROPERTIES do
		originalAtmosphere[name] = atmosphere[name]
	end
end

local function resetLighting()
	for name, value in originalLighting do
		Lighting[name] = value
	end

	if atmosphere and ownsAtmosphere then
		atmosphere:Destroy()
		atmosphere = nil
		ownsAtmosphere = false
	elseif atmosphere then
		for name, value in originalAtmosphere do
			atmosphere[name] = value
		end
	end

	for _, child in Lighting:GetChildren() do
		if child:GetAttribute("Seasonal") then
			child:Destroy()
		elseif child:GetAttribute("PausedForSeason") then
			-- The place's own effect comes back once the holiday's is gone
			child:SetAttribute("PausedForSeason", nil)
			;(child :: any).Enabled = true
		end
	end
end

local function applyLighting(theme)
	for name, value in theme.lighting do
		Lighting[name] = value
	end

	if theme.atmosphere then
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Parent = Lighting
			ownsAtmosphere = true
		end
		for name, value in theme.atmosphere do
			atmosphere[name] = value
		end
	end

	for key, className in EFFECTS do
		local settings = theme[key]
		if settings then
			-- A holiday's effect replaces the place's own one of the same kind (no double glow)
			for _, child in Lighting:GetChildren() do
				if child.ClassName == className and not child:GetAttribute("Seasonal") and (child :: any).Enabled then
					;(child :: any).Enabled = false
					child:SetAttribute("PausedForSeason", true)
				end
			end
			local effect = Instance.new(className)
			effect.Name = "Seasonal" .. className
			effect:SetAttribute("Seasonal", true)
			for name, value in settings do
				effect[name] = value
			end
			effect.Parent = Lighting
		end
	end
end

local currentId: string? = nil

-- The time of day: the owner's choice if they made one, else the season's
local OWNER_CLOCK = "SNOwnerClockTime"
local BASE_PREFIX = "SNBase_"
local function applyClock()
	local override = Lighting:GetAttribute(OWNER_CLOCK)
	if typeof(override) == "number" then
		Lighting.ClockTime = override
	end
	-- Tell clients what the lighting should be, so they can return to it after
	-- an admin event changed theirs
	for _, name in { "ClockTime", "Brightness", "OutdoorAmbient" } do
		Lighting:SetAttribute(BASE_PREFIX .. name, Lighting[name])
	end
end

local function applySeason(id: string?)
	resetLighting()
	SeasonalDecor.clear()
	currentId = id

	local theme = Seasons.getTheme(id)
	if theme then
		applyLighting(theme)
		SeasonalDecor.build(id :: string)
		print(`[Seasons] {theme.icon} {theme.name} is live!`)
	else
		print("[Seasons] No holiday right now, using the normal look.")
	end

	applyClock()
	-- Clients and other scripts react to this
	ReplicatedStorage:SetAttribute(Seasons.ATTRIBUTE, id or Seasons.NONE)
end

applySeason(Seasons.getCurrentId())

-- The owner panel's time of day (clearing it goes back to the season's time)
Lighting:GetAttributeChangedSignal(OWNER_CLOCK):Connect(function()
	if Lighting:GetAttribute(OWNER_CLOCK) == nil then
		local theme = Seasons.getTheme(currentId)
		Lighting.ClockTime = if theme and theme.lighting.ClockTime then theme.lighting.ClockTime else originalLighting.ClockTime
	end
	applyClock()
end)

-- The owner panel can switch seasons instantly
ReplicatedStorage:GetAttributeChangedSignal("SeasonOverride"):Connect(function()
	local id = Seasons.getCurrentId()
	if id ~= currentId then
		applySeason(id)
	end
end)

while true do
	task.wait(CHECK_INTERVAL)
	local id = Seasons.getCurrentId()
	if id ~= currentId then
		applySeason(id)
	end
end
