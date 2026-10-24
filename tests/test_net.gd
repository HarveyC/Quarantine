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
	assert_eq(config.squad.filter(func(s: Dictionary) -> bool: return s.player == 1).size(), 2, "player 2 gets two soldiers")
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
