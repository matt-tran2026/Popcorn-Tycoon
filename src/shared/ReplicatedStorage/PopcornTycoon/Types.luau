--!strict
export type Stalk = { id: string, growthStartedAt: number }
export type Field = { id: string, ownerUserId: number, cropId: string, rows: number, stalks: { [string]: Stalk } }
export type Profile = {
	schemaVersion: number,
	popcorn: number,
	rawCorn: { [string]: number },
	ownedTools: { [string]: boolean },
	equippedTool: string,
	unlockedCrops: { [string]: boolean },
	upgrades: { [string]: boolean },
	fields: { [string]: Field },
}
export type CropDefinition = { displayName: string, growthSeconds: number, popcornValue: number, maxYields: number }
export type HarvestResult = { ok: boolean, reason: string, amount: number }
-- Generic confirmed outcome for microwave, collection and purchase feedback.
export type ActionResult = { ok: boolean, reason: string, amount: number }
return {}
