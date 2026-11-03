-- The Master Shop: what the game sells, in plain cards. A category rail on the left, large
-- item cards on the right. Every card says exactly what it gives, the price this player pays
-- (read live from Roblox, never hard-coded: prices differ by region), whether it is owned,
-- and one action. Robux items open Roblox's own purchase window; Gem items are unlocked on
-- the server, which checks the balance. Nothing here is random, timed or "limited".
-- Everything here only asks; the server checks ids, ownership, balances and rate limits.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Powers = require(ReplicatedStorage.Shared.Powers)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Profile = require(script.Parent.Parent.Profile)
local PriceFetcher = require(script.Parent.Parent.PriceFetcher)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShopRequest = Remotes:WaitForChild("ShopRequest") :: RemoteEvent
local PowerRequest = Remotes:WaitForChild("PowerRequest") :: RemoteEvent

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make
local player = Players.LocalPlayer

local ShopWindow = {}

local RAIL_WIDTH = 188
local CARD_HEIGHT = 200

-- Categories, in rail order. Items are listed below by category id.
ShopWindow.Categories = {
	{ id = "Powers", label = "Premium powers", blurb = "Each power is yours in every mode once unlocked." },
	{ id = "GemPowers", label = "Unlock with Gems", blurb = "The same powers, paid for with Gems you earned or bought." },
	{ id = "Gems", label = "Gem packs", blurb = "Gems unlock powers and abilities. Every pack gives a fixed amount." },
	{ id = "Upgrades", label = "Upgrades", blurb = "One-time upgrades that apply to all of your powers." },
	{ id = "Cosmetics", label = "Cosmetics", blurb = "Looks only. Cosmetics never change damage, speed or any stat." },
}

-- Every item the shop lists. kind: "pass" (Robux game pass), "product" (Robux developer
-- product) or "gemPower" (a premium power bought with Gems).
function ShopWindow.items(): { { [string]: any } }
	local list = {}
	for _, key in { "CorruptionPower", "SyntaxPower", "AdminPower" } do
		local pass = Monetization.Passes[key]
		if pass then
			table.insert(list, { category = "Powers", kind = "pass", key = key, name = pass.name, contents = pass.benefit, icon = "star", accent = Colors.Purple, premium = true, power = pass.power })
		end
	end
	for _, key in { "CorruptionPower", "SyntaxPower", "AdminPower" } do
		local pass = Monetization.Passes[key]
		local def = pass and pass.power and Powers.get(pass.power)
		if def and def.premium and def.premium.gems then
			table.insert(list, {
				category = "GemPowers",
				kind = "gemPower",
				key = key,
				name = pass.name,
				contents = `Unlocks the {pass.name} power, all three degrees, playable in every mode. Same result as the Robux pass.`,
				icon = "gem",
				accent = Colors.Gems,
				power = pass.power,
				gems = def.premium.gems,
			})
		end
	end
	for _, key in Monetization.ProductOrder do
		local product = Monetization.Products[key]
		table.insert(list, { category = "Gems", kind = "product", key = key, name = product.name, contents = product.benefit, icon = "gem", accent = Colors.Gems })
	end
	local slot = Monetization.Passes.ExtraAbilitySlot
	if slot then
		table.insert(list, { category = "Upgrades", kind = "pass", key = "ExtraAbilitySlot", name = slot.name, contents = slot.benefit, icon = "unlock", accent = Colors.Cyan })
	end
	local style = Monetization.Passes.CelestialDragonStyle
	if style then
		table.insert(list, { category = "Cosmetics", kind = "pass", key = "CelestialDragonStyle", name = style.name, contents = style.benefit, icon = "star", accent = Colors.Gold })
	end
	return list
end

local function view(): { [string]: any }
	return Profile.get() or {}
end

local function ownsPass(passKey: string): boolean
	local passes = view().passes
	return typeof(passes) == "table" and passes[passKey] == true
end

local function ownsPower(item): boolean
	if player:GetAttribute(Protocol.Attribute.IsOwner) == true then
		return true
	end
	local data = view().powers
	local entry = typeof(data) == "table" and item.power and data[item.power]
	return ownsPass(item.key) or (typeof(entry) == "table" and entry.owned == true)
end

-- What a card shows right now: { owned, priceText, price (table for gems), action, enabled, onAct }
local function stateOf(item, redraw: () -> ())
	local state = { owned = false, priceText = "", gems = nil :: number?, label = "", enabled = false, act = nil :: (() -> ())? }
	if item.kind == "gemPower" then
		state.gems = item.gems
		state.owned = ownsPower(item)
		local have = Profile.currency("gems")
		if state.owned then
			state.label = "Owned"
		elseif have < item.gems then
			state.label = `Need {Components.formatNumber(item.gems - have)} more`
		else
			state.label = "Unlock"
			state.enabled = true
			state.act = function()
				PowerRequest:FireServer(Protocol.PowerAction.UnlockPower, item.power)
			end
		end
		return state
	end
	local config = if item.kind == "pass" then Monetization.Passes[item.key] else Monetization.Products[item.key]
	local kind = if item.kind == "pass" then "GamePass" else "Product"
	if item.kind == "pass" then
		state.owned = if item.power then ownsPower(item) else ownsPass(item.key)
	end
	local price = PriceFetcher.get(kind, config.id, redraw)
	state.priceText = PriceFetcher.describe(price)
	if state.owned then
		state.label = "Owned"
	elseif price.status == "soon" then
		state.label = "Available soon"
	elseif price.status == "loading" then
		state.label = "Checking price"
	elseif price.status == "unavailable" then
		state.label = "Check again"
		state.enabled = true
		state.act = function()
			PriceFetcher.refresh(kind, config.id)
			redraw()
		end
	else
		state.label = "Buy"
		state.enabled = true
		state.act = function()
			ShopRequest:FireServer(if item.kind == "pass" then Protocol.ShopAction.PromptPass else Protocol.ShopAction.PromptProduct, item.key)
		end
	end
	return state
end

local function buildCard(parent: Instance, item, redraw: () -> ()): Frame
	local st = stateOf(item, redraw)
	local accent = item.accent or Colors.Cyan
	local card = Components.panel({
		Name = "Card_" .. item.key .. "_" .. item.category,
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0.08,
		Parent = parent,
	})
	local art = make("Frame", {
		Name = "Art",
		Position = UDim2.fromOffset(Space.L, Space.L),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = card,
	}, { Components.corner(Theme.SmallCorner), Components.stroke(accent, 1, 0.55) })
	local glyph = Components.icon(item.icon, 40, accent:Lerp(Colors.Text, 0.25))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Parent = art
	local left = Space.L + 72 + Space.L
	Components.text({
		Name = "Name",
		Text = item.name,
		Style = "heading",
		Position = UDim2.fromOffset(left, Space.L),
		Size = UDim2.new(1, -(left + Space.L), 0, 26),
		Parent = card,
	})
	if st.owned then
		local badge = Components.badge("OWNED", Colors.Success)
		badge.Position = UDim2.fromOffset(left, Space.L + 30)
		badge.Parent = card
	end
	Components.text({
		Name = "Contents",
		Text = item.contents,
		Style = "small",
		Color = Colors.TextDim,
		Lines = 4,
		Position = UDim2.fromOffset(left, Space.L + (if st.owned then 58 else 32)),
		Size = UDim2.new(1, -(left + Space.L), 0, 70),
		Parent = card,
	})
	-- Bottom line: price on the left, one action on the right
	local footer = make("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Space.L, 1, -Space.L),
		Size = UDim2.new(1, -Space.L * 2, 0, 44),
		BackgroundTransparency = 1,
		Parent = card,
	})
	if st.gems then
		local price = Components.price(nil, { gems = st.gems }, { Height = 28, TextSize = 16 })
		price.AnchorPoint = Vector2.new(0, 0.5)
		price.Position = UDim2.fromScale(0, 0.5)
		price.Parent = footer
	else
		Components.text({
			Name = "Price",
			Text = st.priceText,
			Style = "strong",
			Color = if st.priceText:sub(1, 2) == "R$" then Colors.Robux else Colors.TextDim,
			Size = UDim2.new(1, -164, 1, 0),
			Parent = footer,
		})
	end
	local button = Components.button(st.label, {
		Name = "Action",
		Variant = if st.enabled and not st.owned then "Primary" else "Secondary",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(156, 44),
		KeepCase = true,
		Parent = footer,
	}, function()
		if st.act then
			st.act()
		end
	end)
	Components.setDisabled(button, not st.enabled or st.owned)
	return card
end

function ShopWindow.register()
	Shell.registerWindow("Shop", {
		title = "Master Shop",
		label = "SHOP",
		icon = "★",
		order = 6,
		nav = false,
		size = Vector2.new(1000, 600),
		accent = Colors.Gold,
		build = function(body: Frame, api)
			local selected = ShopWindow.Categories[1].id
			local items = ShopWindow.items()
			local railButtons = {}

			local rail = make("Frame", { Name = "Rail", Size = UDim2.new(0, RAIL_WIDTH, 1, 0), BackgroundTransparency = 1, Parent = body })
			Components.list(rail, Space.S)
			local main = make("Frame", {
				Name = "Main",
				Position = UDim2.fromOffset(RAIL_WIDTH + Space.L, 0),
				Size = UDim2.new(1, -(RAIL_WIDTH + Space.L), 1, 0),
				BackgroundTransparency = 1,
				Parent = body,
			})
			local heading = Components.text({ Name = "Heading", Text = "", Style = "title", Size = UDim2.new(1, 0, 0, 32), Parent = main })
			local blurb = Components.text({ Name = "Blurb", Text = "", Style = "small", Color = Colors.TextDim, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 22), Parent = main })
			local grid = Components.scroll({ Name = "Cards", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64), Padding = 2, Parent = main })
			Components.grid(grid, UDim2.new(0.5, -Space.S, 0, CARD_HEIGHT), Space.L)

			local redraw
			local function draw()
				for _, child in grid:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				local meta
				for _, category in ShopWindow.Categories do
					if category.id == selected then
						meta = category
					end
				end
				heading.Text = meta.label
				blurb.Text = meta.blurb
				local order = 0
				for _, item in items do
					if item.category == selected then
						order += 1
						local card = buildCard(grid, item, redraw)
						card.LayoutOrder = order
					end
				end
				for id, button in railButtons do
					Components.setSelected(button, id == selected)
				end
			end
			redraw = function()
				if body.Parent and Shell.isOpen("Shop") then
					draw()
				end
			end

			for _, category in ShopWindow.Categories do
				local button = Components.button(category.label, {
					Name = "Rail_" .. category.id,
					Variant = "Ghost",
					KeepCase = true,
					Size = UDim2.new(1, 0, 0, 48),
					Parent = rail,
				}, function()
					selected = category.id
					draw()
				end)
				railButtons[category.id] = button
			end

			-- Roblox's window closed: say what happened, never claim a grant here (the server does that)
			MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, _, purchased)
				if purchased then
					Shell.toast("Thank you. Roblox is confirming your purchase.", "success")
				else
					Shell.toast("Purchase cancelled. Nothing was charged.", "info")
				end
				task.delay(1, redraw)
			end)
			MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, _, purchased)
				if purchased then
					Shell.toast("Thank you. Your Gems arrive as soon as Roblox confirms.", "success")
				else
					Shell.toast("Purchase cancelled. Nothing was charged.", "info")
				end
			end)
			Profile.changed:Connect(redraw)
			draw()
			return {
				onOpen = function(args)
					if typeof(args) == "string" then
						for _, category in ShopWindow.Categories do
							if category.id == args then
								selected = args
							end
						end
					end
					draw()
				end,
			}
		end,
	})
end

return ShopWindow
