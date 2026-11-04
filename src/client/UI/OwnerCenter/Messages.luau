-- Turns the server's refusal codes (see the header of src/server/Services/OverlordService.luau)
-- into plain sentences the owner can act on. Unknown codes fall back to the server's own message.

local Messages = {}

local TEXT: { [string]: string } = {
	not_owner = "Only the owner can do that.",
	bad_request = "The server could not read that request. Check the fields and try again.",
	bad_scope = "That server choice is not valid. Pick this server, all servers, test servers, or at least one listed server.",
	rate_limited = "Too many requests in a row. Wait a moment and try again.",
	unknown_preset = "That preset no longer exists. Reload the catalogue.",
	event_mode_required = "That preset changes gameplay, so it only runs in event mode.",
	match_in_progress = "A match is running, so gameplay changes are held back until it ends.",
	too_many_entries = "Too many presets in one activation. Eight is the most.",
	performance_cap = "That would push the server over its effect budget. Stop something first or pick a lighter preset.",
	global_sync_failed = "No other server confirmed the command. It may still be running on this server.",
	payload_too_large = "That request is too large. Use fewer or simpler settings.",
	filter_failed = "Roblox could not check that text, so nothing was sent.",
	text_filtered = "The Roblox filter changed or blocked that text. Use different words.",
	bad_time = "Pick a time between one minute and thirty days from now.",
	schedule_full = "The schedule is full. Cancel an item first.",
	unknown_item = "That item no longer exists.",
	not_pending = "That item already ran or was cancelled.",
	custom_limit = "You already have the most custom events allowed. Delete one first.",
	too_many_effects = "A custom event can have one to six effects.",
	unknown_effect = "That effect is not available.",
	unknown_server = "That server is no longer listed. Refresh the server list.",
	teleport_failed = "The teleport did not start. Try again.",
	store_failed = "The save did not go through. Try again.",
	busy = "The last request of this kind is still running. Try again in a moment.",
	timeout = "The server did not answer in time.",
	no_servers_picked = "Pick at least one server in the Server monitor first, or choose another scope.",
	bad_likes = "Enter a whole number from 0 to 1,000,000,000.",
	no_selection = "Nothing is selected yet.",
}

local function split(code: string): { string }
	local parts = {}
	for piece in string.gmatch(code, "[^:]+") do
		table.insert(parts, piece)
	end
	return parts
end

-- A sentence for a result table { ok, code?, message? }
function Messages.explain(result: any): string
	local code = if typeof(result) == "table" and typeof(result.code) == "string" then result.code else ""
	local parts = split(code)
	local head = parts[1] or ""
	if head == "incompatible_tags" and parts[2] and parts[3] then
		return `Those presets do not belong together ({parts[2]} and {parts[3]}).`
	elseif head == "channel_conflict" and parts[2] then
		return `Something already running uses the {parts[2]} channel{if parts[3] then " (" .. parts[3] .. ")" else ""}. Stop it first.`
	elseif head == "entries_conflict" and parts[2] then
		return `Two of the chosen presets use the same {parts[2]} channel. Remove one.`
	elseif head == "bad_params" then
		return `A setting is out of range{if parts[2] then " (" .. table.concat(parts, ", ", 2) .. ")" else ""}.`
	end
	local known = TEXT[head]
	if known then
		return known
	end
	if typeof(result) == "table" and typeof(result.message) == "string" and result.message ~= "" then
		return result.message
	end
	return if head ~= "" then `The server refused that request ({head}).` else "The server refused that request."
end

return Messages
