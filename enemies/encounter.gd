class_name Encounter
extends RefCounted
## Fight-level enemy rules: elites and affixes, Hive nodes and other spawners, reinforcement
## waves, spore zones, telegraphed strikes and the three bosses. Rules calls the hooks below;
## state lives in `GameState.encounter` and in unit statuses, so it is in every snapshot.
## OWNER: enemies workstream.
##
## `s.encounter` keys (all optional):
##   act, node ("skirmish" | "nest" | "boss"), outbreak, stage (Outbreak stage 0-4),
##   boss (boss kind), infect_bonus (extra Infection on infected hits), lapse_double (bool),
##   waves: [{turn, every, kinds: Array[String] specs}], incoming: [{turn, cells, kinds}],
##   telegraphs: [{kind, cells, turn, damage, source, smash, unit}],
##   over (bool, boss dead: adds die without death effects).

const SPAWN_CAP := 8             # living non-static enemies; spawners pause above this
## Boss fights by squad size (encounter "squad", default 4): egg sacs the Brood Mother starts
## with, roots shielding the Source, how often boss spawners (sacs, roots) spawn, and the spawn cap.
const BOSS_SACS := {1: 1, 2: 1, 3: 2, 4: 4}
const SOURCE_ROOTS := {1: 1, 2: 1, 3: 2, 4: 3}
const BOSS_SPAWN_EVERY_EXTRA := {1: 2, 2: 2, 3: 1, 4: 0}
const BOSS_DAMAGE := {1: 0.6, 2: 0.7, 3: 0.8, 4: 1.0}   # the boss's own hits on soldiers
const SQUAD_SPAWN_CAP := {1: 4, 2: 5, 3: 7, 4: SPAWN_CAP}
const HIDDEN_REVEAL_RANGE := 4
const SOURCE_PULSE := 5          # Infection to every soldier per turn in the Source's phase 1
const SOURCE_SAFE_RADIUS := 3    # spore rings stop this close to the Source
const CARRIER_BONUS := 1.5       # damage to the opened core from Mutating+ soldiers
const VIRULENT_EXTRA := 15
const REGEN := 3
const FRENZY_MOB := 2
const FRENZY_AIM := 10
const PERMANENT := 1 << 20


# --- setup ---------------------------------------------------------------------------------

## Applies an encounter description from FightBuilder.build (MatchConfig "encounter").
## Places the boss, its parts and Hive nodes, and seeds spore patches. Safe with {}.
static func setup(s: GameState, enc: Dictionary) -> void:
	s.encounter = enc.duplicate(true)
	if enc.is_empty():
		return
	s.encounter["telegraphs"] = []
	s.encounter["incoming"] = []
	if enc.get("hive", false):
		var cell := _marker(s, "hive", _far_spawn(s))
		var hive := _place(s, "hive_node", cell)
		hive.status["spawner"] = {"kinds": ["runner"], "every": 2, "next": 2, "i": 0}
	var markers: Variant = s.grid.get("markers")
	for i in int(enc.get("purge_nests", 0)):
		var cell := _far_spawn(s)
		if markers is Dictionary and markers.get("nest", []).size() > i:
			cell = markers.nest[i]
		elif not s.grid.enemy_spawns.is_empty():
			cell = s.grid.enemy_spawns[(i * 3) % s.grid.enemy_spawns.size()]
		var nest := _place(s, "spore_nest", cell)
		nest.status["spawner"] = {"kinds": ["runner"], "every": 2, "next": 2 + i % 2, "i": 0}
	var squad := clampi(int(enc.get("squad", 4)), 1, 4)
	var slower: int = BOSS_SPAWN_EVERY_EXTRA[squad]
	match str(enc.get("boss", "")):
		"brood_mother":
			var b := _place(s, "brood_mother", _marker(s, "boss", _far_spawn(s)))
			var offsets: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]
			for i in BOSS_SACS[squad]:
				var sac := _place(s, "egg_sac", b.pos + offsets[i])
				sac.status["spawner"] = {"kinds": ["runner"], "every": 2 + slower, "next": 2 + i % 2, "i": 0}
		"colonel_hale":
			var h := _place(s, "colonel_hale", _marker(s, "boss", _far_spawn(s)))
			h.cooldowns["airstrike"] = 1
		"the_source":
			var centre := Vector2i(s.grid.width / 2, s.grid.height / 2)
			var src := _place(s, "the_source", _marker(s, "boss", centre))
			var offsets: Array[Vector2i] = [Vector2i(0, -4), Vector2i(-4, 3), Vector2i(4, 3)]
			for i in SOURCE_ROOTS[squad]:
				var root := _place(s, "source_root", src.pos + offsets[i])
				root.status["spawner"] = {"kinds": ["runner", "spitter"], "every": 3 + slower, "next": 2 + i, "i": i}
	var mult := float(enc.get("boss_health_mult", 1.0))
	for u in s.living(Types.Team.ENEMY):
		if EnemyRoster.is_static(u) or enc.get("ambush", false):
			u.status["alerted"] = true
		if EnemyRoster.is_boss(u) and mult != 1.0:
			u.max_hp = maxi(1, roundi(u.max_hp * mult))
			u.hp = u.max_hp
	_seed_spores(s, int(enc.get("spore_patches", 0)))
	var start_inf := int(enc.get("start_infection", 0))
	if start_inf > 0:
		for u in s.living(Types.Team.PLAYER):
			Infection.add(s, u, start_inf)


static func _place(s: GameState, spec: String, near: Vector2i) -> Unit:
	var u := EnemyRoster.make(spec)
	s.add_unit(u, free_cell(s, near))
	return u


## A cell from the map generator's markers (grid.markers[name]), else `fallback`.
static func _marker(s: GameState, name: String, fallback: Vector2i) -> Vector2i:
	var markers: Variant = s.grid.get("markers")
	if markers is Dictionary and not markers.get(name, []).is_empty():
		return markers[name][0]
	return fallback


## The enemy spawn furthest from the squad (map centre if the map has none).
static func _far_spawn(s: GameState) -> Vector2i:
	var best := Vector2i(s.grid.width / 2, s.grid.height / 4)
	var best_d := -1.0
	for c in s.grid.enemy_spawns:
		var d := _dist_to_squad(s, c)
		if d > best_d:
			best_d = d
			best = c
	return best


static func _dist_to_squad(s: GameState, c: Vector2i) -> float:
	var d := INF
	for u in s.living(Types.Team.PLAYER):
		d = minf(d, Vector2(c).distance_to(Vector2(u.pos)))
	for p in s.grid.player_spawns:
		d = minf(d, Vector2(c).distance_to(Vector2(p)))
	return d


## Nearest walkable, unoccupied cell to `c` (c itself if free).
static func free_cell(s: GameState, c: Vector2i) -> Vector2i:
	var occ := s.occupied()
	if s.grid.is_walkable(c) and not occ.has(c):
		return c
	var seen := {c: true}
	var frontier: Array[Vector2i] = [c]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for f in frontier:
			for d in Grid.DIRS8:
				var n: Vector2i = f + d
				if seen.has(n) or not s.grid.in_bounds(n):
					continue
				seen[n] = true
				if s.grid.is_walkable(n) and not occ.has(n):
					return n
				next.append(n)
		frontier = next
	return c


static func _seed_spores(s: GameState, patches: int) -> void:
	var tries := 0
	while patches > 0 and tries < 200:
		tries += 1
		var c := Vector2i(s.rng.randi_range(1, s.grid.width - 2), s.rng.randi_range(1, s.grid.height - 2))
		if not s.grid.is_walkable(c) or _dist_to_squad(s, c) < 5.0:
			continue
		add_spores(s, EnemyAbilities.square(s.grid, c, 1), Hazards.PERMANENT)
		patches -= 1


# --- shared mechanics ----------------------------------------------------------------------

## Spawns an alerted enemy at (or near) `cell`. Emits {"type": "spawned", unit, kind, cell, from}.
static func spawn(s: GameState, spec: String, cell: Vector2i, source: Unit = null) -> Unit:
	var u := EnemyRoster.make(spec)
	s.add_unit(u, free_cell(s, cell))
	u.status["alerted"] = true
	u.status.erase("hidden")
	s.emit({"type": "spawned", "unit": u.id, "kind": u.kind, "cell": u.pos, "from": source.id if source else -1})
	return u


static func add_telegraph(s: GameState, t: Dictionary) -> void:
	if not s.encounter.has("telegraphs"):
		s.encounter["telegraphs"] = []
	s.encounter.telegraphs.append(t)
	s.emit({"type": "telegraph", "unit": t.get("unit", -1), "kind": t.kind, "cells": t.cells, "turn": t.turn})


## Spore zone on `cells` for `turns` rounds (Hazards.PERMANENT = until removed), through the
## shared Hazards module, which applies the Infection and draws the tiles.
static func add_spores(s: GameState, cells: Array, turns: int, source: Unit = null) -> void:
	Hazards.add(s, cells, "spore", turns, source.id if source else -1)


static func is_spore(s: GameState, c: Vector2i) -> bool:
	return Hazards.at(s, c).get("kind", "") == "spore"


## Shrieker buff: +2 move and +10 aim through the next enemy phase.
static func frenzy(s: GameState, u: Unit) -> void:
	if not u.status.has("frenzy"):
		u.mobility += FRENZY_MOB
		u.aim += FRENZY_AIM
		u.status["frenzy_mob"] = FRENZY_MOB
		u.status["frenzy_aim"] = FRENZY_AIM
	u.status["frenzy"] = s.turn + 1


static func _end_frenzy(u: Unit) -> void:
	u.mobility -= int(u.status.get("frenzy_mob", 0))
	u.aim -= int(u.status.get("frenzy_aim", 0))
	for k in ["frenzy", "frenzy_mob", "frenzy_aim"]:
		u.status.erase(k)


static func reveal(s: GameState, u: Unit) -> void:
	if u.status.get("hidden", false):
		u.status.erase("hidden")
		s.emit({"type": "revealed", "unit": u.id})
		EnemyAI.alert(s, u)


static func release_pin(s: GameState, lurker: Unit) -> void:
	var t := s.get_unit(lurker.status.get("pinning", -1))
	lurker.status.erase("pinning")
	if t != null:
		t.status.erase("pinned_by")
		s.emit({"type": "released", "unit": t.id, "by": lurker.id})


## Removes a unit without damage (boss death clears the adds).
static func kill(s: GameState, u: Unit) -> void:
	if not u.is_alive():
		return
	u.hp = 0
	u.overwatch = false
	s.emit({"type": "died", "unit": u.id})
	on_died(s, u)


# --- Rules hooks ---------------------------------------------------------------------------

## Extra legality checks, run by Rules.validate before module dispatch. "" = allowed.
static func validate(s: GameState, u: Unit, action: Dictionary) -> String:
	if u.status.has("pinned_by"):
		return "Pinned by a Lurker"
	if action.has("target"):
		var t := s.get_unit(action.get("target", -1))
		if t != null and t.status.get("hidden", false) and u.is_enemy_of(t):
			return "No line of sight"
	return ""


static func after_action(s: GameState, u: Unit, action: Dictionary) -> void:
	if action.get("type") == Types.ABILITY and action.get("ability") == "spit" and action.has("cell"):
		add_spores(s, [action.cell], EnemyAbilities.SPORE_TURNS, u)
	if action.get("type") == Types.MOVE and u.team == Types.Team.PLAYER:
		_reveal_near(s)


static func _reveal_near(s: GameState) -> void:
	for e in s.living(Types.Team.ENEMY):
		if not e.status.get("hidden", false) or e.status.has("burrowed"):
			continue
		for t in s.living(Types.Team.PLAYER):
			if e.pos.distance_to(t.pos) <= HIDDEN_REVEAL_RANGE:
				reveal(s, e)
				break


static func on_team_phase_start(s: GameState) -> void:
	for u in s.living(Types.Team.PLAYER):
		if u.status.has("pinned_by"):
			var l := s.get_unit(u.status.pinned_by)
			if l == null or not l.is_alive():
				u.status.erase("pinned_by")
			else:
				u.actions_left = 0
	if s.encounter.get("lapse_double", false):
		_extra_lapse_rolls(s)


## The Source's phase 2: Critical soldiers roll for Lapse a second time (double the odds).
static func _extra_lapse_rolls(s: GameState) -> void:
	var recovered := {}
	for i in range(s.log.size() - 1, -1, -1):
		var ev: Dictionary = s.log[i]
		if ev.type == "team_phase":
			break
		if ev.type == "recover":
			recovered[ev.unit] = true
	for u in s.living(Types.Team.PLAYER):
		if Infection.is_lapsed(u) or recovered.has(u.id):
			continue
		if Infection.tier(u.infection) != Infection.Tier.CRITICAL:
			continue
		var p: float = Infection.lapse_chance(u.infection)
		if s.rng.randf() < p / (1.0 - p):
			u.status["lapsed"] = true
			u.status["lapsed_turn"] = s.turn
			u.ai_controlled = true
			u.overwatch = false
			s.emit({"type": "lapse", "unit": u.id})


static func on_enemy_phase_start(s: GameState) -> void:
	if s.encounter.is_empty():
		return
	_resolve_telegraphs(s)
	var src := _boss(s, "the_source")
	if src != null and int(src.status.get("boss_phase", 1)) == 1:
		var hit: Array[int] = []
		for u in s.living(Types.Team.PLAYER):
			hit.append(u.id)
		s.emit({"type": "source_pulse", "unit": src.id, "units": hit, "amount": SOURCE_PULSE})
		for id in hit:
			Infection.add(s, s.get_unit(id), SOURCE_PULSE)
	_run_spawners(s)
	_spawn_incoming(s)
	_reveal_near(s)
	Rules.check_end(s)


static func _resolve_telegraphs(s: GameState) -> void:
	var keep: Array = []
	for t in s.encounter.get("telegraphs", []):
		if int(t.turn) > s.turn:
			keep.append(t)
			continue
		var src := s.get_unit(int(t.get("source", -1)))
		var victims: Array[Unit] = []
		for u in s.living():
			if t.cells.has(u.pos) and u != src:
				victims.append(u)
		s.emit({"type": "strike", "kind": t.kind, "cells": t.cells, "unit": t.get("unit", -1),
			"units": victims.map(func(x: Unit) -> int: return x.id), "damage": t.damage})
		for u in victims:
			Rules.deal_damage(s, u, int(t.damage), src if src != null and src.is_alive() else null)
		if t.get("smash", false) and s.phase != Types.Phase.ENDED:
			var hits := {}
			for c in t.cells:
				hits[c] = 1
			Destruction.noise(s, t.cells[t.cells.size() / 2])
			Destruction.hit(s, hits, src if src != null and src.is_alive() else null)
		if s.phase == Types.Phase.ENDED:
			return
	s.encounter["telegraphs"] = keep


static func _mobile_enemies(s: GameState) -> int:
	var n := 0
	for u in s.living(Types.Team.ENEMY):
		if not EnemyRoster.is_static(u):
			n += 1
	return n


static func _run_spawners(s: GameState) -> void:
	for u in s.living(Types.Team.ENEMY):
		var sp: Dictionary = u.status.get("spawner", {})
		if sp.is_empty() or s.turn < int(sp.next):
			continue
		sp.next = int(sp.next) + int(sp.every)
		if _mobile_enemies(s) >= _spawn_cap(s):
			continue
		var kinds: Array = sp.kinds
		var kind: String = kinds[int(sp.i) % kinds.size()]
		sp.i = int(sp.i) + 1
		spawn(s, kind, u.pos, u)


static func _spawn_cap(s: GameState) -> int:
	return SQUAD_SPAWN_CAP[clampi(int(s.encounter.get("squad", 4)), 1, 4)]


static func _spawn_incoming(s: GameState) -> void:
	var keep: Array = []
	for w in s.encounter.get("incoming", []):
		if int(w.turn) > s.turn:
			keep.append(w)
			continue
		for i in w.kinds.size():
			if _mobile_enemies(s) < _spawn_cap(s):
				spawn(s, w.kinds[i], w.cells[i % w.cells.size()])
	s.encounter["incoming"] = keep


static func on_unit_turn_start(s: GameState, u: Unit) -> void:
	if EnemyRoster.has_affix(u, "hasted"):
		u.actions_left = Types.ACTIONS_PER_TURN + 1
	if EnemyRoster.has_affix(u, "regenerating") and u.hp < u.max_hp \
			and int(u.status.get("burned_turn", -1)) != s.turn and int(u.status.get("burning", 0)) <= 0:
		var healed := mini(REGEN, u.max_hp - u.hp)
		u.hp += healed
		s.emit({"type": "regenerate", "unit": u.id, "healed": healed, "hp": u.hp})


static func on_unit_turn_end(s: GameState, u: Unit) -> void:
	if u.is_alive() and s.phase != Types.Phase.ENDED:
		EnemyBehaviours.end_turn(s, u)


static func on_enemy_phase_end(s: GameState) -> void:
	for u in s.living():
		if u.status.has("frenzy") and int(u.status.frenzy) <= s.turn:
			_end_frenzy(u)
	if s.encounter.is_empty():
		return
	var src := _boss(s, "the_source")
	if src != null:
		_spread_spore_ring(s, src)
	_announce_waves(s)


## The Source fight: spore zones grow one ring inward from the map edge every turn.
static func _spread_spore_ring(s: GameState, src: Unit) -> void:
	var ring := s.turn - 1
	var cells: Array[Vector2i] = []
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			var edge := mini(mini(x, y), mini(s.grid.width - 1 - x, s.grid.height - 1 - y))
			if edge == ring and EnemyAbilities._cheb(c, src.pos) > SOURCE_SAFE_RADIUS:
				cells.append(c)
	add_spores(s, cells, Hazards.PERMANENT, src)


## Waves due next turn get their cells now, so vents glow a full turn before anything comes out.
static func _announce_waves(s: GameState) -> void:
	var due := s.turn + 1
	for w in s.encounter.get("waves", []):
		if int(w.turn) != due:
			continue
		var cells := _wave_cells(s, w.kinds.size())
		s.encounter.incoming.append({"turn": due, "cells": cells, "kinds": w.kinds.duplicate()})
		s.emit({"type": "reinforcements_incoming", "cells": cells, "turn": due, "count": w.kinds.size()})
		if int(w.get("every", 0)) > 0:
			w.turn = int(w.turn) + int(w.every)


static func _wave_cells(s: GameState, n: int) -> Array[Vector2i]:
	var cands: Array[Vector2i] = []
	var markers: Variant = s.grid.get("markers")
	if markers is Dictionary:
		cands.assign(markers.get("reinforce", []))
	if cands.is_empty():
		cands.assign(s.grid.enemy_spawns)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist_to_squad(s, a) > _dist_to_squad(s, b))
	var out: Array[Vector2i] = []
	var occ := s.occupied()
	for c in cands:
		if out.size() >= n:
			break
		if not occ.has(c):
			out.append(c)
	if out.is_empty():
		out.append(free_cell(s, _far_spawn(s)))
	return out


## Adjusts incoming damage: tethers, armour, the Carrier twist, and boss phase thresholds.
static func modify_damage(s: GameState, target: Unit, amount: int, source: Unit) -> int:
	var tether: String = target.status.get("tether", "")
	if tether != "" and _any_alive(s, tether):
		s.emit({"type": "immune", "unit": target.id, "source": source.id if source else -1, "reason": tether})
		return 0
	var armour := int(target.status.get("armour", 0))
	if EnemyRoster.has_affix(target, "armoured"):
		armour += EnemyRoster.ARMOURED_REDUCTION
	if armour > 0:
		amount = maxi(1, amount - armour)
	if source != null and EnemyRoster.is_boss(source) and target.team == Types.Team.PLAYER:
		amount = maxi(1, roundi(amount * float(BOSS_DAMAGE[clampi(int(s.encounter.get("squad", 4)), 1, 4)])))
	if target.kind == "the_source" and source != null and source.team == Types.Team.PLAYER \
			and Infection.tier(source.infection) >= Infection.Tier.MUTATING:
		amount = ceili(amount * CARRIER_BONUS)
	# Phase-1 bosses always reach their second phase rather than dying outright.
	if target.kind in ["brood_mother", "colonel_hale"] and int(target.status.get("boss_phase", 1)) == 1:
		amount = mini(amount, target.hp - 1)
	return amount


static func on_damaged(s: GameState, target: Unit, source: Unit, amount: int) -> void:
	if source != null and target.team == Types.Team.PLAYER and target.is_alive() \
			and source.team == Types.Team.ENEMY and EnemyRoster.infects(source):
		var extra := int(s.encounter.get("infect_bonus", 0))
		if EnemyRoster.has_affix(source, "virulent"):
			extra += VIRULENT_EXTRA
		if extra > 0:
			Infection.add(s, target, extra)
	if target.status.get("hidden", false):
		reveal(s, target)
	if target.status.has("pinning") and source != null and source.team == Types.Team.PLAYER \
			and source.id != int(target.status.pinning):
		release_pin(s, target)
	if not target.is_alive():
		return
	match target.kind:
		"brood_mother":
			if int(target.status.boss_phase) == 1 and target.hp * 2 <= target.max_hp:
				target.status.boss_phase = 2
				target.mobility = 3
				target.status.erase("tether")
				s.emit({"type": "boss_phase", "unit": target.id, "phase": 2, "boss": target.kind,
					"text": "The Brood Mother tears free!"})
				# She lays two fresh sacs where she was rooted as she tears free (one for a small squad).
				var squad := clampi(int(s.encounter.get("squad", 4)), 1, 4)
				for d in [Vector2i(-1, 1), Vector2i(1, 1)].slice(0, mini(2, BOSS_SACS[squad])):
					var sac := _place(s, "egg_sac", target.pos + d * 2)
					sac.status["alerted"] = true
					sac.status["spawner"] = {"kinds": ["runner"], "every": 2 + BOSS_SPAWN_EVERY_EXTRA[squad], "next": s.turn + 1, "i": 0}
					s.emit({"type": "spawned", "unit": sac.id, "kind": sac.kind, "cell": sac.pos, "from": target.id})
		"colonel_hale":
			if int(target.status.boss_phase) == 1 and target.hp * 2 <= target.max_hp:
				target.status.boss_phase = 2
				target.hp += 20
				target.max_hp = target.hp
				target.status["armour"] = 1
				target.display_name = "Hale, Mutated"
				target.cooldowns.clear()
				s.emit({"type": "boss_phase", "unit": target.id, "phase": 2, "boss": target.kind,
					"hp": target.hp, "max_hp": target.max_hp, "text": "Colonel Hale mutates!"})


static func on_died(s: GameState, u: Unit) -> void:
	if u.status.has("pinning"):
		release_pin(s, u)
	if u.status.has("pinned_by"):
		var l := s.get_unit(u.status.pinned_by)
		u.status.erase("pinned_by")
		if l != null:
			l.status.erase("pinning")
	if s.encounter.get("over", false):
		return
	if u.team == Types.Team.ENEMY and EnemyRoster.has_affix(u, "splitting"):
		for i in 2:
			spawn(s, "runner", u.pos, u)
	if u.kind in ["bloater", "broodling"] and not u.status.get("burst", false):
		EnemyAbilities.burst(s, u)
	if EnemyRoster.is_boss(u):
		s.encounter["over"] = true
		s.emit({"type": "boss_defeated", "unit": u.id, "boss": u.kind})
		for o in s.living(Types.Team.ENEMY):
			kill(s, o)
		return
	if u.kind in ["hive_node", "source_root", "egg_sac"] and not _any_alive(s, u.kind):
		for o in s.living(Types.Team.ENEMY):
			if o.status.get("tether", "") == u.kind:
				o.status.erase("tether")
				s.emit({"type": "untethered", "unit": o.id})
				if o.kind == "the_source":
					o.status.boss_phase = 2
					s.encounter["lapse_double"] = true
					s.emit({"type": "boss_phase", "unit": o.id, "phase": 2, "boss": o.kind,
						"text": "The core opens!"})


static func _any_alive(s: GameState, kind: String) -> bool:
	for o in s.living():
		if o.kind == kind:
			return true
	return false


static func _boss(s: GameState, kind: String) -> Unit:
	for o in s.living(Types.Team.ENEMY):
		if o.kind == kind:
			return o
	return null
