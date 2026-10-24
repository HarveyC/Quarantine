class_name RunSoldier
extends RefCounted
## A soldier that persists across the fights of a run, stored as a plain Dictionary in
## RunState.soldiers so it serializes and replicates as-is.
##
## Framework-owned keys: id, kind, name, owner, status, hp, max_hp, infection, fights, injuries,
## scars, sit_out. Module-owned keys (opaque to the framework): "prog" (Progression record),
## "gear" (GearRun loadout).

const ACTIVE := "active"     # in the squad
const RESERVE := "reserve"   # in its owner's reserve, deploys when an active soldier dies
const DEAD := "dead"
const TURNED := "turned"
const GONE := "gone"         # left the run (sent home, etc.)

const NAMES: Array[String] = [
	"Vasquez", "Okafor", "Lindqvist", "Reyes", "Mbeki", "Kowalski", "Tanaka", "Haddad", "Novak", "Brennan",
	"Iyer", "Duarte", "Sato", "Mercer", "Adeyemi", "Volkov", "Quinn", "Halloran", "Petrov", "Achebe",
	"Moreau", "Castillo", "Ferreira", "Nakamura", "Osei", "Larsen", "Cruz", "Whitlock", "Abara", "Rook",
]


static func make(run: RunState, kind: String, owner: int, status: String = ACTIVE) -> Dictionary:
	var stats: Dictionary = UnitData.SOLDIERS[kind]
	var used := run.soldiers.map(func(o: Dictionary) -> String: return o.name)
	var free := NAMES.filter(func(n: String) -> bool: return not used.has(n))
	if free.is_empty():
		free = NAMES
	var r := {
		"id": run.new_sid(), "kind": kind, "name": free[run.rng.randi() % free.size()], "owner": owner,
		"status": status, "hp": stats.max_hp, "max_hp": stats.max_hp, "infection": 0, "fights": 0,
		"injuries": 0, "scars": [], "sit_out": 0, "gear": {},
		"prog": RunHooks.call_static("Progression", "new_record", [kind], {"kind": kind, "rank": 1}),
	}
	return r


## Squad entry for a MatchConfig: everything Rules.new_mission needs to build this soldier.
static func squad_entry(run: RunState, r: Dictionary) -> Dictionary:
	return {"kind": r.kind, "player": run.controller_of(r), "sid": r.id, "name": r.name, "hp": r.hp,
		"infection": r.infection, "prog": r.prog.duplicate(true), "gear": r.gear.duplicate(true),
		"first_turn_action_loss": run.modifiers.get("first_turn_action_loss", []).has(r.id),
		"doctrines": run.modifiers.get("doctrines", []).duplicate()}


## Called by Rules.new_mission for each squad entry carrying "sid": applies the persistent state.
## Runs before the mission starts, so it may set fields directly.
static func apply_entry(s: GameState, u: Unit, entry: Dictionary) -> void:
	u.status["sid"] = entry.sid
	u.display_name = "%s %s" % [UnitData.SOLDIERS[u.kind].name, entry.name]
	RunHooks.call_static("Progression", "apply_record", [u, entry.prog])
	RunHooks.call_static("GearRun", "apply_to_unit", [u, entry])
	u.hp = clampi(entry.hp, 1, u.max_hp)
	if entry.infection > 0:
		Infection.add(s, u, entry.infection)
	if entry.get("first_turn_action_loss", false):
		u.status["first_turn_action_loss"] = true


## After a fight: copies the unit's end state back into the record. Returns what happened.
static func absorb(r: Dictionary, u: Unit, fight_number: int) -> String:
	if u.status.get("turned", false):
		r.status = TURNED
		r.hp = 0
		return TURNED
	if not u.is_alive():
		r.status = DEAD
		r.hp = 0
		return DEAD
	r.max_hp = u.max_hp
	r.hp = u.hp
	r.infection = u.infection
	r.fights += 1
	RunHooks.call_static("GearRun", "absorb", [r, u])
	RunHooks.call_static("Progression", "after_fight", [r.prog, u, fight_number])
	return ACTIVE
