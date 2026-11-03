# Popcorn Tycoon — Game Design

Status: initial source of truth; starter-field foundation authorized. Established October 29, 2026.
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

Adopted growth rules for the starter foundation:

- Every stalk has a stable ID and its own server-controlled growth-start timestamp.
- Each completed growth cycle produces one yield; initial maximum storage is three yields per stalk.
- Harvesting collects all accumulated yields from that stalk and resets its timestamp to the harvest time. Fractional progress and production beyond capacity are discarded when harvested.
- Corn automatically regrows; newly created starter fields begin with one immediately harvestable yield per stalk.
- Growth is calculated centrally from timestamps, with no per-stalk scripts or continuous per-stalk loops. Advanced tools will eventually target several stalks in one action.
- Growth duration, crop value, and storage capacity are configurable. The first gameplay milestone uses twelve Normal stalks in a 3-by-4 field and a provisional 10-second cycle.
- Storage contains raw corn, not popcorn currency. A 25-second-old stalk yields two with a 10-second cycle; after harvesting it at time 25, its next yield is ready at time 35. A 100-second-old stalk yields only three and also restarts from zero when harvested.

This supersedes the initial field-buffer proposal. There is no additional offline elapsed-time cap in the foundation calculation; the per-stalk yield cap bounds production. Offline accrual uses the same formula once persistent timestamps exist. The current in-memory layer resets on leave and does not provide cross-session offline progression. Crop switching and capacity-upgrade policies remain future decisions before those features are implemented.

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

### Adopted sickle and sell-stand rules (November 3, 2026)

The creator chose Coins from a sell stand as the tool currency. Popcorn sells at the stand for 2 Coins each (whole balance, payout shown before selling); tools and the Extra Row cost Coins. The **Sickle** (200 Coins, bought at the tool shed or from the Shop menu; raised from 60 because one 6×6 pass fills the 50-corn bag, so 200 is about two passes) cuts up to 3 ripe stalks, nearest first, inside a flat 9-stud, 140° sweep in front of the character, once per 0.6 s. Each stalk gives its ready yields under the same bag and partial-fit rules as hand picking. The server picks targets from the character's position and facing; the client only previews them. Hand picking stays available while any tool is held. Every price names its currency in Config; at the creator's request (Nov 3, 2026) Extra Row moved from 100 Popcorn to **200 Coins**, the same two full-bag passes, so Coins are the only spendable balance. The Shop button opens Tools (buy, equip) and Seeds (variety preview) tabs; the HUD shows bag fill, microwave batch state, sale payout and progress to the next tool. Full spec, pacing and backlog: docs/design/FIRST_LOOP_SLICE.md and the vault note "Tool Design".

The prototype intentionally includes the sickle and flamethrower without requiring the weed whacker first. Tool definitions should cover targeting shape, reach, cadence, target limit, unlock conditions, conversion behavior, and presentation references. Future mastery may unlock abilities, range, and effects. Do not introduce mastery into the initial prototype.

Server validation governs tool ownership/equipment, farm ownership, target maturity, range, cadence, target count, and economic outcomes. Responsive client animation can begin immediately, but only confirmed server results award or consume resources.

## 6. Inventory, conversion, and economy

Maintain a distinction between growing corn, field-stored yield, carried corn, and popcorn currency. Inventory must preserve the crop identity required to calculate value; future mutation identity must not be lost by aggregating unlike crops.

### Adopted M3 rules (November 2, 2026)

The creator settled D4–D5. All numbers are configurable starting values to tune through play.

- **Carry limit:** 50 raw corn in total across crops. At the limit, harvesting is refused with "Bag full" feedback. A partly fitting harvest takes only what fits; the stalk keeps the rest (its timestamp moves back so exactly the remainder stays ready), so no corn is lost.
- **Microwave:** one per farm, usable by the owner only. Pressing E loads the whole inventory as one batch: corn leaves the inventory and the reward is fixed at load time. Only one batch cooks at a time; it cooks for 5 seconds with popping effects, and the player may walk away and keep farming. An empty bag gives "No corn to pop" feedback.
- **Popcorn burst and magnet:** when cooking finishes, the popcorn bursts out of the microwave as a bounded number of pieces. Each piece carries part of the reward. After landing, the pieces fly one after another to the owner like a magnet, **wherever the owner is, with no range limit**, and each is credited when its flight ends (about 2 seconds after the burst). Nobody else can receive them. *(Revised November 2, 2026, by the creator: replaces walking-near pickup and the 30-second auto-collect.)*
- **No lost popcorn:** if the owner leaves while a batch is cooking or pieces are in flight, the whole remaining reward is credited at once. When persistence arrives (M5), pending batches and pieces must be saved or settled before release.
- **First upgrade, Extra Row:** a one-time purchase of 200 Coins (100 popcorn until Nov 3, 2026) that adds a seventh row of six stalks (42 in total) to the existing field, at its back edge, away from the stations. New stalks start with one ready yield. The future-expansion lawn stays **reserved for other corn varieties** and is not used for rows. Repeat rows at rising prices are deferred to the farm-expansion feature; they also extend toward the back fence. *(Revised November 3, 2026, with the 6-by-6 starter field.)*
- **Pacing targets:** first harvest within about 10 seconds, first conversion within about 1 minute, and Extra Row affordable after about 3 minutes (about two full bags). Record observed times during M3 playtests.

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

### Starter field and expansion layout (November 3, 2026)

The creator enlarged the starter field to **6 by 6 (36 stalks)** and fixed the expansion directions. Seen from the entrance: the microwave (left of the entrance path) and tool shed (right of it) stand at the **front** of the farm and **face the field**; the starter field sits behind them; **every expansion goes to the left** of the starter field (the reserved lawn now sits there); **row upgrades add rows toward the back** fence. The entrance path lines up with the field. A future sell stand would fit the gap between the two stations, as in the creator's reference image, but no selling exists yet. The plot footprint grew to 82 by 72 studs. The pacing targets below were set for 12 stalks and need re-observing with 36.

### Hub map (November 3, 2026)

The creator chose a hub-and-spoke map: a hexagonal **center island** with a giant popcorn bucket, ring and spoke paths, trees and a welcome sign, joined by six wooden bridges to six **farm islands** in open water. Every farm faces the hub: its entrance meets its bridge, so the stations are the first thing a visitor reaches, the field lies beyond them, and expansions still grow to the visitor's left and rows toward the back (away from the hub). Players spawn on the hub; a sign at each bridge head names that slot's owner or says "Open plot". Unclaimed islands show a complete starter farm as scenery (ripe 6×6 corn, stations, lawn, an "Open Farm" entrance sign) so the map always looks lived in; it has no prompts or purchase sign and is swapped for the real farm when a player takes the slot, and restored when they leave. The water is swimmable terrain over a sand sea floor, framed by a ring of distant hill islands. Six slots means the place's Max Players should be six.

**Brick look (November 3, 2026).** The map, farms and horizon use a classic Roblox brick style: plastic with classic raised Roblox studs on every face, blocky stacked-slab trees, and terraced brick islands on the horizon. Decorations are solid structures (fences, stations, signs, trees, bales, barrels, the bucket); flat paths, crop beds, small details and the corn itself stay walk-through, so harvesting and walking routes are unchanged. Fences block walking but can be jumped, as on any Roblox map.

### Adopted player plot presentation (November 1, 2026)

*Superseded in layout by the November 3 section above; kept for history.*

The reusable plot follows the supplied colorful wooden-farm reference: twelve stalks in three walkable rows on the visitor's left, a central dirt/stepping-stone path, a covered microwave display and tool shed at the rear, and a marked future expansion lawn on the right. A ten-stud entrance, owner sign, wooden fences, lanterns, hay, barrels, grass and flowers define the property. Corn gains stage-scaled leaves and rounded yellow ears. Decorative stations display their future/display-only status; no conversion, tool buying, expansion purchases, or additional fields are implemented. There are no prices on placeholder signs.

Each plot occupies a 60-by-54-stud footprint with 72-stud lateral spacing. The reserved lawn can later support another field; future growth beyond the current footprint must revise slot spacing before generating geometry. The surrounding baseplate is deliberately retained until a world-building milestone is selected. Only two shadowless local lights illuminate each plot; no particles or per-prop scripts are used.

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

Use Roblox Studio, modular strict Luau, Roblox-native multiplayer/persistence/UI, and Git/GitHub source control. The official repository is https://github.com/matt-tran2026/Popcorn-Tycoon, with direct milestone commits to main for now. Separate server systems, client presentation, and shared definitions. Avoid external databases, AWS, Node.js backends, and unnecessary frameworks. Native Roblox Script Sync is the chosen source workflow; its actual synchronization must be verified, not assumed.

The server owns farms, growth, harvesting, rewards, purchases, and saved progression. A compact data model and shared growth calculation must support multiplayer and future field expansion without simulating each stalk continuously. Persistence needs schema versions, safe loading/saving, migration, concurrency protection, and recovery behavior.

Prototype acceptance: a new player can harvest, pop, purchase, progress through three varieties and three interaction modes, leave, and return with correct saved progression and capacity-bounded corn growth. Two players cannot harvest, spend, or convert one another's resources. Mobile interaction is usable. Report actual tests and any unverified behavior. Publishing requires explicit permission.

## 11. Related documents

- `ROADMAP.md`: milestones, dependencies, priorities, and completion gates.
- `ARCHITECTURE.md`: inspection evidence, proposed hierarchy, data contracts, and decision register.
- `AGENTS.md`: instructions for future development sessions.

Initial balance and unresolved rules are proposals, not shipped behavior. Record accepted decisions in `ARCHITECTURE.md` and update affected design sections before implementing them.
