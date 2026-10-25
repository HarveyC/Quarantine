extends Node3D
## Visual for one unit. Holds its own *displayed* copy of hp / infection / statuses,
## updated only by the event player, so the 3D view and HUD can lag behind the
## rules state while animations play.
##
## Soldiers, the infected and civilians are skinned characters (assets/characters, CC0
## Quaternius bodies and clips dressed by tools/build_characters.py) driven by
## SkinnedBody: clips for idle / walk / crouch / hit / death, the rifle posed
## procedurally from low ready to aimed with both hands on it by IK, one-shots for melee
## and spitting. The Bloom's props and the Drifter are static models (assets/models)
## that breathe. Infection shows as spreading veins (character shader) and growths that
## break out per tier. `tick` runs on the event player's clock, so slow motion in a shot
## cinematic slows the bodies too.

signal stepped   # a foot landed while walking (for footstep sounds)

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

const ModelKit := preload("res://view/model_kit.gd")
const GunModels := preload("res://view/gun_models.gd")
const SkinnedBody := preload("res://view/skinned_body.gd")
const MeleeKit := preload("res://view/melee_kit.gd")
const GraftKit := preload("res://view/graft_kit.gd")
const TURN_SPEED := 9.0   # radians per second
## Units are drawn a little larger than life so they read from the tactical camera.
const MODEL_SCALE := 1.12

var unit_id := 0
var kind := ""
var weapon := ""          # weapon id fired (Weapons.id_of), for the gun's look and feel
var display_name := ""
var owner_player := -1
var is_soldier := true
## Built from a soldier model: the squad, and an Echo (a Turned soldier from an earlier run) on the enemy team.
var soldier_body := true
var cell := Vector2i.ZERO
var hp := 1
var max_hp := 1
var infection := 0
var tier := 0
var overwatch := false
var hunkered := false
var guard := false        # Warden's Guard stance (shield up until the next squad phase)
var lapsed := false
var turned := false
var dead := false
var concealed := false    # squad Concealed: a cold-blue dashed ring at the feet
## Timed tags the beats put on this unit (MARKED, SUPPRESSED, STUNNED, CONTAINED):
## key -> the phase index (Combat.phase_index) it ends on. Shown on the status line.
var tags := {}
## Grafts the body wears ({slot: id}), hung on the skeleton by GraftKit.
var grafts := {}

var _body: Node3D        # yaw only
var _rig: Node3D         # bob, lean, knockback, lunge
var _model: Node3D
var _muzzle: Node3D      # props: where spores leave
var _prop: Node3D        # props: the part that breathes
var _prop_y := 0.0
var _aim_local := Vector3(0, 0.85, 0)   # props: middle of the model's bounds, in the rig's space
var _aim_world := Vector3.INF           # what the weapon is pointed at (aim_at), INF = level
var _pitch := 0.0                       # weapon pitch towards _aim_world, radians (+ = down)
var _sac: Node3D         # spitter / bloater glowing sac
var _skin: SkinnedBody   # characters (everything but props)
var _glow: OmniLight3D
var _mats := {}          # role -> ShaderMaterial (this unit's own copies)
var _growths := []       # [stage, MeshInstance3D] infection growths
var _shown_stage := 0
var _popping: Array[Node3D] = []   # growths bursting out during pulse_infection
var _yaw := 0.0
var _yaw_target := 0.0
var _hp_sprite: Sprite3D
var _status_label: Label3D
var _class_label: Label3D
var _infection_ring: MeshInstance3D
var _infection_mat: StandardMaterial3D
var _select_ring: MeshInstance3D
var _target_ring: MeshInstance3D
var _guard_ring: MeshInstance3D
var _cloak_ring: Node3D
var _drawn := false      # melee classes: sidearm out (aiming) instead of the melee weapon
## False when the HUD draws its own nameplates, which hides the floating 3D labels.
static var world_labels := true

var _overlays_on := true
var _flash := 0.0
var _flash_color := Color.WHITE

# animation state
var _time := 0.0
var _moving := false
var _walk := 0.0
var _stride := 0.0
var _aim := 0.0
var _aim_target := 0.0
var _recoil := 0.0
var _hit := 0.0
var _hit_dir := Vector3.ZERO
var _lunge := 0.0
var _crouch := 0.0
var _death := 0.0
# fitting the body to stairs and ramps under its feet (see _fit_ground)
var _feet: Array[Vector3] = []   # foot points in the body's frame, before it turns
var _crawler := false            # many-legged (Lurker, Burrower): tilts with the slope
var _fit_off := 0.0
var _fit_pitch := 0.0
var _fit_roll := 0.0
var _fit_snap := true


func build(u: Unit) -> void:
	unit_id = u.id
	kind = u.kind
	weapon = Weapons.id_of(u)
	display_name = u.display_name
	owner_player = u.owner_player
	is_soldier = u.team == Types.Team.PLAYER
	soldier_body = is_soldier or u.status.has("echo")
	hp = u.hp
	max_hp = u.max_hp
	infection = u.infection
	tier = Infection.tier(u.infection)
	lapsed = u.status.get("lapsed", false)
	grafts = Grafts.of_unit(u).duplicate()
	name = "Unit%d" % unit_id
	_time = float(unit_id) * 1.37
	_body = Node3D.new()
	add_child(_body)
	_rig = Node3D.new()
	_body.add_child(_rig)
	_build_model()
	_build_rings()
	_build_labels()
	set_cell(u.pos)
	_refresh_all()
	if u.status.get("turned", false) and soldier_body:
		set_turned()
	if _skin != null:
		_skin.advance(0.0)


# --- model -------------------------------------------------------------------

func _build_model() -> void:
	_model = ModelKit.instantiate(kind, soldier_body)
	if is_soldier and Weapons.look_of(weapon) != GunModels.kind_look(kind):
		GunModels.swap_look(_model, Weapons.look_of(weapon))
	if soldier_body:
		GraftKit.dress(_model, grafts)
	_rig.add_child(_model)
	_mats = ModelKit.apply_materials(_model, owner_player, soldier_body)
	MeleeKit.tint(kind, _mats)
	_growths = ModelKit.growths(_model)
	_sac = ModelKit.find(_model, "sac")
	if ModelKit.is_skinned(_model):
		_skin = SkinnedBody.new()
		_skin.setup(_model, not soldier_body)
		_skin.speed = {"runner": 1.3, "leaper": 1.2, "broodling": 1.4, "brood_mother": 0.7, "brute": 0.85}.get(kind, 1.0)
	else:
		_prop = ModelKit.find(_model, "body")
		_prop_y = _prop.position.y if _prop != null else 0.0
		_muzzle = ModelKit.find(_model, "muzzle")
		_aim_local = ModelKit.bounds(_model, _rig).get_center()
	_build_lights()


func _build_lights() -> void:
	_glow = OmniLight3D.new()
	_glow.light_color = Palette.TEAL
	_glow.shadow_enabled = false
	_rig.add_child(_glow)
	# a soft key light that travels with the unit so it reads at tactical zoom
	# on the dark map (XCOM-style character light); no shadows, cheap
	var key := OmniLight3D.new()
	key.light_color = Color("ffe6c4") if soldier_body else Color("9fc9c0")
	key.light_energy = 0.75 if soldier_body else 0.5
	key.omni_range = 2.4
	key.omni_attenuation = 1.6
	key.shadow_enabled = false
	key.position = Vector3(0.5, 2.3, 0.7)
	add_child(key)
	_model.scale = Vector3.ONE * MODEL_SCALE * ModelKit.size_of(kind)
	if soldier_body:
		_glow.omni_range = 2.2
		_glow.light_energy = 0.0
		_glow.position = Vector3(0, 1.1, 0)
		_glow.visible = false
	else:
		_glow.omni_range = 2.6 if kind == "spitter" else 2.0
		_glow.light_energy = _enemy_glow()
		_glow.position = Vector3(0, 0.95, 0.1)
		_set_veins(0.62)


func _enemy_glow() -> float:
	return 1.1 if kind in ["spitter", "bloater", "drifter", "the_source"] else 0.7


func _set_veins(k: float) -> void:
	for m in _mats.values():
		var role: String = m.get_meta("role")
		if role in ModelKit.VEINABLE:
			# bare infected skin carries fewer veins than the cloth so they don't read as camo
			m.set_shader_parameter("infection", k * 0.75 if role in ["body", "chitin"] and not soldier_body else k)


func _build_rings() -> void:
	_infection_mat = Palette.emissive(Palette.TEAL, 1.0)
	_infection_ring = Palette.ring(0.34, 0.44, _infection_mat)
	_infection_ring.position.y = 0.03
	_infection_ring.scale.y = 0.3
	add_child(_infection_ring)
	_select_ring = Palette.ring(0.42, 0.48, Palette.overlay(Color(1, 0.86, 0.5, 0.95)))
	_select_ring.position.y = 0.04
	_select_ring.scale.y = 0.2
	_select_ring.visible = false
	add_child(_select_ring)
	_target_ring = Palette.ring(0.44, 0.52, Palette.overlay(Color(Palette.DANGER, 0.95)))
	_target_ring.position.y = 0.05
	_target_ring.scale.y = 0.2
	_target_ring.visible = false
	add_child(_target_ring)
	_guard_ring = Palette.ring(0.5, 0.56, Palette.emissive(Palette.AMBER, 1.6))
	_guard_ring.position.y = 0.035
	_guard_ring.scale.y = 0.2
	_guard_ring.visible = false
	add_child(_guard_ring)
	# Concealed: twelve cold-blue dashes around the feet, the squad-wide "unseen" read.
	_cloak_ring = Node3D.new()
	_cloak_ring.position.y = 0.03
	_cloak_ring.visible = false
	var dash := Palette.overlay(Color(Palette.STEALTH, 0.9))
	for i in 12:
		var a := TAU * float(i) / 12.0
		var d := Palette.box(Vector3(0.16, 0.02, 0.05), dash)
		d.position = Vector3(cos(a), 0, sin(a)) * 0.58
		d.rotation.y = -a + PI * 0.5
		_cloak_ring.add_child(d)
	add_child(_cloak_ring)


func _build_labels() -> void:
	_hp_sprite = Sprite3D.new()
	_hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_sprite.no_depth_test = true
	_hp_sprite.pixel_size = 0.012
	_hp_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_hp_sprite.position.y = 2.15
	add_child(_hp_sprite)
	var tag := Palette.class_letter(kind)
	if is_soldier:
		tag += " P%d" % (owner_player + 1)
	var col := Palette.player_ui(owner_player) if is_soldier else Palette.TEAL
	_class_label = Palette.label3d(tag, 44, col)
	_class_label.position.y = 2.5
	add_child(_class_label)
	_status_label = Palette.label3d("", 28, Palette.AMBER)
	_status_label.position.y = 1.75
	add_child(_status_label)
	for n in [_hp_sprite, _class_label, _status_label]:
		n.visible = world_labels


# --- display state ----------------------------------------------------------

func label() -> String:
	if is_soldier and owner_player >= 0:
		return "%s (P%d)" % [display_name, owner_player + 1]
	return display_name


func set_cell(c: Vector2i) -> void:
	cell = c
	position = Board.cell_to_world(c)
	_fit_snap = true


## Turns the body to face `world`: smoothly in `tick`, or at once with `instant`.
func face_towards(world: Vector3, instant := false) -> void:
	var d := world - position
	if Vector2(d.x, d.z).length() > 0.01:
		_yaw_target = atan2(d.x, d.z)
		if instant:
			set_yaw(_yaw_target)


func set_yaw(yaw: float) -> void:
	_yaw = yaw
	_yaw_target = yaw
	_body.rotation.y = yaw


func facing() -> Vector3:
	return Vector3(sin(_body.rotation.y), 0, cos(_body.rotation.y))


func set_hp(value: int) -> void:
	hp = value
	_refresh_hp()


func set_infection(value: int, t: int) -> void:
	infection = value
	tier = t
	_refresh_infection()


func set_statuses(ow: bool, hk: bool) -> void:
	overwatch = ow
	hunkered = hk
	_refresh_status()


## Warden's Guard stance: shield-up pose, an amber ring and the GUARD tag.
func set_guard(on: bool) -> void:
	guard = on
	_guard_ring.visible = on and not dead
	_refresh_status()


func is_melee_class() -> bool:
	return _skin != null and _skin.melee != ""


func set_lapsed(on: bool) -> void:
	lapsed = on
	_refresh_status()


func set_turned() -> void:
	turned = true
	lapsed = false
	var dead_col := Palette.player_body(owner_player).lerp(Palette.ENEMY_BODY, 0.7)
	for role in ["body", "cloth_team", "cloak_team", "armor_team"]:
		if _mats.has(role):
			_mats[role].set_shader_parameter("albedo", dead_col.darkened(0.1 if role == "cloth_team" else 0.3))
	_class_label.modulate = Palette.TEAL
	if _skin != null:
		_skin.set_feral(true)
	_glow.visible = true
	_glow.light_energy = 1.0
	_refresh_infection()
	_refresh_status()


## Squad concealment shown on this soldier (EventPlayer.concealed).
func set_concealed(on: bool) -> void:
	concealed = on
	_cloak_ring.visible = on and is_soldier and not dead and _overlays_on


func set_tag(key: String, until: int) -> void:
	tags[key] = maxi(until, int(tags.get(key, -1)))
	_refresh_status()


## Drops tags that ended by phase `now`.
func expire_tags(now: int) -> void:
	var gone := false
	for k in tags.keys():
		if int(tags[k]) <= now:
			tags.erase(k)
			gone = true
	if gone:
		_refresh_status()


func set_selected(on: bool) -> void:
	_select_ring.visible = on


func set_targeted(on: bool) -> void:
	_target_ring.visible = on


## Hides the floating HP / labels / rings, e.g. during a shot cinematic.
func set_overlays_visible(on: bool) -> void:
	_overlays_on = on
	for n in [_hp_sprite, _class_label, _status_label]:
		n.visible = on and not dead and world_labels
	_guard_ring.visible = on and guard and not dead
	_cloak_ring.visible = on and concealed and is_soldier and not dead
	if not on:
		_select_ring.visible = false
		_target_ring.visible = false


func flash(color: Color) -> void:
	_flash = 1.0
	_flash_color = color
	_apply_flash()


# --- animation controls (called by the event player) --------------------------

func set_moving(on: bool) -> void:
	_moving = on


## 0 = weapon at low ready, 1 = shouldered and aimed.
func set_aim(target: float) -> void:
	_aim_target = target
	if target <= 0.0:
		_aim_world = Vector3.INF


## Points the weapon at `world` (pitching it up or down) while aimed; set_aim(0) levels it.
func aim_at(world: Vector3) -> void:
	_aim_world = world
	_pitch = aim_pitch(world)


## Pitch (radians, + = down) from this body's shoulder to `world`, within what the arms reach.
func aim_pitch(world: Vector3) -> float:
	var sp: Variant = _bone_world(["spine_03"])
	var from: Vector3 = (sp as Vector3) + Vector3(0, 0.12, 0) if sp != null else position + Vector3(0, 1.4, 0)
	var d := world - from
	return clampf(atan2(-d.y, Vector2(d.x, d.z).length()), -0.6, 0.85)


func aim_now(k: float) -> void:
	_aim = k
	_aim_target = k


func recoil(strength := 1.0) -> void:
	_recoil = strength
	if _skin != null:
		_skin.play_once("shoot")


## Knock the body away from `from_world`.
func hit_react(from_world: Vector3, strength := 1.0) -> void:
	var d := position - from_world
	d.y = 0.0
	_hit_dir = d.normalized() if d.length() > 0.01 else -facing()
	_hit = strength
	if _skin != null:
		_skin.play_once("hit")


## Melee lunge 0..1 (forward strike).
func set_lunge(k: float) -> void:
	if _skin != null and k > 0.05 and _lunge <= 0.05:
		_skin.play_once("melee", 1.3)
	_lunge = k


func muzzle_world() -> Vector3:
	if _skin != null and MeleeKit.MUZZLE.has(_skin.melee):   # the sidearm in the weapon hand
		return _to_world(_skin.skel, _skin.bone_pose("hand_r") * MeleeKit.MUZZLE[_skin.melee])
	if _skin != null:
		var sock := "muzzle" if _skin.skel.find_bone("muzzle") >= 0 else "Head"
		return _to_world(_skin.skel, _skin.bone_pose(sock).origin)
	if _muzzle != null:
		return _to_world(_muzzle, Vector3.ZERO)
	return position + Vector3(0, 1.0, 0)


## Where shots aim and land (and the shot camera looks): the animated upper chest of a
## skinned body (or a crawler's thorax), else the middle of the model itself, so a low egg
## sac or spore nest is shot down at and the floating Drifter up at. Never a fixed height.
func aim_point() -> Vector3:
	var p: Variant = _bone_world(["spine_03", "Thorax"])
	if p != null:
		return p
	var bob := _prop.position.y - _prop_y if _prop != null else 0.0
	return _to_world(_rig, _aim_local + Vector3(0, bob, 0))


func head_world() -> Vector3:
	var p: Variant = _bone_world(["Head"])
	return (p as Vector3) + Vector3(0, 0.12, 0) if p != null else position + Vector3(0, 1.5, 0)


## World position of the first of `bones` this unit's skeleton has, or null.
func _bone_world(bones: Array) -> Variant:
	if _skin == null:
		return null
	for b in bones:
		if _skin.skel.find_bone(b) >= 0:
			return _to_world(_skin.skel, _skin.bone_pose(b).origin)
	return null


## World position of a point in `node`'s local space, computed from the transform
## chain so it works out of the tree (tests) too.
func _to_world(node: Node3D, local: Vector3) -> Vector3:
	var p := local
	var n: Node = node
	while n != null and n != self:
		p = (n as Node3D).transform * p
		n = n.get_parent()
	return transform * p


## Advances procedural animation and fades; called by the event player's clock.
func tick(delta: float) -> void:
	_time += delta
	if _yaw != _yaw_target and not dead:
		_yaw = rotate_toward(_yaw, _yaw_target, delta * TURN_SPEED)
		_body.rotation.y = _yaw
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		_apply_flash()
	_walk = move_toward(_walk, 1.0 if _moving else 0.0, delta * 6.0)
	if _walk > 0.0:
		var before := sin(_stride)
		_stride += delta * (13.0 if kind == "runner" else 11.0)
		if signf(sin(_stride)) != signf(before) and _moving:
			stepped.emit()
	_aim = move_toward(_aim, maxf(_aim_target, 0.55 if overwatch else 0.0), delta * 5.0)
	_recoil = move_toward(_recoil, 0.0, delta * 7.0)
	_hit = move_toward(_hit, 0.0, delta * 3.5)
	_crouch = move_toward(_crouch, 1.0 if hunkered else 0.0, delta * 4.0)
	if _sac != null:
		var s := 1.0 + sin(_time * 3.0) * 0.06 + _aim * 0.12 - _recoil * 0.2
		_sac.scale = Vector3(s, s * 0.95, s)
	if _glow != null and _glow.visible and not soldier_body:
		_glow.light_energy = _enemy_glow() * (0.8 + 0.2 * sin(_time * 4.0 + unit_id))
	_fit_ground(delta)
	if _skin != null:
		_animate_skinned(delta)
	elif _prop != null:
		var b := 1.0 + sin(_time * 1.6 + unit_id) * 0.035 + _aim * 0.08 - _recoil * 0.12 + _hit * 0.1
		_prop.scale = Vector3(b, 2.0 - b, b)
		if kind == "drifter":
			_prop.position.y = _prop_y + sin(_time * 1.1 + unit_id) * 0.08


## Skinned characters: pick the looping clip from the animation state; knockback and
## lunge still shove the whole body.
func _animate_skinned(delta: float) -> void:
	if dead:
		return
	var pose := "idle"
	if _walk > 0.5:
		pose = "walk"
	elif _crouch > 0.5:
		pose = "crouch"
	elif _aim > 0.4:
		pose = "aim"
	elif guard:
		pose = "guard"
	if _skin.melee != "" and (_aim > 0.3) != _drawn:
		_drawn = _aim > 0.3   # sidearm out to shoot, the melee weapon back in hand after
		MeleeKit.set_drawn(_model, _drawn)
	_skin.play_base(pose)
	_pitch = aim_pitch(_aim_world) if _aim_world != Vector3.INF else move_toward(_pitch, 0.0, delta * 3.0)
	_skin.aim_pitch = _pitch
	_skin.advance(delta, _aim, _recoil)
	var local_hit := _body.basis.inverse() * _hit_dir if _hit > 0.0 else Vector3.ZERO
	_rig.position = local_hit * 0.22 * _hit + Vector3(0, 0, 1) * _lunge * 0.35


## Keeps every foot on top of the stairs and rubble ramps it stands over, so bodies don't
## sink into the steps: lifts the body to clear the highest step under its footprint, and
## tilts many-legged bodies (whose legs reach into the next cells) along the slope. Only
## stairs move anything: on flat floors, roofs and ladders the body stays where it is put.
func _fit_ground(delta: float) -> void:
	var g := Board.shown()
	if g == null or _model == null:
		return
	if _feet.is_empty():
		_measure_feet()
	var turn := Basis(Vector3.UP, _body.rotation.y)
	var at: Array[Vector2] = []
	var stairs := {}   # levels of the stairs under the body or any foot
	if Board.stair_dir(cell_at()) != Vector2i.ZERO:
		stairs[g.level(cell_at())] = true
	for f in _feet:
		var w := position + transform.basis * (turn * f)
		var p := Vector2(w.x, w.z)
		at.append(p)
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if Board.stair_dir(c) != Vector2i.ZERO:
			stairs[g.level(c)] = true
	var tilt := Vector2.ZERO
	if _crawler and not stairs.is_empty():
		tilt = _slope(_heights(g, at, stairs))
	var k := 1.0 if _fit_snap else 1.0 - exp(-delta * 14.0)
	_fit_snap = false
	_fit_pitch = lerpf(_fit_pitch, tilt.x, k)
	_fit_roll = lerpf(_fit_roll, tilt.y, k)
	var off := 0.0
	if not stairs.is_empty():
		# tilted, the feet land a little closer in: measure where they really are
		var r := Basis.from_euler(Vector3(_fit_pitch, 0.0, _fit_roll))
		var lean: Array[Vector2] = []
		for f in _feet:
			var w := position + transform.basis * (turn * (r * f))
			lean.append(Vector2(w.x, w.z))
		var hs := _heights(g, lean, stairs)
		off = -INF
		for i in _feet.size():
			if not is_nan(hs[i]):
				off = maxf(off, hs[i] - position.y - scale.y * (r * _feet[i]).y)
		off = 0.0 if off == -INF else off / maxf(scale.y, 0.01)
	var next := lerpf(_fit_off, off, k)
	_body.position.y += next - _fit_off   # on top of any hover the body was given
	_fit_off = next
	_body.rotation.x = _fit_pitch
	_body.rotation.z = _fit_roll


## Surface height under each ground point; NAN for feet over cells the stairs don't join (a
## wall, a drop), which are left hanging. `stairs` holds the levels of the stairs underfoot.
func _heights(g: Grid, at: Array[Vector2], stairs: Dictionary) -> Array:
	var hs: Array = []
	for p in at:
		var c := Vector2i(roundi(p.x), roundi(p.y))
		var lv := g.level(c)
		var ok := Board.stair_dir(c) != Vector2i.ZERO or (g.is_walkable(c) and (stairs.has(lv) or stairs.has(lv - 1)))
		hs.append(Board.surface(p) if ok else NAN)
	return hs


## The cell under the body right now (mid-walk too, unlike `cell`).
func cell_at() -> Vector2i:
	return Vector2i(roundi(position.x), roundi(position.z))


## Pitch and roll (radians, x and y) of the plane through the feet heights `hs` (NAN = skip).
func _slope(hs: Array) -> Vector2:
	var n := 0
	var mean := Vector3.ZERO   # lateral, height, forward
	for i in _feet.size():
		if not is_nan(hs[i]):
			mean += Vector3(_feet[i].x * scale.x, hs[i], _feet[i].z * scale.z)
			n += 1
	if n < 3:
		return Vector2.ZERO
	mean /= n
	var sxx := 0.0
	var sxh := 0.0
	var szz := 0.0
	var szh := 0.0
	for i in _feet.size():
		if not is_nan(hs[i]):
			var x := _feet[i].x * scale.x - mean.x
			var z := _feet[i].z * scale.z - mean.z
			var dh: float = hs[i] - mean.y
			sxx += x * x
			sxh += x * dh
			szz += z * z
			szh += z * dh
	var grade := szh / szz if szz > 0.01 else 0.0   # rise per unit forward
	var side := sxh / sxx if sxx > 0.01 else 0.0
	return Vector2(clampf(-atan(grade), -0.6, 0.6), clampf(atan(side), -0.6, 0.6))


## Foot points in the body's frame: the leg tips of many-legged rigs, else a small stance.
func _measure_feet() -> void:
	if _skin != null:
		for b in _skin.skel.get_bone_count():
			var bone := _skin.skel.get_bone_name(b)
			if bone.contains("Foot"):
				var p := _skin.bone_pose(bone).origin
				var n: Node = _skin.skel
				while n != null and n != _body:
					p = (n as Node3D).transform * p
					n = n.get_parent()
				_feet.append(Vector3(p.x, 0.0, p.z))
	_crawler = _feet.size() >= 6
	if not _crawler:
		_feet.clear()
		var s := MODEL_SCALE * ModelKit.size_of(kind)
		for f in [Vector3(-0.14, 0, 0.17), Vector3(0.14, 0, 0.17), Vector3(-0.14, 0, -0.13), Vector3(0.14, 0, -0.13)]:
			_feet.append(f * s)


func _apply_flash() -> void:
	for m in _mats.values():
		if not (m.get_meta("role") in ModelKit.GLOWING):
			m.set_shader_parameter("flash", _flash * 0.9)
			m.set_shader_parameter("flash_color", _flash_color)


## Death animation progress 0..1: fall away from the killing blow, then sink.
## Infected collapse and dissolve into the ground.
func set_death_progress(t: float) -> void:
	dead = t > 0.0
	_death = t
	if _skin != null:
		_skin.set_death(t)
	elif _model != null:
		_model.scale = Vector3.ONE * MODEL_SCALE * maxf(0.05, 1.0 - t * 0.9)   # props wither
	# the infected (and turned) sink into the ground at the end; fallen soldiers stay
	var sink := maxf(0.0, t - 0.7) / 0.3
	_rig.position.y = -sink * (0.9 if not soldier_body or turned else 0.0)
	if _glow != null:
		_glow.light_energy *= 1.0 - t * 0.5
	for n in [_hp_sprite, _class_label, _status_label, _infection_ring, _select_ring, _target_ring, _guard_ring, _cloak_ring]:
		n.visible = n.visible and t < 0.3
	if t >= 1.0:
		visible = false


func pulse_infection(t: float) -> void:
	_infection_ring.visible = true
	var s := 1.0 + sin(t * PI) * 0.5
	_infection_ring.scale = Vector3(s, 0.3, s)
	if _glow != null:
		_glow.visible = true
		_glow.light_energy = maxf(_glow.light_energy, sin(t * PI) * 2.0)
	# growths of a newly reached tier burst out
	var pop := 1.0 - pow(1.0 - clampf(t * 1.4, 0.0, 1.0), 3.0)
	for n in _popping:
		n.scale = Vector3.ONE * (maxf(0.02, pop * 1.08) if t < 1.0 else 1.0)
	if t >= 1.0:
		_popping.clear()
		_refresh_infection()


func _refresh_all() -> void:
	_refresh_hp()
	_refresh_infection()
	_refresh_status()


func _refresh_hp() -> void:
	var pip_w := 6
	var gap := 2
	var w := maxi(1, max_hp * (pip_w + gap) + gap)
	var img := Image.create(w, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.7))
	var full := Color("8fd16a") if is_soldier else Color("d65a4a")
	if is_soldier and float(hp) / max_hp <= 0.34:
		full = Palette.DANGER
	for i in max_hp:
		var col := full if i < hp else Color(0.25, 0.25, 0.25, 0.9)
		img.fill_rect(Rect2i(gap + i * (pip_w + gap), 2, pip_w, 6), col)
	_hp_sprite.texture = ImageTexture.create_from_image(img)


func _refresh_infection() -> void:
	_infection_ring.scale = Vector3(1, 0.3, 1)
	_infection_ring.visible = is_soldier and infection > 0 and not dead
	var col := Palette.tier_color(tier)
	_infection_mat.emission = col
	_infection_mat.emission_energy_multiplier = 0.6 + tier * 1.4 + infection * 0.01
	if not soldier_body:
		return
	var stage := Infection.Tier.TURNED if turned else tier
	for g in _growths:
		var n: Node3D = g[1]
		var show: bool = stage >= g[0]
		if show and not n.visible and g[0] > _shown_stage and is_inside_tree():
			n.scale = Vector3.ONE * 0.02   # pops in during pulse_infection
			_popping.append(n)
		n.visible = show
	_shown_stage = stage
	var k := 1.0 if turned else clampf(infection / 100.0, 0.0, 1.0)
	_set_veins(k if stage > 0 else 0.0)
	if _mats.has("visor"):
		_mats.visor.set_shader_parameter("emission_color", Palette.player_ui(owner_player).lerp(Palette.TEAL, k))
	if not turned:
		_glow.visible = tier >= 2
		_glow.light_energy = 0.35 * tier


func _refresh_status() -> void:
	var parts: PackedStringArray = []
	if lapsed:
		parts.append("LAPSED")
	if turned:
		parts.append("TURNED")
	if overwatch:
		parts.append("OVERWATCH")
	if guard:
		parts.append("GUARD")
	if hunkered:
		parts.append("HUNKERED")
	for k in ["stunned", "suppressed", "marked", "contained"]:
		if tags.has(k) and not dead:
			parts.append(k.to_upper())
	_status_label.text = " ".join(parts)
	_status_label.modulate = Palette.DANGER if (lapsed or turned) else Palette.AMBER
