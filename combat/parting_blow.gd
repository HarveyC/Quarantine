class_name PartingBlow
extends RefCounted
## Attacks of opportunity. A unit that steps out of a hostile melee fighter's reach takes one free
## strike from it. Once per fighter per phase; a careful move (Disengage) provokes nothing.

static var enabled := true
const CAREFUL_RANGE := 2
const SOLDIER_MELEE := ["reaper", "warden"]


## True when `w` could swing at anyone leaving its reach.
static func can_swing(s: GameState, w: Unit) -> bool:
	if not w.is_alive() or w.status.get("stunned", false) or EnemyRoster.is_static(w):
		return false
	if w.team == Types.Team.PLAYER:
		if ClassAbilities.gun_drawn(w):
			return false   # the melee weapon is put away
		return SOLDIER_MELEE.has(w.kind) or w.abilities.has("lunge") or w.abilities.has("bash")
	return UnitData.is_melee_only(w.kind) and w.damage.y > 0


## Fighters who swing as `mover` steps `from` -> `to`. Pure.
static func provoked(s: GameState, mover: Unit, from: Vector2i, to: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	if not enabled or mover.status.get("careful", false):
		return out
	if maxi(absi(to.x - from.x), absi(to.y - from.y)) > 1:
		return out   # a zipline or a cellar tunnel slips free
	for w in s.units:
		if w != mover and w.is_enemy_of(mover) and can_swing(s, w) \
				and int(w.status.get("pb_phase", -1)) != Combat.phase_index(s) \
				and s.grid.melee_reach(w.pos, from) and not s.grid.melee_reach(w.pos, to):
			out.append(w)
	return out


static func resolve(s: GameState, mover: Unit, swingers: Array[Unit]) -> void:
	for w in swingers:
		if not mover.is_alive() or s.phase == Types.Phase.ENDED:
			return
		w.status["pb_phase"] = Combat.phase_index(s)
		if w.team == Types.Team.PLAYER:
			ClassAbilities.strike(s, w, mover, "bash" if w.abilities.has("bash") and not w.abilities.has("lunge") else "lunge", {"parting": true})
			continue
		var odds := Combat.melee_chance(s, w, mover)
		var r := Combat.resolve_roll(s.rng.randi_range(1, 100), odds)
		var dmg := 0
		if r.hit or r.graze:
			var base := s.rng.randi_range(w.damage.x, w.damage.y)
			dmg = Combat.final_damage(base, r.graze, false)
		s.emit({"type": "ability", "unit": w.id, "ability": "claw", "target": mover.id,
				"hit": r.hit or r.graze, "graze": r.graze, "damage": dmg, "chance": odds.hit, "parting": true})
		if dmg > 0:
			Rules.deal_damage(s, mover, dmg, w)


## True when someone could swing at `u` for leaving its place.
static func threatened(s: GameState, u: Unit) -> bool:
	for w in s.units:
		if w != u and w.is_enemy_of(u) and can_swing(s, w) and s.grid.melee_reach(w.pos, u.pos) \
				and int(w.status.get("pb_phase", -1)) != Combat.phase_index(s):
			return true
	return false


## Cells a Disengage can reach: the usual move range, at most CAREFUL_RANGE tiles away.
static func careful_cells(s: GameState, u: Unit) -> Array:
	var out: Array = []
	for c in Rules.move_range(s, u):
		if Kit.cheb(u.pos, c) <= CAREFUL_RANGE and c != u.pos:
			out.append(c)
	return out
