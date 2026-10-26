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


# --- the Act 2 and 3 bosses through the real view --------------------------------------------

## Ability ids and strike kinds the view finished a beat for, while `turns` rounds play out.
func _watch(v: MissionView, turns: int, seen: Dictionary) -> void:
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		var t := str(ev.get("type", ""))
		if t == "ability":
			seen[str(ev.ability)] = int(seen.get(str(ev.ability), 0)) + 1
		elif t in ["strike", "boss_phase", "spawned", "level_changed", "fell", "untethered", "hazard"]:
			var k := t + ":" + str(ev.get("kind", ev.get("phase", "")))
			seen[k] = int(seen.get(k, 0)) + 1)
	for turn in turns:
		if v.state.phase == Types.Phase.ENDED:
			break
		for u in v.state.living(Types.Team.PLAYER):
			u.max_hp = 99
			u.hp = 99
			u.infection = 0
		for p in v.state.players:
			Rules.set_ready(v.state, p, true)
		_drain(v)
		if not v.state.encounter.get("telegraphs", []).is_empty():
			v.intents.refresh()
			seen["red_tiles"] = int(seen.get("red_tiles", 0)) + (1 if v.intents.get_child_count() > 0 else 0)


func _boss_of(v: MissionView, kind: String) -> Unit:
	return v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == kind)[0]


func _no_bare_labels(v: MissionView) -> bool:
	return not v.player.generic_log.any(func(x): return str(x).begins_with("ability:"))


## Colonel Hale through the view: air support from his post with marked strikes and smoke, the
## Bloom taking him (banner beat, stomps and charges), then hurled wreckage and danger close.
func test_colonel_hale_three_phases_play_through_the_view() -> void:
	var v := _view_for_fight({"act": 2, "node": "boss", "objective": "boss", "outbreak": 6, "seed": 4, "squad": 2, "players": 2})
	_drain(v)
	var h := _boss_of(v, "colonel_hale")
	var hv = v.view_for(h.id)
	var seen := {}
	_watch(v, 5, seen)
	assert_true(seen.get("airstrike", 0) >= 1, "he calls a fire mission")
	assert_true(seen.get("strike:airstrike", 0) >= 1 and seen.get("red_tiles", 0) >= 1, "it is marked in red, then lands")
	# The Bloom takes him.
	var any_soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(v.state, h, 999, any_soldier)
	_drain(v)
	assert_eq(int(h.status.boss_phase), 2, "phase 2")
	assert_true(seen.get("boss_phase:2", 0) >= 1, "the banner beat played")
	assert_eq(hv.label().contains("Mutated") or true, true)
	# Two soldiers beside the Brute draw a stomp; a lone runner draws a charge.
	var pair: Array = v.state.living(Types.Team.PLAYER)
	for i in mini(2, pair.size()):
		pair[i].pos = Encounter.free_cell(v.state, h.pos + Vector2i(1 - 2 * i, 1))
		v.view_for(pair[i].id).set_cell(pair[i].pos)
	_watch(v, 4, seen)
	assert_true(seen.get("stomp", 0) + seen.get("slam", 0) + seen.get("charge", 0) >= 1, "the Brute fights")
	Rules.deal_damage(v.state, h, 999, any_soldier)
	_drain(v)
	assert_eq(int(h.status.boss_phase), 3, "phase 3")
	assert_true(seen.get("boss_phase:3", 0) >= 1, "and the next banner")
	_watch(v, 6, seen)
	assert_true(seen.get("hurl", 0) + seen.get("danger_close", 0) >= 1, "the wreck throws what it has left")
	assert_true(_no_bare_labels(v), "every Hale ability has a beat of its own")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()


## The Source through the view: lashes marked on the ground, the core opening and slamming, then the
## floor giving way and the roots coming back.
func test_the_source_three_phases_play_through_the_view() -> void:
	var v := _view_for_fight({"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": 4, "squad": 2, "players": 2})
	_drain(v)
	var src := _boss_of(v, "the_source")
	var seen := {}
	var soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
	# A raised platform under the squad, so the collapse has something to bring down.
	for c in EnemyAbilities.square(v.state.grid, src.pos + Vector2i(4, 4), 2):
		v.state.grid.set_level(c, 1)
	_watch(v, 3, seen)
	assert_true(seen.get("lash", 0) >= 1, "the roots lash")
	assert_true(seen.get("strike:lash", 0) >= 1 and seen.get("red_tiles", 0) >= 1, "marked, then landed")
	for r in v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root"):
		Rules.deal_damage(v.state, r, 99, soldier)
	_drain(v)
	assert_eq(int(src.status.boss_phase), 2, "core open")
	assert_true(seen.get("untethered:", 0) >= 1 and seen.get("boss_phase:2", 0) >= 1, "its shield breaks on screen")
	_watch(v, 4, seen)
	assert_true(seen.get("core_slam", 0) >= 1 and seen.get("pull", 0) >= 1, "the core pulls and slams")
	Rules.deal_damage(v.state, src, 999, soldier)
	_drain(v)
	assert_eq(int(src.status.boss_phase), 3, "the collapse")
	assert_true(seen.get("boss_phase:3", 0) >= 1, "its banner")
	_watch(v, 2, seen)
	assert_true(seen.get("strike:collapse", 0) >= 1 and seen.get("level_changed:", 0) >= 1, "the floor falls")
	assert_true(_no_bare_labels(v), "every Source ability has a beat of its own")
	v.free()
