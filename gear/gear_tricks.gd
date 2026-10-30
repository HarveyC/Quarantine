class_name GearTricks
extends RefCounted
## Gear that used to be a flat stat and now does something: Painter, Slipstream, Trauma plate, Spall
## liner, Planted rig, Drum swap, Graft weave, Tight group, Fixed blade, Knock rounds, Wick, Pin shot,
## Acid blister, Still life, Dug in, Wounding rounds, Long line and Dead reckoning.
## Rules only; GearFx calls these from its hooks and the beats live in EventPlayer.GEAR_PROCS.

const BLADE_DAMAGE := [3, 5]
const KNOCK_DAMAGE := [2, 3]
const WICK_LENGTH := [2, 4]
const WEAVE_HEAL := [2, 3]
const SLIP_STEPS := [4, 3]
const NEAR := 3.0
const TAP_PENALTY := 20

static var _busy := false   # a trick never sets off a trick of its own kind


static func _has(u: Unit, id: String) -> bool:
	return GearFx.has(u, id)


static func _m2(u: Unit, id: String) -> bool:
	return GearFx.mk(u, id) >= 2


static func _gear(s: GameState, u: Unit, id: String, target: Unit = null, extra := {}) -> void:
	var ev := {"type": "gear", "unit": u.id, "item": id}
	if target != null:
		ev["target"] = target.id
	ev.merge(extra, true)
	s.emit(ev)


# --- Hit chance (GearFx.odds_terms) ---------------------------------------------------------

static func odds(s: GameState, a: Unit, t: Unit, reaction: bool, cover: int, breakdown: Array) -> void:
	if _has(a, "laser_sight") and cover != Types.Cover.NONE and int(a.status.get("painter_turn", -1)) != s.turn:
		breakdown.append(["Painter", Combat.COVER_FULL if cover == Types.Cover.FULL else Combat.COVER_HALF])
	if a.status.get("tap_second", false):
		breakdown.append(["Double tap", 0 if _m2(a, "double_tap") else -TAP_PENALTY])
	if _has(a, "spotter_scope") and GearFx.is_marked(s, t):
		breakdown.append(["Dead reckoning", 100])
	if reaction and _has(a, "ghillie_cloak") and not t.status.get("alerted", true):
		breakdown.append(["Still life", 100])


# --- After a shot (GearFx.after_shot) -------------------------------------------------------

static func after_shot(s: GameState, u: Unit, t: Unit, hit: bool, reaction: bool, dmg: int) -> void:
	if _has(u, "laser_sight") and int(u.status.get("painter_turn", -1)) != s.turn:
		u.status["painter_turn"] = s.turn
		if hit and t.is_alive():
			GearFx._mark(s, t, 3 if _m2(u, "laser_sight") else 1, u)
			_gear(s, u, "laser_sight", t)
	if not hit or _busy:
		return
	if not reaction and s.phase == Types.Phase.TEAM and _has(u, "light_harness") \
			and int(u.status.get("gear_move_len", 0)) >= SLIP_STEPS[1 if _m2(u, "light_harness") else 0]:
		u.status["gear_move_len"] = 0
		u.actions_left += 1
		_gear(s, u, "light_harness", null, {"actions": u.actions_left})
	if _has(u, "match_rounds") and (not reaction or _m2(u, "match_rounds")):
		_tight_group(s, u, t, dmg)
	if _has(u, "slug_rounds") and t.is_alive() and GearFx._dist(u.pos, t.pos) <= GearFx.CLOSE:
		_knock(s, u, t)
	if _has(u, "pilot_light") and t.is_alive() and GearFx.is_burning(s, t):
		var dir := Vector2i(signi(t.pos.x - u.pos.x), signi(t.pos.y - u.pos.y))
		var cells := GearFx.fire_line(u.pos, t.pos + dir, WICK_LENGTH[1 if _m2(u, "pilot_light") else 0])
		GearFx.set_fire(s, u, cells, 1)
		_gear(s, u, "pilot_light", t)
	if _has(u, "hollow_points") and t.is_alive() and Combat.has_status(s, t, "suppressed"):
		t.status["rooted"] = Combat.phase_index(s) + (4 if _m2(u, "hollow_points") else 2)
		_gear(s, u, "hollow_points", t)
	if reaction and _has(u, "expanding_rounds") and t.is_alive() and dmg > 0:
		t.status["wound"] = {"damage": dmg, "by": u.id}
		if _m2(u, "expanding_rounds"):
			t.status["rooted"] = Combat.phase_index(s) + 2
		_gear(s, u, "expanding_rounds", t)
	if _has(u, "spotter_scope") and GearFx.is_marked(s, t):
		var best: Unit = null
		for o in s.living():
			if o != t and u.is_enemy_of(o) and not GearFx.is_marked(s, o) and GearFx._dist(o.pos, t.pos) <= NEAR \
					and (best == null or GearFx._dist(o.pos, t.pos) < GearFx._dist(best.pos, t.pos)):
				best = o
		if best != null:
			GearLinks._tag(s, best, 2 if _m2(u, "spotter_scope") else 1)
			_gear(s, u, "spotter_scope", best)
	if reaction and _has(u, "ghillie_cloak") and t.is_alive() and not t.status.get("alerted", true):
		GearFx._mark(s, t, 3 if _m2(u, "ghillie_cloak") else 1, u)
		_gear(s, u, "ghillie_cloak", t)
	if reaction and _has(u, "bipod") and t.is_alive() and Ammo.can_fire(u):
		var cover := Combat.cover_against(s.grid, t.pos, u.pos)
		var open := cover == Types.Cover.NONE or (cover == Types.Cover.HALF and _m2(u, "bipod"))
		if open and int(u.status.get("dug_turn", -1)) != s.turn:
			u.status["dug_turn"] = s.turn
			_busy = true
			_gear(s, u, "bipod", t)
			Combat.fire(s, u, t, true)
			_busy = false


## Tight group: the second and later hits on one target in a turn repeat the first hit's damage.
static func _tight_group(s: GameState, u: Unit, t: Unit, dmg: int) -> void:
	var rec: Dictionary = u.status.get("tight", {})
	if int(rec.get("turn", -1)) == s.turn and int(rec.get("target", -1)) == t.id:
		if t.is_alive():
			_busy = true
			_gear(s, u, "match_rounds", t, {"damage": int(rec.damage)})
			Rules.deal_damage(s, t, int(rec.damage), u)
			_busy = false
	else:
		u.status["tight"] = {"turn": s.turn, "target": t.id, "damage": dmg}


## Knock rounds: shove `t` a tile away from `u`. Against a wall or a unit, both take damage and `t` is stunned.
static func _knock(s: GameState, u: Unit, t: Unit) -> void:
	var dir := Vector2i(signi(t.pos.x - u.pos.x), signi(t.pos.y - u.pos.y))
	if dir == Vector2i.ZERO or EnemyAbilities.immovable(t):
		return
	var n := t.pos + dir
	var blocker: Unit = s.unit_at(n)
	var dmg: int = KNOCK_DAMAGE[1 if _m2(u, "slug_rounds") else 0]
	if s.grid.is_walkable(n) and blocker == null:
		var before := t.pos
		EnemyAbilities.knockback(s, t, dir, 1)
		if t.pos != before:
			_gear(s, u, "slug_rounds", t)
			return
	_busy = true
	_gear(s, u, "slug_rounds", t, {"blocked": true, "damage": dmg})
	t.status["k_skip_turn"] = true
	t.actions_left = 0
	s.emit({"type": "stunned", "unit": t.id, "by": u.id})
	Rules.deal_damage(s, t, dmg, u)
	if blocker != null and blocker.is_alive() and blocker != u:
		Rules.deal_damage(s, blocker, dmg, u)
	_busy = false


## Recoil lock: Suppress also pins every enemy next to the target (within 2 tiles at Mk II).
static func recoil_lock(s: GameState, u: Unit, t: Unit) -> void:
	if not _has(u, "compensator") or _busy:
		return
	_busy = true
	var r: int = 2 if _m2(u, "compensator") else 1
	for o in s.living():
		if o != t and u.is_enemy_of(o) and GearFx._cheb(o.pos, t.pos) <= r:
			GearFx._suppress(s, u, o)
			_gear(s, u, "compensator", o)
	_busy = false


# --- Kills (GearFx.on_kill) -----------------------------------------------------------------

## Fixed blade: a kill within 2 tiles stabs an adjacent enemy, once a turn.
static func on_kill(s: GameState, u: Unit, t: Unit) -> void:
	kill_chain(s, u)
	if not _has(u, "bayonet") or _busy or GearFx._dist(u.pos, t.pos) > 2.0 or int(u.status.get("blade_turn", -1)) == s.turn:
		return
	for o in s.living():
		if o != t and u.is_enemy_of(o) and s.grid.melee_reach(u.pos, o.pos):
			u.status["blade_turn"] = s.turn
			_busy = true
			var dmg: int = BLADE_DAMAGE[1 if _m2(u, "bayonet") else 0]
			_gear(s, u, "bayonet", o, {"damage": dmg})
			Rules.deal_damage(s, o, dmg, u)
			_busy = false
			return


# --- Extra shots ----------------------------------------------------------------------------

## Steady hands: standing still (Mk II: 2 tiles or fewer) makes the first shot each turn leave an action.
## Called by Combat.apply after a soldier's shot has spent the turn.
static func steady_hands(s: GameState, u: Unit) -> void:
	if not _has(u, "steady_hands") or int(u.status.get("steady_turn", -1)) == s.turn:
		return
	var moved := int(u.status.get("gear_moved_turn", -1)) == s.turn
	if moved and (not _m2(u, "steady_hands") or int(u.status.get("gear_move_len", 0)) > 2):
		return
	u.status["steady_turn"] = s.turn
	u.actions_left += 1
	_gear(s, u, "steady_hands", null, {"actions": u.actions_left})


## Double tap: true once a turn when `u` may fire its second shot at the same target.
static func double_tap(s: GameState, u: Unit) -> bool:
	if not _has(u, "double_tap") or int(u.status.get("tap_turn", -1)) == s.turn or not Ammo.can_fire(u):
		return false
	u.status["tap_turn"] = s.turn
	_gear(s, u, "double_tap")
	return true


## Kill chain: a kill on your own turn gives its action back (Mk I: once a turn, Mk II: every kill).
static func kill_chain(s: GameState, u: Unit) -> void:
	if not _has(u, "kill_chain") or s.phase != Types.Phase.TEAM or u.team != Types.Team.PLAYER:
		return
	if not _m2(u, "kill_chain") and int(u.status.get("chain_turn", -1)) == s.turn:
		return
	u.status["chain_turn"] = s.turn
	u.actions_left += 1
	_gear(s, u, "kill_chain", null, {"actions": u.actions_left})


# --- Damage taken (GearFx.damage_taken) -----------------------------------------------------

static func damage_taken(s: GameState, target: Unit, amount: int, source: Unit) -> int:
	if amount <= 0 or not target.status.has("gear"):
		return amount
	if _has(target, "kevlar_vest"):
		var used := int(target.status.get("plate_hits", 0))
		if used < (2 if _m2(target, "kevlar_vest") else 1) and amount > 1:
			target.status["plate_hits"] = used + 1
			_gear(s, target, "kevlar_vest", null, {"damage": amount - 1})
			amount = 1
	if _has(target, "plated_rig") and int(target.status.get("gear_moved_turn", -1)) != s.turn and amount > 1:
		amount = maxi(1, amount / (3 if _m2(target, "plated_rig") else 2))
		_gear(s, target, "plated_rig")
	if source != null and source.is_alive() and source.is_enemy_of(target) and not _busy:
		_busy = true
		if _has(target, "ballistic_plate"):
			var back: int = amount if _m2(target, "ballistic_plate") else maxi(1, amount / 2)
			var any := false
			for o in s.living():
				if target.is_enemy_of(o) and GearFx._cheb(o.pos, target.pos) <= 1:
					any = true
					Rules.deal_damage(s, o, back, target)
			if any:
				_gear(s, target, "ballistic_plate", source, {"damage": back})
		if _has(target, "mycelial_weave") and int(target.status.get("blister_turn", -1)) != s.turn:
			target.status["blister_turn"] = s.turn
			var cells: Array = [source.pos]
			if _m2(target, "mycelial_weave"):
				for d in Grid.DIRS8:
					cells.append(source.pos + d)
			Hazards.add(s, cells, "acid", 2, target.id, Types.Team.PLAYER)
			_gear(s, target, "mycelial_weave", source)
		_busy = false
	if source != null and source.is_alive() and source.is_enemy_of(target) and _m2(target, "riot_shield") and _has(target, "riot_shield") \
			and GearFx._cheb(source.pos, target.pos) <= 1 and int(target.status.get("bash_turn", -1)) != s.turn:
		target.status["bash_turn"] = s.turn
		source.status["k_skip_turn"] = true
		source.actions_left = 0
		_gear(s, target, "riot_shield", source)
	return amount


## Exo frame: a move that ends beside an enemy slams it back a tile and Suppresses it (Mk II: 2 damage too).
static func after_move(s: GameState, u: Unit) -> void:
	if not _has(u, "exo_frame") or not u.is_alive():
		return
	var foe: Unit = null
	for o in s.living():
		if u.is_enemy_of(o) and GearFx._cheb(o.pos, u.pos) == 1:
			foe = o
			break
	if foe == null:
		return
	var dir := Vector2i(signi(foe.pos.x - u.pos.x), signi(foe.pos.y - u.pos.y))
	EnemyAbilities.knockback(s, foe, dir, 1)
	foe.status["suppressed"] = Combat.phase_index(s) + 2
	foe.overwatch = false
	_gear(s, u, "exo_frame", foe)
	if _m2(u, "exo_frame") and foe.is_alive():
		Rules.deal_damage(s, foe, 2, u)


# --- Turn flow ------------------------------------------------------------------------------

static func on_reload(s: GameState, u: Unit) -> void:
	u.status["plate_hits"] = 0
	if not _has(u, "extended_mag") or _busy:
		return
	_busy = true
	var shots: int = 2 if _m2(u, "extended_mag") else 1
	for o in GearLinks._nearest_visible(s, u, 9, 99):
		if shots <= 0 or not Ammo.can_fire(u) or not u.is_alive():
			break
		if o.is_alive() and Combat.has_status(s, o, "suppressed"):
			shots -= 1
			_gear(s, u, "extended_mag", o)
			Combat.fire(s, u, o, false)
	_busy = false


## Start of the team phase: Graft weave heals, Wounding rounds' wounds open.
static func on_team_phase_start(s: GameState) -> void:
	for u in s.living(Types.Team.PLAYER):
		if _has(u, "bio_mesh") and u.hp < u.max_hp:
			var n := GearFx.awake_mutations(u)
			if n > 0:
				var heal: int = mini(u.max_hp - u.hp, n * WEAVE_HEAL[1 if _m2(u, "bio_mesh") else 0])
				u.hp += heal
				_gear(s, u, "bio_mesh", null, {"heal": heal, "hp": u.hp})
	for e in s.living():
		if e.status.has("wound"):
			var w: Dictionary = e.status.wound
			e.status.erase("wound")
			var by := s.get_unit(int(w.get("by", -1)))
			s.emit({"type": "gear", "unit": by.id if by != null else e.id, "item": "expanding_rounds", "target": e.id, "damage": int(w.damage)})
			Rules.deal_damage(s, e, int(w.damage), by)


static func is_rooted(s: GameState, u: Unit) -> bool:
	return int(u.status.get("rooted", 0)) > Combat.phase_index(s)
