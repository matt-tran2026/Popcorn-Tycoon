"""Preview renders of the Long Scythe (vault note "Blender Tool Models", step 8).

Run inside Blender after build_long_scythe.py: exec(open(<this file>).read(), ns).
Only the Tool_LongScythe collection is rendered; other tool collections are hidden from render
for the duration and restored afterwards. Uses the shared ToolPreviewCam, ToolKey and ToolRim.
The tool is 6.9 studs long, so the camera and lights stand further back than for hand tools.
"""
import os

import bpy
from mathutils import Vector

OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Uncommon\LongScythe\previews"
COLLECTION = "Tool_LongScythe"
CENTRE = (2.2, 1.3, 0.0)

# name: (camera location, look-at point)
VIEWS = {
    "LongScythe_preview": ((7.5, -5.5, 7.5), CENTRE),
    # Square-on to the blade's face, like the creator's reference render.
    "LongScythe_reference": ((2.2, 1.3, 10.5), CENTRE),
    "LongScythe_blade": ((4.6, 1.9, 5.0), (4.4, 1.9, 0.0)),
}


def look_at(obj, location, target):
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def ensure_rig():
    """The shared camera and two area lights (made by the first tool's render script)."""
    scene = bpy.context.scene
    if "ToolPreviewCam" not in bpy.data.objects:
        cam = bpy.data.objects.new("ToolPreviewCam", bpy.data.cameras.new("ToolPreviewCam"))
        scene.collection.objects.link(cam)
    for name, energy, colour in (("ToolKey", 260, (1.0, 0.95, 0.88)), ("ToolRim", 220, (0.8, 0.88, 1.0))):
        if name not in bpy.data.objects:
            data = bpy.data.lights.new(name, "AREA")
            data.energy, data.color, data.size = energy, colour, 3.0
            scene.collection.objects.link(bpy.data.objects.new(name, data))


def render():
    ensure_rig()
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
    for other in bpy.data.collections:
        if other.name.startswith("Tool_") and other.name != COLLECTION and not other.hide_render:
            other.hide_render = True
            hidden.append(other.name)
    # Blender's startup Light and Cube are not part of any tool.
    for extra in ("Light", "Cube"):
        obj = bpy.data.objects.get(extra)
        if obj and not obj.hide_render:
            obj.hide_render = True
            hidden.append("obj:" + extra)
    written = []
    try:
        for name, (loc, target) in VIEWS.items():
            look_at(cam, loc, target)
            view = (Vector(loc) - Vector(target)).normalized()
            side = view.cross(Vector((0, 0, 1)) if abs(view.z) < 0.9 else Vector((1, 0, 0))).normalized()
            look_at(bpy.data.objects["ToolKey"], Vector(target) + (view + side * 0.6 + Vector((0, 0, 0.5))).normalized() * 11.0, target)
            look_at(bpy.data.objects["ToolRim"], Vector(target) + (-view - side * 0.5 + Vector((0, 0, 0.6))).normalized() * 10.5, target)
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
