extends "res://ui/frame.gd"
## Top-right squad readiness: one row per player with actions left and a Ready toggle
## (enabled for local players). Rows are what HUD.panels exposes per player.

signal ready_toggled(player: int, on: bool)

const W := preload("res://ui/widgets.gd")
const SquadRoster := preload("res://ui/squad_roster.gd")


## One player's row. ready_button() is the toggle the HUD and tests drive.
class Row extends HBoxContainer:
	var player := 0
	var _name: Label
	var _you: Label
	var _ap: Control
	var _btn: Button

	func ready_button() -> Button:
		return _btn


var rows: Dictionary = {}   # player id -> Row
var _count: Label
var _rows_box: VBoxContainer


func _init() -> void:
	super(Vector4(16, 12, 16, 12))


func build(players: Array[int]) -> void:
	name = "Readiness"
	custom_minimum_size = Vector2(300, 0)
	var box := Styles.vbox(8)
	add_child(box)
	var head := Styles.hbox(6)
	head.add_child(Styles.caps("Squad readiness", 13, Styles.DIM))
	head.add_child(Styles.spacer())
	_count = Styles.mono("", 12, Styles.AMBER)
	head.add_child(_count)
	box.add_child(head)
	var sep := ColorRect.new()
	sep.color = Styles.BORDER_SOFT
	sep.custom_minimum_size = Vector2(0, 1)
	box.add_child(sep)
	_rows_box = Styles.vbox(4)
	box.add_child(_rows_box)
	for p in players:
		_rows_box.add_child(_row(p))


func _row(p: int) -> Row:
	var r := Row.new()
	r.player = p
	r.add_theme_constant_override("separation", 10)
	var sw := ColorRect.new()
	sw.color = Styles.player_color(p)
	sw.custom_minimum_size = Vector2(10, 10)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(sw)
	r._name = Styles.bold("", 16)
	r.add_child(r._name)
	r._you = Styles.label("you", 13, Styles.MUTED)
	r.add_child(r._you)
	r.add_child(Styles.spacer())
	r._ap = W.Diamonds.new(8.0)
	r._ap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(r._ap)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(104, 30)
	b.add_theme_font_size_override("font_size", 14)
	b.toggled.connect(func(on: bool) -> void: ready_toggled.emit(p, on))
	r.add_child(b)
	r._btn = b
	rows[p] = r
	return r


func refresh(view: MissionView, can_act: bool) -> void:
	var s := view.state
	var n_ready := 0
	for p in rows:
		var r: Row = rows[p]
		var is_ready: bool = s.ready.get(p, false)
		if is_ready:
			n_ready += 1
		var mine: bool = view.session.is_local(p)
		r._name.text = SquadRoster.owner_name(view, p)
		r._you.visible = mine and not view.session is LocalSession
		var total := 0
		var left := 0
		for u in s.units:
			if u.team == Types.Team.PLAYER and u.owner_player == p and u.is_alive() and not u.ai_controlled:
				total += 2
				left += u.actions_left
		(r._ap as W.Diamonds).set_values(total, mini(left, total))
		r._ap.visible = not is_ready
		r._btn.set_pressed_no_signal(is_ready)
		r._btn.text = "Ready" if is_ready else ("Set ready" if mine else "Planning")
		r._btn.disabled = not can_act or not mine
		r._btn.add_theme_color_override("font_color", Styles.HP if is_ready else Styles.player_color(p))
		r._btn.add_theme_color_override("font_disabled_color", Styles.HP if is_ready else Styles.player_color(p).darkened(0.2))
	_count.text = "%d / %d ready" % [n_ready, rows.size()]

