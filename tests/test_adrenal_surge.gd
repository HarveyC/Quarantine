extends TestCase
## Adrenal Surge (v0.17.0 playtest bug: "I activated it but didn't get an extra action"). The rule
## gave the action all along; the HUD drew a fixed two pips, so the third never showed.

const MAIN := preload("res://scenes/main.tscn")

const ROWS := ["..........", "..........", "..........", "..........", ".........."]


func _setup() -> Dictionary:
	var s := make_blank(PackedStringArray(ROWS))
	var sol := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(1, 2))
	sol.owner_player = 0
	sol.status["mutations"] = {"exposed": "adrenal_surge"}
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 4))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	s.players.assign([0])
	sol.actions_left = Types.ACTIONS_PER_TURN
	Infection.add(s, sol, 25)
	return {"s": s, "sol": sol, "foe": foe}


func _surge(_s: GameState, u: Unit) -> Dictionary:
	return {"type": Types.MUTATION, "unit": u.id, "mutation": "adrenal_surge"}


func test_surge_gives_three_usable_actions() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	assert_true(Rules.apply(s, _surge(s, sol)), "surge accepted")
	assert_eq(sol.actions_left, 3, "third action")
	for x in [2, 3, 4]:
		assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": Vector2i(x, 2)}), "move %d" % (x - 1))
	assert_eq(sol.actions_left, 0, "all three spent")
	assert_true(not Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": Vector2i(5, 2)}), "no fourth")


func test_surge_after_a_move_still_adds_one() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": Vector2i(2, 2)}), "move")
	assert_true(Rules.apply(s, _surge(s, sol)), "surge with one action left")
	assert_eq(sol.actions_left, 2, "1 + 1")


func test_action_slots_show_the_bonus_pip() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	assert_eq(Rules.action_slots(sol), 2, "two pips normally")
	Rules.apply(s, _surge(s, sol))
	assert_eq(Rules.action_slots(sol), 3, "three pips after the surge")
	Rules.set_ready(s, 0, true)
	assert_eq(s.turn, 2, "next turn")
	assert_eq(sol.actions_left, 1, "crash: 1 action")
	assert_eq(Rules.action_slots(sol), 2, "back to two pips, one lit")
	assert_true(Rules.action_losses(s, sol).any(func(l): return l.title == "Crash"), "HUD names the crash")


## The real mission view: the action bar and nameplate draw the third pip, and the surge plays a
## beat of its own with sound.
func test_hud_shows_third_action_and_plays_a_beat() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	var v: MissionView = MAIN.instantiate()
	v.start(s, false)
	v.player.flush()
	v.input.select(sol.id)
	v.player.generic_log.clear()
	v.player.sfx_log.clear()
	assert_true(Rules.apply(s, _surge(s, sol)), "surge accepted")
	var ev: Dictionary = s.log.filter(func(e): return e.type == "mutation").back()
	assert_eq(int(ev.get("actions", 0)), 3, "event carries the new action count")
	v.player.flush()
	assert_eq(v.player.generic_log, [] as Array[String], "dedicated beat")
	assert_true(v.player.sfx_log.has("mutation"), "surge sound")
	v.hud.action_bar.refresh(v)
	var ap = v.hud.action_bar._ap
	assert_eq(ap.total, 3, "action bar draws three pips")
	assert_eq(ap.filled, 3, "all three lit")
	v.free()


## Online co-op: clients replay the host's accepted action and compare checksums, so the client
## must land on the same three actions as the host.
func test_surge_syncs_to_a_client_replay() -> void:
	var d := _setup()
	var host: GameState = d.s
	var client := GameState.from_dict(host.to_dict())
	assert_eq(client.checksum(), host.checksum(), "same start")
	var act := _surge(host, d.sol)
	assert_true(Rules.apply(host, act), "host applies")
	assert_true(Rules.apply(client, act), "client replays")
	assert_eq(client.get_unit(d.sol.id).actions_left, 3, "client sees three actions")
	assert_eq(client.checksum(), host.checksum(), "no desync")
	var snap := GameState.from_dict(host.to_dict())
	assert_eq(snap.get_unit(d.sol.id).actions_left, 3, "a resync snapshot keeps the third action")
