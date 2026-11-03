-- The Nexus: the lobby everyone spawns into. It is now the facility's central hub, an
-- enclosed octagonal atrium built by World/Hub.luau (see its header for the plan, the eight
-- portals and the "Guides" waypoint folder). This module keeps the public API the rest of
-- the code uses: Nexus.build(folder) -> SpawnLocation, Nexus.Gates, Nexus.Radius and
-- Nexus.TrainingCenter. The earlier open-air Sanctum build is in git history.

local Hub = require(script.Parent.Hub)

local Nexus = {}

Nexus.Radius = Hub.Radius
Nexus.TrainingCenter = Hub.TrainingCenter
Nexus.Gates = Hub.Gates

function Nexus.build(folder: Instance): SpawnLocation
	return Hub.build(folder)
end

return Nexus
