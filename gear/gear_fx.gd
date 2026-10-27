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
##   "contained": int      phase index until which the unit gains no Infection (Containment emitter)
##   "restrained": int     phase index a Containment foam restraint ends on
##   "suppressed_by": int  unit id whose Suppress is on it (Suppress set free shot)
##   "gear_uses": {ability id: uses this fight}
##   "gear_refund_turn": int  turn a Close-set kill last refunded a move
##   "gear_moved_turn": int   turn the unit last moved (Bipod)
##   "gear_set_mobility": int mobility currently added by the Close set bonus
##   "warrant": bool       the Mark on this enemy came from a Warrant capstone (never expires, +20 aim for all)
##   "warrant_turn": int   turn a Warrant kill last refunded an action
##   "aegis_turn": int     turn Aegis last held a soldier at 1 HP (view beat only)
##   "ignore_armour": bool set only while Wildfire fire damage is being dealt
##
## Gadgets and pocket consumables are abilities: ids "gear:<item>" and "item:<consumable>".
## Combat delegates them here (owns / validate_ability / apply_ability / available_abilities).

const BURN_DAMAGE := 2
const SMOKE_DEFENSE := 20
const SMOKE_RADIUS := 1
const SMOKE_TURNS := 2
const CLOSE := 3.0

## Items whose effect needs a system the game doesn't have yet. They're kept out of reward and
## depot draws until they work. Empty: every item works (tests/test_item_audit.gd checks it).
const PENDING: Array[String] = []
## Containment foam: phases a Lapsed or Turned soldier stays restrained (2 turns), and its reach.
const FOAM_PHASES := 4
const FOAM_RANGE := 4.0
## Fire tiles gear makes: Thermite line length per Mk, and how long each kind of fire lasts.
const THERMITE_LENGTH := [3, 5]
const THERMITE_TURNS := 2
const BURN_SET_FIRE_TURNS := 1
const SCORCHED_PURGE := 10
## Capstones (6 of a tag, GearData.CAPSTONE_THRESHOLD). Warrant: aim bonus on a Marked enemy for the whole
## squad, and the Mark never runs out. Wildfire: Burning spreads to neighbours each team phase.
const WARRANT_AIM := 20
const WARRANT_FOREVER := 1000000
const WILDFIRE_TURNS := 1
const RESONANCE_AIM := 2
const RESONANCE_CAP := 10
const CROSSHAIR_AIM := 20   # reaction: overwatch shots at a Marked enemy
## Kindled Spores: Infection each ignition costs the soldier.
const KINDLED_INFECTION := 2

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
	"antiviral_dose": {"targeting": "unit", "cost": 1},
	"breather_mask": {"targeting": "none", "cost": 1},
	"stim": {"targeting": "none", "cost": 0},
	"frag_grenade": {"targeting": "cell", "cost": 1, "range": 6.0},
	"demo_charge": {"targeting": "cell", "cost": 1, "range": 1.5},
	"flashbang": {"targeting": "cell", "cost": 1, "range": 6.0},
	"smoke_grenade": {"targeting": "cell", "cost": 1, "range": 6.0},
	"recon_drone": {"targeting": "cell", "cost": 1, "range": Vision.DRONE_RANGE},
	"containment_foam": {"targeting": "unit", "cost": 1},
}
## Rangefinder: extra overwatch range per Mk.
const RANGEFINDER_RANGE := 40   # Long line: as far as the soldier can see


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


## Capstone (6 of a tag) on, for a soldier with gear.
static func has_capstone(u: Unit, tag: String) -> bool:
	return u.status.has("gear") and GearTags.unit_has_capstone(u, tag)


static func is_burning(_s: GameState, u: Unit) -> bool:
	return int(u.status.get("burning", 0)) > 0


## Standing in a smoke grenade's cloud: +SMOKE_DEFENSE, and dormant Infected can't spot you.
static func in_smoke(s: GameState, u: Unit) -> bool:
	return Hazards.at(s, u.pos).get("kind", "") == "smoke"


## Mark set: the second hit each turn on one Marked enemy deals double.
static func _mark_set_double(s: GameState, u: Unit, t: Unit, dmg: int) -> void:
	var rec: Dictionary = u.status.get("mark_hits", {})
	if int(rec.get("turn", -1)) == s.turn and int(rec.get("target", -1)) == t.id:
		if not rec.get("done", false) and t.is_alive():
			rec["done"] = true
			s.emit({"type": "gear", "unit": u.id, "item": "mark_double", "target": t.id, "damage": dmg})
			Rules.deal_damage(s, t, dmg, u)
	else:
		u.status["mark_hits"] = {"turn": s.turn, "target": t.id, "done": false}


static func is_marked(s: GameState, u: Unit) -> bool:
	return Combat.has_status(s, u, "tagged")


## Smart-link: `u` may shoot Marked enemy `t` without line of sight while any ally sees it.
static func smart_link_shot(s: GameState, u: Unit, t: Unit) -> bool:
	if not has(u, "smart_link") or not u.is_enemy_of(t) or not t.is_alive() or t.status.get("hidden", false):
		return false
	return is_marked(s, t) and Vision.sees_unit(s, u.team, t)


## Extra tiles of overwatch range (Rangefinder), added to the watcher's sight radius.
static func overwatch_range_bonus(u: Unit) -> int:
	return RANGEFINDER_RANGE if has(u, "rangefinder") else 0


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
		GearTricks.odds(s, a, t, reaction, cover, breakdown)
		if reaction:
			if has(a, "rangefinder") and cover == Types.Cover.FULL:
				breakdown.append(["Long line", Combat.COVER_FULL - (0 if mk(a, "rangefinder") >= 2 else Combat.COVER_HALF)])
			elif has(a, "rangefinder") and cover == Types.Cover.HALF and mk(a, "rangefinder") >= 2:
				breakdown.append(["Long line", Combat.COVER_HALF])
			if has(a, "killbox") and is_marked(s, t):
				breakdown.append(["Killbox", 100])
		if Combat.has_status(s, t, "suppressed"):
			if has(a, "breach_and_clear") and _dist(from, t.pos) <= CLOSE and cover != Types.Cover.NONE:
				breakdown.append(["Breach and clear", Combat.COVER_FULL if cover == Types.Cover.FULL else Combat.COVER_HALF])
		if mk(a, "smart_link") >= 2 and not Combat.can_see(s, from, t.pos) and smart_link_shot(s, a, t):
			breakdown.append(["Smart-link", 10])
		if mk(a, "suppressor") >= 2 and not t.status.get("alerted", true):
			breakdown.append(["Suppressor", 10])
		if mk(a, "speed_loader") >= 2 and a.status.get("gear_fresh_turn", -1) == s.turn:
			breakdown.append(["Speed loader", Ammo.FRESH_AIM])
	if a.team == Types.Team.PLAYER and t.status.get("warrant", false) and is_marked(s, t):
		breakdown.append(["Warrant", WARRANT_AIM])
	if reaction and a.team == Types.Team.PLAYER and is_marked(s, t):
		breakdown.append(["Crosshair", CROSSHAIR_AIM])
	var resonance := resonance_aim(a)
	if resonance > 0:
		breakdown.append(["Resonance", resonance])
	if a.team == Types.Team.PLAYER and a.status.get("doctrines", []).has("buddy_system"):
		for o in s.living(Types.Team.PLAYER):
			if o != a and _cheb(o.pos, from) == 1 and not o.is_enemy_of(a):
				breakdown.append(["Buddy system", 10])
				break
	if Combat.has_status(s, a, "suppressed") and a.status.get("suppress_extra", 0) > 0:
		breakdown.append(["Suppressed (gear)", -int(a.status.suppress_extra)])
	if t.status.has("gear") and has(t, "riot_shield") and cover == Types.Cover.NONE:
		breakdown.append(["Riot shield", -Combat.COVER_HALF])
	elif cover == Types.Cover.NONE and t.team == Types.Team.PLAYER:
		for g in s.living(Types.Team.PLAYER):
			if g != t and _cheb(g.pos, t.pos) == 1 and has(g, "riot_shield"):
				breakdown.append(["Shield cover", -Combat.COVER_HALF])
				break
	if in_smoke(s, t):
		breakdown.append(["Smoke", -SMOKE_DEFENSE])
	if t.status.has("gear"):
		if has(t, "cauterizer") and Hazards.at(s, t.pos).get("kind", "") == "fire":
			breakdown.append(["Cauterizer", -10])
	if t.team == Types.Team.PLAYER:
		for g in s.living(Types.Team.PLAYER):
			if g != t and g.overwatch and _cheb(g.pos, t.pos) == 1 and has(g, "overlook"):
				breakdown.append(["Overlook", -10])
				break
	if t.team == Types.Team.PLAYER:
		for g in s.living(Types.Team.PLAYER):
			if g != t and _cheb(g.pos, t.pos) == 1 and has_set(g, "Guard"):
				breakdown.append(["Guarded", -5])
				break


# --- Shots (Combat.fire) ---------------------------------------------------------------

## Damage of a landed shot after gear.
static func shot_damage(s: GameState, u: Unit, t: Unit, dmg: int, reaction: bool) -> int:
	if dmg > 0 and u.team == Types.Team.PLAYER and _dist(u.pos, t.pos) <= CLOSE and Combat.has_status(s, t, "suppressed"):
		dmg += 1
		s.emit({"type": "gear", "unit": u.id, "item": "pinned_close", "target": t.id})
	if not u.status.has("gear") or dmg <= 0:
		return dmg
	var close := _dist(u.pos, t.pos) <= CLOSE
	if has(u, "spore_rounds"):
		dmg += awake_mutations(u) + (1 if mk(u, "spore_rounds") >= 2 else 0)
	return dmg


## Everything a shot sets off once it has resolved: on-hit ammo, kills, self-Infection.
static func after_shot(s: GameState, u: Unit, t: Unit, hit: bool, reaction: bool, dmg: int = 0) -> void:
	if not u.status.has("gear"):
		return
	var close := _dist(u.pos, t.pos) <= CLOSE
	GearLinks.after_shot(s, u, t, hit, reaction, dmg)
	GearTricks.after_shot(s, u, t, hit, reaction, dmg)
	if hit and dmg > 0 and has_set(u, "Mark") and is_marked(s, t):
		_mark_set_double(s, u, t, dmg)
	if has(u, "spore_rounds"):
		Infection.add(s, u, 2)
	if hit and Kit.awake(u, "kindled_spores"):
		_kindle(s, u, t)
	if hit and t.is_alive():
		if has(u, "tracer_rounds"):
			_mark(s, t, 1 if mk(u, "tracer_rounds") < 2 else 3, u)
		if has(u, "suppressor") and not t.status.get("alerted", true):
			_mark(s, t, 2, u)
		if has(u, "shock_rounds"):
			_suppress(s, u, t, 15 if mk(u, "shock_rounds") >= 2 else 0)
		if has(u, "incendiary_rounds"):
			ignite(s, u, t, mk(u, "incendiary_rounds"))
		if has(u, "igniter_barrel") and u.status.get("igniter_turn", -1) != s.turn:
			u.status["igniter_turn"] = s.turn
			set_fire(s, u, [t.pos], mk(u, "igniter_barrel"))
		if close and has(u, "firestarter"):
			ignite(s, u, t, 1)
	if hit and has(u, "leech_rounds") and Infection.tier(u.infection) >= Infection.Tier.EXPOSED:
		if u.hp < u.max_hp:
			u.hp += 1
			s.emit({"type": "gear", "unit": u.id, "item": "leech_rounds", "heal": 1, "hp": u.hp})
		Infection.add(s, u, 2 if mk(u, "leech_rounds") < 2 else 1)
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


## Kindled Spores (Burn mutation): the hit sets `t` Burning, spore cells next to it burn off as fire.
static func _kindle(s: GameState, u: Unit, t: Unit) -> void:
	var spores: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := t.pos + Vector2i(dx, dy)
			if s.grid.in_bounds(c) and Hazards.at(s, c).get("kind", "") == "spore":
				spores.append(c)
	s.emit({"type": "mutation", "unit": u.id, "mutation": "kindled_spores", "target": t.id})
	if t.is_alive():
		ignite(s, u, t, 1)
	if not spores.is_empty():
		set_fire(s, u, spores, 1)
	Infection.add(s, u, KINDLED_INFECTION)


## Rounds Extended mag adds to the magazine.
static func mag_bonus(_u: Unit) -> int:
	return 0


## Speed loader: the first Reload each turn costs no action.
static func free_reload(u: Unit) -> bool:
	return has(u, "speed_loader")


static func after_reload(s: GameState, u: Unit, _had: int) -> void:
	GearLinks.on_reload(s, u)
	GearTricks.on_reload(s, u)
	if mk(u, "speed_loader") >= 2:
		u.status["gear_fresh_turn"] = s.turn


## Rounds a kill gives back (Scavenger rounds).
static func kill_rounds(u: Unit) -> int:
	return Ammo.SCAVENGER[clampi(mk(u, "scavenger_rounds"), 1, 2) - 1] if has(u, "scavenger_rounds") else 0


static func on_kill(s: GameState, u: Unit, t: Unit, reaction: bool) -> void:
	Ammo.on_kill(s, u)
	GearLinks.on_kill(s, u, t)
	GearTricks.on_kill(s, u, t)
	var was_marked := t.status.has("tagged") and int(t.status.tagged) > Combat.phase_index(s)
	GearLinks.on_kill_signature(s, u, t, was_marked)
	if reaction and has_set(u, "Overwatch"):
		u.overwatch = true
		u.status["ow_until"] = Combat.phase_index(s) + 2
		s.emit({"type": "overwatch", "unit": u.id})
		_heal_one(s, u, "overwatch_set")
	if has_set(u, "Close") and _dist(u.pos, t.pos) <= CLOSE and u.status.get("gear_refund_turn", -1) != s.turn \
			and s.phase == Types.Phase.TEAM and not reaction:
		u.status["gear_refund_turn"] = s.turn
		u.actions_left += 1
		s.emit({"type": "gear", "unit": u.id, "item": "close_set", "actions": u.actions_left})
		_heal_one(s, u, "close_set_heal")
	if was_marked and t.status.get("warrant", false) and has_capstone(u, "Mark") and s.phase == Types.Phase.TEAM \
			and u.status.get("warrant_turn", -1) != s.turn:
		u.status["warrant_turn"] = s.turn
		u.actions_left += 1
		s.emit({"type": "gear", "unit": u.id, "item": "warrant_served", "target": t.id, "actions": u.actions_left})
	if was_marked and has_set(u, "Mark"):
		var best: Unit = null
		for o in s.living():
			if u.is_enemy_of(o) and Combat.can_see(s, u.pos, o.pos) and (best == null or _dist(t.pos, o.pos) < _dist(t.pos, best.pos)):
				best = o
		if best:
			best.status["tagged"] = t.status.tagged
			if t.status.get("warrant", false):
				best.status["warrant"] = true
			s.emit({"type": "gear", "unit": u.id, "item": "mark_set", "target": best.id, "from": t.id})
	if is_burning(s, t):
		_burn_set_spread(s, t)
	if has(u, "purge_canister") and u.infection > 0:
		Infection.add(s, u, -(5 if mk(u, "purge_canister") < 2 else 10))
	if is_burning(s, t) and has(u, "phosphor_rounds"):
		var radius := 1 if mk(u, "phosphor_rounds") < 2 else 2
		for o in s.living():
			if u.is_enemy_of(o) and _cheb(o.pos, t.pos) <= radius:
				ignite(s, u, o, 1)


static func _heal_one(s: GameState, u: Unit, item: String) -> void:
	if u.hp < u.max_hp:
		u.hp += 1
		s.emit({"type": "gear", "unit": u.id, "item": item, "heal": 1, "hp": u.hp})


static func _mark(s: GameState, t: Unit, phases: int, u: Unit = null) -> void:
	var was := is_marked(s, t)
	var until := Combat.phase_index(s) + phases
	if int(t.status.get("tagged", 0)) < until:
		t.status["tagged"] = until
	on_marked(s, u, t, was)


## Warrant (Mark capstone): a Mark `u` puts on `t` never runs out, and the whole squad aims better
## against it. Call after any Mark lands (the Marksman's Tag, tracer rounds, flares, Flies...).
static func on_marked(s: GameState, u: Unit, t: Unit, was := false) -> void:
	GearLinks.on_marked(s, u, t, was)
	if u == null or t == null or not t.is_alive() or not has_capstone(u, "Mark"):
		return
	t.status["tagged"] = WARRANT_FOREVER
	if not t.status.get("warrant", false):
		t.status["warrant"] = true
		s.emit({"type": "gear", "unit": u.id, "item": "warrant", "target": t.id})


static func _suppress(s: GameState, u: Unit, t: Unit, extra: int = 0) -> void:
	t.status["suppressed"] = Combat.phase_index(s) + 2
	t.status["suppressed_by"] = u.id
	t.status.erase("suppress_shot_used")
	t.overwatch = false
	if extra > 0:
		t.status["suppress_extra"] = extra
	else:
		t.status.erase("suppress_extra")
	if has(u, "pinpoint"):
		_mark(s, t, 3, u)
	GearTricks.recoil_lock(s, u, t)
	s.emit({"type": "gear", "unit": u.id, "item": "suppress", "target": t.id})
	GearLinks.on_suppressed(s, u, t)


## Sets `t` Burning for `turns` ticks (the Burn set adds one).
static func ignite(s: GameState, u: Unit, t: Unit, turns: int) -> void:
	if has_set(u, "Burn"):
		turns += 1
	if int(t.status.get("burning", 0)) < turns:
		t.status["burning"] = turns
		t.status["burn_source"] = u.id
		s.emit({"type": "burning", "unit": t.id, "turns": turns})
		GearLinks.on_ignite(s, u, t)


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


## Fire damage to `u`; Wildfire (Burn capstone) fire ignores armour, plating and the Armoured affix.
static func fire_damage(s: GameState, u: Unit, dmg: int, ignores_armour: bool) -> void:
	if ignores_armour:
		u.status["ignore_armour"] = true
	Rules.deal_damage(s, u, dmg)
	u.status.erase("ignore_armour")


## Wildfire (Burn capstone): every enemy next to a Burning enemy of a capstone soldier catches fire too.
## Spread is collected over the whole phase so it moves one ring a turn, not through the whole pack at once.
static func _wildfire_spread(s: GameState, burning: Array) -> void:
	var lit: Array[Unit] = []
	for pair in burning:
		var from: Unit = pair[0]
		var src: Unit = pair[1]
		if not from.is_alive() or not src.is_alive():
			continue
		for o in s.living():
			if o != from and src.is_enemy_of(o) and _cheb(o.pos, from.pos) == 1 and not is_burning(s, o) and not lit.has(o):
				lit.append(o)
				ignite(s, src, o, WILDFIRE_TURNS)
				s.emit({"type": "gear", "unit": from.id, "item": "wildfire", "target": o.id})


## Hazards hook: damage a hazard tile deals to `u`; a Wildfire soldier's fire ignores armour.
static func hazard_damage(s: GameState, u: Unit, h: Dictionary, dmg: int) -> void:
	var src := s.get_unit(int(h.get("source", -1))) if h.kind == "fire" else null
	fire_damage(s, u, dmg, src != null and has_capstone(src, "Burn") and src.is_enemy_of(u))


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
		if has(u, "flame_coat") or has(u, "cauterizer"):
			return Vector2i(0, infection)
		if src != null and has(src, "spotter_flare") and is_marked(s, u):
			damage *= 2
	if h.kind == "spore" and has(u, "filter_mask"):
		infection = 0
	if h.kind == "spore" and infection > 0 and u.status.get("doctrines", []).has("spore_filters"):
		infection = infection * 3 / 4
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
	t.status["suppressed_by"] = u.id
	t.status.erase("suppress_shot_used")
	if not u.status.has("gear"):
		return
	GearTricks.recoil_lock(s, u, t)
	if has(u, "pinpoint"):
		_mark(s, t, 3, u)
	GearLinks.on_suppressed(s, u, t)
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

static func damage_taken(s: GameState, target: Unit, amount: int, source: Unit) -> int:
	amount = GearTricks.damage_taken(s, target, amount, source)
	if amount > 0 and source != null and source.is_alive() and source.is_enemy_of(target) and has(target, "ember_plating"):
		ignite(s, target, source, mk(target, "ember_plating"))
	if amount > 0 and source != null and source.is_enemy_of(target) and target.status.has("gear"):
		GearLinks.on_hurt(s, target, source)
		amount = maxi(1, amount - survival_cut(s, target, source))
	var armor := int(target.status.get("armor", 0))
	return maxi(1, amount - armor) if armor > 0 and amount > 0 else amount


## Resonance: a small aim bonus for committing to one tag, +2 per piece of the soldier's biggest
## tag beyond the first, up to +10. Power comes from the links; this is only a nudge.
static func resonance_aim(u: Unit) -> int:
	if not u.status.has("gear_tags"):
		return 0
	var top := 0
	var c := GearTags.unit_counts(u)
	for k in c:
		top = maxi(top, int(c[k]))
	return clampi((top - 1) * RESONANCE_AIM, 0, RESONANCE_CAP)


## Survival half of a set bonus: damage `target` shrugs off from `source` while `source` carries the
## status of a tag `target` has the set for (Burning, Marked, Suppressed), or Infected for Strain.
static func survival_cut(s: GameState, target: Unit, source: Unit) -> int:
	var cut := 0
	if has_set(target, "Burn") and is_burning(s, source):
		cut += 1
	if has_set(target, "Mark") and is_marked(s, source):
		cut += 1
	if has_set(target, "Suppress") and Combat.has_status(s, source, "suppressed"):
		cut += 1
	if has_set(target, "Strain") and Infection.tier(target.infection) >= Infection.Tier.EXPOSED and EnemyRoster.infects(source):
		cut += 1
	return cut


## Infection a soldier gains from a bite or hit after gear.
static func bite_infection(s: GameState, target: Unit, gain: int) -> int:
	for g in s.living(Types.Team.PLAYER):
		if g != target and has(g, "quarantine_field") and Combat.is_hunkered(s, g) and _cheb(g.pos, target.pos) == 1:
			return 0
	if has(target, "hazard_liner"):
		return gain / 2 if mk(target, "hazard_liner") < 2 else gain / 3
	return gain


# --- Turn flow (Rules) -----------------------------------------------------------------

static func on_team_phase_start(s: GameState) -> void:
	GearTricks.on_team_phase_start(s)
	var wildfire: Array = []   # [burning unit, the Wildfire soldier whose fire it is]
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
			if in_smoke(s, u):
				var cells: Array[Vector2i] = []
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						var c := u.pos + Vector2i(dx, dy)
						if s.grid.in_bounds(c):
							cells.append(c)
				s.emit({"type": "gear", "unit": u.id, "item": "flare_up"})
				set_fire(s, u, cells, 1)
			var wild := src != null and src.is_alive() and has_capstone(src, "Burn") and src.is_enemy_of(u)
			if wild:
				wildfire.append([u, src])
			fire_damage(s, u, dmg, wild)
			if not u.is_alive():
				_burn_set_spread(s, u)
	_wildfire_spread(s, wildfire)
	for u in s.living(Types.Team.PLAYER):
		var fire := 0
		if has(u, "flame_coat") and Hazards.at(s, u.pos).get("kind", "") == "fire":
			fire = mk(u, "flame_coat")
		var had := int(u.status.get("gear_fire_mobility", 0))
		if fire != had:
			u.mobility += fire - had
			u.status["gear_fire_mobility"] = fire


static func on_move(s: GameState, u: Unit, steps := 0) -> void:
	u.status["gear_moved_turn"] = s.turn
	u.status["gear_move_len"] = steps


## Containment foam: a restrained unit sits out its turn (EnemyAI.take_turn checks this).
static func is_restrained(s: GameState, u: Unit) -> bool:
	return Combat.has_status(s, u, "restrained")


## End of the enemy phase, before hazards age (Rules.run_enemy_phase). Crossfire: a soldier
## still on overwatch fires at one Suppressed enemy in sight that stayed put this turn.
static func on_enemy_phase_end(s: GameState) -> void:
	for w in s.living(Types.Team.PLAYER):
		if not has(w, "crossfire") or not Combat.is_overwatching(s, w) or s.phase == Types.Phase.ENDED:
			continue
		for e in s.living(Types.Team.ENEMY):
			if Combat.has_status(s, e, "suppressed") and int(e.status.get("gear_moved_turn", -1)) != s.turn \
					and Vision.overwatch_sees(s, w, e, e.pos):
				s.emit({"type": "gear", "unit": w.id, "item": "crossfire", "target": e.id})
				if not Kit.keep_overwatch(s, w, e):
					w.overwatch = false
					w.status.erase("ow_until")
				Combat.fire(s, w, e, true)
				break


## Suppress set: an enemy you Suppressed that moves in your sight draws one free shot from you,
## overwatch or not. Pure (Combat.reactions_to_move asks it).
static func suppress_shot_ready(s: GameState, w: Unit, mover: Unit, cell: Vector2i) -> bool:
	return w.team == Types.Team.PLAYER and w.is_alive() and has_set(w, "Suppress") and w.is_enemy_of(mover) \
		and Combat.has_status(s, mover, "suppressed") and int(mover.status.get("suppressed_by", -1)) == w.id \
		and not mover.status.get("suppress_shot_used", false) and Combat.can_see(s, w.pos, cell)


static func take_suppress_shot(s: GameState, w: Unit, mover: Unit) -> void:
	mover.status["suppress_shot_used"] = true
	s.emit({"type": "gear", "unit": w.id, "item": "suppress_set", "target": mover.id})
	Combat.fire(s, w, mover, true)


## Guard set: once per enemy phase a Guard-set soldier takes a hit meant for an adjacent ally.
## Returns who the damage lands on (Rules.deal_damage).
static func guard_redirect(s: GameState, target: Unit, source: Unit) -> Unit:
	if s.phase != Types.Phase.ENEMY or source == null or target.team != Types.Team.PLAYER or not source.is_enemy_of(target) \
			or target.status.has("deployable"):
		return target
	for g in s.living(Types.Team.PLAYER):
		if g != target and not g.ai_controlled and _cheb(g.pos, target.pos) == 1 and has_set(g, "Guard") \
				and int(g.status.get("guard_set_phase", -1)) != Combat.phase_index(s):
			g.status["guard_set_phase"] = Combat.phase_index(s)
			s.emit({"type": "gear", "unit": g.id, "item": "guard_set", "target": target.id})
			return g
	return target


## Aegis (Guard capstone): a soldier above 1 HP can't be killed by a single hit; they are left on 1.
static func aegis_hold(s: GameState, target: Unit, amount: int) -> int:
	if amount < target.hp or target.hp <= 1 or not has_capstone(target, "Guard"):
		return amount
	s.emit({"type": "gear", "unit": target.id, "item": "aegis_hold"})
	return target.hp - 1


## Aegis: the damage a Guard-capstone soldier took meant for an ally goes back to whoever dealt it.
static func aegis_return(s: GameState, guard: Unit, source: Unit, amount: int) -> void:
	if amount <= 0 or source == null or not source.is_alive() or not source.is_enemy_of(guard) or not has_capstone(guard, "Guard"):
		return
	s.emit({"type": "gear", "unit": guard.id, "item": "aegis_return", "target": source.id, "damage": amount})
	Rules.deal_damage(s, source, amount, guard)


## Infection `u` actually gains (Infection.add, after Kit): Containment emitter, and the Purge set
## on a turn you purged someone, block it all.
static func infection_gain(s: GameState, u: Unit, amount: int) -> int:
	if amount <= 0 or u.team != Types.Team.PLAYER or s.turn == 0:
		return amount
	if Combat.has_status(s, u, "contained"):
		return 0
	if has_set(u, "Purge") and int(u.status.get("purged_turn", -1)) == s.turn:
		return 0
	return ceili(amount * ward_factor(s, u))


## Share of Infection `u` still takes with wards about: a Guard-set soldier covers themselves and
## adjacent allies, a Purge-set soldier themselves and allies within 2 tiles. Each ward cuts a
## quarter and they multiply.
static func ward_factor(s: GameState, u: Unit) -> float:
	var guard := false
	var purge := false
	for g in s.living(Types.Team.PLAYER):
		var d := _cheb(g.pos, u.pos)
		if has_set(g, "Guard") and d <= 1:
			guard = true
		if has_set(g, "Purge") and d <= 2:
			purge = true
	return (0.75 if guard else 1.0) * (0.75 if purge else 1.0)


## `u` took `amount` Infection off ally `t` (Purge, Decon, Siphon, Stim, Med-injector,
## Suppressant shot). Purge set heals them 1 HP; Bloodletting takes the Infection onto `u` once
## a turn for +1 action. `self_took`: the ability already moved it onto `u` (Siphon).
static func on_purge(s: GameState, u: Unit, t: Unit, amount: int, self_took := false) -> void:
	if t == null or t == u or amount <= 0 or not u.status.has("gear"):
		return
	if has(u, "bloodletting") and not self_took and int(u.status.get("bloodletting_turn", -1)) != s.turn \
			and s.phase == Types.Phase.TEAM:
		u.status["bloodletting_turn"] = s.turn
		u.actions_left += 1
		s.emit({"type": "gear", "unit": u.id, "item": "bloodletting", "actions": u.actions_left})
		Infection.add(s, u, amount)
	u.status["purged_turn"] = s.turn
	if has(t, "filter_mask") and mk(t, "filter_mask") >= 2 and t.hp < t.max_hp:
		t.hp = mini(t.max_hp, t.hp + FILTER_HEAL)
		s.emit({"type": "gear", "unit": t.id, "item": "filter_mask", "heal": FILTER_HEAL, "hp": t.hp})
	GearLinks.on_purge(s, u, t)
	if has_set(u, "Purge") and t.hp < t.max_hp:
		t.hp += 1
		s.emit({"type": "gear", "unit": t.id, "item": "purge_set", "heal": 1, "hp": t.hp})


## Action cost of a built ability after gear (Combat._spend). Hold position: Suppress costs 1.
static func ability_cost(u: Unit, id: String, cost: int) -> int:
	if id == "suppress" and has(u, "hold_position"):
		return 1
	return cost


## Symbiotic suit: a mutation's Infection cost is paid in HP instead (1 HP per 5, Mk II per 10),
## as long as that leaves the soldier standing. Returns the Infection still to pay.
static func mutation_cost(s: GameState, u: Unit, cost: int) -> int:
	if cost <= 0 or not has(u, "symbiotic_suit"):
		return cost
	var hp := ceili(float(cost) / (5.0 if mk(u, "symbiotic_suit") < 2 else 10.0))
	if u.hp <= hp:
		return cost
	u.hp -= hp
	s.emit({"type": "gear", "unit": u.id, "item": "symbiotic_suit", "damage": hp, "hp": u.hp})
	return 0


# --- Gadgets and pocket items as abilities ---------------------------------------------

## Thrown pocket items: a Servo arm graft throws them further.
const WARD_POINTS := 3
const FILTER_HEAL := 3
const SPORE_DIV := 8
const SPORE_RADIUS := 2
const THROWN := ["frag_grenade", "flashbang", "smoke_grenade"]


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
		var reach: float = c.get("range", 1.5) + (Grafts.throw_bonus(u) if key in THROWN else 0.0)
		return {"targeting": c.targeting, "cost": c.cost, "uses": 0, "cooldown": 0, "range": reach,
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
	if id == "item:containment_foam":
		if not (Infection.is_lapsed(t) or t.status.get("turned", false)):
			return "Only a Lapsed or Turned soldier"
		if _dist(u.pos, t.pos) > FOAM_RANGE:
			return "Too far"
		if not Combat.can_see(s, u.pos, t.pos):
			return "No line of sight"
		return ""
	if u.is_enemy_of(t):
		return "Not an ally"
	if _cheb(u.pos, t.pos) > 1:
		return "Too far"
	match id:
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
		"item:demo_charge":
			if c == u.pos or Destruction._cheb(u.pos, c) > Destruction.DEMO_RANGE:
				return "Place it on a tile or wall next to you"
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
	if d.cost >= 0 and Grafts.gadget_free(s, u):
		s.emit({"type": "perk", "unit": u.id, "perk": "servo_arm"})
	else:
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
			ev["units"] = hit.map(func(o): return o.id)
			s.emit(ev)   # the throw plays first, then what it did
			for o in hit:
				_mark(s, o, 3, u)
				s.emit({"type": "gear", "unit": u.id, "item": "mark", "target": o.id})
			_gives_away(s, u, hit)
			return
		"concussion_launcher":
			var r := 2 if mk(u, key) >= 2 else 1
			var hit: Array = (area.call(r) as Array).filter(func(o): return u.is_enemy_of(o))
			ev["units"] = hit.map(func(o): return o.id)
			ev["radius"] = r
			s.emit(ev)
			for o in hit:
				_suppress(s, u, o)
			_gives_away(s, u, hit)
			return
		"flashbang":
			# Stuns: each enemy caught loses its next turn. Bosses and nests shrug it off and are
			# only Suppressed.
			var hit: Array = (area.call(1) as Array).filter(func(o): return u.is_enemy_of(o))
			ev["units"] = hit.map(func(o): return o.id)
			s.emit(ev)
			for o in hit:
				if EnemyRoster.is_boss(o) or UnitData.ENEMIES.get(o.kind, {}).get("static", false):
					_suppress(s, u, o)
					continue
				o.status["k_skip_turn"] = true
				o.overwatch = false
				s.emit({"type": "stunned", "unit": o.id, "by": u.id})
			_gives_away(s, u, hit)
			return
		"thermite_charge":
			var line := fire_line(u.pos, cell, THERMITE_LENGTH[clampi(mk(u, key), 1, 2) - 1])
			s.emit(ev)
			set_fire(s, u, line, THERMITE_TURNS)
			for o in s.living():
				if u.is_enemy_of(o) and line.has(o.pos):
					ignite(s, u, o, 1)
			return
		"med_injector", "suppressant_shot", "antiviral_dose":
			var amount := 35 if key == "antiviral_dose" else 15
			if key == "med_injector" and mk(u, key) >= 2:
				amount = 25
			s.emit(ev)
			var before := t.infection
			Infection.add(s, t, -amount)
			on_purge(s, u, t, before - t.infection)
			if key == "suppressant_shot":
				t.status["k_ward"] = WARD_POINTS
				ev["ward"] = WARD_POINTS
			elif key == "antiviral_dose":
				var burst := (before - t.infection) / SPORE_DIV
				for o in s.living():
					if u.is_enemy_of(o) and _cheb(o.pos, t.pos) <= SPORE_RADIUS and burst > 0:
						Rules.deal_damage(s, o, burst, u)
			return
		"medkit":
			var healed := mini(4, t.max_hp - t.hp)
			t.hp += healed
			ev["heal"] = healed
			ev["hp"] = t.hp
			if healed == 0:
				t.status["k_medshield"] = true
				ev["shield"] = true
			for st in ["burning", "suppressed", "k_skip_turn", "rooted", "wound"]:
				t.status.erase(st)
		"adrenal_pump":
			s.emit(ev)
			Infection.add(s, u, 15)
			return
		"stim":
			u.actions_left += 1
			s.emit(ev)
			Infection.add(s, u, 5)
			return
		"breather_mask":
			var sealed: Array = []
			for o in s.living(Types.Team.PLAYER):
				if _cheb(o.pos, u.pos) <= 2:
					o.status["contained"] = Combat.phase_index(s) + 2
					sealed.append(o.id)
			ev["units"] = sealed
			ev["until"] = Combat.phase_index(s) + 2
		"containment_emitter":
			var until := Combat.phase_index(s) + 2
			var held: Array = []
			for o in s.living(Types.Team.PLAYER):
				if _cheb(o.pos, u.pos) <= 2:
					o.status["contained"] = until
					held.append(o.id)
			ev["units"] = held
			ev["until"] = until
		"containment_foam":
			t.status["restrained"] = Combat.phase_index(s) + FOAM_PHASES
			t.overwatch = false
			t.actions_left = 0
		"deployable_cover":
			s.grid.set_tile(cell, Types.Tile.WALL)
			s.emit(ev)
			Vision.refresh(s)
			return
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
		"frag_grenade", "demo_charge":
			# Destruction hurts the units, breaks cover, walls and roofs, and sets off barrels.
			var p: Dictionary = Destruction.FRAG if key == "frag_grenade" else Destruction.DEMO
			var hit := Destruction.units_in(s, cell, p, u)
			ev["units"] = hit.map(func(o): return o.id)
			ev["damage"] = p.damage
			s.emit(ev)
			Destruction.explode(s, cell, p, u, "frag" if key == "frag_grenade" else "demo", u)
			return
		"recon_drone":
			s.emit(ev)
			Vision.add_reveal(s, cell, Vision.DRONE_RADIUS)
			for o in s.living():
				if u.is_enemy_of(o) and o.pos.distance_to(cell) <= Vision.DRONE_RADIUS:
					_mark(s, o, 2, u)
			return
		"smoke_grenade":
			# A smoke cloud on the tiles: whoever stands in it is harder to hit and can't be
			# spotted, for as long as it hangs (Hazards "smoke").
			s.emit(ev)
			var cells: Array[Vector2i] = []
			for y in range(cell.y - SMOKE_RADIUS, cell.y + SMOKE_RADIUS + 1):
				for x in range(cell.x - SMOKE_RADIUS, cell.x + SMOKE_RADIUS + 1):
					cells.append(Vector2i(x, y))
			Hazards.add(s, cells, "smoke", SMOKE_TURNS, u.id)
			return
	s.emit(ev)


## An attack on dormant enemies (flashbang, concussion, flare) gives a Concealed squad away.
static func _gives_away(s: GameState, u: Unit, hit: Array) -> void:
	if not hit.is_empty():
		Concealment.lose(s, "fired", hit[0], u)


static func _use_charge(u: Unit, id: String) -> void:
	var ps: Array = u.status.get("pockets", [])
	for i in ps.size():
		if ps[i] != null and ps[i].id == id:
			ps[i].charges -= 1
			if ps[i].charges <= 0:
				ps[i] = null
			return
