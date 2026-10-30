# Popcorn Tycoon — Development Roadmap

Established October 29, 2026. Documentation upload is complete. The starter-field foundation has been implemented and playtested; native Script Sync and complete M1/M2 acceptance remain pending as recorded below.

## Milestones

| ID / priority | Outcome and tasks | Dependencies | Completion criteria |
| --- | --- | --- | --- |
| M0 / P0 | Inspect Studio/workspace; document design, architecture, roadmap, and agent rules | None | Inspection recorded; documents exist; required decisions are identified; Studio is unchanged. Complete for initialization; decisions remain open. |
| M1 / P0 | Confirm source workflow, backup strategy, field/yield rules, and player-data contract; establish minimal server/client entry points and configuration locations | M0; D1–D3 in architecture | Source edits can be round-tripped without duplicate scripts; chosen authority is documented; defaults/schema and isolated test persistence strategy are agreed; no unrelated assets. |
| M2 / P0 | One owned field with Normal Corn, visible growth/regrowth, manual harvest, and in-memory corn inventory | M1 | Two players receive isolated ownership; mature cells harvest once per valid cycle; immature, distant, repeated, and foreign-field attempts fail; regrowth matches written examples; desktop and touch input work. |
| M3 / P0 | Microwave, popcorn currency, and first meaningful upgrade | M2; D4–D5 | Harvest → inventory → microwave → currency → upgrade is playable; conversions/purchases cannot duplicate rewards or lose inputs on failed validation; first-session pacing is observed and recorded. |
| M4 / P0 | Full prototype progression: three varieties, sickle, flamethrower, basic upgrade UI | M3; D6 | Normal/Sweet/Golden or agreed alternatives are distinct; sickle harvests groups; flamethrower grants popcorn directly without double conversion; locked tools/varieties cannot be used; balance lives in configuration. |
| M5 / P0 | Durable progression, offline growth, bounded yield storage, and basic return feedback | M4; persistence contracts from M1 | Save/rejoin restores farm, inventory, currency, unlocks, equipment, and growth state; online/offline calculations agree; capacity and partial-cycle cases pass; failed loads cannot overwrite valid saves; duplicate sessions and retry paths are handled. |
| M6 / P0 | Integrated prototype QA, mobile/performance pass, and coherent basic visual/audio polish | M5 | End-to-end new/returning-player loop passes; two-player ownership and abuse cases pass; effects remain bounded; mobile controls/UI are inspected; actual performance observations and remaining risks are recorded. Prototype complete only after these gates. |
| M7 / P1 | Mutations and giant corn, then detailed return summary, multiple fields, and orders/quests in small increments | M6; feature-specific rule decisions | Each feature has a narrow acceptance plan, compatible save migration, readable feedback, and validated economy impact before the next feature starts. |
| M8 / P2 | Weather, collection index, mastery, more varieties, customization, specialty shop, achievements | Stable M7 foundations; select one feature at a time | Each selected feature improves the loop, has clear scope and tests, and meets mobile/performance constraints. This is a backlog, not a commitment to build all features. |
| M9 / P3 | Events, co-op, visits/social play, skins, possible trading and optional fair monetization | Stable core and explicit product decisions | Feature-specific security/economy review and acceptance pass; publishing separately authorized. |

P0 is necessary for the complete prototype; P1 is the next product priority; P2 is expansion; P3 is conditional long-term work. No dates or duration estimates are committed.

## Sequencing notes

- Resolve growth/storage semantics before coding growth; define persistence shape early even while M2–M4 use in-memory data.
- Keep the playable manual-harvest slice small before adding advanced tools.
- Centralize reward calculation and conversion behavior before the flamethrower bypass is introduced.
- Do not expand to mutations, quests, multiple fields, or monetization to compensate for an unsatisfying core loop.
- M5 implements real storage and recovery; the earlier schema plan does not count as tested persistence.
- Each milestone includes necessary verification. M6 integrates and measures the whole game rather than postponing correctness testing until the end.

## Validation gates

| Area | Required evidence |
| --- | --- |
| Growth | No elapsed time, just before/at maturity, multiple cycles, full capacity, backward timestamp, very long absence, harvest/regrow, variety switch, and agreed overflow behavior. |
| Economy | Different crop values, inventory limit, microwave batch/result, direct-pop harvesting, insufficient funds, duplicate actions, and no negative or non-finite state. |
| Multiplayer/security | Two owners, foreign targets, out-of-range requests, unequipped tools, excessive request rate, duplicate targets, and malformed requests. |
| Persistence | First join, successful rejoin, load/save failures, reconnect/session overlap, retries, migration, partial growth, and bounded offline accrual in an isolated test environment. |
| UX | Fast first harvest/conversion, early meaningful upgrade, feedback clarity, desktop/touch operation, screen sizes, respawn, and return feedback. |
| Performance | Record player count, field/crop count, device or emulator, frame behavior, instance/effect counts, and network observations. Set numeric budgets before scaling content; do not claim mobile performance from desktop alone. |

For each completed task record: change, test setup, actual observed result, unresolved issue, and untested cases. Use pure logic tests for meaningful growth/economy invariants and Studio playtests for interaction/replication. Do not label a scripted read-only inspection a playtest.

## Suggested first implementation task

Begin M1 with a minimal ownership-and-data foundation after resolving D1–D3. Choose the source workflow, record worked growth/storage examples and the versioned profile shape, then add only a server bootstrap, player state service with an in-memory store, and a minimal client bootstrap. Verify two distinct player states and safe cleanup. Do not enable live persistence or build the full crop/tool systems in that task.

The first visible gameplay task is M2: one field, one crop, manual harvest and automatic regrowth, followed by the microwave loop in M3.

## Current milestone progress

The creator authorized M1 plus the starter-field portion of M2 after GitHub initialization. The original documents were committed as eb12f67 and their presence on GitHub main was independently verified. Direct milestone commits to main are now the selected Git workflow.

- D1: official GitHub remote established; native Script Sync passed automatic round trips for all three current connections on October 30, 2026. The eight active files reside under src/shared/ReplicatedStorage/PopcornTycoon, src/server/ServerScriptService/PopcornTycoon, and src/client/StarterPlayerScripts/PopcornTycoon. Place backup/reopen verification remains outstanding.
- D2 and initial D7: individual stalk timestamps; one yield/cycle; cap three; harvest all and restart timer; starter corn immediately ready. Field-buffer proposal superseded.
- D3: version 1 in-memory profile and load/get/release boundary implemented; no durable storage or cross-session offline growth.
- Implemented M2 foundation: one owned 3-by-3 placeholder field, Normal Corn, manual native prompts, raw-corn inventory, centralized visual growth updates, server ownership/range/tool/maturity/cadence validation, and basic HUD feedback.
- Studio verification: native E-key harvesting updated raw-corn HUD; the server integration runner passed 24 checks including real-time regrowth and foreign-owner rejection. Ownership fixture is simulated, not a real multi-client playtest.
- Two small follow-up refinements add explicit crop dictionary typing and center the configurable grid; the final source revision also passed all 24 Studio checks with only expected bootstrap/test messages in Output.
- M1's native-sync gate has passed; M1 remains incomplete until place backup/reopen checks pass. M2 remains incomplete until real two-player and mobile input checks pass. No claim of complete prototype readiness.

Next: save/reopen a local place snapshot and verify sync auto-resumes, then run real two-player and touch checks. After those gates, select the M3 microwave/conversion slice and settle D4–D5 before coding it. No microwave or advanced systems belong in the current task.

Mapping repair completed: after reconnection, the actual service/container-based export paths above passed both directions. The inactive folder-only copies were identical and archived outside src/. Source content is unchanged. Current sync verification is complete; reopened-place behavior remains unverified.
