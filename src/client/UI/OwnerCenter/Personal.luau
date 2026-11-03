-- The owner's own tools: God powers (fly, immunity, invisibility, crown), Fighter and degree
-- control, and Summoning and teleportation. These use the owner's existing server paths:
-- AdminRequest SelfToggle / PlayerAction and PowerRequest Select / SetShowcase.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Theme = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Parent.Components)
local Shell = require(script.Parent.Parent.Shell)
local Profile = require(script.Parent.Parent.Parent.Profile)
local Kit = require(script.Parent.Kit)
local Net = require(script.Parent.Net)
local ServerList = require(script.Parent.ServerList)

local AdminAction = Protocol.AdminAction
local PowerAction = Protocol.PowerAction
local Attribute = Protocol.Attribute
local Action = Protocol.OverlordAction
local Colors = Theme.Colors

local player = Players.LocalPlayer

local Personal = {}

local TOGGLES = {
	{ key = "Fly", attribute = Attribute.CanFly, label = "Flight", description = "Fly with the movement keys; Space and Ctrl change height, Shift is faster. G also toggles it." },
	{ key = "Immune", attribute = Attribute.Immune, label = "Immunity", description = "Damage and knock-back do not affect you." },
	{ key = "Invisible", attribute = Attribute.Invisible, label = "Invisibility", description = "Other players cannot see your character." },
	{ key = "Crown", attribute = Attribute.Crown, label = "Owner crown", description = "Shows the owner crown over your character." },
}

function Personal.buildGod(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "God powers", 1)
	Kit.para(scroll, "Switches for your own character. They show what the server says is on right now.", 2)
	local setters = {}
	for index, toggle in TOGGLES do
		local _, set = Components.toggle(toggle.label, player:GetAttribute(toggle.attribute) == true, function(on)
			ctx.sendAdmin(AdminAction.SelfToggle, toggle.key, on)
		end, { Name = "Toggle_" .. toggle.key, LayoutOrder = 2 + index, Description = toggle.description, Parent = scroll })
		setters[toggle.attribute] = set
		player:GetAttributeChangedSignal(toggle.attribute):Connect(function()
			set(player:GetAttribute(toggle.attribute) == true)
		end)
	end
	return {
		show = function()
			for attribute, set in setters do
				set(player:GetAttribute(attribute) == true)
			end
		end,
	}
end

function Personal.buildFighters(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Fighter and degree control", 1)
	Kit.para(scroll, "You own every fighter and phase. Equipping saves the choice as your selection.", 2)
	local powerRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PowerRequest") :: RemoteEvent
	local top = Kit.flow(scroll, 3, 8)
	Kit.button(top, "Open the Fighter Showcase", "Primary", function()
		Shell.open("Powers")
	end, { Name = "OpenShowcase" })
	local showcase = false
	local showcaseButton
	showcaseButton = Kit.button(top, "Showcase mode: off", "Secondary", function()
		showcase = not showcase
		powerRequest:FireServer(PowerAction.SetShowcase, showcase)
		showcaseButton.Text = if showcase then "Showcase mode: on" else "Showcase mode: off"
	end, { Name = "ShowcaseMode", Size = UDim2.fromOffset(210, 44) })
	Kit.caption(scroll, "Showcase mode lets combat powers work in the lobby.", 4)
	local equipped = Kit.card(scroll, 5, { Name = "Equipped" })
	local equippedLine = Kit.pair(equipped, "Equipped now", "...", 1)
	local phaseButtons: { [string]: TextButton } = {}

	local function paint()
		local profile = Profile.get()
		local selected = profile and profile.selected
		local power = selected and selected.power
		local degree = selected and selected.degree
		local def = power and Powers.get(power)
		equippedLine.Text = if def and degree then `{def.name}, phase {degree}` else "not loaded yet"
		for key, button in phaseButtons do
			Components.setSelected(button, key == `{power}:{degree}`)
		end
	end

	for index, powerId in Powers.Order do
		local def = Powers.get(powerId)
		local card = Kit.card(scroll, 5 + index, { Name = "Power_" .. powerId })
		Components.text({ Name = "Name", Text = def.name, Style = "strong", Wrap = true, LayoutOrder = 1, Parent = card })
		local row = Kit.flow(card, 2, 8)
		for degree = 1, Powers.degreeCount(powerId) do
			local info = def.degrees[degree]
			local button = Kit.button(row, `Phase {degree}: {if info then info.name else ""}`, "Ghost", function()
				powerRequest:FireServer(PowerAction.Select, powerId, degree)
				Shell.toast(`Equipping {def.name}, phase {degree}.`, "info")
			end, { Name = `Equip_{powerId}_{degree}` })
			phaseButtons[`{powerId}:{degree}`] = button
		end
	end
	Profile.changed:Connect(paint)
	paint()
	local _ = ctx
	return { show = paint }
end

function Personal.buildSummon(page: Frame, ctx: any)
	local scroll = Kit.page(page)
	Kit.heading(scroll, "Summoning and teleportation", 1)
	Kit.subheading(scroll, "Players on this server", 2)
	Kit.para(scroll, "Go to a player, or bring one to you. Bringing everyone asks you to confirm.", 3)
	local playerList = Kit.stack(scroll, 4, "PlayerRows")
	local function renderPlayers()
		Kit.clear(playerList)
		local order = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				order += 1
				local card = Kit.card(playerList, order, { Name = "Player_" .. other.UserId })
				Components.text({ Name = "Name", Text = other.DisplayName, Style = "strong", Wrap = true, LayoutOrder = 1, Parent = card })
				local row = Kit.flow(card, 2, 8)
				Kit.button(row, "Go to", "Secondary", function()
					ctx.sendAdmin(AdminAction.PlayerAction, other.UserId, "GoTo")
				end, { Name = "GoTo" })
				Kit.button(row, "Bring here", "Secondary", function()
					ctx.sendAdmin(AdminAction.PlayerAction, other.UserId, "Bring")
				end, { Name = "Bring" })
			end
		end
		if order == 0 then
			Kit.empty(playerList, "You are the only player on this server.", 1)
		else
			Kit.button(playerList, "Bring everyone here", "Danger", function()
				Shell.confirm({
					title = "Bring everyone to you?",
					body = "Every other player on this server is moved to your position.",
					danger = true,
					confirmText = "Bring everyone",
					onConfirm = function()
						ctx.sendAdmin(AdminAction.PlayerAction, "Others", "Bring")
					end,
				})
			end, { Name = "BringAll", LayoutOrder = order + 1 })
		end
	end
	Players.PlayerAdded:Connect(renderPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(renderPlayers)
	end)
	Kit.subheading(scroll, "Other servers", 5)
	ServerList.build(scroll, { order = 6, pick = false })
	renderPlayers()
	return {
		show = function()
			renderPlayers()
			Net.request(Action.Servers)
		end,
	}
end

return Personal
