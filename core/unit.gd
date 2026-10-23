class_name Unit
extends RefCounted
## One soldier or enemy. Plain data; behaviour lives in Rules / Combat / Infection / EnemyAI.

var id := 0
var team: int = Types.Team.PLAYER
var kind := ""            # class id ("trooper") or enemy id ("runner"), see UnitData
var display_name := ""
var owner_player := -1    # local/online player that controls this soldier; -1 for enemies
var pos := Vector2i.ZERO
var max_hp := 1
var hp := 1
var aim := 65
var defense := 0
var mobility := 5         # tiles per move action
var damage := Vector2i(3, 5)  # min, max
var actions_left := 0
var overwatch := false
var hunkered := false
var infection := 0        # 0-100, see Infection
var ai_controlled := false  # enemies, and soldiers who have Lapsed or Turned
var abilities: Array[String] = []
var cooldowns := {}       # ability id -> turns remaining
var status := {}          # free-form flags owned by modules, e.g. {"lapsed": true, "tagged": 1}


func is_alive() -> bool:
	return hp > 0


func is_enemy_of(other: Unit) -> bool:
	if status.get("lapsed", false) or other.status.get("lapsed", false):
		return other != self
	return team != other.team


func to_dict() -> Dictionary:
	return {
		"id": id, "team": team, "kind": kind, "display_name": display_name,
		"owner_player": owner_player, "pos": [pos.x, pos.y], "max_hp": max_hp, "hp": hp,
		"aim": aim, "defense": defense, "mobility": mobility, "damage": [damage.x, damage.y],
		"actions_left": actions_left, "overwatch": overwatch, "hunkered": hunkered,
		"infection": infection, "ai_controlled": ai_controlled, "abilities": abilities.duplicate(),
		"cooldowns": cooldowns.duplicate(), "status": status.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	for key in d:
		match key:
			"pos": u.pos = Vector2i(d.pos[0], d.pos[1])
			"damage": u.damage = Vector2i(d.damage[0], d.damage[1])
			"abilities": u.abilities.assign(d.abilities)
			_: u.set(key, d[key])
	return u
