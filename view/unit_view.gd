extends Node3D
## Visual for one unit. Holds its own *displayed* copy of hp / infection / statuses,
## updated only by the event player, so the 3D view and HUD can lag behind the
## rules state while animations play.
##
## Models are built from primitives as a small jointed rig (hips, legs with knees,
## torso, head, arms, weapon) and animated procedurally in `tick`: idle breathing,
## walk cycle, aim, recoil, hit reactions, hunker crouch, death fall. `tick` runs on
## the event player's clock, so slow motion in a shot cinematic slows the bodies too.

signal stepped   # a foot landed while walking (for footstep sounds)

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

const ARMOR := Color("2e322c")
const GUNMETAL := Color("1b1d1f")
const STRAP := Color("23251f")
## Weapon per class: barrel length, body size and extras.
const WEAPONS := {
	"trooper": {"len": 0.62, "body": Vector3(0.07, 0.11, 0.38)},
	"marksman": {"len": 0.9, "body": Vector3(0.06, 0.1, 0.42), "scope": true},
	"medic": {"len": 0.46, "body": Vector3(0.07, 0.1, 0.3)},
	"breacher": {"len": 0.58, "body": Vector3(0.09, 0.12, 0.36), "thick": true},
}

var unit_id := 0
var kind := ""
var display_name := ""
var owner_player := -1
var is_soldier := true
var cell := Vector2i.ZERO
var hp := 1
var max_hp := 1
var infection := 0
var tier := 0
var overwatch := false
var hunkered := false
var lapsed := false
var turned := false
var dead := false

var _body: Node3D        # yaw only
var _rig: Node3D         # bob, lean, knockback, lunge
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arm_r: Node3D
var _arm_l: Node3D
var _gun: Node3D
var _muzzle: Node3D
var _sac: MeshInstance3D           # spitter's glowing back sac
var _glow: OmniLight3D
var _body_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _flash_mats: Array[StandardMaterial3D] = []
var _veins: Node3D
var _hp_sprite: Sprite3D
var _status_label: Label3D
var _class_label: Label3D
var _infection_ring: MeshInstance3D
var _infection_mat: StandardMaterial3D
var _select_ring: MeshInstance3D
var _target_ring: MeshInstance3D
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
var _fall_dir := Vector3.BACK


func build(u: Unit) -> void:
	unit_id = u.id
	kind = u.kind
	display_name = u.display_name
	owner_player = u.owner_player
	is_soldier = u.team == Types.Team.PLAYER
	hp = u.hp
	max_hp = u.max_hp
	infection = u.infection
	tier = Infection.tier(u.infection)
	lapsed = u.status.get("lapsed", false)
	name = "Unit%d" % unit_id
	_time = float(unit_id) * 1.37
	_body = Node3D.new()
	add_child(_body)
	_rig = _node(_body)
	if is_soldier:
		_build_soldier()
	else:
		_build_enemy()
	_build_rings()
	_build_labels()
	set_cell(u.pos)
	_refresh_all()
	_pose()


# --- model -------------------------------------------------------------------

func _node(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := Palette.box(size, m)
	b.position = pos
	b.rotation = rot
	parent.add_child(b)
	return b


func _capsule(parent: Node3D, radius: float, height: float, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, m: Material, pos := Vector3.ZERO, squash := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = squash
	parent.add_child(mi)
	return mi


func _flashable(m: StandardMaterial3D) -> StandardMaterial3D:
	_flash_mats.append(m)
	return m


func _legs_for(hip_y: float, thigh: float, shin: float, width: float, m: Material, boot: Material) -> void:
	_hips = _node(_rig, Vector3(0, hip_y, 0))
	for side in [-1.0, 1.0]:
		var leg := _node(_hips, Vector3(0.11 * side, 0, 0))
		_box(leg, Vector3(width, thigh, width + 0.02), m, Vector3(0, -thigh * 0.5, 0))
		var knee := _node(leg, Vector3(0, -thigh, 0))
		_box(knee, Vector3(width - 0.01, shin, width), m, Vector3(0, -shin * 0.5, 0))
		_box(knee, Vector3(width + 0.02, 0.09, width + 0.12), boot, Vector3(0, -shin + 0.04, 0.04))
		_legs.append(leg)
		_knees.append(knee)


func _build_soldier() -> void:
	var cloth := Palette.player_body(owner_player)
	_body_mat = _flashable(Palette.mat(cloth, 0.9))
	var armor := _flashable(Palette.mat(ARMOR.lerp(cloth, 0.25), 0.7, 0.15))
	var dark := _flashable(Palette.mat(STRAP, 0.95))
	var helmet_mat := _flashable(Palette.mat(cloth.darkened(0.3), 0.55, 0.25))
	var gun_mat := Palette.mat(GUNMETAL, 0.35, 0.75)
	var heavy := kind == "breacher"
	_legs_for(0.8, 0.4, 0.4, 0.14, _body_mat, dark)
	_box(_hips, Vector3(0.36, 0.16, 0.22), dark, Vector3(0, 0.02, 0))   # belt
	_torso = _node(_hips, Vector3(0, 0.08, 0))
	_box(_torso, Vector3(0.34, 0.26, 0.2), _body_mat, Vector3(0, 0.12, 0))          # abdomen
	var chest := Vector3(0.46, 0.38, 0.28) if heavy else Vector3(0.42, 0.34, 0.26)
	_box(_torso, chest, armor, Vector3(0, 0.38, 0.01))                             # vest
	_box(_torso, Vector3(0.3, 0.12, 0.05), dark, Vector3(0, 0.3, 0.155))            # pouches
	for side in [-1.0, 1.0]:
		var pad := Vector3(0.16, 0.08, 0.2) if heavy else Vector3(0.13, 0.06, 0.17)
		_box(_torso, pad, armor, Vector3(0.25 * side, 0.55, 0), Vector3(0, 0, -0.35 * side))
	var pack_col := Color("c9c7bc") if kind == "medic" else Color("2b2e2a")
	_box(_torso, Vector3(0.32, 0.38, 0.16), _flashable(Palette.mat(pack_col, 0.9)), Vector3(0, 0.36, -0.22))
	if kind == "medic":
		var red := Palette.mat(Color("b3322a"), 0.8)
		_box(_torso, Vector3(0.14, 0.04, 0.01), red, Vector3(0, 0.4, -0.305))
		_box(_torso, Vector3(0.04, 0.14, 0.01), red, Vector3(0, 0.4, -0.305))
	if kind == "marksman":
		_box(_torso, Vector3(0.5, 0.14, 0.32), _flashable(Palette.mat(cloth.darkened(0.15), 1.0)), Vector3(0, 0.56, -0.02))  # shoulder cloak
	# head
	_head = _node(_torso, Vector3(0, 0.62, 0.0))
	_box(_head, Vector3(0.12, 0.1, 0.12), dark, Vector3(0, -0.04, 0))
	_sphere(_head, 0.14, _flashable(Palette.mat(Color("6e5646"), 0.8)), Vector3(0, 0.08, 0.01), Vector3(0.95, 1.0, 1.0))
	_sphere(_head, 0.165, helmet_mat, Vector3(0, 0.13, -0.01), Vector3(1.0, 0.72, 1.08))
	_visor_mat = Palette.emissive(Palette.player_ui(owner_player), 2.2)
	_box(_head, Vector3(0.22, 0.055, 0.06), _visor_mat, Vector3(0, 0.08, 0.13))
	# weapon held at the right shoulder; idle is low ready, aim brings it level
	var w: Dictionary = WEAPONS.get(kind, WEAPONS.trooper)
	_gun = _node(_torso, Vector3(0.12, 0.42, 0.12))
	_box(_gun, w.body, gun_mat, Vector3(0, 0, 0.08))
	var blen: float = w.len
	var bw := 0.06 if w.get("thick", false) else 0.035
	_box(_gun, Vector3(bw, bw, blen * 0.6), gun_mat, Vector3(0, 0.02, 0.08 + w.body.z * 0.5 + blen * 0.3))
	_box(_gun, Vector3(0.05, 0.14, 0.06), gun_mat, Vector3(0, -0.1, 0.12))       # magazine
	_box(_gun, Vector3(0.05, 0.08, 0.16), gun_mat, Vector3(0, -0.01, -0.14))      # stock
	if w.get("scope", false):
		_box(_gun, Vector3(0.05, 0.05, 0.2), gun_mat, Vector3(0, 0.09, 0.1))
		_box(_gun, Vector3(0.03, 0.03, 0.01), Palette.emissive(Color("ff5533"), 2.0), Vector3(0, 0.09, 0.205))
	_muzzle = _node(_gun, Vector3(0, 0.02, 0.08 + w.body.z * 0.5 + blen * 0.6))
	# arms reach from the shoulders to the weapon
	_arm_r = _node(_torso, Vector3(0.24, 0.5, 0))
	_box(_arm_r, Vector3(0.1, 0.32, 0.1), _body_mat, Vector3(0, -0.15, 0))
	_arm_l = _node(_torso, Vector3(-0.24, 0.5, 0))
	_box(_arm_l, Vector3(0.1, 0.36, 0.1), _body_mat, Vector3(0, -0.17, 0))
	if kind == "medic":
		_box(_arm_l, Vector3(0.11, 0.06, 0.11), Palette.mat(Color("d8d6cc"), 0.9), Vector3(0, -0.05, 0))
	if heavy:
		var shield := _flashable(Palette.mat(Color("3a3e3b"), 0.5, 0.5))
		_box(_arm_l, Vector3(0.04, 0.5, 0.36), shield, Vector3(-0.06, -0.3, 0.12))
		_box(_arm_l, Vector3(0.045, 0.06, 0.2), Palette.mat(Palette.AMBER, 0.6), Vector3(-0.065, -0.14, 0.12))
	_glow = OmniLight3D.new()
	_glow.light_color = Palette.TEAL
	_glow.omni_range = 2.2
	_glow.light_energy = 0.0
	_glow.position = Vector3(0, 1.0, 0)
	_glow.visible = false
	_rig.add_child(_glow)
	_veins = _make_veins(_torso, 1.2, 0.26, Vector2(0.0, 0.6))
	_veins.visible = false


func _build_enemy() -> void:
	var spitter := kind == "spitter"
	_body_mat = _flashable(Palette.mat(Palette.ENEMY_BODY.lightened(0.05), 0.55, 0.15))
	var flesh := _flashable(Palette.mat(Color("2a2422"), 0.4, 0.1))
	var glow := Palette.emissive(Palette.TEAL, 3.5)
	_legs_for(0.62 if not spitter else 0.66, 0.34, 0.34, 0.12 if not spitter else 0.16, _body_mat, flesh)
	_torso = _node(_hips, Vector3(0, 0.04, 0))
	var bulk := 1.25 if spitter else 1.0
	_capsule(_torso, 0.22 * bulk, 0.62, _body_mat, Vector3(0, 0.28, 0.05))
	_capsule(_torso, 0.2 * bulk, 0.4, flesh, Vector3(0, 0.46, 0.12), Vector3(0.5, 0, 0))
	# glowing pustules
	var rng := RandomNumberGenerator.new()
	rng.seed = unit_id * 3571 + 7
	for i in (5 if spitter else 3):
		var a := rng.randf_range(-2.4, 2.4)
		_sphere(_torso, rng.randf_range(0.035, 0.06), glow, Vector3(sin(a) * 0.21 * bulk, rng.randf_range(0.2, 0.55), cos(a) * 0.2 * bulk))
	if spitter:
		var sac_mat := Palette.emissive(Palette.TEAL, 2.2)
		sac_mat.albedo_color = Color(Palette.TEAL_DIM, 1.0)
		_sac = _sphere(_torso, 0.26, sac_mat, Vector3(0, 0.58, -0.22), Vector3(1.0, 0.85, 1.0))
	_head = _node(_torso, Vector3(0, 0.62, 0.2))
	_sphere(_head, 0.14, flesh, Vector3(0, 0.0, 0.05), Vector3(0.9, 0.85, 1.25))
	_visor_mat = Palette.emissive(Palette.TEAL, 5.0)
	for side in [-1.0, 1.0]:
		_box(_head, Vector3(0.05, 0.03, 0.03), _visor_mat, Vector3(0.06 * side, 0.03, 0.2))
	if spitter:
		_box(_head, Vector3(0.1, 0.05, 0.05), glow, Vector3(0, -0.06, 0.2))
	# long arms with claws
	_arm_r = _node(_torso, Vector3(0.24 * bulk, 0.5, 0.1))
	_arm_l = _node(_torso, Vector3(-0.24 * bulk, 0.5, 0.1))
	for arm in [_arm_r, _arm_l]:
		_box(arm, Vector3(0.08, 0.55, 0.08), _body_mat, Vector3(0, -0.26, 0))
		for k in 3:
			_box(arm, Vector3(0.02, 0.16, 0.02), Palette.mat(Color("8f8a78"), 0.4, 0.3), Vector3((k - 1) * 0.03, -0.6, 0.04), Vector3(0.5, 0, 0))
	_gun = _node(_head, Vector3.ZERO)
	_muzzle = _node(_head, Vector3(0, -0.04, 0.25))
	_glow = OmniLight3D.new()
	_glow.light_color = Palette.TEAL
	_glow.omni_range = 2.6 if spitter else 2.0
	_glow.light_energy = 1.1 if spitter else 0.7
	_glow.position = Vector3(0, 0.9, 0)
	_glow.shadow_enabled = false
	_rig.add_child(_glow)
	_veins = _make_veins(_torso, 3.0, 0.22 * bulk, Vector2(0.05, 0.55))


## Thin glowing streaks wrapped around the torso.
func _make_veins(parent: Node3D, energy: float, radius: float, span: Vector2) -> Node3D:
	var root := Node3D.new()
	var m := Palette.emissive(Palette.TEAL, energy)
	var rng := RandomNumberGenerator.new()
	rng.seed = unit_id * 7919 + 13
	for i in 8:
		var ang := rng.randf() * TAU
		var v := Palette.box(Vector3(0.02, rng.randf_range(0.15, 0.32), 0.02), m)
		v.position = Vector3(sin(ang) * radius, rng.randf_range(span.x, span.y), cos(ang) * radius)
		v.rotation = Vector3(rng.randf_range(-0.7, 0.7), ang, rng.randf_range(-0.7, 0.7))
		root.add_child(v)
	parent.add_child(root)
	return root


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


func _build_labels() -> void:
	_hp_sprite = Sprite3D.new()
	_hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_sprite.no_depth_test = true
	_hp_sprite.pixel_size = 0.012
	_hp_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_hp_sprite.position.y = 1.95
	add_child(_hp_sprite)
	var tag := Palette.class_letter(kind)
	if is_soldier:
		tag += " P%d" % (owner_player + 1)
	var col := Palette.player_ui(owner_player) if is_soldier else Palette.TEAL
	_class_label = Palette.label3d(tag, 44, col)
	_class_label.position.y = 2.3
	add_child(_class_label)
	_status_label = Palette.label3d("", 28, Palette.AMBER)
	_status_label.position.y = 1.75
	add_child(_status_label)


# --- display state ----------------------------------------------------------

func label() -> String:
	if is_soldier and owner_player >= 0:
		return "%s (P%d)" % [display_name, owner_player + 1]
	return display_name


func set_cell(c: Vector2i) -> void:
	cell = c
	position = Board.cell_to_world(c)


func face_towards(world: Vector3) -> void:
	var d := world - position
	if Vector2(d.x, d.z).length() > 0.01:
		_body.rotation.y = atan2(d.x, d.z)


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


func set_lapsed(on: bool) -> void:
	lapsed = on
	_refresh_status()


func set_turned() -> void:
	turned = true
	lapsed = false
	var dead_col := Palette.player_body(owner_player).lerp(Palette.ENEMY_BODY, 0.75)
	_body_mat.albedo_color = dead_col
	_veins.visible = true
	_visor_mat.emission = Palette.TEAL
	_class_label.modulate = Palette.TEAL
	_glow.visible = true
	_glow.light_energy = 1.0
	_refresh_status()


func set_selected(on: bool) -> void:
	_select_ring.visible = on


func set_targeted(on: bool) -> void:
	_target_ring.visible = on


## Hides the floating HP / labels / rings, e.g. during a shot cinematic.
func set_overlays_visible(on: bool) -> void:
	_overlays_on = on
	for n in [_hp_sprite, _class_label, _status_label]:
		n.visible = on and not dead
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


func aim_now(k: float) -> void:
	_aim = k
	_aim_target = k


func recoil(strength := 1.0) -> void:
	_recoil = strength


## Knock the body away from `from_world`.
func hit_react(from_world: Vector3, strength := 1.0) -> void:
	var d := position - from_world
	d.y = 0.0
	_hit_dir = d.normalized() if d.length() > 0.01 else -facing()
	_fall_dir = _hit_dir
	_hit = strength


## Melee lunge 0..1 (forward strike).
func set_lunge(k: float) -> void:
	_lunge = k


func muzzle_world() -> Vector3:
	return _to_world(_muzzle, Vector3.ZERO)


func chest_world() -> Vector3:
	return position + Vector3(0, 1.05 if is_soldier else 0.85, 0)


func head_world() -> Vector3:
	return position + Vector3(0, 1.5, 0)


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
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		_apply_flash()
	_walk = move_toward(_walk, 1.0 if _moving else 0.0, delta * 6.0)
	if _walk > 0.0:
		var before := sin(_stride)
		_stride += delta * 11.0
		if signf(sin(_stride)) != signf(before) and _moving:
			stepped.emit()
	_aim = move_toward(_aim, maxf(_aim_target, 0.55 if overwatch else 0.0), delta * 5.0)
	_recoil = move_toward(_recoil, 0.0, delta * 7.0)
	_hit = move_toward(_hit, 0.0, delta * 3.5)
	_crouch = move_toward(_crouch, 1.0 if hunkered else 0.0, delta * 4.0)
	if _sac != null:
		var s := 1.0 + sin(_time * 3.0) * 0.06
		_sac.scale = Vector3(s, 0.85 * s, s)
	if _glow != null and _glow.visible and not is_soldier:
		_glow.light_energy = (1.1 if kind == "spitter" else 0.7) * (0.8 + 0.2 * sin(_time * 4.0 + unit_id))
	_pose()


func _pose() -> void:
	if _hips == null or _death > 0.0:
		return
	var breathe := sin(_time * 2.1)
	var sw := sin(_stride) * _walk
	var bob := absf(cos(_stride)) * 0.05 * _walk
	var enemy_twitch := 0.0 if is_soldier else sin(_time * 13.0) * sin(_time * 2.3) * 0.08
	# legs: stride swing, knee bend on the back swing, crouch when hunkered
	for i in 2:
		var s := sw if i == 0 else -sw
		_legs[i].rotation.x = s * 0.6 - _crouch * 0.9
		_knees[i].rotation.x = maxf(0.0, -s) * 0.9 + _crouch * 1.6
	var hip_drop := _crouch * 0.28
	_hips.position.y = (0.8 if is_soldier else 0.64) - hip_drop + bob
	# rig: knockback, lunge, idle sway
	var fwd := Vector3(0, 0, 1)
	var local_hit := _body.basis.inverse() * _hit_dir if _hit > 0.0 else Vector3.ZERO
	_rig.position = local_hit * 0.22 * _hit + fwd * _lunge * 0.55
	_rig.rotation.z = sin(_time * 0.8) * 0.015
	# torso: lean into walk / lunge, recoil kick, hit twist, breathing
	var lean := 0.18 * _walk + 0.5 * _lunge + _crouch * 0.35 - _recoil * 0.12
	if not is_soldier:
		lean += 0.45 + enemy_twitch
	_torso.rotation.x = lean - local_hit.z * 0.4 * _hit
	_torso.rotation.z = local_hit.x * 0.4 * _hit
	_torso.position.y = 0.08 + breathe * 0.008
	_head.rotation.x = -lean * 0.6 + (sin(_time * 0.7) * 0.05 if is_soldier else enemy_twitch * 2.0)
	_head.rotation.y = sin(_time * 0.45 + unit_id) * (0.25 if is_soldier else 0.4) * (1.0 - _aim)
	if is_soldier:
		# weapon from low ready (pointing down-forward) to shouldered
		var a := _aim
		_gun.position = Vector3(0.12 - 0.02 * a, 0.38 + 0.08 * a, 0.14 - _recoil * 0.07)
		_gun.rotation.x = lerpf(0.75, -lean, a) - _recoil * 0.25
		_gun.rotation.y = lerpf(-0.35, 0.0, a)
		_arm_r.rotation.x = lerpf(-0.5, -1.25, a) - sw * 0.15
		_arm_l.rotation.x = lerpf(-0.9, -1.45, a) + sw * 0.15
		_arm_l.rotation.y = lerpf(0.5, 0.75, a)
		_arm_r.rotation.z = 0.15
	else:
		# claws swing while walking, raise on lunge
		_arm_r.rotation.x = -0.3 + sw * 0.7 - _lunge * 1.6 + enemy_twitch
		_arm_l.rotation.x = -0.3 - sw * 0.7 - _lunge * 1.2 - enemy_twitch
		_arm_r.rotation.z = 0.25
		_arm_l.rotation.z = -0.25


func _apply_flash() -> void:
	for m in _flash_mats:
		m.emission_enabled = _flash > 0.0
		m.emission = _flash_color
		m.emission_energy_multiplier = _flash * 2.5


## Death animation progress 0..1: fall away from the killing blow, then sink.
## Infected collapse and dissolve into the ground.
func set_death_progress(t: float) -> void:
	dead = t > 0.0
	_death = t
	var fall := minf(t * 1.7, 1.0)
	fall = 1.0 - pow(1.0 - fall, 3.0)
	var local_dir := _body.basis.inverse() * _fall_dir
	# tip over around the axis perpendicular to the fall direction
	var axis := Vector3(local_dir.z, 0, -local_dir.x).normalized()
	if axis.length() < 0.5:
		axis = Vector3.RIGHT
	_rig.basis = Basis(axis, fall * PI * 0.48)
	_rig.position = local_dir * fall * 0.35 + Vector3(0, lerpf(0.0, -0.9, maxf(0.0, t - 0.55) / 0.45), 0)
	if _knees.size() == 2:
		_knees[0].rotation.x = fall * 1.2
		_knees[1].rotation.x = fall * 0.4
	if _glow != null:
		_glow.light_energy *= 1.0 - t * 0.5
	for n in [_hp_sprite, _class_label, _status_label, _infection_ring, _select_ring, _target_ring]:
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
	if t >= 1.0:
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
	if is_soldier and not turned:
		_veins.visible = tier >= 2
		_glow.visible = tier >= 2
		_glow.light_energy = 0.3 * tier
		_visor_mat.emission = Palette.player_ui(owner_player).lerp(Palette.TEAL, clampf(infection / 100.0, 0.0, 1.0))


func _refresh_status() -> void:
	var parts: PackedStringArray = []
	if lapsed:
		parts.append("LAPSED")
	if turned:
		parts.append("TURNED")
	if overwatch:
		parts.append("OVERWATCH")
	if hunkered:
		parts.append("HUNKERED")
	_status_label.text = " ".join(parts)
	_status_label.modulate = Palette.DANGER if (lapsed or turned) else Palette.AMBER
