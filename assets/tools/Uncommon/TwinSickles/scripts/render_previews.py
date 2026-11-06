"""Preview renders of the Twin Sickles (vault note "Blender Tool Models", step 8).

Run inside Blender after build_twin_sickles.py: exec(open(<this file>).read(), ns).
Only the Tool_TwinSickles collection is rendered; other tool collections are hidden from render
for the duration and restored afterwards. Uses the shared ToolPreviewCam, ToolKey and ToolRim.

"TwinSickles_pair" stages the pair like the creator's reference (both crescents standing up,
handles splayed outward). The second sickle is the same meshes turned 180 degrees about the
vertical axis, exactly as the game makes the left-hand copy, so this render also checks that
the turned copy reads as a true mirror image. The staging objects are removed afterwards.
"""
import math
import os

import bpy
from mathutils import Euler, Vector

OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Uncommon\TwinSickles\previews"
COLLECTION = "Tool_TwinSickles"
CENTRE = (0.55, 0.75, 0.0)

# name: (camera location, look-at point, stage the pair?)
VIEWS = {
    "TwinSickles_preview": ((4.2, -3.4, 4.6), CENTRE, False),
    "TwinSickles_reference": ((0.55, 0.75, 6.4), CENTRE, False),
    "TwinSickles_pair": ((0.0, -9.0, 1.6), (0.0, 0.0, 1.3), True),
}


def look_at(obj, location, target):
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def stage_pair(col):
    """Two copies standing in the X/Z plane (camera on -Y), crescents up, handles splayed out."""
    staged = []
    meshes = [o for o in col.objects if o.type == "MESH"]
    for side in (1, -1):
        for src in meshes:
            dup = src.copy()  # shares the mesh data: no new geometry
            dup.name = src.name + ("_R" if side > 0 else "_L")
            col.objects.link(dup)
            # Stand the blade plane up (Blender Y -> Z), lean the handle 40 degrees out and
            # down; the left copy is the right one turned 180 degrees about Z.
            base = Euler((math.radians(90), 0, 0)).to_matrix().to_4x4()
            lean = Euler((0, math.radians(-50), 0)).to_matrix().to_4x4()
            turn = Euler((0, 0, math.radians(0 if side > 0 else 180))).to_matrix().to_4x4()
            dup.matrix_world = turn @ lean @ base
            dup.location = (0.75 * side, 0, 0.6)
            staged.append(dup)
    for src in meshes:
        src.hide_render = True
    return staged, meshes


def render():
    scene = bpy.context.scene
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = 900, 700
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.09, 0.11, 0.18, 1)
    cam = bpy.data.objects["ToolPreviewCam"]
    scene.camera = cam
    col = bpy.data.collections[COLLECTION]
    hidden = []
    for other in bpy.data.collections:
        if other.name.startswith("Tool_") and other.name != COLLECTION and not other.hide_render:
            other.hide_render = True
            hidden.append(other.name)
    light = bpy.data.objects.get("Light")
    if light and not light.hide_render:
        light.hide_render = True
        hidden.append("obj:Light")
    written = []
    try:
        for name, (loc, target, pair) in VIEWS.items():
            staged, originals = stage_pair(col) if pair else ([], [])
            try:
                look_at(cam, loc, target)
                view = (Vector(loc) - Vector(target)).normalized()
                side = view.cross(Vector((0, 0, 1)) if abs(view.z) < 0.9 else Vector((1, 0, 0))).normalized()
                key = bpy.data.objects["ToolKey"]
                look_at(key, Vector(target) + (view + side * 0.6 + Vector((0, 0, 0.5))).normalized() * 7.5, target)
                rim = bpy.data.objects["ToolRim"]
                look_at(rim, Vector(target) + (-view - side * 0.5 + Vector((0, 0, 0.6))).normalized() * 7.0, target)
                path = os.path.join(OUT, name + ".png")
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
                written.append(path)
            finally:
                for dup in staged:
                    bpy.data.objects.remove(dup, do_unlink=True)
                for src in originals:
                    src.hide_render = False
    finally:
        for entry in hidden:
            if entry.startswith("obj:"):
                bpy.data.objects[entry[4:]].hide_render = False
            else:
                bpy.data.collections[entry].hide_render = False
    return written


result = {"written": render()}
