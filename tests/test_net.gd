extends TestCase
## Host-side lobby logic, driven directly without sockets.


func _host() -> NetSession:
	var n := NetSession.new()
	n.is_host = true
	n.my_player = 0
	n.lobby = {1: {"name": "Host", "player": 0, "cid": "host"}}
	return n


func test_new_players_get_consecutive_slots() -> void:
	var n := _host()
	assert_eq(n.handle_hello(2, "Ana", "a"), 1, "second player")
	assert_eq(n.handle_hello(3, "Ben", "b"), 2, "third player")
	n.free()


func test_duplicate_hello_keeps_slot() -> void:
	var n := _host()
	n.handle_hello(2, "Ana", "a")
	assert_eq(n.handle_hello(2, "Ana", "a"), 1, "same connection, same slot")
	assert_eq(n.lobby.size(), 2, "no extra entry")
	n.free()


## The playtest bug: a crashed client's dead connection lingered, so its restart joined as player 3.
func test_reconnect_from_same_install_reuses_slot_and_drops_ghost() -> void:
	var n := _host()
	n.handle_hello(2, "Ana", "a")
	assert_eq(n.handle_hello(5, "Ana", "a"), 1, "reconnect takes the old slot")
	assert_true(not n.lobby.has(2), "ghost connection removed")
	assert_eq(n.lobby.size(), 2, "still two players")
	var config := MatchConfig.make(n.lobby.size())
	assert_eq(config.squad.filter(func(s: Dictionary) -> bool: return s.player == 1).size(), 1, "player 2 gets one soldier")
	n.free()


func test_same_name_different_install_is_a_new_player() -> void:
	var n := _host()
	n.handle_hello(2, "Player", "a")
	assert_eq(n.handle_hello(3, "Player", "b"), 2, "two people both called Player")
	n.free()


func test_reconnect_mid_match_reclaims_absent_slot() -> void:
	var n := _host()
	n.handle_hello(2, "Ana", "a")
	n.in_match = true
	n.state = MatchConfig.build(MatchConfig.make(2, 7))
	n._on_peer_disconnected(2)
	assert_true(n.absent.has(1), "player 2 marked absent")
	assert_eq(n.handle_hello(9, "Ana", "a"), 1, "rejoin gets the same slot")
	assert_true(not n.absent.has(1), "no longer absent")
	n.free()


func test_lobby_squad_picks_share_four_soldiers() -> void:
	var n := _host()
	n.handle_hello(2, "Ana", "a")
	n.handle_pick(1, ["trooper", "medic", "breacher"])
	assert_eq(n.planned_squads()[0], ["trooper", "medic", "breacher"], "host commands three")
	assert_eq(n.room_for(1), 1, "one slot left for Ana")
	n.handle_pick(2, ["marksman", "medic"])
	assert_eq(n.lobby[2].squad, ["marksman"], "cut to the room left")
	n.handle_pick(2, ["nonsense"])
	assert_eq(n.lobby[2].squad, ["marksman"], "unknown classes are ignored")
	n.handle_hello(3, "Ben", "b")
	var plan := n.planned_squads()
	assert_eq(plan[0].size() + plan[1].size() + plan[2].size(), 4, "a third player still fits in 4")
	assert_eq(plan[2].size(), 1, "and gets a soldier")
	n.lobby.erase(3)
	n.handle_hello(4, "Ana", "a")   # same install back before the dead connection timed out
	assert_eq(n.lobby[4].get("squad", []), ["marksman"], "a reconnect keeps its squad")
	var run := RunRules.new_run(2, 3, {}, n.squad_picks())
	assert_eq(run.soldiers_of(0).size(), 3, "the run follows the lobby")
	assert_eq(run.soldiers_of(1).size(), 1, "for every player")
	n.free()


func test_host_waits_for_every_player_to_ready_up() -> void:
	var n := _host()
	assert_true(n.all_ready(), "a lone host is always ready")
	n.handle_hello(2, "Ana", "a")
	n.handle_hello(3, "Ben", "b")
	assert_eq(n.waiting_on(), 2, "both clients still to ready")
	n.start_run()
	assert_true(n.run == null, "the run does not start")
	n.handle_ready(2, true)
	assert_true(n.is_ready(1), "Ana is ready")
	assert_true(not n.all_ready(), "Ben is not")
	n.handle_ready(3, true)
	assert_true(n.all_ready(), "everyone is ready")
	n.free()


func test_changing_squad_or_reconnecting_clears_ready() -> void:
	var n := _host()
	n.handle_hello(2, "Ana", "a")
	n.handle_ready(2, true)
	n.handle_pick(2, ["marksman"])
	assert_true(not n.is_ready(1), "a new pick takes Ready back")
	n.handle_ready(2, true)
	n.handle_hello(5, "Ana", "a")
	assert_true(not n.is_ready(1), "a reconnect starts not ready")
	n.free()
