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
		{"type": "hazard", "kind": "fire", "cells": [Vector2i(3, 3), Vector2i(4, 3)], "turns": 2, "source": soldier.id, "spare": -1},
		{"type": "hazard_tick", "unit": soldier.id, "kind": "fire", "cell": Vector2i(3, 3), "damage": 2, "infection": 0},
		{"type": "hazard_end", "kind": "fire", "cells": [Vector2i(3, 3)]},
		{"type": "objective", "kind": "hold", "progress": 1, "goal": 4},
		{"type": "rescued", "unit": soldier.id},
		{"type": "left_behind", "unit": soldier.id},
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


func test_shot_cinematic_takes_and_returns_camera() -> void:
	var v := _make_view()
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": true, "graze": false,
		"crit": false, "damage": 3, "chance": 70, "reaction": false})
	v.player.enqueue({"type": "damage", "unit": enemy.id, "amount": 3, "hp": 1, "source": soldier.id})
	v.player.advance(0.3)
	assert_true(v.camera_rig.cinematic, "shot camera engaged")
	assert_true(v.player.in_cinematic, "cinematic flagged")
	var steps := 0
	var slowed := false
	while v.player.is_busy() and steps < 2000:
		v.player.advance(1.0 / 30.0)
		slowed = slowed or v.player.world_scale < 0.5
		if v.player.is_busy():
			assert_true(v.camera_rig.cinematic, "camera held through the damage beat")
		steps += 1
	assert_true(slowed, "slow motion during the shot")
	assert_true(not v.camera_rig.cinematic and not v.player.in_cinematic, "tactical camera back after the queue drains")
	assert_eq(v.player.world_scale, 1.0, "normal speed restored")
	assert_eq(v.view_for(enemy.id).hp, 1, "damage applied")
	v.free()


func test_cinematics_off_plays_quick_shot() -> void:
	var v := _make_view()
	v.player.flush()
	var EventPlayer := preload("res://view/event_player.gd")
	EventPlayer.cinematics = false
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": false, "graze": false,
		"crit": false, "damage": 0, "chance": 40, "reaction": false})
	v.player.advance(0.1)
	assert_true(not v.camera_rig.cinematic, "no camera cut")
	v.player.flush()
	EventPlayer.cinematics = true
	v.free()


func test_sound_files_exist() -> void:
	var Sfx := preload("res://view/sfx.gd")
	for s in Sfx.SOUNDS:
		assert_true(ResourceLoader.exists("res://audio/%s.wav" % s), "sound %s" % s)
	assert_true(ResourceLoader.exists("res://audio/ambience.wav"), "ambience")


func test_models_have_rig_joints() -> void:
	var ModelKit := preload("res://view/model_kit.gd")
	for kind in ModelKit.MODELS:
		var m := ModelKit.instantiate(kind, kind not in ["runner", "spitter"])
		for j in ["hips", "torso", "head", "leg_l", "leg_r", "knee_l", "knee_r", "arm_l", "arm_r", "elbow_l", "elbow_r", "muzzle"]:
			assert_true(ModelKit.find(m, j) != null, "%s has joint %s" % [kind, j])
		if kind not in ["runner", "spitter"]:
			assert_true(ModelKit.find(m, "gun") != null and ModelKit.find(m, "support") != null, "%s has a weapon" % kind)
			assert_eq(ModelKit.growths(m).size() >= 3, true, "%s has infection growths" % kind)
		m.free()


func test_infection_growths_follow_tier() -> void:
	var v := _make_view()
	v.player.flush()
	var uv := v.view_for(v.state.controllable_units(0)[0].id)
	var shown := func() -> int:
		var n := 0
		for g in uv._growths:
			if g[1].visible:
				n = maxi(n, g[0])
		return n
	assert_eq(shown.call(), 0, "clean soldier shows no growths")
	uv.set_infection(60, Infection.Tier.MUTATING)
	assert_eq(shown.call(), 2, "mutating shows stage 2 growths")
	uv.set_turned()
	assert_eq(shown.call(), 3, "turned shows every growth")
	v.free()


func test_units_face_nearest_threat() -> void:
	var v := _make_view()
	v.player.flush()
	for u in v.state.living(Types.Team.PLAYER):
		var best: Unit = null
		for e in v.state.living(Types.Team.ENEMY):
			if best == null or Vector2(e.pos - u.pos).length_squared() < Vector2(best.pos - u.pos).length_squared():
				best = e
		var uv := v.view_for(u.id)
		var to := Vector3(best.pos.x - u.pos.x, 0, best.pos.y - u.pos.y).normalized()
		assert_true(uv.facing().dot(to) > 0.95, "%s faces the nearest enemy" % u.display_name)
	var yaws := {}
	for e in v.state.living(Types.Team.ENEMY):
		yaws[snappedf(v.view_for(e.id)._yaw, 0.01)] = true
	assert_true(yaws.size() > 1, "dormant enemies don't all face the same way")
	v.free()


func test_turning_is_smooth() -> void:
	var v := _make_view()
	v.player.flush()
	var uv := v.view_for(v.state.controllable_units(0)[0].id)
	uv.set_yaw(0.0)
	uv.face_towards(uv.position + Vector3(-1, 0, 0))
	uv.tick(0.05)
	assert_true(absf(uv._yaw) > 0.1 and absf(uv._yaw) < PI / 2 - 0.1, "mid-turn after one frame")
	for i in 30:
		uv.tick(0.05)
	assert_true(uv.facing().dot(Vector3(-1, 0, 0)) > 0.99, "turn completes")
	v.free()
