# Farm upgrades: Backpack, Soil, Yield, Storage (November 4, 2026)

Creator request: four Cash upgrades bought from the HUD's Upgrades button. Backpack Capacity is global; Soil Quality, Corn Yield and Stalk Storage are bought separately for every owned plot. All numbers live in `Config.FarmUpgrades` (shared) and are checked by `Config.validate()` at startup.

## Baseline (unchanged)

An unupgraded Normal Corn stalk grows one cycle every 10 s, each cycle is worth **1** raw corn, and it stores at most **3** cycles, so it holds at most **3 raw corn**. Harvesting takes every whole cycle that fits in the bag and restarts the timer; production past the storage limit is discarded.

## Levels

| Level | Backpack (raw corn) | Soil (growth time, Normal) | Yield (corn per cycle) | Storage (stored cycles) |
| --- | --- | --- | --- | --- |
| 0 | 50 | 10 s | 1 | 3 |
| 1 | 100 | 9 s | 2 | 4 |
| 2 | 200 | 8 s | 3 | 5 |
| 3 | 400 | 7 s | 4 | 7 |
| 4 (max) | 800 | 6 s | 5 | 10 |

`Config.FarmUpgrades.<id>.effects[level + 1]` holds these values. Soil is stored as a percent of the crop's base time (100/90/80/70/60), Yield and Storage as bonuses on the crop's `cornPerYield` and `maxYields`, so a future variety with a different base time or storage scales the same way. Backpack values are absolute; level 0 must equal `Config.Inventory.capacity`.

## Formulas (shared `FarmUpgrades` module)

```
bag capacity          = Backpack.effects[backpackLevel + 1]
growth seconds        = max(Config.Growth.minSeconds, crop.growthSeconds * Soil% / 100)   -- minSeconds = 1
stored cycles         = crop.maxYields + Storage bonus
corn per cycle        = crop.cornPerYield + Yield bonus
ready cycles          = min(stored cycles, floor((now - growthStartedAt) / growth seconds + 1e-6))
max corn on a stalk   = corn per cycle x stored cycles            (before tool multipliers)
corn per harvested cycle with a tool = corn per cycle x tool.yieldMultiplier
```

Examples: Yield 1 + Storage 1 holds 2 x 4 = 8; Yield 2 + Storage 2 holds 3 x 5 = 15; both maxed hold 5 x 10 = 50. A Yield 2 plot with 5 stored cycles gives 15 raw corn; a 2x tool makes that 30.

**Prototype rule (creator):** the plot's current Yield level applies to every stored cycle, including cycles grown before the purchase.

## Harvesting

One function (`HarvestService` `take`) serves hands and every swung tool. It takes `min(ready cycles, floor(free bag space / corn per cycle))` whole cycles, adds their corn, and backdates the stalk's timer so exactly the untaken cycles stay ready. A cycle never leaves a stalk without its full corn; a bag with room for less than one cycle refuses the harvest and the stalk keeps everything. The bag limit always comes from `PlayerStateService.bagCapacity`, so it is the same on every plot.

## Changing growth rules on a planted plot

Stalk state stays one timestamp per stalk; no new checkpoint field was needed. When Soil or Storage changes a plot's rules, every stalk on it is settled at purchase time under the **old** rules and rebased onto the new ones (`Growth.rebase`), inside the same unyielding purchase step:

- ready cycles carry over unchanged (never more than the new storage);
- the unfinished cycle carries over as the same **fraction** of a cycle, so faster soil keeps its progress but never pays out time already spent at the slower rate;
- a stalk that was **full** had stopped growing: it keeps its cycles and no partial progress, so a bigger storage starts its next cycle at purchase time. Growth discarded while full cannot be reclaimed.

Rebasing is O(stalks on the plot), once per purchase, independent of elapsed or offline time. Offline growth will use the same formula from saved timestamps.

## Prices (Cash)

Next level = `Pricing.nice(base * growth ^ current level)`, two significant figures, via `Pricing.upgradePrice`.

| Upgrade | Base | Growth | Lv 1 | Lv 2 | Lv 3 | Lv 4 | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Backpack (once) | 200 | x6 | $200 | $1.2K | $7.2K | $43K | $51.6K |
| Soil (per plot) | 300 | x3 | $300 | $900 | $2.7K | $8.1K | $12K |
| Yield (per plot) | 500 | x4 | $500 | $2K | $8K | $32K | $42.5K |
| Storage (per plot) | 750 | x3 | $750 | $2.3K | $6.8K | $20K | $29.9K |

**Pacing check.** Income today is about $100 per 50-corn bag trip (1 popcorn per corn, $2 per popcorn). The first level of each upgrade sits at one to eight bag trips, like the Sickle and the first row ($200, two trips). Backpack is the main income lever because trips are bag-limited: level 1 doubles a trip to $200, so level 2 ($1.2K) is six trips, level 3 ($7.2K) eighteen $400 trips, level 4 ($43K) about fifty $800 trips. Bigger bags only pay once the plot grows enough corn, which is what Yield and Storage add (36 stalks hold 108 corn at level 0, 216 at Yield 1). Maxing every plot costs about $84K per plot ($760K for nine) plus the Backpack, which lands in the creator's Beginner to Early game bands ($0–10M) next to the land prices (plots $25K–$8.5M). These are provisional; tune after a human pacing playtest.

## Data

`schemaVersion` 3 (profiles are still in memory):

- `profile.upgrades: { Backpack: number }` (was an unused `{ [string]: boolean }`).
- `field.upgrades: { Soil: number, Yield: number, Storage: number }`; every new plot starts at 0.
- `CropDefinition.cornPerYield` (Normal = 1).

`PlayerStateService.migrate(profile)` upgrades a v2 profile in place (numeric levels, clamped to each upgrade's range, malformed values become 0). The future DataStore loader must call it before handing a profile out.

Replicated to the owner's client as player attributes: `BagCapacity`, `Upgrade_Backpack`, `Upgrade_<fieldId>_<Soil|Yield|Storage>`, `Plots`. Stalk parts carry `AvailableYields`, `MaxYields`, `CornPerYield`, `Cobs` and `Full`.

## Purchases and security

Remote `UpgradeRequest(upgradeId, fieldId?)`; answered on `ActionResult` as `"FarmUpgrade"`. The client sends nothing else. `UpgradeService.buyUpgrade` checks, in order: per-player cooldown (`Config.UpgradeMenu.requestCooldownSeconds`, 0.3 s; every request resets it), known upgrade id, loaded profile, scope (global must have no plot; field upgrades need an owned plot id of at most 16 characters), current level and max, price, and Cash balance. It then spends and applies in one unyielding step and publishes the new state. A repeated request is a separate, separately paid purchase of the next level; a burst inside the cooldown buys at most one level.

## Presentation

- **Upgrades menu** (`UpgradesController`, client): studded orange brick panel matching the HUD button, plot picker listing only owned plots, four cards with Blender-rendered icons, level bars, "Now"/"Next" benefit, price button with coin (green when affordable, grey with "Need $X"), MAX LEVEL at the cap. On a confirmed purchase the card bounces, flashes a sunburst and floats the new stat; Cash floats "−$" from the cash bar. Refusals shake the card and show the server's reason. Shared menu pieces moved to `MenuKit` (also used by the Shop).
- **Backpack:** the pack for the player's level hangs on the character's back (massless, non-colliding, welded to the torso).
- **Soil:** each upgraded plot's soil and tilled rows darken per level; from level 2 small decor clumps sit inside the bed edging (Pebbles, then Sprouts at 3, Blossoms at 4; at most 10 per plot). Other plots keep their own look.
- **Yield:** a ripe stalk shows one cob per corn in a cycle (Corn_Cob1..Corn_Cob5) and grows a little taller at levels 3–4. A stalk with no ready cycle shows no cobs.
- **Storage:** a full stalk tints its cobs gold, and the pick badge shows gold pips with a FULL tag. The badge has one pip per stored cycle (smaller past 5) and a "+n" corn count when a cycle is worth more than one.

## Blender assets

Built in the vault's `Assets/Upgrades/UpgradeAssets.blend` (script `Assets/Upgrades/scripts/build_upgrade_assets.py`, previews and icon renders beside it) and exported as `Assets/Upgrades/UpgradeAssets.fbx`: `CS_Stalk` + `Corn_Cob1..5` (the existing lite stalk with its three cobs split apart plus two mirrored cobs), `Backpack_0..4`, `Pebbles`, `Sprouts`, `Blossoms`. All vertex-coloured on one white material, 1 unit = 1 stud. Triangles: stalk 3,102, cobs 770–826 each, packs 412–1,476, decor 80–700. A level-0 stalk draws about 3.9k triangles (the old template drew about 5.5k); a level-4 stalk about 7.1k.

The four menu icons are uploaded image assets (ids in `UITheme.Upgrades` and `assets/ui/manifest.json`). The FBX is **not yet imported** (the 3D Importer needs a person at Studio); until it is, the game uses placeholders: brick packs per tier, studded clumps for soil decor, and the existing three-cob stalk (shown whole when ripe, taller at high Yield). Import steps are in docs/testing/FARM_UPGRADES.md.
