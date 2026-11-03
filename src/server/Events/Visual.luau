-- Builds an effect module for visuals that the clients draw. The server only publishes a
-- small record (ctx.publish) under ReplicatedStorage.OverlordFx; src/client/Overlord draws it.
-- Stopping removes the record, and every client cleans up what it drew.

local Visual = {}

function Visual.module(definition: {
	channels: { string },
	group: string,
	cost: any,
	params: { [string]: any },
	ownerOnly: boolean?,
}, id: string)
	return {
		id = id,
		channels = definition.channels,
		group = definition.group,
		cost = definition.cost,
		params = definition.params,
		ownerOnly = definition.ownerOnly or false,
		gameplay = false,
		start = function(ctx, params)
			return ctx.publish(id, params)
		end,
	}
end

return Visual
