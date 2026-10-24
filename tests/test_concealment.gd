extends TestCase
## Squad Concealment (stealth/concealment.gd): which fights start concealed, what breaks it,
## patrols, the ambush bonus, and that it all stays in the snapshot.


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, at: Vector2i, kind := "trooper") -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	u.actions_left = 2
	return s.add_unit(u, at)


func _enemy(s: GameState, at: Vector2i, kind := "runner") -> Unit:
	return s.add_unit(EnemyRoster.make(kind), at)


## A long open strip with the squad concealed.
func _concealed(w := 24, h := 5) -> GameState:
	var s := make_blank(_open(w, h))
	s.phase = Types.Phase.TEAM
	s.turn = 1
	return s


func _arm(s: GameState) -> void:
	Encounter.setup(s, {"concealed": true})
	Vision.refresh(s)


func _types(s: GameState) -> Array:
	return s.log.map(func(e: Dictionary) -> String: return str(e.type))


func test_concealment_is_a_per_mission_option() -> void:
	assert_true(FightBuilder.starts_concealed("skirmish", "extract"), "an extract starts concealed")
	assert_true(FightBuilder.starts_concealed("nest", "purge"), "so does a nest")
	assert_true(not FightBuilder.starts_concealed("skirmish", "hold"), "holding the beacon starts detected")
	assert_true(not FightBuilder.starts_concealed("ambush", "extract"), "an ambush starts detected")
	assert_true(not FightBuilder.starts_concealed("boss", "boss"), "bosses start detected")
	assert_true(not FightBuilder.starts_concealed("skirmish", "rescue", {"detected": true}), "an event can force it")
	var built := FightBuilder.build({"act": 1, "node": "skirmish", "objective": "rescue", "seed": 4})
	assert_true(built.encounter.concealed, "FightBuilder writes it into the encounter")
	assert_true(not FightBuilder.build({"act": 2, "node": "boss", "objective": "boss", "seed": 4}).encounter.concealed, "boss")
	var s := _concealed()
	Encounter.setup(s, {})
	assert_true(not Concealment.active(s) and not Concealment.used(s), "no encounter, no concealment")


func test_quick_play_starts_concealed() -> void:
	var s := MatchConfig.build(MatchConfig.make(1, 77))
	assert_true(Concealment.active(s), "a quick match starts concealed")
	for e in s.living(Types.Team.ENEMY):
		assert_true(not EnemyAI.is_alerted(e), "%s is dormant" % e.display_name)


func test_walking_into_detection_breaks_it_mid_move() -> void:
	var s := _concealed()
	var u := _soldier(s, Vector2i(5, 2))
	var e := _enemy(s, Vector2i(14, 2))
	_arm(s)
	assert_true(Concealment.active(s), "concealed at the start")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": u.id, "to": Vector2i(8, 2)}), "a move to 6 tiles away")
	assert_true(Concealment.active(s), "6 tiles from a sleeping Runner: still unseen")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": u.id, "to": Vector2i(12, 2)}), "walk right up to it")
	assert_true(not Concealment.active(s), "spotted on the way")
	assert_eq(u.pos, Vector2i(12, 2), "the walk still finishes")
	assert_true(EnemyAI.is_alerted(e), "the spotter wakes")
	var lost: Array = s.log.filter(func(ev: Dictionary) -> bool: return ev.type == "concealment_lost")
	assert_eq(lost.size(), 1, "one concealment_lost")
	assert_eq(lost[0].cause, "spotted", "cause")
	assert_eq(lost[0].unit, e.id, "who saw us")
	assert_eq(lost[0].by, u.id, "who was seen")
	# The walk up to the tile where they were seen plays first, so the alarm lands on time.
	var types := _types(s)
	var at := types.find("concealment_lost")
	assert_eq(types[at - 1], "move", "the move segment comes right before the alarm")
	var seg: Dictionary = s.log[at - 1]
	assert_true(e.pos.distance_to(seg.path[-1]) <= Concealment.DETECT_RADIUS, "segment ends where they were spotted")
	assert_eq(Concealment.lost_turn(s), 1, "lost on turn 1")


func test_sleeping_infected_only_spot_you_close_up() -> void:
	var s := _concealed()
	_soldier(s, Vector2i(2, 2))
	var e := _enemy(s, Vector2i(9, 2))   # 7 tiles: in sight range, outside detection
	_arm(s)
	e.actions_left = 2
	EnemyAI.take_turn(s, e)
	if Concealment.active(s):
		assert_true(not EnemyAI.is_alerted(e), "a dormant Runner 7 tiles off doesn't notice the squad")
	else:
		# Its patrol walked it into range: that's being spotted, fairly.
		assert_true(_types(s).has("move"), "only by patrolling closer")
	var s2 := make_blank(_open(24, 5))
	s2.phase = Types.Phase.ENEMY
	_soldier(s2, Vector2i(2, 2))
	var e2 := _enemy(s2, Vector2i(9, 2))
	e2.actions_left = 2
	EnemyAI.take_turn(s2, e2)
	assert_true(EnemyAI.is_alerted(e2), "without concealment the same Runner wakes")


func test_any_shot_gives_the_squad_away() -> void:
	var s := _concealed()
	var u := _soldier(s, Vector2i(2, 2), "marksman")
	var e := _enemy(s, Vector2i(10, 2), "fallen")
	var other := _enemy(s, Vector2i(22, 4))
	_arm(s)
	var odds := Combat.hit_chance(s, u, e)
	var labels: Array = odds.breakdown.map(func(t: Array) -> String: return t[0])
	assert_true(labels.has("Unaware"), "a dormant target is caught unaware")
	assert_true(Rules.apply(s, {"type": Types.SHOOT, "unit": u.id, "target": e.id}), "shoot")
	assert_true(not Concealment.active(s), "the shot breaks concealment")
	assert_eq(s.encounter.concealment.cause, "fired", "cause")
	assert_true(EnemyAI.is_alerted(e) or not e.is_alive(), "the target wakes")
	assert_true(not EnemyAI.is_alerted(other), "a pod far away sleeps on")
	odds = Combat.hit_chance(s, u, other)
	labels = odds.breakdown.map(func(t: Array) -> String: return t[0])
	assert_true(not labels.has("Unaware"), "no bonus once the squad is detected")


func test_overwatch_ambush_bonus_on_the_reveal_turn() -> void:
	var s := _concealed()
	var u := _soldier(s, Vector2i(2, 2))
	var e := _enemy(s, Vector2i(10, 2))
	_arm(s)
	Concealment.lose(s, "fired", e, u)
	s.phase = Types.Phase.ENEMY
	var labels: Array = Combat.hit_chance(s, u, e, u.pos, true).breakdown.map(func(t: Array) -> String: return t[0])
	assert_true(labels.has("Ambush shot"), "reaction shots in the reveal turn's enemy phase")
	s.turn = 2
	labels = Combat.hit_chance(s, u, e, u.pos, true).breakdown.map(func(t: Array) -> String: return t[0])
	assert_true(not labels.has("Ambush shot"), "only that turn")


func test_explosions_and_damage_break_it() -> void:
	var s := _concealed()
	_soldier(s, Vector2i(2, 2))
	_enemy(s, Vector2i(20, 2))
	_arm(s)
	Destruction.noise(s, Vector2i(5, 2))
	assert_true(not Concealment.active(s), "a blast is heard")
	assert_eq(s.encounter.concealment.cause, "explosion", "cause")
	var s2 := _concealed()
	var u2 := _soldier(s2, Vector2i(2, 2))
	var e2 := _enemy(s2, Vector2i(20, 2))
	_arm(s2)
	Rules.deal_damage(s2, u2, 1, e2)
	assert_eq(s2.encounter.concealment.cause, "attacked", "an enemy hitting us")


func test_patrols_are_deterministic_and_stay_near_home() -> void:
	var a := _patrolled(5)
	var b := _patrolled(5)
	assert_eq(a.map(func(u: Unit) -> Vector2i: return u.pos), b.map(func(u: Unit) -> Vector2i: return u.pos), "same seed, same patrol")
	var moved := false
	for u in a:
		assert_true(Vector2(u.pos).distance_to(Vector2(u.status.patrol_home)) <= Concealment.PATROL_RADIUS, "stays near home")
		moved = moved or u.pos != u.status.patrol_home
	assert_true(moved, "somebody walked")


func _patrolled(seed: int) -> Array:
	var s := make_blank(_open(40, 9), seed)
	s.phase = Types.Phase.ENEMY
	_soldier(s, Vector2i(1, 4))
	for c in [Vector2i(28, 2), Vector2i(30, 6), Vector2i(34, 4)]:
		_enemy(s, c)
	_arm(s)
	for turn in 6:
		for e in s.living(Types.Team.ENEMY):
			e.actions_left = 2
			EnemyAI.take_turn(s, e)
	assert_true(Concealment.active(s), "the squad is far away: still concealed")
	return s.living(Types.Team.ENEMY)


func test_spawns_arrive_dormant_while_concealed() -> void:
	var s := _concealed()
	_soldier(s, Vector2i(2, 2))
	_arm(s)
	var u := Encounter.spawn(s, "runner", Vector2i(20, 2))
	assert_true(not EnemyAI.is_alerted(u), "reinforcements don't know where the squad is either")
	assert_true(Concealment.active(s), "and their arrival doesn't break it")


func test_echo_fights_start_detected() -> void:
	var s := _concealed()
	_soldier(s, Vector2i(2, 2))
	s.grid.enemy_spawns = [Vector2i(20, 2)]
	_arm(s)
	Story.setup_echo(s, {"kind": "trooper", "key": "e1", "name": "Vance"})
	assert_true(not Concealment.active(s), "an Echo knows where its old squad is")


func test_concealment_survives_a_snapshot() -> void:
	var s := _concealed()
	_soldier(s, Vector2i(2, 2))
	_enemy(s, Vector2i(20, 2))
	_arm(s)
	var copy := GameState.from_dict(s.to_dict())
	assert_true(Concealment.active(copy), "resync keeps concealment")
	assert_eq(copy.checksum(), s.checksum(), "same checksum")


func test_danger_cells_mark_where_you_would_be_seen() -> void:
	var s := _concealed()
	_soldier(s, Vector2i(2, 2))
	var e := _enemy(s, Vector2i(12, 2))
	_arm(s)
	var cells := Concealment.danger_cells(s, [e])
	assert_true(cells.has(Vector2i(9, 2)), "3 tiles off is red")
	assert_true(not cells.has(Vector2i(6, 2)), "6 tiles off is safe")
	assert_true(Concealment.danger_cells(s, []).is_empty(), "nothing in sight, nothing marked")


func test_smoke_hides_you_from_dormant_enemies() -> void:
	var s := _concealed()
	var sol := _soldier(s, Vector2i(9, 2))
	var e := _enemy(s, Vector2i(12, 2))
	_arm(s)
	assert_true(Concealment.detects(s, e, sol), "3 tiles off in the open: spotted")
	Hazards.add(s, [sol.pos], "smoke", 2)
	assert_true(not Concealment.detects(s, e, sol), "in smoke: unseen")
	assert_true(not Concealment.danger_cells(s, [e]).has(sol.pos), "smoke tiles are not red")


func test_sight_fields_follow_line_of_sight_per_enemy() -> void:
	var s := make_blank(PackedStringArray([
		"..............",
		"......#.......",
		"..............",
	]))
	s.phase = Types.Phase.TEAM
	s.turn = 1
	_soldier(s, Vector2i(0, 0))
	var e := _enemy(s, Vector2i(9, 1))
	var awake := _enemy(s, Vector2i(2, 2))
	_arm(s)
	EnemyAI.alert(s, awake)
	var f := Concealment.sight_fields(s, [e, awake])
	assert_true(f.has(e.id) and not f.has(awake.id), "only dormant enemies watch")
	var cells: Dictionary = f[e.id].cells
	assert_true(cells.has(Vector2i(7, 1)), "open tile in range")
	assert_true(not cells.has(Vector2i(5, 1)), "the wall shadows the tile behind it")
	assert_true(not cells.has(Vector2i(6, 1)), "walls themselves are not ground")
	assert_eq(f[e.id].at, e.pos, "field remembers its watcher")
