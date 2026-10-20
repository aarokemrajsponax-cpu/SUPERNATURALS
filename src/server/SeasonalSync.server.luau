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

	-- Clients and other scripts react to this
	ReplicatedStorage:SetAttribute(Seasons.ATTRIBUTE, id or Seasons.NONE)
end

applySeason(Seasons.getCurrentId())

while true do
	task.wait(CHECK_INTERVAL)
	local id = Seasons.getCurrentId()
	if id ~= currentId then
		applySeason(id)
	end
end
