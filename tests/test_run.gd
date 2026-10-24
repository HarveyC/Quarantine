extends TestCase
## Run framework: node map generation, route vote, node flow, fights, save/resume.


func _nodes_in_row(map: Array, row: int) -> Array:
	return map.filter(func(n: Dictionary) -> bool: return n.row == row)


func test_map_shape_and_fixed_rows() -> void:
	for seed in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + 1
		var act := seed % 3 + 1
		var map := RunMap.generate(rng, act)
		assert_true(_nodes_in_row(map, 1).size() in [2, 3], "2-3 start nodes")
		assert_true(_nodes_in_row(map, 1).all(func(n): return n.type == RunMap.SKIRMISH), "row 1 skirmish")
		assert_true(_nodes_in_row(map, 4).all(func(n): return n.type == RunMap.HOSPITAL), "row 4 hospital")
		assert_eq(_nodes_in_row(map, 5).size(), 1, "one boss")
		assert_true(RunMap._valid(act, [_nodes_in_row(map, 1), _nodes_in_row(map, 2), _nodes_in_row(map, 3)]), "placement rules hold, seed %d" % seed)


func test_map_links_cover_every_node_and_never_cross() -> void:
	for seed in 60:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + 100
		var map := RunMap.generate(rng, 2)
		var incoming := {}
		for n in map:
			if n.row < 5:
				assert_true(n.links.size() in [1, 2], "1-2 links out")
			for id in n.links:
				incoming[id] = true
		for n in map:
			if n.row > 1:
				assert_true(incoming.has(n.id), "every node is reachable")
		# No crossing: for links a->b and c->d in the same row pair, a.col < c.col implies b.col <= d.col.
		var cols := {}
		for n in map:
			cols[n.id] = n.col
		for a in map:
			for c in map:
				if a.row != c.row or cols[a.id] >= cols[c.id]:
					continue
				for b in a.links:
					for d in c.links:
						assert_true(cols[b] <= cols[d], "links cross (seed %d)" % seed)


func test_map_generation_is_deterministic() -> void:
	var a := RunRules.new_run(2, 777)
	var b := RunRules.new_run(2, 777)
	RunRules.start_run(a)
	RunRules.start_run(b)
	assert_eq(a.map, b.map, "same seed, same map")
	assert_eq(a.checksum(), b.checksum(), "same checksum")


func test_solo_run_squad_and_vote_resolves_instantly() -> void:
	var run := RunRules.new_run(1, 42)
	RunRules.start_run(run)
	assert_eq(run.players, [0] as Array[int], "one player")
	assert_eq(run.soldiers_of(0).size(), 4, "solo player commands all four")
	assert_eq(run.serum[0], 4, "1 sample per soldier controlled")
	assert_eq(run.reserve_of(0).size(), 1, "one recruit in reserve")
	var target: int = run.reachable_nodes()[0]
	assert_true(RunRules.apply(run, {"type": RunRules.VOTE, "player": 0, "node": target}), "vote accepted")
	assert_eq(run.node, target, "single vote resolves at once")
	assert_eq(run.phase, RunState.Phase.FIGHT, "row 1 is a fight")
	assert_eq(run.outbreak, 1, "+1 Outbreak per node")
	assert_eq(run.fight_config.squad.size(), 4, "four soldiers deploy")
	assert_true(run.fight_config.squad.all(func(e): return e.player == 0), "all controlled by player 0")


func test_split_vote_waits_then_host_breaks_tie() -> void:
	var run := RunRules.new_run(2, 5)
	RunRules.start_run(run)
	var opts := run.reachable_nodes()
	RunRules.apply(run, {"type": RunRules.VOTE, "player": 1, "node": opts[0]})
	assert_eq(run.node, -1, "waits for every present player")
	RunRules.apply(run, {"type": RunRules.VOTE, "player": 0, "node": opts[1]})
	assert_eq(run.node, opts[1], "host breaks the split")


func test_benched_player_does_not_block_vote() -> void:
	var run := RunRules.new_run(3, 9)
	RunRules.start_run(run)
	RunRules.apply(run, {"type": RunRules.BENCH, "player": 0, "target": 2, "on": true})
	var opt: int = run.reachable_nodes()[0]
	assert_true(not RunRules.apply(run, {"type": RunRules.VOTE, "player": 2, "node": opt}), "benched can't vote")
	RunRules.apply(run, {"type": RunRules.VOTE, "player": 0, "node": opt})
	RunRules.apply(run, {"type": RunRules.VOTE, "player": 1, "node": opt})
	assert_eq(run.node, opt, "resolved without the benched player")
	assert_true(run.fight_config.squad.all(func(e): return e.player != 2), "host plays the benched player's soldier")


func test_reveal_spends_intel() -> void:
	var run := RunRules.new_run(1, 3)
	RunRules.start_run(run)
	var hidden := run.map.filter(func(n): return n.hidden)
	if hidden.is_empty():
		return
	assert_true(RunRules.apply(run, {"type": RunRules.REVEAL, "player": 0, "node": hidden[0].id}), "reveal")
	assert_eq(run.intel, 0, "intel spent")
	assert_true(not hidden[0].hidden and hidden[0].resolved != "", "resolved")
	assert_true(not RunRules.apply(run, {"type": RunRules.REVEAL, "player": 0, "node": hidden[0].id}), "already revealed")


## Plays a fight to the end with a fake outcome: every soldier survives with 1 damage.
func _win_fight(run: RunState, bonus: bool = false) -> void:
	var s := MatchConfig.build(run.fight_config)
	Rules.start_mission(s)
	for u in s.living(Types.Team.PLAYER):
		u.hp -= 1
	for u in s.living(Types.Team.ENEMY):
		u.hp = 0
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.VICTORY, "fake win")
	assert_true(RunRules.apply(run, {"type": RunRules.FIGHT_END, "player": 0, "outcome": RunRules.fight_outcome(s, bonus)}), "fight_end")


func _vote_first(run: RunState) -> void:
	var opts := run.reachable_nodes()
	# Prefer non-fight nodes to exercise the node flow.
	var pick: int = opts[0]
	for id in opts:
		if not RunMap.is_fight(RunMap.shown_type(run.get_node(id))):
			pick = id
	for p in run.present_players():
		RunRules.apply(run, {"type": RunRules.VOTE, "player": p, "node": pick})


func test_full_run_to_victory_and_save_resume() -> void:
	var run := RunRules.new_run(2, 2024)
	RunRules.start_run(run)
	var guard := 0
	var saved_mid := ""
	while run.phase != RunState.Phase.ENDED and guard < 100:
		guard += 1
		match run.phase:
			RunState.Phase.MAP: _vote_first(run)
			RunState.Phase.FIGHT:
				if saved_mid == "":
					saved_mid = run.save_string()
				_win_fight(run, true)
			_:
				assert_true(false, "stuck in phase %d with no modules" % run.phase)
				break
	assert_eq(run.result, Types.Result.VICTORY, "run won")
	assert_eq(run.act, 3, "ended in act 3")
	assert_true(run.fights_won >= 6, "fought through three acts")
	var loaded := RunState.from_save_string(saved_mid)
	assert_true(loaded != null, "save loads")
	assert_eq(loaded.phase, RunState.Phase.FIGHT, "resumes in the fight")
	assert_eq(RunState.from_save_string(loaded.save_string()).checksum(), loaded.checksum(), "save round-trips")


func test_fight_heals_pays_and_tracks_outbreak() -> void:
	var run := RunRules.new_run(1, 11)
	RunRules.start_run(run)
	_vote_first(run)
	var before := run.supplies
	_win_fight(run, true)
	assert_eq(run.supplies, before + 50, "skirmish pays 40 + 10 bonus")
	assert_eq(run.intel, 2, "bonus objective gives Intel")
	for r in run.squad():
		assert_eq(r.hp, r.max_hp, "25% heal after the fight covers 1 damage")
		assert_eq(r.fights, 1, "fight counted")
	assert_eq(run.phase, RunState.Phase.MAP, "back on the map")


func test_death_deploys_recruit_and_wipe_ends_run() -> void:
	var run := RunRules.new_run(1, 12)
	RunRules.start_run(run)
	_vote_first(run)
	var s := MatchConfig.build(run.fight_config)
	Rules.start_mission(s)
	var dead := s.living(Types.Team.PLAYER)[0]
	dead.hp = 0
	for u in s.living(Types.Team.ENEMY):
		u.hp = 0
	Rules.check_end(s)
	RunRules.apply(run, {"type": RunRules.FIGHT_END, "player": 0, "outcome": RunRules.fight_outcome(s)})
	assert_eq(run.get_soldier(dead.status.sid).status, RunSoldier.DEAD, "dead soldier stays dead")
	assert_eq(run.squad().size(), 4, "recruit fills the slot")
	assert_eq(run.reserve_of(0).size(), 0, "reserve used")
	_vote_first(run)
	if run.phase != RunState.Phase.FIGHT:
		return
	s = MatchConfig.build(run.fight_config)
	Rules.start_mission(s)
	for u in s.living(Types.Team.PLAYER):
		u.hp = 0
	Rules.check_end(s)
	RunRules.apply(run, {"type": RunRules.FIGHT_END, "player": 0, "outcome": RunRules.fight_outcome(s)})
	assert_eq(run.result, Types.Result.DEFEAT, "a wiped squad loses the run")


func test_persistent_state_reaches_the_mission() -> void:
	var run := RunRules.new_run(1, 13)
	RunRules.start_run(run)
	run.squad()[0].hp = 2
	run.squad()[0].infection = 30
	_vote_first(run)
	var s := MatchConfig.build(run.fight_config)
	var u: Unit = s.units.filter(func(x): return x.status.get("sid", -1) == run.squad()[0].id)[0]
	assert_eq(u.hp, 2, "HP carries over")
	assert_eq(u.infection, 30, "Infection carries over")
	assert_eq(Infection.tier(u.infection), Infection.Tier.EXPOSED, "tier applied")
