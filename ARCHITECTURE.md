# Popcorn Tycoon — Architecture and Decisions

Status: initial recommendations plus adopted starter-field decisions in section 9. Established October 29, 2026. Section 9 supersedes conflicting initial proposals below.

## 1. Observed foundation

Read-only inspection through Roblox Studio MCP found one connected Studio, `Place1`, in Edit mode with Edit DataModel access. PlaceId and GameId both reported 0; no published experience identity was established by this inspection.

| Location | Observed content |
| --- | --- |
| Workspace | Camera, Baseplate, Terrain, SpawnLocation; six descendants total |
| Lighting | Sky, SunRays, Atmosphere, Bloom, DepthOfField |
| StarterPlayer | Empty StarterPlayerScripts and StarterCharacterScripts containers |
| ReplicatedStorage, ServerScriptService, ServerStorage, StarterGui, StarterPack, ReplicatedFirst, SoundService | Empty |
| Scripts | No LuaSourceContainers found under the ten inspected services |
| Local workspace | Only empty `work/` and `outputs/` directories before initialization; not a Git repository; no ancestor AGENTS.md found in the checked directory chain |

Tools used: connected-Studio listing, Studio state, and a read-only Luau inventory of those services and script paths. No Source contents needed inspection because the script inventory was empty. This was an architecture inventory, not a full asset/settings audit. Script Sync availability, Studio API-service settings, persistence access, GitHub connection/repository, multiplayer playtest capability, and saved place-file location remain unverified. Studio content, play mode, and publishing state were not modified.

## 2. Recommended Explorer hierarchy

This is a target structure to create incrementally after implementation is requested. Existing baseplate/spawn/lighting stay until understood and intentionally changed.

```text
ReplicatedStorage
  PopcornTycoon
    Shared
      Types                  -- public data types and network contracts
      Config                 -- crop/tool/upgrade definitions, shared display data
      Domain                 -- pure growth and value rules; server owns inputs
    Remotes                  -- small explicit request/result/state interface
    Assets                   -- only client-needed models/effects
ServerScriptService
  PopcornTycoon
    Bootstrap                -- one server entry Script
    Services
      PlayerDataService      -- load/session lifecycle, saves, migrations
      FarmService            -- ownership and authoritative field state
      HarvestService         -- targeting/validation and harvest transactions
      InventoryService       -- corn quantities and identity
      ConversionService      -- microwave batches and direct-pop transactions
      EconomyService         -- currency, rewards, purchases/unlocks
    Persistence              -- store adapter, schema defaults and migrations
    Config                   -- server-only settings where needed
ServerStorage
  PopcornTycoon
    FarmTemplates
    CropTemplates
    ToolTemplates
StarterPlayer
  StarterPlayerScripts
    PopcornTycoon
      Bootstrap              -- one client entry LocalScript
      Controllers            -- input, farm visuals, UI, audio/effects
StarterGui
  PopcornHUD                 -- native Roblox ScreenGui
Workspace
  Map                        -- shared environment when needed
  Farms                      -- runtime farm models, stable field/cell IDs
```

Do not create empty services or folders just to fill this tree. Manual harvesting needs no physical Tool instance unless interaction design calls for it. StarterPack may remain empty; distribute owned tools through server-controlled equipment when implemented. Shared definitions are visible to clients, so keep secrets and authoritative state server-side. Sharing a pure formula does not give the client authority to award its result.

## 3. Recommended local repository structure

The current workspace root should become the project root if accepted. Do not assume a GitHub repository exists or create/push one as part of initialization.

```text
GAME_DESIGN.md
ROADMAP.md
ARCHITECTURE.md
AGENTS.md
README.md                    # later: actual setup and verified sync steps
src/
  shared/                    # Shared modules
  server/                    # Bootstrap, Services, Persistence, server Config
  client/                    # Bootstrap and Controllers
tests/
  domain/                    # meaningful deterministic rule tests
  integration/               # persistence/network scenarios as needed
assets/                      # source models/audio/art when actually created
places/                      # deliberate place snapshots if chosen
docs/
  decisions/                 # expanded decisions if this register outgrows the file
  testing/                   # dated validation records
work/                        # temporary local scratch; ignore in Git
outputs/                     # review exports; not source code authority
```

The source-to-Explorer mapping is a recommendation, not an active sync configuration. File naming and mapping must match the chosen sync mechanism; do not assume Rojo conventions work with Roblox Script Sync. Track scripts/configuration and deliberate assets in Git; decide whether place files belong in Git, Git LFS, or a separate backup process based on actual size and workflow. Ignore scratch files, credentials, and machine-specific paths. Avoid committing duplicate generated exports by default.

Canonical documentation lives at the workspace root. `outputs/initialization/` contains review copies made during this initialization only; refresh them explicitly if needed, and do not treat them as a second source of truth.

## 4. Responsibilities and data flow

Client intent → validated server action → one authoritative state transition → server state/result → client presentation.

- The client supplies a bounded action request, such as a target cell or microwave interaction. It does not supply trusted crop values, elapsed time, reward totals, prices, or inventory state.
- Resolve player identity from the server connection. Validate types, finite numbers, ownership, equipped/unlocked tool, spatial reach, maturity, capacity, cooldown, and target limits. Deduplicate IDs and rate-limit requests.
- Centralize rules in pure domain functions. Services coordinate state and Roblox instances. Keep presentation separate from rewards.
- Serialize related per-player economy changes. Check and commit harvest/conversion/purchase transitions without yielding between validation and state mutation. For time-based microwave work, reserve inputs and define completion/cancellation/recovery explicitly.
- A repeated request must not repeat a grant. Use state preconditions and action/batch identity where needed; session request IDs alone are insufficient for durable operations.
- Replicate only necessary public field state and player-owned HUD information. Avoid broadcasting full private inventories or saving every visual change.
- Clients may interpolate growth and play immediate feedback, then reconcile with server results. Rejected actions must not leave phantom resources or permanent visual changes.

These are contracts, not a commitment to a framework or a large generic service system.

## 5. Proposed persistent profile

Define a versioned, serializable plain-data schema before persistence implementation. Never persist Instances, CFrames as engine objects, connections, or visual trees.

| Group | Candidate fields |
| --- | --- |
| Profile | schemaVersion, popcorn balance, unlocked crop/tool/upgrade IDs, equipped tool ID |
| Inventory | stacks keyed by crop ID and, later, mutation identity; carried quantities |
| Fields | stable field ID, variety ID, capacity/upgrade levels, growth checkpoint, stored corn, compact cell availability/progress required by chosen model |
| Processing | durable pending conversion state only if chosen microwave timing requires it |
| Time | last authoritative checkpoint/accrual timestamp; server-controlled session bookkeeping |

Exact field names and encodings are unresolved. Define reward/version behavior when balance configuration changes so old inventory and offline yields have predictable valuation. A field's production checkpoint must advance whenever elapsed growth is reconciled, including harvesting, saving, and rejoining. Do not grant offline growth once from a logout time and again from an older field checkpoint.

### Growth calculation contract

Given valid saved field state, authoritative current time, and validated crop configuration, return updated compact field state and an accrual summary. Bound storage; clamp negative elapsed time; preserve or discard fractional cycles according to the accepted rule. Reapplying the calculation at the same time must grant nothing additional. Advance checkpoints even when capacity discards production, so freeing space cannot reclaim already-discarded time.

Write examples for half a growth cycle, exact maturity, several cycles, full storage, partially consumed storage, a negative clock delta, and a long absence. Use batched/closed-form accrual where possible; no loop per elapsed second or offline cycle. Render cells from compact state, using a bounded shared update schedule or client interpolation rather than a script per stalk. More detail is justified only if gameplay requires independent cell growth.

### Persistence contract

Use Roblox DataStoreService directly or a justified Roblox-native abstraction. Before adopting one, verify current official guidance and maintenance. Require concurrency-safe ownership/session handling, bounded retries/backoff, request-budget awareness, staggered autosaves, shutdown/player-leave handling, migration, and explicit error feedback. A shutdown save alone is insufficient.

On a failed load, do not replace existing data with writable defaults. Keep the profile unavailable, retry safely, or prevent play until recovery. Guard against stale servers overwriting newer sessions. Store related player economy state together where practical; do not assume transactions across keys. Test crashes/disconnects/repeated completion for any persisted pending batch. Use isolated test keys/store/environment and never enable production data access casually.

## 6. Required decisions, resolved just before their dependent work

“Required” means the rule must be settled before that system is coded, not that every question blocks all development. Proposed defaults below are recommendations awaiting acceptance, not final design.

| ID / needed by | Decision | Recommendation and tradeoff |
| --- | --- | --- |
| D1 / M1 | Source authority, sync, backup, repository ownership | Verify Script Sync support and a reversible round trip first. Prefer local text source under Git if reliable. Until sync is verified, explicitly name Studio as script authority and export after each task. Do not edit competing copies or add Rojo automatically. Determine a local place backup path; GitHub remote can follow later. |
| D2 / M1–M2 | Field storage and harvest semantics | Prefer compact field storage with stable visual cells. Specify whether one action takes one ear or a bounded share of accumulated corn, how visual cells become unavailable, when they regrow, capacity units, and what variety switching does to existing corn. This is the largest gameplay/data-model dependency. |
| D3 / M1; production adapter by M5 | Player-data schema and save ownership | Plan versioned player profiles, a small store adapter, protected session ownership, and an isolated test store. Begin in memory. Confirm direct DataStore implementation versus a maintained native abstraction before durable persistence. |
| D4 / M3 | Inventory and microwave behavior | Start with crop-aware integer stacks and a simple explicit batch conversion. Choose capacity, processing duration, queue/reservation, cancellation, and disconnect recovery before coding. Immediate versus delayed conversion materially changes persistence needs. |
| D5 / M3 | First-session economy and pacing | Choose measurable targets for first harvest, conversion, and upgrade, then tune configurable values through play. Do not invent final balance from competitor games. |
| D6 / M4 | Three prototype crops and tool rules | Recommend Normal/Sweet/Golden; manual, sickle, flamethrower. Define sickle area/cadence and direct-pop capacity/reward handling before implementation. |
| D7 / M5 | Offline bounds and time semantics | Capacity-limited accumulation; decide any additional time cap, remainder behavior, and configuration-version policy. Use server timestamps and the same online/offline accrual function. |
| D8 / before M6 scaling | Device/player/field budgets | Mobile first; choose supported player count, initial field size, visual density, and measured frame/network budgets before scaling. Two-player correctness testing alone does not prove target server capacity. |

## 7. Optional decisions that do not block the prototype foundation

- Final visual theme refinements, corn names beyond the proposed first three, final sound/animation library, and UI ornamentation.
- ConfigService/live tuning or experiments, analytics instrumentation, additional tooling, and a larger test framework. Static validated configuration modules are sufficient initially; research current APIs before adopting live tuning.
- Mutations, giant-corn probabilities, weather, mastery, collections, quests, multiple-field management, and farm customization: settle each when its milestone is selected.
- Visiting, co-op, trading, seasons, skins, and optional monetization: no commitment yet.
- GitHub repository name/visibility and hosting remote: decide before creating/pushing a remote, but local foundation work can proceed first.

## 8. Decision log

| Date | Status | Entry |
| --- | --- | --- |
| 2026-10-29 | User requirement | Initialization is documentation-only; no gameplay, unnecessary assets, or publishing. |
| 2026-10-29 | User requirement | Native Roblox stack; server-authoritative systems; efficient offline growth; incremental prototype scope. |
| 2026-10-29 | Proposed | Hierarchy, service boundaries, schema outline, and D1–D8 defaults above. No unresolved recommendation has been treated as an accepted product rule. |

## 9. Adopted foundation decisions

The creator authorized the first implementation after the original documents were pushed and verified on GitHub. Preserve sections 1–8 as the initial inspection/proposal record; the following supersedes conflicting proposals, especially the field-level buffer.

### D1: Git and native Script Sync selected

Official repository: https://github.com/matt-tran2026/Popcorn-Tycoon.git. Branch: main. Initial documentation commit: eb12f67. Git identity is repository-local, using the connected GitHub login and its noreply address. Direct commits to main are authorized for verified milestones; never force-push. The four original root documents were verified through the GitHub connector after pushing. work/ and outputs/ are ignored.

Source mapping is now concrete:

| Local path | Studio root | Files |
| --- | --- | --- |
| src/shared/PopcornTycoon | ReplicatedStorage.PopcornTycoon | Config.luau, Types.luau, Growth.luau |
| src/server/PopcornTycoon | ServerScriptService.PopcornTycoon | Bootstrap.server.luau, PlayerStateService.luau, FarmService.luau, HarvestService.luau |
| src/client/PopcornTycoon | StarterPlayer.StarterPlayerScripts.PopcornTycoon | Bootstrap.local.luau |

The observed native chooser adds the Explorer folder name under the selected directory. Select src/shared, src/server, and src/client as parent directories; the actual source roots are the nested paths above. Following a partial-sync check, the creator stopped all three connections, and the eight unchanged source files were consolidated into this layout with backup/hash verification. This supersedes earlier assumptions that scripts would be written directly inside each selected parent. Reconnection and fresh three-root round trips are required before calling the repaired setup verified.

Native Script Sync is selected, but connection and bidirectional round-trip verification remain pending. Windows UI capture failed twice after window recovery with capture/channel timeout errors. The source was installed through MCP as a deliberate initial copy; this is not evidence of native sync. Local files under Git are the intended code authority. Until native sync is confirmed, reconcile every MCP change back to disk, compare full source, and never edit competing versions concurrently.

See README.md for manual setup, conflict handling, round-trip acceptance, and Studio asset backups. Script Sync covers code/folders, not models/terrain/settings. No local place snapshot has yet been confirmed saved. The current farm geometry is generated from tracked source, but that does not replace a complete place backup.

### D2 and initial D7: individual stalk timestamps

Each stalk has an ID and growthStartedAt. At server time now, available yields are min(maxYields, floor(max(0, now - growthStartedAt) / growthSeconds)). Capacity is initially three. The calculation does not mutate or repeatedly credit inventory. On harvest, transfer all available yields to rawCorn[cropId] and set growthStartedAt = now in one non-yielding transition. This discards remainder and excess production. No additional absence-time cap is needed for this foundation. Newly created stalks start one growth cycle old, with one yield immediately available.

For a 10-second cycle, a stalk started at 100 yields 0 at 109.99, 1 at 110, 2 at 125, and 3 at 140 or much later. Harvest at 125 transfers 2, resets start to 125, and yields 0 immediately and 1 at 135. Future timestamps yield 0 until time catches up. Persisting these timestamps later enables offline accrual without simulating offline players. Current in-memory sessions reset on leave, so cross-session offline growth is not implemented.

One shared server task refreshes all stalk visuals every 0.25 seconds, updating only changed stages/yields. No stalk contains a script or its own loop. The first field is a configurable 3-by-3 grid with provisional Normal Corn growth of 10 seconds. Future crop switching/upgrades must settle migration/overflow behavior before development.

### D3: schema version 1 and memory adapter

The implemented contract is declared in src/shared/PopcornTycoon/Types.luau:

- schemaVersion = 1; popcorn: number; rawCorn: crop-ID-to-quantity dictionary.
- ownedTools: ID-to-boolean dictionary; equippedTool: ID; unlockedCrops: ID-to-boolean dictionary.
- fields: field-ID-to-record dictionary with id, ownerUserId, cropId, and stalks.
- stalks: stalk-ID-to-record dictionary with id and growthStartedAt.

PlayerStateService.load(userId, now), get(userId), and release(userId) isolate profile lifecycle. They currently allocate and remove memory only. Future persistence must load and validate a real stored profile at that boundary rather than recreate starter defaults, and implement the protections in section 5. There is no live DataStore access.

### Minimal implementation boundaries

FarmService generates and owns placeholder geometry, resolves registered prompts, updates visible stages, and cleans up reusable farm slots. HarvestService validates actual player identity, target types, ownership, equipped/owned manual tool, living character, distance, request cadence, and computed maturity, then grants raw corn and resets the timer. Server Bootstrap handles lifecycle and one centralized ProximityPromptService event. HarvestResult is a server-to-client RemoteEvent; clients do not supply rewards. The client Bootstrap renders a small native HUD and server-confirmed feedback; native prompts provide keyboard and touch interactions.

Runtime geometry is Workspace.PopcornFarms/Farm_<userId>. Each farm has Soil and nine Stalk/Ear pairs. Prompts reside on stalks. ReplicatedStorage.PopcornTycoon.Remotes and PopcornHUD are runtime-created. No unrelated baseplate, spawn, lighting, or assets were replaced.

The larger service hierarchy remains a future recommendation; inventory is updated in the small harvest transaction until conversion/economy requirements justify separate services. No microwave, flamethrower, shops, mutations, quests, or persistence were introduced.

References consulted: [native Script Sync](https://create.roblox.com/docs/scripting/sync), [client/server boundary security](https://create.roblox.com/docs/scripting/security/client-server-boundary), and Roblox engine documentation for ProximityPrompt and ScriptEditorService.UpdateSourceAsync. Actual verification evidence belongs in docs/testing/STARTER_FIELD.md.
