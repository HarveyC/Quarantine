class_name Combat
extends RefCounted
## Line of sight, hit chance, shooting, overwatch, hunker and class abilities.
## OWNER: combat workstream. Public functions below are the contract other modules use;
## keep their signatures stable. Current bodies are placeholders.


## True if a unit at `from` can see `to`.
static func can_see(s: GameState, from: Vector2i, to: Vector2i) -> bool:
	return from.distance_to(to) <= 12.0


## Hostile living units `u` can currently shoot at.
static func visible_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in s.units:
		if t.is_alive() and u.is_enemy_of(t) and can_see(s, u.pos, t.pos):
			out.append(t)
	return out


## Shot odds from `attacker` to `target`, optionally as if the attacker stood at `from`.
## Returns {"hit": int 0-100, "graze": int, "crit": int, "cover": Types.Cover,
##          "flanked": bool, "breakdown": Array of [label: String, value: int]}.
static func hit_chance(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos) -> Dictionary:
	return {"hit": attacker.aim, "graze": 0, "crit": 0, "cover": Types.Cover.NONE, "flanked": false,
		"breakdown": [["Aim", attacker.aim]]}


## Abilities `u` could use right now: Array of {"id", "name", "targeting": "none"|"unit"|"cell", "ready": bool}.
static func available_abilities(s: GameState, u: Unit) -> Array[Dictionary]:
	return []


static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	match action.type:
		Types.SHOOT:
			var t := s.get_unit(action.get("target", -1))
			if t == null or not visible_targets(s, u).has(t):
				return "No line of sight"
		Types.ABILITY:
			return "Not implemented"
	return ""


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	match action.type:
		Types.SHOOT:
			var t := s.get_unit(action.target)
			var odds := hit_chance(s, u, t)
			var hit: bool = s.rng.randi_range(1, 100) <= odds.hit
			var dmg: int = s.rng.randi_range(u.damage.x, u.damage.y) if hit else 0
			s.emit({"type": "shot", "unit": u.id, "target": t.id, "hit": hit, "graze": false, "crit": false,
				"damage": dmg, "chance": odds.hit, "reaction": false})
			u.actions_left = 0
			if hit:
				Rules.deal_damage(s, t, dmg, u)
		Types.OVERWATCH:
			u.overwatch = true
			u.actions_left = 0
			s.emit({"type": "overwatch", "unit": u.id})
		Types.HUNKER:
			u.hunkered = true
			u.actions_left = 0
			s.emit({"type": "hunker", "unit": u.id})


## Units on overwatch that would react to `mover` entering `cell`. Must not change state.
static func reactions_to_move(s: GameState, mover: Unit, cell: Vector2i) -> Array[Unit]:
	return []


## Fire the reactions found by reactions_to_move.
static func resolve_reactions(s: GameState, mover: Unit, reactors: Array[Unit]) -> void:
	pass
