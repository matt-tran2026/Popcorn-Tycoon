# Popcorn Tycoon — Development Roadmap

Established October 29, 2026. Documentation upload and current native Script Sync verification are complete. The first harvesting gameplay slice is implemented and playtested; outstanding M1/M2 acceptance checks are recorded below.

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
- Implemented M2 foundation: one owned 3-by-4 placeholder field with owner label, Normal Corn, manual native prompts, raw-corn inventory, centralized visual growth updates, server ownership/range/tool/maturity/cadence validation, and basic HUD feedback with a confirmed-harvest flash.
- Studio verification: native E-key harvesting updated raw-corn HUD; the server integration runner passed 24 checks including real-time regrowth and foreign-owner rejection. Ownership fixture is simulated, not a real multi-client playtest.
- Two small follow-up refinements add explicit crop dictionary typing and center the configurable grid; the final source revision also passed all 24 Studio checks with only expected bootstrap/test messages in Output.
- M1's native-sync gate has passed; M1 remains incomplete until place backup/reopen checks pass. M2's real two-client ownership/independent harvesting checks have passed; actual touch input remains unverified. No claim of complete prototype readiness.

Next: save/reopen a local place snapshot and verify sync auto-resumes, then run real two-player and touch checks. After those gates, select the M3 microwave/conversion slice and settle D4–D5 before coding it. No microwave or advanced systems belong in the current task.

Mapping repair completed: after reconnection, the actual service/container-based export paths above passed both directions. The inactive folder-only copies were identical and archived outside src/. Source content is unchanged. Current sync verification is complete; reopened-place behavior remains unverified.

October 30 gameplay follow-up: reused existing services and expanded to twelve stalks without changing any sync connection or source root. Thirty server integration checks passed, including real-time regrowth, visible stages, owner labels, separate slots, foreign-field rejection, duplicate rejection, and profile/attribute updates. Native E-key harvests and the HUD flash were observed. iPhone 17 Pro landscape and portrait HUD layouts fit; a GUI mouse-click probe did not trigger a harvest, so actual touch tapping remains unverified. See docs/testing/FIRST_GAMEPLAY.md for full evidence and outstanding checks. Do not equate phone layout inspection with successful touch gameplay or a real-device performance test.

A subsequent native StudioTestService two-client session passed nine further checks with two actual simulated client DataModels: distinct profiles, owned fields, disjoint slots, bidirectional foreign-field rejection, independent successful harvesting, and correct inventory attributes. The test returned to Edit mode and its temporary Workspace runner was removed. This supersedes the earlier single-client-only limitation for ownership and inventory isolation; manual cross-client UI/input observation is still useful.

### Selected visual slice: reusable player plot — November 1, 2026

The creator selected a farm-visual milestone before microwave gameplay. Implemented a reusable reference-inspired wooden farm with entrance/owner signage, row beds, growth-scaled corn leaves, fenced grass property, paths, two lantern lights, small props, a microwave display, tool shed and future expansion lawn. No conversion, purchasing, new fields or main world were added.

Validation and remaining manual gates are recorded in docs/testing/FARM_PLOT.md. Existing growth/security checks and real two-client isolation checks remain mandatory after visual edits. Touch input, real-device performance and a controlled place-reopen test remain separate acceptance gates. Next: review this plot in normal third-person play and on touch hardware, confirm the saved place snapshot, then select microwave rules D4–D5 or a focused visual refinement based on feedback.

### Visual overhaul and M3 rules — November 2, 2026

The full UI/farm/environment overhaul was delivered in `bad9f83` (see docs/testing/VISUAL_OVERHAUL.md); real touch, device performance and place reopen remain open gates. The creator then settled D4–D5 (GAME_DESIGN.md §6, ARCHITECTURE.md decision register): 50-corn bag, 5-second owner-only microwave batches whose popcorn bursts into collectible pieces, and a 100-popcorn Extra Row as the first upgrade.

M3 implemented the same day (docs/testing/M3_MICROWAVE.md): bag cap with partial harvest, ConversionService (microwave batches, popcorn burst that flies magnet-style to the owner wherever they are, settle on leave), UpgradeService (Extra Row), working microwave station and four-row bed. StarterField 30/30, FarmPlot 31/31, Economy 35/35 (after the magnet revision) and Multiplayer 13/13 passed; the real E-key harvest → pop → collect loop worked. A bot reached 100 popcorn in 106 s (lower bound). M3 stays open until a human pacing playtest and an eye check of the burst/particles; touch on the new prompts is unverified.

### Bigger starter field and expansion layout — November 3, 2026

The creator asked for a 6-by-6 starter field (36 stalks), stations at the front facing the field, all expansions to the left of the field, and row upgrades toward the back. Implemented in Config, FarmService, FarmVisuals, ConversionService (the burst now fans out along the microwave's facing) and EnvironmentVisuals (entrance oaks moved). Evidence in docs/testing/FARM_EXPANSION_LAYOUT.md: StarterField 30/30, FarmPlot 82/82 (real walk to all 36 stalks), Economy 36/36 (Extra Row plants row 7 behind row 6). The Multiplayer two-client runner was updated but **not re-run**. Extra Row pacing at 100 popcorn needs a fresh human playtest with 36 stalks.

### Hub map — November 3, 2026

The creator asked for a map with a center island connecting every player's farm. Implemented MapVisuals (hexagonal hub, six bridges, six farm islands, bridge-head owner signs, hub spawn), rotated farm placement in FarmService, and an ocean/horizon EnvironmentVisuals (terrain water over the lowered baseplate). Evidence in docs/testing/HUB_MAP.md: StarterField 30/30 (one intermittent failure on the first run right after Play started; repro and two re-runs passed), FarmPlot 83/83 including a pathfinding walk from the hub spawn to the farm entrance (about 11 s), Economy 36/36 with a rotated fixture farm. Multiplayer runner updated but not re-run. Open: Max Players must be set to 6 in Game Settings; walk length from hub to farm; the place holds three Sky objects so the skybox is chosen arbitrarily.

Open plots (same day): every unclaimed slot now shows a non-interactive starter farm instead of bare grass; it is replaced when a player takes the slot and rebuilt when they leave. StarterField 31/31 (the slot returns to a starter farm after its farm is removed) and FarmPlot 84/84 (open plots fill every free slot and hold no prompts or scripts). Economy and Multiplayer were not re-run for this change. A full map is about 3,450 BaseParts in the workspace (each open plot about 500); real-device performance is unmeasured.

### First loop slice: sell, Shop, sickle — November 3, 2026

Harvest → pop → sell → buy → harvest again is playable on each player's own island. A sell stand next to the microwave converts popcorn to Coins (2 each, payout shown first). The Shop button opens Tools (buy and equip the Sickle) and Seeds (preview) tabs. The Sickle sweeps up to 3 ripe stalks with staggered snips and kernels arcing to the player. The HUD shows bag fill, microwave batch state, sale payout and progress to the next tool. Prices name their currency in Config. At the creator's request, Extra Row moved from 100 Popcorn to 200 Coins (the same two passes), so Coins are the only spendable balance. The Sickle price was raised from 60 to 200 Coins because a measured pass fills the 50-corn bag (17 stalks, 14 s, 100 coins), so 200 is two passes. Evidence: Economy 41/41, Tools 37/37, FarmPlot 84/84 and a real-input loop (E pop, E sell, B Shop, buy, equip, F swing for +9 corn). Not re-run: StarterField, Multiplayer. Extra Row checks re-run after the currency move: 10/10. Open: human pacing and feel playtest, touch on a device, audio backlog. Design note: docs/design/FIRST_LOOP_SLICE.md.

### Brick map with solid decorations — November 3, 2026

The creator asked for a lego-brick Roblox look and for decorations players cannot walk through. A new BrickStyle module gives all generated scenery (hub, bridges, farm islands, farms, open plots, distant isles) Plastic with classic Roblox stud surfaces on every face (a first pass with the baseplate's stud texture read as a flat checker grid, so the creator asked for more pronounced studs). It replaces the mesh oaks with blocky brick trees, turns the distant hills into terraced brick islands, and makes decorations solid. Flat paths, beds, edging, tiny details and all crops stay walk-through. Each fence run gets an invisible barrier, because the rails were climbable like a ladder. The hub hexagon's overlapping layers are offset so their studs do not z-fight. Stud surfaces are drawn by the engine, so the look adds no instances. Evidence: FarmPlot 88/88 (633 parts) on the texture pass; after the switch to stud surfaces, a static recheck confirmed Plastic, studded ground and soil and no texture objects on the farm, with collisions unchanged. The pathfinding walk from the spawn over the bridge takes about 12 s, a walk into the side fence stops at the rails, and all 36 stalks can be walked to and picked. Not re-run: StarterField, Economy, Tools, Multiplayer (no economy code changed). Open: the place has three Sky objects so the skybox is arbitrary (purple or blue); the hub corners show a rotated stud grid; real-device performance is unmeasured; the microwave and shed keep their textured meshes.

