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


## The squad panel's preview must say what the choice really does: for every event's first
## step, every option with no dice in it lands each soldier on the HP and Infection the
## preview promised.
func test_event_previews_match_outcomes() -> void:
	var checked := 0
	for id in EventData.EVENTS:
		var probe := _setup("event", 1, id)
		var opts := EventRules.options_for(probe.run, probe.run.node_state, 0)
		probe.screen.free()
		for o in opts:
			if not o.ok or "chance" in str(EventRules._option(probe.run.node_state, o.id).get("effects", [])):
				continue
			var d := _setup("event", 1, id)
			var run: RunState = d.run
			for r in run.squad():
				r.hp = maxi(1, r.max_hp - 2)
				r.infection = 40
			var action := {"type": "node_choose", "player": 0, "option": o.id}
			if o.target == "own_soldier":
				var ok := run.soldiers_of(0).filter(func(r): return NodeRules.validate(run, action.merged({"soldier": r.id})) == "")
				if ok.is_empty():
					d.screen.free()
					continue
				action.soldier = ok[0].id
			if NodeRules.validate(run, action) != "":
				d.screen.free()
				continue
			var preview := EventRules.preview(run, run.node_state, o.id, 0, action.get("soldier", -1))
			NodeRules.apply(run, action)
			for sid in preview:
				var rec = RunAccess.soldier(run, sid)
				if rec == null:
					continue
				if preview[sid].has("infection"):
					checked += 1
					assert_eq(rec.infection, preview[sid].infection, "%s/%s Infection" % [id, o.id])
				if preview[sid].has("hp"):
					checked += 1
					assert_eq(rec.hp, preview[sid].hp, "%s/%s HP" % [id, o.id])
			d.screen.free()
	assert_true(checked >= 8, "previews checked against outcomes (%d)" % checked)


func test_trial_preview_names_the_tier_jump() -> void:
	var d := _setup("event", 1, "the_trial")
	var run: RunState = d.run
	var rec: Dictionary = run.squad()[0]
	rec.infection = 41
	var p := EventRules.preview(run, run.node_state, "take", 0, rec.id)
	assert_eq(p[rec.id].infection, 56, "41 + 15")
	assert_eq(p[rec.id].mutation, 1, "one random mutation")
	assert_eq(Infection.tier(p[rec.id].infection), Infection.Tier.MUTATING, "crosses into Mutating")
	assert_true(EventRules.preview(run, run.node_state, "refuse", 0).is_empty(), "leaving them changes nobody")
	d.screen.free()


func test_squad_panel_shows_the_hovered_choice() -> void:
	var d := _setup("event", 1, "the_trial")
	var run: RunState = d.run
	var screen: Control = d.screen
	var panel = screen.squad_panel
	assert_true(panel != null, "event screen has a squad panel")
	assert_eq(panel._cards.size(), RunAccess.active_soldiers(run).size(), "a card per active soldier")
	var rec: Dictionary = run.soldiers_of(0)[0]
	var b: Button = _buttons(screen).filter(func(x): return x.text == rec.name)[0]
	b.mouse_entered.emit()
	assert_eq(panel._cards[rec.id].delta.get("infection", -1), mini(rec.infection + 15, 99), "hover previews the shot")
	for sid in panel._cards:
		if sid != rec.id:
			assert_true(panel._cards[sid].delta.is_empty(), "other soldiers untouched")
	b.mouse_exited.emit()
	assert_true(panel._cards[rec.id].delta.is_empty(), "leaving the button clears the preview")
	screen.free()


func test_hospital_and_depot_previews() -> void:
	var rec := {"hp": 3, "max_hp": 8, "injuries": 1, "infection": 52, "prog": {}}
	assert_eq(FieldHospital.preview(rec, "patch"), {"hp": 8, "injuries": 0}, "patch heals to full")
	assert_eq(FieldHospital.preview(rec, "purge").infection, 22, "purge takes 30")
	assert_eq(FieldHospital.preview(rec, "cure").infection, 0, "cure clears Infection")
	var d := _setup("depot", 1)
	assert_true(d.screen.squad_panel != null, "depot has a squad panel")
	var buy: Button = _buttons(d.screen).filter(func(b): return not b.disabled and b.text.begins_with("For "))[0]
	buy.mouse_entered.emit()
	var lit: Array = d.screen.squad_panel._cards.values().filter(func(c): return not c.delta.is_empty())
	assert_eq(lit.size(), 1, "the buyer's card previews the purchase")
	d.screen.free()
