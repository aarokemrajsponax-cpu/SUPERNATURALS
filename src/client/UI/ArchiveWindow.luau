-- The Meridian Archive: the lore book players read at the lectern in the
-- Lounge (the Shell window "Archive"). It is drawn as a real codex: a leather
-- cover, paper pages with a soft gutter shadow, page numbers and a ribbon, as
-- an open spread on wide screens and one page at a time on phones.
--
-- Every document in Shared/Content/Archive is typeset by its kind
-- (handwritten letters, lined journals, typewritten memos, file-folder
-- dossiers, terminal logs, transcripts, reports and notes). Text is measured
-- with TextService and broken into lines and pages here, so nothing runs off
-- a page, and redactions are real black bars: the hidden words never reach a
-- TextLabel. Figures are drawn from UI shapes in a pencil, blueprint, photo or
-- terminal style, or as a small 3D scene. Pages turn with a short fold from
-- the arrows, Q/E or the arrow keys, LB/RB, a swipe, or a tap on a page edge.
-- The server hears which documents were shown (ProgressAction.ReadLore), so
-- "new" marks clear and the book reopens where the player left off.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Archive = require(ReplicatedStorage.Shared.Content.Archive)
local Protocol = require(ReplicatedStorage.Shared.Protocol)
local Components = require(script.Parent.Components)
local Shell = require(script.Parent.Shell)
local Theme = require(script.Parent.Theme)
local Profile = require(script.Parent.Parent.Profile)
local Vfx = require(script.Parent.Parent.Effects.Vfx)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProgressRequest = Remotes:WaitForChild("ProgressRequest") :: RemoteEvent

local make = Components.make
local rgb = Color3.fromRGB
local CSK = ColorSequenceKeypoint.new
local NSK = NumberSequenceKeypoint.new

local ArchiveWindow = {}

-- Tunables (sizes are design pixels at 1280x720; the Shell scales the interface)
local CONFIG = {
	WindowSize = Vector2.new(1180, 660),
	-- Screens narrower than this (or a phone) get one page at a time
	SpreadWidth = 820,
	Cover = 14,
	ControlsHeight = 44,
	ControlsGap = 22,
	MaxPageHeight = 600,
	MaxSpreadPage = 560,
	MaxSinglePage = 600,
	-- Type grows a little on one-page (phone) layouts
	SingleTypeScale = 1.12,
	-- Each half of a page turn (the old leaf folding away, the new one landing)
	TurnTime = 0.2,
	-- Seconds between ReadLore messages (the server rate limits "Progress")
	ReadSpacing = 0.8,
	SwipeDistance = 50,
	BlurSize = 12,
	-- Built pages kept either side of the open spread, for quick turning
	PageCache = 6,
	-- Radians per second for the turning Lantern
	SpinSpeed = 0.35,
	-- Contents rows are buttons, so they keep a full touch target
	Row = 44,
}

-- The Sanctum palette (docs/ArtDirection.md): ivory paper, warm inks, dark
-- leather, patinated bronze and lapis, with gold leaf kept for one detail.
-- Red appears only as ink on the documents themselves (rubber stamps).
local C = {
	Paper = rgb(236, 229, 213),
	PaperCream = rgb(240, 230, 207),
	PaperWhite = rgb(238, 235, 227),
	PaperLined = rgb(237, 231, 216),
	Manila = rgb(221, 199, 153),
	Slip = rgb(233, 215, 158),
	Sheet = rgb(245, 241, 231),
	Endpaper = rgb(31, 43, 74),
	Edge = rgb(214, 205, 186),
	Ink = rgb(43, 38, 33),
	InkSoft = rgb(102, 92, 80),
	InkFaded = rgb(138, 126, 110),
	InkBlue = rgb(33, 45, 82),
	InkType = rgb(42, 40, 42),
	Pencil = rgb(82, 81, 84),
	Red = rgb(168, 68, 58),
	Bronze = rgb(140, 106, 63),
	BronzeLight = rgb(181, 139, 79),
	BronzeInk = rgb(118, 88, 50),
	GoldLeaf = rgb(217, 178, 95),
	Ivory = rgb(237, 230, 214),
	IvorySoft = rgb(185, 176, 160),
	IvoryFaint = rgb(142, 134, 118),
	Graphite = rgb(26, 24, 20),
	Accent = rgb(201, 164, 92),
	Ribbon = rgb(31, 43, 74),
	Leather = rgb(56, 38, 29),
	LeatherDark = rgb(30, 21, 17),
	Gold = rgb(140, 106, 63),
	Redact = rgb(22, 19, 17),
	Terminal = rgb(18, 20, 17),
	Amber = rgb(240, 172, 78),
	AmberDim = rgb(160, 114, 56),
	Phosphor = rgb(132, 214, 140),
	Blueprint = rgb(32, 66, 114),
	BlueGrid = rgb(112, 164, 218),
	BlueLine = rgb(228, 238, 250),
	BlueCyan = rgb(150, 214, 240),
	BlueRed = rgb(226, 86, 70),
	Rule = rgb(146, 168, 196),
	Margin = rgb(198, 112, 104),
	Shadow = rgb(10, 9, 8),
}

local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.clamp(color.R * factor, 0, 1), math.clamp(color.G * factor, 0, 1), math.clamp(color.B * factor, 0, 1))
end

local function px(value: number): number
	return math.floor(value + 0.5)
end

local function corner(parent: Instance, radius: number): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function round(parent: Instance): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = parent })
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local playing = TweenService:Create(instance, info, goal)
	playing:Play()
	return playing
end

-- Type ----------------------------------------------------------------------------------------

type Typeface = { face: Font, enum: Enum.Font, bar: number, mono: boolean }
type Style = { font: Typeface, size: number, pitch: number, color: Color3, barColor: Color3? }

local function fontEnum(name: string): Enum.Font
	local ok, value = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value
	end
	return Enum.Font.SourceSans
end

-- Every face is checked by name; a missing family falls back to Builder Sans
local function fontFace(name: string, weight: Enum.FontWeight, style: Enum.FontStyle): Font
	local ok, face = pcall(Font.fromName, name, weight, style)
	if ok and face then
		return face
	end
	return Font.new("rbxasset://fonts/families/BuilderSans.json", weight, style)
end

-- `bar` is how tall a redaction bar is next to this face (it differs a lot
-- between a typewriter face and a handwriting face at the same TextSize)
local function typeface(name: string, weight: Enum.FontWeight?, style: Enum.FontStyle?, bar: number, mono: boolean?): Typeface
	return {
		face = fontFace(name, weight or Enum.FontWeight.Regular, style or Enum.FontStyle.Normal),
		enum = fontEnum(name),
		bar = bar,
		mono = mono == true,
	}
end

-- A face from an Enum.Font's family (Accanthis is "Bodoni" in Enum.Font)
local function enumTypeface(enumName: string, weight: Enum.FontWeight?, style: Enum.FontStyle?, bar: number): Typeface
	local enum = fontEnum(enumName)
	local ok, base = pcall(Font.fromEnum, enum)
	local family = if ok and base then base.Family else "rbxasset://fonts/families/BuilderSans.json"
	return {
		face = Font.new(family, weight or Enum.FontWeight.Regular, style or Enum.FontStyle.Normal),
		enum = enum,
		bar = bar,
		mono = false,
	}
end

local Bold, Italic, Medium = Enum.FontWeight.Bold, Enum.FontStyle.Italic, Enum.FontWeight.Medium

local TYPE = {
	-- Chapter titles and display capitals
	Display = enumTypeface("Bodoni", nil, nil, 0.6),
	-- Interface labels (the controls under the book)
	Ui = { face = Theme.Faces.SemiBold, enum = fontEnum("BuilderSansMedium"), bar = 0.6, mono = false },
	UiBold = { face = Theme.Faces.Bold, enum = fontEnum("BuilderSansBold"), bar = 0.6, mono = false },
	Serif = typeface("Merriweather", nil, nil, 0.6),
	SerifItalic = typeface("Merriweather", nil, Italic, 0.6),
	SerifBold = typeface("Merriweather", Bold, nil, 0.6),
	SerifBoldItalic = typeface("Merriweather", Bold, Italic, 0.6),
	Hand = typeface("Kalam", nil, nil, 0.42),
	Note = typeface("PatrickHand", nil, nil, 0.52),
	Type = typeface("SpecialElite", nil, nil, 0.8),
	Mono = typeface("RobotoMono", nil, nil, 0.62, true),
	MonoItalic = typeface("RobotoMono", nil, Italic, 0.62, true),
	MonoBold = typeface("RobotoMono", Bold, nil, 0.62, true),
	Sci = typeface("Michroma", nil, nil, 0.55),
	Tech = typeface("Jura", Medium, nil, 0.6),
}

local function style(font: Typeface, size: number, lead: number, color: Color3): Style
	local rounded = px(size)
	return { font = font, size = rounded, pitch = px(rounded * lead), color = color }
end

local BIG = Vector2.new(100000, 100000)
local widths: { [string]: number } = {}

-- Width of one line of plain text, from the real font (cached)
local function measure(text: string, font: Typeface, size: number): number
	if text == "" then
		return 0
	end
	local key = font.enum.Name .. "|" .. size .. "|" .. text
	local cached = widths[key]
	if cached then
		return cached
	end
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, size, font.enum, BIG)
	end)
	local width = if ok and typeof(bounds) == "Vector2" then bounds.X else (utf8.len(text) or #text) * size * 0.5
	widths[key] = width
	return width
end

local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }
local function escape(text: string): string
	return (string.gsub(text, "[&<>\"']", ESCAPES))
end

-- Setting text --------------------------------------------------------------------------------
-- Marked-up text becomes words: runs of pieces (plain or italic), or a
-- redaction `bar` some characters wide. A `glued` word follows the previous
-- one with no space between ("*settled*." or "{{...}}, Director").

type Piece = { text: string, italic: boolean }
type Word = { pieces: { Piece }, bar: number?, glued: boolean }
type Run = { x: number, w: number, rich: string }
type Bar = { x: number, w: number }
type Line = { runs: { Run }, bars: { Bar }, width: number }

-- Long redactions break into pieces this many characters wide, so a bar can
-- carry on onto the next line like real marker over a paragraph
local BAR_CHUNK = 10

local function parseWords(text: string, italic: boolean?): { Word }
	local result: { Word } = {}
	local spaced = true
	local base = italic == true
	local function addText(chunk: string, isItalic: boolean)
		for gap, word in string.gmatch(chunk, "(%s*)(%S+)") do
			local glued = gap == "" and not spaced and #result > 0
			local last = result[#result]
			if glued and last and not last.bar then
				table.insert(last.pieces, { text = word, italic = isItalic })
			else
				table.insert(result, { pieces = { { text = word, italic = isItalic } }, glued = glued })
			end
			spaced = false
		end
		if string.find(chunk, "%s$") then
			spaced = true
		end
	end
	local function addBar(hidden: string)
		-- Only the length of the hidden words is used: they are never kept
		local units = math.max(3, utf8.len(hidden) or #hidden)
		local glued = not spaced and #result > 0
		while units > 0 do
			local take = math.min(units, BAR_CHUNK)
			table.insert(result, { pieces = {}, bar = take, glued = glued })
			glued = false
			units -= take
		end
		spaced = false
	end
	local index = 1
	while index <= #text do
		local barAt = string.find(text, "{{", index, true)
		local italicAt = string.find(text, "*", index, true)
		local nextAt = math.min(barAt or math.huge, italicAt or math.huge)
		if nextAt == math.huge then
			addText(string.sub(text, index), base)
			break
		end
		if nextAt > index then
			addText(string.sub(text, index, nextAt - 1), base)
		end
		if nextAt == barAt then
			local close = string.find(text, "}}", nextAt + 2, true)
			if not close then
				-- An unclosed redaction hides the rest rather than showing it
				addBar(string.sub(text, nextAt + 2))
				break
			end
			addBar(string.sub(text, nextAt + 2, close - 1))
			index = close + 2
		else
			local close = string.find(text, "*", nextAt + 1, true)
			if not close then
				addText(string.sub(text, nextAt + 1), base)
				break
			end
			-- *words* inside italic text (a quoted line) turn roman, as in print
			addText(string.sub(text, nextAt + 1, close - 1), not base)
			index = close + 1
		end
	end
	return result
end

local function plainOf(word: Word): string
	local parts = {}
	for _, piece in word.pieces do
		table.insert(parts, piece.text)
	end
	return table.concat(parts)
end

local function richOf(word: Word): string
	local parts = {}
	for _, piece in word.pieces do
		local text = escape(piece.text)
		table.insert(parts, if piece.italic then "<i>" .. text .. "</i>" else text)
	end
	return table.concat(parts)
end

-- Proportional faces are measured word by word, so leave a little room: the
-- renderer must never wrap a line we didn't
local FIT = 0.965

-- Breaks marked-up text into lines no wider than `width`; the first line
-- starts `indent` in. Each line knows where its text runs and bars sit.
local function setText(text: string, st: Style, width: number, indent: number?, italic: boolean?): { Line }
	local font, size = st.font, st.size
	local space, unit
	if font.mono then
		local cell = measure("0000000000", font, size) / 10
		space, unit = cell, cell
	else
		space = math.max(1, measure("a a", font, size) - measure("aa", font, size))
		unit = measure("n", font, size) * 0.92
	end
	local function widthOf(word: Word): number
		if word.bar then
			return word.bar * unit
		elseif font.mono then
			return (utf8.len(plainOf(word)) or 0) * space
		end
		return measure(plainOf(word), font, size)
	end
	local fit = if font.mono then 1 else FIT

	local lines: { Line } = {}
	local current: { { word: Word, w: number } } = {}
	local used = 0
	local start = indent or 0
	local limit = (width - start) * fit

	local function flush()
		local line: Line = { runs = {}, bars = {}, width = 0 }
		local x = start
		local run: Run? = nil
		local parts: { string } = {}
		local bar: Bar? = nil
		for index, entry in current do
			local word = entry.word
			local gap = if index > 1 and not word.glued then space else 0
			if word.bar then
				if run then
					run.rich = table.concat(parts)
					run = nil
				end
				if bar then
					bar.w = x + gap + entry.w - bar.x
				else
					bar = { x = x + gap, w = entry.w }
					table.insert(line.bars, bar :: Bar)
				end
			else
				bar = nil
				if run then
					if gap > 0 then
						table.insert(parts, " ")
					end
					table.insert(parts, richOf(word))
					run.w = x + gap + entry.w - run.x
				else
					run = { x = x + gap, w = entry.w, rich = "" }
					parts = { richOf(word) }
					table.insert(line.runs, run :: Run)
				end
			end
			x += gap + entry.w
		end
		if run then
			run.rich = table.concat(parts)
		end
		line.width = x
		table.insert(lines, line)
		current = {}
		used = 0
		start = 0
		limit = width * fit
	end

	for _, word in parseWords(text, italic) do
		local w = widthOf(word)
		local add = (if #current > 0 and not word.glued then space else 0) + w
		if #current > 0 and used + add > limit then
			-- Words glued to this one move to the next line with it
			local carry = {}
			if word.glued then
				local first = #current
				while first > 1 and current[first].word.glued do
					first -= 1
				end
				if first > 1 then
					for k = first, #current do
						table.insert(carry, current[k])
					end
					for _ = first, #current do
						table.remove(current)
					end
				end
			end
			flush()
			for _, entry in carry do
				used += (if #current > 0 and not entry.word.glued then space else 0) + entry.w
				table.insert(current, entry)
			end
			add = (if #current > 0 and not word.glued then space else 0) + w
		end
		table.insert(current, { word = word, w = w })
		used += add
	end
	if #current > 0 or #lines == 0 then
		flush()
	end
	return lines
end

-- A printout line in a monospace face: a leading time or day column stays
-- put and the rest wraps under itself (a hanging indent), like a real log
local function setMono(text: string, st: Style, width: number): { Line }
	if string.match(text, "^%s*$") then
		return { { runs = {}, bars = {}, width = 0 } }
	end
	local cell = measure("0000000000", st.font, st.size) / 10
	local columns = math.max(16, math.floor(width / cell))
	local prefix, rest = string.match(text, "^(.-%S%s%s+)(%S.*)$")
	if not prefix then
		prefix, rest = string.match(text, "^(%s+)(%S.*)$")
	end
	if not prefix or #prefix > columns * 0.45 or string.find(prefix, "{{", 1, true) then
		prefix, rest = "", text
	end
	local hang = #(prefix :: string) * cell
	local lines = setText(rest :: string, st, width - hang)
	for _, line in lines do
		for _, run in line.runs do
			run.x += hang
		end
		for _, bar in line.bars do
			bar.x += hang
		end
		line.width += hang
	end
	local label = string.gsub(prefix :: string, "%s+$", "")
	if label ~= "" then
		table.insert(lines[1].runs, 1, { x = 0, w = #label * cell, rich = escape(label) })
	end
	return lines
end

-- Kinds ---------------------------------------------------------------------------------------
-- How each kind of document is set: its paper, body face and size (lead is
-- line pitch over size), space after paragraphs (in lines), headings, and
-- whatever it's printed on (a terminal panel, a paper slip).

local NO_INSET = { 0, 0, 0, 0 }

local KINDS: { [string]: { [string]: any } } = {
	letter = {
		paper = C.PaperCream, body = TYPE.Hand, size = 24, lead = 1.08, color = C.InkBlue, gap = 0.45,
		heading = TYPE.Hand, headingColor = C.InkBlue, crease = true,
	},
	journal = {
		paper = C.PaperLined, body = TYPE.Serif, size = 16, lead = 1.5, color = C.Ink, gap = 0, indent = 22,
		heading = TYPE.SerifBoldItalic, headingSize = 15, headingColor = C.BronzeInk, ruled = true,
	},
	memo = {
		paper = C.PaperWhite, body = TYPE.Type, size = 14, lead = 1.55, color = C.InkType, gap = 0.6,
		heading = TYPE.Type, linesSize = 14, linesColor = C.InkType,
		stamp = { "MERIDIAN INSTITUTE", "INTERNAL" },
	},
	dossier = {
		paper = C.Manila, body = TYPE.Serif, size = 15, lead = 1.55, color = C.Ink, gap = 0.5,
		heading = TYPE.Sci, headingSize = 14, headingColor = C.Ink, headingRule = true, headingUpper = true,
		clip = true, tab = "SUBJECT REGISTRY",
	},
	log = {
		paper = C.Paper, body = TYPE.Mono, size = 14, lead = 1.42, color = C.Amber, gap = 0.6,
		heading = TYPE.MonoBold, headingColor = C.Amber, panel = "terminal", inset = { 18, 36, 18, 26 },
	},
	transcript = {
		paper = C.PaperWhite, body = TYPE.Serif, size = 15, lead = 1.55, color = C.Ink, gap = 0.45,
		heading = TYPE.SerifBold, speakers = true,
	},
	report = {
		paper = C.PaperWhite, body = TYPE.Type, size = 14, lead = 1.55, color = C.InkType, gap = 0.6,
		heading = TYPE.Type, linesSize = 14, linesColor = C.InkType,
		stamp = { "CLASSIFIED", "MERIDIAN STATION" },
	},
	note = {
		paper = C.Paper, body = TYPE.Note, size = 23, lead = 1.1, color = rgb(64, 62, 66), gap = 0.4,
		heading = TYPE.Note, panel = "slip", inset = { 26, 24, 26, 22 },
	},
}

local MEMO_FIELDS = { TO = true, FROM = true, RE = true, CC = true, DATE = true, SUBJECT = true }

local ROMAN = { { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local function roman(number: number): string
	local parts = {}
	for _, pair in ROMAN do
		while number >= pair[1] do
			table.insert(parts, pair[2])
			number -= pair[1]
		end
	end
	return table.concat(parts)
end

local function seedOf(text: string): number
	local seed = 7
	for index = 1, #text do
		seed = (seed * 31 + string.byte(text, index)) % 2147483647
	end
	return seed
end

-- Drawing -------------------------------------------------------------------------------------
-- Figures are built from thin rotated frames (strokes), discs and labels.

local function stroke(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, alpha: number)
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.25 then
		return
	end
	make("Frame", {
		Name = "Stroke",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromOffset(length + thickness * 0.5, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = math.clamp(alpha, 0, 1),
		BorderSizePixel = 0,
		Parent = parent,
	})
end

local function polyline(parent: Instance, points: { Vector2 }, thickness: number, color: Color3, alpha: number, closed: boolean?)
	for index = 1, #points - 1 do
		stroke(parent, points[index], points[index + 1], thickness, color, alpha)
	end
	if closed and #points > 2 then
		stroke(parent, points[#points], points[1], thickness, color, alpha)
	end
end

-- Pencil: each line goes down in two or three slightly different passes,
-- the way a hand goes over a line, a little lighter each time
local function sketch(parent: Instance, points: { Vector2 }, rng: Random, color: Color3, options: { [string]: any }?)
	local opts = options or {}
	local passes = opts.passes or 2
	local jitter = opts.jitter or 0.6
	local thickness = opts.thickness or 1.2
	local alpha = opts.alpha or 0.4
	for pass = 1, passes do
		local previous: Vector2? = nil
		local first: Vector2? = nil
		local fade = (pass - 1) * 0.14
		for _, point in points do
			local moved = point + Vector2.new(rng:NextNumber(-jitter, jitter), rng:NextNumber(-jitter, jitter))
			if previous then
				stroke(parent, previous, moved, thickness * rng:NextNumber(0.75, 1.1), color, alpha + fade + rng:NextNumber(-0.05, 0.12))
			else
				first = moved
			end
			previous = moved
		end
		if opts.closed and previous and first then
			stroke(parent, previous, first, thickness, color, alpha + fade)
		end
	end
end

-- A smooth curve through the points (Catmull-Rom)
local function spline(points: { Vector2 }, steps: number): { Vector2 }
	local result = {}
	for index = 1, #points - 1 do
		local p0 = points[math.max(1, index - 1)]
		local p1, p2 = points[index], points[index + 1]
		local p3 = points[math.min(#points, index + 2)]
		for step = 0, steps - 1 do
			local t = step / steps
			local t2, t3 = t * t, t * t * t
			local point = (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
			table.insert(result, point)
		end
	end
	table.insert(result, points[#points])
	return result
end

local function ellipse(center: Vector2, rx: number, ry: number, count: number, rng: Random?, wobble: number?, from: number?, to: number?): { Vector2 }
	local points = {}
	local a0, a1 = from or 0, to or math.pi * 2
	for index = 0, count do
		local angle = a0 + (a1 - a0) * index / count
		local f = 1 + (if rng and wobble then rng:NextNumber(-wobble, wobble) else 0)
		table.insert(points, center + Vector2.new(math.cos(angle) * rx * f, math.sin(angle) * ry * f))
	end
	return points
end

local function disc(parent: Instance, center: Vector2, radius: number, color: Color3, alpha: number): Frame
	local frame = make("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		BackgroundColor3 = color,
		BackgroundTransparency = alpha,
		BorderSizePixel = 0,
		Parent = parent,
	})
	round(frame)
	return frame
end

local function ring(parent: Instance, center: Vector2, radius: number, thickness: number, color: Color3, alpha: number): Frame
	local frame = disc(parent, center, radius, color, 1)
	make("UIStroke", { Color = color, Thickness = thickness, Transparency = alpha, Parent = frame })
	return frame
end

local function box(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, alpha: number)
	polyline(parent, { a, Vector2.new(b.X, a.Y), b, Vector2.new(a.X, b.Y) }, thickness, color, alpha, true)
end

-- A short label inside a figure, anchored at `at` (left, centre or right)
local function figureText(parent: Instance, text: string, at: Vector2, font: Typeface, size: number, color: Color3, align: string?, alpha: number?, rotation: number?): TextLabel
	local width = math.ceil(measure(text, font, size) * 1.06) + 8
	return make("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(if align == "Center" then 0.5 elseif align == "Right" then 1 else 0, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(width, size + 6),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = font.face,
		TextSize = size,
		TextColor3 = color,
		TextTransparency = alpha or 0,
		TextWrapped = true,
		TextXAlignment = if align == "Center"
			then Enum.TextXAlignment.Center
			elseif align == "Right" then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Left,
		Rotation = rotation or 0,
		Parent = parent,
	})
end

local function gradient(parent: Instance, colors: { Color3 }, rotation: number): UIGradient
	local keys = {}
	for index, color in colors do
		table.insert(keys, CSK((index - 1) / (#colors - 1), color))
	end
	return make("UIGradient", { Color = ColorSequence.new(keys), Rotation = rotation, Parent = parent })
end

local function fill(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, alpha: number): Frame
	return make("Frame", {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BackgroundTransparency = alpha,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

-- Darkened edges, the way an old lens falls off toward the corners
local function vignette(canvas: Instance, strength: number)
	local depth = 0.34
	for _, side in { { 0, 0, depth, 1, 0 }, { 1 - depth, 0, depth, 1, 180 }, { 0, 0, 1, depth, 90 }, { 0, 1 - depth, 1, depth, 270 } } do
		local frame = make("Frame", {
			Name = "Vignette",
			Position = UDim2.fromScale(side[1], side[2]),
			Size = UDim2.fromScale(side[3], side[4]),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = canvas,
		})
		make("UIGradient", {
			Rotation = side[5],
			Transparency = NumberSequence.new({ NSK(0, 1 - strength), NSK(1, 1) }),
			Parent = frame,
		})
	end
end

local function grain(canvas: Instance, w: number, h: number, rng: Random, count: number)
	for _ = 1, count do
		local size = if rng:NextNumber() < 0.8 then 1 else 2
		make("Frame", {
			Name = "Grain",
			Position = UDim2.fromOffset(rng:NextInteger(0, math.max(0, w - 2)), rng:NextInteger(0, math.max(0, h - 2))),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = if rng:NextNumber() < 0.5 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
			BackgroundTransparency = rng:NextNumber(0.55, 0.85),
			BorderSizePixel = 0,
			Parent = canvas,
		})
	end
end

local function scanlines(parent: Instance, h: number, spacing: number, alpha: number)
	for y = 1, h - 1, spacing do
		make("Frame", {
			Name = "Scanline",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = alpha,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = parent,
		})
	end
end

local function blueprintGrid(canvas: Instance, w: number, h: number)
	local minor, major = 12, 60
	for x = minor, w - 1, minor do
		fill(canvas, x, 0, 1, h, C.BlueGrid, if x % major == 0 then 0.7 else 0.87)
	end
	for y = minor, h - 1, minor do
		fill(canvas, 0, y, w, 1, C.BlueGrid, if y % major == 0 then 0.7 else 0.87)
	end
end

local function titleBlock(canvas: Instance, at: Vector2, lines: { string })
	local width = 0
	for _, text in lines do
		width = math.max(width, measure(text, TYPE.Mono, 14))
	end
	local frame = fill(canvas, at.X, at.Y, math.ceil(width) + 18, 8 + #lines * 17, C.Blueprint, 0)
	frame.Name = "TitleBlock"
	make("UIStroke", { Color = C.BlueLine, Thickness = 1, Transparency = 0.3, Parent = frame })
	for index, text in lines do
		figureText(frame, text, Vector2.new(6, 12 + (index - 1) * 17), TYPE.Mono, 14, C.BlueLine, "Left", 0.1)
	end
end

-- Figures -------------------------------------------------------------------------------------
-- Each draws into a canvas `w` by `h`. ctx.spinners collects the 3D models
-- the window turns every frame.

type FigureContext = { spinners: { any } }
local FIGURES: { [string]: (canvas: Frame, w: number, h: number, rng: Random, ctx: FigureContext) -> () } = {}

-- Hale's sketch of the impact bowl from the west rim
FIGURES.valley_sketch = function(canvas, w, h, rng)
	local function P(x: number, y: number): Vector2
		return Vector2.new(x * w, y * h)
	end
	local ink = C.Pencil
	local far = spline({ P(0, 0.24), P(0.1, 0.16), P(0.22, 0.21), P(0.36, 0.09), P(0.5, 0.15), P(0.63, 0.07), P(0.78, 0.14), P(0.9, 0.09), P(1, 0.16) }, 4)
	sketch(canvas, far, rng, ink, { thickness = 1.3, alpha = 0.35 })
	for index = 2, #far - 1, 2 do
		local p = far[index]
		stroke(canvas, p + Vector2.new(2, 3), p + Vector2.new(-4, 3 + rng:NextNumber(5, 10)), 1, ink, 0.64)
	end
	local near = spline({ P(0, 0.34), P(0.14, 0.29), P(0.3, 0.33), P(0.45, 0.27), P(0.62, 0.31), P(0.8, 0.26), P(1, 0.32) }, 4)
	sketch(canvas, near, rng, ink, { thickness = 1.1, alpha = 0.45 })

	-- The bowl: contours closing in on the object
	local center = P(0.5, 0.6)
	local rx, ry = 0.4 * w, 0.24 * h
	for index, f in { 1, 0.76, 0.53, 0.31 } do
		sketch(canvas, ellipse(center, rx * f, ry * f, 32, rng, 0.025), rng, ink, {
			passes = if index == 1 then 3 else 2,
			thickness = if index == 1 then 1.5 else 1.1,
			alpha = if index == 1 then 0.22 else 0.38 + index * 0.05,
			closed = true,
		})
	end
	-- The glassed rim: short ticks round the near side
	for degrees = 12, 168, 11 do
		local angle = math.rad(degrees)
		local p = center + Vector2.new(math.cos(angle) * rx, math.sin(angle) * ry)
		local out = Vector2.new(math.cos(angle), math.sin(angle) * 0.7).Unit
		stroke(canvas, p, p + out * rng:NextNumber(4, 7), 1, ink, 0.42)
	end
	-- The object, long and faceted, and faint strokes radiating off it
	local tilt = math.rad(-14)
	local function at(x: number, y: number): Vector2
		return center + Vector2.new(x * math.cos(tilt) - y * math.sin(tilt), x * math.sin(tilt) + y * math.cos(tilt))
	end
	sketch(canvas, { at(0, -15), at(5, -3), at(3, 11), at(0, 15), at(-4, 4), at(-5, -6), at(0, -15) }, rng, ink, { thickness = 1.3, alpha = 0.15, jitter = 0.3 })
	stroke(canvas, at(0, -15), at(1, 15), 1, ink, 0.45)
	stroke(canvas, at(5, -3), at(-4, 4), 1, ink, 0.55)
	for k = 0, 11 do
		local angle = k / 12 * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local d = Vector2.new(math.cos(angle), math.sin(angle) * 0.62)
		stroke(canvas, center + d * 22, center + d * rng:NextNumber(29, 37), 1, ink, 0.62)
	end

	-- His labels
	local hand = TYPE.Hand
	figureText(canvas, "W. rim, looking east", P(0.015, 0.05), hand, 14, ink, "Left", 0.2)
	figureText(canvas, "rim (glassed)", P(0.01, 0.42), hand, 14, ink, "Left", 0.1)
	sketch(canvas, spline({ P(0.1, 0.46), P(0.14, 0.49), P(0.175, 0.5) }, 3), rng, ink, { passes = 1, thickness = 1, alpha = 0.35 })
	figureText(canvas, "object", P(0.8, 0.41), hand, 14, ink, "Left", 0.1)
	local tip = at(7, -2)
	sketch(canvas, spline({ P(0.79, 0.44), P(0.68, 0.47), P(0.6, 0.52), tip }, 3), rng, ink, { passes = 1, thickness = 1, alpha = 0.32 })
	stroke(canvas, tip, tip + Vector2.new(6, -1), 1, ink, 0.32)
	stroke(canvas, tip, tip + Vector2.new(3, -5), 1, ink, 0.32)
	-- 40 m across the bowl
	local y = 0.935 * h
	local left, right, half = 0.1 * w, 0.9 * w, 20
	sketch(canvas, { Vector2.new(left, y), Vector2.new(w / 2 - half, y) }, rng, ink, { passes = 1, alpha = 0.35, thickness = 1 })
	sketch(canvas, { Vector2.new(w / 2 + half, y), Vector2.new(right, y) }, rng, ink, { passes = 1, alpha = 0.35, thickness = 1 })
	stroke(canvas, Vector2.new(left, y - 5), Vector2.new(left, y + 5), 1, ink, 0.35)
	stroke(canvas, Vector2.new(right, y - 5), Vector2.new(right, y + 5), 1, ink, 0.35)
	figureText(canvas, "40 m", Vector2.new(w / 2, y), hand, 14, ink, "Center", 0.1)
end

-- The tune, on a hand-ruled stave: four notes rising, one falling, a rest
FIGURES.tune = function(canvas, w, h, rng)
	local ink = C.Pencil
	local gap = math.max(6, math.floor(h * 0.11))
	local bottom = math.floor(h * 0.66)
	local left, right = w * 0.05, w * 0.95
	for line = 0, 4 do
		local y = bottom - line * gap
		local slope = rng:NextNumber(-1.2, 1.2)
		local points = {}
		for k = 0, 6 do
			table.insert(points, Vector2.new(left + (right - left) * k / 6, y + slope * k / 6 + rng:NextNumber(-0.4, 0.4)))
		end
		sketch(canvas, points, rng, ink, { thickness = 1, alpha = 0.42, jitter = 0.3 })
	end
	local top = bottom - 4 * gap
	sketch(canvas, { Vector2.new(left, top), Vector2.new(left, bottom) }, rng, ink, { thickness = 1.2, alpha = 0.35, jitter = 0.3 })
	sketch(canvas, { Vector2.new(right - 5, top), Vector2.new(right - 5, bottom) }, rng, ink, { thickness = 1, alpha = 0.35, jitter = 0.3 })
	sketch(canvas, { Vector2.new(right, top), Vector2.new(right, bottom) }, rng, ink, { thickness = 2.2, alpha = 0.28, jitter = 0.3 })
	for index, step in { 1, 3, 5, 7, 4 } do
		local x = w * (0.17 + (index - 1) * 0.13)
		local y = bottom - step * gap / 2
		local head = make("Frame", {
			Name = "Note",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(gap * 1.3, gap * 0.86),
			Rotation = -22,
			BackgroundColor3 = ink,
			BackgroundTransparency = 0.16,
			BorderSizePixel = 0,
			Parent = canvas,
		})
		round(head)
		local up = step < 5
		local sx = if up then x + gap * 0.58 else x - gap * 0.58
		local reach = if up then -gap * 3.3 else gap * 3.3
		sketch(canvas, { Vector2.new(sx, y), Vector2.new(sx + 0.5, y + reach) }, rng, ink, { passes = 1, thickness = 1.2, alpha = 0.25, jitter = 0.3 })
		figureText(canvas, tostring(index), Vector2.new(x, bottom + gap * 1.8), TYPE.Hand, 14, ink, "Center", 0.3)
	end
	-- the rest, a hand-drawn zigzag
	local rx, ry = w * 0.82, bottom - 2 * gap
	sketch(canvas, {
		Vector2.new(rx - 2, ry - gap * 1.5),
		Vector2.new(rx + 4, ry - gap * 0.8),
		Vector2.new(rx - 3, ry - gap * 0.1),
		Vector2.new(rx + 4, ry + gap * 0.6),
		Vector2.new(rx - 2, ry + gap * 0.9),
		Vector2.new(rx + 1, ry + gap * 1.5),
	}, rng, ink, { thickness = 2, alpha = 0.2, jitter = 0.3 })
	figureText(canvas, "rest", Vector2.new(rx, bottom + gap * 1.8), TYPE.Hand, 14, ink, "Center", 0.3)
end

-- Growth against distance from the Lantern
FIGURES.exposure_chart = function(canvas, w, h, rng)
	local function P(x: number, y: number): Vector2
		return Vector2.new(x * w, y * h)
	end
	local line = C.BlueLine
	local top, origin, far = P(0.15, 0.1), P(0.15, 0.78), P(0.93, 0.78)
	polyline(canvas, { top, origin, far }, 1.5, line, 0.05)
	polyline(canvas, { top + Vector2.new(-4, 7), top, top + Vector2.new(4, 7) }, 1.5, line, 0.05)
	polyline(canvas, { far + Vector2.new(-7, -4), far, far + Vector2.new(-7, 4) }, 1.5, line, 0.05)
	for _, tick in { { 0.22, "1 m" }, { 0.45, "3 m" }, { 0.85, "10 m" } } do
		local p = P(tick[1] :: number, 0.78)
		stroke(canvas, p, p + Vector2.new(0, 5), 1.2, line, 0.1)
		figureText(canvas, tick[2] :: string, p + Vector2.new(0, 14), TYPE.Mono, 14, line, "Center", 0.05)
	end
	figureText(canvas, "DISTANCE FROM THE LANTERN", P(0.54, 0.93), TYPE.Mono, 14, line, "Center", 0.3)
	figureText(canvas, "GROWTH", P(0.07, 0.44), TYPE.Mono, 14, line, "Center", 0.3, -90)
	local curve = spline({
		P(0.17, 0.12), P(0.205, 0.17), P(0.22, 0.25), P(0.25, 0.43), P(0.3, 0.5), P(0.35, 0.46),
		P(0.4, 0.55), P(0.45, 0.6), P(0.6, 0.67), P(0.85, 0.71), P(0.92, 0.715),
	}, 5)
	polyline(canvas, curve, 2, C.BlueCyan, 0.05)
	for _, p in { P(0.22, 0.25), P(0.45, 0.6), P(0.85, 0.71) } do
		ring(canvas, p, 4, 1.4, line, 0)
		stroke(canvas, p + Vector2.new(0, -11), p + Vector2.new(0, -5), 1, line, 0.25)
		stroke(canvas, p + Vector2.new(0, 5), p + Vector2.new(0, 11), 1, line, 0.25)
	end
	-- somebody's spiral beside the 1 m point
	local spiral = {}
	local center = P(0.31, 0.2)
	for k = 0, 44 do
		local t = k / 44 * math.pi * 5
		local r = 1.2 + k * 0.26
		table.insert(spiral, center + Vector2.new(math.cos(t) * r, math.sin(t) * r))
	end
	sketch(canvas, spiral, rng, line, { passes = 1, thickness = 1, alpha = 0.35, jitter = 0.2 })
	titleBlock(canvas, Vector2.new(w - 100, 8), { "SERIES 1", "FIG. 2" })
end

-- The Garden in plan, with the leaning maple circled
FIGURES.garden_plan = function(canvas, w, h, rng)
	local function P(x: number, y: number): Vector2
		return Vector2.new(x * w, y * h)
	end
	local line = C.BlueLine
	local a, b = P(0.05, 0.08), P(0.76, 0.92)
	box(canvas, a, b, 1.6, line, 0.05)
	box(canvas, a + Vector2.new(4, 4), b - Vector2.new(4, 4), 1, line, 0.4)
	-- gate gap in the south wall
	fill(canvas, P(0.38, 0).X, b.Y - 6, 22, 9, C.Blueprint, 0)

	-- pond, with a few ripples
	local pond = P(0.22, 0.66)
	local outline = {}
	for k = 0, 23 do
		local angle = k / 24 * math.pi * 2
		local r = 1 + math.sin(angle * 3) * 0.12 + rng:NextNumber(-0.04, 0.04)
		table.insert(outline, pond + Vector2.new(math.cos(angle) * 0.1 * w * r, math.sin(angle) * 0.15 * h * r))
	end
	polyline(canvas, spline(outline, 2), 1.3, line, 0.1, true)
	for k = -1, 1 do
		local y = pond.Y + k * 8
		polyline(canvas, { Vector2.new(pond.X - 14, y), Vector2.new(pond.X - 7, y - 2), Vector2.new(pond.X, y), Vector2.new(pond.X + 7, y - 2), Vector2.new(pond.X + 14, y) }, 1, line, 0.5)
	end
	figureText(canvas, "POND", pond + Vector2.new(0, 0.2 * h), TYPE.Mono, 14, line, "Center", 0.2)

	-- the Lantern at the centre
	local lantern = P(0.43, 0.48)
	ring(canvas, lantern, 12, 1.4, line, 0)
	polyline(canvas, { lantern + Vector2.new(0, -6), lantern + Vector2.new(4, 0), lantern + Vector2.new(0, 6), lantern + Vector2.new(-4, 0) }, 1.2, line, 0, true)
	figureText(canvas, "LANTERN", lantern + Vector2.new(0, 22), TYPE.Mono, 14, line, "Center", 0.1)

	-- paths (dashed)
	local function dashed(points: { Vector2 })
		local curve = spline(points, 6)
		for index = 1, #curve - 1, 2 do
			stroke(canvas, curve[index], curve[index + 1], 1.2, line, 0.25)
		end
	end
	dashed({ P(0.41, 0.92), P(0.37, 0.8), P(0.44, 0.68), P(0.43, 0.56) })
	dashed({ P(0.76, 0.4), P(0.66, 0.34), P(0.57, 0.44), P(0.47, 0.47) })
	figureText(canvas, "EAST PATH", P(0.66, 0.28), TYPE.Mono, 14, line, "Center", 0.3)

	-- trees
	local placed = 0
	local tries = 0
	while placed < 18 and tries < 400 do
		tries += 1
		local p = P(rng:NextNumber(0.1, 0.72), rng:NextNumber(0.14, 0.86))
		if (p - pond).Magnitude > 0.16 * w and (p - lantern).Magnitude > 0.11 * w and (p - P(0.62, 0.22)).Magnitude > 0.06 * w then
			ring(canvas, p, rng:NextNumber(3.5, 5.5), 1, line, 0.2)
			disc(canvas, p, 1, line, 0.2)
			placed += 1
		end
	end
	-- the leaning maple, circled in pencil, with its lean drawn in
	local maple = P(0.62, 0.22)
	ring(canvas, maple, 5.5, 1.2, line, 0)
	local graphite = rgb(196, 204, 214)
	sketch(canvas, ellipse(maple, 14, 12, 18, rng, 0.08, -0.4, math.pi * 2 + 0.5), rng, graphite, { passes = 2, thickness = 1.2, alpha = 0.35, jitter = 0.5 })
	local lean = (lantern - maple).Unit
	local tipPoint = maple + lean * 30
	sketch(canvas, { maple + lean * 15, tipPoint }, rng, graphite, { passes = 1, thickness = 1.2, alpha = 0.3 })
	local side = Vector2.new(-lean.Y, lean.X)
	stroke(canvas, tipPoint, tipPoint - lean * 6 + side * 4, 1.2, graphite, 0.3)
	stroke(canvas, tipPoint, tipPoint - lean * 6 - side * 4, 1.2, graphite, 0.3)

	-- legend column
	local north = P(0.88, 0.2)
	stroke(canvas, north + Vector2.new(0, 14), north + Vector2.new(0, -14), 1.4, line, 0.05)
	polyline(canvas, { north + Vector2.new(-5, -6), north + Vector2.new(0, -14), north + Vector2.new(5, -6) }, 1.4, line, 0.05)
	figureText(canvas, "N", north + Vector2.new(0, -24), TYPE.Mono, 14, line, "Center", 0)
	local legend = P(0.8, 0.5)
	ring(canvas, legend + Vector2.new(6, 0), 4.5, 1, line, 0.2)
	figureText(canvas, "TREE", legend + Vector2.new(16, 0), TYPE.Mono, 14, line, "Left", 0.2)
	titleBlock(canvas, P(0.79, 0.66), { "THE GARDEN", "PLAN 1:500", "ARCH. COPY" })
end

-- The hall beneath the bowl, surveyed by lamp on the first descent
FIGURES.hall_survey = function(canvas, w, h, rng)
	local line = C.BlueLine
	local hand = rgb(214, 222, 234)
	local side = math.min(h - 22, w * 0.52)
	local a = Vector2.new(14, (h - side) / 2)
	local b = a + Vector2.new(side, side)
	local center = (a + b) / 2
	box(canvas, a, b, 1.6, line, 0.05)
	box(canvas, a + Vector2.new(4, 4), b - Vector2.new(4, 4), 1, line, 0.45)
	-- two colonnades of column dots
	for ringIndex, inset in { side * 0.09, side * 0.17 } do
		local count = if ringIndex == 1 then 11 else 8
		local lo, hi = a + Vector2.new(inset, inset), b - Vector2.new(inset, inset)
		for k = 0, count do
			local t = k / count
			local x = lo.X + (hi.X - lo.X) * t
			local y = lo.Y + (hi.Y - lo.Y) * t
			for _, p in { Vector2.new(x, lo.Y), Vector2.new(x, hi.Y), Vector2.new(lo.X, y), Vector2.new(hi.X, y) } do
				disc(canvas, p, if ringIndex == 1 then 2.6 else 2, line, if ringIndex == 1 then 0.05 else 0.25)
			end
		end
	end
	-- the vault overhead (dashed), broken open on one side
	local vault = side * 0.3
	local arc = ellipse(center, vault, vault, 56)
	for index = 1, #arc - 1, 2 do
		local angle = (index - 1) / 56 * math.pi * 2
		if angle < 3.75 or angle > 4.55 then
			stroke(canvas, arc[index], arc[index + 1], 1.2, line, 0.15)
		end
	end
	for _, angle in { 3.75, 4.55 } do
		local edge = center + Vector2.new(math.cos(angle), math.sin(angle)) * vault
		local out = Vector2.new(math.cos(angle), math.sin(angle))
		polyline(canvas, { edge - out * 5, edge + Vector2.new(-out.Y, out.X) * 3, edge + out * 5 }, 1, line, 0.2)
	end
	-- eight bays round the dais, numbered in the surveyor's hand
	for k = 0, 7 do
		local divide = (k + 0.5) / 8 * math.pi * 2 - math.pi / 2
		local d = Vector2.new(math.cos(divide), math.sin(divide))
		stroke(canvas, center + d * side * 0.11, center + d * side * 0.27, 1, line, 0.6)
		local angle = k / 8 * math.pi * 2 - math.pi / 2
		local spot = center + Vector2.new(math.cos(angle), math.sin(angle)) * side * 0.2
		figureText(canvas, tostring(k + 1), spot, TYPE.Hand, 14, hand, "Center", 0.05)
	end
	-- the dais, with the Lantern star where the crystal stands
	local dais = side * 0.08
	box(canvas, center - Vector2.new(dais, dais), center + Vector2.new(dais, dais), 1.5, line, 0)
	box(canvas, center - Vector2.new(dais - 3, dais - 3), center + Vector2.new(dais - 3, dais - 3), 1, line, 0.4)
	for _, rotation in { 0, 45 } do
		make("Frame", {
			Name = "Star",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(6, 6),
			Rotation = rotation,
			BackgroundColor3 = line,
			BorderSizePixel = 0,
			Parent = canvas,
		})
	end
	-- the surveyor's note, the scale and the title block
	local column = b.X + 26
	figureText(canvas, "lamp survey, 1st descent", Vector2.new(column, a.Y + 14), TYPE.Hand, 14, hand, "Left", 0.05)
	sketch(canvas, { Vector2.new(column, a.Y + 26), Vector2.new(math.min(w - 8, column + 150), a.Y + 27) }, rng, hand, { passes = 1, thickness = 1, alpha = 0.35, jitter = 0.4 })
	local scaleY = b.Y - 6
	local unit = math.min(30, (w - column - 60) / 4)
	for k = 0, 3 do
		fill(canvas, column + k * unit, scaleY - 3, unit, 5, line, if k % 2 == 0 then 0.1 else 0.75)
	end
	box(canvas, Vector2.new(column, scaleY - 3), Vector2.new(column + unit * 4, scaleY + 2), 1, line, 0.2)
	figureText(canvas, "0", Vector2.new(column, scaleY - 15), TYPE.Mono, 14, line, "Center", 0.2)
	figureText(canvas, "20 m", Vector2.new(column + unit * 4, scaleY - 15), TYPE.Mono, 14, line, "Center", 0.2)
	titleBlock(canvas, Vector2.new(column, a.Y + 40), { "HALL BENEATH", "DEPTH 41 M", "AUG. 1980" })
end

local SIGILS: { (canvas: Frame, c: Vector2, r: number, color: Color3) -> () } = {
	-- ATLAS: a rising bar
	function(canvas, c, r, color)
		box(canvas, c + Vector2.new(-r * 0.22, -r * 0.35), c + Vector2.new(r * 0.22, r), 1.5, color, 0)
		polyline(canvas, { c + Vector2.new(-r * 0.45, -r * 0.6), c + Vector2.new(0, -r * 1.05), c + Vector2.new(r * 0.45, -r * 0.6) }, 1.5, color, 0)
		stroke(canvas, c + Vector2.new(-r * 0.8, r), c + Vector2.new(r * 0.8, r), 1.5, color, 0)
	end,
	-- VEIL: a half circle
	function(canvas, c, r, color)
		local base = c + Vector2.new(0, r * 0.45)
		polyline(canvas, ellipse(base, r, r, 16, nil, nil, math.pi, math.pi * 2), 1.5, color, 0)
		stroke(canvas, base + Vector2.new(-r, 0), base + Vector2.new(r, 0), 1.5, color, 0)
	end,
	-- CHIMERA: three claw strokes
	function(canvas, c, r, color)
		for k = -1, 1 do
			local x = c.X + k * r * 0.5
			local points = spline({ Vector2.new(x + r * 0.4, c.Y - r), Vector2.new(x + r * 0.08, c.Y), Vector2.new(x - r * 0.35, c.Y + r) }, 4)
			for index = 1, #points - 1 do
				stroke(canvas, points[index], points[index + 1], 2.4 - index * 0.15, color, 0)
			end
		end
	end,
	-- FURNACE: a flame inside a gear
	function(canvas, c, r, color)
		ring(canvas, c, r * 0.82, 1.5, color, 0)
		for k = 0, 7 do
			local angle = k / 8 * math.pi * 2
			local p = c + Vector2.new(math.cos(angle), math.sin(angle)) * r * 0.98
			make("Frame", {
				Name = "Tooth",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(p.X, p.Y),
				Size = UDim2.fromOffset(r * 0.3, r * 0.26),
				Rotation = math.deg(angle),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = canvas,
			})
		end
		local flame = spline({
			c + Vector2.new(0, -r * 0.55), c + Vector2.new(r * 0.26, -r * 0.05), c + Vector2.new(r * 0.2, r * 0.32),
			c + Vector2.new(0, r * 0.42), c + Vector2.new(-r * 0.2, r * 0.32), c + Vector2.new(-r * 0.26, -r * 0.05), c + Vector2.new(0, -r * 0.55),
		}, 3)
		polyline(canvas, flame, 1.4, color, 0)
	end,
	-- ECLIPSE: a ring with its inside filled
	function(canvas, c, r, color)
		ring(canvas, c, r, 1.5, color, 0)
		disc(canvas, c, r * 0.66, color, 0.05)
	end,
	-- LATTICE: a grid of dots
	function(canvas, c, r, color)
		for gx = -1, 1 do
			for gy = -1, 1 do
				disc(canvas, c + Vector2.new(gx, gy) * r * 0.72, 2.3, color, 0)
			end
		end
	end,
	-- WARDEN: a keyhole in a shield
	function(canvas, c, r, color)
		local shield = spline({
			c + Vector2.new(-r * 0.8, -r * 0.9), c + Vector2.new(r * 0.8, -r * 0.9), c + Vector2.new(r * 0.78, r * 0.05),
			c + Vector2.new(0, r * 1.0), c + Vector2.new(-r * 0.78, r * 0.05), c + Vector2.new(-r * 0.8, -r * 0.9),
		}, 3)
		polyline(canvas, shield, 1.5, color, 0)
		disc(canvas, c + Vector2.new(0, -r * 0.22), r * 0.2, color, 0)
		local slot = make("Frame", {
			Name = "Keyhole",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(c.X, c.Y - r * 0.2),
			Size = UDim2.fromOffset(r * 0.18, r * 0.48),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = canvas,
		})
		corner(slot, 1)
	end,
	-- the eighth square is left blank
	function() end,
}

FIGURES.programme_sigils = function(canvas, w, h)
	local line = C.BlueLine
	local names = { "ATLAS", "VEIL", "CHIMERA", "FURNACE", "ECLIPSE", "LATTICE", "WARDEN", "" }
	local mx, my = 8, 6
	local cw, ch = (w - mx * 2) / 4, (h - my * 2) / 2
	for index = 1, 8 do
		local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
		local x0, y0 = mx + col * cw, my + row * ch
		local cell = make("Frame", {
			Name = "Cell",
			Position = UDim2.fromOffset(x0 + 3, y0 + 3),
			Size = UDim2.fromOffset(cw - 6, ch - 6),
			BackgroundTransparency = 1,
			Parent = canvas,
		})
		make("UIStroke", { Color = line, Thickness = 1, Transparency = if index == 8 then 0.6 else 0.45, Parent = cell })
		local r = math.min(cw, ch) * 0.19
		SIGILS[index](canvas, Vector2.new(x0 + cw / 2, y0 + ch * 0.42), r, line)
		if names[index] ~= "" then
			figureText(canvas, names[index], Vector2.new(x0 + cw / 2, y0 + ch * 0.8), TYPE.Sci, 14, line, "Center", 0.05)
		end
	end
end

-- The station plan from the incident record
FIGURES.cascade_map = function(canvas, w, h)
	local function P(x: number, y: number): Vector2
		return Vector2.new(x * w, y * h)
	end
	local line = C.BlueLine
	local chamber5 = P(0.82, 0.5)
	-- the spread, drawn first so the linework sits on top
	for index, radius in { 0.62, 0.46, 0.32, 0.19 } do
		disc(canvas, chamber5, radius * w, C.BlueRed, 0.92 - index * 0.035)
	end
	box(canvas, P(0.02, 0.04), P(0.98, 0.96), 1, line, 0.55)
	box(canvas, P(0.33, 0.24), P(0.63, 0.76), 1.6, line, 0.05)
	figureText(canvas, "GARDEN", P(0.48, 0.44), TYPE.Mono, 14, line, "Center", 0.05)
	figureText(canvas, "INCIDENT 88-0412", P(0.48, 0.56), TYPE.Mono, 14, line, "Center", 0.35)
	local chambers = {
		{ "1", 0.06, 0.08 }, { "2", 0.06, 0.4 }, { "3", 0.06, 0.72 },
		{ "4", 0.74, 0.08 }, { "5", 0.74, 0.4 }, { "6", 0.74, 0.72 },
		{ "7", 0.4, 0.06 }, { "8", 0.4, 0.8 },
	}
	for _, spec in chambers do
		local x, y = spec[2] :: number, spec[3] :: number
		local wide = if spec[1] == "7" or spec[1] == "8" then 0.16 else 0.16
		local tall = if spec[1] == "7" or spec[1] == "8" then 0.12 else 0.2
		local a, b = P(x, y), P(x + wide, y + tall)
		if spec[1] == "5" then
			fill(canvas, a.X, a.Y, b.X - a.X, b.Y - a.Y, C.BlueRed, 0.35)
		end
		box(canvas, a, b, 1.3, line, 0.05)
		figureText(canvas, spec[1] :: string, (a + b) / 2, TYPE.Mono, 14, line, "Center", 0)
		-- corridor to the Garden
		local mid = (a + b) / 2
		local target = if x < 0.3 then Vector2.new(P(0.33, 0).X, mid.Y)
			elseif x > 0.7 then Vector2.new(P(0.63, 0).X, mid.Y)
			elseif y < 0.3 then Vector2.new(mid.X, P(0, 0.24).Y)
			else Vector2.new(mid.X, P(0, 0.76).Y)
		local from = if x < 0.3 then Vector2.new(b.X, mid.Y)
			elseif x > 0.7 then Vector2.new(a.X, mid.Y)
			elseif y < 0.3 then Vector2.new(mid.X, b.Y)
			else Vector2.new(mid.X, a.Y)
		stroke(canvas, from, target, 1, line, 0.4)
	end
	-- Door 09, in red on the west wall
	local door = P(0.02, 0.82)
	fill(canvas, door.X - 3, door.Y - 9, 6, 18, C.BlueRed, 0)
	stroke(canvas, P(0.22, 0.82), door, 1, C.BlueRed, 0.2)
	figureText(canvas, "09", door + Vector2.new(9, -12), TYPE.Mono, 14, C.BlueRed, "Left", 0)
	-- legend
	fill(canvas, P(0.4, 0).X, P(0, 0.64).Y, 8, 8, C.BlueRed, 0.3)
	figureText(canvas, "AFFECTED", Vector2.new(P(0.4, 0).X + 12, P(0, 0.64).Y + 4), TYPE.Mono, 14, line, "Left", 0.25)
end

-- A grainy security still: dawn, mist on the pond, an old man and a broom
FIGURES.groundskeeper = function(canvas, w, h, rng)
	local function P(x: number, y: number): Vector2
		return Vector2.new(x * w, y * h)
	end
	canvas.BackgroundColor3 = rgb(126, 136, 130)
	gradient(canvas, { rgb(170, 178, 172), rgb(132, 142, 136), rgb(70, 78, 74) }, 90)
	-- roof lattice, high and faint
	local girder = rgb(66, 72, 70)
	for k = -1, 7 do
		stroke(canvas, P(k * 0.16 - 0.1, 0), P(k * 0.16 + 0.12, 0.28), 1, girder, 0.8)
		stroke(canvas, P(k * 0.16 + 0.12, 0), P(k * 0.16 - 0.1, 0.28), 1, girder, 0.85)
	end
	stroke(canvas, P(0, 0.29), P(1, 0.27), 2, girder, 0.7)
	-- trees along the far side
	for k = 0, 16 do
		disc(canvas, P(k / 16 + rng:NextNumber(-0.02, 0.02), 0.44 + rng:NextNumber(-0.03, 0.02)), rng:NextNumber(0.05, 0.085) * w, rgb(62, 72, 68), rng:NextNumber(0.35, 0.55))
	end
	-- the Lantern, far behind, glowing faintly
	local lantern = P(0.72, 0.4)
	for _, spec in { { 44, 0.9 }, { 24, 0.82 }, { 11, 0.6 }, { 4.5, 0.2 }, { 2, 0 } } do
		disc(canvas, lantern, spec[1], rgb(238, 244, 240), spec[2])
	end
	-- mist lying over the pond
	local mist = fill(canvas, 0, h * 0.4, w, h * 0.26, rgb(226, 232, 228), 0.35)
	mist.Name = "Mist"
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NSK(0, 1), NSK(0.5, 0.45), NSK(1, 1) }), Parent = mist })
	-- the pond
	local pond = make("Frame", {
		Name = "Pond",
		Position = UDim2.fromOffset(w * 0.48, h * 0.6),
		Size = UDim2.fromOffset(w * 0.6, h * 0.12),
		BackgroundColor3 = rgb(88, 98, 96),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	round(pond)
	stroke(canvas, P(0.56, 0.645), P(0.9, 0.65), 1, rgb(200, 210, 206), 0.6)
	-- the east path, coming in from the bottom left
	local path = spline({ P(-0.05, 1.02), P(0.12, 0.9), P(0.3, 0.8), P(0.46, 0.7) }, 4)
	for index = 1, #path - 1 do
		local t = index / #path
		stroke(canvas, path[index], path[index + 1], 30 - t * 24, rgb(156, 162, 154), 0.5)
	end
	-- the groundskeeper in a low stance, holding the broom like a staff
	local ink = rgb(30, 33, 32)
	local function limb(a: Vector2, b: Vector2, c: Vector2, thickness: number)
		stroke(canvas, a, b, thickness, ink, 0.04)
		stroke(canvas, b, c, thickness * 0.85, ink, 0.04)
	end
	local footShadow = make("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(w * 0.3, h * 0.845),
		Size = UDim2.fromOffset(w * 0.2, h * 0.03),
		BackgroundColor3 = ink,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	round(footShadow)
	local hip = P(0.3, 0.66)
	limb(hip + Vector2.new(-2, 0), P(0.255, 0.74), P(0.225, 0.835), 5)
	limb(hip + Vector2.new(2, 0), P(0.345, 0.74), P(0.375, 0.835), 5)
	stroke(canvas, P(0.215, 0.835), P(0.235, 0.835), 3, ink, 0.05)
	stroke(canvas, P(0.37, 0.835), P(0.39, 0.835), 3, ink, 0.05)
	stroke(canvas, hip, P(0.306, 0.53), 9, ink, 0.04)
	disc(canvas, P(0.31, 0.49), 5.5, ink, 0.04)
	limb(P(0.306, 0.55), P(0.27, 0.585), P(0.235, 0.575), 3)
	limb(P(0.306, 0.55), P(0.345, 0.575), P(0.385, 0.555), 3)
	stroke(canvas, P(0.15, 0.6), P(0.47, 0.535), 2, ink, 0.05)
	local brush = make("Frame", {
		Name = "Broom",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(w * 0.48, h * 0.532),
		Size = UDim2.fromOffset(12, 7),
		Rotation = -12,
		BackgroundColor3 = ink,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = canvas,
	})
	corner(brush, 2)
	-- the camera's own marks
	local overlay = rgb(236, 240, 236)
	figureText(canvas, "CAM 04  EAST PATH", P(0.03, 0.08), TYPE.Mono, 14, overlay, "Left", 0.15)
	figureText(canvas, "05:02", P(0.97, 0.92), TYPE.Mono, 14, overlay, "Right", 0.1)
	scanlines(canvas, h, 3, 0.9)
	grain(canvas, w, h, rng, 200)
	vignette(canvas, 0.55)
end

-- AJKR's first photograph: dark, overgrown, a maple leaning toward the light
FIGURES.ajkr_photo = function(canvas, w, h, rng)
	local function P(x: number, y: number): Vector2
		return Vector2.new(x * w, y * h)
	end
	canvas.BackgroundColor3 = rgb(16, 18, 18)
	gradient(canvas, { rgb(30, 32, 34), rgb(18, 20, 19), rgb(9, 10, 9) }, 90)
	-- roof lattice, far above
	for k = -3, 10 do
		stroke(canvas, P(k * 0.12, 0), P(k * 0.12 + 0.2, 0.36), 1, rgb(120, 126, 130), 0.86)
		stroke(canvas, P(k * 0.12 + 0.2, 0), P(k * 0.12, 0.36), 1, rgb(120, 126, 130), 0.9)
	end
	-- the light at the centre
	local light = P(0.64, 0.5)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2 + 0.3
		stroke(canvas, light, light + Vector2.new(math.cos(angle), math.sin(angle)) * w * 0.3, 1, rgb(255, 238, 200), 0.94)
	end
	for _, spec in { { 72, 0.93 }, { 44, 0.88 }, { 24, 0.74 }, { 11, 0.42 }, { 4, 0.02 } } do
		disc(canvas, light, spec[1], rgb(255, 238, 202), spec[2])
	end
	-- the maple, bending toward it
	local trunk = spline({ P(0.24, 1.04), P(0.26, 0.86), P(0.31, 0.7), P(0.39, 0.58), P(0.48, 0.52) }, 4)
	local bark = rgb(28, 19, 15)
	for index = 1, #trunk - 1 do
		stroke(canvas, trunk[index], trunk[index + 1], 9 - index / #trunk * 6.5, bark, 0.04)
	end
	for _, spec in { { 6, 0.36, 0.5 }, { 9, 0.44, 0.44 }, { 11, 0.5, 0.58 } } do
		local from = trunk[spec[1]]
		stroke(canvas, from, P(spec[2], spec[3]), 2, bark, 0.1)
	end
	for _ = 1, 26 do
		local p = P(0.42 + rng:NextNumber(-0.17, 0.17), 0.4 + rng:NextNumber(-0.15, 0.13))
		local toLight = math.clamp(1 - (p - light).Magnitude / (w * 0.35), 0, 1)
		local color = rgb(84, 24, 20):Lerp(rgb(176, 58, 36), toLight)
		disc(canvas, p, rng:NextNumber(0.025, 0.055) * w, color, rng:NextNumber(0.12, 0.35))
	end
	-- tall grass in the foreground
	for _ = 1, 64 do
		local x = rng:NextNumber(-0.02, 1.02) * w
		local tall = rng:NextNumber(0.12, 0.34) * h
		local lean = rng:NextNumber(-6, 10) + (light.X - x) * 0.04
		local lit = math.abs(x - light.X) < w * 0.22
		local color = if lit then rgb(74, 88, 56) else rgb(22, 32, 22)
		local base = Vector2.new(x, h + 2)
		local mid = base + Vector2.new(lean * 0.4, -tall * 0.55)
		local tip = base + Vector2.new(lean, -tall)
		local thickness = rng:NextNumber(1.3, 2.4)
		stroke(canvas, base, mid, thickness, color, 0.05)
		stroke(canvas, mid, tip, thickness * 0.6, color, 0.1)
	end
	grain(canvas, w, h, rng, 240)
	vignette(canvas, 0.75)
end

-- WARDEN's bird, saved as text
local BIRD = {
	[[                .--.]],
	[[               / o  `.]],
	[[           <___      |]],
	[[               \  .  /`-.]],
	[[                |  `-'    `-.]],
	[[                \    `-.     `.]],
	[[                 `.     `-.___.']],
	[[                   `-.__.-' \]],
	[[                      ||     `.]],
	[[  ____________________||__________________]],
}

FIGURES.bird = function(canvas, w, h)
	local size = 14
	local pitch = 15
	local cell = measure("0000000000", TYPE.Mono, size) / 10
	local columns = 0
	for _, text in BIRD do
		columns = math.max(columns, #text)
	end
	local x0 = math.floor((w - columns * cell) / 2)
	local y0 = math.max(24, math.floor((h - #BIRD * pitch) / 2) + 8)
	figureText(canvas, "IMG_0001.TXT", Vector2.new(4, 10), TYPE.Mono, 14, C.Phosphor, "Left", 0.5)
	for index, text in BIRD do
		make("TextLabel", {
			Name = "Art",
			Position = UDim2.fromOffset(x0, y0 + (index - 1) * pitch),
			Size = UDim2.fromOffset(math.ceil(#text * cell) + 12, pitch),
			BackgroundTransparency = 1,
			Text = text,
			FontFace = TYPE.Mono.face,
			TextSize = size,
			TextColor3 = C.Phosphor,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = canvas,
		})
	end
end

-- The Lantern itself: a pale faceted crystal turning slowly in the dark
FIGURES.lantern = function(canvas, w, h, rng, ctx)
	canvas.BackgroundColor3 = rgb(15, 17, 23)
	local middle = Vector2.new(w / 2, h / 2)
	for _, spec in { { 0.5, 0.95 }, { 0.34, 0.92 }, { 0.2, 0.86 } } do
		disc(canvas, middle, spec[1] * math.min(w, h), rgb(150, 210, 230), spec[2])
	end
	local side = math.min(w, h) * 0.98
	local viewport = make("ViewportFrame", {
		Name = "Lantern",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(side, side),
		BackgroundTransparency = 1,
		Ambient = rgb(92, 104, 124),
		LightColor = rgb(255, 244, 228),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
		Parent = canvas,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.6, 11), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model = Instance.new("Model")
	model.Name = "Crystal"
	local function part(size: Vector3, cframe: CFrame, color: Color3, transparency: number, material: Enum.Material)
		local piece = Instance.new("Part")
		piece.Anchored = true
		piece.CastShadow = false
		piece.Size = size
		piece.CFrame = cframe
		piece.Color = color
		piece.Transparency = transparency
		piece.Material = material
		piece.Parent = model
	end
	local pale = rgb(214, 236, 242)
	for k = 0, 2 do
		part(Vector3.new(0.95, 3.4, 0.55), CFrame.Angles(0, math.rad(k * 60), 0), pale, 0.15, Enum.Material.Glass)
	end
	-- a cube stood on its corner makes each pointed end
	local corner45 = CFrame.Angles(math.rad(45), 0, math.rad(35.26))
	part(Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 1.7, 0) * corner45, pale, 0.15, Enum.Material.Glass)
	part(Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, -1.7, 0) * corner45, pale, 0.15, Enum.Material.Glass)
	part(Vector3.new(0.3, 2.7, 0.3), CFrame.new(), rgb(206, 246, 255), 0, Enum.Material.Neon)
	part(Vector3.new(0.26, 0.8, 0.18), CFrame.new(1.3, 0.7, 0.2) * CFrame.Angles(0, 0.4, 0.5), pale, 0.25, Enum.Material.Glass)
	part(Vector3.new(0.2, 0.6, 0.15), CFrame.new(-1.15, -0.95, -0.3) * CFrame.Angles(0.3, 0, -0.6), pale, 0.25, Enum.Material.Glass)
	model.Parent = viewport
	local tilt = CFrame.Angles(0, 0, math.rad(12))
	local angle = rng:NextNumber(0, math.pi * 2)
	model:PivotTo(tilt * CFrame.Angles(0, angle, 0))
	table.insert(ctx.spinners, { model = model, tilt = tilt, angle = angle, holder = viewport })
end

-- How tall each style of figure is, against its width
local FIGURE_RATIO = { pencil = 0.44, blueprint = 0.5, photo = 0.52, terminal = 0.47, viewport = 0.62 }

-- Builds a figure in its mount: a tipped-in sketch sheet, a blueprint, a
-- bordered print, a terminal screen or a dark plate. `bare` draws straight
-- onto the page (a pencil drawing on a note).
local function buildFigure(parent: Instance, id: string, x: number, y: number, w: number, h: number, ctx: FigureContext, bare: boolean?): Frame
	local figure = Archive.Figures[id]
	local look = if figure then figure.style else "pencil"
	local rng = Random.new(seedOf(id))
	local holder = make("Frame", {
		Name = "Figure_" .. id,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local function shadow(spread: number, alpha: number)
		local frame = fill(holder, 2, 3, w + spread, h + spread, C.Shadow, alpha)
		frame.Name = "Shadow"
		corner(frame, 3)
	end
	local inset = 8
	local surface: Frame
	if bare then
		surface = holder
		inset = 0
	elseif look == "blueprint" then
		shadow(1, 0.8)
		surface = fill(holder, 0, 0, w, h, C.Blueprint, 0)
		corner(surface, 2)
		local border = make("Frame", { Name = "Border", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, Parent = surface })
		make("UIStroke", { Color = C.BlueLine, Thickness = 1, Transparency = 0.55, Parent = border })
	elseif look == "photo" then
		shadow(1, 0.78)
		surface = fill(holder, 0, 0, w, h, rgb(238, 235, 228), 0)
		inset = 7
	elseif look == "terminal" then
		shadow(1, 0.75)
		surface = fill(holder, 0, 0, w, h, rgb(44, 44, 40), 0)
		corner(surface, 8)
		local screen = fill(surface, 6, 6, w - 12, h - 12, rgb(9, 13, 10), 0)
		screen.Name = "Screen"
		corner(screen, 5)
		inset = 10
	elseif look == "viewport" then
		shadow(1, 0.75)
		surface = fill(holder, 0, 0, w, h, rgb(15, 17, 23), 0)
		inset = 6
	else
		-- a sheet tipped in with two strips of tape
		shadow(0, 0.84)
		surface = fill(holder, 0, 0, w, h, C.Sheet, 0)
	end
	surface.Name = if surface == holder then holder.Name else "Mount"
	local cw, ch = math.max(10, w - inset * 2), math.max(10, h - inset * 2)
	local canvas = make("Frame", {
		Name = "Canvas",
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.fromOffset(cw, ch),
		BackgroundTransparency = 1,
		BackgroundColor3 = C.Blueprint,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = surface,
	})
	if look == "blueprint" and not bare then
		blueprintGrid(canvas, cw, ch)
	elseif look == "photo" or look == "viewport" then
		canvas.BackgroundTransparency = 0
	end
	local draw = FIGURES[id]
	if draw then
		draw(canvas, cw, ch, rng, ctx)
	end
	if look == "terminal" and not bare then
		scanlines(canvas, ch, 3, 0.8)
	end
	if look == "pencil" and not bare then
		for _, spec in { { 0.06, -36 }, { 0.94, 34 } } do
			make("Frame", {
				Name = "Tape",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(spec[1], 0, 0, 2),
				Size = UDim2.fromOffset(46, 13),
				Rotation = spec[2],
				BackgroundColor3 = rgb(236, 226, 194),
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = holder,
			})
		end
	elseif look == "photo" and not bare then
		-- black paper photo corners
		for _, spec in { { 0, 0, 45 }, { 1, 0, 135 }, { 1, 1, 225 }, { 0, 1, 315 } } do
			make("Frame", {
				Name = "PhotoCorner",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spec[1], spec[2]),
				Size = UDim2.fromOffset(26, 9),
				Rotation = -spec[3] + 90,
				BackgroundColor3 = rgb(40, 34, 30),
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = holder,
			})
		end
	end
	return holder
end

-- Pagination ----------------------------------------------------------------------------------

type Geometry = {
	single: boolean,
	pageW: number,
	pageH: number,
	cover: number,
	textW: number,
	textH: number,
	top: number,
	bottom: number,
	outer: number,
	inner: number,
	scale: number,
	bookW: number,
	bookH: number,
}

local function geometryFor(size: Vector2, compact: boolean): Geometry
	local single = compact or size.X < CONFIG.SpreadWidth
	local cover = CONFIG.Cover
	local pageH = math.floor(math.min(size.Y - CONFIG.ControlsHeight - CONFIG.ControlsGap - cover * 2 - 4, CONFIG.MaxPageHeight))
	local pageW
	if single then
		pageW = math.floor(math.min(size.X - cover * 2 - 16, pageH * 1.45, CONFIG.MaxSinglePage))
	else
		pageW = math.floor(math.min((size.X - cover * 2 - 16) / 2, pageH * 0.98, CONFIG.MaxSpreadPage))
	end
	local top = if single then 40 else 46
	local bottom = if single then 40 else 46
	local outer = if single then 40 else 42
	local inner = if single then 40 else 48
	return {
		single = single,
		pageW = pageW,
		pageH = pageH,
		cover = cover,
		textW = pageW - outer - inner,
		textH = pageH - top - bottom,
		top = top,
		bottom = bottom,
		outer = outer,
		inner = inner,
		scale = if single then CONFIG.SingleTypeScale else 1,
		bookW = (if single then pageW else pageW * 2) + cover * 2,
		bookH = pageH + cover * 2,
	}
end

-- A document's pages: an opener (number, title, source line) then its blocks,
-- flowed line by line. Figures that don't fit float to the top of the next
-- page while the text carries on.
local function flowDocument(doc: any, geo: Geometry): { any }
	local spec = KINDS[doc.kind] or KINDS.journal
	local s = geo.scale
	local W, H = geo.textW, geo.textH
	local inset = spec.inset or NO_INSET
	local il, it, ir, ib = px(inset[1] * s), px(inset[2] * s), px(inset[3] * s), px(inset[4] * s)
	local bodyW = W - il - ir
	local body = style(spec.body, spec.size * s, spec.lead, spec.color)
	if spec.panel == "terminal" then
		body.barColor = spec.color
	end
	local pitch = body.pitch
	local snap = spec.ruled == true
	local heading = style(spec.heading or spec.body, (spec.headingSize or spec.size) * s, 1.5, spec.headingColor or spec.color)
	heading.barColor = body.barColor
	local mono = style(TYPE.Mono, (spec.linesSize or spec.size) * s, 1.45, spec.linesColor or spec.color)
	mono.barColor = body.barColor
	local direction = style(TYPE.MonoItalic, 14 * s, 1, C.InkSoft)
	local speaker = style(TYPE.SerifBold, 14 * s, 1, C.BronzeInk)
	direction.pitch, speaker.pitch = pitch, pitch
	if snap then
		heading.pitch, mono.pitch = pitch, pitch
	end
	local captionStyle = if spec.panel == "terminal"
		then style(TYPE.MonoItalic, 14 * s, 1.4, C.AmberDim)
		else style(TYPE.SerifItalic, 14 * s, 1.4, C.InkSoft)
	local gap = px(pitch * (spec.gap or 0.5))
	local function grid(h: number): number
		return if snap then math.ceil(h / pitch - 0.01) * pitch else h
	end

	local pages = {}
	local page: any
	local y = 0
	local deferred = {}
	local bodyCount = 0

	local function newPage()
		page = { kind = "doc", doc = doc, items = {}, bodyTop = 0, bodyEnd = H, docPage = #pages + 1, first = #pages == 0, last = false, head = doc.title }
		table.insert(pages, page)
		y = it
		bodyCount = 0
		local waiting = deferred
		deferred = {}
		for _, item in waiting do
			item.y = y
			table.insert(page.items, item)
			y += item.h
			bodyCount += 1
		end
	end
	local function room(): number
		return H - ib - y
	end
	local function put(item: any)
		item.y = y
		table.insert(page.items, item)
		y += item.h
		bodyCount += 1
	end
	-- One paragraph's lines. `prefix` (a speaker, a number, a memo field)
	-- sits on the first line's baseline in its own column.
	local function putLines(lines: { Line }, st: Style, x: number, align: string?, areaW: number, prefix: any?)
		for index, line in lines do
			local need = st.pitch * (if index == 1 then math.min(2, #lines) else 1)
			if room() < need and bodyCount > 0 then
				newPage()
			end
			local lx = x
			if align == "center" then
				lx = x + math.floor((areaW - line.width) / 2)
			elseif align == "right" then
				lx = x + areaW - line.width
			end
			local item = { kind = "line", x = lx, h = st.pitch, line = line, style = st }
			put(item)
			if index == 1 and prefix then
				prefix.y = item.y
				table.insert(page.items, prefix)
			end
		end
	end
	local function opener(lines: { Line }, st: Style)
		for _, line in lines do
			table.insert(page.items, { kind = "line", x = math.floor((W - line.width) / 2), y = y, h = st.pitch, line = line, style = st })
			y += st.pitch
		end
	end

	-- The opener
	newPage()
	y = 0
	local labelStyle = style(TYPE.UiBold, 14 * s, 1.7, C.BronzeInk)
	local titleStyle = style(TYPE.Display, 30 * s, 1.15, C.Ink)
	local metaStyle = style(TYPE.SerifItalic, 14 * s, 1.45, C.InkSoft)
	opener(setText(Theme.track(doc.label), labelStyle, W), labelStyle)
	opener(setText(doc.title, titleStyle, W), titleStyle)
	y += px(3 * s)
	if typeof(doc.meta) == "string" and doc.meta ~= "" then
		opener(setText(doc.meta, metaStyle, math.floor(W * 0.88), 0, true), metaStyle)
	end
	y += px(4 * s)
	table.insert(page.items, { kind = "ornament", x = 0, w = W, y = y, h = px(22 * s) })
	y += px(22 * s) + px(10 * s)
	page.bodyTop = y
	y += it

	-- Transcripts: speakers get a column as wide as the longest name
	local speakerCol = 0
	if spec.speakers then
		local widest = 0
		for _, block in doc.blocks do
			if typeof(block) == "string" then
				local name = string.match(block, "^([%u][%u%.' ]*%u%.?):%s")
				if name then
					widest = math.max(widest, measure(name, speaker.font, speaker.size))
				end
			end
		end
		if widest > 0 then
			speakerCol = math.clamp(math.ceil(widest) + px(16 * s), px(56 * s), math.floor(bodyW * 0.3))
		end
	end

	local afterHeading = true
	local inFields = false
	local function prefixItem(text: string, st: Style): any
		return { kind = "line", x = il, h = st.pitch, line = setText(text, st, 10000)[1], style = st }
	end

	local function paragraph(text: string)
		if spec.speakers then
			local name, rest = string.match(text, "^([%u][%u%.' ]*%u%.?):%s+(.+)$")
			local col = il + speakerCol
			if name and rest then
				putLines(setText(rest, body, bodyW - speakerCol), body, col, nil, bodyW, prefixItem(name, speaker))
			elseif string.sub(text, 1, 1) == "(" then
				putLines(setText(text, direction, bodyW - speakerCol), direction, col, nil, bodyW)
			else
				putLines(setText(text, body, bodyW - speakerCol), body, col, nil, bodyW)
			end
		elseif spec.body == TYPE.Type then
			-- Typewritten: memo fields in a column, numbered points hanging
			local field, value = string.match(text, "^(%u+):%s*(.*)$")
			if field and MEMO_FIELDS[field] then
				local col = math.ceil(measure("SUBJECT:", body.font, body.size)) + px(10 * s)
				putLines(setText(value :: string, body, bodyW - col), body, il + col, nil, bodyW, prefixItem(field .. ":", body))
				inFields = true
				return
			end
			if inFields then
				inFields = false
				y += px(pitch * 0.3)
				put({ kind = "rule", x = il, w = bodyW, h = px(pitch * 0.7) })
			end
			local number, rest = string.match(text, "^(%d+%.)%s+(.+)$")
			if number and rest then
				local col = math.ceil(measure("00.", body.font, body.size)) + px(8 * s)
				putLines(setText(rest, body, bodyW - col), body, il + col, nil, bodyW, prefixItem(number, body))
			else
				putLines(setText(text, body, bodyW), body, il, nil, bodyW)
			end
		else
			local indent = if spec.indent and not afterHeading then px(spec.indent * s) else 0
			putLines(setText(text, body, bodyW, indent), body, il, nil, bodyW)
		end
		y += gap
		afterHeading = false
	end

	local function headingBlock(text: string)
		local before = if bodyCount > 0 then (if snap then pitch else px(pitch * 0.7)) else 0
		local lines = setText(if spec.headingUpper then string.upper(text) else text, heading, bodyW)
		local after = if spec.headingRule then px(10 * s) else 0
		if room() < before + #lines * heading.pitch + after + body.pitch * 2 and bodyCount > 0 then
			newPage()
			before = 0
		end
		y += before
		putLines(lines, heading, il, nil, bodyW)
		if spec.headingRule then
			put({ kind = "rule", x = il, w = math.min(bodyW, px(140 * s)), h = after })
		end
		afterHeading = true
	end

	local function linesBlock(list: { string })
		for _, text in list do
			for _, line in setMono(text, mono, bodyW) do
				if room() < mono.pitch and bodyCount > 0 then
					newPage()
				end
				put({ kind = "line", x = il, h = mono.pitch, line = line, style = mono })
			end
		end
		y += gap
	end

	local function figureBlock(block: any)
		local figure = Archive.Figures[block.figure]
		if not figure then
			return
		end
		local bare = spec.panel == "slip"
		local fw = bodyW
		local ratio = if bare then 0.36 else (FIGURE_RATIO[figure.style] or 0.45)
		local capLines = if typeof(block.caption) == "string" then setText(block.caption, captionStyle, math.floor(fw * 0.9)) else {}
		local captionH = #capLines * captionStyle.pitch
		local maxH = H - it - ib - captionH - px(30 * s)
		local fh = math.max(60, math.min(px(fw * ratio), maxH, px(250 * s)))
		local top = px(6 * s)
		local h = grid(top + fh + px(10 * s) + captionH + px(12 * s))
		local item = { kind = "figure", x = il, w = fw, h = h, top = top, figH = fh, figure = block.figure, caption = capLines, captionStyle = captionStyle, bare = bare }
		if room() < h and bodyCount > 0 then
			table.insert(deferred, item)
			return
		end
		put(item)
	end

	local function signedBlock(text: string)
		local hand = doc.kind == "letter" or doc.kind == "note"
		local st = if hand then style(spec.body, spec.size * s * 1.15, spec.lead, spec.color) else body
		if snap then
			st = table.clone(st)
			st.pitch = pitch
		end
		y += if snap then pitch else px(pitch * 0.4)
		local lines = setText(text, st, bodyW)
		if hand or snap then
			putLines(lines, st, il, "right", bodyW)
		else
			local indent = math.floor(bodyW * 0.45)
			putLines(lines, st, il + indent, nil, bodyW - indent)
		end
	end

	for _, block in doc.blocks do
		if typeof(block) == "string" then
			paragraph(block)
		elseif typeof(block) == "table" then
			if block.heading then
				headingBlock(block.heading)
			elseif block.lines then
				linesBlock(block.lines)
			elseif block.figure then
				figureBlock(block)
			elseif block.signed then
				signedBlock(block.signed)
			end
		end
	end
	if #deferred > 0 then
		newPage()
	end
	if spec.panel == "terminal" then
		if room() >= mono.pitch then
			put({ kind = "cursor", x = il, h = body.pitch, style = body })
		end
	elseif spec.panel ~= "slip" and room() >= px(34 * s) then
		y += px(8 * s)
		put({ kind = "ornament", x = 0, w = W, h = px(24 * s) })
	end
	page.last = true
	page.bodyEnd = math.min(H, y + ib)
	return pages
end

-- The contents pages: chapters, then the recovered files
local function flowContents(book: any, geo: Geometry): { any }
	local s = geo.scale
	local H = geo.textH
	local row = CONFIG.Row
	local pages = {}
	local page: any
	local y = 0
	local function newPage(kind: string)
		page = { kind = kind, items = {}, head = if kind == "contents" then "Contents" else "Recovered Files" }
		table.insert(pages, page)
		y = 0
	end
	local function header(title: string, continued: boolean)
		local size = px((if continued then 14 else 20) * s)
		local h = px(size * 1.7)
		table.insert(page.items, { kind = "title", text = if continued then title .. ", continued" else title, size = size, y = y, h = h })
		y += h
		table.insert(page.items, { kind = "ornament", x = 0, w = geo.textW, y = y, h = px(22 * s) })
		y += px(30 * s)
	end
	newPage("contents")
	header("Contents", false)
	for index, doc in book.chapters do
		if y + row > H then
			newPage("contents")
			header("Contents", true)
		end
		table.insert(page.items, { kind = "entry", doc = doc, number = roman(index), y = y, h = row })
		y += row
	end
	newPage("files")
	header("Recovered Files", false)
	local progressH = px(46 * s)
	table.insert(page.items, { kind = "progress", y = y, h = progressH })
	y += progressH
	for index, id in Archive.FileOrder do
		if y + row > H then
			newPage("files")
			header("Recovered Files", true)
		end
		table.insert(page.items, { kind = "file", id = id, number = index, y = y, h = row })
		y += row
	end
	return pages
end

local function paginate(geo: Geometry, found: { [string]: boolean }): any
	local book = { geo = geo, pages = {}, docs = {}, chapters = {}, docById = {}, found = found, foundCount = 0 }
	for index, chapter in Archive.Chapters do
		local doc = {
			id = chapter.id, title = chapter.title, kind = chapter.kind, meta = chapter.meta, blocks = chapter.blocks or {},
			label = "Chapter " .. roman(index), isFile = false,
		}
		table.insert(book.docs, doc)
		table.insert(book.chapters, doc)
		book.docById[doc.id] = doc
	end
	for index, id in Archive.FileOrder do
		local file = Archive.Files[id]
		if file and found[id] then
			book.foundCount += 1
			local doc = {
				id = id, title = file.title, kind = file.kind, meta = file.meta, blocks = file.blocks or {},
				label = `Recovered file {index}`, isFile = true,
			}
			table.insert(book.docs, doc)
			book.docById[id] = doc
		end
	end
	local pages = book.pages
	if not geo.single then
		table.insert(pages, { kind = "endpaper", items = {} })
	end
	table.insert(pages, { kind = "title", items = {} })
	book.titleIndex = #pages
	for _, page in flowContents(book, geo) do
		table.insert(pages, page)
	end
	for _, doc in book.docs do
		doc.start = #pages + 1
		local flowed = flowDocument(doc, geo)
		doc.pageCount = #flowed
		for _, page in flowed do
			table.insert(pages, page)
		end
	end
	if not geo.single and #pages % 2 == 1 then
		table.insert(pages, { kind = "endpaper", items = {}, back = true })
	end
	-- Numbers count from the page after the title page
	book.lastNumber = 0
	for index, page in pages do
		if index > book.titleIndex and page.kind ~= "endpaper" then
			page.number = index - book.titleIndex
			book.lastNumber = page.number
		end
	end
	return book
end

-- Pages ---------------------------------------------------------------------------------------

local function drawLine(parent: Instance, line: Line, st: Style, x: number, y: number)
	for _, run in line.runs do
		make("TextLabel", {
			Name = "Text",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(px(x + run.x), y),
			Size = UDim2.fromOffset(math.ceil(run.w + math.max(10, run.w * 0.06)), st.pitch),
			FontFace = st.font.face,
			TextSize = st.size,
			TextColor3 = st.color,
			RichText = true,
			Text = run.rich,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = parent,
		})
	end
	for _, bar in line.bars do
		local h = math.max(4, px(st.size * st.font.bar))
		local frame = make("Frame", {
			Name = "Redaction",
			BackgroundColor3 = st.barColor or C.Redact,
			BackgroundTransparency = if st.barColor then 0.12 else 0,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(px(x + bar.x) - 1, y + px((st.pitch - h) / 2) + 1),
			Size = UDim2.fromOffset(math.max(6, px(bar.w) + 2), h),
			Parent = parent,
		})
		corner(frame, 1)
	end
end

-- A label laid out by hand (single line, measured, never wrapping)
local function label(parent: Instance, text: string, x: number, y: number, w: number, h: number, font: Typeface, size: number, color: Color3, align: Enum.TextXAlignment?, truncate: boolean?): TextLabel
	return make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(math.max(1, math.ceil(w)), h),
		FontFace = font.face,
		TextSize = size,
		TextColor3 = color,
		Text = text,
		TextWrapped = not truncate,
		TextTruncate = if truncate then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = parent,
	})
end

-- The Lantern star (two squares at 45 degrees) between two bronze hairlines
local function ornament(parent: Instance, cx: number, cy: number, color: Color3, s: number)
	local mark = make("Frame", {
		Name = "Ornament",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(px(7 * s), px(7 * s)),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	make("Frame", {
		Name = "Star",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = mark,
	})
	for _, side in { -1, 1 } do
		make("Frame", {
			Name = "Hairline",
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
			Position = UDim2.fromOffset(cx + side * px(11 * s), cy),
			Size = UDim2.fromOffset(px(46 * s), 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = parent,
		})
	end
	return mark
end

local function lockIcon(parent: Instance, cx: number, cy: number, size: number, color: Color3)
	local holder = make("Frame", {
		Name = "Lock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local shackle = make("Frame", {
		Name = "Shackle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.56, 0.66),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	round(shackle)
	make("UIStroke", { Color = color, Thickness = 1.6, Parent = shackle })
	local body = make("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.84, 0.56),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = holder,
	})
	corner(body, 2)
	make("Frame", {
		Name = "Keyhole",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, math.max(3, math.floor(size * 0.22))),
		BackgroundColor3 = C.Paper,
		BorderSizePixel = 0,
		Parent = body,
	})
end

-- A rubber stamp, a little crooked and worn
local function stamp(parent: Instance, lines: { string }, at: Vector2, rotation: number, s: number, rng: Random)
	local big = px((if #lines[1] > 12 then 14 else 18) * s)
	local small = px(14 * s)
	local width = math.ceil(math.max(measure(lines[1], TYPE.Sci, big), measure(lines[2] or "", TYPE.Type, small))) + px(28 * s)
	local height = big + small + px(22 * s)
	local frame = make("Frame", {
		Name = "Stamp",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(width, height),
		Rotation = rotation,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = parent,
	})
	make("UIStroke", { Color = C.Red, Thickness = 2.2, Transparency = 0.22, Parent = frame })
	corner(frame, 3)
	local inner = make("Frame", { Name = "Inner", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, ZIndex = 3, Parent = frame })
	make("UIStroke", { Color = C.Red, Thickness = 1, Transparency = 0.35, Parent = inner })
	local first = label(frame, lines[1], 0, px(9 * s), width, big + 4, TYPE.Sci, big, C.Red, Enum.TextXAlignment.Center)
	first.TextTransparency = 0.18
	first.ZIndex = 3
	if lines[2] then
		local second = label(frame, lines[2], 0, px(11 * s) + big, width, small + 4, TYPE.Type, small, C.Red, Enum.TextXAlignment.Center)
		second.TextTransparency = 0.25
		second.ZIndex = 3
	end
	-- worn ink: flecks of paper showing through
	for _ = 1, 16 do
		fill(frame, rng:NextInteger(2, width - 4), rng:NextInteger(2, height - 4), rng:NextInteger(1, 3), rng:NextInteger(1, 2), C.PaperWhite, rng:NextNumber(0.15, 0.5)).ZIndex = 4
	end
end

local function paperclip(parent: Instance, x: number, y: number, s: number)
	local clip = make("Frame", { Name = "Paperclip", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(px(15 * s), px(46 * s)), Rotation = -6, BackgroundTransparency = 1, ZIndex = 4, Parent = parent })
	round(clip)
	make("UIStroke", { Color = rgb(122, 126, 130), Thickness = 2, Transparency = 0.05, Parent = clip })
	local inner = make("Frame", { Name = "Inner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -px(5 * s)), Size = UDim2.fromOffset(px(8 * s), px(32 * s)), BackgroundTransparency = 1, ZIndex = 4, Parent = clip })
	round(inner)
	make("UIStroke", { Color = rgb(150, 154, 158), Thickness = 1.6, Transparency = 0.1, Parent = inner })
end

-- Builds one page. `side` is "left", "right" or "single" (spine on the left)
local function buildPage(book: any, index: number, side: string, state: any): Frame
	local model = book.pages[index]
	local geo: Geometry = book.geo
	local s = geo.scale
	local doc = model.doc
	local spec = if doc then (KINDS[doc.kind] or KINDS.journal) else nil
	local paper = if model.kind == "endpaper" then C.Endpaper elseif spec then spec.paper else C.Paper
	local W, H = geo.pageW, geo.pageH
	local rng = Random.new(index * 7919 + 13)
	local page = make("Frame", {
		Name = "Page" .. index,
		Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = paper,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	})
	-- Paper darkens a touch toward the spine
	local spineLeft = side ~= "left"
	local keys = if spineLeft
		then { CSK(0, shade(paper, 0.9)), CSK(0.07, shade(paper, 0.965)), CSK(0.3, paper), CSK(1, shade(paper, 0.985)) }
		else { CSK(0, shade(paper, 0.985)), CSK(0.7, paper), CSK(0.93, shade(paper, 0.965)), CSK(1, shade(paper, 0.9)) }
	make("UIGradient", { Color = ColorSequence.new(keys), Parent = page })
	local gutter = make("Frame", {
		Name = "Gutter",
		Position = UDim2.fromOffset(if spineLeft then 0 else W - 34, 0),
		Size = UDim2.fromOffset(34, H),
		BackgroundColor3 = C.Shadow,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = page,
	})
	make("UIGradient", {
		Rotation = if spineLeft then 0 else 180,
		Transparency = NumberSequence.new({ NSK(0, if side == "single" then 0.82 else 0.7), NSK(1, 1) }),
		Parent = gutter,
	})

	local cx = if side == "right" then geo.inner else geo.outer
	local content = make("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(cx, geo.top),
		Size = UDim2.fromOffset(geo.textW, geo.textH),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = page,
	})

	-- Running head and folio
	if model.number then
		local head = if side == "left" then "The Meridian Archive" else (model.head or "")
		label(page, string.upper(head), cx, px(geo.top * 0.24), geo.textW, px(20 * s), TYPE.Display, px(14 * s), C.InkFaded, Enum.TextXAlignment.Center, true)
		local folio = tostring(model.number)
		local align = if side == "left" then Enum.TextXAlignment.Left elseif side == "right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
		label(page, folio, cx, H - px(geo.bottom * 0.74), geo.textW, px(20 * s), TYPE.Serif, px(14 * s), C.InkSoft, align)
	end

	if model.kind == "endpaper" then
		-- a fine printed lattice, and a bookplate inside the front cover
		local step = 26
		for k = -math.ceil(H / step), math.ceil(W / step) do
			stroke(page, Vector2.new(k * step, 0), Vector2.new(k * step + H, H), 1, C.Bronze, 0.72)
			stroke(page, Vector2.new(k * step + H, 0), Vector2.new(k * step, H), 1, C.Bronze, 0.72)
		end
		if not model.back then
			local plateW, plateH = px(W * 0.62), px(H * 0.34)
			local plate = make("Frame", {
				Name = "Bookplate",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.46),
				Size = UDim2.fromOffset(plateW, plateH),
				BackgroundColor3 = C.PaperCream,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = page,
			})
			make("UIStroke", { Color = C.BronzeLight, Thickness = 1, Transparency = 0.2, Parent = plate })
			local inner = make("Frame", { Name = "Inner", Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), BackgroundTransparency = 1, ZIndex = 2, Parent = plate })
			make("UIStroke", { Color = C.InkSoft, Thickness = 1, Transparency = 0.55, Parent = inner })
			label(plate, Theme.track("Ex libris"), 0, px(plateH * 0.12), plateW, px(22 * s), TYPE.Display, px(16 * s), C.BronzeInk, Enum.TextXAlignment.Center).ZIndex = 2
			label(plate, "Meridian Station", 0, px(plateH * 0.3), plateW, px(34 * s), TYPE.SerifItalic, px(21 * s), C.Ink, Enum.TextXAlignment.Center).ZIndex = 2
			local note = label(plate, "The Lounge copy. Please leave it on the lectern.", px(18 * s), px(plateH * 0.54), plateW - px(36 * s), px(44 * s), TYPE.Serif, px(14 * s), C.InkSoft, Enum.TextXAlignment.Center)
			note.ZIndex = 2
			ornament(plate, plateW / 2, px(plateH * 0.86), C.Bronze, s * 0.8).ZIndex = 2
		end
		return page
	elseif model.kind == "title" then
		local W2 = geo.textW
		local y = px(10 * s)
		local titleStyle = style(TYPE.Display, 36 * s, 1.12, C.Ink)
		for _, line in setText(Theme.track(Archive.Title), titleStyle, W2) do
			drawLine(content, line, titleStyle, math.floor((W2 - line.width) / 2), y)
			y += titleStyle.pitch
		end
		ornament(content, W2 / 2, y + px(12 * s), C.Bronze, s)
		y += px(28 * s)
		local subStyle = style(TYPE.SerifItalic, 14 * s, 1.5, C.InkSoft)
		for _, line in setText(Archive.Subtitle, subStyle, math.floor(W2 * 0.78)) do
			drawLine(content, line, subStyle, math.floor((W2 - line.width) / 2), y)
			y += subStyle.pitch
		end
		y += px(16 * s)
		local footH = px(24 * s)
		local captionH = px(26 * s)
		local plateH = math.max(80, geo.textH - y - captionH - footH - px(10 * s))
		local plateW = math.min(px(W2 * 0.68), px(plateH * 1.05))
		buildFigure(content, "lantern", math.floor((W2 - plateW) / 2), y, plateW, plateH, state)
		y += plateH + px(6 * s)
		label(content, "Plate I. The Lantern.", 0, y, W2, captionH, TYPE.SerifItalic, px(14 * s), C.InkSoft, Enum.TextXAlignment.Center)
		label(content, Theme.track("Meridian Station, Kestrel Valley"), 0, geo.textH - footH, W2, footH, TYPE.Display, px(14 * s), C.BronzeInk, Enum.TextXAlignment.Center)
		return page
	end

	-- Paper and furniture by kind
	if spec then
		local panelTop, panelBottom = model.bodyTop, model.bodyEnd
		if spec.ruled then
			local pitch = px(px(spec.size * s) * spec.lead)
			local size = px(spec.size * s)
			local offset = math.floor((pitch - size) / 2 + size * 0.8) + 2
			local y = geo.top + panelTop + offset
			while y < H - px(geo.bottom * 0.75) do
				fill(page, 0, y, W, 1, C.Rule, 0.55).Name = "Rule"
				y += pitch
			end
			fill(page, cx - px(14 * s), 0, 1, H, C.Margin, 0.45).Name = "MarginLine"
		end
		if spec.crease then
			fill(page, 0, px(H * 0.36), W, 1, rgb(255, 255, 255), 0.55).Name = "Crease"
			fill(page, 0, px(H * 0.36) + 1, W, 1, C.Shadow, 0.9).Name = "Crease"
		end
		if spec.clip and model.first then
			paperclip(page, cx + px(10 * s), -px(14 * s), s)
			local tabW = math.ceil(measure(spec.tab, TYPE.Sci, px(14 * s))) + px(28 * s)
			local tab = fill(page, W - tabW - geo.outer, 0, tabW, px(28 * s), shade(C.Manila, 0.9), 0)
			tab.Name = "FolderTab"
			corner(tab, 2)
			label(tab, spec.tab, 0, px(4 * s), tabW, px(22 * s), TYPE.Sci, px(14 * s), C.InkSoft, Enum.TextXAlignment.Center)
		end
		if spec.stamp and model.first then
			stamp(content, spec.stamp, Vector2.new(geo.textW - px(4 * s), panelTop + px(4 * s)), -7, s, rng)
		end
		if spec.panel == "terminal" then
			local panel = make("Frame", {
				Name = "Terminal",
				Position = UDim2.fromOffset(-px(6 * s), panelTop),
				Size = UDim2.fromOffset(geo.textW + px(12 * s), math.max(40, panelBottom - panelTop)),
				BackgroundColor3 = C.Terminal,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 1,
				Parent = content,
			})
			corner(panel, 6)
			make("UIStroke", { Color = rgb(74, 66, 52), Thickness = 1, Transparency = 0.2, Parent = panel })
			gradient(panel, { shade(C.Terminal, 0.8), C.Terminal, shade(C.Terminal, 0.75) }, 90)
			scanlines(panel, math.max(40, panelBottom - panelTop), 3, 0.78)
			local headSize = px(14 * s)
			label(panel, "MS/WARDEN  " .. string.upper(doc.id) .. ".LOG", px(12 * s), px(8 * s), geo.textW * 0.72, px(20 * s), TYPE.Mono, headSize, C.AmberDim, Enum.TextXAlignment.Left, true)
			label(panel, `P.{model.docPage}`, geo.textW * 0.72, px(8 * s), geo.textW * 0.28, px(20 * s), TYPE.Mono, headSize, C.AmberDim, Enum.TextXAlignment.Right)
			if not model.last then
				label(panel, "-- MORE --", px(12 * s), math.max(40, panelBottom - panelTop) - px(26 * s), geo.textW, px(20 * s), TYPE.Mono, headSize, C.AmberDim, Enum.TextXAlignment.Left)
			end
		elseif spec.panel == "slip" then
			local slipH = math.max(60, panelBottom - panelTop)
			fill(content, 3, panelTop + 4, geo.textW, slipH, C.Shadow, 0.85).Name = "SlipShadow"
			local slip = fill(content, 0, panelTop, geo.textW, slipH, C.Slip, 0)
			slip.Name = "Slip"
			gradient(slip, { shade(C.Slip, 1.02), C.Slip, shade(C.Slip, 0.93) }, 90)
			for _, spec2 in { { 0.12, -8 }, { 0.88, 7 } } do
				make("Frame", {
					Name = "Tape",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(geo.textW * spec2[1], panelTop + 2),
					Size = UDim2.fromOffset(px(52 * s), px(15 * s)),
					Rotation = spec2[2],
					BackgroundColor3 = rgb(238, 230, 204),
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					ZIndex = 3,
					Parent = content,
				})
			end
		end
	end

	-- Items
	for _, item in model.items do
		local kind = item.kind
		if kind == "line" then
			drawLine(content, item.line, item.style, item.x, item.y)
		elseif kind == "ornament" then
			ornament(content, item.w / 2, item.y + item.h / 2, if spec and spec.panel == "terminal" then C.AmberDim else C.Bronze, s)
		elseif kind == "rule" then
			fill(content, item.x, item.y + math.floor(item.h / 2), item.w, 1, if spec then spec.color else C.Ink, 0.6).Name = "Rule"
		elseif kind == "cursor" then
			local cursor = fill(content, item.x, item.y + px(item.h * 0.2), px(item.style.size * 0.6), px(item.h * 0.62), C.Amber, 0.1)
			cursor.Name = "Cursor"
			table.insert(state.blinkers, cursor)
		elseif kind == "figure" then
			buildFigure(content, item.figure, item.x, item.y + item.top, item.w, item.figH, state, item.bare)
			local y = item.y + item.top + item.figH + px(10 * s)
			for _, line in item.caption do
				drawLine(content, line, item.captionStyle, item.x + math.floor((item.w - line.width) / 2), y)
				y += item.captionStyle.pitch
			end
		elseif kind == "title" then
			label(content, item.text, 0, item.y, geo.textW, item.h, TYPE.Display, item.size, C.Ink, Enum.TextXAlignment.Center, true)
		elseif kind == "entry" then
			state.contentsEntry(content, item)
		elseif kind == "file" then
			state.fileEntry(content, item)
		elseif kind == "progress" then
			state.progressRow(content, item)
		end
	end
	return page
end

-- The window -----------------------------------------------------------------------------------

local PAGE_ACTION = "SNArchivePages"
local PAGE_KEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }
-- By name: an EnumItem is only safe as a table key where the engine keeps one per value
local BACK_KEYS = { Q = true, Left = true, ButtonL1 = true }
local FORWARD_KEYS = { E = true, Right = true, ButtonR1 = true }

-- Set while the window exists, so tests (and other code) can reach it
local handleKey: ((Enum.KeyCode) -> ())? = nil
local current: any = nil

-- The Archive is its own object: the glass window chrome around it is hidden
local function hideChrome(body: Frame)
	local panel = body.Parent
	local window = panel and panel.Parent
	if not (panel and panel:IsA("Frame") and window) then
		return
	end
	for _, child in window:GetChildren() do
		if child:IsA("Frame") and string.sub(child.Name, 1, 6) == "Shadow" then
			child.Visible = false
		end
	end
	panel.BackgroundTransparency = 1
	for _, child in panel:GetChildren() do
		if child:IsA("UIStroke") or child:IsA("UIGradient") then
			child.Enabled = false
		elseif child:IsA("GuiObject") and child ~= body then
			child.Visible = false
		end
	end
	body.Position = UDim2.new()
	body.Size = UDim2.fromScale(1, 1)
	local padding = body:FindFirstChildOfClass("UIPadding")
	if padding then
		padding:Destroy()
	end
end

local function deviceKind(): string
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(last) == "EnumItem" then
		if string.find(last.Name, "Gamepad") then
			return "gamepad"
		elseif last == Enum.UserInputType.Touch then
			return "touch"
		end
	end
	return "keyboard"
end

local function build(body: Frame, _api)
	hideChrome(body)
	local window = (body.Parent :: Instance).Parent :: Frame
	local root = make("Frame", { Name = "Archive", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })

	local state: any = {
		book = nil,
		geo = nil,
		geoKey = "",
		foundKey = "",
		index = 1,
		frames = {},
		turnToken = 0,
		lastSize = nil,
		resumed = false,
		read = {},
		spinners = {},
		blinkers = {},
		position = { id = "", page = 0 },
		saved = { id = "", page = 0 },
		contentsDirty = false,
	}
	current = state
	local chrome: any = {}
	local controls: any = {}

	-- Reading progress ------------------------------------------------------------------------
	local pending: { { id: string, page: number } } = {}
	local sending = false
	local function queueRead(id: string, page: number)
		page = math.clamp(math.floor(page), 0, 99)
		for _, entry in pending do
			if entry.id == id then
				entry.page = page
				return
			end
		end
		table.insert(pending, { id = id, page = page })
		if sending then
			return
		end
		sending = true
		task.spawn(function()
			while #pending > 0 do
				local entry = table.remove(pending, 1) :: { id: string, page: number }
				ProgressRequest:FireServer(Protocol.ProgressAction.ReadLore, entry.id, entry.page)
				task.wait(CONFIG.ReadSpacing)
			end
			sending = false
		end)
	end

	local function readProfile(): ({ [string]: boolean }, string)
		local view = Profile.get()
		local lore = view and view.lore
		local found = {}
		local parts = {}
		if typeof(lore) == "table" then
			if typeof(lore.found) == "table" then
				for _, id in Archive.FileOrder do
					if lore.found[id] == true then
						found[id] = true
						table.insert(parts, id)
					end
				end
			end
			if typeof(lore.read) == "table" then
				for id, flag in lore.read do
					if flag == true and typeof(id) == "string" then
						state.read[id] = true
					end
				end
			end
		end
		return found, table.concat(parts, ",")
	end

	-- Contents rows ---------------------------------------------------------------------------
	local openDocument: (id: string, page: number?) -> ()

	local function displayNumber(doc: any): string
		local page = state.book.pages[doc.start]
		return if page and page.number then tostring(page.number) else ""
	end

	local function leaders(row: Instance, from: number, to: number, size: number, h: number)
		local width = to - from
		local dot = measure(". ", TYPE.Serif, size)
		if width < dot * 3 or dot <= 0 then
			return
		end
		local count = math.floor((width - 4) / dot)
		label(row, string.rep(". ", count), from, 0, width, h, TYPE.Serif, size, C.InkFaded, Enum.TextXAlignment.Right)
	end

	local function rowButton(content: Instance, name: string, item: any): TextButton
		return make("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, item.y),
			Size = UDim2.fromOffset(state.geo.textW, item.h),
			Selectable = true,
			SelectionImageObject = (function()
				local outline = make("Frame", { Name = "Focus", Position = UDim2.fromOffset(-4, 0), Size = UDim2.new(1, 8, 1, 0), BackgroundTransparency = 1 })
				make("UIStroke", { Color = C.Bronze, Thickness = 2, Parent = outline })
				return outline
			end)(),
			Parent = content,
		})
	end

	local function hover(row: TextButton, title: TextLabel)
		row.MouseEnter:Connect(function()
			title.TextColor3 = C.BronzeInk
			row.BackgroundTransparency = 0.96
		end)
		row.MouseLeave:Connect(function()
			title.TextColor3 = C.Ink
			row.BackgroundTransparency = 1
		end)
	end

	function state.contentsEntry(content: Instance, item: any)
		local s = state.geo.scale
		local W = state.geo.textW
		local doc = item.doc
		local numberW = px(36 * s)
		local titleSize, numberSize = px(16 * s), px(14 * s)
		local row = rowButton(content, "Entry_" .. doc.id, item)
		label(row, item.number, 0, 0, numberW - px(12 * s), item.h, TYPE.Serif, numberSize, C.InkSoft, Enum.TextXAlignment.Right)
		local folio = displayNumber(doc)
		local folioW = math.ceil(measure(folio, TYPE.Serif, titleSize)) + 4
		local titleW = math.min(math.ceil(measure(doc.title, TYPE.Serif, titleSize)) + 6, W - numberW - folioW - 24)
		local title = label(row, doc.title, numberW, 0, titleW, item.h, TYPE.Serif, titleSize, C.Ink, Enum.TextXAlignment.Left, true)
		leaders(row, numberW + titleW + 6, W - folioW - 6, titleSize, item.h)
		label(row, folio, W - folioW, 0, folioW, item.h, TYPE.Serif, titleSize, C.Ink, Enum.TextXAlignment.Right)
		hover(row, title)
		row.Activated:Connect(function()
			openDocument(doc.id, 0)
		end)
	end

	function state.fileEntry(content: Instance, item: any)
		local s = state.geo.scale
		local W = state.geo.textW
		local numberW = px(36 * s)
		local titleSize = px(16 * s)
		local file = Archive.Files[item.id]
		local doc = state.book.docById[item.id]
		if doc then
			local row = rowButton(content, "File_" .. item.id, item)
			label(row, tostring(item.number), 0, 0, numberW - px(12 * s), item.h, TYPE.Serif, px(14 * s), C.InkSoft, Enum.TextXAlignment.Right)
			local folio = displayNumber(doc)
			local folioW = math.ceil(measure(folio, TYPE.Serif, titleSize)) + 4
			local isNew = not state.read[item.id]
			local badgeW = if isNew then px(52 * s) else 0
			local titleW = math.min(math.ceil(measure(doc.title, TYPE.Serif, titleSize)) + 6, W - numberW - folioW - badgeW - 24)
			local title = label(row, doc.title, numberW, 0, titleW, item.h, TYPE.Serif, titleSize, C.Ink, Enum.TextXAlignment.Left, true)
			local x = numberW + titleW + 6
			if isNew then
				local badge = make("Frame", {
					Name = "NewBadge",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, x, 0.5, 0),
					Size = UDim2.fromOffset(badgeW - 8, px(22 * s)),
					Rotation = -4,
					BackgroundTransparency = 1,
					Parent = row,
				})
				make("UIStroke", { Color = C.Bronze, Thickness = 1.3, Transparency = 0.05, Parent = badge })
				corner(badge, 2)
				label(badge, "NEW", 0, 0, badgeW - 8, px(22 * s), TYPE.UiBold, px(14 * s), C.BronzeInk, Enum.TextXAlignment.Center)
				x += badgeW
			end
			leaders(row, x, W - folioW - 6, titleSize, item.h)
			label(row, folio, W - folioW, 0, folioW, item.h, TYPE.Serif, titleSize, C.Ink, Enum.TextXAlignment.Right)
			hover(row, title)
			row.Activated:Connect(function()
				openDocument(item.id, 0)
			end)
		else
			-- Not found yet: only the hint, faded, behind a small lock
			local row = make("Frame", { Name = "Locked_" .. item.id, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, item.y), Size = UDim2.fromOffset(W, item.h), Parent = content })
			lockIcon(row, numberW - px(19 * s), item.h / 2, px(15 * s), C.InkFaded)
			local hint = if file and typeof(file.hint) == "string" then file.hint else "Somewhere in the station."
			label(row, hint, numberW, 0, W - numberW, item.h, TYPE.SerifItalic, px(14 * s), C.InkFaded, Enum.TextXAlignment.Left, true)
		end
	end

	function state.progressRow(content: Instance, item: any)
		local s = state.geo.scale
		local W = state.geo.textW
		local total = #Archive.FileOrder
		local found = state.book.foundCount
		label(content, `{found} of {total} recovered`, 0, item.y, W, px(22 * s), TYPE.SerifItalic, px(14 * s), C.InkSoft, Enum.TextXAlignment.Center)
		local box = px(8 * s)
		local spacing = px(6 * s)
		local rowW = total * box + (total - 1) * spacing
		for index = 1, total do
			local square = fill(content, math.floor((W - rowW) / 2) + (index - 1) * (box + spacing), item.y + px(28 * s), box, box, C.Bronze, if index <= found then 0.05 else 1)
			square.Name = "Progress"
			square.Rotation = 45
			make("UIStroke", { Color = C.Bronze, Thickness = 1, Transparency = 0.2, Parent = square })
		end
	end

	-- Page frames -----------------------------------------------------------------------------
	local function frameFor(index: number): Frame?
		local book = state.book
		if not book or index < 1 or index > #book.pages then
			return nil
		end
		local frame = state.frames[index]
		if not frame then
			local side = if state.geo.single then "single" elseif index % 2 == 1 then "left" else "right"
			frame = buildPage(book, index, side, state)
			state.frames[index] = frame
		end
		return frame
	end

	local function dropLeaves()
		if not chrome.leaves then
			return
		end
		for _, frame in state.frames do
			if frame.Parent and frame.Parent.Parent == chrome.leaves then
				frame.Parent = nil
			end
		end
		chrome.leaves:ClearAllChildren()
	end

	local function mountPage(frame: Frame?, slot: Frame?)
		if frame and slot then
			frame.AnchorPoint = Vector2.zero
			frame.Position = UDim2.new()
			frame.Parent = slot
		end
	end

	local function clearFrames()
		dropLeaves()
		for _, frame in state.frames do
			frame:Destroy()
		end
		state.frames = {}
		state.spinners = {}
		state.blinkers = {}
	end

	local function visibleIndices(): { number }
		if state.geo.single then
			return { state.index }
		end
		return { state.index, state.index + 1 }
	end

	local function refreshControls()
		if not controls.prev or not state.book then
			return
		end
		local book = state.book
		local numbers = {}
		for _, index in visibleIndices() do
			local page = book.pages[index]
			if page and page.number then
				table.insert(numbers, page.number)
			end
		end
		controls.indicator.Text = if #numbers == 2
			then `Pages {numbers[1]}-{numbers[2]} of {book.lastNumber}`
			elseif #numbers == 1 then `Page {numbers[1]} of {book.lastNumber}`
			else "Title page"
		local step = if state.geo.single then 1 else 2
		controls.setEnabled(controls.prev, state.index > 1)
		controls.setEnabled(controls.next, state.index + step <= #book.pages)
	end

	local function noteShown()
		local book = state.book
		local shown = nil
		for _, index in visibleIndices() do
			local page = book.pages[index]
			if page and page.doc then
				if not state.read[page.doc.id] then
					state.read[page.doc.id] = true
					queueRead(page.doc.id, page.docPage - 1)
					state.contentsDirty = true
				end
				shown = shown or { id = page.doc.id, page = page.docPage - 1 }
			end
		end
		state.position = shown or { id = "", page = 0 }
		-- "new" marks on the contents pages are out of date: rebuild them
		if state.contentsDirty then
			state.contentsDirty = false
			for index, frame in state.frames do
				local page = book.pages[index]
				if page and page.kind == "files" then
					local parent = frame.Parent
					frame:Destroy()
					state.frames[index] = nil
					if parent and parent ~= chrome.leaves then
						mountPage(frameFor(index), parent :: Frame)
					end
				end
			end
		end
	end

	local function trimCache()
		for index, frame in state.frames do
			if math.abs(index - state.index) > CONFIG.PageCache then
				frame:Destroy()
				state.frames[index] = nil
			end
		end
	end

	-- Puts the current page(s) in place at once
	local function render()
		state.turnToken += 1
		dropLeaves()
		for _, frame in state.frames do
			frame.Parent = nil
		end
		if not state.book or not chrome.slots then
			return
		end
		mountPage(frameFor(state.index), chrome.slots[1])
		if not state.geo.single then
			mountPage(frameFor(state.index + 1), chrome.slots[2])
		end
		trimCache()
		refreshControls()
		noteShown()
	end

	local function normalize(index: number): number
		local book = state.book
		index = math.clamp(index, 1, math.max(1, #book.pages))
		if not state.geo.single and index % 2 == 0 then
			index -= 1
		end
		return index
	end

	local function flash()
		if not chrome.area then
			return
		end
		local cover = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Paper, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4, Parent = chrome.area })
		tween(cover, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		task.delay(0.25, function()
			cover:Destroy()
		end)
	end

	local function goTo(index: number, quiet: boolean?)
		state.index = normalize(index)
		render()
		if not quiet then
			flash()
		end
	end

	openDocument = function(id: string, page: number?)
		local doc = state.book and state.book.docById[id]
		if not doc then
			return
		end
		goTo(doc.start + math.clamp(math.floor(page or 0), 0, math.max(0, doc.pageCount - 1)))
	end

	-- Page turns: the old leaf folds in toward the spine, then the new one opens out
	local function turn(direction: number)
		local book = state.book
		if not book or not chrome.slots then
			return
		end
		local geo = state.geo
		local step = if geo.single then 1 else 2
		local fromIndex = state.index
		local toIndex = fromIndex + direction * step
		if toIndex < 1 or toIndex > #book.pages then
			return
		end
		-- Anything still moving lands first
		render()
		state.index = toIndex
		local token = state.turnToken + 1
		state.turnToken = token
		local fold = TweenInfo.new(CONFIG.TurnTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local land = TweenInfo.new(CONFIG.TurnTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		Vfx.sound("PageTurn", SoundService)

		local function leaf(anchorRight: boolean, x: number, width: number, page: Frame, shadeFrom: number): (Frame, Frame)
			local container = make("Frame", {
				Name = "Leaf",
				AnchorPoint = Vector2.new(if anchorRight then 1 else 0, 0),
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.fromOffset(width, geo.pageH),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Parent = chrome.leaves,
			})
			page.AnchorPoint = Vector2.new(if anchorRight then 1 else 0, 0)
			page.Position = UDim2.fromScale(if anchorRight then 1 else 0, 0)
			page.Parent = container
			local shadow = make("Frame", {
				Name = "Shade",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.Shadow,
				BackgroundTransparency = shadeFrom,
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = container,
			})
			return container, shadow
		end
		local function finish()
			task.delay(CONFIG.TurnTime, function()
				if state.turnToken == token then
					render()
				end
			end)
		end

		local slots = chrome.slots
		local W = geo.pageW
		if geo.single then
			if direction > 0 then
				local old, new = frameFor(fromIndex), frameFor(toIndex)
				mountPage(new, slots[1])
				if old then
					local container, shadow = leaf(false, 0, W, old, 1)
					tween(container, fold, { Size = UDim2.fromOffset(0, geo.pageH) })
					tween(shadow, fold, { BackgroundTransparency = 0.55 })
				end
			else
				local new = frameFor(toIndex)
				if new then
					local container, shadow = leaf(false, 0, 0, new, 0.55)
					tween(container, land, { Size = UDim2.fromOffset(W, geo.pageH) })
					tween(shadow, land, { BackgroundTransparency = 1 })
				end
			end
			finish()
			return
		end

		-- Spreads: two halves
		local outgoing = if direction > 0 then frameFor(fromIndex + 1) else frameFor(fromIndex)
		local under = if direction > 0 then frameFor(toIndex + 1) else frameFor(toIndex)
		local incoming = if direction > 0 then frameFor(toIndex) else frameFor(toIndex + 1)
		mountPage(under, if direction > 0 then slots[2] else slots[1])
		if outgoing then
			local container, shadow = leaf(direction < 0, W, W, outgoing, 1)
			tween(container, fold, { Size = UDim2.fromOffset(0, geo.pageH) })
			tween(shadow, fold, { BackgroundTransparency = 0.55 })
		end
		task.delay(CONFIG.TurnTime, function()
			if state.turnToken ~= token then
				return
			end
			dropLeaves()
			if incoming then
				local container, shadow = leaf(direction > 0, W, 0, incoming, 0.55)
				tween(container, land, { Size = UDim2.fromOffset(W, geo.pageH) })
				tween(shadow, land, { BackgroundTransparency = 1 })
			end
			finish()
		end)
	end

	-- Controls --------------------------------------------------------------------------------
	-- Interface pieces follow the Sanctum panels: graphite plates with a bronze
	-- hairline, square corners, Builder Sans labels and bronze key caps.
	local function selectionOutline(): Frame
		local outline = make("Frame", {
			Name = "Focus",
			Position = UDim2.fromOffset(-3, -3),
			Size = UDim2.new(1, 6, 1, 6),
			BackgroundTransparency = 1,
		})
		make("UIStroke", { Color = C.Ivory, Thickness = 2, Parent = outline })
		return outline
	end

	local function keycap(parent: Instance, order: number): (Frame, TextLabel)
		local cap = make("Frame", {
			Name = "Keycap",
			LayoutOrder = order,
			Size = UDim2.fromOffset(32, 24),
			BackgroundColor3 = C.Graphite,
			BorderSizePixel = 0,
			Parent = parent,
		})
		corner(cap, 2)
		make("UIStroke", { Color = C.Bronze, Thickness = 1, Transparency = 0.2, Parent = cap })
		local text = make("TextLabel", {
			Name = "Key",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			FontFace = TYPE.UiBold.face,
			TextSize = 14,
			TextColor3 = C.Accent,
			Text = "",
			TextWrapped = true,
			Parent = cap,
		})
		return cap, text
	end

	local function chevron(parent: Instance, order: number, pointsLeft: boolean)
		local holder = make("Frame", { Name = "Chevron", LayoutOrder = order, Size = UDim2.fromOffset(10, 16), BackgroundTransparency = 1, Parent = parent })
		local tipX = if pointsLeft then 2 else 8
		local backX = if pointsLeft then 8 else 2
		stroke(holder, Vector2.new(backX, 2), Vector2.new(tipX, 8), 2, C.Ivory, 0.05)
		stroke(holder, Vector2.new(tipX, 8), Vector2.new(backX, 14), 2, C.Ivory, 0.05)
	end

	local quick = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local function barButton(parent: Instance, name: string, text: string, side: string?, onPress: () -> ()): (TextButton, TextLabel?)
		local caption = string.upper(text)
		local textW = math.ceil(measure(caption, TYPE.UiBold, 16)) + 6
		local width = 32 + textW + (if side == "key" then 10 + 32 elseif side then 10 + 10 + 32 + 10 else 0)
		local button = make("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.Graphite,
			BackgroundTransparency = 0.06,
			Size = UDim2.fromOffset(width, CONFIG.ControlsHeight),
			Selectable = true,
			SelectionImageObject = selectionOutline(),
			Parent = parent,
		})
		corner(button, 2)
		local hairline = make("UIStroke", { Color = C.Bronze, Thickness = 1, Transparency = 0.55, Parent = button })
		local scale = make("UIScale", { Parent = button })
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
			Parent = button,
		})
		local key: TextLabel? = nil
		if side == "left" then
			chevron(button, 1, true)
			local _, k = keycap(button, 2)
			key = k
		end
		make("TextLabel", {
			Name = "Text",
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(textW, 22),
			FontFace = TYPE.UiBold.face,
			TextSize = 16,
			TextColor3 = C.Ivory,
			Text = caption,
			TextWrapped = true,
			Parent = button,
		})
		if side == "right" or side == "key" then
			local _, k = keycap(button, 4)
			key = k
		end
		if side == "right" then
			chevron(button, 5, false)
		end
		button.MouseEnter:Connect(function()
			if button.Active then
				tween(hairline, quick, { Transparency = 0.15 })
				tween(button, quick, { BackgroundColor3 = shade(C.Graphite, 1.35) })
			end
		end)
		button.MouseLeave:Connect(function()
			tween(hairline, quick, { Transparency = 0.55 })
			tween(button, quick, { BackgroundColor3 = C.Graphite })
		end)
		button.Activated:Connect(function()
			if button.Active then
				scale.Scale = 0.98
				tween(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 })
				onPress()
			end
		end)
		return button, key
	end

	-- Disabled controls fade to 45% and stop answering
	function controls.setEnabled(button: TextButton, enabled: boolean)
		button.Active = enabled
		for _, item in button:GetDescendants() do
			if item:IsA("TextLabel") then
				item.TextTransparency = if enabled then 0 else 0.55
			elseif item:IsA("Frame") and item.Name == "Stroke" then
				item.BackgroundTransparency = if enabled then 0.05 else 0.6
			end
		end
		button.BackgroundTransparency = if enabled then 0.06 else 0.45
	end

	local function refreshKeys()
		if not controls.prevKey then
			return
		end
		local kind = deviceKind()
		local prevText, nextText, closeText = "Q", "E", "Esc"
		if kind == "gamepad" then
			prevText, nextText, closeText = "LB", "RB", "B"
		end
		controls.prevKey.Text = prevText
		controls.nextKey.Text = nextText
		controls.closeKey.Text = closeText
		for _, key in { controls.prevKey, controls.nextKey, controls.closeKey } do
			(key.Parent :: Frame).Visible = kind ~= "touch"
		end
	end

	-- The cover, pages, ribbon and controls for the current geometry
	local function buildChrome()
		root:ClearAllChildren()
		chrome = {}
		controls.prev = nil
		local geo: Geometry = state.geo
		local H = window.Size.Y.Offset
		local cover = geo.cover
		local total = geo.bookH + CONFIG.ControlsGap + CONFIG.ControlsHeight
		local top = math.max(0, math.floor((H - total) / 2))
		local book = make("Frame", {
			Name = "Book",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, top),
			Size = UDim2.fromOffset(geo.bookW, geo.bookH),
			BackgroundTransparency = 1,
			Parent = root,
		})
		chrome.book = book
		for index, spec in { { 34, 14, 0.88 }, { 18, 8, 0.8 }, { 6, 3, 0.62 } } do
			local shadow = make("Frame", {
				Name = "Shadow" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, spec[2]),
				Size = UDim2.new(1, spec[1], 1, spec[1]),
				BackgroundColor3 = C.Shadow,
				BackgroundTransparency = spec[3],
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = book,
			})
			corner(shadow, 12 + spec[1] // 2)
		end
		-- Leather, with a blind-tooled gilt line just inside the edge
		local leather = make("Frame", { Name = "Cover", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Leather, BorderSizePixel = 0, ZIndex = 2, Parent = book })
		corner(leather, 10)
		make("UIStroke", { Color = C.LeatherDark, Thickness = 1.5, Transparency = 0.1, Parent = leather })
		gradient(leather, { shade(C.Leather, 1.12), C.Leather, shade(C.Leather, 0.8) }, 90)
		local tooling = make("Frame", { Name = "Tooling", Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1, ZIndex = 2, Parent = leather })
		corner(tooling, 7)
		make("UIStroke", { Color = C.Bronze, Thickness = 1, Transparency = 0.55, Parent = tooling })
		-- bronze corner pieces, as on a bound codex
		for _, spot in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
			local piece = make("Frame", {
				Name = "CornerPiece",
				AnchorPoint = Vector2.new(spot[1], spot[2]),
				Position = UDim2.fromScale(spot[1], spot[2]),
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = C.Bronze,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = leather,
			})
			corner(piece, 3)
			gradient(piece, { C.BronzeLight, C.Bronze, shade(C.Bronze, 0.75) }, 45)
		end
		-- The page block's edges peeking out around the open pages
		local pagesW = if geo.single then geo.pageW else geo.pageW * 2
		for step = 2, 1, -1 do
			local x = if geo.single then cover else cover - step * 2
			local edge = make("Frame", {
				Name = "Edge" .. step,
				Position = UDim2.fromOffset(x, cover + step),
				Size = UDim2.fromOffset(pagesW + step * (if geo.single then 2 else 4), geo.pageH + step),
				BackgroundColor3 = shade(C.Edge, 1 - step * 0.05),
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = book,
			})
			corner(edge, 2)
		end
		local area = make("Frame", {
			Name = "Pages",
			Position = UDim2.fromOffset(cover, cover),
			Size = UDim2.fromOffset(pagesW, geo.pageH),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = book,
		})
		chrome.area = area
		chrome.slots = {}
		for slot = 1, (if geo.single then 1 else 2) do
			chrome.slots[slot] = make("Frame", {
				Name = "Slot" .. slot,
				Position = UDim2.fromOffset((slot - 1) * geo.pageW, 0),
				Size = UDim2.fromOffset(geo.pageW, geo.pageH),
				BackgroundColor3 = C.Paper,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 1,
				Parent = area,
			})
		end
		chrome.leaves = make("Frame", { Name = "Turning", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = area })
		if not geo.single then
			fill(area, geo.pageW - 1, 0, 2, geo.pageH, C.Shadow, 0.55).ZIndex = 3
			for _, y in { -5, geo.pageH } do
				local band = make("Frame", {
					Name = "Headband",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromOffset(geo.pageW, y),
					Size = UDim2.fromOffset(18, 5),
					BackgroundColor3 = C.Ribbon,
					BorderSizePixel = 0,
					ZIndex = 3,
					Parent = area,
				})
				corner(band, 2)
				fill(band, 0, 2, 18, 1, C.PaperCream, 0.3)
			end
		end
		-- The ribbon lies down the page margin and hangs out below the book
		local ribbonX = cover + (if geo.single then geo.pageW - 28 else geo.pageW + 24)
		local ribbon = make("Frame", {
			Name = "Ribbon",
			Position = UDim2.fromOffset(ribbonX, cover - 4),
			Size = UDim2.fromOffset(9, geo.pageH + 4 + 16),
			BackgroundColor3 = C.Ribbon,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = book,
		})
		gradient(ribbon, { shade(C.Ribbon, 0.82), shade(C.Ribbon, 1.15), shade(C.Ribbon, 0.82) }, 0)
		for _, sideSign in { -1, 1 } do
			make("Frame", {
				Name = "Tail",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, sideSign * 2, 1, -3),
				Size = UDim2.fromOffset(5, 9),
				Rotation = -sideSign * 14,
				BackgroundColor3 = shade(C.Ribbon, 0.92),
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = ribbon,
			})
		end
		-- Tap or click a page edge to turn
		for _, spec in { { "TurnBack", cover - 4, -1 }, { "TurnForward", geo.bookW - cover - 32, 1 } } do
			local zone = make("TextButton", {
				Name = spec[1],
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Selectable = false,
				Position = UDim2.fromOffset(spec[2], cover),
				Size = UDim2.fromOffset(36, geo.pageH),
				ZIndex = 7,
				Parent = book,
			})
			zone.Activated:Connect(function()
				turn(spec[3])
			end)
		end
		-- Swipe on touch screens
		local swipeStart: Vector2? = nil
		area.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				swipeStart = Vector2.new(input.Position.X, input.Position.Y)
			end
		end)
		area.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch or not swipeStart then
				return
			end
			local delta = Vector2.new(input.Position.X, input.Position.Y) - swipeStart
			swipeStart = nil
			if math.abs(delta.X) >= CONFIG.SwipeDistance and math.abs(delta.X) > math.abs(delta.Y) then
				turn(if delta.X < 0 then 1 else -1)
			end
		end)

		-- Controls under the book
		local bar = make("Frame", {
			Name = "Controls",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, top + geo.bookH + CONFIG.ControlsGap),
			Size = UDim2.fromOffset(geo.bookW, CONFIG.ControlsHeight),
			BackgroundTransparency = 1,
			Parent = root,
		})
		local prev, prevKey = barButton(bar, "Previous", "Previous", "left", function()
			turn(-1)
		end)
		prev.Position = UDim2.fromOffset(0, 0)
		local nextButton, nextKey = barButton(bar, "Next", "Next", "right", function()
			turn(1)
		end)
		nextButton.AnchorPoint = Vector2.new(1, 0)
		nextButton.Position = UDim2.fromScale(1, 0)
		local middle = make("Frame", {
			Name = "Middle",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(1, -(prev.Size.X.Offset + nextButton.Size.X.Offset + 16), 1, 0),
			BackgroundTransparency = 1,
			Parent = bar,
		})
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
			Parent = middle,
		})
		local contents = barButton(middle, "Contents", "Contents", nil, function()
			goTo(state.book.titleIndex + 1)
		end)
		contents.LayoutOrder = 1
		local indicator = make("TextLabel", {
			Name = "Indicator",
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(170, 22),
			FontFace = TYPE.Ui.face,
			TextSize = 14,
			TextColor3 = C.IvorySoft,
			Text = "",
			TextTruncate = Enum.TextTruncate.AtEnd,
			-- phones show the folio on the page itself; the bar keeps its room for buttons
			Visible = not geo.single,
			Parent = middle,
		})
		local close, closeKey = barButton(middle, "Close", "Close", "key", function()
			Shell.close()
		end)
		close.LayoutOrder = 3
		controls.prev, controls.prevKey = prev, prevKey
		controls.next, controls.nextKey = nextButton, nextKey
		controls.contents = contents
		controls.indicator = indicator
		controls.close, controls.closeKey = close, closeKey
		refreshKeys()
	end

	-- Fits the book to the window and repaginates when the size or the
	-- recovered files change, keeping the reader on the same page of the same
	-- document
	local function layout(force: boolean?)
		local size = Vector2.new(window.Size.X.Offset, window.Size.Y.Offset)
		state.lastSize = window.Size
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local compact = viewport.X < 900 or viewport.Y < 500
		local geo = geometryFor(size, compact)
		local found, foundKey = readProfile()
		local geoKey = `{geo.pageW}x{geo.pageH}:{geo.single}:{size.Y}`
		if not force and state.book and geoKey == state.geoKey and foundKey == state.foundKey then
			return
		end
		local keep = state.position
		local changedShape = geoKey ~= state.geoKey or not chrome.slots
		state.geo = geo
		state.geoKey = geoKey
		state.foundKey = foundKey
		clearFrames()
		state.book = paginate(geo, found)
		if changedShape then
			buildChrome()
		end
		local doc = keep and keep.id ~= "" and state.book.docById[keep.id]
		if doc then
			state.index = normalize(doc.start + math.clamp(keep.page, 0, doc.pageCount - 1))
		else
			state.index = normalize(state.index)
		end
		render()
	end

	handleKey = function(keyCode: Enum.KeyCode)
		if not Shell.isOpen("Archive") then
			return
		end
		local name = if typeof(keyCode) == "EnumItem" then keyCode.Name else ""
		if BACK_KEYS[name] then
			turn(-1)
		elseif FORWARD_KEYS[name] then
			turn(1)
		end
	end

	-- A new recovered file (or a read mark from another device) shows at once
	Profile.changed:Connect(function()
		if state.book then
			layout()
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(refreshKeys)

	local function setBlur(on: boolean)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local blur = camera:FindFirstChild("SNArchiveBlur") :: BlurEffect?
		if on then
			if not blur then
				blur = make("BlurEffect", { Name = "SNArchiveBlur", Size = 0, Parent = camera })
			end
			tween(blur :: BlurEffect, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = CONFIG.BlurSize })
		elseif blur then
			local fading = blur
			tween(fading, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = 0 })
			task.delay(0.25, function()
				if not Shell.isOpen("Archive") then
					fading:Destroy()
				end
			end)
		end
	end

	local elapsed = 0
	return {
		onOpen = function(args: any?)
			layout()
			if typeof(args) == "table" and typeof(args.doc) == "string" then
				openDocument(args.doc, if typeof(args.page) == "number" then args.page else 0)
			elseif not state.resumed then
				-- First time this session: pick up where the player left off
				state.resumed = true
				local view = Profile.get()
				local lore = view and view.lore
				if typeof(lore) == "table" and typeof(lore.last) == "string" and lore.last ~= "" then
					state.saved = { id = lore.last, page = if typeof(lore.page) == "number" then lore.page else 0 }
					openDocument(lore.last, state.saved.page)
				end
			end
			ContextActionService:BindActionAtPriority(PAGE_ACTION, function(_, inputState, input)
				if inputState == Enum.UserInputState.Begin then
					handleKey(input.KeyCode)
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, table.unpack(PAGE_KEYS))
			refreshKeys()
			setBlur(true)
		end,
		onClose = function()
			ContextActionService:UnbindAction(PAGE_ACTION)
			setBlur(false)
			local position = state.position
			if position.id ~= "" and (position.id ~= state.saved.id or position.page ~= state.saved.page) then
				state.saved = { id = position.id, page = position.page }
				queueRead(position.id, position.page)
			end
		end,
		update = function(dt: number)
			if window.Size ~= state.lastSize then
				layout()
			end
			elapsed += dt
			for index = #state.spinners, 1, -1 do
				local spinner = state.spinners[index]
				if spinner.holder.Parent == nil and not spinner.holder:IsDescendantOf(game) then
					-- its page is parked; keep it for when the page comes back
				elseif spinner.holder:IsDescendantOf(root) then
					spinner.angle += dt * CONFIG.SpinSpeed
					spinner.model:PivotTo(spinner.tilt * CFrame.Angles(0, spinner.angle, 0))
				end
			end
			local on = elapsed % 1.1 < 0.6
			for _, cursor in state.blinkers do
				cursor.Visible = on
			end
		end,
		focus = function()
			return controls.next
		end,
	}
end

function ArchiveWindow.register()
	Shell.registerWindow("Archive", {
		title = "The Meridian Archive",
		label = "ARCHIVE",
		icon = "A",
		order = 90,
		-- Opened from the lectern in the Lounge, not the dock
		nav = false,
		size = CONFIG.WindowSize,
		accent = C.Accent,
		build = build,
	})
end

-- Tunables, readable (and adjustable in tests)
ArchiveWindow.Config = CONFIG

-- Turns pages as if the key were pressed (tests and other input paths)
function ArchiveWindow.press(keyCode: Enum.KeyCode)
	if handleKey then
		handleKey(keyCode)
	end
end

-- The open book's state, for tests: { book, index, geo, frames, read }
function ArchiveWindow.debugState(): any
	return current
end

-- Exposed for tests: how a piece of marked-up text is set
ArchiveWindow.setText = function(text: string, width: number): { Line }
	return setText(text, style(TYPE.Serif, 16, 1.5, C.Ink), width)
end

-- Exposed for tests and previews: draws one figure into `parent`
function ArchiveWindow.buildFigure(parent: Instance, id: string, w: number, h: number): Frame
	return buildFigure(parent, id, 0, 0, w, h, { spinners = {} }, false)
end

return ArchiveWindow
