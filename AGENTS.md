# Popcorn Tycoon — Agent Instructions

## Purpose and source of truth

Build a distinctive Roblox corn-harvesting and popcorn progression game incrementally. Read `GAME_DESIGN.md`, `ROADMAP.md`, and `ARCHITECTURE.md` before development. The initial assignment permits documentation and inspection only; do not begin gameplay until the user requests implementation. Later implementation requests authorize their necessary scoped work without reopening this initialization restriction.

Root documents are canonical. Copies in `outputs/initialization/` are review exports, not independent instructions or source authority. Update design/decision records when accepted behavior changes. Distinguish user requirements, observations, proposals, and implemented behavior.

## Session workflow

1. Read these instructions and applicable descendant instructions; inspect the local files and Git status if a repository exists. Preserve unrelated changes.
2. List connected Studios and select the intended project; get its current mode and available DataModels. Inspect existing hierarchy and relevant script sources before modifications. Never assume a previous Studio ID or instance path still identifies the correct place.
3. If multiple places are ambiguous, resolve the target before mutations. Understand existing objects before deleting/replacing them. Do not publish the live game without explicit permission.
4. State the small task and its acceptance criteria. Consult the architecture decision register before dependent work; resolve concrete rule ambiguities without silently changing the design.
5. Establish which source copy is authoritative. Verify the actual sync workflow before using it. Avoid simultaneous MCP and local edits to competing versions. Read back changes and verify source mapping.
6. Make the smallest coherent implementation, test the changed behavior with available Studio tools, inspect errors, and record results. Report unavailable tools and unverified cases accurately.
7. Update documentation and roadmap status only when acceptance evidence supports completion. Summarize what changed, what was tested, and what remains.

Do not create a GitHub repository, push changes, publish an experience, or enable production DataStore access merely because infrastructure is mentioned in the design. Set up Git/GitHub as an explicitly selected development task. Read-only inspection needs no separate permission. Do not add approval steps to routine authorized reversible development.

## Luau conventions and module boundaries

- Prefer `--!strict` for authored Luau. Define types for player profiles, fields, crop/tool definitions, action payloads, and results. Explain any necessary untyped integration boundary.
- Use descriptive PascalCase module/service/controller names and types, camelCase local variables/functions, and stable configuration IDs independent of display names.
- Keep modules focused and dependencies explicit. Avoid giant bootstrap scripts, duplicate rule implementations, generic frameworks without a demonstrated need, and circular service dependencies.
- Separate server services, client controllers, and shared pure rules/config/types according to `ARCHITECTURE.md`. Shared code is not secret or authoritative merely because the server also runs it.
- Validate configuration at startup. Centralize crop values, growth durations, capacities, prices, tool reach/cadence, and upgrade requirements. Do not scatter economy constants through scripts. Do not use player persistence as a substitute for configuration.
- Keep growth and economic calculations deterministic from explicit inputs. Inject time/store boundaries where useful for testing; avoid hidden dependencies on wall-clock time in pure rules.
- Handle failures explicitly; log useful context without sensitive profile dumps. Clean up connections, tool actions, tasks, and runtime farm models on player removal/respawn as appropriate.
- Use Roblox-native services/UI/persistence. Do not introduce external databases, AWS, Node.js backends, Rojo, or unnecessary frameworks without a justified requirement and workflow decision. Local development utilities do not require a runtime backend.

## Server authority and transactions

- Clients request actions; servers decide ownership, eligibility, target validity, growth, amounts, rewards, and purchases. Derive identity from the connection, never a client-selected user ID.
- Validate request shape, finite numeric values, allowed IDs, farm/cell ownership, range, equipped tools, cooldown/rate, target limits, inventory/capacity, funds, and unlock conditions.
- Deduplicate target lists and defend repeated/replayed actions. Centralize reward and currency mutations. Do not award once on the client and again on the server.
- Make harvest, purchase, and conversion transitions coherent and idempotent where retries apply. Do not yield between checking state and committing a protected state transition. Reserve inputs and define recovery for delayed conversions.
- Flamethrower harvests use the same eligibility/value rules but route directly to popcorn. They must not also add convertible inventory.
- Replicate only data needed by that client. Predict visuals if helpful, then reconcile; client visuals never prove a valid harvest.

## Growth and persistence

- No per-stalk Scripts, continuous per-stalk loops, offline player simulation, or unbounded work proportional to absence duration.
- Use compact field/cell state, bounded shared scheduling, timestamp-based accrual, and client visual interpolation where appropriate. Keep online and offline economic rules identical.
- Settle D2 and D7 rules explicitly: buffer units, harvest consumption, regrowth, fractional progress, full storage, crop switching, elapsed-time bounds, and configuration changes.
- Use server-controlled timestamps, clamp negative elapsed time, bound yield, and advance accrual checkpoints so reconnects/repeated requests cannot claim time twice.
- Version saved schemas and migrations. Handle load failure without overwriting real data with defaults. Guard session ownership, retries, save budgets, and stale writes. Save related player economy state coherently.
- Plan autosave, leave, shutdown, reconnect, and failed-save recovery; never rely only on shutdown. Isolate test data from production data. Verify current official Roblox API guidance when implementing persistence or sync.

## Performance and presentation

- Design multiplayer ownership and cleanup from the first vertical slice. Optimize mobile rendering and input from the start.
- Keep crop instances, effect density, particle lifetimes, sound counts, update work, and replicated messages bounded. Batch visual/state changes where useful; measure before adopting complex optimization.
- For MCP Luau operations that do substantial work, use bounded chunks and yield between chunks. Avoid unbounded main-thread loops and parenting huge subtrees in one operation.
- Use native UI, consistent styling, readable status, touch-friendly controls, and clear first-harvest/conversion feedback. Art should express farm/crop/tool progression.
- Preserve the deliberate prototype scope. Do not add mutations, quests, trading, monetization, or a large asset library until the corresponding feature is selected.

## Testing and completion standards

- For implemented features, use Studio MCP playtests when available; static inspection is not gameplay verification. Keep edits in the intended DataModel and avoid leaving a test session running unintentionally.
- Run meaningful deterministic checks for growth/economy invariants and focused integration checks for persistence/remote contracts. Do not create tests that merely repeat implementation details or add a framework for documentation-only changes.
- Cover maturity boundaries, regrowth, capacity, partial cycles, long absences, negative time deltas, repeat requests, invalid targets, conversion duplication, and purchase failures as relevant.
- Validate two-player ownership and replication, not just a single-player happy path. State when available MCP tooling cannot provide a real multi-client test.
- Test persistence in an isolated environment: first join/rejoin, load/save failures, stale/overlapping sessions, retries, migrations, and pending batch recovery where applicable.
- Inspect touch controls, small-screen UI, and bounded effects. Emulator checks are distinct from real-device performance evidence.
- Record tested setup, observed results, errors, and unverified risks. Do not claim saves, offline growth, performance, or security are proven from a code review alone.
- Never mark a milestone complete with required acceptance checks outstanding. Report blockers directly and continue independent work where possible.

## Initial implementation handoff

Start with M1 and D1–D3. The first code task should establish verified source ownership, minimal bootstraps, a versioned in-memory player-state contract, and ownership lifecycle checks. The first gameplay slice is one field, Normal Corn, manual harvest/inventory, and regrowth; microwave/economy follow. Advanced tools, persistent storage, and offline growth are later prototype increments, not initialization work.

## Adopted workflow and first milestone

The creator has now authorized Git setup, documentation upload, native Script Sync setup, and the first starter-field gameplay foundation. This supersedes the initial documentation-only scope for that work. Implement only bootstraps, shared types/configuration, schemaVersion 1 in-memory state, an owned field, a few stalks, centralized timestamp growth, manual harvest, and server validation. No microwave, shops, flamethrower, mutations, quests, live DataStores, or publishing in this milestone.

- Official remote: https://github.com/matt-tran2026/Popcorn-Tycoon.git. Use main directly until the creator requests a branch/PR workflow.
- Commit logical verified milestones with descriptive messages; push at milestone completion and verify remote files. Never force-push without explicit authorization. Inspect any remote/local differences before integrating.
- Keep the four root planning documents maintained. Do not commit work/, outputs/, credentials, logs, or redundant initialization exports.
- Native Script Sync is verified in both directions for the current connections. Actual script roots are src/shared/ReplicatedStorage/PopcornTycoon, src/server/ServerScriptService/PopcornTycoon, and src/client/StarterPlayerScripts/PopcornTycoon. Preserve these working connections. The current exports include service/container names beneath the selected src/shared, src/server, and src/client directories. Inspect generated paths and use Reveal in Explorer when recreating connections; do not assume a folder chooser exports only the selected folder name. Repeat real round-trip probes after remapping. Source equality alone does not verify sync.
- Stalk state is individual growthStartedAt timestamps, with one yield per cycle and configurable initial capacity three. Harvest all yields and reset to current server time; starter stalks begin one cycle old. Discard fractional/excess production on harvest. This supersedes the field-buffer recommendation.
- Profile version 1 includes popcorn, rawCorn by crop ID, ownedTools/equippedTool, unlockedCrops, fields with owner/crop IDs, and stalk timestamps. Start with load/get/release in memory; leaving resets data until persistence is implemented.
- Save local place snapshots for unsynced models, terrain, UI, and Studio settings under places/ before/after milestones using Save to File. Never confuse local saving with publishing. Record whether a snapshot was actually saved; source files alone are not a complete Studio backup.
