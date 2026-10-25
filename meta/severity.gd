class_name Severity
extends RefCounted
## Difficulty levels between runs, like Slay the Spire's Ascension (the design doc's "Outbreak
## levels", named Severity in game so they don't clash with the in-run Outbreak meter).
## Beating the Source at Severity N unlocks N+1, up to 10. Each level keeps every rule below it.
## The run's level is `run.meta.severity`, picked by the host before the run starts.

const MAX := 10
## Field Data bonus per level (+10% each).
const FIELD_DATA_BONUS := 0.1

## Level N's rule is LEVELS[N - 1]. `icon` is an Icons id.
const LEVELS: Array[Dictionary] = [
	{"name": "Hot zone", "rule": "The run starts at Outbreak 3", "icon": "outbreak"},
	{"name": "Price gouging", "rule": "Depot prices +15%", "icon": "depot"},
	{"name": "Short rations", "rule": "Start with 30 Supplies instead of 60", "icon": "supplies"},
	{"name": "Thin medicine", "rule": "Heal 15% after fights instead of 35%", "icon": "hospital"},
	{"name": "Swollen hosts", "rule": "Bosses have 25% more health", "icon": "boss"},
	{"name": "Lean pickings", "rule": "Fights pay 25% fewer Supplies", "icon": "supplies"},
	{"name": "No reserves", "rule": "Nobody starts with a reserve recruit", "icon": "survivors"},
	{"name": "Dense hive", "rule": "Every fight has 1 more enemy", "icon": "nest"},
	{"name": "Unbroken", "rule": "Beating a boss lowers Outbreak by 1 instead of 3", "icon": "outbreak"},
	{"name": "Ground zero", "rule": "Soldiers start the run at 20 Infection", "icon": "serum"},
]

const START_OUTBREAK := 3
const DEPOT_MULT := 1.15
const START_SUPPLIES := 30
const HEAL_AFTER_FIGHT := 0.15
const BOSS_HEALTH_MULT := 1.25
const INCOME_MULT := 0.75
const BOSS_OUTBREAK_DROP := 1
const START_INFECTION := 20


static func level(run) -> int:
	return clampi(int(run.meta.get("severity", 0)), 0, MAX)


static func at_least(run, n: int) -> bool:
	return level(run) >= n


static func name_of(n: int) -> String:
	return "Severity %d" % n if n > 0 else "Severity 0"


## Applies the start-of-run rules. Called by RunRules.new_run once the squad exists.
static func apply_new_run(run: RunState) -> void:
	if at_least(run, 1):
		run.outbreak = START_OUTBREAK
	if at_least(run, 3):
		run.supplies = START_SUPPLIES
	if at_least(run, 4):
		run.modifiers["heal_after_fight"] = HEAL_AFTER_FIGHT
	if at_least(run, 7):
		run.soldiers = run.soldiers.filter(func(r: Dictionary) -> bool: return r.status != RunSoldier.RESERVE)
	if at_least(run, 10):
		for r in run.soldiers:
			r.infection = maxi(r.infection, START_INFECTION)


## Fight rules, applied to MatchConfig.for_fight's spec before FightBuilder sees it.
static func adjust_fight_spec(run, spec: Dictionary) -> void:
	var mods: Dictionary = spec.get("modifiers", {})
	if at_least(run, 5) and spec.get("node", "") == "boss":
		mods["boss_health_mult"] = float(mods.get("boss_health_mult", 1.0)) * BOSS_HEALTH_MULT
	if at_least(run, 8):
		mods["extra_enemies"] = int(mods.get("extra_enemies", 0)) + 1
	spec["modifiers"] = mods


static func depot_mult(run) -> float:
	return DEPOT_MULT if at_least(run, 2) else 1.0


static func income(run, supplies: int) -> int:
	return roundi(supplies * INCOME_MULT) if at_least(run, 6) else supplies


static func boss_outbreak_drop(run, normal: int) -> int:
	return BOSS_OUTBREAK_DROP if at_least(run, 9) else normal


static func field_data_mult(n: int) -> float:
	return 1.0 + FIELD_DATA_BONUS * n
