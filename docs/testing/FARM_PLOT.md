# Reusable player farm plot — November 1, 2026

## Scope and setup

Connected through Roblox Studio MCP to Popcorn Tycoon.rbxl in Edit mode. Inspected all eight existing runtime sources, the workspace, and the four root planning documents. Local main began clean at c6b550f. Local tracked source remains authoritative; none of the three native Script Sync connections or directories was changed.

Added one stateless server module, FarmVisuals, and integrated it into FarmService. Config defines a 60-by-54 plot with 72-stud slot spacing. Existing harvest validation, player state, growth math, bootstrap and client HUD are unchanged. The supplied image guided arrangement and palette; its currency amounts, UI, cliffs, trees, waterfall and surrounding world were not implemented.

## Created runtime objects

Each Workspace.PopcornFarms.Farm_<userId> retains Soil, twelve Stalk/Ear pairs and native harvest prompts. Each stalk gains four leaves controlled by the existing stage update. Soil.OwnerLabel remains compatible with existing tests and adorns the entrance owner sign.

Scenery groups: GrassFoundation, Paths, FieldBorders, PerimeterFence, MicrowaveStation, SellStand, FutureExpansion, GardenDetails (ToolShed removed Nov 3 2026). They contain wood fencing/signs, dirt and stepping stones, a covered microwave display, a pitched-roof shed with three tool silhouettes, dashed expansion boundaries, barrels, hay, grass and flowers. Stations are labelled display-only/future; no new interactions, fields or purchases exist. Geometry is generated at Play time and cleaned up with the player's farm, so it is not a permanent Edit-mode farm model.

Per plot: 339 BaseParts, 379 total descendants, two shadowless PointLights, twelve ProximityPrompts, no scripts or particles. Decoration disables collision, touch and query; only the new grass foundation collides. The entrance is ten studs wide, and stalk centers remain five studs apart. The plot reserves its right lawn for future expansion. Expanding beyond its footprint requires a deliberate spacing change.

## Observed results

| Test | Result |
| --- | --- |
| Native Script Sync | Modified Config/FarmService and new FarmVisuals arrived automatically from disk. All nine final runtime sources matched normalized local source before final Play and after stopping. No MCP source-copy fallback. |
| Existing StarterField runner | PASS 30/30, including boundary/cap calculations, ownership/range/tool/malformed requests, duplicate rejection, inventory, visible growth stages and actual ten-second regrowth. Passed again on final synchronized source. |
| New FarmPlot runner | PASS 31/31 on final source. Actual Humanoid:MoveTo traversal from spawn through the entrance/cross path and through all three rows, registered prompts and successful server harvest at all twelve stalks, exact inventory total, bounded scenery/lights, no decorative collision obstacles or scripts. |
| Native input | E-key via Studio MCP increased raw corn 39 → 42 and displayed +3 corn / stalk regrowing feedback in the iPhone emulator. This uses the real prompt-to-server-to-HUD path; it is not a touch tap. |
| Real multiplayer | Native StudioTestService launched two simulated client DataModels. PASS 11/11: independent profiles/owners/inventory, complete decorated bounding boxes separated by more than eight studs, twelve prompts each, bidirectional foreign-field rejection, successful independent harvesting and inventory attributes. |
| Visual review | Inspected overhead and entrance/near-field views. Fixed grass being hidden below the original baseplate, mirrored layout to put corn on the visitor's left, and raised dirt/expansion markings above the grass. Final screenshot confirmed visible dirt/stone paths and separate decorated plots. |
| Mobile layout | iPhone 17 Pro landscape inspected; portrait 401×778 viewport inspected, HUD TextFits=true at approximately 361×88. Native touch movement/jump controls visible in portrait. Camera rotation is needed to see the full plot on a narrow screen. |
| Output and cleanup | Final single-player Output contained only normal bootstrap messages, PASS 30 and PASS 31. No relevant runtime errors observed. Stopped Play, reset simulator to default landscape, removed temporary multiplayer probe, verified no runtime farms/test runners remained in Edit. |
| Git checks | git diff --check passed; fetched origin and confirmed no remote divergence before committing. |

The first Play started before one path-height disk change reached Edit, so its path visual was stale. The final run was preceded by a complete source comparison, then both single-player runners were repeated. Final multiplayer used the updated paths. Earlier screen captures during the synthetic-owner regression show a second fixture farm; those images alone are not multiplayer proof. The separate StudioTestService run provides real two-client evidence.

## Limitations and manual checks

- Actual touch prompt tapping is still unverified. Phone emulation and successful keyboard input do not prove touch interaction or mobile performance.
- No real-device frame-rate/network benchmark or high-player-count stress test was performed. The measured part count is a composition bound, not a performance guarantee.
- Scenery uses simple native parts and materials. Crops/tools remain stylized placeholders; the surrounding baseplate and original global lighting are retained. Lanterns provide local warm accents. Fences/buildings intentionally permit walking through them to avoid collision snags.
- No microwave conversion, tool purchases, expansion purchases, persistence, plaza, pets, or publishing.
- Creator reported saving the pre-change backup, but the requested local places folder was empty on inspection. Saved location and reopenability were not independently verified. The creator also confirmed saving places/PopcornTycoon-farm-plot.rbxl after testing, but Get-Item still reported that exact path missing. Both saves are user-reported; no binary snapshot could be included in the commit. Controlled close/reopen and sync-resume verification remain outstanding.

Manual review: press Play, walk through the gate and between all rows, harvest with E and with a real touch tap, wait ten seconds and harvest again. Inspect signage and shed/microwave proportions in normal third-person view. In Server & Clients with two clients, visit the other farm and verify no corn is granted. Stop Play before saving a local place snapshot. Preserve all current sync connections.

## Reproduction

Run tests/StarterField.server.luau as a temporary Server RunContext Script in ServerScriptService during Play. After its Results attribute reports success, run tests/FarmPlot.server.luau the same way with the player at the normal spawn (the first runner restores its starting pivot). It walks the actual avatar and modifies only disposable session state. Read the Results attributes and Output, then stop Play.

For two clients, use tests/Multiplayer.server.luau as documented in README. Remove its temporary Edit-mode Workspace probe after collecting ExecuteMultiplayerTestAsync's returned result. Never put these runners into the production sync roots.
