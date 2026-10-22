-- TEMP: training hall being rebuilt
local Common = require(script.Parent.Common)
local TrainingHall = {}
function TrainingHall.build(center: Vector3): (Model, { CFrame })
	local model = Instance.new("Model")
	model.Name = "TrainingGround"
	Common.block(model, "Floor", Vector3.new(34, 1, 44), CFrame.new(center), Color3.new(0.3, 0.3, 0.3), Enum.Material.Slate)
	local spots = {}
	for _, z in { -12, 0, 12 } do
		local position = center + Vector3.new(-4, 3.5, z)
		table.insert(spots, CFrame.lookAt(position, position + Vector3.new(1, 0, 0)))
	end
	return model, spots
end
return TrainingHall
