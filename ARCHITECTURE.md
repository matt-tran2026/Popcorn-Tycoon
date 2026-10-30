# Popcorn Tycoon — Architecture and Decisions

Status: recommendations, not implemented infrastructure. Established October 29, 2026.

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
