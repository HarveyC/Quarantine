extends TestCase
## Objective win/lose rules on generated maps.

const FightDebrief := preload("res://ui/fight_debrief.gd")

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
	var events: Array = []
	lost.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	_place(lost, lost.living(Types.Team.ENEMY)[0], lost.grid.marker("beacon")[4])
	_end_round(lost)
	assert_eq(lost.result, Types.Result.NONE, "one overrun round only warns")
	assert_true(events.any(func(ev: Dictionary) -> bool: return ev.type == "beacon_overrun"), "warning event")
	assert_eq(lost.objective.held, 0, "an overrun round isn't held")
	assert_true(Objectives.describe(lost).contains("OVERRUN"), "HUD line warns")
	_end_round(lost)
	assert_eq(lost.result, Types.Result.DEFEAT, "enemies own the beacon two rounds running")
	assert_eq(Objectives.loss_cause(lost), "beacon", "the beacon lost it")
	assert_eq(Objectives.soldiers(lost).size(), 4, "with the squad still standing")
	var end: Array = events.filter(func(ev: Dictionary) -> bool: return ev.type == "mission_end")
	assert_eq(end.size(), 1, "one mission_end")
	assert_eq(str(end[0].get("cause", "")), "beacon", "mission_end names the cause")


func test_retaking_the_beacon_resets_the_overrun() -> void:
	var s := _mission("hold")
	var zone := s.grid.marker("beacon")
	var foe := s.living(Types.Team.ENEMY)[0]
	_place(s, foe, zone[4])
	_end_round(s)
	assert_eq(int(s.objective.overrun), 1, "overrun")
	_place(s, Objectives.soldiers(s)[0], zone[0])
	_end_round(s)
	assert_eq(s.result, Types.Result.NONE, "contested, not lost")
	assert_eq(int(s.objective.overrun), 0, "retaken")
	assert_eq(int(s.objective.held), 1, "counts as held")
	_place(s, Objectives.soldiers(s)[0], s.grid.player_spawns[0])
	_end_round(s)
	assert_eq(s.result, Types.Result.NONE, "a fresh overrun warns again instead of losing")


## Harvey's report: a 2-soldier Hold the beacon lost on turn 1 with both soldiers alive (enemies
## start detected and rush through the beacon before the squad can reach it). Real fights, real
## AI, the squad standing still: round 1 never ends the fight.
func test_two_soldier_hold_is_never_lost_on_turn_one() -> void:
	for seed in [12] + range(1, 25):
		var spec := {"act": 1, "row": 2, "node": "skirmish", "objective": "hold", "outbreak": 0,
			"seed": seed, "players": 1, "squad": 2, "modifiers": {}}
		var built := FightBuilder.build(spec)
		var s := MatchConfig.build({"map": MatchConfig.MAP, "squad": [{"kind": "marksman", "player": 0}, {"kind": "trooper", "player": 0}],
			"enemies": built.enemies, "encounter": built.encounter, "seed": seed,
			"map_spec": {"biome": RunMap.biome(1), "objective": "hold", "seed": seed, "act": 1, "row": 2, "outbreak": 0}})
		Rules.start_mission(s)
		for p in s.players:
			Rules.set_ready(s, p, true)
		assert_eq(s.phase != Types.Phase.ENDED, true, "seed %d: still on after round 1" % seed)
		assert_eq(s.turn, 2, "seed %d: round 2" % seed)


func test_loss_cause_names_each_loss() -> void:
	var wipe := _mission("skirmish")
	for u in Objectives.soldiers(wipe):
		u.hp = 0
	Rules.check_end(wipe)
	assert_eq(Objectives.loss_cause(wipe), "squad_down", "squad wipe")

	var ex := _mission("extract")
	ex.turn = Objectives.EXTRACT_TURNS
	_end_round(ex)
	assert_eq(ex.result, Types.Result.DEFEAT, "nobody made the dropship")
	assert_eq(Objectives.loss_cause(ex), "left_behind", "left behind")

	var tu := _mission("skirmish")
	for u in Objectives.soldiers(tu):
		u.status["turned"] = true
		u.team = Types.Team.ENEMY
	Rules.check_end(tu)
	assert_eq(Objectives.loss_cause(tu), "turned", "everyone Turned")

	var won := _mission("skirmish")
	for u in won.living(Types.Team.ENEMY):
		u.hp = 0
	Rules.check_end(won)
	assert_eq(Objectives.loss_cause(won), "", "a win has no loss cause")
	for k in Objectives.LOSS:
		assert_true(str(Objectives.LOSS[k].title) != "" and str(Objectives.LOSS[k].line) != "", k + " has text")


## The debrief after a lost objective says "Mission failed", names the cause, and holds on the
## battlefield longer than after a win before the banner comes in.
func test_debrief_names_the_cause_of_a_loss() -> void:
	var s := _mission("hold")
	_place(s, s.living(Types.Team.ENEMY)[0], s.grid.marker("beacon")[4])
	_end_round(s)
	_end_round(s)
	assert_eq(s.result, Types.Result.DEFEAT, "lost")
	var d := FightDebrief.new()
	d.play(s)
	assert_eq(d.summary.cause, "beacon", "summary carries the cause")
	assert_eq(FightDebrief.headline(d.summary), "Mission failed", "not 'Squad lost' with soldiers alive")
	var texts := _texts(d)
	assert_true(texts.has("BEACON OVERRUN"), "cause named in the banner: %s" % [texts])
	assert_true(texts.any(func(t: String) -> bool: return t.to_lower().contains("2 rounds")), "and explained")
	assert_true(not texts.any(func(t: String) -> bool: return t.to_lower().contains("fell")), "no 'the squad fell'")
	d._process(FightDebrief.HOLD + 0.1)
	assert_true(not d.shown, "a loss holds on the battlefield past the win beat")
	d._process(FightDebrief.LOSS_HOLD)
	assert_true(d.shown, "then the banner")
	d.free()

	var wipe := _mission("skirmish")
	for u in Objectives.soldiers(wipe):
		u.hp = 0
	Rules.check_end(wipe)
	var d2 := FightDebrief.new()
	d2.play(wipe)
	assert_eq(FightDebrief.headline(d2.summary), "Squad lost", "a wipe is still Squad lost")
	assert_true(_texts(d2).has("ALL SOLDIERS DOWN"), "and says so")
	d2.free()


func test_quick_play_overlay_names_the_cause() -> void:
	var o := preload("res://ui/end_overlay.gd").new()
	o.build()
	o.show_result(Types.Result.DEFEAT, 2, true, false, "beacon")
	assert_true(o._sub.text.begins_with("Beacon overrun on turn 2"), o._sub.text)
	o.free()


func _texts(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return out


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
		if Objectives._cheb(cell, start) >= 2 and s.unit_at(cell) == null:
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
