extends Node
## Music and soundscape director, autoloaded as "Soundscape". View-only: it watches which screen
## is up (title, route map, node screens, a fight) and what the squad can see, and drives the
## music layers, ambience beds, spot sounds, stingers, enemy voices and button sounds. It never
## touches the rules, so it cannot affect online sync. All audio is synthesized by
## tools/gen_music.py (no third-party assets).
##
## Buses (default_bus_layout.tres): Music (ducks under Weapons), Ambience, SFX > Weapons/Voices,
## UI. Volumes live in user://audio.cfg and are edited in the Sound panel (F10 anywhere, or the
## Sound button on the title screen). M in a fight mutes everything (view/sfx.gd).
##
## Combat music is one loop split into synced stems that fade with the fight:
##   base    always             pulse   enemies in sight (held a while after they vanish)
##   danger  heavy contact, a soldier near death, or the enemy turn with enemies in sight
##   bloom   the squad's highest Infection (full when someone has Lapsed or Turned)
## While the squad is Concealed (as the event player shows it) the fight plays the stealth loop
## instead: tense and quiet, same key and tempo. When the squad is spotted the reveal stinger
## hits and the combat stems come in with pulse and danger forced up for ASSAULT_HOLD seconds.
## Boss fights swap to the boss loop: base, high (boss hurt or in a later phase), bloom (always
## full against the Source).

const EnemyVoices := preload("res://view/enemy_voices.gd")
const AudioSettings := preload("res://ui/audio_settings.gd")

const SETTINGS_PATH := "user://audio.cfg"
## Buses the Sound panel exposes, with their default volume (linear 0..1).
const VOLUME_BUSES := {"Master": 0.8, "Music": 0.7, "Ambience": 0.8, "SFX": 1.0, "UI": 0.7}
const TRACKS := {
	"menu": ["menu"], "map": ["map"], "rest": ["rest"],
	"stealth": ["stealth"],
	"combat": ["combat_base", "combat_pulse", "combat_danger", "combat_bloom"],
	"boss": ["boss_base", "boss_high", "boss_bloom"],
}
## Which track and ambience bed each mood uses ("" = silence).
const MOODS := {
	"menu": ["menu", "amb_wall"], "map": ["map", "amb_map"], "rest": ["rest", "amb_map"],
	"stealth": ["stealth", "act"], "combat": ["combat", "act"], "boss": ["boss", "act"], "after": ["", "act"], "summary": ["menu", "amb_map"],
}
const ACT_BEDS := {1: "amb_wall", 2: "amb_port", 3: "amb_bore"}
const BED_DB := {"amb_wall": -4.0, "amb_port": -3.0, "amb_bore": -2.0, "amb_map": -6.0}
const SPOTS := {
	"amb_wall": ["spot_siren_1", "spot_siren_2", "spot_gunfire_1", "spot_gunfire_2", "spot_howl_1", "spot_howl_2", "spot_pa", "spot_fence"],
	"amb_port": ["spot_siren_1", "spot_siren_2", "spot_glass", "spot_collapse", "spot_creak", "spot_howl_1", "spot_howl_2", "spot_gunfire_2"],
	"amb_bore": ["spot_drip", "spot_whisper_1", "spot_whisper_2", "spot_rumble", "spot_bloom", "spot_howl_1", "spot_creak"],
	"amb_map": ["spot_rotor", "spot_gunfire_1", "spot_siren_2"],
}
const STINGERS := ["st_win", "st_lose", "st_contact", "st_reveal", "st_boss", "st_node", "st_rank"]
const UI_SOUNDS := {"hover": "res://audio/ui_hover.wav", "click": "res://audio/ui_click.wav",
	"open": "res://audio/ui/open.ogg", "close": "res://audio/ui/close.ogg", "tick": "res://audio/ui/tick.ogg",
	"deny": "res://audio/ui_deny.wav"}
const UI_DB := {"hover": -16.0, "click": -9.0, "open": -10.0, "close": -10.0, "tick": -14.0, "deny": -12.0}
## Linear gain change per second for track fades and layer fades.
const FADE_IN := 0.7
const FADE_OUT := 0.45
const LAYER_IN := 0.8
const LAYER_OUT := 0.2
## Seconds the pulse layer stays up after the last enemy leaves sight.
const ENGAGED_HOLD := 10.0
## Seconds without contact before a new sighting earns the contact stinger again.
const CONTACT_REARM := 25.0
## Seconds of all-out music (pulse and danger up) after the squad loses concealment.
const ASSAULT_HOLD := 30.0

var mood := ""
var act := 1
var _tracks := {}        # track key -> {"players": [...], "gain": float, "target": float, "layers": [...], "layer_targets": [...]}
var _beds := {}          # bed name -> {"player": AudioStreamPlayer, "gain": float, "target": float}
var _bed := ""
var _stinger: AudioStreamPlayer
var _spot_player: AudioStreamPlayer
var _ui_players: Array[AudioStreamPlayer] = []
var _streams := {}
var _rng := RandomNumberGenerator.new()
var _spot_in := 12.0
var _bark_in := 8.0
var _view: Node = null
var _voices: EnemyVoices
var _engaged_until := -1.0
var _assault_until := -1.0
var _last_contact := -1000.0
var _view_at := 0.0
var _boss_announced := false
var _ended := false
var _phase_key := ""
var _clock := 0.0
var _settings: Control
var volumes := {}
## `-- --audio-log` prints mood changes, stingers and combat layer targets (for testing).
var _log := OS.get_cmdline_user_args().has("--audio-log")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	load_settings()
	_stinger = _player("Music")
	_spot_player = _player("Ambience")
	for i in 4:
		_ui_players.append(_player("UI"))
	get_tree().node_added.connect(_on_node_added)


# --- settings -------------------------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var ok := cfg.load(SETTINGS_PATH) == OK
	for bus in VOLUME_BUSES:
		volumes[bus] = clampf(float(cfg.get_value("volume", bus, VOLUME_BUSES[bus])) if ok else VOLUME_BUSES[bus], 0.0, 1.0)
		_apply_volume(bus)
	set_muted(bool(cfg.get_value("volume", "muted", false)) if ok else false, false)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus in volumes:
		cfg.set_value("volume", bus, volumes[bus])
	cfg.set_value("volume", "muted", is_muted())
	cfg.save(SETTINGS_PATH)


func set_volume(bus: String, linear: float, save := true) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)
	if save:
		save_settings()


func _apply_volume(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volumes[bus], 0.0001)) if volumes[bus] > 0.0 else -80.0)


func set_muted(on: bool, save := true) -> void:
	AudioServer.set_bus_mute(0, on)
	if save:
		save_settings()


func is_muted() -> bool:
	return AudioServer.is_bus_mute(0)


## Opens the Settings screen on its Audio tab (the old Sound panel when SettingsHost is absent).
func toggle_settings() -> void:
	if get_node_or_null("/root/SettingsHost") != null:
		GameSettings.open_menu("audio")
		return
	if _settings != null and is_instance_valid(_settings):
		close_settings()
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_settings = AudioSettings.new()
	_settings.closed.connect(close_settings)
	layer.add_child(_settings)
	ui("open")


func close_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		_settings.get_parent().queue_free()
		ui("close")
	_settings = null


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F10 and get_node_or_null("/root/SettingsHost") == null:
		toggle_settings()
		get_viewport().set_input_as_handled()


# --- per-frame direction --------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	var d := _detect()
	_follow_view(d.get("view"))
	if d.mood == "combat" or d.mood == "boss":
		_direct_combat(d)
	else:
		set_mood(d.mood, d.act)
	_fade(delta)
	_tick_spots(delta)
	_tick_barks(delta)


## Works out what's on screen. Reads the App's fields; tolerates any of them missing.
func _detect() -> Dictionary:
	var app := get_tree().root.get_node_or_null("App")
	var view: Node = null
	if app != null:
		view = app.get("view")
	elif get_tree().current_scene != null and get_tree().current_scene.get("unit_views") != null:
		view = get_tree().current_scene
	if view != null and is_instance_valid(view) and view.get("state") != null:
		var enc: Dictionary = view.state.encounter
		var boss := str(enc.get("boss", ""))
		return {"mood": "boss" if boss != "" else "combat", "act": int(enc.get("act", act)), "view": view, "boss": boss}
	var rv: Node = app.get("run_view") if app != null else null
	if rv != null and is_instance_valid(rv) and rv.get("run") != null and rv.visible:
		var run: RunState = rv.run
		var m := "map"
		match run.phase:
			RunState.Phase.NODE:
				var kind := RunMap.shown_type(run.current_node())
				m = "rest" if kind in [RunMap.HOSPITAL, RunMap.DEPOT, RunMap.SURVIVORS] else "map"
			RunState.Phase.REWARD:
				m = "rest"
			RunState.Phase.ENDED:
				m = "summary"
		return {"mood": m, "act": run.act, "phase": "%d:%d" % [run.phase, run.node]}
	return {"mood": "menu", "act": 1}


## Switches music and ambience to a mood (crossfading). Safe to call every frame.
func set_mood(m: String, a := 1) -> void:
	if not MOODS.has(m):
		return
	if m == mood and a == act:
		return
	var was := mood
	mood = m
	act = a
	if _log:
		print("[audio] mood %s act %d" % [m, a])
	var spec: Array = MOODS[m]
	for key in TRACKS:
		_track_target(key, 1.0 if key == spec[0] else 0.0)
	var bed: String = ACT_BEDS.get(clampi(a, 1, 3), "amb_wall") if spec[1] == "act" else spec[1]
	_set_bed(bed)
	if m == "rest" and was in ["map", "rest"]:
		stinger("st_node")
	elif m == "rest" and was in ["stealth", "combat", "boss", "after"]:
		stinger("st_rank")


func _direct_combat(d: Dictionary) -> void:
	var view: Node = d.view
	var info := combat_info(view)
	if info.ended:
		if not _ended:
			_ended = true
		set_mood("after", d.act)
		return
	var player: Node = view.get("player")
	if d.mood == "combat" and player != null and bool(player.get("concealed")):
		set_mood("stealth", d.act)   # enemies in sight while unseen don't earn the contact stinger
		return
	set_mood(d.mood, d.act)
	info["assault"] = _assault_until > _clock
	if info.threat > 0.0:
		if d.mood == "boss" and info.boss_seen and not _boss_announced:
			_boss_announced = true
			stinger("st_boss")
		elif d.mood == "combat" and _engaged_until < _clock and _clock - _last_contact > CONTACT_REARM \
				and _clock - _view_at > 2.0:   # not for enemies already in sight as the fight loads
			stinger("st_contact")
		_engaged_until = _clock + ENGAGED_HOLD
		_last_contact = _clock
	info["engaged"] = _engaged_until > _clock
	var t: Dictionary = _tracks.get(d.mood, {})
	if not t.is_empty():
		var mix := boss_mix(info, d.boss) if d.mood == "boss" else combat_mix(info)
		if _log and mix != t.layer_targets:
			print("[audio] layers ", mix, " threat ", info.threat)
		t.layer_targets = mix


## What the squad sees right now, from the unit views (so it matches the screen, not the rules).
static func combat_info(view: Node) -> Dictionary:
	var info := {"threat": 0.0, "visible": 0, "low_hp": false, "infection": 0.0, "lost": false,
		"enemy_phase": false, "ended": false, "boss_seen": false, "boss_hurt": 0.0, "boss_phase": 1}
	var player: Node = view.get("player")
	if player != null:
		info.enemy_phase = bool(player.get("enemy_phase"))
		info.ended = bool(player.get("ended"))
	var uvs: Dictionary = view.get("unit_views") if view.get("unit_views") != null else {}
	for uv in uvs.values():
		if not is_instance_valid(uv) or uv.dead:
			continue
		var hostile: bool = not uv.is_soldier or uv.turned
		if hostile:
			if not uv.visible:
				continue
			info.visible += 1
			var w := 1.0
			var u: Unit = view.state.get_unit(uv.unit_id) if view.get("state") != null else null
			var st: Dictionary = u.status if u != null else {}
			if st.has("boss"):
				w = 3.0
				info.boss_seen = true
				info.boss_hurt = 1.0 - float(uv.hp) / maxf(1.0, float(uv.max_hp))
				info.boss_phase = int(st.get("boss_phase", 1))
			elif st.get("elite", false):
				w = 2.0
			elif st.get("static", false) or uv.kind in ["hive_node", "egg_sac", "spore_nest", "source_root"]:
				w = 0.5
			info.threat += w
		else:
			if float(uv.hp) <= 0.35 * float(uv.max_hp):
				info.low_hp = true
			info.infection = maxf(info.infection, uv.infection / 100.0)
			if uv.lapsed:
				info.lost = true
		if uv.turned:
			info.lost = true
	return info


## Combat layer volumes (linear) for `info` (see combat_info; "engaged" adds the pulse hold).
static func combat_mix(info: Dictionary) -> Array:
	var threat: float = info.get("threat", 0.0)
	var engaged: bool = info.get("engaged", threat > 0.0) or info.get("assault", false)
	var pulse := 1.0 if engaged else 0.0
	var danger := clampf((threat - 2.0) / 2.0, 0.0, 1.0)
	if info.get("assault", false):
		danger = 1.0   # just spotted: all-out fight
	if engaged and info.get("low_hp", false):
		danger = maxf(danger, 0.8)
	if threat > 0.0 and info.get("enemy_phase", false):
		danger = maxf(danger, 0.6)
	return [1.0, pulse, danger, _bloom_level(info)]


static func boss_mix(info: Dictionary, boss: String) -> Array:
	var high := clampf(0.3 + float(info.get("boss_hurt", 0.0)) * 1.4, 0.0, 1.0)
	if int(info.get("boss_phase", 1)) >= 2 or info.get("low_hp", false):
		high = 1.0
	var bloom := 1.0 if boss == "the_source" else _bloom_level(info)
	return [1.0, high, bloom]


static func _bloom_level(info: Dictionary) -> float:
	if info.get("lost", false):
		return 1.0
	return clampf((float(info.get("infection", 0.0)) - 0.15) / 0.55, 0.0, 1.0)


func _follow_view(view: Variant) -> void:
	if view == _view:
		return
	_view = view
	_voices = null
	_engaged_until = -1.0
	_assault_until = -1.0
	_last_contact = -1000.0
	_view_at = _clock
	_boss_announced = false
	_ended = false
	if view == null or not is_instance_valid(view):
		_view = null
		return
	_voices = EnemyVoices.new(view)
	var player: Node = view.get("player")
	if player != null and player.has_signal("beat_started"):
		player.beat_started.connect(_on_beat)
	if player != null and player.has_signal("unit_killed"):
		player.unit_killed.connect(func(id: int) -> void:
			if _voices != null:
				_voices.on_beat({"type": "killed", "unit": id}))


func _on_beat(ev: Dictionary) -> void:
	if _voices != null:
		_voices.on_beat(ev)
	if str(ev.get("type", "")) == "concealment_lost":
		stinger("st_reveal")
		_assault_until = _clock + ASSAULT_HOLD
		_engaged_until = _clock + ENGAGED_HOLD
		_last_contact = _clock   # the reveal stands in for the contact stinger
		set_mood("combat", act)
	if str(ev.get("type", "")) == "mission_end":
		_ended = true
		set_mood("after", act)
		stinger("st_win" if int(ev.get("result", 0)) == Types.Result.VICTORY else "st_lose")


# --- players --------------------------------------------------------------------------------

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


func _looped(path: String) -> AudioStream:
	var s := _stream(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


func _track_target(key: String, target: float) -> void:
	if target > 0.0 and not _tracks.has(key):
		var players := []
		for name in TRACKS[key]:
			var p := _player("Music")
			p.stream = _looped("res://audio/music/%s.ogg" % name)
			players.append(p)
		var n: int = players.size()
		var layers := []
		layers.resize(n)
		layers.fill(0.0)
		layers[0] = 1.0
		_tracks[key] = {"players": players, "gain": 0.0, "target": 0.0, "layers": layers, "layer_targets": layers.duplicate()}
	if _tracks.has(key):
		var t: Dictionary = _tracks[key]
		t.target = target
		if target > 0.0 and not (t.players[0] as AudioStreamPlayer).playing:
			for p in t.players:     # same frame, so the stems start on the same mix step
				if p.stream != null:
					p.play()


func _set_bed(bed: String) -> void:
	if bed == _bed:
		return
	_bed = bed
	for b in _beds.values():
		b.target = 0.0
	if bed == "":
		return
	if not _beds.has(bed):
		var p := _player("Ambience")
		p.stream = _looped("res://audio/amb/%s.ogg" % bed)
		_beds[bed] = {"player": p, "gain": 0.0, "target": 0.0}
	_beds[bed].target = 1.0
	if not _beds[bed].player.playing and _beds[bed].player.stream != null:
		_beds[bed].player.play()
	_spot_in = _rng.randf_range(6.0, 14.0)


func _fade(delta: float) -> void:
	for key in _tracks.keys():
		var t: Dictionary = _tracks[key]
		t.gain = move_toward(t.gain, t.target, delta * (FADE_IN if t.target > t.gain else FADE_OUT))
		for i in t.layers.size():
			var tgt: float = t.layer_targets[i]
			t.layers[i] = move_toward(t.layers[i], tgt, delta * (LAYER_IN if tgt > t.layers[i] else LAYER_OUT))
			var p: AudioStreamPlayer = t.players[i]
			p.volume_db = linear_to_db(maxf(t.gain * t.layers[i], 0.0001))
		if t.gain <= 0.0 and t.target <= 0.0:
			for p in t.players:
				p.stop()
				p.queue_free()
			_tracks.erase(key)
	for name in _beds.keys():
		var b: Dictionary = _beds[name]
		b.gain = move_toward(b.gain, b.target, delta * (0.5 if b.target > b.gain else 0.35))
		b.player.volume_db = linear_to_db(maxf(b.gain, 0.0001)) + float(BED_DB.get(name, 0.0))
		if b.gain <= 0.0 and b.target <= 0.0:
			b.player.queue_free()
			_beds.erase(name)


func _tick_spots(delta: float) -> void:
	_spot_in -= delta
	if _spot_in > 0.0 or _bed == "":
		return
	var pool: Array = SPOTS.get(_bed, [])
	_spot_in = _rng.randf_range(9.0, 22.0)
	if pool.is_empty() or _spot_player.playing:
		return
	var s := _stream("res://audio/amb/%s.ogg" % pool[_rng.randi() % pool.size()])
	if s != null:
		_spot_player.stream = s
		_spot_player.volume_db = _rng.randf_range(-13.0, -6.0)
		_spot_player.pitch_scale = _rng.randf_range(0.92, 1.06)
		_spot_player.play()


## Now and then a visible enemy makes a noise of its own during the squad's turn.
func _tick_barks(delta: float) -> void:
	_bark_in -= delta
	if _bark_in > 0.0:
		return
	_bark_in = _rng.randf_range(7.0, 15.0)
	if _voices == null or _view == null or not is_instance_valid(_view) or _ended:
		return
	var player: Node = _view.get("player")
	if player != null and (player.get("enemy_phase") or player.call("is_busy")):
		return
	var seen := []
	for uv in _view.unit_views.values():
		if is_instance_valid(uv) and not uv.dead and not uv.is_soldier and uv.visible:
			seen.append(uv)
	if not seen.is_empty():
		_voices.bark(seen[_rng.randi() % seen.size()], -9.0)


## Plays a music stinger over everything (one at a time).
func stinger(name: String) -> void:
	var s := _stream("res://audio/music/%s.ogg" % name)
	if s == null:
		return
	if _log:
		print("[audio] stinger ", name)
	_stinger.stream = s
	_stinger.volume_db = -2.0
	_stinger.play()


# --- interface sounds -----------------------------------------------------------------------

func ui(kind: String) -> void:
	var s := _stream(UI_SOUNDS.get(kind, "res://audio/ui/%s.ogg" % kind))
	if s == null:
		return
	var p := _ui_players[0]
	for q in _ui_players:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = UI_DB.get(kind, -10.0)
	p.pitch_scale = _rng.randf_range(0.97, 1.03)
	p.play()


## Every button in the game gets a hover tick and a click, unless it sets meta "silent".
func _on_node_added(n: Node) -> void:
	var b := n as BaseButton
	if b == null or b.has_meta("silent"):
		return
	b.mouse_entered.connect(func() -> void:
		if is_instance_valid(b) and not b.disabled:
			ui("hover"))
	b.pressed.connect(func() -> void: ui("click"))
