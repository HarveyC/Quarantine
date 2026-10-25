extends Control
## Small plates that follow units on screen, replacing the floating "M P1" letters:
## class icon in the owner's colour, actions left and HP pips for soldiers; HP and
## name for enemies. The current shot target also gets its hit chance next to it.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const UnitView := preload("res://view/unit_view.gd")
const InputController := preload("res://view/input_controller.gd")

const HEAD := Vector3(0, 2.0, 0)
const HEAD_ENEMY := Vector3(0, 1.6, 0)   # infected models are shorter
## Timed tags from gear and abilities (UnitView.tags): icon and colour on the plate.
const TAG_ICONS := {"stunned": ["stun", Color("9fd0ff")], "suppressed": ["suppress", Styles.AMBER],
	"marked": ["tag", Styles.DANGER], "contained": ["cure", Styles.TEAL], "restrained": ["lock", Color("e4ece9")]}

var view: MissionView
var _plates: Dictionary = {}   # unit id -> Control
var _odds: Control
var _odds_hit: Label
var _odds_sub: Label
var _odds_for := -1


func build(v: MissionView) -> void:
	view = v
	name = "Nameplates"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_odds = Styles.hbox(8)
	_odds_hit = Styles.mono("", 34, Styles.AMBER)
	_odds_hit.add_theme_constant_override("outline_size", 6)
	_odds_hit.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_odds.add_child(_odds_hit)
	_odds_sub = Styles.caps("", 13, Styles.DANGER_TEXT)
	_odds_sub.add_theme_constant_override("outline_size", 4)
	_odds_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_odds.add_child(_odds_sub)
	_odds.visible = false
	add_child(_odds)


func refresh() -> void:
	for c in _plates.values():
		remove_child(c)
		c.queue_free()
	_plates.clear()
	var sel := view.input.selected_id if view.input != null else -1
	var target: Unit = null
	var shooter: Unit = null
	if view.input != null and view.input.mode == InputController.Mode.SHOOT:
		target = view.input.current_target()
		shooter = view.input.selected_unit()
	for uv in view.unit_views.values():
		if uv.dead or not uv.visible or uv.get_meta("ghost", false):
			continue
		var plate := _plate(uv, uv.unit_id == sel, target != null and target.id == uv.unit_id, shooter)
		add_child(plate)
		_plates[uv.unit_id] = plate
	_odds_for = -1
	_odds.visible = false
	if target != null and shooter != null:
		var odds := Combat.hit_chance(view.state, shooter, target)
		_odds_hit.text = "%d%%" % int(odds.get("hit", 0))
		_odds_sub.text = "FLANKED" if odds.get("flanked", false) else ""
		_odds_for = target.id
		move_child(_odds, get_child_count() - 1)
	_layout()


func _plate(uv: UnitView, selected: bool, targeted: bool, shooter: Unit) -> Control:
	var f := W.Frame.new(Vector4(6, 3, 7, 3))
	var col := Styles.player_color(uv.owner_player) if uv.is_soldier else Styles.DANGER
	var line := col.darkened(0.45)
	if selected or targeted:
		line = Styles.AMBER if targeted else col
	f.set_look(Color(0.034, 0.05, 0.08, 0.86), line, Styles.AMBER, false)
	var row := Styles.hbox(5)
	f.add_child(row)
	var ic := W.Icon.new(Icons.for_class(uv.kind) if uv.is_soldier else "enemy", col, 15.0, 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	if uv.is_soldier:
		var u := view.state.get_unit(uv.unit_id)
		if u != null and not uv.turned and not uv.lapsed and not view.player.enemy_phase:
			var d := W.Diamonds.new(6.0)
			d.set_values(2, u.actions_left)
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(d)
		if u != null and u.status.has("pinned_by") and not uv.dead:
			row.add_child(W.Icon.new("pinned", Styles.DANGER, 14.0, 2.0))
		if uv.overwatch:
			row.add_child(W.Icon.new("overwatch", Styles.AMBER, 14.0, 2.0))
		if uv.hunkered:
			row.add_child(W.Icon.new("hunker", Styles.AMBER, 14.0, 2.0))
		if uv.concealed and not uv.turned:
			row.add_child(W.Icon.new("concealed", Styles.STEALTH, 14.0, 2.0))
	else:
		row.add_child(Styles.caps(uv.display_name, 11, Styles.DANGER_TEXT))
		# While the squad is Concealed, the ones still watching wear an open eye.
		var e := view.state.get_unit(uv.unit_id)
		if view.player != null and view.player.concealed and e != null and not EnemyAI.is_alerted(e) \
				and not EnemyRoster.is_static(e):
			row.add_child(W.Icon.new("detected", Styles.DANGER, 14.0, 2.0))
	for k in TAG_ICONS:
		if uv.tags.has(k):
			row.add_child(W.Icon.new(TAG_ICONS[k][0], TAG_ICONS[k][1], 14.0, 2.0))
	var hp := W.Pips.new(Vector2(7, 4))
	var lose := 0
	if targeted and shooter != null:
		lose = mini(shooter.damage.y, uv.hp)
	hp.set_values(uv.max_hp, uv.hp, lose, Styles.HP if uv.is_soldier else Styles.DANGER)
	hp.gap = 2.0
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hp)
	if uv.is_soldier and uv.tier >= 2:
		var dot := W.Icon.new("dot", Styles.TEAL, 8.0)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
	f.reset_size()
	return f


func _layout() -> void:
	if view == null or view.camera_rig == null or not is_inside_tree():
		return
	var cam := view.camera_rig.camera
	if cam == null or not cam.is_inside_tree():
		return
	for id in _plates:
		var plate: Control = _plates[id]
		var uv := view.view_for(id)
		if uv == null or not uv.is_visible_in_tree() or uv.dead:
			plate.visible = false
			continue
		var p := uv.global_position + (HEAD if uv.is_soldier else HEAD_ENEMY)
		if cam.is_position_behind(p):
			plate.visible = false
			continue
		var sp := cam.unproject_position(p) / get_viewport().get_visible_rect().size * size
		plate.visible = true
		var pos := sp - Vector2(plate.size.x * 0.5, plate.size.y)
		pos.x = clampf(pos.x, 4.0, size.x - plate.size.x - 4.0)
		pos.y = clampf(pos.y, 4.0, size.y - plate.size.y - 4.0)
		plate.position = pos.round()
		if id == _odds_for:
			_odds.visible = true
			_odds.reset_size()
			_odds.position = (sp + Vector2(plate.size.x * 0.5 + 10, -_odds.size.y * 0.5 - plate.size.y * 0.5)).round()


func _process(_delta: float) -> void:
	_layout()
