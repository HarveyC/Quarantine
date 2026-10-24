extends ColorRect
## Full-screen Victory / Defeat overlay with a Restart button.

signal restart_pressed
signal leave_pressed

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")

## Seconds the battlefield stays clear after a loss before the overlay fades in.
const LOSS_BEAT := 1.6

var _title: Label
var _sub: Label
var _restart: Button


func build() -> void:
	name = "EndOverlay"
	color = Color(0, 0, 0, 0.72)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	_title = Styles.label("", 72)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = Styles.label("", 20, Styles.MUTED)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	var btn := Button.new()
	btn.text = "RESTART MISSION"
	btn.custom_minimum_size = Vector2(260, 52)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func() -> void: restart_pressed.emit())
	box.add_child(btn)
	_restart = btn
	var leave := Button.new()
	leave.text = "MAIN MENU"
	leave.custom_minimum_size = Vector2(260, 44)
	leave.add_theme_font_size_override("font_size", 18)
	leave.pressed.connect(func() -> void: leave_pressed.emit())
	box.add_child(leave)


## `cause` is an Objectives.LOSS key: a loss names it, and comes in after LOSS_BEAT seconds so the
## player first sees what happened on the battlefield.
func show_result(result: int, turn: int, can_restart: bool = true, in_run: bool = false, cause := "") -> void:
	_restart.visible = can_restart
	var win := result == Types.Result.VICTORY
	_title.text = "VICTORY" if win else "DEFEAT"
	_title.add_theme_color_override("font_color", Palette.TEAL if win else Palette.DANGER)
	_sub.text = ("Zone cleared in %d turns." if win else "The squad was lost on turn %d.") % turn
	if not win and Objectives.LOSS.has(cause):
		_sub.text = "%s on turn %d.\n%s" % [Objectives.LOSS[cause].title, turn, Objectives.LOSS[cause].line]
	if in_run:
		_sub.text += "\nBack to the map..." if win else "\nThe run is over."
	elif not can_restart:
		_sub.text += "\nWaiting for the host to restart."
	visible = true
	modulate.a = 1.0
	if not win and is_inside_tree():
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.4).set_delay(LOSS_BEAT)
