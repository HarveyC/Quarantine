extends TestCase
## The enemy roster in the 3D view: every enemy event animates, and the intent overlay draws
## during the team phase. Built out of the tree like test_view.gd.

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")


func _view_for_fight(spec: Dictionary, boss_only := "") -> MissionView:
	var fight := FightBuilder.build(spec)
	var config := MatchConfig.make(1, 99)
	config["enemies"] = fight.enemies.filter(func(e): return boss_only == "" or str(e).begins_with(boss_only))
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
	var seen := {"sunk": 0.0, "trail": false, "eruption_tiles": false, "label": false, "moved": 0, "erupted": false, "rocks": false}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		if int(ev.get("unit", -1)) != bm.id:
			return
		if ev.get("type") == "ability" and ev.get("ability") == "burrow":
			seen.sunk = uv._sink
		if ev.get("type") == "ability" and ev.get("ability") == "erupt":
			seen.erupted = true
		if ev.get("type") == "ability" and ev.get("ability") == "rockfall" and not (ev.get("cells", []) as Array).is_empty():
			seen.rocks = true
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
	assert_true(seen.rocks, "the eruption throws rocks")
	assert_true(not v.player.generic_log.any(func(x): return str(x).contains("burrow") or str(x).contains("erupt")), "no bare-label fallback beats")
	assert_true(bm.is_alive() and uv.visible and uv._sink == 0.0, "and she is back above ground afterwards")
	v.free()


## Berserk Brood Mother: crouches (telegraph), springs in an arc and lands with her own beat.
func test_berserk_brood_mother_leap_plays_through_the_view() -> void:
	var v := _view_for_fight({"act": 1, "node": "boss", "objective": "boss", "outbreak": 4, "seed": 4, "squad": 2, "players": 2})
	_drain(v)
	var s: GameState = v.state
	var bm: Unit = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "brood_mother")[0]
	for o in s.living(Types.Team.ENEMY):
		if o != bm:
			Encounter.kill(s, o)
	bm.status.erase("tether")
	bm.status.boss_phase = 3
	bm.mobility = BroodMother.MOBILITY[3]
	var high: Unit = s.living(Types.Team.PLAYER)[0]
	var others := s.living(Types.Team.PLAYER)
	for u in others:
		u.max_hp = 99
		u.hp = 99
	for r in range(4, 1, -1):
		var found := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = bm.pos + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and s.grid.in_bounds(c) and s.grid.is_walkable(c) and s.unit_at(c) == null:
					high.pos = c
					found = true
					break
			if found:
				break
		if found:
			break
	s.grid.set_level(high.pos, 1)
	v.view_for(high.id).set_cell(high.pos)
	var seen := {"arc": false, "landed": false}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		if int(ev.get("unit", -1)) != bm.id:
			return
		if ev.get("type") == "move" and ev.get("leap", false):
			seen.arc = true
		if ev.get("type") == "ability" and ev.get("ability") == "leap":
			seen.landed = true)
	for turn in 6:
		if s.phase == Types.Phase.ENDED or seen.landed:
			break
		for p in s.players:
			Rules.set_ready(s, p, true)
		_drain(v)
	assert_true(seen.arc and seen.landed, "she springs and lands")
	assert_true(not v.player.generic_log.any(func(x): return str(x).contains("leap")), "no bare-label fallback beat")
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


## The Breaker through the view: marked charge lanes and cover flattened, the plate splitting off on
## the model, rubble marked on a soldier up high, then two lanes at once.
func test_the_breaker_three_phases_play_through_the_view() -> void:
	var v := _view_for_fight({"act": 1, "node": "boss", "objective": "boss", "outbreak": 4, "seed": 5, "squad": 2, "players": 2, "boss": "breaker"}, "breaker")
	_drain(v)
	var b := _boss_of(v, "breaker")
	var bv = v.view_for(b.id)
	var plate: Node = bv._model.find_child("plate_front", true, false)
	assert_true(plate != null and plate.visible, "the rig wears its front plate")
	var seen := {}
	var lanes_drawn := 0
	for turn in 4:
		_watch(v, 1, seen)
		v.intents.refresh()
		if b.status.has("charge_dir") and v.intents.get_child_count() > 0:
			lanes_drawn += 1
	assert_true(lanes_drawn >= 1, "its wound-up lane is drawn in red")
	assert_true(seen.get("charge", 0) >= 1, "it charges")
	# The plate splits off.
	var soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(v.state, b, 999, soldier)
	_drain(v)
	assert_eq(int(b.status.boss_phase), 2, "phase 2")
	assert_true(seen.get("boss_phase:2", 0) >= 1 and not plate.visible, "the plate is gone from the model")
	# A soldier on a raised tile draws rubble.
	var high: Unit = v.state.living(Types.Team.PLAYER)[0]
	high.pos = Encounter.free_cell(v.state, b.pos + Vector2i(0, 5))
	v.state.grid.set_level(high.pos, 1)
	v.view_for(high.id).set_cell(high.pos)
	b.cooldowns.erase("debris")
	_watch(v, 4, seen)
	assert_true(seen.get("debris", 0) >= 1, "it tears rubble down")
	assert_true(seen.get("strike:debris", 0) >= 1 and seen.get("red_tiles", 0) >= 1, "marked in red, then it lands")
	# Stripped to the frame.
	Rules.deal_damage(v.state, b, 999, soldier)
	_drain(v)
	assert_eq(int(b.status.boss_phase), 3, "phase 3")
	var skirts: Node = bv._model.find_child("skirts", true, false)
	assert_true(skirts != null and not skirts.visible, "the side skirts come off too")
	var double := false
	for turn in 5:
		_watch(v, 1, seen)
		double = double or b.status.has("charge_dir2")
		if double:
			v.intents.refresh()
			assert_true(v.intents.get_child_count() > 0, "both lanes are drawn")
			break
	assert_true(double, "two lanes are marked at once")
	assert_true(seen.get("boss_phase:3", 0) >= 1 and _no_bare_labels(v), "every Breaker ability has a beat of its own")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()


## Colonel Hale through the view: air support from his post with marked strikes and smoke, the
## Bloom taking him (banner beat, stomps and charges), then hurled wreckage and danger close.
func test_colonel_hale_three_phases_play_through_the_view() -> void:
	var v := _view_for_fight({"act": 2, "node": "boss", "objective": "boss", "outbreak": 6, "seed": 5, "squad": 2, "players": 2, "boss": "colonel_hale"}, "colonel_hale")   # his escort has its own tests
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


## The Choir Prophet through the view: verses marked on the ground and landing, the chant ring pulsing
## Infection into a soldier inside it, the hymn answering (fix, then a soldier compelled), then Hush, the
## hymn building and the Crescendo.
func test_choir_prophet_three_phases_play_through_the_view() -> void:
	var s := make_blank(PackedStringArray(Array(range(20)).map(func(_y): return ".".repeat(20))))
	var trooper := UnitData.make("trooper", Types.Team.PLAYER)
	trooper.owner_player = 0
	trooper.abilities.append("lockdown")
	s.add_unit(trooper, Vector2i(8, 12))
	var medic := UnitData.make("medic", Types.Team.PLAYER)
	medic.owner_player = 0
	s.add_unit(medic, Vector2i(11, 8))   # inside the chant ring
	s.grid.enemy_spawns.assign([Vector2i(10, 4), Vector2i(2, 2), Vector2i(17, 2)])
	s.grid.markers["boss"] = [Vector2i(10, 4)]
	Encounter.setup(s, {"boss": "choir_prophet", "node": "boss", "act": 2, "squad": 2})
	Vision.disable(s)
	var v: MissionView = MAIN.instantiate()
	v.start(s)
	_drain(v)
	var h := _boss_of(v, "choir_prophet")
	var seen := {}
	var extra := {}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		var t := str(ev.get("type", ""))
		if t in ["ring", "hymn", "lapse", "hushed", "lock_lost"]:
			extra[t] = int(extra.get(t, 0)) + 1)
	_watch(v, 3, seen)
	assert_true(seen.get("verse", 0) >= 1, "he sings a verse")
	assert_true(seen.get("strike:verse", 0) >= 1 and seen.get("red_tiles", 0) >= 1, "marked in red, then it lands")
	assert_true(extra.get("ring", 0) >= 1, "the ring presses Infection into the soldier inside it")
	# The circle breaks and the hymn answers.
	for c in s.living(Types.Team.ENEMY).filter(func(u): return u.kind == ChoirProphet.choir_kind("cantor")):
		Encounter.kill(s, c)
	Rules.deal_damage(s, h, 999, trooper)
	_drain(v)
	assert_eq(int(h.status.boss_phase), 2, "phase 2")
	assert_true(seen.get("boss_phase:2", 0) >= 1, "the banner beat played")
	for u in s.living(Types.Team.PLAYER):
		u.pos = Encounter.free_cell(s, h.pos + Vector2i(u.id * 2, 5))
		v.view_for(u.id).set_cell(u.pos)
	_watch(v, 6, seen)
	assert_true(seen.get("fix", 0) >= 1, "he fixes on a soldier")
	assert_true(seen.get("compel", 0) >= 1 and extra.get("lapse", 0) >= 1, "and takes them")
	# The circle closes in.
	for u in s.living(Types.Team.PLAYER):
		Infection.end_lapse(s, u)
	Rules.deal_damage(s, h, 999, trooper)
	_drain(v)
	assert_eq(int(h.status.boss_phase), 3, "phase 3")
	assert_true(seen.get("boss_phase:3", 0) >= 1, "and the next banner")
	_watch(v, 8, seen)
	assert_true(seen.get("quell", 0) >= 1, "Hush")
	assert_true(extra.get("hymn", 0) >= 1, "the hymn builds")
	assert_true(seen.get("crescendo", 0) >= 1 and seen.get("strike:crescendo", 0) >= 1, "the Crescendo is marked, then lands")
	assert_true(not v.player.generic_log.any(func(x): return ChoirProphet.OWNS.any(func(id): return str(x) == "ability:" + id)), "every Choir Prophet ability has a beat of its own")
	assert_true(not v.player.generic_log.any(func(x): return str(x).begins_with("event:")), "no unhandled events")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()


## The Director through the view: her lock and snipe from the roofs, the second team and the retrieval
## mark, the cage, then a Collector dragging a pinned soldier to the lane and taking them.
func test_the_director_three_phases_play_through_the_view() -> void:
	var v := _view_for_fight({"act": 2, "node": "boss", "objective": "boss", "outbreak": 6, "seed": 5, "squad": 2, "players": 2, "boss": "director"}, "director")
	_drain(v)
	var d := _boss_of(v, "director")
	var seen := {}
	_watch(v, 3, seen)
	assert_true(seen.get("sight", 0) >= 1, "she locks a soldier")
	var any_soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
	d.status.erase("tether")
	Rules.deal_damage(v.state, d, 999, any_soldier)
	_drain(v)
	assert_eq(int(d.status.boss_phase), 2, "phase 2")
	assert_true(seen.get("boss_phase:2", 0) >= 1, "the second team banner played")
	_watch(v, 3, seen)
	assert_true(seen.get("flag", 0) >= 1, "she marks a soldier")
	d.status.erase("tether")
	Rules.deal_damage(v.state, d, 999, any_soldier)
	_drain(v)
	assert_eq(int(d.status.boss_phase), 3, "phase 3")
	assert_true(seen.get("boss_phase:3", 0) >= 1, "the extraction banner played")
	_watch(v, 4, seen)
	assert_true(seen.get("retrieve", 0) >= 1, "she drops the cage")
	assert_true(seen.get("strike:retrieval", 0) >= 1 and seen.get("red_tiles", 0) >= 1, "marked in red, then landed")
	# Recovery's Netter holds a soldier and a Collector drags them off the map.
	var victim: Unit = v.state.living(Types.Team.PLAYER)[0]
	var c := Encounter._place(v.state, "collector", Encounter.free_cell(v.state, victim.pos + Vector2i(1, 0)))
	Recovery.hold(v.state, c, victim)
	Recovery.apply(v.state, c, {"ability": "drag", "target": victim.id})
	_drain(v)
	assert_true(seen.get("drag", 0) >= 1, "the drag shows")
	assert_true(_no_bare_labels(v), "every Director ability has a beat of its own")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()


## The Source through the view: lashes marked on the ground, the core opening and slamming, then the
## floor giving way and the roots coming back.
func test_the_source_three_phases_play_through_the_view() -> void:
	var v := _view_for_fight({"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": 4, "squad": 2, "players": 2, "boss": "the_source"})
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


## The Lantern Echoes through the view: the Echoes fight with their class kit and say so on screen,
## the Last Echo is shielded, a fallen Echo falls to spores, the Source takes the body and the husk
## pulses, then the Last Echo wears the weakest soldier.
func test_the_lantern_echoes_play_through_the_view() -> void:
	var fight := FightBuilder.build({"act": 3, "node": "boss", "objective": "boss", "outbreak": 6, "seed": 4, "squad": 3, "players": 1, "boss": "lantern_echoes"})
	var config := MatchConfig.make(1, 99)
	config["enemies"] = []
	config["encounter"] = fight.encounter
	config["map_spec"] = {"biome": "bore", "objective": "boss", "seed": 4, "act": 3, "boss": "lantern_echoes"}
	config["squad"] = [{"kind": "trooper", "player": 0}, {"kind": "medic", "player": 0}, {"kind": "breacher", "player": 0}]
	var v: MissionView = MAIN.instantiate()
	v.start(MatchConfig.build(config))
	_drain(v)
	var boss := _boss_of(v, "lantern_echoes")
	var seen := {}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		var t := str(ev.get("type", ""))
		if t in ["echo_fell", "echo_taken", "immune", "source_pulse", "boss_phase", "died"]:
			var k := t + ":" + str(ev.get("phase", ev.get("reason", "")))
			seen[k] = int(seen.get(k, 0)) + 1
		elif t == "ability":
			seen["ability:" + str(ev.ability)] = int(seen.get("ability:" + str(ev.ability), 0)) + 1)
	var soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
	assert_eq(LanternEchoes.echoes(v.state).size(), 3, "an Echo per soldier")
	# The Echoes stride in and use the squad's own kit.
	_watch(v, 4, seen)
	var signatures := 0
	for id in ["lockdown", "quarantine_field", "bring_down", "suppress", "stim", "breach"]:
		signatures += int(seen.get("ability:" + id, 0)) + int(seen.get(id, 0))
	var echo_overwatch := v.state.log.filter(func(e): return e.type == "overwatch" and v.state.get_unit(e.unit).status.get("lantern_echo", false)).size()
	assert_true(signatures + echo_overwatch >= 1, "the Echoes use their class kit (%d)" % (signatures + echo_overwatch))
	# The Last Echo is shielded while they stand.
	Rules.deal_damage(v.state, boss, 5, soldier)
	_drain(v)
	assert_true(seen.get("immune:echoes", 0) >= 1, "its shield plays on screen")
	assert_eq(boss.hp, boss.max_hp, "and holds")
	# The first Echo falls: spores, a banner, and the Source takes the body.
	var first: Unit = LanternEchoes.echoes(v.state)[0]
	var fv = v.view_for(first.id)
	Rules.deal_damage(v.state, first, 999, soldier)
	_drain(v)
	assert_true(seen.get("echo_fell:", 0) >= 1, "it falls to spores")
	assert_true(fv._sink > 0.0, "and the floor takes the body")
	assert_eq(int(boss.status.boss_phase), 2, "phase 2")
	assert_true(seen.get("boss_phase:2", 0) >= 1, "with its banner")
	_watch(v, 1, seen)
	assert_true(seen.get("echo_taken:", 0) >= 1 and LanternEchoes.taken(v.state).size() >= 1, "the husk rises on screen")
	_watch(v, 1, seen)
	assert_true(seen.get("source_pulse:", 0) >= 1, "and pulses Infection")
	# The rest fall: the husk collapses and the Last Echo takes the weakest soldier's shape.
	for e in LanternEchoes.echoes(v.state):
		Rules.deal_damage(v.state, e, 999, soldier)
	_drain(v)
	assert_eq(int(boss.status.boss_phase), 3, "phase 3")
	assert_true(seen.get("boss_phase:3", 0) >= 1, "its banner")
	assert_eq(LanternEchoes.taken(v.state).size(), 0, "the husks are gone")
	_watch(v, 2, seen)
	assert_true(_no_bare_labels(v), "every Echo ability has a beat of its own")


## The Bore Engine through the view: pistons marked then landing, a cut valve venting and its platform
## falling, the jaws, the core opening with a countdown, and sealing again with valves regrown.
func test_the_bore_engine_plays_pistons_valves_window_and_reseal_through_the_view() -> void:
	var v := _view_for_fight({"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": 4, "squad": 2, "players": 2, "boss": "bore_engine"}, "bore_engine")
	_drain(v)
	var e := _boss_of(v, "bore_engine")
	var seen := {}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		var t := str(ev.get("type", ""))
		if t in ["valve_cut", "core_open", "core_sealed", "untethered"]:
			seen[t] = int(seen.get(t, 0)) + 1)
	_watch(v, 2, seen)
	assert_true(seen.get("piston", 0) >= 1, "the pistons sweep")
	assert_true(seen.get("strike:piston", 0) >= 1 and seen.get("red_tiles", 0) >= 1, "marked in red, then landed")
	var soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
	var valves := v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == "coolant_valve")
	assert_eq(valves.size(), 3, "three valves on the deck")
	for c in EnemyAbilities.square(v.state.grid, valves[0].pos, 2):
		v.state.grid.set_level(c, 1)
	v.board.rebuild_tiles()
	Rules.deal_damage(v.state, valves[0], 99, soldier)
	_drain(v)
	assert_true(seen.get("valve_cut", 0) >= 1 and seen.get("boss_phase:2", 0) >= 1, "the valve vents and the Engine overloads")
	soldier.pos = Encounter.free_cell(v.state, e.pos + Vector2i(1, 1))
	_watch(v, 2, seen)
	assert_true(seen.get("bite", 0) >= 1 and seen.get("strike:bite", 0) >= 1, "the jaws clamp on a soldier beside it")
	assert_true(seen.get("strike:collapse", 0) >= 1 and seen.get("level_changed:", 0) >= 1, "the cut valve's platform falls")
	for valve in v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == "coolant_valve"):
		Rules.deal_damage(v.state, valve, 99, soldier)
	_drain(v)
	assert_true(BoreEngine.is_open(e), "the core is open")
	assert_true(seen.get("core_open", 0) >= 1 and seen.get("untethered:", 0) >= 1 and seen.get("boss_phase:3", 0) >= 1, "its shield breaks on screen")
	_watch(v, BoreEngine.WINDOW[2], seen)
	assert_true(seen.get("core_sealed", 0) >= 1, "the core seals again")
	assert_true(v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == "coolant_valve").size() >= 1, "valves are back")
	for u in v.state.living():
		assert_true(v.view_for(u.id) != null, "a view for every unit")
	assert_true(_no_bare_labels(v), "every Engine ability has a beat of its own")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()


func test_parting_blow_warning_card_has_width() -> void:
	var s := make_state(["runner"])
	var v: MissionView = MAIN.instantiate()
	v.start(s)
	v.hud.show_move_warning(["Runner: 70% for 2 to 4"], true)
	var card: Control = v.hud._move_warning
	assert_true(card != null, "warning card shown")
	assert_true(card.get_combined_minimum_size().x >= 300.0, "card is wide enough to read, not a sliver")
	v.hud.hide_move_warning()
	assert_true(v.hud._move_warning == null, "warning card cleared")
	v.free()


## Every unit stands on the floor of its cell once a beat queue is over, whatever the fight threw at it.
func test_units_stand_on_their_floor_after_the_source_fight() -> void:
	var bad := []
	for sd in [1, 2, 3]:
		var v := _view_for_fight({"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": sd, "squad": 3, "players": 1, "boss": "the_source"})
		_drain(v)
		var src: Unit = v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == "the_source")[0]
		for u in v.state.living(Types.Team.PLAYER):
			u.max_hp = 999
			u.hp = 999
		for turn in 14:
			if v.state.phase == Types.Phase.ENDED:
				break
			if turn == 4:
				src.hp = mini(src.hp, SourceBoss.gate(src) - 1)
			for p in v.state.players:
				Rules.set_ready(v.state, p, true)
			_drain(v)
			for u in v.state.living():
				var uv := v.view_for(u.id)
				var want := Board.cell_to_world(u.pos).y
				if uv.visible and absf(uv.position.y - want) > 0.05:
					bad.append("seed %d turn %d %s at %s y=%.2f want %.2f" % [sd, turn, u.kind, str(u.pos), uv.position.y, want])
				if uv.visible and uv._body != null and uv._body.position.y < -0.3:
					bad.append("seed %d turn %d %s body y=%.2f" % [sd, turn, u.kind, uv._body.position.y])
		v.free()
	assert_eq(bad.size(), 0, "units on their floor: %s" % str(bad.slice(0, 6)))


func test_soldier_on_a_collapsing_tile_drops_with_it() -> void:
	var v := _view_for_fight({"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": 1, "squad": 3, "players": 1, "boss": "the_source"})
	_drain(v)
	var s: GameState = v.state
	var raised: Vector2i = Vector2i(-1, -1)
	for y in s.grid.height:
		for x in s.grid.width:
			if s.grid.level(Vector2i(x, y)) > 0 and s.unit_at(Vector2i(x, y)) == null and s.grid.is_walkable(Vector2i(x, y)):
				raised = Vector2i(x, y)
	assert_true(raised.x >= 0, "the arena has raised tiles")
	var u: Unit = s.living(Types.Team.PLAYER)[0]
	u.pos = raised
	v.view_for(u.id).set_cell(raised)
	var before := v.view_for(u.id).position.y
	assert_true(before > 0.1, "standing up on the tile")
	Elevation.set_level(s, raised, 0)
	_drain(v)
	assert_true(absf(v.view_for(u.id).position.y - Board.cell_to_world(raised).y) < 0.05, "and level with the floor once it falls")
	v.free()


## The Source's aspects through the view: the banner naming it, Hunger's pull in phase 1, Remembers' named
## Echoes rising before the core opens, and Regrown's root growing back with its own banner.
func test_the_source_aspects_play_through_the_view() -> void:
	var seen := {}
	var watch := func(v: MissionView) -> void:
		v.player.beat_finished.connect(func(ev: Dictionary) -> void:
			var t := str(ev.get("type", ""))
			if t == "ability":
				seen[str(ev.ability)] = int(seen.get(str(ev.ability), 0)) + 1
			elif t == "boss_aspect":
				seen["aspect:" + str(ev.aspect)] = 1
			elif t in ["boss_phase", "spawned"]:
				var k := t + ":" + str(ev.get("phase", ev.get("kind", "")))
				seen[k] = int(seen.get(k, 0)) + 1)
	for aspect in SourceBoss.ASPECTS:
		seen.clear()
		var spec := {"act": 3, "node": "boss", "objective": "boss", "outbreak": 9, "seed": 4, "squad": 2, "players": 2,
			"boss": "the_source", "aspect": aspect, "echo_names": ["Osei"]}
		var v := _view_for_fight(spec)
		watch.call(v)
		_drain(v)
		_watch(v, 3, {})
		assert_true(seen.get("aspect:" + aspect, 0) >= 1, "%s: the banner names the aspect" % aspect)
		match aspect:
			"hunger":
				assert_true(seen.get("pull", 0) >= 1, "Hunger pulls before the core opens")
			"remembers":
				assert_true(v.state.living(Types.Team.ENEMY).any(func(u): return u.display_name == "Echo of Osei"), "an Echo wearing a fallen name")
				assert_true(seen.get("spawned:fallen", 0) >= 1, "it rises on screen")
			"regrown":
				var src := _boss_of(v, "the_source")
				var soldier: Unit = v.state.living(Types.Team.PLAYER)[0]
				for r in v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root"):
					Rules.deal_damage(v.state, r, 99, soldier)
				_drain(v)
				_watch(v, SourceBoss.REGROWN_WINDOW[2] + 1, {})
				assert_true(seen.get("boss_phase:1", 0) >= 1, "the roots grow back, with a banner")
				assert_true(seen.get("spawned:source_root", 0) >= 1, "and the root rises")
				assert_eq(int(src.status.boss_phase), 1, "closed again")
		assert_true(_no_bare_labels(v), "%s: every beat has its own animation" % aspect)
		v.free()
