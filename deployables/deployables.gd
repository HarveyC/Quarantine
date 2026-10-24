class_name Deployables
extends RefCounted
## Things soldiers put on the field: sentry turrets and decoys. Each is a player-team Unit with
## status["deployable"] = kind, ai_controlled (no player commands it) and owned by the deploying
## soldier's player. It acts at the start of the team phase, like a Lapsed soldier, through
## EnemyAI's generic brain (shoot the best visible hostile; mobility 0, so it never moves).
## Deployables never count as squad for defeat, objectives or run results, take no Infection,
## and expire after `turns` team phases.

## Stat blocks. `turns` = team phases it lasts (0 = until destroyed).
const KINDS := {
	"turret": {"name": "Sentry turret", "max_hp": 4, "aim": 65, "damage": [2, 4], "turns": 3},
	"decoy": {"name": "Decoy", "max_hp": 5, "aim": 0, "damage": [0, 0], "turns": 2},
}


static func is_deployable(u: Unit) -> bool:
	return u.status.has("deployable")


## "" if a `kind` can go at `cell`, otherwise why not.
static func can_place(s: GameState, kind: String, cell: Vector2i) -> String:
	if not KINDS.has(kind):
		return "Unknown deployable"
	if not s.grid.is_walkable(cell):
		return "Can't place there"
	if s.unit_at(cell) != null:
		return "Cell is occupied"
	return ""


## Places a deployable for `owner` (the soldier who used the item or ability). Call it from
## inside an action's apply (GearRun / Combat / Progression), so it replicates with that action.
## Emits {"type": "deployed", "unit", "kind", "cell", "owner"} and returns the new unit, or null.
static func spawn(s: GameState, kind: String, cell: Vector2i, owner: Unit, turns: int = -1) -> Unit:
	if can_place(s, kind, cell) != "":
		return null
	var k: Dictionary = KINDS[kind]
	var u := Unit.new()
	u.kind = kind
	u.team = Types.Team.PLAYER
	u.display_name = k.name
	u.owner_player = owner.owner_player if owner != null else -1
	u.max_hp = k.max_hp
	u.hp = k.max_hp
	u.aim = k.aim
	u.mobility = 0
	u.damage = Vector2i(k.damage[0], k.damage[1])
	u.ai_controlled = true
	u.status["deployable"] = kind
	u.status["alerted"] = true
	u.status["owner_unit"] = owner.id if owner != null else -1
	var life: int = k.turns if turns < 0 else turns
	if life > 0:
		u.status["expires_turn"] = s.turn + life
	if kind == "decoy":
		u.status["decoy"] = true
	s.add_unit(u, cell)
	s.emit({"type": "deployed", "unit": u.id, "kind": kind, "cell": cell, "owner": u.status.owner_unit})
	return u


## Called by Rules.start_team_phase before deployables act: removes expired ones.
static func on_team_phase_start(s: GameState) -> void:
	for u in s.living(Types.Team.PLAYER):
		if is_deployable(u) and u.status.has("expires_turn") and s.turn >= u.status.expires_turn:
			u.hp = 0
			s.emit({"type": "deployable_end", "unit": u.id})
			s.emit({"type": "died", "unit": u.id})


## Living squad soldiers: player team, not deployables.
static func soldiers(s: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in s.living(Types.Team.PLAYER):
		if not is_deployable(u):
			out.append(u)
	return out
