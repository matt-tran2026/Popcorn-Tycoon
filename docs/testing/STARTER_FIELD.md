# Starter-field foundation verification

Session: GitHub setup and first gameplay foundation, October 29, 2026 (creator's timezone).

## Environment

Studio target: Place1, PlaceId/GameId 0 at initial inspection. Started a disposable Play session using Studio MCP with one real local player (tranman2026). Server Bootstrap uses Server RunContext; client Bootstrap is a LocalScript. Source consists of eight Luau files under src/. No publishing or DataStore access was performed.

## GitHub documentation upload

- Initialized the existing workspace as a Git repository on main; remote was empty.
- Repository-local author identity uses the connected matt-tran2026 GitHub login and GitHub noreply address.
- Pushed eb12f67 (`chore: initialize Popcorn Tycoon project documentation`).
- Independently fetched AGENTS.md, GAME_DESIGN.md, ROADMAP.md, and ARCHITECTURE.md from GitHub main through the GitHub connector. All four existed and returned their expected headings.
- outputs/initialization was excluded; original documents were preserved in the initial commit before updating adopted decisions.

## Executed gameplay checks

1. Started Play through MCP. Server and client printed their ready messages. A single owned field and the HUD were created.
2. Moved the actual character near ready corn using server-side test positioning, then sent a native E keypress through MCP. RawCorn became 3 and the client HUD reported `+3 corn · stalk regrowing`. The server-to-client result and HUD path were observed, not inferred from source. The stalk had reached its three-yield cap by that point in the test session.
3. Captured the play viewport through Studio MCP. The placeholder soil/stalk/ear layout and readable HUD rendered. This was desktop inspection only.
4. Installed tests/StarterField.server.luau as a temporary Server RunContext Script in the running server. It passed all 24 checks listed below, including waiting an actual configured 10-second growth cycle. The synthetic second-owner farm/profile were cleaned up. Stop Play removes test mutations and the runner.

| Check | Initial run |
| --- | --- |
| Zero elapsed yields zero | PASS |
| Negative elapsed clamped | PASS |
| Just before maturity | PASS |
| Exact maturity grants one | PASS |
| Two cycles plus remainder | PASS |
| Long absence bounded at three | PASS |
| Repeated pure calculation is stable | PASS |
| Profile version and starting contract | PASS |
| Nine independent stalk timestamps | PASS |
| New starter corn immediately harvestable | PASS |
| Profiles do not alias | PASS |
| Foreign-owner field rejected while in range | PASS |
| Malformed target rejected | PASS |
| Out-of-range action rejected | PASS |
| Invalid equipped tool rejected | PASS |
| Capped harvest grants exactly three | PASS |
| Immediate replay rate limited | PASS |
| Immature stalk cannot grant twice after cooldown | PASS |
| Visible stalk resets after harvesting | PASS |
| Harvest discards fractional progress | PASS |
| Actual elapsed-time regrowth becomes available | PASS |
| Regrown stalk grants one | PASS |
| Manual harvest does not grant popcorn | PASS |
| Synthetic profile/farm cleanup | PASS |

The server runner accesses the real gameplay module cache. An earlier ad hoc MCP command attempted to require PlayerStateService directly and assert that it contained the live profile; that assertion failed because the command's require context did not share the server gameplay module state. This was a test-harness error, not a reported gameplay exception. It was corrected by executing the integration runner as an actual server Script. The Output log also contained a tool-generated camera reset notice. No gameplay runtime errors were observed in the tested bootstrap/harvest/regrowth paths.

After adding an explicit typed crop dictionary and centering the layout from configured row/column counts, a fresh Play session reran the same integration suite: all 24 checks passed again. Output contained only the expected server/client ready messages and `PASS 24 checks`. Play was stopped after the final run.

## Source synchronization and backup

Native Script Sync is selected but pending. UI screen capture timed out twice even after reacquiring Studio. Accessibility-only reading subsequently worked, but clicking a menu failed with `coordinate input geometry is unavailable`. The creator found the folders and reported that choosing Sync to… did not open a chooser. Manual retry in Edit mode and a local save were suggested; completion is not yet confirmed.

MCP installation and full source comparison are separate checks from native sync. A code copy and matching strings do not prove a live connection. No disk → Studio → disk round trip has yet passed. No local .rbxl place backup is confirmed saved. README.md contains exact mapping, setup, conflict review, verification steps, and a backup path.

A disk-only smoke probe appended a temporary comment to one shared, server, and client file while in Edit mode. None of the three comments appeared in the corresponding Studio source, so disk-to-Studio syncing was not active for any root at that check. The temporary disk comments were removed. A final exact comparison confirmed all eight local/Studio source pairs matched through the deliberate MCP installation, with no leftover test runner or runtime farms in Edit mode. This equality result does not change the failed native-sync probe result.

## Sync follow-up history and remaining verification

### Follow-up: creator connected folders

After the creator reported connecting all three roots, an Edit-mode round-trip check found partial synchronization:

- Shared: disk edits to src/shared/PopcornTycoon/Growth.luau reached ReplicatedStorage.PopcornTycoon.Growth, and a different Studio comment returned to that same nested disk file. Both directions passed for this actual path.
- The tracked src/shared/Growth.luau did not drive that Studio script. The chooser exported a PopcornTycoon subdirectory under src/shared, leaving three additional untracked copies of the shared modules. Those files were preserved; do not delete or move an active sync root blindly.
- Server/client: disk comments in the tracked src/server/Bootstrap.server.luau and src/client/Bootstrap.local.luau did not reach Studio; Studio comments did not appear anywhere under src/server or src/client. Their actual sync locations still need inspection using Script Sync → Reveal in Explorer. This does not prove they are disconnected everywhere on disk, only that they are not connected to the tested repository paths.
- All temporary comments were removed from Studio and disk. All eleven inspected local source files were restored exactly to their pre-test content; all eight Studio source files matched the original tracked sources. No gameplay logic or play mode was changed.

Native sync therefore remains incomplete for the intended repository layout. Shared sync itself works, but its directory mapping needs reconciliation. Server/client paths remain unresolved. Earlier setup instructions assumed the chosen directory was the sync root itself; this observed export includes the folder name and needs to be reflected in the final mapping before adopting it as source authority.

### Mapping repair preparation

The creator confirmed all three sync connections were stopped with local files retained. Before filesystem changes, source copies were backed up under ignored work/. The three duplicated shared files were hash-identical. Eight source files were consolidated into src/{shared,server,client}/PopcornTycoon with identical before/after hashes; no gameplay edits were made. This adopts the observed native export convention rather than fighting the extra folder level. The chooser should select src/shared, src/server, or src/client; the resulting script root includes one PopcornTycoon directory. Updated instructions distinguish the chooser's parent from the final source root. Reconnection and fresh two-way tests remain pending.

### October 30, 2026: three connections verified

After the creator confirmed reconnection, the exports included additional service/container directories. Distinct disk-only comments in the old and newly exported paths identified the active paths without assuming the chooser's behavior. The following table supersedes earlier mapping assumptions and pending-sync status:

| Active file tested | Disk → Studio | Studio → disk |
| --- | --- | --- |
| src/shared/ReplicatedStorage/PopcornTycoon/Growth.luau | PASS | PASS |
| src/server/ServerScriptService/PopcornTycoon/Bootstrap.server.luau | PASS | PASS |
| src/client/StarterPlayerScripts/PopcornTycoon/Bootstrap.local.luau | PASS | PASS |

Disk comments arrived automatically in their corresponding Studio scripts; separate Studio comments written with UpdateSourceAsync returned automatically to the active files. Neither direction was established by manually copying a matching source. Old folder-only copies did not drive Studio. All probes were removed and the eight Studio files matched their unchanged gameplay sources. A cleanup command initially returned two values from string.gsub and was rejected by UpdateSourceAsync; disk cleanup subsequently propagated successfully and final checks confirmed no markers remained.

The eight inactive duplicate files were compared against active files by hash, then archived under ignored work/ instead of moving or renaming any active sync root. Only eight canonical source files remain under src/. Gameplay was not changed and no playtest was needed for source relocation/comment cleanup. Current Edit-mode native Script Sync is verified; saving/reopening the place and automatic resumption remain unverified. No publishing was performed.

- Real two-client ownership, replication, join/leave, and independent progression. The second-owner fixture does not substitute for this.
- Touch-device prompts and small-screen layout; real mobile performance.
- Saved-place reopen/auto-resume behavior; current three-root round trips have passed.
- A saved/reopened local place snapshot including unsynced assets/settings.
- Strict static analysis diagnostics were not retrieved; `--!strict` annotations are not proof of a clean analyzer run.
- Durable persistence, save/rejoin restoration, migrations, and true cross-session offline growth are intentionally absent. The formula was tested against long elapsed timestamps, but profiles currently reset on leave.

Do not mark M1/M2 completely accepted while place backup/reopen, multiplayer, and mobile checks remain outstanding.
