extends "res://ui/frame.gd"
## Bottom action bar: the selected soldier, one big icon button per action (hotkey
## keycap top-left, action cost top-right; mutations in teal with their Infection
## cost), and the READY button. A hint line above it explains targeting modes.

signal action_pressed(key: String)
signal ready_pressed

const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const InputController := preload("res://view/input_controller.gd")
const SquadRoster := preload("res://ui/squad_roster.gd")

const BTN := Vector2(86, 96)

var _who: Label
var _name: Label
var _class: Label
var _ap: Control
var _ap_text: Label
var _buttons: HBoxContainer
var _ready: Button
var _ready_label: Label
var _empty: Label
var _soldier_box: VBoxContainer


func _init() -> void:
	super(Vector4(14, 12, 14, 12))


func build() -> void:
	name = "ActionBar"
	var row := Styles.hbox(14)
	add_child(row)
	_soldier_box = Styles.vbox(5)
	_soldier_box.custom_minimum_size = Vector2(150, 0)
	_soldier_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_soldier_box)
	_who = Styles.caps("", 12, Styles.TEXT)
	_soldier_box.add_child(_who)
	_name = Styles.caps("", 21)
	_soldier_box.add_child(_name)
	_class = Styles.label("", 13, Styles.DIM)
	_soldier_box.add_child(_class)
	var ap := Styles.hbox(6)
	_ap = W.Diamonds.new(8.0)
	_ap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ap.add_child(_ap)
	_ap_text = Styles.mono("", 10, Styles.DIM)
	ap.add_child(_ap_text)
	_soldier_box.add_child(ap)
	_empty = Styles.label("Select a soldier (click or Tab)", 15, Styles.DIM)
	_empty.custom_minimum_size = Vector2(150, 0)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_empty)
	var sep := ColorRect.new()
	sep.color = Styles.BORDER_SOFT
	sep.custom_minimum_size = Vector2(1, BTN.y)
	row.add_child(sep)
	_buttons = Styles.hbox(6)
	row.add_child(_buttons)
	_ready = Button.new()
	_ready.focus_mode = Control.FOCUS_NONE
	_ready.custom_minimum_size = Vector2(110, BTN.y)
	_ready.add_theme_stylebox_override("normal", Styles.panel_box(Color(0, 0, 0, 0), Styles.player_color(0)))
	_ready.pressed.connect(func() -> void: ready_pressed.emit())
	var rb := Styles.vbox(6)
	rb.alignment = BoxContainer.ALIGNMENT_CENTER
	rb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ready_label = Styles.caps("Ready", 21)
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rb.add_child(_ready_label)
	var kc := W.keycap("Space")
	kc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rb.add_child(kc)
	_ready.add_child(rb)
	row.add_child(_ready)


func refresh(view: MissionView) -> void:
	var input: InputController = view.input
	var u := input.selected_unit()
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	var can_act := input.can_act()
	_soldier_box.visible = u != null
	_empty.visible = u == null
	if u == null:
		_empty.text = "Select a soldier (click or Tab)" if can_act else "Stand by..."
		for i in 4:
			_buttons.add_child(_placeholder())
	else:
		var pcol := Styles.player_color(u.owner_player)
		_who.text = SquadRoster.owner_name(view, u.owner_player).to_upper()
		_who.add_theme_color_override("font_color", pcol)
		_name.text = u.display_name.to_upper()
		_class.text = "%s  ·  %s" % [UnitData.SOLDIERS.get(u.kind, {}).get("name", u.kind.capitalize()), Weapons.display_name(u.kind)]
		(_ap as W.Diamonds).set_values(2, u.actions_left)
		_ap_text.text = "%d ACTION%s" % [u.actions_left, "" if u.actions_left == 1 else "S"]
		for a in input.actions():
			_buttons.add_child(_button(input, a, can_act))
	# Ready applies to the owner of the selected soldier, else the first local player.
	var p := ready_player(view)
	var is_ready: bool = view.state.ready.get(p, false)
	var pcol2 := Styles.player_color(p)
	_ready.disabled = not can_act or p < 0
	_ready_label.text = "Ready" if not is_ready else "Unready"
	_ready_label.add_theme_color_override("font_color", Styles.HP if is_ready else Styles.TEXT)
	_ready.add_theme_stylebox_override("normal", Styles.panel_box(Color(0, 0, 0, 0), pcol2))
	_ready.add_theme_stylebox_override("hover", Styles.panel_box(Color(pcol2, 0.12), pcol2))
	_ready.add_theme_stylebox_override("disabled", Styles.panel_box(Color(0, 0, 0, 0), Styles.BORDER))


static func ready_player(view: MissionView) -> int:
	var u: Unit = view.input.selected_unit() if view.input != null else null
	if u != null and view.session.is_local(u.owner_player):
		return u.owner_player
	for p in view.state.players:
		if view.session.is_local(p) and not view.state.ready.get(p, false):
			return p
	for p in view.state.players:
		if view.session.is_local(p):
			return p
	return -1


func _placeholder() -> Control:
	var c := Panel.new()
	c.custom_minimum_size = BTN
	c.add_theme_stylebox_override("panel", Styles.panel_box(Color(0, 0, 0, 0.2), Color("1f2620")))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(input: InputController, a: Dictionary, can_act: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = BTN
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not (a.enabled and can_act)
	var active := _is_active(input, a)
	var mutation: bool = a.get("mutation", false)
	var fg := Styles.TEXT
	var label := str(a.label)
	var cost := "1"
	if mutation:
		fg = Styles.TEAL
		label = str(a.get("name", label))
		cost = "+%d" % int(a.get("cost", 0))
		b.add_theme_stylebox_override("normal", Styles.panel_box(Color("0f1b18"), Color("2b7d70")))
		b.add_theme_stylebox_override("hover", Styles.panel_box(Color("13241f"), Styles.TEAL))
		b.add_theme_stylebox_override("disabled", Styles.panel_box(Color("0c1311"), Color("1d3a34")))
	if active:
		fg = Styles.AMBER_DARK
		b.add_theme_stylebox_override("normal", Styles.panel_box(Styles.AMBER, Styles.AMBER))
		b.add_theme_stylebox_override("hover", Styles.panel_box(Styles.AMBER.lightened(0.1), Styles.AMBER))
	if b.disabled:
		fg = Color(fg, 0.35)
	b.tooltip_text = label + ("\n" + str(a.desc) if a.get("key") == "shoot" and a.has("desc") else "")
	var key: String = a.key
	b.pressed.connect(func() -> void: action_pressed.emit(key))
	var col := Styles.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 8
	var ic := W.Icon.new(Icons.for_action(a), fg, 26.0, 1.7)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var l := Styles.caps(_short(label), 13, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.custom_minimum_size = Vector2(BTN.x - 8, 0)
	col.add_child(l)
	b.add_child(col)
	if str(a.get("hotkey", "")) != "":
		var kc := W.keycap(a.hotkey, 9, Styles.AMBER_DARK if active else Color("d6d2c2"),
			Styles.AMBER.darkened(0.1) if active else Color("151a16"), Color("9b7a2c") if active else (Color("2b7d70") if mutation else Color("4d574b")))
		kc.position = Vector2(5, 5)
		b.add_child(kc)
	var c := Styles.mono(cost, 10, fg if (active or mutation) else Styles.DIM)
	c.position = Vector2(BTN.x - 8 - 7 * cost.length(), 5)
	b.add_child(c)
	return b


func _short(label: String) -> String:
	return label.replace("Marksman ", "").replace(" (", "\n(").split("\n")[0]


func _is_active(input: InputController, a: Dictionary) -> bool:
	if a.key == "shoot":
		return input.mode == InputController.Mode.SHOOT
	if input.pending.is_empty():
		return false
	return input.pending.get("ability", input.pending.get("mutation", "")) == a.get("id", "")

