-- The GUI tree exporter shared by the UI dump scripts: turns a GuiObject tree into plain
-- tables for tools/uipreview/render.py. Exports layout, colours, fonts (family, weight,
-- style), strokes, gradients, rotation, and for ViewportFrames the parts, camera and light.
local roblox = require("@lune/roblox") :: any

local function enumName(v)
	return if typeof(v) == "EnumItem" then v.Name else nil
end
local function udim2(v)
	return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
end
local function color(v)
	return { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) }
end
local function rgb01(v)
	return { v.R, v.G, v.B }
end
local function get(item, prop)
	local ok, value = pcall(function()
		return item[prop]
	end)
	return if ok then value else nil
end
local function cf(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function stops(seq)
	local list = {}
	if typeof(seq) == "ColorSequence" then
		for _, k in seq.Keypoints do
			table.insert(list, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		end
	elseif typeof(seq) == "NumberSequence" then
		for _, k in seq.Keypoints do
			table.insert(list, { k.Time, k.Value })
		end
	end
	return list
end

-- The contents of a ViewportFrame, in the part format of tools/preview/dump3d.luau
local function dumpViewport(item)
	local vp: any = { parts = {} }
	local camera = get(item, "CurrentCamera")
	if typeof(camera) ~= "Instance" then
		for _, d in item:GetDescendants() do
			if d:IsA("Camera") then
				camera = d
				break
			end
		end
	end
	if typeof(camera) == "Instance" then
		vp.camera = cf(camera.CFrame)
		vp.fov = camera.FieldOfView
	end
	vp.ambient = rgb01(item.Ambient)
	vp.lightColor = rgb01(item.LightColor)
	local dir = item.LightDirection
	vp.lightDirection = { dir.X, dir.Y, dir.Z }
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local shape = "Block"
			if d:IsA("WedgePart") then
				shape = "Wedge"
			elseif d:IsA("CornerWedgePart") then
				shape = "CornerWedge"
			elseif d:IsA("Part") then
				shape = enumName(get(d, "Shape")) or "Block"
			end
			table.insert(vp.parts, {
				name = d.Name,
				shape = shape,
				cf = cf(d.CFrame),
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				color = rgb01(d.Color),
				material = enumName(d.Material) or "Plastic",
				transparency = d.Transparency,
				reflectance = get(d, "Reflectance") or 0,
				shadow = false,
			})
		end
	end
	return vp
end

local function dump(item)
	local node: any = { class = item.ClassName, name = item.Name, children = {} }
	if item:IsA("GuiObject") then
		node.size = udim2(item.Size)
		node.pos = udim2(item.Position)
		node.anchor = { item.AnchorPoint.X, item.AnchorPoint.Y }
		node.rotation = item.Rotation
		node.visible = item.Visible
		node.bg = color(item.BackgroundColor3)
		node.bgAlpha = item.BackgroundTransparency
		node.z = item.ZIndex
		node.order = item.LayoutOrder
		node.auto = enumName(item.AutomaticSize)
		node.clips = item.ClipsDescendants
		if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
			node.text = item.Text
			node.textSize = item.TextSize
			node.textColor = color(item.TextColor3)
			node.textAlpha = item.TextTransparency
			node.alignX = enumName(item.TextXAlignment)
			node.alignY = enumName(item.TextYAlignment)
			node.wrap = item.TextWrapped
			node.scaled = item.TextScaled
			node.truncate = enumName(item.TextTruncate)
			node.lineHeight = get(item, "LineHeight") or 1
			local face = get(item, "FontFace")
			node.weight = if face then face.Weight.Name else "Regular"
			node.family = if face then face.Family else nil
			node.style = if face then face.Style.Name else "Normal"
		end
		if item:IsA("ImageLabel") then
			node.image = true
		end
		if item:IsA("ScrollingFrame") then
			node.scroll = true
		end
		if item:IsA("ViewportFrame") then
			node.viewport = dumpViewport(item)
		end
	elseif item:IsA("UIListLayout") then
		node.fill = enumName(item.FillDirection)
		node.padding = { item.Padding.Scale, item.Padding.Offset }
		node.hAlign = enumName(item.HorizontalAlignment)
		node.vAlign = enumName(item.VerticalAlignment)
	elseif item:IsA("UIGridLayout") then
		node.cell = udim2(item.CellSize)
		node.cellPad = udim2(item.CellPadding)
	elseif item:IsA("UIPadding") then
		node.pad = { item.PaddingTop.Offset, item.PaddingRight.Offset, item.PaddingBottom.Offset, item.PaddingLeft.Offset }
	elseif item:IsA("UICorner") then
		node.radius = { item.CornerRadius.Scale, item.CornerRadius.Offset }
	elseif item:IsA("UIStroke") then
		node.color = color(item.Color)
		node.thickness = item.Thickness
		node.alpha = item.Transparency
		node.mode = enumName(item.ApplyStrokeMode)
	elseif item:IsA("UIGradient") then
		node.colors = stops(item.Color)
		node.alphas = stops(item.Transparency)
		node.rotation = item.Rotation
	elseif item:IsA("UIScale") then
		node.scale = item.Scale
	elseif item:IsA("UISizeConstraint") then
		node.minSize = { item.MinSize.X, item.MinSize.Y }
	elseif item:IsA("UITextSizeConstraint") then
		node.maxTextSize = item.MaxTextSize
		node.minTextSize = item.MinTextSize
	elseif item:IsA("ScreenGui") then
		node.enabled = item.Enabled
	end
	for _, child in item:GetChildren() do
		table.insert(node.children, dump(child))
	end
	return node
end

return dump
