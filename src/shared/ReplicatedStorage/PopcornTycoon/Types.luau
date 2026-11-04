--!strict
export type Stalk = { id: string, growthStartedAt: number }
export type Field = { id: string, ownerUserId: number, cropId: string, rows: number, stalks: { [string]: Stalk } }
export type Profile = {
	schemaVersion: number,
	popcorn: number,
	coins: number,
	rawCorn: { [string]: number },
	ownedTools: { [string]: boolean },
	equippedTool: string,
	unlockedCrops: { [string]: boolean },
	upgrades: { [string]: boolean },
	fields: { [string]: Field },
}
export type CropDefinition = { displayName: string, growthSeconds: number, popcornValue: number, maxYields: number }
-- tool and targets are set for swung tools so the client can play one snip per stalk.
export type HarvestResult = { ok: boolean, reason: string, amount: number, tool: string?, targets: { Vector3 }? }
-- Every price names the balance it is paid from (see Config.Economy).
export type Currency = "Coins" | "Popcorn"
export type ToolDefinition = {
	displayName: string, description: string, price: number, currency: Currency, reach: number, arcDegrees: number,
	maxTargets: number, cooldownSeconds: number, yieldMultiplier: number,
	swingSeconds: number?, snipStaggerSeconds: number?, kernelFlySeconds: number?,
}
export type TargetCandidate = { id: string, position: Vector3 }
-- Generic confirmed outcome for microwave, collection and purchase feedback.
export type ActionResult = { ok: boolean, reason: string, amount: number }
return {}
