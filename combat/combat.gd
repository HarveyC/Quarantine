class_name Combat
extends RefCounted
## Line of sight, cover, hit chance, shooting, overwatch, hunker and class abilities.
## OWNER: combat workstream. Public functions below are the contract other modules use;
## keep their signatures stable.
##
## Timed statuses: Combat stores timed effects in `unit.status` as the *phase index* they
## expire on (see `phase_index`), and treats them as expired once the game reaches it, so
## nothing has to tick them. Expired entries are swept from `unit.status` at the start of
## every Combat.apply. Keys used: "suppressed", "tagged" (int expiry), plus "ow_until" and
## "hunker_until" which time-limit the `overwatch` / `hunkered` flags (needed for enemies,
## whose flags Rules never clears).

const SIGHT_RANGE := 14.0
const COVER_HALF := 20
const COVER_FULL := 40
const CLOSE_RANGE := 3.0
const CLOSE_BONUS := 15
const LONG_RANGE := 10.0
const LONG_PENALTY_PER_TILE := 3
const TAG_BONUS := 15
const SUPPRESS_PENALTY := 30
const REACTION_PENALTY := 15
const MIN_CHANCE := 5
const GRAZE_BAND := 10
const FLANK_CRIT := 40
const MELEE_COVER := 20

## Ability table. "cost": actions spent, or -1 for "all actions" (ends the turn).
const ABILITIES := {
	"suppress": {"name": "Suppress", "targeting": "unit", "cost": -1, "cooldown": 2,
		"desc": "Pin a visible enemy: -30 aim on its next shot and cancels its overwatch. Ends turn."},
	"tag": {"name": "Marksman Tag", "targeting": "unit", "cost": 1, "cooldown": 2,
		"desc": "Mark a visible enemy until the end of the next enemy phase: all soldiers get +15 aim against it. 1 action."},
	"stim": {"name": "Stim", "targeting": "unit", "cost": 1, "cooldown": 2,
		"desc": "Self or adjacent ally: heal 3 and reduce infection by 15. 1 action."},
	"breach": {"name": "Breach", "targeting": "unit", "cost": -1, "cooldown": 3,
		"desc": "Hit an enemy within 2 tiles for 4-6, ignoring cover. Never misses. Ends turn."},
	"claw": {"name": "Claw", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Melee attack on an adjacent enemy. Only half cover counts. Ends turn."},
	"spit": {"name": "Spit", "targeting": "cell", "cost": -1, "cooldown": 2,
		"desc": "Lob a glob at a cell within 7 tiles: 2 damage to every unit within 1 tile. Ends turn."},
}

const STIM_HEAL := 3
const STIM_CURE := 15
const BREACH_RANGE := 2
const BREACH_DAMAGE := Vector2i(4, 6)
const SPIT_RANGE := 7.0
const SPIT_RADIUS := 1
const SPIT_DAMAGE := 2


# ---------------------------------------------------------------- timing / status

## Monotonic counter of half-turns: team phase of turn T = 2T, enemy phase = 2T + 1.
static func phase_index(s: GameState) -> int:
	return s.turn * 2 + (1 if s.phase == Types.Phase.ENEMY else 0)


## True if a timed (or boolean) status is currently active on `u`. Pure.
static func has_status(s: GameState, u: Unit, key: String) -> bool:
	if not u.status.has(key):
		return false
	var v: Variant = u.status[key]
	if v is int:
		return phase_index(s) < int(v)
	return bool(v)


static func is_overwatching(s: GameState, u: Unit) -> bool:
	if not u.overwatch or not u.is_alive():
		return false
	return not u.status.has("ow_until") or phase_index(s) < int(u.status["ow_until"])


static func is_hunkered(s: GameState, u: Unit) -> bool:
	if not u.hunkered:
		return false
	return not u.status.has("hunker_until") or phase_index(s) < int(u.status["hunker_until"])


## Removes expired timed statuses and stale overwatch/hunker flags.
static func _sweep(s: GameState) -> void:
	var now := phase_index(s)
	for u in s.units:
		for key in ["suppressed", "tagged"]:
			if u.status.has(key) and u.status[key] is int and now >= int(u.status[key]):
				u.status.erase(key)
		if u.status.has("ow_until") and now >= int(u.status["ow_until"]):
			u.overwatch = false
			u.status.erase("ow_until")
		if u.status.has("hunker_until") and now >= int(u.status["hunker_until"]):
			u.hunkered = false
			u.status.erase("hunker_until")


# ---------------------------------------------------------------- line of sight

## True if a unit at `from` can see `to`. Walls block, low cover and units do not.
## A viewer standing next to a wall may "step out" to the open cells beside it.
static func can_see(s: GameState, from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
	if from.distance_to(to) > SIGHT_RANGE:
		return false
	if line_clear(s.grid, from, to):
		return true
	for p in peek_cells(s.grid, from):
		if line_clear(s.grid, p, to):
			return true
	return false


## Supercover line between cell centers; true if no WALL lies strictly between `a` and `b`.
## When the line passes exactly through a corner it is blocked only if both side cells block.
static func line_clear(g: Grid, a: Vector2i, b: Vector2i) -> bool:
	var nx := absi(b.x - a.x)
	var ny := absi(b.y - a.y)
	var sx := signi(b.x - a.x)
	var sy := signi(b.y - a.y)
	var c := a
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		var lhs := (1 + 2 * ix) * ny
		var rhs := (1 + 2 * iy) * nx
		if lhs == rhs:
			if g.blocks_los(Vector2i(c.x + sx, c.y)) and g.blocks_los(Vector2i(c.x, c.y + sy)):
				return false
			c += Vector2i(sx, sy)
			ix += 1
			iy += 1
		elif lhs < rhs:
			c.x += sx
			ix += 1
		else:
			c.y += sy
			iy += 1
		if c != b and g.blocks_los(c):
			return false
	return true


## Open cells a unit at `c` can lean out to: beside each orthogonally adjacent wall.
static func peek_cells(g: Grid, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Grid.DIRS4:
		var w := c + d
		if not g.in_bounds(w) or not g.blocks_los(w):
			continue
		for p in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var q: Vector2i = c + p
			if g.in_bounds(q) and not g.blocks_los(q) and not out.has(q):
				out.append(q)
	return out


## Hostile living units `u` can currently shoot at.
static func visible_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in s.units:
		if t.is_alive() and u.is_enemy_of(t) and can_see(s, u.pos, t.pos):
			out.append(t)
	return out


# ---------------------------------------------------------------- cover / odds

## Cover a unit at `target` has against an attack from `from`: the best obstacle one step
## toward the attacker on x and on y.
static func cover_against(g: Grid, target: Vector2i, from: Vector2i) -> int:
	var best: int = Types.Cover.NONE
	var sx := signi(from.x - target.x)
	var sy := signi(from.y - target.y)
	if sx != 0:
		best = maxi(best, g.cover_value(target + Vector2i(sx, 0)))
	if sy != 0:
		best = maxi(best, g.cover_value(target + Vector2i(0, sy)))
	return best


## Shot odds from `attacker` to `target`, optionally as if the attacker stood at `from`.
## Returns {"hit": int 0-100, "graze": int, "crit": int, "cover": Types.Cover,
##          "flanked": bool, "los": bool, "breakdown": Array of [label: String, value: int]}.
## "graze" is the width of the graze band (rolls in hit+1..hit+graze graze); "crit" is the
## chance that a hit is critical. `reaction` applies the overwatch penalty.
static func hit_chance(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos, reaction: bool = false) -> Dictionary:
	var los := can_see(s, from, target.pos)
	var cover := cover_against(s.grid, target.pos, from)
	var flanked := cover == Types.Cover.NONE
	var breakdown: Array = [["Aim", attacker.aim]]
	if cover != Types.Cover.NONE:
		var cv := COVER_FULL if cover == Types.Cover.FULL else COVER_HALF
		breakdown.append(["Full cover" if cover == Types.Cover.FULL else "Half cover", -cv])
		if is_hunkered(s, target):
			breakdown.append(["Hunkered", -cv])
	if target.defense != 0:
		breakdown.append(["Defense", -target.defense])
	var dist := from.distance_to(target.pos)
	if dist <= CLOSE_RANGE:
		breakdown.append(["Close range", CLOSE_BONUS])
	elif dist > LONG_RANGE:
		breakdown.append(["Long range", -LONG_PENALTY_PER_TILE * ceili(dist - LONG_RANGE)])
	if attacker.team == Types.Team.PLAYER and has_status(s, target, "tagged"):
		breakdown.append(["Tagged", TAG_BONUS])
	if has_status(s, attacker, "suppressed"):
		breakdown.append(["Suppressed", -SUPPRESS_PENALTY])
	if reaction:
		breakdown.append(["Reaction shot", -REACTION_PENALTY])
	return _finish_odds(breakdown, cover, flanked, los, FLANK_CRIT if flanked else 0)


## Odds of a claw (melee) attack: aim, minus 20 if the target has any cover toward the attacker.
static func melee_chance(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos) -> Dictionary:
	var cover := cover_against(s.grid, target.pos, from)
	var breakdown: Array = [["Aim", attacker.aim]]
	if cover != Types.Cover.NONE:
		breakdown.append(["Cover", -MELEE_COVER])
	if has_status(s, attacker, "suppressed"):
		breakdown.append(["Suppressed", -SUPPRESS_PENALTY])
	return _finish_odds(breakdown, cover, cover == Types.Cover.NONE, true, 0)


static func _finish_odds(breakdown: Array, cover: int, flanked: bool, los: bool, crit: int) -> Dictionary:
	var total := 0
	for term in breakdown:
		total += int(term[1])
	var hit := clampi(total, MIN_CHANCE, 100) if los else 0
	if not los:
		breakdown.append(["No line of sight", -total])
	var graze := mini(GRAZE_BAND, 100 - hit) if los else 0
	return {"hit": hit, "graze": graze, "crit": crit if los else 0, "cover": cover,
		"flanked": flanked, "los": los, "breakdown": breakdown}


## Resolves a single 1..100 roll against odds: hit if roll <= hit, graze if within the band
## above it, crit if roll <= hit * crit / 100 (so `crit` is the crit chance given a hit).
static func resolve_roll(roll: int, odds: Dictionary) -> Dictionary:
	var hit_c: int = odds.hit
	var graze_c: int = odds.graze
	var crit_c: int = odds.crit
	var hit := roll <= hit_c
	var graze := not hit and roll <= hit_c + graze_c
	var crit := hit and roll * 100 <= hit_c * crit_c
	return {"hit": hit, "graze": graze, "crit": crit}


## Damage after graze (half, min 1) or crit (+50%, rounded up).
static func final_damage(base: int, graze: bool, crit: bool) -> int:
	if graze:
		return maxi(1, base / 2)
	if crit:
		return ceili(base * 1.5)
	return base


# ---------------------------------------------------------------- abilities

## Abilities `u` could use right now: Array of {"id", "name", "targeting": "none"|"unit"|"cell",
## "ready": bool, "cooldown": int, "cost": int (-1 = ends turn), "desc", "targets": Array of unit ids}.
static func available_abilities(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in u.abilities:
		if not ABILITIES.has(id):
			continue
		var def: Dictionary = ABILITIES[id]
		var cd: int = u.cooldowns.get(id, 0)
		var targets := ability_targets(s, u, id)
		var has_targets: bool = def.targeting == "cell" or not targets.is_empty()
		out.append({"id": id, "name": def.name, "targeting": def.targeting, "cost": def.cost,
			"cooldown": cd, "desc": def.desc, "targets": targets,
			"ready": cd <= 0 and u.actions_left > 0 and u.is_alive() and has_targets})
	return out


## Unit ids `u` may target with a unit-targeted ability (empty for cell abilities).
static func ability_targets(s: GameState, u: Unit, id: String) -> Array[int]:
	var out: Array[int] = []
	if not ABILITIES.has(id) or ABILITIES[id].targeting != "unit":
		return out
	for t in s.units:
		if _ability_target_error(s, u, id, t) == "":
			out.append(t.id)
	return out


static func _ability_target_error(s: GameState, u: Unit, id: String, t: Unit) -> String:
	if t == null or not t.is_alive():
		return "No such target"
	match id:
		"suppress", "tag":
			if not u.is_enemy_of(t) or not can_see(s, u.pos, t.pos):
				return "No line of sight"
		"stim":
			if u.is_enemy_of(t):
				return "Not an ally"
			if _cheb(u.pos, t.pos) > 1:
				return "Too far"
		"breach":
			if not u.is_enemy_of(t):
				return "Not an enemy"
			if _cheb(u.pos, t.pos) > BREACH_RANGE:
				return "Too far"
			if not can_see(s, u.pos, t.pos):
				return "No line of sight"
		"claw":
			if not u.is_enemy_of(t):
				return "Not an enemy"
			if _cheb(u.pos, t.pos) != 1:
				return "Not adjacent"
	return ""


static func _spit_cell_error(s: GameState, u: Unit, cell: Variant) -> String:
	if not cell is Vector2i:
		return "No target cell"
	var c: Vector2i = cell
	if not s.grid.in_bounds(c) or s.grid.blocks_los(c):
		return "Invalid cell"
	if u.pos.distance_to(c) > SPIT_RANGE:
		return "Too far"
	if not can_see(s, u.pos, c):
		return "No line of sight"
	return ""


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _validate_ability(s: GameState, u: Unit, action: Dictionary) -> String:
	var id: String = action.get("ability", "")
	if not ABILITIES.has(id) or not u.abilities.has(id):
		return "Unknown ability"
	if int(u.cooldowns.get(id, 0)) > 0:
		return "On cooldown"
	if ABILITIES[id].targeting == "cell":
		return _spit_cell_error(s, u, action.get("cell"))
	var t := u
	if action.has("target"):
		t = s.get_unit(action.target)
	elif id != "stim":
		return "No target"
	return _ability_target_error(s, u, id, t)


static func _spend(u: Unit, id: String) -> void:
	var def: Dictionary = ABILITIES[id]
	var cost: int = def.cost
	u.actions_left = 0 if cost < 0 else maxi(0, u.actions_left - cost)
	var cd: int = def.cooldown
	if cd > 0:
		u.cooldowns[id] = cd


static func _apply_ability(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.ability
	_spend(u, id)
	if id == "spit":
		var cell: Vector2i = action.cell
		var hit_units: Array[Unit] = []
		for t in s.units:
			if t.is_alive() and t != u and _cheb(t.pos, cell) <= SPIT_RADIUS:
				hit_units.append(t)
		s.emit({"type": "ability", "unit": u.id, "ability": id, "cell": cell,
			"units": hit_units.map(func(x: Unit) -> int: return x.id), "damage": SPIT_DAMAGE})
		for t in hit_units:
			Rules.deal_damage(s, t, SPIT_DAMAGE, u)
		return
	var t: Unit = s.get_unit(action.target) if action.has("target") else u
	match id:
		"suppress":
			t.status["suppressed"] = phase_index(s) + 2
			t.overwatch = false
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id})
		"tag":
			t.status["tagged"] = phase_index(s) + (2 if s.phase != Types.Phase.ENEMY else 3)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id})
		"stim":
			var healed := mini(STIM_HEAL, t.max_hp - t.hp)
			t.hp += healed
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id, "heal": healed, "hp": t.hp})
			Infection.add(s, t, -STIM_CURE)
		"breach":
			var dmg := s.rng.randi_range(BREACH_DAMAGE.x, BREACH_DAMAGE.y)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id, "hit": true, "damage": dmg})
			Rules.deal_damage(s, t, dmg, u)
		"claw":
			var odds := melee_chance(s, u, t)
			var r := resolve_roll(s.rng.randi_range(1, 100), odds)
			u.status.erase("suppressed")
			var dmg := 0
			if r.hit or r.graze:
				dmg = final_damage(s.rng.randi_range(u.damage.x, u.damage.y), r.graze, false)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id,
				"hit": r.hit or r.graze, "graze": r.graze, "damage": dmg, "chance": odds.hit})
			if dmg > 0:
				Rules.deal_damage(s, t, dmg, u)


# ---------------------------------------------------------------- actions

static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	match action.type:
		Types.SHOOT:
			var t := s.get_unit(action.get("target", -1))
			if t == null or not visible_targets(s, u).has(t):
				return "No line of sight"
		Types.ABILITY:
			return _validate_ability(s, u, action)
	return ""


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	_sweep(s)
	match action.type:
		Types.SHOOT:
			u.actions_left = 0
			fire(s, u, s.get_unit(action.target), false)
		Types.OVERWATCH:
			u.overwatch = true
			u.status["ow_until"] = phase_index(s) + 2
			u.actions_left = 0
			s.emit({"type": "overwatch", "unit": u.id})
		Types.HUNKER:
			u.hunkered = true
			u.status["hunker_until"] = phase_index(s) + 2
			u.actions_left = 0
			s.emit({"type": "hunker", "unit": u.id})
		Types.ABILITY:
			_apply_ability(s, u, action)


## Rolls one shot from `u` at `t`, emits the "shot" event and deals damage. Spends no actions.
## A graze has hit = true, graze = true and reduced damage.
static func fire(s: GameState, u: Unit, t: Unit, reaction: bool) -> void:
	var odds := hit_chance(s, u, t, u.pos, reaction)
	var r := resolve_roll(s.rng.randi_range(1, 100), odds)
	u.status.erase("suppressed")
	var dmg := 0
	if r.hit or r.graze:
		dmg = final_damage(s.rng.randi_range(u.damage.x, u.damage.y), r.graze, r.crit)
	s.emit({"type": "shot", "unit": u.id, "target": t.id, "hit": r.hit or r.graze, "graze": r.graze,
		"crit": r.crit, "damage": dmg, "chance": odds.hit, "reaction": reaction})
	if dmg > 0:
		Rules.deal_damage(s, t, dmg, u)


## Units on overwatch that would react to `mover` entering `cell`. Must not change state.
static func reactions_to_move(s: GameState, mover: Unit, cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	for w in s.units:
		if w != mover and is_overwatching(s, w) and w.is_enemy_of(mover) and can_see(s, w.pos, cell):
			out.append(w)
	return out


## Fire the reactions found by reactions_to_move: each shoots at -15 aim and leaves overwatch.
static func resolve_reactions(s: GameState, mover: Unit, reactors: Array[Unit]) -> void:
	for w in reactors:
		if not mover.is_alive() or s.phase == Types.Phase.ENDED:
			return
		if not is_overwatching(s, w):
			continue
		w.overwatch = false
		w.status.erase("ow_until")
		fire(s, w, mover, true)
