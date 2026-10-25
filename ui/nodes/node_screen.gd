extends Control
## Base for the node screens (event, depot, hospital, survivors). Fills the view, rebuilds
## itself from run.node_state after every run event, and sends input as run actions through
## session.submit_run. Draws a section for every player in session.local_players(), so solo
## and hot-seat players act for everyone they control. OWNER: nodes workstream.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Feel := preload("res://ui/ui_feel.gd")
const SquadPanel := preload("res://ui/nodes/squad_panel.gd")
const Tips := preload("res://ui/tips/tips.gd")

var run: RunState
var session
var _dirty := false
var _body: VBoxContainer
var _scroll: ScrollContainer
## The squad column beside the choices, on screens that call with_squad() (else null).
var squad_panel: SquadPanel


func setup(r: RunState, s) -> void:
	run = r
	session = s
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Styles.make_theme()
	var bg := ColorRect.new()
	bg.color = NodeUi.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56 if side in ["left", "right"] else 34)
	add_child(margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_scroll)
	_body = NodeUi.vbox(22)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	run.event.connect(_on_run_event)
	rebuild()
	if is_inside_tree():
		Feel.deal(_body.get_children(), 0.05)
		Feel.sound("page")


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
	squad_panel = null
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


## Node icon, kicker, big title and an optional block on the right (e.g. the squad's Supplies).
func header(kicker: String, title: String, kicker_color: Color, right: Control = null, icon := "") -> Control:
	var row := NodeUi.hbox(18)
	if icon != "":
		# The node's icon on its own, no ring round it.
		var ic := W.Icon.new(icon, kicker_color, 56, 2.2)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var left := NodeUi.vbox(2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(NodeUi.caption(kicker, kicker_color, 15))
	left.add_child(NodeUi.title(title, 52))
	row.add_child(left)
	if right != null:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
	return row


## `main` with the squad panel to its right, so choices that depend on a soldier's state sit
## next to that state. Hook choices to it with squad_panel.hook().
func with_squad(main: Control) -> Control:
	var row := NodeUi.hbox(28)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(main)
	squad_panel = SquadPanel.new()
	squad_panel.setup(run, session)
	row.add_child(squad_panel)
	return row


## Supplies, Intel, Outbreak and each local player's Serum, top right: icon, number, caption.
func wallet() -> Control:
	var row := NodeUi.hbox(26)
	row.add_child(_stat("supplies", "Supplies", str(run.supplies), NodeUi.SUPPLY))
	row.add_child(_stat("intel", "Intel", str(run.intel), NodeUi.DIM))
	row.add_child(_stat("outbreak", "Outbreak", str(run.outbreak), NodeUi.TEAL))
	for p in local_players():
		var cap := "Serum" if local_players().size() == 1 else "Serum %s" % NodeUi.player_name(session, p)
		row.add_child(_stat("serum", cap, "%d" % run.serum.get(p, 0), NodeUi.TEAL))
	return row


func _stat(icon: String, caption: String, value: String, color: Color) -> Control:
	var h := NodeUi.hbox(8)
	if not Tips.term(h, icon).has_meta(Tips.META):
		h.tooltip_text = caption
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := W.Icon.new(icon, color, 22, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := NodeUi.vbox(0)
	v.add_child(Styles.mono(value, 22, Styles.TEXT))
	v.add_child(NodeUi.caption(caption, NodeUi.FAINT, 11))
	h.add_child(v)
	return h


## Leave buttons for every local player who hasn't left, and who's still here.
func footer(note: String, can_leave := true, leave_text := "Leave") -> Control:
	var row := NodeUi.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	var text := note
	var l := NodeUi.label(text, 14, NodeUi.FAINT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)
	var many := run.present_players().size() > 1
	for p in run.present_players():
		if many and (not p in local_players() or p in ns().left):
			row.add_child(_ready_chip(p, p in ns().left))
	for p in local_players():
		if p in ns().left:
			continue
		var t := leave_text if local_players().size() == 1 else "%s · %s" % [leave_text, NodeUi.player_name(session, p)]
		var b := NodeUi.button(t, can_leave, true, "", "arrow_right")
		b.custom_minimum_size = Vector2(220, 50)
		b.pressed.connect(submit.bind({"type": "node_leave", "player": p}))
		row.add_child(b)
	# The scroll box clips, so keep the leave buttons' glow clear of its right and bottom edges.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	pad.add_child(row)
	return pad


## A teammate's state in the footer: their colour, name and a check once they're done.
func _ready_chip(p: int, done: bool) -> Control:
	var col := NodeUi.player_color(p)
	var h := NodeUi.hbox(6)
	h.add_child(W.Icon.new("check" if done else "waiting", col if done else NodeUi.FAINT, 16, 1.8))
	h.add_child(NodeUi.caption(NodeUi.player_name(session, p), col, 13))
	return h


## A player's section title with their colour.
func player_caption(p: int, extra := "") -> Label:
	var t := NodeUi.player_name(session, p) + ("  ·  " + extra if extra != "" else "")
	return NodeUi.caption(t, NodeUi.player_color(p), 14)
