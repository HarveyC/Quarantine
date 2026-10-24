extends TestCase
## Objective win/lose rules on generated maps.

const SQUAD := [
	{"kind": "trooper", "player": 0}, {"kind": "marksman", "player": 0},
	{"kind": "medic", "player": 1}, {"kind": "breacher", "player": 1},
]


func _mission(objective: String, enemies: Array[String] = ["runner"], seed: int = 3) -> GameState:
	var grid := MapGen.generate({"biome": "wall", "objective": objective, "seed": seed})
	var s := Rules.new_mission_on_grid(grid, SQUAD, enemies, seed)
	Rules.start_mission(s)
	return s


## Ends the squad's turn and the enemy phase without the AI moving anyone (enemies parked dead-still).
func _end_round(s: GameState) -> void:
	for u in s.living(Types.Team.ENEMY):
		u.status["alerted"] = false
		u.mobility = 0
	for p in s.players:
		Rules.set_ready(s, p, true)


## Puts `u` on `cell`, clearing whoever stands there.
func _place(s: GameState, u: Unit, cell: Vector2i) -> void:
	var other := s.unit_at(cell)
	if other != null and other != u:
		other.pos = Vector2i(-50, -50)
	u.pos = cell


func test_kills_alone_do_not_win_extract_or_hold() -> void:
	for o in ["extract", "hold"]:
		var s := _mission(o)
		for u in s.living(Types.Team.ENEMY):
			u.hp = 0
		Rules.check_end(s)
		assert_eq(s.result, Types.Result.NONE, o + " goes on")
	var sk := _mission("skirmish")
	for u in sk.living(Types.Team.ENEMY):
		u.hp = 0
	Rules.check_end(sk)
	assert_eq(sk.result, Types.Result.VICTORY, "skirmish wins on kills")


func test_extract_wins_when_everyone_is_on_the_pad() -> void:
	var s := _mission("extract")
	var evac := s.grid.marker("evac")
	var squad := Objectives.soldiers(s)
	for i in squad.size():
		_place(s, squad[i], evac[i])
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "extracted")
	assert_true(Objectives.bonus_met(s), "nobody left behind")


func test_extract_dropship_leaves_after_turn_limit() -> void:
	var s := _mission("extract")
	var squad := Objectives.soldiers(s)
	_place(s, squad[0], s.grid.marker("evac")[0])
	s.turn = Objectives.EXTRACT_TURNS
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "one made it")
	assert_eq(Objectives.soldiers(s).size(), 1, "the rest are lost")
	assert_true(not Objectives.bonus_met(s), "bonus needs everyone")


func test_hold_counts_rounds_and_is_lost_to_an_uncontested_zone() -> void:
	var s := _mission("hold")
	var zone := s.grid.marker("beacon")
	_place(s, Objectives.soldiers(s)[0], zone[0])
	for i in Objectives.HOLD_TURNS - 1:
		_end_round(s)
		assert_eq(s.result, Types.Result.NONE, "still holding after %d" % (i + 1))
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "held")
	assert_true(Objectives.bonus_met(s), "never contested")

	var lost := _mission("hold")
	_place(lost, lost.living(Types.Team.ENEMY)[0], lost.grid.marker("beacon")[4])
	_end_round(lost)
	assert_eq(lost.result, Types.Result.DEFEAT, "enemies own the beacon")


func test_rescue_civilians_follow_and_reach_the_exit() -> void:
	var s := _mission("rescue")
	var civs := s.living(Types.Team.PLAYER).filter(func(u: Unit) -> bool: return Objectives.is_civilian(u))
	assert_eq(civs.size(), s.grid.marker("civilian").size(), "civilians spawned on their markers")
	assert_true(civs.all(func(c: Unit) -> bool: return c.owner_player == -1 and not c.ai_controlled), "nobody commands them")
	assert_eq(s.controllable_units(0).size() + s.controllable_units(1).size(), 4, "squad unchanged")
	# A soldier next to each civilian: they follow towards it.
	var c: Unit = civs[0]
	var start := c.pos
	var sol := Objectives.soldiers(s)[0]
	var far := start
	for cell in Rules.move_range(s, c):
		if Objectives._cheb(cell, start) >= 3 and s.unit_at(cell) == null:
			far = cell
			break
	_place(s, sol, far)
	_end_round(s)
	assert_true(Objectives._cheb(c.pos, sol.pos) <= 1, "civilian walked up to the soldier")
	# Walk everyone to the exit.
	var exit := s.grid.marker("exit")
	for i in civs.size():
		_place(s, civs[i], exit[i])
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "rescued")
	assert_true(Objectives.bonus_met(s), "all civilians safe")


func test_squad_wipe_is_defeat_even_with_civilians_alive() -> void:
	var s := _mission("rescue")
	for u in Objectives.soldiers(s):
		u.hp = 0
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.DEFEAT, "civilians don't count as squad")


func test_purge_wins_when_nests_die() -> void:
	var s := _mission("purge", ["runner", "runner"])
	var nest := s.living(Types.Team.ENEMY)[0]
	nest.kind = Objectives.NEST_KIND
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.NONE, "nest alive")
	nest.hp = 0
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.VICTORY, "nests gone, the runner can stay")


func test_objective_state_survives_snapshot() -> void:
	var s := _mission("hold")
	_place(s, Objectives.soldiers(s)[0], s.grid.marker("beacon")[0])
	_end_round(s)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.objective, s.objective, "progress restored")
	assert_eq(back.grid.objective, "hold", "objective on the grid")
	assert_true(Objectives.describe(back).contains("1/4"), "HUD line shows progress")
