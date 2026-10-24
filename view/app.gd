class_name App
extends Node
## Game root: title menu and lobby, the session (local or online), and the mission view.
##
## Command line (after `--`), for testing without clicking through the menu:
##   --host[=port]  --join=address[:port]  --name=Name  --autostart=N (host starts at N players)
##   --autoplay / --screenshot=... with neither host nor join start a local hot-seat match directly.

const MISSION := preload("res://scenes/main.tscn")
const MainMenu := preload("res://ui/main_menu.gd")

var net: NetSession
var session: Node      # LocalSession or NetSession
var view: MissionView
var menu: MainMenu
var _autostart := 0
var _autostart_armed := false
var _menu_layer: CanvasLayer


func _ready() -> void:
	name = "App"
	net = NetSession.new()
	net.name = "Net"
	add_child(net)
	net.lobby_changed.connect(_on_lobby_changed)
	net.match_started.connect(func(s: GameState) -> void: _show_mission(net, s, true))
	net.resynced.connect(func(s: GameState) -> void: _show_mission(net, s, false))
	net.disconnected.connect(_on_disconnected)
	net.rejected.connect(func(reason: String) -> void: if view: view.hud.toast(reason))
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)
	menu = MainMenu.new()
	_menu_layer.add_child(menu)
	menu.host_requested.connect(_host)
	menu.join_requested.connect(_join)
	menu.local_requested.connect(_local)
	menu.start_requested.connect(net.start_match)
	menu.leave_requested.connect(_leave)
	_handle_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menu-shot="):
			_menu_shot = a.trim_prefix("--menu-shot=")


var _menu_shot := ""
var _frames := 0


func _process(_d: float) -> void:
	if _menu_shot == "":
		return
	_frames += 1
	if _frames == 20 and menu != null:
		_host("Harvey", NetSession.DEFAULT_PORT)   # show the lobby view
	elif _frames == 80:
		get_viewport().get_texture().get_image().save_png(_menu_shot)
		print("[menu-shot] saved ", _menu_shot)
		get_tree().quit(0)


func _handle_args() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var nm: String = args.get("name", "Player")
	_autostart = int(args.get("autostart", "0"))
	if args.has("host"):
		_host(nm, int(args.host) if args.host.is_valid_int() else NetSession.DEFAULT_PORT)
	elif args.has("join"):
		var parts: PackedStringArray = args.join.split(":")
		var port := int(parts[1]) if parts.size() > 1 else NetSession.DEFAULT_PORT
		_join(nm, parts[0], port)
		if args.has("double-join"):   # test aid: an impatient second click on Join
			_join(nm, parts[0], port)
	elif args.has("autoplay") or args.has("screenshot"):
		_local(2)


func _host(nm: String, port: int) -> void:
	var err := net.host(port, nm)
	if err != "":
		menu.show_status(err)
		return
	session = net
	menu.show_lobby(net)


func _join(nm: String, address: String, port: int) -> void:
	var err := net.join(address, port, nm)
	if err != "":
		menu.show_status(err)
		return
	session = net
	menu.show_status("Connecting to %s:%d..." % [address, port])


func _local(players: int) -> void:
	var local := LocalSession.new()
	local.name = "Local"
	add_child(local)
	session = local
	local.match_started.connect(func(s: GameState) -> void: _show_mission(local, s, true))
	local.start_new(players)


func _on_lobby_changed() -> void:
	if view == null and session == net:
		menu.show_lobby(net)
	elif view != null:
		view.hud.refresh()
	if net.is_host and not net.in_match and _autostart > 0 and net.lobby.size() >= _autostart and not _autostart_armed:
		# Short grace period so late or duplicate connections land before the squad is split.
		_autostart_armed = true
		get_tree().create_timer(2.0).timeout.connect(func() -> void: if not net.in_match: net.start_match())


func _show_mission(s: Node, state: GameState, begin: bool) -> void:
	if view == null:
		view = MISSION.instantiate()
		view.auto_start = false
		add_child(view)
	view.session = s
	if not view.left_match.is_connected(_leave):
		view.left_match.connect(_leave)
	view.start(state, begin)
	_menu_layer.visible = false


func _on_disconnected(reason: String) -> void:
	_close_view()
	session = null
	menu.show_menu(reason)
	_menu_layer.visible = true
	if OS.get_cmdline_user_args().has("--autoplay"):
		print("[autoplay] disconnected: ", reason)
		get_tree().quit(0)


func _leave() -> void:
	if session == net:
		net.leave()
	elif session != null:
		session.queue_free()
	session = null
	_close_view()
	menu.show_menu()
	_menu_layer.visible = true


func _close_view() -> void:
	if view != null:
		view.queue_free()
		view = null
