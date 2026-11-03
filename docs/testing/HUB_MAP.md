# Hub map — November 3, 2026

## Request

The creator asked for a map with a center island connecting every player's farm from the center, using a hub-and-spoke reference image (hexagonal plaza with a popcorn bucket, bridges out to farm islands across water).

## Change

- `Config.Map`: 6 slots, hub apothem 55, farm entrances on a 115-stud ring, 10-stud bridges, water level -2, 1200-stud ocean. `Config.validate` checks that neighboring plots fit their share of the ring. `Config.Farm.separation` was removed.
- `MapVisuals` (new): hexagonal hub island (grass over a sand shore), ring and spoke paths, a striped popcorn-bucket centerpiece on a plinth, oaks, hay, rocks, a welcome sign, lanterns and an owner sign at each bridge head, six collidable plank bridges with rails, and a grass island under every slot. `farmFrame(slot)` maps the canonical farm frame onto a slot so the entrance faces the hub. The SpawnLocation moves onto the hub.
- `FarmService`: builds each farm in the canonical frame, then pivots it onto its slot. Purchased rows are built the same way and then handed to the farm. Slots are capped at `Config.Map.slots`, and slot signs update on create and remove.
- `EnvironmentVisuals`: the meadow, stream and waterfall are replaced by terrain water (filled in strips), the baseplate lowered and resized as a sand sea floor, and a ring of 20 distant hill islands.
- Tests: footprint-overlap checks replace the X-spacing checks, layout checks use each farm's own frame, and FarmPlot walks from the hub spawn to the farm with PathfindingService.

## Results (Studio MCP Play, single client)

| Check | Result |
| --- | --- |
| StarterField runner | First run: 29/30. "regrown harvest adds one" failed once right after Play started. An isolated repro of the same sequence passed, and two full re-runs passed 30/30. Likely a startup timing hitch; treat as intermittent. |
| FarmPlot runner | PASS 83/83. Pathfinding walk from the hub spawn around the bucket and over the bridge to the entrance took about 11.4 s, then all 36 stalks were walked to and harvested. Hub sign named the owner. |
| Economy runner | PASS 36/36. The fixture farm in slot 1 faces the hub (dot product 1.0); Extra Row is still planted behind row 6 in the rotated frame; slot signs return to "Open plot" after removal. |
| Visual check | Overview shows the hub, six bridges and islands, the owner's farm and a rotated fixture farm both laid out correctly; water and horizon islands render. Map: 252 BaseParts; horizon: 120. |

## Not verified / open

- Multiplayer two-client runner updated but not re-run.
- Climbing out of the water onto an island edge was not tested.
- Max Players is not set by scripts; set it to 6 in Game Settings. A seventh player would get no farm and a server warning.
- The place contains three Sky objects ("Sky", "Stylized", "Simple Sunset Sky"), so the visible skybox is arbitrary.
- Touch input and device performance with terrain water and six full farms.

## Spawn fix (same day)

The creator reported spawning trapped under the bucket. Cause: the place's saved SpawnLocation sits at (0, 0.5, 0), the hub center, and MapVisuals moved it only after the yielding startup work (asset loads, terrain fill). An early joiner loaded at the center before the move, and the bucket was then built around them. `MapVisuals.placeSpawn()` now runs first in the server Bootstrap, before anything yields, and turns the spawn to face the bucket. Fresh Play: the character spawned at (-3.5, 3, -21.5), 22 studs in front of the bucket and facing it, in the Running state, and walked 12 studs forward and 12 sideways without being blocked.

## Open plots show starter farms (same day)

The creator asked for every open plot to look like the starter farm a new player receives. FarmService now builds `Workspace.PopcornOpenPlots/OpenPlot_<slot>` for each free slot at startup: soil, the full FarmVisuals scenery with an "Open Farm" entrance sign, and 36 ripe corn meshes. There are no prompts, row "FOR SALE" sign, player state or growth updates. `FarmService.create` destroys the slot's open plot before building the owned farm; `FarmService.remove` rebuilds it.

| Check | Result |
| --- | --- |
| Startup | 5 open plots beside the player's farm, 0 prompts, 2,490 open-plot BaseParts; 3,455 BaseParts in the whole workspace. |
| StarterField runner | PASS 31/31. Open plots went 5 → 4 while the fixture farm held a slot and back to 5 after removal. |
| FarmPlot runner | PASS 84/84, including "open slots show starter farms without prompts" and the hub-to-farm pathfinding walk. |
| Visual check | Overview shows a farm on all six islands; close-up of an open plot shows the "Open Farm" sign, stations and ripe corn. |

Not re-run for this change: Economy and Multiplayer runners. Real-device performance with six full farms is unmeasured.
