"""Builds the Popcorn Tycoon Harvest Hook (Common, catalog #4) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_HarvestHook" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the right hand) is the origin.
  * The handle runs along +X toward the head. The hook curls in the X/Y plane toward +Y;
    Z is its thickness. Blender (x, y, z) -> tool frame (x, z, y).
  * Colours are vertex colours on one white material.

Reference: the creator's render (dark hand-forged iron hook shaped like a question mark, a
dark iron ferrule, a spiral leather-wrapped handle and an iron butt cap). Only the tool is
modelled; the stump is staging.

Meshes (each becomes one MeshPart):
  HookHandle  leather-wrapped grip           -> slides on the Reach motor, Material Leather
  HookBlade   ferrule + shank + curled hook  -> welded to the handle, Material Metal
  HookPommel  iron butt cap                  -> welded to the handle, Material Metal
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_HarvestHook"
rng = random.Random(23)  # Fixed seed: hammered iron and leather come out the same every build.


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


IRON = (64, 68, 74)
IRON_DARK = (44, 47, 52)
IRON_LIGHT = (100, 106, 114)
STEEL_WORN = (150, 157, 166)
EDGE = (196, 202, 210)
FERRULE = (72, 76, 82)
FERRULE_LIGHT = (112, 118, 126)
LEATHER = (107, 64, 38)
LEATHER_DARK = (70, 41, 24)
LEATHER_LIGHT = (134, 84, 51)

# Design points (Blender coordinates). The grip is the origin.
POMMEL = (-1.13, -0.9)     # iron butt cap
WRAP = (-0.92, 0.74)       # leather wrap
FERRULE_X = (0.7, 1.08)    # iron collar
SHANK_START = Vector((0.98, 0.0, 0.0))
CURL_START = Vector((1.78, -0.08, 0.0))  # the shank dips a little away from the curl, as forged
CURL_RADIUS = 1.04
CURL_SWEEP = 262           # degrees the hook turns through (a question mark)
CURL_SHRINK = 0.2          # the curl tightens toward the tip


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
    """Revolves (x, radius) points around the X axis. Returns rings of verts."""
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
    """Leather wrap as a spiral: the ridge phase turns with the angle, so the bands wind round
    the grip without extra geometry. Grooves are darker, ridge tops catch the light."""
    bm = bmesh.new()
    colours = []
    segments, rows = 12, 26
    a0, a1 = WRAP
    pitch = 0.205
    rings = []
    for i in range(rows):
        x = a0 + (a1 - a0) * i / (rows - 1)
        u = (x - a0) / (a1 - a0)
        swell = 0.152 + 0.012 * math.sin(math.pi * u)
        if i == 0 or i == rows - 1:
            swell -= 0.012  # tucked ends under the cap and ferrule
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            phase = ((x - pitch * a / (2 * math.pi)) / pitch) % 1.0
            ridge = math.sin(math.pi * phase) ** 0.7
            r = swell + 0.024 * ridge
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
            if ridge < 0.35:
                rgb = LEATHER_DARK
            elif ridge > 0.85 and math.sin(a) > 0.2:
                rgb = LEATHER_LIGHT
            else:
                rgb = LEATHER
            colours.append(jitter(rgb, 0.06))
        rings.append(ring)
    for i in range(rows - 1):
        for s in range(segments):
            n = (s + 1) % segments
            bm.faces.new((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]))
    cap(bm, rings[0], a0, colours, LEATHER_DARK, -1)
    cap(bm, rings[-1], a1, colours, LEATHER_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "HookHandle", lambda i, co: colours[i])


def build_pommel():
    bm = bmesh.new()
    colours = []
    a, b = POMMEL
    profile = [(a, 0.12), (a + 0.025, 0.185), (a + 0.07, 0.205), (b - 0.07, 0.205), (b - 0.03, 0.19), (b, 0.165)]

    def colour(i, s, x):
        return jitter(FERRULE_LIGHT if i in (2, 3) and math.sin(2 * math.pi * s / 12) > 0 else FERRULE, 0.06)

    rings = lathe(bm, profile, 12, colours, colour)
    cap(bm, rings[0], a - 0.012, colours, IRON_DARK, -1)
    cap(bm, rings[-1], b, colours, IRON_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "HookPommel", lambda i, co: colours[i])


def hook_path():
    """Centre line of the hook as (point, sharpness) pairs. Sharpness 0 on the round shank,
    1 where the inner edge of the curl is ground to a cutting edge."""
    path = []
    # Shank: out of the ferrule, dipping slightly away from the curl.
    for i in range(4):
        t = i / 4
        p = SHANK_START.lerp(CURL_START, t) + Vector((0, -0.05 * math.sin(math.pi * t), 0))
        path.append((p, 0.0))
    # Curl: a tightening circle that turns toward +Y, over the top and back toward the handle.
    centre = CURL_START + Vector((0, CURL_RADIUS, 0))
    steps = 28
    for i in range(steps + 1):
        u = i / steps
        theta = math.radians(CURL_SWEEP * u)
        r = CURL_RADIUS * (1 - CURL_SHRINK * u)
        p = centre + Vector((r * math.sin(theta), -r * math.cos(theta), 0))
        path.append((p, max(0.0, min(1.0, (u - 0.35) * 2.5))))
    return path


# (inward, up) of each section corner as fractions of the width and thickness. Inward points
# at the curl's centre: the spine is outside, the ground edge inside.
SECTION = [(-0.5, 0.32), (-0.05, 0.5), (0.3, 0.42), (0.5, 0.0), (0.3, -0.42), (-0.05, -0.5), (-0.5, -0.32)]


def build_blade():
    bm = bmesh.new()
    colours = []
    up = Vector((0, 0, 1))
    path = hook_path()
    count = len(path)
    rings = []
    for i, (centre, sharp) in enumerate(path):
        u = i / (count - 1)
        ahead = (path[min(i + 1, count - 1)][0] - path[max(i - 1, 0)][0]).normalized()
        inward = up.cross(ahead).normalized()  # left of the heading = toward the curl centre
        # A thick forged bar (the reference is a bar, not a blade) that keeps its weight round
        # the curl and only thins over the last third to a needle tip. A slow ripple in the
        # width reads as hand forging.
        width = (0.25 * (1 - u ** 2.4) + 0.045) * (1 + 0.06 * math.sin(9 * u + 0.6))
        thick = (0.2 * (1 - u ** 2.0) + 0.045) * (1 + 0.05 * math.sin(7 * u + 1.9))
        hammer = rng.uniform(-0.1, 0.1)
        ring = []
        for k, (n, b) in enumerate(SECTION):
            if k in (2, 4):
                b = b * (1 - 0.55 * sharp)  # bevels close in toward the ground edge
            co = centre + inward * n * width + up * b * thick
            ring.append(bm.verts.new(co))
            if k == 3:
                rgb = EDGE if sharp > 0.5 else STEEL_WORN
            elif k in (2, 4):
                rgb = STEEL_WORN if sharp > 0.5 else IRON_LIGHT
            elif k == 1:
                rgb = IRON_LIGHT  # top face catches the light
            elif k in (0, 6):
                rgb = IRON_DARK  # blackened spine
            else:
                rgb = IRON
            c = jitter(rgb, 0.05)
            colours.append(tuple(max(0, min(255, v * (1 + hammer))) for v in c))
        rings.append(ring)
    sides = len(SECTION)
    for i in range(count - 1):
        for s in range(sides):
            q = (s + 1) % sides
            bm.faces.new((rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s]))
    last, prev = path[-1][0], path[-2][0]
    tip_at = last + (last - prev).normalized() * 0.24
    tip = bm.verts.new(tip_at)
    colours.append(EDGE)
    for s in range(sides):
        q = (s + 1) % sides
        bm.faces.new((rings[-1][s], rings[-1][q], tip))
    bm.faces.new(list(reversed(rings[0])))

    # Dark iron ferrule with a raised lip at each end, closed toward the hook.
    a, b = FERRULE_X
    ferrule = [(a, 0.168), (a + 0.03, 0.198), (a + 0.08, 0.2), (a + 0.1, 0.186), (b - 0.12, 0.186),
               (b - 0.09, 0.198), (b - 0.04, 0.196), (b, 0.15)]

    def fcolour(i, s, x):
        return jitter(FERRULE_LIGHT if i in (2, 5) else FERRULE, 0.05)

    rings_f = lathe(bm, ferrule, 12, colours, fcolour)
    cap(bm, rings_f[0], a, colours, IRON_DARK, -1)
    cap(bm, rings_f[-1], b + 0.02, colours, IRON_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = finish(bm, "HookBlade", lambda i, co: colours[i])
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
        }
    made["totalTris"] = sum(v["tris"] for v in made.values() if isinstance(v, dict))
    handle = made["HookHandle"]
    centre_x = (handle["min"][0] + handle["max"][0]) / 2
    made["gripFromCentre"] = round(-centre_x, 3)  # handle bbox centre -> grip, toward the head

    def tool_point(v):
        # Blender (x, y, z) -> tool frame (x, z, y): Y is the thin axis, Z the curl side.
        return [round(v.x, 3), round(v.z, 3), round(v.y, 3)]

    crown = path[4 + 14][0]  # the top of the curl, where it turns back
    made["points"] = {
        "HookTip": tool_point(tip_at),
        "HookCrown": tool_point(crown),
        "CurlCentre": tool_point(CURL_START + Vector((0, CURL_RADIUS * 0.92, 0))),
    }
    return made


result = build()
