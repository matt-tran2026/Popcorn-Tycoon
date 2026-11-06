"""Preview renders of the Hedge Trimmer (vault note "Blender Tool Models", step 8).

Run inside Blender after build_hedge_trimmer.py: exec(open(<this file>).read(), ns).
Only the Tool_HedgeTrimmer collection is rendered; other tool collections are hidden from render
for the duration and restored afterwards. Uses the shared ToolPreviewCam, ToolKey and ToolRim.
The tool is 5.4 studs long. Views: a 3/4 preview, the reference angle (blade to the left, as in
the creator's render) and the view from behind the player, roughly what the game camera sees.
"""
import os

import bpy
from mathutils import Vector

OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Uncommon\HedgeTrimmer\previews"
COLLECTION = "Tool_HedgeTrimmer"
CENTRE = (1.95, -0.2, 0.0)

# name: (camera location, look-at point)
VIEWS = {
    "HedgeTrimmer_preview": ((6.2, 3.2, 6.4), CENTRE),
    # From -Z with the blade to the left, like the creator's reference render.
    "HedgeTrimmer_reference": ((0.9, 1.6, -7.2), CENTRE),
    # From behind and above the grip, roughly the game camera behind the player.
    "HedgeTrimmer_behind": ((-4.2, 3.6, 2.6), (2.4, -0.5, 0.0)),
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
