"""Fonts and text layout shared by the offline preview renderers (render3d.py for
SurfaceGui / BillboardGui text, tools/uipreview/render.py for screen UI).

The game's fonts are Roblox's own, which cannot be used offline, so open stand-ins from
tools/fonts are used: Montserrat for Builder Sans and Gotham (at the matching weight),
Michroma, and Roboto Mono. Anything else falls back to Montserrat Regular. Widths are
close, not exact: Builder Sans is a little narrower than Montserrat, so Builder Sans text
is drawn with a 0.94 advance factor.
"""
import os

from PIL import Image, ImageDraw, ImageFont

FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fonts")
WEIGHTS = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500,
           "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Heavy": 900}
LINE_HEIGHT = 1.0  # Roblox lays a line out at TextSize x LineHeight (TextBounds.Y == TextSize for one line)

_cache = {}


def family_key(family):
    """Maps a Roblox font family string to (stand-in name, advance factor)."""
    f = (family or "").lower()
    if "michroma" in f:
        return "Michroma", 1.0
    if "robotomono" in f or "code" in f:
        return "RobotoMono", 1.0
    if "builder" in f:
        return "Montserrat", 0.94
    return "Montserrat", 1.0


def _path(name, style):
    if name == "Michroma":
        return os.path.join(FONT_DIR, "Michroma-Regular.ttf")
    if name == "RobotoMono":
        return os.path.join(FONT_DIR, "RobotoMono[wght].ttf")
    if style == "Italic":
        return os.path.join(FONT_DIR, "Montserrat-Italic[wght].ttf")
    return os.path.join(FONT_DIR, "Montserrat[wght].ttf")


class Face:
    """One font at one size: width measuring and drawing with the stand-in font."""

    def __init__(self, family, weight, style, size):
        name, self.track = family_key(family)
        self.size = max(1.0, float(size))
        w = WEIGHTS.get(weight, 400) if isinstance(weight, str) else int(weight or 400)
        key = (name, style == "Italic", w, round(self.size * 2) / 2)
        if key not in _cache:
            font = ImageFont.truetype(_path(name, style), key[3])
            if name == "Montserrat":
                font.set_variation_by_axes([w])
            elif name == "RobotoMono":
                font.set_variation_by_axes([min(700, max(100, w))])
            _cache[key] = font
        self.font = _cache[key]
        self.asc, self.desc = self.font.getmetrics()

    def width(self, text):
        if not text:
            return 0.0
        return self.font.getlength(text) * self.track

    @property
    def line_height(self):
        return self.size * LINE_HEIGHT

    def draw(self, draw, x, line_top, text, fill, stroke=0, stroke_fill=None):
        """Draws one line with its line box starting at line_top (x is the left edge)."""
        base = line_top + (self.line_height - (self.asc + self.desc)) / 2 + self.asc
        kw = {}
        if stroke > 0:
            kw = {"stroke_width": stroke, "stroke_fill": stroke_fill}
        if self.track == 1.0:
            draw.text((x, base), text, font=self.font, fill=fill, anchor="ls", **kw)
        else:
            cursor = x
            for ch in text:
                draw.text((cursor, base), ch, font=self.font, fill=fill, anchor="ls", **kw)
                cursor += self.font.getlength(ch) * self.track


def wrap(text, face, width):
    """Greedy word wrap like TextWrapped; explicit newlines are kept."""
    lines = []
    for para in text.split("\n"):
        line = ""
        for word in para.split(" "):
            trial = (line + " " + word) if line else word
            if face.width(trial) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def layout_text(text, family, weight, style, size, width, wrap_on, line_height=1.0):
    """Returns (face, lines, block width, block height) at a given size."""
    face = Face(family, weight, style, size)
    lines = wrap(text, face, width) if wrap_on else text.split("\n")
    bw = max((face.width(l) for l in lines), default=0)
    bh = len(lines) * face.line_height * (line_height if line_height else 1.0)
    return face, lines, bw, bh


def scaled_size(text, family, weight, style, width, height, wrap_on, lo=1, hi=100, line_height=1.0):
    """TextScaled: the largest integer size in [lo, hi] whose block fits width x height."""
    lo, hi = int(max(1, lo)), int(max(1, hi))
    best = lo
    a, b = lo, hi
    while a <= b:
        mid = (a + b) // 2
        _, _, bw, bh = layout_text(text, family, weight, style, mid, width, wrap_on, line_height)
        if bw <= width + 0.5 and bh <= height + 0.5:
            best = mid
            a = mid + 1
        else:
            b = mid - 1
    return best


def draw_block(img, rect, text, family, weight, style, size, color, alpha, align_x, align_y,
               wrap_on, line_height=1.0, stroke=None, scale=1.0):
    """Draws a text block into an RGBA PIL image. rect = (x, y, w, h) in image pixels;
    size is in the same pixels. stroke = (color rgb, thickness px, opacity) or None.
    Returns (block width, block height)."""
    x, y, w, h = rect
    face, lines, bw, bh = layout_text(text, family, weight, style, size, w, wrap_on, line_height)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    lh = face.line_height * (line_height if line_height else 1.0)
    top = y + {"Top": 0, "Bottom": h - bh}.get(align_y, (h - bh) / 2)
    outline = Image.new("L", img.size, 0) if stroke and stroke[2] > 0.01 and stroke[1] > 0 else None
    od = ImageDraw.Draw(outline) if outline is not None else None
    for i, line in enumerate(lines):
        lw = face.width(line)
        if align_x == "Left":
            lx = x
        elif align_x == "Right":
            lx = x + w - lw
        else:
            lx = x + (w - lw) / 2
        ly = top + i * lh
        if od is not None:
            sw = max(1, round(stroke[1] * scale))
            face.draw(od, lx, ly, line, 255, stroke=sw, stroke_fill=255)
        face.draw(d, lx, ly, line, tuple(color) + (int(255 * (1 - alpha)),))
    if outline is not None:
        ring = Image.new("RGBA", img.size, tuple(stroke[0]) + (0,))
        ring.putalpha(outline.point(lambda v: int(v * stroke[2])))
        img.alpha_composite(ring)
    img.alpha_composite(layer)
    return bw, bh
