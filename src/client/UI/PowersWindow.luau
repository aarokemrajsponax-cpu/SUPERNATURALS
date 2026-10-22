-- The Powers window: choose one of the eight powers, a degree, and the
-- abilities to take into a fight. The left column lists the powers; the right
-- shows the chosen one: what it is and how it plays, mastery, its degrees
-- (three, or four for The Grandmaster, and what unlocks each), every ability with its cost, cooldown and
-- price, the loadout slots, the ultimate, and its defense identity. Premium
-- powers show their exact Robux price, the Gems path, and that they can be
-- tried free in Training and CPU Practice. A power's cosmetic pass (Celestial
-- Dragon Style) shows Roblox's live price, or "Not on sale yet".
-- Everything here only asks; the server checks ownership, prices and locks.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Profile = require(script.Parent.Parent.Profile)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PowerRequest = Remotes:WaitForChild("PowerRequest") :: RemoteEvent

local Action = Protocol.PowerAction
local Attribute = Protocol.Attribute
local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local player = Players.LocalPlayer

local PowersWindow = {}

local LIST_WIDTH = 236
local KIND_LABELS = {
	Melee = "Melee",
	Area = "Area",
	Grab = "Grab",
	Dash = "Dash",
	Projectile = "Projectile",
	Throw = "Throw",
	Counter = "Counter",
	Zone = "Zone",
	Buff = "Buff",
	Teleport = "Teleport",
	Form = "Form",
	Construct = "Construct",
	Ultimate = "Ultimate",
}

local function powerData(powerId: string): { [string]: any }
	return Profile.powerData(powerId)
end

local function isOwnerAccount(): boolean
	return player:GetAttribute(Attribute.IsOwner) == true
end

-- Does the player own this power outright (free powers always)?
local function owns(def): boolean
	if not def.premium then
		return true
	end
	if isOwnerAccount() then
		return true
	end
	local view = Profile.get()
	local passes = view and view.passes
	if typeof(passes) == "table" and passes[def.premium.pass] then
		return true
	end
	return powerData(def.id).owned == true
end

-- Live Robux prices of cosmetic passes (asked once; nil until Roblox answers, false if it can't)
local livePrices: { [string]: any } = {}

local function cosmeticPrice(passKey: string, onReady: () -> ()): (string, boolean)
	local pass = Monetization.Passes[passKey]
	if not pass or typeof(pass.id) ~= "number" or pass.id <= 0 then
		return "Not on sale yet", false
	end
	local known = livePrices[passKey]
	if known == nil then
		livePrices[passKey] = "pending"
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(pass.id, Enum.InfoType.GamePass)
			end)
			local price = ok and typeof(info) == "table" and info.PriceInRobux
			livePrices[passKey] = if typeof(price) == "number" and price > 0 then price else false
			onReady()
		end)
		return "Checking price", false
	elseif typeof(known) == "number" then
		return `R$ {Components.formatNumber(known)}`, true
	elseif known == "pending" then
		return "Checking price", false
	end
	return "Not on sale yet", false
end

local function ownsPass(passKey: string): boolean
	local view = Profile.get()
	local passes = view and view.passes
	return typeof(passes) == "table" and passes[passKey] == true
end

local function degreeOpen(def, degree: number): boolean
	return isOwnerAccount() or Powers.degreeUnlocked(def.id, degree, powerData(def.id))
end

local function savedLoadout(powerId: string, degree: number): { string }
	local view = Profile.get()
	local loadouts = view and view.loadouts
	local saved = typeof(loadouts) == "table" and loadouts[powerId]
	local list = typeof(saved) == "table" and saved[tostring(degree)]
	if typeof(list) == "table" then
		local ok, _, cleaned = Powers.validateLoadout(powerId, degree, list, powerData(powerId))
		if ok and cleaned then
			return cleaned
		end
	end
	return Powers.defaultLoadout(powerId, degree)
end

local function pips(count: number): string
	return string.rep("●", count) .. string.rep("○", 5 - count)
end

local function statsLine(ability, resourceName: string?): string
	local parts = {}
	if ability.kind == "Ultimate" then
		table.insert(parts, "Needs a full ultimate bar")
	else
		if (ability.cooldown or 0) > 0 then
			table.insert(parts, `⏱ {ability.cooldown}s`)
		end
		if (ability.cost or 0) > 0 then
			table.insert(parts, `{ability.cost} {resourceName or "energy"}`)
		end
	end
	if (ability.damage or 0) > 0 then
		table.insert(parts, `{ability.damage} damage`)
	end
	if ability.defense == "Timing" then
		table.insert(parts, "Timing-bar defense")
	elseif ability.defense == "Prompt" then
		table.insert(parts, "Dodge/block prompt")
	elseif ability.defense == "Mash" then
		table.insert(parts, "Mash to escape")
	end
	return table.concat(parts, "   ·   ")
end

function PowersWindow.register()
	Shell.registerWindow("Powers", {
		title = "Powers",
		label = "POWERS",
		icon = "✨",
		order = 2,
		size = Vector2.new(1000, 600),
		accent = Colors.Purple,
		build = function(body: Frame, api)
			local selectedPower = Powers.Default
			local selectedDegree = 1
			-- Unsaved loadout changes, per power and degree
			local drafts: { [string]: { string } } = {}
			local cards: { [string]: any } = {}

			local function draftKey(): string
				return `{selectedPower}/{selectedDegree}`
			end
			local function draft(): { string }
				local key = draftKey()
				if not drafts[key] then
					drafts[key] = savedLoadout(selectedPower, selectedDegree)
				end
				return drafts[key]
			end

			-- Left: the eight powers -------------------------------------------------
			local list = Components.scroll({
				Name = "PowerList",
				Size = UDim2.new(0, LIST_WIDTH, 1, 0),
				Padding = 2,
				Parent = body,
			})
			Components.list(list, Space.S)

			-- Right: the chosen power ----------------------------------------------------
			local detail = Components.scroll({
				Name = "PowerDetail",
				Position = UDim2.fromOffset(LIST_WIDTH + Space.L, 0),
				Size = UDim2.new(1, -(LIST_WIDTH + Space.L), 1, -60),
				Padding = 2,
				Parent = body,
			})
			local actions = make("Frame", {
				Name = "PowerActions",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.new(1, -(LIST_WIDTH + Space.L), 0, 48),
				BackgroundTransparency = 1,
				Parent = body,
			})
			Components.list(actions, Space.S, {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			})

			local render: () -> ()

			local function badgeFor(def): (string?, Color3?)
				local view = Profile.get()
				local selected = view and view.selected
				if typeof(selected) == "table" and selected.power == def.id then
					return "EQUIPPED", Colors.Success
				end
				if def.premium then
					if owns(def) then
						return "OWNED", Colors.Gold
					end
					return "PREMIUM", Colors.Gold
				end
				return nil, nil
			end

			local function renderList()
				for _, entry in cards do
					entry.frame:Destroy()
				end
				table.clear(cards)
				for order, powerId in Powers.Order do
					local def = Powers.get(powerId)
					if def then
						local badge, color = badgeFor(def)
						local frame, card = Components.card({
							LayoutOrder = order,
							Size = UDim2.new(1, 0, 0, 70),
							Accent = def.colors.primary,
							Icon = def.icon,
							Title = def.name,
							Body = def.tagline,
							Badge = badge,
							BadgeColor = color,
							Selected = powerId == selectedPower,
							onClick = function()
								selectedPower = powerId
								local view = Profile.get()
								local selected = view and view.selected
								selectedDegree = if typeof(selected) == "table" and selected.power == powerId then selected.degree else 1
								render()
							end,
						})
						frame.Parent = list
						cards[powerId] = { frame = frame, card = card }
					end
				end
			end

			-- One section heading
			local function heading(parent: Instance, order: number, text: string)
				Components.text({
					Text = text,
					Style = "Micro",
					Color = Colors.TextMuted,
					LayoutOrder = order,
					Parent = parent,
				})
			end

			local function send(...)
				PowerRequest:FireServer(...)
			end

			render = function()
				local def = Powers.get(selectedPower)
				if not def then
					return
				end
				-- A degree another power had (4) doesn't exist on a three-degree power
				if not Powers.validDegree(def.id, selectedDegree) then
					selectedDegree = 1
				end
				for powerId, entry in cards do
					entry.card.setSelected(powerId == selectedPower)
				end
				for _, child in detail:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for _, child in actions:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				if not detail:FindFirstChildOfClass("UIListLayout") then
					Components.list(detail, Space.M)
				end
				local accent = def.colors.primary
				local data = powerData(def.id)
				local owned = owns(def)
				local resourceName = if def.resource then def.resource.name else nil

				-- Hero: icon, name, tagline, style and difficulty
				local hero = make("Frame", {
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 72),
					BackgroundTransparency = 1,
					Parent = detail,
				})
				local tile = Components.iconTile(def.icon, 64, accent)
				tile.Parent = hero
				Components.text({
					Text = def.name,
					Style = "Title",
					Position = UDim2.fromOffset(78, 2),
					Size = UDim2.new(1, -78, 0, 32),
					Parent = hero,
				})
				Components.text({
					Text = `{def.tagline}   ·   {def.style}`,
					Style = "Caption",
					Position = UDim2.fromOffset(78, 34),
					Size = UDim2.new(1, -78, 0, 18),
					Parent = hero,
				})
				Components.text({
					Text = `Difficulty  {pips(def.difficulty)}`,
					Style = "Micro",
					Color = accent,
					Position = UDim2.fromOffset(78, 52),
					Size = UDim2.new(1, -78, 0, 16),
					Parent = hero,
				})

				Components.text({
					Text = def.description,
					Style = "Body",
					Color = Colors.TextDim,
					Wrap = true,
					LayoutOrder = 2,
					Parent = detail,
				})

				-- Premium: exact price, the Gems path, and the free trial
				if def.premium then
					local premium = make("Frame", {
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundColor3 = Colors.Gold,
						BackgroundTransparency = 0.9,
						Parent = detail,
					}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Gold, 1, 0.5) })
					Components.padding(Space.M).Parent = premium
					Components.list(premium, Space.XS)
					local note = if owned
						then `✅  You own {def.name}. It's yours in every mode.`
						else `👑  Premium power: unlocks for R$ {Components.formatNumber(def.premium.robux)} (a one-time game pass) or {Components.formatNumber(def.premium.gems)} Gems. You can try it free in Training and CPU Practice.`
					Components.text({ Text = note, Style = "Body", Wrap = true, LayoutOrder = 1, Parent = premium })
				end

				-- Cosmetic pass (looks only): what it changes, the live price, a buy button
				local cosmetic = def.cosmetic
				if cosmetic and cosmetic.pass then
					local panel = make("Frame", {
						Name = "CosmeticPass",
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundColor3 = Colors.Gold,
						BackgroundTransparency = 0.92,
						Parent = detail,
					}, { Components.corner(Theme.SmallCorner), Components.stroke(Colors.Gold, 1, 0.6) })
					Components.padding(Space.M).Parent = panel
					local textColumn = make("Frame", {
						Size = UDim2.new(1, -(170 + Space.M), 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Parent = panel,
					})
					Components.list(textColumn, Space.XS)
					Components.text({ Text = string.upper(cosmetic.name), Style = "Label", Wrap = true, LayoutOrder = 1, Parent = textColumn })
					Components.text({ Text = cosmetic.benefit, Style = "Caption", Color = Colors.TextDim, Wrap = true, LayoutOrder = 2, Parent = textColumn })
					local ownedStyle = ownsPass(cosmetic.pass)
					local priceText, onSale = cosmeticPrice(cosmetic.pass, function()
						if selectedPower == def.id and render then
							render()
						end
					end)
					local buy = Components.button(if ownedStyle then "OWNED" else priceText, {
						Name = "CosmeticBuy",
						Variant = if ownedStyle then "Secondary" else "Gold",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(1, 0.5),
						Size = UDim2.fromOffset(170, 44),
						TextSize = Theme.TextSize.Caption,
						Parent = panel,
					}, function()
						send(Action.PromptPass, def.id, "Cosmetic")
					end)
					if ownedStyle or not onSale then
						Components.setDisabled(buy, true)
					end
				end

				-- Mastery
				local xp = if typeof(data.xp) == "number" then data.xp else 0
				local level = Powers.masteryLevel(xp)
				local nextXp = Powers.nextLevelXp(xp)
				local thisXp = Powers.Mastery.Thresholds[level] or 0
				local progress, setProgress = Components.progress({
					LayoutOrder = 4,
					Label = `MASTERY LEVEL {level}`,
					Value = if nextXp then `{Components.formatNumber(xp)} / {Components.formatNumber(nextXp)} XP` else "MAX LEVEL",
					Size = UDim2.new(1, 0, 0, 36),
				}, accent)
				progress.Parent = detail
				setProgress(if nextXp then (xp - thisXp) / math.max(1, nextXp - thisXp) else 1)

				-- Degrees
				heading(detail, 5, "DEGREE")
				-- Three degrees sit in one row; four (The Grandmaster) in a 2 x 2 grid so names fit
				local degreeCount = Powers.degreeCount(def.id)
				local columns = if degreeCount > 3 then 2 else degreeCount
				local rows = math.ceil(degreeCount / columns)
				local degreeRow = make("Frame", {
					LayoutOrder = 6,
					Size = UDim2.new(1, 0, 0, rows * 48 + (rows - 1) * Space.S),
					BackgroundTransparency = 1,
					Parent = detail,
				})
				local grid = Instance.new("UIGridLayout")
				grid.CellPadding = UDim2.fromOffset(Space.S, Space.S)
				grid.CellSize = UDim2.new(1 / columns, -math.ceil(Space.S * (columns - 1) / columns), 0, 48)
				grid.SortOrder = Enum.SortOrder.LayoutOrder
				grid.FillDirection = Enum.FillDirection.Horizontal
				grid.Parent = degreeRow
				for degree = 1, degreeCount do
					local degreeDef = def.degrees[degree]
					local open = degreeOpen(def, degree)
					local chosen = degree == selectedDegree
					local button = Components.button(`{if open then "" else "🔒 "}{degree}  ·  {string.upper(degreeDef.name)}`, {
						LayoutOrder = degree,
						Variant = if chosen then "Primary" else "Secondary",
						Size = UDim2.new(1 / columns, -6, 1, 0),
						TextSize = Theme.TextSize.Caption,
					}, function()
						selectedDegree = degree
						render()
					end)
					button.Parent = degreeRow
				end
				local degreeDef = def.degrees[selectedDegree]
				Components.text({
					Text = degreeDef.description,
					Style = "Body",
					Color = Colors.TextDim,
					Wrap = true,
					LayoutOrder = 7,
					Parent = detail,
				})
				local degreeOpenNow = degreeOpen(def, selectedDegree)
				if not degreeOpenNow and degreeDef.unlock then
					local unlockRow = make("Frame", {
						LayoutOrder = 8,
						Size = UDim2.new(1, 0, 0, 48),
						BackgroundTransparency = 1,
						Parent = detail,
					})
					Components.text({
						Text = `🔒  Reach mastery level {degreeDef.unlock.mastery}, or unlock it now:`,
						Style = "Label",
						Size = UDim2.new(1, -200, 1, 0),
						Parent = unlockRow,
					})
					local unlock = Components.button(`UNLOCK  💵 {Components.formatNumber(degreeDef.unlock.money)}`, {
						Variant = "Gold",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(1, 0.5),
						Size = UDim2.fromOffset(190, 44),
						TextSize = Theme.TextSize.Caption,
						Parent = unlockRow,
					}, function()
						api.confirm({
							title = `Unlock {degreeDef.name}?`,
							body = `{def.name}'s Degree {selectedDegree} will be yours to use and equip.`,
							price = { money = degreeDef.unlock.money },
							confirmText = "Unlock",
							icon = def.icon,
							onConfirm = function()
								send(Action.UnlockDegree, def.id, selectedDegree)
							end,
						})
					end)
					if not Powers.degreeUnlocked(def.id, selectedDegree - 1, data) and not isOwnerAccount() then
						Components.setDisabled(unlock, true)
					end
				end

				-- Loadout slots
				local current = draft()
				heading(detail, 9, `LOADOUT  ·  {#current} / {degreeDef.slots} SLOTS  ·  CLICK AN ABILITY TO EQUIP OR REMOVE IT`)
				local slotRow = make("Frame", {
					LayoutOrder = 10,
					Size = UDim2.new(1, 0, 0, 52),
					BackgroundTransparency = 1,
					Parent = detail,
				})
				Components.list(slotRow, Space.S, { FillDirection = Enum.FillDirection.Horizontal })
				for slot = 1, degreeDef.slots do
					local abilityId = current[slot]
					local ability = abilityId and Powers.abilityFor(def.id, abilityId, selectedDegree)
					local chip = make("Frame", {
						LayoutOrder = slot,
						Size = UDim2.new(1 / degreeDef.slots, -Space.S, 1, 0),
						BackgroundColor3 = if ability then Colors.PanelLight else Colors.Panel,
						BackgroundTransparency = if ability then 0.1 else 0.4,
						Parent = slotRow,
					}, {
						Components.corner(Theme.SmallCorner),
						Components.stroke(if ability then accent else Colors.Stroke, 1.5, if ability then 0.3 else 0.8),
					})
					Components.padding(0, Space.S, 0, Space.S).Parent = chip
					Components.text({
						Text = if ability then `{slot}  {ability.icon}  {ability.name}` else `{slot}  Empty`,
						Style = "Caption",
						Weight = "Bold",
						Color = if ability then Colors.Text else Colors.TextMuted,
						Size = UDim2.fromScale(1, 1),
						Parent = chip,
					})
				end

				-- Abilities this degree can equip, then the ultimate
				heading(detail, 11, "ABILITIES")
				local order = 12
				local function abilityRow(ability, isUltimate: boolean)
					order += 1
					local abilityOwned = isUltimate or Powers.abilityOwned(def.id, ability.id, data, selectedDegree)
					local equipped = table.find(current, ability.id) ~= nil
					local rowAccent = if isUltimate then Colors.Gold else accent
					local row = make("Frame", {
						LayoutOrder = order,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundColor3 = Colors.PanelLight,
						BackgroundTransparency = if equipped or isUltimate then 0.15 else 0.45,
						Parent = detail,
					}, {
						Components.corner(Theme.SmallCorner),
						Components.stroke(if equipped or isUltimate then rowAccent else Colors.Stroke, 1.5, if equipped or isUltimate then 0.35 else 0.8),
					})
					Components.padding(Space.M, Space.M, Space.M, 64).Parent = row
					local rowTile = Components.iconTile(ability.icon, 40, rowAccent)
					rowTile.Position = UDim2.fromOffset(-52, 0)
					rowTile.Parent = row
					local textColumn = make("Frame", {
						Size = UDim2.new(1, -170, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						Parent = row,
					})
					Components.list(textColumn, 2)
					Components.text({
						Text = `{ability.name}   ·   {string.upper(KIND_LABELS[ability.kind] or ability.kind)}`,
						Style = "Label",
						Color = if isUltimate then Colors.Gold else Colors.Text,
						LayoutOrder = 1,
						Parent = textColumn,
					})
					Components.text({
						Text = ability.description,
						Style = "Caption",
						Wrap = true,
						LayoutOrder = 2,
						Parent = textColumn,
					})
					Components.text({
						Text = statsLine(ability, resourceName),
						Style = "Micro",
						Color = rowAccent,
						LayoutOrder = 3,
						Parent = textColumn,
					})
					-- Right side: buy, equip or remove
					local side = make("Frame", {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.fromOffset(158, 44),
						BackgroundTransparency = 1,
						Parent = row,
					})
					if isUltimate then
						Components.badge("ULTIMATE", Colors.Gold).Parent = side
					elseif not abilityOwned and ability.price then
						local priceText = if ability.price.gems then `💎 {Components.formatNumber(ability.price.gems)}` else `💵 {Components.formatNumber(ability.price.money)}`
						local buy = Components.button(`UNLOCK  {priceText}`, {
							Variant = "Gold",
							Size = UDim2.fromScale(1, 1),
							TextSize = Theme.TextSize.Caption,
							Parent = side,
						}, function()
							api.confirm({
								title = `Unlock {ability.name}?`,
								body = ability.description,
								price = ability.price,
								confirmText = "Unlock",
								icon = ability.icon,
								onConfirm = function()
									send(Action.UnlockAbility, def.id, ability.id)
								end,
							})
						end)
						if def.premium and not owned then
							Components.setDisabled(buy, true)
						end
					else
						Components.button(if equipped then "REMOVE" else "EQUIP", {
							Variant = if equipped then "Ghost" else "Secondary",
							Size = UDim2.fromScale(1, 1),
							TextSize = Theme.TextSize.Caption,
							Parent = side,
						}, function()
							local index = table.find(current, ability.id)
							if index then
								table.remove(current, index)
							elseif #current < degreeDef.slots then
								table.insert(current, ability.id)
							else
								api.toast(`All {degreeDef.slots} slots are full. Remove one first.`, "error")
								return
							end
							render()
						end)
					end
				end
				for _, abilityId in Powers.available(def.id, selectedDegree) do
					abilityRow(Powers.abilityFor(def.id, abilityId, selectedDegree), false)
				end
				local ultimate = Powers.ultimateOf(def.id, selectedDegree)
				if ultimate then
					abilityRow(Powers.abilityFor(def.id, ultimate, selectedDegree), true)
				end

				-- Defense identity: the power's counters and stances
				local counters = {}
				for _, abilityId in def.abilityOrder do
					local ability = def.abilities[abilityId]
					if ability and (ability.kind == "Counter" or ability.redirect) then
						table.insert(counters, `{ability.name} (Degree {ability.minDegree or 1}+)`)
					end
				end
				if #counters > 0 then
					Components.text({
						Text = `🛡️  Defense: {table.concat(counters, ", ")}, plus block, parry and dodge.`,
						Style = "Caption",
						Wrap = true,
						LayoutOrder = order + 1,
						Parent = detail,
					})
				end

				-- Actions: save the loadout and use this power at this degree
				local view = Profile.get()
				local selected = view and view.selected
				local isCurrent = typeof(selected) == "table" and selected.power == def.id and selected.degree == selectedDegree
				local saved = savedLoadout(def.id, selectedDegree)
				local changed = table.concat(saved, ",") ~= table.concat(current, ",")
				if def.premium and not owned then
					Components.button(`BUY  R$ {Components.formatNumber(def.premium.robux)}`, {
						LayoutOrder = 1,
						Variant = "Gold",
						Size = UDim2.fromOffset(170, 44),
						TextSize = Theme.TextSize.Caption,
						Parent = actions,
					}, function()
						send(Action.PromptPass, def.id)
					end)
					Components.button(`💎 {Components.formatNumber(def.premium.gems)} GEMS`, {
						LayoutOrder = 2,
						Variant = "Secondary",
						Size = UDim2.fromOffset(150, 44),
						TextSize = Theme.TextSize.Caption,
						Parent = actions,
					}, function()
						api.confirm({
							title = `Unlock {def.name} with Gems?`,
							body = `{def.name} becomes yours in every mode, all three degrees (each degree still unlocks with mastery or Money).`,
							price = { gems = def.premium.gems },
							confirmText = "Unlock",
							icon = def.icon,
							onConfirm = function()
								send(Action.UnlockPower, def.id)
							end,
						})
					end)
				end
				local save = Components.button("SAVE LOADOUT", {
					LayoutOrder = 3,
					Variant = "Secondary",
					Size = UDim2.fromOffset(150, 44),
					TextSize = Theme.TextSize.Caption,
					Parent = actions,
				}, function()
					send(Action.SetLoadout, def.id, selectedDegree, table.clone(current))
				end)
				Components.setDisabled(save, not changed or not degreeOpenNow or #current == 0)
				local use = Components.button(if isCurrent then "✓  IN USE" elseif def.premium and not owned then "TRY IT" else "USE THIS POWER", {
					LayoutOrder = 4,
					Variant = "Primary",
					Size = UDim2.fromOffset(170, 44),
					TextSize = Theme.TextSize.Caption,
					Parent = actions,
				}, function()
					if changed then
						send(Action.SetLoadout, def.id, selectedDegree, table.clone(current))
					end
					send(Action.Select, def.id, selectedDegree)
				end)
				Components.setDisabled(use, (isCurrent and not changed) or not degreeOpenNow)
			end

			-- Fresh data from the server (an unlock went through, a loadout saved)
			Profile.changed:Connect(function()
				if Shell.isOpen("Powers") then
					table.clear(drafts)
					renderList()
					render()
				end
			end)

			return {
				onOpen = function()
					local view = Profile.get()
					local selected = view and view.selected
					if typeof(selected) == "table" and Powers.get(selected.power) then
						selectedPower = selected.power
						selectedDegree = selected.degree
					end
					table.clear(drafts)
					renderList()
					render()
				end,
			}
		end,
	})
end

return PowersWindow
