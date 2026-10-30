class_name Broker
extends RefCounted
## The Act 1 boss fight, "the Haul". Harrow's biggest looter and his convoy. Three phases, each gated
## so no single hit skips one:
##   1 Haggle (100-67%): keeps to cover and shoots while Cutters (reinforcements) lift soldiers' items.
##   2 Haul (67-33%): takes each soldier's best item (disabled for the fight while he holds it) and
##     runs for the exit lane at the arena's edge, shooting on the way. Every hit that lands shakes one
##     item loose and back to its owner. Reaching the exit with loot burns it.
##   3 Burn (33-0%): cornered, he burns whatever he still holds (those items stay gone for the fight),
##     lobs firebombs at clusters and clubs whoever is nearest.
## Items are never lost for good by the Cutters' own thefts (kill the Cutter, as ever); the Broker's
## hoard is the part a build has to survive. Encounter, EnemyBehaviours and FightBuilder call in here.
## Status keys: Broker "hoard": Array of {unit, item}, "exit": Vector2i; soldier "stolen" (shared with
## the Cutter, see Scavengers) and "burned": Array of item ids.
## OWNER: enemies workstream.

## Boss HP as a share of his 30, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 1.25, 2: 1.45, 3: 2.1, 4: 2.4}
const MOBILITY := {2: 6, 3: 5}
## Cutters that come in as reinforcements (turn, then every WAVE_EVERY), by squad size.
const WAVE_KINDS := {1: [], 2: ["cutter"], 3: ["cutter", "cutter"], 4: ["cutter", "cutter", "torchman"]}
const WAVE_FIRST := 3
const WAVE_EVERY := 4
const BOMB_COOLDOWN := 2
const EXIT_REACH := 1          # Chebyshev distance to the exit cell that counts as arrived


static func setup(s: GameState, b: Unit, squad: int) -> void:
	b.status["alerted"] = true
	b.status["hoard"] = []
	b.status["exit"] = exit_cell(s, b)
	if not WAVE_KINDS[squad].is_empty():
		if not s.encounter.has("waves"):
			s.encounter["waves"] = []
		s.encounter.waves.append({"turn": WAVE_FIRST, "every": WAVE_EVERY, "kinds": WAVE_KINDS[squad].duplicate()})


## The exit lane's cell: the arena's exit marker, else the edge cell furthest from the squad.
static func exit_cell(s: GameState, b: Unit) -> Vector2i:
	var markers: Variant = s.grid.get("markers")
	if markers is Dictionary and not markers.get("exit", []).is_empty():
		return markers.exit[0]
	var best := b.pos
	var best_d := -1.0
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			if Scavengers.edge_dist(s, c) != 0 or not s.grid.is_walkable(c):
				continue
			var d := Encounter._dist_to_squad(s, c)
			if d > best_d:
				best_d = d
				best = c
	return best


## The exit lane the dangers overlay marks: the gate and the ground in front of it.
static func exit_cells(s: GameState, u: Unit) -> Array:
	var gate: Vector2i = u.status.exit
	var out: Array = []
	for dy in range(-EXIT_REACH, EXIT_REACH + 1):
		for dx in range(-EXIT_REACH, EXIT_REACH + 1):
			var c := gate + Vector2i(dx, dy)
			if s.grid.in_bounds(c) and s.grid.is_walkable(c):
				out.append(c)
	return out


# --- phases --------------------------------------------------------------------------------

## HP at which phase 2 and phase 3 start.
static func gates(u: Unit) -> Array[int]:
	return [ceili(u.max_hp * 2 / 3.0), ceili(u.max_hp / 3.0)]


## Caps a hit so it stops at the next phase gate.
static func clamp_damage(u: Unit, amount: int) -> int:
	var phase := int(u.status.get("boss_phase", 1))
	var g := gates(u)
	if phase <= g.size() and u.hp > g[phase - 1]:
		return mini(amount, u.hp - g[phase - 1])
	return amount


static func on_damaged(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	var g := gates(u)
	if phase > g.size() or u.hp > g[phase - 1]:
		if phase == 2 and not u.status.hoard.is_empty():
			_shake_loose(s, u)
		return
	if phase == 1:
		_enter_haul(s, u)
	else:
		_enter_burn(s, u, "The Broker is cornered and torches the loot!")


## Phase 2: every soldier loses their best item to his hoard and the exit lane is marked.
static func _enter_haul(s: GameState, u: Unit) -> void:
	u.status.boss_phase = 2
	u.mobility = MOBILITY[2]
	u.cooldowns.clear()
	u.display_name = "The Broker, Loaded"
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 2, "boss": u.kind,
		"hp": u.hp, "max_hp": u.max_hp, "text": "The Broker takes the squad's best gear and runs!"})
	for t in s.living(Types.Team.PLAYER):
		var item := Scavengers._best_item(t)
		if item == "":
			continue
		var stolen: Array = t.status.get("stolen", [])
		stolen.append(item)
		t.status["stolen"] = stolen
		u.status.hoard.append({"unit": t.id, "item": item})
		s.emit({"type": "stolen", "unit": t.id, "thief": u.id, "item": item})
	s.emit({"type": "exit_marked", "unit": u.id, "cell": u.status.exit})


## A hit knocks the oldest item in his hoard loose, back to its owner.
static func _shake_loose(s: GameState, u: Unit) -> void:
	var loot: Dictionary = u.status.hoard.pop_front()
	var t := s.get_unit(int(loot.unit))
	if t == null:
		return
	var stolen: Array = t.status.get("stolen", [])
	stolen.erase(loot.item)
	t.status["stolen"] = stolen
	s.emit({"type": "recovered", "unit": t.id, "item": loot.item, "from": u.id})


## Phase 3 (or the exit reached): the hoard burns for good.
static func _enter_burn(s: GameState, u: Unit, text: String) -> void:
	u.status.boss_phase = 3
	u.mobility = MOBILITY[3]
	u.cooldowns.clear()
	u.cooldowns["firebomb"] = 1
	u.display_name = "The Broker, Cornered"
	var burned := 0
	for loot in u.status.hoard:
		var t := s.get_unit(int(loot.unit))
		if t == null:
			continue
		var gone: Array = t.status.get("burned", [])
		gone.append(loot.item)
		t.status["burned"] = gone
		burned += 1
	var ids: Array = u.status.hoard.map(func(l: Dictionary) -> int: return int(l.unit))
	u.status.hoard = []
	s.emit({"type": "boss_phase", "unit": u.id, "phase": 3, "boss": u.kind,
		"hp": u.hp, "max_hp": u.max_hp, "text": text})
	if burned > 0:
		s.emit({"type": "burned", "unit": u.id, "units": ids, "count": burned})


# --- his turn --------------------------------------------------------------------------------

static func take_turn(s: GameState, u: Unit) -> void:
	var phase := int(u.status.get("boss_phase", 1))
	for step in 4:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var hostiles := EnemyAI._hostiles(s, u)
		if hostiles.is_empty():
			return
		var went := false
		phase = int(u.status.get("boss_phase", 1))
		match phase:
			1: went = _haggle(s, u, hostiles)
			2: went = _haul(s, u, hostiles)
			_: went = _burn(s, u, hostiles)
		if not went:
			return


## Phase 1: cover and fire. The Cutters do the stealing.
static func _haggle(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	return _act(s, EnemyBehaviours.cover_shooter(s, u, hostiles))


## Phase 2: move toward the exit lane, then take a shot if he has one. Reaching the lane burns the hoard.
static func _haul(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	var exit: Vector2i = u.status.exit
	if EnemyAI._cheb(u.pos, exit) <= EXIT_REACH:
		_enter_burn(s, u, "The Broker reaches the gate and torches the loot!")
		return false
	if u.actions_left >= 2:
		var step := _toward(s, u, exit)
		if step != u.pos and _act(s, EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": step})):
			return true
	var shot := EnemyAI._best_shot(s, u)
	if not shot.is_empty():
		return _act(s, shot.action)
	var step := _toward(s, u, exit)
	return step != u.pos and _act(s, EnemyAI._check(s, {"type": Types.MOVE, "unit": u.id, "to": step}))


## Phase 3: firebomb the biggest cluster, otherwise club whoever is nearest.
static func _burn(s: GameState, u: Unit, hostiles: Array[Unit]) -> bool:
	if int(u.cooldowns.get("firebomb", 0)) <= 0:
		var bomb := bomb_cell(s, u, hostiles)
		if bomb.hits >= 1 and _act(s, EnemyAI._check(s, {"type": Types.ABILITY, "unit": u.id, "ability": "firebomb", "cell": bomb.cell})):
			return true
	return _act(s, EnemyBehaviours.rush(s, u, hostiles, "slam"))


## The 3x3 within firebomb range that catches the most soldiers and the fewest of his own. {cell, hits}.
static func bomb_cell(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	var best := {"cell": u.pos, "hits": 0}
	var best_score := 0.0
	for h in hostiles:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = h.pos + Vector2i(dx, dy)
				if not s.grid.in_bounds(c) or EnemyAI._cheb(c, u.pos) > EnemyRoster.SATCHEL_RANGE \
						or EnemyAI._cheb(c, u.pos) <= 1 or not Combat.can_see(s, u.pos, c):
					continue
				var hits := 0
				var score := 0.0
				for o in s.living():
					if EnemyAI._cheb(o.pos, c) <= 1:
						var foe := u.is_enemy_of(o)
						hits += 1 if foe else -1
						score += 1.0 if foe else -1.5
				if score > best_score:
					best_score = score
					best = {"cell": c, "hits": hits}
	return best


## The reachable cell that gets him closest to `target` along walkable ground.
static func _toward(s: GameState, u: Unit, target: Vector2i) -> Vector2i:
	var dist := _walk_dist(s, target)
	var reach := Rules.move_range(s, u)
	var best := u.pos
	var best_d: int = dist.get(u.pos, 999)
	for c in reach:
		var d: int = dist.get(c, 999)
		if d < best_d or (d == best_d and best != u.pos and int(reach[c]) < int(reach[best])):
			best_d = d
			best = c
	return best


## Steps to `target` from every walkable cell (8-way, ignoring units).
static func _walk_dist(s: GameState, target: Vector2i) -> Dictionary:
	var dist := {target: 0}
	var frontier: Array[Vector2i] = [target]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for f in frontier:
			for d in Grid.DIRS8:
				var n: Vector2i = f + d
				if dist.has(n) or not s.grid.in_bounds(n) or not s.grid.is_walkable(n):
					continue
				dist[n] = int(dist[f]) + 1
				next.append(n)
		frontier = next
	return dist


static func _act(s: GameState, a: Dictionary) -> bool:
	return not a.is_empty() and EnemyBehaviours._try(s, a)
