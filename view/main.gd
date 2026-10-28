class_name MissionView
extends Node3D
## Entry point and view root. Builds a mission, the 3D board, unit views, camera,
## event player, input and HUD, and wires GameState.event into the event player.
## Run with `-- --autoplay` to ready every player each turn (headless smoke test),
## or `-- --screenshot=<path.png>` (needs a real renderer) to save a frame and quit.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")
const UnitView := preload("res://view/unit_view.gd")
const Fx := preload("res://view/fx.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const EventPlayer := preload("res://view/event_player.gd")
const InputController := preload("res://view/input_controller.gd")
const Hud := preload("res://ui/hud.gd")
const Sfx := preload("res://view/sfx.gd")
const PostFx := preload("res://view/post_fx.gd")
const EnemyBeats := preload("res://view/enemy_beats.gd")
const IntentOverlay := preload("res://view/intent_overlay.gd")
const FogOverlay := preload("res://view/fog_overlay.gd")
const MarkLayer := preload("res://ui/marks/mark_layer.gd")
const FightSurface := preload("res://ui/marks/fight_surface.gd")

signal left_match
## A run fight's debrief was continued or skipped; the app moves on to the run view.
signal debrief_finished

const MAP := "res://maps/mission_01.txt"
const AUTOPLAY_MAX_TURNS := 30
const AUTOPLAY_SPEED := 12.0

var state: GameState
## LocalSession or NetSession: who may act, and where actions go. Created on demand for hot-seat.
var session: Node
## When false, App drives start() with a session instead of _ready building a local mission.
var auto_start := true
var board: Board
var fx: Fx
var sfx: Sfx
var camera_rig: CameraRig
var player: EventPlayer
var input: InputController
var hud: Hud
var unit_views: Dictionary = {}   # unit id -> UnitView
var intents: IntentOverlay
var fog: FogOverlay
## Co-op pings and map drawing.
var marks: MarkLayer
var autoplay := false
var debrief_done := false
var screenshot_path := ""
var _frames := 0
var _autoplay_done := false
var _world: Node3D
var _units_root: Node3D
var _ui_layer: CanvasLayer


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
	if auto_start:
		var seed := 0
		var objective := ""
		var biome := "wall"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--biome="):   # dev aid: which act's parcels --objective uses
				biome = arg.trim_prefix("--biome=")
			if arg.begins_with("--seed="):
				seed = int(arg.trim_prefix("--seed="))
			elif arg.begins_with("--objective="):   # dev aid: a generated act 1 map of this fight type
				objective = arg.trim_prefix("--objective=")
		var fight := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--fight="):
				fight = arg.trim_prefix("--fight=")
		start(fight_mission(fight, seed) if fight != "" else default_mission(seed, objective, biome))


func _exit_tree() -> void:
	if is_instance_valid(session) and session is LocalSession and not session.is_inside_tree():
		session.free()


static func default_mission(seed: int = 0, objective: String = "", biome := "wall") -> GameState:
	var squad := [
		{"kind": "trooper", "player": 0}, {"kind": "marksman", "player": 0},
		{"kind": "medic", "player": 1}, {"kind": "breacher", "player": 1},
	]
	var enemies: Array[String] = ["runner", "runner", "spitter", "runner", "spitter"]
	if objective != "":
		var grid := MapGen.generate({"biome": biome, "objective": objective, "seed": seed})
		return Rules.new_mission_on_grid(grid, squad, enemies, seed)
	return Rules.new_mission(MAP, squad, enemies, seed)


## Dev aid: `-- --fight=<node>,<act>,<outbreak>` (e.g. boss,3,9 or nest,2,10) plays one
## FightBuilder fight on the test map.
static func fight_mission(arg: String, seed: int = 0) -> GameState:
	var parts := arg.split(",")
	var spec := {"node": parts[0], "act": int(parts[1]) if parts.size() > 1 else 1,
		"outbreak": int(parts[2]) if parts.size() > 2 else 0, "seed": seed if seed != 0 else 1,
		"objective": "boss" if parts[0] == "boss" else ""}
	var fight := FightBuilder.build(spec)
	var config := MatchConfig.make(2, spec.seed)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	return MatchConfig.build(config)


## Builds the whole view for `s` and starts the mission. Works out of the tree too (tests).
func start(s: GameState, begin := true) -> void:
	_teardown()
	state = s
	debrief_done = false
	if session == null:
		session = LocalSession.new()
	if session is LocalSession:
		session.state = s
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_build_environment()
	board = Board.new()
	board.name = "Board"
	board.build(s.grid)
	board.sync_hazards(s.hazards)
	_world.add_child(board)
	_units_root = Node3D.new()
	_units_root.name = "Units"
	_world.add_child(_units_root)
	for u in s.units:
		_add_unit_view(u)
	fog = FogOverlay.new()
	fog.name = "Fog"
	_world.add_child(fog)
	fog.setup(s.grid)
	fx = Fx.new()
	fx.name = "Fx"
	_world.add_child(fx)
	sfx = Sfx.new()
	add_child(sfx)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	_world.add_child(camera_rig)
	camera_rig.setup(board.center(), Vector2(s.grid.width, s.grid.height))
	camera_rig.face_heading(spawn_heading(s))
	camera_rig.camera.current = true
	player = EventPlayer.new()
	player.name = "EventPlayer"
	player.view = self
	player.speed = AUTOPLAY_SPEED if autoplay else GameSettings.game_speed()
	player.concealed = Concealment.active(s)
	add_child(player)
	input = InputController.new()
	input.name = "Input"
	input.view = self
	add_child(input)
	var post := CanvasLayer.new()
	post.name = "PostFx"
	post.layer = 0
	add_child(post)
	post.add_child(PostFx.make())
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	_ui_layer.layer = 1
	add_child(_ui_layer)
	hud = Hud.new()
	_ui_layer.add_child(hud)
	hud.setup(self)
	marks = MarkLayer.new()
	_ui_layer.add_child(marks)
	marks.setup(FightSurface.new(self), session)
	marks.draw_tapped.connect(camera_rig.zoom_cycle)
	player.beat_started.connect(input.on_beat)
	player.beat_started.connect(hud.on_beat)
	player.drained.connect(_on_drained)
	intents = IntentOverlay.new()
	intents.view = self
	_world.add_child(intents)
	input.changed.connect(hud.refresh)
	s.event.connect(_on_state_event)
	show_vision(FogOverlay.annotate(s, {"type": "start"}), true)
	face_threats(true)
	if begin:
		Rules.start_mission(s)


func on_debrief_finished() -> void:
	debrief_done = true
	debrief_finished.emit()


func restart() -> void:
	if session is LocalSession and not (session is TutorialSession):
		start(default_mission())
	else:
		session.restart()


func leave() -> void:
	left_match.emit()


var _pause_layer: CanvasLayer


## Opens or closes the in-game menu (Esc with nothing selected).
func toggle_pause() -> void:
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null
		return
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 40
	add_child(_pause_layer)
	var m: Control = preload("res://ui/pause_menu.gd").new()
	m.closed.connect(toggle_pause)
	m.leave_requested.connect(leave)
	_pause_layer.add_child(m)


func _teardown() -> void:
	if state != null and state.event.is_connected(_on_state_event):
		state.event.disconnect(_on_state_event)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	unit_views.clear()
	state = null


## Night-time quarantine checkpoint: dim moonlight, warm sodium floodlights pooling
## on the ground, teal infection glow carried by bloom, fog and a muted grade.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("07090a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2c3a40")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_strength = 1.1
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(5, 0.3)
	env.fog_enabled = true
	env.fog_light_color = Color("131c1d")
	env.fog_light_energy = 1.0
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0
	# Forward+ only (ignored by the Compatibility renderer).
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.5
	env.ssil_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color("8a9a90")
	env.volumetric_fog_emission = Color("050807")
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 40.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.82
	GameSettings.apply_environment(env)   # the quality preset drops the costly effects
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color("8fa3b0")
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.rotation_degrees = Vector3(-58, -30, 0)
	_world.add_child(moon)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("2f6f6a")
	rim.light_energy = 0.3
	rim.rotation_degrees = Vector3(-25, 150, 0)
	_world.add_child(rim)
	BiomeLook.light(env, moon, rim, state.grid.biome if state != null else "")


func _add_unit_view(u: Unit) -> UnitView:
	var uv := UnitView.new()
	uv.build(u)
	if u.team != Types.Team.PLAYER and state != null and not Vision.sees_unit(state, Types.Team.PLAYER, u):
		uv.visible = false
	EnemyBeats.dress(uv, u)
	if player != null:
		uv.set_concealed(player.concealed)
	uv.stepped.connect(_on_step)
	_units_root.add_child(uv)
	unit_views[u.id] = uv
	return uv


## View for a unit id. Units the view has not seen yet (spawned by another module)
## get a view created from their current state.
func _on_step() -> void:
	if sfx != null and player != null and player.speed <= 3.0:
		sfx.footstep()


func view_for(id: int) -> UnitView:
	if unit_views.has(id):
		return unit_views[id]
	var u: Unit = state.get_unit(id) if state != null else null
	if u == null:
		return null
	return _add_unit_view(u)


## Living unit shown at a cell (by displayed position). Units hidden by fog don't count.
func unit_view_at(c: Vector2i) -> UnitView:
	for uv in unit_views.values():
		if not uv.dead and uv.visible and uv.cell == c:
			return uv
	return null


## Every rules event goes to the event player with a snapshot of what the squad saw at
## that moment (FogOverlay.annotate), so fog and hidden enemies play back in step.
func _on_state_event(ev: Dictionary) -> void:
	player.enqueue(FogOverlay.annotate(state, ev))


## Applies an event's fog snapshot: the fog texture, and which enemies are shown, ghosted
## (Spore Sense) or hidden.
func show_vision(ev: Dictionary, instant := false) -> void:
	if ev.has("_fog"):
		fog.show_fog(ev._fog, instant)
	if not ev.has("_unseen"):
		return
	var unseen: Array = ev._unseen
	var ghosts: Array = ev.get("_sensed", [])
	var alive: Array = ev.get("_alive", [])
	for id in unit_views:
		var uv: UnitView = unit_views[id]
		if not alive.has(id):
			continue
		uv.visible = not unseen.has(id) or ghosts.has(id)
		FogOverlay.set_ghost(uv, ghosts.has(id))


func unit_name(id: int) -> String:
	var uv := view_for(id)
	return uv.label() if uv != null else "#%d" % id


func _on_drained() -> void:
	for u in state.living():   # nobody is left buried by a skipped beat
		var bv := view_for(u.id)
		if bv != null and not u.status.has("burrowed"):
			bv.set_sink(0.0)
	face_threats()
	intents.refresh()
	input.on_drained()
	hud.refresh()


## Idle facing: each unit turns toward its nearest hostile. Dormant enemies keep a
## spread of their own headings until alerted. Worked out from the shared state, so
## every peer shows the same facing.
func face_threats(instant := false) -> void:
	for u in state.living():
		var uv := view_for(u.id)
		if uv == null or uv.dead:
			continue
		if u.team == Types.Team.ENEMY and not EnemyAI.is_alerted(u) and not u.status.get("turned", false):
			if instant:
				uv.set_yaw(fposmod(u.id * 2.399, TAU))
			continue
		var best: Unit = null
		var best_d := INF
		for o in state.living():
			if o != u and u.is_enemy_of(o) and (u.team != Types.Team.PLAYER or Vision.sees_unit(state, u.team, o)):
				var d := Vector2(o.pos - u.pos).length_squared()
				if d < best_d:
					best_d = d
					best = o
		if best != null:
			uv.face_towards(Board.cell_to_world(best.pos), instant)
		elif instant and u.team == Types.Team.PLAYER:
			uv.face_towards(uv.position + spawn_heading(state), true)


## Grid direction from the squad's spawn zone into the map: towards the enemy pods when
## there are any, otherwise towards the map centre. Never zero.
static func spawn_heading(s: GameState) -> Vector3:
	var from := Vector2.ZERO
	var spawns: Array = s.grid.player_spawns
	for c in spawns:
		from += Vector2(c)
	from /= maxi(1, spawns.size())
	var to := Vector2(s.grid.width, s.grid.height) * 0.5
	var pods: Array = s.grid.enemy_spawns
	if not pods.is_empty():
		to = Vector2.ZERO
		for c in pods:
			to += Vector2(c)
		to /= pods.size()
	var d := to - from
	if d.length() < 1.0:
		d = Vector2(s.grid.width, s.grid.height) * 0.5 - from
	if d.length() < 0.5:
		d = Vector2(1, 1)
	return Vector3(d.x, 0, d.y).normalized() * 2.0


# --- headless auto-play ------------------------------------------------------

func _process(_delta: float) -> void:
	if board != null:
		board.tick_hazards(Time.get_ticks_msec() / 1000.0)
		if state != null and not state.grid.roofed.is_empty():
			var squad: Array = []
			for u in state.units:
				if u.team == Types.Team.PLAYER and u.is_alive() and unit_views.has(u.id):
					squad.append((unit_views[u.id] as UnitView).cell)
			board.open_roofs(squad)
	if autoplay and state != null and not player.is_busy():
		_autoplay_step()
	if screenshot_path != "":
		_screenshot_step()


## Dev aid: `--screenshot-action=shoot|fire|ready|overview|scout|map` sets up a scene before the capture
## (scout: a soldier walks out and back, leaving explored-but-not-visible fog behind);
## `--screenshot-frame=N` picks the frame (default 150). With Godot's `--write-movie`
## and `--fixed-fps`, `fire` records a whole shot cinematic.
func _screenshot_step() -> void:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var shot_frame := 150
	for a in args:
		if a.begins_with("--screenshot-frame="):
			shot_frame = int(a.trim_prefix("--screenshot-frame="))
	if _frames == 2 and args.has("--screenshot-action=map"):   # whole map, fog off, from high up
		Vision.disable(state)
		show_vision(FogOverlay.annotate(state, {"type": "start"}), true)
		fog.visible = false
		_ui_layer.visible = false
		var sun := DirectionalLight3D.new()   # flat daylight so the layout reads
		sun.light_energy = 1.6
		sun.rotation_degrees = Vector3(-60, 35, 0)
		sun.shadow_enabled = true
		_world.add_child(sun)
	if _frames == 60 and args.has("--screenshot-action=map"):
		camera_rig._target_dist = CameraRig.MAX_DIST
		camera_rig._dist = CameraRig.MAX_DIST
		camera_rig.focus(board.center())
	elif _frames == 60 and (args.has("--screenshot-action=overview") or args.has("--screenshot-action=scout")):   # whole map from high up
		camera_rig._target_dist = CameraRig.MAX_DIST
		camera_rig.focus(board.center())
		if args.has("--screenshot-action=scout"):
			var u := state.controllable_units(0)[0]
			set_meta("scout_from", u.pos)
			for i in 2:
				var m := _autoplay_advance(u)
				if not m.is_empty():
					session.submit(m)
	elif _frames == 100 and args.has("--screenshot-action=scout"):
		var u := state.controllable_units(1)[0]
		var m := _autoplay_advance(u)
		if not m.is_empty():
			session.submit(m)
	elif _frames == 60 and args.has("--screenshot-action=marks"):
		_screenshot_marks()
	elif _frames == 60:
		input.cycle()
	elif _frames == 70 and (args.has("--screenshot-action=shoot") or args.has("--screenshot-action=fire")):
		input.trigger("shoot")
	elif _frames == 100 and args.has("--screenshot-action=fire"):
		input.confirm_shot()
	elif _frames == 70 and args.has("--screenshot-action=ready"):
		for p in session.local_players():
			session.set_ready(p, true)
	elif _frames == shot_frame:
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		print("[screenshot] saved ", screenshot_path)
		get_tree().quit(0)


## Dev aid for `--screenshot-action=marks`: two players' pings (one off screen), strokes and the
## ping wheel open.
func _screenshot_marks() -> void:
	Vision.disable(state)
	show_vision(FogOverlay.annotate(state, {"type": "start"}), true)
	input.deselect()
	var enemy: Unit = state.living(Types.Team.ENEMY)[0]
	camera_rig.focus(Board.cell_to_world(enemy.pos + Vector2i(-1, 1)))
	camera_rig.snap()
	var send := func(m: Dictionary) -> void:
		marks._on_marked(Marks.sanitize(m))
	var to := enemy.pos + Vector2i(-3, 2)
	send.call({"type": "ping", "player": 0, "where": "fight", "kind": "attack", "cell": enemy.pos, "unit": enemy.id})
	send.call({"type": "ping", "player": 1, "where": "fight", "kind": "move", "cell": to})
	send.call({"type": "ping", "player": 1, "where": "fight", "kind": "danger", "cell": Vector2i(state.grid.width - 1, 0)})
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var p0 := Board.cell_to_world(to, 0.06)
	var p1 := Board.cell_to_world(enemy.pos, 0.06)
	for i in 16:   # player 2 draws a curved approach; player 1 circles the enemy
		var k := i / 15.0
		a.append(p0.lerp(p1, k) + Vector3(sin(k * PI) * 1.2, 0, 0))
		b.append(p1 + Vector3(cos(k * TAU * 0.9) * 1.1, 0, sin(k * TAU * 0.9) * 1.1))
	send.call({"type": "stroke", "player": 1, "where": "fight", "id": 1, "points": a})
	send.call({"type": "stroke", "player": 0, "where": "fight", "id": 1, "points": b})
	marks.wheel.size = marks.size
	marks.wheel.open_at(marks.size * Vector2(0.74, 0.5), Marks.color(0), "Fuel barrel")
	marks.wheel.point_at(Vector2(60, 60))


func _autoplay_step() -> void:
	if _autoplay_done:
		return
	if state.phase == Types.Phase.ENDED or state.turn > AUTOPLAY_MAX_TURNS:
		_autoplay_done = true
		var res: String = Types.Result.keys()[state.result]
		print("[autoplay] finished: turn %d, result %s, %d events, checksum %d" % [state.turn, res, state.log.size(), state.checksum()])
		if state.phase != Types.Phase.ENDED:   # out of turns: say what the fight was stuck on
			var foes: Array = state.living(Types.Team.ENEMY).map(func(u: Unit) -> String: return "%s@%s hp%d" % [u.kind, u.pos, u.hp])
			var squad: Array = state.living(Types.Team.PLAYER).map(func(u: Unit) -> String: return "%s@%s hp%d" % [u.kind, u.pos, u.hp])
			print("[autoplay] stalled: objective %s %s, soldiers %s, enemies %s" % [state.grid.objective, state.objective, squad, foes])
		if session.get("run") != null:
			return   # in a run the run view carries on to the next node
		# Online, give the last network messages a moment to go out before quitting.
		get_tree().create_timer(0.1 if session is LocalSession else 1.5).timeout.connect(func() -> void: get_tree().quit(0))
		return
	if state.phase != Types.Phase.TEAM or (session.has_method("is_waiting") and session.is_waiting()):
		return
	_autoplay_marks()
	# One shot per frame from any of our soldiers with a visible target, then ready up.
	for p in session.local_players():
		for u in state.controllable_units(p):
			if u.actions_left > 0:
				var reload := {"type": Types.RELOAD, "unit": u.id}
				if not Ammo.can_fire(u) and Rules.validate(state, reload) == "":
					session.submit(reload)   # a dry gun reloads before anything else
					return
				var targets := Combat.shot_targets(state, u)
				var shot := {"type": Types.SHOOT, "unit": u.id, "target": targets[0].id} if not targets.is_empty() else {}
				if not shot.is_empty() and Rules.validate(state, shot) == "":
					session.submit(shot)
					return
	# Nothing in sight (fog of war): advance on the nearest enemy, one move per frame.
	for p in session.local_players():
		for u in state.controllable_units(p):
			if u.actions_left > 0 and Combat.shot_targets(state, u).is_empty():
				var move := _autoplay_advance(u)
				if not move.is_empty():
					session.submit(move)
					return
	# Civilians are ours to move too: walk them to the exit or evac once the squad is close or the fight is over.
	for c in state.living(Types.Team.PLAYER).filter(func(c: Unit) -> bool: return Objectives.is_civilian(c)):
		if c.actions_left > 0 and (state.living(Types.Team.ENEMY).is_empty() or Objectives.nearest_soldier_dist(state, c.pos) <= 2):
			var cm := _autoplay_advance(c)
			if not cm.is_empty():
				session.submit(cm)
				return
	for p in session.local_players():
		if state.phase == Types.Phase.TEAM and not state.ready.get(p, false):
			print("[autoplay] turn %d: player %d ready" % [state.turn, p])
			session.set_ready(p, true)
			return


var _autoplay_marked := false


## Test aid (`--autoplay-marks`): on its first turn each peer pings a soldier's cell and draws a
## short line, so tests/net_playtest.sh can check marks cross the network.
func _autoplay_marks() -> void:
	if _autoplay_marked or not OS.get_cmdline_user_args().has("--autoplay-marks") or marks == null:
		return
	_autoplay_marked = true
	var mine := state.controllable_units(session.local_players()[0])
	if mine.is_empty():
		return
	var c: Vector2i = mine[0].pos
	marks.ping({"cell": c, "context": ""}, "move")
	session.mark({"type": Marks.STROKE, "where": Marks.FIGHT, "player": session.local_players()[0], "id": 1, "end": true,
		"points": PackedVector3Array([Board.cell_to_world(c), Board.cell_to_world(c + Vector2i(2, 1))])})


## The move that takes `u` closest to the nearest enemy, or {} if it is as close as it gets.
func _autoplay_advance(u: Unit) -> Dictionary:
	var foes := state.living(Types.Team.ENEMY)
	var goals: Array = foes.map(func(e: Unit) -> Vector2i: return e.pos)
	if Objectives.is_civilian(u):   # a civilian only ever heads for the way out
		goals = state.grid.marker("evac" if str(state.grid.objective) == "escort" else "exit")
	elif goals.is_empty():   # nobody left to fight: walk to the objective (the squad then escorts the civilians)
		goals = state.grid.marker({"rescue": "exit", "escort": "evac", "extract": "evac", "hold": "beacon"}.get(str(state.grid.objective), ""))
	if goals.is_empty():
		return {}
	# Walk the real way round walls and through doorways: head for the goal nearest by path, and take
	# the cell in range that is closest to it by path (straight-line distance dead-ends against a wall).
	var from_here := state.grid.reachable(u.pos, 1000)
	var goal: Vector2i = goals[0]
	var best_d := 1 << 30
	for g in goals:
		var d: int = from_here.get(g, 1 << 29)
		if d < best_d:
			best_d = d
			goal = g
	var to_goal := state.grid.reachable(goal, 1000)
	var here: int = to_goal.get(u.pos, 1 << 29)
	var best := u.pos
	var best_path := here
	for c in Rules.move_range(state, u):
		var d: int = to_goal.get(c, 1 << 29)
		if d < best_path:
			best_path = d
			best = c
	if best == u.pos or best == goal:
		return {}
	var move := {"type": Types.MOVE, "unit": u.id, "to": best}
	return move if Rules.validate(state, move) == "" else {}
