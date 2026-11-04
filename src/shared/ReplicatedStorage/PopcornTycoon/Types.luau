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
export type HarvestResult = { ok: boolean, reason: string, amount: number, tool: string?, targets: { Vector3 }? }
-- Every price names the balance it is paid from (see Config.Economy).
export type Currency = "Cash" | "Popcorn"
export type ToolDefinition = {
	displayName: string, description: string, price: number, currency: Currency, reach: number, arcDegrees: number,
	maxTargets: number, cooldownSeconds: number, yieldMultiplier: number,
	swingSeconds: number?, snipStaggerSeconds: number?, kernelFlySeconds: number?,
}
export type TargetCandidate = { id: string, position: Vector3 }
-- Generic confirmed outcome for microwave, collection and purchase feedback. Farm upgrade
-- purchases also name the upgrade, the plot (field upgrades) and the level now owned.
export type ActionResult = { ok: boolean, reason: string, amount: number, upgradeId: string?, fieldId: string?, level: number? }
return {}
