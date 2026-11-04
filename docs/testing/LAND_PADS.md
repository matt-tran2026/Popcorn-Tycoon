# Land pads and the 3x3 plot grid — November 4, 2026

## Request

The creator asked to remove the "FOR SALE" sign for the Extra Row and replace it with a purchase pad, allow up to 6 extra rows, add extra plots of corn (up to 8 more), lay the plots out 3x3 on each island with room for 6 extra rows each, and raise the price of rows and plots after every purchase. The creator also asked for help pricing them from the game's economy. Choices made by the creator: step on a pad to buy; plots unlock in a fixed nearest-first order; the 50-corn bag stays as it is (a bag upgrade system comes later). For pricing the creator supplied a progression-stage table and a rebirth table (recorded in GAME_DESIGN.md, "Progression stages and rebirths").

## Change

- **Shared:** `Config.Plot` (6 columns, 6 base rows, 6 extra rows, spacing 5) replaces `Config.Starter`. `Config.Grid.order` lists the nine cells in purchase order. `Config.layoutRows`, `cellSize` and `cellOffset` derive the geometry. `Config.Farm` is 122 × 234 studs. `Config.Map.entranceRadius` is 120 (was 115). `Config.Upgrades.ExtraRow/ExtraPlot` hold base, growth and currency; `Config.Pads` holds the re-arm rule. `validate()` checks that every cell and the station strip fit. SchemaVersion 2. `Types.Field` gains `plot`. New `Pricing.luau`: `nice`, `rowsBought`, `plotsBought`, `rowPrice`, `plotPrice`.
- **Server:** `PlayerStateService` builds fields `Plot1`…`Plot9` with stalk IDs `"<plot>_<n>"` (`stalkId`, `addPlot`). `FarmService` (rewritten) builds owned plots (soil + `PlotBed_n`), locked cells (`LockedCell_n`, 5 parts each) and the pads (`RowPad_<fieldId>`, `PlotPad`), handles pad touches with one attempt per step-on, and re-prices every pad after a purchase. `FarmVisuals` lays out the 3x3 grid with walkways and gains `buildPlotBed` and `buildLockedCell`; the single field border and the FutureExpansion lawn are gone. `UpgradeService` has `buyRow(player, fieldId)` and `buyPlot(player)`. `HarvestService.swing` targets ripe corn on every plot. `Bootstrap` wires the pad handler, drops the `BuyRow` prompt and adds a Studio-only `ServerStorage.DebugGrantCash`. `EnvironmentVisuals` moves the horizon islands out to 470–530 studs.
- **Client:** new `PadController` (green/red by affordability, other players' pads hidden). `PromptController` and `HarvestHighlight` follow the renames; the client `Bootstrap` starts PadController and gives the purchase notice a chime and a floating "−$".
- **Tests:** all five runners moved to `Plot1` / `"1_n"` IDs. Economy replaces the Extra Row section with row-pad, plot-pad, limit and real step-on checks. FarmPlot checks the pads, locked cells and walkways; it also replaces the stale `Counter` check (the Blender sell stand of `b0cb51d` has no part named Counter) with a solid-mesh check on both stations. Multiplayer checks that a second player cannot buy land on the first farm; its join window grew from 25 s to 45 s.

## Prices

price = nice(base × growth ^ already bought), rounded to two significant figures.

| Purchase | Base × growth | Sequence | Total |
| --- | --- | --- | --- |
| Extra Row (54 max, counted across plots) | $200 × 1.16 | $200, $230, $270, $310, $360, $420 (starter's six) … 12th $1.2K … 24th $7K … 36th $42K … 54th $520K | $3,776,550 |
| New Plot (8 max) | $25K × 2.3 | $25K, $58K, $130K, $300K, $700K, $1.6M, $3.7M, $8.5M | $15,013,000 |

## Results (Studio MCP, November 4)

| Check | Result |
| --- | --- |
| StarterField runner | PASS 31/31 |
| FarmPlot runner | PASS 89/89 after the Counter fix (first run stopped at check 4 on it). Walk from the hub spawn over the bridge to the cross path: 14.1 s. All 36 starter stalks walked to and harvested once. |
| Tools runner | PASS 34/34 |
| Economy runner | PASS 59/59: row and plot prices, insufficient cash, unowned or malformed plot, out of range, row planted behind the old rows, pad moves and re-prices, a full plot (12 rows) rejects more, plot purchase plants 6 rows and its own row pad, plot pad moves to cell 3, stepping on a pad buys exactly one row, all nine plots then "Every plot is yours". |
| Multiplayer (`ExecuteMultiplayerTestAsync(2, …)`) | PASS 12/12. First attempt failed "two real simulated clients joined" at the old 25 s window; passed with 45 s. |
| Manual playtest (single client) | Row pad: $200 charged, 6 stalks planted, pad moved to row 8 at $230; all 12 rows then the pad disappears. Plot pad: $25K charged, plot 2 planted with its own row pad ($490); plot pad moved to cell 3 at $58K. Short of cash: one "Need $8K more" notice over 3 s of standing; the pad tinted red, an affordable pad green. Hand pick and sickle swing on plot 2 work; microwave and sell stand still pay out. |
| Max-out | All 9 plots and 54 rows bought in one session: 648 stalks, no pads left. The last 48 rows and 7 plots cost $18,762,760; with the first 6 rows and plot 2 that is $18,789,550, exactly the two table totals. |
| Budget | Starter farm 741 BaseParts (was 619), 3 lights. Open plot 663 BaseParts. Fully bought farm about 5,900 descendants. About 60 FPS in Studio on the creator's PC with one maxed farm. |
| Output | No errors. |

## Not verified / open

- Real phone or tablet: pad touch, readability of the price tags, and frame rate with a maxed farm (648 stalks ≈ 3.2k corn mesh parts per farm; six maxed farms ≈ 19k).
- Human feel: walking time from the back plots to the microwave (≈ 170 studs, about 11 s) and whether step-on buying causes accidental purchases.
- Economy: income is about $100 per bag trip, so plot 2 alone is about 250 trips. The curve assumes the planned bag upgrades and rebirth multipliers.
- Rebirths: not implemented; when they are, decide what they reset and whether land prices should reset with land (they will, since prices derive from owned fields).
- No place snapshot was saved to `places/` for this change.
