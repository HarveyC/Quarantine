extends TestCase
## Parting blow: stepping out of a melee fighter's reach gives it a free strike. Disengage avoids it.

const OPEN := [
	"............",
	"............",
	"............",
	"............",
	"............",
	"............",
]


func _state() -> GameState:
	var s := make_blank(PackedStringArray(OPEN), 77)
	s.turn = 1
	s.phase = Types.Phase.TEAM
	return s


func _add(s: GameState, kind: String, team: int, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
	else:
		u.status["alerted"] = true
	Vision.refresh(s)
	return u


func _blows(s: GameState, act: Dictionary) -> Array:
	var events: Array = []
	s.event.connect(func(ev): events.append(ev))
	Rules.apply(s, act)
	return events.filter(func(e): return e.type == "ability" and e.get("parting", false))


func test_leaving_a_runner_provokes_one_blow() -> void:
	var s := _state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	var blows := _blows(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(0, 2)})
	assert_eq(blows.size(), 1, "one free strike for leaving reach")


func test_staying_in_reach_is_free() -> void:
	var s := _state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	var blows := _blows(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(3, 3)})
	assert_eq(blows.size(), 0, "still touching, so no blow")


func test_disengage_provokes_nothing_and_is_short() -> void:
	var s := _state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	assert_true(Rules.validate(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(0, 2), "careful": true}) != "", "3 tiles is too far")
	var blows := _blows(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(1, 2), "careful": true})
	assert_eq(blows.size(), 0, "no blow when disengaging")
	assert_eq(t.pos, Vector2i(1, 2), "moved")


func test_one_blow_per_fighter_per_phase() -> void:
	var s := _state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	assert_eq(_blows(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(2, 2)}).size(), 1, "first step away")
	t.pos = Vector2i(5, 2)
	assert_eq(_blows(s, {"type": Types.MOVE, "unit": t.id, "to": Vector2i(8, 2)}).size(), 0, "already swung this phase")


func test_gunners_do_not_swing_but_reapers_do() -> void:
	var s := _state()
	var runner := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	_add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	assert_true(not PartingBlow.can_swing(s, s.units[1]), "a Trooper has no blow")
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(5, 2))
	assert_true(PartingBlow.can_swing(s, r), "a Reaper does")
	runner.actions_left = 2
	var blows := _blows(s, {"type": Types.MOVE, "unit": runner.id, "to": Vector2i(4, 5)})
	assert_true(blows.size() >= 1, "the Reaper strikes the fleeing Runner")


func test_enemy_blow_is_full_claw_damage() -> void:
	var s := _state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	t.hp = 99
	t.max_hp = 99
	var b := _add(s, "brute", Types.Team.ENEMY, Vector2i(4, 2))
	s.rng.seed = 5
	var worst := 0
	for i in 20:
		t.hp = 99
		b.status.erase("pb_phase")
		t.pos = Vector2i(3, 2)
		PartingBlow.resolve(s, t, [b])
		worst = maxi(worst, 99 - t.hp)
	assert_true(worst >= b.damage.y - 1, "a Brute's blow can reach its normal claw damage")
