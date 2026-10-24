extends TestCase
## Builds every node screen headlessly and clicks through it, so a screen can't break silently.


class StubSession:
	extends RefCounted
	var run: RunState
	var players: Array[int] = []
	var player_names := {}
	var sent: Array = []

	func local_players() -> Array[int]:
		return players

	func submit_run(action: Dictionary) -> void:
		sent.append(action)
		NodeRules.apply(run, action)


func _setup(kind: String, num_players := 2, event_id := "") -> Dictionary:
	var run := RunRules.new_run(num_players, 31)
	GearRun.init_run(run)
	run.phase = RunState.Phase.NODE
	run.supplies = 300
	NodeRules.enter(run, kind, event_id)
	var session := StubSession.new()
	session.run = run
	session.players.assign(run.players)
	var screen: Control = NodeRules.screen(kind).new()
	screen.setup(run, session)
	return {"run": run, "session": session, "screen": screen}


func _buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out


## Presses the first enabled button, rebuilds, and repeats until the node closes.
func _click_through(d: Dictionary, limit := 40) -> void:
	var run: RunState = d.run
	var screen: Control = d.screen
	for i in limit:
		if NodeRules.is_done(run):
			break
		var live := _buttons(screen).filter(func(b): return not b.disabled)
		assert_true(not live.is_empty(), "a button to press (step %d)" % i)
		if live.is_empty():
			break
		live[i % live.size()].pressed.emit()
		screen.rebuild()
	assert_true(NodeRules.is_done(run), "screen reached the end (%s)" % run.node_state.get("event", run.node_state.get("kind")))
	assert_true(not d.session.sent.is_empty(), "sent actions")
	assert_true(_rejected(run).is_empty(), "no button sent an illegal action: %s" % str(_rejected(run)))
	screen.free()


func _rejected(run: RunState) -> Array:
	return run.log.filter(func(e): return e.type == "rejected")


func test_every_event_screen_plays_through() -> void:
	for id in EventData.EVENTS:
		var d := _setup("event", 2, id)
		d.run.act = 3
		_click_through(d)


func test_event_screen_solo() -> void:
	var d := _setup("event", 1, "supply_cache")
	_click_through(d)


func test_depot_screen() -> void:
	var d := _setup("depot")
	var buys := _buttons(d.screen).filter(func(b): return not b.disabled and b.text.begins_with("For "))
	assert_true(buys.size() >= 2, "buy buttons per soldier")
	buys[0].pressed.emit()
	assert_eq(d.session.sent[0].type, "node_buy", "buy sent")
	d.screen.rebuild()
	_click_through(d)


func test_hospital_screen() -> void:
	var d := _setup("hospital")
	d.run.squad()[0].hp = 1
	d.screen.rebuild()
	_click_through(d)
	assert_true(d.run.log.any(func(e): return e.type == "hospital_treat"), "treated someone")


func test_survivors_screen() -> void:
	var d := _setup("survivors", 3)
	_click_through(d)
	assert_true(d.run.node_state.claimed_by != -1, "recruit placed")
