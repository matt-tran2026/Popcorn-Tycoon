# Harvesting tool collection: design and production conventions

Status: Stage 1 started November 5, 2026. The Sickle has a Blender model, pose animations, original sounds and pooled VFX wired in and tested. Its FBX import and audio upload are manual steps still waiting. The other 35 tools are at concept stage. Every tool's status is in `assets/tools/manifest.json`.

Source of truth for each tool's stats and abilities: the creator's 36-tool catalog (pasted November 5, 2026). Concept sheet with art direction, rarity ladder and a card per tool: the Design canvas "Popcorn Tycoon — Harvesting Tool Collection" (https://claude.ai/artifact/YFz4MyWvRqYLHeLy7Q2Tkg). The tree stumps in the reference renders are staging only (creator, Nov 5): only the tool itself is modelled.

## Split between gameplay and presentation

| Concern | Lives in | Who reads it |
| --- | --- | --- |
| Stats, rarity, behaviour family, price | `Config.Tools.<id>` (shared) | Server decides; client only previews targets |
| Model, grip, named points, trail | `ToolPresentation.<id>.model` (shared) | `ToolModels` (server) builds the Tool |
| Pose clips, timing markers | `ToolPresentation.<id>.clips` | `ToolAnimator` (client) |
| Sounds (uploaded id + fallback, volume, pitch range) | `ToolPresentation.<id>.sounds` | `ToolEffects.sound` (client) |
| Harvest VFX parameters | `ToolPresentation.<id>.vfx` | `ToolEffects` (client) |

`Config.validate` checks that every tool in `Config.Tools` has a presentation entry with the same rarity, clips whose keys run in order from 0 to 1, trails that name real points, and a Swing clip exactly `swingSeconds` long. Nothing in `ToolPresentation`, `ToolAnimator` or `ToolEffects` can change a harvest: effects play only for stalks the server lists in its `HarvestResult`.

Stable tool ids are PascalCase and match `Config.Tools` keys (`Sickle`, `LongScythe`, `WeedWhacker`, `ThunderRake`, `Flamethrower`, …). The catalog's "Bare Hands" is the existing `Manual` hand pick.

## Behaviour families

Tools combine shared harvesting families rather than having 36 separate scripts: SingleTarget, ArcSweep, LineHarvest, ContinuousHarvest, ProjectileHarvest, AreaOfEffect, ChainHarvest, DashHarvest, PullHarvest, InstantConversion, ChargedAttack, MultiPulseHarvest. `Types.ToolBehavior` lists the implemented ones: only **ArcSweep** so far (`ToolRules.pickTargets`, used by `HarvestService.swing`). Each new family is added to HarvestService with its own server checks (ownership, equip, cooldown, target cap, dedup, backpack), then listed in `Types.ToolBehavior`. InstantConversion must route to popcorn through the same value rules as the microwave and never add raw corn (AGENTS.md).

## Models (Blender → Roblox)

- Folder per tool: `assets/tools/<Rarity>/<Tool>/` with `scripts/` (build script, re-runnable), `source/<Tool>.blend`, `exports/<Tool>.fbx`, `audio/`, `previews/`. Shared art is in `assets/tools/_shared/`.
- 1 Blender unit = 1 stud. The grip point is the origin, the handle runs along +X toward the head, and a flat head lies in the X/Y plane.
- Colours are vertex colours on one white material, as for the earlier Blender assets. Each part that needs its own Roblox Material (wood, metal) is a separate mesh. Moving parts (fans, jaws, gears) will be separate meshes too.
- Triangle and texture budgets by rarity are on the design canvas (Common 1.5k up to Mythic and Secret 8k). Sickle: handle 240 and blade 544 triangles.
- Import: Studio 3D Importer with Upload on. Put the imported Model at `ServerStorage.PopcornTemplates.Tools.<template>` (place file only) and save the place. `ToolModels.build` finds the handle mesh by name and works out the tool frame from the meshes: X along the handle's long axis toward the head, Y the head's thinnest axis, Z the side the head sits on. That frame gives `Tool.Grip` and the named attachments, however the importer centred or turned the meshes. It sets the parts white, applies Materials and welds them. Without the template, or if its meshes are missing, the procedural part-built model in `ToolModels` is used and a warning is printed. A Tool carries `ModelSource` ("Blender" or "Procedural") and `Rarity` attributes.

## Animation

Roblox animations made in Blender cannot simply be dropped onto an R15 avatar, and published animation ids need the creator's upload. Tool animations are therefore **pose clips in code**. `ToolAnimator` rotates R15 joints (Waist, Neck, shoulders, elbows, wrists) on top of what the Animator plays, once per frame from one PreSimulation connection. The legs keep walking, and rotations never pile up even when nothing else drives a joint. R6 gets the shoulders and neck. Clips use keys at fractions 0–1 with Sine, Back, Quad or Linear easing, plus named markers (`Hit`, `Shing`) that time sounds and effects. Per tool: `Equip`, `Idle` (loop) and the action clips, with Overheat, Charge and the like for the families that need them. Keyframed Animation assets remain an option later for full-body moves (Pogo Plunger, Rocket Plow) once uploads are possible.

Sickle clips: Equip 0.32 s (hand drawn up from the hip, wrist flourish, Shing at 55%); Idle 2.4 s sway; Swing 0.32 s (cock right with a waist twist, whip left, follow-through, settle; Hit at 42%, so harvest snaps start 0.13 s after the server confirms).

## Sound

Original sounds only, synthesised with Python (numpy and scipy) by each tool's `scripts/synth_*.py` with a fixed seed: 44.1 kHz mono 16-bit WAV peaking at −3 dBFS. The game varies pitch within each sound's `pitch` range. Volumes follow the canvas mix: equip around 0.3, actions around 0.35, harvest hits around 0.5. Harvest sounds are 3D at the stalk; equip and swing play for the holder. Sounds with no uploaded id use `fallback` (the old swing and snip) or stay silent.

Uploading audio: the Studio MCP can only upload images, so audio is uploaded by the creator. Steps: Studio → Window → Asset Manager → Bulk Import (or Toolbox → Creations → Audio), choose the WAVs in `assets/tools/<Rarity>/<Tool>/audio/`, wait for moderation, copy each asset id, then set `id = "rbxassetid://…"` in `ToolPresentation.<id>.sounds` and in the manifest. Never invent ids.

## VFX

`ToolEffects` keeps pooled effects under `workspace.Terrain`: one leaf `ParticleEmitter` on one Attachment, moved and told to `Emit` for each burst. A swing creates no Parts or emitters, and 10 swings in a row still leave one emitter. Each burst is full under 60 studs from the camera, halved to 120 and skipped beyond. `ToolEffects.particleScale` is the hook for a future reduced-effects setting. The leaf texture is original (drawn with PIL, `_shared/make_leaf.py`) and uploaded as `rbxassetid://107437834728710`. Swing trails are a `SwingTrail` between two named points on the handle, switched on for 80% of the swing.

## Collection and chest compatibility

Each tool has, or will have: stable id, display name, rarity, description (Config); icon and preview render (`previews/`); equip model (template); animation, sound and VFX references (ToolPresentation); gameplay config (Config). The planned tiered chests and a preview stage (the tool on a slow turntable over a rarity-coloured glow disc) can read these without new data. No chest system is implemented.

## Stage plan

Stage 1 is Sickle, Long Scythe, Weed Whacker, Thunder Rake and Flamethrower, then Common/Uncommon, Rare, Epic, Legendary, Mythic, Secret, and final integration (catalog order and pipeline on the design canvas). A tool is complete only with its model imported, its animations, sounds and VFX in game, its gameplay integrated and its tests run (manifest `status`).
