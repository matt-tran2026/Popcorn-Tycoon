"""Preview renders of the Weed Whacker (vault note "Blender Tool Models", step 8).

Run inside Blender after build_weed_whacker.py: exec(open(<this file>).read(), ns).
Only the Tool_WeedWhacker collection is rendered; other tool collections are hidden from render
for the duration and restored afterwards. Uses the shared ToolPreviewCam, ToolKey and ToolRim.
The tool is 6.8 studs from the starter handle to the blade's front teeth. Views: a 3/4 preview
from above on the gauge side, the reference angle (the gauge/air-filter side, head low, as in the
creator's render), the view from behind the player and a close-up of the head from below-front.
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Rare\WeedWhacker\previews"
COLLECTION = "Tool_WeedWhacker"
CENTRE = (1.4, 0.0, 0.0)

VIEWS = {
    "WeedWhacker_preview": ((4.6, 5.6, 7.6), CENTRE, (0, 1, 0)),
    "WeedWhacker_reference": ((2.2, 1.4, 9.4), (1.4, 0.1, 0.0), (0, 1, 0)),
    "WeedWhacker_behind": ((-5.2, 3.4, 2.6), (1.6, -0.1, 0.0), (0, 1, 0)),
    "WeedWhacker_head": ((6.6, 1.2, 2.6), (3.9, -0.35, 0.0), (0, 1, 0)),
}


def look_at(obj, location, target, up=(0, 1, 0)):
    """Points the object's -Z at target with `up` as screen up."""
    obj.location = location
    forward = (Vector(target) - Vector(location)).normalized()
    up = Vector(up)
    if abs(forward.dot(up)) > 0.95:
        up = Vector((0, 0, 1))
    right = forward.cross(up).normalized()
    true_up = right.cross(forward).normalized()
    obj.rotation_euler = Matrix((right, true_up, -forward)).transposed().to_euler()


def ensure_rig():
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
    for extra in ("Light", "Cube"):
        obj = bpy.data.objects.get(extra)
        if obj and not obj.hide_render:
            obj.hide_render = True
            hidden.append("obj:" + extra)
    written = []
    try:
        for name, (loc, target, up) in VIEWS.items():
            look_at(cam, loc, target, up)
            view = (Vector(loc) - Vector(target)).normalized()
            side = view.cross(Vector((0, 1, 0)) if abs(view.y) < 0.9 else Vector((1, 0, 0))).normalized()
            look_at(bpy.data.objects["ToolKey"], Vector(target) + (view + side * 0.6 + Vector((0, 0.5, 0))).normalized() * 9.0, target)
            look_at(bpy.data.objects["ToolRim"], Vector(target) + (-view - side * 0.5 + Vector((0, 0.6, 0))).normalized() * 8.5, target)
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
