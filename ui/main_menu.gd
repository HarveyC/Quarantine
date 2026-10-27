extends Control
## Title screen and lobby. The title is a wordmark over a slow spore backdrop with one column of
## icon buttons (Continue, Solo, Host, Join, Hot-seat, Quick mission, Settings, Quit); Join opens
## a small address panel beside the column. The lobby shows four player slots with each player's
## colour, name and squad, the shared squad meter (4 soldiers in all, coloured by who commands
## them), the squad builder (how many soldiers, then a class for each) and the host's address as
## a copyable chip. Solo and hot-seat runs open the same lobby in local mode, where every player
## is edited on this machine and hot-seat players can be added or removed.
## Emits requests; App owns the sessions and the mission view.

signal host_requested(name: String, port: int)
signal join_requested(name: String, address: String, port: int)
signal local_requested(players: int)
## Title "Solo run" / "Hot-seat run": App offers training first, then opens the local lobby.
signal run_requested(players: int)
## Local lobby: start a run or a single fight with `picks` (player -> Array of classes).
signal local_run_requested(players: int, picks: Dictionary)
signal local_quick_requested(players: int, picks: Dictionary)
signal training_requested
signal continue_requested
signal start_requested
signal start_run_requested
signal leave_requested
## Online lobby: this player's squad changed (one class per soldier).
signal squad_picked(kinds: Array)
## Host a friends-only Steam lobby (only offered when Steam is running).
signal steam_host_requested(name: String)
## Open the Steam overlay to invite friends to our lobby.
signal steam_invite_requested

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const Feel := preload("res://ui/ui_feel.gd")
const FieldHQ := preload("res://ui/meta/field_hq.gd")
const Tips := preload("res://ui/tips/tips.gd")
const SETTINGS_SCRIPT := "res://view/game_settings.gd"
const COLUMN_W := 400.0

var _name: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: PanelContainer
var _status_label: Label
var _menu_box: Control
var _lobby_box: Control
var _join_panel: Control
var _lobby_count: Label
var _lobby_pips: W.Pips
var _slots: HBoxContainer
var _lobby_title: Label
var _squad_meter: SquadMeter
var _squad_count: Label
var _squad_title: Label
var _size_row: HBoxContainer
var _room_label: Label
var _soldier_row: HBoxContainer
var _class_row: HBoxContainer
var _address_row: HBoxContainer
var _lobby_hint: Label
var _solo_btn: Button
var _start_btn: Button
var _ready_btn: Button
var _start_run_btn: Button
var _continue_btn: Button
var _continue_sub: Label
var _lobby_continue: CheckBox
var _steam_host_btn: Button
var _invite_btn: Button
var _leave_btn: Button
## The lobby on show: an online NetSession, or null for the local (solo / hot-seat) lobby.
var _net: NetSession
var _local_players := 1
## Local lobby squads: player -> Array of classes.
var _local_picks := {}
## Whose squad the builder edits (local lobby) and which of their soldiers takes a class pick.
var _edit_player := 0
var _sel := 0


var _fit: W.FitBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Styles.make_theme()
	var bg := Backdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var fit := W.FitBox.new()
	fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit = fit
	add_child(fit)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 64)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.add_child(margin)
	var root := Styles.vbox(20)
	margin.add_child(root)
	root.add_child(_wordmark())
	# Stacks the menu and the lobby, and tells the FitBox how much room they need.
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	_build_menu(body)
	_build_lobby(body)
	_status = PanelContainer.new()
	var sb := Styles.panel_box(Color(0.16, 0.05, 0.03, 0.9), Styles.DANGER)
	sb.border_width_left = 3
	_status.add_theme_stylebox_override("panel", sb)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var srow := Styles.hbox(10)
	srow.add_child(W.Icon.new("alert", Styles.DANGER, 18, 1.8))
	_status_label = Styles.label("", 15, Styles.TEXT)
	srow.add_child(_status_label)
	_status.add_child(srow)
	add_child(_status)
	show_menu()


func _wordmark() -> Control:
	var box := Styles.vbox(4)
	var kicker := Styles.hbox(12)
	var lamp := W.Icon.new("lantern", Styles.AMBER, 34, 2.0)
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker.add_child(lamp)
	var company := Styles.display("Lantern Company", 20, Styles.AMBER, false)
	(company.get_theme_font("font") as FontVariation).spacing_glyph = 5
	kicker.add_child(company)
	box.add_child(kicker)
	var title := Styles.display("Carriers", 122, Styles.TEXT)
	title.add_theme_font_override("font", Styles.font_copy(Styles.FONT_DISPLAY_BLACK, -2))
	box.add_child(title)
	box.add_child(Styles.label("Something down the shaft is calling your name.", 20, Styles.DIM))
	return box


# --- title -------------------------------------------------------------------------------------

func _build_menu(body: Control) -> void:
	var row := Styles.hbox(40)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_box = row
	body.add_child(row)
	var col := Styles.vbox(8)
	col.custom_minimum_size.x = COLUMN_W
	row.add_child(col)
	_continue_btn = _menu_button(col, "Continue run", "continue", func() -> void: continue_requested.emit(), "primary")
	_continue_sub = Styles.mono("", 11, Color(Styles.AMBER, 0.7))
	col.add_child(_continue_sub)
	_solo_btn = _menu_button(col, "Solo run", "solo", func() -> void: run_requested.emit(1))
	_solo_btn.tooltip_text = "One player commanding 1 to 4 soldiers. A full three-act run."
	var training := _menu_button(col, "Training", "flag", func() -> void: training_requested.emit())
	training.tooltip_text = "A short guided mission that teaches the rules."
	_steam_host_btn = _menu_button(col, "Host on Steam", "coop", func() -> void: steam_host_requested.emit(_name.text))
	_steam_host_btn.tooltip_text = "A friends-only lobby. Invite friends through Steam."
	_steam_host_btn.visible = _platform() != null and _platform().steam_ready()
	var host := _menu_button(col, "Host by address", "online", func() -> void: host_requested.emit(_name.text, _port_value()))
	host.tooltip_text = "Open a lobby for up to 4 players. Friends join with your address."
	var join := _menu_button(col, "Join game", "join", _toggle_join)
	join.tooltip_text = "Connect to a friend's lobby by address."
	var hot := _menu_button(col, "Hot-seat run", "hotseat", func() -> void: run_requested.emit(2))
	hot.tooltip_text = "Two to four players on one screen, sharing up to 4 soldiers."
	var quick := _menu_button(col, "Quick mission", "quick", func() -> void: local_requested.emit(2))
	quick.tooltip_text = "A single hot-seat fight, no run."
	col.add_child(_gap(4))
	var hq := _menu_button(col, "Field HQ", "doctrine", open_field_hq, "ghost")
	hq.tooltip_text = "Unlocks, Severity, run record and achievements."
	var archive := _menu_button(col, "Archive", "intel", func() -> void: add_child(preload("res://ui/story/archive_screen.gd").new()), "ghost")
	archive.tooltip_text = "Intel logs and endings you have found."
	_menu_button(col, "Settings", "settings", _open_settings, "ghost")
	_menu_button(col, "Quit", "leave", func() -> void: get_tree().quit(), "ghost")
	# Join panel, beside the column.
	var jp := W.Frame.new(Vector4(20, 16, 20, 18))
	jp.custom_minimum_size = Vector2(380, 0)
	jp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_join_panel = jp
	var jv := Styles.vbox(10)
	jp.add_child(jv)
	var jh := Styles.hbox(8)
	jh.add_child(W.Icon.new("join", Styles.AMBER, 18, 1.8))
	jh.add_child(Styles.caps("Join a lobby", 17))
	jv.add_child(jh)
	jv.add_child(Styles.caps("Host address", 12, Styles.MUTED))
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.1.20"
	_address.mouse_filter = Control.MOUSE_FILTER_STOP
	_address.text_submitted.connect(func(_t: String) -> void: _emit_join())
	jv.add_child(_address)
	var prow := Styles.hbox(10)
	var pcol := Styles.vbox(4)
	pcol.add_child(Styles.caps("Port", 12, Styles.MUTED))
	_port = LineEdit.new()
	_port.text = str(NetSession.DEFAULT_PORT)
	_port.custom_minimum_size.x = 110
	_port.mouse_filter = Control.MOUSE_FILTER_STOP
	pcol.add_child(_port)
	prow.add_child(pcol)
	prow.add_child(Styles.spacer())
	var go := Styles.icon_button("Connect", "arrow_right", "primary", 16, 42)
	go.size_flags_vertical = Control.SIZE_SHRINK_END
	go.custom_minimum_size.x = 150
	go.pressed.connect(_emit_join)
	prow.add_child(go)
	jv.add_child(prow)
	row.add_child(jp)
	jp.visible = false
	row.add_child(Styles.spacer())
	# Callsign, bottom right of the title.
	var right := Styles.vbox(8)
	right.size_flags_vertical = Control.SIZE_SHRINK_END
	var cs := W.Frame.new(Vector4(16, 12, 16, 14))
	cs.set_look(Color(0.039, 0.055, 0.094, 0.8), Styles.BORDER, Styles.AMBER, false)
	cs.custom_minimum_size.x = 280
	var cv := Styles.vbox(6)
	cs.add_child(cv)
	var ch := Styles.hbox(8)
	ch.add_child(W.Icon.new("solo", Styles.DIM, 14, 1.6))
	ch.add_child(Styles.caps("Callsign", 12, Styles.MUTED))
	cv.add_child(ch)
	_name = LineEdit.new()
	var steam_name: String = _platform().player_name() if _platform() != null else ""
	_name.text = steam_name if steam_name != "" else (OS.get_environment("USER").capitalize() if OS.has_environment("USER") else "Player")
	_name.max_length = 16
	_name.mouse_filter = Control.MOUSE_FILTER_STOP
	_name.tooltip_text = "Shown to the other players online."
	cv.add_child(_name)
	right.add_child(cs)
	right.add_child(_keys_hint())
	row.add_child(right)


func _keys_hint() -> Control:
	var h := Styles.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(W.keycap("F10"))
	h.add_child(Styles.caps("Sound", 11, Styles.MUTED))
	return h


func _gap(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## One button in a menu column: icon, caps text, full column width.
func _menu_button(parent: Control, text: String, icon: String, cb: Callable, kind := "secondary") -> Button:
	var b := Styles.icon_button(text, icon, kind, 19 if kind != "ghost" else 17, 46.0 if kind != "ghost" else 34.0)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _toggle_join() -> void:
	_join_panel.visible = not _join_panel.visible
	_fit.refit()
	if _join_panel.visible:
		Feel.enter(_join_panel)
		Feel.sound("open")
		_address.grab_focus()


func _open_settings() -> void:
	if ResourceLoader.exists(SETTINGS_SCRIPT):
		var gs: Script = load(SETTINGS_SCRIPT)
		if gs.has_method("open_menu"):
			gs.call("open_menu")
			return
	var ss := get_node_or_null("/root/Soundscape")
	if ss != null:
		ss.toggle_settings()


# --- lobby -------------------------------------------------------------------------------------

func _build_lobby(body: Control) -> void:
	var v := Styles.vbox(22)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_box = v
	body.add_child(v)
	var head := Styles.hbox(16)
	_lobby_title = Styles.caps("Lobby", 34)
	head.add_child(_lobby_title)
	_lobby_pips = W.Pips.new(Vector2(18, 6))
	_lobby_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_lobby_pips)
	_lobby_count = Styles.mono("", 15, Styles.DIM)
	head.add_child(_lobby_count)
	head.add_child(_gap_x(18))
	var sq := Styles.caps("Squad", 15, Styles.DIM)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sq)
	_squad_meter = SquadMeter.new()
	_squad_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_squad_meter)
	_squad_count = Styles.mono("", 15, Styles.DIM)
	head.add_child(_squad_count)
	head.add_child(Styles.spacer())
	_address_row = Styles.hbox(10)
	head.add_child(_address_row)
	v.add_child(head)
	_slots = Styles.hbox(14)
	v.add_child(_slots)
	v.add_child(_build_squad_builder())
	_lobby_hint = Styles.label("", 14, Styles.MUTED)
	v.add_child(_lobby_hint)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)
	var bar := Styles.hbox(14)
	_lobby_continue = CheckBox.new()
	_lobby_continue.text = "Continue the saved run"
	_lobby_continue.focus_mode = Control.FOCUS_NONE
	bar.add_child(_lobby_continue)
	bar.add_child(Styles.spacer())
	_invite_btn = Styles.icon_button("Invite Steam friends", "coop", "secondary", 17, 54)
	_invite_btn.pressed.connect(func() -> void: steam_invite_requested.emit())
	bar.add_child(_invite_btn)
	_leave_btn = Styles.icon_button("Leave", "leave", "ghost", 17, 50)
	_leave_btn.pressed.connect(func() -> void:
		if _net == null:
			show_menu()
		else:
			leave_requested.emit())
	bar.add_child(_leave_btn)
	_ready_btn = Styles.icon_button("Ready", "check", "primary", 20, 54)
	_ready_btn.custom_minimum_size.x = 260
	_ready_btn.pressed.connect(func() -> void:
		if _net != null:
			Feel.sound("pick")
			_net.set_lobby_ready(not _net.is_ready(_net.my_player)))
	Tips.term(_ready_btn, "lobby_ready")
	bar.add_child(_ready_btn)
	_start_btn = Styles.icon_button("Quick mission", "quick", "secondary", 18, 54)
	_start_btn.tooltip_text = "A single fight, no run."
	_start_btn.pressed.connect(func() -> void:
		if _net == null:
			_save_local()
			local_quick_requested.emit(_local_players, _local_picks.duplicate(true))
		else:
			start_requested.emit())
	bar.add_child(_start_btn)
	_start_run_btn = Styles.icon_button("Start run", "play", "primary", 20, 54)
	_start_run_btn.custom_minimum_size.x = 260
	_start_run_btn.pressed.connect(func() -> void:
		if _net == null:
			_save_local()
			local_run_requested.emit(_local_players, _local_picks.duplicate(true))
		else:
			start_run_requested.emit())
	bar.add_child(_start_run_btn)
	v.add_child(bar)


func show_menu(message: String = "") -> void:
	var saved := RunSave.read() if RunSave.exists() else null
	_continue_btn.visible = saved != null
	_continue_sub.visible = saved != null
	if saved != null:
		_continue_sub.text = RunSave.summary(saved).to_upper()
	_solo_btn.text = "Solo run" + _severity_tag()
	_menu_box.visible = true
	_lobby_box.visible = false
	_join_panel.visible = false
	_fit.refit()
	show_status(message)
	if is_inside_tree():
		Feel.deal(_menu_box.get_child(0).get_children(), 0.035)


## Field HQ over the menu: Field Data unlocks, Severity, run record, achievements.
func open_field_hq() -> void:
	var hq := FieldHQ.new()
	hq.closed.connect(func() -> void: if _menu_box.visible: show_menu(_status_label.text))
	add_child(hq)


func _severity_tag() -> String:
	var n := Profile.severity()
	return "  ·  Severity %d" % n if n > 0 else ""


func _platform() -> Node:
	return get_node_or_null("/root/Platform")


func show_status(message: String) -> void:
	_status_label.text = message
	_status.visible = message != ""
	if _status.visible and is_inside_tree():
		Feel.enter(_status, 0.0, 10.0)
		Feel.sound("close")


## Shows the lobby for `net`. Called again whenever the lobby changes.
func show_lobby(net: NetSession) -> void:
	var first := not _lobby_box.visible or _net != net
	_net = net
	if _edit_player != net.my_player:
		_sel = 0
	_edit_player = net.my_player
	var entries := net.lobby.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.player < b.player)
	if first:
		_restore_online_squad(net)
	_lobby_title.text = "LOBBY"
	_render_lobby(entries, net.planned_squads(), net.room_for(net.my_player), first)
	NodeUi.clear(_address_row)
	if net.is_host:
		var addrs := NetSession.local_addresses()
		var addr: String = addrs[0] if not addrs.is_empty() else "?"
		var port := _port_value()
		_address_row.add_child(W.Icon.new("online", Styles.DIM, 18, 1.8))
		var chip := Styles.mono("%s : %d" % [addr, port], 16, Styles.TEXT)
		chip.tooltip_text = "Friends on your network join with this address.\nOver the internet they need your public IP and port %d forwarded, or a shared LAN tool like Tailscale." % port
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		_address_row.add_child(chip)
		var copy := Styles.icon_button("Copy", "copy", "ghost", 14, 34)
		copy.tooltip_text = "Copy the address"
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set("%s:%d" % [addr, port])
			copy.text = "Copied")
		_address_row.add_child(copy)
		_lobby_hint.text = "Everyone picks how many soldiers they command. The whole squad is %d at most, and fights scale to its size." % MatchConfig.MAX_SQUAD
	else:
		_lobby_hint.text = "Pick your squad, then Ready up. The host starts the run."
	_invite_btn.visible = net.via_steam()
	_invite_btn.disabled = net.steam_lobby() == 0
	if net.via_steam():
		NodeUi.clear(_address_row)
		_address_row.add_child(W.Icon.new("coop", Styles.DIM, 18, 1.8))
		_address_row.add_child(Styles.caps("Steam lobby", 15, Styles.TEXT))
		if net.is_host:
			_lobby_hint.text = "Invite friends, or they can pick Join game on you in their Steam friends list."
	_start_btn.visible = net.is_host
	_start_run_btn.visible = net.is_host
	_start_run_btn.text = "Start run" + _severity_tag()
	var waiting := net.waiting_on()
	_start_btn.disabled = waiting > 0
	_start_run_btn.disabled = waiting > 0
	var wait_tip := "Waiting for %d %s to Ready up." % [waiting, "player" if waiting == 1 else "players"] if waiting > 0 else ""
	_start_btn.tooltip_text = wait_tip if waiting > 0 else "A single fight, no run."
	_start_run_btn.tooltip_text = wait_tip
	_ready_btn.visible = not net.is_host
	var mine := net.is_ready(net.my_player)
	_ready_btn.text = "Ready" if not mine else "Not ready"
	_lobby_continue.visible = net.is_host and RunSave.exists()


## The local lobby for a solo (1 player) or hot-seat run: every squad is set up on this machine.
## Opens on the squads last picked for that mode.
func show_local_lobby(players: int) -> void:
	_net = null
	var mode := "solo" if players <= 1 else "hotseat"
	var saved := Profile.last_squad(mode)
	if players > 1 and saved.size() > 1:
		players = saved.size()
	_local_players = clampi(players, 1, MatchConfig.MAX_SQUAD)
	_local_picks = {}
	var ok := Progression.unlocked_classes(Profile.meta())
	for p in _local_players:
		var kinds: Array = (saved.get(p, []) as Array).filter(func(k) -> bool: return ok.has(k)) if saved.get(p) is Array else []
		if not kinds.is_empty():
			_local_picks[p] = kinds
	_edit_player = 0
	_sel = 0
	_show_local(true)


func _show_local(first := false) -> void:
	_menu_box.visible = false
	_join_panel.visible = false
	_status.visible = false
	var plan := _local_plan()
	_local_picks = plan.duplicate(true)   # concrete classes, so edits start from what's shown
	var entries: Array = []
	for p in _local_players:
		entries.append({"player": p, "name": _local_name(p)})
	_lobby_title.text = "SOLO" if _local_players == 1 else "HOT-SEAT"
	_render_lobby(entries, plan, MatchConfig.room_for(_local_players, _local_picks, _edit_player), first)
	NodeUi.clear(_address_row)
	_address_row.add_child(W.Icon.new("solo" if _local_players == 1 else "hotseat", Styles.DIM, 18, 1.8))
	_address_row.add_child(Styles.caps("This machine", 15, Styles.TEXT))
	if _local_players == 1:
		_lobby_hint.text = "Command 1 to %d soldiers. Fights scale to the size of your squad." % MatchConfig.MAX_SQUAD
	else:
		_lobby_hint.text = "Click a player to set up their squad. You share %d soldiers at most." % MatchConfig.MAX_SQUAD
	_invite_btn.visible = false
	_start_btn.visible = true
	_start_btn.disabled = false
	_start_btn.tooltip_text = "A single fight, no run."
	_start_run_btn.visible = true
	_start_run_btn.disabled = false
	_start_run_btn.tooltip_text = ""
	_ready_btn.visible = false
	_start_run_btn.text = "Start run" + _severity_tag()
	_lobby_continue.visible = false


func _local_plan() -> Dictionary:
	var plan := {}
	for p in _local_players:
		plan[p] = []
	for e in MatchConfig.squad_plan(_local_players, _local_picks):
		plan[e.player].append(e.kind)
	return plan


func _local_name(p: int) -> String:
	if p == 0:
		var n := _name.text.strip_edges()
		return n if n != "" else "Player 1"
	return "Player %d" % (p + 1)


func _save_local() -> void:
	Profile.set_last_squad("solo" if _local_players == 1 else "hotseat", _local_picks.duplicate(true))


## Online: send the squad this player picked last time, once, when they arrive in a lobby.
func _restore_online_squad(net: NetSession) -> void:
	for v in net.lobby.values():
		if v.player == net.my_player and not v.get("squad", []).is_empty():
			return
	var saved: Array = Profile.last_squad("online").get(0, [])
	var ok := Progression.unlocked_classes(Profile.meta())
	saved = saved.filter(func(k) -> bool: return ok.has(k))
	if not saved.is_empty():
		squad_picked.emit(saved)


func _refresh_lobby() -> void:
	if _net != null:
		show_lobby(_net)
	else:
		_show_local()


## The parts the online and local lobbies share: player slots, the squad meter and the builder.
## `plan` is player -> Array of classes; `room` is how many soldiers the edited player can field.
func _render_lobby(entries: Array, plan: Dictionary, room: int, first: bool) -> void:
	_menu_box.visible = false
	_lobby_box.visible = true
	_status.visible = false
	_fit.refit()
	var local := _net == null
	_lobby_pips.set_values(NetSession.MAX_PLAYERS, entries.size(), 0, Styles.AMBER)
	_lobby_count.text = "%d / %d" % [entries.size(), NetSession.MAX_PLAYERS]
	var cols: Array = []
	var names: Array = []
	for e in entries:
		for k in plan.get(e.player, []):
			cols.append(Styles.player_color(e.player))
			names.append("%s: %s" % [e.name, UnitData.SOLDIERS[k].name])
	_squad_meter.set_colors(cols)
	_squad_meter.tooltip_text = "\n".join(names)
	_squad_count.text = "%d / %d" % [cols.size(), MatchConfig.MAX_SQUAD]
	NodeUi.clear(_slots)
	for i in NetSession.MAX_PLAYERS:
		if i < entries.size():
			_slots.add_child(_slot(entries[i], plan.get(entries[i].player, []), local and entries.size() > 1, local and i > 0 and i == entries.size() - 1))
		elif local and i == entries.size():
			_slots.add_child(_add_player_slot(entries.size() < MatchConfig.MAX_SQUAD))
		elif not local:
			_slots.add_child(_slot({}, [], false, false))
	var kinds: Array = plan.get(_edit_player, []).duplicate()
	_sel = clampi(_sel, 0, maxi(0, kinds.size() - 1))
	var col := Styles.player_color(_edit_player)
	if local and _local_players > 1:
		_squad_title.text = "P%d SQUAD" % (_edit_player + 1)
	else:
		_squad_title.text = "YOUR SQUAD"
	_squad_title.add_theme_color_override("font_color", col if local and _local_players > 1 else Styles.DIM)
	NodeUi.clear(_size_row)
	for n in range(1, MatchConfig.MAX_SQUAD + 1):
		_size_row.add_child(_size_tile(n, kinds.size(), n <= room, col))
	var others := MatchConfig.MAX_SQUAD - room
	_room_label.text = "%d of %d taken by the others" % [others, MatchConfig.MAX_SQUAD] if others > 0 else ""
	NodeUi.clear(_soldier_row)
	for i in kinds.size():
		_soldier_row.add_child(_soldier_tile(i, kinds[i], col, i == _sel))
	NodeUi.clear(_class_row)
	var picked: String = kinds[_sel] if _sel < kinds.size() else ""
	var open := Progression.unlocked_classes(Profile.meta())
	for k in open:
		_class_row.add_child(_class_tile(k, k == picked))
	# Locked classes stay in view, greyed, so their hover card can say how to unlock them.
	for k in UnitData.SOLDIERS:
		if not open.has(k):
			_class_row.add_child(_class_tile(k, false, true))
	if first and is_inside_tree():
		Feel.deal(_slots.get_children(), 0.06)
		Feel.sound("open")


## How many soldiers, how they're split and which of them gets the next class pick.
func _build_squad_builder() -> Control:
	var v := Styles.vbox(12)
	var head := Styles.hbox(14)
	_squad_title = Styles.caps("Your squad", 14, Styles.DIM)
	_squad_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_squad_title)
	_size_row = Styles.hbox(6)
	head.add_child(_size_row)
	_room_label = Styles.mono("", 13, Styles.MUTED)
	_room_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_room_label)
	v.add_child(head)
	var row := Styles.hbox(14)
	_soldier_row = Styles.hbox(10)
	row.add_child(_soldier_row)
	var arrow := W.Icon.new("arrow_left", Styles.MUTED, 22, 1.8)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	_class_row = Styles.hbox(10)
	row.add_child(_class_row)
	v.add_child(row)
	return v


## Sets the edited player's squad: online it goes to the host, locally it applies here.
func _set_squad(kinds: Array) -> void:
	if _net != null:
		Profile.set_last_squad("online", {0: kinds.duplicate()})
		squad_picked.emit(kinds)
		if not _net.is_host:
			_refresh_lobby()
	else:
		_local_picks[_edit_player] = kinds
		_refresh_lobby()


func _current_squad() -> Array:
	if _net != null:
		return _net.planned_squads().get(_edit_player, []).duplicate()
	return _local_plan().get(_edit_player, []).duplicate()


## Classes already in the lobby's squads.
func _used_classes() -> Dictionary:
	var used := {}
	var plan := _net.planned_squads() if _net != null else _local_plan()
	for p in plan:
		for k in plan[p]:
			used[k] = true
	return used


## A class not in `used` (the first unlocked one if every class is taken).
func _free_class(used: Dictionary) -> String:
	var ok := Progression.unlocked_classes(Profile.meta())
	for k in ok:
		if not used.has(k):
			return k
	return ok[0] if not ok.is_empty() else MatchConfig.CLASSES[0]


## Grows or shrinks the edited squad to `n`; new soldiers take classes nobody has yet and the
## newest one is selected for a class pick.
func _resize_squad(n: int) -> void:
	var kinds := _current_squad()
	var old := kinds.size()
	if n == old:
		return
	var used := _used_classes()
	while kinds.size() > n:
		kinds.pop_back()
	while kinds.size() < n:
		var k := _free_class(used)
		kinds.append(k)
		used[k] = true
	_sel = n - 1 if n > old else mini(_sel, n - 1)
	Feel.sound("pick")
	_set_squad(kinds)


## A squad size button: the number over a row of soldier pips; dim when there's no room.
func _size_tile(n: int, current: int, open: bool, col: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = n == current
	b.disabled = not open
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(62, 52)
	b.tooltip_text = ("%d soldier" % n + ("s" if n > 1 else "")) if open else "The others have the rest of the %d squad slots" % MatchConfig.MAX_SQUAD
	Styles.style_button(b, "secondary", 0)
	Styles.round_button(b, 14)
	var on := n == current
	if on:
		b.add_theme_stylebox_override("pressed", Styles.glow_box(Color(Styles.AMBER, 0.14), Styles.AMBER, Color(Styles.AMBER, 0.35), 12, 14))
	var v := Styles.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Styles.caps(str(n), 18, Styles.AMBER if on else (Styles.TEXT if open else Styles.MUTED))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var pips := W.Pips.new(Vector2(7, 4))
	pips.gap = 2.0
	pips.set_values(n, n, 0, Styles.AMBER if on else (col if open else Styles.BORDER_STRONG))
	pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pips)
	b.add_child(v)
	b.pressed.connect(func() -> void: _resize_squad(n))
	return b


## One soldier of the edited squad: portrait in the owner's colour, class and slot number.
## The selected one (amber) takes the next class pick.
func _soldier_tile(i: int, kind: String, col: Color, on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(132, 112)
	Tips.soldier_class(b, kind)
	Styles.style_button(b, "secondary", 0)
	Styles.round_button(b, 24)
	if on:
		b.add_theme_stylebox_override("pressed", Styles.glow_box(Color(Styles.AMBER, 0.12), Styles.AMBER, Color(Styles.AMBER, 0.35), 16, 24))
	var v := Styles.vbox(6)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pt := W.Portrait.new(50.0)
	pt.setup(kind, col, 0, on)
	pt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pt)
	var l := Styles.caps(UnitData.SOLDIERS[kind].name, 14, Styles.AMBER if on else Styles.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	var idx := Styles.mono("%d" % (i + 1), 11, Styles.AMBER if on else Styles.MUTED)
	idx.position = Vector2(12, 8)
	b.add_child(idx)
	b.pressed.connect(func() -> void:
		Feel.sound("pick")
		_sel = i
		_refresh_lobby())
	return b


## One of the four lobby slots: the player's colour along the top, name, tags and squad.
## `pickable`: a local lobby click edits this player's squad; `removable`: the last hot-seat
## player can be dropped.
func _slot(e: Dictionary, kinds: Array, pickable: bool, removable: bool) -> Control:
	var f := W.Frame.new(Vector4(18, 16, 18, 16))
	f.custom_minimum_size = Vector2(250, 176)
	if e.is_empty():
		f.set_look(Color(0.04, 0.055, 0.09, 0.45), Styles.BORDER_SOFT, Styles.AMBER, false)
		var v := Styles.vbox(10)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var ic := W.Icon.new("waiting", Styles.BORDER_STRONG, 30, 1.8)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var l := Styles.caps("Open slot", 14, Styles.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		f.add_child(v)
		return f
	var col := Styles.player_color(e.player)
	var you: bool = (_net != null and e.player == _net.my_player) or (_net == null and e.player == 0)
	var editing: bool = pickable and e.player == _edit_player
	var lit := editing or (you and not pickable)
	f.set_look(Color(0.05, 0.07, 0.11, 0.9), Color(col, 0.55) if lit else Styles.BORDER, Styles.AMBER, lit)
	f.draw.connect(func() -> void:
		var w := f.size.x * 0.36
		W.Draw.capsule(f, Rect2((f.size.x - w) * 0.5, -2, w, 4), col))
	if pickable:
		f.mouse_filter = Control.MOUSE_FILTER_STOP
		f.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		f.tooltip_text = "Set up %s's squad" % e.name
		f.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _edit_player != e.player:
				Feel.sound("pick")
				_edit_player = e.player
				_sel = 0
				_refresh_lobby())
	var v := Styles.vbox(10)
	f.add_child(v)
	var top := Styles.hbox(8)
	top.add_child(Styles.caps("P%d" % (e.player + 1), 14, col))
	top.add_child(Styles.spacer())
	if _net != null and e.player == 0:
		top.add_child(W.chip("Host", Styles.DIM, false, 11))
	if editing:
		top.add_child(W.chip("Editing", col, true, 11))
	elif you and not pickable:
		top.add_child(W.chip("You", col, true, 11))
	if removable:
		var rm := Styles.icon_button("Remove", "minus", "ghost", 12, 26)
		rm.tooltip_text = "Remove this player"
		rm.pressed.connect(func() -> void:
			Feel.sound("close")
			_local_picks.erase(e.player)
			_local_players -= 1
			if _edit_player >= _local_players:
				_edit_player = 0
				_sel = 0
			_refresh_lobby())
		top.add_child(rm)
	v.add_child(top)
	v.add_child(Styles.caps(str(e.name), 26))
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)
	if kinds.size() == 1:
		var r := Styles.hbox(10)
		var pt := W.Portrait.new(48.0)
		pt.setup(kinds[0], col, 0)
		r.add_child(pt)
		r.add_child(Styles.caps(UnitData.SOLDIERS[kinds[0]].name, 17, Styles.TEXT))
		v.add_child(r)
	elif kinds.size() > 1:
		var r := Styles.hbox(6)
		for k in kinds:
			var pt := W.Portrait.new(42.0)
			pt.setup(k, col, 0)
			pt.tooltip_text = UnitData.SOLDIERS[k].name
			pt.mouse_filter = Control.MOUSE_FILTER_PASS
			r.add_child(pt)
		r.add_child(Styles.spacer())
		var n := Styles.mono("x%d" % kinds.size(), 15, col)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(n)
		v.add_child(r)
	return f


## Local lobby: a slot that adds another hot-seat player.
func _add_player_slot(open: bool) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(250, 176)
	b.disabled = not open
	b.tooltip_text = "Add a hot-seat player" if open else "The squad is full: drop a soldier first"
	Styles.style_button(b, "secondary", 0)
	Styles.round_button(b, Styles.RADIUS)
	var v := Styles.vbox(10)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := W.Icon.new("plus", Styles.DIM if open else Styles.BORDER_STRONG, 30, 1.8)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Styles.caps("Add player", 14, Styles.DIM if open else Styles.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	b.pressed.connect(func() -> void:
		Feel.sound("open")
		_local_players += 1
		_edit_player = _local_players - 1
		_sel = 0
		_refresh_lobby())
	return b


## A class tile: the class icon over its name; amber when it's the selected soldier's class.
## A locked class is a dim tile with a lock that can't be picked. Hovering shows the class card.
func _class_tile(k: String, on: bool, locked := false) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.disabled = locked
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(112, 112)
	Tips.soldier_class(b, k, locked)
	Styles.style_button(b, "secondary")
	Styles.round_button(b, 24)
	if on:
		b.add_theme_stylebox_override("pressed", Styles.glow_box(Color(Styles.AMBER, 0.14), Styles.AMBER, Color(Styles.AMBER, 0.35), 16, 24))
	var v := Styles.vbox(8)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := W.Icon.new(Icons.for_class(k), Styles.AMBER if on else (Styles.MUTED if locked else Styles.DIM), 52, 1.9)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Styles.caps(UnitData.SOLDIERS[k].name, 14, Styles.AMBER if on else (Styles.MUTED if locked else Styles.TEXT))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	# The tile widens for a long class name at a big text size.
	var text_w := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
	b.custom_minimum_size.x = maxf(118.0, text_w + 28.0)
	if locked:
		b.modulate.a = 0.6
		var lock := W.Icon.new("lock", Styles.DIM, 16, 1.6)
		lock.position = Vector2(b.custom_minimum_size.x - 26, 10)
		b.add_child(lock)
		return b
	b.pressed.connect(func() -> void:
		Feel.sound("pick")
		var kinds := _current_squad()
		if _sel < kinds.size():
			kinds[_sel] = k
			_set_squad(kinds)
		else:
			_refresh_lobby())
	return b


func _gap_x(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Host: whether to continue the saved run instead of starting a new one.
func continue_saved() -> bool:
	return _lobby_continue.visible and _lobby_continue.button_pressed


func _emit_join() -> void:
	var addr := _address.text.strip_edges()
	if addr.is_empty():
		show_status("Enter the host's address first")
		return
	join_requested.emit(_name.text, addr, _port_value())


func _port_value() -> int:
	return int(_port.text) if _port.text.is_valid_int() else NetSession.DEFAULT_PORT


## The shared squad: one capsule per soldier slot (4 in all), in the colour of the player who
## commands it; empty slots stay dark.
class SquadMeter extends Control:
	const SEG := Vector2(26, 8)
	const GAP := 4.0
	var cols: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(MatchConfig.MAX_SQUAD * SEG.x + (MatchConfig.MAX_SQUAD - 1) * GAP, SEG.y + 6)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_colors(c: Array) -> void:
		cols = c
		queue_redraw()

	func _draw() -> void:
		var y := (size.y - SEG.y) * 0.5
		for i in MatchConfig.MAX_SQUAD:
			var r := Rect2(i * (SEG.x + GAP), y, SEG.x, SEG.y)
			W.Draw.capsule(self, r, cols[i] if i < cols.size() else Styles.HP_OFF)


## Title backdrop: night blue deepening to the Bloom's teal on the right, where the Bloom's heart
## pulses with tendrils creeping out of it toward the menu, and slow spores drifting up.
class Backdrop extends Control:
	const COUNT := 70
	var _spores: Array = []
	var _t := 0.0
	var _veins: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in COUNT:
			_spores.append({"p": Vector2(rng.randf(), rng.randf()), "v": rng.randf_range(0.004, 0.016),
				"r": rng.randf_range(1.0, 3.2), "ph": rng.randf() * TAU, "a": rng.randf_range(0.15, 0.6),
				"hot": rng.randf() < 0.12})

	func _ready() -> void:
		var v := W.Veins.new("center", 0.55, 8, 11)
		v.origin = Vector2(0.78, 0.5)
		v.alpha = 0.55
		v.branching = 0.12
		v.start_radius = 150.0
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(v)
		_veins = v

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		for s in _spores:
			s.p.y -= s.v * delta
			s.p.x += sin(_t * 0.4 + s.ph) * 0.0006
			if s.p.y < -0.02:
				s.p.y = 1.02
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Styles.GROUND)
		# The Bloom's light: wide soft rings toward the heart on the right.
		var heart := Vector2(size.x * 0.78, size.y * 0.5)
		for i in 48:
			var k := float(i) / 48.0
			draw_circle(heart, size.y * (1.1 - k * 0.95), Color(Color("0f2a2e").lerp(Styles.TEAL, k * 0.2), 0.035 + k * 0.012))
		# Faint contour lines, like a survey of the colony.
		for i in 6:
			var pts := PackedVector2Array()
			var y0 := size.y * (0.12 + i * 0.16)
			for xi in 33:
				var x := size.x * xi / 32.0
				pts.append(Vector2(x, y0 + sin(xi * 0.45 + i * 1.7) * 14.0))
			draw_polyline(pts, Color(Styles.DIM, 0.05), 1.0, true)
		# The heart itself: an irregular glowing blob that breathes.
		var pulse := 1.0 + 0.03 * sin(_t * 1.1)
		var R := size.y * 0.15 * pulse
		W.Draw.glow(self, heart, R * 3.0, Styles.TEAL, 1.2)
		# A soft radial ramp from the dark rind to a pale hot core, each ring a little lumpy.
		var ramp := [Color("0a2a2a"), Color("127a6b"), Styles.TEAL, Color("b6fff1")]
		var rings := 22
		for i in rings:
			var k := float(i) / (rings - 1)
			var seg := k * (ramp.size() - 1)
			var col: Color = ramp[mini(int(seg), ramp.size() - 2)].lerp(ramp[mini(int(seg) + 1, ramp.size() - 1)], seg - int(seg))
			var poly := PackedVector2Array()
			var rk := 1.0 - k * 0.85
			for j in 56:
				var a := TAU * j / 56.0
				var wob := 1.0 + 0.08 * sin(a * 3.0 + _t * 0.5) * rk + 0.05 * sin(a * 5.0 - _t * 0.7) * rk
				poly.append(heart + Vector2(cos(a), sin(a)) * R * rk * wob + Vector2(-R * 0.15, -R * 0.12) * k)
			draw_colored_polygon(poly, Color(col, 0.55 + 0.45 * k))
		var spot := heart + Vector2(-R * 0.1, -R * 0.2)
		W.Draw.glow(self, spot, R * 0.5, Color("ff5fa2"), 0.6)
		for s in _spores:
			var p: Vector2 = s.p * size
			var a: float = s.a * (0.6 + 0.4 * sin(_t * 1.3 + s.ph))
			var c: Color = Styles.DANGER if s.hot else Styles.TEAL
			draw_circle(p, s.r * 2.6, Color(c, a * 0.12))
			draw_circle(p, s.r, Color(c, a))
		# Vignette.
		for i in 12:
			var w := 30.0 + i * 18.0
			draw_rect(r.grow(-i * 6.0), Color(0, 0, 0, 0.03), false, w)
