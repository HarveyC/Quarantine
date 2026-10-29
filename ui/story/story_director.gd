extends CanvasLayer
## Plays the story over whatever is on screen: the briefing when a run starts, the act
## transitions, boss intros, the ending, radio chatter between nodes and in fights, and the
## Source's whispers to an infected soldier (only that soldier's player sees them). Watches the
## App's session; reads run and fight events and never changes them, so every peer plays its own
## copy and skipping a scene only skips it for you.
##
## Fight chatter follows the mission view's event player, not the rules: Rules resolves a whole
## enemy turn at once, so a line said when the event fires would arrive while the attack is still
## animating. "Down" and "turned" lines wait for that beat to finish, contact and whispers start
## with their beat, and run events that land mid-fight (an Echo laid to rest, intel recovered, a
## recruit) wait until the queue has drained. Host and clients play the same beats, so the timing
## is the same on every peer.

const Styles := preload("res://ui/styles.gd")
const StoryScene := preload("res://ui/story/story_scene.gd")
const VoicePlayer := preload("res://view/voice_player.gd")

const RADIO_SECS := 5.0
const WHISPER_SECS := 4.5
const MAX_RADIO := 2

var app: Node
var _session: Node
var _run: RunState
var _state: GameState
var _player: Node          # the mission view's EventPlayer while a fight is on screen
var _held: Array[Callable] = []   # run-event lines waiting for the fight's beats to finish
var _scene: Control
var _queue: Array = []
var _played := {}
var _radio_box: VBoxContainer
var _whisper: VBoxContainer
var _whisper_head: Label
var _whisper_rule: Label
var _whisper_line: Label
var _whisper_t := 0.0
var _contact_said := false
var _boss_said := {}   # boss bark keys already said this fight
var _tiers := {}           # unit id -> last infection tier seen
var _whispered := {}       # "sid:tier" -> true
var _last_stage := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	layer = 15
	_rng.randomize()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Styles.make_theme()
	root.name = "Overlay"
	add_child(root)
	# Top centre: clear of the mission HUD's squad list and readiness panel, and of the map's
	# route vote panel.
	_radio_box = Styles.vbox(8)
	_radio_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_radio_box.offset_left = -230
	_radio_box.offset_right = 230
	_radio_box.offset_top = 112
	_radio_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_radio_box)
	# What happened first (tier and what it does), then the Source's line under it as flavour.
	_whisper = Styles.vbox(4)
	_whisper.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_whisper.offset_left = -500
	_whisper.offset_right = 500
	_whisper.offset_top = 300
	_whisper.modulate.a = 0.0
	_whisper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_whisper_head = Styles.caps("", 24, Styles.TEAL)
	_whisper_rule = Styles.label("", 17, Styles.TEXT)
	_whisper_line = Styles.label("", 18, Styles.TEAL)
	for l: Label in [_whisper_head, _whisper_rule, _whisper_line]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_outline_size", 8)
		_whisper.add_child(l)
	root.add_child(_whisper)


func _process(delta: float) -> void:
	var s: Node = app.get("session") if app != null else null
	if not is_instance_valid(s):
		s = null
	_session = s
	var run: RunState = s.get("run") if s != null else null
	if run != _run:
		_bind_run(run)
	# The mission view stays up after a fight until its last beats and the debrief have played,
	# so the chatter follows it rather than the session's state.
	var v: Node = app.get("view") if app != null and s != null else null
	if not is_instance_valid(v):
		v = null
	var pl: Node = v.get("player") if v != null else null
	if not is_instance_valid(_player):
		_player = null
	if pl != _player:
		_bind_player(pl, v.get("state") if v != null else null)
	if s == null:
		_clear()
	_release_held()
	if _scene == null and not _queue.is_empty():
		_start(_queue.pop_front())
	if _whisper_t > 0.0:
		_whisper_t -= delta
		_whisper.modulate.a = clampf(minf(_whisper_t, WHISPER_SECS - _whisper_t) / 0.6, 0.0, 1.0) * 0.95


func playing() -> bool:
	return _scene != null or not _queue.is_empty()


func _clear() -> void:
	_queue.clear()
	if _scene != null:
		_scene.queue_free()
		_scene = null
	_held.clear()
	for c in _radio_box.get_children():
		c.queue_free()


# --- binding ------------------------------------------------------------------------------

func _bind_run(run: RunState) -> void:
	if _run != null and _run.event.is_connected(_on_run_event):
		_run.event.disconnect(_on_run_event)
	_run = run
	if run == null:
		return
	run.event.connect(_on_run_event)
	_last_stage = RunRules.outbreak_stage(run.outbreak)
	if run.act == 1 and run.node == -1 and run.fights_won == 0 and run.phase != RunState.Phase.ENDED:
		_queue_scene("intro:%d" % run.seed, intro_spec(run))


func _bind_player(pl: Node, st: GameState) -> void:
	if is_instance_valid(_player):
		if _player.beat_started.is_connected(_on_beat_started):
			_player.beat_started.disconnect(_on_beat_started)
		if _player.beat_finished.is_connected(_on_beat_finished):
			_player.beat_finished.disconnect(_on_beat_finished)
	_player = pl
	_state = st
	_contact_said = false
	_boss_said.clear()
	_tiers.clear()
	if pl == null or st == null:
		_player = null
		_state = null
		return
	pl.beat_started.connect(_on_beat_started)
	pl.beat_finished.connect(_on_beat_finished)
	for u in st.units:
		_tiers[u.id] = Infection.tier(u.infection)


## True while a fight is on screen and still has beats to play.
func _fight_busy() -> bool:
	return is_instance_valid(_player) and _player.is_busy()


func _release_held() -> void:
	if _held.is_empty() or _fight_busy():
		return
	var held := _held.duplicate()
	_held.clear()
	for c in held:
		c.call()


## Says a run-event line now, or once the fight on screen has caught up with the rules.
func _after_beats(say: Callable) -> void:
	if _fight_busy():
		_held.append(say)
	else:
		say.call()


func _queue_scene(key: String, spec: Dictionary) -> void:
	if _played.has(key) or spec.is_empty():
		return
	_played[key] = true
	_queue.append(spec)


func _start(spec: Dictionary) -> void:
	_scene = StoryScene.new()
	get_node("Overlay").add_child(_scene)
	get_node("Overlay").move_child(_scene, 0)
	_scene.play(spec)
	_scene.finished.connect(func() -> void: _scene = null)


# --- run events ---------------------------------------------------------------------------

func _on_run_event(ev: Dictionary) -> void:
	var run := _run
	match ev.type:
		"act_start":
			if ev.act >= 2:
				_queue_scene("act:%d:%d" % [run.seed, ev.act], act_spec(run, ev.act))
		"fight_start":
			if ev.kind == RunMap.BOSS:
				var boss: String = run.act_boss()
				_queue_scene("boss:%d:%d" % [run.seed, run.act], boss_spec(run, boss))
		"ending":
			_queue_scene("ending:%d" % run.seed, ending_spec(run))
		"node_enter":
			var t: String = ev.node_type
			if StoryData.BARKS.has(t):
				_bark(t, {})
		"outbreak":
			var stage := RunRules.outbreak_stage(ev.total)
			if stage > _last_stage and stage >= 2:
				_after_beats(_bark.bind("outbreak", {}))
			_last_stage = stage
		"recruit_deployed":
			var r := run.get_soldier(ev.sid)
			if not r.is_empty():
				_after_beats(_bark.bind("recruit", {"name": r.name}))
		"echo_met":
			_after_beats(_bark.bind("echo", {"name": ev.name, "wave": _echo_wave(ev.key)}))
		"echo_laid":
			_after_beats(_bark.bind("echo_laid", {"name": ev.name}))
		"lore":
			var e := StoryData.lore_entry(ev.id)
			if not e.is_empty():
				_after_beats(_radio.bind("INTEL RECOVERED", "%s · %s" % [e.title, e.from], Styles.TEAL_DIM))


func _echo_wave(key: String) -> int:
	for e in _run.story.get("echoes", []):
		if e.key == key:
			return e.wave
	return 0


# --- fight events ---------------------------------------------------------------------------

## As a beat starts: the "!" over the enemy that spotted the squad, the tier change on a soldier.
func _on_beat_started(ev: Dictionary) -> void:
	var st := _state
	if st == null:
		return
	match str(ev.get("type", "")):
		"alerted":
			if not _contact_said:
				_contact_said = true
				_bark("contact", {})
		"infection":
			var u := st.get_unit(ev.unit)
			if u == null or not u.status.has("sid"):
				return
			var before: int = _tiers.get(u.id, 0)
			_tiers[u.id] = ev.tier
			if ev.tier > before and ev.tier in [2, 3]:
				_whisper_to(u, ev.tier)


## Once a beat has played out: a soldier is only called down when the body is on the ground.
func _on_beat_finished(ev: Dictionary) -> void:
	var st := _state
	if st == null:
		return
	match str(ev.get("type", "")):
		"died":
			var u := st.get_unit(ev.unit)
			if u != null and u.status.has("sid") and not u.status.get("turned", false):
				_bark("dead", {"name": _surname(u)})
		"turned":
			var u := st.get_unit(ev.unit)
			if u != null and u.status.has("sid"):
				_bark("turned", {"name": _surname(u)})
		"boss_phase":
			_boss_bark("%s_%d" % [ev.get("boss", ""), int(ev.get("phase", 0))])
		"untethered":
			var u := st.get_unit(ev.unit)
			if u != null:
				_boss_bark(u.kind + "_open")


## Boss fight lines (StoryData.BARKS "<boss>_<phase>", "<boss>_open"), each once a fight.
func _boss_bark(key: String) -> void:
	if (StoryData.BARKS.has(key) or StoryData.CAPTION_BARKS.has(key)) and not _boss_said.has(key):
		_boss_said[key] = true
		_bark(key, {})


func _surname(u: Unit) -> String:
	if _run != null:
		var r := _run.get_soldier(u.status.get("sid", -1))
		if not r.is_empty():
			return r.name
	return u.display_name


func _whisper_to(u: Unit, tier: int) -> void:
	var key := "%s:%d" % [u.status.sid, tier]
	if _whispered.has(key) or _session == null or not _session.is_local(u.owner_player):
		return
	_whispered[key] = true
	var lines: Array = StoryData.WHISPERS[tier]
	var col := Infection.tier_color(tier)
	_whisper_head.text = ("%s is %s" % [_surname(u), Infection.tier_name(tier)]).to_upper()
	_whisper_head.add_theme_color_override("font_color", col)
	_whisper_rule.text = tier_rule(tier)
	var said := StoryData.fill(lines[_rng.randi() % lines.size()], {"name": _surname(u)})
	_whisper_line.text = "\u201c%s\u201d" % said
	_whisper_line.modulate.a = 0.75
	_say("SOURCE", said)
	_whisper_t = WHISPER_SECS


## What reaching `tier` does, in one line under the whisper's heading.
static func tier_rule(tier: int) -> String:
	var p: Dictionary = Infection.PASSIVES.get(tier, {})
	var parts: Array[String] = ["Infection %d+" % Infection.THRESHOLDS[tier]]
	if int(p.get("mobility", 0)) > 0:
		parts.append("+%d move" % int(p.mobility))
	if int(p.get("aim", 0)) > 0:
		parts.append("+%d aim" % int(p.aim))
	if Infection.LAPSE_CHANCE.has(tier):
		parts.append("%d%% Lapse chance each turn" % roundi(Infection.LAPSE_CHANCE[tier] * 100))
	if tier == Infection.Tier.CRITICAL:
		parts.append("Turns at %d" % Infection.TURNED_AT)
	return "  \u00b7  ".join(parts)


# --- radio --------------------------------------------------------------------------------

## A short radio line. Act 1 is Okafor, act 2 her signal breaks up, act 3 has no radio, so a
## soldier of the squad says it.
func _bark(key: String, vars: Dictionary) -> void:
	if _run == null:
		return
	var lines: Array = StoryData.BARKS.get(key, StoryData.CAPTION_BARKS.get(key, []))
	if lines.is_empty():
		return
	var clean := StoryData.fill(lines[_rng.randi() % lines.size()], vars)
	var text := clean
	var who := "MAJOR OKAFOR"
	var salt := -1
	if _run.act == 2 and key not in ["dead", "turned", "echo_laid"]:
		salt = _rng.randi() % 4
		text = StoryData.garble(text, salt)
	elif _run.act >= 3:
		who = _squad_voice(vars.get("name", ""))
	_radio(who, text, Styles.AMBER)
	_say(who, clean, {"radio": true, "dropouts": VoicePlayer.dropouts(clean, salt)})


func _say(who: String, text: String, opts := {}) -> void:
	var s := get_node_or_null("/root/Soundscape")
	if s != null:
		s.say(who, text, opts)


func _squad_voice(not_name: String) -> String:
	var squad := _run.squad().filter(func(r: Dictionary) -> bool: return r.name != not_name)
	if squad.is_empty():
		return "LANTERN"
	var r: Dictionary = squad[_rng.randi() % squad.size()]
	return ("%s %s" % [UnitData.SOLDIERS[r.kind].name, r.name]).to_upper()


func _radio(who: String, text: String, col: Color) -> void:
	var f := preload("res://ui/frame.gd").new(Vector4(14, 9, 14, 10))
	f.set_look(Color(0.03, 0.045, 0.073, 0.84), Styles.BORDER_SOFT, Styles.AMBER, false)
	f.stripe = col
	var box := Styles.vbox(3)
	f.add_child(box)
	var head := Styles.hbox(8)
	head.add_child(Styles.caps("Radio" if col == Styles.AMBER else "Field log", 11, Styles.MUTED))
	head.add_child(Styles.caps(who, 12, col))
	box.add_child(head)
	var l := Styles.label(text, 16, Styles.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 400
	box.add_child(l)
	_radio_box.add_child(f)
	while _radio_box.get_child_count() > MAX_RADIO:
		var old := _radio_box.get_child(0)
		_radio_box.remove_child(old)
		old.queue_free()
	f.modulate.a = 0.0
	var tw := f.create_tween()
	tw.tween_property(f, "modulate:a", 1.0, 0.25)
	tw.tween_interval(RADIO_SECS)
	tw.tween_property(f, "modulate:a", 0.0, 0.6)
	tw.tween_callback(f.queue_free)


# --- scene specs (pure, also used by tests and the shot tool) ---------------------------------

static func cast_of(run: RunState) -> Array:
	var out: Array = []
	for r in run.squad():
		out.append({"kind": r.kind, "owner": r.owner, "infection": r.infection, "sid": r.id, "name": r.name})
	return out


static func _voice(run: RunState, line: Array) -> Array:
	if line[0] != "SQUAD":
		return line
	var squad := run.squad()
	if squad.is_empty():
		return ["", line[1]]
	var r: Dictionary = squad[0]
	return ["%s %s" % [UnitData.SOLDIERS[r.kind].name, r.name], line[1]]


static func _lines(run: RunState, lines: Array, vars: Dictionary = {}) -> Array:
	var out: Array = []
	for l in lines:
		out.append(_voice(run, [l[0], StoryData.fill(l[1], vars)]))
	return out


static func intro_spec(run: RunState) -> Dictionary:
	var st: Dictionary = run.story
	var key := "first"
	if int(st.get("runs", 0)) > 0:
		key = "lost" if st.get("last_result", "") != "won" else st.get("last_ending", "burn")
		if not StoryData.INTRO_OPENERS.has(key):
			key = "burn"
	var lines: Array = StoryData.INTRO_OPENERS[key].duplicate()
	lines.append_array(StoryData.INTRO_ORDERS if key == "first" else StoryData.INTRO_ORDERS.slice(2))
	var vars := {"wave": st.get("wave", StoryData.FIRST_WAVE), "last_wave": st.get("last_wave", 0)}
	return {"stage": "wall", "title": "Wave %d" % vars.wave, "sub": "Lantern Company · The Cordon, Harrow",
		"lines": _lines(run, lines, vars), "cast": cast_of(run)}


static func act_spec(run: RunState, act: int) -> Dictionary:
	var a: Dictionary = StoryData.ACT_SCENES.get(act, {})
	var by_boss: Dictionary = StoryData.ACT_SCENES_BY_BOSS.get(run.act_boss(), {})
	if not by_boss.is_empty() and run.act == act:
		a = by_boss
	if a.is_empty():
		return {}
	var lines: Array = a.lines.duplicate()
	if act == 3 and run.story.get("source_reached", false):
		lines[1] = StoryData.SOURCE_REMEMBERS
	return {"stage": a.stage, "title": a.title, "sub": a.sub, "lines": _lines(run, lines), "cast": cast_of(run)}


static func boss_spec(run: RunState, boss: String) -> Dictionary:
	var b: Dictionary = StoryData.BOSS_SCENES.get(boss, {})
	if b.is_empty():
		return {}
	var lines: Array = b.lines.duplicate()
	if boss == "the_source" and run.story.get("last_ending", "") == "burn":
		lines.insert(1, StoryData.SOURCE_BURNED)
	return {"stage": "boss", "boss": boss, "title": b.title, "sub": b.sub, "lines": _lines(run, lines),
		"cast": cast_of(run)}


static func ending_spec(run: RunState) -> Dictionary:
	var id: String = run.story.get("ending", "")
	var e: Dictionary = StoryData.ENDINGS.get(id, {})
	if e.is_empty():
		return {}
	var cast := cast_of(run)
	var carrier := 0
	var name := ""
	for i in cast.size():
		if cast[i].sid == run.story.get("carrier", -1):
			carrier = i
			name = "%s %s" % [UnitData.SOLDIERS[cast[i].kind].name, cast[i].name]
	var raw: Array = []
	for l in e.lines:
		# the carrier says their own last words
		raw.append([name, l[1]] if id == "carry" and l[0] == "SQUAD" and name != "" else l)
	return {"stage": e.stage, "title": e.title, "sub": e.sub, "lines": _lines(run, raw, {"name": name}),
		"cast": cast, "carrier_index": carrier}
