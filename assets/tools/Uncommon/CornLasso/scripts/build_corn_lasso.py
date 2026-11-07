"""Builds the Popcorn Tycoon Corn Lasso (Uncommon) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_CornLasso" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the middle of the leather grip, where the
    right hand closes) is the origin, and the handle runs along +X toward the rope.
  * Everything that hangs (the coil, the open loop, the tassels) sits on Blender +Y, so the other
    meshes average well off the handle's centre: tool Z = Blender +Y, and Blender (x, y, z) maps to
    tool (x, z, y). The rope rings lie flat in the X/Y plane (Z is their normal = tool Y).
  * Colours are vertex colours on one white material, one flat colour per face (no jitter).

Reference: the creator's render (a braided rope lasso with a brown leather-wrapped grip, studded
steel collars at both ends, leather tassels, a coil of rope and an open loop with a knot). Only
the tool is modelled; the stump, corn and swirls are staging. Design canvas: "Corn Lasso"
(https://claude.ai/artifact/Jsjsw8qthL5AYuqg7boGve).

Style: built like the creator's weapon pack (as the Long Scythe, Hedge Trimmer and Picker): chunky
low-poly solids with one flat colour per face. Rope is a 6-sided tube; the twist is painted as
diagonal stripes on the faces (no extra geometry).

Meshes (each becomes one MeshPart):
  LassoHandle    leather grip with a spiral wrap               -> the Tool's Handle (Leather)
  LassoFittings  front collar, butt cap, studs, butt ring      -> welded (Metal)
  LassoTassels   fringe strips at the butt and under the collar -> welded (Leather)
  LassoCoil      three turns of hanging rope                   -> welded (Fabric)
  LassoLoop      lead, honda knot and the open loop            -> Motor6D "Loop" at LOOP_PIVOT (Fabric)
"""
import math

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_CornLasso"


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


# Paint (the design canvas's vertex colours).
ROPE = (200, 165, 119)
ROPE_LIGHT = (222, 190, 140)
ROPE_TWIST = (156, 124, 82)
LEATHER = (142, 78, 40)
LEATHER_LIGHT = (179, 106, 58)
LEATHER_DARK = (62, 36, 20)
TASSEL = (160, 89, 44)
TASSEL_DARK = (120, 64, 30)
STEEL = (143, 148, 154)
STEEL_LIGHT = (185, 190, 196)
STEEL_DARK = (91, 97, 104)

# Design points (Blender coordinates, studs).
GRIP = (-0.85, 0.80)                 # leather grip from butt to front
GRIP_PROFILE = [(-0.85, 0.165), (-0.7, 0.185), (-0.35, 0.18), (0.0, 0.17), (0.35, 0.178), (0.65, 0.185), (0.8, 0.17)]
WRAP_PITCH = 0.24                    # spiral wrap band pitch along X
COLLAR = (0.78, 1.12, 0.215)         # front collar x0, x1, radius
BUTT = (-1.15, -0.83, 0.21)          # butt cap x0, x1, radius
STUD = 0.05                          # stud half size
BUTT_RING = ((-1.25, 0.0), 0.09, 0.032)  # centre, ring radius, wire radius
ROPE_R = 0.068                       # rope radius (chunky, as the reference)
SIDES = 6
LOOP_PIVOT = (1.12, 0.05)            # where the rope leaves the collar; the Loop motor turns here
HONDA = (2.3, 0.4)                   # the knot the loop runs through
LOOP_CENTRE = (3.0, 0.95)
LOOP_R = 0.85
COIL_CENTRE = (1.55, 0.75)
COIL_R = 0.5
COIL_TURNS = 3
COIL_SEG = 20                        # segments per turn


class Builder:
    """Collects faces with a flat colour each."""

    def __init__(self):
        self.bm = bmesh.new()
        self.colours = []
        self.layer = self.bm.faces.layers.int.new("colour")

    def face(self, verts, colour):
        f = self.bm.faces.new(verts)
        if colour not in self.colours:
            self.colours.append(colour)
        f[self.layer] = self.colours.index(colour)
        return f

    def vert(self, co):
        return self.bm.verts.new(co)

    def finish(self, name):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        cols = [self.colours[f[self.layer]] for f in bm.faces]
        # Triangulate keeps each face's layer value, so colour after splitting.
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")
        cols = [self.colours[f[self.layer]] for f in bm.faces]
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        att = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for poly in me.polygons:
            for li in poly.loop_indices:
                att.data[li].color_srgb = srgb(*cols[poly.index])
            poly.use_smooth = False
        return bpy.data.objects.new(name, me)


# ---------------------------------------------------------------------------------------------
# Primitives

def lathe(b, profile, sides, colour_of, x_axis=True, centre=(0.0, 0.0), cap=True):
    """Revolves (x, radius) points around the X axis. colour_of(row, col, x0, x1) -> colour.
    Vertex 0 of each ring sits at angle 0 (+Y)."""
    rings = []
    for x, r in profile:
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(b.vert((x, centre[0] + r * math.cos(a), centre[1] + r * math.sin(a))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            b.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]],
                   colour_of(i, k, profile[i][0], profile[i + 1][0]))
    if cap:
        b.face(list(reversed(rings[0])), colour_of(-1, 0, profile[0][0], profile[0][0]))
        b.face(rings[-1], colour_of(-2, 0, profile[-1][0], profile[-1][0]))
    return rings


def frames(points, closed=False):
    """Tangent, normal (as close to +Z as possible) and binormal per path point."""
    out = []
    n = len(points)
    for i in range(n):
        if closed:
            t = points[(i + 1) % n] - points[(i - 1) % n]
        else:
            t = points[min(i + 1, n - 1)] - points[max(i - 1, 0)]
        t.normalize()
        up = Vector((0, 0, 1))
        nrm = up - t * t.dot(up)
        if nrm.length < 1e-4:
            nrm = Vector((0, 1, 0)) - t * t.y
        nrm.normalize()
        out.append((t, nrm, t.cross(nrm)))
    return out


def tube(b, points, radius, sides=SIDES, closed=False, colour_of=None, cap=True):
    """Sweeps a regular polygon along a path. The section's first axis stays near +Z, so a
    planar path never twists. colour_of(i, k) -> colour (default: rope twist stripes)."""
    if colour_of is None:
        colour_of = rope_colour
    fr = frames(points, closed)
    rings = []
    for p, (t, nrm, bin_) in zip(points, fr):
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(b.vert(p + (nrm * math.cos(a) + bin_ * math.sin(a)) * radius))
        rings.append(ring)
    count = len(rings) if closed else len(rings) - 1
    for i in range(count):
        r0, r1 = rings[i], rings[(i + 1) % len(rings)]
        for k in range(sides):
            k2 = (k + 1) % sides
            b.face([r0[k], r0[k2], r1[k2], r1[k]], colour_of(i, k))
    if cap and not closed:
        b.face(list(reversed(rings[0])), ROPE_TWIST)
        b.face(rings[-1], ROPE_TWIST)
    return rings


def rope_colour(i, k):
    """Three strands: diagonal stripes, as (i + k) is constant along a spiral."""
    s = (i + k) % 3
    return ROPE_TWIST if s == 0 else (ROPE_LIGHT if s == 1 else ROPE)


def box(b, lo, hi, colour):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = [b.vert(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 4, 7, 3)):
        b.face([v[i] for i in f], colour)


def strip(b, a, c, width, thick, colour, colour_end):
    """A flat leather strip from a to c (Vectors), its width across Z... thin box along the line."""
    d = (c - a)
    d.normalize()
    side = Vector((0, 0, 1))
    side = side - d * d.dot(side)
    side.normalize()
    out = d.cross(side)
    hw, ht = width / 2, thick / 2
    corners = []
    for p in (a, c):
        for s, o in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            corners.append(b.vert(p + side * (s * hw) + out * (o * ht)))
    q = corners
    b.face([q[0], q[1], q[2], q[3]], colour)
    b.face([q[7], q[6], q[5], q[4]], colour_end)
    for k in range(4):
        k2 = (k + 1) % 4
        b.face([q[k], q[4 + k], q[4 + k2], q[k2]], colour)


def stud(b, centre, normal, size):
    """A low domed stud: a square plate with a pyramid cap, standing on `normal`."""
    n = normal.normalized()
    u = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
    u = (u - n * n.dot(u)).normalized()
    w = n.cross(u)
    base = [b.vert(centre + (u * sx + w * sy) * size) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    mid = [b.vert(centre + n * size * 0.55 + (u * sx + w * sy) * size * 0.8) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    tip = b.vert(centre + n * size * 1.1)
    for k in range(4):
        k2 = (k + 1) % 4
        b.face([base[k], base[k2], mid[k2], mid[k]], STEEL_DARK)
        b.face([mid[k], mid[k2], tip], STEEL_LIGHT)


def bezier(p0, p1, p2, p3, n):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append(p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3)
    return pts


# ---------------------------------------------------------------------------------------------
# Meshes

def build_handle():
    b = Builder()
    # Regular grid along the grip, radius offset by a spiral ridge (the wrap bands), as the
    # Harvest Hook's grip: the phase (x - pitch * angle / 2pi) / pitch winds round the grip.
    rows = 20
    x0, x1 = GRIP
    prof = GRIP_PROFILE

    def radius_at(x):
        for (xa, ra), (xb, rb) in zip(prof, prof[1:]):
            if xa <= x <= xb:
                return ra + (rb - ra) * (x - xa) / (xb - xa)
        return prof[-1][1]

    sides = 8
    rings = []
    phases = []
    for i in range(rows + 1):
        x = x0 + (x1 - x0) * i / rows
        ring, ph = [], []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            phase = ((x - WRAP_PITCH * a / (2 * math.pi)) / WRAP_PITCH) % 1.0
            ridge = 0.022 * math.cos(2 * math.pi * phase)
            r = radius_at(x) + ridge
            ring.append(b.vert((x, r * math.cos(a), r * math.sin(a))))
            ph.append(phase)
        rings.append(ring)
        phases.append(ph)
    for i in range(rows):
        for k in range(sides):
            k2 = (k + 1) % sides
            p = phases[i][k]
            colour = LEATHER_LIGHT if (p < 0.18 or p > 0.86) else (LEATHER_DARK if 0.42 < p < 0.58 else LEATHER)
            b.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], colour)
    b.face(list(reversed(rings[0])), LEATHER_DARK)
    b.face(rings[-1], LEATHER_DARK)
    return b.finish("LassoHandle")


def build_fittings():
    b = Builder()

    def collar_colour(lit_rows):
        def f(i, k, xa, xb):
            if i < 0:
                return STEEL_DARK
            return STEEL_LIGHT if i in lit_rows else (STEEL_DARK if i == 0 else STEEL)
        return f

    cx0, cx1, cr = COLLAR
    lathe(b, [(cx0, cr * 0.82), (cx0 + 0.03, cr), (cx0 + 0.07, cr * 1.06), (cx1 - 0.07, cr * 1.06), (cx1 - 0.03, cr),
              (cx1, cr * 0.7)], 8, collar_colour({1, 3}))
    bx0, bx1, br = BUTT
    lathe(b, [(bx0, br * 0.55), (bx0 + 0.05, br * 0.95), (bx0 + 0.09, br * 1.04), (bx1 - 0.06, br * 1.04), (bx1 - 0.02, br),
              (bx1, br * 0.82)], 8, collar_colour({1, 3}))
    # Four studs round each collar (top, bottom and both faces), as the reference's rivets.
    for x, r in (((cx0 + cx1) / 2, cr * 1.06), ((bx0 + bx1) / 2 + 0.01, br * 1.04)):
        for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
            n = Vector((0, math.cos(a), math.sin(a)))
            stud(b, Vector((x, 0, 0)) + n * (r - 0.005), n, STUD)
    # Butt ring: a small torus in the X/Y plane, hanging the tassels.
    (rx, ry), rr, wr = BUTT_RING
    pts = [Vector((rx + rr * math.cos(2 * math.pi * i / 10), ry + rr * math.sin(2 * math.pi * i / 10), 0)) for i in range(10)]
    tube(b, pts, wr, sides=5, closed=True, colour_of=lambda i, k: STEEL_LIGHT if k in (0, 1) else STEEL)
    return b.finish("LassoFittings")


def build_tassels():
    b = Builder()
    # Butt tassel: a bead on the ring's lower edge, four strips fanned down (+Y) and apart in Z.
    (rx, ry), rr, _ = BUTT_RING
    knot = Vector((rx - 0.03, ry + rr + 0.05, 0))
    lathe_bead(b, knot, 0.055)
    for dx, dz, length in ((-0.17, 0.05, 0.68), (-0.07, -0.05, 0.75), (0.04, 0.06, 0.72), (0.13, -0.04, 0.62)):
        a = knot + Vector((0, 0.04, dz * 0.4))
        c = knot + Vector((dx, length, dz))
        strip(b, a, c, 0.09, 0.025, TASSEL if dz > 0 else TASSEL_DARK, LEATHER_DARK)
    # Front tassel under the collar, toward the camera side (+Z) so it clears the coil.
    knot2 = Vector((0.9, COLLAR[2] + 0.06, 0.08))
    lathe_bead(b, knot2, 0.05)
    for dx, dz, length in ((-0.1, 0.06, 0.45), (0.0, 0.0, 0.5), (0.09, 0.09, 0.42)):
        a = knot2 + Vector((0, 0.03, 0))
        c = knot2 + Vector((dx, length, dz))
        strip(b, a, c, 0.08, 0.025, TASSEL if dx <= 0 else TASSEL_DARK, LEATHER_DARK)
    return b.finish("LassoTassels")


def lathe_bead(b, centre, r):
    """A small 6-sided bead (the tassel knot), axis along Y."""
    rings = []
    for dy, rad in ((-r, r * 0.5), (0, r), (r, r * 0.6)):
        ring = [b.vert(centre + Vector((rad * math.cos(2 * math.pi * k / 6), dy, rad * math.sin(2 * math.pi * k / 6)))) for k in range(6)]
        rings.append(ring)
    for i in range(2):
        for k in range(6):
            k2 = (k + 1) % 6
            b.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], LEATHER_DARK if i == 0 else TASSEL_DARK)
    b.face(list(reversed(rings[0])), LEATHER_DARK)
    b.face(rings[-1], TASSEL_DARK)


def build_coil():
    b = Builder()
    cx, cy = COIL_CENTRE
    # Drop from the collar's underside into the top of the coil.
    top = Vector((cx, cy - COIL_R, -0.12))
    drop = bezier(Vector((1.05, 0.14, -0.02)), Vector((1.18, 0.3, -0.06)), Vector((cx - 0.3, cy - COIL_R - 0.02, -0.1)), top, 5)
    pts = drop[:-1]
    # Three slightly uneven turns, as hand-coiled rope: radius and centre drift a little per
    # turn, Z climbs from -0.12 to +0.12 so the turns sit side by side.
    n = COIL_TURNS * COIL_SEG
    for i in range(n + 1):
        t = i / n
        a = -math.pi / 2 + 2 * math.pi * COIL_TURNS * t
        r = COIL_R * (1 + 0.06 * math.sin(2 * math.pi * t * 1.3 + 0.4))
        ox = 0.04 * math.sin(2 * math.pi * t)
        pts.append(Vector((cx + ox + r * math.cos(a), cy + r * math.sin(a), -0.12 + 0.24 * t)))
    tube(b, pts, ROPE_R)
    return b.finish("LassoCoil")


def build_loop():
    b = Builder()
    px, py = LOOP_PIVOT
    hx, hy = HONDA
    lead = bezier(Vector((px - 0.06, py, 0)), Vector((1.5, 0.0, 0)), Vector((1.95, 0.12, 0)), Vector((hx, hy, 0)), 9)
    tube(b, lead, ROPE_R)
    # The open loop: a full circle that starts and ends in the honda, with a little wobble out
    # of plane so it reads as rope, not a hoop.
    lx, ly = LOOP_CENTRE
    start = math.atan2(hy - ly, hx - lx)
    ring = []
    seg = 30
    for i in range(seg):
        a = start + 2 * math.pi * i / seg
        r = LOOP_R * (1 + 0.03 * math.sin(3 * a))
        ring.append(Vector((lx + r * math.cos(a), ly + r * math.sin(a), 0.05 * math.sin(2 * a))))
    tube(b, ring, ROPE_R * 0.95, closed=True)
    # Honda knot: a fat barrel along the lead's last direction, covering the joint.
    d = (lead[-1] - lead[-3]).normalized()
    centre = Vector((hx, hy, 0))
    knot = [centre - d * 0.13, centre - d * 0.06, centre + d * 0.06, centre + d * 0.13]
    radii = [ROPE_R * 1.1, ROPE_R * 1.75, ROPE_R * 1.75, ROPE_R * 1.1]
    fr = frames(knot)
    rings = []
    for p, rad, (t, nrm, bn) in zip(knot, radii, fr):
        rings.append([b.vert(p + (nrm * math.cos(2 * math.pi * k / 6) + bn * math.sin(2 * math.pi * k / 6)) * rad) for k in range(6)])
    for i in range(3):
        for k in range(6):
            k2 = (k + 1) % 6
            b.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], ROPE_TWIST if i == 1 else ROPE)
    b.face(list(reversed(rings[0])), ROPE_TWIST)
    b.face(rings[-1], ROPE_TWIST)
    return b.finish("LassoLoop")


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
    objs = (build_handle(), build_fittings(), build_tassels(), build_coil(), build_loop())
    for obj in objs:
        obj.data.materials.append(mat)
        col.objects.link(obj)
        lo = [min(v.co[k] for v in obj.data.vertices) for k in range(3)]
        hi = [max(v.co[k] for v in obj.data.vertices) for k in range(3)]
        made[obj.name] = {"tris": len(obj.data.polygons), "min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]}
    made["totalTris"] = sum(v["tris"] for v in made.values() if isinstance(v, dict))
    handle = made["LassoHandle"]
    centre = [round((handle["min"][k] + handle["max"][k]) / 2, 3) for k in range(3)]
    size = [round(handle["max"][k] - handle["min"][k], 3) for k in range(3)]
    made["handleCentre"], made["handleSize"] = centre, size
    made["gripFromCentre"] = round(-centre[0], 3)
    # ToolModels.toolFrame points tool Z at the other meshes' average centre, relative to the
    # handle mesh's centre. Here they hang on +Y, so Blender (x, y, z) -> tool (x, z, y).
    others = [made[o.name] for o in objs[1:]]
    head_y = sum((o["min"][1] + o["max"][1]) / 2 for o in others) / len(others)
    made["sideMargin"] = round(head_y - centre[1], 3)
    made["gripSide"] = round(-centre[1], 3)

    def tool_point(x, y, z=0.0):
        return [round(x, 3), round(z, 3), round(y, 3)]

    made["points"] = {
        "RopeOut": tool_point(*LOOP_PIVOT),
        "Honda": tool_point(*HONDA),
        "LoopCentre": tool_point(*LOOP_CENTRE),
        "LoopFar": tool_point(LOOP_CENTRE[0] + LOOP_R, LOOP_CENTRE[1]),
        "CoilCentre": tool_point(*COIL_CENTRE),
        "Butt": tool_point(*BUTT_RING[0]),
    }
    made["pivots"] = {"Loop": tool_point(*LOOP_PIVOT)}
    return made


result = build()
