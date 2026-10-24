extends Control
## The Archive, from the main menu: intel logs recovered across runs (unfound ones stay dark),
## the endings seen, the wave count, and the Echoes waiting past the wall. Reads StoryProfile.

signal closed

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")

var _list: VBoxContainer
var _body: Label
var _from: Label
var _title: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Styles.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.017, 0.025, 0.043, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()


func _build() -> void:
	var snap := StoryProfile.snapshot()
	var found: Array = snap.lore
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)
	var root := Styles.vbox(18)
	margin.add_child(root)
	var top := Styles.hbox(18)
	var head := Styles.vbox(2)
	head.add_child(Styles.caps("Lantern Company · Firebase Kilo", 14, Styles.DIM))
	head.add_child(Styles.caps("Archive", 44))
	top.add_child(head)
	top.add_child(Styles.spacer())
	top.add_child(_stat("Next wave", str(snap.wave)))
	top.add_child(_stat("Intel", "%d / %d" % [found.size(), StoryData.LORE.size()]))
	var endings := PackedStringArray()
	for id in StoryData.ENDING_ORDER:
		if snap.endings.has(id):
			endings.append(StoryData.ENDINGS[id].title)
	top.add_child(_stat("Endings", ", ".join(endings) if not endings.is_empty() else "None yet"))
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(120, 44)
	back.pressed.connect(_close)
	top.add_child(back)
	root.add_child(top)

	var cols := Styles.hbox(24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 420
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_list = Styles.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var first_found := ""
	for i in StoryData.LORE.size():
		var e: Dictionary = StoryData.LORE[i]
		var have := found.has(e.id)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%02d   %s" % [i + 1, e.title if have else "Not recovered"]
		b.custom_minimum_size = Vector2(400, 40)
		b.disabled = not have
		b.focus_mode = Control.FOCUS_NONE
		var id: String = e.id
		b.pressed.connect(func() -> void: _show(id))
		_list.add_child(b)
		if have and first_found == "":
			first_found = e.id

	var reader := W.Frame.new(Vector4(28, 24, 28, 24))
	reader.set_look(Color(0.037, 0.055, 0.088, 0.9), Styles.BORDER)
	reader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(reader)
	var rbox := Styles.vbox(12)
	reader.add_child(rbox)
	_from = Styles.caps("", 14, Styles.DIM)
	rbox.add_child(_from)
	_title = Styles.caps("", 30)
	rbox.add_child(_title)
	_body = Styles.label("", 20, Styles.TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 400
	rbox.add_child(_body)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbox.add_child(grow)
	if not snap.echoes.is_empty():
		rbox.add_child(Styles.caps("Echoes past the wall", 14, Styles.TEAL_DIM))
		var names := PackedStringArray()
		for e in snap.echoes:
			names.append("%s %s (wave %d)" % [UnitData.SOLDIERS.get(e.kind, {}).get("name", e.kind), e.name, e.wave])
		var l := Styles.label(", ".join(names), 15, Styles.TEAL_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
		rbox.add_child(l)
	if first_found != "":
		_show(first_found)
	else:
		_title.text = "Nothing recovered yet"
		_body.text = "Bosses and Echoes carry intel. Bring it back and it is filed here."


func _stat(caption: String, value: String) -> Control:
	var v := Styles.vbox(2)
	v.add_child(Styles.caps(caption, 12, Styles.MUTED))
	v.add_child(Styles.caps(value, 20, Styles.TEXT))
	return v


func _show(id: String) -> void:
	var e := StoryData.lore_entry(id)
	_from.text = e.get("from", "")
	_title.text = e.get("title", "")
	_body.text = e.get("text", "")


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev.is_pressed() and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
