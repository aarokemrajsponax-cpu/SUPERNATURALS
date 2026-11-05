"""Draws an exported SurfaceGui / BillboardGui subtree (absolute Position/Size layout)
into an RGBA PIL image. Used by render3d.py. Supports Frame, TextLabel, TextButton,
UICorner, UIStroke (frame border and text outline), UIGradient, UIPadding,
UITextSizeConstraint, Rotation, Visible, ZIndex, TextScaled, TextWrapped, alignment.
Not drawn: images, list/grid layouts, automatic sizing, clipping, rich text.
"""
import math

from PIL import Image, ImageDraw

import guifonts


def _first(node, cls):
    for c in node.get("children", []):
        if c["class"] == cls:
            return c
    return None


def _gradient_color(stops, t):
    if not stops:
        return None
    if t <= stops[0][0]:
        return stops[0][1:]
    for a, b in zip(stops, stops[1:]):
        if t <= b[0]:
            f = (t - a[0]) / max(b[0] - a[0], 1e-6)
            return [a[i] + (b[i] - a[i]) * f for i in range(1, len(a))]
    return stops[-1][1:]


def apply_gradient(layer, box, grad, mask):
    """Tints the pixels of `mask` (L image, node shape) inside box by a UIGradient."""
    x, y, w, h = [int(round(v)) for v in box]
    if w <= 0 or h <= 0 or not grad.get("colors"):
        return layer
    ang = math.radians(grad.get("rotation", 0))
    dx, dy = math.cos(ang), math.sin(ang)
    # t runs along the gradient direction, 0 at the box edge in -direction, 1 at the other
    extent = abs(dx) * w + abs(dy) * h
    ys, xs = None, None
    import numpy as np
    gx = (np.arange(w) + 0.5 - w / 2)[None, :]
    gy = (np.arange(h) + 0.5 - h / 2)[:, None]
    t = np.clip((gx * dx + gy * dy) / max(extent, 1e-6) + 0.5, 0, 1)
    cs = grad["colors"]
    tr = grad.get("alphas") or []
    rgb = np.zeros((h, w, 3), np.float32)
    al = np.ones((h, w), np.float32)
    ts = np.array([c[0] for c in cs])
    for ch in range(3):
        rgb[..., ch] = np.interp(t, ts, [c[1 + ch] for c in cs])
    if tr:
        al = 1 - np.interp(t, np.array([a[0] for a in tr]), [a[1] for a in tr])
    arr = np.array(layer)
    # A box that runs past the image edge (a card scrolled partly out of view) is clipped to it,
    # not skipped: skipping left such cards plain white
    H, W = arr.shape[:2]
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + w, W), min(y + h, H)
    if x1 <= x0 or y1 <= y0:
        return layer
    rgb = rgb[y0 - y:y1 - y, x0 - x:x1 - x]
    al = al[y0 - y:y1 - y, x0 - x:x1 - x]
    region = arr[y0:y1, x0:x1]
    region[..., :3] = (region[..., :3].astype(np.float32) * rgb).astype(np.uint8)
    region[..., 3] = (region[..., 3].astype(np.float32) * al).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def _rect(node, parent, k):
    px, py, pw, ph = parent
    s, p, a = node["size"], node["pos"], node["anchor"]
    w = s[0] * pw + s[1] * k
    h = s[2] * ph + s[3] * k
    x = px + p[0] * pw + p[1] * k - a[0] * w
    y = py + p[2] * ph + p[3] * k - a[1] * h
    return x, y, w, h


def draw_children(img, node, parent_rect, k):
    kids = [c for c in node.get("children", []) if "size" in c and c.get("visible", True)]
    for c in sorted(kids, key=lambda c: c.get("z", 1)):
        draw_node(img, c, parent_rect, k)


def draw_node(img, node, parent_rect, k):
    x, y, w, h = _rect(node, parent_rect, k)
    if w <= 0 or h <= 0:
        return
    layer = img
    rot = node.get("rotation") or 0
    if rot:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    corner = _first(node, "UICorner")
    radius = 0
    if corner:
        radius = min(corner["radius"][0] * min(w, h) + corner["radius"][1] * k, min(w, h) / 2)
    box = [x, y, x + w - 1, y + h - 1]
    alpha = 1 - node.get("bgAlpha", 1)
    grad = _first(node, "UIGradient")
    if alpha > 0.01:
        fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(fill).rounded_rectangle(box, radius=radius, fill=tuple(node["bg"]) + (int(alpha * 255),))
        if grad:
            fill = apply_gradient(fill, (x, y, w, h), grad, None)
        layer.alpha_composite(fill)
    is_text = bool(node.get("text"))
    stroke = _first(node, "UIStroke")
    if stroke and not is_text and stroke["alpha"] < 0.99 and stroke["thickness"] > 0:
        t = max(1, round(stroke["thickness"] * k))
        ring = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(ring).rounded_rectangle([box[0] - t / 2, box[1] - t / 2, box[2] + t / 2, box[3] + t / 2],
                                               radius=radius + t / 2, outline=tuple(stroke["color"]) + (int((1 - stroke["alpha"]) * 255),), width=t)
        layer.alpha_composite(ring)
    if is_text:
        pad = _first(node, "UIPadding")
        pt, pr, pb, pl = [v * k for v in (pad["pad"] if pad else (0, 0, 0, 0))]
        rect = (x + pl, y + pt, max(1, w - pl - pr), max(1, h - pt - pb))
        cons = _first(node, "UITextSizeConstraint")
        lo = cons["minTextSize"] * k if cons else 1
        hi = cons["maxTextSize"] * k if cons else 10000
        fam, wt, st = node.get("family"), node.get("weight", "Regular"), node.get("style", "Normal")
        lh = node.get("lineHeight") or 1.0
        wrap_on = bool(node.get("wrap"))
        if node.get("scaled"):
            size = guifonts.scaled_size(node["text"], fam, wt, st, rect[2], rect[3], wrap_on, lo, min(hi, 100 * k), lh)
        else:
            size = min(max(node.get("textSize", 14) * k, lo), hi)
        st_arg = None
        if stroke and stroke.get("mode") != "Border" and stroke["alpha"] < 0.99:
            st_arg = (stroke["color"], stroke["thickness"] * k, 1 - stroke["alpha"])
        guifonts.draw_block(layer, rect, node["text"], fam, wt, st, size, node.get("textColor", [255, 255, 255]),
                            node.get("textAlpha", 0), node.get("alignX"), node.get("alignY"), wrap_on, lh, st_arg, k)
    draw_children(layer, node, (x, y, w, h), k)
    if rot:
        layer = layer.rotate(-rot, center=(x + w / 2, y + h / 2), resample=Image.BICUBIC)
        img.alpha_composite(layer)


def draw_gui(children, width, height, k=1.0):
    """Draws top-level GuiObjects over a width x height design canvas, scaled by k."""
    img = Image.new("RGBA", (max(1, int(round(width * k))), max(1, int(round(height * k)))), (0, 0, 0, 0))
    draw_children(img, {"children": children}, (0, 0, width * k, height * k), k)
    return img
