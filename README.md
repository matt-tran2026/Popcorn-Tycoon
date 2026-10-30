# Popcorn Tycoon

Roblox corn-harvesting simulator foundation. The official repository is https://github.com/matt-tran2026/Popcorn-Tycoon and current development uses main directly.

Read GAME_DESIGN.md, ROADMAP.md, ARCHITECTURE.md, and AGENTS.md before development. The current slice is an in-memory owned field with twelve Normal Corn stalks, an owner label, manual harvesting, and timestamp regrowth. Successful harvests update the raw-corn HUD and briefly flash its background. There is no save/rejoin progression yet.

## Studio source setup

Use native [Roblox Script Sync](https://create.roblox.com/docs/scripting/sync). No Rojo project or external runtime backend is required. Mapping:

| Studio Explorer folder | Parent directory to select in Sync to… | Actual script directory |
| --- | --- | --- |
| ReplicatedStorage → PopcornTycoon | src/shared | src/shared/ReplicatedStorage/PopcornTycoon |
| ServerScriptService → PopcornTycoon | src/server | src/server/ServerScriptService/PopcornTycoon |
| StarterPlayer → StarterPlayerScripts → PopcornTycoon | src/client | src/client/StarterPlayerScripts/PopcornTycoon |

All three current connections passed disk-to-Studio and Studio-to-disk probes on October 30, 2026. Preserve these working connections. The exports include service/container directories beneath the selected parents, as shown in the last column; earlier assumptions about the chooser's output layout were superseded by actual probes.

For a fresh setup, use Sync to… on the intended Explorer source tree and select the corresponding parent in the middle column. Inspect the exported hierarchy and use Script Sync → Reveal in Explorer to confirm the resulting script directory matches the last column. Do not create another connection or duplicate source copy if the resulting hierarchy differs; reconcile the actual path first. Inspect conflict previews and choose Keep Disk only when the tracked files are the intended source. The workspace repository root is `C:\Users\matth\Documents\Codex\2026-10-29\i-m-starting-a-new-roblox`.

File mappings: .luau → ModuleScript, .server.luau → Script with Server RunContext, .local.luau → LocalScript. Tests are intentionally outside synced gameplay roots and do not run at startup.

### Required round-trip verification

In Edit mode, after connecting the folders, append a temporary comment to Growth.luau on disk. Read Studio's script to confirm it arrives automatically without an MCP copy. Append a different comment in Studio using the script editor or UpdateSourceAsync and verify the file changes automatically. Remove both temporary comments, confirm identical final sources, and repeat a small round trip for the server and client roots. Check for duplicate script names and disk directories. Record results in docs/testing/STARTER_FIELD.md. These checks passed for all three current connections; repeat them after any remapping. Reopen/automatic-resume verification remains outstanding.

## Play

Press Play in Studio. Walk forward from spawn to the field. Press E near a ready corn prompt, or tap its native prompt on touch devices. Raw corn appears in the HUD. Harvesting consumes all available yields on that stalk, resets its growth, and yields again after the configured cycle. Capacity is initially three; the first starter field begins with one yield per stalk. Play sessions reset on leave.

Tuning lives in src/shared/ReplicatedStorage/PopcornTycoon/Config.luau. The 10-second growth cycle and twelve-stalk layout are temporary prototype choices. Do not infer final economy balance from them.

## Tests

tests/StarterField.server.luau is a Studio-only integration runner. During a disposable Play session, install its exact source as a temporary Server RunContext Script in ServerScriptService named PopcornMilestoneTests. It runs against a live player and the real server services, checks growth boundaries, ownership rejection, range/tool validation, duplicate/immature harvesting, inventory changes, and real-time regrowth, and writes JSON evidence to its Results attribute. It creates and removes a second synthetic owner fixture. It is not a real two-client test. Stop Play to remove the runner and all test mutations. Do not place it in the normal source sync folders.

Use native input separately to verify the ProximityPrompt → server transaction → client HUD path. Results and known limitations are documented in docs/testing/STARTER_FIELD.md.

The latest gameplay verification is in docs/testing/FIRST_GAMEPLAY.md. The focused runner now checks twelve stalks, visible stages, owner labels, disjoint slots, and inventory replication attributes as well as the original growth/security cases.

tests/Multiplayer.server.luau is a separate StudioTestService runner. Install it temporarily as a Server RunContext Script named PopcornMultiplayerProbe in Workspace (outside the synced source trees). From plugin context invoke StudioTestService:ExecuteMultiplayerTestAsync(2, { test = "PopcornOwnership" }) asynchronously. The server runner returns nine checks through EndTest; the plugin caller must collect that return value and remove the Edit-mode temporary probe afterward. It passed with two actual simulated clients in this milestone. Do not leave the temporary test object in a saved place.

### Manual restart and multiplayer checks

Stop Play. Use File → Save to File / Save to File As and save `places/PopcornTycoon-foundation.rbxl` locally (not Publish to Roblox). Close Studio, reopen that exact file, and let native Script Sync resume. Do not stop/recreate/reorganize the existing connections. Inspect conflict previews instead of blindly discarding either version. Ask the agent to repeat a harmless round trip on the existing paths after reopening; a normal Play/Stop cycle is not a Studio restart.

For a manual two-client test, choose Server & Clients in Studio's testing-mode dropdown, set two clients, then press Play or F7. Each player should have a different labelled field and independent inventory. Approach the other player's ripe corn: it must grant nothing. Each player should be able to harvest their own corn, wait ten seconds for regrowth, and harvest it again. End Session closes the simulated clients/server. See [Roblox testing modes](https://create.roblox.com/docs/studio/testing-modes).

On a phone or touch emulator, tap the native harvest prompt and confirm the count changes once, the stalk shrinks/loses its ripe ear, and corn becomes available after ten seconds. Landscape and portrait HUD layout were inspected in the iPhone 17 Pro emulator; a successful touch tap still requires manual verification.

## Git workflow

- Work on main for now. Inspect status/diff and fetch before integrating remote changes; preserve history and never force-push without explicit permission.
- Commit logical tested changes with descriptive messages; push verified milestones, then verify the branch head and files on GitHub.
- Keep code, configuration, tests, and root design documentation under version control. work/ and outputs/ are ignored. Avoid credentials, logs, caches, and machine-specific settings.
- GitHub connection was verified with the initial documentation push. Authentication failures on future pushes must be reported, not described as success.

## Studio asset backups

Script Sync does not back up models, terrain, UI instances, or place settings. Before and after a meaningful Studio asset milestone, stop Play and use Studio's File menu → Save to File / Save to File As (wording depends on version) to save a local snapshot under places/, for example `places/PopcornTycoon-foundation.rbxl`. This is a local save, not Publish to Roblox. Check the file exists and reopens before calling the backup verified. Commit deliberately sized snapshots with the corresponding milestone; if binary files become large, choose Git LFS before adding them. Never replace a known-good snapshot without retaining its Git history.

For the current foundation all new farm geometry and UI are generated by tracked code, but the original place still requires a local snapshot. UI automation could not capture Studio, so no saved place snapshot is currently confirmed. Opening a fresh baseplate and configuring the three script roots can reproduce the code-generated slice; it does not reproduce every existing place setting.
