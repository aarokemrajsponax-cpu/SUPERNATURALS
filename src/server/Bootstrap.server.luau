-- Starts every server service in a fixed order. Each service gets Init(services)
-- to grab references to the others, then Start() to begin running.

local Services = script.Parent.Services

local ORDER = {
	"AntiExploitService",
	"DataService",
	"CurrencyService",
	"PurchaseService",
	"WorldService",
	"ArenaService",
	"CharacterService",
	"DamageService",
	"StatusService",
	"CombatService",
	"ProjectileService",
	"ConstructService",
	"DefenseService",
	"PowerService",
	"AbilityService",
	"CpuService",
	"DummyService",
	"MatchService",
	"ProgressionService",
	"LoreService",
	"AdminEventService",
	"OwnerService",
}

local services = {}
for _, name in ORDER do
	services[name] = require(Services[name])
end
for _, name in ORDER do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end
for _, name in ORDER do
	local service = services[name]
	if service.Start then
		task.spawn(service.Start, service)
	end
end
