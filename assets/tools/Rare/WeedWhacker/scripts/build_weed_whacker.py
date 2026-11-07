"""Builds the Popcorn Tycoon Weed Whacker (Rare) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_WeedWhacker" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the right hand on the orange trigger grip)
    is the origin. The shaft runs along +X toward the cutting head.
  * The side profile is in the X/Y plane with +Y up (engine top, loop handle). The disc blade
    lies flat in the X/Z plane under the gearhead, so its thin axis is Blender Y.
  * The heat gauge, air filter and loop knob sit on the +Z side, so in game ToolModels.toolFrame
    points tool Z at Blender +Z and, with the blade as `head`, tool Y = Blender +Y: Blender
    (x, y, z) -> tool frame (x, y, z). build() reports the margin as `sideMargin`.
  * Colours are vertex colours on one white material.

Reference: the creator's render (an orange two-stroke engine with dark covers and a grey tank, an
orange trigger grip, a black loop handle, a long grey shaft, an angled gearhead with a guard and a
spinning toothed disc). Only the tool is modelled; the stump, corn, swirls and leaves are staging.
Design canvas: "Weed Whacker Design" (https://claude.ai/artifact/7evSGJm7UZsvKYNcUCZDY2).

Style: built like the creator's weapon pack (as the Hedge Trimmer): flat extruded plates and
chunky low-poly solids, one flat colour per face, a darker plate slightly bigger than the face
plate for a cartoon outline, layered inset plates.

Meshes (each becomes one MeshPart):
  WhackerGrip    trigger housing, trigger, throttle lock         -> the Tool's Handle
  WhackerShaft   tube from the clutch to the gearhead, collars    -> welded (Metal)
  WhackerEngine  housing, cylinder cover, tank, starter, filter   -> Engine motor (vibration)
  WhackerHeat    gauge bezel and five bars (white, tinted in game) -> welded to the engine (Neon)
  WhackerLoop    loop handle, clamp, knob                         -> welded
  WhackerGuard   gearhead and half-round guard                    -> welded
  WhackerBlade   toothed disc, slots, hub, nut                    -> Spin motor
"""
import math

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_WeedWhacker"


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


# Paint (the design canvas's tokens).
ORANGE = (242, 107, 29)
ORANGE_LIGHT = (255, 148, 71)
ORANGE_DARK = (142, 58, 14)
DARK = (43, 47, 54)
DARK_LIGHT = (61, 67, 76)
DARKEST = (30, 33, 38)
TANK = (185, 190, 198)
TANK_LIGHT = (214, 219, 226)
TANK_DARK = (137, 143, 152)
SHAFT = (122, 128, 136)
SHAFT_LIGHT = (160, 166, 174)
SHAFT_DARK = (84, 89, 96)
LOOP = (36, 39, 44)
LOOP_LIGHT = (58, 63, 71)
GEAR = (58, 63, 71)
GEAR_LIGHT = (84, 91, 101)
BLADE = (201, 208, 216)
BLADE_LIGHT = (227, 232, 237)
BLADE_DARK = (110, 115, 122)
TEETH = (240, 244, 248)
HUB = (91, 97, 104)
WHITE = (255, 255, 255)
BEZEL = (43, 47, 54)

# Styles: (side colour, colour of faces facing +Y (lit top), colour facing -Y (underside)).
S_ORANGE = (ORANGE, ORANGE_LIGHT, ORANGE_DARK)
S_ORANGE_OUT = (ORANGE_DARK, ORANGE_DARK, ORANGE_DARK)
S_DARK = (DARK, DARK_LIGHT, DARKEST)
S_FIN = (DARK_LIGHT, DARK_LIGHT, DARK)
S_TANK = (TANK, TANK_LIGHT, TANK_DARK)
S_SHAFT = (SHAFT, SHAFT_LIGHT, SHAFT_DARK)
S_COLLAR = (SHAFT_DARK, SHAFT, DARK)
S_LOOP = (LOOP, LOOP_LIGHT, LOOP)
S_SLEEVE = (LOOP_LIGHT, LOOP_LIGHT, LOOP)
S_GEAR = (GEAR, GEAR_LIGHT, DARK)
S_GEAR_OUT = (DARKEST, DARKEST, DARKEST)
S_BLADE = (BLADE, BLADE_LIGHT, BLADE_DARK)
S_BLADE_OUT = (BLADE_DARK, BLADE_DARK, BLADE_DARK)
S_TEETH = (TEETH, TEETH, BLADE)
S_SLOT = (HUB, HUB, HUB)
S_HUB = (HUB, SHAFT, DARK)
S_NUT = (SHAFT_LIGHT, BLADE_LIGHT, SHAFT)
S_BEZEL = (BEZEL, BEZEL, BEZEL)
S_BAR = (WHITE, WHITE, WHITE)

# Design points (Blender coordinates).
SHAFT_X = (-0.62, 3.62)
SHAFT_R = 0.1
HOUSING = (-1.75, -0.42, -0.8, 0.62)
HOUSING_RADII = (0.12, 0.12, 0.3, 0.25)
LOOP_X = 0.85     # within the left hand's reach from the hip-held grip (forward-kinematics search, Nov 7)
LOOP_TOP = 0.8
HUB_C = (3.9, -0.44)       # disc centre (x, y); the disc lies in the X/Z plane
BLADE_R = 0.78
TEETH_N = 18
GUARD_R = 0.94
ENGINE_PIVOT = (-0.55, 0.0, 0.0)
SIDES = 8


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


def circle(cx, cy, r, n, a0=0.0):
    return [(cx + r * math.cos(a0 + 2 * math.pi * k / n), cy + r * math.sin(a0 + 2 * math.pi * k / n)) for k in range(n)]


def plate(b, pts, w0, w1, style, axis="z"):
    """Extrudes a 2D polygon into a closed slab.
    axis "z": pts are (x, y), extruded along z w0..w1 (side profile plates).
    axis "x": pts are (z, y), extruded along x w0..w1 (plates across the shaft).
    axis "y": pts are (x, z), extruded along y w0..w1 (flat-lying plates: blade, guard)."""
    pts = ccw(pts)

    def v3(p, w):
        if axis == "z":
            return (p[0], p[1], w)
        if axis == "x":
            return (w, p[1], p[0])
        return (p[0], w, p[1])

    lo = [b.bm.verts.new(v3(p, w0)) for p in pts]
    hi = [b.bm.verts.new(v3(p, w1)) for p in pts]
    b.face(list(reversed(lo)), style)
    b.face(hi, style)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        b.face((lo[i], lo[j], hi[j], hi[i]), style)


def tube(b, path, radius, style, plane_normal, sides=SIDES):
    """Sweeps a regular polygon section along a planar 3D path, with end caps. The section's
    first axis is the path plane's normal, so the tube never twists."""
    path = [Vector(p) for p in path]
    u = Vector(plane_normal).normalized()
    rings = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        v = t.cross(u).normalized()
        ring = []
        for s in range(sides):
            a = 2 * math.pi * (s + 0.5) / sides
            ring.append(b.bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * radius))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(sides):
            n = (s + 1) % sides
            b.face((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]), style)
    b.face(list(reversed(rings[0])), style)
    b.face(rings[-1], style)


def lathe(b, profile, styles, sides=SIDES):
    """Revolves (x, radius) points round the X axis (y = z = 0) with end caps. `styles` is one
    style, or one per segment between profile points."""
    rings = []
    for x, r in profile:
        rings.append([b.bm.verts.new((x, r * math.cos(2 * math.pi * (s + 0.5) / sides),
                                      r * math.sin(2 * math.pi * (s + 0.5) / sides))) for s in range(sides)])
    for i in range(len(rings) - 1):
        style = styles[i] if isinstance(styles, list) else styles
        if abs(profile[i][0] - profile[i + 1][0]) < 1e-6 and abs(profile[i][1] - profile[i + 1][1]) < 1e-6:
            continue
        for s in range(sides):
            n = (s + 1) % sides
            b.face((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]), style)
    first = styles[0] if isinstance(styles, list) else styles
    last = styles[-1] if isinstance(styles, list) else styles
    b.face(list(reversed(rings[0])), first)
    b.face(rings[-1], last)


def arc_points(c, r, a0, a1, steps):
    return [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * k / steps)),
             c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]


def build_grip():
    """Orange trigger housing round the shaft (the hand's grip), a dark trigger underneath and
    the throttle lock on top. Grip point = origin, inside the housing on the shaft axis."""
    b = Builder()
    body = (-0.5, -0.2, 0.45, 0.2)
    plate(b, rounded_rect(*body, 0.12, grow=0.05), -0.15, 0.15, S_ORANGE_OUT)
    plate(b, rounded_rect(*body, 0.12), -0.19, 0.19, S_ORANGE)
    for x in (-0.36, -0.22, -0.08):  # grip ribs where the palm goes
        plate(b, rounded_rect(x, -0.13, x + 0.06, 0.13, 0.02), -0.21, 0.21, S_DARK)
    plate(b, [(0.04, -0.19), (0.32, -0.19), (0.27, -0.36), (0.09, -0.38)], -0.07, 0.07, S_DARK)
    plate(b, rounded_rect(-0.32, 0.18, -0.06, 0.36, (0.02, 0.02, 0.07, 0.07)), -0.08, 0.08, S_DARK)
    return b.finish("WhackerGrip")


def build_shaft():
    b = Builder()
    x0, x1 = SHAFT_X
    r = SHAFT_R
    prof = [(x0, r), (0.45, r), (0.45, 0.14), (0.62, 0.14), (0.62, r), (3.33, r), (3.33, 0.14), (3.5, 0.14), (3.5, r), (x1, r)]
    styles = [S_SHAFT, S_COLLAR, S_COLLAR, S_COLLAR, S_SHAFT, S_COLLAR, S_COLLAR, S_COLLAR, S_SHAFT]
    lathe(b, prof, styles)
    return b.finish("WhackerShaft")


def build_engine():
    b = Builder()
    # Clutch bell: an orange cone from the housing's front onto the shaft.
    lathe(b, [(-0.9, 0.3), (-0.74, 0.3), (-0.5, 0.15)], S_ORANGE)
    # Housing: dark outline plate (bigger, thinner), the shell, and a raised inset (stepped bevel).
    x0, y0, x1, y1 = HOUSING
    plate(b, rounded_rect(x0, y0, x1, y1, HOUSING_RADII, grow=0.06), -0.36, 0.36, S_ORANGE_OUT)
    plate(b, rounded_rect(x0, y0, x1, y1, HOUSING_RADII), -0.42, 0.42, S_ORANGE)
    plate(b, rounded_rect(x0, y0, x1, y1, HOUSING_RADII, grow=-0.08), -0.48, 0.48, S_ORANGE)
    # Finned cylinder cover on top, and the spark plug boot behind it.
    plate(b, rounded_rect(-1.56, 0.36, -0.94, 0.78, (0.04, 0.04, 0.12, 0.12)), -0.3, 0.3, S_DARK)
    for x in (-1.46, -1.33, -1.2, -1.07):
        plate(b, rounded_rect(x, 0.6, x + 0.05, 0.88, 0.02), -0.25, 0.25, S_FIN)
    plate(b, rounded_rect(-1.74, 0.6, -1.6, 0.8, 0.05), -0.07, 0.07, S_DARK)
    # Fuel tank under the housing, with its cap at the front.
    plate(b, rounded_rect(-1.66, -0.76, -0.94, -0.38, 0.1), -0.34, 0.34, S_TANK)
    plate(b, rounded_rect(-1.0, -0.66, -0.86, -0.5, 0.04), -0.1, 0.1, S_DARK)
    # Recoil starter cover on the back and its orange pull handle.
    plate(b, rounded_rect(-0.36, -0.3, 0.36, 0.5, 0.14), -1.92, -1.76, S_DARK, axis="x")
    plate(b, rounded_rect(-0.18, 0.04, 0.18, 0.16, 0.05), -2.0, -1.92, S_ORANGE, axis="x")
    # Air filter cover with its screw knob on the +Z side; muffler on -Z.
    plate(b, rounded_rect(-1.56, -0.26, -1.0, 0.28, 0.1), 0.44, 0.6, S_DARK)
    plate(b, circle(-1.28, 0.01, 0.06, 8), 0.6, 0.65, S_COLLAR)
    plate(b, rounded_rect(-1.5, -0.16, -1.06, 0.18, 0.08), -0.54, -0.44, S_COLLAR)
    plate(b, rounded_rect(-1.18, -0.06, -1.1, 0.04, 0.02), -0.57, -0.54, S_DARK)
    return b.finish("WhackerEngine")


def build_heat():
    """The heat gauge on the engine's +Z side: a dark bezel and five white bars. In game the mesh
    is Neon and its Color is tinted cool blue -> amber -> red by the heat (white bars take the tint,
    the dark bezel stays dark)."""
    b = Builder()
    plate(b, rounded_rect(-1.62, 0.32, -0.94, 0.56, 0.05), 0.47, 0.51, S_BEZEL)
    for k in range(5):
        x = -1.57 + 0.12 * k
        plate(b, rounded_rect(x, 0.36, x + 0.09, 0.52, 0.02), 0.47, 0.54, S_BAR)
    return b.finish("WhackerHeat")


def build_loop():
    """Loop handle across the shaft (in the Y/Z plane at LOOP_X): the left hand holds its top.
    A clamp block on the shaft and a tightening knob on the +Z side."""
    b = Builder()
    x = LOOP_X
    top_c = LOOP_TOP - 0.3
    w = 0.34
    path = [(x, 0.1, -w), (x, top_c, -w)]
    path += [(x, top_c + 0.3 * math.sin(math.radians(a)), -w * math.cos(math.radians(a))) for a in range(15, 180, 15)]
    path += [(x, top_c, w), (x, 0.1, w)]
    tube(b, path, 0.08, S_LOOP, (1, 0, 0))
    sleeve = [(x, top_c + 0.3 * math.sin(math.radians(a)), -w * math.cos(math.radians(a))) for a in range(40, 145, 15)]
    tube(b, sleeve, 0.1, S_SLEEVE, (1, 0, 0))
    plate(b, rounded_rect(-0.42, -0.2, 0.42, 0.2, 0.08), x - 0.1, x + 0.1, S_DARK, axis="x")
    plate(b, rounded_rect(0.42, -0.09, 0.54, 0.09, 0.03), x - 0.06, x + 0.06, S_COLLAR, axis="x")
    return b.finish("WhackerLoop")


def build_guard():
    """Angled gearhead at the shaft's end and the half-round guard over the back of the disc."""
    b = Builder()
    gear = [(3.46, 0.15), (3.95, 0.15), (4.08, 0.02), (4.06, -0.3), (3.98, -0.37), (3.8, -0.37), (3.6, -0.17), (3.46, -0.15)]
    plate(b, gear, -0.2, 0.2, S_GEAR)
    plate(b, rounded_rect(3.62, -0.02, 3.98, 0.1, 0.03), -0.22, 0.22, S_GEAR_OUT)
    cx = HUB_C[0]
    # Guard: a flat half ring (X/Z plane) over the back half of the disc, a dark outline plate, and
    # a skirt round its outer edge hanging past the teeth.
    def band(r0, r1, a0, a1, steps=12):
        outer = [(cx + r1 * math.cos(math.radians(a0 + (a1 - a0) * k / steps)), r1 * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]
        inner = [(cx + r0 * math.cos(math.radians(a1 - (a1 - a0) * k / steps)), r0 * math.sin(math.radians(a1 - (a1 - a0) * k / steps))) for k in range(steps + 1)]
        return outer + inner
    plate(b, band(0.26, GUARD_R + 0.05, 112, 248), -0.345, -0.315, S_GEAR_OUT, axis="y")
    plate(b, band(0.3, GUARD_R, 115, 245), -0.37, -0.29, S_GEAR, axis="y")
    plate(b, band(GUARD_R - 0.05, GUARD_R, 115, 245), -0.5, -0.3, S_GEAR, axis="y")
    return b.finish("WhackerGuard")


def build_blade():
    """Toothed steel disc flat in the X/Z plane, centred under the gearhead. Three dark slots and
    the hub make the spin readable; 18 raked teeth round the rim."""
    b = Builder()
    cx, cy = HUB_C
    plate(b, circle(cx, 0.0, BLADE_R + 0.04, 36), cy - 0.015, cy + 0.015, S_BLADE_OUT, axis="y")
    plate(b, circle(cx, 0.0, BLADE_R, 36), cy - 0.03, cy + 0.03, S_BLADE, axis="y")
    step = 2 * math.pi / TEETH_N
    for k in range(TEETH_N):
        a = k * step
        base0 = (cx + (BLADE_R - 0.04) * math.cos(a), (BLADE_R - 0.04) * math.sin(a))
        base1 = (cx + (BLADE_R - 0.04) * math.cos(a + step * 0.85), (BLADE_R - 0.04) * math.sin(a + step * 0.85))
        tip = (cx + (BLADE_R + 0.12) * math.cos(a + step * 0.2), (BLADE_R + 0.12) * math.sin(a + step * 0.2))
        plate(b, [base0, base1, tip], cy - 0.025, cy + 0.025, S_TEETH, axis="y")
    for k in range(3):
        a0 = math.radians(120 * k)
        outer = [(cx + 0.6 * math.cos(a0 + math.radians(d)), 0.6 * math.sin(a0 + math.radians(d))) for d in range(0, 46, 9)]
        inner = [(cx + 0.36 * math.cos(a0 + math.radians(d)), 0.36 * math.sin(a0 + math.radians(d))) for d in range(30, -1, -10)]
        plate(b, outer + inner, cy - 0.036, cy + 0.036, S_SLOT, axis="y")
    plate(b, circle(cx, 0.0, 0.21, 12), cy - 0.06, cy + 0.06, S_HUB, axis="y")
    plate(b, circle(cx, 0.0, 0.11, 6), cy - 0.09, cy + 0.08, S_NUT, axis="y")
    return b.finish("WhackerBlade")


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
    for obj in (build_grip(), build_shaft(), build_engine(), build_heat(), build_loop(), build_guard(), build_blade()):
        obj.data.materials.append(mat)
        col.objects.link(obj)
        lo = [min(v.co[k] for v in obj.data.vertices) for k in range(3)]
        hi = [max(v.co[k] for v in obj.data.vertices) for k in range(3)]
        made[obj.name] = {"tris": len(obj.data.polygons), "min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]}
    meshes = [n for n in made]
    made["totalTris"] = sum(made[n]["tris"] for n in meshes)
    grip = made["WhackerGrip"]
    centre = [round((grip["min"][k] + grip["max"][k]) / 2, 3) for k in range(3)]
    made["handleCentre"] = centre
    made["handleSize"] = [round(grip["max"][k] - grip["min"][k], 3) for k in range(3)]
    made["gripFromCentre"] = round(-centre[0], 3)
    others = [made[n] for n in meshes if n != "WhackerGrip"]
    avg = [sum((o["min"][k] + o["max"][k]) / 2 for o in others) / len(others) for k in range(3)]
    # toolFrame: X toward the others' average (must be ahead of the grip), Z toward their side.
    made["headAhead"] = round(avg[0] - centre[0], 3)
    made["sideMargin"] = round(avg[2] - centre[2], 3)  # > 0: tool Z = Blender +Z
    blade = made["WhackerBlade"]
    made["bladeSize"] = [round(blade["max"][k] - blade["min"][k], 3) for k in range(3)]
    made["points"] = {
        "Hub": [HUB_C[0], HUB_C[1], 0.0],
        "BladeFront": [round(HUB_C[0] + BLADE_R + 0.12, 3), HUB_C[1], 0.0],
        "Spray": [round(HUB_C[0] + 0.5, 3), round(HUB_C[1] - 0.06, 3), 0.0],
        "EngineTop": [-1.25, 0.88, 0.0],
        "Exhaust": [-1.14, -0.01, -0.57],
        "HeatGauge": [-1.28, 0.44, 0.54],
        "LeftHand": [LOOP_X, LOOP_TOP, 0.0],
    }
    made["joints"] = {"Spin": [HUB_C[0], HUB_C[1], 0.0], "Engine": list(ENGINE_PIVOT)}
    return made


result = build()
