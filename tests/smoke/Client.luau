-- Shared helpers for client smoke tests (tests/smoke_*.luau), so each area of
-- the game can have its own smoke file instead of everyone editing smoke.luau:
--   local Client = require("./smoke/Client")
--   local t = Client.load(process.args[1])
--   t.check("my window builds", function() local ui = t.startUI() ... end)
--   t.finish()
-- The helpers are the same ones tests/smoke.luau uses (press, findNamed,
-- findText, sentSince, auditLayout).

local process = require("@lune/process")
local roblox = require("@lune/roblox") :: any

local Engine = require("./Engine")

local Client = {}

local CLIENT = "StarterPlayer.StarterPlayerScripts.Client."
Client.CLIENT = CLIENT

function Client.load(placePath: string?)
	local world = Engine.load(placePath or "build/game.rbxl")
	local t: any = {
		world = world,
		game = world.game,
		task = Engine.task,
		Engine = Engine,
		roblox = roblox,
		CLIENT = CLIENT,
	}

	local passed, failed = 0, 0
	function t.check(name: string, fn: () -> ())
		local errorsBefore = #Engine.errors
		local ok, err = pcall(fn)
		-- Errors thrown inside game code's own threads count too
		if ok and #Engine.errors > errorsBefore then
			ok, err = false, "game code errored: " .. tostring(Engine.errors[errorsBefore + 1])
		end
		if ok then
			passed += 1
			print("ok   " .. name)
		else
			failed += 1
			print("FAIL " .. name)
			print("     " .. tostring(err))
		end
	end

	function t.finish()
		print(`\n{passed} passed, {failed} failed`)
		process.exit(if failed == 0 then 0 else 1)
	end

	-- A client module by its path under the client folder, e.g. "UI.Shell"
	function t.client(path: string)
		return world.require(world.find(CLIENT .. path))
	end

	function t.shared(path: string)
		return world.require(world.find("ReplicatedStorage.Shared." .. path))
	end

	function t.count(root, className: string): number
		local total = 0
		for _, item in root:GetDescendants() do
			if item:IsA(className) then
				total += 1
			end
		end
		return total
	end

	function t.press(button)
		Engine.signalOf(button, "Activated"):Fire()
	end

	function t.findNamed(root, name: string)
		for _, item in root:GetDescendants() do
			if item.Name == name then
				return item
			end
		end
		return nil
	end

	function t.findText(root, text: string)
		for _, item in root:GetDescendants() do
			if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text == text then
				return item
			end
		end
		return nil
	end

	-- Remote calls the client made since index `start` (see #Engine.sent)
	function t.sentSince(start: number, remote: string, first: any?)
		local found = {}
		for index = start + 1, #Engine.sent do
			local entry = Engine.sent[index]
			if entry.remote == remote and (first == nil or entry.args[1] == first) then
				table.insert(found, entry)
			end
		end
		return found
	end

	-- Every non-scaled text must wrap, cut off with "…" or grow to fit, and every
	-- control a finger can press must be at least 44 tall
	function t.auditLayout(root, label: string)
		local loose, small = {}, {}
		for _, item in root:GetDescendants() do
			if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" and not item.TextScaled then
				local fits = item.TextWrapped or item.TextTruncate ~= roblox.Enum.TextTruncate.None or item.AutomaticSize ~= roblox.Enum.AutomaticSize.None
				if not fits and utf8.len(item.Text) > 3 then
					table.insert(loose, item:GetFullName() .. ` "{item.Text}"`)
				end
			end
			if item:IsA("GuiButton") and item.Selectable and item.Size.Y.Scale == 0 and item.Size.Y.Offset < 44 then
				table.insert(small, item:GetFullName() .. " " .. tostring(item.Size.Y.Offset))
			end
		end
		assert(#loose == 0, `{label}: text that can overflow its box:\n       ` .. table.concat(loose, "\n       "))
		assert(#small == 0, `{label}: touch targets under 44px:\n       ` .. table.concat(small, "\n       "))
	end

	-- Fires a server -> client event on a remote, e.g. t.fire("DataEvent", "Profile", {...})
	function t.fire(remote: string, ...)
		Engine.signalOf(world.find("ReplicatedStorage.Remotes." .. remote), "OnClientEvent"):Fire(...)
	end

	-- Starts the real interface (UIController) with stand-ins for the controllers
	-- it talks to. Returns { gui, Shell, UIController, device = function(kind) }.
	-- Safe to call more than once: later calls return the same interface.
	local started = nil
	function t.startUI(profile: any?)
		if started then
			return started
		end
		local Input = t.client("Controllers.InputController")
		local deviceKind = "keyboard"
		local fakeInput = {
			Bindings = Input.Bindings,
			device = function()
				return deviceKind
			end,
		}
		local Abilities = t.client("Controllers.AbilityController")
		Abilities:Init({ PowerFxController = { predict = function() end }, InputController = fakeInput })
		local UIController = t.client("Controllers.UIController")
		UIController:Init({
			InputController = fakeInput,
			AbilityController = Abilities,
			EffectsController = {
				currentGuard = function()
					return 50
				end,
			},
		})
		UIController:Start()
		t.fire("DataEvent", "Profile", profile or {
			currencies = { money = 12000, gems = 6666 },
			selected = { power = "StrongDude", degree = 1 },
			settings = { cameraShake = true, uiScale = 1 },
		})
		Engine.task.wait(0.1)
		started = {
			gui = world.localPlayer.PlayerGui:FindFirstChild("SNInterface"),
			Shell = t.client("UI.Shell"),
			UIController = UIController,
			device = function(kind: string)
				deviceKind = kind
			end,
		}
		return started
	end

	-- Resizes the stand-in screen (the Shell rescales the interface)
	function t.setScreen(width: number, height: number)
		pcall(function()
			world.camera.ViewportSize = roblox.Vector2.new(width, height)
		end)
		Engine.signalOf(world.camera, "Property:ViewportSize"):Fire()
		Engine.task.wait(0.05)
	end

	return t
end

return Client
