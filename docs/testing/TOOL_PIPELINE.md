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

**Reverted the same day.** The creator chose the original plain swoosh. The swing uses Sickle_Swish 136321679774475 again, which the running game was checked to use. Both shing WAVs and their synthesis code were removed from the repo; the other three WAVs regenerate byte-for-byte unchanged. The two uploads (111045205785758, 113494806859866) cannot be deleted from Studio, whose Asset Manager has no delete or archive. The creator archived them on the Creator Dashboard. Afterwards its Audio tab listed only Stalk_Snap, Sickle_Swish and Sickle_Equip.

## Corn Clippers (Common #2, November 5)

The creator's catalog card: 1 stalk per action, 0.12 s cooldown, 8 studs, 1× yield, raw corn; "Rapid Snip". Reference render: yellow-handled bypass pruners.

**Model.** `assets/tools/Common/CornClippers/scripts/build_corn_clippers.py` builds five meshes, 1,340 triangles in all (Common budget 1.5k), all vertex-coloured: ClippersHandle 222 (lower handle, the Tool's Handle, SmoothPlastic), ClippersBlade 342 (cutting blade, tang, pivot bolt and nut; Metal), ClippersJaw 230 (hook jaw and tang; Metal; turns on a Motor6D named `Jaw`), ClippersJawGrip 222 (upper handle; SmoothPlastic; welded to the jaw), ClippersSpring 324 (coil; Metal; Motor6D `Spring` at half the jaw angle). `render_previews.py` writes five angles plus two closed-jaw renders to `previews/`. Compared with the reference after the first pass, the handle ends were too pointed, the hook too thin, the spring too small and the yellow too dull; all four were fixed in a second pass. Exported `exports/CornClippers.fbx` (65 KB) and `source/CornClippers.blend` (149 KB). **Not imported into Studio yet** (needs the creator: desktop control was declined), so the game uses the part-built fallback in `ToolModels.cornClippers`, which has the same part names, joints, points and grip.

**Gameplay.** `Config.Tools.CornClippers`: SingleTarget, reach 8, arc 90°, maxTargets 1, cooldown 0.12 s, ×1, $100 Cash (first guess, under the Sickle's $200). SingleTarget shares `ToolRules.pickTargets` with ArcSweep; `Config.validate` requires maxTargets 1 for it. HarvestService's swing cadence changed for every tool: an accepted swing sets the next due time one cooldown after the later of now and the previous due time, and a swing may arrive up to half a cooldown early. This absorbs network jitter at 0.12 s and still caps the rate.

**Presentation.** Pose clips: Equip 0.3 s with a jaw click, Idle 2.4 s, and Swing/SwingAlt 0.12 s, which alternate between an upward and a downward wrist flick. The jaw closes 24° at the Hit marker (45%) and springs open again. `ToolAnimator` now drives any pose name that is not a character joint as a Motor6D inside the held Tool. Each confirmed cut shows a pooled `PopcornToolFlash` sparkle (built-in `sparkles_main.dds`) and 4 leaf flecks. Original WAVs `CornClippers_Snip` (0.16 s, dry double click) and `CornClippers_Equip` (0.42 s) are in `audio/` but not uploaded. Until they are, the snip falls back to the Creator Store scissors snip 9118831072, and the harvest uses the uploaded Stalk_Snap.

**Sync note.** Native Script Sync carried the edits to the shared modules into Studio but not those to the server or client modules. Those were applied to Studio through the MCP `multi_edit` with the same replacements, and byte sums were compared afterwards: Studio and the repo match for all nine changed modules.

| Runner | Result | Notes |
| --- | --- | --- |
| `tests/CornClippers.server.luau` (new) | **20/20 pass** (second run; the first found two problems) | Config matches the catalog; one target, the nearest inside a 45° half-cone and 8 studs; model with `Jaw`/`Spring` Motor6Ds and the upper handle welded to the jaw; the snip pose moves the hook toward the blade (z −0.193 → 0.007) and the upper handle down (0.790 → 0.492); Shop buy charges $100 once; equip tracked; a snip cuts exactly 1 stalk; an immediate repeat is refused; a snip 0.075 s later (jitter) is accepted, and the next instant one refused; 1.2 s of per-frame spam passes the cadence gate 11 times (bound 12); out of reach cuts nothing. First run: the part-built handle was built pointing −X, which would have held the tool backwards (fixed: handle built butt to bolster, grip and points expressed in the handle frame); the spam check counted harvests rather than cadence passes. |
| `tests/CornClippersVisuals.client.luau` (new) | **11/11 pass** | Real avatar: equip; jaw rests at 0°, closes to −23.6° during a snip and reopens to 0°; the server harvested 1 stalk; flash emitter pooled; 6 quick snips harvested 6; one flash and one leaf emitter after all snips; unequip. |
| Sickle regression (temporary runner) | **7/7 pass** | Blender template still builds with the blade welded to the Handle and the trail; swing cuts 3; immediate repeat and +0.2 s refused; after the cooldown it swings again. |

Console: no errors. A side screenshot in Play showed the part-built clippers held in the right hand with the blades forward, the upper handle on top and the jaws opening in a vertical plane.

**Not verified:** the Blender meshes in game (pending import), the template-path grip with real imported meshes, how the WAVs sound, touch devices, a second player watching (pose clips and the jaw are local only), R6 avatars.
