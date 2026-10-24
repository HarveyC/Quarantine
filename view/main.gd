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

signal left_match

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
var camera_rig: CameraRig
var player: EventPlayer
var input: InputController
var hud: Hud
var unit_views: Dictionary = {}   # unit id -> UnitView
var autoplay := false
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
		start(default_mission())


func _exit_tree() -> void:
	if session is LocalSession and not session.is_inside_tree():
		session.free()


static func default_mission(seed: int = 0) -> GameState:
	var squad := [
		{"kind": "trooper", "player": 0}, {"kind": "marksman", "player": 0},
		{"kind": "medic", "player": 1}, {"kind": "breacher", "player": 1},
	]
	var enemies: Array[String] = ["runner", "runner", "spitter", "runner", "spitter"]
	return Rules.new_mission(MAP, squad, enemies, seed)


## Builds the whole view for `s` and starts the mission. Works out of the tree too (tests).
func start(s: GameState, begin := true) -> void:
	_teardown()
	state = s
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
	_world.add_child(board)
	_units_root = Node3D.new()
	_units_root.name = "Units"
	_world.add_child(_units_root)
	for u in s.units:
		_add_unit_view(u)
	fx = Fx.new()
	fx.name = "Fx"
	_world.add_child(fx)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	_world.add_child(camera_rig)
	camera_rig.setup(board.center(), Vector2(s.grid.width, s.grid.height))
	camera_rig.camera.current = true
	player = EventPlayer.new()
	player.name = "EventPlayer"
	player.view = self
	player.speed = AUTOPLAY_SPEED if autoplay else 1.0
	add_child(player)
	input = InputController.new()
	input.name = "Input"
	input.view = self
	add_child(input)
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	add_child(_ui_layer)
	hud = Hud.new()
	_ui_layer.add_child(hud)
	hud.setup(self)
	player.beat_started.connect(input.on_beat)
	player.beat_started.connect(hud.on_beat)
	player.drained.connect(_on_drained)
	input.changed.connect(hud.refresh)
	s.event.connect(player.enqueue)
	if begin:
		Rules.start_mission(s)


func restart() -> void:
	if session is LocalSession:
		start(default_mission())
	else:
		session.restart()


func leave() -> void:
	left_match.emit()


func _teardown() -> void:
	if state != null and state.event.is_connected(player.enqueue):
		state.event.disconnect(player.enqueue)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	unit_views.clear()
	state = null


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0d0c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a4a4e")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color("1c2a2a")
	env.fog_density = 0.012
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("c9c2ad")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, -35, 0)
	_world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("2f6f6a")
	rim.light_energy = 0.25
	rim.rotation_degrees = Vector3(-30, 150, 0)
	_world.add_child(rim)


func _add_unit_view(u: Unit) -> UnitView:
	var uv := UnitView.new()
	uv.build(u)
	_units_root.add_child(uv)
	unit_views[u.id] = uv
	return uv


## View for a unit id. Units the view has not seen yet (spawned by another module)
## get a view created from their current state.
func view_for(id: int) -> UnitView:
	if unit_views.has(id):
		return unit_views[id]
	var u: Unit = state.get_unit(id) if state != null else null
	if u == null:
		return null
	return _add_unit_view(u)


## Living unit shown at a cell (by displayed position).
func unit_view_at(c: Vector2i) -> UnitView:
	for uv in unit_views.values():
		if not uv.dead and uv.cell == c:
			return uv
	return null


func unit_name(id: int) -> String:
	var uv := view_for(id)
	return uv.label() if uv != null else "#%d" % id


func _on_drained() -> void:
	input.on_drained()
	hud.refresh()


# --- headless auto-play ------------------------------------------------------

func _process(_delta: float) -> void:
	if autoplay and state != null and not player.is_busy():
		_autoplay_step()
	if screenshot_path != "":
		_screenshot_step()


## Dev aid: `--screenshot-action=shoot|ready` sets up a scene before the capture.
func _screenshot_step() -> void:
	_frames += 1
	var args := OS.get_cmdline_user_args()
	if _frames == 60:
		input.cycle()
	elif _frames == 70 and args.has("--screenshot-action=shoot"):
		input.trigger("shoot")
	elif _frames == 70 and args.has("--screenshot-action=ready"):
		for p in session.local_players():
			session.set_ready(p, true)
	elif _frames == 150:
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		print("[screenshot] saved ", screenshot_path)
		get_tree().quit(0)


func _autoplay_step() -> void:
	if _autoplay_done:
		return
	if state.phase == Types.Phase.ENDED or state.turn > AUTOPLAY_MAX_TURNS:
		_autoplay_done = true
		var res: String = Types.Result.keys()[state.result]
		print("[autoplay] finished: turn %d, result %s, %d events, checksum %d" % [state.turn, res, state.log.size(), state.checksum()])
		# Online, give the last network messages a moment to go out before quitting.
		get_tree().create_timer(0.1 if session is LocalSession else 1.5).timeout.connect(func() -> void: get_tree().quit(0))
		return
	if state.phase != Types.Phase.TEAM or (session.has_method("is_waiting") and session.is_waiting()):
		return
	# One shot per frame from any of our soldiers with a visible target, then ready up.
	for p in session.local_players():
		for u in state.controllable_units(p):
			if u.actions_left > 0:
				var targets := Combat.visible_targets(state, u)
				var shot := {"type": Types.SHOOT, "unit": u.id, "target": targets[0].id} if not targets.is_empty() else {}
				if not shot.is_empty() and Rules.validate(state, shot) == "":
					session.submit(shot)
					return
	for p in session.local_players():
		if state.phase == Types.Phase.TEAM and not state.ready.get(p, false):
			print("[autoplay] turn %d: player %d ready" % [state.turn, p])
			session.set_ready(p, true)
			return
