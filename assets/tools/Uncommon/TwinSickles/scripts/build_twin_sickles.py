"""Builds the Popcorn Tycoon Twin Sickles (Uncommon) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_TwinSickles" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the hand) is the origin.
  * The handle runs along +X toward the blade. The crescent curls in the X/Y plane toward +Y;
    Z is its thickness. Blender (x, y, z) -> tool frame (x, z, y).
  * Colours are vertex colours on one white material.

Reference: the creator's render (two matching polished-steel crescents that sweep almost all
the way round, a dark engraved panel along the spine near the root, ornate silver collars,
leather-strapped wooden handles and silver butt caps). Only the tool is modelled; the stump,
corn and swirl effects are staging.

ONE sickle is modelled. The game holds a copy in each hand. The whole sickle, vertex colours
included, is symmetric about its flat plane (Blender Z = 0), so the left-hand copy is the same
meshes turned 180 degrees: a rotation of a plane-symmetric mesh is its mirror image, and no
second (mirrored) upload is needed. Keep it symmetric when editing.

Meshes (each becomes one MeshPart):
  TwinHandle  leather-strapped wooden grip  -> the Tool's Handle, Material Wood
  TwinBlade   silver collar + crescent      -> welded to the handle, Material Metal
  TwinPommel  silver butt cap               -> welded to the handle, Material Metal
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_TwinSickles"
rng = random.Random(31)  # Fixed seed: steel and wood come out the same every build.


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


STEEL = (204, 210, 218)
STEEL_SHADE = (176, 184, 194)
SPINE = (160, 168, 180)
EDGE = (248, 250, 252)
PANEL = (70, 76, 88)
PANEL_LIGHT = (150, 158, 170)  # silver scrollwork in the engraved panel
SILVER = (196, 202, 210)
SILVER_DARK = (104, 110, 122)
WOOD = (120, 80, 50)
WOOD_DARK = (88, 58, 36)
LEATHER = (96, 58, 34)
LEATHER_DARK = (64, 38, 22)
LEATHER_LIGHT = (128, 82, 50)

# Design points (Blender coordinates). The grip is the origin.
POMMEL = (-1.0, -0.84)     # silver butt cap
WRAP = (-0.86, 0.68)       # leather-strapped wood
COLLAR = (0.64, 0.94)      # ornate silver collar
SHANK = (0.8, 1.05)        # straight root of the blade out of the collar
RX, RY = 0.98, 0.9         # the crescent: a slightly squashed circle, tangent to the handle line
SWEEP = 282                # degrees the blade turns through; the tip ends above the grip
PANEL_TO = 0.4             # the engraved panel runs from the collar to this fraction of the blade


def jitter(rgb, amount):
    k = 1 + rng.uniform(-amount, amount)
    return tuple(max(0, min(255, c * k)) for c in rgb)


def finish(bm, name, colour_of_vertex):
    """Turns a bmesh into a flat-shaded mesh object with per-corner vertex colours."""
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    att = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for loop in me.loops:
        att.data[loop.index].color_srgb = srgb(*colour_of_vertex(loop.vertex_index, me.vertices[loop.vertex_index].co))
    for poly in me.polygons:
        poly.use_smooth = False
    return bpy.data.objects.new(name, me)


def lathe(bm, profile, segments, colour_list, colour_fn):
    """Revolves (x, radius) points around the X axis. Returns rings of verts. An even segment
    count with a vertex at angle 0 keeps the ring symmetric about Z = 0."""
    rings = []
    for i, (x, r) in enumerate(profile):
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
            colour_list.append(colour_fn(i, s, x))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(segments):
            n = (s + 1) % segments
            bm.faces.new((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]))
    return rings


def cap(bm, ring, x, colour_list, rgb, outward):
    centre = bm.verts.new((x, 0, 0))
    colour_list.append(rgb)
    for s in range(len(ring)):
        a, b = ring[s], ring[(s + 1) % len(ring)]
        bm.faces.new((centre, b, a) if outward < 0 else (centre, a, b))


def build_handle():
    """Wood with a leather strap wound round it. The strap is a spiral ridge (its phase turns
    with the angle), so it winds without extra geometry; wood shows in the gaps. The strap
    phase uses |angle| so the colours stay symmetric about the blade's plane."""
    bm = bmesh.new()
    colours = []
    segments, rows = 12, 26
    a0, a1 = WRAP
    pitch = 0.22
    grain = [rng.uniform(-0.08, 0.08) for _ in range(segments // 2 + 1)]
    rings = []
    for i in range(rows):
        x = a0 + (a1 - a0) * i / (rows - 1)
        u = (x - a0) / (a1 - a0)
        swell = 0.146 + 0.014 * math.sin(math.pi * u)
        if i == 0 or i == rows - 1:
            swell -= 0.01
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            mirror = min(s, segments - s)  # same value for +angle and -angle
            folded = 2 * math.pi * mirror / segments
            phase = ((x - pitch * folded / (2 * math.pi)) / pitch) % 1.0
            strap = math.sin(math.pi * min(1.0, phase / 0.62)) if phase < 0.62 else 0.0
            r = swell + 0.026 * strap
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
            if strap <= 0.05:
                k = 1 + grain[mirror]
                rgb = tuple(c * k for c in (WOOD if mirror % 3 else WOOD_DARK))
            elif strap > 0.85 and math.cos(a) > -0.2:
                rgb = LEATHER_LIGHT
            elif strap < 0.4:
                rgb = LEATHER_DARK
            else:
                rgb = LEATHER
            colours.append(jitter(rgb, 0.05))
        rings.append(ring)
    for i in range(rows - 1):
        for s in range(segments):
            n = (s + 1) % segments
            bm.faces.new((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]))
    cap(bm, rings[0], a0, colours, LEATHER_DARK, -1)
    cap(bm, rings[-1], a1, colours, LEATHER_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "TwinHandle", lambda i, co: colours[i])


def build_pommel():
    """Rounded silver butt cap with a dark groove, like the reference's end caps."""
    bm = bmesh.new()
    colours = []
    a, b = POMMEL
    profile = [(a, 0.1), (a + 0.02, 0.165), (a + 0.05, 0.2), (a + 0.09, 0.212), (b - 0.05, 0.2),
               (b - 0.035, 0.18), (b - 0.02, 0.195), (b, 0.17)]

    def colour(i, s, x):
        if i == 5:
            return jitter(SILVER_DARK, 0.04)
        return jitter(EDGE if i in (2, 3) and math.cos(2 * math.pi * s / 12) > 0.3 else SILVER, 0.04)

    rings = lathe(bm, profile, 12, colours, colour)
    cap(bm, rings[0], a - 0.015, colours, SILVER, -1)
    cap(bm, rings[-1], b, colours, SILVER_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "TwinPommel", lambda i, co: colours[i])


def blade_path():
    """Spine line of the blade as a list of points: a straight root out of the collar, then a
    squashed circle tangent to the handle line that turns SWEEP degrees toward +Y, over the top
    and back down toward the grip."""
    path = []
    s0, s1 = SHANK
    for i in range(3):
        path.append(Vector((s0 + (s1 - s0) * i / 3, 0.0, 0.0)))
    centre = Vector((s1, RY, 0.0))
    steps = 34
    for i in range(steps + 1):
        a = math.radians(-90 + SWEEP * i / steps)
        path.append(centre + Vector((RX * math.cos(a), RY * math.sin(a), 0.0)))
    return path


# Cross-section corners: (inward fraction of the width, fraction of the thickness). Inward
# points at the crescent's centre: the rounded spine is outside, the cutting edge inside. The
# section is symmetric top/bottom. Corners 2-3 (and 9-10) are the engraved panel's floor.
SECTION = [
    (0.0, 0.3), (0.12, 0.5), (0.2, 0.5), (0.48, 0.5), (0.56, 0.5), (0.8, 0.3), (1.0, 0.0),
    (0.8, -0.3), (0.56, -0.5), (0.48, -0.5), (0.2, -0.5), (0.12, -0.5), (0.0, -0.3),
]
PANEL_FLOOR = {2, 3, 9, 10}
PANEL_RIM = {1, 4, 8, 11}


def build_blade():
    bm = bmesh.new()
    colours = []
    up = Vector((0, 0, 1))
    path = blade_path()
    count = len(path)
    rings = []
    for i, spine in enumerate(path):
        t = i / (count - 1)
        ahead = (path[min(i + 1, count - 1)] - path[max(i - 1, 0)]).normalized()
        inward = up.cross(ahead).normalized()  # left of the heading = toward the centre
        # Broad root (a little narrower in the collar), tapering to a needle tip.
        neck = min(1.0, 0.78 + i * 0.08)
        width = (0.45 * (1 - t) ** 0.9 + 0.03) * neck
        thick = 0.13 * (1 - 0.7 * t) + 0.025
        # The panel is sunk into both faces near the root and fades out along the blade.
        sink = 0.0 if t > PANEL_TO else min(1.0, (PANEL_TO - t) / 0.06)
        ring = []
        for k, (w, h) in enumerate(SECTION):
            depth = h
            if k in PANEL_FLOOR:
                depth = h * (1 - 0.32 * sink)
            co = spine + inward * w * width + up * depth * thick
            ring.append(bm.verts.new(co))
            if k == 6:
                rgb = EDGE
            elif k in (5, 7):
                rgb = STEEL
            elif k in (0, 12):
                rgb = SPINE
            elif k in PANEL_FLOOR and sink > 0.5:
                # Silver scroll marks every third ring on the dark engraved floor.
                rgb = PANEL_LIGHT if (i % 3 == 1 and k in (3, 9)) or (i % 3 == 2 and k in (2, 10)) else PANEL
            elif k in PANEL_RIM and sink > 0.5:
                rgb = SILVER
            else:
                rgb = STEEL_SHADE if k in (1, 11) else STEEL
            colours.append(jitter(rgb, 0.03))
        rings.append(ring)
    sides = len(SECTION)
    for i in range(count - 1):
        for s in range(sides):
            q = (s + 1) % sides
            bm.faces.new((rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s]))
    last, prev = path[-1], path[-2]
    tip_at = last + (last - prev).normalized() * 0.16 + up.cross((last - prev).normalized()) * 0.015
    tip = bm.verts.new(tip_at)
    colours.append(EDGE)
    for s in range(sides):
        q = (s + 1) % sides
        bm.faces.new((rings[-1][s], rings[-1][q], tip))
    bm.faces.new(list(reversed(rings[0])))

    # Ornate silver collar: a fat central band between two raised lips, with dark grooves.
    a, b = COLLAR
    collar = [(a, 0.17), (a + 0.02, 0.205), (a + 0.05, 0.215), (a + 0.07, 0.195), (a + 0.1, 0.205),
              (b - 0.1, 0.205), (b - 0.07, 0.195), (b - 0.05, 0.215), (b - 0.02, 0.205), (b, 0.16)]

    def ccolour(i, s, x):
        if i in (3, 6):
            return jitter(SILVER_DARK, 0.04)
        if i in (4, 5) and s % 2 == 0:
            return jitter(EDGE, 0.03)  # bright facets on the band, like the reference's pattern
        return jitter(SILVER, 0.04)

    rings_c = lathe(bm, collar, 12, colours, ccolour)
    cap(bm, rings_c[0], a, colours, SILVER_DARK, -1)
    cap(bm, rings_c[-1], b + 0.015, colours, SILVER_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = finish(bm, "TwinBlade", lambda i, co: colours[i])
    return obj, tip_at, path


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


def symmetry_error(obj):
    """Largest distance from a vertex mirrored in Z to the nearest vertex (0 = symmetric)."""
    from mathutils import kdtree
    verts = obj.data.vertices
    tree = kdtree.KDTree(len(verts))
    for v in verts:
        tree.insert(v.co, v.index)
    tree.balance()
    worst = 0.0
    for v in verts:
        _, _, dist = tree.find(Vector((v.co.x, v.co.y, -v.co.z)))
        worst = max(worst, dist)
    return worst


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
    blade, tip_at, path = build_blade()
    made = {}
    for obj in (build_handle(), blade, build_pommel()):
        obj.data.materials.append(mat)
        col.objects.link(obj)
        lo = [min(v.co[k] for v in obj.data.vertices) for k in range(3)]
        hi = [max(v.co[k] for v in obj.data.vertices) for k in range(3)]
        made[obj.name] = {
            "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons),
            "min": [round(v, 3) for v in lo],
            "max": [round(v, 3) for v in hi],
            "symmetryError": round(symmetry_error(obj), 5),
        }
    made["totalTris"] = sum(v["tris"] for v in made.values() if isinstance(v, dict))
    handle = made["TwinHandle"]
    centre_x = (handle["min"][0] + handle["max"][0]) / 2
    made["gripFromCentre"] = round(-centre_x, 3)  # handle bbox centre -> grip, toward the head

    def tool_point(v):
        # Blender (x, y, z) -> tool frame (x, z, y): Y is the thin axis, Z the curl side.
        return [round(v.x, 3), round(v.z, 3), round(v.y, 3)]

    steps_before_arc = 3
    crown = path[steps_before_arc + round(34 * 180 / SWEEP)]  # top of the crescent
    front = path[steps_before_arc + round(34 * 90 / SWEEP)]   # the far front of the curve
    made["points"] = {
        "BladeTip": tool_point(tip_at),
        "BladeFront": tool_point(front),
        "BladeCrown": tool_point(crown),
    }
    return made


result = build()
