"""Builds the Popcorn Tycoon Sickle (Common) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read()). Rebuilds the "Tool_Sickle" collection
from scratch, so it is safe to re-run after tweaking numbers.

Frame and scale (shared by every tool in assets/tools):
  * 1 Blender unit = 1 Roblox stud.
  * The grip point (centre of the hand) is the origin. The handle runs along +X toward the
    blade. The blade lies flat in the X/Y plane; Z is its thickness.
  * Through FBX, Blender +Z becomes Roblox +Y, so in Roblox the blade lies flat in X/Z,
    matching the old part-built sickle and its Tool.Grip.
  * Colours are vertex colours on one white material (the 3D Importer shows them; set the
    MeshParts' Color to white in Studio).

Meshes (each becomes one MeshPart):
  SickleHandle  wood grip with end knob  -> the Tool's Handle, Material Wood
  SickleBlade   iron ferrule + crescent  -> welded to the Handle, Material Metal
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_Sickle"
rng = random.Random(7)  # Fixed seed: the hammered/grain colours come out the same every build.


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


WOOD = (139, 92, 56)
WOOD_DARK = (104, 66, 39)
WOOD_LIGHT = (165, 113, 70)
IRON = (86, 92, 101)
IRON_LIGHT = (126, 133, 142)
STEEL = (186, 194, 204)
SPINE = (136, 145, 157)
EDGE = (246, 248, 250)


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
    obj = bpy.data.objects.new(name, me)
    return obj


def lathe(bm, profile, segments, colour_list, colour_fn):
    """Revolves (x, radius) points around the X axis. Returns rings of verts."""
    rings = []
    for i, (x, r) in enumerate(profile):
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            v = bm.verts.new((x, r * math.cos(a), r * math.sin(a)))
            colour_list.append(colour_fn(i, s, x))
            ring.append(v)
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
    bm = bmesh.new()
    colours = []
    # Chunky, slightly swelling grip with a rounded knob at the butt (x < 0 is the butt end).
    profile = [(-1.12, 0.05), (-1.10, 0.15), (-1.04, 0.225), (-0.94, 0.24), (-0.84, 0.205),
               (-0.70, 0.185), (-0.30, 0.2), (0.15, 0.195), (0.55, 0.178), (0.78, 0.172)]
    segments = 12
    grain = [rng.uniform(-0.12, 0.12) for _ in range(segments)]

    def colour(i, s, x):
        base = WOOD_DARK if i <= 3 else WOOD  # Darker, worn knob.
        if i > 3 and s % 4 == 1:
            base = WOOD_LIGHT  # Lighter grain streaks running along the handle.
        k = 1 + grain[s] + rng.uniform(-0.04, 0.04)
        return tuple(max(0, min(255, c * k)) for c in base)

    rings = lathe(bm, profile, segments, colours, colour)
    cap(bm, rings[0], -1.13, colours, WOOD_DARK, -1)
    cap(bm, rings[-1], 0.78, colours, WOOD_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "SickleHandle", lambda i, co: colours[i])


def blade_frames():
    """Centre-line frames for the blade: (outer spine point, inward unit vector, t 0..1)."""
    heel_u, radius = 1.18, 1.12
    sweep_from, sweep_to = -90.0, 158.0
    frames = []
    # Tang: straight out of the ferrule, spine on the -Y side, edge facing +Y.
    for u in (0.86, 1.0):
        frames.append((Vector((u, 0, 0)), Vector((0, 1, 0))))
    steps = 30
    centre = Vector((heel_u, radius, 0))
    for i in range(steps + 1):
        a = math.radians(sweep_from + (sweep_to - sweep_from) * i / steps)
        # A slightly squashed circle reads more like a hand-forged crescent than a perfect ring.
        outward = Vector((math.cos(a) * 1.0, math.sin(a) * 0.93, 0))
        point = centre + Vector((outward.x * radius, outward.y * radius, 0))
        frames.append((point, -outward.normalized()))
    count = len(frames)
    return [(p, n, i / (count - 1)) for i, (p, n) in enumerate(frames)]


def build_blade():
    bm = bmesh.new()
    colours = []
    frames = blade_frames()
    rings = []
    phase = rng.uniform(0, math.tau)
    for i, (spine, inward, t) in enumerate(frames):
        # A narrow neck out of the ferrule swells to a broad heel, then tapers to a needle tip.
        neck = min(1.0, 0.45 + i * 0.22)
        width = (0.44 * (1 - t) ** 0.75 + 0.035) * neck
        # Hand-forged spine: a gentle low-frequency wave, not random chips.
        wobble = 0.0 if t < 0.1 or t > 0.9 else 0.018 * math.sin(t * 23 + phase)
        thick = 0.14 * (1 - 0.65 * t) + 0.02
        spine = spine - inward * wobble
        up = Vector((0, 0, 1))
        section = [
            (spine + up * thick / 2, SPINE),
            (spine + inward * width * 0.55 + up * thick * 0.36, STEEL),
            (spine + inward * width, EDGE),
            (spine + inward * width * 0.55 - up * thick * 0.36, STEEL),
            (spine - up * thick / 2, SPINE),
        ]
        ring = []
        for co, rgb in section:
            ring.append(bm.verts.new(co))
            colours.append(jitter(rgb, 0.07) if rgb == STEEL else jitter(rgb, 0.03))
        rings.append(ring)
    n = len(rings[0])
    for i in range(len(rings) - 1):
        for s in range(n):
            q = (s + 1) % n
            bm.faces.new((rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s]))
    # Needle tip: close the last ring to a point just past it.
    last_spine, last_in, _ = frames[-1]
    prev_spine = frames[-2][0]
    tip = bm.verts.new(last_spine + (last_spine - prev_spine).normalized() * 0.16 + last_in * 0.02)
    colours.append(EDGE)
    for s in range(n):
        q = (s + 1) % n
        bm.faces.new((rings[-1][s], rings[-1][q], tip))
    # Flat end inside the ferrule.
    bm.faces.new(list(reversed(rings[0])))

    # Iron ferrule: a collar with two raised rings, over the tang.
    ferrule = [(0.70, 0.0), (0.70, 0.2), (0.72, 0.232), (0.76, 0.24), (0.80, 0.222), (0.95, 0.222),
               (0.99, 0.24), (1.03, 0.232), (1.05, 0.2), (1.05, 0.0)]
    segments = 12

    def fcolour(i, s, x):
        return jitter(IRON_LIGHT if i in (3, 7) else IRON, 0.05)

    lathe(bm, ferrule, segments, colours, fcolour)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "SickleBlade", lambda i, co: colours[i])


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
    for obj in (build_handle(), build_blade()):
        obj.data.materials.append(mat)
        col.objects.link(obj)
        made[obj.name] = {
            "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons),
            "dims": [round(d, 3) for d in obj.dimensions],
        }
    return made


result = build()
