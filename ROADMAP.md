# Popcorn Tycoon — Development Roadmap

Established October 29, 2026. Only documentation initialization is complete. No gameplay has been implemented or playtested.

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
