--!strict
export type Stalk = { id: string, growthStartedAt: number }
export type Field = { id: string, ownerUserId: number, cropId: string, stalks: { [string]: Stalk } }
export type Profile = {
	schemaVersion: number,
	popcorn: number,
	rawCorn: { [string]: number },
	ownedTools: { [string]: boolean },
	equippedTool: string,
	unlockedCrops: { [string]: boolean },
	fields: { [string]: Field },
}
export type CropDefinition = { displayName: string, growthSeconds: number, popcornValue: number, maxYields: number }
export type HarvestResult = { ok: boolean, reason: string, amount: number }
return {}
