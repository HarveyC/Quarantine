extends Control
## Title screen and lobby: Host, Join by address, or Local hot-seat.
## Emits requests; App owns the sessions and the mission view.

signal host_requested(name: String, port: int)
signal join_requested(name: String, address: String, port: int)
signal local_requested(players: int)
signal run_requested(players: int)
signal continue_requested
signal start_requested
signal start_run_requested
signal leave_requested
signal class_picked(kind: String)
## Host a friends-only Steam lobby (only offered when Steam is running).
signal steam_host_requested(name: String)
## Open the Steam overlay to invite friends to our lobby.
signal steam_invite_requested

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")

var _name: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: Label
var _menu_box: VBoxContainer
var _lobby_box: VBoxContainer
var _lobby_title: Label
var _lobby_list: VBoxContainer
var _lobby_hint: Label
var _class_row: HBoxContainer
var _start_btn: Button
var _start_run_btn: Button
var _continue_btn: Button
var _lobby_continue: CheckBox
var _steam_host_btn: Button
var _invite_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Styles.make_theme()
	var bg := ColorRect.new()
	bg.color = Styles.BG.darkened(0.3)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_theme_stylebox_override("panel", Styles.panel_box(Styles.BG, Palette.TEAL.darkened(0.5)))
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	root.add_child(Styles.label("CARRIERS", 40, Palette.TEAL))
	root.add_child(Styles.label("Co-op tactics in the infected zone", 16, Styles.TEXT))
	_build_menu(root)
	_build_lobby(root)
	_status = Styles.label("", 15, Palette.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)
	show_menu()


func _build_menu(root: VBoxContainer) -> void:
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	root.add_child(_menu_box)
	var steam_name: String = _platform().player_name() if _platform() != null else ""
	_name = _field(_menu_box, "Your name", steam_name if steam_name != "" else (OS.get_environment("USER").capitalize() if OS.has_environment("USER") else "Player"))
	_continue_btn = _button(_menu_box, "Continue run")
	_continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	var solo_btn := _button(_menu_box, "Solo run")
	solo_btn.pressed.connect(func() -> void: run_requested.emit(1))
	_steam_host_btn = _button(_menu_box, "Host on Steam (invite friends)")
	_steam_host_btn.pressed.connect(func() -> void: steam_host_requested.emit(_name.text))
	_steam_host_btn.visible = _platform() != null and _platform().steam_ready()
	var host_btn := _button(_menu_box, "Host online game (by address)")
	host_btn.pressed.connect(func() -> void: host_requested.emit(_name.text, _port_value()))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_menu_box.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "Host address, e.g. 192.168.1.20"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _emit_join())
	join_row.add_child(_address)
	var join_btn := _button(join_row, "Join")
	join_btn.custom_minimum_size.x = 100
	join_btn.pressed.connect(_emit_join)
	_port = _field(_menu_box, "Port", str(NetSession.DEFAULT_PORT))
	var hot_run := _button(_menu_box, "Hot-seat run (2 players, one screen)")
	hot_run.pressed.connect(func() -> void: run_requested.emit(2))
	var local_btn := _button(_menu_box, "Quick mission (hot-seat, no run)")
	local_btn.pressed.connect(func() -> void: local_requested.emit(2))
	var sound_btn := _button(_menu_box, "Sound")
	sound_btn.pressed.connect(func() -> void:
		var ss := get_node_or_null("/root/Soundscape")
		if ss != null:
			ss.toggle_settings())


func _build_lobby(root: VBoxContainer) -> void:
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	root.add_child(_lobby_box)
	_lobby_title = Styles.label("LOBBY", 22, Styles.TEXT)
	_lobby_box.add_child(_lobby_title)
	_lobby_list = VBoxContainer.new()
	_lobby_box.add_child(_lobby_list)
	_lobby_box.add_child(Styles.label("Your soldier", 14, Styles.MUTED))
	_class_row = HBoxContainer.new()
	_class_row.add_theme_constant_override("separation", 6)
	_lobby_box.add_child(_class_row)
	_lobby_hint = Styles.label("", 14, Styles.MUTED)
	_lobby_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lobby_box.add_child(_lobby_hint)
	_lobby_continue = CheckBox.new()
	_lobby_continue.text = "Continue the saved run"
	_lobby_continue.focus_mode = Control.FOCUS_NONE
	_lobby_box.add_child(_lobby_continue)
	_invite_btn = _button(_lobby_box, "Invite Steam friends")
	_invite_btn.pressed.connect(func() -> void: steam_invite_requested.emit())
	_start_run_btn = _button(_lobby_box, "Start run")
	_start_run_btn.pressed.connect(func() -> void: start_run_requested.emit())
	_start_btn = _button(_lobby_box, "Quick mission (no run)")
	_start_btn.pressed.connect(func() -> void: start_requested.emit())
	var leave := _button(_lobby_box, "Leave")
	leave.pressed.connect(func() -> void: leave_requested.emit())


func show_menu(message: String = "") -> void:
	var saved := RunSave.read() if RunSave.exists() else null
	_continue_btn.visible = saved != null
	if saved != null:
		_continue_btn.text = "Continue run  (%s)" % RunSave.summary(saved)
	_menu_box.visible = true
	_lobby_box.visible = false
	_status.text = message


func show_status(message: String) -> void:
	_status.text = message


## Shows the lobby for `net`. Called again whenever the lobby changes.
func show_lobby(net: NetSession) -> void:
	_menu_box.visible = false
	_lobby_box.visible = true
	_status.text = ""
	for c in _lobby_list.get_children():
		c.queue_free()
	var entries := net.lobby.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.player < b.player)
	# Who plays what if the match started now (a solo host gets the full squad of 4).
	var plan := MatchConfig.squad_plan(net.lobby.size(), net.class_picks())
	var mine := ""
	for e in entries:
		var you := " (you)" if e.player == net.my_player else ""
		var kinds := PackedStringArray()
		for sq in plan:
			if sq.player == e.player:
				kinds.append(UnitData.SOLDIERS[sq.kind].name)
				if e.player == net.my_player:
					mine = sq.kind
		_lobby_list.add_child(Styles.label("Player %d  ·  %s%s  ·  %s" % [e.player + 1, e.name, you, ", ".join(kinds)], 18, Palette.player_ui(e.player)))
	for c in _class_row.get_children():
		c.queue_free()
	_class_row.visible = net.lobby.size() > 1
	for k in Progression.unlocked_classes(Profile.meta()):
		var b := Button.new()
		b.text = UnitData.SOLDIERS[k].name
		b.toggle_mode = true
		b.button_pressed = k == mine
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: class_picked.emit(k))
		_class_row.add_child(b)
	var split := "solo runs field all 4 soldiers" if net.lobby.size() == 1 else "one soldier each"
	_invite_btn.visible = net.via_steam()
	_invite_btn.disabled = net.steam_lobby() == 0
	if net.via_steam():
		_lobby_hint.text = ("Invite friends, or they can pick Join game on you in their Steam friends list. Squad: %s." if net.is_host
			else "Waiting for the host to start. Squad: %s.") % split
	elif net.is_host:
		var addrs := NetSession.local_addresses()
		_lobby_hint.text = "Friends join with your address: %s (port %d). Over the internet they need your public IP and port %d forwarded, or a shared LAN tool like Tailscale.\nSquad: %s." % [
			", ".join(addrs) if not addrs.is_empty() else "?", int(_port_value()), int(_port_value()), split]
	else:
		_lobby_hint.text = "Waiting for the host to start. Squad: %s." % split
	_start_btn.visible = net.is_host
	_start_run_btn.visible = net.is_host
	_lobby_continue.visible = net.is_host and RunSave.exists()
	_lobby_title.text = "LOBBY  (%d/%d)" % [net.lobby.size(), NetSession.MAX_PLAYERS]


## Host: whether to continue the saved run instead of starting a new one.
func continue_saved() -> bool:
	return _lobby_continue.visible and _lobby_continue.button_pressed


func _platform() -> Node:
	return get_node_or_null("/root/Platform")


func _emit_join() -> void:
	var addr := _address.text.strip_edges()
	if addr.is_empty():
		show_status("Enter the host's address first")
		return
	join_requested.emit(_name.text, addr, _port_value())


func _port_value() -> int:
	return int(_port.text) if _port.text.is_valid_int() else NetSession.DEFAULT_PORT


func _field(parent: Control, label: String, value: String) -> LineEdit:
	parent.add_child(Styles.label(label, 14, Styles.MUTED))
	var e := LineEdit.new()
	e.text = value
	parent.add_child(e)
	return e


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", 18)
	parent.add_child(b)
	return b
