"""Builds the Popcorn Tycoon Spring-Loaded Picker (Uncommon) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_SpringLoadedPicker"
collection from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the centre of the D handle's rear bar, where
    the right hand closes) is the origin.
  * The barrel runs along +X at height AXIS_Y. The side profile lies in the X/Y plane (Y up in
    the side view) and Z is the thickness, so the claw fingers are flat plates in X/Y.
  * Colours are vertex colours on one white material, one flat colour per face.

Reference: the creator's render (a red saw-style D handle with a trigger and a side lever, a big
steel coil spring between two red collars, a grey slide bar under the coil, a red nose and a
two-finger steel claw with orange kernel grip pads). Only the tool is modelled; the stump, corn
and motion swirls are staging. Design canvas: "Spring-Loaded Picker — Tool Design"
(https://claude.ai/artifact/3cB9iuzciMRSf13CMkNuME).

Style: built like the creator's weapon pack (as the Long Scythe and Hedge Trimmer): flat extruded
plates and chunky low-poly solids, a darker plate slightly bigger than the face plate for a
cartoon outline, layered inset plates. Red plastic parts are SmoothPlastic in Roblox, steel Metal.

Meshes (each becomes one MeshPart):
  PickerHandle      D grip, housing, rear collar, trigger, slide bar, bolts  -> the Tool's Handle
  PickerLatch       side release lever                                      -> Motor6D "Latch"
  PickerSpring      the coil                                                -> Motor6D "Spring" (stretches)
  PickerRod         plunger rod, clevis and jaw bolts                       -> Motor6D "Plunger" (slides)
  PickerHead        front collar, nose and lugs                             -> welded to PickerRod
  PickerJawTop      upper finger + kernel pad                               -> Motor6D "JawTop"
  PickerJawBottom   lower finger + kernel pad                               -> Motor6D "JawBottom"
"""
import math

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_SpringLoadedPicker"


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


# Paint (the design canvas's vertex colours).
RED = (217, 52, 43)
RED_LIGHT = (240, 90, 72)
RED_DARK = (158, 32, 25)
OUTLINE = (110, 20, 16)
STEEL = (180, 188, 198)
STEEL_LIGHT = (220, 225, 230)
STEEL_DARK = (110, 119, 130)
IRON = (125, 133, 143)
BOLT = (201, 207, 214)
TRIGGER = (60, 65, 73)
KERNEL = (227, 154, 59)
KERNEL_LIGHT = (246, 196, 92)
KERNEL_DARK = (168, 96, 30)

# Styles: (side colour, colour of faces facing +Y (lit top), colour facing -Y (underside)).
S_RED = (RED, RED_LIGHT, RED_DARK)
S_OUTLINE = (OUTLINE, OUTLINE, OUTLINE)
S_STEEL = (STEEL, STEEL_LIGHT, STEEL_DARK)
S_COIL = (STEEL, STEEL_LIGHT, STEEL_DARK)
S_IRON = (IRON, IRON, STEEL_DARK)
S_BOLT = (BOLT, BOLT, STEEL_DARK)
S_TRIGGER = (TRIGGER, TRIGGER, TRIGGER)
S_KERNEL = (KERNEL, KERNEL_LIGHT, KERNEL_DARK)
S_KERNEL_BUMP = (KERNEL_LIGHT, KERNEL_LIGHT, KERNEL)

# Design points (Blender coordinates).
AXIS_Y = 0.6                      # barrel axis height above the grip
LOOP = [(0.95, 0.71), (-0.14, 0.71), (0.13, -0.7), (0.76, -0.7), (0.86, 0.12)]  # D-loop centre line corners
LOOP_RADII = (0.0, 0.24, 0.2, 0.14, 0.1)  # fillet per corner: a squared saw grip, not a ring
LOOP_HALF = 0.18                  # half width of the loop's bars
LOOP_Z = 0.2                      # half thickness of the loop
HOUSING = (0.7, -0.02, 1.3, 1.06) # x0, y0, x1, y1
REAR_COLLAR = (1.28, 1.5, 0.52)   # x0, x1, radius
SPRING_X = (1.5, 3.0)             # coil rear and front end (rest length 1.5)
SPRING_R = 0.34                   # coil radius to the wire centre
WIRE_R = 0.075
TURNS = 6
SEG_PER_TURN = 8
WIRE_SIDES = 6
FRONT_COLLAR = (3.0, 3.22, 0.46)
NOSE = (3.22, 3.54, 0.18)
CLEVIS = (3.5, 3.8, 0.26, 0.15)  # x0, x1, half height, half thickness
JAW_PIVOT = (3.67, 0.15)          # (x, height above the axis); the bottom jaw mirrors it
JAW_LINE = [(3.67, 0.15), (4.02, 0.45), (4.38, 0.52), (4.53, 0.33)]  # top finger centre line (x, dy)
LATCH_PIVOT = (0.98, 0.44)
LATCH_TIP = (0.82, 0.1)
SLIDE = (1.0, 2.3, 0.02, 0.16, -0.26, -0.12)  # x0, x1, y0, y1, z0, z1 (on the -Z side, seen in the reference view)


class Builder:
    """Collects faces with a colour style; colours are picked from each face's normal at the end."""

    def __init__(self):
        self.bm = bmesh.new()
        self.styles = []
        self.layer = self.bm.faces.layers.int.new("style")

    def face(self, verts, style):
        f = self.bm.faces.new(verts)
        if style not in self.styles:
            self.styles.append(style)
        f[self.layer] = self.styles.index(style)
        return f

    def finish(self, name):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")
        bm.normal_update()
        cols = []
        for f in bm.faces:
            base, up, down = self.styles[f[self.layer]]
            ny = f.normal.y
            cols.append(up if ny > 0.55 else (down if ny < -0.55 else base))
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        att = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for poly in me.polygons:
            for li in poly.loop_indices:
                att.data[li].color_srgb = srgb(*cols[poly.index])
            poly.use_smooth = False
        return bpy.data.objects.new(name, me)


def ccw(pts):
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    return pts if area > 0 else list(reversed(pts))


def rounded_rect(x0, y0, x1, y1, radii, grow=0.0, seg=3):
    """Points of a rounded rectangle (CCW), each corner its own radius, grown outward by `grow`."""
    x0, y0, x1, y1 = x0 - grow, y0 - grow, x1 + grow, y1 + grow
    if isinstance(radii, (int, float)):
        radii = (radii,) * 4
    corners = (((x0, y0), 180), ((x1, y0), 270), ((x1, y1), 0), ((x0, y1), 90))
    pts = []
    for ((cx, cy), a0), r in zip(corners, radii):
        r = max(0.0, r + grow)
        sx = 1 if a0 in (180, 90) else -1
        sy = 1 if a0 in (180, 270) else -1
        ccx, ccy = cx + sx * r, cy + sy * r
        if r < 1e-4:
            pts.append((cx, cy))
            continue
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((ccx + r * math.cos(a), ccy + r * math.sin(a)))
    return pts


def plate(b, pts, z0, z1, style):
    """Extrudes a 2D (x, y) polygon into a closed slab from z0 to z1."""
    pts = ccw(pts)
    lo = [b.bm.verts.new((p[0], p[1], z0)) for p in pts]
    hi = [b.bm.verts.new((p[0], p[1], z1)) for p in pts]
    b.face(list(reversed(lo)), style)
    b.face(hi, style)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        b.face((lo[i], lo[j], hi[j], hi[i]), style)


def chaikin(pts, rounds=2):
    """Corner-cutting on a closed polygon: rounds the corners, keeps the edges' middles."""
    for _ in range(rounds):
        out = []
        n = len(pts)
        for i in range(n):
            p, q = pts[i], pts[(i + 1) % n]
            out.append((0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]))
            out.append((0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1]))
        pts = out
    return pts


def fillet(pts, radii, seg=3):
    """Rounds each corner of a closed polygon with its own radius (0 keeps it sharp)."""
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        r = radii[i]
        if r <= 0:
            out.append(tuple(p1))
            continue
        d0, d1 = (p0 - p1).normalized(), (p2 - p1).normalized()
        half = math.acos(max(-1.0, min(1.0, d0.dot(d1)))) / 2
        t = r / math.tan(half)
        a, c = p1 + d0 * t, p1 + d1 * t
        centre = p1 + (d0 + d1).normalized() * (r / math.sin(half))
        a0 = math.atan2(a.y - centre.y, a.x - centre.x)
        a1 = math.atan2(c.y - centre.y, c.x - centre.x)
        sweep = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(seg + 1):
            ang = a0 + sweep * k / seg
            out.append((centre.x + r * math.cos(ang), centre.y + r * math.sin(ang)))
    return out


def offset_closed(pts, d):
    """Mitred offset of a CCW closed polygon (outward for d > 0)."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0, e1 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n0, n1 = Vector((e0.y, -e0.x)), Vector((e1.y, -e1.x))
        m = (n0 + n1).normalized()
        scale = d / max(0.3, m.dot(n1))
        out.append((p1.x + m.x * scale, p1.y + m.y * scale))
    return out


def ring_plate(b, centre, half, z0, z1, style):
    """A closed band (the D loop) of width 2*half around a closed centre line, z0..z1 thick."""
    centre = ccw(centre)
    outer, inner = offset_closed(centre, half), offset_closed(centre, -half)
    n = len(centre)
    vo0 = [b.bm.verts.new((p[0], p[1], z0)) for p in outer]
    vo1 = [b.bm.verts.new((p[0], p[1], z1)) for p in outer]
    vi0 = [b.bm.verts.new((p[0], p[1], z0)) for p in inner]
    vi1 = [b.bm.verts.new((p[0], p[1], z1)) for p in inner]
    for i in range(n):
        j = (i + 1) % n
        b.face((vo1[i], vo1[j], vi1[j], vi1[i]), style)
        b.face((vo0[j], vo0[i], vi0[i], vi0[j]), style)
        b.face((vo0[i], vo0[j], vo1[j], vo1[i]), style)
        b.face((vi0[j], vi0[i], vi1[i], vi1[j]), style)


def ribbon(line, w0, w1):
    """Outline polygon of an open centre line with width tapering from w0 to w1."""
    pts = [Vector(p) for p in line]
    left, right = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = Vector((-t.y, t.x))
        w = (w0 + (w1 - w0) * i / (len(pts) - 1)) / 2
        left.append(tuple(p + nrm * w))
        right.append(tuple(p - nrm * w))
    return left + list(reversed(right))


def lathe(b, profile, sides, style, cy=AXIS_Y, phase=0.5):
    """Revolves (x, radius) points round the barrel axis (parallel to X at height cy), with caps."""
    rings = []
    for x, r in profile:
        ring = []
        for s in range(sides):
            a = 2 * math.pi * (s + phase) / sides
            ring.append(b.bm.verts.new((x, cy + r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(sides):
            n = (s + 1) % sides
            b.face((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]), style)
    b.face(list(reversed(rings[0])), style)
    b.face(rings[-1], style)


def disc(b, x0, x1, r, sides, style, chamfer=0.04):
    lathe(b, [(x0, r - chamfer), (x0 + chamfer, r), (x1 - chamfer, r), (x1, r - chamfer)], sides, style)


def hex_bolt(b, x, y, z0, z1, r):
    plate(b, [(x + r * math.cos(math.radians(30 + 60 * k)), y + r * math.sin(math.radians(30 + 60 * k))) for k in range(6)], z0, z1, S_BOLT)


def box(b, x0, x1, y0, y1, z0, z1, style):
    plate(b, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1, style)


def coil(b):
    """The helix: a WIRE_SIDES section swept round the barrel axis TURNS times."""
    x0, x1 = SPRING_X
    steps = TURNS * SEG_PER_TURN
    centre = []
    for k in range(steps + 1):
        u = k / steps
        th = 2 * math.pi * TURNS * u
        x = x0 + WIRE_R + (x1 - x0 - 2 * WIRE_R) * u
        centre.append((Vector((x, AXIS_Y + SPRING_R * math.cos(th), SPRING_R * math.sin(th))), th))
    rings = []
    for k, (p, th) in enumerate(centre):
        q0 = centre[max(k - 1, 0)][0]
        q1 = centre[min(k + 1, steps)][0]
        t = (q1 - q0).normalized()
        u_axis = Vector((0, math.cos(th), math.sin(th)))
        u_axis = (u_axis - t * u_axis.dot(t)).normalized()
        v_axis = t.cross(u_axis).normalized()
        ring = []
        for s in range(WIRE_SIDES):
            a = 2 * math.pi * s / WIRE_SIDES
            ring.append(b.bm.verts.new(p + (u_axis * math.cos(a) + v_axis * math.sin(a)) * WIRE_R))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(WIRE_SIDES):
            n = (s + 1) % WIRE_SIDES
            b.face((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]), S_COIL)
    b.face(list(reversed(rings[0])), S_COIL)
    b.face(rings[-1], S_COIL)


def build_handle():
    b = Builder()
    loop = fillet(LOOP, LOOP_RADII)
    # D loop: dark outline band (wider, thinner) under the red band.
    ring_plate(b, loop, LOOP_HALF + 0.045, -LOOP_Z + 0.05, LOOP_Z - 0.05, S_OUTLINE)
    ring_plate(b, loop, LOOP_HALF, -LOOP_Z, LOOP_Z, S_RED)
    # Housing: outline plate, shell, raised inset (stepped bevel).
    x0, y0, x1, y1 = HOUSING
    radii = (0.08, 0.08, 0.16, 0.12)
    plate(b, rounded_rect(x0, y0, x1, y1, radii, grow=0.05), -0.25, 0.25, S_OUTLINE)
    plate(b, rounded_rect(x0, y0, x1, y1, radii), -0.3, 0.3, S_RED)
    plate(b, rounded_rect(x0, y0, x1, y1, radii, grow=-0.07), -0.34, 0.34, S_RED)
    # Rear collar where the coil seats, and its dark seat ring.
    c0, c1, cr = REAR_COLLAR
    disc(b, c0, c1, cr, 12, S_RED, chamfer=0.05)
    disc(b, c1 - 0.01, c1 + 0.04, cr - 0.08, 12, S_OUTLINE, chamfer=0.01)
    # Trigger hanging from the top bar inside the loop.
    trig = [(0.66, 0.56), (0.5, 0.56), (0.42, 0.38), (0.46, 0.27), (0.54, 0.38), (0.68, 0.44)]
    plate(b, trig, -0.08, 0.08, S_TRIGGER)
    # Slide bar under the coil (reference side, -Z) with a chunky end stop and its bracket.
    sx0, sx1, sy0, sy1, sz0, sz1 = SLIDE
    plate(b, rounded_rect(sx0, sy0, sx1, sy1, 0.04), sz0, sz1, S_STEEL)
    plate(b, rounded_rect(sx1 - 0.04, sy0 - 0.06, sx1 + 0.12, sy1 + 0.06, 0.03), sz0 - 0.02, sz1 + 0.02, S_STEEL)
    box(b, 1.2, 1.4, 0.02, 0.2, sz1 - 0.02, 0.0, S_STEEL)
    # Hex bolts through the top bar and the housing (both sides).
    for z in (1, -1):
        hex_bolt(b, 0.48, 0.71, z * 0.19, z * 0.24, 0.075)
        hex_bolt(b, 1.08, 0.86, z * 0.33, z * 0.38, 0.07)
    return b.finish("PickerHandle")


def build_latch():
    b = Builder()
    px, py = LATCH_PIVOT
    tx, ty = LATCH_TIP
    arm = ribbon([(px, py), (tx, ty)], 0.12, 0.09)
    # On the -Z side of the housing, the side the reference render shows.
    plate(b, arm, -0.39, -0.34, S_STEEL)
    plate(b, rounded_rect(tx - 0.07, ty - 0.07, tx + 0.07, ty + 0.05, 0.03), -0.42, -0.34, S_STEEL)  # thumb knob
    hex_bolt(b, px, py, -0.44, -0.34, 0.075)
    return b.finish("PickerLatch")


def build_spring():
    b = Builder()
    coil(b)
    return b.finish("PickerSpring")


def build_rod():
    b = Builder()
    lathe(b, [(1.3, 0.1), (3.57, 0.1)], 8, S_IRON)
    x0, x1, hh, ht = CLEVIS
    plate(b, rounded_rect(x0, AXIS_Y - hh, x1, AXIS_Y + hh, 0.05), -ht, ht, S_STEEL)
    for side in (1, -1):
        y = AXIS_Y + side * JAW_PIVOT[1]
        for z in (1, -1):
            hex_bolt(b, JAW_PIVOT[0], y, z * ht, z * (ht + 0.06), 0.06)
    return b.finish("PickerRod")


def build_head():
    b = Builder()
    f0, f1, fr = FRONT_COLLAR
    disc(b, f0, f1, fr, 12, S_RED, chamfer=0.05)
    disc(b, f0 - 0.04, f0 + 0.01, fr - 0.08, 12, S_OUTLINE, chamfer=0.01)
    n0, n1, nr = NOSE
    disc(b, n0 - 0.02, n1, nr, 8, S_RED, chamfer=0.03)
    for side in (1, -1):
        y0, y1 = sorted((AXIS_Y + side * 0.17, AXIS_Y + side * 0.31))
        box(b, n0, n0 + 0.17, y0, y1, -0.12, 0.12, S_RED)
    return b.finish("PickerHead")


def build_jaw(name, side):
    b = Builder()
    line = [(x, AXIS_Y + side * dy) for x, dy in JAW_LINE]
    plate(b, ribbon(line, 0.22, 0.13), -0.09, 0.09, S_STEEL)
    plate(b, ribbon(line[:2], 0.3, 0.22), -0.075, 0.075, S_STEEL)  # thicker root round the bolt
    # Kernel grip pad on the inside of the fingertip, with rows of kernel bumps on both faces.
    tx, ty = line[-1]
    px0, px1 = tx - 0.2, tx
    py0, py1 = sorted((ty - side * 0.0, ty - side * 0.15))
    plate(b, rounded_rect(px0, py0, px1, py1, 0.02), -0.1, 0.1, S_KERNEL)
    for i in range(4):
        for z in (1, -1):
            kx = px0 + 0.025 + i * 0.045
            box(b, kx, kx + 0.03, py0 + 0.025, py1 - 0.025, z * 0.1, z * 0.12, S_KERNEL_BUMP)
    return b.finish(name)


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
    objs = (build_handle(), build_latch(), build_spring(), build_rod(), build_head(),
            build_jaw("PickerJawTop", 1), build_jaw("PickerJawBottom", -1))
    for obj in objs:
        obj.data.materials.append(mat)
        col.objects.link(obj)
        lo = [min(v.co[k] for v in obj.data.vertices) for k in range(3)]
        hi = [max(v.co[k] for v in obj.data.vertices) for k in range(3)]
        made[obj.name] = {"tris": len(obj.data.polygons), "min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]}
    made["totalTris"] = sum(v["tris"] for v in made.values() if isinstance(v, dict))
    handle = made["PickerHandle"]
    centre = [round((handle["min"][k] + handle["max"][k]) / 2, 3) for k in range(3)]
    size = [round(handle["max"][k] - handle["min"][k], 3) for k in range(3)]
    made["handleCentre"], made["handleSize"] = centre, size
    made["gripFromCentre"] = round(-centre[0], 3)
    # ToolModels.toolFrame points tool Z at the other meshes' average centre, relative to the
    # handle mesh's centre. Here they sit above it (+Y), so Blender (x, y, z) -> tool (x, z, y)
    # (as the Sickle), and the grip (y = 0) is gripSide = -centre.y along tool Z.
    others = [made[o.name] for o in objs[1:]]
    head_y = sum((o["min"][1] + o["max"][1]) / 2 for o in others) / len(others)
    made["sideMargin"] = round(head_y - centre[1], 3)  # > 0: the head is above the handle centre
    made["gripSide"] = round(-centre[1], 3)

    def tool_point(x, y, z=0.0):
        return [round(x, 3), round(z, 3), round(y, 3)]

    made["points"] = {
        "ClawTip": tool_point(4.58, AXIS_Y),
        "Muzzle": tool_point(FRONT_COLLAR[1], AXIS_Y),
        "SpringMid": tool_point((SPRING_X[0] + SPRING_X[1]) / 2, AXIS_Y),
        "SpringRear": tool_point(SPRING_X[0], AXIS_Y),
    }
    made["pivots"] = {
        "Latch": tool_point(*LATCH_PIVOT),
        "Spring": tool_point(SPRING_X[0], AXIS_Y),
        "Plunger": tool_point(FRONT_COLLAR[0], AXIS_Y),
        "JawTop": tool_point(JAW_PIVOT[0], AXIS_Y + JAW_PIVOT[1]),
        "JawBottom": tool_point(JAW_PIVOT[0], AXIS_Y - JAW_PIVOT[1]),
    }
    made["springLength"] = round(SPRING_X[1] - SPRING_X[0], 3)
    return made


result = build()
