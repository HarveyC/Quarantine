extends TestCase
## Steam layer (Platform autoload, SteamTransport, CloudSync, CrashReporter) against a fake Steam,
## so CI covers it without GodotSteam installed.

const PlatformScript := preload("res://platform/platform.gd")
const FakeSteam := preload("res://tests/fake_steam.gd")
const FakePeer := preload("res://tests/fake_steam_peer.gd")
const FakeAchievements := preload("res://tests/fake_achievements.gd")


func _platform(fake: RefCounted) -> Node:
	var p: Node = PlatformScript.new()
	p.init_steam(fake, 480)
	return p


func _transport(fake: RefCounted, lobby: int = 0) -> SteamTransport:
	var t := SteamTransport.new(fake, lobby)
	t.make_peer = func() -> MultiplayerPeer: return FakePeer.new()
	return t


func test_platform_starts_steam_and_sets_menu_presence() -> void:
	var fake := FakeSteam.new()
	var p := _platform(fake)
	assert_true(p.steam == fake, "Steam is up")
	assert_eq(p.steam_status, "", "no error")
	assert_eq(p.player_name(), "Harvey", "Steam name")
	assert_eq(fake.presence.get("steam_display"), "#Menu", "menu presence")
	p.free()


func test_platform_without_steam_running_stays_offline() -> void:
	var fake := FakeSteam.new()
	fake.init_status = 2
	var p := _platform(fake)
	assert_true(p.steam == null, "no Steam")
	assert_true(p.steam_status.contains("isn't running"), "says why: " + p.steam_status)
	assert_true(not p.steam_ready(), "no Steam hosting offered")
	p.set_presence("run")   # harmless without Steam
	assert_eq(p.player_name(), "", "no Steam name")
	p.free()


func test_launch_lobby_from_command_line() -> void:
	assert_eq(PlatformScript.launch_lobby(PackedStringArray(["--", "+connect_lobby", "1234"])), 1234, "lobby id")
	assert_eq(PlatformScript.launch_lobby(PackedStringArray(["+connect_lobby"])), 0, "missing id")
	assert_eq(PlatformScript.launch_lobby(PackedStringArray([])), 0, "none")


func test_invite_and_friends_list_join_requests_reach_the_game() -> void:
	var fake := FakeSteam.new()
	var p := _platform(fake)
	var got: Array[int] = []
	p.lobby_join_requested.connect(func(id: int) -> void: got.append(id))
	fake.join_requested.emit(55, 7)
	fake.join_game_requested.emit(7, "+connect_lobby 66")
	assert_eq(got, [55, 66] as Array[int], "both routes ask to join")
	p.free()


func test_lobby_presence_offers_join_game() -> void:
	var fake := FakeSteam.new()
	var p := _platform(fake)
	p.set_presence("lobby", {"players": 2}, 99, 2)
	assert_eq(fake.presence.get("steam_display"), "#Lobby", "lobby line")
	assert_eq(fake.presence.get("connect"), "+connect_lobby 99", "join button")
	assert_eq(fake.presence.get("steam_player_group_size"), "2", "group size")
	p.free()


func test_achievements_and_stats_mirror_to_steam() -> void:
	var fake := FakeSteam.new()
	var p := _platform(fake)
	FakeAchievements.listeners.clear()
	p.bind_achievements(FakeAchievements)
	assert_true(fake.achievements.has("FIRST_WIN"), "earned offline, synced on start")
	assert_eq(fake.stats.get("RUNS"), 3, "stats go up in upper case")
	FakeAchievements.earn("boss_slayer")
	assert_true(fake.achievements.has("BOSS_SLAYER"), "new unlock reaches Steam")
	assert_true(fake.stored >= 2, "stats stored")
	p.free()


func test_steam_host_creates_tagged_lobby_and_relay_host() -> void:
	var fake := FakeSteam.new()
	var t := _transport(fake)
	var peers: Array = []
	t.ready.connect(func(p: MultiplayerPeer) -> void: peers.append(p))
	assert_eq(t.host(), "", "hosting under way")
	assert_eq(t.lobby_id, 99, "lobby made")
	assert_eq(fake.getLobbyData(99, "game"), "carriers", "tagged as ours")
	assert_eq(peers.size(), 1, "peer ready")
	assert_true(peers[0].hosting, "peer hosts")
	assert_true(t.invite_friends() and fake.invited == 1, "invite opens the overlay")
	t.close()
	assert_eq(fake.left, [99], "leaves the lobby on close")


func test_steam_host_reports_lobby_failure() -> void:
	var fake := FakeSteam.new()
	fake.lobby_result = 2
	var t := _transport(fake)
	var reasons: Array[String] = []
	t.failed.connect(func(r: String) -> void: reasons.append(r))
	t.host()
	assert_eq(reasons.size(), 1, "failure reported")


func test_steam_join_connects_to_the_lobby_owner() -> void:
	var fake := FakeSteam.new()
	var t := _transport(fake, 99)
	assert_eq(t.join(), "", "joining under way")
	assert_true(t.peer != null and t.peer.target == 2002, "client aimed at the owner")
	assert_eq(t.player_id(), "steam:1001", "Steam id is the reconnect id")
	var again := t.rejoin_copy() as SteamTransport
	assert_eq([again.lobby_id, again.host_steam_id], [99, 2002], "reconnect targets the same host")


func test_steam_join_refuses_other_games_lobbies() -> void:
	var fake := FakeSteam.new()
	fake.lobby_data[77] = {"game": "spacewar"}
	var t := _transport(fake, 77)
	var reasons: Array[String] = []
	t.failed.connect(func(r: String) -> void: reasons.append(r))
	t.join()
	assert_eq(reasons.size(), 1, "refused")
	assert_true(t.peer == null, "no connection")


func test_steam_rejoin_falls_back_to_host_when_lobby_is_gone() -> void:
	var fake := FakeSteam.new()
	fake.join_response = 2
	var t := SteamTransport.new(fake, 99, 2002)
	t.make_peer = func() -> MultiplayerPeer: return FakePeer.new()
	t.join()
	assert_true(t.peer != null and t.peer.target == 2002, "connects to the host directly")


func test_cloud_sync_round_trip() -> void:
	var fake := FakeSteam.new()
	var path := "user://test_cloud_sync.txt"
	var cloud := CloudSync.new(fake)
	cloud.files = [path]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("local save")
	f.close()
	assert_eq(cloud.push(), [path] as Array[String], "uploads a new file")
	assert_eq(fake.cloud["test_cloud_sync.txt"].data.get_string_from_utf8(), "local save", "cloud copy")
	assert_eq(cloud.push(), [] as Array[String], "unchanged file not re-uploaded")
	# Newer save from another PC wins on startup.
	fake.cloud["test_cloud_sync.txt"] = {"data": "deck save".to_utf8_buffer(), "time": int(Time.get_unix_time_from_system()) + 100}
	assert_eq(cloud.pull(), [path] as Array[String], "takes the newer cloud copy")
	assert_eq(FileAccess.get_file_as_string(path), "deck save", "local file replaced")
	# A finished run deletes its save; the cloud copy must go too.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	cloud.push()
	assert_true(not fake.cloud.has("test_cloud_sync.txt"), "deleted from the cloud")


func test_cloud_sync_off_when_player_disabled_it() -> void:
	var fake := FakeSteam.new()
	fake.cloud_on = false
	assert_true(not CloudSync.new(fake).enabled(), "respects the Steam setting")
	assert_true(not CloudSync.new(null).enabled(), "no Steam, no cloud")


func test_crash_reporter_notices_unclean_exit() -> void:
	var dir := "user://test_crash"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "/logs"))
	var log := FileAccess.open(dir + "/logs/godot2026-10-24T10.00.00.log", FileAccess.WRITE)
	log.store_string("line one\nSCRIPT ERROR: boom\n")
	log.close()
	var c := CrashReporter.new()
	c.lock_path = dir + "/running.lock"
	c.dir = dir + "/reports"
	c.logs_dir = dir + "/logs"
	c.stop()
	assert_eq(c.start(), "", "clean start, no report")
	c.stop()
	assert_eq(c.start(), "", "clean exit, no report")
	# No stop(): the session "crashed".
	var report := c.start()
	assert_true(report != "", "crash noticed")
	var text := FileAccess.get_file_as_string(report)
	assert_true(text.contains("SCRIPT ERROR: boom"), "includes the end of the log")
	assert_true(text.contains("version="), "includes the version")
	c.stop()


## The menu and app read the Platform autoload; make sure they still compile.
func test_menu_and_app_scripts_compile() -> void:
	assert_true(load("res://ui/main_menu.gd") != null, "main menu")
	assert_true(load("res://view/app.gd") != null, "app")
	assert_true(load("res://platform/platform.gd") != null, "platform")
