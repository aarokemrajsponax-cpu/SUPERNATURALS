"""Approximate Roblox GUI layout + drawing from the JSON the dump scripts write, to
eyeball the interface and flag text that overflows its box. Not pixel-exact.

Draws: Frames with UICorner, UIStroke (borders, and text outlines for Contextual strokes),
UIGradient fills, UIPadding, list/grid layouts, AutomaticSize, ClipsDescendants, GuiObject
Rotation (the whole subtree turns about the frame centre, so the drawn icons come out right),
text in stand-in fonts (Montserrat for Builder Sans / Gotham at the matching weight,
Michroma, Roboto Mono; see tools/fonts), TextScaled with UITextSizeConstraint, and
ViewportFrame contents (parts, camera, light) through tools/preview/render3d.py.
Not drawn: images (a flat blue box), gradients on text and strokes, particle or transparent
parts inside viewports, emoji (a gold square), SurfaceGuis.

Usage: python3 tools/uipreview/render.py <scene.json> <out.png>
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = os.environ.get("SN_PREVIEW_DIR") or os.path.join(HERE, "..", "preview")
sys.path.insert(0, os.path.abspath(PREVIEW))
import guidraw  # noqa: E402
import guifonts  # noqa: E402

problems = []
_viewport_cache = {}


def face_of(node, size):
    return guifonts.Face(node.get("family"), node.get("weight", "Regular"), node.get("style", "Normal"), max(1, size))


def is_emoji(ch):
    return ord(ch) > 0x2100


def text_width(text, face):
    w, plain = 0, []
    for ch in text:
        if is_emoji(ch):
            if 0xFE00 <= ord(ch) <= 0xFE0F:
                continue
            w += face.width("".join(plain))
            plain = []
            w += face.size * 1.1
        else:
            plain.append(ch)
    return w + face.width("".join(plain))


def wrap_lines(text, face, width):
    lines = []
    for para in text.split("\n"):
        line = ""
        for word in para.split(" "):
            trial = (line + " " + word) if line else word
            if text_width(trial, face) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def kids(node, cls=None):
    return [c for c in node["children"] if cls is None or c["class"] == cls]


def gui_kids(node):
    return [c for c in node["children"] if "size" in c]


def first(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def padding_of(node):
    p = first(node, "UIPadding")
    return p["pad"] if p else [0, 0, 0, 0]


def text_bounds(node, avail_w):
    size = node.get("textSize", 14)
    text = node.get("text", "")
    if not text:
        return 0, 0
    face = face_of(node, size)
    if node.get("wrap"):
        lines = wrap_lines(text, face, max(1, avail_w))
        return max(text_width(l, face) for l in lines), len(lines) * face.line_height
    return text_width(text, face), face.line_height


def layout(node, rect, parent_content, positioned=None):
    """rect is set by the caller; computes children rects, returns the node's final rect."""
    x, y, w, h = rect
    node["rect"] = [x, y, w, h]
    pad = padding_of(node)
    cx, cy = x + pad[3], y + pad[0]
    cw, ch = max(0, w - pad[1] - pad[3]), max(0, h - pad[0] - pad[2])
    lst = first(node, "UIListLayout")
    grid = first(node, "UIGridLayout")
    children = [c for c in gui_kids(node) if c.get("visible", True)]

    def size_of(c, pw, ph):
        s = c["size"]
        sw = s[0] * pw + s[1]
        sh = s[2] * ph + s[3]
        mn = first(c, "UISizeConstraint")
        if mn:
            sw = max(sw, mn["minSize"][0])
            sh = max(sh, mn["minSize"][1])
        return sw, sh

    placed = []
    if grid:
        cell = grid["cell"]
        cpad = grid["cellPad"]
        cwid = cell[0] * cw + cell[1]
        chei = cell[2] * ch + cell[3]
        px = cpad[1]
        py = cpad[3]
        per_row = max(1, int((cw + px) // (cwid + px))) if cwid > 0 else 1
        for i, c in enumerate(sorted(children, key=lambda c: c["order"])):
            r, col = divmod(i, per_row)
            placed.append((c, [cx + col * (cwid + px), cy + r * (chei + py), cwid, chei], True))
    elif lst:
        gap = lst["padding"][1]
        horizontal = lst["fill"] == "Horizontal"
        ordered = sorted(children, key=lambda c: c["order"])
        sizes = []
        for c in ordered:
            sw, sh = size_of(c, cw, ch)
            sizes.append([sw, sh])
        # auto-size children first so the list knows their sizes
        tmp = []
        for c, (sw, sh) in zip(ordered, sizes):
            r = measure(c, sw, sh, cw, ch)
            tmp.append(r)
        total = sum((r[0] if horizontal else r[1]) for r in tmp) + gap * max(0, len(tmp) - 1)
        if horizontal:
            start = cx
            if lst["hAlign"] == "Center":
                start = cx + (cw - total) / 2
            elif lst["hAlign"] == "Right":
                start = cx + cw - total
            pos = start
            for c, (sw, sh) in zip(ordered, tmp):
                yy = cy
                if lst["vAlign"] == "Center":
                    yy = cy + (ch - sh) / 2
                elif lst["vAlign"] == "Bottom":
                    yy = cy + ch - sh
                placed.append((c, [pos, yy, sw, sh], True))
                pos += sw + gap
        else:
            start = cy
            if lst["vAlign"] == "Center":
                start = cy + (ch - total) / 2
            elif lst["vAlign"] == "Bottom":
                start = cy + ch - total
            pos = start
            for c, (sw, sh) in zip(ordered, tmp):
                xx = cx
                if lst["hAlign"] == "Center":
                    xx = cx + (cw - sw) / 2
                elif lst["hAlign"] == "Right":
                    xx = cx + cw - sw
                placed.append((c, [xx, pos, sw, sh], True))
                pos += sh + gap
    else:
        for c in children:
            sw, sh = size_of(c, cw, ch)
            sw, sh = measure(c, sw, sh, cw, ch)
            p = c["pos"]
            px = cx + p[0] * cw + p[1] - c["anchor"][0] * sw
            py = cy + p[2] * ch + p[3] - c["anchor"][1] * sh
            placed.append((c, [px, py, sw, sh], False))
    for c, r, _ in placed:
        layout(c, r, (cx, cy, cw, ch))
    return node["rect"]


def measure(c, sw, sh, pw, ph):
    """Applies AutomaticSize: grows to fit children / text."""
    auto = c.get("auto")
    if not auto or auto == "None":
        return sw, sh
    pad = padding_of(c)
    if "text" in c and c.get("text"):
        tw, th = text_bounds(c, sw - pad[1] - pad[3] if auto != "X" else 10000)
        if auto in ("X", "XY"):
            sw = max(sw, tw + pad[1] + pad[3])
        if auto in ("Y", "XY"):
            sh = max(sh, th + pad[0] + pad[2])
    # children extents
    lst = first(c, "UIListLayout")
    grid = first(c, "UIGridLayout")
    children = [k for k in gui_kids(c) if k.get("visible", True)]
    if not children:
        return sw, sh
    cw = sw - pad[1] - pad[3]
    chh = sh - pad[0] - pad[2]
    if grid:
        cell = grid["cell"]
        cwid = cell[0] * cw + cell[1]
        chei = cell[2] * chh + cell[3]
        gap = grid["cellPad"][3]
        per_row = max(1, int((cw + grid["cellPad"][1]) // (cwid + grid["cellPad"][1]))) if cwid > 0 else 1
        rows = (len(children) + per_row - 1) // per_row
        need_h = rows * chei + max(0, rows - 1) * gap
        if auto in ("Y", "XY"):
            sh = max(sh, need_h + pad[0] + pad[2])
        return sw, sh
    if lst:
        gap = lst["padding"][1]
        horizontal = lst["fill"] == "Horizontal"
        tot_main, max_cross = 0, 0
        for k in children:
            kw = k["size"][0] * cw + k["size"][1]
            kh = k["size"][2] * chh + k["size"][3]
            kw, kh = measure(k, kw, kh, cw, chh)
            if horizontal:
                tot_main += kw
                max_cross = max(max_cross, kh)
            else:
                tot_main += kh
                max_cross = max(max_cross, kw)
        tot_main += gap * max(0, len(children) - 1)
        if horizontal:
            if auto in ("X", "XY"):
                sw = max(sw, tot_main + pad[1] + pad[3])
            if auto in ("Y", "XY"):
                sh = max(sh, max_cross + pad[0] + pad[2])
        else:
            if auto in ("Y", "XY"):
                sh = max(sh, tot_main + pad[0] + pad[2])
            if auto in ("X", "XY"):
                sw = max(sw, max_cross + pad[1] + pad[3])
        return sw, sh
    max_x, max_y = 0, 0
    for k in children:
        kw = k["size"][0] * cw + k["size"][1]
        kh = k["size"][2] * chh + k["size"][3]
        kw, kh = measure(k, kw, kh, cw, chh)
        p = k["pos"]
        kx = p[0] * cw + p[1] - k["anchor"][0] * kw
        ky = p[2] * chh + p[3] - k["anchor"][1] * kh
        max_x = max(max_x, kx + kw)
        max_y = max(max_y, ky + kh)
    if auto in ("X", "XY"):
        sw = max(sw, max_x + pad[1] + pad[3])
    if auto in ("Y", "XY"):
        sh = max(sh, max_y + pad[0] + pad[2])
    return sw, sh


def blend(base, color, alpha):
    return tuple(int(b * (1 - alpha) + c * alpha) for b, c in zip(base, color))


def subtree_bounds(node):
    x, y, w, h = node["rect"]
    x0, y0, x1, y1 = x, y, x + w, y + h
    for k in node["children"]:
        if "rect" in k and k.get("visible", True):
            kx0, ky0, kx1, ky1 = subtree_bounds(k)
            x0, y0, x1, y1 = min(x0, kx0), min(y0, ky0), max(x1, kx1), max(y1, ky1)
    return x0, y0, x1, y1


def draw_node(img, node, clip, path, depth=0):
    """Draws a node. A rotated node (and everything under it) is drawn flat on a scratch
    layer, then turned about the node's centre, as Roblox does."""
    if "rect" not in node or not node.get("visible", True):
        return
    rot = node.get("rotation") or 0
    if not rot or "size" not in node:
        return draw_node_flat(img, node, clip, path, depth)
    x, y, w, h = node["rect"]
    cx, cy = x + w / 2, y + h / 2
    x0, y0, x1, y1 = subtree_bounds(node)
    r = int(math.ceil(max(math.hypot(px - cx, py - cy) for px in (x0, x1) for py in (y0, y1)))) + 6
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_node_flat(layer, node, None, path, depth)
    bx, by = int(math.floor(cx)) - r, int(math.floor(cy)) - r
    region = layer.crop((bx, by, bx + 2 * r, by + 2 * r))
    region = region.rotate(-rot, center=(cx - bx, cy - by), resample=Image.BICUBIC)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(region, (bx, by))
    if clip:
        mask = Image.new("L", img.size, 0)
        c = list(clip)
        ImageDraw.Draw(mask).rectangle([c[0], c[1], max(c[0], c[2]), max(c[1], c[3])], fill=255)
        out.putalpha(Image.composite(out.getchannel("A"), Image.new("L", img.size, 0), mask))
    img.alpha_composite(out)


def viewport_image(node, w, h):
    vp = node.get("viewport")
    if not vp or not vp.get("camera") or not vp.get("parts") or w < 2 or h < 2:
        return None
    key = (json.dumps(vp, sort_keys=True), int(w), int(h))
    if key not in _viewport_cache:
        import render3d
        d = vp["lightDirection"]
        # LightDirection is the way the light travels; the renderer wants the way to the light
        sun = [-d[0], -d[1], -d[2]]
        _viewport_cache[key] = render3d.render_scene_image(
            {"parts": vp["parts"]}, vp["camera"], vp.get("fov") or 70, int(w), int(h), sun, vp["ambient"], vp["lightColor"])
    return _viewport_cache[key]


def draw_node_flat(img, node, clip, path, depth=0):
    x, y, w, h = node["rect"]
    corner = first(node, "UICorner")
    radius = 0
    if corner:
        radius = corner["radius"][0] * min(w, h) + corner["radius"][1]
        radius = min(radius, min(w, h) / 2)
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    alpha = 1 - node.get("bgAlpha", 1)
    box = [x, y, x + max(0, w - 1), y + max(0, h - 1)]
    is_text_class = node["class"] in ("TextLabel", "TextButton", "TextBox")
    if alpha > 0.01 and w > 0 and h > 0:
        d.rounded_rectangle(box, radius=radius, fill=tuple(node["bg"]) + (int(alpha * 255),))
        grad = first(node, "UIGradient")
        if grad:
            overlay = guidraw.apply_gradient(overlay, (x, y, w, h), grad, None)
            d = ImageDraw.Draw(overlay)
    stroke = first(node, "UIStroke")
    border = stroke and (not is_text_class or stroke.get("mode") == "Border")
    if border and stroke["alpha"] < 0.99 and w > 0 and h > 0:
        d.rounded_rectangle(box, radius=radius, outline=tuple(stroke["color"]) + (int((1 - stroke["alpha"]) * 255),), width=max(1, round(stroke["thickness"])))
    if node.get("viewport") is not None and w > 1 and h > 1:
        view = viewport_image(node, w, h)
        if view is not None:
            overlay.alpha_composite(view, (int(x), int(y)))
    if node.get("image"):
        d.rounded_rectangle(box, radius=radius, fill=(120, 140, 180, 255))
    text = node.get("text") or ""
    name = path + "/" + node["name"]
    if text:
        pad = padding_of(node)
        tx, ty, tw, th = x + pad[3], y + pad[0], w - pad[1] - pad[3], h - pad[0] - pad[2]
        cons = first(node, "UITextSizeConstraint")
        lo = cons["minTextSize"] if cons else 1
        hi = cons["maxTextSize"] if cons else 10000
        lh = node.get("lineHeight") or 1
        wrap_on = bool(node.get("wrap"))
        size = node.get("textSize", 14)
        if node.get("scaled"):
            size = guifonts.scaled_size(text, node.get("family"), node.get("weight", "Regular"), node.get("style", "Normal"),
                                        max(1, tw), max(1, th), wrap_on, lo, min(hi, 100), lh)
        else:
            size = min(max(size, lo), hi)
        face = face_of(node, size)
        lines = wrap_lines(text, face, tw) if wrap_on else text.split("\n")
        width = max(text_width(l, face) for l in lines)
        height = len(lines) * face.line_height * lh
        overflow_x = width > tw + 1 and not wrap_on and not node.get("scaled")
        # extra LineHeight only opens gaps between lines, so a single line never overflows by it
        tight = height - face.line_height * (lh - 1) if lh > 1 else height
        overflow_y = tight > th + 2 and not node.get("scaled")
        if overflow_x and node.get("truncate") == "AtEnd":
            problems.append(("truncated", name, text, round(width), round(tw)))
            while lines[0] and text_width(lines[0] + "...", face) > tw:
                lines[0] = lines[0][:-1]
            lines[0] += "..."
            width = text_width(lines[0], face)
        elif overflow_x:
            problems.append(("OVERFLOW-X", name, text, round(width), round(tw)))
        if overflow_y and len(text) > 0:
            problems.append(("OVERFLOW-Y", name, text, round(height), round(th)))
        col = tuple(node.get("textColor", [255, 255, 255])) + (int((1 - node.get("textAlpha", 0)) * 255),)
        if node.get("alignY") == "Top":
            yy = ty
        elif node.get("alignY") == "Bottom":
            yy = ty + th - height
        else:
            yy = ty + (th - height) / 2
        outline = None
        if stroke and not border and stroke["alpha"] < 0.99 and stroke["thickness"] > 0:
            outline = Image.new("L", img.size, 0)
        od = ImageDraw.Draw(outline) if outline is not None else None
        sw = max(1, round(stroke["thickness"])) if outline is not None else 0
        for line in lines:
            lw = text_width(line, face)
            if node.get("alignX") == "Left":
                xx = tx
            elif node.get("alignX") == "Right":
                xx = tx + tw - lw
            else:
                xx = tx + (tw - lw) / 2
            if any(is_emoji(c) for c in line):
                cursor = xx
                for ch in line:
                    if 0xFE00 <= ord(ch) <= 0xFE0F:
                        continue
                    if is_emoji(ch):
                        d.rounded_rectangle([cursor + 1, yy + size * 0.15, cursor + size * 0.95, yy + size * 1.05], radius=3, fill=(255, 210, 120, col[3]))
                        cursor += size * 1.1
                    else:
                        face.draw(d, cursor, yy, ch, col)
                        cursor += face.width(ch)
            else:
                if od is not None:
                    face.draw(od, xx, yy, line, 255, stroke=sw, stroke_fill=255)
                face.draw(d, xx, yy, line, col)
            yy += face.line_height * lh
        if outline is not None:
            ring = Image.new("RGBA", img.size, tuple(stroke["color"]) + (0,))
            ring.putalpha(outline.point(lambda v: int(v * (1 - stroke["alpha"]))))
            ring.alpha_composite(overlay)
            overlay = ring
        if overflow_x and node.get("truncate") != "AtEnd" or overflow_y:
            if not os.environ.get("NO_FLAGS"):
                ImageDraw.Draw(overlay).rectangle(box, outline=(255, 0, 0, 255), width=2)
    if clip:
        mask = Image.new("L", img.size, 0)
        c = list(clip); c[2] = max(c[0], c[2]); c[3] = max(c[1], c[3]); ImageDraw.Draw(mask).rectangle(c, fill=255)
        overlay.putalpha(Image.composite(overlay.getchannel("A"), Image.new("L", img.size, 0), mask))
    img.alpha_composite(overlay)
    child_clip = clip
    if node.get("scroll") or node.get("clips"):
        c = [x, y, x + w, y + h]
        child_clip = c if not clip else [max(c[0], clip[0]), max(c[1], clip[1]), min(c[2], clip[2]), min(c[3], clip[3])]
    ordered = sorted([k for k in node["children"] if "size" in k], key=lambda k: k.get("z", 1))
    for k in ordered:
        draw_node(img, k, child_clip, name, depth + 1)


def main(path, out):
    data = json.load(open(path))
    vw, vh = data["viewport"]
    inset = data["inset"]
    scale = data["scale"]
    tree = data["tree"]
    # design-pixel canvas (UIScale applied when saving)
    W, H = vw / scale, (vh - inset) / scale
    root = {"name": tree["name"], "children": tree["children"], "rect": [0, 0, W, H], "visible": True}
    layout(root, [0, 0, W, H], None)
    img = Image.new("RGBA", (int(W), int(H)), (34, 44, 58, 255))
    # a stand-in "game world" gradient
    d = ImageDraw.Draw(img)
    for i in range(int(H)):
        t = i / H
        d.line([(0, i), (W, i)], fill=(int(46 + 30 * t), int(64 + 20 * t), int(80 + 10 * t), 255))
    if tree.get("enabled", True) is not False:
        for k in sorted(root["children"], key=lambda k: k.get("z", 1)):
            if "size" in k:
                draw_node(img, k, None, "")
    final = img.resize((int(vw), int(vh - inset)))
    canvas = Image.new("RGBA", (int(vw), int(vh)), (20, 20, 20, 255))
    canvas.paste(final, (0, inset))
    if inset:
        guifonts.Face(None, "Regular", "Normal", 14).draw(ImageDraw.Draw(canvas), 10, 18, "Roblox top bar (inset)", (200, 200, 200, 255))
    canvas.convert("RGB").save(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
    for p in problems:
        print(*p, sep=" | ")
