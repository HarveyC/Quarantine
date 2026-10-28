extends RefCounted
## Enemy vocal cues: each kind has a bark and a death cry (audio/vo/, synthesized by
## tools/gen_music.py), played from the unit's position in 3D on the Voices bus. Driven by the
## event player's beats, so every peer hears the same cue at the same moment.

const VOICES := 6
## Kinds with no voice of their own (static props) map to "", others could share a voice here.
const ALIAS := {"hive_node": "", "egg_sac": "", "spore_nest": "", "source_root": "",
	"cutter": "fallen", "torchman": "fallen", "fence": "fallen"}   # the looters are people
## Barks per beat type, with a volume (dB) and a chance.
const CUES := {
	"alerted": [0.0, 1.0], "spawned": [-3.0, 0.7], "revealed": [0.0, 1.0], "telegraph": [-2.0, 1.0],
	"boss_phase": [3.0, 1.0], "shot": [-5.0, 0.25], "ability": [-1.0, 0.8], "move": [-12.0, 0.025],
}
## Below this gap (seconds) a new bark is dropped, so a swarm doesn't turn into noise.
const MIN_GAP := 0.3
## Bosses who talk: a spoken line from StoryData.HALE_BARKS for the phase, on these beats only
## (never on moves, shots or the idle chatter), at least TALK_GAP seconds apart.
const TALKERS := {"colonel_hale": ["alerted", "revealed", "boss_phase", "ability", "telegraph"]}
const TALK_GAP := 6.0
const HURT_GAP := 0.5

var _view: Node
var _players: Array[AudioStreamPlayer3D] = []
var _streams := {}
var _last := -10.0
var _last_unit := {}
var _phase := {}   # unit id -> boss phase seen in the beats
var _talk_i := 0
var _hurt_i := 0


func _init(view: Node) -> void:
	_view = view
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Voices"
		p.unit_size = 14.0
		p.max_db = 4.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.panning_strength = 0.8
		view.add_child(p)
		_players.append(p)


func on_beat(ev: Dictionary) -> void:
	var type := str(ev.get("type", ""))
	if type == "boss_phase":
		_phase[int(ev.get("unit", -1))] = int(ev.get("phase", 2))
	if type == "killed":   # the death cry goes up with the killing blow
		var uv := _unit(ev)
		if uv != null and (not uv.is_soldier or uv.turned):
			bark(uv, 0.0, true)
		return
	if type == "damage":   # a wound that did not kill: the kind's own yelp
		var hurt := _unit(ev)
		if hurt != null and (not hurt.is_soldier or hurt.turned) and int(ev.get("hp", 1)) > 0 and int(ev.get("amount", 0)) > 0:
			hurt_cry(hurt)
		return
	if not CUES.has(type):
		return
	var uv := _unit(ev)
	if uv == null or uv.is_soldier:
		return
	if TALKERS.has(uv.kind):
		if type in TALKERS[uv.kind]:
			talk(uv, 2.0 if type == "boss_phase" else 0.0)
		return
	var cue: Array = CUES[type]
	if type == "ability" and str(ev.get("ability", "")) == "scream":
		cue = [4.0, 1.0]
	if randf() <= float(cue[1]):
		bark(uv, float(cue[0]))


## The voice file for a kind ("" if it has none).
static func voice_for(kind: String, die := false) -> String:
	var k: String = ALIAS.get(kind, kind)
	if k == "":
		return ""
	return "res://audio/vo/%s%s.ogg" % [k, "_die" if die else ""]


## The pain cry file for a kind ("" if it has none): take 1 or 2.
static func hurt_for(kind: String, take := 1) -> String:
	var k: String = ALIAS.get(kind, kind)
	if k == "":
		return ""
	return "res://audio/vo/%s_hurt%s.ogg" % [k, "" if take <= 1 else str(take)]


## A talking boss's spoken lines for a phase.
static func talk_lines(kind: String, phase: int) -> Array[String]:
	var out: Array[String] = []
	if kind == "colonel_hale":
		var p := 2 if phase >= 2 else 1
		for t in StoryData.HALE_BARKS[p]:
			out.append(VoiceLines.clip("hale_turned" if p == 2 else "hale", t))
	return out


func talk(uv: Node3D, volume_db := 0.0) -> void:
	if not is_instance_valid(uv) or not uv.is_inside_tree() or not uv.visible:
		return
	if _players.is_empty() or not is_instance_valid(_players[0]):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var phase := int(_phase.get(uv.unit_id, 1))
	var key := "talk%d" % uv.unit_id
	if now - float(_last_unit.get(key, -100.0)) < TALK_GAP and not (phase >= 2 and not _last_unit.has(key + "p2")):
		return
	var lines := talk_lines(uv.kind, phase)
	if lines.is_empty():
		return
	_talk_i += 1
	var path := lines[_talk_i % lines.size()]
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	if _streams[path] == null:
		return
	_last_unit[key] = now
	if phase >= 2:
		_last_unit[key + "p2"] = true
	var p := _players[0]
	for q in _players:
		if not q.playing:
			p = q
			break
	p.stream = _streams[path]
	p.global_position = uv.global_position + Vector3(0, 1.2, 0)
	p.volume_db = volume_db + 4.0
	p.pitch_scale = 1.0
	p.play()


## A short pain cry from the unit, alternating between two takes. Rate-limited per unit so
## a burst of hits (or burning) is one yelp, not a stutter.
func hurt_cry(uv: Node3D) -> void:
	if not is_instance_valid(uv) or not uv.is_inside_tree() or not uv.visible or _players.is_empty() or not is_instance_valid(_players[0]):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_unit.get("hurt%d" % uv.unit_id, -10.0)) < HURT_GAP:
		return
	_hurt_i += 1
	var path := hurt_for(uv.kind, 1 + _hurt_i % 2)
	if path == "":
		return
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	if _streams[path] == null:
		return
	_last_unit["hurt%d" % uv.unit_id] = now
	var p := _players[0]
	for q in _players:
		if not q.playing:
			p = q
			break
	p.stream = _streams[path]
	p.global_position = uv.global_position + Vector3(0, 1.2, 0)
	p.volume_db = 1.0 + (2.0 if uv.scale.x > 1.15 else 0.0)
	p.pitch_scale = randf_range(0.93, 1.07) * (0.85 if uv.scale.x > 1.15 else 1.0)
	p.play()


func bark(uv: Node3D, volume_db := 0.0, die := false) -> void:
	if not is_instance_valid(uv) or not uv.is_inside_tree() or (not uv.visible and not die):
		return
	if TALKERS.has(uv.kind) and not die:
		return   # talking bosses speak through talk(), not the idle chatter
	if _players.is_empty() or not is_instance_valid(_players[0]):
		return   # the battle view (and its players) was freed while a beat was still queued
	var now := Time.get_ticks_msec() / 1000.0
	if not die and (now - _last < MIN_GAP or now - float(_last_unit.get(uv.unit_id, -10.0)) < 2.5):
		return
	var path := voice_for(uv.kind, die)
	if path == "":
		return
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	if _streams[path] == null:
		return
	_last = now
	_last_unit[uv.unit_id] = now
	var p := _players[0]
	for q in _players:
		if not q.playing:
			p = q
			break
	p.stream = _streams[path]
	p.global_position = uv.global_position + Vector3(0, 1.2, 0)
	p.volume_db = volume_db + (2.0 if uv.scale.x > 1.15 else 0.0)
	p.pitch_scale = randf_range(0.9, 1.08) * (0.85 if uv.scale.x > 1.15 else 1.0)
	p.play()


func _unit(ev: Dictionary) -> Node3D:
	if not ev.has("unit") or _view == null or not is_instance_valid(_view):
		return null
	return _view.view_for(int(ev.unit))
