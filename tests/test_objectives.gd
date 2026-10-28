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


func test_rescue_civilians_are_moved_by_any_player_and_cannot_attack() -> void:
	var s := _mission("rescue")
	var civs := s.living(Types.Team.PLAYER).filter(func(u: Unit) -> bool: return Objectives.is_civilian(u))
	assert_eq(civs.size(), s.grid.marker("civilian").size(), "civilians spawned on their markers")
	assert_true(civs.all(func(c: Unit) -> bool: return c.owner_player == -1 and not c.ai_controlled), "nobody owns them")
	assert_eq(s.controllable_units(0).size() + s.controllable_units(1).size(), 4, "squad unchanged")
	var c: Unit = civs[0]
	var start := c.pos
	_end_round(s)
	assert_eq(c.pos, start, "a civilian never walks on their own")
	var dest := start
	for cell in Rules.move_range(s, c):
		if s.unit_at(cell) == null:
			dest = cell
			break
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": c.id, "to": dest}), "a player can move a civilian")
	assert_eq(c.pos, dest, "and it moved")
	assert_true(Rules.validate(s, {"type": Types.HUNKER, "unit": c.id}) != "", "civilians cannot act beyond moving")
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


# ---------------------------------------------------------------- sprint objectives

func test_new_objectives_generate_without_fallback() -> void:
	for biome in ["wall", "port", "bore"]:
		for o in Objectives.NEW_KINDS:
			for seed in range(1, 5):
				var g := MapGen.generate({"biome": biome, "objective": o, "seed": seed})
				assert_eq(g.objective, o, "%s %s %d keeps its objective" % [biome, o, seed])
				assert_true(g.width >= 22, "%s %s sized" % [biome, o])
				var key: String = {"escort": "evac", "demolish": "charge", "hack": "relay", "samples": "sample"}[o]
				assert_true(not g.marker(key).is_empty(), "%s %s has %s" % [biome, o, key])
				if o != "escort":
					assert_eq(g.marker(key).size(), 3, "%s %s three sites" % [biome, o])
	var grand := MapGen.generate({"biome": "wall", "objective": "demolish", "seed": 2})
	assert_eq(grand.width, 28, "sites ride on grand maps")


func test_escort_courier_is_moved_by_players_and_wins_at_evac() -> void:
	var s := _mission("escort")
	var c := Objectives.courier(s)
	assert_true(c != null and c.is_alive(), "a courier starts")
	var d0 := Objectives._courier_dist(s, c.pos)
	assert_true(d0 > 0, "the evac zone is a walk away")
	var here := c.pos
	_end_round(s)
	assert_eq(c.pos, here, "it does not walk on its own")
	var best := c.pos
	for cell in Rules.move_range(s, c):
		if Objectives._courier_dist(s, cell) < Objectives._courier_dist(s, best):
			best = cell
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": c.id, "to": best}), "a player moves the courier")
	assert_true(Objectives._courier_dist(s, c.pos) < d0, "closer to evac")
	_place(s, c, s.grid.marker("evac")[0])
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "courier at evac wins")


func test_ending_the_turn_runs_one_enemy_phase_while_civilians_move() -> void:
	for kind in ["escort", "rescue"]:
		var s := _mission(kind)
		var turn := s.turn
		var phases := func() -> int: return s.log.filter(func(e: Dictionary) -> bool: return e.type == "enemy_phase").size()
		var before: int = phases.call()
		_end_round(s)
		assert_eq(phases.call() - before, 1, "%s: one enemy phase per ended turn" % kind)
		assert_eq(s.turn, turn + 1, "%s: one turn passes" % kind)


func test_escort_is_lost_when_the_courier_dies() -> void:
	var s := _mission("escort")
	var c := Objectives.courier(s)
	c.hp = 0
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.DEFEAT, "lost")
	assert_eq(Objectives.loss_cause(s), "courier_down", "named")
	assert_true(Objectives.LOSS.has("courier_down"), "has text")


func test_demolish_arms_fuses_and_blows() -> void:
	var s := _mission("demolish")
	var sites := s.grid.marker("charge")
	var squad := Objectives.soldiers(s)
	for i in sites.size():
		_place(s, squad[i], sites[i])
	_end_round(s)
	assert_eq(s.objective.charges.count("armed"), 3, "all armed")
	for u in squad:
		u.pos = Vector2i(-40, -40)
		u.hp = 99
	assert_eq(s.result, Types.Result.NONE, "fuse still burning")
	_end_round(s)
	assert_eq(s.objective.charges.count("blown"), 3, "all blown")
	assert_eq(s.result, Types.Result.VICTORY, "won")


func test_demolish_enemy_defuses_and_clock_runs_out() -> void:
	var s := _mission("demolish")
	var sites := s.grid.marker("charge")
	var squad := Objectives.soldiers(s)
	_place(s, squad[0], sites[0])
	Rules.set_ready(s, 0, true)
	Rules.set_ready(s, 1, true)
	assert_eq(s.objective.charges[0], "armed", "armed")
	squad[0].pos = Vector2i(-40, -40)
	var e := s.living(Types.Team.ENEMY)[0]
	_place(s, e, sites[0])
	_end_round(s)
	assert_eq(s.objective.charges[0], "idle", "an enemy on it defuses it")
	s.turn = Objectives.DEMOLISH_TURNS
	_end_round(s)
	assert_eq(s.result, Types.Result.DEFEAT, "out of time")
	assert_eq(Objectives.loss_cause(s), "charges_late", "named")


func test_hack_needs_two_turns_and_two_relays() -> void:
	var s := _mission("hack")
	var relays := s.grid.marker("relay")
	var squad := Objectives.soldiers(s)
	_place(s, squad[0], relays[0])
	_place(s, squad[1], relays[1])
	_end_round(s)
	assert_eq(s.objective.relays.count("hacked"), 0, "one turn is not enough")
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "two relays hacked")


func test_hack_is_lost_when_relays_are_destroyed() -> void:
	var s := _mission("hack")
	var relays := s.grid.marker("relay")
	for i in [0, 1]:
		var e := s.living(Types.Team.ENEMY)[0] if i == 0 else Unit.new()
		if i == 1:
			e = s.living(Types.Team.ENEMY)[0]
		_place(s, e, relays[i])
		s.objective.relays[i] = "idle"
		Objectives._hack_round(s)
		e.pos = Vector2i(-40, -40)
	assert_eq(s.result, Types.Result.NONE, "check_end not run yet")
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.DEFEAT, "too few relays left")
	assert_eq(Objectives.loss_cause(s), "relays_lost", "named")


func test_samples_are_carried_slowed_and_delivered() -> void:
	var s := _mission("samples")
	var spots := s.grid.marker("sample")
	var squad := Objectives.soldiers(s)
	var base := squad[0].mobility
	_place(s, squad[0], spots[0])
	_place(s, squad[1], spots[1])
	_end_round(s)
	assert_eq(s.objective.samples.count("carried"), 2, "two taken")
	assert_eq(squad[0].mobility, base - Objectives.SAMPLE_SLOW, "slowed")
	_place(s, squad[0], s.grid.marker("exit")[0])
	_place(s, squad[1], s.grid.marker("exit")[1])
	_end_round(s)
	assert_eq(s.result, Types.Result.VICTORY, "delivered")
	assert_eq(squad[0].mobility, base, "mobility restored")


func test_samples_drop_when_the_carrier_falls_and_are_lost_to_enemies() -> void:
	var s := _mission("samples")
	var spots := s.grid.marker("sample")
	var squad := Objectives.soldiers(s)
	_place(s, squad[0], spots[0])
	_end_round(s)
	assert_eq(s.objective.samples[0], "carried", "taken")
	squad[0].hp = 0
	Objectives._samples_round(s)
	assert_eq(s.objective.samples[0], "ground", "dropped where it fell")
	var e := s.living(Types.Team.ENEMY)[0]
	_place(s, e, s.objective.where[0])
	Objectives._samples_round(s)
	assert_eq(s.objective.samples[0], "lost", "trampled")
	e.pos = Vector2i(-40, -40)
	for i in [1, 2]:
		s.objective.samples[i] = "lost"
	Objectives._samples_check(s)
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.DEFEAT, "too few left")
	assert_eq(Objectives.loss_cause(s), "samples_lost", "named")
