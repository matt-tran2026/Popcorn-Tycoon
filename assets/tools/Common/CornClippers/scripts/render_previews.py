"""Preview renders of the Corn Clippers from several angles (vault note "Blender Tool Models", step 8).

Run inside Blender after build_corn_clippers.py: exec(open(<this file>).read(), ns).
Set ns["JAW_DEGREES"] before running to render the jaw closed (rotates ClippersJaw and
ClippersJawGrip about the pivot bolt, the spring by half), as the snip does in game.
Only the Tool_CornClippers collection is rendered; other tool collections are hidden from
render for the duration and restored afterwards.
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else None
OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Common\CornClippers\previews"
COLLECTION = "Tool_CornClippers"
PIVOT = Vector((0.95, 0.165, 0.0))  # Pivot bolt in Blender coordinates (grip at the origin).
JAW_DEGREES = globals().get("JAW_DEGREES", 0.0)

# name: (camera location, look-at point). The reference render is the "front" view mirrored
# (the model is built seen from behind), so "reference" looks from -Z with the blade to the left.
VIEWS = {
    "CornClippers_preview": ((3.4, -3.2, 3.6), (0.75, 0.25, 0.0)),
    "CornClippers_reference": ((0.75, 0.3, -4.6), (0.75, 0.3, 0.0)),
    "CornClippers_back": ((0.75, 0.3, 4.6), (0.75, 0.3, 0.0)),
    "CornClippers_top": ((0.75, 3.8, 1.6), (0.75, 0.3, 0.0)),
    "CornClippers_end": ((5.0, 0.6, -1.4), (0.75, 0.3, 0.0)),
}


def look_at(cam, location, target):
    cam.location = location
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def set_jaw(degrees):
    rot = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.radians(degrees), 4, "Z") @ Matrix.Translation(-PIVOT)
    half = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.radians(degrees / 2), 4, "Z") @ Matrix.Translation(-PIVOT)
    for name in ("ClippersJaw", "ClippersJawGrip"):
        bpy.data.objects[name].matrix_world = rot
    bpy.data.objects["ClippersSpring"].matrix_world = half


def render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE_NEXT"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = 900, 700
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.09, 0.11, 0.18, 1)
    cam = bpy.data.objects["ToolPreviewCam"]
    scene.camera = cam
    hidden = []
    for col in bpy.data.collections:
        if col.name.startswith("Tool_") and col.name != COLLECTION and not col.hide_render:
            col.hide_render = True
            hidden.append(col.name)
    for name in ("Camera", "Light"):
        obj = bpy.data.objects.get(name)
        if obj and not obj.hide_render and obj.type == "LIGHT":
            obj.hide_render = True
            hidden.append("obj:" + name)
    set_jaw(JAW_DEGREES)
    suffix = "" if JAW_DEGREES == 0 else "_closed"
    written = []
    try:
        for name, (loc, target) in VIEWS.items():
            if suffix and name not in ("CornClippers_reference", "CornClippers_preview"):
                continue
            look_at(cam, loc, target)
            # Keep the key light over the camera's shoulder and the rim behind the tool, at the
            # same distance as the Sickle's setup (about 7.5), so 260 W / 220 W never blow out.
            view = (Vector(loc) - Vector(target)).normalized()
            side = view.cross(Vector((0, 1, 0)) if abs(view.y) < 0.9 else Vector((1, 0, 0))).normalized()
            key = bpy.data.objects["ToolKey"]
            key.location = Vector(target) + (view + side * 0.6 + Vector((0, 0.5, 0))).normalized() * 7.5
            look_at(key, key.location, target)
            rim = bpy.data.objects["ToolRim"]
            rim.location = Vector(target) + (-view - side * 0.5 + Vector((0, 0.6, 0))).normalized() * 7.0
            look_at(rim, rim.location, target)
            path = os.path.join(OUT, name + suffix + ".png")
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            written.append(path)
    finally:
        set_jaw(0)
        for entry in hidden:
            if entry.startswith("obj:"):
                bpy.data.objects[entry[4:]].hide_render = False
            else:
                bpy.data.collections[entry].hide_render = False
    return written


result = {"written": render()}
