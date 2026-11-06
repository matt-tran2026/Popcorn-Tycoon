"""Builds the Popcorn Tycoon Hedge Trimmer (Uncommon) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_HedgeTrimmer" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the right hand on the rear loop) is the origin.
  * The blade bar runs along +X. The blades lie flat in the X/Y plane with their teeth pointing
    +Y and -Y; Z is their thickness. The housing sits on +Y above the bar, in the same plane, as in
    the reference render. In game the tool frame's Z points toward the bar (Blender -Y), so for
    this tool Blender (x, y, z) -> tool frame (x, z, -y); see build() for gripSide.
  * Colours are vertex colours on one white material.

Reference: the creator's render (a green moulded housing with orange controls and vent panel, a
rear loop handle, a front bow over the housing, a flat hand guard, and a long steel bar with
square teeth on both edges). Only the tool is modelled; the stump, corn and motion swirls are
staging. Design page: "Hedge Trimmer Tool Design" (https://claude.ai/artifact/UmAQrcS2dihvTcuWqPzebb).

Style: built like the creator's weapon pack (as the Long Scythe): flat extruded plates and chunky
low-poly solids, one flat colour per face, a darker plate slightly bigger than the face plate for
a cartoon outline, layered inset plates. Plastic parts are SmoothPlastic in Roblox, steel Metal.

Meshes (each becomes one MeshPart):
  TrimmerHandle       rear loop + trigger                        -> the Tool's Handle
  TrimmerBody         housing, panels, vents, switch, bow, guard  -> welded
  TrimmerBar          gearbox neck, spine rail, rivets            -> welded
  TrimmerBladeTop     upper toothed blade (z 0 .. +0.07)         -> slides along X
  TrimmerBladeBottom  lower toothed blade, half a tooth out of step -> slides along X
"""
import math

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_HedgeTrimmer"


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


# Paint (the design page's tokens).
GREEN = (79, 174, 50)
GREEN_LIGHT = (124, 207, 74)
GREEN_DARK = (47, 122, 34)
ORANGE = (242, 138, 26)
ORANGE_DARK = (196, 98, 12)
VENT = (43, 47, 51)
STEEL = (169, 176, 184)
STEEL_LIGHT = (227, 232, 237)
STEEL_DARK = (107, 115, 124)
RIVET = (76, 83, 91)
NAMEPLATE = (201, 207, 213)

# Styles: (cap/side colour, colour of faces facing +Y (lit top), colour facing -Y (underside)).
S_GREEN = (GREEN, GREEN_LIGHT, GREEN_DARK)
S_GREEN_FLAT = (GREEN, GREEN, GREEN)
S_OUTLINE = (GREEN_DARK, GREEN_DARK, GREEN_DARK)
S_ORANGE = (ORANGE, ORANGE, ORANGE_DARK)
S_ORANGE_RIM = (ORANGE_DARK, ORANGE_DARK, ORANGE_DARK)
S_VENT = (VENT, VENT, VENT)
S_STEEL = (STEEL, STEEL, STEEL)
S_TEETH = (STEEL_LIGHT, STEEL_LIGHT, STEEL)
S_STEEL_DARK = (STEEL_DARK, STEEL_DARK, RIVET)
S_RIVET = (RIVET, RIVET, RIVET)
S_NAMEPLATE = (NAMEPLATE, NAMEPLATE, NAMEPLATE)

# Design points (Blender coordinates).
HOUSING = (0.5, -1.0, 2.0, 0.46)     # side profile box: x0, y0, x1, y1
HOUSING_RADII = (0.08, 0.12, 0.45, 0.38)  # corners: bottom-left, bottom-right, top-right, top-left
BLADE_Y = -0.62                      # centre line of the bar
BLADE_X = (2.15, 4.6)                # blade root, nose
STRIP = 0.2                          # half height of the blade strip
TOOTH = 0.2                          # tooth length
PITCH = 0.3                          # tooth spacing
BOW_X = 1.05                         # mid-housing, so the left hand can reach it from the rear grip
GUARD_X = (1.99, 2.15)
TUBE_SIDES = 8


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
    corners = (  # centre, start angle (bottom-left, bottom-right, top-right, top-left)
        ((x0, y0), 180), ((x1, y0), 270), ((x1, y1), 0), ((x0, y1), 90))
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


def plate(b, pts, w0, w1, style, axis="z"):
    """Extrudes a 2D polygon into a closed slab. axis "z": pts are (x, y), extruded z w0..w1.
    axis "x": pts are (z, y), extruded along x w0..w1 (the hand guard)."""
    pts = ccw(pts)

    def v3(p, w):
        return (p[0], p[1], w) if axis == "z" else (w, p[1], p[0])

    lo = [b.bm.verts.new(v3(p, w0)) for p in pts]
    hi = [b.bm.verts.new(v3(p, w1)) for p in pts]
    b.face(list(reversed(lo)), style)
    b.face(hi, style)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        b.face((lo[i], lo[j], hi[j], hi[i]), style)


def tube(b, path, radius, style, plane_normal, sides=TUBE_SIDES):
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


def arc_points(c, r, a0, a1, steps):
    return [(c[0] + r * math.cos(math.radians(a0 + (a1 - a0) * k / steps)),
             c[1] + r * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]


def build_handle():
    """Rear loop: the grip bar (origin at its centre) runs back, bends down and returns forward
    into the housing's lower back. An orange trigger hangs under the grip inside the loop."""
    b = Builder()
    path2 = [(0.62, 0.0), (-0.3, 0.0)]
    path2 += arc_points((-0.3, -0.3), 0.3, 90, 180, 4)[1:]          # top-back corner
    path2 += [(-0.6, -0.56)]
    path2 += arc_points((-0.3, -0.56), 0.3, 180, 270, 4)[1:]        # bottom-back corner
    path2 += [(0.62, -0.86)]
    tube(b, [(x, y, 0.0) for x, y in path2], 0.15, S_GREEN, (0, 0, 1))
    plate(b, rounded_rect(0.05, -0.38, 0.38, -0.08, (0.1, 0.02, 0.02, 0.02)), -0.09, 0.09, S_ORANGE)
    return b.finish("TrimmerHandle")


def build_body():
    b = Builder()
    x0, y0, x1, y1 = HOUSING
    # Housing: dark outline plate (bigger, thinner), the shell, and a raised inset (stepped bevel).
    plate(b, rounded_rect(x0, y0, x1, y1, HOUSING_RADII, grow=0.06), -0.46, 0.46, S_OUTLINE)
    plate(b, rounded_rect(x0, y0, x1, y1, HOUSING_RADII), -0.52, 0.52, S_GREEN)
    plate(b, rounded_rect(x0, y0, x1, y1, HOUSING_RADII, grow=-0.08), -0.58, 0.58, S_GREEN)
    # Orange side panel with a dark rim and a vent window (both sides; the slab passes through).
    plate(b, rounded_rect(1.22, -0.6, 1.9, -0.1, 0.12, grow=0.04), -0.61, 0.61, S_ORANGE_RIM)
    plate(b, rounded_rect(1.22, -0.6, 1.9, -0.1, 0.12), -0.63, 0.63, S_ORANGE)
    plate(b, rounded_rect(1.34, -0.5, 1.78, -0.2, 0.05), -0.66, 0.66, S_VENT)
    # Two vent slots behind the bow, and the steel nameplate low at the front.
    for vx in (0.62, 0.76):
        plate(b, rounded_rect(vx, 0.0, vx + 0.07, 0.3, 0.03), -0.62, 0.62, S_VENT)
    plate(b, rounded_rect(1.3, -0.92, 1.86, -0.72, 0.03, grow=0.03), -0.6, 0.6, S_RIVET)
    plate(b, rounded_rect(1.3, -0.92, 1.86, -0.72, 0.03), -0.62, 0.62, S_NAMEPLATE)
    # Orange switch on top (a chunky rocker) and a dark base under it.
    plate(b, rounded_rect(1.24, 0.36, 1.6, 0.5, 0.03), -0.24, 0.24, S_VENT)
    plate(b, rounded_rect(1.28, 0.4, 1.56, 0.58, (0.02, 0.02, 0.06, 0.06)), -0.18, 0.18, S_ORANGE)
    # Front bow: a round tube arching over the housing from side to side, in the Y/Z plane.
    bow = [(BOW_X, -0.92, -0.66), (BOW_X, 0.3, -0.66)]
    bow += [(BOW_X, 0.3 + 0.66 * math.sin(math.radians(a)), -0.66 * math.cos(math.radians(a)))
            for a in range(15, 180, 15)]
    bow += [(BOW_X, 0.3, 0.66), (BOW_X, -0.92, 0.66)]
    tube(b, bow, 0.13, S_GREEN, (1, 0, 0))
    # Hand guard: a flat plate across the base of the bar (Y/Z plane), outline plate behind it.
    g0, g1 = GUARD_X
    guard = (-0.64, -1.3, 0.64, 0.3)
    plate(b, rounded_rect(*guard, 0.22, grow=0.06), g0 + 0.03, g1 - 0.03, S_OUTLINE, axis="x")
    plate(b, rounded_rect(*guard, 0.22), g0, g1, S_GREEN_FLAT, axis="x")
    return b.finish("TrimmerBody")


def build_bar():
    b = Builder()
    # Gearbox neck out of the housing's front, under the guard.
    plate(b, rounded_rect(1.9, -0.86, 2.45, -0.4, 0.06), -0.2, 0.2, S_STEEL_DARK)
    # Spine rail over both blades, and rivets through it.
    plate(b, rounded_rect(2.1, BLADE_Y - 0.09, 4.42, BLADE_Y + 0.09, 0.08), -0.13, 0.13, S_STEEL_DARK)
    for x in (2.6, 3.2, 3.8, 4.3):
        plate(b, rounded_rect(x - 0.05, BLADE_Y - 0.05, x + 0.05, BLADE_Y + 0.05, 0.05, seg=1), -0.16, 0.16, S_RIVET)
    return b.finish("TrimmerBar")


def build_blade(name, z0, z1, phase):
    """A flat steel strip with a rounded nose, and square teeth (bright cutting faces) along both
    edges. `phase` shifts the teeth by part of a pitch so the two blades scissor."""
    b = Builder()
    xs, xe = BLADE_X
    cy = BLADE_Y
    strip = [(xs, cy - STRIP), (xe - 0.16, cy - STRIP)]
    strip += arc_points((xe - 0.16, cy), STRIP, -90, 90, 4)[1:-1]
    strip += [(xe - 0.16, cy + STRIP), (xs, cy + STRIP)]
    plate(b, strip, z0, z1, S_STEEL)
    teeth = 0
    x = xs + 0.08 + phase
    while x + 0.16 <= xe - 0.18:
        for side in (1, -1):
            base = cy + side * (STRIP - 0.03)
            tip = cy + side * (STRIP + TOOTH)
            pts = [(x, base), (x + 0.16, base), (x + 0.13, tip), (x + 0.03, tip)]
            plate(b, pts, z0 + 0.005, z1 - 0.005, S_TEETH)
            teeth += 1
        x += PITCH
    return b.finish(name), teeth


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
    top, teeth_top = build_blade("TrimmerBladeTop", 0.0, 0.07, PITCH / 2)
    bottom, teeth_bottom = build_blade("TrimmerBladeBottom", -0.07, 0.0, 0.0)
    made = {}
    for obj in (build_handle(), build_body(), build_bar(), top, bottom):
        obj.data.materials.append(mat)
        col.objects.link(obj)
        lo = [min(v.co[k] for v in obj.data.vertices) for k in range(3)]
        hi = [max(v.co[k] for v in obj.data.vertices) for k in range(3)]
        made[obj.name] = {
            "tris": len(obj.data.polygons),
            "min": [round(v, 3) for v in lo],
            "max": [round(v, 3) for v in hi],
        }
    made["totalTris"] = sum(v["tris"] for v in made.values() if isinstance(v, dict))
    made["teeth"] = [teeth_top, teeth_bottom]
    handle = made["TrimmerHandle"]
    made["handleCentre"] = [round((handle["min"][k] + handle["max"][k]) / 2, 3) for k in range(3)]
    made["gripFromCentre"] = round(-made["handleCentre"][0], 3)

    # In game, ToolModels.toolFrame points Z at the side the other meshes sit on relative to the
    # handle mesh's centre: here below it (Blender -Y, toward the bar). So for this tool
    # Blender (x, y, z) -> tool frame (x, z, -y), and the grip bar (Blender y = 0) sits
    # gripSide = handle centre y along tool Z from the handle mesh's centre.
    others = [made[n] for n in ("TrimmerBody", "TrimmerBar", "TrimmerBladeTop", "TrimmerBladeBottom")]
    head_y = sum((o["min"][1] + o["max"][1]) / 2 for o in others) / len(others)
    made["sideMargin"] = round(made["handleCentre"][1] - head_y, 3)  # > 0: the head is below the handle
    made["gripSide"] = made["handleCentre"][1]

    def tool_point(x, y, z=0.0):
        return [round(x, 3), round(z, 3), round(-y, 3)]

    made["points"] = {
        "BladeTip": tool_point(BLADE_X[1], BLADE_Y),
        "BladeRoot": tool_point(BLADE_X[0] + 0.1, BLADE_Y),
        "BladeMid": tool_point((BLADE_X[0] + BLADE_X[1]) / 2, BLADE_Y),
        "LeftHand": tool_point(BOW_X, 0.96),
        "Motor": tool_point(1.55, -0.3),
    }
    return made


result = build()
