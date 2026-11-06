"""Preview renders of the Harvest Hook (vault note "Blender Tool Models", step 8).

Run inside Blender after build_harvest_hook.py: exec(open(<this file>).read(), ns).
Only the Tool_HarvestHook collection is rendered; other tool collections are hidden from render
for the duration and restored afterwards. Uses the shared ToolPreviewCam, ToolKey and ToolRim.
"""
import os

import bpy
from mathutils import Vector

OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Common\HarvestHook\previews"
COLLECTION = "Tool_HarvestHook"
CENTRE = (0.85, 0.75, 0.0)

# name: (camera location, look-at point). "reference" matches the creator's render: the flat
# face of the hook toward the camera, seen from -Z so the hook sits on the left of the handle.
VIEWS = {
    "HarvestHook_preview": ((4.4, -3.6, 5.0), CENTRE),
    "HarvestHook_reference": ((0.85, 0.75, -6.8), CENTRE),
    "HarvestHook_head": ((4.6, 0.4, 2.6), (1.9, 0.9, 0.0)),
}


def look_at(obj, location, target):
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


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
    hidden = []
    for col in bpy.data.collections:
        if col.name.startswith("Tool_") and col.name != COLLECTION and not col.hide_render:
            col.hide_render = True
            hidden.append(col.name)
    light = bpy.data.objects.get("Light")
    if light and not light.hide_render:
        light.hide_render = True
        hidden.append("obj:Light")
    written = []
    try:
        for name, (loc, target) in VIEWS.items():
            look_at(cam, loc, target)
            view = (Vector(loc) - Vector(target)).normalized()
            side = view.cross(Vector((0, 1, 0)) if abs(view.y) < 0.9 else Vector((1, 0, 0))).normalized()
            key = bpy.data.objects["ToolKey"]
            key_at = Vector(target) + (view + side * 0.6 + Vector((0, 0.5, 0))).normalized() * 7.5
            look_at(key, key_at, target)
            rim = bpy.data.objects["ToolRim"]
            rim_at = Vector(target) + (-view - side * 0.5 + Vector((0, 0.6, 0))).normalized() * 7.0
            look_at(rim, rim_at, target)
            path = os.path.join(OUT, name + ".png")
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            written.append(path)
    finally:
        for entry in hidden:
            if entry.startswith("obj:"):
                bpy.data.objects[entry[4:]].hide_render = False
            else:
                bpy.data.collections[entry].hide_render = False
    return written


result = {"written": render()}
