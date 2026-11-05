# Tool pipeline, Stage 1 (Sickle): test evidence (November 5, 2026)

Setup: Roblox Studio `Popcorn Tycoon.rbxl` (unpublished), Play Solo with the Owner's Studio account, native Script Sync live. Before Play, the three new modules (`ToolPresentation`, `ToolAnimator`, `ToolEffects`) and the edited `ToolModels`, `ToolService`, `ToolController` and `Config` were confirmed in Studio. Design: [docs/design/TOOL_COLLECTION.md](../design/TOOL_COLLECTION.md).

Runners were created in Edit with the Studio MCP `multi_edit` tool outside the synced folders, one set per Play, and the runner folders were deleted afterwards.

| Runner | Result | Notes |
| --- | --- | --- |
| `tests/Tools.server.luau` (unchanged) | **34/34 pass** | Regression after `ToolService` switched to `ToolModels.build/has`: targeting, Shop buy/refusals, equip tracking, 3-stalk swing, cadence, bag limit, facing away, hand pick with the Sickle held, unequip, respawn gives exactly one Sickle. |
| `tests/ToolVisualsSetup.server.luau` + `tests/ToolVisuals.client.luau` (new) | **16/16 pass** (run twice; second run after widening the swing) | On a real avatar: Rarity/ModelSource attributes, SwingTrail present; equip raises the hand from −0.92 to +0.81 studs (torso space); idle sway 0.057 studs; swing moves the hand from +1.60 (wind-up, right) to +0.06 (cut, left) with the maximum before the minimum; trail on during the swing and off after; back to the hold pose (x 1.44 vs 1.46); server harvested 3 corn; leaf emitter pooled under Terrain with the uploaded texture; 11 swings leave 1 emitter; unequip returns the tool to the Backpack. |
| `tests/ToolTemplateFrame.server.luau` (new) | **7/7 pass** | The Blender-template path, using a stand-in `ServerStorage.PopcornTemplates.Tools.Sickle` built from Parts laid out like the exported FBX (removed afterwards): template used, handle = grip mesh, blade welded, Wood/Metal and white colour, `Handle.CFrame * Grip` lands exactly on the grip point with the expected orientation (error 0.0000), BladeTip attachment on the blade side, trail, rarity. |

Console: no errors. On first use Studio logged `Asset content representation is being generated` for the newly uploaded leaf texture (normal processing delay for a fresh upload), so the leaf flecks may draw blank for the first minutes.

## Not verified yet

- The real Blender Sickle in game: the FBX was not imported because desktop control of Studio was declined. Grip, scale, materials and clipping need a look once it is imported (the frame maths is covered by the stand-in test).
- The original sounds in game: the WAVs exist and were checked by level and spectrum (Equip peak −3 dBFS, RMS −22 dB, centroid 5.6 kHz; Swish RMS −18 dB, 1.7 kHz; Snap RMS −25 dB, 3.6 kHz), but they are not uploaded and nobody has listened to them yet. Until upload, the swing and harvest keep the old sounds and the equip is silent.
- How the swing looks on screen: the game camera overrode the scripted test camera, so the swing was verified by measured hand positions, not by eye.
- Touch devices, R6 avatars, a second player watching (the pose layering is local only, as was the old swing), Multiplayer runner.
