extends TestCase
## The faction packs through the real 3D view: every new ability and event plays its own beat (no bare
## labels), makes its sound, and leaves the picture the rules say it should. Built out of the tree like
## test_enemy_view.gd. Rules are in test_faction_packs.gd.

const MAIN := preload("res://scenes/main.tscn")
const IntentOverlay := preload("res://view/intent_overlay.gd")
const EnemyKit := preload("res://view/enemy_kit.gd")

var _types: Array[String] = []


func _view() -> MissionView:
	var s := make_state(["runner"])
	Vision.disable(s)   # about the beats, not fog of war
	var keep := true
	for u in s.living(Types.Team.ENEMY):
		if keep:   # one far-off Runner keeps the fight from ending; each test places the enemies it needs
			keep = false
			u.pos = Vector2i(s.grid.width - 1, 0)
			u.status.erase("alerted")
		else:
			u.hp = 0
	var v: MissionView = MAIN.instantiate()
	v.start(s)
	_drain(v)
	_types.clear()
	v.player.beat_finished.connect(func(ev: Dictionary) -> void: _types.append(str(ev.get("type", "")) + ":" + str(ev.get("ability", ""))))
	return v


func _drain(v: MissionView) -> void:
	var steps := 0
	while v.player.is_busy() and steps < 20000:
		v.player.advance(1.0 / 15.0)
		steps += 1


func _cell(s: GameState, dx: int, dy: int) -> Vector2i:
	return Encounter.free_cell(s, s.living(Types.Team.PLAYER)[0].pos + Vector2i(dx, dy))


func _enemy(s: GameState, spec: String, at: Vector2i) -> Unit:
	var u := s.add_unit(EnemyRoster.make(spec), at)
	u.status["alerted"] = true
	return u


func _act(v: MissionView, u: Unit, action: Dictionary) -> void:
	var s: GameState = v.state
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	assert_eq(Rules.validate(s, action), "", "legal: " + str(action.get("ability", action.get("type"))))
	Rules.apply(s, action)
	_drain(v)


func _beat(ability: String) -> bool:
	return _types.has("ability:" + ability)


func _no_bare_labels(v: MissionView, what: String) -> void:
	assert_true(not v.player.generic_log.any(func(x): return str(x).contains(what)), "no bare-label fallback for " + what)


func test_packrat_plates_come_off_with_a_clang() -> void:
	var v := _view()
	var s: GameState = v.state
	var sol: Unit = s.living(Types.Team.PLAYER)[0]
	var pr := _enemy(s, "packrat", _cell(s, 1, -3))
	_drain(v)
	Rules.deal_damage(s, pr, 4, sol)
	_drain(v)
	assert_true(_types.has("scrap:"), "the scrap beat played")
	assert_true(v.player.sfx_log.has("plate_clang"), "with a clang")
	assert_eq(v.view_for(pr.id).hp, pr.hp, "and the health bar follows")
	v.free()


func test_a_snare_is_laid_drawn_and_springs_with_its_own_beats() -> void:
	var v := _view()
	var s: GameState = v.state
	var sol: Unit = s.living(Types.Team.PLAYER)[0]
	var target := _cell(s, 0, -2)
	s.grid.tiles[(target.y - 1) * s.grid.width + target.x] = Types.Tile.LOW   # cover beside it
	var rig := _enemy(s, "rigger", _cell(s, 2, -4))
	_drain(v)
	_act(v, rig, {"type": Types.ABILITY, "unit": rig.id, "ability": "snare", "cell": target})
	assert_true(_beat("snare"), "the snare beat played")
	assert_true(v.player.sfx_log.has("grapple"), "with the line's sound")
	_no_bare_labels(v, "snare")
	s.phase = Types.Phase.TEAM
	v.intents.refresh()
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "snare"), "the snare is a danger tile")
	assert_true(v.intents.get_child_count() > 0, "and the overlay draws it")
	sol.actions_left = 2
	Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": target})
	_drain(v)
	assert_true(_types.has("snared:"), "the snared beat played")
	assert_eq(v.view_for(sol.id).cell, target, "the soldier's view stopped on the snare")
	Scavengers.lay_snare(s, rig, _cell(s, 3, -1))
	Encounter.kill(s, rig)
	_drain(v)
	assert_true(_types.has("snares_cut:"), "cutting the lines has a beat")
	v.free()


func test_a_flare_lights_the_squad_and_calls_cutters() -> void:
	var v := _view()
	var s: GameState = v.state
	s.encounter["concealment"] = {"on": true, "lost_turn": -1, "cause": ""}
	var sol: Unit = s.living(Types.Team.PLAYER)[0]
	var look := _enemy(s, "lookout", _cell(s, 0, -4))
	_drain(v)
	_act(v, look, {"type": Types.ABILITY, "unit": look.id, "ability": "flare", "target": sol.id})
	assert_true(_beat("flare"), "the flare beat played")
	assert_true(v.player.sfx_log.has("flare_pop"), "with the pop")
	assert_true(_types.has("concealment_lost:") and _types.has("reinforcements_incoming:"), "the squad is seen and the vents glow")
	_no_bare_labels(v, "flare")
	v.free()


func test_a_sergeants_order_puts_the_overwatcher_on_overwatch_on_screen() -> void:
	var v := _view()
	var s: GameState = v.state
	var sgt := _enemy(s, "sergeant", _cell(s, 0, -5))
	var ow := _enemy(s, "overwatcher", _cell(s, 2, -5))
	_drain(v)
	assert_true(not v.view_for(ow.id).overwatch, "not yet")
	_act(v, sgt, {"type": Types.ABILITY, "unit": sgt.id, "ability": "order"})
	assert_true(_beat("order"), "the order beat played")
	assert_true(v.player.sfx_log.has("order_call"), "with the call")
	assert_true(v.view_for(ow.id).overwatch, "the Overwatcher's view shows Overwatch")
	_no_bare_labels(v, "order")
	v.free()


func test_a_frag_arcs_in_and_goes_off_on_the_marked_tiles() -> void:
	var v := _view()
	var s: GameState = v.state
	var sol: Unit = s.living(Types.Team.PLAYER)[0]
	var gren := _enemy(s, "grenadier", _cell(s, 0, -6))
	_drain(v)
	_act(v, gren, {"type": Types.ABILITY, "unit": gren.id, "ability": "frag", "cell": sol.pos})
	assert_true(_beat("frag") and _types.has("telegraph:"), "the throw and its warning played")
	assert_true(v.player.sfx_log.has("satchel_arm"), "with the arming click")
	_no_bare_labels(v, "frag")
	s.phase = Types.Phase.TEAM
	v.intents.refresh()
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "frag" and d.cells.has(sol.pos)), "the 3x3 is marked red")
	var hp := sol.hp
	s.turn += 1
	Encounter._resolve_telegraphs(s)
	_drain(v)
	assert_true(_types.has("strike:") and sol.hp == hp - EnemyRoster.FRAG_DAMAGE, "and it goes off")
	v.free()


func test_a_fallen_guard_is_knelt_over_and_gets_back_up_on_screen() -> void:
	var v := _view()
	var s: GameState = v.state
	var guard := _enemy(s, "shieldman", _cell(s, 0, -5))
	var medic := _enemy(s, "field_medic", _cell(s, 3, -5))
	_drain(v)
	Encounter.kill(s, guard)
	_drain(v)
	assert_true(_types.has("downed:"), "the fall has its beat")
	if EnemyAbilities._cheb(medic.pos, guard.pos) > 1:
		_act(v, medic, {"type": Types.MOVE, "unit": medic.id, "to": _cell(s, 1, -5)})
	_act(v, medic, {"type": Types.ABILITY, "unit": medic.id, "ability": "revive"})
	assert_true(_beat("revive"), "the medic kneels with a beat")
	assert_true(v.intents != null and EnemyIntent.links(s).any(func(l): return l[0] == medic.id and l[1] == guard.id), "a line joins the medic and its patient")
	var kneel := s.turn
	s.turn = kneel + EnemyRoster.REVIVE_ROUNDS
	medic.actions_left = 2
	Encounter.on_unit_turn_start(s, medic)
	_drain(v)
	var up: Array = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "shieldman")
	assert_eq(up.size(), 1, "the Shieldman is up in the rules")
	assert_true(_types.has("revived:"), "the revived beat played")
	assert_true(v.view_for(up[0].id) != null and v.view_for(up[0].id).visible, "a view stands in the cell")
	assert_true(not v.view_for(guard.id).visible, "the body is gone from the floor")
	assert_eq(v.view_for(up[0].id).hp, up[0].hp, "on half health")
	v.free()


func test_a_tender_mends_machines_with_lines_and_numbers() -> void:
	var v := _view()
	var s: GameState = v.state
	var tender := _enemy(s, "tender", _cell(s, 0, -5))
	var loader := _enemy(s, "loader", _cell(s, 2, -5))
	var hound := _enemy(s, "hound", _cell(s, 4, -5))
	loader.hp = 3
	hound.hp = 1
	v.view_for(loader.id).set_hp(3)
	v.view_for(hound.id).set_hp(1)
	_drain(v)
	_act(v, tender, {"type": Types.ABILITY, "unit": tender.id, "ability": "repair"})
	assert_true(_beat("repair"), "the repair beat played")
	assert_true(v.player.sfx_log.has("emitter_hum"), "with the hum")
	assert_eq(v.view_for(loader.id).hp, 3 + EnemyRoster.REPAIR_HEAL, "the Loader's health bar rose")
	assert_eq(v.view_for(hound.id).hp, mini(hound.max_hp, 1 + EnemyRoster.REPAIR_HEAL), "so did the Hound's")
	_no_bare_labels(v, "repair")
	v.free()


func test_a_carrier_drops_hounds_with_dust_not_spores() -> void:
	var v := _view()
	var s: GameState = v.state
	var carrier := _enemy(s, "carrier", _cell(s, 0, -6))
	_drain(v)
	s.turn = 2
	Encounter._run_spawners(s)
	_drain(v)
	var hounds: Array = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "hound")
	assert_eq(hounds.size(), EnemyRoster.CARRIER_DROP, "two Hounds in the rules")
	for h in hounds:
		assert_true(v.view_for(h.id) != null and v.view_for(h.id).visible, "and in the view")
	assert_true(v.player.sfx_log.has("gadget_deploy"), "they arrive with the bay sound, not the Infected sting")
	s.phase = Types.Phase.TEAM
	var it: Dictionary = EnemyIntent.intents(s).filter(func(i): return i.unit == carrier.id)[0]
	assert_eq(it.icon, "spawn", "the Carrier's intent is its countdown")
	v.free()


func test_an_arc_cracks_to_the_target_and_jumps() -> void:
	var v := _view()
	var s: GameState = v.state
	var squad := s.living(Types.Team.PLAYER)
	var welder := _enemy(s, "arc_welder", _cell(s, 0, -3))
	_drain(v)
	var target: Unit = squad[0]
	welder.pos = _cell(s, 1, -2)
	var hp := {}
	for u in squad:
		hp[u.id] = u.hp
	_act(v, welder, {"type": Types.ABILITY, "unit": welder.id, "ability": "arc", "target": target.id})
	assert_true(_beat("arc"), "the arc beat played")
	assert_true(v.player.sfx_log.has("whiz_zap"), "with the crack")
	assert_true(target.hp < hp[target.id], "the target is hurt")
	assert_eq(v.view_for(target.id).hp, target.hp, "and its bar follows")
	_no_bare_labels(v, "arc")
	v.free()


func test_every_new_intent_has_a_word() -> void:
	for icon in ["snare", "flare", "order", "frag", "revive", "repair", "arc"]:
		assert_true(IntentOverlay.ICON_TEXT.has(icon), icon + " has an intent word")
	for k in ["packrat", "rigger", "lookout", "sergeant", "grenadier", "field_medic", "tender", "carrier", "arc_welder"]:
		assert_true(EnemyKit.has(k), k + " has its own rig")
		assert_true(EnemyKit.body_of(k) != "", k + " has a body")
