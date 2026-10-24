extends Node3D
## Angled tactical camera. WASD / arrow keys / screen-edge pan, Q/E rotate in
## 90 degree steps, mouse wheel zoom. Everything eases towards its target.
## Keys are InputMap actions (rebindable, see view/game_settings.gd); on a gamepad the
## right stick pans, LT/RT rotate and the stick clicks zoom.
##
## Cinematic mode (shot cams): the event player hands over two camera poses and
## drives the blend between them on its own clock with `cine_progress`, so slow
## motion and test stepping stay in sync. `end_cinematic` cuts back to tactical.

const Board := preload("res://view/board.gd")
const PITCH_DEG := 55.0
const MIN_DIST := 6.0
const MAX_DIST := 26.0
const PAN_SPEED := 12.0
const EDGE_PX := 12

var camera: Camera3D
var bounds := AABB(Vector3.ZERO, Vector3(16, 0, 16))
var edge_pan := true

var _target_pos := Vector3.ZERO
var _target_yaw := deg_to_rad(45.0)
var _target_dist := 13.0
var _yaw := _target_yaw
var _dist := _target_dist

var cinematic := false
var _cine_from := Transform3D.IDENTITY
var _cine_to := Transform3D.IDENTITY
var _cine_fov := Vector2(50, 50)
var _cine_k := 0.0
var _shake := 0.0
var _shake_t := 0.0
var _kick := 0.0


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 200.0
	add_child(camera)


func setup(board_center: Vector3, board_size: Vector2) -> void:
	bounds = AABB(Vector3(-1, 0, -1), Vector3(board_size.x + 1, 0, board_size.y + 1))
	_target_pos = board_center
	snap()


## Ease the camera towards a world point (e.g. an acting enemy).
func focus(world: Vector3) -> void:
	_target_pos = _clamp(Vector3(world.x, 0, world.z))


## Starts (or re-aims) a cinematic shot: camera moves from pose `from` to `to`
## (world transforms, looking down -Z) and FOV from `fov.x` to `fov.y`.
func cine(from: Transform3D, to: Transform3D, fov := Vector2(42, 42)) -> void:
	cinematic = true
	_cine_from = from
	_cine_to = to
	_cine_fov = fov
	cine_progress(0.0)


func cine_progress(k: float) -> void:
	_cine_k = clampf(k, 0.0, 1.0)
	_apply()


func end_cinematic() -> void:
	if not cinematic:
		return
	cinematic = false
	camera.fov = 50.0
	_apply()


## A camera pose at `eye` looking at `target`.
static func look_pose(eye: Vector3, target: Vector3) -> Transform3D:
	var d := target - eye
	var up := Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(d, up), eye)


## Scaled by the Screen shake setting (0 turns shake and recoil punch off).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * GameSettings.screen_shake())


## Recoil punch: the camera snaps back a little and the FOV widens, then settles.
func kick(amount: float) -> void:
	_kick = minf(2.0, _kick + amount * GameSettings.screen_shake())


func rotate_step(dir: int) -> void:
	_target_yaw += dir * PI * 0.5


func zoom_step(dir: int) -> void:
	_target_dist = clampf(_target_dist * (1.0 + 0.12 * dir), MIN_DIST, MAX_DIST)


func snap() -> void:
	position = _target_pos
	_yaw = _target_yaw
	_dist = _target_dist
	_apply()


func _clamp(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, bounds.position.x, bounds.end.x), 0, clampf(p.z, bounds.position.z, bounds.end.z))


func _process(delta: float) -> void:
	_discrete_input()
	var move := _pan_input()
	if move != Vector2.ZERO:
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0, -sin(_yaw))
		var speed := PAN_SPEED * GameSettings.camera_speed() * (_dist / 15.0) * delta
		_target_pos = _clamp(_target_pos + (right * move.x + fwd * move.y) * speed)
	var k := 1.0 - exp(-delta * 8.0)
	position = position.lerp(_target_pos, k)
	_yaw = lerp_angle(_yaw, _target_yaw, k)
	_dist = lerpf(_dist, _target_dist, k)
	_shake = move_toward(_shake, 0.0, delta * 2.5)
	_kick = move_toward(_kick, 0.0, delta * (4.0 + _kick * 6.0))
	_shake_t += delta
	_apply()


func _pan_input() -> Vector2:
	var v := Vector2.ZERO
	if cinematic:
		return v
	if not _input_blocked():
		v.x = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
		v.y = Input.get_action_strength("cam_forward") - Input.get_action_strength("cam_back")
	if edge_pan and GameSettings.edge_pan() and not _input_blocked() and DisplayServer.get_name() != "headless" and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		if Rect2(Vector2.ZERO, size).has_point(m):
			if m.x < EDGE_PX: v.x -= 1
			elif m.x > size.x - EDGE_PX: v.x += 1
			if m.y < EDGE_PX: v.y += 1
			elif m.y > size.y - EDGE_PX: v.y -= 1
	return v.limit_length(1.0)


## Rotate and zoom are polled so the gamepad triggers (analog axes) step once per pull.
func _discrete_input() -> void:
	if cinematic or _input_blocked():
		return
	if Input.is_action_just_pressed("cam_rotate_left"): rotate_step(-1)
	if Input.is_action_just_pressed("cam_rotate_right"): rotate_step(1)
	if Input.is_action_just_pressed("cam_zoom_in"): zoom_step(-2)
	if Input.is_action_just_pressed("cam_zoom_out"): zoom_step(2)


## The Settings screen or a text field has the keyboard.
func _input_blocked() -> bool:
	GameSettings.ensure_input_map()
	if GameSettings.is_menu_open():
		return true
	var vp := get_viewport()
	return vp != null and vp.gui_get_focus_owner() is LineEdit


func _unhandled_input(event: InputEvent) -> void:
	if cinematic:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: zoom_step(-1)
			MOUSE_BUTTON_WHEEL_DOWN: zoom_step(1)


func _apply() -> void:
	var jitter := Vector3.ZERO
	if _shake > 0.0:
		var a := _shake * _shake * 0.12
		jitter = Vector3(sin(_shake_t * 71.0), sin(_shake_t * 53.0 + 1.3), sin(_shake_t * 61.0 + 2.1)) * a
	if cinematic:
		var e := _cine_k * _cine_k * (3.0 - 2.0 * _cine_k)   # smoothstep
		var pose := _cine_from.interpolate_with(_cine_to, e)
		pose.origin += jitter + pose.basis.z * _kick * 0.07
		# The camera is a child of the rig, so express the world pose in rig space.
		camera.transform = transform.affine_inverse() * pose
		camera.fov = lerpf(_cine_fov.x, _cine_fov.y, e) + _kick * 2.5
		return
	var pitch := deg_to_rad(PITCH_DEG)
	var offset := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch)) * _dist
	camera.transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset * (1.0 + _kick * 0.012) + jitter)


## Cell under a screen point, by intersecting the camera ray with the floor plane.
func screen_to_world(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	# Highest level first: a roof hides what is behind and below it.
	for lvl in range(Grid.MAX_LEVEL, 0, -1):
		var roof: Variant = Plane(Vector3.UP, Board.RAISE * lvl).intersects_ray(origin, dir)
		if roof != null and Board.lift(Board.world_to_cell(roof)) >= Board.RAISE * lvl - 0.01:
			return roof
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
