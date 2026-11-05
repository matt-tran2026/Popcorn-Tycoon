"""Builds the Popcorn Tycoon Corn Clippers (Common) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns); ns["result"] holds the stats.
Rebuilds the "Tool_CornClippers" collection from scratch, so it is safe to re-run.

Reference: the creator's render (bypass pruners, bright yellow handles, steel blade and hook,
coil spring between the handles, round pivot bolt). The model is that render seen from behind
(blades toward +X), which keeps the real layering: blade on the -Z side, hook on the +Z side.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. Grip point (centre of the hand on the lower handle) = origin.
  * The lower handle runs along +X toward the blades. The tool is flat in the X/Y plane, Z is
    its thickness. +Y is the side the upper handle and the hook's pivot sit on.
  * Colours are vertex colours on one white material.

Meshes (each becomes one MeshPart). The jaw half turns about the pivot bolt (Blender Z axis
through PIVOT) on a Motor6D in game, so it is split from the fixed half:
  ClippersHandle    lower yellow handle             -> the Tool's Handle, SmoothPlastic (fixed)
  ClippersBlade     cutting blade, its tang, bolt   -> Metal, welded to the Handle (fixed)
  ClippersJaw       hook (anvil) jaw and its tang   -> Metal, Motor6D "Jaw" about the pivot
  ClippersJawGrip   upper yellow handle             -> SmoothPlastic, welded to ClippersJaw
  ClippersSpring    coil spring between the handles -> Metal, Motor6D "Spring" (half the jaw angle)
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_CornClippers"
rng = random.Random(11)  # Fixed seed: colour jitter is identical every build.

# Design coordinates: pivot bolt at (0, 0), u toward the blade tip, v toward the upper handle.
# One stud is about 420 px of the 2000 px reference render (tip to handle end about 2.7 studs).
GRIP = Vector((-0.95, -0.165, 0.0))  # Centre of the hand on the lower handle (becomes the origin).
PIVOT = Vector((0.0, 0.0, 0.0))

YELLOW = (255, 199, 28)
YELLOW_LIGHT = (255, 226, 92)
YELLOW_DARK = (232, 162, 16)
BOLSTER = (246, 178, 22)
STEEL = (196, 203, 212)
STEEL_DARK = (142, 150, 161)
EDGE = (246, 248, 251)
BOLT = (176, 184, 194)
BOLT_LIGHT = (222, 227, 233)
SPRING = (150, 157, 167)
SPRING_LIGHT = (205, 211, 219)

BLADE_Z = -0.05  # Centre plane of the cutting blade and its tang (front in the reference).
JAW_Z = 0.05  # Centre plane of the hook jaw and its tang.
PLATE = 0.08  # Tang plate thickness.


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


def jitter(rgb, amount):
    k = 1 + rng.uniform(-amount, amount)
    return tuple(max(0, min(255, c * k)) for c in rgb)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Builder:
    """A bmesh plus one colour per vertex (in creation order)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.colours = []

    def vert(self, co, rgb):
        self.colours.append(rgb)
        return self.bm.verts.new(co)

    def face(self, verts):
        return self.bm.faces.new(verts)

    def finish(self, name):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
        me = bpy.data.meshes.new(name)
        bm.normal_update()
        bm.to_mesh(me)
        bm.free()
        att = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for loop in me.loops:
            att.data[loop.index].color_srgb = srgb(*self.colours[loop.vertex_index])
        for poly in me.polygons:
            poly.use_smooth = False
        return bpy.data.objects.new(name, me)


def catmull(points, samples):
    """Smooth curve through 2D/3D points (Catmull-Rom), `samples` points from first to last."""
    pts = [Vector(p) for p in points]
    pts = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    segments = len(pts) - 3
    for i in range(samples):
        f = i / (samples - 1) * segments
        k = min(int(f), segments - 1)
        t = f - k
        p0, p1, p2, p3 = pts[k], pts[k + 1], pts[k + 2], pts[k + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    return out


def frames_along(centres):
    """(centre, tangent, in-plane normal) for a centre line lying in the X/Y plane."""
    out = []
    for i, c in enumerate(centres):
        a = centres[max(0, i - 1)]
        b = centres[min(len(centres) - 1, i + 1)]
        t = (b - a).normalized()
        n = Vector((-t.y, t.x, 0.0))
        out.append((c, t, n))
    return out


def connect(b, rings, closed=True):
    count = len(rings[0])
    for i in range(len(rings) - 1):
        for s in range(count if closed else count - 1):
            q = (s + 1) % count
            b.face((rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s]))


def fan(b, ring, tip_co, rgb):
    tip = b.vert(tip_co, rgb)
    for s in range(len(ring)):
        q = (s + 1) % len(ring)
        b.face((ring[s], ring[q], tip))


def superellipse(count, half_h, half_d, power):
    """Rounded-box section points (along in-plane normal, along Z), starting at the top."""
    pts = []
    for s in range(count):
        a = math.pi / 2 - 2 * math.pi * s / count
        c, d = math.cos(a), math.sin(a)
        pts.append((math.copysign(abs(d) ** power, d) * half_h, math.copysign(abs(c) ** power, c) * half_d, d))
    return pts


def build_grip(b, centre_points, rings_n, height, depth, bolster_until, base_rgb):
    """A chunky yellow handle swept along a smooth centre line, bolster first, rounded end.

    height(t)/depth(t) give the section size at t (0 bolster face .. 1 butt end)."""
    centres = [Vector((p.x, p.y, 0.0)) for p in catmull(centre_points, rings_n)]
    frames = frames_along(centres)
    rings = []
    sides = 8
    for i, (c, t, n) in enumerate(frames):
        f = i / (rings_n - 1)
        h, d = height(f), depth(f)
        if n.y < 0:
            n = -n  # Section "top" faces +Y (up in the reference), so the gloss paints the top.
        # Round the butt: the last rings shrink on a quarter circle.
        end = (f - 0.80) / 0.20
        if end > 0:
            k = math.sqrt(max(0.0, 1 - end * end * 0.55))
            h, d = h * k, d * k
        ring = []
        for (along_n, along_z, up) in superellipse(sides, h / 2, d / 2, 0.62):
            co = c + n * along_n + Vector((0, 0, along_z))
            if f < bolster_until:
                rgb = BOLSTER
            else:
                # Painted gloss: lighter on the upper side of the section, darker underneath.
                rgb = mix(base_rgb, YELLOW_LIGHT, max(0.0, up) * 0.55) if up >= 0 else mix(base_rgb, YELLOW_DARK, -up * 0.6)
            ring.append(b.vert(co, jitter(rgb, 0.03)))
        rings.append(ring)
    connect(b, rings)
    # Flat bolster face toward the pivot (the steel tang disappears into it).
    b.face(list(reversed(rings[0])))
    c, t, _ = frames[-1]
    fan(b, rings[-1], c + t * 0.05, YELLOW_DARK)
    return centres


def lower_handle():
    b = Builder()
    pts = [(-0.20, -0.172), (-0.42, -0.178), (-0.72, -0.172), (-1.05, -0.162), (-1.36, -0.148), (-1.58, -0.13)]

    def height(f):
        if f < 0.14:
            return 0.31
        if f < 0.24:
            return 0.31 - (f - 0.14) / 0.10 * 0.09
        return 0.22 + 0.045 * math.sin((f - 0.24) / 0.76 * math.pi)

    def depth(f):
        return 0.27 if f < 0.14 else 0.215 + 0.03 * math.sin(max(0.0, f - 0.14) / 0.86 * math.pi)

    build_grip(b, pts, 14, height, depth, 0.14, YELLOW)
    return b.finish("ClippersHandle")


def upper_handle():
    b = Builder()
    pts = [(-0.02, 0.30), (-0.22, 0.36), (-0.42, 0.48), (-0.64, 0.67), (-0.90, 0.84), (-1.18, 0.95)]

    def height(f):
        if f < 0.14:
            return 0.30
        if f < 0.24:
            return 0.30 - (f - 0.14) / 0.10 * 0.09
        return 0.21 + 0.05 * math.sin((f - 0.24) / 0.76 * math.pi)

    def depth(f):
        return 0.26 if f < 0.14 else 0.21 + 0.03 * math.sin(max(0.0, f - 0.14) / 0.86 * math.pi)

    build_grip(b, pts, 14, height, depth, 0.14, YELLOW)
    return b.finish("ClippersJawGrip")


def hull(points):
    """Convex hull (monotone chain), counter-clockwise."""
    pts = sorted(set((round(p[0], 5), round(p[1], 5)) for p in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, c):
        return (a[0] - o[0]) * (c[1] - o[1]) - (a[1] - o[1]) * (c[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def plate(b, outline, z_centre, thickness, rgb, rim_rgb):
    """Extrudes a convex outline with a small chamfer on both faces."""
    cx = sum(p[0] for p in outline) / len(outline)
    cy = sum(p[1] for p in outline) / len(outline)
    chamfer = 0.014
    rings = []
    for z, inset in ((z_centre - thickness / 2, chamfer), (z_centre - thickness / 2 + chamfer, 0.0),
                     (z_centre + thickness / 2 - chamfer, 0.0), (z_centre + thickness / 2, chamfer)):
        ring = []
        for (x, y) in outline:
            d = Vector((cx - x, cy - y))
            d = d.normalized() * inset if d.length > 1e-6 else d
            ring.append(b.vert((x + d.x, y + d.y, z), jitter(rgb if inset else rim_rgb, 0.04)))
        rings.append(ring)
    connect(b, rings)
    b.face(list(reversed(rings[0])))
    b.face(rings[-1])


def circle(cx, cy, r, n, start=0.0):
    return [(cx + r * math.cos(start + 2 * math.pi * k / n), cy + r * math.sin(start + 2 * math.pi * k / n)) for k in range(n)]


def lathe_z(b, profile, cx, cy, segments, colour_of_ring, top_rgb):
    """Revolves (z, radius) points about a Z-parallel axis through (cx, cy); caps the last ring."""
    rings = []
    for i, (z, r) in enumerate(profile):
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            ring.append(b.vert((cx + r * math.cos(a), cy + r * math.sin(a), z), jitter(colour_of_ring(i), 0.03)))
        rings.append(ring)
    connect(b, rings)
    z_last = profile[-1][0]
    fan(b, rings[-1], (cx, cy, z_last), top_rgb)
    b.face(list(reversed(rings[0])))


def blade_and_bolt():
    b = Builder()
    # Cutting blade: spine on top, a convex cutting edge underneath rising to the tip.
    spine = catmull([(0.06, 0.15), (0.35, 0.14), (0.65, 0.105), (0.90, 0.045), (1.08, -0.025)], 14)
    edge = catmull([(0.06, -0.27), (0.35, -0.255), (0.65, -0.195), (0.90, -0.12), (1.08, -0.05)], 14)
    rings = []
    z = Vector((0, 0, 1))
    for i in range(len(spine)):
        t = i / (len(spine) - 1)
        s3, e3 = Vector((spine[i].x, spine[i].y, BLADE_Z)), Vector((edge[i].x, edge[i].y, BLADE_Z))
        across = e3 - s3
        th = 0.075 * (1 - 0.55 * t) + 0.012
        section = [
            (s3 + z * th / 2, STEEL_DARK),
            (s3 + across * 0.55 + z * th * 0.42, STEEL),
            (e3, EDGE),
            (s3 + across * 0.55 - z * th * 0.42, STEEL),
            (s3 - z * th / 2, STEEL_DARK),
        ]
        rings.append([b.vert(co, jitter(rgb, 0.05 if rgb == STEEL else 0.02)) for co, rgb in section])
    connect(b, rings)
    tip = Vector((1.15, -0.042, BLADE_Z))
    tip_v = b.vert(tip, EDGE)
    for s in range(5):
        q = (s + 1) % 5
        b.face((rings[-1][s], rings[-1][q], tip_v))
    b.face(list(reversed(rings[0])))
    # Tang plate: round boss around the pivot, running back into the lower handle's bolster.
    outline = hull(circle(0, 0, 0.19, 14) + [(0.13, 0.15), (0.13, -0.27), (-0.26, -0.09), (-0.26, -0.25)])
    plate(b, outline, BLADE_Z, PLATE, STEEL, STEEL_DARK)
    # Pivot bolt head on the blade side, nut on the jaw side.
    back = BLADE_Z - PLATE / 2
    lathe_z(b, [(back + 0.004, 0.092), (back - 0.022, 0.092), (back - 0.036, 0.078), (back - 0.041, 0.05)],
            0, 0, 12, lambda i: BOLT_LIGHT if i == 1 else BOLT, BOLT)
    front = JAW_Z + PLATE / 2
    lathe_z(b, [(front - 0.004, 0.078), (front + 0.03, 0.078), (front + 0.036, 0.06)],
            0, 0, 6, lambda i: BOLT, BOLT_LIGHT)
    return b.finish("ClippersBlade")


def jaw():
    b = Builder()
    # Hook (anvil) jaw: a blunt banana curving down and forward under the blade.
    centres = catmull([(0.06, -0.10), (0.20, -0.30), (0.38, -0.48), (0.58, -0.60), (0.78, -0.665)], 13)
    frames = frames_along([Vector((c.x, c.y, JAW_Z)) for c in centres])
    rings = []
    for i, (c, t, n) in enumerate(frames):
        f = i / (len(frames) - 1)
        w = 0.27 - 0.07 * f
        th = 0.085 - 0.02 * f
        end = (f - 0.78) / 0.22
        if end > 0:
            k = math.sqrt(max(0.0, 1 - end * end * 0.7))
            w, th = w * k, th * k
        z = Vector((0, 0, 1))
        # n points to the concave side (toward the blade): a slightly sharper anvil edge there.
        section = [
            (c + n * w * 0.5, STEEL), (c + n * w * 0.22 + z * th / 2, STEEL),
            (c - n * w * 0.30 + z * th / 2, STEEL_DARK), (c - n * w * 0.5, STEEL_DARK),
            (c - n * w * 0.30 - z * th / 2, STEEL_DARK), (c + n * w * 0.22 - z * th / 2, STEEL),
        ]
        rings.append([b.vert(co, jitter(rgb, 0.05)) for co, rgb in section])
    connect(b, rings)
    c, t, _ = frames[-1]
    fan(b, rings[-1], c + t * 0.05, STEEL_DARK)
    b.face(list(reversed(rings[0])))
    # Tang plate: boss round the pivot, neck up into the upper handle's bolster.
    outline = hull(circle(0, 0, 0.19, 14) + [(-0.10, 0.33), (0.08, 0.33), (0.20, -0.18), (0.02, -0.26)])
    plate(b, outline, JAW_Z, PLATE, STEEL, STEEL_DARK)
    return b.finish("ClippersJaw")


SPRING_FROM = Vector((-0.42, -0.04, 0.0))  # Top of the lower handle.
SPRING_TO = Vector((-0.34, 0.315, 0.0))  # Underside of the upper handle.


def spring():
    b = Builder()
    axis = SPRING_TO - SPRING_FROM
    length = axis.length
    w = axis.normalized()
    u = Vector((-w.y, w.x, 0.0))
    v = Vector((0, 0, 1))
    turns, per_turn, sides = 5, 8, 4
    coil_r, wire_r = 0.088, 0.022
    steps = turns * per_turn + 1
    rings = []
    for i in range(steps):
        a = 2 * math.pi * i / per_turn
        along = (i / (steps - 1)) * length
        centre = SPRING_FROM + w * along + (u * math.cos(a) + v * math.sin(a)) * coil_r
        tangent = (u * -math.sin(a) + v * math.cos(a)) * (2 * math.pi * coil_r / per_turn) + w * (length / (steps - 1))
        tangent.normalize()
        n1 = (centre - (SPRING_FROM + w * along)).normalized()
        n2 = tangent.cross(n1).normalized()
        ring = []
        for s in range(sides):
            phi = 2 * math.pi * s / sides + math.pi / 4
            rgb = SPRING_LIGHT if s == 0 else SPRING
            ring.append(b.vert(centre + (n1 * math.cos(phi) + n2 * math.sin(phi)) * wire_r, jitter(rgb, 0.04)))
        rings.append(ring)
    connect(b, rings)
    b.face(list(reversed(rings[0])))
    b.face(rings[-1])
    return b.finish("ClippersSpring")


def white_material():
    mat = bpy.data.materials.get("ToolVertexColour")
    if mat is None:
        mat = bpy.data.materials.new("ToolVertexColour")
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        bsdf = nodes.get("Principled BSDF")
        attr = nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.55
    return mat


def to_tool_frame(p):
    """Design point -> tool frame used by ToolPresentation points (X along handle, Z = Blender Y)."""
    q = Vector(p) - GRIP
    return [round(q.x, 3), round(-q.z, 3), round(q.y, 3)]


def build():
    old = bpy.data.collections.get(COLLECTION)
    if old:
        for obj in list(old.objects):
            mesh = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if mesh and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(col)
    mat = white_material()
    made = {}
    total = 0
    objs = [lower_handle(), blade_and_bolt(), jaw(), upper_handle(), spring()]
    for obj in objs:
        # Grip point to the origin.
        for vtx in obj.data.vertices:
            vtx.co -= GRIP
        obj.data.update()
        obj.data.materials.append(mat)
        col.objects.link(obj)
        tris = len(obj.data.polygons)
        total += tris
        xs = [vtx.co.x for vtx in obj.data.vertices]
        ys = [vtx.co.y for vtx in obj.data.vertices]
        zs = [vtx.co.z for vtx in obj.data.vertices]
        made[obj.name] = {
            "tris": tris,
            "dims": [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
            "centre": [round((max(xs) + min(xs)) / 2, 3), round((max(ys) + min(ys)) / 2, 3), round((max(zs) + min(zs)) / 2, 3)],
        }
    handle = made["ClippersHandle"]
    return {
        "meshes": made,
        "totalTris": total,
        # ToolPresentation numbers, read straight off the build.
        "gripFromCentre": round(-handle["centre"][0], 3),
        "pivot": to_tool_frame(PIVOT),
        "points": {
            "BladeTip": to_tool_frame((1.15, -0.042, 0)),
            "SnipPoint": to_tool_frame((0.42, -0.16, 0)),
        },
    }


result = build()
