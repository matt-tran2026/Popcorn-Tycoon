# M3 Microwave Loop Verification

Run on November 2, 2026, on top of `bad9f83`. The build implements the D4–D5 rules adopted the same day (GAME_DESIGN.md §6).

## What changed

- **Config:**
  - `Inventory.capacity` (50).
  - `Microwave`: cook time 5 s, 8 pieces, landing 0.7 s, flight 0.9 s, 0.08 s stagger between pieces.
  - `Upgrades.ExtraRow`: 100 popcorn.
  - `Starter.layoutRows` (4).
  - Startup validation for all of these.
- **Profile:** in-memory `upgrades` and `field.rows`. Schema version stays 1, because nothing is persisted yet.
- **HarvestService:**
  - Enforces the 50-corn bag.
  - A partly fitting harvest takes what fits; the stalk timer is backdated so exactly the remainder stays ready.
- **ConversionService (new):**
  - Owner-only, range-checked microwave.
  - The whole bag loads as one batch: it is removed and priced at load, and one batch cooks at a time.
  - When cooking ends, the reward bursts into at most 8 anchored, non-colliding pieces that split the reward exactly.
  - **Magnet payout (revised by the creator the same day):** after landing, the pieces fly one after another to the owner wherever they are, with no range. The server credits each piece on a fixed schedule (landing + stagger + flight, about 2 s in total). The client only animates. Everything still in flight is settled on leave. This replaced the first version's 6-stud walk-near pickup and 30-second auto-collect.
- **UpgradeService (new):**
  - Extra Row purchase: owner-only, range-checked, one-time, with no yields between the checks and the commit.
  - It plants stalks 13–16, which start with one yield ready.
- **FarmService / FarmVisuals:**
  - The bed is laid out for four rows, so existing stalks don't move when a row is bought. The field grew 2.5 studs at the front and back, and the cross path moved forward.
  - A double-sided "FOR SALE" sign with a BuyRow prompt stands on the empty row.
  - The microwave station moved back 2.5 studs and is no longer `VisualOnly`. An invisible door anchor carries the Microwave prompt and a bounded popping ParticleEmitter.
  - The future-expansion lawn is untouched; it is reserved for other varieties.
- **Client:**
  - The bag shows "x/50" and turns gold when full.
  - Toasts for bag full, popping, collection, auto-collect and purchase.
  - The Popcorn counter pulses on payout.
  - Pieces animate in a burst arc from the microwave, then home in on the owner's character, speeding up and shrinking as they arrive. The server places them at their landing spot; the client animates locally.
  - Other farms' Microwave and BuyRow prompts are hidden.
- **Remote:** a new `ActionResult` RemoteEvent `(kind, {ok, reason, amount})`, server to client only.

## Results

| Check | Result |
| --- | --- |
| Bootstrap | Clean Output; 15 synced scripts with no duplicates. |
| StarterField runner | PASS 30/30. |
| FarmPlot runner | PASS 31/31. Now expects 12 Harvest + 1 Microwave + 1 BuyRow prompt and a working (non-visual-only) microwave. |
| Economy runner (new, `tests/Economy.server.luau`) | PASS 35/35 after the magnet revision (33/33 on the first version). Covers: partial harvest and remainder; full bag refused without consuming the stalk; foreign, malformed and out-of-range microwave requests; full-bag batch reserved and not yet paid; double press while cooking; burst piece count and exact value split; staggered flight delays; nothing paid before landing; popcorn reaches the owner standing 150+ studs away and is credited exactly once; empty bag rejected; second batch pays once with no extra payout; settle mid-cook, and repeated; Extra Row with too little popcorn, foreign, out of range, success, sign removal, 16 stalks and prompts, row placed at the rear, second purchase rejected, new stalk harvestable. |
| Multiplayer runner | PASS 13/13 with two simulated clients. New: the second player can't use the first player's microwave or buy the first farm's row. |
| Real input | First version: E at stalk 1 → +3 corn; E at the microwave → bag 3 → 0; after cooking, 3 pieces burst and were collected; popcorn 0 → 3. Magnet version: E harvest, E at the microwave, then walked about 40 studs to the farm entrance; the popcorn was credited there. |
| Layout | Screenshots before and after purchase: the empty fourth bed shows the FOR SALE sign; after purchase, 16 stalks and no sign. There is a walkway of about 4 studs between the field and the microwave. |
| Sync equality | All 15 Studio sources match the disk files (newline-normalised length). No stray scripts, farms or probes left in Edit. |

## Pacing (D5)

A server-side bot, temporary and not committed, walked the field in snake order, harvested ripe stalks, and popped whenever it carried at least 20 corn. It ran on the first version and walked to each popcorn piece; with the magnet, that walk disappears, so the time to 100 can only get shorter.

| Milestone | Bot time | Target |
| --- | --- | --- |
| First harvest | 1.8 s | ≈10 s |
| First microwave load | 11.5 s | — |
| First popcorn collected | 18 s | ≈1 min |
| 100 popcorn (Extra Row affordable) | 106 s (4 batches, 84 harvests) | ≈3 min |

The bot routes perfectly and never pauses, so these are lower bounds. A real first-time player should land nearer the 3-minute target. Keep the 100-popcorn price until a human playtest says otherwise.

## Not verified and observations

- **Burst, magnet flight and popping particles** have not been checked by eye. Screen captures can't easily catch the roughly 2-second animation. Please watch one batch in Play.
- **Not re-run after the magnet revision:** StarterField, FarmPlot and Multiplayer. The revision touched only the microwave payout, its config and the client animation; those suites don't depend on them.
- **Default-style prompts:** the Microwave and BuyRow prompts use Roblox's default prompt UI, not the custom harvest button. Touch tapping on them is unverified.
- **Audio:** no popping sound yet; no audio asset has been chosen.
- **Human pacing** and real touch remain manual checks.
- **Persistence (M5):** pending batches and pieces live only in memory. On leave they are credited immediately. M5 must persist or settle them.
- **Microwave sign text:** "Press E to pop your corn" is partly hidden behind the kiosk mesh from some angles.
