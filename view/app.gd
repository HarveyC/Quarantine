class_name App
extends Node
## Game root: title menu and lobby, the session (local or online), and the mission view.
##
## Command line (after `--`), for testing without clicking through the menu:
##   --host[=port]  --join=address[:port]  --name=Name  --autostart=N (host starts at N players)
##   --autoplay / --screenshot=... with neither host nor join start a local hot-seat match directly.
##   --run=N starts a local run for N players (1 = solo); --autostart-run makes --autostart start a run.
##   --drop-client-at=N (host) cuts the first client off after action N, to test reconnecting.

const MISSION := preload("res://scenes/main.tscn")
const MainMenu := preload("res://ui/main_menu.gd")
## Longest a finished fight waits on its debrief before moving on anyway.
const DEBRIEF_MAX := 20.0
const FADE_OUT := 0.35
const FADE_IN := 0.5

var net: NetSession
var session: Node      # LocalSession or NetSession
var view: MissionView
var menu: MainMenu
var run_view: RunView
var _run_layer: CanvasLayer
var _closing_mission := false
var _close_gen := 0
var _fade: ColorRect
var _fade_tween: Tween
var _autostart_run := false
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
	net.run_changed.connect(func(_r: RunState) -> void: _update_screens())
	net.rejected.connect(func(reason: String) -> void: if view: view.hud.toast(reason))
	_run_layer = CanvasLayer.new()
	_run_layer.layer = 5
	add_child(_run_layer)
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)
	menu = MainMenu.new()
	_menu_layer.add_child(menu)
	# Black cover for the cut from a finished fight to the run view.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(_fade)
	menu.host_requested.connect(_host)
	menu.join_requested.connect(_join)
	menu.local_requested.connect(_local)
	menu.start_requested.connect(net.start_match)
	menu.run_requested.connect(_local_run)
	menu.continue_requested.connect(_continue_run)
	menu.start_run_requested.connect(_start_net_run)
	menu.leave_requested.connect(_leave)
	menu.class_picked.connect(net.pick_class)
	menu.steam_host_requested.connect(_host_steam)
	menu.steam_invite_requested.connect(func() -> void:
		if not net.invite_friends():
			menu.show_status("The Steam overlay isn't available. Friends can still pick Join game on you in their friends list."))
	net.reconnecting.connect(func(attempt: int, of: int) -> void:
		if view: view.hud.toast("Connection lost, reconnecting (%d/%d)..." % [attempt, of]))
	net.reconnected.connect(func() -> void: if view: view.hud.toast("Reconnected"))
	var plat := _platform()
	if plat != null:
		plat.lobby_join_requested.connect(_join_steam)
		if plat.crash_report != "":
			menu.show_status("Carriers closed unexpectedly last time. A crash report was saved to %s" % ProjectSettings.globalize_path(plat.crash_report))
	_handle_args()
	var launch_lobby: int = plat.take_launch_lobby() if plat != null else 0
	if launch_lobby != 0:
		_join_steam.call_deferred(launch_lobby)
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
	_autostart_run = args.has("autostart-run")
	net.drop_client_at = int(args.get("drop-client-at", "-1"))
	if args.has("host"):
		_host(nm, int(args.host) if args.host.is_valid_int() else NetSession.DEFAULT_PORT)
	elif args.has("join"):
		var parts: PackedStringArray = args.join.split(":")
		var port := int(parts[1]) if parts.size() > 1 else NetSession.DEFAULT_PORT
		_join(nm, parts[0], port)
		if args.has("double-join"):   # test aid: an impatient second click on Join
			_join(nm, parts[0], port)
	elif args.has("run"):
		_local_run(int(args.run) if args.run.is_valid_int() else 1, int(args.get("seed", "0")))
	elif args.has("lineup") or args.has("lineup-mode"):
		_menu_layer.visible = false
		var lineup := preload("res://view/lineup.gd").new()
		add_child(lineup)
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


func _host_steam(nm: String) -> void:
	var plat := _platform()
	if plat == null or not plat.steam_ready():
		menu.show_status("Steam isn't available: %s" % (plat.steam_status if plat else "not installed"))
		return
	var err := net.host_steam(plat.steam, nm)
	if err != "":
		menu.show_status(err)
		return
	session = net
	menu.show_lobby(net)


## Joins a friend's Steam lobby (invite accepted, Join game in the friends list, +connect_lobby).
func _join_steam(lobby_id: int) -> void:
	var plat := _platform()
	if plat == null or not plat.steam_ready():
		return
	if session != null:
		_leave()
	var err := net.join_steam(plat.steam, lobby_id, plat.player_name())
	if err != "":
		menu.show_status(err)
		return
	session = net
	menu.show_status("Joining your friend's game on Steam...")


func _platform() -> Node:
	return get_node_or_null("/root/Platform")


func _presence() -> void:
	var plat := _platform()
	if plat != null:
		plat.update_presence(session)


func _local(players: int) -> void:
	var local := LocalSession.new()
	local.name = "Local"
	add_child(local)
	session = local
	local.match_started.connect(func(s: GameState) -> void: _show_mission(local, s, true))
	local.start_new(players)


func _make_local() -> LocalSession:
	var local := LocalSession.new()
	local.name = "Local"
	add_child(local)
	session = local
	local.match_started.connect(func(s: GameState) -> void: _show_mission(local, s, true))
	local.resynced.connect(func(s: GameState) -> void: _show_mission(local, s, false))
	local.run_changed.connect(func(_r: RunState) -> void: _update_screens())
	local.rejected.connect(func(reason: String) -> void: if view: view.hud.toast(reason))
	return local


## Solo (1) or hot-seat run on this machine: no lobby, no network.
func _local_run(players: int, seed: int = 0) -> void:
	_make_local().start_run(players, seed)


func _continue_run() -> void:
	var saved := RunSave.read()
	if saved == null:
		menu.show_status("The saved run could not be loaded")
		return
	_make_local().resume_run(saved)


func _start_net_run() -> void:
	if menu.continue_saved():
		net.resume = RunSave.read()
	net.start_run()


## Shows the run view between fights and the mission view during one. When a fight ends the
## mission stays up until its last beats and the debrief have played (or the player skips), then
## fades into the run view.
func _update_screens() -> void:
	var run: RunState = session.get("run") if session != null else null
	if run == null:
		if run_view != null:
			run_view.visible = false
		return
	var fighting := run.phase == RunState.Phase.FIGHT
	if view != null and (not fighting or view.state != session.state):
		if not _closing_mission:
			_closing_mission = true
			_wait_for_debrief()
		return
	if fighting and view != null:
		if run_view != null:
			run_view.visible = false
		return
	if run_view == null:
		run_view = RunView.new()
		run_view.autoplay = OS.get_cmdline_user_args().has("--autoplay")
		run_view.leave_requested.connect(_leave)
		_run_layer.add_child(run_view)
	if run_view.run != run:
		run_view.setup(session)
	run_view.visible = true
	run_view.refresh()
	_menu_layer.visible = false
	_presence()


func _wait_for_debrief() -> void:
	_close_gen += 1
	var gen := _close_gen
	var finish := func() -> void: _finish_mission(gen)
	if OS.get_cmdline_user_args().has("--autoplay"):
		get_tree().create_timer(0.5).timeout.connect(finish)
		return
	if view.debrief_done:
		finish.call_deferred()
		return
	view.debrief_finished.connect(finish, CONNECT_ONE_SHOT)
	# A fight that ends without a debrief (a new fight replaced it, a resync) still moves on.
	get_tree().create_timer(DEBRIEF_MAX).timeout.connect(finish)


func _finish_mission(gen: int) -> void:
	if gen != _close_gen or not _closing_mission:
		return
	_close_gen += 1
	var swap := func() -> void:
		_closing_mission = false
		if view != null and (session == null or session.get("run") == null or session.run.phase != RunState.Phase.FIGHT or view.state != session.state):
			_close_view()
		_update_screens()
	if OS.get_cmdline_user_args().has("--autoplay"):
		swap.call()
		return
	_fade_to(1.0, FADE_OUT, func() -> void:
		swap.call()
		_fade_to(0.0, FADE_IN))


func _fade_to(alpha: float, secs: float, then: Callable = Callable()) -> void:
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, secs)
	if then.is_valid():
		_fade_tween.tween_callback(then)


func _on_lobby_changed() -> void:
	_presence()
	if view == null and session == net:
		menu.show_lobby(net)
	elif view != null:
		view.hud.refresh()
	if net.is_host and not net.in_match and _autostart > 0 and net.lobby.size() >= _autostart and not _autostart_armed:
		# Short grace period so late or duplicate connections land before the squad is split.
		_autostart_armed = true
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if not net.in_match:
				if _autostart_run:
					net.start_run()
				else:
					net.start_match())


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
	_presence()
	if run_view != null:
		run_view.visible = false


func _on_disconnected(reason: String) -> void:
	_reset_fade()
	_close_view()
	_close_run_view()
	session = null
	menu.show_menu(reason)
	_menu_layer.visible = true
	_presence()
	if OS.get_cmdline_user_args().has("--autoplay"):
		print("[autoplay] disconnected: ", reason)
		get_tree().quit(0)


func _leave() -> void:
	_reset_fade()
	if session == net:
		net.leave()
	elif session != null:
		session.queue_free()
	session = null
	_close_view()
	_close_run_view()
	menu.show_menu()
	_menu_layer.visible = true
	_presence()


func _reset_fade() -> void:
	_closing_mission = false
	_close_gen += 1
	if _fade_tween != null:
		_fade_tween.kill()
	_fade.color.a = 0.0


func _close_run_view() -> void:
	if run_view != null:
		run_view.queue_free()
		run_view = null


func _close_view() -> void:
	if view != null:
		view.queue_free()
		view = null
