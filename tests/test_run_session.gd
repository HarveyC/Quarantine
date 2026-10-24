extends TestCase
## Runs through the session layer: solo with no network, host-side online run logic.


func _local() -> LocalSession:
	var l := LocalSession.new()
	l.save_enabled = false
	return l


func test_solo_run_needs_no_lobby_and_builds_fights() -> void:
	var l := _local()
	var started := []
	l.match_started.connect(func(s: GameState) -> void: started.append(s))
	l.start_run(1, 31)
	assert_eq(l.local_players(), [0] as Array[int], "solo player is local")
	var node: int = l.run.reachable_nodes()[0]
	l.submit_run({"type": RunRules.VOTE, "player": 0, "node": node})
	assert_eq(l.run.phase, RunState.Phase.FIGHT, "vote resolves straight into the fight")
	assert_eq(started.size(), 1, "the session built the mission")
	var s: GameState = started[0]
	Rules.start_mission(s)
	for u in s.living(Types.Team.ENEMY):
		u.hp = 0
	Rules.check_end(s)
	assert_true(l.run.phase != RunState.Phase.FIGHT, "mission end reported to the run")
	assert_eq(l.run.fights_won, 1, "fight counted")
	l.free()


func test_resume_mid_fight_restores_the_mission() -> void:
	var l := _local()
	l.start_run(1, 32)
	l.submit_run({"type": RunRules.VOTE, "player": 0, "node": l.run.reachable_nodes()[0]})
	Rules.start_mission(l.state)
	var text := l.run.save_string()
	var l2 := _local()
	var resumed := []
	l2.resynced.connect(func(s: GameState) -> void: resumed.append(s))
	l2.resume_run(RunState.from_save_string(text))
	assert_eq(resumed.size(), 1, "fight resumed, not restarted")
	assert_eq(resumed[0].checksum(), l.state.checksum(), "same mission state")
	l.free()
	l2.free()


func test_host_benches_a_dropped_player_and_checks_run_actions() -> void:
	var n := NetSession.new()
	n.is_host = true
	n.my_player = 0
	n.lobby = {1: {"name": "Host", "player": 0, "cid": "h"}}
	n.handle_hello(2, "Ana", "a")
	n.start_run()
	assert_true(n.in_match and n.run != null, "run started")
	assert_eq(n.run.players.size(), 2, "two players")
	var opt: int = n.run.reachable_nodes()[0]
	assert_eq(n._check_request(2, {"type": NetSession.RUN, "action": {"type": RunRules.VOTE, "player": 0, "node": opt}}), "You can only act for yourself", "can't vote for the host")
	n._on_peer_disconnected(2)
	assert_true(n.run.benched.get(1, false), "dropped player benched")
	n._handle_request(1, {"type": NetSession.RUN, "action": {"type": RunRules.VOTE, "player": 0, "node": opt}})
	assert_eq(n.run.node, opt, "host's vote alone decides while the other player is benched")
	n.free()
