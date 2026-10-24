extends TestCase
## EnemyAI tests. They assert behaviour that holds both with the Combat stub (abilities
## rejected, distance-only LOS) and with a full Combat implementation.


func _open_rows(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _enemy(s: GameState, kind: String, at: Vector2i) -> Unit:
	return s.add_unit(UnitData.make(kind, Types.Team.ENEMY), at)


func _events(s: GameState, type: String, unit_id: int = -1) -> Array:
	return s.log.filter(func(e): return e.type == type and (unit_id == -1 or e.get("unit", -1) == unit_id))


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _nearest_soldier_dist(s: GameState, u: Unit) -> float:
	var best := INF
	for t in s.living(Types.Team.PLAYER):
		best = minf(best, Vector2(u.pos).distance_to(Vector2(t.pos)))
	return best


## A soldier sealed in a walled pocket far to the left: nothing can see or reach it.
func _isolated_map() -> GameState:
	var rows := PackedStringArray([
		"..#.............................",
		"..#.............................",
		"..#.............................",
	])
	var s := make_blank(rows)
	_soldier(s, "trooper", Vector2i(0, 1))
	return s


func test_dormant_enemy_does_not_attack_or_advance() -> void:
	for seed in [1, 2, 3, 4, 5, 6]:
		var s := _isolated_map()
		s.rng.seed = seed
		var e := _enemy(s, "runner", Vector2i(25, 1))
		e.actions_left = 2
		EnemyAI.take_turn(s, e)
		assert_true(not EnemyAI.is_alerted(e), "still dormant (seed %d)" % seed)
		assert_true(_cheb(e.pos, Vector2i(25, 1)) <= 2, "at most a small shuffle (seed %d)" % seed)
		assert_eq(_events(s, "shot").size() + _events(s, "ability").size(), 0, "no attacks")
		assert_eq(_events(s, "alerted").size(), 0, "no alert event")
		assert_eq(_events(s, "rejected").size(), 0, "no rejected actions")


func test_enemy_alerts_when_soldier_in_sight() -> void:
	var s := make_blank(_open_rows(10, 10))
	_soldier(s, "trooper", Vector2i(1, 1))
	var e := _enemy(s, "runner", Vector2i(4, 4))
	e.actions_left = 2
	EnemyAI.take_turn(s, e)
	assert_true(EnemyAI.is_alerted(e), "alerted")
	assert_eq(_events(s, "alerted", e.id).size(), 1, "one alerted event")
	assert_true(e.actions_left < 2 or s.phase == Types.Phase.ENDED, "acted after alert")
	# A second turn does not re-emit.
	e.actions_left = 2
	EnemyAI.take_turn(s, e)
	assert_eq(_events(s, "alerted", e.id).size(), 1, "alerted emitted only once")


func test_enemy_alerts_when_damaged() -> void:
	var s := _isolated_map()
	var e := _enemy(s, "spitter", Vector2i(25, 1))
	Rules.deal_damage(s, e, 1, null)
	e.actions_left = 2
	EnemyAI.take_turn(s, e)
	assert_true(EnemyAI.is_alerted(e), "damage alerts")


func test_pod_alert_spreads_within_radius_only() -> void:
	var s := _isolated_map()
	var a := _enemy(s, "runner", Vector2i(18, 1))
	var b := _enemy(s, "spitter", Vector2i(24, 1))   # 6 from a
	var c := _enemy(s, "runner", Vector2i(31, 1))    # 7 from b, 13 from a
	Rules.deal_damage(s, a, 1, null)
	a.actions_left = 2
	EnemyAI.take_turn(s, a)
	assert_true(EnemyAI.is_alerted(a), "a alerted")
	assert_true(EnemyAI.is_alerted(b), "b alerted by pod")
	assert_true(not EnemyAI.is_alerted(c), "c too far")
	assert_eq(_events(s, "alerted").size(), 2, "two alerted events")


func test_pod_alert_at_turn_start() -> void:
	var s := _isolated_map()
	var a := _enemy(s, "runner", Vector2i(20, 1))
	var b := _enemy(s, "runner", Vector2i(24, 1))
	a.status["alerted"] = true   # e.g. alerted earlier, then walked near b
	b.actions_left = 2
	EnemyAI.take_turn(s, b)
	assert_true(EnemyAI.is_alerted(b), "b wakes next to an alerted ally")


func test_runner_advances_toward_squad() -> void:
	var s := make_state(["runner"])
	Rules.start_mission(s)
	var r := s.living(Types.Team.ENEMY)[0]
	r.status["alerted"] = true
	r.actions_left = 2
	var before := _nearest_soldier_dist(s, r)
	EnemyAI.take_turn(s, r)
	assert_true(_nearest_soldier_dist(s, r) < before - 3.0, "runner closed distance (%f -> %f)" % [before, _nearest_soldier_dist(s, r)])
	assert_eq(_events(s, "rejected").size(), 0, "no rejected actions")


func test_runner_reaches_and_attacks() -> void:
	var s := make_blank(_open_rows(12, 12))
	var t := _soldier(s, "trooper", Vector2i(2, 2))
	var r := _enemy(s, "runner", Vector2i(7, 7))
	r.status["alerted"] = true
	r.actions_left = 2
	EnemyAI.take_turn(s, r)
	assert_eq(_cheb(r.pos, t.pos), 1, "runner ends adjacent")
	var attacks := _events(s, "shot", r.id).size() + _events(s, "ability", r.id).size()
	assert_true(attacks >= 1 or s.phase == Types.Phase.ENDED, "runner attacked after closing in")


func test_spitter_keeps_distance() -> void:
	var s := make_blank(_open_rows(16, 16))
	_soldier(s, "trooper", Vector2i(8, 8))
	var sp := _enemy(s, "spitter", Vector2i(8, 10))
	sp.status["alerted"] = true
	sp.actions_left = 2
	EnemyAI.take_turn(s, sp)
	assert_true(_nearest_soldier_dist(s, sp) >= 4.0, "spitter backed off to %f" % _nearest_soldier_dist(s, sp))
	assert_eq(_events(s, "rejected").size(), 0, "no rejected actions")


func test_spitter_approaches_from_far() -> void:
	var s := make_blank(_open_rows(16, 3))
	_soldier(s, "trooper", Vector2i(0, 1))
	var sp := _enemy(s, "spitter", Vector2i(15, 1))
	sp.status["alerted"] = true
	sp.actions_left = 2
	EnemyAI.take_turn(s, sp)
	assert_true(sp.pos.x < 15, "spitter moved closer")
	assert_true(_nearest_soldier_dist(s, sp) >= 4.0, "but not too close")


func test_lapsed_soldier_acts_without_hanging() -> void:
	for seed in range(1, 21):
		var s := make_state(["runner", "spitter"], seed)
		Rules.start_mission(s)
		var u := s.living(Types.Team.PLAYER)[0]
		u.status["lapsed"] = true
		u.ai_controlled = true
		u.actions_left = 2
		var start := u.pos
		EnemyAI.take_turn(s, u)
		assert_eq(_events(s, "rejected").size(), 0, "no rejected actions (seed %d)" % seed)
		var acted := u.pos != start or _events(s, "shot", u.id).size() > 0
		assert_true(acted or not u.is_alive(), "lapsed soldier acted (seed %d)" % seed)


func test_lapsed_soldier_boxed_in_gives_up() -> void:
	var s := make_blank(PackedStringArray(["###", "#.#", "###"]))
	var u := _soldier(s, "medic", Vector2i(1, 1))
	_enemy(s, "runner", Vector2i(0, 0))   # inside a wall cell; just keeps the mission alive
	u.status["lapsed"] = true
	u.ai_controlled = true
	u.actions_left = 2
	EnemyAI.take_turn(s, u)
	assert_eq(_events(s, "rejected").size(), 0, "no rejected actions")


func test_lapsed_soldier_in_team_phase() -> void:
	var s := make_state(["runner"], 77)
	Rules.start_mission(s)
	var u := s.living(Types.Team.PLAYER)[1]
	u.status["lapsed"] = true
	u.ai_controlled = true
	for p in s.players:
		Rules.set_ready(s, p, true)
	assert_true(s.turn >= 2 or s.phase == Types.Phase.ENDED, "turn advanced with a lapsed soldier")
	# Lapsed during the previous team phase, so it recovers at the start of this one.
	assert_true(s.phase == Types.Phase.ENDED or not u.ai_controlled, "lapsed soldier recovered")
	assert_eq(_events(s, "rejected").size(), 0, "no rejected actions")


func test_turned_soldier_uses_generic_ai() -> void:
	var s := make_blank(_open_rows(16, 3))
	_soldier(s, "trooper", Vector2i(0, 1))
	var turned := s.add_unit(UnitData.make("breacher", Types.Team.ENEMY), Vector2i(15, 1))
	turned.actions_left = 2
	EnemyAI.take_turn(s, turned)
	var acted := turned.pos.x < 15 or _events(s, "shot", turned.id).size() > 0
	assert_true(acted, "turned soldier is active without alert")
	assert_eq(_events(s, "rejected").size(), 0, "no rejected actions")


## 40 rounds on the mission map with 6 enemies while the squad only readies up.
func test_soak_40_rounds_six_enemies() -> void:
	var s := make_state(["runner", "runner", "spitter", "spitter", "runner", "spitter"], 4242)
	# The map has fewer enemy spawns than enemies; spread stacked ones onto free cells.
	var taken := {}
	for u in s.units:
		if taken.has(u.pos):
			for c in s.grid.reachable(u.pos, 4, taken):
				if not taken.has(c):
					u.pos = c
					break
		taken[u.pos] = true
		# Durable squad, so the soak runs the full 40 rounds instead of ending in a quick defeat.
		if u.team == Types.Team.PLAYER:
			u.max_hp = 10000
			u.hp = 10000
	Rules.start_mission(s)
	var started := Time.get_ticks_msec()
	var rounds := 0
	for i in 40:
		if s.phase == Types.Phase.ENDED:
			break
		for p in s.players:
			Rules.set_ready(s, p, true)
		rounds += 1
		_assert_consistent(s, "round %d" % rounds)
	assert_true(rounds > 1, "rounds ran")
	assert_eq(_events(s, "rejected").size(), 0, "AI never applied a rejected action")
	assert_true(Time.get_ticks_msec() - started < 20000, "soak finished in reasonable time")


func _assert_consistent(s: GameState, ctx: String) -> void:
	var cells := {}
	for u in s.units:
		assert_true(u.hp >= 0 and u.hp <= u.max_hp, "%s: hp in range for %d" % [ctx, u.id])
		if not u.is_alive():
			continue
		assert_true(s.grid.is_walkable(u.pos), "%s: unit %d on walkable cell" % [ctx, u.id])
		assert_true(not cells.has(u.pos), "%s: unit %d shares cell %s" % [ctx, u.id, u.pos])
		cells[u.pos] = true
		if u.team == Types.Team.ENEMY:
			assert_eq(u.actions_left, 0, "%s: enemy %d done" % [ctx, u.id])
	if s.phase != Types.Phase.ENDED:
		assert_eq(s.phase, Types.Phase.TEAM, ctx + ": back in team phase")


## A soldier in the middle of a wide roof: the only way up is the ladder at the far end. A runner
## below has to go round to the ladder, not stand at the foot of the wall.
func test_runner_climbs_to_a_soldier_on_a_roof() -> void:
	var rows := PackedStringArray([
		"................",
		"...^^^^^^^^/....",
		"...^^^^^^^^.....",
		"...^^^^^^^^.....",
		"................",
		"................",
		"................",
	])
	var s := make_blank(rows)
	var sol := _soldier(s, "trooper", Vector2i(5, 2))
	sol.max_hp = 1000
	sol.hp = 1000
	var e := _enemy(s, "runner", Vector2i(5, 6))
	e.status["alerted"] = true
	var reached := false
	for turn in 4:
		e.actions_left = 2
		EnemyAI.take_turn(s, e)
		if _cheb(e.pos, sol.pos) == 1 or not _events(s, "ability", e.id).is_empty():
			reached = true
			break
	assert_true(reached, "the runner reached the roof by the ladder (ended at %s)" % e.pos)
	assert_eq(s.grid.level(e.pos), 1, "it is up on the roof")


## A runner that can't reach anyone this turn ends its move behind cover rather than in the open,
## when that costs it no ground.
func test_runner_approaches_through_cover() -> void:
	var rows := _open_rows(32, 9)
	rows[4] = rows[4].substr(0, 22) + "#" + rows[4].substr(23)
	var s := make_blank(rows)
	var sol := _soldier(s, "trooper", Vector2i(15, 5))
	var e := _enemy(s, "runner", Vector2i(30, 5))
	e.status["alerted"] = true
	e.actions_left = 2
	var action := EnemyAI._choose(s, e)
	assert_eq(action.get("type"), Types.MOVE, "it advances")
	var to: Vector2i = action.get("to", e.pos)
	assert_true(to.x <= 24, "it still closes in (to %s)" % to)
	assert_true(not Combat.can_see(s, sol.pos, to), "behind the wall, out of the soldier's sight (to %s)" % to)
