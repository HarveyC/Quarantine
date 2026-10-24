extends Node
## Autoload "Platform": the storefront layer. With the GodotSteam GDExtension installed and Steam
## running it starts Steam and provides lobbies (through NetSession.host_steam/join_steam),
## invites and join-from-friends-list, rich presence, achievements and stats, and Steam Cloud
## saves. Without it (CI, itch/zip builds, `-- --no-steam`) every call is a harmless no-op and the
## game plays over ENet as before. Crash reports work either way.
##
## Steam's singleton is reached through Engine.get_singleton and called dynamically, so this file
## parses and runs on builds that don't have GodotSteam at all.

## A friend picked "Join game" in Steam or accepted an invite: join this lobby.
signal lobby_join_requested(lobby_id: int)

## Valve's test app (Spacewar) until Carriers has its own; set carriers/steam/app_id to change.
const DEV_APP_ID := 480
const CLOUD_PUSH_SECONDS := 10.0

## The GodotSteam singleton once Steam is up, else null. Untyped: methods resolve at runtime.
var steam = null
## Why Steam isn't available, for the title screen and logs ("" when it is).
var steam_status := "Steam not installed in this build"
var cloud: CloudSync
var crash: CrashReporter
## Path of a report about the previous session crashing, or "".
var crash_report := ""
var _launch_lobby := 0
var _cloud_timer := 0.0
var _presence := {}
## The Achievements class once bound (null until meta progression lands).
var achievements: Script


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	crash = CrashReporter.new()
	crash_report = crash.start()
	if crash_report != "":
		print("[platform] the last session didn't exit cleanly; report: ", ProjectSettings.globalize_path(crash_report))
		_upload_crash(crash_report)
	if OS.get_cmdline_user_args().has("--no-steam"):
		steam_status = "Steam turned off (--no-steam)"
	elif Engine.has_singleton("Steam"):
		init_steam(Engine.get_singleton("Steam"), app_id())
	_launch_lobby = launch_lobby(OS.get_cmdline_args())


func _exit_tree() -> void:
	if steam != null:
		cloud.push()
		if steam.has_method("steamShutdown"):
			steam.steamShutdown()
	if crash != null:
		crash.stop()


func _process(delta: float) -> void:
	if steam == null:
		return
	steam.run_callbacks()
	_cloud_timer += delta
	if _cloud_timer >= CLOUD_PUSH_SECONDS:
		_cloud_timer = 0.0
		cloud.push()


static func app_id() -> int:
	return int(ProjectSettings.get_setting("carriers/steam/app_id", DEV_APP_ID))


## Starts Steam through `s` (the GodotSteam singleton, or a test fake). True when it's up.
func init_steam(s, id: int) -> bool:
	var res: Dictionary = s.steamInitEx(id, false) if s.has_method("steamInitEx") else {"status": 0 if s.steamInit() else 1}
	if int(res.get("status", 1)) != 0:
		steam_status = "Steam isn't running (%s)" % res.get("verbal", "init failed")
		print("[platform] ", steam_status)
		return false
	steam = s
	steam_status = ""
	print("[platform] Steam up: app %d, user %s" % [id, steam.getPersonaName()])
	steam.connect("join_requested", _on_join_requested)
	if steam.has_signal("join_game_requested"):
		steam.connect("join_game_requested", _on_join_game_requested)
	cloud = CloudSync.new(steam)
	var pulled := cloud.pull()
	if not pulled.is_empty():
		print("[platform] took newer saves from Steam Cloud: ", pulled)
	bind_achievements()
	set_presence("menu")
	return true


func steam_ready() -> bool:
	return steam != null and SteamTransport.available()


## The Steam name, or "" without Steam (the menu falls back to the OS user name).
func player_name() -> String:
	return steam.getPersonaName() if steam != null else ""


# --- joining from Steam -----------------------------------------------------------

## A lobby given on the command line (Steam launches us with `+connect_lobby <id>` when a friend
## joins from the friends list while the game isn't running). Returned once.
func take_launch_lobby() -> int:
	var id := _launch_lobby
	_launch_lobby = 0
	return id


static func launch_lobby(args: PackedStringArray) -> int:
	var i := args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		return int(args[i + 1])
	return 0


func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	lobby_join_requested.emit(lobby_id)


## "Join game" from the friends list while we're running, via the rich presence connect string.
func _on_join_game_requested(_friend_id: int, connect: String) -> void:
	var id := launch_lobby(connect.split(" ", false))
	if id != 0:
		lobby_join_requested.emit(id)


# --- rich presence ------------------------------------------------------------------

## Shows what we're doing on the friends list. `token` picks a line from the rich presence
## localization file uploaded to Steamworks (steam/rich_presence.vdf): menu, lobby, run, fight.
## With a lobby, friends get a "Join game" button.
func set_presence(token: String, vars: Dictionary = {}, lobby_id: int = 0, size: int = 0) -> void:
	var want := {"steam_display": "#" + token.capitalize().replace(" ", "")}
	for k in vars:
		want[k] = str(vars[k])
	if lobby_id != 0:
		want["connect"] = "+connect_lobby %d" % lobby_id
		want["steam_player_group"] = str(lobby_id)
		want["steam_player_group_size"] = str(size)
	if want == _presence or steam == null:
		return
	steam.clearRichPresence()
	for k in want:
		steam.setRichPresence(k, want[k])
	_presence = want


## Picks the presence for whatever `session` is doing (null = title screen).
func update_presence(session: Node) -> void:
	if steam == null:
		return
	var lobby := 0
	var size := 0
	if session is NetSession:
		lobby = (session as NetSession).steam_lobby()
		size = (session as NetSession).lobby.size()
	var run: RunState = session.get("run") if session != null else null
	if session == null:
		set_presence("menu")
	elif run != null:
		set_presence("fight" if run.phase == RunState.Phase.FIGHT else "run", {"act": run.act, "row": run.row}, lobby, size)
	elif session is NetSession and not (session as NetSession).in_match:
		set_presence("lobby", {"players": size}, lobby, size)
	else:
		set_presence("fight", {"act": 1, "row": 1}, lobby, size)


# --- achievements and stats -----------------------------------------------------

## Mirrors the game's own achievements (class Achievements, from meta progression) to Steam.
## Bound late by class name so this works before and after that module exists. Steam names are
## the ids in upper case (first_win -> FIRST_WIN); stats likewise.
func bind_achievements(source: Script = null) -> void:
	achievements = source if source != null else RunHooks.script_of("Achievements")
	if steam == null or achievements == null:
		return
	for id in achievements.call("unlocked"):
		steam.setAchievement(steam_name(id))
	achievements.call("on_unlocked", _on_achievement)
	push_stats()


func _on_achievement(id: String) -> void:
	if steam == null:
		return
	steam.setAchievement(steam_name(id))
	push_stats()


func push_stats() -> void:
	if steam == null:
		return
	if achievements != null and achievements.has_method("stats"):
		var stats: Dictionary = achievements.call("stats")
		for k in stats:
			steam.setStatInt(steam_name(k), int(stats[k]))
	steam.storeStats()


static func steam_name(id: String) -> String:
	return id.to_upper()


# --- crash reports ----------------------------------------------------------------

func _upload_crash(path: String) -> void:
	var url := CrashReporter.upload_url()
	if url == "":
		return
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		print("[platform] crash report upload: HTTP %d" % code)
		req.queue_free())
	req.request(url, ["Content-Type: text/plain"], HTTPClient.METHOD_POST, FileAccess.get_file_as_string(path))
