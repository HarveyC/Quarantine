extends PanelContainer
## One player's squad card: soldiers (HP, actions, infection, statuses) and a READY toggle.
## Values come from the unit views (what is currently shown), actions from GameState.

signal unit_clicked(id: int)
signal ready_toggled(player: int, on: bool)

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")
const UnitView := preload("res://view/unit_view.gd")

var player := 0
var _rows: VBoxContainer
var _ready_btn: Button
var _title: Label


func build(p: int) -> void:
	player = p
	name = "PlayerPanel%d" % p
	custom_minimum_size = Vector2(270, 0)
	add_theme_stylebox_override("panel", Styles.panel_box(Styles.BG, Palette.player_ui(p).darkened(0.4)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Styles.label("PLAYER %d" % (p + 1), 18, Palette.player_ui(p))
	box.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	box.add_child(_rows)
	_ready_btn = Button.new()
	_ready_btn.toggle_mode = true
	_ready_btn.focus_mode = Control.FOCUS_NONE
	_ready_btn.custom_minimum_size = Vector2(0, 44)
	_ready_btn.add_theme_font_size_override("font_size", 20)
	_ready_btn.toggled.connect(func(on: bool) -> void: ready_toggled.emit(player, on))
	box.add_child(_ready_btn)


func ready_button() -> Button:
	return _ready_btn


func refresh(view: MissionView, selected_id: int, can_act: bool) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for uv in view.unit_views.values():
		if uv.is_soldier and uv.owner_player == player:
			_rows.add_child(_row(view, uv, uv.unit_id == selected_id))
	var pname: String = view.session.player_names.get(player, "")
	var mine: bool = view.session.is_local(player)
	_title.text = "PLAYER %d%s%s" % [player + 1, "  ·  " + pname if pname != "" else "", "  (you)" if mine and not view.session is LocalSession else ""]
	var is_ready: bool = view.state.ready.get(player, false)
	_ready_btn.set_pressed_no_signal(is_ready)
	_ready_btn.text = "READY - waiting" if is_ready else "READY"
	_ready_btn.disabled = not can_act or not mine
	_ready_btn.add_theme_color_override("font_color", Palette.player_ui(player) if is_ready else Styles.TEXT)


func _row(view: MissionView, uv: UnitView, selected: bool) -> Control:
	var u := view.state.get_unit(uv.unit_id)
	var out_of_play := uv.dead or uv.turned or uv.lapsed
	var row := PanelContainer.new()
	var border := Palette.player_ui(player) if selected else Styles.BORDER
	row.add_theme_stylebox_override("panel", Styles.panel_box(Color(0.16, 0.19, 0.14, 0.95) if selected else Styles.BG_SOFT, border))
	row.mouse_default_cursor_shape = Control.CURSOR_ARROW if out_of_play else Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(e: InputEvent) -> void:
		if not out_of_play and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			unit_clicked.emit(uv.unit_id))
	if out_of_play:
		row.modulate = Color(1, 1, 1, 0.6)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var title := Styles.label("%s  [%s]" % [uv.display_name, Palette.class_letter(uv.kind)], 15, Palette.player_ui(player))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var hp_col := Palette.DANGER if uv.hp * 3 <= uv.max_hp else Styles.TEXT
	top.add_child(Styles.label("HP %d/%d" % [uv.hp, uv.max_hp], 14, hp_col))
	# Actions come from the rules state; during enemy playback it already holds next turn's values.
	var ap: int = u.actions_left if u != null and u.is_alive() and not out_of_play else 0
	var ap_text := "  AP -" if view.player.enemy_phase else "  AP %d" % ap
	top.add_child(Styles.label(ap_text, 14, Palette.AMBER if ap > 0 and not view.player.enemy_phase else Styles.MUTED))
	var inf := HBoxContainer.new()
	inf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inf)
	var bar := Styles.bar(Palette.tier_color(uv.tier))
	bar.value = uv.infection
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inf.add_child(bar)
	inf.add_child(Styles.label(" %s %d" % [Infection.tier_name(uv.tier), uv.infection], 12, Palette.tier_color(uv.tier)))
	var st := _status_text(uv)
	if st != "":
		box.add_child(Styles.label(st, 12, Palette.DANGER if (uv.dead or uv.turned or uv.lapsed) else Palette.AMBER))
	for c in box.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _status_text(uv: UnitView) -> String:
	if uv.dead:
		return "KIA"
	var parts: PackedStringArray = []
	if uv.turned:
		parts.append("TURNED")
	if uv.lapsed:
		parts.append("LAPSED (AI)")
	if uv.overwatch:
		parts.append("Overwatch")
	if uv.hunkered:
		parts.append("Hunkered")
	return "  ".join(parts)
