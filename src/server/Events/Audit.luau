-- Bounded audit log: the last N owner actions, kept in memory and in one DataStore key.
-- Every entry says who, what, where, which preset, when and how it ended.

local Audit = {}
Audit.__index = Audit

Audit.CAP = 200

function Audit.new(store, clock: () -> number, wait: (number) -> ())
	return setmetatable({ store = store, clock = clock, wait = wait, recent = {}, writes = 0, failures = 0 }, Audit)
end

local function trim(list: { any }, cap: number)
	while #list > cap do
		table.remove(list, 1)
	end
end

-- entry: { by = userId, action = string, scope = string, presets = { string }?, outcome = string, reason = string?, id = string? }
function Audit:record(entry)
	entry.t = self.clock()
	table.insert(self.recent, entry)
	trim(self.recent, Audit.CAP)
	if not self.store then
		return
	end
	for attempt = 1, 3 do
		local ok = pcall(function()
			self.store:UpdateAsync("log", function(old)
				local log = if type(old) == "table" then old else {}
				table.insert(log, entry)
				trim(log, Audit.CAP)
				return log
			end)
		end)
		if ok then
			self.writes += 1
			return
		end
		self.failures += 1
		self.wait(0.5 * 2 ^ (attempt - 1))
	end
end

-- Newest last; `limit` entries at most
function Audit:read(limit: number?): { any }
	local count = math.clamp(limit or 50, 1, Audit.CAP)
	local out = {}
	for i = math.max(1, #self.recent - count + 1), #self.recent do
		table.insert(out, self.recent[i])
	end
	return out
end

-- The persisted log (what survives a restart)
function Audit:readStored(): { any }
	if not self.store then
		return {}
	end
	local ok, log = pcall(function()
		return self.store:GetAsync("log")
	end)
	return if ok and type(log) == "table" then log else {}
end

return Audit
