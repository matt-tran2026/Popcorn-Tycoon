# Owner Developer Panel: test evidence (November 4, 2026)

Setup: Roblox Studio `Popcorn Tycoon.rbxl` (unpublished, PlaceId 0), one local player in Play Solo, native Script Sync live for all three roots. The Play Solo player is the Studio account (UserId 4648453584, the allowlisted Owner). Design: [docs/design/DEVELOPER_PANEL.md](../design/DEVELOPER_PANEL.md).

## How the runners were run

As in docs/testing/FARM_UPGRADES.md, each runner was created in **Edit** with the Studio MCP `multi_edit` tool outside the synced folders: server runners at `ServerScriptService.PopcornTestRunners.<Name>`, the client runner at `StarterPlayer.StarterPlayerScripts.PopcornTestRunners.AdminClient`. Each Studio copy was checked byte-for-byte against the repo file (byte count and byte sum), and runners were run one per Play. FarmPlot does not wait for the player, so it was installed disabled and enabled from the Server DataModel once the farm existed. All runner folders were deleted afterwards. The MCP Luau sandbox can neither `require` game modules nor invoke remotes ("Capabilities property: Network"), which is why the network path has its own LocalScript runner.

Before and after the runs, every source in the three synced roots (39 scripts) matched the disk files by byte count and byte sum.

## Results

| Runner | Result | Notes |
| --- | --- | --- |
| `tests/Admin.server.luau` (new) | **108/108 pass** | First run. Authorization policy, unauthorized callers at the remote's entry point, validation, replay, rate and busy limits, every command group, HUD attributes, ordinary harvest/swing/purchase afterwards, isolation from a second owner. |
| `tests/AdminClient.client.luau` (new) | **16/16 pass** | Real `AdminRequest` calls over the network from the client: the panel exists for the Owner, $1M / 250 popcorn / full bag / Backpack max update the attributes **and the normal HUD labels** (`$1M`, `250`, `50/50`), replays, NaN, infinity and negative amounts refused over the wire, amount parser. |
| `tests/FarmUpgrades.server.luau` | **63/63 pass** | Unchanged runner, after the `UpgradeService.applyLevel` refactor. |
| `tests/Tools.server.luau` | **34/34 pass** | After the `ToolService.grant/revoke` additions. |
| `tests/Economy.server.luau` | **59/59 pass** | Pad purchases now commit through `grantRow`/`grantPlot`; includes a real step-on pad. |
| `tests/StarterField.server.luau` | **31/31 pass** | Includes real-time regrowth and the `RawCorn` attribute (now also published by `PlayerStateService.publish`). |
| `tests/FarmPlot.server.luau` | **FAIL at check 1 (pre-existing)**, then **89/89** with one budget raised | `bounded plot geometry and lights` expects ≤ 780 farm parts. The farm now has 849, all from the five-cob Blender `CornStalk` template (6 parts per stalk instead of 3, +108). It arrived with the farm-upgrades commit `2828185`, after which FarmPlot was recorded as "not run". Nothing in this change adds farm geometry. A Studio-only copy with the limit at 860 passed all 89 checks (hub-to-farm walk 13.9 s; all 36 stalks walked to and harvested once). The repo runner was **not** changed. Updating its budget is left for the creator to decide. |
| `tests/Multiplayer.server.luau` | **not run** | Needs StudioTestService's two-client mode, which the sandboxed MCP Luau cannot start. |

## What the admin runners cover (request checklist)

Permissions: 1. the allowlisted Owner gets the panel UI and every command; 2–3. an ordinary caller (UserId 123456789) is refused all 39 commands at `AdminService.handle`, the function the remote's `OnServerInvoke` calls, with no state returned. Studio test Player2 (−2) is refused too, and nothing changes; 4. `mutationsAllowed(false)` is false. **Not tested live:** a real non-Studio server (a published place was not used). The remote is only created when `mutationsAllowed` is true, and `handle` re-checks it on every request.

Economy: 5. Cash give/set/remove/zero/max, clamped at 0 and at $1Qd; 6. popcorn give/set/remove/clear, and the sell stand's payout text follows; 7. raw corn add; 8. fill respects the bag (50, and 800 at Backpack max), adding to a full bag is refused, lowering Backpack drops the excess; 9. `Cash`, `Popcorn`, `RawCorn`, `BagCapacity` attributes and the HUD labels update at once. Refused: NaN, ±infinity, negative, fractional, above max, strings, booleans, 0 for Give.

Farming: 10. Grow makes all 36 stalks harvestable and draws them ripe (stage 3); 11. Fill reaches 3 cycles unupgraded and 10 cycles × 3 corn = 30 per stalk with Storage max and Yield 2; 12. Reset clears every ready cycle and redraws seedlings; 13. stalk attributes (`GrowthStage`, `AvailableYields`, `Full`, `CornPerYield`) update on the same tick; 14. a normal hand pick afterwards takes one cycle into a bag with room for one and leaves two on the stalk; a normal Sickle swing still harvests; 15. 90% progress finishes in real time (~1 s) and then reads exactly one cycle. Refused: unowned plot, numeric/missing plot id, percent 101, NaN, −1.

Upgrades: 16. Backpack set/+1/max/reset with `BagCapacity` 200 → … → 800 → 50; 17. Soil max gives 6 s cycles and keeps full stalks full (rebase); 18. Yield 2 gives 3 corn per cycle; 19. Storage max gives 10 stored cycles; 20. Backpack limits inventory; 21. a second plot stays at Storage 0 while plot 1 is maxed. `*` applies to all plots; Max all / Reset all; no Cash charged; then an ordinary `buyUpgrade` still charges $300. Refused: level 99, −1, 1.5, unknown upgrade, field upgrade without a plot.

Tools and land: 22. give Sickle (profile, `Owned_Sickle`, Tool in the backpack), give again refused, unknown/unfinished tools refused; 23. equip; remove while equipped falls back to hands with no Tool left behind, hands cannot be removed, reset; 24. Unlock All Plots stops at 9 (8 bought), no plot pad remains, another plot is refused; 25. a free row plants 6 valid stalks; Fill All Rows gives every plot 12 rows and rows × columns stalks with no row pads; 26. Economy's ordinary pad purchases and harvesting pass (above). While Unlock All Plots ran, another command was refused as busy.

Multiplayer: 27–28. a second owner's fixture profile (Cash, popcorn, corn, upgrades, tools, plot count, every stalk timestamp) is unchanged after all owner commands. An extra `userId` argument is ignored. This is a simulated second owner, not a second client.

Teleport and movement: farm entrance, hub and selected plot within 6 studs of the target. Unowned plot refused. Walk speed 64, out-of-range 5000 and NaN refused, back to 16.

## Real clicks through the panel

`user_mouse_input` with an **instance_path** clicks GuiButtons (screen coordinates do not; a coordinate click on the HUD's Shop button did nothing either). Rows and buttons got unique names (`EconomyPage.Row4.B_1M`) for this. In one Play session, after F4: **+$1M** → HUD `$1M` and the Shop "!" badge; **Zero** pressed once only armed ("Sure?", "Press again to confirm: Zero", no command in Output), pressed twice ran exactly one `cash.zero`; **+$1M** again; tab **Upgrades → Max All Upgrades** → bag meter `0/800`, plot 1 Soil/Yield/Storage 4; tab **Farming → Fill All Stalks to Maximum** → "Filled Plot1 · 50 corn per stalk", plot info "6 s per cycle · 5 corn per cycle · stores 10 cycles = 50 max corn per stalk · Ready now: 1800 corn on 36 stalks (36 full)"; tab **Tools → Give, Equip** (Sickle) → `EquippedTool` Sickle; tab **Player → Speed 64** → WalkSpeed 64; **Fly** on → holding Space for 1 s rose 61 studs; **Fly** off → PlatformStand false, fly constraints removed, landed and Running; **Noclip** on → 0 colliding character parts; off → 3 restored; **X** closed the panel. Output showed only the matching `[Admin]` lines.

## Visual checks

Screenshots in Play (desktop viewport 1549×583): F4 opened the panel through the MCP keyboard tool. The Economy, Farming, Upgrades, Tools and Player tabs render in the studded brick style (Fredoka One, black outlines, chunky buttons, Owner · Studio only chip), with readable plot stats and level labels. The farm showed ripe cobs after admin growth and the HUD matched the cleaned-up balances. Output showed no errors in any run, only the one-line `[Admin]` logs.

## Not verified

- The panel's stale-id resync (the server returns `lastId`, the panel skips ahead) was added after the Admin and AdminClient runs; it changes only an already-refused reply and was not exercised (a fresh panel never needs it).
- Every button by hand. The click run above covered one or more buttons on every tab, the confirmation and fly/noclip; the rest were covered through the same remote by the runners.
- A real two-client session, a real non-Studio server, touch devices or the device emulator (DEV button, small-screen scale), and the A−/A+ size buttons.
