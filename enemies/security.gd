class_name Security
extends RefCounted
## Colony Security: Hale's cordon holdouts who never turned. People, so their hits deal damage only.
##   Shieldman    a riot shield: hits from the front arc deal no damage (Encounter.modify_damage). Flanks,
##                height and blasts get round it. Slams like a Carapace.
##   Overwatcher  holds its post. It shoots what it sees, else keeps Overwatch up, and its reaction
##                shots carry no aim penalty (Combat.hit_chance).
##   Emplacement  a sandbag gun that never moves. Every enemy phase it marks a cone of floor that
##                goes off next phase for CROSSFIRE_DAMAGE on everyone standing in it, Infected too.
##   Sergeant     calls "order": every armed ally it can see goes on Overwatch (and is shown doing it).
##   Grenadier    lobs a frag over cover onto a 3x3 (EnemyAbilities "frag"), no line of sight to the spot needed.
##   Field medic  kneels by a fallen Security. REVIVE_ROUNDS rounds later it gets up on half health,
##                unless the medic is hurt first. Each body gets up once. Status keys: fallen unit
##                "downed" (waiting) / "rising" (taken); medic "reviving": {body, start}.
## Every action still goes through Rules.validate/apply. OWNER: enemies workstream.

const REVIVABLE: Array[String] = ["shieldman", "overwatcher", "sergeant", "grenadier"]


## Takes the shot it has, else keeps Overwatch up. Never advances.
static func overwatcher(s: GameState, u: Unit) -> Dictionary:
	var shot := EnemyAI._best_shot(s, u)
	if not shot.is_empty():
		return shot.action
	return EnemyAI._check(s, {"type": Types.OVERWATCH, "unit": u.id})


## Aims at the nearest soldier on its first turn, then keeps that facing and lays the cone.
static func emplacement_turn(s: GameState, u: Unit) -> void:
	if not u.status.has("facing"):
		var near: Unit = null
		for h in EnemyAI._hostiles(s, u):
			if near == null or EnemyAI._dist(u.pos, h.pos) < EnemyAI._dist(u.pos, near.pos):
				near = h
		if near == null:
			return
		var f := Vector2i(signi(near.pos.x - u.pos.x), signi(near.pos.y - u.pos.y))
		u.status["facing"] = f if f != Vector2i.ZERO else Vector2i(0, 1)
	var cells := cone(s, u)
	if cells.is_empty():
		return
	Encounter.add_telegraph(s, {"kind": "crossfire", "cells": cells, "turn": s.turn + 1,
		"damage": EnemyRoster.CROSSFIRE_DAMAGE, "source": u.id, "smash": false, "unit": u.id})


## Floor the gun covers: within range, inside the cone around its facing, in its line of sight.
static func cone(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f := Vector2(u.status.get("facing", Vector2i(0, 1))).normalized()
	var r := EnemyRoster.CROSSFIRE_RANGE
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := Vector2i(dx, dy)
			if d == Vector2i.ZERO:
				continue
			var c := u.pos + d
			if not s.grid.in_bounds(c) or not s.grid.is_walkable(c):
				continue
			if Vector2(d).normalized().dot(f) < EnemyRoster.CROSSFIRE_CONE or not Combat.can_see(s, u.pos, c):
				continue
			out.append(c)
	return out


# --- Sergeant ----------------------------------------------------------------------------------

## Orders when someone could use it, else fights like a cover shooter.
static func sergeant(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if int(u.cooldowns.get("order", 0)) <= 0 and not order_targets(s, u).is_empty():
		return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "order"})
	return EnemyBehaviours.cover_shooter(s, u, hostiles)


## Armed allies in sight that are not already on Overwatch.
static func order_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in s.living(u.team):
		if o == u or not _armed(o) or Combat.is_overwatching(s, o):
			continue
		if EnemyAbilities._cheb(u.pos, o.pos) <= EnemyRoster.ORDER_RANGE and Combat.can_see(s, u.pos, o.pos):
			out.append(o)
	return out


static func _armed(o: Unit) -> bool:
	var st: Dictionary = UnitData.ENEMIES.get(o.kind, {})
	return not st.get("melee_only", false) and not st.get("static", false) and int(st.get("damage", [0, 0])[1]) > 0 \
		and not EnemyRoster.is_boss(o) and not o.status.get("hidden", false)


static func order(s: GameState, u: Unit) -> void:
	var ids: Array[int] = []
	for o in order_targets(s, u):
		o.overwatch = true
		o.status["ow_until"] = Combat.phase_index(s) + 2
		ids.append(o.id)
		s.emit({"type": "overwatch", "unit": o.id})
	s.emit({"type": "ability", "unit": u.id, "ability": "order", "units": ids})


# --- Field medic -------------------------------------------------------------------------------

## Hook from Encounter.on_died: a Security that falls while a medic lives can be got back up.
static func on_died(s: GameState, u: Unit) -> void:
	if u.team != Types.Team.ENEMY or not REVIVABLE.has(u.kind) or u.status.get("revived", false) \
			or u.status.get("elite", false) or s.phase == Types.Phase.ENDED:
		return
	for o in s.living(u.team):
		if o.kind == "field_medic":
			u.status["downed"] = true
			s.emit({"type": "downed", "unit": u.id})
			return


## The fallen Security waiting for a medic within a step of `u`, or null.
static func body_near(s: GameState, u: Unit) -> Unit:
	for b in downed_bodies(s):
		if EnemyAbilities._cheb(u.pos, b.pos) <= 1:
			return b
	return null


static func downed_bodies(s: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	for b in s.units:
		if not b.is_alive() and b.status.get("downed", false) and not b.status.has("rising"):
			out.append(b)
	return out


static func begin_revive(s: GameState, u: Unit) -> void:
	var body := body_near(s, u)
	u.status["reviving"] = {"body": body.id, "start": s.turn}
	s.emit({"type": "ability", "unit": u.id, "ability": "revive", "target": body.id})


## Walks to the nearest fallen ally and kneels; shoots like a cover shooter when nobody is down.
static func medic(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if body_near(s, u) != null:
		return EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "revive"})
	var bodies := downed_bodies(s)
	if bodies.is_empty():
		return EnemyBehaviours.cover_shooter(s, u, hostiles)
	var body: Unit = bodies[0]
	for b in bodies:
		if EnemyAI._dist(u.pos, b.pos) < EnemyAI._dist(u.pos, body.pos):
			body = b
	var reach := Rules.move_range(s, u)
	var best := u.pos
	var best_score := -INF
	for c in reach:
		if c == body.pos or EnemyAbilities._cheb(c, body.pos) > 1:
			continue
		var sc := -int(reach[c]) * 0.1 + EnemyBehaviours._flee_score(s, u, c, hostiles) * 0.2
		if sc > best_score:
			best_score = sc
			best = c
	if best != u.pos:
		return EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": best})
	return {}


## Hook from Encounter.on_unit_turn_start: the medic's patient gets up.
static func on_turn_start(s: GameState, u: Unit) -> void:
	if u.kind != "field_medic" or not u.status.has("reviving"):
		return
	var rv: Dictionary = u.status.reviving
	if s.turn - int(rv.start) < EnemyRoster.REVIVE_ROUNDS:
		return
	u.status.erase("reviving")
	var body := s.get_unit(int(rv.body))
	if body == null or body.is_alive():
		return
	body.status["rising"] = true
	var n := EnemyRoster.make(body.kind)
	s.add_unit(n, Encounter.free_cell(s, body.pos))
	n.status["alerted"] = true
	n.status["revived"] = true
	n.hp = maxi(1, (n.max_hp + 1) / 2)
	s.emit({"type": "revived", "unit": n.id, "body": body.id, "by": u.id, "hp": n.hp})


## Hook from Encounter.on_damaged: a hit on a kneeling medic breaks the revive off.
static func on_damaged(s: GameState, target: Unit) -> void:
	if target.kind == "field_medic" and target.status.has("reviving"):
		target.status.erase("reviving")
		s.emit({"type": "revive_broken", "unit": target.id})
