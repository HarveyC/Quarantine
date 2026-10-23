extends Node3D
## Visual for one unit. Holds its own *displayed* copy of hp / infection / statuses,
## updated only by the event player, so the 3D view and HUD can lag behind the
## rules state while animations play.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

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

var _body: Node3D
var _body_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _veins: Node3D
var _hp_sprite: Sprite3D
var _status_label: Label3D
var _class_label: Label3D
var _infection_ring: MeshInstance3D
var _infection_mat: StandardMaterial3D
var _select_ring: MeshInstance3D
var _target_ring: MeshInstance3D
var _flash := 0.0
var _flash_color := Color.WHITE


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
	_body = Node3D.new()
	add_child(_body)
	if is_soldier:
		_build_soldier()
	else:
		_build_enemy()
	_build_rings()
	_build_labels()
	set_cell(u.pos)
	_refresh_all()


func _capsule(radius: float, height: float, m: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	return mi


func _build_soldier() -> void:
	_body_mat = Palette.mat(Palette.player_body(owner_player), 0.8)
	var torso := _capsule(0.26, 1.15, _body_mat)
	torso.position.y = 0.58
	_body.add_child(torso)
	var helmet := _capsule(0.17, 0.36, Palette.mat(Palette.player_body(owner_player).darkened(0.35), 0.6, 0.3))
	helmet.position.y = 1.2
	_body.add_child(helmet)
	_visor_mat = Palette.emissive(Palette.player_ui(owner_player), 1.6)
	var visor := Palette.box(Vector3(0.24, 0.07, 0.08), _visor_mat)
	visor.position = Vector3(0, 1.22, 0.15)
	_body.add_child(visor)
	var pack := Palette.box(Vector3(0.34, 0.42, 0.16), Palette.mat(Color("2b2e2a"), 0.9))
	pack.position = Vector3(0, 0.75, -0.27)
	_body.add_child(pack)
	var gun := Palette.box(Vector3(0.07, 0.07, 0.55), Palette.mat(Color("1e2124"), 0.4, 0.7))
	gun.position = Vector3(0.24, 0.72, 0.22)
	_body.add_child(gun)
	_veins = _make_veins(0.6)
	_veins.visible = false


func _build_enemy() -> void:
	_body_mat = Palette.mat(Palette.ENEMY_BODY, 0.6, 0.2)
	var torso := _capsule(0.3, 1.0, _body_mat)
	torso.position = Vector3(0, 0.55, 0.05)
	torso.rotation.x = deg_to_rad(18)
	_body.add_child(torso)
	var head := _capsule(0.16, 0.34, _body_mat)
	head.position = Vector3(0, 1.0, 0.25)
	head.rotation.x = deg_to_rad(70)
	_body.add_child(head)
	_visor_mat = Palette.emissive(Palette.TEAL, 4.0)
	for side in [-1.0, 1.0]:
		var eye := Palette.box(Vector3(0.05, 0.04, 0.04), _visor_mat)
		eye.position = Vector3(0.07 * side, 1.04, 0.42)
		_body.add_child(eye)
	_veins = _make_veins(2.5)


## Thin glowing streaks wrapped around the body.
func _make_veins(energy: float) -> Node3D:
	var root := Node3D.new()
	var m := Palette.emissive(Palette.TEAL, energy)
	var rng := RandomNumberGenerator.new()
	rng.seed = unit_id * 7919 + 13
	for i in 6:
		var v := Palette.box(Vector3(0.025, rng.randf_range(0.25, 0.5), 0.025), m)
		var ang := rng.randf() * TAU
		v.position = Vector3(cos(ang) * 0.27, rng.randf_range(0.3, 0.9), sin(ang) * 0.27)
		v.rotation = Vector3(rng.randf_range(-0.6, 0.6), ang, rng.randf_range(-0.6, 0.6))
		root.add_child(v)
	_body.add_child(root)
	return root


func _build_rings() -> void:
	_infection_mat = Palette.emissive(Palette.TEAL, 1.0)
	_infection_ring = Palette.ring(0.34, 0.44, _infection_mat)
	_infection_ring.position.y = 0.03
	_infection_ring.scale.y = 0.3
	add_child(_infection_ring)
	_select_ring = Palette.ring(0.42, 0.48, Palette.overlay(Color(1, 0.95, 0.75, 0.9)))
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
	_hp_sprite.position.y = 1.72
	add_child(_hp_sprite)
	var tag := Palette.class_letter(kind)
	if is_soldier:
		tag += " P%d" % (owner_player + 1)
	var col := Palette.player_ui(owner_player) if is_soldier else Palette.TEAL
	_class_label = Palette.label3d(tag, 44, col)
	_class_label.position.y = 2.08
	add_child(_class_label)
	_status_label = Palette.label3d("", 28, Palette.AMBER)
	_status_label.position.y = 1.5
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
	_body_mat.albedo_color = Palette.player_body(owner_player).lerp(Palette.ENEMY_BODY, 0.75)
	_veins.visible = true
	_visor_mat.emission = Palette.TEAL
	_class_label.modulate = Palette.TEAL
	_refresh_status()


func set_selected(on: bool) -> void:
	_select_ring.visible = on


func set_targeted(on: bool) -> void:
	_target_ring.visible = on


func flash(color: Color) -> void:
	_flash = 1.0
	_flash_color = color
	_apply_flash()


## Fades out the hit flash; called by the event player's clock.
func tick(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		_apply_flash()


func _apply_flash() -> void:
	_body_mat.emission_enabled = _flash > 0.0
	_body_mat.emission = _flash_color
	_body_mat.emission_energy_multiplier = _flash * 3.0


## Death animation progress 0..1: topple and sink.
func set_death_progress(t: float) -> void:
	dead = t > 0.0
	_body.rotation.z = lerpf(0.0, PI * 0.5, minf(t * 1.6, 1.0))
	_body.position.y = lerpf(0.0, -0.7, maxf(0.0, t - 0.5) * 2.0)
	for n in [_hp_sprite, _class_label, _status_label, _infection_ring, _select_ring, _target_ring]:
		n.visible = n.visible and t < 0.3
	if t >= 1.0:
		visible = false


func pulse_infection(t: float) -> void:
	_infection_ring.visible = true
	var s := 1.0 + sin(t * PI) * 0.5
	_infection_ring.scale = Vector3(s, 0.3, s)
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
