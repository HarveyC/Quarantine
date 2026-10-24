extends "res://ui/frame.gd"
## The card training lessons and first-time tips use: a small amber kicker (TRAINING 3 / 12,
## or TIP), a caps title, one or two short lines, optional keycaps and a small diagram, and
## its buttons. Kept short on purpose: the arrow and the tile markers do the explaining.

signal pressed(id: String)

const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")

const WIDTH := 430.0

var _kicker: Label
var _title: Label
var _text: Label
var _keys: HBoxContainer
var _terms: HFlowContainer
var _visual: Control
var _buttons: HBoxContainer
var _dots: Control


func _init() -> void:
	super(Vector4(18, 14, 18, 14))
	name = "CoachCard"
	set_look(Color(0.035, 0.05, 0.085, 0.95), Styles.BORDER_STRONG)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Styles.vbox(8)
	add_child(box)
	var head := Styles.hbox(10)
	_kicker = Styles.caps("", 12, Styles.AMBER)
	head.add_child(_kicker)
	head.add_child(Styles.spacer())
	_dots = Dots.new()
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_dots)
	box.add_child(head)
	_title = Styles.caps("", 24)
	box.add_child(_title)
	_text = Styles.label("", 15, Styles.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = WIDTH - 36
	box.add_child(_text)
	_visual = Diagram.new()
	box.add_child(_visual)
	_keys = Styles.hbox(8)
	box.add_child(_keys)
	# Glossary terms named in the text: hover one for its card.
	_terms = HFlowContainer.new()
	_terms.add_theme_constant_override("h_separation", 6)
	_terms.add_theme_constant_override("v_separation", 6)
	_terms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_terms)
	_buttons = Styles.hbox(8)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_buttons)


func set_width(w: float) -> void:
	custom_minimum_size.x = w
	_text.custom_minimum_size.x = w - 36
	_visual.custom_minimum_size.x = w - 36


## `buttons`: Array of [id, label, primary]. `step`/`steps` fill the progress dots (0 = none).
func show_card(kicker: String, title: String, text: String, keys: Array = [], visual := "",
		buttons: Array = [], step := 0, steps := 0) -> void:
	_kicker.text = kicker.to_upper()
	_title.text = title.to_upper()
	_text.text = text
	(_dots as Dots).set_values(step, steps)
	(_visual as Diagram).kind = visual
	_visual.visible = visual != ""
	_visual.queue_redraw()
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	for k in keys:
		_keys.add_child(W.keycap(str(k), 12))
	_keys.visible = not keys.is_empty()
	for c in _terms.get_children():
		_terms.remove_child(c)
		c.queue_free()
	for k in Glossary.scan(title + ". " + text).slice(0, 4):
		_terms.add_child(Tips.chip(k, 11))
	_terms.visible = _terms.get_child_count() > 0
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	for b in buttons:
		_buttons.add_child(_button(str(b[0]), str(b[1]), bool(b[2])))
	_buttons.visible = not buttons.is_empty()
	reset_size()


func _button(id: String, label: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_override("font", Styles.FONT_DISPLAY if primary else Styles.FONT_DISPLAY_MEDIUM)
	b.add_theme_font_size_override("font_size", 12)
	Styles.style_button(b, "primary" if primary else "ghost", 18)
	b.pressed.connect(func() -> void: pressed.emit(id))
	return b


## Lesson progress: one diamond per lesson, done ones filled.
class Dots extends Control:
	var step := 0
	var steps := 0

	func set_values(s: int, n: int) -> void:
		step = s
		steps = n
		custom_minimum_size = Vector2(n * 11, 10)
		visible = n > 0
		queue_redraw()

	func _draw() -> void:
		for i in steps:
			var c := Vector2(i * 11 + 5, 5)
			var pts := PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)])
			if i < step:
				draw_colored_polygon(pts, Styles.AMBER)
			elif i == step:
				draw_colored_polygon(pts, Color(Styles.AMBER, 0.35))
				pts.append(pts[0])
				draw_polyline(pts, Styles.AMBER, 1.2)
			else:
				pts.append(pts[0])
				draw_polyline(pts, Styles.BORDER_STRONG, 1.2)


## Small drawings for the lessons that are about numbers: cover, height and Infection tiers.
class Diagram extends Control:
	var kind := ""

	func _init() -> void:
		custom_minimum_size = Vector2(WIDTH - 36, 74)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		match kind:
			"cover": _cover()
			"height": _height()
			"tiers": _tiers()
			"stealth": _stealth()

	func _text(at: Vector2, t: String, col: Color, sz := 12, mono := false) -> void:
		var f: Font = Styles.FONT_MONO if mono else Styles.FONT_COND_BOLD
		draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

	func _soldier(at: Vector2, col: Color) -> void:
		draw_circle(at + Vector2(0, -22), 5.0, col)
		draw_rect(Rect2(at + Vector2(-5, -16), Vector2(10, 16)), col)

	func _cover() -> void:
		var ground := 58.0
		for i in 2:
			var x := 30.0 + i * 190.0
			var full := i == 1
			draw_line(Vector2(x - 20, ground), Vector2(x + 130, ground), Styles.BORDER_STRONG, 1.0)
			_soldier(Vector2(x + 10, ground), Styles.player_color(0))
			var h := 40.0 if full else 20.0
			draw_rect(Rect2(x + 22, ground - h, 9, h), Styles.DIM)
			# Shield plate like the board shows it.
			draw_rect(Rect2(x + 34, ground - h * 0.9, 3, h * 0.8), Styles.AMBER)
			_text(Vector2(x + 48, ground - 26), "FULL" if full else "HALF", Styles.TEXT, 15)
			_text(Vector2(x + 48, ground - 8), "-%d AIM" % (Combat.COVER_FULL if full else Combat.COVER_HALF), Styles.AMBER, 12, true)

	func _height() -> void:
		var ground := 62.0
		draw_line(Vector2(10, ground), Vector2(WIDTH - 50, ground), Styles.BORDER_STRONG, 1.0)
		draw_rect(Rect2(14, ground - 30, 70, 30), Color("1e2737"))
		draw_line(Vector2(14, ground - 30), Vector2(84, ground - 30), Styles.AMBER, 2.0)
		for i in 4:
			draw_line(Vector2(88, ground - 6 - i * 7), Vector2(96, ground - 6 - i * 7), Styles.DIM, 1.5)
		_soldier(Vector2(52, ground - 30), Styles.player_color(0))
		draw_dashed_line(Vector2(62, ground - 50), Vector2(176, ground - 22), Styles.AMBER, 1.5, 6.0)
		draw_rect(Rect2(170, ground - 14, 8, 14), Styles.DIM)
		draw_circle(Vector2(186, ground - 20), 5.0, Styles.DANGER)
		draw_rect(Rect2(181, ground - 15, 10, 15), Styles.DANGER)
		_text(Vector2(220, ground - 42), "+%d AIM" % Elevation.AIM_BONUS, Styles.AMBER, 13, true)
		_text(Vector2(220, ground - 24), "+%d SIGHT" % Vision.HIGH_GROUND_BONUS, Styles.AMBER, 13, true)
		_text(Vector2(220, ground - 6), "COVER -1 STEP", Styles.AMBER, 13, true)

	## A soldier in the clear, a sleeping Infected and the red tiles where it would spot them.
	func _stealth() -> void:
		var ground := 50.0
		var tile := 24.0
		var n := 11
		var x0 := 6.0
		var enemy := n - 1
		var r := int(Concealment.DETECT_RADIUS)
		for i in n:
			var hot := enemy - i <= r
			var col := Color(Styles.DANGER, 0.32) if hot else Color(Styles.STEALTH, 0.12)
			draw_rect(Rect2(x0 + i * tile, ground, tile - 2, 8), col)
			if hot and i != enemy:
				draw_rect(Rect2(x0 + i * tile, ground, tile - 2, 8), Color(Styles.DANGER, 0.85), false, 1.0)
		_soldier(Vector2(x0 + tile * 1.5 - 1, ground), Styles.player_color(0))
		var ex := x0 + enemy * tile + tile * 0.5 - 1
		draw_circle(Vector2(ex, ground - 22), 5.0, Styles.DANGER)
		draw_rect(Rect2(ex - 5, ground - 16, 10, 16), Styles.DANGER)
		_text(Vector2(ex - 4, ground - 32), "z", Styles.DIM, 12)
		_text(Vector2(x0, ground + 24), "CONCEALED", Styles.STEALTH, 12)
		_text(Vector2(x0 + (enemy - r) * tile, ground + 24), "SPOTTED IN %d TILES" % r, Styles.DANGER_TEXT, 12)
		_text(Vector2(x0 + tile * 3.0, ground - 30), "+%d AIM UNAWARE" % Concealment.AMBUSH_AIM, Styles.AMBER, 12, true)

	func _tiers() -> void:
		var x0 := 4.0
		var w := size.x - 8.0
		var y := 20.0
		draw_rect(Rect2(x0, y, w, 8), Color("0e2026"))
		var names := ["Clean", "Exposed", "Mutating", "Critical", "Turned"]
		for i in 4:
			var a := x0 + w * Infection.THRESHOLDS[i] / 100.0
			var b := x0 + w * Infection.THRESHOLDS[i + 1] / 100.0
			draw_rect(Rect2(a, y, b - a - 1, 8), Color(Infection.tier_color(i), 0.35 + 0.15 * i))
		for i in 5:
			var tx := x0 + w * Infection.THRESHOLDS[i] / 100.0
			draw_line(Vector2(tx, y - 4), Vector2(tx, y + 12), Styles.TEAL, 1.0)
			_text(Vector2(clampf(tx - 8, 0, w - 22), y - 7), str(Infection.THRESHOLDS[i]), Styles.TEAL_DIM, 10, true)
			var lx := clampf(tx - (0 if i == 0 else 26), 0, w - 44)
			_text(Vector2(lx, y + 30), names[i].to_upper(), Infection.tier_color(i) if i > 0 else Styles.DIM, 11)
		_text(Vector2(x0 + w * 0.25, y + 48), "MUTATION WAKES", Styles.TEAL_DIM, 10)
		_text(Vector2(x0 + w * 0.5 + 4, y + 48), "CAN LAPSE", Styles.TEAL_DIM, 10)
		_text(Vector2(x0 + w - 70, y + 48), "ENEMY", Styles.DANGER, 10)
