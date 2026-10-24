extends Control
## Bottom-centre action wheel: the selected soldier's portrait (Infection as a teal ring, the
## lantern glow because it's the one you're acting with) with its name, HP and action orbs, and
## one round button per action fanned in an arc above it (hotkey cap top left; mutations in
## teal with their Infection cost; the action being aimed glows amber). The READY pill sits to
## the right. Hint text for targeting modes lives in the HUD above it.

signal action_pressed(key: String)
signal ready_pressed

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const InputController := preload("res://view/input_controller.gd")
const SquadRoster := preload("res://ui/squad_roster.gd")

const SIZE := Vector2(980, 300)
## Centre of the portrait and of the arc.
const HUB := Vector2(490, 236)
const PORTRAIT := 112.0
const ARC_R := 204.0
const BTN := 70.0

var _portrait: W.Portrait
var _who: Label
var _name: Label
var _class: Label
var _ap: W.Diamonds
var _hp: W.Pips
var _empty: Label
var _soldier_box: VBoxContainer
var _buttons: Control
var _ready: Button
var _ready_label: Label
var _arc_span := Vector2(PI * 1.06, PI * 1.94)


func build() -> void:
	name = "ActionBar"
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait = W.Portrait.new(PORTRAIT)
	_portrait.position = HUB - Vector2(PORTRAIT, PORTRAIT) * 0.5
	add_child(_portrait)
	_soldier_box = Styles.vbox(3)
	_soldier_box.alignment = BoxContainer.ALIGNMENT_END
	_soldier_box.position = Vector2(HUB.x - 130, HUB.y - PORTRAIT * 0.5 - 96)
	_soldier_box.size = Vector2(260, 88)
	add_child(_soldier_box)
	var orbs := Styles.hbox(8)
	orbs.alignment = BoxContainer.ALIGNMENT_CENTER
	_ap = W.Diamonds.new(10.0)
	_ap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orbs.add_child(_ap)
	_soldier_box.add_child(orbs)
	var nm := Styles.hbox(8)
	nm.alignment = BoxContainer.ALIGNMENT_CENTER
	_name = Styles.display("", 17, Styles.TEXT, true, false)
	nm.add_child(_name)
	_who = Styles.caps("", 11, Styles.TEXT)
	_who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_child(_who)
	_soldier_box.add_child(nm)
	_class = Styles.label("", 13, Styles.DIM)
	_class.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_soldier_box.add_child(_class)
	var hp := Styles.hbox(0)
	hp.alignment = BoxContainer.ALIGNMENT_CENTER
	_hp = W.Pips.new(Vector2(12, 5))
	hp.add_child(_hp)
	_soldier_box.add_child(hp)
	_empty = Styles.label("Select a soldier\n(click or Tab)", 14, Styles.DIM)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.position = HUB - Vector2(70, 24)
	_empty.size = Vector2(140, 48)
	add_child(_empty)
	_buttons = Control.new()
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_buttons)
	_ready = Button.new()
	_ready.focus_mode = Control.FOCUS_NONE
	_ready.size = Vector2(180, 62)
	_ready.position = Vector2(SIZE.x - _ready.size.x, HUB.y - 64)
	_ready.pressed.connect(func() -> void: ready_pressed.emit())
	var rb := Styles.hbox(10)
	rb.alignment = BoxContainer.ALIGNMENT_CENTER
	rb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ready_label = Styles.display("Ready", 17, Styles.TEXT, true, false)
	rb.add_child(_ready_label)
	var kc := W.keycap("Space", 10)
	kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rb.add_child(kc)
	_ready.add_child(rb)
	add_child(_ready)


func _draw() -> void:
	# The wheel's faint guide arc.
	draw_arc(HUB, ARC_R, _arc_span.x - 0.12, _arc_span.y + 0.12, 64, Color(Styles.DIM, 0.12), 2.0, true)
	draw_arc(HUB, ARC_R - BTN * 0.5 - 8, _arc_span.x, _arc_span.y, 64, Color(Styles.DIM, 0.05), 1.0, true)


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
		_empty.text = "Select a soldier\n(click or Tab)" if can_act else "Stand by..."
		_portrait.setup("", Styles.BORDER_STRONG, 0, false, true)
		_portrait.modulate.a = 0.5
		_place([null, null, null, null], input, can_act)
	else:
		var pcol := Styles.player_color(u.owner_player)
		_portrait.modulate.a = 1.0
		_portrait.setup(u.kind, pcol, u.infection, can_act and view.session.is_local(u.owner_player))
		_who.text = SquadRoster.owner_name(view, u.owner_player)
		_who.add_theme_color_override("font_color", pcol)
		_name.text = u.display_name
		_class.text = "%s  ·  %s" % [UnitData.SOLDIERS.get(u.kind, {}).get("name", u.kind.capitalize()), Weapons.of(u).name]
		_ap.set_values(2, u.actions_left)
		_hp.set_values(u.max_hp, u.hp, 0, Styles.DANGER if u.hp * 3 <= u.max_hp else Styles.HP)
		_place(input.actions(), input, can_act)
	# Ready applies to the owner of the selected soldier, else the first local player.
	var p := ready_player(view)
	var is_ready: bool = view.state.ready.get(p, false)
	var pcol2 := Styles.player_color(p)
	_ready.disabled = not can_act or p < 0
	_ready_label.text = "Ready" if not is_ready else "Unready"
	_ready_label.add_theme_color_override("font_color", Styles.HP if is_ready else Styles.TEXT)
	_ready.add_theme_stylebox_override("normal", Styles.glow_box(Color(0.04, 0.055, 0.09, 0.88), pcol2, Color(pcol2, 0.22), 12, Styles.PILL))
	_ready.add_theme_stylebox_override("hover", Styles.glow_box(Color(pcol2, 0.14), pcol2, Color(pcol2, 0.4), 16, Styles.PILL))
	_ready.add_theme_stylebox_override("pressed", Styles.glow_box(Color(pcol2, 0.22), pcol2, Color(pcol2, 0.4), 16, Styles.PILL))
	_ready.add_theme_stylebox_override("disabled", Styles.panel_box(Color(0.04, 0.055, 0.09, 0.6), Styles.BORDER, Styles.PILL))
	_ready.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	queue_redraw()


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


## Fans the buttons along the arc, evenly from left to right.
func _place(actions: Array, input: InputController, can_act: bool) -> void:
	var n := actions.size()
	var spread := clampf(0.19 * (n - 1), 0.0, 0.86)
	var mid := PI * 1.5
	_arc_span = Vector2(mid - PI * spread * 0.5, mid + PI * spread * 0.5) if n > 1 else Vector2(mid - 0.3, mid + 0.3)
	var px := BTN if n <= 6 else BTN - 8.0
	var r := ARC_R if n <= 6 else ARC_R + 8.0
	for i in n:
		var a := mid if n == 1 else _arc_span.x + (_arc_span.y - _arc_span.x) * i / float(n - 1)
		var at := HUB + Vector2(cos(a), sin(a)) * r
		var b: Control = _placeholder(px) if actions[i] == null else _button(input, actions[i], can_act, px)
		b.position = at - Vector2(px, px) * 0.5
		_buttons.add_child(b)


func _placeholder(px: float) -> Control:
	var c := Panel.new()
	c.size = Vector2(px, px)
	c.add_theme_stylebox_override("panel", Styles.panel_box(Color(0.04, 0.055, 0.09, 0.35), Styles.BORDER_SOFT, Styles.PILL))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(input: InputController, a: Dictionary, can_act: bool, px: float) -> Button:
	var b := Button.new()
	b.size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not (a.enabled and can_act)
	var active := _is_active(input, a)
	var mutation: bool = a.get("mutation", false)
	var fg := Styles.TEXT
	var label := str(a.label)
	var cost := ""
	var line := Styles.BORDER_STRONG
	var fill := Color(0.04, 0.055, 0.09, 0.9)
	var glow := Color(0, 0, 0, 0.35)
	if mutation:
		fg = Styles.TEAL
		label = str(a.get("name", label))
		cost = "+%d" % int(a.get("cost", 0))
		line = Color(Styles.TEAL, 0.75)
		fill = Color(0.03, 0.13, 0.13, 0.92)
		glow = Color(Styles.TEAL, 0.3)
	var box := Styles.glow_box(fill, line, glow, 10, Styles.PILL)
	box.set_border_width_all(2 if mutation else 1)
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", Styles.glow_box(fill.lightened(0.05), Styles.AMBER if not mutation else Styles.TEAL, Color(Styles.AMBER if not mutation else Styles.TEAL, 0.4), 14, Styles.PILL))
	b.add_theme_stylebox_override("pressed", Styles.glow_box(Color(Styles.AMBER, 0.25), Styles.AMBER, Color(Styles.AMBER, 0.5), 14, Styles.PILL))
	b.add_theme_stylebox_override("disabled", Styles.panel_box(Color(0.04, 0.055, 0.09, 0.55), Styles.BORDER_SOFT, Styles.PILL))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if active:
		fg = Styles.AMBER_DARK
		var on := Styles.glow_box(Styles.AMBER, Styles.AMBER_LIGHT, Color(Styles.AMBER, 0.6), 20, Styles.PILL)
		b.add_theme_stylebox_override("normal", on)
		b.add_theme_stylebox_override("hover", on)
	if b.disabled:
		fg = Color(fg, 0.35)
	b.tooltip_text = label + ("\n" + str(a.desc) if a.get("key") == "shoot" and a.has("desc") else "")
	var key: String = a.key
	b.pressed.connect(func() -> void: action_pressed.emit(key))
	var ip := px * 0.42
	var ic := W.Icon.new(Icons.for_action(a), fg, ip, 2.0)
	ic.position = (Vector2(px, px) - Vector2(ip, ip)) * 0.5
	b.add_child(ic)
	# The name sits under the button, outside the circle, so long names never clip.
	var l := Styles.bold(_short(label), 12, fg if not active else Styles.AMBER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(130, 18)
	l.position = Vector2((px - 130) * 0.5, px + 3)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(Styles.GROUND, 0.85))
	b.add_child(l)
	if str(a.get("hotkey", "")) != "":
		var kc := W.keycap(a.hotkey, 9, Styles.AMBER_DARK if active else Styles.TEXT,
			Styles.AMBER_LIGHT if active else Color("141c2a"), Styles.AMBER_DEEP if active else (Color(Styles.TEAL, 0.6) if mutation else Styles.BORDER_STRONG))
		kc.position = Vector2(-4, -2)
		b.add_child(kc)
	if cost != "":
		var c := W.chip(cost, Styles.TEAL, true, 10)
		c.position = Vector2(px - 26, -4)
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
