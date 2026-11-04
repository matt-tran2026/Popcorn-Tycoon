# Farm upgrades: test evidence (November 4, 2026)

Setup: Roblox Studio `Popcorn Tycoon.rbxl`, one local player in Play (Server DataModel), native Script Sync live for all three roots. Design and formulas: docs/design/FARM_UPGRADES.md.

## How the runners were run this time

The Studio MCP Luau sandbox now refuses to parent or `require` scripts (`cannot reparent ... Capabilities property: Network`), so the old "create a temporary Script during Play" step fails. Instead each runner was created in **Edit** mode with the Studio MCP `multi_edit` tool at `ServerScriptService.PopcornTestRunners.<Name>` (outside the synced `PopcornTycoon` folder), enabled one at a time, and run by starting Play. All runners now wait for the first player's profile, farm and character, so they work both as Play-start scripts and mid-session. The folder was deleted afterwards; the place holds no test scripts.

## Results (final code)

| Runner | Result | Notes |
| --- | --- | --- |
| `tests/FarmUpgrades.server.luau` (new) | **63/63 pass** | Final run after every fix. Earlier runs found two problems, both fixed: hand picks reported "Harvested" instead of "Bag full" on a partial pick (compared corn to cycles), and the runner itself needed to buy the Sickle through ToolService. |
| `tests/StarterField.server.luau` | **31/31 pass** | Growth boundaries, ownership, stages, real-time regrowth. |
| `tests/Tools.server.luau` | **34/34 pass** | Sell stand, Shop, sickle sweep and partial bag. |
| `tests/Economy.server.luau` | **59/59 pass** | Microwave, popcorn flight, settle on leave, rows, plots, real step-on pad. |
| `tests/Multiplayer.server.luau` | **not run** | Needs StudioTestService's two-client mode, which the sandboxed MCP Luau cannot start. The FarmUpgrades runner covers ownership with a second-owner fixture profile (simulated, not a second client). |
| `tests/FarmPlot.server.luau` | not run | No farm geometry changed beyond soil colours and decor. |

What FarmUpgrades covers, by the request's checklist:

1. All four upgrades bought (Backpack to max; Soil, Yield, Storage on plot 1; Yield on plot 2). 2. Exact Cash deductions ($200, $1,200 burst, $300 …). 3. Insufficient funds refused with "Need $50 more", nothing changed. 4. Max level refused without charge. 5. Bag capacity 50/100/200/400/800 and the `BagCapacity` attribute. 6. Hand picks respect the bag in whole cycles. 7. Sickle swings respect the bag in whole cycles. 8. Soil 10/9/8/7/6 s. 9. Corn per cycle 1–5. 10. An unupgraded stalk holds 3 raw corn. 11. Storage 3/4/5/7/10 cycles. 12. 8 and 15 corn combinations, 50 maxed. 13. Storage on a full stalk keeps the old limit (no reclaimed growth), deterministic and live. 14. Soil keeps ready cycles and the partial-cycle fraction, and pays nothing retroactively (2.95 cycles stays 2 at 9 s). 15. A partial pick leaves the uncollected cycle on the stalk; a cycle that does not fit is not consumed. 16. Sickle multiplier 2 × Yield 3 corn × 2 cycles × 3 stalks = 36. 17. Plot 2 keeps its own levels and soil look. 18. Backpack limit applies on plot 2. 19. A new plot starts at level 0. 20. A new row on an upgraded plot starts one 9 s cycle old with its plot's storage and yield. 21. A second owner's plot levels never move, and an unowned plot id is refused. 22. A burst of five requests buys one level and charges once; a request inside the cooldown is refused. 23. No negative Cash or inventory. Also: unknown, numeric and table upgrade ids, missing or oversized plot ids, a plot sent with a global upgrade, level clamping (NaN, negative, huge, string), the growth floor, v2 → v3 migration, visuals (no cobs on an unripe stalk, FULL state, prompt "15/15 corn", richer soil on the upgraded plot only), and price display ($2.3K, $4.05K …).

24–25. Microwave, selling and field expansion: Economy 59/59 and Tools 34/34 above.

26. UI shows server-confirmed values: real clicks through the Studio MCP mouse tool on the HUD Upgrades button and card buttons (with test Cash from a temporary Studio-only fixture) bought Backpack to max, Soil 2, Yield 2, Storage 1. Afterwards every card's level, "Now", "Next" and button text matched the server's `Upgrade_*` attributes; the bag meter read 0/800; a short-on-Cash click showed "Need $4.05K more · sell popcorn at the stand"; all four icons reported `IsLoaded`. The close button closes the menu. This pass found that `Money.short` printed $2,300 as "$2.29K" (a float truncation bug that also affected land prices); fixed and covered by the runner.

27. Mobile: **not verified on a device or the emulator** (desktop control of Studio was not available). The panel is laid out at 640×460 and scaled to the safe area like the Shop; on a 677×280 phone-landscape safe area that is a scale of about 0.52, so card buttons are about 70×20 px, below a comfortable touch size. Treat phone usability as open.

Other observations: the level-4 placeholder pack rode on the character's back while walking with no effect on movement; no Output errors in any run. Pressing Escape in Play opens Roblox's own menu first (the existing panels behave the same).

## Not verified

- Blender assets in Studio: the FBX is exported but not imported (see below). Placeholders were what ran in these tests.
- Real two-client play, touch input, real devices, frame rate with many upgraded stalks.
- Persistence and save/rejoin (profiles are still in memory; the migration function is tested on a table only).
- Human pacing of the prices.

## Importing the Blender assets (manual step)

1. In Studio (Edit mode): Home → Import 3D → choose `Assets/Upgrades/UpgradeAssets.fbx` in the vault (`Popcorn Tycoon/Assets/Upgrades/`). Keep "Upload to Roblox" on, name the import `UpgradeAssets`, Import. It lands in Workspace.
2. Paste this in the Command Bar and press Enter (it keeps the old stalk as `CornStalk_3Cob`):

```lua
local src = assert(workspace:FindFirstChild("UpgradeAssets"), "Import UpgradeAssets.fbx first")
local templates = game.ServerStorage:WaitForChild("PopcornTemplates")
local function take(name)
	local p = src:FindFirstChild(name, true)
	assert(p and p:IsA("MeshPart"), "missing " .. name)
	p.Color, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = Color3.new(1, 1, 1), true, false, false, false
	return p
end
local old = templates:FindFirstChild("CornStalk")
if old then old.Name = "CornStalk_3Cob" end
local corn = Instance.new("Model")
corn.Name = "CornStalk"
local stalk = take("CS_Stalk")
stalk.Name, stalk.Parent = "Stalk", corn
for i = 1, 5 do take("Corn_Cob" .. i).Parent = corn end
corn.PrimaryPart, corn.Parent = stalk, templates
local packs = Instance.new("Model")
packs.Name = "Backpacks"
for i = 0, 4 do take("Backpack_" .. i).Parent = packs end
packs.Parent = templates
local decor = Instance.new("Model")
decor.Name = "SoilDecor"
for _, n in { "Pebbles", "Sprouts", "Blossoms" } do take(n).Parent = decor end
decor.Parent = templates
src:Destroy()
print("Upgrade templates ready")
```

3. Save the place (Ctrl+S). Templates live only in the place file.
4. Play and check: packs face outward on the back (if a pack faces the torso, its mesh came in rotated 180°; tell Claude and the weld gets a turn), ripe stalks show 1 cob at Yield 0 and up to 5 at Yield 4, soil decor sits inside the bed edging from Soil 2.
