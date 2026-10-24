extends Control
## Base for the node screens (event, depot, hospital, survivors). Fills the view, rebuilds
## itself from run.node_state after every run event, and sends input as run actions through
## session.submit_run. Draws a section for every player in session.local_players(), so solo
## and hot-seat players act for everyone they control. OWNER: nodes workstream.

var run: RunState
var session
var _dirty := false
var _body: VBoxContainer
var _scroll: ScrollContainer


func setup(r: RunState, s) -> void:
	run = r
	session = s
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = NodeUi.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40 if side in ["left", "right"] else 28)
	add_child(margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_scroll)
	_body = NodeUi.vbox(18)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	run.event.connect(_on_run_event)
	rebuild()


func _exit_tree() -> void:
	if run != null and run.event.is_connected(_on_run_event):
		run.event.disconnect(_on_run_event)


func _on_run_event(_ev: Dictionary) -> void:
	if not _dirty:
		_dirty = true
		_rebuild_later.call_deferred()


func _rebuild_later() -> void:
	_dirty = false
	if is_inside_tree() and not run.node_state.is_empty():
		rebuild()


func rebuild() -> void:
	NodeUi.clear(_body)
	if run.node_state.is_empty():
		return
	_build(_body)


## Subclasses fill the screen.
func _build(_into: VBoxContainer) -> void:
	pass


func ns() -> Dictionary:
	return run.node_state


func local_players() -> Array:
	var present := run.present_players()
	return Array(session.local_players()).filter(func(p): return p in present)


func submit(action: Dictionary) -> void:
	session.submit_run(action)


## Kicker, big title and an optional line on the right (e.g. the squad's Supplies).
func header(kicker: String, title: String, kicker_color: Color, right: Control = null) -> Control:
	var row := NodeUi.hbox(20)
	var left := NodeUi.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(NodeUi.caption(kicker, kicker_color, 15))
	left.add_child(NodeUi.label(title.to_upper(), 44))
	row.add_child(left)
	if right != null:
		row.add_child(right)
	return row


## Supplies, Intel, Outbreak and each local player's Serum, top right.
func wallet() -> Control:
	var row := NodeUi.hbox(28)
	row.add_child(_stat("Supplies", str(run.supplies), NodeUi.AMBER))
	row.add_child(_stat("Intel", str(run.intel), NodeUi.TEXT))
	row.add_child(_stat("Outbreak", str(run.outbreak), NodeUi.BAD))
	for p in local_players():
		var label := "Serum" if local_players().size() == 1 else "Serum · %s" % NodeUi.player_name(session, p)
		row.add_child(_stat(label, "%d" % run.serum.get(p, 0), NodeUi.TEAL))
	return row


func _stat(caption: String, value: String, color: Color) -> Control:
	var v := NodeUi.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_END
	var c := NodeUi.caption(caption)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(c)
	var l := NodeUi.label(value, 28, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(l)
	return v


## Leave buttons for every local player who hasn't left, and who's still here.
func footer(note: String, can_leave := true, leave_text := "Leave") -> Control:
	var row := NodeUi.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	var waiting: Array = run.present_players().filter(func(p): return not p in ns().left)
	var text := note
	if not local_players().is_empty() and waiting.size() > 0 and run.present_players().size() > 1:
		text += ("  ·  " if text != "" else "") + "Waiting for %d of %d" % [waiting.size(), run.present_players().size()]
	var l := NodeUi.label(text, 14, NodeUi.FAINT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	for p in local_players():
		if p in ns().left:
			continue
		var t := leave_text if local_players().size() == 1 else "%s · %s" % [leave_text, NodeUi.player_name(session, p)]
		var b := NodeUi.button(t, can_leave, true)
		b.custom_minimum_size = Vector2(200, 46)
		b.pressed.connect(submit.bind({"type": "node_leave", "player": p}))
		row.add_child(b)
	return row


## A player's section title with their colour.
func player_caption(p: int, extra := "") -> Label:
	var t := NodeUi.player_name(session, p) + ("  ·  " + extra if extra != "" else "")
	return NodeUi.caption(t, NodeUi.player_color(p), 14)
