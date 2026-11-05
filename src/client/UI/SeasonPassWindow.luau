-- The Season pass: 30 tiers as one horizontal track, a free row and a premium row. Shows the
-- player's points, what each tier gives, claim buttons, the two offers (premium track, tier
-- skip) with the price Roblox reports for this player, and the season's real end date as plain
-- text. No countdown, no "last chance" wording: every tier can be reached for free by playing.
-- The window only asks; the server (SeasonPassService) checks tiers, claims and purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local SeasonPass = require(ReplicatedStorage.Shared.Config.SeasonPass)
local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Profile = require(script.Parent.Parent.Profile)
local PriceFetcher = require(script.Parent.Parent.PriceFetcher)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShopRequest = Remotes:WaitForChild("ShopRequest") :: RemoteEvent

local Colors = Theme.Colors
local Space = Theme.Space
local make = Components.make

local SeasonPassWindow = {}

local CELL_W = 156
local CELL_H = 140
local GAP = 8
local LABEL_W = 120
local HEADER_H = 28
local OFFER_H = 116
-- Top 64, points 40, the track (header, two rows, scrollbar), a gap, then the offers
local PAGE_H = 118 + (HEADER_H + GAP + CELL_H * 2 + GAP + 10) + 4 + OFFER_H

local KIND_WORD = { title = "Title", plate = "Nameplate", aura = "Aura", knockout = "Knockout effect" }

local function color3(rgb: { number }?): Color3
	if typeof(rgb) ~= "table" or #rgb < 3 then
		return Colors.Copper
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Where the player stands, as the window shows it: { points, tier, premium, claimed }
local function passState(season)
	local view = Profile.get() or {}
	local pass = view.pass
	if typeof(pass) ~= "table" or pass.season ~= season.id then
		return { points = 0, tier = 0, premium = false, claimed = {} }
	end
	local points = if typeof(pass.points) == "number" then pass.points else 0
	return {
		points = points,
		tier = SeasonPass.tierOf(points),
		premium = pass.premium == true,
		claimed = if typeof(pass.claimed) == "table" then pass.claimed else {},
	}
end

-- What one cell gives: { name, kind, colors? }
local function rewardOf(track: string, tier: number)
	if track == "free" then
		local entry = SeasonPass.Free[tier]
		if entry.money then
			return { name = `{entry.money} Money`, kind = "Money" }
		end
		local item = Cosmetics.get(entry.cosmetic)
		return { name = item and item.name or "?", kind = item and KIND_WORD[item.kind] or "", colors = item and item.colors }
	end
	local item = Cosmetics.get(SeasonPass.Premium[tier])
	return { name = item and item.name or "?", kind = item and KIND_WORD[item.kind] or "", colors = item and item.colors }
end

-- Is tier `tier` of `track` claimable, claimed or waiting? -> "claimed" | "ready" | "premium" | "locked"
local function cellState(state, track: string, tier: number): string
	if state.claimed[SeasonPass.claimKey(track, tier)] == true then
		return "claimed"
	end
	if tier > state.tier then
		return "locked"
	end
	if track == "premium" and not state.premium then
		return "premium"
	end
	return "ready"
end

local function claimKeys(state): { string }
	local keys = {}
	for tier = 1, SeasonPass.TierCount do
		for _, track in { "free", "premium" } do
			if cellState(state, track, tier) == "ready" then
				table.insert(keys, SeasonPass.claimKey(track, tier))
			end
		end
	end
	return keys
end

local function buildCell(parent: Instance, state, track: string, tier: number, x: number, y: number)
	local reward = rewardOf(track, tier)
	local status = cellState(state, track, tier)
	local fill = Colors.PanelLight
	if status == "ready" then
		fill = Colors.Selected
	elseif status == "claimed" then
		fill = Colors.Panel
	end
	local cell = make("Frame", {
		Name = `Cell_{track}_{tier}`,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(CELL_W, CELL_H),
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Parent = parent,
	}, { Components.corner(Theme.SmallCorner) })
	if status == "ready" then
		make("Frame", { Name = "Bar", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Colors.Cyan, BorderSizePixel = 0, Parent = cell })
	end
	-- The item's own colours as a strip along the top, so a look can be judged before claiming
	local swatch = make("Frame", { Name = "Swatch", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 5), BackgroundTransparency = 1, Parent = cell })
	local colors = reward.colors
	if colors and #colors > 0 then
		for index, rgb in colors do
			make("Frame", {
				Position = UDim2.fromScale((index - 1) / #colors, 0),
				Size = UDim2.fromScale(1 / #colors, 1),
				BackgroundColor3 = color3(rgb),
				BorderSizePixel = 0,
				Parent = swatch,
			})
		end
	else
		make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Colors.Copper, BorderSizePixel = 0, Parent = swatch })
	end
	local dim = status == "locked" or status == "premium"
	Components.text({
		Name = "Name",
		Text = reward.name,
		Style = "small",
		TextSize = 16,
		Weight = "SemiBold",
		Color = if dim then Colors.TextMuted else Colors.Text,
		Lines = 2,
		Position = UDim2.fromOffset(8, 18),
		Size = UDim2.new(1, -16, 0, 44),
		Parent = cell,
	})
	Components.text({
		Name = "Kind",
		Text = reward.kind,
		Style = "small",
		TextSize = 16,
		Color = Colors.TextMuted,
		Position = UDim2.fromOffset(8, 64),
		Size = UDim2.new(1, -16, 0, 22),
		Parent = cell,
	})
	local footer = UDim2.new(1, -16, 0, 44)
	if status == "ready" then
		local key = SeasonPass.claimKey(track, tier)
		Components.button("Claim", {
			Name = "Claim",
			Variant = "Primary",
			TextSize = 16,
			Position = UDim2.new(0, 8, 1, -50),
			Size = footer,
			Parent = cell,
		}, function()
			ShopRequest:FireServer(Protocol.ShopAction.ClaimTier, key)
		end)
	else
		local label = if status == "claimed" then "Claimed" elseif status == "premium" then "Premium only" else `Tier {tier}`
		Components.text({
			Name = "Status",
			Text = label,
			Style = "small",
			TextSize = 16,
			Weight = "SemiBold",
			Color = if status == "claimed" then Colors.Success elseif status == "premium" then Colors.Copper else Colors.TextMuted,
			AlignY = "Center",
			Position = UDim2.new(0, 8, 1, -50),
			Size = footer,
			Parent = cell,
		})
	end
	return cell
end

-- The price block of a product offer: { priceText, label, enabled, owned, act }
local function offerState(productKey: string, redraw: () -> (), blocked: string?, owned: boolean?)
	local product = Monetization.Products[productKey]
	local state = { priceText = "", label = "", enabled = false, owned = owned == true, act = nil :: (() -> ())? }
	local price = PriceFetcher.get("Product", product.id, redraw)
	state.priceText = PriceFetcher.describe(price)
	if owned then
		state.label = "Unlocked"
	elseif blocked then
		state.label = blocked
	elseif price.status == "soon" then
		state.label = "Available soon"
	elseif price.status == "loading" then
		state.label = "Checking price"
	elseif price.status == "unavailable" then
		state.label = "Check again"
		state.enabled = true
		state.act = function()
			PriceFetcher.refresh("Product", product.id)
			redraw()
		end
	else
		state.label = "Buy"
		state.enabled = true
		state.act = function()
			ShopRequest:FireServer(Protocol.ShopAction.PromptProduct, productKey)
		end
	end
	return state
end

local function buildOffer(parent: Instance, name: string, text: string, st, index: number)
	local card = Components.panel({
		Name = "Offer_" .. name:gsub("%s", ""),
		BackgroundColor3 = Colors.PanelLight,
		BackgroundTransparency = 0,
		Position = UDim2.new(0.5 * (index - 1), if index == 1 then 0 else GAP / 2, 0, 0),
		Size = UDim2.new(0.5, -GAP / 2, 1, 0),
		Parent = parent,
	})
	Components.text({ Name = "Name", Text = name, Style = "heading", TextSize = 22, Position = UDim2.fromOffset(Space.L, 8), Size = UDim2.new(1, -(Space.L * 2 + 150), 0, 30), Parent = card })
	Components.text({ Name = "About", Text = text, Style = "small", TextSize = 16, Color = Colors.TextDim, Lines = 3, Position = UDim2.fromOffset(Space.L, 40), Size = UDim2.new(1, -(Space.L * 2 + 150), 0, 68), Parent = card })
	Components.text({
		Name = "Price",
		Text = st.priceText,
		Style = "strong",
		TextSize = 18,
		AlignX = "Right",
		Color = if st.priceText:sub(1, 2) == "R$" then Colors.Robux else Colors.TextDim,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Space.L, 0, 10),
		Size = UDim2.fromOffset(142, 22),
		Parent = card,
	})
	local button = Components.button(st.label, {
		Name = "Action",
		Variant = if st.enabled and not st.owned then "Primary" else "Secondary",
		KeepCase = true,
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Space.L, 1, -8),
		Size = UDim2.fromOffset(142, 44),
		Parent = card,
	}, function()
		if st.act then
			st.act()
		end
	end)
	Components.setDisabled(button, not st.enabled)
	return card
end

function SeasonPassWindow.register()
	Shell.registerWindow("SeasonPass", {
		title = "Season pass",
		label = "PASS",
		icon = "★",
		order = 5,
		size = Vector2.new(1040, 600),
		accent = Colors.Copper,
		build = function(body: Frame, api)
			local season = SeasonPass.shown(os.time())
			local running = SeasonPass.current(os.time()) ~= nil

			-- Everything sits on one page that scrolls up and down when the screen is small
			local content = Components.scroll({ Name = "Content", Size = UDim2.fromScale(1, 1), ScrollBarThickness = 4 })
			content.Parent = body
			local page = make("Frame", { Name = "Page", Size = UDim2.new(1, -8, 0, PAGE_H), BackgroundTransparency = 1, Parent = content })

			-- Top: season name and plain end date on the left, claim-all on the right
			local top = make("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Parent = page })
			Components.text({ Name = "Season", Text = season.name, Style = "title", Size = UDim2.new(1, -190, 0, 34), Parent = top })
			local ends = if running then `Runs until {season.endText}. Every tier can be reached by playing.` else `This season ended on {season.endText}. Rewards you reached can still be claimed.`
			Components.text({ Name = "Ends", Text = ends, Style = "small", TextSize = 16, Color = Colors.TextDim, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, -190, 0, 24), Parent = top })
			local claimAll

			-- Points line with a bar to the next tier
			local progress = make("Frame", { Name = "Progress", Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, Parent = page })
			local pointsText = Components.text({ Name = "Points", Text = "", Style = "strong", TextSize = 20, Size = UDim2.new(1, 0, 0, 26), Parent = progress })
			local barFrame, setBar = Components.bar({ Name = "Bar", Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 8), Parent = progress }, Colors.Copper)
			barFrame.BorderSizePixel = 0

			-- The track
			local trackTop = 118
			local trackHeight = HEADER_H + GAP + CELL_H * 2 + GAP + 10
			local labels = make("Frame", { Name = "Labels", Position = UDim2.fromOffset(0, trackTop), Size = UDim2.fromOffset(LABEL_W, trackHeight), BackgroundTransparency = 1, Parent = page })
			local scroll = Components.scroll({
				Name = "Track",
				Position = UDim2.fromOffset(LABEL_W + GAP, trackTop),
				Size = UDim2.new(1, -(LABEL_W + GAP), 0, trackHeight),
				ScrollingDirection = Enum.ScrollingDirection.X,
				AutomaticCanvasSize = Enum.AutomaticSize.None,
				CanvasSize = UDim2.fromOffset(SeasonPass.TierCount * (CELL_W + GAP), 0),
				ScrollBarThickness = 6,
				HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
				VerticalScrollBarInset = Enum.ScrollBarInset.None,
			})
			scroll.Parent = page

			local offers = make("Frame", {
				Name = "Offers",
				Position = UDim2.fromOffset(0, PAGE_H - OFFER_H),
				Size = UDim2.new(1, 0, 0, OFFER_H),
				BackgroundTransparency = 1,
				Parent = page,
			})

			local firstDraw = true
			local redraw
			local function draw()
				local state = passState(season)
				local position = scroll.CanvasPosition
				for _, child in scroll:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for _, child in labels:GetChildren() do
					child:Destroy()
				end
				for _, child in offers:GetChildren() do
					child:Destroy()
				end

				-- Points
				local nextTier = math.min(SeasonPass.TierCount, state.tier + 1)
				local toNext = nextTier * SeasonPass.PointsPerTier - state.points
				if state.tier >= SeasonPass.TierCount then
					pointsText.Text = `Tier {SeasonPass.TierCount} of {SeasonPass.TierCount}. You have reached the last tier.`
					setBar(1)
				else
					pointsText.Text = `Tier {state.tier} of {SeasonPass.TierCount}. {state.points} points, {toNext} to tier {nextTier}.`
					setBar((state.points - state.tier * SeasonPass.PointsPerTier) / SeasonPass.PointsPerTier)
				end

				-- Row labels
				local rowY = { free = HEADER_H + GAP, premium = HEADER_H + GAP + CELL_H + GAP }
				Components.text({ Name = "FreeLabel", Text = "Free", Style = "heading", TextSize = 22, Position = UDim2.fromOffset(0, rowY.free + 8), Size = UDim2.fromOffset(LABEL_W, 24), Parent = labels })
				Components.text({ Name = "FreeNote", Text = "Money and looks", Style = "small", TextSize = 16, Color = Colors.TextMuted, Lines = 2, Position = UDim2.fromOffset(0, rowY.free + 38), Size = UDim2.fromOffset(LABEL_W, 46), Parent = labels })
				Components.text({ Name = "PremiumLabel", Text = "Premium", Style = "heading", TextSize = 22, Color = Colors.Copper, Position = UDim2.fromOffset(0, rowY.premium + 8), Size = UDim2.fromOffset(LABEL_W, 24), Parent = labels })
				Components.text({ Name = "PremiumNote", Text = if state.premium then "Unlocked" else "Locked", Style = "small", TextSize = 16, Color = if state.premium then Colors.Success else Colors.TextMuted, Position = UDim2.fromOffset(0, rowY.premium + 38), Size = UDim2.fromOffset(LABEL_W, 24), Parent = labels })

				-- Tiers
				for tier = 1, SeasonPass.TierCount do
					local x = (tier - 1) * (CELL_W + GAP)
					Components.text({
						Name = "Tier_" .. tier,
						Text = `Tier {tier}`,
						Style = "number",
						TextSize = 16,
						Weight = "SemiBold",
						Color = if tier == state.tier then Colors.Cyan elseif tier < state.tier then Colors.TextDim else Colors.TextMuted,
						Position = UDim2.fromOffset(x + 2, 0),
						Size = UDim2.fromOffset(CELL_W, HEADER_H),
						Parent = scroll,
					})
					buildCell(scroll, state, "free", tier, x, rowY.free)
					buildCell(scroll, state, "premium", tier, x, rowY.premium)
				end
				scroll.CanvasPosition = position
				if firstDraw then
					firstDraw = false
					local focus = math.max(0, state.tier - 1)
					scroll.CanvasPosition = Vector2.new(focus * (CELL_W + GAP), 0)
				end

				-- Claim all (one request per reward; the server checks each)
				if claimAll then
					claimAll:Destroy()
				end
				local keys = claimKeys(state)
				claimAll = Components.button(if #keys > 0 then `Claim all ({#keys})` else "Nothing to claim", {
					Name = "ClaimAll",
					Variant = if #keys > 0 then "Primary" else "Secondary",
					KeepCase = true,
					TextSize = 16,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 4),
					Size = UDim2.fromOffset(176, 44),
					Parent = top,
				}, function()
					task.spawn(function()
						for _, key in keys do
							ShopRequest:FireServer(Protocol.ShopAction.ClaimTier, key)
							task.wait(0.3)
						end
					end)
				end)
				Components.setDisabled(claimAll, #keys == 0)

				-- Offers
				local blockedPremium, blockedSkip = nil, nil
				if not running then
					blockedPremium, blockedSkip = "No season now", "No season now"
				elseif state.tier >= SeasonPass.TierCount then
					blockedSkip = "Last tier reached"
				end
				local premiumState = offerState("SeasonPremium", function() redraw() end, blockedPremium, state.premium)
				buildOffer(offers, "Premium track", "One cosmetic at every tier, 30 in all, for this season only. No Money, Gems or power.", premiumState, 1)
				local skipState = offerState("SeasonTierSkip", function() redraw() end, blockedSkip, false)
				buildOffer(offers, "Tier skip", "Adds one tier of points, never past the last tier. You can reach every tier for free.", skipState, 2)
			end

			redraw = function()
				if body.Parent and Shell.isOpen("SeasonPass") then
					draw()
				end
			end
			Profile.changed:Connect(redraw)
			draw()
			return {
				onOpen = function()
					draw()
				end,
			}
		end,
	})
end

return SeasonPassWindow
