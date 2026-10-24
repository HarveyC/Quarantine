extends Control
## Title screen and lobby. The title is a wordmark over a slow spore backdrop with one column of
## icon buttons (Continue, Solo, Host, Join, Hot-seat, Quick mission, Settings, Quit); Join opens
## a small address panel beside the column. The lobby shows four player slots with each player's
## colour, name and soldier, the class tiles, and the host's address as a copyable chip.
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
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const Feel := preload("res://ui/ui_feel.gd")
const FieldHQ := preload("res://ui/meta/field_hq.gd")
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
var _class_title: Label
var _class_row: HBoxContainer
var _address_row: HBoxContainer
var _lobby_hint: Label
var _solo_btn: Button
var _start_btn: Button
var _start_run_btn: Button
var _continue_btn: Button
var _continue_sub: Label
var _lobby_continue: CheckBox
var _steam_host_btn: Button
var _invite_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Styles.make_theme()
	var bg := Backdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 64)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var root := Styles.vbox(26)
	margin.add_child(root)
	root.add_child(_wordmark())
	var body := Control.new()
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
	var kicker := Styles.hbox(10)
	var line := ColorRect.new()
	line.color = Styles.AMBER
	line.custom_minimum_size = Vector2(36, 2)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker.add_child(line)
	kicker.add_child(Styles.caps("Lantern Company · Harrow colony", 15, Styles.DIM))
	box.add_child(kicker)
	var title := Styles.caps("Carriers", 112, Styles.TEXT)
	(title.get_theme_font("font") as FontVariation).spacing_glyph = 10
	title.add_theme_constant_override("outline_size", 0)
	box.add_child(title)
	box.add_child(Styles.label("Co-op tactics. The Bloom is in your blood; push to the Source before it wins.", 17, Styles.DIM))
	return box


# --- title -------------------------------------------------------------------------------------

func _build_menu(body: Control) -> void:
	var row := Styles.hbox(40)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_box = row
	body.add_child(row)
	var col := Styles.vbox(10)
	col.custom_minimum_size.x = COLUMN_W
	row.add_child(col)
	_continue_btn = _menu_button(col, "Continue run", "continue", func() -> void: continue_requested.emit(), "primary")
	_continue_sub = Styles.mono("", 11, Color(Styles.AMBER, 0.7))
	col.add_child(_continue_sub)
	_solo_btn = _menu_button(col, "Solo run", "solo", func() -> void: run_requested.emit(1))
	_solo_btn.tooltip_text = "One soldier, one player. A full three-act run."
	_steam_host_btn = _menu_button(col, "Host on Steam", "coop", func() -> void: steam_host_requested.emit(_name.text))
	_steam_host_btn.tooltip_text = "A friends-only lobby. Invite friends through Steam."
	_steam_host_btn.visible = _platform() != null and _platform().steam_ready()
	var host := _menu_button(col, "Host by address", "online", func() -> void: host_requested.emit(_name.text, _port_value()))
	host.tooltip_text = "Open a lobby for up to 4 players. Friends join with your address."
	var join := _menu_button(col, "Join game", "join", _toggle_join)
	join.tooltip_text = "Connect to a friend's lobby by address."
	var hot := _menu_button(col, "Hot-seat run", "hotseat", func() -> void: run_requested.emit(2))
	hot.tooltip_text = "Two players, one screen, one soldier each."
	var quick := _menu_button(col, "Quick mission", "quick", func() -> void: local_requested.emit(2))
	quick.tooltip_text = "A single hot-seat fight, no run."
	col.add_child(_gap(10))
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
	cs.set_look(Color(0.043, 0.055, 0.047, 0.8), Styles.BORDER, Styles.AMBER, false)
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
	var b := Styles.icon_button(text, icon, kind, 19 if kind != "ghost" else 17, 54.0 if kind != "ghost" else 42.0)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _toggle_join() -> void:
	_join_panel.visible = not _join_panel.visible
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
	head.add_child(Styles.caps("Lobby", 34))
	_lobby_pips = W.Pips.new(Vector2(18, 6))
	_lobby_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_lobby_pips)
	_lobby_count = Styles.mono("", 15, Styles.DIM)
	head.add_child(_lobby_count)
	head.add_child(Styles.spacer())
	_address_row = Styles.hbox(10)
	head.add_child(_address_row)
	v.add_child(head)
	_slots = Styles.hbox(14)
	v.add_child(_slots)
	_class_title = Styles.caps("Your soldier", 14, Styles.DIM)
	v.add_child(_class_title)
	_class_row = Styles.hbox(10)
	v.add_child(_class_row)
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
	var leave := Styles.icon_button("Leave", "leave", "ghost", 17, 50)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	bar.add_child(leave)
	_start_btn = Styles.icon_button("Quick mission", "quick", "secondary", 18, 54)
	_start_btn.tooltip_text = "A single fight, no run."
	_start_btn.pressed.connect(func() -> void: start_requested.emit())
	bar.add_child(_start_btn)
	_start_run_btn = Styles.icon_button("Start run", "play", "primary", 20, 54)
	_start_run_btn.custom_minimum_size.x = 260
	_start_run_btn.pressed.connect(func() -> void: start_run_requested.emit())
	bar.add_child(_start_run_btn)
	v.add_child(bar)


func show_menu(message: String = "") -> void:
	var saved := RunSave.read() if RunSave.exists() else null
	_continue_btn.visible = saved != null
	_continue_sub.visible = saved != null
	if saved != null:
		_continue_sub.text = RunSave.summary(saved).to_upper()
	_solo_btn.text = "SOLO RUN" + _severity_tag()
	_menu_box.visible = true
	_lobby_box.visible = false
	_join_panel.visible = false
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
	return "  ·  SEVERITY %d" % n if n > 0 else ""


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
	var first := not _lobby_box.visible
	_menu_box.visible = false
	_lobby_box.visible = true
	_status.visible = false
	var entries := net.lobby.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.player < b.player)
	var plan := MatchConfig.squad_plan(net.lobby.size(), net.class_picks())
	var mine := ""
	for sq in plan:
		if sq.player == net.my_player:
			mine = sq.kind
	_lobby_pips.set_values(NetSession.MAX_PLAYERS, net.lobby.size(), 0, Styles.AMBER)
	_lobby_count.text = "%d / %d" % [net.lobby.size(), NetSession.MAX_PLAYERS]
	NodeUi.clear(_slots)
	for i in NetSession.MAX_PLAYERS:
		var e: Dictionary = entries[i] if i < entries.size() else {}
		var kinds: Array = []
		if not e.is_empty():
			for sq in plan:
				if sq.player == e.player:
					kinds.append(sq.kind)
		_slots.add_child(_slot(e, kinds, net))
	NodeUi.clear(_class_row)
	var pick := net.lobby.size() > 1
	_class_row.visible = pick
	_class_title.visible = pick
	for k in Progression.unlocked_classes(Profile.meta()):
		_class_row.add_child(_class_tile(k, k == mine))
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
			copy.text = "COPIED")
		_address_row.add_child(copy)
		_lobby_hint.text = "Each player brings one soldier."
	else:
		_lobby_hint.text = "Waiting for the host to start."
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
	_start_run_btn.text = "START RUN" + _severity_tag()
	_lobby_continue.visible = net.is_host and RunSave.exists()
	if first and is_inside_tree():
		Feel.deal(_slots.get_children(), 0.06)
		Feel.sound("open")


## One of the four lobby slots: the player's colour along the top, name, tags and soldier.
func _slot(e: Dictionary, kinds: Array, net: NetSession) -> Control:
	var f := W.Frame.new(Vector4(18, 16, 18, 16))
	f.custom_minimum_size = Vector2(250, 190)
	if e.is_empty():
		f.set_look(Color(0.03, 0.04, 0.035, 0.55), Color("1f2620"), Styles.AMBER, false)
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
	var you: bool = e.player == net.my_player
	f.set_look(Color(0.05, 0.065, 0.055, 0.92), Color(col, 0.55) if you else Styles.BORDER, Styles.AMBER, you)
	f.draw.connect(func() -> void: f.draw_rect(Rect2(0, 0, f.size.x, 3), col))
	var v := Styles.vbox(10)
	f.add_child(v)
	var top := Styles.hbox(8)
	top.add_child(Styles.caps("P%d" % (e.player + 1), 14, col))
	top.add_child(Styles.spacer())
	if e.player == 0:
		top.add_child(W.chip("Host", Styles.DIM, false, 11))
	if you:
		top.add_child(W.chip("You", col, true, 11))
	v.add_child(top)
	v.add_child(Styles.caps(str(e.name), 26))
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grow)
	for k in kinds:
		var r := Styles.hbox(10)
		r.add_child(W.glyph(k, col, 40.0))
		r.add_child(Styles.caps(UnitData.SOLDIERS[k].name, 17, Styles.TEXT))
		v.add_child(r)
	return f


## A class tile in "Your soldier": the class icon over its name; amber when picked.
func _class_tile(k: String, on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(118, 104)
	b.tooltip_text = str(UnitData.SOLDIERS[k].get("blurb", UnitData.SOLDIERS[k].name))
	Styles.style_button(b, "secondary")
	var v := Styles.vbox(8)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := W.Icon.new(Icons.for_class(k), Styles.AMBER if on else Styles.DIM, 34, 1.9)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Styles.caps(UnitData.SOLDIERS[k].name, 14, Styles.AMBER if on else Styles.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	b.pressed.connect(func() -> void:
		Feel.sound("pick")
		class_picked.emit(k))
	return b


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


## Title backdrop: a dark gradient, a faint survey grid, a lantern glow and slow teal spores.
class Backdrop extends Control:
	const COUNT := 70
	var _spores: Array = []
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in COUNT:
			_spores.append({"p": Vector2(rng.randf(), rng.randf()), "v": rng.randf_range(0.004, 0.016),
				"r": rng.randf_range(1.0, 3.2), "ph": rng.randf() * TAU, "a": rng.randf_range(0.15, 0.6)})

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
		draw_rect(r, Color("080a09"))
		# Vertical gradient bands toward a warm floor glow.
		var bands := 24
		for i in bands:
			var k := float(i) / bands
			var c := Color("0b0e0c").lerp(Color("141410"), k * k)
			draw_rect(Rect2(0, size.y * k, size.x, size.y / bands + 1), c)
		# Survey grid.
		var step := 64.0
		var gc := Color(1, 1, 1, 0.025)
		var x := fmod(size.x * 0.5, step)
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), gc, 1.0)
			x += step
		var y := fmod(size.y * 0.5, step)
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), gc, 1.0)
			y += step
		# Lantern glow and the shaft's teal light, far right.
		var glow := Vector2(size.x * 0.78, size.y * 0.62)
		for i in 10:
			var rr := size.y * (0.75 - i * 0.06)
			draw_circle(glow, rr, Color(Styles.TEAL, 0.012))
		var lamp := Vector2(size.x * 0.2, size.y * 0.1)
		for i in 8:
			draw_circle(lamp, size.y * (0.5 - i * 0.05), Color(Styles.AMBER, 0.008))
		for s in _spores:
			var p: Vector2 = s.p * size
			var a: float = s.a * (0.6 + 0.4 * sin(_t * 1.3 + s.ph))
			draw_circle(p, s.r * 2.6, Color(Styles.TEAL, a * 0.12))
			draw_circle(p, s.r, Color(Styles.TEAL, a))
		# Vignette.
		for i in 12:
			var w := 30.0 + i * 18.0
			draw_rect(r.grow(-i * 6.0), Color(0, 0, 0, 0.035), false, w)
