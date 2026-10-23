extends PanelContainer
## Bottom bar: selected soldier, its actions with hotkeys, and the targeting panel
## (hit chance with breakdown while shooting, hints while picking a unit/cell).

signal action_pressed(key: String)

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")
const InputController := preload("res://view/input_controller.gd")

var _title: Label
var _buttons: HBoxContainer
var _info: RichTextLabel


func build() -> void:
	name = "ActionBar"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.custom_minimum_size = Vector2(560, 0)
	_info.visible = false
	box.add_child(_info)
	_title = Styles.label("", 16)
	box.add_child(_title)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	box.add_child(_buttons)


func refresh(view: MissionView) -> void:
	var input: InputController = view.input
	var u := input.selected_unit()
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	if u == null:
		_title.text = "Select a soldier (click or Tab)" if input.can_act() else "Stand by..."
		_info.visible = false
		return
	var owner_col := Palette.player_ui(u.owner_player)
	_title.text = "%s  -  Player %d  -  %d action%s left" % [u.display_name, u.owner_player + 1, u.actions_left, "" if u.actions_left == 1 else "s"]
	_title.add_theme_color_override("font_color", owner_col)
	for a in input.actions():
		var b := Button.new()
		b.text = ("[%s] " % a.hotkey if a.hotkey != "" else "") + str(a.label)
		b.custom_minimum_size = Vector2(110, 40)
		b.disabled = not (a.enabled and input.can_act())
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_pressed_no_signal(_is_active(input, a))
		if a.get("mutation", false):
			b.add_theme_color_override("font_color", Palette.TEAL)
		var key: String = a.key
		b.pressed.connect(func() -> void: action_pressed.emit(key))
		_buttons.add_child(b)
	_refresh_info(view, input, u)


func _is_active(input: InputController, a: Dictionary) -> bool:
	if a.key == "shoot":
		return input.mode == InputController.Mode.SHOOT
	if input.pending.is_empty():
		return false
	return input.pending.get("ability", input.pending.get("mutation", "")) == a.get("id", "")


func _refresh_info(view: MissionView, input: InputController, u: Unit) -> void:
	var text := ""
	match input.mode:
		InputController.Mode.SHOOT:
			var t := input.current_target()
			if t != null:
				text = hit_text(view.state, u, t)
				text += "\n[color=#8a8f86][lb]Enter] / click target: fire    [lb]Tab] next target    [lb]Esc] cancel[/color]"
		InputController.Mode.TARGET_UNIT:
			text = "Pick a target unit    [lb]Esc] cancel"
		InputController.Mode.TARGET_CELL:
			text = "Pick a target cell    [lb]Esc] cancel"
	_info.text = text
	_info.visible = text != ""


## Hit chance summary with breakdown, from Combat.hit_chance.
static func hit_text(s: GameState, u: Unit, t: Unit) -> String:
	var odds := Combat.hit_chance(s, u, t)
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  HP %d/%d" % [t.display_name, t.hp, t.max_hp])
	lines.append("[color=#%s][b]HIT %d%%[/b][/color]   GRAZE %d%%   CRIT %d%%" % [
		Palette.AMBER.to_html(false), int(odds.get("hit", 0)), int(odds.get("graze", 0)), int(odds.get("crit", 0))])
	var cover := int(odds.get("cover", Types.Cover.NONE))
	var tags := PackedStringArray()
	if cover != Types.Cover.NONE:
		tags.append("%s cover" % ("Full" if cover == Types.Cover.FULL else "Half"))
	if odds.get("flanked", false):
		tags.append("[color=#%s]FLANKED[/color]" % Palette.DANGER.to_html(false))
	var parts := PackedStringArray()
	for row in odds.get("breakdown", []):
		if row is Array and row.size() >= 2:
			parts.append("%s %+d" % [str(row[0]), int(row[1])])
	if not parts.is_empty():
		tags.append("[color=#8a8f86]%s[/color]" % "   ".join(parts))
	if not tags.is_empty():
		lines.append("   ".join(tags))
	return "\n".join(lines)
