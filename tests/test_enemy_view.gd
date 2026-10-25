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
			drew = drew or v.intents.get_child_count() > 0
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


## The Brood Mother's phase 2 through the real view: she walks up and claws, dives with a visible
## sink, the dig trail and eruption tiles are drawn, and she bursts up out of the floor again.
func test_brood_mother_phase_2_plays_burrow_trail_and_eruption() -> void:
	var v := _view_for_fight({"act": 1, "node": "boss", "objective": "boss", "outbreak": 4, "seed": 4, "squad": 2, "players": 2})
	_drain(v)
	var s: GameState = v.state
	var bm: Unit = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "brood_mother")[0]
	for o in s.living(Types.Team.ENEMY):
		if o.kind == "egg_sac":
			Encounter.kill(s, o)
	bm.status.erase("tether")
	bm.status.boss_phase = 2
	bm.mobility = BroodMother.MOBILITY[2]
	bm.hp = BroodMother.gates(bm)[0]
	for u in s.living(Types.Team.PLAYER):
		u.max_hp = 99
		u.hp = 99
	var uv = v.view_for(bm.id)
	var seen := {"sunk": 0.0, "trail": false, "eruption_tiles": false, "label": false, "moved": 0, "erupted": false}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		if int(ev.get("unit", -1)) != bm.id:
			return
		if ev.get("type") == "ability" and ev.get("ability") == "burrow":
			seen.sunk = uv._sink
		if ev.get("type") == "ability" and ev.get("ability") == "erupt":
			seen.erupted = true
		if ev.get("type") == "move" and ev.get("tunnel", false):
			seen.moved += 1)
	var walked := 0
	var last := bm.pos
	for turn in 14:
		if s.phase == Types.Phase.ENDED:
			break
		for p in s.players:
			Rules.set_ready(s, p, true)
		_drain(v)
		if bm.pos != last and not seen.erupted:
			walked += 1
		last = bm.pos
		if bm.status.has("emerge_cell"):
			v.intents.refresh()
			var kinds: Array = EnemyIntent.dangers(s).map(func(d): return d.kind)
			seen.trail = seen.trail or (kinds.has("trail") and kinds.has("erupt"))
			seen.eruption_tiles = seen.eruption_tiles or v.intents.get_child_count() > 0
			for c in v.intents.get_children():
				if c is Label3D and (c as Label3D).text == "ERUPTS":
					seen.label = true
	assert_true(walked >= 1, "she walks up to the squad on her surfaced turns")
	assert_eq(seen.sunk, 1.0, "the dive sinks her fully into the floor")
	assert_true(seen.trail and seen.eruption_tiles, "the dig trail and the eruption tiles are drawn")
	assert_true(seen.label, "the eruption is labelled")
	assert_true(seen.erupted and seen.moved >= 1, "she tunnels under and erupts")
	assert_true(not v.player.generic_log.any(func(x): return str(x).contains("burrow") or str(x).contains("erupt")), "no bare-label fallback beats")
	assert_true(bm.is_alive() and uv.visible and uv._sink == 0.0, "and she is back above ground afterwards")
	v.free()
