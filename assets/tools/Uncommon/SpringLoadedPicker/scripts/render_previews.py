"""Preview renders of the Spring-Loaded Picker (vault note "Blender Tool Models", step 8).

Run inside Blender after build_spring_loaded_picker.py: exec(open(<this file>).read(), ns).
Only the Tool_SpringLoadedPicker collection is rendered; other tool collections are hidden from
render for the duration and restored afterwards. Uses the shared ToolPreviewCam, ToolKey and
ToolRim. The tool is 4.7 studs long. Views: a 3/4 preview, the reference angle (claw to the left,
latch side toward the camera, as in the creator's render), the view from behind the player, and
the "fired" pose (head shot forward, coil stretched, jaws shut, latch flipped) set with
POSE = "fired" before running.
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

OUT = globals().get("OUT_DIR") or r"C:\Users\matth\OneDrive\Documents\Obsidian Vault\Popcorn Tycoon\Popcorn Tycoon\assets\tools\Uncommon\SpringLoadedPicker\previews"
COLLECTION = "Tool_SpringLoadedPicker"
CENTRE = (2.15, 0.15, 0.0)
POSE = globals().get("POSE") or "rest"

VIEWS = {
    "SpringLoadedPicker_preview": ((5.4, 3.6, 6.4), CENTRE),
    # From -Z with the claw on the left, like the creator's reference render.
    "SpringLoadedPicker_reference": ((1.6, 1.4, -8.2), CENTRE),
    # From behind and above the grip, roughly the game camera behind the player.
    "SpringLoadedPicker_behind": ((-3.8, 3.4, 2.4), (2.4, 0.4, 0.0)),
}
if POSE == "fired":
    VIEWS = {"SpringLoadedPicker_fired": VIEWS["SpringLoadedPicker_reference"]}

# The fired pose, mirroring ToolPresentation's Swing clip at its widest: plunger +0.6 studs,
# coil stretched to match, jaws shut (top -11 deg, bottom +11 deg about Blender Z), latch -35 deg.
PLUNGE = 0.6
SPRING_X0, SPRING_LEN = 1.5, 1.5
AXIS_Y = 0.6


def look_at(obj, location, target):
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


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


def about(pivot, degrees):
    p = Vector(pivot)
    return Matrix.Translation(p) @ Matrix.Rotation(math.radians(degrees), 4, "Z") @ Matrix.Translation(-p)


def set_pose(fired):
    objs = bpy.data.objects
    for name in ("PickerLatch", "PickerSpring", "PickerRod", "PickerHead", "PickerJawTop", "PickerJawBottom"):
        objs[name].matrix_world = Matrix.Identity(4)
    if not fired:
        return
    slide = Matrix.Translation((PLUNGE, 0, 0))
    objs["PickerRod"].matrix_world = slide
    objs["PickerHead"].matrix_world = slide
    objs["PickerJawTop"].matrix_world = slide @ about((3.67, AXIS_Y + 0.15, 0), -11)
    objs["PickerJawBottom"].matrix_world = slide @ about((3.67, AXIS_Y - 0.15, 0), 11)
    objs["PickerLatch"].matrix_world = about((0.98, 0.44, 0), -35)
    s = (SPRING_LEN + PLUNGE) / SPRING_LEN
    objs["PickerSpring"].matrix_world = (Matrix.Translation((SPRING_X0, 0, 0)) @ Matrix.Diagonal((s, 1, 1, 1))
                                         @ Matrix.Translation((-SPRING_X0, 0, 0)))


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
    set_pose(POSE == "fired")
    try:
        for name, (loc, target) in VIEWS.items():
            look_at(cam, loc, target)
            view = (Vector(loc) - Vector(target)).normalized()
            side = view.cross(Vector((0, 0, 1)) if abs(view.z) < 0.9 else Vector((1, 0, 0))).normalized()
            look_at(bpy.data.objects["ToolKey"], Vector(target) + (view + side * 0.6 + Vector((0, 0, 0.5))).normalized() * 9.0, target)
            look_at(bpy.data.objects["ToolRim"], Vector(target) + (-view - side * 0.5 + Vector((0, 0, 0.6))).normalized() * 8.5, target)
            path = os.path.join(OUT, name + ".png")
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            written.append(path)
    finally:
        set_pose(False)
        for entry in hidden:
            if entry.startswith("obj:"):
                bpy.data.objects[entry[4:]].hide_render = False
            else:
                bpy.data.collections[entry].hide_render = False
    return written


result = {"written": render(), "pose": POSE}
