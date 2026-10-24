extends Control
## After the Source falls: the squad chooses how it ends. Three cards (Burn it, Deliver a sample,
## Carry it); a locked one says what it needs. Every present player votes, majority wins and the
## host breaks a tie; solo picks at once. Sends Story.ENDING_VOTE through the session.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")

var run: RunState
var session: Node
var _cards: HBoxContainer
var _note: Label


func _init() -> void:
	theme = Styles.make_theme()


func setup(r: RunState, s: Node) -> void:
	run = r
	session = s
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := Styles.vbox(18)
	center.add_child(box)
	var head := Styles.caps("The bottom of the Bore", 16, Styles.DIM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var title := Styles.caps("The Source is broken open", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Styles.label("It is still alive. Decide what Lantern Company does with it.", 18, Styles.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_cards = Styles.hbox(18)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_cards)
	_note = Styles.label("", 14, Styles.MUTED)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	run.event.connect(_on_event)
	_refresh()


func _on_event(_ev: Dictionary) -> void:
	if is_inside_tree():
		_refresh.call_deferred()


func _refresh() -> void:
	if run == null:
		return
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var opts := Story.ending_options(run)
	for i in opts.size():
		_cards.add_child(_card(opts[i], i))
	if run.is_solo():
		_note.text = "Click a choice or press its number."
	else:
		var waiting := PackedStringArray()
		for p in run.present_players():
			if not run.story.votes.has(p):
				waiting.append(_pname(p))
		_note.text = "Everyone votes. A tie goes to the host's pick." + (" Waiting on %s." % ", ".join(waiting) if not waiting.is_empty() else "")


func _card(o: Dictionary, i: int) -> Control:
	var e: Dictionary = StoryData.ENDINGS[o.id]
	var mine := false
	for p in session.local_players():
		if run.story.votes.get(p, "") == o.id:
			mine = true
	var f := W.Frame.new(Vector4(22, 18, 22, 18))
	var teal: bool = o.id == "carry"
	var line := Styles.AMBER if mine else (Styles.BORDER_STRONG if o.ok else Styles.BORDER_SOFT)
	f.set_look(Color(0.12, 0.11, 0.07, 0.94) if mine else Color(0.043, 0.065, 0.103, 0.94), line, Styles.AMBER, o.ok)
	f.custom_minimum_size = Vector2(330, 300)
	var box := Styles.vbox(10)
	f.add_child(box)
	var top := Styles.hbox(10)
	if o.ok:
		top.add_child(W.keycap(str(i + 1)))
	top.add_child(Styles.caps(e.sub, 13, Styles.TEAL_DIM if teal else Styles.DIM))
	box.add_child(top)
	box.add_child(Styles.caps(e.title, 32, (Styles.TEAL if teal else Styles.TEXT) if o.ok else Styles.MUTED))
	var carrier := Story.carrier(run)
	var who := "%s %s" % [UnitData.SOLDIERS[carrier.kind].name, carrier.name] if not carrier.is_empty() else "A Critical soldier"
	var desc := Styles.label(StoryData.fill(e.desc, {"name": who}), 16, Styles.TEXT if o.ok else Styles.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 286
	box.add_child(desc)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grow)
	if not o.ok:
		var why := Styles.label("Locked. " + o.reason, 14, Styles.DANGER_TEXT)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 286
		box.add_child(why)
	elif not run.is_solo():
		var chips := Styles.hbox(6)
		for p in run.story.votes:
			if run.story.votes[p] == o.id:
				chips.add_child(W.chip(_pname(p), Styles.player_color(p), true, 11))
		box.add_child(chips)
	if o.ok:
		f.mouse_filter = Control.MOUSE_FILTER_STOP
		f.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var id: String = o.id
		f.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_vote(id))
	for c in f.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _pname(p: int) -> String:
	var n: String = session.player_names.get(p, "") if session != null and session.get("player_names") != null else ""
	return n if n != "" else "P%d" % (p + 1)


func _vote(id: String) -> void:
	for p in session.local_players():
		var a := {"type": Story.ENDING_VOTE, "player": p, "ending": id}
		if Story.validate(run, a) == "":
			session.submit_run(a)


func _unhandled_key_input(ev: InputEvent) -> void:
	if run == null or not is_visible_in_tree() or not ev.is_pressed() or ev.is_echo():
		return
	var k := (ev as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_3:
		var opts := Story.ending_options(run)
		var o: Dictionary = opts[k - KEY_1]
		if o.ok:
			_vote(o.id)
			get_viewport().set_input_as_handled()
