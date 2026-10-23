extends TestCase
## View/HUD tests. The runner works inside SceneTree._init, before the tree is live,
## so these build the main scene out of the tree and drive the event player's clock
## by hand. test_main_scene_enters_tree also adds one instance to the real root so
## its _ready runs on the first frame (script errors there fail run.sh).

const MAIN := preload("res://scenes/main.tscn")


func _make_view(begin := true) -> MissionView:
	var v: MissionView = MAIN.instantiate()
	v.start(MissionView.default_mission(1234), begin)
	return v


func test_main_scene_builds_views_and_hud() -> void:
	var v := _make_view()
	assert_eq(v.unit_views.size(), v.state.units.size(), "one view per unit")
	assert_eq(v.hud.panels.size(), 2, "one panel per player")
	assert_true(v.player.is_busy(), "mission start queued events")
	v.player.flush()
	assert_true(not v.player.is_busy(), "queue drained")
	assert_true(v.hud.combat_log.line_count() > 0, "log has lines")
	for u in v.state.units:
		assert_eq(v.view_for(u.id).cell, u.pos, "view cell matches state for %d" % u.id)
	v.free()


func test_move_animates_from_event_path() -> void:
	var v := _make_view()
	v.player.flush()
	var u := v.state.controllable_units(0)[0]
	var uv := v.view_for(u.id)
	var start := u.pos
	var to := u.pos + Vector2i(0, -2)
	assert_true(Rules.apply(v.state, {"type": Types.MOVE, "unit": u.id, "to": to}), "move accepted")
	assert_eq(uv.cell, start, "view waits for the queue")
	assert_true(not v.input.can_act(), "input locked while playing")
	v.player.advance(0.14)
	assert_true(uv.position.z < float(start.y) and uv.position.z > float(to.y), "mid-path position")
	v.player.flush()
	assert_eq(uv.cell, to, "arrived")
	assert_true(v.input.can_act(), "input unlocked")
	v.free()


func test_synthetic_events_play_without_errors() -> void:
	var v := _make_view()
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	var events: Array[Dictionary] = [
		{"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": true, "graze": false, "crit": true, "damage": 3, "chance": 70, "reaction": false},
		{"type": "damage", "unit": enemy.id, "amount": 3, "hp": 1, "source": soldier.id},
		{"type": "shot", "unit": enemy.id, "target": soldier.id, "hit": false, "graze": false, "crit": false, "damage": 0, "chance": 40, "reaction": true},
		{"type": "overwatch", "unit": soldier.id},
		{"type": "hunker", "unit": soldier.id},
		{"type": "infection", "unit": soldier.id, "value": 45, "tier": 2},
		{"type": "ability", "unit": soldier.id, "ability": "suppress", "target": enemy.id},
		{"type": "mutation", "unit": soldier.id, "mutation": "spore_burst", "cell": Vector2i(3, 3)},
		{"type": "lapse", "unit": soldier.id},
		{"type": "recover", "unit": soldier.id},
		{"type": "some_future_event", "unit": soldier.id, "foo": [1, 2]},
		{"type": "no_unit_event"},
		{"type": "damage", "unit": enemy.id, "amount": 1, "hp": 0, "source": soldier.id},
		{"type": "died", "unit": enemy.id},
		{"type": "turned", "unit": soldier.id},
		{"type": "mission_end", "result": Types.Result.DEFEAT},
	]
	for ev in events:
		v.player.enqueue(ev)
	var steps := 0
	while v.player.is_busy() and steps < 2000:
		v.player.advance(1.0 / 30.0)
		steps += 1
	assert_true(not v.player.is_busy(), "queue drained by stepping")
	var ev_view := v.view_for(enemy.id)
	assert_eq(ev_view.hp, 0, "enemy hp from event")
	assert_true(ev_view.dead and not ev_view.visible, "enemy death played")
	var sv := v.view_for(soldier.id)
	assert_eq(sv.infection, 45, "infection value")
	assert_eq(sv.tier, 2, "infection tier")
	assert_true(sv.turned, "turned flag")
	assert_true(v.hud.end_overlay.visible, "end overlay shown")
	assert_true(v.hud.combat_log.line_count() >= events.size(), "every event logged")
	v.free()


func test_input_actions_and_rejection_toast() -> void:
	var v := _make_view()
	v.player.flush()
	v.input.cycle()
	var u := v.input.selected_unit()
	assert_true(u != null, "a soldier is selected")
	var keys := v.input.actions().map(func(a: Dictionary) -> String: return a.key)
	assert_true(keys.has("shoot") and keys.has("overwatch") and keys.has("hunker"), "base actions listed")
	assert_eq(v.input.actions()[0].hotkey, "1", "hotkeys")
	v.input.submit({"type": Types.MOVE, "unit": u.id, "to": Vector2i(0, 0)})
	v.player.flush()
	assert_true(v.hud.toast_text() != "", "rejection shown as toast")
	v.input.select(u.id)
	v.input.trigger("hunker")
	v.player.flush()
	assert_eq(u.actions_left, 0, "hunker ended the turn")
	assert_true(v.view_for(u.id).hunkered, "hunker shown")
	v.free()


func test_ready_buttons_run_enemy_phase() -> void:
	var v := _make_view()
	v.player.flush()
	v.hud.panels[0].ready_button().button_pressed = true
	assert_eq(v.state.ready.get(0), true, "player 1 ready via button")
	v.player.flush()
	v.hud.panels[1].ready_button().button_pressed = true
	assert_true(v.state.turn == 2 or v.state.phase == Types.Phase.ENDED, "enemy phase resolved")
	assert_true(v.player.is_busy(), "enemy phase queued for playback")
	v.player.flush()
	for u in v.state.living():
		assert_eq(v.view_for(u.id).cell, u.pos, "view caught up for %d" % u.id)
	v.free()


func test_main_scene_enters_tree() -> void:
	var tree := Engine.get_meta("test_tree", null) as SceneTree
	assert_true(tree != null, "scene tree available")
	var v: MissionView = MAIN.instantiate()
	tree.root.add_child(v)   # _ready (and a frame of processing) runs once the tree starts
	assert_true(v.get_parent() == tree.root, "added to root")


func test_restart_rebuilds_view() -> void:
	var v := _make_view()
	v.player.flush()
	var old_state := v.state
	v.restart()
	assert_true(v.state != old_state, "fresh state")
	assert_eq(v.unit_views.size(), v.state.units.size(), "views rebuilt")
	assert_true(not v.hud.end_overlay.visible, "overlay hidden")
	v.player.flush()
	v.free()
