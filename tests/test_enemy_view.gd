extends TestCase
## The enemy roster in the 3D view: every enemy event animates, and the intent overlay draws
## during the team phase. Built out of the tree like test_view.gd.

const MAIN := preload("res://scenes/main.tscn")


func _view_for_fight(spec: Dictionary) -> MissionView:
	var fight := FightBuilder.build(spec)
	var config := MatchConfig.make(1, 99)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	var v: MissionView = MAIN.instantiate()
	v.start(MatchConfig.build(config))
	return v


func _drain(v: MissionView) -> void:
	var steps := 0
	while v.player.is_busy() and steps < 20000:
		v.player.advance(1.0 / 15.0)
		steps += 1


func test_enemy_fights_play_through_the_view() -> void:
	var specs := [
		{"act": 3, "node": "nest", "objective": "hold", "outbreak": 10, "seed": 4},
		{"act": 1, "node": "boss", "objective": "boss", "outbreak": 4, "seed": 4},
		{"act": 2, "node": "boss", "objective": "boss", "outbreak": 7, "seed": 4},
		{"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": 4},
	]
	for sp in specs:
		var v := _view_for_fight(sp)
		_drain(v)
		var drew := false
		for turn in 6:
			if v.state.phase == Types.Phase.ENDED:
				break
			v.intents.refresh()
			drew = drew or v.intents.get_child_count() > 0 or not v.intents.labels.is_empty()
			for p in v.state.players:
				Rules.set_ready(v.state, p, true)
			_drain(v)
		assert_true(drew, "intent overlay drew something (%s act %d)" % [sp.node, sp.act])
		assert_true(not v.player.is_busy(), "queue drained")
		for u in v.state.units:
			var uv := v.view_for(u.id)
			assert_true(uv != null, "view for every unit")
			if u.is_alive() and not u.status.get("hidden", false):
				assert_eq(uv.cell, u.pos, "view cell matches state (%s)" % u.kind)
		v.free()


func test_hidden_lurker_is_not_drawn_until_revealed() -> void:
	var s := make_state(["lurker", "runner"])
	Vision.disable(s)   # about the Lurker's own stealth, not fog of war (test_vision.gd)
	var v: MissionView = MAIN.instantiate()
	v.start(s)
	_drain(v)
	var l: Unit = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "lurker")[0]
	assert_true(not v.view_for(l.id).visible, "hidden")
	Encounter.reveal(s, l)
	_drain(v)
	assert_true(v.view_for(l.id).visible, "revealed")
	v.free()
