-- LOCKER (Shell window "Locker", reachable from the dock): what you own and what you can still
-- earn. Two tabs. Cosmetics lists every title, nameplate style, aura and knockout effect by
-- slot, owned first, each with the one plain line that says how to get it, and Wear / Take off
-- for the ones you own. Achievements lists every achievement with a progress bar and its reward.
-- Everything is read from the saved profile the server sends; wearing something is only a
-- request, the server checks it (CosmeticService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Components)
local Icons = require(script.Parent.Icons)
local Profile = require(script.Parent.Parent.Profile)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)

local make = Components.make
local Colors = Theme.Colors
local Space = Theme.Space

local LockerWindow = {}

LockerWindow.Slots = {
	{ slot = "title", heading = "Titles", empty = "No titles yet." },
	{ slot = "plate", heading = "Nameplate styles", empty = "No nameplate styles yet. They come from the season pass and special events." },
	{ slot = "aura", heading = "Auras", empty = "No auras yet." },
	{ slot = "knockout", heading = "Knockout effects", empty = "No knockout effects yet." },
}

LockerWindow.Tabs = {
	{ id = "cosmetics", label = "Cosmetics" },
	{ id = "achievements", label = "Achievements" },
}

local SOURCE_LABEL = {
	tutorial = "Tour",
	founder = "Founder",
	group = "Group",
	referral = "Invite",
	achievement = "Achievement",
	season = "Season pass",
	shop = "Shop",
	owner = "Special",
}

local function toColor(value: any): Color3?
	if typeof(value) ~= "table" or typeof(value[1]) ~= "number" or typeof(value[2]) ~= "number" or typeof(value[3]) ~= "number" then
		return nil
	end
	if value[1] > 1 or value[2] > 1 or value[3] > 1 then
		return Color3.fromRGB(value[1], value[2], value[3])
	end
	return Color3.new(value[1], value[2], value[3])
end

local function card(parent: Instance, name: string, order: number, locked: boolean): Frame
	local frame = make("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = if locked then 0.35 else 0,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		Components.corner(Theme.SmallCorner),
		Components.padding(Space.M, Space.M, Space.M, Space.L),
		make("UISizeConstraint", { MinSize = Vector2.new(0, 64) }),
	})
	return frame
end

local function build(body: Frame)
	local tab = "cosmetics"
	local lastEquip = 0

	local column = Components.scroll({ Name = "LockerColumn", Padding = 2, Parent = body })
	Components.list(column, Space.L)

	local top = make("Frame", { Name = "Top", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = column })
	local content = make("Frame", {
		Name = "Content", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Parent = column,
	})
	Components.list(content, Space.L)

	local function view(): { [string]: any }
		return Profile.get() or {}
	end

	local function equip(slot: string, id: string)
		if os.clock() - lastEquip < 0.35 then
			return
		end
		lastEquip = os.clock()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("CosmeticRequest")
		if remote then
			(remote :: RemoteEvent):FireServer(Protocol.CosmeticAction.Equip, slot, id)
		end
	end

	-- Cosmetics -----------------------------------------------------------------------------------
	local function itemRow(parent: Instance, order: number, item: any, owned: boolean, worn: boolean)
		local row = card(parent, "Item_" .. item.id, order, not owned)
		if worn then
			-- The worn item: the selected fill and a 3 px cyan bar on its left edge
			row.BackgroundColor3 = Colors.Selected
			make("Frame", {
				Name = "WornBar", Size = UDim2.new(0, 3, 1, Space.M * 2), Position = UDim2.fromOffset(-Space.L, -Space.M),
				BackgroundColor3 = Colors.Cyan, BorderSizePixel = 0, Parent = row,
			})
		end
		local text = make("Frame", {
			Name = "Text", Size = UDim2.new(1, -150, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = row,
		})
		Components.list(text, 4)
		local titleRow = make("Frame", { Name = "NameRow", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = text })
		Components.list(titleRow, Space.S, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
		if not owned then
			local lock = Icons.make("lock", 16, Colors.TextMuted)
			lock.LayoutOrder = 1
			lock.Parent = titleRow
		end
		local name = Components.text({
			Name = "Name", Text = item.name, Style = "strong", Color = if owned then Colors.Text else Colors.TextDim,
			Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, Parent = titleRow,
		})
		local _ = name
		if item.colors and #item.colors > 0 then
			local strip = make("Frame", { Name = "Colors", LayoutOrder = 3, Size = UDim2.fromOffset(#item.colors * 18, 6), BackgroundTransparency = 1, Parent = titleRow })
			Components.list(strip, 2, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center })
			for index, entry in item.colors do
				make("Frame", { Name = "Band" .. index, LayoutOrder = index, Size = UDim2.fromOffset(16, 4), BackgroundColor3 = toColor(entry) or Colors.Steel, BorderSizePixel = 0, Parent = strip })
			end
		end
		Components.text({ Name = "How", Text = item.how or "", Style = "small", Wrap = true, Color = Colors.TextDim, LayoutOrder = 2, Parent = text })
		if owned then
			Components.button(if worn then "Take off" else "Wear", {
				Name = if worn then "TakeOff" else "Wear",
				Variant = "Secondary",
				KeepCase = true,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -Space.L, 0.5, 0),
				Size = UDim2.fromOffset(120, 44),
				Parent = row,
			}, function()
				equip(item.kind, if worn then "" else item.id)
			end)
		else
			local tag = SOURCE_LABEL[item.source] or "Locked"
			local chip = Components.chip(tag, { Name = "Locked", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -Space.L, 0.5, 0), Color = Colors.TextMuted })
			chip.Parent = row
		end
	end

	local function buildCosmetics()
		local data = view()
		local cosmetics = data.cosmetics or {}
		local owned = cosmetics.owned or {}
		local equipped = cosmetics.equipped or {}
		for order, entry in LockerWindow.Slots do
			local section = make("Frame", {
				Name = "Slot_" .. entry.slot, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, Parent = content,
			})
			Components.list(section, Space.S)
			Components.text({ Name = "Heading", Text = entry.heading, Style = "heading", LayoutOrder = 0, Parent = section })
			local items = Cosmetics.ofKind(entry.slot)
			table.sort(items, function(a, b)
				local ao, bo = owned[a.id] == true, owned[b.id] == true
				if ao ~= bo then
					return ao
				end
				return a.name < b.name
			end)
			if #items == 0 then
				Components.text({ Name = "Empty", Text = entry.empty, Style = "body", Wrap = true, Color = Colors.TextMuted, LayoutOrder = 1, Parent = section })
			end
			for index, item in items do
				itemRow(section, index, item, owned[item.id] == true, equipped[entry.slot] == item.id and owned[item.id] == true)
			end
		end
	end

	-- Achievements ----------------------------------------------------------------------------------
	local function buildAchievements()
		local data = view()
		local doneCount = 0
		for _, def in Achievements.List do
			if Achievements.isDone(def, data) then
				doneCount += 1
			end
		end
		local summary = Components.text({
			Name = "Summary", Text = `{doneCount} of {#Achievements.List} achievements done`, Style = "strong", Color = Colors.TextDim, LayoutOrder = 0, Parent = content,
		})
		local _ = summary
		for groupOrder, group in Achievements.Groups do
			local section = make("Frame", {
				Name = "Group_" .. group, LayoutOrder = groupOrder, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, Parent = content,
			})
			Components.list(section, Space.S)
			Components.text({ Name = "Heading", Text = group, Style = "heading", LayoutOrder = 0, Parent = section })
			local order = 0
			for _, def in Achievements.List do
				if def.group == group then
					order += 1
					local done = Achievements.isDone(def, data)
					local value = math.min(Achievements.valueOf(def, data), def.goal)
					local row = card(section, "Achievement_" .. def.id, order, false)
					local column2 = make("Frame", { Name = "Column", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = row })
					Components.list(column2, 6)
					local head = make("Frame", { Name = "Head", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = column2 })
					Components.text({ Name = "Name", Text = def.name, Style = "strong", Color = if done then Colors.Success else Colors.Text, Size = UDim2.new(0.65, 0, 1, 0), Parent = head })
					Components.text({
						Name = "Count", Text = if done then "Done" else `{Achievements.format(def, value)} / {Achievements.format(def, def.goal)}`,
						Style = "number", Color = if done then Colors.Success else Colors.TextDim, AlignX = "Right",
						AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.35, 0, 1, 0), Parent = head,
					})
					Components.text({ Name = "Desc", Text = def.desc, Style = "small", Wrap = true, Color = Colors.TextDim, LayoutOrder = 2, Parent = column2 })
					local bar, set = Components.bar({ Name = "Bar", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 6) }, if done then Colors.Success else Colors.Accent)
					bar.Parent = column2
					set(value / def.goal)
					local reward = def.title and Cosmetics.get(def.title)
					if reward then
						Components.text({ Name = "Reward", Text = `Reward: the title {reward.name}`, Style = "caption", Color = Colors.TextMuted, LayoutOrder = 4, Parent = column2 })
					end
				end
			end
		end
	end

	local function refresh()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if tab == "cosmetics" then
			buildCosmetics()
		else
			buildAchievements()
		end
	end
	LockerWindow.refresh = refresh

	Components.segmented(nil, LockerWindow.Tabs, tab, function(id)
		tab = id
		refresh()
	end, { Name = "LockerTabs", Size = UDim2.new(0, 340, 0, 44), Parent = top })

	Profile.changed:Connect(function()
		if Shell.isOpen("Locker") then
			refresh()
		end
	end)
	refresh()

	return {
		onOpen = function()
			refresh()
		end,
	}
end

function LockerWindow.register()
	Shell.registerWindow("Locker", {
		title = "Locker",
		label = "LOCKER",
		icon = "user",
		order = 4,
		build = build,
	})
end

return LockerWindow
