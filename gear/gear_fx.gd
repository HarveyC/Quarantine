class_name GearFx
extends RefCounted
## What gear does in a mission. Combat, Rules and Infection call these hooks with one line
## each; everything reads the gear GearRun.apply_to_unit stamped into `unit.status["gear"]`.
##
## Status keys owned here (in `unit.status`):
##   "burning": int        Burning ticks left (2 damage at each team phase start)
##   "burn_source": int    unit id that set it Burning (Burn set spread, Spotter flare)
##   "gear_fire_mobility": int mobility currently added by Flame-retardant coat
##   "suppress_extra": int extra aim penalty on a Suppressed unit (Compensator, Shock rounds Mk II)
##   "smoked": int         phase index a smoke grenade's +20 defense ends on
##   "contained": int      phase index until which the unit gains no Infection (Containment emitter)
##   "gear_uses": {ability id: uses this fight}
##   "gear_refund_turn": int  turn a Close-set kill last refunded a move
##   "gear_moved_turn": int   turn the unit last moved (Bipod)
##   "gear_set_mobility": int mobility currently added by the Close set bonus
##
## Gadgets and pocket consumables are abilities: ids "gear:<item>" and "item:<consumable>".
## Combat delegates them here (owns / validate_ability / apply_ability / available_abilities).

const BURN_DAMAGE := 2
const SMOKE_DEFENSE := 20
const CLOSE := 3.0

## Items whose effect needs a system the game doesn't have yet (fog of war, restraint,
## mutation costs). They're kept out of reward and depot draws until they work.
const PENDING: Array[String] = [
	"symbiotic_suit",
	"crossfire", "hold_position", "bloodletting",
	"containment_foam",
]
## Fire tiles gear makes: Thermite line length per Mk, and how long each kind of fire lasts.
const THERMITE_LENGTH := [3, 5]
const THERMITE_TURNS := 2
const BURN_SET_FIRE_TURNS := 1
const SCORCHED_PURGE := 10

## Gadget abilities: targeting, action cost (0 = free, -1 = ends turn), uses per fight
## (Mk I, Mk II; 0 = unlimited) and cooldown (Mk I, Mk II).
const GADGETS := {
	"flare_launcher": {"targeting": "cell", "cost": 1, "uses": [0, 0], "cooldown": [3, 2], "range": 8.0},
	"concussion_launcher": {"targeting": "cell", "cost": 1, "uses": [1, 1], "cooldown": [0, 0], "range": 7.0},
	"thermite_charge": {"targeting": "cell", "cost": 1, "uses": [1, 1], "cooldown": [0, 0], "range": 6.0},
	"med_injector": {"targeting": "unit", "cost": 1, "uses": [1, 1], "cooldown": [0, 0]},
	"adrenal_pump": {"targeting": "none", "cost": 0, "uses": [1, 2], "cooldown": [0, 0]},
	"deployable_cover": {"targeting": "cell", "cost": 1, "uses": [1, 2], "cooldown": [0, 0], "range": 1.5},
	"grapple": {"targeting": "cell", "cost": 1, "uses": [1, 2], "cooldown": [0, 0], "range": 5.0},
	"containment_emitter": {"targeting": "none", "cost": 1, "uses": [0, 0], "cooldown": [3, 2]},
	"sentry_turret": {"targeting": "cell", "cost": 1, "uses": [1, 1], "cooldown": [0, 0], "range": 3.0},
}
## Sentry turret per Mk: team phases it lasts, aim, damage (Deployables runs it).
const TURRET := [{"turns": 3, "aim": 60, "damage": 2}, {"turns": 4, "aim": 70, "damage": 3}]
const CONSUMABLE_USE := {
	"medkit": {"targeting": "unit", "cost": 1},
	"suppressant_shot": {"targeting": "unit", "cost": 1},
	"stim": {"targeting": "none", "cost": 0},
	"frag_grenade": {"targeting": "cell", "cost": 1, "range": 6.0},
	"flashbang": {"targeting": "cell", "cost": 1, "range": 6.0},
	"smoke_grenade": {"targeting": "cell", "cost": 1, "range": 6.0},
	"recon_drone": {"targeting": "cell", "cost": 1, "range": Vision.DRONE_RANGE},
}
## Rangefinder: extra overwatch range per Mk.
const RANGEFINDER_RANGE := [2, 3]


static func is_pending(id: String) -> bool:
	return PENDING.has(id)


# --- Queries ---------------------------------------------------------------------------

static func mk(u: Unit, id: String) -> int:
	var g: Dictionary = u.status.get("gear", {})
	for slot in g:
		if g[slot].id == id:
			return int(g[slot].mk)
	return 0


static func has(u: Unit, id: String) -> bool:
	return mk(u, id) > 0


static func has_set(u: Unit, tag: String) -> bool:
	return u.status.has("gear") and GearTags.unit_has_set(u, tag)


static func is_burning(_s: GameState, u: Unit) -> bool:
	return int(u.status.get("burning", 0)) > 0


static func is_marked(s: GameState, u: Unit) -> bool:
	return Combat.has_status(s, u, "tagged")


## Smart-link: `u` may shoot Marked enemy `t` without line of sight while any ally sees it.
static func smart_link_shot(s: GameState, u: Unit, t: Unit) -> bool:
	if not has(u, "smart_link") or not u.is_enemy_of(t) or not t.is_alive() or t.status.get("hidden", false):
		return false
	return is_marked(s, t) and Vision.sees_unit(s, u.team, t)


## Extra tiles of overwatch range (Rangefinder), added to the watcher's sight radius.
static func overwatch_range_bonus(u: Unit) -> int:
	var m := mk(u, "rangefinder")
	return RANGEFINDER_RANGE[clampi(m, 1, 2) - 1] if m > 0 else 0


## Rough awake-mutation count until Progression reports it: one per Infection tier reached.
static func awake_mutations(u: Unit) -> int:
	var p = GearTags.progression()
	if GearTags.provides(p, "awake_mutation_count"):
		return int(p.awake_mutation_count(u))
	return clampi(Infection.tier(u.infection), 0, 3)


static func _dist(a: Vector2i, b: Vector2i) -> float:
	return a.distance_to(b)


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --- Hit chance (Combat.hit_chance) ----------------------------------------------------

## Appends gear terms to a hit-chance breakdown ([label, value] pairs).
static func odds_terms(s: GameState, a: Unit, t: Unit, from: Vector2i, reaction: bool, cover: int, breakdown: Array) -> void:
	if a.status.has("gear"):
		if reaction:
			if has(a, "bipod") and a.status.get("gear_moved_turn", -1) != s.turn:
				breakdown.append(["Bipod", 10 if mk(a, "bipod") < 2 else 15])
			if has_set(a, "Overwatch"):
				breakdown.append(["Overwatch set", 10])
			if has(a, "rangefinder") and cover == Types.Cover.FULL:
				breakdown.append(["Rangefinder", Combat.COVER_FULL - Combat.COVER_HALF])
			if has(a, "killbox") and is_marked(s, t):
				breakdown.append(["Killbox", 100])
		if Combat.has_status(s, t, "suppressed"):
			if has_set(a, "Suppress"):
				breakdown.append(["Suppress set", 15])
			if has(a, "breach_and_clear") and _dist(from, t.pos) <= CLOSE and cover != Types.Cover.NONE:
				breakdown.append(["Breach and clear", Combat.COVER_FULL if cover == Types.Cover.FULL else Combat.COVER_HALF])
		if mk(a, "smart_link") >= 2 and not Combat.can_see(s, from, t.pos) and smart_link_shot(s, a, t):
			breakdown.append(["Smart-link", 10])
		if mk(a, "suppressor") >= 2 and not t.status.get("alerted", true):
			breakdown.append(["Suppressor", 10])
	if a.team == Types.Team.PLAYER and a.status.get("doctrines", []).has("buddy_system"):
		for o in s.living(Types.Team.PLAYER):
			if o != a and _cheb(o.pos, from) == 1 and not o.is_enemy_of(a):
				breakdown.append(["Buddy system", 10])
				break
	if Combat.has_status(s, a, "suppressed") and a.status.get("suppress_extra", 0) > 0:
		breakdown.append(["Suppressed (gear)", -int(a.status.suppress_extra)])
	if t.status.has("gear") and has(t, "riot_shield") and cover == Types.Cover.NONE:
		breakdown.append(["Riot shield", -Combat.COVER_HALF])
	if Combat.has_status(s, t, "smoked"):
		breakdown.append(["Smoke", -SMOKE_DEFENSE])
	if t.team == Types.Team.PLAYER:
		for g in s.living(Types.Team.PLAYER):
			if g != t and _cheb(g.pos, t.pos) == 1 and has_set(g, "Guard"):
				breakdown.append(["Guarded", -5])
				break


# --- Shots (Combat.fire) ---------------------------------------------------------------

## Damage of a landed shot after gear.
static func shot_damage(s: GameState, u: Unit, t: Unit, dmg: int, reaction: bool) -> int:
	if not u.status.has("gear") or dmg <= 0:
		return dmg
	var close := _dist(u.pos, t.pos) <= CLOSE
	if close and has(u, "slug_rounds"):
		dmg += mk(u, "slug_rounds")
	if reaction and has(u, "expanding_rounds"):
		dmg += 1 + mk(u, "expanding_rounds")
	if has_set(u, "Mark") and is_marked(s, t):
		dmg += 1
	if has_set(u, "Strain") and Infection.tier(u.infection) >= Infection.Tier.EXPOSED:
		dmg += 1
	if has(u, "spore_rounds"):
		dmg += awake_mutations(u) + (1 if mk(u, "spore_rounds") >= 2 else 0)
	return dmg


## Everything a shot sets off once it has resolved: on-hit ammo, kills, self-Infection.
static func after_shot(s: GameState, u: Unit, t: Unit, hit: bool, reaction: bool, dmg: int = 0) -> void:
	if not u.status.has("gear"):
		return
	var close := _dist(u.pos, t.pos) <= CLOSE
	if has(u, "spore_rounds"):
		Infection.add(s, u, 2)
	if hit and t.is_alive():
		if has(u, "tracer_rounds"):
			_mark(s, t, 1 if mk(u, "tracer_rounds") < 2 else 3)
		if has(u, "suppressor") and not t.status.get("alerted", true):
			_mark(s, t, 2)
		if has(u, "shock_rounds"):
			_suppress(s, u, t, 15 if mk(u, "shock_rounds") >= 2 else 0)
		if has(u, "incendiary_rounds"):
			ignite(s, u, t, mk(u, "incendiary_rounds"))
		if has(u, "igniter_barrel") and u.status.get("igniter_turn", -1) != s.turn:
			u.status["igniter_turn"] = s.turn
			set_fire(s, u, [t.pos], mk(u, "igniter_barrel"))
	if hit and t.team == Types.Team.ENEMY and has(u, "purifier_rounds") and u.infection > 0:
		Infection.add(s, u, -(3 if mk(u, "purifier_rounds") < 2 else 5))
	if hit and close and has(u, "feral_grip") and u.hp < u.max_hp:
		u.hp += 1
		s.emit({"type": "gear", "unit": u.id, "item": "feral_grip", "heal": 1, "hp": u.hp})
	if hit and close and dmg > 0 and has(u, "choke"):
		for o in s.living():
			if o != t and u.is_enemy_of(o) and _cheb(o.pos, t.pos) == 1:
				var splash := dmg if mk(u, "choke") >= 2 else maxi(1, dmg / 2)
				s.emit({"type": "gear", "unit": u.id, "item": "choke", "target": o.id, "damage": splash})
				Rules.deal_damage(s, o, splash, u)
				break
	if not t.is_alive() and u.is_enemy_of(t):
		on_kill(s, u, t, reaction)


static func on_kill(s: GameState, u: Unit, t: Unit, reaction: bool) -> void:
	var was_marked := t.status.has("tagged") and int(t.status.tagged) > Combat.phase_index(s)
	if reaction and has_set(u, "Overwatch"):
		u.overwatch = true
		u.status["ow_until"] = Combat.phase_index(s) + 2
		s.emit({"type": "overwatch", "unit": u.id})
	if has_set(u, "Close") and _dist(u.pos, t.pos) <= CLOSE and u.status.get("gear_refund_turn", -1) != s.turn \
			and s.phase == Types.Phase.TEAM and not reaction:
		u.status["gear_refund_turn"] = s.turn
		u.actions_left += 1
		s.emit({"type": "gear", "unit": u.id, "item": "close_set", "actions": u.actions_left})
	if was_marked and has_set(u, "Mark"):
		var best: Unit = null
		for o in s.living():
			if u.is_enemy_of(o) and Combat.can_see(s, u.pos, o.pos) and (best == null or _dist(t.pos, o.pos) < _dist(t.pos, best.pos)):
				best = o
		if best:
			best.status["tagged"] = t.status.tagged
			s.emit({"type": "gear", "unit": u.id, "item": "mark_set", "target": best.id})
	if is_burning(s, t):
		_burn_set_spread(s, t)
	if is_burning(s, t) and has(u, "phosphor_rounds"):
		var radius := 1 if mk(u, "phosphor_rounds") < 2 else 2
		for o in s.living():
			if u.is_enemy_of(o) and _cheb(o.pos, t.pos) <= radius:
				ignite(s, u, o, 1)


static func _mark(s: GameState, t: Unit, phases: int) -> void:
	var until := Combat.phase_index(s) + phases
	if int(t.status.get("tagged", 0)) < until:
		t.status["tagged"] = until


static func _suppress(s: GameState, u: Unit, t: Unit, extra: int = 0) -> void:
	t.status["suppressed"] = Combat.phase_index(s) + 2
	t.overwatch = false
	var bonus := extra
	if has(u, "compensator"):
		bonus += 10 if mk(u, "compensator") < 2 else 15
	if bonus > 0:
		t.status["suppress_extra"] = bonus
	else:
		t.status.erase("suppress_extra")
	s.emit({"type": "gear", "unit": u.id, "item": "suppress", "target": t.id})


## Sets `t` Burning for `turns` ticks (the Burn set adds one).
static func ignite(s: GameState, u: Unit, t: Unit, turns: int) -> void:
	if has_set(u, "Burn"):
		turns += 1
	if int(t.status.get("burning", 0)) < turns:
		t.status["burning"] = turns
		t.status["burn_source"] = u.id
		s.emit({"type": "burning", "unit": t.id, "turns": turns})


## Puts `u`'s fire on `cells` for `turns` rounds (Hazards; walls are skipped there).
static func set_fire(s: GameState, u: Unit, cells: Array, turns: int) -> void:
	Hazards.add(s, cells, "fire", turns, u.id)


## Burn set: an enemy that dies Burning from a Burn-set soldier's fire sets the tiles around it alight.
static func _burn_set_spread(s: GameState, t: Unit) -> void:
	var src := s.get_unit(int(t.status.get("burn_source", -1)))
	if src == null or not has_set(src, "Burn"):
		return
	var cells: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := t.pos + Vector2i(dx, dy)
			if s.grid.in_bounds(c):
				cells.append(c)
	set_fire(s, src, cells, BURN_SET_FIRE_TURNS)


## Hazards hook: what a hazard tile does to `u` once gear has its say. Returns
## Vector2i(damage, infection). Flame-retardant coat ignores fire, Filter mask ignores spores,
## Scorched earth fire spares the squad and burns Infection off them instead, Spotter flare
## doubles fire damage on Marked enemies.
static func hazard_hit(s: GameState, u: Unit, h: Dictionary, damage: int, infection: int) -> Vector2i:
	if h.kind == "fire":
		var src := s.get_unit(int(h.get("source", -1)))
		if src != null and has(src, "scorched_earth") and not src.is_enemy_of(u):
			if u.team == Types.Team.PLAYER and u.infection > 0 and not u.status.has("deployable"):
				s.emit({"type": "gear", "unit": src.id, "item": "scorched_earth", "target": u.id})
				Infection.add(s, u, -SCORCHED_PURGE)
			return Vector2i.ZERO
		if has(u, "flame_coat"):
			return Vector2i(0, infection)
		if src != null and has(src, "spotter_flare") and is_marked(s, u):
			damage *= 2
	if h.kind == "spore" and has(u, "filter_mask"):
		infection = 0
	return Vector2i(damage, infection)


## A line of `length` tiles starting at `cell`, running away from `from` (8 directions).
static func fire_line(from: Vector2i, cell: Vector2i, length: int) -> Array[Vector2i]:
	var d := cell - from
	var dir := Vector2i(signi(d.x), signi(d.y))
	if dir == Vector2i.ZERO:
		dir = Vector2i.RIGHT
	var out: Array[Vector2i] = []
	for i in length:
		out.append(cell + dir * i)
	return out


## Combat's Suppress ability: Compensator penalty, Rotary feed cone.
static func on_suppress(s: GameState, u: Unit, t: Unit) -> void:
	if not u.status.has("gear"):
		return
	if has(u, "compensator"):
		t.status["suppress_extra"] = 10 if mk(u, "compensator") < 2 else 15
	if has(u, "rotary_feed"):
		var reach := 3 if mk(u, "rotary_feed") < 2 else 4
		var dir := Vector2(t.pos - u.pos).normalized()
		for o in s.living():
			if o == t or not u.is_enemy_of(o) or not Combat.can_see(s, u.pos, o.pos):
				continue
			var off := Vector2(o.pos - t.pos)
			if off.length() <= reach and (off.length() < 0.1 or dir.dot(off.normalized()) > 0.5 or _cheb(o.pos, t.pos) <= 1):
				_suppress(s, u, o)


# --- Damage taken (Rules.deal_damage) and Infection (Infection.on_damaged) --------------

static func damage_taken(_s: GameState, target: Unit, amount: int, _source: Unit) -> int:
	var armor := int(target.status.get("armor", 0))
	return maxi(1, amount - armor) if armor > 0 and amount > 0 else amount


## Infection a soldier gains from a bite or hit after gear.
static func bite_infection(s: GameState, target: Unit, gain: int) -> int:
	if Combat.has_status(s, target, "contained"):
		return 0
	for g in s.living(Types.Team.PLAYER):
		if g != target and has(g, "quarantine_field") and Combat.is_hunkered(s, g) and _cheb(g.pos, target.pos) == 1:
			return 0
	if has(target, "hazard_liner"):
		return gain / 2 if mk(target, "hazard_liner") < 2 else gain / 3
	return gain


# --- Turn flow (Rules) -----------------------------------------------------------------

static func on_team_phase_start(s: GameState) -> void:
	for u in s.living():
		if is_burning(s, u):
			var left := int(u.status.burning) - 1
			if left > 0:
				u.status["burning"] = left
			else:
				u.status.erase("burning")
			var dmg := BURN_DAMAGE
			var src := s.get_unit(int(u.status.get("burn_source", -1)))
			if src != null and has(src, "spotter_flare") and is_marked(s, u):
				dmg *= 2
			s.emit({"type": "burn", "unit": u.id, "damage": dmg})
			Rules.deal_damage(s, u, dmg)
			if not u.is_alive():
				_burn_set_spread(s, u)
	for u in s.living(Types.Team.PLAYER):
		var want := 1 if has_set(u, "Close") else 0
		var have := int(u.status.get("gear_set_mobility", 0))
		if want != have:
			u.mobility += want - have
			u.status["gear_set_mobility"] = want
		var fire := 0
		if has(u, "flame_coat") and Hazards.at(s, u.pos).get("kind", "") == "fire":
			fire = mk(u, "flame_coat")
		var had := int(u.status.get("gear_fire_mobility", 0))
		if fire != had:
			u.mobility += fire - had
			u.status["gear_fire_mobility"] = fire


static func on_move(s: GameState, u: Unit) -> void:
	u.status["gear_moved_turn"] = s.turn


# --- Gadgets and pocket items as abilities ---------------------------------------------

static func owns(id: String) -> bool:
	return id.begins_with("gear:") or id.begins_with("item:")


static func _def(u: Unit, id: String) -> Dictionary:
	var key := id.substr(5)
	if id.begins_with("gear:") and GADGETS.has(key) and has(u, key):
		var m := mk(u, key)
		var g: Dictionary = GADGETS[key]
		return {"targeting": g.targeting, "cost": g.cost, "uses": g.uses[m - 1], "cooldown": g.cooldown[m - 1],
			"range": g.get("range", 1.5), "name": GearData.item_name(key), "desc": GearData.desc(key, m)}
	if id.begins_with("item:") and CONSUMABLE_USE.has(key) and charges(u, key) > 0:
		var c: Dictionary = CONSUMABLE_USE[key]
		return {"targeting": c.targeting, "cost": c.cost, "uses": 0, "cooldown": 0, "range": c.get("range", 1.5),
			"name": "%s ×%d" % [GearData.item_name(key), charges(u, key)], "desc": GearData.desc(key)}
	return {}


static func charges(u: Unit, id: String) -> int:
	var n := 0
	for p in u.status.get("pockets", []):
		if p != null and p.id == id:
			n += int(p.charges)
	return n


## Ability entries in Combat.available_abilities' shape for this soldier's gadget and pockets.
static func available_abilities(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if u.team != Types.Team.PLAYER or not u.status.has("gear"):
		return out
	var ids: Array[String] = []
	var g = u.status.gear.get("gadget")
	if g != null and GADGETS.has(g.id):
		ids.append("gear:" + g.id)
	for p in u.status.get("pockets", []):
		if p != null and CONSUMABLE_USE.has(p.id) and not ids.has("item:" + p.id):
			ids.append("item:" + p.id)
	for id in ids:
		var d := _def(u, id)
		if d.is_empty():
			continue
		var reason := _ready_reason(s, u, id, d)
		out.append({"id": id, "name": d.name, "targeting": d.targeting, "cost": d.cost,
			"cooldown": int(u.cooldowns.get(id, 0)), "desc": d.desc, "targets": _targets(s, u, id, d),
			"ready": reason == "", "reason": reason, "gear": true})
	return out


static func _ready_reason(_s: GameState, u: Unit, id: String, d: Dictionary) -> String:
	if not u.is_alive() or u.actions_left < 1:
		return "No actions left"
	if int(u.cooldowns.get(id, 0)) > 0:
		return "Cooling down (%d)" % int(u.cooldowns[id])
	if d.uses > 0 and int(u.status.get("gear_uses", {}).get(id, 0)) >= d.uses:
		return "Used up this fight"
	return ""


static func _targets(s: GameState, u: Unit, id: String, d: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if d.targeting != "unit":
		return out
	for t in s.living():
		if _target_error(s, u, id, t) == "":
			out.append(t.id)
	return out


static func _target_error(s: GameState, u: Unit, id: String, t: Unit) -> String:
	if t == null or not t.is_alive():
		return "No such target"
	if u.is_enemy_of(t):
		return "Not an ally"
	if _cheb(u.pos, t.pos) > 1:
		return "Too far"
	match id:
		"item:medkit":
			if t.hp >= t.max_hp:
				return "Already at full health"
		"item:suppressant_shot", "gear:med_injector":
			if t.infection <= 0:
				return "Not infected"
	return ""


static func _cell_error(s: GameState, u: Unit, id: String, d: Dictionary, cell: Variant) -> String:
	if not cell is Vector2i:
		return "No target cell"
	var c: Vector2i = cell
	if not s.grid.in_bounds(c):
		return "Invalid cell"
	if _dist(u.pos, c) > d.range:
		return "Too far"
	match id:
		"gear:deployable_cover":
			if not s.grid.is_walkable(c) or s.unit_at(c) != null or c == u.pos:
				return "Needs an empty tile next to you"
		"gear:grapple":
			var delta := c - u.pos
			if delta == Vector2i.ZERO or not (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y)):
				return "Straight lines only"
			if not s.grid.is_walkable(c) or s.unit_at(c) != null:
				return "Can't land there"
		"gear:sentry_turret":
			var why := Deployables.can_place(s, "turret", c)
			if why != "":
				return why
			if not Combat.can_see(s, u.pos, c):
				return "No line of sight"
		"item:recon_drone":
			pass   # it flies: any cell in range
		_:
			if s.grid.blocks_los(c) or not Combat.can_see(s, u.pos, c):
				return "No line of sight"
	return ""


static func validate_ability(s: GameState, u: Unit, action: Dictionary) -> String:
	var id: String = action.get("ability", "")
	var d := _def(u, id)
	if d.is_empty():
		return "Unknown ability"
	var reason := _ready_reason(s, u, id, d)
	if reason != "":
		return reason
	match d.targeting:
		"unit":
			return _target_error(s, u, id, s.get_unit(action.get("target", u.id)))
		"cell":
			return _cell_error(s, u, id, d, action.get("cell"))
	return ""


static func apply_ability(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.ability
	var d := _def(u, id)
	u.actions_left = 0 if d.cost < 0 else maxi(0, u.actions_left - int(d.cost))
	if d.cooldown > 0:
		u.cooldowns[id] = d.cooldown
	var uses: Dictionary = u.status.get("gear_uses", {})
	uses[id] = int(uses.get(id, 0)) + 1
	u.status["gear_uses"] = uses
	if id.begins_with("item:"):
		_use_charge(u, id.substr(5))
	var ev := {"type": "ability", "unit": u.id, "ability": id, "name": GearData.item_name(id.substr(5))}
	var key := id.substr(5)
	var t: Unit = s.get_unit(action.get("target", u.id)) if d.targeting == "unit" else null
	var cell: Vector2i = action.get("cell", u.pos) if d.targeting == "cell" else u.pos
	if t:
		ev["target"] = t.id
	if d.targeting == "cell":
		ev["cell"] = cell
	var area := func(r: int) -> Array[Unit]:
		var out: Array[Unit] = []
		for o in s.living():
			if _cheb(o.pos, cell) <= r:
				out.append(o)
		return out
	match key:
		"flare_launcher":
			var hit: Array = (area.call(1) as Array).filter(func(o): return u.is_enemy_of(o))
			for o in hit:
				_mark(s, o, 3)
			ev["units"] = hit.map(func(o): return o.id)
		"concussion_launcher", "flashbang":
			var r := 2 if key == "concussion_launcher" and mk(u, key) >= 2 else 1
			var hit: Array = (area.call(r) as Array).filter(func(o): return u.is_enemy_of(o))
			for o in hit:
				_suppress(s, u, o)
			ev["units"] = hit.map(func(o): return o.id)
		"thermite_charge":
			var line := fire_line(u.pos, cell, THERMITE_LENGTH[clampi(mk(u, key), 1, 2) - 1])
			s.emit(ev)
			set_fire(s, u, line, THERMITE_TURNS)
			for o in s.living():
				if u.is_enemy_of(o) and line.has(o.pos):
					ignite(s, u, o, 1)
			return
		"med_injector", "suppressant_shot":
			var amount := 15
			if key == "med_injector" and mk(u, key) >= 2:
				amount = 25
			s.emit(ev)
			Infection.add(s, t, -amount)
			if has_set(u, "Purge") and t != u and t.hp < t.max_hp:
				t.hp += 1
			return
		"medkit":
			var healed := mini(4, t.max_hp - t.hp)
			t.hp += healed
			ev["heal"] = healed
			ev["hp"] = t.hp
		"adrenal_pump":
			s.emit(ev)
			Infection.add(s, u, 15)
			return
		"stim":
			u.actions_left += 1
			s.emit(ev)
			Infection.add(s, u, 5)
			return
		"containment_emitter":
			var until := Combat.phase_index(s) + 2
			for o in s.living(Types.Team.PLAYER):
				if _cheb(o.pos, u.pos) <= 2:
					o.status["contained"] = until
		"deployable_cover":
			s.grid.tiles[cell.y * s.grid.width + cell.x] = Types.Tile.WALL
		"grapple":
			var from := u.pos
			u.pos = cell
			s.emit(ev)
			var path: Array[Vector2i] = [cell]
			s.emit({"type": "move", "unit": u.id, "from": from, "path": path})
			return
		"sentry_turret":
			var k: Dictionary = TURRET[clampi(mk(u, key), 1, 2) - 1]
			s.emit(ev)
			var tu := Deployables.spawn(s, "turret", cell, u, k.turns)
			if tu != null:
				tu.aim = k.aim
				tu.damage = Vector2i(k.damage, k.damage)
			return
		"frag_grenade":
			var hit: Array = (area.call(1) as Array).filter(func(o): return o != u)
			ev["units"] = hit.map(func(o): return o.id)
			ev["damage"] = 3
			s.emit(ev)
			for o in hit:
				Rules.deal_damage(s, o, 3, u)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var c := cell + Vector2i(dx, dy)
					if s.grid.in_bounds(c) and s.grid.tile(c) == Types.Tile.LOW:
						s.grid.tiles[c.y * s.grid.width + c.x] = Types.Tile.FLOOR
			return
		"recon_drone":
			s.emit(ev)
			Vision.add_reveal(s, cell, Vision.DRONE_RADIUS)
			return
		"smoke_grenade":
			for o in area.call(1):
				if not u.is_enemy_of(o):
					o.status["smoked"] = Combat.phase_index(s) + 4
	s.emit(ev)


static func _use_charge(u: Unit, id: String) -> void:
	var ps: Array = u.status.get("pockets", [])
	for i in ps.size():
		if ps[i] != null and ps[i].id == id:
			ps[i].charges -= 1
			if ps[i].charges <= 0:
				ps[i] = null
			return
