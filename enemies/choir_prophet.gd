class_name ChoirProphet
extends RefCounted
## The Act 2 boss fight "the Hymn". A prophet on a dais sings the Choir's circle over the arena.
## Three phases, each gated so no single hit skips one:
##   1 Antiphon (100-67%): Cantors ring the Prophet and guard him (every hit loses GUARD damage while
##     one sings). He sings Verses, marked 3x3s that land next enemy phase. Inside the chant ring the
##     Choir hits harder and every soldier gains Infection each round.
##   2 Answer (67-33%): the hymn quickens the Choir. He fixes the hymn on the most Infected soldier he
##     can see (a teal link); if the link still holds next round the soldier is Compelled for two
##     rounds and fights for the song (a lone soldier stands transfixed and loses the rounds). Cleanse
##     them, break sight or Suppress him to stop it.
##   3 Crescendo (33-0%): the ring closes in and bites harder. Hush silences one soldier's signature,
##     and every third round the hymn peaks: a Crescendo marked across everything he can see.
## Suppress him and he cannot sing that round: no ring, no verse, no link. Never needs a second
## soldier. Encounter, EnemyBehaviours, EnemyAbilities and FightBuilder call in here.
## OWNER: enemies workstream.

## Boss HP as a share of his 40, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.85, 2: 0.65, 3: 1.1, 4: 1.5}
## Damage each hit loses while a Cantor sings, and how many Cantors ring him.
const GUARD := 2
const CANTORS := {1: 1, 2: 1, 3: 2, 4: 3}
## The chant ring: radius by phase, the extra damage the Choir deals inside it, and the Infection a
## soldier inside it gains at the start of every enemy phase.
const RING := {1: 5.0, 2: 4.0, 3: 3.0}
const RING_DAMAGE := {1: 0, 2: 1, 3: 2}
const RING_INFECTION := {1: 4, 2: 6, 3: 8}
const VERSE_DAMAGE := 2
const VERSE_RANGE := 14.0
const COMPEL_ROUNDS := {1: 1, 2: 1, 3: 2, 4: 2}
const HUSH_ROUNDS := 2
const HYMN_MAX := 3
const CRESCENDO_RADIUS := 10.0
const CRESCENDO_DAMAGE := 4
const CRESCENDO_INFECTION := 10
## The Choir's reinforcements: from turn 2, every third round.
const WAVE_FIRST := 2
const WAVE_EVERY := 4
const WAVE_KINDS := {1: [], 2: ["acolyte"], 3: ["acolyte", "acolyte", "cantor"], 4: ["acolyte", "acolyte", "acolyte", "cantor"]}
## Stand-ins until the Choir faction kinds exist (the Infected sing too).
const FALLBACK := {"cantor": "shrieker", "acolyte": "runner"}
## Ability ids that live here (EnemyAbilities.DEFS lists them, the rules below run them).
const OWNS: Array[String] = ["verse", "fix", "compel", "hush", "crescendo"]
const NAMES := {1: "The Choir Prophet", 2: "Prophet, Answered", 3: "Prophet, Crescendo"}


## `want` if the roster has it, else the Infected stand-in.
static func choir_kind(want: String) -> String:
	return want if UnitData.ENEMIES.has(want) else str(FALLBACK.get(want, "runner"))


static func squad_of(s: GameState) -> int:
	return clampi(int(s.encounter.get("squad", 4)), 1, 4)


static func setup(s: GameState, u: Unit, squad: int) -> void:
	u.status["alerted"] = true
	u.status["dais"] = u.pos
	u.status["hymn"] = 0
	u.cooldowns["fix"] = 1
	var kind := choir_kind("cantor")
	for c in _ring_spots(s, u.pos, int(CANTORS[squad])):
		var cantor := Encounter._place(s, kind, c)
		cantor.status["alerted"] = true
	if not s.encounter.has("waves"):
		s.encounter["waves"] = []
	var kinds: Array = []
	for k in WAVE_KINDS[squad]:
		kinds.append(choir_kind(k))
	if not kinds.is_empty():
		s.encounter.waves.append({"turn": WAVE_FIRST, "every": WAVE_EVERY, "kinds": kinds})


## `n` free cells two tiles from the dais, spread around it.
static func _ring_spots(s: GameState, c: Vector2i, n: int) -> Array[Vector2i]:
	var ring: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var p := c + Vector2i(dx, dy)
			if maxi(absi(dx), absi(dy)) == 2 and s.grid.in_bounds(p) and s.grid.is_walkable(p) and s.unit_at(p) == null:
				ring.append(p)
	ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return atan2(a.y - c.y, a.x - c.x) < atan2(b.y - c.y, b.x - c.x))
	var out: Array[Vector2i] = []
	for i in mini(n, ring.size()):
		out.append(ring[(i * ring.size()) / n])
	return out


# --- the circle ----------------------------------------------------------------------------------

static func prophet(s: GameState) -> Unit:
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "choir_prophet":
			return o
	return null


## True while he is singing: alive, and not suppressed this round.
static func singing(s: GameState, u: Unit) -> bool:
	return u != null and u.is_alive() and not Combat.has_status(s, u, "suppressed")


static func phase_of(u: Unit) -> int:
	return clampi(int(u.status.get("boss_phase", 1)), 1, 3)


static func ring_radius(u: Unit) -> float:
	return RING[phase_of(u)]


## Cantors that guard him: alive and within a step of the chant ring.
static func singers(s: GameState, u: Unit) -> Array[Unit]:
	var kind := choir_kind("cantor")
	var out: Array[Unit] = []
	for o in s.living(Types.Team.ENEMY):
		if o.kind == kind and o != u and o.pos.distance_to(u.pos) <= ring_radius(u) + 1.5:
			out.append(o)
	return out


## [cantor id, prophet id] for the teal threads that show who guards him.
static func guards(s: GameState) -> Array:
	var u := prophet(s)
	var out: Array = []
	if u == null or not Vision.sees_unit(s, Types.Team.PLAYER, u):
		return out
	for c in singers(s, u):
		if Vision.sees_unit(s, Types.Team.PLAYER, c):
			out.append([c.id, u.id])
	return out


## +damage when a Choir unit fights inside the chant ring while he sings.
static func chant_bonus(s: GameState, source: Unit) -> int:
	var u := prophet(s)
	if not singing(s, u) or source.team != Types.Team.ENEMY or EnemyRoster.is_static(source):
		return 0
	return int(RING_DAMAGE[phase_of(u)]) if source.pos.distance_to(u.pos) <= ring_radius(u) else 0


# --- phases --------------------------------------------------------------------------------------

static func gates(u: Unit) -> Array[int]:
	return [ceili(u.max_hp * 2 / 3.0), ceili(u.max_hp / 3.0)]


## Caps a hit so it stops at the next phase gate, after the Cantors' guard takes its share.
static func clamp_damage(s: GameState, u: Unit, amount: int) -> int:
	if amount > 0 and not singers(s, u).is_empty():
		amount = maxi(1, amount - GUARD)
	var phase := int(u.status.get("boss_phase", 1))
	var g := gates(u)
	if phase <= g.size() and u.hp > g[phase - 1]:
		return mini(amount, u.hp - g[phase - 1])
	return amount


static func on_damaged(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	var g := gates(u)
	if phase > g.size() or u.hp > g[phase - 1]:
		return
	u.status.boss_phase = phase + 1
	u.cooldowns.clear()
	u.display_name = NAMES[phase + 1]
	if phase == 1:
		u.cooldowns["fix"] = 1
		for o in s.living(Types.Team.ENEMY):
			if o != u and not EnemyRoster.is_static(o):
				Encounter.frenzy(s, o)
		s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
			"hp": u.hp, "max_hp": u.max_hp, "text": "The hymn answers!"})
		return
	u.status["hymn"] = 0
	u.cooldowns["hush"] = 1
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
		"hp": u.hp, "max_hp": u.max_hp, "text": "The circle closes!"})


## Start of every enemy phase: the ring presses Infection into every soldier standing in it.
static func on_enemy_phase_start(s: GameState) -> void:
	var u := prophet(s)
	if not singing(s, u):
		return
	var r := ring_radius(u)
	var amount: int = RING_INFECTION[phase_of(u)]
	var hit: Array[int] = []
	for t in s.living(Types.Team.PLAYER):
		if t.pos.distance_to(u.pos) <= r and not t.status.get("hidden", false):
			hit.append(t.id)
	if hit.is_empty():
		return
	s.emit({"type": "chant", "unit": u.id, "units": hit, "amount": amount, "radius": r})
	for id in hit:
		Infection.add(s, s.get_unit(id), amount)


## Start of every squad phase: Hush wears off.
static func on_team_phase_start(s: GameState) -> void:
	for t in s.living(Types.Team.PLAYER):
		if t.status.has("hushed"):
			t.status.hushed = int(t.status.hushed) - 1
			if int(t.status.hushed) <= 0:
				t.status.erase("hushed")
				s.emit({"type": "unhushed", "unit": t.id})


## Why `u` cannot use `action` ("" if it can): a Hushed soldier's signature is silent.
static func validate_hushed(u: Unit, action: Dictionary) -> String:
	if u.status.has("hushed") and action.get("type") == Types.ABILITY and Signatures.is_signature(str(action.get("ability", ""))):
		return "Hushed: the hymn silences the signature"
	return ""


## +/- damage for a Compelled soldier's own shots: they fight the song, so their hits are halved.
static func compelled_damage(source: Unit, amount: int) -> int:
	if source != null and source.status.has("compelled") and amount > 1:
		return ceili(amount / 2.0)
	return amount


# --- his abilities (EnemyAbilities routes the ids in OWNS here) -------------------------------------

static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	var id: String = action.ability
	if not singing(s, u):
		return "Suppressed: he cannot sing"
	match id:
		"verse":
			var cell: Variant = action.get("cell")
			if not cell is Vector2i or not s.grid.in_bounds(cell):
				return "Invalid cell"
			if u.pos.distance_to(cell) > VERSE_RANGE or not Combat.can_see(s, u.pos, cell):
				return "Out of range"
		"fix":
			var t := s.get_unit(int(action.get("target", -1)))
			if t == null or not _can_fix(s, u, t):
				return "Nobody to fix on"
		"compel":
			var t := s.get_unit(int(u.status.get("fixed", -1)))
			if t == null or not t.is_alive() or not Combat.can_see(s, u.pos, t.pos):
				return "Lost the target"
		"hush":
			var t := s.get_unit(int(action.get("target", -1)))
			if t == null or not _can_hush(s, u, t):
				return "Nobody to silence"
		"crescendo":
			if int(u.status.get("hymn", 0)) < HYMN_MAX:
				return "The hymn has not peaked"
	return ""


static func apply(s: GameState, u: Unit, action: Dictionary) -> void:
	match str(action.ability):
		"verse":
			var cells := EnemyAbilities.square(s.grid, action.cell, 1)
			s.emit({"type": "ability", "unit": u.id, "ability": "verse", "cell": action.cell, "cells": cells})
			Encounter.add_telegraph(s, {"kind": "verse", "cells": cells, "turn": s.turn + 1,
				"damage": VERSE_DAMAGE, "source": u.id, "smash": false, "unit": u.id})
		"fix":
			var t := s.get_unit(action.target)
			u.status["fixed"] = t.id
			s.emit({"type": "ability", "unit": u.id, "ability": "fix", "target": t.id})
			s.emit({"type": "telegraph", "unit": u.id, "kind": "fix", "cells": [t.pos] as Array[Vector2i], "turn": s.turn + 1, "target": t.id})
		"compel":
			var t := s.get_unit(int(u.status.fixed))
			u.status.erase("fixed")
			s.emit({"type": "ability", "unit": u.id, "ability": "compel", "target": t.id})
			compel(s, t)
		"hush":
			var t := s.get_unit(action.target)
			t.status["hushed"] = HUSH_ROUNDS + 1
			s.emit({"type": "ability", "unit": u.id, "ability": "hush", "target": t.id})
		"crescendo":
			var cells := crescendo_cells(s, u)
			u.status["hymn"] = 0
			s.emit({"type": "ability", "unit": u.id, "ability": "crescendo", "cells": cells})
			Encounter.add_telegraph(s, {"kind": "crescendo", "cells": cells, "turn": s.turn + 1,
				"damage": CRESCENDO_DAMAGE, "source": u.id, "smash": false, "unit": u.id, "infect": CRESCENDO_INFECTION})


## Every floor tile he can see within the hymn's reach: hide behind something solid.
static func crescendo_cells(s: GameState, u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := int(CRESCENDO_RADIUS)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := u.pos + Vector2i(dx, dy)
			if c != u.pos and s.grid.in_bounds(c) and s.grid.is_walkable(c) and u.pos.distance_to(c) <= CRESCENDO_RADIUS \
					and Combat.can_see(s, u.pos, c):
				out.append(c)
	return out


static func _can_fix(s: GameState, u: Unit, t: Unit) -> bool:
	return t.is_alive() and t.team == Types.Team.PLAYER and not t.status.get("lapsed", false) \
		and not t.status.get("hidden", false) and not u.status.has("fixed") and Combat.can_see(s, u.pos, t.pos)


static func _can_hush(s: GameState, u: Unit, t: Unit) -> bool:
	return t.is_alive() and t.team == Types.Team.PLAYER and not t.status.has("hushed") and not t.status.get("lapsed", false) \
		and t.abilities.any(func(a: String) -> bool: return Signatures.is_signature(a)) and Combat.can_see(s, u.pos, t.pos)


## The hymn takes a soldier: they Lapse for COMPEL_ROUNDS rounds (Infection ends a Lapse after one
## round, so the count is held in "compelled") and any cure ends it at once.
static func compel(s: GameState, t: Unit) -> void:
	t.status["lapsed"] = true
	t.status["lapsed_turn"] = s.turn
	t.status["compelled"] = int(COMPEL_ROUNDS[squad_of(s)]) + 1
	t.ai_controlled = true
	t.overwatch = false
	s.emit({"type": "lapse", "unit": t.id, "compelled": true})
	Kit.on_lapse(s, t)


# --- his turn ------------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	if u.status.has("fixed"):
		if not EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "compel"}):
			u.status.erase("fixed")
			s.emit({"type": "lock_lost", "unit": u.id})
	if not singing(s, u):
		return
	var phase := phase_of(u)
	var hostiles := _targets(s, u)
	if phase == 3:
		u.status["hymn"] = int(u.status.get("hymn", 0)) + 1
		s.emit({"type": "hymn", "unit": u.id, "charge": u.status.hymn, "max": HYMN_MAX})
		if int(u.status.hymn) >= HYMN_MAX and EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "crescendo"}):
			return
	if hostiles.is_empty():
		return
	var taken: Array[Vector2i] = []
	for step in 2:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var went := false
		if step == 0:   # the first bar is the special one when it is ready, the second is always a verse
			went = _special(s, u, phase, hostiles) or _verse(s, u, hostiles, taken)
		else:
			went = _verse(s, u, hostiles, taken) or _special(s, u, phase, hostiles)
		if not went:
			break
	if u.actions_left > 0 and u.is_alive() and s.phase != Types.Phase.ENDED:
		_psalm(s, u, hostiles)


## Hush (phase 3) or the fix (phases 2 and 3), whichever is ready.
static func _special(s: GameState, u: Unit, phase: int, hostiles: Array[Unit]) -> bool:
	if phase == 3 and int(u.cooldowns.get("hush", 0)) <= 0:
		var h := hush_target(s, u, hostiles)
		if h != null and EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "hush", "target": h.id}):
			return true
	if phase >= 2 and not u.status.has("fixed") and int(u.cooldowns.get("fix", 0)) <= 0:
		var t := fix_target(s, u, hostiles)
		if t != null and EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "fix", "target": t.id}):
			return true
	return false


static func _verse(s: GameState, u: Unit, hostiles: Array[Unit], taken: Array[Vector2i]) -> bool:
	var cell := verse_cell(s, u, hostiles, taken)
	if cell.hits <= 0:
		return false
	taken.append_array(EnemyAbilities.square(s.grid, cell.cell, 1))
	return EnemyBehaviours._try(s, {"type": Types.ABILITY, "unit": u.id, "ability": "verse", "cell": cell.cell})


## Soldiers he would sing at: on our side of the line, not already his, in plain sight.
static func _targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in s.living(Types.Team.PLAYER):
		if not t.status.has("compelled") and not t.status.get("hidden", false) and Combat.can_see(s, u.pos, t.pos):
			out.append(t)
	return out


## The most Infected soldier he can see (then the nearest to him).
static func fix_target(s: GameState, u: Unit, hostiles: Array[Unit]) -> Unit:
	var best: Unit = null
	for t in hostiles:
		if not _can_fix(s, u, t):
			continue
		if best == null or t.infection > best.infection \
				or (t.infection == best.infection and u.pos.distance_to(t.pos) < u.pos.distance_to(best.pos)):
			best = t
	return best


## A soldier with a signature ready to use (the one that would hurt most to lose).
static func hush_target(s: GameState, u: Unit, hostiles: Array[Unit]) -> Unit:
	var best: Unit = null
	for t in hostiles:
		if _can_hush(s, u, t) and (best == null or t.infection > best.infection):
			best = t
	return best


## The 3x3 that catches the most soldiers (and none of his own), skipping ground a verse already marks.
static func verse_cell(s: GameState, u: Unit, hostiles: Array[Unit], taken: Array[Vector2i]) -> Dictionary:
	var best := {"cell": u.pos, "hits": 0}
	var best_score := 0.0
	for h in hostiles:
		if taken.has(h.pos) or u.pos.distance_to(h.pos) > VERSE_RANGE:
			continue
		var hits := 0
		var score := 0.0
		for o in s.living():
			if EnemyAI._cheb(o.pos, h.pos) <= 1:
				if u.is_enemy_of(o) and not o.status.has("compelled"):
					hits += 1
					score += 1.0 + 0.02 * o.infection
				else:
					score -= 1.5
		if score > best_score:
			best_score = score
			best = {"cell": h.pos, "hits": hits}
	return best


## Nothing to sing: a plain shot at the best target in sight.
static func _psalm(s: GameState, u: Unit, hostiles: Array[Unit]) -> void:
	var best: Unit = null
	var best_hit := -1
	for t in Combat.visible_targets(s, u):
		if t.team != Types.Team.PLAYER or t.status.has("compelled"):
			continue
		var hit: int = Combat.hit_chance(s, u, t).hit
		if hit > best_hit:
			best_hit = hit
			best = t
	if best != null:
		EnemyBehaviours._try(s, {"type": Types.SHOOT, "unit": u.id, "target": best.id})


# --- a Compelled soldier ----------------------------------------------------------------------------

## Fights for the song: shoots the nearest squadmate in sight, else walks toward one. A soldier with
## no squad stands transfixed and loses the rounds. Their hits are halved (compelled_damage).
static func compelled_turn(s: GameState, u: Unit) -> void:
	var steps := 0
	while u.actions_left > 0 and u.is_alive() and s.phase != Types.Phase.ENDED and steps < 4:
		steps += 1
		var mates: Array[Unit] = []
		for o in s.living(Types.Team.PLAYER):
			if o != u and not o.status.get("hidden", false):
				mates.append(o)
		var action := {}
		var seen: Array[Unit] = []
		for t in Combat.visible_targets(s, u):
			if mates.has(t):
				seen.append(t)
		if not seen.is_empty():
			seen.sort_custom(func(a: Unit, b: Unit) -> bool: return u.pos.distance_to(a.pos) < u.pos.distance_to(b.pos))
			action = EnemyAI._check(s, {"type": Types.SHOOT, "unit": u.id, "target": seen[0].id})
		if action.is_empty():
			var goal := u.pos
			var best := INF
			for o in mates:
				if u.pos.distance_to(o.pos) < best:
					best = u.pos.distance_to(o.pos)
					goal = o.pos
			if mates.is_empty():
				return
			var cells: Array = Rules.move_range(s, u).keys()
			var to := u.pos
			var to_d := u.pos.distance_to(goal)
			for c in cells:
				var d := Vector2(c).distance_to(Vector2(goal))
				if d < to_d and d >= 1.0:
					to_d = d
					to = c
			if to != u.pos:
				action = EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": to})
		if action.is_empty() or not Rules.apply(s, action):
			return
