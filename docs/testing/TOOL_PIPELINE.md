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

- The real Blender Sickle in game: imported later the same day (section below); the creator's own look is still pending.
- The original sounds: uploaded and loading in game (section below); nobody has listened to them yet.
- How the swing looks on screen: the game camera overrode the scripted test camera, so the swing was verified by measured hand positions, not by eye.
- Touch devices, R6 avatars, a second player watching (the pose layering is local only, as was the old swing), Multiplayer runner.

## Real Blender model in game (later on November 5)

At the creator's request Claude imported `exports/Sickle.fbx` with the 3D Importer (desktop control allowed this time; Upload on). It arrived at 100× scale and turned 180°, was scaled by 0.01, and is stored at `ServerStorage.PopcornTemplates.Tools.Sickle` (meshes: SickleBlade 107593357248946, SickleHandle 122836565528948). The place was saved (Ctrl+S, local file only, not published). In Play the granted Sickle reported `ModelSource = Blender`, with a Wood handle, a Metal blade (both white so the vertex colours show), the trail and the weld. The first look showed the inherited Grip standing the blade upright over the head, facing forward and hiding the face. The new hold (`ToolPresentation.hold`) was measured in character space: blade centre 2.9 studs in front, blade face up (normal y 0.97), tip curling back on the left. A screenshot from the side confirmed it. Two real F-key swings harvested corn with no errors. Still pending: the creator's own look, the audio upload, and the leaf texture, which Studio still reported as "being generated" about 25 minutes after upload.

## Sickle sounds uploaded (later on November 5)

At the creator's request Claude uploaded the three WAVs through the Asset Manager (Import with the Audio Files filter, then the rights confirmation, 0 Robux fee): Sickle_Equip 116936988986525, Sickle_Swish 136321679774475, Stalk_Snap 125411384210572. The ids were read off the screen, then confirmed with `MarketplaceService:GetProductInfo` (names match; asset type 3 Audio; creator tranman2026). In a Play client all three loaded with lengths of 0.55, 0.36 and 0.42 s, exactly matching the WAVs, and the console showed no errors. `ToolPresentation.Sickle.sounds` now uses them, with the old sounds kept as fallbacks. Nobody has listened to them yet.

## Swing sound with a metal shing (later on November 5)

The creator liked the air swoosh and asked for a metal "shing" mixed in. `swish_shing` layers short ringing partials (3.15, 4.87, 6.62 and 8.35 kHz, with a 3.5% upward glide) over a thin edge-scrape, starting 55 ms in and about 7 dB below the swoosh. The swoosh envelope is unchanged. Energy above 3 kHz rose from 11% to 31%, and the metal ring now runs a little past the end of the swoosh. The other three WAVs regenerated byte-for-byte identical. Uploaded as Sickle_SwishShing 111045205785758 (checked with GetProductInfo: Audio, tranman2026). It loads in a Play client at 0.36 s and is now `ToolPresentation.Sickle.sounds.Swing`. Not listened to by Claude.

The creator found that shing too sharp. `swish_soft_shing` replaces it with lower partials (1.98, 3.11 and 4.37 kHz; the 6.6 and 8.4 kHz ones are gone), a 15 ms attack instead of 6 ms, a duller 2.2–5 kHz scrape and a 5 kHz low-pass, sitting 9 dB under the swoosh. Power above 6 kHz fell from 1.5% to 0.02%, about the plain swoosh's level, while the ring tones still stand 7.7 dB above the swoosh at their pitches. Uploaded as Sickle_SwishShingSoft 113494806859866 (GetProductInfo: Audio, tranman2026). It loads at 0.36 s and the running game uses it, with no console errors.
