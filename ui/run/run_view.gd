class_name RunView
extends Control
## Between fights: the act's node map with live route-vote pins, the squad, the run's currencies,
## and whichever screen the run phase needs (a module's node or reward screen, or the run summary).
## Reads RunState; every input goes through session.submit_run, so solo, hot-seat and online
## share one path. Solo and hot-seat: a click on the map votes for every local player at once.

signal leave_requested

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")
const ICONS := {
	RunMap.SKIRMISH: "⚔", RunMap.NEST: "☣", RunMap.EVENT: "!", RunMap.DEPOT: "$", RunMap.HOSPITAL: "+",
	RunMap.SURVIVORS: "☺", RunMap.BOSS: "☠", RunMap.UNKNOWN: "?", RunMap.AMBUSH: "⚔",
}
const OBJECTIVE_NAMES := {"extract": "Extract", "hold": "Hold", "rescue": "Rescue", "purge": "Purge", "boss": "Boss"}
const BIOME_NAMES: Array[String] = ["The Wall", "The Port", "The Bore"]
const PANEL_BG := Color(0.05, 0.06, 0.06, 0.82)

var session: Node
var run: RunState
var autoplay := false

var _top: Label
var _outbreak: Label
var _serum: Label
var _map: Control
var _squad_box: VBoxContainer
var _info: RichTextLabel
var _log: Label
var _reveal_btn: Button
var _loadout_btn: Button
var _loadout: Control
var _screen_holder: Control
## Full-screen module screens (node, reward, loadout) go here, over a dark backdrop.
var _full_holder: Control
var _screen: Control
var _screen_key := ""
var _node_buttons := {}   # node id -> Button
var _reveal_mode := false
var _log_lines: Array[String] = []
var _auto_t := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Styles.make_theme()
	var bg := ColorRect.new()
	bg.color = Color("0b0d0d")
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
	_screen_key = ""
	refresh()


# --- layout -----------------------------------------------------------------------

func _build() -> void:
	var top := _panel(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	top.add_child(row)
	_top = Styles.label("", 20, Styles.TEXT)
	row.add_child(_top)
	_outbreak = Styles.label("", 18, Palette.DANGER)
	row.add_child(_outbreak)
	_serum = Styles.label("", 16, Palette.TEAL)
	row.add_child(_serum)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_reveal_btn = Button.new()
	_reveal_btn.text = "Reveal ? (1 Intel)"
	_reveal_btn.toggle_mode = true
	_reveal_btn.focus_mode = Control.FOCUS_NONE
	_reveal_btn.toggled.connect(func(on: bool) -> void: _reveal_mode = on)
	row.add_child(_reveal_btn)
	_loadout_btn = Button.new()
	_loadout_btn.text = "Loadout"
	_loadout_btn.focus_mode = Control.FOCUS_NONE
	_loadout_btn.pressed.connect(_open_loadout)
	row.add_child(_loadout_btn)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func() -> void: leave_requested.emit())
	row.add_child(menu)

	var squad := _panel(Control.PRESET_LEFT_WIDE)
	squad.offset_left = 16
	squad.offset_top = 76
	squad.offset_bottom = -16
	squad.custom_minimum_size.x = 300
	_squad_box = VBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 8)
	squad.add_child(_squad_box)

	var side := _panel(Control.PRESET_RIGHT_WIDE)
	side.offset_right = -16
	side.offset_top = 76
	side.offset_bottom = -16
	side.custom_minimum_size.x = 300
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 10)
	side.add_child(side_box)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size = Vector2(270, 160)
	side_box.add_child(_info)
	_log = Styles.label("", 14, Styles.MUTED)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log.custom_minimum_size.x = 270
	side_box.add_child(_log)

	_map = Control.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = 340
	_map.offset_right = -340
	_map.offset_top = 90
	_map.offset_bottom = -30
	_map.mouse_filter = Control.MOUSE_FILTER_PASS
	_map.draw.connect(_draw_map)
	_map.resized.connect(_layout_nodes)
	add_child(_map)

	_screen_holder = CenterContainer.new()
	_screen_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_holder)
	_full_holder = ColorRect.new()
	_full_holder.color = Color(0.02, 0.025, 0.025, 0.92)
	_full_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_full_holder.visible = false
	add_child(_full_holder)


## A dark see-through panel with amber corner marks (the approved UI look).
func _panel(preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(preset)
	p.add_theme_stylebox_override("panel", Styles.panel_box(PANEL_BG, Color(0.25, 0.26, 0.24, 0.6), 2))
	p.draw.connect(func() -> void: _corner_marks(p))
	add_child(p)
	return p


static func _corner_marks(c: Control) -> void:
	var s := c.size
	var k := 10.0
	var col := Palette.AMBER
	for corner in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), s]:
		var dx := k if corner.x == 0 else -k
		var dy := k if corner.y == 0 else -k
		c.draw_line(corner, corner + Vector2(dx, 0), col, 2.0)
		c.draw_line(corner, corner + Vector2(0, dy), col, 2.0)


# --- refresh ------------------------------------------------------------------------

func refresh() -> void:
	if run == null:
		return
	var p_count := run.players.size()
	_top.text = "ACT %s · %s   ◆ %d Supplies   ◈ %d Intel   %s" % [["I", "II", "III"][clampi(run.act - 1, 0, 2)],
		BIOME_NAMES[clampi(run.act - 1, 0, 2)], run.supplies, run.intel, "Solo" if p_count == 1 else "%d players" % p_count]
	var stage := RunRules.outbreak_stage(run.outbreak)
	_outbreak.text = "OUTBREAK %d · %s" % [run.outbreak, RunRules.OUTBREAK_NAMES[stage]]
	var serum := PackedStringArray()
	for p in run.players:
		serum.append("%s%.1f" % ["" if p_count == 1 else "P%d " % (p + 1), run.serum.get(p, 0) / 2.0])
	_serum.text = "Serum doses: " + "  ".join(serum)
	_reveal_btn.visible = run.phase == RunState.Phase.MAP
	_loadout_btn.visible = run.phase == RunState.Phase.MAP and RunHooks.has("GearRun", "loadout_screen")
	if _loadout != null and run.phase != RunState.Phase.MAP:
		_close_loadout()
	_reveal_btn.disabled = run.intel < 1 or not run.map.any(func(n: Dictionary) -> bool: return n.hidden)
	if _reveal_btn.disabled:
		_reveal_btn.button_pressed = false
	_refresh_squad()
	_rebuild_nodes()
	_refresh_info()
	_refresh_screen()
	_map.queue_redraw()


func _refresh_squad() -> void:
	for c in _squad_box.get_children():
		c.queue_free()
	_squad_box.add_child(Styles.label("SQUAD", 18, Styles.TEXT))
	for r in run.squad():
		_squad_box.add_child(_soldier_card(r))
	var reserve := run.soldiers.filter(func(r: Dictionary) -> bool: return r.status == RunSoldier.RESERVE)
	if not reserve.is_empty():
		_squad_box.add_child(Styles.label("RESERVE", 15, Styles.MUTED))
		for r in reserve:
			_squad_box.add_child(Styles.label("  %s %s · %s" % [UnitData.SOLDIERS[r.kind].name, r.name, _owner_name(r.owner)], 14, Palette.player_ui(r.owner)))
	var lost := run.soldiers.filter(func(r: Dictionary) -> bool: return r.status in [RunSoldier.DEAD, RunSoldier.TURNED])
	if not lost.is_empty():
		_squad_box.add_child(Styles.label("LOST", 15, Styles.MUTED))
		for r in lost:
			_squad_box.add_child(Styles.label("  %s %s (%s)" % [UnitData.SOLDIERS[r.kind].name, r.name, r.status], 14, Styles.MUTED))


func _soldier_card(r: Dictionary) -> Control:
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	var stripe := ColorRect.new()
	stripe.color = Palette.player_ui(r.owner)
	stripe.custom_minimum_size = Vector2(4, 0)
	card.add_child(stripe)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var rank: int = r.prog.get("rank", 1)
	var extra := " · sits out" if r.sit_out > 0 else ""
	box.add_child(Styles.label("%s %s  ·  R%d%s" % [UnitData.SOLDIERS[r.kind].name, r.name, rank, extra], 15, Styles.TEXT))
	box.add_child(Styles.label(_owner_name(r.owner), 12, Palette.player_ui(r.owner)))
	var hp := Styles.bar(Color("b8c4a0"), 6)
	hp.max_value = maxi(1, r.max_hp)
	hp.value = r.hp
	box.add_child(hp)
	var inf := Styles.bar(Palette.tier_color(Infection.tier(r.infection)), 6)
	inf.value = r.infection
	box.add_child(inf)
	box.add_child(Styles.label("HP %d/%d   Infection %d · %s" % [r.hp, r.max_hp, r.infection, Infection.tier_name(Infection.tier(r.infection))], 12, Styles.MUTED))
	return card


func _owner_name(p: int) -> String:
	var n: String = session.player_names.get(p, "") if session != null else ""
	if run.is_solo():
		return n if n != "" else "You"
	return "P%d%s%s" % [p + 1, " " + n if n != "" else "", " (benched)" if run.benched.get(p, false) else ""]


# --- map -----------------------------------------------------------------------------

func _node_pos(n: Dictionary) -> Vector2:
	var s := _map.size
	var y: float = s.y - (n.row - 0.5) / RunState.ROWS * s.y
	var x: float = 40 + n.x * (s.x - 80)
	return Vector2(x, y)


func _rebuild_nodes() -> void:
	var ids := {}
	for n in run.map:
		ids[n.id] = true
	for id in _node_buttons.keys():
		if not ids.has(id) or not is_instance_valid(_node_buttons[id]):
			if is_instance_valid(_node_buttons[id]):
				_node_buttons[id].queue_free()
			_node_buttons.erase(id)
	var reach := run.reachable_nodes() if run.phase == RunState.Phase.MAP else ([] as Array[int])
	for n in run.map:
		var b: Button = _node_buttons.get(n.id)
		if b == null:
			b = Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(54, 54)
			b.add_theme_font_size_override("font_size", 24)
			var id: int = n.id
			b.pressed.connect(func() -> void: _on_node_pressed(id))
			b.mouse_entered.connect(func() -> void: _refresh_info(id))
			_map.add_child(b)
			_node_buttons[n.id] = b
		var type := RunMap.shown_type(n)
		b.text = ICONS.get(type, "·")
		var can := reach.has(n.id)
		var border := Palette.AMBER if can else (Palette.TEAL_DIM if n.id == run.node else Color(0.3, 0.31, 0.29))
		var fill := Color(0.16, 0.13, 0.07, 0.95) if can else (Color(0.06, 0.07, 0.07, 0.9) if not n.visited else Color(0.1, 0.12, 0.11, 0.9))
		for st in ["normal", "hover", "pressed", "disabled"]:
			var sb := Styles.panel_box(fill.lightened(0.12) if st == "hover" and can else fill, border, 27)
			sb.set_border_width_all(3 if can or n.id == run.node else 1)
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", Palette.AMBER if can else (Styles.TEXT if not n.visited else Styles.MUTED))
		b.add_theme_color_override("font_disabled_color", Styles.MUTED)
		b.disabled = not (can or (_reveal_mode and n.hidden and run.phase == RunState.Phase.MAP))
		b.tooltip_text = _node_title(n)
	_layout_nodes()


func _layout_nodes() -> void:
	for n in run.map if run else []:
		var b: Button = _node_buttons.get(n.id)
		if b != null:
			b.position = _node_pos(n) - b.custom_minimum_size / 2
	_map.queue_redraw()


func _draw_map() -> void:
	if run == null:
		return
	for n in run.map:
		for id in n.links:
			var m := run.get_node(id)
			var travelled: bool = n.visited and m.visited
			var col := Palette.TEAL_DIM if travelled else Color(0.32, 0.33, 0.3, 0.7)
			_map.draw_dashed_line(_node_pos(n), _node_pos(m), col, 2.0 if travelled else 1.5, 6.0)
	# Vote pins: one dot per voter in their colour, a crown on the host's.
	var font := get_theme_default_font()
	var per_node := {}
	for p in run.votes:
		var id: int = run.votes[p]
		per_node[id] = per_node.get(id, []) + [p]
	for id in per_node:
		var at := _node_pos(run.get_node(id)) + Vector2(-((per_node[id].size() - 1) * 9), -40)
		for p in per_node[id]:
			_map.draw_circle(at, 7, Palette.player_ui(p))
			if p == run.host_player and not run.is_solo():
				_map.draw_string(font, at + Vector2(-6, -10), "♛", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.AMBER)
			at.x += 18


func _node_title(n: Dictionary) -> String:
	var type := RunMap.shown_type(n)
	var t: String = RunMap.NAMES.get(type, type)
	if n.objective != "" and type != RunMap.UNKNOWN:
		t += " · " + OBJECTIVE_NAMES.get(n.objective, n.objective)
	return t


func _on_node_pressed(id: int) -> void:
	var n := run.get_node(id)
	if _reveal_mode and n.hidden:
		session.submit_run({"type": RunRules.REVEAL, "player": session.local_players()[0], "node": id})
		_reveal_btn.button_pressed = false
		return
	for p in session.local_players():
		if run.phase == RunState.Phase.MAP and not run.benched.get(p, false):
			session.submit_run({"type": RunRules.VOTE, "player": p, "node": id})


func _refresh_info(hover: int = -1) -> void:
	var lines := PackedStringArray()
	match run.phase:
		RunState.Phase.MAP:
			if run.is_solo():
				lines.append("[color=#e8b04a]Choose the next node.[/color]")
			else:
				lines.append("[color=#e8b04a]Vote for the next node.[/color] Majority wins; a split goes to the host (♛).")
			if run.modifiers.get("force_nest_next", false):
				lines.append("Air support: the squad must hit the nest.")
		RunState.Phase.FIGHT: lines.append("Deploying...")
		RunState.Phase.NODE, RunState.Phase.REWARD: lines.append("")
	if hover >= 0:
		var n := run.get_node(hover)
		lines.append("")
		lines.append("[b]%s[/b]  (row %d)" % [_node_title(n), n.row])
		var type := RunMap.shown_type(n)
		if type == RunMap.NEST:
			var pv: Dictionary = RunHooks.call_static("FightBuilder", "preview", [{"act": run.act, "row": n.row, "node": type, "objective": n.objective, "seed": n.seed}], {})
			if pv.get("elite", "") != "":
				lines.append("Elite: " + pv.elite)
		elif type == RunMap.UNKNOWN:
			lines.append("Could be an event, an ambush, a depot or survivors. Spend 1 Intel to reveal it.")
	var stage := RunRules.outbreak_stage(run.outbreak)
	lines.append("")
	lines.append("[color=#e2533a]Outbreak %d: %s.[/color] +1 per node; -3 per boss." % [run.outbreak, RunRules.OUTBREAK_NAMES[stage]])
	_info.text = "\n".join(lines)


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
		return
	else:
		_screen = _waiting_panel("Waiting for the squad..." if run.phase == RunState.Phase.REWARD else RunMap.NAMES.get(RunMap.shown_type(run.current_node()), ""))
	_screen_holder.add_child(_screen)


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


func _summary() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(520, 0)
	p.add_theme_stylebox_override("panel", Styles.panel_box(Color(0.03, 0.04, 0.04, 0.95), Palette.AMBER.darkened(0.3), 2))
	p.draw.connect(func() -> void: _corner_marks(p))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	var win := run.result == Types.Result.VICTORY
	var title := Styles.label("THE SOURCE IS BURNING" if win else "LANTERN COMPANY IS LOST", 34, Palette.TEAL if win else Palette.DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var lost := run.soldiers.filter(func(r: Dictionary) -> bool: return r.status in [RunSoldier.DEAD, RunSoldier.TURNED]).size()
	var lines := [
		"Reached act %d, row %d" % [run.act, run.row],
		"Fights won: %d" % run.fights_won,
		"Soldiers lost: %d (%d Turned)" % [lost, run.echoes.size()],
		"Final Outbreak: %d (%s)" % [run.outbreak, RunRules.OUTBREAK_NAMES[RunRules.outbreak_stage(run.outbreak)]],
		"Supplies left: %d" % run.supplies,
	]
	for l in lines:
		box.add_child(Styles.label(l, 18, Styles.TEXT))
	var b := Button.new()
	b.text = "MAIN MENU"
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(b)
	return p


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
