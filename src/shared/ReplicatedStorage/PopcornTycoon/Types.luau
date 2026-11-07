--!strict
export type Stalk = { id: string, growthStartedAt: number }
-- Farm upgrade levels (0 = not upgraded). Field upgrades belong to one plot; global ones to the
-- player. Levels are whole numbers from 0 to the upgrade's max (Config.FarmUpgrades).
export type FieldUpgradeLevels = { Soil: number, Yield: number, Storage: number }
export type GlobalUpgradeLevels = { Backpack: number }
-- One plot. plot is its index in Config.Grid.order (1 = starter); stalk ids are "<plot>_<n>".
export type Field = {
	id: string, plot: number, ownerUserId: number, cropId: string, rows: number,
	stalks: { [string]: Stalk }, upgrades: FieldUpgradeLevels,
}
export type Profile = {
	schemaVersion: number,
	popcorn: number,
	cash: number,
	rawCorn: { [string]: number },
	ownedTools: { [string]: boolean },
	equippedTool: string,
	unlockedCrops: { [string]: boolean },
	upgrades: GlobalUpgradeLevels,
	fields: { [string]: Field },
}
-- A "yield" is one completed growth cycle. maxYields is how many cycles a stalk stores;
-- cornPerYield is the raw corn each cycle is worth before tool multipliers.
export type CropDefinition = { displayName: string, growthSeconds: number, popcornValue: number, maxYields: number, cornPerYield: number }
-- The growth rules a stalk actually follows: its crop's base values with its field's upgrades
-- applied (FarmUpgrades.rules). A CropDefinition is itself a valid GrowthRules (no upgrades).
export type GrowthRules = { growthSeconds: number, maxYields: number, cornPerYield: number }
export type UpgradeScope = "Global" | "Field"
-- effects[level + 1] is the upgrade's value at that level (see Config.FarmUpgrades for units).
-- The price of buying level n + 1 is Pricing.nice(base * growth ^ n).
export type FarmUpgradeDefinition = {
	displayName: string, description: string, scope: UpgradeScope, effects: { number },
	base: number, growth: number, currency: Currency,
}
-- tool and targets are set for swung tools so the client can play one snip per stalk.
-- Alternating tools (Twin Sickles) also report the hand that swung, whether it was the combo
-- swing, and the streak of successful swings counted toward the next combo, so the client's
-- prediction (ToolController) resyncs after every swing. Dash tools report the lane length the
-- server used (dashReach: reach, or less where a wall cut it short).
export type HarvestResult = {
	ok: boolean, reason: string, amount: number, tool: string?, targets: { Vector3 }?,
	hand: SwingHand?, combo: boolean?, streak: number?, dashReach: number?,
}
-- Every price names the balance it is paid from (see Config.Economy).
export type Currency = "Cash" | "Popcorn"
export type ToolRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"
-- Harvesting families (docs/design/TOOL_COLLECTION.md). Implemented: ArcSweep (up to
-- maxTargets in a wide arc), SingleTarget (the one nearest ripe stalk in a narrow cone) and
-- LineHarvest (up to maxTargets in a straight lane ahead, laneWidth studs wide) and
-- PullHarvest (the nearest maxTargets in a long forward cone; the client pulls the ears back)
-- and DashHarvest (the LineHarvest lane, cut short where a wall would stop the character; the
-- client lunges the character down it) and TargetedPull (the ripe stalk the player aims at, up
-- to reach away, plus the nearest ripe stalks within loopRadius of it; the client throws a rope)
-- and ContinuousHarvest (held, not swung: while the button is held the server cuts one ripe
-- stalk within reach every cooldownSeconds, nearest the cutting head first, until the tool
-- overheats; see ToolContinuous and HeatState).
export type ToolBehavior = "ArcSweep" | "SingleTarget" | "LineHarvest" | "PullHarvest" | "DashHarvest" | "TargetedPull" | "ContinuousHarvest"
-- ContinuousHarvest (Weed Whacker): runSeconds of running fills the heat gauge from empty; full
-- heat locks the tool for coolSeconds while it cools to empty, and letting go cools it at the
-- same rate (1 / coolSeconds per second). headAhead: how far in front of the character the
-- cutting head is; targets nearest that point go first (reach is still measured from the root).
export type ToolContinuous = { runSeconds: number, coolSeconds: number, headAhead: number }
-- Server truth of a continuous tool's heat (the client reads it from Tool attributes): `heat`
-- (0..1) at time `at`, whether the engine is running since then, and when an overheat lock ends.
export type HeatState = { heat: number, at: number, running: boolean, overheatUntil: number }
-- DashHarvest movement (client-side; the server only shortens the lane at walls the same way):
-- speed in studs per second along the facing, hop = the upward kick at take-off (studs per
-- second). The dash covers the lane's full length (reach, or less at a wall).
export type ToolDash = { speed: number, hop: number }
-- Alternating dual-wield swings (Twin Sickles): the hands take turns, and every `every`-th
-- successful swing in a row (each within windowSeconds of the last hit) is a combo swing with
-- a wider arc.
export type SwingHand = "Right" | "Left"
export type ToolCombo = { every: number, arcDegrees: number, windowSeconds: number }
-- The shape of one swing of an alternating tool; ToolRules.nextSwing decides it.
export type SwingShape = { hand: SwingHand, combo: boolean }
-- Per-player swing state of an alternating tool (server truth; the client keeps a prediction).
export type ComboState = { hand: SwingHand, streak: number, lastHit: number }
export type ToolDefinition = {
	displayName: string, description: string, rarity: ToolRarity, behavior: ToolBehavior,
	-- arcDegrees: the sweep of ArcSweep/SingleTarget tools. laneWidth: the full width of a
	-- LineHarvest lane, centred on the facing direction.
	price: number, currency: Currency, reach: number, arcDegrees: number?, laneWidth: number?,
	maxTargets: number, cooldownSeconds: number, yieldMultiplier: number,
	-- Alternating tools: each hand's arc is centred sideDegrees toward that hand's side of the
	-- facing direction; combo makes every n-th successful swing in a row a wider arc.
	sideDegrees: number?, combo: ToolCombo?,
	-- DashHarvest tools: the lunge (laneWidth and reach give the lane it harvests).
	dash: ToolDash?,
	-- TargetedPull tools (Corn Lasso): how far from the aimed stalk the loop also snags others.
	loopRadius: number?,
	-- ContinuousHarvest tools (Weed Whacker): run time, overheat cooldown and the head's position.
	continuous: ToolContinuous?,
	swingSeconds: number?, snipStaggerSeconds: number?, kernelFlySeconds: number?,
}
export type TargetCandidate = { id: string, position: Vector3 }
-- Generic confirmed outcome for microwave, collection and purchase feedback. Farm upgrade
-- purchases also name the upgrade, the plot (field upgrades) and the level now owned.
export type ActionResult = { ok: boolean, reason: string, amount: number, upgradeId: string?, fieldId: string?, level: number? }
return {}
