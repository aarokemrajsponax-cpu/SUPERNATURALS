-- Helpers every effect uses to change the world and put it back exactly.

local Env = {}

-- Remembers the listed properties of `instance`; the returned function restores them
function Env.capture(instance: Instance, names: { string }): () -> ()
	local saved = {}
	for _, name in names do
		saved[name] = (instance :: any)[name]
	end
	return function()
		for name, value in saved do
			pcall(function()
				(instance :: any)[name] = value
			end)
		end
	end
end

-- Blends two numbers
function Env.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Env.lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

function Env.rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return Env
