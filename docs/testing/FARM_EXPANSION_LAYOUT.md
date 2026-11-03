# Starter field 6x6 and expansion layout — November 3, 2026

## Request

The creator asked for a bigger starter field (6 by 6). Expansions go to the left of the original field. The microwave and tool shed move to the front of the farm and face the field, so purchased rows are added toward the back. A reference image (wooden farm with popcorn, sell and tools stands in front of the field and a "next plot" on the left) guided the arrangement.

## Change

- `Config.Starter`: 6 rows × 6 columns planted, 7 layout rows (one reserved for Extra Row at the back).
- `Config.Farm`: plot 82 × 72 studs, slot separation 92, field origin `(0, 0, 53.5)` so the entrance lines up with spawn, plot offset `(19, 0, -8.5)`. `Config.Farm.size` was removed; FarmService derives the Soil size from the starter layout.
- `FarmVisuals.build` now returns `(ownerSign, microwaveFront)`. Stations are authored facing -Z and turned 180° around their anchors so they face the field (meshes included). Station and shed title signs are lettered on both faces. The expansion lawn has the same footprint as the starter field and sits to its left, with a side path between them. Fence runs use ~9-stud spans to stay within the part budget.
- `FarmService` places the microwave interaction door from `microwaveFront`; `ConversionService` fans popcorn landings along the door's facing instead of a hard-coded -Z.
- `EnvironmentVisuals`: the two entrance oaks moved to x = -32 and 65 so they do not overlap the larger fence.

## Results (Studio MCP Play, single client)

| Check | Result |
| --- | --- |
| StarterField runner | PASS 30/30 (36 timed stalks, fixture farm in the next slot) |
| FarmPlot runner | PASS 82/82: 573 BaseParts, 2 lights, 36 harvest prompts, no scripts, no collision obstacles. Stations stand in front of the field, microwave faces +Z, lawn lies left of the field. Humanoid:MoveTo from spawn through the entrance and cross path to all 36 stalks, each harvested once. |
| Economy runner | PASS 36/36, including a new check that all burst pieces land on the field side. Extra Row plants row 7 (stalks 37–42) behind row 6; 601 BaseParts afterwards. |
| Visual check | Screenshots from the entrance, from the field and from above: stations face the field with readable signs, field back-right, lawn back-left, row 7 at the back. |

## Not verified

- Multiplayer two-client runner (StudioTestService) was updated for the new counts but not re-run.
- Pacing: with 36 ready stalks a full 50-corn bag comes much sooner; the 100-popcorn Extra Row price was not retuned.
- Touch input and device performance with 36–42 corn meshes per plot.
