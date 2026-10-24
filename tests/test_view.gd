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


func _press(v: MissionView, key: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = key
	k.pressed = true
	v.input._unhandled_input(k)


func test_space_toggles_ready_and_runs_enemy_phase() -> void:
	var v := _make_view()
	v.player.flush()
	_press(v, KEY_SPACE)
	assert_eq(v.state.ready.get(0), true, "Space readies player 1")
	v.player.flush()
	v.input.select(v.state.controllable_units(1)[0].id)   # hot-seat: player 2's soldier
	_press(v, KEY_SPACE)
	assert_true(v.state.turn == 2 or v.state.phase == Types.Phase.ENDED, "Space readies player 2, enemy phase resolved")
	v.player.flush()
	v.free()


func test_space_unreadies_selected_players_soldier() -> void:
	var v := _make_view()
	v.player.flush()
	v.input.select(v.state.controllable_units(0)[0].id)
	_press(v, KEY_SPACE)
	assert_eq(v.state.ready.get(0), true, "ready")
	v.player.flush()
	_press(v, KEY_SPACE)
	assert_eq(v.state.ready.get(0), false, "Space again unreadies")
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


func test_every_gun_fires_through_the_shot_beat() -> void:
	var v := _make_view()
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	var uv := v.view_for(soldier.id)
	var k := 0
	for id in Weapons.TABLE:
		uv.weapon = id
		for outcome in [[true, false], [false, false], [true, true]]:
			v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": outcome[0], "graze": outcome[1],
				"crit": false, "damage": 1, "chance": 50, "reaction": k % 2 == 0})
			var steps := 0
			while v.player.is_busy() and steps < 600:
				v.player.advance(1.0 / 20.0)
				steps += 1
			assert_true(not v.player.is_busy(), "%s shot finishes" % id)
			k += 1
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


func test_teammate_shots_skip_the_shot_camera() -> void:
	var v := _make_view()
	v.player.flush()
	var local := v.session
	var net := NetSession.new()
	net.my_player = 0
	v.session = net
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	var mine := v.state.controllable_units(0)[0]
	var theirs := v.state.controllable_units(1)[0]
	v.player.enqueue({"type": "shot", "unit": theirs.id, "target": enemy.id, "hit": false, "graze": false,
		"crit": false, "damage": 0, "chance": 40, "reaction": false})
	v.player.advance(0.1)
	assert_true(not v.camera_rig.cinematic, "teammate's shot keeps my camera")
	v.player.flush()
	v.player.enqueue({"type": "shot", "unit": mine.id, "target": enemy.id, "hit": false, "graze": false,
		"crit": false, "damage": 0, "chance": 40, "reaction": false})
	v.player.advance(0.3)
	assert_true(v.camera_rig.cinematic, "my own shot cuts to the shot camera")
	v.player.flush()
	v.player.enqueue({"type": "shot", "unit": enemy.id, "target": theirs.id, "hit": false, "graze": false,
		"crit": false, "damage": 0, "chance": 40, "reaction": false})
	v.player.advance(0.3)
	assert_true(v.camera_rig.cinematic, "enemy shots still cut")
	v.player.flush()
	v.session = local
	net.free()
	v.free()


func test_sound_files_exist() -> void:
	var Sfx := preload("res://view/sfx.gd")
	for s in Sfx.SOUNDS:
		assert_true(ResourceLoader.exists("res://audio/%s.wav" % s), "sound %s" % s)
	assert_true(ResourceLoader.exists("res://audio/ambience.wav"), "ambience")


func test_characters_are_rigged() -> void:
	var ModelKit := preload("res://view/model_kit.gd")
	var SkinnedBody := preload("res://view/skinned_body.gd")
	for kind in ModelKit.CHARACTERS:
		var m := ModelKit.instantiate(kind, true)
		assert_true(ModelKit.is_skinned(m), "%s is skinned" % kind)
		var body := SkinnedBody.new()
		body.setup(m, kind not in ["trooper", "marksman", "medic", "breacher", "civilian"])
		for pose in ["idle", "walk", "death"]:
			assert_true(body.has_clip(pose), "%s has a %s clip" % [kind, pose])
		if kind in ["trooper", "marksman", "medic", "breacher"]:
			assert_true(body.armed, "%s carries a weapon" % kind)
			assert_true(body.skel.find_bone("muzzle") >= 0, "%s has a muzzle" % kind)
			assert_eq(ModelKit.growths(m).size() >= 3, true, "%s has infection growths" % kind)
		m.free()
	for kind in ModelKit.MODELS:
		var p := ModelKit.instantiate(kind, false)
		assert_true(ModelKit.find(p, "body") != null, "%s prop has a body" % kind)
		p.free()


func test_hands_stay_on_the_rifle() -> void:
	var u := Unit.new()
	u.id = 1
	u.kind = "trooper"
	u.team = Types.Team.PLAYER
	u.owner_player = 0
	u.max_hp = 5
	u.hp = 5
	var uv := preload("res://view/unit_view.gd").new()
	uv.build(u)
	for aim in [0.0, 1.0]:
		uv.aim_now(aim)
		uv.set_moving(aim < 0.5)
		for i in 10:
			uv.tick(0.05)
		var body = uv._skin
		var grip: Vector3 = body.bone_pose("support").origin
		assert_true(body.bone_pose("hand_l").origin.distance_to(grip) < 0.06, "off hand on the support grip (aim %s)" % aim)
		assert_true(body.bone_pose("hand_r").origin.distance_to(body.bone_pose("gun").origin) < 0.06, "trigger hand on the grip (aim %s)" % aim)
	assert_eq(String(uv._skin.player.current_animation), "Idle", "standing still plays idle")
	uv.set_moving(true)
	uv.tick(0.5)
	assert_eq(String(uv._skin.player.current_animation), "Jog_Fwd", "moving plays the jog")
	uv.free()


func test_hits_flinch_without_falling_and_aim_at_the_chest() -> void:
	for kind in ["runner", "trooper", "brute"]:
		var u := Unit.new()
		u.id = 1
		u.kind = kind
		u.team = Types.Team.PLAYER if kind == "trooper" else Types.Team.ENEMY
		u.owner_player = 0 if kind == "trooper" else -1
		u.max_hp = 5
		u.hp = 5
		var uv := preload("res://view/unit_view.gd").new()
		uv.build(u)
		uv.tick(0.05)
		var chest: float = uv.chest_world().y
		assert_true(chest > 1.0 and chest < 2.2, "%s is shot in the chest, not the hips (%.2f)" % [kind, chest])
		var standing: float = uv.head_world().y
		uv.hit_react(Vector3(0, 0, 3), 1.0)
		var lowest := standing
		for i in 30:
			uv.tick(0.05)
			lowest = minf(lowest, uv.head_world().y)
		assert_true(lowest > standing * 0.7, "%s flinches but stays on its feet (%.2f of %.2f)" % [kind, lowest, standing])
		uv.free()


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
	var s := MissionView.default_mission(1234)
	Vision.disable(s)   # with fog on, soldiers only turn toward enemies they can see
	var v: MissionView = MAIN.instantiate()
	v.start(s)
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


## A run fight ends on the debrief (not the restart overlay): kills, wounds and Infection per
## soldier, a key shows it at once, the next continues and tells the app to move on.
func test_run_fight_ends_on_debrief() -> void:
	var l := LocalSession.new()
	l.save_enabled = false
	l.start_run(1, 31)
	RunAutoplay.settle(l.run, l.submit_run)
	l.submit_run({"type": RunRules.VOTE, "player": 0, "node": l.run.reachable_nodes()[0]})
	var s := l.state
	var v: MissionView = MAIN.instantiate()
	v.session = l
	v.start(s, true)
	v.player.flush()
	var soldier: Unit = s.living(Types.Team.PLAYER).filter(func(u: Unit) -> bool: return u.status.has("sid"))[0]
	var foe: Unit = s.living(Types.Team.ENEMY)[0]
	assert_eq(int(soldier.status.get("start_hp", -1)), soldier.hp, "start HP recorded")
	Rules.deal_damage(s, foe, 999, soldier)
	Rules.deal_damage(s, soldier, 2, foe)
	Infection.add(s, soldier, 5)
	var sum: Dictionary = v.hud.debrief.summarize(s)
	var row: Dictionary = sum.soldiers.filter(func(r: Dictionary) -> bool: return r.unit == soldier.id)[0]
	assert_eq(row.kills, 1, "kill credited")
	assert_eq(row.wounds, 2, "wounds = HP lost this fight")
	assert_true(row.infection_gained >= 5, "Infection gained")
	assert_eq(row.fate, "wounded", "fate")
	var finished := []
	v.debrief_finished.connect(func() -> void: finished.append(true))
	for u in s.living(Types.Team.ENEMY):
		u.hp = 0
	s.objective.result = Types.Result.VICTORY
	Rules.check_end(s)
	v.player.flush()
	assert_true(v.hud.debrief.visible, "debrief up")
	assert_true(not v.hud.end_overlay.visible, "no restart overlay in a run")
	assert_true(not v.hud.debrief.shown, "holds on the final beat first")
	v.hud.debrief.skip()
	assert_true(v.hud.debrief.shown and finished.is_empty(), "first press shows the summary")
	v.hud.debrief._t = 1.0
	v.hud.debrief.skip()
	assert_eq(finished.size(), 1, "second press continues")
	assert_true(v.debrief_done, "view knows")
	v.free()
	l.free()


func _melee_view(kind: String) -> Node3D:
	var u := Unit.new()
	u.id = 1
	u.kind = kind
	u.team = Types.Team.PLAYER
	u.owner_player = 0
	u.max_hp = 6
	u.hp = 6
	var uv = preload("res://view/unit_view.gd").new()
	uv.build(u)
	return uv


## Reaper and Warden borrow a body, hold melee props instead of a rifle, and draw the
## sidearm only to shoot; the Warden's Guard stance raises the shield.
func test_melee_classes_hold_melee_props_and_draw_the_sidearm() -> void:
	var MeleeKit := preload("res://view/melee_kit.gd")
	for kind in ["reaper", "warden"]:
		var uv = _melee_view(kind)
		assert_true(uv.is_melee_class(), "%s is a melee class" % kind)
		assert_true(not uv._skin.armed, "%s holds no rifle by IK" % kind)
		var weapon := uv._model.find_child("melee_weapon", true, false) as Node3D
		var drawn := uv._model.find_child("sidearm_drawn", true, false) as Node3D
		assert_true(weapon != null and drawn != null, "%s has its melee weapon and sidearm" % kind)
		assert_true(uv._model.find_child("shield", true, false) != null if kind == "warden" else uv._model.find_child("bloom_arm", true, false) != null, "%s class prop" % kind)
		uv.tick(0.05)
		assert_true(weapon.visible and not drawn.visible, "%s: melee weapon in hand at rest" % kind)
		uv.aim_now(1.0)
		uv.tick(0.05)
		assert_true(drawn.visible and not weapon.visible, "%s: sidearm drawn to aim" % kind)
		uv.tick(0.5)
		assert_eq(String(uv._skin.player.current_animation), "Pistol_Aim_Neutral", "%s pistol stance" % kind)
		var hand: Vector3 = uv._to_world(uv._skin.skel, uv._skin.bone_pose("hand_r").origin)
		assert_true(uv.muzzle_world().distance_to(hand) < 0.45, "%s muzzle at the weapon hand" % kind)
		uv.aim_now(0.0)
		uv.tick(0.5)
		assert_true(weapon.visible and not drawn.visible, "%s: sidearm holstered again" % kind)
		assert_true(MeleeKit.size_of(kind) > 0.9, "size")
		if kind == "warden":
			uv.set_guard(true)
			uv.tick(0.5)
			assert_eq(String(uv._skin.player.current_animation), "Idle_Shield", "guard raises the shield")
			assert_true(uv._status_label.text.contains("GUARD"), "guard tag")
		uv.free()


func test_melee_class_events_play() -> void:
	var s := MissionView.default_mission(1234)
	var squad := s.living(Types.Team.PLAYER)
	squad[0].kind = "reaper"
	squad[2].kind = "warden"
	var v: MissionView = MAIN.instantiate()
	v.start(s, true)
	v.player.flush()
	var reaper: Unit = squad[0]
	var warden: Unit = squad[2]
	var foes := s.living(Types.Team.ENEMY)
	var foe: Unit = foes[0]
	var wv := v.view_for(warden.id)
	var events: Array[Dictionary] = [
		{"type": "move", "unit": reaper.id, "from": reaper.pos, "path": [reaper.pos + Vector2i(1, 0)]},
		{"type": "ability", "unit": reaper.id, "ability": "lunge", "target": foe.id, "hit": true, "graze": false, "damage": 3, "chance": 80},
		{"type": "damage", "unit": foe.id, "amount": 3, "hp": 2, "source": reaper.id},
		{"type": "ability", "unit": reaper.id, "ability": "lunge", "cleave": true, "target": foes[1].id, "hit": true, "graze": true, "damage": 1, "chance": 80},
		{"type": "damage", "unit": foes[1].id, "amount": 1, "hp": 4, "source": reaper.id},
		{"type": "perk", "unit": reaper.id, "perk": "bloodlust"},
		{"type": "bleeding", "unit": foe.id, "turns": 2},
		{"type": "guard", "unit": warden.id},
		{"type": "ability", "unit": warden.id, "ability": "bash", "target": foe.id, "hit": true, "graze": false, "damage": 2, "chance": 75, "reaction": true},
		{"type": "damage", "unit": foe.id, "amount": 2, "hp": 0, "source": warden.id},
		{"type": "move", "unit": foe.id, "from": foe.pos, "path": [foe.pos + Vector2i(0, 1)], "knockback": true},
		{"type": "stunned", "unit": foe.id, "by": warden.id},
		{"type": "move", "unit": warden.id, "from": warden.pos, "path": [warden.pos + Vector2i(0, -1)]},
		{"type": "ability", "unit": warden.id, "ability": "bash", "charge": true, "target": foes[1].id, "hit": false, "graze": false, "damage": 0, "chance": 60},
		{"type": "ability", "unit": reaper.id, "ability": "riposte", "target": foes[1].id, "hit": true, "graze": false, "damage": 2, "chance": 70},
		{"type": "bleed", "unit": foe.id, "damage": 1},
		{"type": "guard", "unit": warden.id},
	]
	var guard_seen := []
	v.player.beat_started.connect(func(ev: Dictionary) -> void:
		if ev.get("type") == "stunned":
			guard_seen.append(wv.guard))
	for ev in events:
		v.player.enqueue(ev)
	var steps := 0
	while v.player.is_busy() and steps < 3000:
		v.player.advance(1.0 / 30.0)
		steps += 1
	assert_true(not v.player.is_busy(), "queue drained")
	assert_eq(guard_seen, [false], "a Guard bash spends the stance")
	assert_true(wv.guard, "guard shown again")
	assert_eq(v.view_for(foe.id).cell, foe.pos + Vector2i(0, 1), "knocked back")
	assert_true(v.hud.combat_log.line_count() >= events.size(), "every event logged")
	v.player.enqueue({"type": "team_phase", "turn": 2})
	v.player.flush()
	assert_true(not wv.guard, "guard ends at the next squad phase")
	var EventText := preload("res://ui/event_text.gd")
	var line := EventText.describe(events[1], func(id: int) -> String: return str(id))
	assert_true(line.contains("lunges at") and line.contains("80%"), "lunge log line")
	v.free()


## Unit-targeted abilities highlight only the targets Combat lists.
func test_unit_ability_highlights_its_targets() -> void:
	var v := _make_view()
	v.player.flush()
	v.input.cycle()
	var u := v.input.selected_unit()
	var foes := v.state.living(Types.Team.ENEMY)
	v.input._trigger(u, {"key": "ability:lunge", "label": "Lunge", "targeting": "unit", "type": Types.ABILITY,
		"id": "lunge", "enabled": true, "targets": [foes[0].id]})
	assert_eq(v.input.mode, v.input.Mode.TARGET_UNIT, "targeting")
	assert_true(v.view_for(foes[0].id)._target_ring.visible, "listed target highlighted")
	assert_true(not v.view_for(foes[1].id)._target_ring.visible, "others not")
	v.input._show_landing(u, foes[0].pos)   # no ClassAbilities.lunge_landing yet: no error, no path
	v.input.cancel()
	assert_true(v.input.unit_targets.is_empty(), "cleared on cancel")
	var Icons := preload("res://ui/icons.gd")
	for k in ["reaper", "warden"]:
		assert_eq(Icons.for_class(k), k, "%s class icon" % k)
	for id in ["lunge", "bash", "guard", "shield_charge"]:
		assert_eq(Icons.for_action({"id": id}), id, "%s icon" % id)
	v.free()
