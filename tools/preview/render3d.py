#!/usr/bin/env python3
"""Renders a scene exported by dump3d.luau to PNG images, so a build can be
looked at without Studio.

It is an approximation of Roblox's Future lighting, not a match: parts are
drawn with flat normals, a sun with shadows, point/spot/surface lights
without shadows, a little procedural texture per material, neon glow, glass,
atmosphere haze, bloom and the place's colour correction. Good enough to judge
composition, colour, lighting mood, clutter and scale.

Usage:
  python3 tools/preview/render3d.py scene.json out/prefix [--size 1280x720]
      [--views overview,eye,top] [--cam name:x,y,z:tx,ty,tz[:fov]] ...
Writes out/prefix_<view>.png for each view (auto views frame the scene;
cameras exported with the scene, e.g. an arena's spawn view, are added).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Roblox's default terrain material colours (Terrain:SetMaterialColor overrides them)
TERRAIN_COLORS = {
    "Grass": (106, 127, 63), "Slate": (63, 127, 107), "Concrete": (127, 102, 63), "Brick": (138, 86, 62),
    "Sand": (143, 126, 95), "WoodPlanks": (139, 109, 79), "Rock": (102, 108, 111), "Glacier": (101, 176, 234),
    "Snow": (195, 199, 218), "Sandstone": (137, 90, 71), "Mud": (58, 46, 36), "Basalt": (30, 30, 37),
    "Ground": (102, 92, 59), "CrackedLava": (232, 156, 74), "Asphalt": (115, 123, 107), "Cobblestone": (132, 123, 90),
    "Ice": (129, 194, 224), "LeafyGrass": (115, 132, 74), "Salt": (198, 189, 181), "Limestone": (206, 173, 148),
    "Pavement": (148, 148, 140), "Water": (12, 84, 92), "Air": (0, 0, 0),
}

# How each material reads: (texture strength, texture scale in studs, specular, pattern)
MATERIALS = {
    "Plastic": (0.02, 4, 0.10, None), "SmoothPlastic": (0.0, 4, 0.22, None), "Neon": (0, 1, 0, None),
    "Wood": (0.10, 1.2, 0.05, "grain"), "WoodPlanks": (0.12, 1.0, 0.05, "planks"), "Marble": (0.07, 3, 0.35, "veins"),
    "Slate": (0.12, 2.0, 0.08, "noise"), "Concrete": (0.07, 0.8, 0.04, "noise"), "Granite": (0.10, 0.6, 0.12, "noise"),
    "Brick": (0.14, 1.0, 0.03, "bricks"), "Pebble": (0.14, 0.5, 0.05, "noise"), "Cobblestone": (0.18, 1.6, 0.06, "cobble"),
    "CorrodedMetal": (0.16, 1.0, 0.25, "noise"), "DiamondPlate": (0.10, 0.7, 0.55, "diamond"), "Foil": (0.08, 0.5, 0.7, "noise"),
    "Metal": (0.05, 1.0, 0.6, "brushed"), "Grass": (0.14, 0.6, 0.03, "noise"), "LeafyGrass": (0.16, 0.6, 0.03, "noise"),
    "Sand": (0.08, 0.4, 0.02, "noise"), "Fabric": (0.08, 0.3, 0.02, "noise"), "Ice": (0.05, 2, 0.6, None),
    "Glass": (0.0, 1, 0.9, None), "ForceField": (0, 1, 0.3, None), "Basalt": (0.14, 1.4, 0.05, "noise"),
    "CrackedLava": (0.25, 2.0, 0.05, "cracks"), "Rock": (0.15, 2.0, 0.05, "noise"), "Ground": (0.12, 1.0, 0.02, "noise"),
    "Mud": (0.10, 1.0, 0.1, "noise"), "Asphalt": (0.08, 0.4, 0.05, "noise"), "Limestone": (0.08, 1.5, 0.05, "noise"),
    "Pavement": (0.10, 2.0, 0.05, "tiles"), "Salt": (0.06, 0.5, 0.1, "noise"), "Snow": (0.04, 1.0, 0.1, "noise"),
    "Sandstone": (0.10, 1.5, 0.05, "noise"), "Glacier": (0.05, 2, 0.4, None), "Cardboard": (0.06, 0.5, 0.02, "noise"),
    "Carpet": (0.06, 0.3, 0.01, "noise"), "CeramicTiles": (0.06, 1.0, 0.4, "tiles"), "ClayRoofTiles": (0.12, 1.0, 0.1, "bricks"),
    "RoofShingles": (0.12, 0.8, 0.05, "bricks"), "Leather": (0.06, 0.5, 0.15, "noise"), "Plaster": (0.04, 1.0, 0.04, "noise"),
    "Rubber": (0.03, 1.0, 0.1, None), "Glacier ": (0.05, 2, 0.4, None),
}
TRANSPARENT_MATERIALS = {"Glass", "ForceField", "Water"}


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


# Geometry -------------------------------------------------------------------------------

def unit_box():
    v = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], dtype=np.float32)
    idx = lambda x, y, z: ((x > 0) * 4 + (y > 0) * 2 + (z > 0))
    faces = []
    for axis in range(3):
        for sign in (-1, 1):
            corners = []
            for a in (-1, 1):
                for b in (-1, 1):
                    p = [0, 0, 0]
                    p[axis] = sign
                    others = [i for i in range(3) if i != axis]
                    p[others[0]] = a
                    p[others[1]] = b
                    corners.append(idx(*p))
            c00, c01, c10, c11 = corners
            faces.append((c00, c10, c11))
            faces.append((c00, c11, c01))
    return v, np.array(faces)


def unit_wedge():
    # Roblox WedgePart: full bottom and back (+Z) faces; the slope runs from the
    # top back edge down to the bottom front (-Z) edge
    v = np.array([
        [-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1],  # bottom
        [-1, 1, 1], [1, 1, 1],  # top back edge
    ], dtype=np.float32)
    f = [(0, 1, 2), (0, 2, 3),  # bottom
         (3, 2, 5), (3, 5, 4),  # back
         (0, 4, 5), (0, 5, 1),  # slope
         (0, 3, 4), (1, 5, 2)]  # sides
    return v, np.array(f)


def unit_corner_wedge():
    v = np.array([[-1, -1, -1], [1, -1, -1], [1, -1, 1], [-1, -1, 1], [1, 1, -1]], dtype=np.float32)
    f = [(0, 1, 2), (0, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    return v, np.array(f)


def unit_cylinder(segments, axis=0):
    # Roblox part cylinders run along X; terrain cylinders along Y
    verts = []
    for s in (-1, 1):
        for i in range(segments):
            a = 2 * math.pi * i / segments
            p = [0.0, 0.0, 0.0]
            others = [i2 for i2 in range(3) if i2 != axis]
            p[axis] = s
            p[others[0]] = math.cos(a)
            p[others[1]] = math.sin(a)
            verts.append(p)
    verts.append([(-1 if i == axis else 0) for i in range(3)])
    verts.append([(1 if i == axis else 0) for i in range(3)])
    c0, c1 = 2 * segments, 2 * segments + 1
    f = []
    for i in range(segments):
        j = (i + 1) % segments
        a0, a1, b0, b1 = i, j, segments + i, segments + j
        f.append((a0, b0, b1))
        f.append((a0, b1, a1))
        f.append((c0, a1, a0))
        f.append((c1, b0, b1))
    return np.array(verts, dtype=np.float32), np.array(f)


def unit_sphere(rings, segments):
    verts = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        for s in range(segments):
            th = 2 * math.pi * s / segments
            verts.append([math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th)])
    f = []
    for r in range(rings):
        for s in range(segments):
            a = r * segments + s
            b = r * segments + (s + 1) % segments
            c = (r + 1) * segments + s
            d = (r + 1) * segments + (s + 1) % segments
            if r != 0:
                f.append((a, b, d))
            if r != rings - 1:
                f.append((a, d, c))
    return np.array(verts, dtype=np.float32), np.array(f)


SHAPES = {
    "Block": unit_box(), "Wedge": unit_wedge(), "CornerWedge": unit_corner_wedge(),
}
CYL_CACHE = {}
SPHERE_CACHE = {}


def cylinder(segments, axis):
    key = (segments, axis)
    if key not in CYL_CACHE:
        CYL_CACHE[key] = unit_cylinder(segments, axis)
    return CYL_CACHE[key]


def sphere(rings, segments):
    key = (rings, segments)
    if key not in SPHERE_CACHE:
        SPHERE_CACHE[key] = unit_sphere(rings, segments)
    return SPHERE_CACHE[key]


def cframe_matrix(cf):
    pos = np.array(cf[0:3], dtype=np.float32)
    rot = np.array(cf[3:12], dtype=np.float32).reshape(3, 3)
    return pos, rot


class Mesh:
    def __init__(self):
        self.tris = []      # (N, 3, 3) world vertices
        self.color = []     # linear albedo
        self.material = []
        self.alpha = []
        self.shadow = []
        self.reflect = []
        self.terrain = []

    def add(self, verts, faces, color, material, alpha, shadow, reflect, terrain=False):
        t = verts[faces]
        self.tris.append(t)
        n = len(faces)
        self.color.append(np.repeat(np.array([color], dtype=np.float32), n, axis=0))
        self.material += [material] * n
        self.alpha += [alpha] * n
        self.shadow += [shadow] * n
        self.reflect += [reflect] * n
        self.terrain += [terrain] * n

    def finish(self):
        if not self.tris:
            self.tris = np.zeros((0, 3, 3), np.float32)
            self.color = np.zeros((0, 3), np.float32)
        else:
            self.tris = np.concatenate(self.tris).astype(np.float32)
            self.color = np.concatenate(self.color)
        self.material = np.array(self.material, dtype=object)
        self.alpha = np.array(self.alpha, dtype=np.float32)
        self.shadow = np.array(self.shadow, dtype=bool)
        self.reflect = np.array(self.reflect, dtype=np.float32)
        self.terrain = np.array(self.terrain, dtype=bool)
        e1 = self.tris[:, 1] - self.tris[:, 0]
        e2 = self.tris[:, 2] - self.tris[:, 0]
        n = np.cross(e1, e2)
        ln = np.linalg.norm(n, axis=1, keepdims=True)
        self.area = ln[:, 0] / 2
        self.normal = n / np.maximum(ln, 1e-9)


def build_mesh(scene):
    mesh = Mesh()
    for p in scene.get("parts", []):
        pos, rot = cframe_matrix(p["cf"])
        size = np.array(p["size"], dtype=np.float32)
        shape = p["shape"]
        if shape == "Cylinder":
            radius = min(size[1], size[2]) / 2
            seg = int(np.clip(radius * 3, 10, 32))
            v, f = cylinder(seg, 0)
            scale = np.array([size[0] / 2, radius, radius], dtype=np.float32)
        elif shape == "Ball":
            d = float(min(size))
            rings = int(np.clip(d * 1.5, 6, 14))
            v, f = sphere(rings, rings * 2)
            scale = np.array([d / 2] * 3, dtype=np.float32)
        else:
            v, f = SHAPES.get(shape, SHAPES["Block"])
            scale = size / 2
        world = (v * scale) @ rot.T + pos
        color = srgb_to_linear(p["color"])
        mesh.add(world, f, color, p["material"], 1 - float(p.get("transparency", 0)), bool(p.get("shadow", True)),
                 float(p.get("reflectance", 0)))

    colors = dict(TERRAIN_COLORS)
    for name, c in (scene.get("terrainColors") or {}).items():
        colors[name] = tuple(int(x * 255) for x in c)
    water = scene.get("water") or {}
    for t in scene.get("terrain", []):
        mat = t["material"]
        if mat == "Air":
            continue
        base = colors.get(mat, (128, 128, 128))
        if mat == "Water" and water.get("color"):
            base = tuple(int(x * 255) for x in water["color"])
        color = srgb_to_linear(np.array(base) / 255)
        alpha = 0.55 if mat == "Water" else 1.0
        if t["kind"] == "Ball":
            r = t["radius"]
            v, f = sphere(10, 20)
            world = v * r + np.array(t["center"], np.float32)
        else:
            pos, rot = cframe_matrix(t["cf"])
            if t["kind"] == "Cylinder":
                v, f = cylinder(24, 1)
                scale = np.array([t["radius"], t["height"] / 2, t["radius"]], np.float32)
            elif t["kind"] == "Wedge":
                v, f = SHAPES["Wedge"]
                scale = np.array(t["size"], np.float32) / 2
            else:
                v, f = SHAPES["Block"]
                scale = np.array(t["size"], np.float32) / 2
            world = (v * scale) @ rot.T + pos
        mesh.add(world, f, color, "T:" + mat, alpha, mat != "Water", 0.0, terrain=True)
    mesh.finish()
    return mesh


# Cameras --------------------------------------------------------------------------------

def look_at(position, target, fov, width, height):
    position = np.array(position, np.float32)
    target = np.array(target, np.float32)
    forward = target - position
    forward /= max(np.linalg.norm(forward), 1e-6)
    up = np.array([0, 1, 0], np.float32)
    if abs(forward @ up) > 0.995:
        up = np.array([0, 0, -1], np.float32)
    right = np.cross(forward, up)
    right /= np.linalg.norm(right)
    true_up = np.cross(right, forward)
    focal = (height / 2) / math.tan(math.radians(fov) / 2)
    return {"pos": position, "fwd": forward, "right": right, "up": true_up, "focal": focal, "w": width, "h": height}


def scene_bounds(mesh):
    if len(mesh.tris) == 0:
        return np.zeros(3), np.ones(3)
    pts = mesh.tris.reshape(-1, 3)
    span = mesh.tris.max(axis=1) - mesh.tris.min(axis=1)
    # Frame the built things: terrain and very long parts (beams, skyboxes) don't count
    keep = (span.max(axis=1) < 150) & ~mesh.terrain
    pts = mesh.tris[keep].reshape(-1, 3) if keep.any() else pts
    lo = np.percentile(pts, 1, axis=0)
    hi = np.percentile(pts, 99, axis=0)
    return lo, hi


def auto_cameras(mesh, names, width, height):
    lo, hi = scene_bounds(mesh)
    center = (lo + hi) / 2
    extent = hi - lo
    radius = float(np.linalg.norm(extent[[0, 2]])) / 2 + 4
    cams = {}
    ground = lo[1] + min(extent[1], 1)
    if "overview" in names:
        d = radius * 1.35
        pos = center + np.array([-0.62, 0.62, 0.62]) * d
        cams["overview"] = look_at(pos, center + np.array([0, -extent[1] * 0.1, 0]), 50, width, height)
    if "eye" in names:
        pos = np.array([center[0] - radius * 0.72, ground + 6, center[2] + radius * 0.12])
        cams["eye"] = look_at(pos, np.array([center[0], ground + 4.5, center[2]]), 70, width, height)
    if "top" in names:
        pos = center + np.array([0, radius * 2.2, radius * 0.25])
        cams["top"] = look_at(pos, center, 45, width, height)
    if "low" in names:
        pos = np.array([center[0] + radius * 0.5, ground + 2.5, center[2] - radius * 0.65])
        cams["low"] = look_at(pos, np.array([center[0], ground + 8, center[2]]), 75, width, height)
    return cams


# Rasterising ------------------------------------------------------------------------------

NEAR = 0.2


def to_camera(cam, pts):
    rel = pts - cam["pos"]
    return np.stack([rel @ cam["right"], rel @ cam["up"], rel @ cam["fwd"]], axis=-1)


def clip_near(tri_cam):
    """Clips one camera-space triangle against the near plane (z = NEAR, z is depth).
    Returns a list of 0-2 triangles."""
    inside = [p for p in tri_cam if p[2] >= NEAR]
    if len(inside) == 3:
        return [tri_cam]
    if not inside:
        return []
    poly = []
    for i in range(3):
        a, b = tri_cam[i], tri_cam[(i + 1) % 3]
        ain, bin_ = a[2] >= NEAR, b[2] >= NEAR
        if ain:
            poly.append(a)
        if ain != bin_:
            t = (NEAR - a[2]) / (b[2] - a[2])
            poly.append(a + (b - a) * t)
    out = []
    for i in range(1, len(poly) - 1):
        out.append(np.array([poly[0], poly[i], poly[i + 1]]))
    return out


def rasterize(screen_tris, inv_depth, ids, width, height, depth_buf, id_buf, cull=True):
    """screen_tris (N,3,2) pixel coords, inv_depth (N,3) 1/z. Writes nearest (largest 1/z)."""
    for k in range(len(screen_tris)):
        t = screen_tris[k]
        x0, y0 = t[0]
        x1, y1 = t[1]
        x2, y2 = t[2]
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        if cull and area > 0:
            continue
        minx = max(int(math.floor(min(x0, x1, x2))), 0)
        maxx = min(int(math.ceil(max(x0, x1, x2))), width - 1)
        miny = max(int(math.floor(min(y0, y1, y2))), 0)
        maxy = min(int(math.ceil(max(y0, y1, y2))), height - 1)
        if minx > maxx or miny > maxy:
            continue
        xs = np.arange(minx, maxx + 1, dtype=np.float32) + 0.5
        ys = np.arange(miny, maxy + 1, dtype=np.float32)[:, None] + 0.5
        w0 = ((x1 - xs) * (y2 - ys) - (x2 - xs) * (y1 - ys)) / area
        w1 = ((x2 - xs) * (y0 - ys) - (x0 - xs) * (y2 - ys)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        z = w0 * inv_depth[k, 0] + w1 * inv_depth[k, 1] + w2 * inv_depth[k, 2]
        region = depth_buf[miny:maxy + 1, minx:maxx + 1]
        closer = inside & (z > region)
        if closer.any():
            region[closer] = z[closer]
            id_buf[miny:maxy + 1, minx:maxx + 1][closer] = ids[k]


def project(cam, mesh, select):
    """Camera-space clip + projection for the selected triangles. Returns screen
    triangles, 1/z per vertex and triangle ids."""
    tris = mesh.tris[select]
    ids = np.nonzero(select)[0]
    cam_pts = to_camera(cam, tris.reshape(-1, 3)).reshape(-1, 3, 3)
    z = cam_pts[:, :, 2]
    all_in = (z >= NEAR).all(axis=1)
    any_in = (z >= NEAR).any(axis=1)
    keep_tris = [cam_pts[all_in]]
    keep_ids = [ids[all_in]]
    partial = np.nonzero(any_in & ~all_in)[0]
    extra, extra_ids = [], []
    for i in partial:
        for t in clip_near(cam_pts[i]):
            extra.append(t)
            extra_ids.append(ids[i])
    if extra:
        keep_tris.append(np.array(extra, np.float32))
        keep_ids.append(np.array(extra_ids))
    cam_pts = np.concatenate(keep_tris)
    ids = np.concatenate(keep_ids)
    f = cam["focal"]
    sx = cam["w"] / 2 + cam_pts[:, :, 0] / cam_pts[:, :, 2] * f
    sy = cam["h"] / 2 - cam_pts[:, :, 1] / cam_pts[:, :, 2] * f
    screen = np.stack([sx, sy], axis=-1)
    # Drop triangles entirely off screen
    mn = screen.min(axis=1)
    mx = screen.max(axis=1)
    on = (mx[:, 0] >= 0) & (mn[:, 0] < cam["w"]) & (mx[:, 1] >= 0) & (mn[:, 1] < cam["h"])
    return screen[on], 1 / cam_pts[on][:, :, 2], ids[on]


# Lighting ---------------------------------------------------------------------------------

def sun_direction(lighting):
    clock = float(lighting.get("clockTime") or 14)
    lat = math.radians(float(lighting.get("latitude") or 41.7))
    hour = (clock - 12) / 24 * 2 * math.pi
    # Sun path for an equinox day at this latitude: rises in the east (+X here)
    # and sets in the west, tilted toward the south (+Z)
    x = -math.sin(hour)
    y = math.cos(hour) * math.cos(lat)
    z = math.cos(hour) * math.sin(lat)
    d = np.array([x, y, z], np.float32)
    d /= np.linalg.norm(d)
    if d[1] < 0.08:
        # Below the horizon: Roblox lights the night with the moon, from above
        d = np.array([0.3, 0.6, 0.4], np.float32)
        d /= np.linalg.norm(d)
        return d, True
    return d, False


def build_shadow_map(mesh, sun, size=2048):
    lo, hi = scene_bounds(mesh)
    center = (lo + hi) / 2
    radius = float(np.linalg.norm(hi - lo)) / 2 + 10
    fwd = -sun
    up = np.array([0, 1, 0], np.float32) if abs(fwd[1]) < 0.99 else np.array([0, 0, 1], np.float32)
    right = np.cross(fwd, up)
    right /= np.linalg.norm(right)
    true_up = np.cross(right, fwd)
    origin = center - fwd * radius * 2
    sel = mesh.shadow & (mesh.alpha > 0.5)
    tris = mesh.tris[sel]
    rel = tris.reshape(-1, 3) - origin
    u = (rel @ right) / radius
    v = (rel @ true_up) / radius
    d = rel @ fwd
    sx = (u * 0.5 + 0.5) * size
    sy = (0.5 - v * 0.5) * size
    screen = np.stack([sx, sy], -1).reshape(-1, 3, 2)
    inv = (1 / np.maximum(d, 1e-3)).reshape(-1, 3)
    depth = np.zeros((size, size), np.float32)
    ids = np.full((size, size), -1, np.int32)
    rasterize(screen, inv, np.arange(len(screen)), size, size, depth, ids, cull=False)
    return {"origin": origin, "right": right, "up": true_up, "fwd": fwd, "radius": radius, "size": size, "depth": depth}


def shadow_lookup(sm, points, normals):
    rel = points + normals * 0.15 - sm["origin"]
    u = (rel @ sm["right"]) / sm["radius"]
    v = (rel @ sm["up"]) / sm["radius"]
    d = rel @ sm["fwd"]
    size = sm["size"]
    lit = np.zeros(len(points), np.float32)
    offsets = [(0, 0), (1.2, 0), (-1.2, 0), (0, 1.2), (0, -1.2)]
    for ox, oy in offsets:
        sx = np.clip(((u * 0.5 + 0.5) * size + ox).astype(np.int32), 0, size - 1)
        sy = np.clip(((0.5 - v * 0.5) * size + oy).astype(np.int32), 0, size - 1)
        stored = sm["depth"][sy, sx]
        nearest = np.where(stored > 0, 1 / np.maximum(stored, 1e-9), 1e9)
        lit += (d <= nearest + 0.35 + d * 0.002).astype(np.float32)
    return lit / len(offsets)


def hash_noise(p, scale):
    q = np.floor(p / scale)
    n = np.sin(q[:, 0] * 12.9898 + q[:, 1] * 78.233 + q[:, 2] * 37.719) * 43758.5453
    return n - np.floor(n)


def value_noise(p, scale):
    """Smooth-ish noise from blending a few hashed grids."""
    a = hash_noise(p, scale)
    b = hash_noise(p + 0.5 * scale, scale)
    c = hash_noise(p * 1.7 + 3.1, scale * 0.5)
    return (a + b) * 0.35 + c * 0.3


def material_detail(materials, points, normals):
    """Brightness multiplier per pixel from a cheap procedural pattern per material."""
    out = np.ones(len(points), np.float32)
    names = np.unique(materials)
    for name in names:
        key = name[2:] if name.startswith("T:") else name
        strength, scale, _, pattern = MATERIALS.get(key, (0.04, 2, 0.1, "noise"))
        if strength <= 0:
            continue
        m = materials == name
        p = points[m]
        n = np.abs(normals[m])
        if pattern == "planks":
            axis = np.where(n[:, 1] > 0.5, p[:, 0], p[:, 1])
            plank = np.floor(axis / scale)
            seam = (np.abs(axis / scale - np.round(axis / scale)) < 0.04).astype(np.float32)
            n2 = np.sin(plank * 91.7) * 0.5 + 0.5
            out[m] = 1 + (n2 - 0.5) * strength * 1.4 - seam * 0.35
        elif pattern == "bricks":
            h = p[:, 1] / (scale * 0.5)
            row = np.floor(h)
            along = np.where(n[:, 0] > 0.5, p[:, 2], p[:, 0]) / scale + (row % 2) * 0.5
            mortar = ((np.abs(h - np.round(h)) < 0.07) | (np.abs(along - np.round(along)) < 0.035)).astype(np.float32)
            out[m] = 1 + (hash_noise(np.stack([np.floor(along), row, row], 1), 1) - 0.5) * strength - mortar * 0.3
        elif pattern == "cobble":
            v = value_noise(p, scale)
            edge = (np.abs(np.sin(p[:, 0] / scale * 2.3 + np.sin(p[:, 2] / scale * 1.7)) * np.sin(p[:, 2] / scale * 2.1)) < 0.08)
            out[m] = 1 + (v - 0.5) * strength * 2 - edge * 0.25
        elif pattern == "tiles":
            gx = np.abs(p[:, 0] / scale - np.round(p[:, 0] / scale)) < 0.03
            gz = np.abs(p[:, 2] / scale - np.round(p[:, 2] / scale)) < 0.03
            out[m] = 1 + (hash_noise(p, scale) - 0.5) * strength - (gx | gz) * 0.2
        elif pattern == "diamond":
            d = (np.sin((p[:, 0] + p[:, 2]) / scale * 6) * np.sin((p[:, 0] - p[:, 2]) / scale * 6))
            out[m] = 1 + d * strength
        elif pattern == "brushed":
            out[m] = 1 + (hash_noise(p * np.array([1, 40, 1]), scale) - 0.5) * strength
        elif pattern == "cracks":
            v = value_noise(p, scale)
            out[m] = 0.55 + (v > 0.62) * 1.2
        else:
            out[m] = 1 + (value_noise(p, scale) - 0.5) * strength * 2
    return out


def light_falloff(dist, rng):
    x = np.clip(1 - dist / max(rng, 0.1), 0, 1)
    return x * x


# Rendering a view -------------------------------------------------------------------------

def gaussian_blur(img, sigma):
    if sigma <= 0.5:
        return img
    radius = int(sigma * 2.5)
    xs = np.arange(-radius, radius + 1)
    k = np.exp(-(xs ** 2) / (2 * sigma * sigma))
    k /= k.sum()
    out = img
    for axis in (0, 1):
        padded = np.pad(out, [(radius, radius) if a == axis else (0, 0) for a in range(3)], mode="edge")
        acc = np.zeros_like(out)
        for i, w in enumerate(k):
            sl = [slice(None)] * 3
            sl[axis] = slice(i, i + out.shape[axis])
            acc += padded[tuple(sl)] * w
        out = acc
    return out


def bloom(img, threshold, intensity, size):
    bright = np.clip(img - threshold, 0, None)
    small = bright[::4, ::4]
    blurred = gaussian_blur(small, max(1.0, size / 8))
    blurred2 = gaussian_blur(small, max(2.0, size / 3))
    up = np.repeat(np.repeat((blurred + blurred2) * 0.5, 4, axis=0), 4, axis=1)[: img.shape[0], : img.shape[1]]
    return img + up * intensity


def aces(x):
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip((x * (a * x + b)) / (x * (c * x + d) + e), 0, 1)


def render_view(scene, mesh, cam, shadow_map, sun, night, out_path, label):
    W, H = cam["w"], cam["h"]
    lighting = scene.get("lighting") or {}
    atmos = scene.get("atmosphere")

    opaque = (mesh.alpha > 0.97) & ~np.isin(mesh.material, list(TRANSPARENT_MATERIALS))
    screen, inv, ids = project(cam, mesh, opaque)
    depth = np.zeros((H, W), np.float32)
    idbuf = np.full((H, W), -1, np.int32)
    rasterize(screen, inv, ids, W, H, depth, idbuf, cull=False)

    # Rays for every pixel
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    dirs = (cam["fwd"][None, None, :] * cam["focal"]
            + cam["right"][None, None, :] * (xs[..., None] + 0.5 - W / 2)
            - cam["up"][None, None, :] * (ys[..., None] + 0.5 - H / 2))
    dirs /= np.linalg.norm(dirs, axis=-1, keepdims=True)

    # Sky
    zen = srgb_to_linear(np.array([0.30, 0.52, 0.86]))
    hor = srgb_to_linear(np.array(atmos["color"]) if atmos else np.array([0.75, 0.82, 0.9]))
    if atmos and atmos.get("decay"):
        zen = zen * 0.6 + srgb_to_linear(np.array(atmos["decay"])) * 0.4
    if night:
        zen, hor = zen * 0.08, hor * 0.15
    up = np.clip(dirs[..., 1], -0.2, 1)
    t = np.clip(up, 0, 1) ** 0.45
    img = hor[None, None, :] * (1 - t[..., None]) + zen[None, None, :] * t[..., None]
    sun_dot = np.clip((dirs @ sun), 0, 1)
    if not night:
        img += np.array([1.0, 0.85, 0.6])[None, None, :] * (sun_dot ** 600 * 8 + sun_dot ** 12 * 0.25)[..., None]

    hit = idbuf >= 0
    pix = np.nonzero(hit)
    tri = idbuf[pix]
    n = mesh.normal[tri]
    origin = mesh.tris[tri, 0]
    ray = dirs[pix]
    denom = np.sum(n * ray, axis=1)
    denom = np.where(np.abs(denom) < 1e-6, -1e-6, denom)
    dist = np.sum(n * (origin - cam["pos"]), axis=1) / denom
    dist = np.clip(dist, 0, 1e5)
    points = cam["pos"] + ray * dist[:, None]
    # Face the camera
    flip = np.sum(n * ray, axis=1) > 0
    n = np.where(flip[:, None], -n, n)

    albedo = mesh.color[tri].copy()
    mats = mesh.material[tri]
    albedo *= material_detail(mats, points, n)[:, None]

    brightness = float(lighting.get("brightness") or 2)
    sun_color = np.array([1.0, 0.94, 0.84], np.float32) * brightness * (0.15 if night else 1.0)
    if lighting.get("colorShiftTop"):
        sun_color = sun_color * (1 + np.array(lighting["colorShiftTop"]) * 0.5)
    ndl = np.clip(n @ sun, 0, 1)
    shadow = shadow_lookup(shadow_map, points, n) if shadow_map is not None else np.ones(len(points))
    ambient = srgb_to_linear(np.array(lighting.get("ambient") or [0.27, 0.27, 0.27]))
    outdoor = srgb_to_linear(np.array(lighting.get("outdoorAmbient") or [0.5, 0.5, 0.5]))
    sky_vis = 0.55 + 0.45 * n[:, 1]
    light = sun_color[None, :] * (ndl * shadow)[:, None]
    light += outdoor[None, :] * (sky_vis * 0.9)[:, None] + ambient[None, :] * 0.6
    # Bounce light from the sunlit ground
    light += sun_color[None, :] * (0.06 * np.clip(-n[:, 1] * 0.5 + 0.5, 0, 1))[:, None]

    for lt in scene.get("lights", []):
        lp = np.array(lt["position"], np.float32)
        rng = float(lt["range"])
        if lt["kind"] == "SurfaceLight" and lt.get("cf"):
            pos, rot = cframe_matrix(lt["cf"])
            faces = {"Front": -rot[:, 2], "Back": rot[:, 2], "Top": rot[:, 1], "Bottom": -rot[:, 1], "Right": rot[:, 0], "Left": -rot[:, 0]}
            fn = faces.get(lt.get("face") or "Front", -rot[:, 2])
            half = np.abs(np.array(lt["size"]) / 2 @ np.abs(rot.T) @ np.abs(fn))
            lp = pos + fn * (float(half) + 0.1)
        delta = lp - points
        d = np.linalg.norm(delta, axis=1)
        near = d < rng
        if not near.any():
            continue
        l = delta[near] / np.maximum(d[near, None], 1e-6)
        ndl_p = np.clip(np.sum(n[near] * l, axis=1), 0, 1) * 0.85 + 0.15
        fall = light_falloff(d[near], rng)
        if lt["kind"] == "SurfaceLight" and lt.get("cf"):
            fall *= np.clip(np.sum(-l * fn, axis=1), 0, 1)
        contrib = np.array(lt["color"], np.float32)[None, :] * (float(lt["brightness"]) * 1.4 * fall * ndl_p)[:, None]
        light[near] += srgb_to_linear(np.ones(3)) * contrib

    color = albedo * light
    # Specular from the sun
    spec_amount = np.array([MATERIALS.get(m[2:] if m.startswith("T:") else m, (0, 1, 0.1, None))[2] for m in mats], np.float32)
    h = sun[None, :] - ray
    h /= np.linalg.norm(h, axis=1, keepdims=True)
    spec = np.clip(np.sum(n * h, axis=1), 0, 1) ** 48 * spec_amount * shadow
    color += sun_color[None, :] * spec[:, None] * 0.6
    # Reflectance: mix in the sky
    refl = mesh.reflect[tri]
    if refl.any():
        color = color * (1 - refl[:, None]) + hor[None, :] * refl[:, None] * 0.8
    # Neon glows: unlit, bright
    neon = mats == "Neon"
    if neon.any():
        color[neon] = mesh.color[tri][neon] * 2.4 + 0.05

    # Atmosphere haze with distance
    if atmos:
        density = float(atmos.get("density") or 0.3)
        haze = float(atmos.get("haze") or 0)
        k = 0.0011 * density * (1 + haze * 0.3)
        f = 1 - np.exp(-k * np.maximum(dist - 20, 0))
        hz = hor * (0.9 if not night else 0.2)
        color = color * (1 - f[:, None]) + hz[None, :] * f[:, None]
    fog_end = float(lighting.get("fogEnd") or 1e5)
    if fog_end < 5000:
        fs = float(lighting.get("fogStart") or 0)
        f = np.clip((dist - fs) / max(fog_end - fs, 1), 0, 1)
        fc = srgb_to_linear(np.array(lighting.get("fogColor") or [0.75, 0.75, 0.75]))
        color = color * (1 - f[:, None]) + fc[None, :] * f[:, None]

    img[pix] = color
    zbuf = np.full((H, W), 1e9, np.float32)
    zbuf[pix] = dist

    # Transparent triangles, back to front, each shaded flat at its centre
    trans = ~opaque & (mesh.alpha > 0.02)
    if trans.any():
        screen_t, inv_t, ids_t = project(cam, mesh, trans)
        order = np.argsort(inv_t.mean(axis=1))
        for k in order:
            tid = ids_t[k]
            t2 = screen_t[k]
            x0, y0 = t2[0]
            x1, y1 = t2[1]
            x2, y2 = t2[2]
            area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if abs(area) < 1e-9:
                continue
            minx = max(int(math.floor(min(x0, x1, x2))), 0)
            maxx = min(int(math.ceil(max(x0, x1, x2))), W - 1)
            miny = max(int(math.floor(min(y0, y1, y2))), 0)
            maxy = min(int(math.ceil(max(y0, y1, y2))), H - 1)
            if minx > maxx or miny > maxy:
                continue
            gx = np.arange(minx, maxx + 1, dtype=np.float32) + 0.5
            gy = np.arange(miny, maxy + 1, dtype=np.float32)[:, None] + 0.5
            w0 = ((x1 - gx) * (y2 - gy) - (x2 - gx) * (y1 - gy)) / area
            w1 = ((x2 - gx) * (y0 - gy) - (x0 - gx) * (y2 - gy)) / area
            w2 = 1 - w0 - w1
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            z = 1 / np.maximum(w0 * inv_t[k, 0] + w1 * inv_t[k, 1] + w2 * inv_t[k, 2], 1e-9)
            region_z = zbuf[miny:maxy + 1, minx:maxx + 1]
            vis = inside & (z < region_z)
            if not vis.any():
                continue
            base = mesh.color[tid]
            nrm = mesh.normal[tid]
            mat = mesh.material[tid]
            a = float(mesh.alpha[tid])
            if mat == "Glass":
                a = max(a * 0.35, 0.18)
            elif mat == "ForceField":
                a = a * 0.5
            lit = base * (sun_color * max(0.0, float(abs(nrm @ sun))) * 0.6 + outdoor * 0.9 + ambient * 0.5)
            if mat == "Neon":
                lit = base * 2.4
            region = img[miny:maxy + 1, minx:maxx + 1]
            region[vis] = region[vis] * (1 - a) + lit * a
            if mat == "Glass":
                region[vis] += hor * 0.08

    # Particles and beams as soft glows
    glow = np.zeros_like(img)
    for pe in scene.get("particles", []):
        p = np.array(pe["position"], np.float32)
        cp = to_camera(cam, p[None, :])[0]
        if cp[2] < NEAR:
            continue
        sx = W / 2 + cp[0] / cp[2] * cam["focal"]
        sy = H / 2 - cp[1] / cp[2] * cam["focal"]
        r = max(2.0, float(pe["size"]) * 1.6 / cp[2] * cam["focal"])
        if not (-r < sx < W + r and -r < sy < H + r):
            continue
        x0, x1 = int(max(sx - r * 2, 0)), int(min(sx + r * 2, W - 1))
        y0, y1 = int(max(sy - r * 2, 0)), int(min(sy + r * 2, H - 1))
        if x0 >= x1 or y0 >= y1:
            continue
        gx = np.arange(x0, x1 + 1) - sx
        gy = (np.arange(y0, y1 + 1) - sy)[:, None]
        fall = np.exp(-(gx * gx + gy * gy) / (2 * r * r))
        amount = min(1.0, float(pe["rate"]) / 25) * (0.25 + float(pe.get("lightEmission") or 0) * 0.6) * (1 - float(pe.get("transparency") or 0))
        occl = (zbuf[y0:y1 + 1, x0:x1 + 1] > cp[2] - 1)
        glow[y0:y1 + 1, x0:x1 + 1] += srgb_to_linear(np.array(pe["color"]))[None, None, :] * (fall * amount * occl)[..., None]
    for bm in scene.get("beams", []):
        a3 = to_camera(cam, np.array([bm["a"], bm["b"]], np.float32))
        if (a3[:, 2] < NEAR).any():
            continue
        pa = np.array([W / 2 + a3[0, 0] / a3[0, 2] * cam["focal"], H / 2 - a3[0, 1] / a3[0, 2] * cam["focal"]])
        pb = np.array([W / 2 + a3[1, 0] / a3[1, 2] * cam["focal"], H / 2 - a3[1, 1] / a3[1, 2] * cam["focal"]])
        width = max(1.0, float(bm["width"]) / a3[:, 2].mean() * cam["focal"] * 0.5)
        x0, x1 = int(max(min(pa[0], pb[0]) - width, 0)), int(min(max(pa[0], pb[0]) + width, W - 1))
        y0, y1 = int(max(min(pa[1], pb[1]) - width, 0)), int(min(max(pa[1], pb[1]) + width, H - 1))
        if x0 >= x1 or y0 >= y1:
            continue
        gx = np.arange(x0, x1 + 1)
        gy = np.arange(y0, y1 + 1)[:, None]
        d = pb - pa
        L2 = max(float(d @ d), 1e-6)
        tt = np.clip(((gx - pa[0]) * d[0] + (gy - pa[1]) * d[1]) / L2, 0, 1)
        px = pa[0] + tt * d[0] - gx
        py = pa[1] + tt * d[1] - gy
        dd = np.sqrt(px * px + py * py)
        amount = np.clip(1 - dd / width, 0, 1) * (1 - float(bm.get("transparency") or 0)) * (0.4 + float(bm.get("lightEmission") or 0))
        glow[y0:y1 + 1, x0:x1 + 1] += srgb_to_linear(np.array(bm["color"]))[None, None, :] * amount[..., None]
    img += glow

    # Post: bloom, exposure, tone map, colour correction
    bl = scene.get("bloom")
    if bl:
        img = bloom(img, max(0.6, float(bl["threshold"]) * 0.9), float(bl["intensity"]) * 0.9, float(bl["size"]))
    exposure = 2 ** float(lighting.get("exposure") or 0)
    img = aces(img * exposure * 1.15)
    img = linear_to_srgb(img)
    for cc in scene.get("colorCorrection") or []:
        img = img + float(cc.get("brightness") or 0)
        img = (img - 0.5) * (1 + float(cc.get("contrast") or 0)) + 0.5
        lum = (img @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
        img = lum + (img - lum) * (1 + float(cc.get("saturation") or 0))
        if cc.get("tint"):
            img = img * np.array(cc["tint"], np.float32)[None, None, :]
    img = np.clip(img, 0, 1)
    out = Image.fromarray((img * 255).astype(np.uint8))

    # Sign text, small and pale, so labels can be checked
    texts = scene.get("texts") or []
    if texts:
        draw = ImageDraw.Draw(out)
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf", 14)
        except OSError:
            font = ImageFont.load_default()
        for tx in texts:
            cp = to_camera(cam, np.array([tx["position"]], np.float32))[0]
            if cp[2] < 1 or cp[2] > 220:
                continue
            sx = W / 2 + cp[0] / cp[2] * cam["focal"]
            sy = H / 2 - cp[1] / cp[2] * cam["focal"]
            if 0 <= sx < W and 0 <= sy < H and zbuf[int(sy), int(sx)] > cp[2] - 2:
                text = tx["text"][:40]
                draw.text((sx, sy), text, fill=tuple(int(c * 255) for c in (tx.get("color") or [1, 1, 1])), font=font, anchor="mm")
    draw = ImageDraw.Draw(out)
    draw.text((8, H - 18), label, fill=(255, 255, 255))
    out.save(out_path)


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    scene_path, prefix = args[0], args[1]
    width, height = 1280, 720
    views = ["overview", "eye", "top"]
    custom = []
    i = 2
    while i < len(args):
        if args[i] == "--size":
            width, height = map(int, args[i + 1].lower().split("x"))
            i += 2
        elif args[i] == "--views":
            views = [v for v in args[i + 1].split(",") if v]
            i += 2
        elif args[i] == "--cam":
            parts = args[i + 1].split(":")
            name = parts[0]
            pos = list(map(float, parts[1].split(",")))
            tgt = list(map(float, parts[2].split(",")))
            fov = float(parts[3]) if len(parts) > 3 else 70
            custom.append((name, pos, tgt, fov))
            i += 2
        else:
            raise SystemExit("unknown argument " + args[i])
    with open(scene_path) as f:
        scene = json.load(f)
    mesh = build_mesh(scene)
    print(f"{len(mesh.tris)} triangles from {len(scene.get('parts', []))} parts and {len(scene.get('terrain', []))} terrain fills")
    sun, night = sun_direction(scene.get("lighting") or {})
    shadow_map = build_shadow_map(mesh, sun) if len(mesh.tris) else None
    cams = auto_cameras(mesh, views, width, height)
    for cam in scene.get("cameras") or []:
        cams[cam["name"]] = look_at(cam["position"], cam["target"], cam.get("fov", 70), width, height)
    for name, pos, tgt, fov in custom:
        cams[name] = look_at(pos, tgt, fov, width, height)
    os.makedirs(os.path.dirname(prefix) or ".", exist_ok=True)
    for name, cam in cams.items():
        path = f"{prefix}_{name}.png"
        render_view(scene, mesh, cam, shadow_map, sun, night, path, f"{os.path.basename(prefix)} / {name}")
        print("wrote", path)


if __name__ == "__main__":
    main()
