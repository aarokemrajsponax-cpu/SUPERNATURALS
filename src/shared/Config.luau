local Config = {}

Config.GameName = "SUPERNATURALS"

-- Seasonal Sync picks the holiday from today's date automatically.
-- To preview a holiday in Studio, put its name here, for example:
--   Config.ForceSeason = "Christmas"
-- Options: "Halloween", "Thanksgiving", "Christmas", "NewYears",
--          "Valentines", "StPatricks", "Easter"
-- Set it back to nil before publishing.
Config.ForceSeason = nil :: string?

return Config
