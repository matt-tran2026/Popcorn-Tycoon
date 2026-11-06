"""Builds the Popcorn Tycoon Pitchfork (Common, catalog #3) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_Pitchfork" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the right hand) is the origin.
  * The handle runs along +X toward the head. The three prongs lie flat in the X/Y plane;
    Z is their thickness. Blender (x, y, z) -> tool frame (x, z, y).
  * Colours are vertex colours on one white material.

Reference: the creator's render (weathered wooden shaft, dark steel ferrule, three curved steel
prongs with the outer pair bowing out and turning slightly in at the tips). Only the tool is
modelled; the stump is staging.

Meshes (each becomes one MeshPart):
  PitchforkHandle  long wooden shaft with a rounded butt  -> the Tool's Handle, Material Wood
  PitchforkHead    ferrule + three prongs                 -> welded to the Handle, Material Metal
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_Pitchfork"
rng = random.Random(11)  # Fixed seed: grain and hammered steel come out the same every build.


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


WOOD = (150, 108, 70)
WOOD_DARK = (110, 76, 46)
WOOD_LIGHT = (176, 131, 88)
IRON = (92, 98, 106)
IRON_LIGHT = (134, 141, 150)
STEEL = (186, 194, 204)
STEEL_DARK = (128, 137, 148)
STEEL_LIGHT = (226, 231, 236)
TIP = (246, 248, 250)

# Design points (Blender coordinates). The grip is the origin.
BUTT_X = -1.56          # rounded end of the shaft
SHAFT_END_X = 2.56      # shaft runs into the ferrule
FERRULE = (2.42, 2.98)  # dark steel collar
SPLIT_X = 2.95          # prongs leave the ferrule here
HEAD_HALF_WIDTH = 0.54  # outer prongs at their widest
TIP_X = 4.52            # middle prong tip


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
    bm = bmesh.new()
    colours = []
    # Long, slightly swelling shaft: a worn rounded butt, a fuller section where the hands go,
    # thinning a little toward the ferrule.
    profile = [(BUTT_X, 0.05), (BUTT_X + 0.03, 0.13), (BUTT_X + 0.1, 0.175), (BUTT_X + 0.22, 0.17),
               (-0.9, 0.158), (-0.2, 0.164), (0.5, 0.16), (1.3, 0.152), (2.0, 0.146), (SHAFT_END_X, 0.142)]
    segments = 12
    grain = [rng.uniform(-0.12, 0.12) for _ in range(segments)]

    def colour(i, s, x):
        base = WOOD_DARK if i <= 2 else WOOD  # Darker, handled butt.
        if i > 2 and s % 4 == 1:
            base = WOOD_LIGHT  # Lighter grain streaks along the shaft.
        if i > 2 and s % 6 == 4:
            base = WOOD_DARK
        k = 1 + grain[s] + rng.uniform(-0.04, 0.04)
        return tuple(max(0, min(255, c * k)) for c in base)

    rings = lathe(bm, profile, segments, colours, colour)
    cap(bm, rings[0], BUTT_X - 0.005, colours, WOOD_DARK, -1)
    cap(bm, rings[-1], SHAFT_END_X, colours, WOOD_DARK, 1)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "PitchforkHandle", lambda i, co: colours[i])


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3


def prong_path(side):
    """Centre line of one prong as a list of points. side = 0 (middle), +1 or -1 (outer)."""
    if side == 0:
        a, b = Vector((SPLIT_X - 0.05, 0, 0)), Vector((TIP_X, 0, 0.06))
        return [a.lerp(b, i / 14) + Vector((0, 0, 0.05 * math.sin(math.pi * i / 14) ** 2)) for i in range(15)]
    w = HEAD_HALF_WIDTH * side
    # Out of the ferrule, bowing outward, then forward with the tip turning slightly in and up,
    # like the reference's hand-forged tines.
    first = [bezier(Vector((SPLIT_X - 0.05, 0.06 * side, 0)), Vector((SPLIT_X + 0.3, 0.05 * side, 0)),
                    Vector((SPLIT_X + 0.22, w, 0)), Vector((SPLIT_X + 0.62, w, 0.01)), i / 7) for i in range(8)]
    second = [bezier(Vector((SPLIT_X + 0.62, w, 0.01)), Vector((SPLIT_X + 1.05, w * 1.0, 0.02)),
                     Vector((TIP_X - 0.45, w * 0.96, 0.04)), Vector((TIP_X - 0.12, w * 0.84, 0.1)), i / 7) for i in range(1, 8)]
    return first + second


def build_head():
    bm = bmesh.new()
    colours = []
    up = Vector((0, 0, 1))
    sides = 6
    for side in (0, 1, -1):
        path = prong_path(side)
        count = len(path)
        rings = []
        for i, centre in enumerate(path):
            t = i / (count - 1)
            ahead = path[min(i + 1, count - 1)] - path[max(i - 1, 0)]
            forward = ahead.normalized()
            across = up.cross(forward).normalized()
            normal = forward.cross(across).normalized()
            # Thick where the prong leaves the ferrule, tapering to a sharp tip. Slightly
            # flattened (wider than tall), as forged tines are.
            radius = 0.1 * (1 - t) ** 0.6 + 0.032
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                co = centre + across * math.cos(a) * radius * 1.1 + normal * math.sin(a) * radius * 0.85
                ring.append(bm.verts.new(co))
                if t > 0.82:
                    rgb = TIP
                elif math.sin(a) > 0.3:
                    rgb = STEEL_LIGHT  # Polished top where the light catches.
                elif math.sin(a) < -0.3:
                    rgb = STEEL_DARK
                else:
                    rgb = STEEL
                colours.append(jitter(rgb, 0.06 if rgb == STEEL else 0.03))
            rings.append(ring)
        for i in range(count - 1):
            for s in range(sides):
                q = (s + 1) % sides
                bm.faces.new((rings[i][s], rings[i][q], rings[i + 1][q], rings[i + 1][s]))
        tip = bm.verts.new(path[-1] + (path[-1] - path[-2]).normalized() * 0.2)
        colours.append(TIP)
        for s in range(sides):
            q = (s + 1) % sides
            bm.faces.new((rings[-1][s], rings[-1][q], tip))
        bm.faces.new(list(reversed(rings[0])))

    # Dark steel ferrule with two raised rings, over the end of the shaft (like the reference's
    # socket collar), closed at the prong end.
    a, b = FERRULE
    ferrule = [(a, 0.0), (a, 0.172), (a + 0.03, 0.198), (a + 0.08, 0.2), (a + 0.11, 0.186), (b - 0.14, 0.186),
               (b - 0.1, 0.2), (b - 0.05, 0.198), (b - 0.02, 0.17), (b + 0.04, 0.11), (b + 0.05, 0.0)]

    def fcolour(i, s, x):
        return jitter(IRON_LIGHT if i in (3, 7) else IRON, 0.05)

    lathe(bm, ferrule, 12, colours, fcolour)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "PitchforkHead", lambda i, co: colours[i])


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
    for obj in (build_handle(), build_head()):
        obj.data.materials.append(mat)
        col.objects.link(obj)
        lo = [min(v.co[k] for v in obj.data.vertices) for k in range(3)]
        hi = [max(v.co[k] for v in obj.data.vertices) for k in range(3)]
        made[obj.name] = {
            "tris": sum(len(p.vertices) - 2 for p in obj.data.polygons),
            "min": [round(v, 3) for v in lo],
            "max": [round(v, 3) for v in hi],
        }
    handle = made["PitchforkHandle"]
    centre_x = (handle["min"][0] + handle["max"][0]) / 2
    made["gripFromCentre"] = round(-centre_x, 3)  # handle bbox centre -> grip, toward the head
    # Named points in the tool frame (x, z, y from Blender).
    made["points"] = {
        "MiddleTip": [TIP_X + 0.2, 0.08, 0.0],
        "OuterTipL": [TIP_X + 0.06, 0.13, HEAD_HALF_WIDTH * 0.8],
        "OuterTipR": [TIP_X + 0.06, 0.13, -HEAD_HALF_WIDTH * 0.8],
    }
    return made


result = build()
