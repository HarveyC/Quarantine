class_name RunView
extends Control
## Between fights: the act's node map (rows left to right, drop point to boss) with the squad's
## position, open routes, live route-vote chips and a hover card per node; the route vote, the
## squad strip, the run's currencies, and whichever screen the run phase needs (a module's node or
## reward screen, or the run summary). Reads RunState; every input goes through
## session.submit_run, so solo, hot-seat and online share one path. Solo and hot-seat: a click on
## the map votes for every local player at once. Keys 1-4 vote for the routes in the vote panel.

signal leave_requested

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")
const W := preload("res://ui/widgets.gd")
const MapBoard := preload("res://ui/run/map_board.gd")
const NodeInfo := preload("res://ui/run/node_info.gd")
const Feel := preload("res://ui/ui_feel.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const BIOME_NAMES: Array[String] = ["The Wall", "The Port", "The Bore"]
const ROMAN: Array[String] = ["I", "II", "III"]
const PANEL_BG := Color(0.05, 0.06, 0.06, 0.82)
const SIDE_W := 330.0
const SQUAD_H := 100.0

var session: Node
var run: RunState
var autoplay := false

var _act: Label
var _biome: Label
var _outbreak: Label
var _outbreak_tier: Label
var _outbreak_bar: OutbreakBar
var _supplies: Label
var _intel: Label
var _serum: Label
var _map: MapBoard
var _squad_row: HBoxContainer
var _vote_title: Label
var _vote_box: VBoxContainer
var _vote_note: Label
var _log: Label
var _reveal_btn: Button
var _loadout_btn: Button
var _loadout: Control
var _screen_holder: Control
## Full-screen module screens (node, reward, loadout) go here, over a dark backdrop.
var _full_holder: Control
var _screen: Control
var _screen_key := ""
## node id -> the map's node control (kept for dev tools and tests).
var _node_buttons := {}
var _reveal_mode := false
var _log_lines: Array[String] = []
var _auto_t := 0.0


## Outbreak as segments grouped by stage (0-2, 3-5, 6-8, 9-12, 13+).
class OutbreakBar extends Control:
	const SEGS := 15
	const BREAKS: Array[int] = [3, 6, 9, 13]
	var value := 0

	func _init() -> void:
		custom_minimum_size = Vector2(SEGS * 19 + BREAKS.size() * 6, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		for i in SEGS:
			if BREAKS.has(i):
				x += 6
			draw_rect(Rect2(x, 0, 16, size.y), Styles.TEAL if i < value else Color("1d2723"))
			x += 19


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Styles.make_theme()
	var bg := ColorRect.new()
	bg.color = Color("0c0f0d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()


func setup(s: Node) -> void:
	if run != null and run.event.is_connected(_on_run_event):
		run.event.disconnect(_on_run_event)
	session = s
	run = s.run
	run.event.connect(_on_run_event)
	_log_lines.clear()
	_log.text = ""
	_screen_key = ""
	_map.set_run(run)
	refresh()


# --- layout -----------------------------------------------------------------------

func _build() -> void:
	_map = MapBoard.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = 24
	_map.offset_right = -(SIDE_W + 40)
	_map.offset_top = 104
	_map.offset_bottom = -(SQUAD_H + 40)
	_map.node_pressed.connect(_on_node_pressed)
	_map.node_hovered.connect(func(_id: int) -> void: _refresh_vote_panel())
	add_child(_map)

	# Top bar: act and biome, Outbreak, currencies and buttons.
	var top := Styles.hbox(28)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 40
	top.offset_right = -40
	top.offset_top = 24
	add_child(top)
	var title := Styles.vbox(2)
	_act = Styles.caps("", 14, Styles.DIM)
	title.add_child(_act)
	_biome = Styles.caps("", 42)
	title.add_child(_biome)
	top.add_child(title)
	top.add_child(Styles.spacer())
	var ob := Styles.vbox(6)
	ob.alignment = BoxContainer.ALIGNMENT_CENTER
	var ob_row := Styles.hbox(10)
	ob_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ob_row.add_child(W.Icon.new("outbreak", Styles.TEAL, 18, 1.8))
	_outbreak = Styles.caps("", 15, Styles.TEAL)
	ob_row.add_child(_outbreak)
	_outbreak_tier = Styles.label("", 13, Styles.MUTED)
	_outbreak_tier.visible = false
	ob_row.add_child(_outbreak_tier)
	ob.mouse_filter = Control.MOUSE_FILTER_PASS
	ob.tooltip_text = "Outbreak rises by 1 at every node and drops by %d when an act boss dies.\nHigher stages make fights harder." % RunRules.BOSS_OUTBREAK_DROP
	ob.add_child(ob_row)
	_outbreak_bar = OutbreakBar.new()
	_outbreak_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ob.add_child(_outbreak_bar)
	top.add_child(ob)
	top.add_child(Styles.spacer())
	var res := Styles.hbox(24)
	res.alignment = BoxContainer.ALIGNMENT_CENTER
	_supplies = _resource(res, "supplies", NodeInfo.DEPOT_GOLD, "Supplies")
	_intel = _resource(res, "intel", Styles.DIM, "Intel")
	_serum = _resource(res, "serum", Styles.TEAL, "Serum")
	top.add_child(res)
	var btns := Styles.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveal_btn = _top_button("Reveal", "reveal")
	_reveal_btn.tooltip_text = "Spend 1 Intel to see what a hidden node is."
	_reveal_btn.toggle_mode = true
	_reveal_btn.toggled.connect(func(on: bool) -> void:
		_reveal_mode = on
		_map.reveal_mode = on
		_map.refresh()
		_refresh_vote_panel())
	btns.add_child(_reveal_btn)
	_loadout_btn = _top_button("Loadout", "loadout")
	_loadout_btn.pressed.connect(_open_loadout)
	btns.add_child(_loadout_btn)
	var menu := _top_button("Menu", "menu")
	menu.pressed.connect(_toggle_pause)
	btns.add_child(menu)
	top.add_child(btns)

	# Right: the route vote and the field log.
	var side := W.Frame.new(Vector4(18, 16, 18, 16))
	side.set_look(Color(0.043, 0.055, 0.047, 0.86), Styles.BORDER)
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -(SIDE_W + 40)
	side.offset_right = -40
	side.offset_top = 128
	side.offset_bottom = -(SQUAD_H + 48)
	add_child(side)
	var side_box := Styles.vbox(10)
	side.add_child(side_box)
	_vote_title = Styles.caps("Route vote", 15, Styles.DIM)
	side_box.add_child(_vote_title)
	_vote_box = Styles.vbox(8)
	side_box.add_child(_vote_box)
	_vote_note = Styles.label("", 13, Styles.DIM)
	_vote_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vote_note.custom_minimum_size.x = SIDE_W - 40
	side_box.add_child(_vote_note)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_box.add_child(grow)
	side_box.add_child(Styles.caps("Field log", 13, Styles.MUTED))
	_log = Styles.label("", 13, Styles.MUTED)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size.x = SIDE_W - 40
	side_box.add_child(_log)

	# Bottom: the squad strip.
	_squad_row = Styles.hbox(12)
	_squad_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_squad_row.offset_left = 40
	_squad_row.offset_right = -40
	_squad_row.offset_top = -(SQUAD_H + 28)
	_squad_row.offset_bottom = -28
	add_child(_squad_row)

	_screen_holder = CenterContainer.new()
	_screen_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_holder)
	_full_holder = ColorRect.new()
	_full_holder.color = Color(0.02, 0.025, 0.025, 0.92)
	_full_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_holder.visible = false
	add_child(_full_holder)


func _resource(parent: Control, icon: String, col: Color, caption: String) -> Label:
	var row := Styles.hbox(8)
	row.add_child(W.Icon.new(icon, col, 18, 1.8))
	var v := Styles.mono("", 17)
	row.add_child(v)
	row.add_child(Styles.label(caption, 13, Styles.MUTED))
	parent.add_child(row)
	return v


func _top_button(text: String, icon: String) -> Button:
	var b := Styles.icon_button(text, icon, "secondary", 15, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


var _pause: Control


func _toggle_pause() -> void:
	if _pause != null and is_instance_valid(_pause):
		_pause.queue_free()
		_pause = null
		return
	_pause = PauseMenu.new()
	_pause.closed.connect(_toggle_pause)
	_pause.leave_requested.connect(func() -> void: leave_requested.emit())
	add_child(_pause)


static func _corner_marks(c: Control) -> void:
	var s := c.size
	var k := 10.0
	var col := Styles.AMBER
	for corner in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), s]:
		var dx := k if corner.x == 0 else -k
		var dy := k if corner.y == 0 else -k
		c.draw_line(corner, corner + Vector2(dx, 0), col, 2.0)
		c.draw_line(corner, corner + Vector2(0, dy), col, 2.0)


# --- refresh ------------------------------------------------------------------------

func refresh() -> void:
	if run == null:
		return
	var a := clampi(run.act - 1, 0, 2)
	_act.text = "ACT %s OF III · %s" % [ROMAN[a], "SOLO" if run.is_solo() else "%d PLAYERS" % run.players.size()]
	_biome.text = BIOME_NAMES[a].to_upper()
	var stage := RunRules.outbreak_stage(run.outbreak)
	_outbreak.text = "OUTBREAK %d · %s" % [run.outbreak, RunRules.OUTBREAK_NAMES[stage].to_upper()]
	_outbreak_tier.text = "+1 each node · -%d per boss" % RunRules.BOSS_OUTBREAK_DROP
	_outbreak_bar.value = run.outbreak
	_outbreak_bar.queue_redraw()
	_supplies.text = str(run.supplies)
	_intel.text = str(run.intel)
	_serum.text = _serum_text()
	var on_map := run.phase == RunState.Phase.MAP
	_reveal_btn.visible = on_map
	_loadout_btn.visible = on_map and RunHooks.has("GearRun", "loadout_screen")
	if _loadout != null and not on_map:
		_close_loadout()
	_reveal_btn.disabled = run.intel < 1 or not run.map.any(func(n: Dictionary) -> bool: return n.hidden)
	if _reveal_btn.disabled and _reveal_btn.button_pressed:
		_reveal_btn.button_pressed = false
	_reveal_btn.text = "REVEAL  1"
	_map.names = session.player_names if session != null else {}
	_map.refresh()
	_node_buttons = _map.dots
	_refresh_squad()
	_refresh_vote_panel()
	_refresh_screen()


func _serum_text() -> String:
	if run.is_solo():
		return "%.1f" % (run.serum.get(run.players[0], 0) / 2.0)
	var parts := PackedStringArray()
	for p in run.players:
		parts.append("P%d %.1f" % [p + 1, run.serum.get(p, 0) / 2.0])
	return "  ".join(parts)


# --- squad strip -----------------------------------------------------------------------

func _refresh_squad() -> void:
	for c in _squad_row.get_children():
		_squad_row.remove_child(c)
		c.queue_free()
	var squad := run.squad()
	squad.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.owner < b.owner or (a.owner == b.owner and a.id < b.id))
	for r in squad:
		_squad_row.add_child(_soldier_card(r))
	_squad_row.add_child(_reserve_card())


func _soldier_card(r: Dictionary) -> Control:
	var pcol := Styles.player_color(r.owner)
	var card := W.Frame.new(Vector4(16, 12, 14, 12))
	card.stripe = pcol
	var tier := Infection.tier(r.infection)
	card.set_look(Color(0.066, 0.082, 0.07, 0.92), Color(Styles.TEAL, 0.35) if tier >= 2 else Styles.BORDER_SOFT, Styles.AMBER, false)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = 250
	var row := Styles.hbox(12)
	card.add_child(row)
	var glyph := W.glyph(r.kind, pcol, 46.0)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var col := Styles.vbox(5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var top := Styles.hbox(6)
	top.add_child(Styles.caps(r.name, 17))
	top.add_child(Styles.spacer())
	if r.sit_out > 0:
		top.add_child(Styles.caps("Sits out %d" % r.sit_out, 12, Styles.DANGER_TEXT))
	else:
		top.add_child(Styles.caps("Rank %d" % r.prog.get("rank", 1), 12, Styles.DIM))
	col.add_child(top)
	var mid := Styles.hbox(6)
	var sub: String = UnitData.SOLDIERS[r.kind].name
	if not run.is_solo():
		sub += " · " + _owner_name(r.owner)
	mid.add_child(Styles.label(sub, 13, Styles.DIM))
	mid.add_child(Styles.spacer())
	mid.add_child(Styles.mono("%d/%d" % [r.hp, r.max_hp], 11, Styles.DIM))
	var hp := W.Pips.new(Vector2(10, 5))
	hp.set_values(r.max_hp, r.hp, 0, Styles.DANGER if r.hp * 3 <= r.max_hp else Styles.HP)
	mid.add_child(hp)
	col.add_child(mid)
	var inf := Styles.hbox(8)
	var bar := W.InfBar.new(5.0)
	bar.set_value(r.infection)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inf.add_child(bar)
	var tl := Styles.mono("%d %s" % [r.infection, Infection.tier_name(tier).to_upper()], 10, Styles.TEAL if tier >= 1 else Styles.TEAL_DIM)
	tl.custom_minimum_size = Vector2(84, 0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inf.add_child(tl)
	col.add_child(inf)
	return card


## Reserve recruits and the fallen, in one small card at the end of the strip.
func _reserve_card() -> Control:
	var card := W.Frame.new(Vector4(16, 12, 16, 12))
	card.set_look(Color(0.043, 0.055, 0.047, 0.86), Styles.BORDER_SOFT, Styles.AMBER, false)
	card.custom_minimum_size.x = 230
	var box := Styles.vbox(4)
	card.add_child(box)
	var reserve := run.soldiers.filter(func(r: Dictionary) -> bool: return r.status == RunSoldier.RESERVE)
	box.add_child(Styles.caps("Reserve · %d" % reserve.size(), 13, Styles.DIM))
	for r in reserve.slice(0, 3):
		box.add_child(_mini_line(r, Styles.TEXT))
	if reserve.size() > 3:
		box.add_child(Styles.label("+%d more" % (reserve.size() - 3), 12, Styles.MUTED))
	var lost := run.soldiers.filter(func(r: Dictionary) -> bool: return r.status in [RunSoldier.DEAD, RunSoldier.TURNED])
	if not lost.is_empty():
		var turned := lost.filter(func(r: Dictionary) -> bool: return r.status == RunSoldier.TURNED).size()
		box.add_child(Styles.caps("Lost %d%s" % [lost.size(), " · %d Turned" % turned if turned > 0 else ""], 12, Styles.MUTED))
	if reserve.is_empty() and lost.is_empty():
		box.add_child(Styles.label("Nobody in reserve.", 13, Styles.MUTED))
	return card


func _mini_line(r: Dictionary, col: Color) -> Control:
	var row := Styles.hbox(8)
	var dot := ColorRect.new()
	dot.color = Styles.player_color(r.owner)
	dot.custom_minimum_size = Vector2(4, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	row.add_child(Styles.label("%s %s" % [UnitData.SOLDIERS[r.kind].name, r.name], 13, col))
	return row


func _owner_name(p: int) -> String:
	var n: String = session.player_names.get(p, "") if session != null else ""
	if run.is_solo():
		return n if n != "" else "You"
	return "%s%s" % [n if n != "" else "P%d" % (p + 1), " (benched)" if run.benched.get(p, false) else ""]


# --- route vote ------------------------------------------------------------------------------

func _refresh_vote_panel() -> void:
	if run == null:
		return
	for c in _vote_box.get_children():
		_vote_box.remove_child(c)
		c.queue_free()
	var notes := PackedStringArray()
	match run.phase:
		RunState.Phase.MAP:
			_vote_title.text = "NEXT MOVE" if run.is_solo() else "ROUTE VOTE"
			var opts := run.reachable_nodes()
			for i in opts.size():
				_vote_box.add_child(_option_row(run.get_node(opts[i]), i))
			notes.append(_vote_status())
			if run.modifiers.get("force_nest_next", false):
				notes.append("Air support: the squad must hit the nest.")
			if _reveal_mode:
				notes.append("Reveal: click a dashed ? node to spend 1 Intel and see what it is.")
		RunState.Phase.FIGHT:
			_vote_title.text = "DEPLOYING"
			notes.append("The squad is moving in.")
		_:
			_vote_title.text = "ON SITE"
			var n := run.current_node()
			if not n.is_empty():
				notes.append(NodeInfo.title(n))
	_vote_note.text = "\n\n".join(notes)


func _option_row(n: Dictionary, i: int) -> Control:
	var type := RunMap.shown_type(n)
	var voters: Array = run.votes.keys().filter(func(p: int) -> bool: return run.votes[p] == n.id)
	voters.sort()
	var mine := false
	for p in session.local_players():
		if run.votes.get(p, -1) == n.id:
			mine = true
	var f := W.Frame.new(Vector4(14, 10, 14, 10))
	var hot: bool = _map.hover == n.id
	var tc := NodeInfo.color(type)
	f.set_look(Color(0.12, 0.11, 0.07, 0.94) if mine else (Color("161b17") if hot else Color("121613")),
		Styles.AMBER if mine else (Styles.BORDER_STRONG if hot else Color("2c342d")), Styles.AMBER, mine)
	f.mouse_filter = Control.MOUSE_FILTER_STOP
	f.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var id: int = n.id
	f.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_vote(id))
	f.mouse_entered.connect(func() -> void: _map.set_hover(id))
	f.mouse_exited.connect(func() -> void:
		if _map.hover == id:
			_map.set_hover(-1))
	var box := Styles.vbox(6)
	f.add_child(box)
	var head := Styles.hbox(10)
	if i < 4:
		head.add_child(W.keycap(str(i + 1)))
	head.add_child(W.Icon.new(NodeInfo.icon(type), tc if tc != Styles.TEXT else Styles.DIM, 20, 1.8))
	head.add_child(Styles.caps(NodeInfo.title(n), 17, tc if tc != Styles.TEXT else Styles.TEXT))
	head.add_child(Styles.spacer())
	if not run.is_solo():
		head.add_child(Styles.mono(str(voters.size()), 14, Styles.TEXT if voters.size() > 0 else Styles.MUTED))
	box.add_child(head)
	if not voters.is_empty() and not run.is_solo():
		var chips := Styles.hbox(6)
		for p in voters:
			var t := _owner_name(p) + (" · host" if p == run.host_player else "")
			chips.add_child(W.chip(t, Styles.player_color(p), true, 11))
		box.add_child(chips)
	for c in f.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _vote_status() -> String:
	if run.is_solo():
		return "Click a node or press its number. Hover a node to see what's there."
	var waiting := PackedStringArray()
	for p in run.present_players():
		if not run.votes.has(p):
			waiting.append(_owner_name(p))
	if run.votes.is_empty():
		return "Everyone votes. Majority wins; a tie goes to the host's pick."
	var lead := run.get_node(RunRules.vote_winner(run))
	var counts := {}
	for p in run.votes:
		counts[run.votes[p]] = counts.get(run.votes[p], 0) + 1
	var best: int = counts.values().max()
	var tied: bool = counts.values().count(best) > 1
	var s := ""
	if tied:
		s = "Tied %d to %d. The host breaks ties, so this goes to %s unless someone changes their vote." % [best, best, NodeInfo.title(lead)]
	else:
		s = "%s leads." % NodeInfo.title(lead)
	if not waiting.is_empty():
		s += " Waiting on " + ", ".join(waiting) + "."
	return s


# --- input ----------------------------------------------------------------------------------

func _on_node_pressed(id: int) -> void:
	var n := run.get_node(id)
	if _reveal_mode and n.hidden:
		session.submit_run({"type": RunRules.REVEAL, "player": session.local_players()[0], "node": id})
		_reveal_btn.button_pressed = false
		return
	if run.reachable_nodes().has(id):
		_vote(id)


func _vote(id: int) -> void:
	if run.phase == RunState.Phase.MAP:
		Feel.sound("vote")
	for p in session.local_players():
		if run.phase == RunState.Phase.MAP and not run.benched.get(p, false):
			session.submit_run({"type": RunRules.VOTE, "player": p, "node": id})


func _unhandled_key_input(e: InputEvent) -> void:
	if run == null or not visible or run.phase != RunState.Phase.MAP or _full_holder.visible or not e.is_pressed() or e.is_echo():
		return
	var k := (e as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_4:
		var opts := run.reachable_nodes()
		var i := k - KEY_1
		if i < opts.size():
			_vote(opts[i])
			get_viewport().set_input_as_handled()


# --- phase screens ------------------------------------------------------------------------

func _refresh_screen() -> void:
	var key := ""
	var script: Variant = null
	match run.phase:
		RunState.Phase.NODE:
			key = "node:%d" % run.node
			script = RunHooks.call_static("NodeRules", "screen", [RunMap.shown_type(run.current_node())])
		RunState.Phase.REWARD:
			key = "reward:%d" % run.fights_won
			script = RunHooks.call_static("GearRun", "reward_screen", [])
			if RunHooks.call_static("Story", "has_pending", [run], false):
				key = "ending"
				script = RunHooks.call_static("Story", "screen", [])
		RunState.Phase.ENDED:
			key = "end"
	if key == _screen_key:
		return
	_screen_key = key
	if _screen != null:
		_screen.queue_free()
		_screen = null
	_full_holder.visible = _loadout != null
	if key == "":
		return
	if key == "end":
		_screen = _summary()
	elif script is Script:
		_screen = (script as Script).new()
		_add_full(_screen)
		if _screen.has_method("setup"):
			_screen.setup(run, session)
		Feel.enter(_full_holder, 0.0, 0.0, 0.3)
		Feel.sound("node" if run.phase == RunState.Phase.NODE else "page")
		return
	else:
		_screen = _waiting_panel("Waiting for the squad..." if run.phase == RunState.Phase.REWARD else RunMap.NAMES.get(RunMap.shown_type(run.current_node()), ""))
	if key == "end":
		_add_full(_screen)
		Feel.enter(_full_holder, 0.0, 0.0, 0.5)
		Feel.deal(end_cards, 0.07, 0.2)
		return
	_screen_holder.add_child(_screen)
	Feel.enter(_screen, 0.0, 0.0)


func _add_full(c: Control) -> void:
	_full_holder.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_holder.visible = true


func _open_loadout() -> void:
	if _loadout != null:
		return
	var script: Variant = RunHooks.call_static("GearRun", "loadout_screen", [])
	if not script is Script:
		return
	_loadout = (script as Script).new()
	if _loadout.has_signal("closed"):
		_loadout.connect("closed", _close_loadout)
	_add_full(_loadout)
	_loadout.setup(run, session)
	Feel.enter(_full_holder, 0.0, 0.0, 0.2)
	Feel.sound("open")


func _close_loadout() -> void:
	if _loadout != null:
		_loadout.queue_free()
		_loadout = null
		_full_holder.visible = _screen != null and _screen.get_parent() == _full_holder


func _waiting_panel(text: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Styles.panel_box(PANEL_BG, Palette.AMBER.darkened(0.4), 2))
	p.add_child(Styles.label(text, 20, Styles.TEXT))
	return p


## The headline for the run's end: [title, colour]. A story ending can change it here.
func _summary_title() -> Array:
	if run.result == Types.Result.VICTORY:
		return [StoryData.SUMMARY_TITLES.get(run.story.get("ending", ""), StoryData.SUMMARY_TITLES.burn), Styles.HP]
	return [StoryData.SUMMARY_TITLES.lost, Styles.DANGER]


## Run end: a full-screen board with the headline, how far the squad got (act and row pips),
## stat tiles with icons, and each soldier's fate.
var end_cards: Array[Control] = []


func _summary() -> Control:
	end_cards.clear()
	var root := MarginContainer.new()
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 120)
	root.add_theme_constant_override("margin_top", 80)
	root.add_theme_constant_override("margin_bottom", 70)
	var v := Styles.vbox(30)
	root.add_child(v)
	var head: Array = _summary_title()
	var win := run.result == Types.Result.VICTORY
	var top := Styles.vbox(6)
	var kick := "Run complete" if win else "Run over"
	if not run.story.is_empty():
		kick += " · Wave %d" % run.story.get("wave", 0)
	if Severity.level(run) > 0:
		kick += " · Severity %d" % Severity.level(run)
	top.add_child(Styles.caps(kick, 16, Styles.DIM))
	top.add_child(Styles.caps(head[0], 76, head[1]))
	v.add_child(top)
	v.add_child(_progress_track())
	var tiles := Styles.hbox(16)
	var lost := run.soldiers.filter(func(r: Dictionary) -> bool: return r.status in [RunSoldier.DEAD, RunSoldier.TURNED]).size()
	var stage := RunRules.outbreak_stage(run.outbreak)
	tiles.add_child(_stat_tile("skirmish", str(run.fights_won), "Fights won", Styles.AMBER))
	tiles.add_child(_stat_tile("skull", str(lost), "Soldiers lost", Styles.DANGER_TEXT, "%d Turned" % run.echoes.size() if run.echoes.size() > 0 else ""))
	tiles.add_child(_stat_tile("outbreak", str(run.outbreak), "Outbreak", Styles.TEAL, RunRules.OUTBREAK_NAMES[stage]))
	tiles.add_child(_stat_tile("supplies", str(run.supplies), "Supplies left", NodeInfo.DEPOT_GOLD))
	tiles.add_child(_stat_tile("intel", "+%d" % MetaProgress.field_data(run), "Field Data", Styles.AMBER, "For every player"))
	v.add_child(tiles)
	var earned := Achievements.earned_by(run)
	var laid: int = run.story.get("echoes", []).filter(func(e: Dictionary) -> bool: return e.laid).size()
	var lore: Array = run.story.get("lore", [])
	if not earned.is_empty() or laid > 0 or not lore.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 8)
		chips.add_theme_constant_override("v_separation", 8)
		for id in earned:
			var c := W.Frame.new(Vector4(10, 6, 12, 6))
			c.set_look(Color(Styles.AMBER, 0.08), Color(Styles.AMBER, 0.5), Styles.AMBER, false)
			var h := Styles.hbox(8)
			h.add_child(W.Icon.new("trophy", Styles.AMBER, 16, 1.7))
			h.add_child(Styles.caps(Achievements.DEFS[id].name, 13, Styles.AMBER))
			c.add_child(h)
			chips.add_child(c)
		if laid > 0:
			chips.add_child(_story_chip("turned", "Echoes laid to rest: %d" % laid))
		for id in lore:
			chips.add_child(_story_chip("intel", StoryData.lore_entry(id).get("title", id)))
		v.add_child(chips)
	v.add_child(Styles.caps("Lantern Company", 15, Styles.DIM))
	var fates := HFlowContainer.new()
	fates.add_theme_constant_override("h_separation", 12)
	fates.add_theme_constant_override("v_separation", 12)
	for r in run.soldiers:
		fates.add_child(_fate_card(r))
	v.add_child(fates)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)
	var bar := Styles.hbox(12)
	bar.add_child(Styles.spacer())
	var b := Styles.icon_button("Main menu", "arrow_right", "primary", 20, 56)
	b.custom_minimum_size.x = 300
	b.pressed.connect(func() -> void: leave_requested.emit())
	bar.add_child(b)
	v.add_child(bar)
	return root


## A teal chip for story finds on the run board: Echoes laid to rest and intel recovered.
func _story_chip(icon: String, text: String) -> Control:
	var c := W.Frame.new(Vector4(10, 6, 12, 6))
	c.set_look(Color(Styles.TEAL, 0.08), Color(Styles.TEAL, 0.45), Styles.TEAL, false)
	var h := Styles.hbox(8)
	h.add_child(W.Icon.new(icon, Styles.TEAL, 16, 1.7))
	h.add_child(Styles.caps(text, 13, Styles.TEAL))
	c.add_child(h)
	return c


## Three acts of five rows as pips, lit up to where the run ended.
func _progress_track() -> Control:
	var row := Styles.hbox(18)
	for a in 3:
		var col := Styles.vbox(8)
		col.add_child(Styles.caps("Act %s · %s" % [ROMAN[a], BIOME_NAMES[a]], 13, Styles.TEXT if a + 1 <= run.act else Styles.MUTED))
		var pips := W.Pips.new(Vector2(44, 8))
		var reached := 0
		if a + 1 < run.act:
			reached = 5
		elif a + 1 == run.act:
			reached = run.row
		pips.set_values(5, mini(reached, 5), 0, Styles.AMBER if run.result != Types.Result.VICTORY else Styles.HP)
		col.add_child(pips)
		row.add_child(col)
	return row


func _stat_tile(icon: String, value: String, caption: String, col: Color, sub := "") -> Control:
	var f := W.Frame.new(Vector4(20, 16, 20, 16))
	end_cards.append(f)
	f.set_look(Color(0.05, 0.065, 0.055, 0.92), Styles.BORDER, Styles.AMBER, false)
	f.custom_minimum_size = Vector2(230, 0)
	var h := Styles.hbox(14)
	f.add_child(h)
	var ic := W.Icon.new(icon, col, 36, 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := Styles.vbox(0)
	v.add_child(Styles.mono(value, 34, Styles.TEXT))
	v.add_child(Styles.caps(caption, 12, Styles.DIM))
	if sub != "":
		v.add_child(Styles.caps(sub, 11, col))
	h.add_child(v)
	return f


## One soldier's fate: class glyph in the owner's colour, name, and Alive / Fallen / Turned.
func _fate_card(r: Dictionary) -> Control:
	var f := W.Frame.new(Vector4(14, 10, 16, 10))
	end_cards.append(f)
	var pcol := Styles.player_color(r.owner)
	f.stripe = pcol
	var dead: bool = r.status == RunSoldier.DEAD
	var turned: bool = r.status == RunSoldier.TURNED
	f.set_look(Color(0.05, 0.065, 0.055, 0.9), Styles.BORDER_SOFT, Styles.AMBER, false)
	var h := Styles.hbox(10)
	f.add_child(h)
	h.add_child(W.glyph(r.kind, pcol if not (dead or turned) else Styles.MUTED, 40.0))
	var v := Styles.vbox(2)
	v.add_child(Styles.caps(r.name, 17, Styles.TEXT if not (dead or turned) else Styles.DIM))
	var state := "Turned" if turned else ("Fallen" if dead else ("Reserve" if r.status == RunSoldier.RESERVE else "Alive"))
	var scol := Styles.TEAL if turned else (Styles.DANGER_TEXT if dead else Styles.HP)
	var sr := Styles.hbox(5)
	sr.add_child(W.Icon.new("turned" if turned else ("skull" if dead else "check"), scol, 13, 1.6))
	sr.add_child(Styles.caps(state, 12, scol))
	v.add_child(sr)
	h.add_child(v)
	return f


# --- events and autoplay ------------------------------------------------------------------

func _on_run_event(ev: Dictionary) -> void:
	var line := ""
	match ev.type:
		"supplies": line = "%+d Supplies (%s)" % [ev.amount, ev.reason]
		"intel": line = "%+d Intel (%s)" % [ev.amount, ev.reason]
		"outbreak": line = "Outbreak %+d → %d" % [ev.amount, ev.total]
		"serum": line = "%+d Serum sample%s" % [ev.amount, "" if abs(ev.amount) == 1 else "s"]
		"reveal": line = "Revealed: %s" % RunMap.NAMES.get(ev["as"], ev["as"])
		"node_enter": line = "Entered %s" % RunMap.NAMES.get(ev.node_type, ev.node_type)
		"soldier_lost":
			var r := run.get_soldier(ev.sid)
			line = "%s %s %s" % [UnitData.SOLDIERS[r.kind].name, r.name, "Turned" if ev.how == RunSoldier.TURNED else "was killed"]
		"recruit_deployed":
			var r := run.get_soldier(ev.sid)
			line = "%s %s joins the squad" % [UnitData.SOLDIERS[r.kind].name, r.name]
		"recruit": line = "New recruit in reserve"
		"echo_laid": line = "Echo %s laid to rest" % ev.name
		"lore": line = "Intel recovered: %s" % StoryData.lore_entry(ev.id).get("title", ev.id)
		"act_start": line = "Act %d begins" % ev.act
		"bench": line = "P%d %s" % [ev.player + 1, "benched" if ev.on else "is back"]
		"rejected": if session != null and session.is_local(ev.action.get("player", -1)): line = ev.reason
	if line != "":
		_log_lines.append(line)
		if _log_lines.size() > 8:
			_log_lines.pop_front()
		_log.text = "\n".join(_log_lines)
	if is_inside_tree():
		refresh.call_deferred()


func _process(delta: float) -> void:
	_shot_step()
	if not autoplay or run == null or not visible:
		return
	_auto_t += delta
	if _auto_t < 0.3:
		return
	_auto_t = 0.0
	if run.phase == RunState.Phase.MAP:
		var opts := run.reachable_nodes()
		for p in session.local_players():
			if not run.votes.has(p) and not run.benched.get(p, false) and not opts.is_empty():
				print("[autoplay] act %d row %d: player %d votes %d" % [run.act, run.row, p, opts[0]])
				session.submit_run({"type": RunRules.VOTE, "player": p, "node": opts[0]})
				return
	elif run.phase == RunState.Phase.NODE or run.phase == RunState.Phase.REWARD:
		for a in RunAutoplay.actions(run):
			if session.is_local(a.get("player", -1)) and RunRules.validate(run, a) == "":
				session.submit_run(a)
				return
	elif run.phase == RunState.Phase.ENDED and not _ended_printed:
		_ended_printed = true
		print("[autoplay] run finished: %s, act %d, run checksum %d" % [Types.Result.keys()[run.result], run.act, run.checksum()])
		get_tree().create_timer(0.1 if session is LocalSession else 1.5).timeout.connect(func() -> void: get_tree().quit(0))


var _ended_printed := false
var _shot_frames := 0


## Dev aid: `-- --run=1 --run-shot=<path.png>` saves the map screen and quits.
func _shot_step() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--run-shot=") and visible:
			_shot_frames += 1
			if _shot_frames == 40:
				get_viewport().get_texture().get_image().save_png(a.trim_prefix("--run-shot="))
				print("[run-shot] saved")
				get_tree().quit(0)
