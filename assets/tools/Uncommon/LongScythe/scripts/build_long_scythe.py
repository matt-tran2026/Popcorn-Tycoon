"""Builds the Popcorn Tycoon Long Scythe (Uncommon) in Blender 5.2.

Run inside Blender: exec(open(<this file>).read(), ns). Rebuilds the "Tool_LongScythe" collection
from scratch, so it is safe to re-run after tweaking numbers. Sets `result` to a dict.

Frame and scale (shared by every tool in assets/tools, see the vault note "Blender Tool Models"):
  * 1 Blender unit = 1 Roblox stud. The grip point (the right hand) is the origin.
  * The shaft runs along +X toward the blade. The blade lies flat in the X/Y plane and reaches
    toward +Y; Z is its thickness. Blender (x, y, z) -> tool frame (x, z, y).
  * Colours are vertex colours on one white material.

Reference: the creator's render (a long wooden shaft with iron collars and two grip nibs, an
oversized silver crescent with a dark engraved panel along the spine and barbs on its back).
Only the tool is modelled; the stump, corn and wind swirls are staging.

Style: imitates how the creator's weapon pack is built (Nov 6 2026 look at its scythes and axes):
flat, extruded silhouettes instead of swept round sections; solid flat colour per region (no
noise, no gradients); layered plates (a darker, slightly larger outline plate behind a lighter
face plate, and a dark inset panel on top); low-poly octagonal shafts; a chunky, spiky outline
that reads at a distance. In Roblox every mesh is SmoothPlastic, as in the pack.

Meshes (each becomes one MeshPart):
  LongScytheHandle    octagonal wooden shaft      -> the Tool's Handle
  LongScytheBlade     crescent plates + top collar -> welded to the shaft
  LongScytheFittings  two grip nibs + butt ferrule -> welded to the shaft
"""
import math

import bmesh
import bpy
from mathutils import Vector

COLLECTION = "Tool_LongScythe"


def srgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


# Flat palette, pack-style: a few solid tones per material, no per-vertex jitter.
WOOD = (150, 104, 64)
WOOD_DARK = (118, 80, 48)
WOOD_END = (104, 70, 42)
IRON = (128, 133, 141)
IRON_DARK = (84, 89, 98)
IRON_LIGHT = (176, 181, 188)
RIM = (86, 93, 106)        # the dark outline plate behind the blade
STEEL = (200, 207, 216)    # blade face
SPINE = (160, 168, 181)    # the back band of the face
EDGE = (246, 248, 252)     # cutting edge band
PANEL = (64, 70, 84)       # engraved panel

# Design points (Blender coordinates). The grip is the origin.
SHAFT = (-1.3, 5.3)        # wooden shaft, butt to top
TOP = 4.95                 # where the blade's root leaves the shaft
COLLAR = (4.62, 5.12)      # iron collar holding the blade
FERRULE = (-1.32, -1.04)   # iron ring at the butt
NIBS = (0.6, 2.7)          # the two grip nibs (right hand below the first, left hand at the second)
SEG = 8                    # octagonal, low-poly like the pack's shafts


def finish(bm, name, face_colours):
    """Turns a bmesh into a flat-shaded mesh object, one flat colour per face."""
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    att = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in me.polygons:
        rgb = face_colours[poly.index]
        for li in poly.loop_indices:
            att.data[li].color_srgb = srgb(*rgb)
        poly.use_smooth = False
    return bpy.data.objects.new(name, me)


def lathe(bm, colours, profile, colour_fn, segments=SEG, centre=(0.0, 0.0), caps=True):
    """Revolves (x, radius) points around an axis parallel to X through (y, z) = centre.
    colour_fn(row, segment) -> rgb for the band between row and row + 1."""
    cy, cz = centre
    rings = []
    for x, r in profile:
        ring = []
        for s in range(segments):
            a = 2 * math.pi * (s + 0.5) / segments
            ring.append(bm.verts.new((x, cy + r * math.cos(a), cz + r * math.sin(a))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(segments):
            n = (s + 1) % segments
            bm.faces.new((rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]))
            colours.append(colour_fn(i, s))
    if caps:
        for ring, x, flip in ((rings[0], profile[0][0], True), (rings[-1], profile[-1][0], False)):
            centre_v = bm.verts.new((x, cy, cz))
            for s in range(segments):
                a, b = ring[s], ring[(s + 1) % segments]
                bm.faces.new((centre_v, b, a) if flip else (centre_v, a, b))
                colours.append(colour_fn(0 if flip else len(profile) - 2, s))
    return rings


def slab(bm, colours, rows, z, colour_fn, tip=None):
    """Extrudes a strip polygon into a flat plate from -z to +z.
    rows[i][j]: 2D points, i along the blade, j across it (spine -> edge). The outline is the
    first and last columns plus the first row (and the tip point, if given). colour_fn(i, j)
    gives the face colour of top/bottom cell (i, j); walls use the cell next to them."""
    nr, nc = len(rows), len(rows[0])
    top = [[bm.verts.new((p.x, p.y, z)) for p in row] for row in rows]
    bot = [[bm.verts.new((p.x, p.y, -z)) for p in row] for row in rows]
    for i in range(nr - 1):
        for j in range(nc - 1):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
            colours.append(colour_fn(i, j))
            bm.faces.new((bot[i][j], bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j]))
            colours.append(colour_fn(i, j))
    # Side walls along the spine (j = 0) and the edge (j = last).
    for i in range(nr - 1):
        bm.faces.new((top[i][0], bot[i][0], bot[i + 1][0], top[i + 1][0]))
        colours.append(colour_fn(i, 0))
        e = nc - 1
        bm.faces.new((top[i][e], top[i + 1][e], bot[i + 1][e], bot[i][e]))
        colours.append(colour_fn(i, nc - 2))
    # Root wall.
    for j in range(nc - 1):
        bm.faces.new((top[0][j], top[0][j + 1], bot[0][j + 1], bot[0][j]))
        colours.append(colour_fn(0, j))
    last = nr - 1
    if tip is None:
        for j in range(nc - 1):
            bm.faces.new((top[last][j], bot[last][j], bot[last][j + 1], top[last][j + 1]))
            colours.append(colour_fn(last - 1, j))
    else:
        tt, tb = bm.verts.new((tip.x, tip.y, z * 0.6)), bm.verts.new((tip.x, tip.y, -z * 0.6))
        for j in range(nc - 1):
            bm.faces.new((top[last][j], tt, top[last][j + 1]))
            colours.append(colour_fn(last - 1, j))
            bm.faces.new((bot[last][j], bot[last][j + 1], tb))
            colours.append(colour_fn(last - 1, j))
        e = nc - 1
        bm.faces.new((top[last][0], bot[last][0], tb, tt))
        colours.append(colour_fn(last - 1, 0))
        bm.faces.new((top[last][e], tt, tb, bot[last][e]))
        colours.append(colour_fn(last - 1, e - 1))


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3


# Spine of the crescent: out of the collar, bulging away from the shaft top, then curling back
# toward the butt so the tip hooks round toward the player (as in the reference).
SPINE_CTRL = (Vector((TOP, 0.0)), Vector((TOP + 1.2, 1.5)), Vector((TOP + 0.4, 3.55)), Vector((TOP - 1.65, 3.65)))
STEPS = 22


def spine_path():
    pts = [bezier(*SPINE_CTRL, i / STEPS) for i in range(STEPS + 1)]
    out = []
    for i, p in enumerate(pts):
        ahead = (pts[min(i + 1, STEPS)] - pts[max(i - 1, 0)]).normalized()
        inward = Vector((-ahead.y, ahead.x))  # left of the heading = the concave (edge) side
        out.append((p, inward))
    return out


def width_at(t):
    """Oversized blade: narrow neck in the collar, a broad heel, tapering to the hooked tip."""
    neck = min(1.0, 0.55 + t * 4.5)
    return 0.98 * neck * (1 - t) ** 0.8 + 0.02


# Across the blade (fractions of the width, spine -> edge): spine band, face, edge band.
CROSS = (0.0, 0.16, 0.74, 1.0)


def build_blade():
    bm = bmesh.new()
    colours = []
    path = spine_path()
    n = len(path)

    def rows_for(grow):
        rows = []
        for i, (p, inward) in enumerate(path[:-1]):
            t = i / (n - 1)
            w = width_at(t)
            spine = p - inward * grow
            rows.append([spine + inward * (f * (w + 2 * grow)) for f in CROSS])
        return rows

    tip_p, tip_in = path[-1]
    tip_dir = (path[-1][0] - path[-2][0]).normalized()

    # 1. Dark outline plate, slightly bigger and thinner (shows as a rim round the face).
    slab(bm, colours, rows_for(0.07), 0.1, lambda i, j: RIM, tip=tip_p + tip_dir * 0.16)

    # 2. Face plate: spine band, silver face, bright edge band.
    def face_colour(i, j):
        return (SPINE, STEEL, EDGE)[j]

    slab(bm, colours, rows_for(0.0), 0.13, face_colour, tip=tip_p + tip_dir * 0.06)

    # 3. Engraved panel: a dark sliver along the spine for the first half, with a light line.
    panel_rows = []
    for i, (p, inward) in enumerate(path[1:12], start=1):
        t = i / (n - 1)
        w = width_at(t)
        fade = 1 - (i - 1) / 10
        a, b = 0.2, 0.2 + 0.36 * fade + 0.02
        panel_rows.append([p + inward * (a * w), p + inward * ((a + b) / 2 * w), p + inward * (b * w)])
    slab(bm, colours, panel_rows, 0.145, lambda i, j: PANEL)

    # 4. Two barbs on the back of the blade (the reference's notched spine; the pack's spikes).
    for at, size in ((7, 0.32), (13, 0.24)):
        p, inward = path[at]
        ahead = (path[at + 1][0] - path[at - 1][0]).normalized()
        base0 = p + ahead * size * 0.55
        base1 = p - ahead * size * 0.55
        point = p - inward * size * 0.95 - ahead * size * 0.8  # leans back toward the root
        for z, rgb in ((0.1, RIM), (0.125, STEEL)):
            vs = [bm.verts.new((v.x, v.y, z)) for v in (base0, point, base1)]
            vb = [bm.verts.new((v.x, v.y, -z)) for v in (base0, point, base1)]
            bm.faces.new(vs)
            colours.append(rgb)
            bm.faces.new(list(reversed(vb)))
            colours.append(rgb)
            for k in range(3):
                q = (k + 1) % 3
                bm.faces.new((vs[k], vb[k], vb[q], vs[q]))
                colours.append(rgb)
            if z == 0.1:
                # Shrink the face layer so the dark rim shows round the barb too.
                c = (base0 + point + base1) / 3
                base0, point, base1 = (c + (v - c) * 0.72 for v in (base0, point, base1))

    # 5. Iron collar round the shaft top, holding the blade root.
    a, b = COLLAR
    profile = [(a, 0.19), (a + 0.06, 0.23), (b - 0.06, 0.23), (b, 0.19)]
    lathe(bm, colours, profile, lambda i, s: IRON_LIGHT if i == 1 and s in (1, 2) else (IRON if i == 1 else IRON_DARK))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = finish(bm, "LongScytheBlade", colours)
    return obj, path


def build_handle():
    """Octagonal wooden shaft, a touch thicker at the butt, with two-tone faceted grain."""
    bm = bmesh.new()
    colours = []
    a, b = SHAFT
    rows = 10
    profile = []
    for i in range(rows + 1):
        x = a + (b - a) * i / rows
        u = i / rows
        profile.append((x, 0.155 - 0.025 * u))
    # Rounded top end above the collar.
    profile.append((b + 0.06, 0.1))

    def colour(i, s):
        if i == len(profile) - 2:
            return WOOD_END
        return WOOD_DARK if s % 3 == 0 else WOOD

    lathe(bm, colours, profile, colour)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "LongScytheHandle", colours)


def build_fittings():
    """Two grip nibs (iron band + square peg with a bent end, sticking out on the blade side, as
    in the reference) and the iron ferrule at the butt."""
    bm = bmesh.new()
    colours = []
    a, b = FERRULE
    lathe(bm, colours, [(a - 0.04, 0.12), (a, 0.18), (b, 0.18), (b + 0.03, 0.165)],
          lambda i, s: IRON_LIGHT if i == 1 and s in (1, 2) else (IRON if i == 1 else IRON_DARK))

    def box(lo, hi, rgb, light):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        v = [bm.verts.new(c) for c in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                       (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
        for face, shade in (((0, 3, 2, 1), rgb), ((4, 5, 6, 7), light), ((0, 1, 5, 4), rgb),
                            ((1, 2, 6, 5), light), ((2, 3, 7, 6), rgb), ((3, 0, 4, 7), rgb)):
            bm.faces.new([v[k] for k in face])
            colours.append(shade)

    for x in NIBS:
        lathe(bm, colours, [(x - 0.13, 0.17), (x - 0.1, 0.2), (x + 0.1, 0.2), (x + 0.13, 0.17)],
              lambda i, s: IRON if i == 1 else IRON_DARK)
        # Peg out toward +Y (the blade side), then a short foot bent back toward the butt.
        box((x - 0.07, 0.15, -0.07), (x + 0.07, 0.55, 0.07), IRON, IRON_LIGHT)
        box((x - 0.3, 0.45, -0.07), (x + 0.07, 0.6, 0.07), IRON_DARK, IRON)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "LongScytheFittings", colours)


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
    blade, path = build_blade()
    made = {}
    for obj in (build_handle(), blade, build_fittings()):
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
    handle = made["LongScytheHandle"]
    centre_x = (handle["min"][0] + handle["max"][0]) / 2
    made["gripFromCentre"] = round(-centre_x, 3)  # handle bbox centre -> grip, toward the head

    def tool_point(p, z=0.0):
        # Blender (x, y, z) -> tool frame (x, z, y): Y is the thin axis, Z the blade side.
        return [round(p.x, 3), round(z, 3), round(p.y, 3)]

    tip_p = path[-1][0] + (path[-1][0] - path[-2][0]).normalized() * 0.16
    heel_p, heel_in = path[4]
    made["points"] = {
        "BladeTip": tool_point(tip_p),
        "BladeHeel": tool_point(heel_p + heel_in * width_at(4 / STEPS)),
        "BladeBack": tool_point(path[11][0]),
        "BladeRoot": tool_point(path[1][0]),
        "LeftHand": [NIBS[1], 0.0, 0.0],
    }
    return made


result = build()
