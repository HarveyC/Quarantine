extends TestCase
## View/HUD tests. The runner works inside SceneTree._init, before the tree is live,
## so these build the main scene out of the tree and drive the event player's clock
## by hand. test_main_scene_enters_tree also adds one instance to the real root so
## its _ready runs on the first frame (script errors there fail run.sh).

const MAIN := preload("res://scenes/main.tscn")
const InputController := preload("res://view/input_controller.gd")
const Palette := preload("res://view/palette.gd")


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
		"crit": true, "damage": 3, "chance": 70, "reaction": false})
	v.player.enqueue({"type": "damage", "unit": enemy.id, "amount": 3, "hp": 1, "source": soldier.id})
	v.player.advance(0.3)
	assert_true(v.camera_rig.cinematic, "a crit cuts to the shot camera")
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
	v.player.enqueue({"type": "shot", "unit": theirs.id, "target": enemy.id, "hit": true, "graze": false,
		"crit": true, "damage": 2, "chance": 40, "reaction": false})
	v.player.advance(0.1)
	assert_true(not v.camera_rig.cinematic, "teammate's shot keeps my camera")
	v.player.flush()
	v.player.enqueue({"type": "shot", "unit": mine.id, "target": enemy.id, "hit": true, "graze": false,
		"crit": true, "damage": 2, "chance": 40, "reaction": false})
	v.player.advance(0.3)
	assert_true(v.camera_rig.cinematic, "my own shot cuts to the shot camera")
	v.player.flush()
	v.player.enqueue({"type": "shot", "unit": enemy.id, "target": theirs.id, "hit": true, "graze": false,
		"crit": true, "damage": 2, "chance": 40, "reaction": false})
	v.player.advance(0.3)
	assert_true(v.camera_rig.cinematic, "enemy shots still cut")
	v.player.flush()
	v.session = local
	net.free()
	v.free()


## Puts `target`'s view a few tiles from `shooter`'s on the same level, so a shot is routine.
func _close_range(v: MissionView, shooter: Unit, target: Unit) -> void:
	v.view_for(target.id).position = v.view_for(shooter.id).position + Vector3(4, 0, 0)


func test_routine_shots_stay_on_the_tactical_camera() -> void:
	var v := _make_view()
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	_close_range(v, soldier, enemy)
	for outcome in [[true, 70], [false, 70], [false, 20]]:
		v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": outcome[0], "graze": false,
			"crit": false, "damage": 2, "chance": outcome[1], "reaction": false})
		v.player.enqueue({"type": "damage", "unit": enemy.id, "amount": 2, "hp": 4, "source": soldier.id})
		v.player.advance(0.3)
		assert_true(not v.camera_rig.cinematic, "routine shot stays tactical %s" % [outcome])
		v.player.flush()
	# Shots into the soldier: a graze from an ordinary enemy is no moment either.
	v.player.enqueue({"type": "shot", "unit": enemy.id, "target": soldier.id, "hit": true, "graze": true,
		"crit": false, "damage": 1, "chance": 60, "reaction": false})
	v.player.advance(0.3)
	assert_true(not v.camera_rig.cinematic, "enemy graze stays tactical")
	v.player.flush()
	v.free()


func test_epic_moments_cut_to_the_shot_camera() -> void:
	var v := _make_view()
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	_close_range(v, soldier, enemy)
	var shot := {"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": true, "graze": false,
		"crit": false, "damage": 3, "chance": 70, "reaction": false}
	var dies := {"type": "died", "unit": enemy.id}
	var hurt := {"type": "damage", "unit": enemy.id, "amount": 3, "hp": 0, "source": soldier.id}
	v.player._queue.append_array([hurt, dies])
	assert_eq(v.player.shot_moment(shot), "kill", "a kill is a moment")
	for uv in v.unit_views.values():
		if not uv.is_soldier and uv.unit_id != enemy.id:
			uv.dead = true
	assert_eq(v.player.shot_moment(shot), "last_enemy", "the last kill of the fight")
	v.player._queue.clear()
	assert_eq(v.player.shot_moment(shot), "", "the same hit without a kill is routine")
	v.view_for(enemy.id).position = v.view_for(soldier.id).position + Vector3(11, 0, 0)
	assert_eq(v.player.shot_moment(shot), "long_shot", "a hit from 11 tiles")
	v.view_for(enemy.id).position = v.view_for(soldier.id).position + Vector3(7, -preload("res://view/board.gd").RAISE, 0)
	assert_eq(v.player.shot_moment(shot), "high_ground", "shooting down from a roof")
	var later := {"type": "move", "unit": soldier.id, "from": soldier.pos, "path": [soldier.pos]}
	v.player._queue.append_array([hurt, later, dies])
	_close_range(v, soldier, enemy)
	assert_eq(v.player.shot_moment(shot), "", "a death after the next action is not this shot's kill")
	v.player._queue.clear()
	v.free()


func test_epic_shots_play_at_raised_game_speed() -> void:
	var v := _make_view()
	v.player.flush()
	var soldier := v.state.controllable_units(0)[0]
	var enemy := v.state.living(Types.Team.ENEMY)[0]
	v.player.speed = 3.0
	v.player.enqueue({"type": "shot", "unit": soldier.id, "target": enemy.id, "hit": true, "graze": false,
		"crit": false, "damage": 6, "chance": 70, "reaction": false})
	v.player.enqueue({"type": "damage", "unit": enemy.id, "amount": 6, "hp": 0, "source": soldier.id})
	v.player.enqueue({"type": "died", "unit": enemy.id})
	v.player.advance(0.1)
	assert_true(v.camera_rig.cinematic, "a kill cuts at 3x game speed")
	assert_true(v.player.clock_speed() > 1.0 and v.player.clock_speed() < 3.0, "sped up, but less than the game")
	v.player.flush()
	assert_eq(v.player.clock_speed(), 3.0, "full game speed after the shot")
	v.player.speed = 12.0   # autoplay
	var other := v.state.living(Types.Team.ENEMY)[1]
	v.player.enqueue({"type": "shot", "unit": soldier.id, "target": other.id, "hit": true, "graze": false,
		"crit": true, "damage": 6, "chance": 70, "reaction": false})
	v.player.advance(0.05)
	assert_true(not v.camera_rig.cinematic, "autoplay never cuts")
	v.player.flush()
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


## Floating texts on screen right now (Label3D children of the fx layer).
func _fx_texts(v: MissionView) -> Array[String]:
	var out: Array[String] = []
	for it in v.fx._items:
		if it.kind == "text":
			out.append((it.node as Label3D).text)
	return out


## Plays the queue to the end, collecting every floating text shown along the way.
func _play_collecting_texts(v: MissionView) -> Array[String]:
	var seen: Array[String] = []
	var steps := 0
	while v.player.is_busy() and steps < 2000:
		v.player.advance(1.0 / 30.0)
		v.fx.advance(1.0 / 30.0)
		for t in _fx_texts(v):
			if not seen.has(t):
				seen.append(t)
		steps += 1
	return seen


func test_stim_heal_refills_the_hp_bar_and_shows_the_number() -> void:
	# Playtest bug: Stim healed in the rules but the HP pips, nameplate and HUD (which read the
	# UnitView) never moved, and nothing said how much it healed.
	var v := _make_view()
	v.player.flush()
	var med := v.state.controllable_units(0)[0]
	var uv := v.view_for(med.id)
	if not med.abilities.has("stim"):
		med.abilities.append("stim")
	med.hp = 2
	uv.set_hp(2)
	med.infection = 30
	uv.set_infection(30, Infection.tier(30))
	assert_true(Rules.apply(v.state, {"type": Types.ABILITY, "unit": med.id, "ability": "stim"}), "stim self")
	assert_eq(med.hp, 5, "rules healed 3")
	var texts := _play_collecting_texts(v)
	assert_eq(uv.hp, 5, "HP pips refilled to match the rules")
	assert_true(texts.has("+3 HP"), "heal number shown: %s" % [texts])
	assert_true(texts.has("-15 INF"), "cure number shown: %s" % [texts])
	v.free()


func test_heal_events_update_the_hp_bar() -> void:
	var v := _make_view()
	v.player.flush()
	var u := v.state.controllable_units(0)[0]
	var uv := v.view_for(u.id)
	uv.set_hp(1)
	v.player.enqueue({"type": "ability", "unit": u.id, "ability": "item:medkit", "target": u.id, "heal": 4, "hp": 5})
	var texts := _play_collecting_texts(v)
	assert_eq(uv.hp, 5, "medkit refills HP")
	assert_true(texts.has("+4 HP"), "medkit heal number")
	v.player.enqueue({"type": "heal", "unit": u.id, "amount": 2, "hp": 7, "source": "field_surgeon"})
	v.player.enqueue({"type": "gear", "unit": u.id, "item": "leech_rounds", "heal": 1, "hp": 8})
	texts = _play_collecting_texts(v)
	assert_eq(uv.hp, 8, "perk and gear heals refill HP")
	assert_true(texts.has("+2 HP") and texts.has("+1 HP"), "perk and gear heal numbers: %s" % [texts])
	v.free()


## Playtest bug: smoke grenades (and a bunch of other items) "do nothing". Every gadget and
## pocket item use plays its own beat: a readable title (never the raw "item:..." id) and
## something on screen.
func test_every_item_use_plays_a_visible_beat() -> void:
	var v := _make_view()
	v.player.flush()
	var u := v.state.controllable_units(0)[0]
	var foe := v.state.living(Types.Team.ENEMY)[0]
	var ids: Array[String] = []
	for k in GearFx.CONSUMABLE_USE:
		ids.append("item:" + k)
	for k in GearFx.GADGETS:
		ids.append("gear:" + k)
	for id in ids:
		var key := id.substr(5)
		var ev := {"type": "ability", "unit": u.id, "ability": id, "name": GearData.item_name(key)}
		var targeting: String = GearFx.CONSUMABLE_USE.get(key, GearFx.GADGETS.get(key, {})).get("targeting", "none")
		if targeting == "cell":
			ev["cell"] = u.pos + Vector2i(0, -2)
			ev["units"] = [foe.id]
		elif targeting == "unit":
			ev["target"] = u.id
		v.player.enqueue(ev)
		var texts := _play_collecting_texts(v)
		assert_true(not texts.is_empty(), "%s shows a title" % id)
		for t in texts:
			assert_true(not t.contains(":") and not t.contains("_"), "%s shows a raw id: %s" % [id, t])
	v.free()


func test_item_effects_tag_units_and_draw_smoke() -> void:
	var v := _make_view()
	v.player.flush()
	var u := v.state.controllable_units(0)[0]
	var foe := v.state.living(Types.Team.ENEMY)[0]
	var fv := v.view_for(foe.id)
	fv.visible = true
	var t := v.player.turn
	v.player.enqueue({"type": "gear", "unit": u.id, "item": "mark", "target": foe.id})
	v.player.enqueue({"type": "stunned", "unit": foe.id, "by": u.id})
	var texts := _play_collecting_texts(v)
	assert_true(fv.tags.has("marked") and fv.tags.has("stunned"), "tags on the enemy: %s" % [fv.tags])
	assert_true(texts.has("MARKED") and texts.has("STUNNED"), "named over the enemy: %s" % [texts])
	v.player.enqueue({"type": "enemy_phase", "turn": t})
	v.player.enqueue({"type": "team_phase", "turn": t + 1})
	_play_collecting_texts(v)
	assert_true(not fv.tags.has("stunned"), "the stun wears off by the next squad phase")
	var cells: Array[Vector2i] = [u.pos + Vector2i(0, -1), u.pos + Vector2i(1, -1)]
	v.player.enqueue({"type": "hazard", "kind": "smoke", "cells": cells, "turns": 2})
	_play_collecting_texts(v)
	assert_true(v.board._hazard_nodes.has(cells[0]) and v.board._hazard_nodes.has(cells[1]), "the cloud is drawn")
	v.free()


func test_concealment_shows_on_the_squad_and_the_screen_edge() -> void:
	var v := _make_view()
	v.player.flush()
	var soldiers := v.state.living(Types.Team.PLAYER)
	v.state.encounter["concealment"] = {"on": true, "lost_turn": -1, "cause": ""}
	v.player.concealed = true
	for s in soldiers:
		assert_true(v.view_for(s.id).concealed, "every soldier wears the concealed ring")
	for i in 60:
		v.hud._process(1.0 / 30.0)
	assert_true(v.hud.stealth_edge_alpha() > 0.3, "the screen edge glows cold blue")
	v.player.enqueue({"type": "concealment_lost", "cause": "spotted", "unit": -1, "by": -1})
	_play_collecting_texts(v)
	assert_true(not v.view_for(soldiers[0].id).concealed, "rings drop when the squad is seen")
	v.free()


func test_enemy_sight_areas_and_spotted_path_while_concealed() -> void:
	var v := _make_view()
	v.player.flush()
	var u := v.state.controllable_units(0)[0]
	var foe: Unit = null
	for e in v.state.living(Types.Team.ENEMY):
		if v.view_for(e.id).visible:
			foe = e
			break
	if foe == null:
		foe = v.state.living(Types.Team.ENEMY)[0]
		v.view_for(foe.id).visible = true
	for e in v.state.living(Types.Team.ENEMY):
		e.status.erase("alerted")
	v.state.encounter["concealment"] = {"on": true, "lost_turn": -1, "cause": ""}
	v.player.concealed = true
	var fields := v.input.sight_fields()
	assert_true(fields.has(foe.id), "a seen dormant enemy has a sight area")
	v.input.refresh()
	assert_true(v.board._sight_layer.get_child_count() > 0, "the sight area is drawn")
	var path: Array[Vector2i] = [u.pos]
	var red: Vector2i = fields[foe.id].cells.keys()[0]
	path.append(red)
	assert_eq(v.input.spotted_step(path), 1, "the step into red ground is where you're seen")
	v.board.show_path(path, 1)
	var eye := false
	for c in v.board._path_layer.get_children():
		eye = eye or c is Sprite3D
	assert_true(eye, "an eye hangs over the spotted step")
	v.player.concealed = false
	v.input.refresh()
	assert_eq(v.board._sight_layer.get_child_count(), 0, "no sight areas once detected")


func test_shoot_cycles_onto_a_fuel_barrel() -> void:
	var v := _make_view()
	v.player.flush()
	var s := v.state
	v.input.cycle()
	var u := v.input.selected_unit()
	var cell := InputController.NO_CELL
	for d in [Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(1, -1), Vector2i(-1, -1)]:
		var c: Vector2i = u.pos + d
		if s.grid.in_bounds(c) and s.grid.tile(c) == Types.Tile.FLOOR and s.unit_at(c) == null and Combat.can_see(s, u.pos, c) \
				and Vision.cell_visible(s, u.team, c):
			cell = c
			break
	assert_true(cell != InputController.NO_CELL, "a free cell in sight")
	s.grid.set_tile(cell, Types.Tile.LOW)
	s.grid.volatile[cell] = true
	v.input.trigger("shoot")
	assert_eq(v.input.mode, InputController.Mode.SHOOT, "aiming")
	assert_true(v.input.targets.has(cell), "the barrel is in the target cycle: %s" % str(v.input.targets))
	assert_eq(v.input.targets.back(), cell, "after the enemies")
	for i in v.input.targets.size():
		if v.input.current_barrel() == cell:
			break
		v.input.cycle_target(1)
	assert_eq(v.input.current_barrel(), cell, "cycled onto it")
	assert_true(v.input.current_target() == null, "no unit targeted")
	v.hud.refresh()
	assert_true(v.hud.target_panel.visible, "the shot panel shows the barrel odds")
	v.input.confirm_shot()
	v.player.flush()
	var shots: Array = s.log.filter(func(ev): return ev.type == "barrel_shot")
	assert_eq(shots.size(), 1, "one Shoot at the barrel")
	assert_eq(u.actions_left, 0, "it ended the turn")
	assert_eq(not shots[0].hit, s.grid.is_volatile(cell), "the barrel went up only on a hit")
	v.free()


func test_map_markings_each_have_a_look_a_card_and_a_key_entry() -> void:
	var v := _make_view()
	v.player.flush()
	var u := v.state.controllable_units(0)[0]
	for k in TileOverlays.KINDS:
		assert_true(Glossary.has(TileOverlays.term(k)), "%s has a glossary card" % k)
	assert_true(TileOverlays.color("spore") == Palette.TEAL, "spores are the Infection teal")
	for k in TileOverlays.KINDS:
		if k != "spore":
			assert_true(TileOverlays.color(k) != Palette.TEAL, "%s is not teal: teal means Infection" % k)
	var looks := {}
	for k in ["move", "sight", "aim", "blast", "fire", "spore", "acid", "smoke"]:
		var look := TileOverlays.pattern(k) + str(TileOverlays.color(k))
		assert_true(not looks.has(look), "%s looks unlike %s" % [k, looks.get(look, "")])
		looks[look] = k
	# Hazards: drawn with their own pattern, listed in the key, named on hover.
	var spore := u.pos + Vector2i(1, 0)
	var fire := u.pos + Vector2i(2, 0)
	v.board.set_hazard([spore], "spore")
	v.board.set_hazard([fire], "fire")
	assert_eq(v.board.hazard_at(spore), "spore")
	assert_true(v.board._hazard_edges.get_child_count() > 0, "hazard areas are outlined")
	v.input.selected_id = u.id
	v.input.mode = v.input.Mode.MOVE
	v.input.refresh()
	var on: Array[String] = v.board.active_overlays()
	for k in ["move", "spore", "fire"]:
		assert_true(on.has(k), "the key lists %s: %s" % [k, on])
	v.hud.map_key.refresh()
	assert_eq(v.hud.map_key.shown(), on, "the map key shows what is on the floor")
	assert_true(v.hud.map_key.visible, "the key is up while something is marked")
	assert_eq(v.input.tile_terms(spore)[0], "hazard_spore", "hovering spores explains spores")
	v.board.clear_hazard([spore, fire])
	assert_true(not v.board.active_overlays().has("spore"), "cleared hazards leave the key")
	# Aiming an item: amber, listed as the aim area (never teal).
	v.board.mark_cells([u.pos], Color(Palette.AMBER, 0.22), "aim")
	assert_true(v.board.active_overlays().has("aim"), "the aimed area is in the key")
	v.board.clear_overlays()
	assert_true(not v.board.active_overlays().has("aim"), "and leaves it once cleared")
	assert_true(not (v.board._hover is MeshInstance3D), "the cursor is corner marks, not a white tile")
	v.free()


func test_objective_zones_are_labelled_on_the_map() -> void:
	var g := Grid.from_rows(PackedStringArray(["......", "......", "......", "......"]))
	g.objective = "extract"
	g.markers["evac"] = [Vector2i(4, 1), Vector2i(5, 1)]
	var b: Node3D = load("res://view/board.gd").new()
	b.build(g)
	assert_eq(b.zones(), ["evac"] as Array[String])
	assert_eq(b.zone_at(Vector2i(4, 1)), "evac")
	var label: Label3D = b._fixed.find_child("ZoneLabel", true, false)
	assert_true(label != null and label.text == "EVAC", "the evac pad is named on the map")
	assert_true(b.active_overlays().has("evac"), "and listed in the map key")
	b.free()


## A grafted soldier wears a prop on the skeleton for each part, Machine and Bloom alike.
func test_grafted_soldiers_wear_their_parts() -> void:
	var GraftKit := preload("res://view/graft_kit.gd")
	var u := UnitData.make("trooper", Types.Team.PLAYER)
	u.owner_player = 0
	Grafts.apply_to_unit(u, {"grafts": {"head": "targeting_optic", "arm": "bloom_limb", "chest": "plated_ribs", "legs": "runner_legs"}})
	var uv = preload("res://view/unit_view.gd").new()
	uv.build(u)
	var props: Array[String] = GraftKit.props(uv._model)
	for p in ["graft_head", "graft_arm", "graft_claw", "graft_chest", "graft_thigh_l", "graft_calf_r"]:
		assert_true(props.has(p), "%s worn" % p)
	uv.free()
	var bare = preload("res://view/unit_view.gd").new()
	bare.build(UnitData.make("trooper", Types.Team.PLAYER))
	assert_eq(GraftKit.props(bare._model), [] as Array[String], "no grafts, no props")
	bare.free()
