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
## Close range for passives like Point Blank. Range aim terms are per weapon (Weapons).
const CLOSE_RANGE := 3.0
const TAG_BONUS := 15
const SUPPRESS_PENALTY := 30
const REACTION_PENALTY := 15
const MIN_CHANCE := 5
const GRAZE_BAND := 10
const FLANK_CRIT := 40
const MELEE_COVER := 20
const NO_CELL := Vector2i(-999, -999)

## Ability table. "cost": actions spent, or -1 for "all actions" (ends the turn).
const ABILITIES := {
	"suppress": {"name": "Suppress", "targeting": "unit", "cost": -1, "cooldown": 2,
		"desc": "Pin a visible enemy: -30 aim on its next shot and cancels its overwatch. Ends turn."},
	"tag": {"name": "Marksman Tag", "targeting": "unit", "cost": 1, "cooldown": 2,
		"desc": "Mark a visible enemy until the end of the next enemy phase: all soldiers get +15 aim against it. 1 action."},
	"stim": {"name": "Stim", "targeting": "unit", "cost": 1, "cooldown": 2,
		"desc": "Self or adjacent ally: heal 3 and reduce infection by 15. 1 action."},
	"breach": {"name": "Breach", "targeting": "unit", "cost": -1, "cooldown": 3,
		"desc": "Hit an enemy within 2 tiles for 4-6, ignoring cover, and knock its cover down a step. Never misses. Ends turn."},
	"claw": {"name": "Claw", "targeting": "unit", "cost": -1, "cooldown": 0,
		"desc": "Melee attack on an adjacent enemy. Only half cover counts. Ends turn."},
	"spit": {"name": "Spit", "targeting": "cell", "cost": -1, "cooldown": 3,
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
## Height: raised cells taller than both ends block like walls. Two ground units can't see across
## a roof; from a roof (or flying) you look over other roofs of that height, and from an upper
## roof (level 2) over everything but walls.
static func can_see(s: GameState, from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
	if from.distance_to(to) > SIGHT_RANGE:
		return false
	var g := s.grid
	var over := maxi(_eye(s, from), _eye(s, to)) if not g.levels.is_empty() else -1
	if line_clear(g, from, to, over):
		return true
	for p in peek_cells(g, from):
		if line_clear(g, p, to, over):
			return true
	return false


## Height of whatever stands at `c`: its level, at least 1 for a flying unit.
static func _eye(s: GameState, c: Vector2i) -> int:
	var h := s.grid.level(c)
	var u := s.unit_at(c)
	if u != null and u.status.get("flying", false):
		h = maxi(h, 1)
	return h


## Supercover line between cell centers; true if no WALL lies strictly between `a` and `b`
## (nor a raised cell higher than `over`; `over` < 0 ignores height, `true` means 0 for old callers),
## and no edge wall stands on a border it crosses (edge walls are one storey tall: units higher
## than that see over them, unless `over` < 0).
## When the line passes exactly through a corner it is blocked only if both ways around it are.
static func line_clear(g: Grid, a: Vector2i, b: Vector2i, over: Variant = -1) -> bool:
	var top: int = (0 if over else -1) if over is bool else int(over)
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
			var x := Vector2i(sx, 0)
			var y := Vector2i(0, sy)
			var via_x := _blocks(g, c + x, top) or _edge_blocks(g, c, x, top) or _edge_blocks(g, c + x, y, top)
			var via_y := _blocks(g, c + y, top) or _edge_blocks(g, c, y, top) or _edge_blocks(g, c + y, x, top)
			if via_x and via_y:
				return false
			c += Vector2i(sx, sy)
			ix += 1
			iy += 1
		elif lhs < rhs:
			if _edge_blocks(g, c, Vector2i(sx, 0), top):
				return false
			c.x += sx
			ix += 1
		else:
			if _edge_blocks(g, c, Vector2i(0, sy), top):
				return false
			c.y += sy
			iy += 1
		if c != b and _blocks(g, c, top):
			return false
	return true


static func _blocks(g: Grid, c: Vector2i, top: int) -> bool:
	return g.blocks_los(c) or (top >= 0 and g.level(c) > top)


static func _edge_blocks(g: Grid, c: Vector2i, d: Vector2i, top: int) -> bool:
	return g.edge_blocks_los(c, d) and (top < 0 or g.edge_top(c, d) > top)


## Open cells a unit at `c` can lean out to: beside each orthogonally adjacent wall or edge wall.
static func peek_cells(g: Grid, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Grid.DIRS4:
		var w := c + d
		if not g.in_bounds(w) or not (g.blocks_los(w) or g.edge_blocks_los(c, d)):
			continue
		for p in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var q: Vector2i = c + p
			if g.in_bounds(q) and not g.blocks_los(q) and not g.edge_blocks_los(c, p) and not out.has(q):
				out.append(q)
	return out


## Hostile living units `u` can currently shoot at. Squad units also need the target inside
## the squad's shared vision (fog of war, see Vision); enemy targeting is unchanged.
static func visible_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in s.units:
		if t.is_alive() and u.is_enemy_of(t) and not t.status.get("hidden", false) and can_see(s, u.pos, t.pos) \
				and in_squad_sight(s, u, t):
			out.append(t)
	return out


## Fog of war gate for squad units: the target must be seen by the squad. Always true for enemies.
static func in_squad_sight(s: GameState, u: Unit, t: Unit) -> bool:
	return u.team != Types.Team.PLAYER or Vision.sees_unit(s, u.team, t)


## Everything `u` may SHOOT: visible targets plus Smart-link shots at Marked enemies an ally sees.
static func shot_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out := visible_targets(s, u)
	for t in s.living():
		if not out.has(t) and u.is_enemy_of(t) and GearFx.smart_link_shot(s, u, t):
			out.append(t)
	return out


## Fuel barrels `u` may SHOOT ({"type": SHOOT, "cell": c}): squad soldiers with a gun, barrels
## in their own sight (Destruction.barrel_targets).
static func shot_barrels(s: GameState, u: Unit) -> Array[Vector2i]:
	if not _shoots_barrels(u):
		var none: Array[Vector2i] = []
		return none
	return Destruction.barrel_targets(s, u)


static func _shoots_barrels(u: Unit) -> bool:
	return u.team == Types.Team.PLAYER and not u.ai_controlled and not UnitData.is_melee_only(u.kind)


# ---------------------------------------------------------------- cover / odds

## Cover a unit at `target` has against an attack from `from`: the best obstacle one step
## toward the attacker on x and on y.
## A raised block beside the target is a building wall: full cover against anyone lower than its roof.
static func cover_against(g: Grid, target: Vector2i, from: Vector2i) -> int:
	var best: int = Types.Cover.NONE
	var sx := signi(from.x - target.x)
	var sy := signi(from.y - target.y)
	for side in [Vector2i(sx, 0), Vector2i(0, sy)]:
		if side == Vector2i.ZERO:
			continue
		var n: Vector2i = target + side
		best = maxi(best, g.cover_toward(target, side))
		if g.level(n) > g.level(target) and g.level(from) < g.level(n):
			best = Types.Cover.FULL
	return best


## Shot odds from `attacker` to `target`, optionally as if the attacker stood at `from`.
## Returns {"hit": int 0-100, "graze": int, "crit": int, "cover": Types.Cover,
##          "flanked": bool, "los": bool, "breakdown": Array of [label: String, value: int]}.
## "graze" is the width of the graze band (rolls in hit+1..hit+graze graze); "crit" is the
## chance that a hit is critical. `reaction` applies the overwatch penalty.
static func hit_chance(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos, reaction: bool = false) -> Dictionary:
	var los := can_see(s, from, target.pos) or Kit.shared_sight(s, attacker, target.pos) \
		or GearFx.smart_link_shot(s, attacker, target)
	var flat_cover := Kit.cover_against(s, attacker, target, cover_against(s.grid, target.pos, from), from)
	var cover := Elevation.adjust_cover(s, attacker, target, from, flat_cover)
	var flanked := flat_cover == Types.Cover.NONE and cover == Types.Cover.NONE
	var breakdown: Array = [["Aim", attacker.aim]]
	var height_aim := Elevation.aim_mod(s, attacker, target, from)
	if height_aim != 0:
		breakdown.append(["High ground", height_aim])
	if cover != Types.Cover.NONE and Infection.has_hive_sense(s, attacker):
		breakdown.append(["Hive Sense (ignores cover)", 0])
	elif cover != Types.Cover.NONE:
		var cv := COVER_FULL if cover == Types.Cover.FULL else COVER_HALF
		breakdown.append(["Full cover" if cover == Types.Cover.FULL else "Half cover", -cv])
		if is_hunkered(s, target):
			breakdown.append(["Hunkered", -cv])
	if target.defense != 0:
		breakdown.append(["Defense", -target.defense])
	Weapons.range_terms(attacker, from.distance_to(target.pos), breakdown)
	if attacker.team == Types.Team.PLAYER and has_status(s, target, "tagged"):
		breakdown.append(["Tagged", TAG_BONUS])
	if has_status(s, attacker, "suppressed"):
		breakdown.append(["Suppressed", -SUPPRESS_PENALTY])
	if reaction and Weapons.reaction_penalty(attacker, REACTION_PENALTY) != 0:
		breakdown.append(["Reaction shot", -Weapons.reaction_penalty(attacker, REACTION_PENALTY)])
	GearFx.odds_terms(s, attacker, target, from, reaction, cover, breakdown)
	Concealment.odds_terms(s, attacker, target, reaction, breakdown)
	var crit := Kit.modify_odds(s, attacker, target, from, reaction, breakdown)
	return _finish_odds(breakdown, cover, flanked, los, mini(100, (FLANK_CRIT if flanked else 0) + crit + Weapons.crit_bonus(attacker)),
		Weapons.graze_band(attacker, GRAZE_BAND))


## Shot odds at the fuel barrel on `c`: aim, a bonus for the big still drum, high ground, range,
## suppression and the overwatch penalty. No cover, no crits, no graze: it goes off or it doesn't.
static func barrel_chance(s: GameState, attacker: Unit, c: Vector2i, from: Vector2i = attacker.pos, reaction: bool = false) -> Dictionary:
	var breakdown: Array = [["Aim", attacker.aim], ["Fuel drum", Destruction.BARREL_AIM]]
	if s.grid.level(from) > s.grid.level(c):
		breakdown.append(["High ground", Elevation.AIM_BONUS])
	Weapons.range_terms(attacker, from.distance_to(c), breakdown)
	if has_status(s, attacker, "suppressed"):
		breakdown.append(["Suppressed", -SUPPRESS_PENALTY])
	if reaction and Weapons.reaction_penalty(attacker, REACTION_PENALTY) != 0:
		breakdown.append(["Reaction shot", -Weapons.reaction_penalty(attacker, REACTION_PENALTY)])
	return _finish_odds(breakdown, Types.Cover.NONE, false, can_see(s, from, c), 0, 0)


## Odds of a claw (melee) attack: aim, minus 20 if the target has any cover toward the attacker.
static func melee_chance(s: GameState, attacker: Unit, target: Unit, from: Vector2i = attacker.pos) -> Dictionary:
	var cover := cover_against(s.grid, target.pos, from)
	var breakdown: Array = [["Aim", attacker.aim]]
	if cover != Types.Cover.NONE:
		breakdown.append(["Cover", -MELEE_COVER])
	if has_status(s, attacker, "suppressed"):
		breakdown.append(["Suppressed", -SUPPRESS_PENALTY])
	return _finish_odds(breakdown, cover, cover == Types.Cover.NONE, true, 0)


static func _finish_odds(breakdown: Array, cover: int, flanked: bool, los: bool, crit: int, band := GRAZE_BAND) -> Dictionary:
	var total := 0
	for term in breakdown:
		total += int(term[1])
	var hit := clampi(total, MIN_CHANCE, 100) if los else 0
	if not los:
		breakdown.append(["No line of sight", -total])
	var graze := mini(band, 100 - hit) if los else 0
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
	out.append_array(ClassAbilities.available(s, u))
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
	out.append_array(GearFx.available_abilities(s, u))
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
			if not u.is_enemy_of(t) or not can_see(s, u.pos, t.pos) or not in_squad_sight(s, u, t):
				return "No line of sight"
		"stim":
			if u.is_enemy_of(t):
				return "Not an ally"
			if _cheb(u.pos, t.pos) > Kit.ability_range(u, "stim", 1):
				return "Too far"
		"breach":
			if not u.is_enemy_of(t):
				return "Not an enemy"
			if _cheb(u.pos, t.pos) > Kit.ability_range(u, "breach", BREACH_RANGE):
				return "Too far"
			if not can_see(s, u.pos, t.pos) or not in_squad_sight(s, u, t):
				return "No line of sight"
		"claw":
			if not u.is_enemy_of(t):
				return "Not an enemy"
			if not s.grid.melee_reach(u.pos, t.pos):
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
	if GearFx.owns(id): return GearFx.validate_ability(s, u, action)
	if ClassAbilities.handles(id):
		return ClassAbilities.validate(s, u, action)
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
	var cost: int = Kit.ability_cost(u, id, def.cost)
	u.actions_left = 0 if cost < 0 else maxi(0, u.actions_left - cost)
	var cd: int = Kit.ability_cooldown(u, id, def.cooldown)
	if cd > 0:
		u.cooldowns[id] = cd


static func _apply_ability(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.ability
	if GearFx.owns(id):
		GearFx.apply_ability(s, u, action)
		return
	if ClassAbilities.handles(id):
		ClassAbilities.apply(s, u, action)
		return
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
			GearFx.on_suppress(s, u, t)
		"tag":
			t.status["tagged"] = phase_index(s) + (2 if s.phase != Types.Phase.ENEMY else 3)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id})
		"stim":
			var healed := mini(Kit.medic_heal(t, STIM_HEAL), t.max_hp - t.hp)
			t.hp += healed
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id, "heal": healed, "hp": t.hp})
			var before := t.infection
			Infection.add(s, t, -Kit.medic_cure(t, STIM_CURE))
			Kit.after_stim(s, u, t, before - t.infection)
		"breach":
			var dmg := s.rng.randi_range(BREACH_DAMAGE.x, BREACH_DAMAGE.y)
			s.emit({"type": "ability", "unit": u.id, "ability": id, "target": t.id, "hit": true, "damage": dmg})
			var cover := Destruction.cover_cells(s.grid, t.pos, u.pos)   # the blast knocks its cover down a step
			Rules.deal_damage(s, t, dmg, u)
			if not cover.is_empty() and s.phase != Types.Phase.ENDED:
				var hits := {}
				for c in cover:
					hits[c] = 1
				Destruction.hit(s, hits, u)
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
				Kit.after_melee(s, u, t, dmg)
			Kit.after_claw(s, u, t)
	Kit.after_ability(s, u, id, t)


# ---------------------------------------------------------------- actions

static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	match action.type:
		Types.SHOOT:
			if UnitData.is_melee_only(u.kind):
				return "Melee only"
			if action.has("cell"):
				var c: Variant = action.cell
				if not c is Vector2i or not _shoots_barrels(u):
					return "Can't shoot that"
				return Destruction.barrel_error(s, u, c)
			var t := s.get_unit(action.get("target", -1))
			if t == null or not shot_targets(s, u).has(t):
				return "No line of sight"
		Types.ABILITY:
			return _validate_ability(s, u, action)
	return ""


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	_sweep(s)
	match action.type:
		Types.SHOOT:
			u.actions_left = 0
			if action.has("cell"):
				fire_at_barrel(s, u, action.cell, false)
			else:
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
		dmg = Kit.shot_damage(s, u, t, final_damage(s.rng.randi_range(u.damage.x, u.damage.y), r.graze, r.crit))
		dmg = GearFx.shot_damage(s, u, t, dmg, reaction)
	s.emit({"type": "shot", "unit": u.id, "target": t.id, "hit": r.hit or r.graze, "graze": r.graze,
		"crit": r.crit, "damage": dmg, "chance": odds.hit, "reaction": reaction})
	if dmg > 0:
		Rules.deal_damage(s, t, dmg, u)
	elif not (r.hit or r.graze):
		Weapons.after_miss(s, u, t)
	GearFx.after_shot(s, u, t, r.hit or r.graze, reaction, dmg)
	Kit.after_shot(s, u, t, odds, dmg > 0)


## Rolls one shot from `u` at the fuel barrel on `c` and emits "barrel_shot"; a hit sets it off
## (Destruction.hit, chain and fire included). Spends no actions.
static func fire_at_barrel(s: GameState, u: Unit, c: Vector2i, reaction: bool) -> void:
	var odds := barrel_chance(s, u, c, u.pos, reaction)
	var hit := s.rng.randi_range(1, 100) <= int(odds.hit)
	u.status.erase("suppressed")
	s.emit({"type": "barrel_shot", "unit": u.id, "cell": c, "hit": hit, "chance": odds.hit, "reaction": reaction})
	if hit:
		Destruction.hit(s, {c: 1}, u)


## Overwatch at a fuel barrel instead of the mover: a barrel the watcher sees whose blast (chain
## included) catches the mover and none of the watcher's side, when that shot is at least as
## likely as the one at the mover. NO_CELL when there is none. Must not change state.
static func reaction_barrel(s: GameState, w: Unit, mover: Unit) -> Vector2i:
	if not _shoots_barrels(w) or s.grid.volatile.is_empty():
		return NO_CELL
	var direct := int(hit_chance(s, w, mover, w.pos, true).hit)
	var best := NO_CELL
	var best_odds := direct - 1
	for c in shot_barrels(s, w):
		var blasts := Destruction.barrel_blasts(s, c)
		var caught := func(o: Unit) -> bool: return blasts.any(func(b: Vector2i) -> bool: return Kit.cheb(b, o.pos) <= 1)
		if not caught.call(mover):
			continue
		if s.living().any(func(o: Unit) -> bool: return not o.is_enemy_of(w) and caught.call(o)):
			continue
		var odds := int(barrel_chance(s, w, c, w.pos, true).hit)
		if odds > best_odds:
			best_odds = odds
			best = c
	return best


## Units on overwatch that would react to `mover` entering `cell`. Must not change state.
## Overwatch covers the watcher's own sight radius (Vision.overwatch_sees), not the squad's.
static func reactions_to_move(s: GameState, mover: Unit, cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	for w in s.units:
		if w != mover and is_overwatching(s, w) and w.is_enemy_of(mover) and Kit.can_react(w, mover) \
				and (Vision.overwatch_sees(s, w, mover, cell) or (not mover.status.get("hidden", false) and Kit.shared_sight(s, w, cell))):
			out.append(w)
	return out


## Fire the reactions found by reactions_to_move: each shoots at -15 aim and leaves overwatch.
static func resolve_reactions(s: GameState, mover: Unit, reactors: Array[Unit]) -> void:
	for w in reactors:
		if not mover.is_alive() or s.phase == Types.Phase.ENDED:
			return
		if not is_overwatching(s, w):
			continue
		if not Kit.keep_overwatch(s, w, mover):
			w.overwatch = false
			w.status.erase("ow_until")
		var barrel := reaction_barrel(s, w, mover)
		if barrel != NO_CELL:
			fire_at_barrel(s, w, barrel, true)
		else:
			fire(s, w, mover, true)
