class_name Infection
extends RefCounted
## Infection meter (0-100), tiers, mutation powers, Lapse rolls and Turning.
## OWNER: infection workstream. Public functions are the contract; bodies are placeholders.

enum Tier { CLEAN, EXPOSED, MUTATING, CRITICAL, TURNED }


static func tier(value: int) -> int:
	return Tier.CLEAN


static func tier_name(t: int) -> String:
	return Tier.keys()[t].capitalize()


## Change a unit's infection and emit {"type": "infection", "unit", "value", "tier"}.
static func add(s: GameState, u: Unit, amount: int) -> void:
	u.infection = clampi(u.infection + amount, 0, 100)
	s.emit({"type": "infection", "unit": u.id, "value": u.infection, "tier": tier(u.infection)})


## Called by Rules at the start of every team phase (Lapse rolls, recovery).
static func on_team_phase_start(s: GameState) -> void:
	pass


## Called by Rules.deal_damage whenever `source` damages `target`.
static func on_damaged(s: GameState, target: Unit, source: Unit, amount: int) -> void:
	pass


## Mutation powers `u` could use: Array of {"id", "name", "cost", "targeting": "none"|"unit"|"cell", "ready": bool}.
static func available_mutations(s: GameState, u: Unit) -> Array[Dictionary]:
	return []


static func validate_mutation(s: GameState, u: Unit, action: Dictionary) -> String:
	return "Not implemented"


static func apply_mutation(s: GameState, u: Unit, action: Dictionary) -> void:
	pass
