# First gameplay milestone — October 30, 2026

## Review and scope

Read the four root planning/instruction files and inspected the eight existing Studio scripts and hierarchy through MCP. The existing slice already provided schemaVersion 1 memory profiles, owned farms, per-stalk timestamps, capped yields, visible growth stages, native manual prompts, server validations, and inventory/HUD feedback. Reused those systems rather than replacing them.

All three established Script Sync connections and source directories were preserved. No connection was stopped, recreated, or reorganized. The project was Place1 in Edit mode, with the existing baseplate/spawn/lighting and eight gameplay scripts. No place snapshot existed under places/ at this check.

## Changes

- Config.luau: starter grid expanded from 3-by-3 to 3-by-4 (twelve stalks); growth remains a configurable ten seconds with maximum three yields.
- FarmService.luau: simple BillboardGui owner label on the existing soil part; optional owner display name passed by the server bootstrap.
- Server Bootstrap: passes the actual player's DisplayName to the farm renderer.
- Client Bootstrap: one cancellable 0.4-second background-color tween confirms successful harvests. Rewards still come exclusively from the server.
- Existing tests/StarterField.server.luau extended to thirty checks.
- New tests/Multiplayer.server.luau exercises two actual simulated client DataModels through native StudioTestService.
- Updated GAME_DESIGN.md, ARCHITECTURE.md, ROADMAP.md, and README.md to reflect the current slice and manual verification steps.

No microwave, flamethrower, mutations, quests, shops, advanced UI, DataStore access, or publishing was added.

## Executed tests

### Native source synchronization

Made gameplay source changes on disk only, then read all eight Studio sources through MCP and compared their full contents with the local files: eight of eight matched automatically before Play. Rechecked after Play/Stop: eight of eight still matched. No source-copy fallback was used. This verifies the current live connections, not Studio-restart resumption.

### Single-player Play and native keyboard input

Started a fresh MCP Play session. The actual player received Farm_<UserId> with the correct OwnerUserId, a matching display-name label, and twelve stalks. Moved the character near corn for testing, sent a native E keypress, and observed RawCorn rise from zero to two with the server-confirmed harvest message in the client HUD. The yield count was two because two growth cycles were available at that time.

A later E-key harvest increased the displayed inventory from six to nine. A temporary client observer detected the green harvest-flash color. The observer and test camera existed only in the disposable Play session and were removed when Play stopped.

### Thirty server integration checks: PASS

Ran the exact tests/StarterField.server.luau source as a temporary Server RunContext Script in the live server. It reported PASS 30 checks:

- Zero/negative elapsed time, just-before/exact maturity, partial cycles, very long absence capacity, and stable repeated pure calculation.
- Version 1 profile contract, twelve separately timed stalks, immediately available starter corn, and non-aliased profiles.
- Disjoint farm slots, distinct owners, correct owner label, middle/late visible growth stages, and hidden immature ears.
- In-range foreign-field rejection, malformed target rejection, distance rejection, and invalid equipped-tool rejection.
- Exact capped yield grant, matching inventory attribute, immediate replay rate limiting, and no second grant after cooldown while immature.
- Visual reset, discarded fractional remainder, actual elapsed ten-second regrowth, successful reharvest, and no popcorn grant.
- Cleanup of the synthetic second-owner profile/farm.

This runner uses one real player and a synthetic ownership fixture. The separate two-client test below validates real multiplayer assignment/isolation.

### Two actual simulated clients: PASS nine checks

Consulted the current official StudioTestService documentation and invoked ExecuteMultiplayerTestAsync with two clients from plugin context. The temporary Workspace server runner returned launched=true, passed=true, and nine passing checks:

1. Two actual client DataModels joined the server.
2. Player profiles and raw-corn inventories were distinct.
3. Each player owned their assigned field.
4. Their field positions did not overlap.
5. First player could not harvest the second player's field while in range.
6. Second player could not harvest the first player's field while in range.
7. First player's valid harvest affected only their inventory.
8. Second player's valid harvest affected only their inventory.
9. Both players' replicated inventory attributes matched their independent state.

These tests drive the real server HarvestService with actual players; they do not pretend to be manual UI interaction in both client windows. The session ended through EndTest and Studio returned to Edit mode. Collected the returned result and removed the temporary Edit-mode Workspace script after verifying its name, class, and exact test source.

### Phone emulator layout

Used StudioDeviceSimulatorService with the dynamically listed iPhone 17 Pro preset (874-by-402 logical landscape preset, 460 DPI). Game ScreenOrientation was Sensor; runtime HUD ScreenInsets was CoreUISafeInsets. Inspected screenshots in landscape and portrait. HUD text fit in both: landscape panel 520-by-88; portrait panel approximately 361-by-88. Touch controls were visible in the landscape view. Owner labels can leave the screen when their farms are near the camera's edge; no custom touch controls were added.

A mouse-to-native-prompt GUI-path probe returned tool success but did not change inventory. Billboard GUI screen targeting through that path did not establish a successful touch tap. Actual tapping remains unverified; do not describe the phone gameplay path as passed based only on layout or E-key testing.

Stopped Play and reset simulation to the default Studio viewport. Temporary test mutations and client/server observers were removed.

### Output and cleanup

Single-player Output contained only server/client ready messages and PASS 30 checks, with no relevant gameplay runtime errors. The multiplayer runner returned a complete passing result. A device-inspection command queried an unsupported GetCurrentDeviceAsync member inside pcall; this was a caught inspection error, corrected by using documented GetDeviceInfoAsync/SetDeviceAsync/SetOrientationAsync methods. It did not originate from gameplay code.

Verified the single-player test runner and runtime farms were absent after Stop. Verified the temporary multiplayer Workspace probe was removed after collecting its result. No syncing roots or unrelated Studio content were modified.

## Outstanding checks and manual steps

### Save/reopen and sync resumption

Requires manual action because native window capture/input previously failed in this environment. In Edit mode, use File → Save to File / Save to File As to save `C:\Users\matth\Documents\Codex\2026-10-29\i-m-starting-a-new-roblox\places\PopcornTycoon-foundation.rbxl` locally. Close Studio and reopen that exact file. Allow existing sync connections to resume; inspect any conflict preview without recreating mappings or blindly overwriting changes. Tell the agent after reopening so it can repeat a harmless round trip. A Play/Stop cycle does not prove restart behavior. No local saved-place backup or restart has yet been verified.

### Manual gameplay

- Walk from spawn to your labelled field and harvest several stalks with E. Confirm each action adds only its available yield, the ear disappears/stalk shrinks, and the HUD flashes.
- Attempt another action on the same stalk immediately and after the short input cooldown; neither should add corn before maturity.
- Wait ten seconds, confirm the mature yellow ear returns, and harvest again. After thirty seconds unharvested corn should cap at three yields.
- On touch hardware/emulation, tap the native harvest prompt and repeat those observations.
- For a visual two-client pass, choose Server & Clients in the testing dropdown, select two clients, and press Play/F7. Confirm both labelled fields and independent HUD counts; try each other's corn. End Session closes the test.

In-memory progress intentionally resets on leave. Persistence, cross-session offline growth, full static type diagnostics, real-device mobile performance, and reconnect/respawn stress testing are not verified here. Complete place backup/reopen and touch input checks before marking every M1/M2 acceptance gate complete.

## Next milestone

Close the outstanding manual checks, then define the M3 microwave batch/capacity/timing rules and first-upgrade pacing before implementing conversion and popcorn currency flow. No M3 gameplay was included in this change.

References: [Roblox testing modes](https://create.roblox.com/docs/studio/testing-modes), [StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService).
