-- Starts every client controller in a fixed order: Init(controllers) to grab
-- references, then Start() to begin running.

local Controllers = script.Parent.Controllers

local ORDER = {
	"CameraController",
	"EffectsController",
	"PowerFxController",
	"CombatController",
	"AbilityController",
	"InputController",
	"DefenseController",
	"UIController",
	"WorldFxController",
	"AdminEffectsController",
	"OwnerController",
}

local controllers = {}
for _, name in ORDER do
	controllers[name] = require(Controllers[name])
end
for _, name in ORDER do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end
for _, name in ORDER do
	local controller = controllers[name]
	if controller.Start then
		task.spawn(controller.Start, controller)
	end
end
