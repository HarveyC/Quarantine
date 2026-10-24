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
	_rewards(run)
	assert_eq(run.players, [0] as Array[int], "one player")
	assert_eq(run.soldiers_of(0).size(), 4, "solo player commands all four")
	assert_eq(run.serum[0], 4, "1 sample per soldier controlled")
	assert_eq(run.reserve_of(0).size(), RunRules.reserve_for(4), "two recruits in reserve with 4 soldiers")
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
	_rewards(run)
	var opts := run.reachable_nodes()
	RunRules.apply(run, {"type": RunRules.VOTE, "player": 1, "node": opts[0]})
	assert_eq(run.node, -1, "waits for every present player")
	RunRules.apply(run, {"type": RunRules.VOTE, "player": 0, "node": opts[1]})
	assert_eq(run.node, opts[1], "host breaks the split")


func test_benched_player_does_not_block_vote() -> void:
	var run := RunRules.new_run(3, 9)
	RunRules.start_run(run)
	_rewards(run)
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
	_rewards(run)
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
	s.objective.result = Types.Result.VICTORY   # extract / hold fights don't end on kills alone
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.VICTORY, "fake win")
	assert_true(RunRules.apply(run, {"type": RunRules.FIGHT_END, "player": 0, "outcome": RunRules.fight_outcome(s, bonus)}), "fight_end")
	_take_rank_up_picks(run)


## Makes every waiting Progression pick (first perk on offer, mutation offers skipped).
func _take_rank_up_picks(run: RunState) -> void:
	if run.phase == RunState.Phase.ENDED:
		return
	for r in run.squad():
		var guard := 0
		while Progression.pending_picks(r) > 0 and guard < 10:
			guard += 1
			var offer := Progression.perk_offer(run, r)
			var act := {"type": "prog_perk_pick", "player": run.controller_of(r), "sid": r.id, "perk": offer[0] if offer.size() > 0 else ""}
			var err := RunRules.validate(run, act)
			assert_eq(err, "", "perk pick")
			if err != "":
				break
			RunRules.apply(run, act)
		while not r.prog.offers.is_empty() and guard < 20:
			guard += 1
			RunRules.apply(run, {"type": "prog_skip_offer", "player": run.controller_of(r), "sid": r.id})


## Settles the REWARD step (the starting kit and post-fight picks once GearRun is in): takes the
## first card when it's legal, otherwise skips, and votes for the first Doctrine.
func _rewards(run: RunState) -> void:
	var guard := 0
	while run.phase == RunState.Phase.REWARD and guard < 50:
		guard += 1
		var acted := false
		for sid in run.gear.get("offers", {}).keys():
			var r := run.get_soldier(sid)
			var pick := {"type": "gear_pick", "player": run.controller_of(r), "soldier": sid, "card": 0}
			if RunRules.validate(run, pick) != "":
				pick.card = -1
			acted = RunRules.apply(run, pick) or acted
		var vote: Dictionary = run.gear.get("doctrine_vote", {})
		if not vote.is_empty():
			for p in run.present_players():
				acted = RunRules.apply(run, {"type": "gear_doctrine", "player": p, "doctrine": vote.options[0]}) or acted
		for a in Story.autoplay_actions(run):   # the ending vote after the act 3 boss
			acted = RunRules.apply(run, a) or acted
		if not acted:
			return


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
	_rewards(run)
	var guard := 0
	var saved_mid := ""
	while run.phase != RunState.Phase.ENDED and guard < 100:
		guard += 1
		match run.phase:
			RunState.Phase.MAP: _vote_first(run)
			RunState.Phase.NODE:
				for a in NodeRules.autoplay_actions(run):
					RunRules.apply(run, a)
			RunState.Phase.REWARD: _rewards(run)
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
	_rewards(run)
	_vote_first(run)
	var before := run.supplies
	_win_fight(run, true)
	assert_eq(run.supplies, before + 50, "skirmish pays 40 + 10 bonus")
	assert_eq(run.intel, 2, "bonus objective gives Intel")
	_rewards(run)
	for r in run.squad():
		assert_eq(r.hp, r.max_hp, "25% heal after the fight covers 1 damage")
		assert_eq(r.fights, 1, "fight counted")
	assert_eq(run.phase, RunState.Phase.MAP, "back on the map")


func test_death_deploys_recruit_and_wipe_ends_run() -> void:
	var run := RunRules.new_run(1, 12)
	RunRules.start_run(run)
	_rewards(run)
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
	assert_eq(run.reserve_of(0).size(), RunRules.reserve_for(4) - 1, "one recruit used")
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
	_rewards(run)
	run.squad()[0].hp = 2
	run.squad()[0].infection = 30
	_vote_first(run)
	var s := MatchConfig.build(run.fight_config)
	var u: Unit = s.units.filter(func(x): return x.status.get("sid", -1) == run.squad()[0].id)[0]
	assert_eq(u.hp, 2, "HP carries over")
	assert_eq(u.infection, 30, "Infection carries over")
	assert_eq(Infection.tier(u.infection), Infection.Tier.EXPOSED, "tier applied")


func test_bridge_removes_a_column_and_keeps_the_map_connected() -> void:
	for seed in 30:
		var run := RunRules.new_run(1, seed + 500)
		RunRules.start_run(run)
		var start := run.reachable_nodes()[0]
		run.node = start
		run.row = 1
		var before := run.map.size()
		RunMap.remove_column(run.map, 1)
		assert_true(run.map.size() < before, "nodes removed")
		var ids := {}
		for n in run.map:
			ids[n.id] = true
		var incoming := {}
		for n in run.map:
			for id in n.links:
				assert_true(ids.has(id), "no link to a removed node")
				incoming[id] = true
			if n.row < 5:
				assert_true(not n.links.is_empty(), "every node leads on")
		for n in run.map:
			if n.row > 2:
				assert_true(incoming.has(n.id), "every later node is reachable")


func test_squad_defaults_solo_four_and_coop_one_each() -> void:
	var solo := RunRules.new_run(1, 5)
	assert_eq(solo.squad().size(), 4, "solo fields 4 by default")
	assert_eq(solo.serum[0], 4, "a sample per soldier")
	for n in [2, 3, 4]:
		var run := RunRules.new_run(n, 5)
		assert_eq(run.squad().size(), n, "%d players, %d soldiers" % [n, n])
		for p in n:
			assert_eq(run.soldiers_of(p).filter(func(r): return r.status == RunSoldier.ACTIVE).size(), 1, "one each")
			assert_eq(run.reserve_of(p).size(), RunRules.START_RESERVE, "reserve per player")
	var picked := RunRules.new_run(2, 5, {}, {0: "medic", 1: "medic"})
	assert_eq(picked.squad().map(func(r): return r.kind), ["medic", "medic"], "picks are honoured, repeats allowed")
	var partial := MatchConfig.squad_plan(3, {1: "trooper"})
	assert_eq(partial.map(func(e): return e.kind), ["marksman", "trooper", "medic"], "defaults skip picked classes")


func test_players_choose_their_squad_size() -> void:
	var lone := RunRules.new_run(1, 5, {}, {0: ["breacher"]})
	assert_eq(lone.squad().size(), 1, "solo can run a single soldier")
	assert_eq(lone.squad()[0].kind, "breacher", "with the picked class")
	assert_eq(lone.serum[0], 1, "one sample for one soldier")
	assert_eq(lone.reserve_of(0).size(), RunRules.reserve_for(1), "one recruit")
	var pair := RunRules.new_run(1, 5, {}, {0: ["medic", "marksman"]})
	assert_eq(pair.squad().map(func(r): return r.kind), ["medic", "marksman"], "solo pair")
	var duo := RunRules.new_run(2, 5, {}, {0: ["trooper", "medic"], 1: ["breacher", "marksman"]})
	assert_eq(duo.soldiers_of(0).size(), 2, "player 1 commands two")
	assert_eq(duo.soldiers_of(1).size(), 2, "player 2 commands two")
	assert_eq(duo.serum[1], 2, "a sample per soldier you control")
	var uneven := RunRules.new_run(2, 5, {}, {0: ["trooper", "medic", "breacher"]})
	assert_eq(uneven.soldiers_of(0).size(), 3, "3 + 1")
	assert_eq(uneven.soldiers_of(1).size(), 1, "the other player still gets one")
	assert_eq(uneven.reserve_of(0).size(), 2, "3 soldiers start with 2 recruits")
	assert_eq(uneven.reserve_of(1).size(), 1, "1 soldier starts with 1 recruit")
	var cfg := MatchConfig.for_fight(duo, {"kind": "skirmish", "objective": "hold", "seed": 4})
	assert_eq(cfg.fight.squad, 4, "enemies scale to soldiers, not players")
	assert_eq(MatchConfig.for_fight(lone, {"kind": "skirmish", "objective": "hold", "seed": 4}).fight.squad, 1, "a lone soldier faces a lone-soldier fight")


func test_squad_picks_never_pass_four() -> void:
	var plan := MatchConfig.squad_plan(2, {0: ["trooper", "medic", "breacher", "marksman"], 1: ["medic"]})
	assert_eq(plan.size(), 4, "at most 4 in all")
	assert_eq(plan.filter(func(e): return e.player == 1).size(), 1, "everyone keeps a soldier")
	var four := MatchConfig.squad_plan(4, {0: ["trooper", "medic"], 1: ["breacher", "marksman"], 2: ["medic"], 3: ["trooper"]})
	for p in 4:
		assert_eq(four.filter(func(e): return e.player == p).size(), 1, "4 players means one each")
	assert_eq(MatchConfig.room_for(2, {0: ["trooper", "medic", "breacher"]}, 1), 1, "room left for player 2")
	assert_eq(MatchConfig.room_for(2, {0: ["trooper"]}, 0), 3, "the rest is mine")
	assert_eq(MatchConfig.room_for(1, {}, 0), 4, "solo has all 4")
	var filled := MatchConfig.squad_plan(1, {0: ["", "", "medic"]})
	assert_eq(filled.map(func(e): return e.kind), ["trooper", "marksman", "medic"], "blanks take free classes")


func test_solo_bonds_any_two_soldiers() -> void:
	var run := RunRules.new_run(1, 5, {}, {0: ["trooper", "medic"]})
	var a: Dictionary = run.squad()[0]
	assert_eq(Progression.bond_partners(run, a).size(), 1, "the other soldier")
	var lone := RunRules.new_run(1, 5, {}, {0: ["trooper"]})
	assert_true(Progression.bond_partners(lone, lone.squad()[0]).is_empty(), "nobody to bond with")
	var duo := RunRules.new_run(2, 5, {}, {0: ["trooper", "medic"], 1: ["breacher"]})
	var mine: Dictionary = duo.soldiers_of(0)[0]
	assert_eq(Progression.bond_partners(duo, mine).map(func(r): return r.owner), [1], "co-op bonds across players")


func test_fights_scale_with_squad_size() -> void:
	for act in [1, 2, 3]:
		for seed in [3, 11, 29]:
			var spec := {"act": act, "row": 2, "node": "skirmish", "objective": "extract", "outbreak": 4, "seed": seed}
			var full: Dictionary = FightBuilder.build(spec.merged({"squad": 4}))
			var duo: Dictionary = FightBuilder.build(spec.merged({"squad": 2}))
			assert_true(duo.enemies.size() <= 3, "a duo faces at most 3 at the start")
			assert_true(duo.enemies.size() <= full.enemies.size(), "never more than a full squad")
	var boss: Dictionary = FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "seed": 3, "squad": 2})
	assert_eq(boss.encounter.get("boss_health_mult", 1.0), FightBuilder.SQUAD_BOSS_HEALTH[2], "smaller squads face a weaker boss")
	var run := RunRules.new_run(3, 9)
	var cfg := MatchConfig.for_fight(run, {"kind": "skirmish", "objective": "hold", "seed": 4})
	assert_eq(cfg.fight.squad, 3, "the fight spec carries the squad size")


## Skirmish and Ambush objectives spread across the whole mix in every act: plain clear fights
## come up, and no single objective (extract included) takes over an act.
func test_objective_mix_has_variety() -> void:
	for act in [1, 2, 3]:
		var counts := {}
		var total := 0
		var repeats := 0
		for seed in 300:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed * 7 + act
			var map := RunMap.generate(rng, act)
			var in_map := {}
			for n in map:
				if n.type == RunMap.SKIRMISH:
					counts[n.objective] = counts.get(n.objective, 0) + 1
					in_map[n.objective] = in_map.get(n.objective, 0) + 1
					total += 1
			for k in in_map:
				repeats += in_map[k] - 1
		for k in ["skirmish", "extract", "hold", "rescue", "purge"]:
			var share := float(counts.get(k, 0)) / total
			assert_true(share >= 0.1 and share <= 0.32, "act %d: %s is %.0f%% of skirmishes" % [act, k, share * 100.0])
		assert_true(float(repeats) / total < 0.3, "act %d: few repeated objectives in one act (%d of %d)" % [act, repeats, total])


func test_ambush_objective_avoids_the_acts_repeats() -> void:
	var run := RunState.new()
	run.act = 2
	run.rng.seed = 5
	run.map = [{"type": RunMap.SKIRMISH, "objective": "extract", "resolved": ""},
		{"type": RunMap.SKIRMISH, "objective": "extract", "resolved": ""},
		{"type": RunMap.SKIRMISH, "objective": "extract", "resolved": ""}]
	var extracts := 0
	for i in 400:
		if RunMap.roll_objective(run.rng, run.act, run.map) == "extract":
			extracts += 1
	assert_true(extracts < 400 * 0.1, "three extracts already on the map make a fourth rare (%d/400)" % extracts)
