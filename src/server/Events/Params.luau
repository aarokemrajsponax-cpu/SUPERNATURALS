-- Parameter schemas for event effects. Every value that reaches an effect (from a preset, an
-- owner override or a message from another server) passes through Params.clean first.
-- Values are plain data (numbers, strings, booleans, {r,g,b} arrays) so they travel in
-- MessagingService payloads unchanged.
--
-- A spec is one of:
--   { type = "number", min, max, default, scales = true? }   (scales: the intensity override applies)
--   { type = "enum", values = {..}, default }
--   { type = "color", default = {r,g,b} }                    (tint: the colour override applies)
--   { type = "string", maxLen, default }                      (letters, digits, spaces, . ! ' -)
--   { type = "bool", default }

local Params = {}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cleanColor(value: any): { number }?
	if type(value) ~= "table" or #value ~= 3 then
		return nil
	end
	local out = {}
	for index = 1, 3 do
		local channel = value[index]
		if not isFinite(channel) or channel < 0 or channel > 255 then
			return nil
		end
		out[index] = math.floor(channel + 0.5)
	end
	return out
end

-- Returns the cleaned table (defaults filled in), or nil and a reason
function Params.clean(schema: { [string]: any }, input: any, intensity: number?, tint: { number }?): ({ [string]: any }?, string?)
	if input ~= nil and type(input) ~= "table" then
		return nil, "params_not_table"
	end
	input = input or {}
	for key in input do
		if type(key) ~= "string" or schema[key] == nil then
			return nil, `unknown_param:{tostring(key)}`
		end
	end
	local out = {}
	for name, spec in schema do
		local value = input[name]
		if value == nil then
			value = spec.default
		end
		local kind = spec.type
		if kind == "number" then
			if not isFinite(value) or value < spec.min or value > spec.max then
				return nil, `bad_number:{name}`
			end
			if spec.scales and intensity then
				value = math.clamp(value * intensity, spec.min, spec.max)
			end
		elseif kind == "enum" then
			if table.find(spec.values, value) == nil then
				return nil, `bad_enum:{name}`
			end
		elseif kind == "color" then
			local color = cleanColor(value)
			if not color then
				return nil, `bad_color:{name}`
			end
			value = tint or color
		elseif kind == "string" then
			if type(value) ~= "string" or #value > spec.maxLen or string.find(value, "[^%w %.!'%-]") then
				return nil, `bad_string:{name}`
			end
		elseif kind == "bool" then
			if type(value) ~= "boolean" then
				return nil, `bad_bool:{name}`
			end
		else
			return nil, `bad_spec:{name}`
		end
		out[name] = value
	end
	return out
end

-- Validates the owner's per-activation overrides
function Params.cleanOverrides(input: any): ({ [string]: any }?, string?)
	if input == nil then
		return {}
	end
	if type(input) ~= "table" then
		return nil, "overrides_not_table"
	end
	local out = {}
	for key, value in input do
		if key == "duration" then
			if not isFinite(value) or value < 0 or value > 21600 then
				return nil, "bad_duration"
			end
			out.duration = math.floor(value)
		elseif key == "intensity" then
			if not isFinite(value) or value < 0.25 or value > 2 then
				return nil, "bad_intensity"
			end
			out.intensity = value
		elseif key == "color" then
			local color = cleanColor(value)
			if not color then
				return nil, "bad_color"
			end
			out.color = color
		else
			return nil, `unknown_override:{tostring(key)}`
		end
	end
	return out
end

function Params.color3(value: { number }): Color3
	return Color3.fromRGB(value[1], value[2], value[3])
end

return Params
