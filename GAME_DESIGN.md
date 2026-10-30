# Popcorn Tycoon — Game Design

Status: initial source of truth, documentation only. Established October 29, 2026.
Owner: the creator. Changes should preserve the agreed core loop and record meaningful scope or rule changes here.

## 1. Vision and pillars

Popcorn Tycoon is a Roblox farming and harvesting simulator with tycoon progression and offline corn growth. Players begin by picking individual ears, carrying corn to a microwave, and spending the resulting popcorn on crops, tools, and farm expansion. Later tools transform the interaction itself: wide swings clear groups of corn, continuous tools clear rows, and a flamethrower harvests and pops corn in one action.

The pillars are satisfying harvesting, visible farm progression, exciting rare discoveries, and rewarding returns after time away. Grow a Garden, Bee Swarm Simulator, Restaurant Tycoon 2, and resource collectors such as Clash of Clans are references for qualities, not templates to copy. Popcorn, popping effects, increasingly dramatic harvesting, and a cohesive farming/movie-theater visual identity distinguish this game.

Prioritize responsive interactions and polish over feature count. Avoid unrelated simulator mechanics, compulsory chores, and clutter.

## 2. Core loop and early experience

1. Grow corn automatically in a player-owned field.
2. Harvest mature corn using the equipped tool.
3. Carry harvested corn in inventory to a microwave.
4. Convert it into popcorn, the primary currency.
5. Buy corn varieties, tools, and field upgrades.
6. Repeat with more valuable crops and more powerful interactions.

The flamethrower bypasses inventory-to-microwave conversion for the corn it harvests; the server grants its popcorn reward directly. Other tools retain normal conversion unless their definition explicitly says otherwise.

The first harvest and conversion should happen quickly, and the first meaningful upgrade should be obtainable early. Exact timing targets and costs remain balance decisions. The first session should teach ownership, maturity, harvesting, conversion, and purchasing through a small number of clear interactions. Provide feedback for immature crops, full inventory, insufficient funds, and unavailable upgrades.

## 3. Farms, growth, and accumulated yield

Players own individual farms with fields. The prototype begins with one field per player; the data model should allow multiple fields with different corn varieties later. Players do not manually replant each stalk. Harvesting starts the next growth cycle automatically, with visible growth stages before maturity.

Each variety defines its growth duration, base yield/value, appearance, and unlock conditions. Fully grown fields accumulate additional harvest yields up to configurable storage capacity, including while the player is offline. Returning players see clear feedback about accumulated harvests, and eventually a fuller offline summary.

Offline growth is calculated by the server from saved timestamps and field state. No offline player simulation or separate loop/script per stalk is allowed. Online and offline growth must use the same rules so reconnecting does not change rewards.

Important rules still to resolve before growth implementation:

- Whether stored yield belongs to the whole field or individual stalks.
- How a manual harvest consumes accumulated yield and changes that stalk's visual maturity.
- What happens to production time and fractional progress at capacity.
- Whether any elapsed-time cap applies in addition to yield capacity.
- What happens to stored yield when switching varieties or upgrading capacity.

Recommended starting model: compact field state with stable harvest-cell identifiers, timestamps, and a field yield buffer. Visual stalks represent harvestable cells; cell availability prevents harvesting the same visual target repeatedly. Final consumption and regrowth rules must be written as worked examples before implementation. Storage is corn, not free popcorn: the player must still harvest and convert it unless a tool explicitly bypasses conversion.

## 4. Corn varieties

All names, prices, durations, yields, and unlock conditions are configurable and preliminary. Proposed prototype varieties are Normal, Sweet, and Golden; confirm this choice before content implementation.

| Variety | Intended role | Status |
| --- | --- | --- |
| Normal Corn | Recognizable starter crop | Proposed prototype |
| Sweet Corn | First valuable crop upgrade | Proposed prototype |
| Golden Corn | Visually rewarding prototype goal | Proposed prototype |
| Ruby Corn | Higher-tier progression | Future |
| Crystal Corn | Higher-tier progression | Future |
| Cosmic Corn | Dramatic late progression | Future |

Each definition needs a stable ID, display name, appearance reference, growth time, corn-to-popcorn value, unlock price/requirement, and optional special characteristics. Higher tiers must be recognizable by silhouette, material, and effects as well as color. Their relative value and production rate should be intentionally balanced; no final economy numbers are assigned yet.

## 5. Harvesting tools

| Tool | Interaction | Scope |
| --- | --- | --- |
| Manual | Pick individual ears and carry corn to microwave | Prototype |
| Sickle | Swing through several nearby stalks | Prototype |
| Weed whacker | Continuously harvest while moving through fields | Future |
| Flamethrower | Harvest and instantly convert corn, with fire and popping feedback | Prototype |
| Laser harvester | Longer-distance harvesting with dramatic effects | Future |

The prototype intentionally includes the sickle and flamethrower without requiring the weed whacker first. Tool definitions should cover targeting shape, reach, cadence, target limit, unlock conditions, conversion behavior, and presentation references. Future mastery may unlock abilities, range, and effects. Do not introduce mastery into the initial prototype.

Server validation governs tool ownership/equipment, farm ownership, target maturity, range, cadence, target count, and economic outcomes. Responsive client animation can begin immediately, but only confirmed server results award or consume resources.

## 6. Inventory, conversion, and economy

Maintain a distinction between growing corn, field-stored yield, carried corn, and popcorn currency. Inventory must preserve the crop identity required to calculate value; future mutation identity must not be lost by aggregating unlike crops. Inventory capacity, microwave batch size, processing time, and interruption behavior remain decisions.

The microwave should visibly and audibly pop corn and clearly report its result. A conversion must consume inputs and grant currency exactly once, including repeated requests, disconnects, and retries. Purchases validate balance, requirements, ownership, and duplicate requests on the server. Prevent negative balances, invalid numeric inputs, and duplicate unlock charges.

Proposed economic foundation: whole-number corn units and popcorn rewards, centralized reward calculation, configurable prices and rates, and no client-supplied prices or rewards. Avoid numeric overflow and define a supported currency ceiling before advanced progression.

## 7. Mutations and rare discoveries

Future mutations may include Buttered, Rainbow, Fire, Frozen, Electrified, and Giant Corn. They can affect value, appearance, size, or tool interactions. Weather may influence their probabilities. Discovery feedback should celebrate rare corn without overwhelming routine harvesting.

Basic mutations and giant corn are high-priority additions after the complete prototype. Mutation chances, stacking, creation timing, offline behavior, and tool interactions need explicit rules before development. Rare corn preservation/display is a later possibility; no collection or display system is required initially.

## 8. Presentation and accessibility

- Stylized, colorful, cohesive 3D farms and increasingly impressive crops and tools.
- Strong growth silhouettes, readable harvest feedback, and visible farm expansion.
- Consistent native Roblox UI using popcorn, theater, and farming motifs.
- Responsive harvesting/popping animations and coordinated sound effects.
- Mobile-friendly controls, generous touch targets, readable text, safe-area layouts, and minimal HUD clutter.
- Convey maturity, rarity, ownership, and errors with more than color alone.
- Bound particles, lights, sounds, and visible crop detail for mobile performance; reduce excessive effects where practical.

Prototype presentation should be polished enough to judge the loop. Do not produce a large asset library before validating it.

## 9. Scope and priorities

### Complete playable prototype

One player-owned field; three corn varieties; visible growth and automatic regrowth; manual harvesting; corn inventory; working microwave; popcorn currency; sickle; flamethrower; basic upgrades; saved progression; timestamp-based offline growth with bounded stored yields. Basic feedback on return belongs to this scope, while a detailed offline summary can follow.

### High priority after prototype

Basic mutations, giant corn, popcorn orders/NPC quests, detailed offline harvest summaries, multiple-field management, and richer harvesting animation/audio. Basic interaction feedback is already required in the prototype.

### Mid priority

Weather affecting corn, collection index, tool mastery and abilities, expanded varieties, farm customization, rotating specialty shop, and achievements.

### Long term and conditional

Seasonal events, cooperative harvest challenges, visiting farms, social features, cosmetic tool skins, trading if appropriate, and fair optional Robux monetization. None is an initial prototype requirement. Assess duplication and economy risks before trading; decide monetization only after the core experience is enjoyable.

## 10. Technical boundaries and acceptance

Use Roblox Studio, modular strict Luau, Roblox-native multiplayer/persistence/UI, and Git/GitHub source control. Separate server systems, client presentation, and shared definitions. Avoid external databases, AWS, Node.js backends, and unnecessary frameworks. Evaluate Roblox Script Sync against the actual setup before adopting it.

The server owns farms, growth, harvesting, rewards, purchases, and saved progression. A compact data model and shared growth calculation must support multiplayer and future field expansion without simulating each stalk continuously. Persistence needs schema versions, safe loading/saving, migration, concurrency protection, and recovery behavior.

Prototype acceptance: a new player can harvest, pop, purchase, progress through three varieties and three interaction modes, leave, and return with correct saved progression and capacity-bounded corn growth. Two players cannot harvest, spend, or convert one another's resources. Mobile interaction is usable. Report actual tests and any unverified behavior. Publishing requires explicit permission.

## 11. Related documents

- `ROADMAP.md`: milestones, dependencies, priorities, and completion gates.
- `ARCHITECTURE.md`: inspection evidence, proposed hierarchy, data contracts, and decision register.
- `AGENTS.md`: instructions for future development sessions.

Initial balance and unresolved rules are proposals, not shipped behavior. Record accepted decisions in `ARCHITECTURE.md` and update affected design sections before implementing them.
