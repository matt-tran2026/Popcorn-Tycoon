# Owner Developer Panel (November 4, 2026)

A Studio-only, Owner-only testing panel that changes the Owner's own live profile so the economy, farming, upgrades, tools and land can be tested without grinding or waiting. It is not a moderation system and has no commands that touch other players. Creator request, November 4, 2026. Test evidence: [docs/testing/DEVELOPER_PANEL.md](../testing/DEVELOPER_PANEL.md).

## Files

| File | Side | Role |
| --- | --- | --- |
| `src/server/ServerScriptService/PopcornTycoon/AdminConfig.luau` | Server only (never replicates) | Owner allowlist by UserId, rank table, Studio test users, environment switch, limits. |
| `src/server/ServerScriptService/PopcornTycoon/AdminService.luau` | Server | Authorization, validation, rate limit, replay guard, the command registry, the Owner's snapshot, the `AdminRequest` remote. |
| `src/client/StarterPlayerScripts/PopcornTycoon/AdminController.luau` | Client | The panel UI (F4 / DEV button), built only after the server confirms an Owner. Fly and noclip. |

Existing services gained small shared commit helpers so purchases and developer commands share one path: `UpgradeService.applyLevel`, `grantRow`, `grantPlot` (the purchase functions now call them after charging), `ToolService.implemented`, `grant`, `revoke`, `FarmService.plotFrame` and `MapVisuals.hubFrame`. `PlayerStateService.publish` now also publishes `RawCorn`.

## Who can use it

1. **Studio only.** `AdminConfig.mutationsAllowed(RunService:IsStudio())` must be true. Outside Studio the server never creates the `AdminRequest` remote, so there is nothing to fire, and `AdminService.handle` refuses every request again on its own. `AdminConfig.allowOutsideStudio` is `false`; keep it that way.
2. **Owner rank, by UserId.** `AdminConfig.rankOf(userId, isStudio, creator)`:
   - an id in `AdminConfig.Members` gets its rank (today only `Owner`);
   - the creator of a **user-owned** experience is Owner (`trustUserCreator`); a **group-owned** experience never grants anything, so group members are not Owners;
   - Studio's simulated test players (UserIds −1, −2, …) only get a rank from `AdminConfig.studioTestUsers`, and only in Studio. Player1 (−1) is Owner so the panel can be tried in a "Clients and Servers" test; Player2 and later stay ordinary players. Negative ids are never real accounts.
3. **Every request** is checked in this order: environment, rank, token bucket, request id, command name, command rank, argument shape, busy flag, profile. The client UI is a convenience only; showing it grants nothing.

### Authorizing an account

Open `AdminConfig.luau` and add a line to `AdminConfig.Members`:

```lua
AdminConfig.Members = {
	[4648453584] = "Owner",
	[<another UserId>] = "Owner",
} :: { [number]: string }
```

A UserId is the number in the profile URL `roblox.com/users/<UserId>/profile`, or run this in Studio's command bar: `print(game:GetService("StudioService"):GetUserId())`. Use UserIds, never names. `4648453584` (tranman2026) is the creator's account, confirmed by the creator on November 4, 2026. A future rank goes into `AdminConfig.Ranks` with a lower power, and a command can then name it in `minRank`.

## Opening and using it

- **Desktop:** press **F4** (again to close; Esc also closes). **Touch:** a small red **DEV** button on the right edge, shown only to Owners on touch-enabled devices. The **X** closes it; **A−** / **A+** change its size; it also scales to the screen.
- Five tabs: **Economy, Farming, Upgrades, Tools, Player**. Every press shows the server's answer in the status line (green or red). Red **destructive** buttons (Zero, Clear, Empty, Reset…) arm on the first press ("Sure?") and run on a second press within 2.5 s. Only one command is in flight at a time, so a double click never runs twice.
- Amount boxes accept `5000`, `1,500`, `$2.5K`, `1M`, `1B`, `1e6`; the server re-checks everything.
- The plot picker is shared by the Farming, Upgrades and Player tabs. **All** applies a farming or field-upgrade command to every owned plot.
- While open, the panel refreshes its plot statistics every 2 seconds. Balances follow the normal HUD attributes immediately.

## Commands

All commands act on the caller's own profile. None charge Cash. Numbers must be finite whole numbers, unless noted otherwise. Amount limits are 1 to `AdminConfig.maxBalance` (10^15, shown as $1Qd), or 0 to that for Set. Balances are clamped at 0 and at the maximum.

| Tab | Command (`AdminRequest` name and args) | Effect |
| --- | --- | --- |
| Economy | `cash.add {amount}` · presets +$1K, +$100K, +$1M, +$1B | Give Cash. |
| | `cash.set {amount}` · `cash.remove {amount}` · `cash.zero` · `cash.max` | Set exactly, remove (never below 0), zero, testing max. |
| | `popcorn.add/set/remove {amount}` · `popcorn.zero` · `popcorn.max` · presets +100, +1K, +10K, +1M | Same for the popcorn balance (the sell stand's payout follows). |
| | `corn.add {cropId, amount}` | Add raw corn of a chosen variety, never above the bag (`PlayerStateService.bagCapacity`). |
| | `corn.fill {cropId}` · `corn.empty` | Fill the bag to its current capacity; empty it. |
| Farming | `field.grow {fieldId}` | Every stalk on the plot gets at least one ready cycle (stalks holding more keep them). |
| | `field.fill {fieldId}` | Every stalk holds the plot's full storage: crop `maxYields` + Stalk Storage bonus, worth `cornPerYield` (crop + Corn Yield bonus) per cycle. |
| | `field.reset {fieldId}` | Every stalk starts a fresh cycle now (no ready corn). |
| | `field.progress {fieldId, percent}` · 0/25/50/75/100 buttons | Every stalk is `percent` (0–100, fractions allowed) through its first cycle; 100 = one ready cycle. |
| | `land.plot` · `land.row {fieldId}` | Unlock the next plot / plant the next row for free, through the pads' own commit (`UpgradeService.grantPlot/grantRow`). |
| | `land.allPlots` · `land.allRows` | Unlock every plot / fill every owned plot's rows, one plot or row at a time (yields between steps; other admin commands wait). |
| Upgrades | `upgrade.set {upgradeId, fieldId?, level}` · `upgrade.step` (+1) · `upgrade.max` · `upgrade.reset` | Backpack is player-wide (no `fieldId`); Soil, Yield and Storage need an owned plot or `*`. Levels 0 to the max in `Config.FarmUpgrades`. Goes through `UpgradeService.applyLevel`, the same commit as a purchase minus the charge: Soil/Storage changes rebase stalks (`Growth.rebase`), attributes refresh the Upgrades menu, visuals follow. Lowering Backpack drops raw corn above the new bag size. |
| | `upgrades.maxAll` · `upgrades.resetAll` | Backpack and every upgrade on every owned plot. |
| Tools | `tool.give {toolId}` · `tool.giveAll` | Ownership through `ToolService.grant` (profile + Tool instance). Only tools in `Config.Tools` with a model builder; future tools appear automatically. |
| | `tool.equip {toolId}` (or `"Manual"` for hands) | Same as the Shop's equip. |
| | `tool.remove {toolId}` · `tool.reset` | `ToolService.revoke`: destroys the Tool and falls back to hands if it was equipped. Hands (Manual) can never be removed. |
| Player | `tp.farm` · `tp.hub` · `tp.plot {fieldId}` | Teleport to the farm entrance (`FarmService.spawnFrame`), the hub spawn (`MapVisuals.hubFrame`) or the front of an owned plot (`FarmService.plotFrame`). |
| | `move.speed {speed}` (16–120) · `move.reset` | Walk speed on the current Humanoid only; a respawn restores normal. |
| | Fly / Noclip toggles | Client-only aids on the Owner's own character: fly (move keys steer, Space up, Ctrl down) and noclip. Undone when switched off or on respawn. |
| (internal) | `hello` · `state` | Handshake and refresh; return the Owner's own snapshot. |

Panel information: Cash, popcorn, raw corn / bag size, held tool, owned plots and rows, every plot's crop, stalk count, rows, Soil/Yield/Storage levels, effective growth time, corn per cycle, stored cycles, max corn per stalk and ready corn; the player's name, UserId, walk speed and the selected plot.

## Safety rules

- Identity comes from the connection. No command takes a target player; an extra `userId` argument is ignored.
- Each request carries an increasing request id. An old or repeated id is refused without running ("Duplicate request ignored"), so a replayed request never grants twice. The reply carries the server's last id so an honest panel can resync. The panel never retries on its own.
- Token bucket: 10 requests at once, refilled at 5 per second (`AdminConfig.rate`). Arguments: at most 8 keys, strings of 32 characters or fewer, only numbers, strings and booleans.
- Unauthorized callers get `Not authorized` with no state. At most one warning line per 10 s per player goes to Output.
- Every executed command prints one line in Studio Output: `[Admin] <name> <command> -> ok/refused: <result>`. No profile dumps.
- Growth is changed only through each stalk's `growthStartedAt` (no new growth system, no per-stalk scripts). `FarmService.update` redraws the stages, cobs, prompts and pick badges on the same tick.
- Normal purchases are unchanged: pads, the Upgrades menu and the Shop still charge their prices. The admin path only calls the shared commit helpers.

## Persistence

Profiles are still in memory (no DataStore; `PlayerStateService` resets on leave), so developer changes vanish when the session ends and cannot touch saved progression. When persistence is added, keep Studio sessions on an isolated test store, or make the admin service refuse to run against production data.

## Limitations

- Rows and buttons have unique names (`EconomyPage.Row4.B_1M`), so Studio automation can click them by instance path; screen-coordinate clicks do not reach GuiButtons in Studio's MCP tools.
- No real two-client run. The unauthorized and Player2 cases were tested at the server entry point with stand-in callers, and isolation with a second-owner fixture profile.
- The phone layout was not checked on a device or emulator. At small scales the buttons get small; A+ helps.
- Fly uses `LinearVelocity`/`AlignOrientation` on the client. It is a test aid, not a game feature.
