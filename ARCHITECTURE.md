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
| D4 / M3 | Inventory and microwave behavior | **Adopted November 2, 2026** (see GAME_DESIGN.md §6): crop-aware integer stacks, 50-corn cap with partial harvest leaving the remainder on the stalk; one owner-only microwave per farm; the whole inventory loads as one batch, removed and priced at load; one batch at a time, 5 s cook; the reward bursts into a bounded set of owner-only pieces that fly to the owner wherever they are (no range) and are credited on a fixed server schedule when each flight ends, or at once on leave. The client only animates the flight. Delayed conversion means M5 must persist or settle pending batches/pieces. |
| D5 / M3 | First-session economy and pacing | **Adopted November 2, 2026:** targets of first harvest ≈10 s, first conversion ≈1 min, first upgrade ≈3 min. First upgrade is a one-time 100-popcorn Extra Row (fourth row of four stalks at the field's rear; the expansion lawn is reserved for other varieties). Tune configured values through observed play. **Superseded November 4, 2026** by repeatable land pads (up to 6 rows per plot, 8 extra plots, rising Cash prices); see section 9, "Land pads and the 3x3 plot grid". |
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
| 2026-11-04 | User requirement | Replace the Extra Row sign with step-on purchase pads; up to 6 extra rows per plot and 8 extra plots in a 3x3 grid per island; every row and plot costs more than the last. Plots unlock nearest first. Bag capacity stays 50 (a bag upgrade system comes later). |
| 2026-11-04 | User requirement | Four Cash farm upgrades from the Upgrades button: Backpack Capacity (global), Soil Quality, Corn Yield, Stalk Storage (per plot). An unupgraded stalk keeps 1 corn per cycle and 3 stored cycles. The current Yield level applies to all stored cycles. |
| 2026-11-04 | Adopted | Levels and prices in Config.FarmUpgrades (see docs/design/FARM_UPGRADES.md). Rule changes on planted plots rebase each stalk's timestamp at purchase (keep ready cycles and the partial-cycle fraction; no partial progress for a full stalk); no extra checkpoint state. |
| 2026-11-04 | User requirement | Owner-only Developer Panel for testing: one Owner rank by UserId, server-enforced, Studio-only mutations, commands only on the Owner's own profile, no moderation features. |
| 2026-11-04 | Adopted | AdminConfig (server-only allowlist; user-owned creator trusted, groups never; Studio test user −1 is Owner, −2+ are not), AdminService (one `AdminRequest` RemoteFunction created only in Studio; increasing request ids, token bucket, busy flag), AdminController (F4 / DEV). Purchases and admin commands share `UpgradeService.applyLevel/grantRow/grantPlot` and `ToolService.grant/revoke`. |
| 2026-11-04 | Adopted | Prices tuned to the creator's progression stages (Beginner $0–100K, Early game $100K–10M, Rebirth 1 at $10M): rows $200 ×1.16 per row bought across all plots, plots $25K ×2.3 per plot, both rounded to two significant figures. |

## 9. Adopted foundation decisions

The creator authorized the first implementation after the original documents were pushed and verified on GitHub. Preserve sections 1–8 as the initial inspection/proposal record; the following supersedes conflicting proposals, especially the field-level buffer.

### D1: Git and native Script Sync selected

Official repository: https://github.com/matt-tran2026/Popcorn-Tycoon.git. Branch: main. Initial documentation commit: eb12f67. Git identity is repository-local, using the connected GitHub login and its noreply address. Direct commits to main are authorized for verified milestones; never force-push. The four original root documents were verified through the GitHub connector after pushing. work/ and outputs/ are ignored.

Source mapping is now concrete:

| Local path | Studio root | Files |
| --- | --- | --- |
| src/shared/ReplicatedStorage/PopcornTycoon | ReplicatedStorage.PopcornTycoon | Config.luau, Types.luau, Growth.luau |
| src/server/ServerScriptService/PopcornTycoon | ServerScriptService.PopcornTycoon | Bootstrap.server.luau, PlayerStateService.luau, FarmService.luau, HarvestService.luau |
| src/client/StarterPlayerScripts/PopcornTycoon | StarterPlayer.StarterPlayerScripts.PopcornTycoon | Bootstrap.local.luau |

After the creator reconnected all three trees, probes identified the actual source roots above, including service/container names. All three passed disk-to-Studio and Studio-to-disk tests on October 30, 2026. Preserve these working connections. Earlier direct-root and folder-name-only layout assumptions are superseded by this observed mapping. Inactive duplicate files were hash-compared and archived under ignored work/; only the eight active files remain under src/.

Native Script Sync is now verified for current Edit-mode connections. The initial MCP installation was only a source copy; the later automatic round trips establish live synchronization. Local files under Git are the code authority. Avoid concurrent conflicting edits and repeat the probes after remapping. Studio reopen/automatic-resume has not yet been tested.

See README.md for manual setup, conflict handling, round-trip acceptance, and Studio asset backups. Script Sync covers code/folders, not models/terrain/settings. No local place snapshot has yet been confirmed saved. The current farm geometry is generated from tracked source, but that does not replace a complete place backup.

### D2 and initial D7: individual stalk timestamps

Each stalk has an ID and growthStartedAt. At server time now, available yields are min(maxYields, floor(max(0, now - growthStartedAt) / growthSeconds)). Capacity is initially three. The calculation does not mutate or repeatedly credit inventory. On harvest, transfer all available yields to rawCorn[cropId] and set growthStartedAt = now in one non-yielding transition. This discards remainder and excess production. No additional absence-time cap is needed for this foundation. Newly created stalks start one growth cycle old, with one yield immediately available.

For a 10-second cycle, a stalk started at 100 yields 0 at 109.99, 1 at 110, 2 at 125, and 3 at 140 or much later. Harvest at 125 transfers 2, resets start to 125, and yields 0 immediately and 1 at 135. Future timestamps yield 0 until time catches up. Persisting these timestamps later enables offline accrual without simulating offline players. Current in-memory sessions reset on leave, so cross-session offline growth is not implemented.

One shared server task refreshes all stalk visuals every 0.25 seconds, updating only changed stages/yields. No stalk contains a script or its own loop. The first field is now a configurable 3-by-4 grid with provisional Normal Corn growth of 10 seconds. Future crop switching/upgrades must settle migration/overflow behavior before development.

### D3: schema version 1 and memory adapter

The implemented contract is declared in src/shared/ReplicatedStorage/PopcornTycoon/Types.luau:

- schemaVersion = 1; popcorn: number; rawCorn: crop-ID-to-quantity dictionary.
- ownedTools: ID-to-boolean dictionary; equippedTool: ID; unlockedCrops: ID-to-boolean dictionary.
- fields: field-ID-to-record dictionary with id, ownerUserId, cropId, and stalks.
- stalks: stalk-ID-to-record dictionary with id and growthStartedAt.

PlayerStateService.load(userId, now), get(userId), and release(userId) isolate profile lifecycle. They currently allocate and remove memory only. Future persistence must load and validate a real stored profile at that boundary rather than recreate starter defaults, and implement the protections in section 5. There is no live DataStore access.

### Minimal implementation boundaries

FarmService generates and owns placeholder geometry, resolves registered prompts, updates visible stages, and cleans up reusable farm slots. HarvestService validates actual player identity, target types, ownership, equipped/owned manual tool, living character, distance, request cadence, and computed maturity, then grants raw corn and resets the timer. Server Bootstrap handles lifecycle and one centralized ProximityPromptService event. HarvestResult is a server-to-client RemoteEvent; clients do not supply rewards. The client Bootstrap renders a small native HUD and server-confirmed feedback; native prompts provide keyboard and touch interactions.

Runtime geometry is Workspace.PopcornFarms/Farm_<userId>. Each farm has Soil, one Stalk/Ear pair per planted stalk (36 at start since November 3, 2026), and a BillboardGui owner label attached to Soil. Prompts reside on stalks. ReplicatedStorage.PopcornTycoon.Remotes and PopcornHUD are runtime-created. No unrelated baseplate, spawn, lighting, or assets were replaced. A single cancellable client tween flashes the HUD for a confirmed harvest; it does not grant resources.

The larger service hierarchy remains a future recommendation; inventory is updated in the small harvest transaction until conversion/economy requirements justify separate services. No microwave, flamethrower, shops, mutations, quests, or persistence were introduced.

References consulted: [native Script Sync](https://create.roblox.com/docs/scripting/sync), [client/server boundary security](https://create.roblox.com/docs/scripting/security/client-server-boundary), and Roblox engine documentation for ProximityPrompt and ScriptEditorService.UpdateSourceAsync. Actual verification evidence belongs in docs/testing/STARTER_FIELD.md.

### Reusable plot generator (November 1, 2026)

The subsequent visual milestone adds FarmVisuals.luau inside the existing server sync root (nine runtime source files total). FarmService retains all slot allocation, prompt registration, growth rendering and cleanup. FarmVisuals.build(farm, fieldOrigin, ownerName) creates only bounded static scenery and returns the entrance owner-sign part. No economy or player-state rules moved into the generator. The original Soil/OwnerLabel path remains for compatibility, but the label now adorns the entrance sign. Stalk/Ear instance names and prompt ancestry are unchanged; four leaves per stalk resize only when the existing centralized growth stage changes.

*(The footprint, scenery groups and part counts in this paragraph describe the November 1 plot; the November 4 grid layout is in "Land pads and the 3x3 plot grid" below.)* Config.Farm defines the field origin, plot offset, footprint and 72-stud slot separation. Scenery contains Paths, FieldBorders, PerimeterFence, MicrowaveStation, SellStand, FutureExpansion and GardenDetails (the ToolShed was removed Nov 3 2026; tools are bought from the Shop menu). GrassFoundation is collidable and sits just above the original baseplate; other decoration disables collision, touch and query to avoid obstructing avatar movement or targeting. The generated plot has 339 BaseParts, two shadowless PointLights, twelve harvest prompts and no embedded scripts. This is a bounded prototype composition, not a measured target-server/mobile performance guarantee.

The creator reported saving the pre-change local place backup. The requested places/ directory remained empty on filesystem inspection, so its actual saved location and reopenability were not independently verified. This session connected to Popcorn Tycoon.rbxl instead of the previous Place1; native disk edits and a newly added module propagated automatically, with all nine final sources compared equal. This establishes current source synchronization, not a controlled restart/resume test. Existing connections were never recreated or reorganized.

### HUD art pass and Cash rename (November 3, 2026)

Client: HudController.luau (client sync root) owns the PopcornHUD ScreenGui and returns show/pulse functions; Bootstrap keeps the Inventory and Shop panels, remote feedback, popcorn-piece animation and camera placement. UI art is uploaded image assets referenced from UITheme.Hud; text is native TextLabels (Enum.Font.FredokaOne) so values stay live and localizable. One layout pass on ScreenGui.AbsoluteSize, GuiService.TopbarInset and PreferredInput changes positions everything; there is no per-frame UI work. The pixel layout is the pure function HudController.placements(screen, viewport, touch, topbar), so it can be checked for any device size without a client. The popcorn bucket lives in a second ScreenGui, PopcornHUDTop (ScreenInsets None, DisplayOrder below PopcornHUD so panels cover it), so it can sit in the free middle of the top bar. A boolean TouchLayout attribute on PopcornHUD forces either layout for Studio checks. Shared: Money.luau formats balances and prices; it never changes amounts. Server and shared code use Cash everywhere Coins was used (profile.cash, player attribute Cash, Types.Currency "Cash" | "Popcorn", Config.Sell.cashPerPopcorn). The coin-jar prop on the sell stand keeps its part names; it is decoration only.

### Land pads and the 3x3 plot grid (November 4, 2026)

**Data.** schemaVersion 2 (profiles are still in memory, so nothing migrates). `profile.fields` holds one Field per owned plot, keyed `Plot1`…`Plot9`; each Field gains `plot` (its index in `Config.Grid.order`) and `rows`. Stalk IDs are `"<plot>_<n>"` (n row-major within the plot, e.g. `1_14`), unique across the farm, so stalk part names (`Stalk_1_14`) and client `StalkId` lookups stay flat. `profile.upgrades.ExtraRow` is gone. `PlayerStateService.stalkId`, `plantRow` and `addPlot` (next cell in order, base rows planted ripe) are the only field constructors.

**Config.** `Config.Plot` (crop, 6 columns, 6 base rows, 6 extra rows, spacing 5) replaces `Config.Starter`. `Config.Grid.order` lists the nine cells in purchase order as `{gx, gz}` (starter front-center, then front-left, front-right, middle, back). `Config.layoutRows()`, `cellSize()` (34 × 64 studs) and `cellOffset(plot)` are the single source of plot geometry. `Config.Farm` is now 122 × 234 studs with the entrance at canonical Z = 0; `Config.Map.entranceRadius` went from 115 to 120 so neighbouring islands clear each other; `validate()` asserts every cell fits the island and the station strip still fits in front. `Config.Upgrades.ExtraRow/ExtraPlot` hold `base`, `growth`, `currency` (and `max` for plots); `Config.Pads` holds the step-off re-arm rule.

**Pricing.** Shared `Pricing.luau` derives both counts from a fields map (rows bought = Σ(rows − baseRows), plots bought = fields − 1) and returns `nice(base × growth ^ bought)`, rounded to two significant figures. Because prices come from owned land, anything that resets fields (a future rebirth) resets prices.

**Server.** FarmService builds each owned plot's `Soil` (plot 1 keeps the name `Soil` for the client camera) and `PlotBed_n` (FarmVisuals.buildPlotBed), each locked cell's `LockedCell_n` (buildLockedCell, five parts), and the pads: `RowPad_<fieldId>` on the next empty row of every plot that has room and one `PlotPad` on the next locked cell. Later builds go through a scratch model turned by the farm's placement, as purchased rows always have. Pads are walk-through slabs with a neon top and a price BillboardGui, carrying `PadKind`, `FieldId`, `Row`/`Plot`, `Price` and `Currency` attributes. A pad's `Touched` handler accepts only the farm owner's character and forwards to a handler Bootstrap registers (`FarmService.setPadHandler`, avoiding a FarmService ↔ UpgradeService cycle). One attempt per step-on: FarmService.update re-arms a pad once the player's root leaves it (Config.Pads.reach past its edge) and at least `rearmSeconds` later. UpgradeService.buyRow(player, fieldId) and buyPlot(player) validate ownership, limits, that the player stands on or beside the live pad, and the Cash balance, then spend and commit without yielding; FarmService.plantRow/addPlot rebuild the pads and re-price all of them. HarvestService.swing collects ripe candidates from every plot (FarmService.fieldOf maps a stalk to its plot). The `BuyRow` prompt and row sign are removed. Bootstrap also creates a Studio-only `ServerStorage.DebugGrantCash` BindableFunction (guarded by RunService:IsStudio) so tests can grant Cash to the live profile.

**Client.** PadController tints the local player's pads green or red from the `Cash`/`Popcorn` attributes against each pad's `Price` and hides other players' pads (LocalTransparencyModifier, tag disabled). It handles pad pieces streaming in separately. The Upgrade notice now plays a chime and a floating "−$" like a tool purchase.

### Farm upgrades (November 4, 2026)

**Data.** schemaVersion 3: `profile.upgrades = { Backpack }` and `field.upgrades = { Soil, Yield, Storage }`, whole-number levels (Types.GlobalUpgradeLevels / FieldUpgradeLevels); `CropDefinition.cornPerYield`. `PlayerStateService.migrate` turns a v2 profile into v3 (clamped levels) and is the hook a future loader must call. `PlayerStateService.bagCapacity` is the only capacity check; `plantRow` starts new stalks one cycle old under the field's current rules.

**Rules.** Shared `FarmUpgrades.luau` (pure): `rules(crop, levels)` → `GrowthRules { growthSeconds, maxYields, cornPerYield }`, `fieldRules(field)`, `bagCapacity`, `price` (via `Pricing.upgradePrice`), `clampLevel`, `describe`. `Growth.yields/progress` take GrowthRules (a crop definition is the unupgraded case) and add a 1e-6 cycle epsilon so timestamps backdated by whole cycles never read one short; `Growth.corn` and `Growth.rebase` are new.

**Server.** `UpgradeService.buyUpgrade(player, upgradeId, fieldId)` (remote `UpgradeRequest`, reply on `ActionResult` as "FarmUpgrade"): cooldown, id, scope, ownership, level, price and balance checks, then spend, rebase stalks (Soil/Storage) and set the level without yielding; visuals follow. `HarvestService.take` uses the field's rules and the player's capacity for hands and tools alike and reports whether cycles were left behind. `FarmService.update` computes each plot's rules once per tick and publishes `MaxYields`, `CornPerYield`, `Cobs` and `Full` on stalks; `applyFieldLook` restyles one plot. `UpgradeVisuals` (server, presentation only) owns the back pack, soil colours and decor, cob visibility and the full tint, with part-built placeholders when the Blender templates (`PopcornTemplates.Backpacks`, `SoilDecor`, five-cob `CornStalk`) are missing.

**Client.** `UpgradesController` builds the menu from `Upgrade_*`, `Plots`, `BagCapacity` and `Cash` attributes and only sends (upgradeId, fieldId). `MenuKit` holds the brick-menu helpers now shared with ShopController. HudController and the Inventory panel read `BagCapacity`; HarvestHighlight reads each stalk's storage and corn per cycle.

**Budget.** A starter farm is about 1,250 descendants; a fully bought farm is 648 stalks and about 5,900 descendants. With one maxed farm and five open plots Studio held about 60 FPS on the creator's PC; mobile is unmeasured.

### Owner Developer Panel (November 4, 2026)

**Server.** `AdminConfig` (ServerScriptService, never replicated) holds `Members` (UserId → rank), `Ranks` (rank → power; only Owner today), `trustUserCreator`, `studioTestUsers` (−1 Owner, Studio only), `allowOutsideStudio = false`, `maxBalance` (10^15), the rate limit and the walk-speed range. Pure helpers: `rankOf(userId, isStudio, creator)`, `mutationsAllowed(isStudio)` and `atLeast`. `AdminService.init(remotes)` validates the config and creates the `AdminRequest` RemoteFunction only where mutations are allowed. `AdminService.handle(player, requestId, command, args)` checks, in order: environment, rank, token bucket, an increasing request id (stale ids are refused and the server's last id is returned for resync), the command name, its `minRank`, argument shape (at most 8 keys; strings of 32 characters or fewer; numbers, strings and booleans only), the busy flag and the profile. It then runs one command from the registry against the caller's own profile and returns the result and the caller's snapshot. Each executed command prints one `[Admin]` line. Commands never charge Cash and reuse the gameplay commits: `UpgradeService.applyLevel` (rebase plus publish plus visuals), `grantRow`, `grantPlot`, `ToolService.grant`, `revoke` and `equip`, `PlayerStateService.publish` and stalk `growthStartedAt`. Bulk land commands yield between plots and rows. `FarmService.plotFrame` and `MapVisuals.hubFrame` give the teleport spots. `PlayerStateService.publish` now also publishes `RawCorn`.

**Client.** `AdminController.start()` waits up to 15 s for `AdminRequest`, sends `hello`, and builds the `PopcornAdmin` ScreenGui only on success, so ordinary players and production servers get no UI. MenuKit brick style; five tabs; destructive buttons need two presses; one request in flight at a time; a 2-second `state` refresh while open; fly (LinearVelocity plus AlignOrientation) and noclip are local and undone on respawn.

**Persistence.** None yet; developer changes live only in the in-memory session. A future DataStore must keep Studio sessions on an isolated store.
