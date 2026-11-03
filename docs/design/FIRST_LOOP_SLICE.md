# First loop slice: harvest → pop → sell → buy → harvest again

Status: implemented and auto-tested November 3, 2026. Needs a human playtest.
Related: vault notes "Gameplay Ideas and Audio Feel" and "Tool Design", and [GAME_DESIGN.md](../../GAME_DESIGN.md).

## What the slice contains

| Piece | Behavior |
| --- | --- |
| Sell stand | A striped cart next to the microwave at the farm entrance, on the player's own island. Pressing E sells the whole popcorn balance. The prompt shows the payout first ("50 popcorn → 100 coins"). After a sale, a toast shows the result, a coin chime plays and the counter pulses. |
| Shop button | Opens a Shop panel (also B). **Tools** tab: cards for Hands and the Sickle, each showing its effect, reach and cadence. The button shows the state: Buy, price plus how much more is needed, Owned · Equip, or Equipped · put away. **Seeds** tab: the planted Normal Corn card with growth time, yield and sale price, and a coming-soon line. |
| Sickle | Server-picked sweep of up to 3 ripe stalks on the player's own farm. It uses the same take() rule as hand picking, so whatever doesn't fit in the bag stays on the stalk. A swing plays staggered snips, and one kernel arcs from each cut stalk to the player. Swing with a mouse click, a touch tap or **F**. |
| HUD | Counters for raw corn (with a bag fill bar that turns red when full), popcorn and Coins. A status strip shows the microwave batch ("Popping 50 corn · 4s", popcorn flying in, ready), the sale payout ("Sell 50 → 100 coins") and the next goal ("Sickle 100/200 coins", then "ready to buy", then how to swing). |
| Server authority | Selling, buying, equipping and swing rewards are all decided on the server. Each check-and-commit happens in one step with no yields in between. Ownership is set together with the charge, so a repeated buy gets "Already owned" and is never charged twice. Shop requests are throttled to one per 0.25 s per player. The client only ever sends an action name and a tool ID. |

## Economy choice

**Two models:**

- **Popcorn is the currency (M3).** Popcorn is both the product and the money. There is no sell step, Extra Row costs 100 popcorn, and the HUD needs two counters.
- **Coins model (prototype, chosen).** Popcorn is the product and is sold at the stand for Coins, which buy tools.
  - What this changes: a sell step, a third HUD counter, and a payout preview.
  - Coins are the only thing you spend, so selling everything is always right and the HUD's one balance pays for tools and land alike.

The creator chose Coins on Nov 3, 2026. It is set explicitly in config:

- Every price names its currency (`currency = "Coins" | "Popcorn"`, checked by `Config.validate`).
- The Sickle is priced in Coins.
- **Extra Row moved to Coins at the creator's request: 200 Coins** (was 100 Popcorn). That is the same two full-bag passes, so its pacing is unchanged.
- Charges go through `PlayerStateService.balance/spend`; the row sign, prompt and toast read the currency from Config.

**Settled Nov 3, 2026:** Extra Row is bought with Coins. Sickle and Extra Row now compete for the same 200 coins, so the player picks tool or land first.

## Pacing and tuning

Measured in a Studio playtest with a walking bot:

| Measure | Result |
| --- | --- |
| Hub spawn to the field (pathfinding walk) | 13 s |
| Hand-picking a full 50-corn bag (steady state, 3 yields per stalk) | 17 stalks, 14 s |
| One pass (pick, pop 5 s plus flight, sell) | 50 popcorn → **100 coins** |

**Sickle price.** At 60 coins (the first hypothesis), one pass already pays for the sickle. That hypothesis assumed a 15-corn harvest, but the 6×6 field fills the bag every pass. So the price is now **200 coins = two full passes**, which matches the target.

Where to tune, all in `src/shared/ReplicatedStorage/PopcornTycoon/Config.luau`:

| Knob | Current | Effect |
| --- | --- | --- |
| `Tools.Sickle.price` | 200 Coins | Passes to the first tool |
| `Sell.coinsPerPopcorn` | 2 | Coins per pass (with a full bag) |
| `Inventory.capacity` | 50 | The real bottleneck: a pass is bag-limited, not field-limited |
| `Crops.Normal.popcornValue` | 1 | 1 raw corn → 1 popcorn |
| `Tools.Sickle.maxTargets / reach / arcDegrees / cooldownSeconds` | 3 / 9 / 140° / 0.6 s | How satisfying the sweep feels |
| `Upgrades.ExtraRow.price / currency` | 200 / Coins | Land pacing (two full-bag passes) |

**Design consequence.** Because passes are bag-limited, the sickle speeds up *filling* the bag (about 6 swings instead of 17 picks) but does not raise income per pass. That makes the **Bigger Bag** the natural second purchase.

## Progression backlog (later slices)

**Tools**
- Hand harvest: live.
- Sickle: live.
- **Bigger Bag** (separate equipment, 50 → 100, works with any tool). Probably the next purchase.
- **Heavy Sickle**: fewer targets (2), ×2 yield per stalk, slower (≈0.9 s). Already supported by `yieldMultiplier`.
- **Instant-pop tools**: grant popcorn directly and never also award raw corn (AGENTS.md rule).
  - Laser Vision: pops along a line.
  - Fireball: a tight cluster on a cooldown.
  - Flamethrower: a wide cone while moving.

**Farm**
- More rows. Extra Row already plants row 7 behind row 6, away from the stations; check that placement before changing the layout.
- Bigger stalks that look bigger and yield more.
- Faster soil (shorter `growthSeconds`).
- Variety plots on the reserved lawn left of the field.

**Machines**
- Starter microwave → faster microwave → Theater Popper (bigger batch) → Convection Oven (batch queue) → Gravity Popper (late game, bonus on big batches).
- Advanced machines need to stay worth using after instant popping. Proposal: only machines make higher-value specialty popcorn (e.g. Kettle Popcorn). Instant-pop is the fast route; machines are the valuable route.

**Crops**
- Unlock varieties in the Seeds tab, then choose what each field plants.
- Each card shows growth time, yield and sale price.
- Starting hypotheses: Classic 2, Golden 4, Rainbow 7 coins per popcorn.
- Needs a popcorn balance typed by variety, because it is a single number today.

**Audio and effects**
- Live: staggered, pitch-varied snips and a swing whoosh; kernels arc into the player; coin chime on sell and buy.
- Backlog:
  - A crisp snap on each hand pick.
  - A distinct bag-full cue (the bar turns red today, but there is no sound).
  - Microwave pops that start sparse, build into a flurry, pause, then ding.
  - A trimmed snip clip (the current one is 1.1 s long).

## Open decisions

1. Which should a new player buy first, sickle or Extra Row? Both cost 200; watch what playtesters choose.
2. Is there still a reason to hold popcorn, now that it only sells? (Specialty popcorn from machines could make it one.)
3. A typed popcorn balance for varieties: how are mixed-variety batches handled?
4. Should other players see the sickle swing? It is local only today; showing it needs an uploaded animation.
5. Is the 140° arc generous or sloppy in hand?
6. What do the Bigger Bag and Heavy Sickle cost, and should they be sold at the shed, in the Shop, or both?

## Verified vs. needs a human

- **Auto-verified (Studio, Nov 3, 2026):**
  - Economy 41/41 (new: HUD batch states), then the Extra Row checks 10/10 again after the move to Coins (coin price on the sign, popcorn alone can't buy it, charges once).
  - Tools 37/37 (new: Shop buy from anywhere, throttled repeat, repeat buy not charged, popcorn can't pay a Coins price, shed out of range, Shop equip and put-away).
  - FarmPlot 84/84 (628 parts).
- **Real-input loop (keyboard and mouse in the Studio client):**
  1. E at the microwave: popped 50.
  2. E at the stand: sold for 100 coins.
  3. B opened the Shop, showing "need 100 more".
  4. A second pass reached 200 coins.
  5. Shop Buy charged 200 once.
  6. Shop Equip equipped the sickle.
  7. F cut 3 stalks for +9 corn, with kernels and target rings.
- **Needs a human:**
  - Whether the loop makes sense without explanation.
  - Pacing feel at 200 coins.
  - How the sound timing feels.
  - Touch on a real device (tap-to-swing, the Shop at phone width).
  - Two-player runs (the Multiplayer runner was not re-run).
  - The swing as seen by other players.
- **Not re-run this time:** StarterField. Nothing it covers changed, but the earlier session's run (31/31) was before these edits.
