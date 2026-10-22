-- This client's copy of its saved data (money, gems, unlocked powers,
-- loadouts, base, settings...). The server sends a safe copy whenever it
-- changes; screens read it here and listen to `changed`. It's for display only:
-- every purchase or unlock is still checked by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DataEvent = Remotes:WaitForChild("DataEvent") :: RemoteEvent

local Profile = {}

local current: { [string]: any }? = nil
-- Whether the server can save progress (false in Studio without API access)
Profile.saving = true
Profile.savingMessage = nil :: string?

local changedEvent = Instance.new("BindableEvent")
local persistenceEvent = Instance.new("BindableEvent")
local rewardEvent = Instance.new("BindableEvent")
local toastEvent = Instance.new("BindableEvent")
-- Fires with the new profile view
Profile.changed = changedEvent.Event
-- Fires with (saving: boolean, message: string?)
Profile.persistenceChanged = persistenceEvent.Event
-- Fires with the reward summary after a match
Profile.rewarded = rewardEvent.Event
-- Fires with (text, kind) for short messages from the server
Profile.toasted = toastEvent.Event

function Profile.get(): { [string]: any }?
	return current
end

-- Runs callback(view) now if the profile has arrived, otherwise once it does
function Profile.whenReady(callback: ({ [string]: any }) -> ())
	if current then
		task.spawn(callback, current)
		return
	end
	local connection
	connection = Profile.changed:Connect(function(view)
		connection:Disconnect()
		callback(view)
	end)
end

-- Small helpers screens use a lot
function Profile.currency(kind: string): number
	local currencies = current and current.currencies
	local value = currencies and currencies[kind]
	return if typeof(value) == "number" then value else 0
end

function Profile.powerData(powerId: string): { [string]: any }
	local powers = current and current.powers
	local data = powers and powers[powerId]
	return if typeof(data) == "table" then data else {}
end

DataEvent.OnClientEvent:Connect(function(kind, data)
	if kind == Protocol.DataEvent.Profile and typeof(data) == "table" then
		current = data
		changedEvent:Fire(data)
	elseif kind == Protocol.DataEvent.Persistence and typeof(data) == "table" then
		Profile.saving = data.saving ~= false
		Profile.savingMessage = if typeof(data.message) == "string" then data.message else nil
		persistenceEvent:Fire(Profile.saving, Profile.savingMessage)
	elseif kind == Protocol.DataEvent.Reward and typeof(data) == "table" then
		rewardEvent:Fire(data)
	elseif kind == Protocol.DataEvent.Toast and typeof(data) == "table" and typeof(data.text) == "string" then
		toastEvent:Fire(data.text, if typeof(data.kind) == "string" then data.kind else "info")
	end
end)

return Profile
