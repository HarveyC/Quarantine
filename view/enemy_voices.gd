extends RefCounted
## Enemy vocal cues: each kind has a bark and a death cry (audio/vo/, synthesized by
## tools/gen_music.py), played from the unit's position in 3D on the Voices bus. Driven by the
## event player's beats, so every peer hears the same cue at the same moment.

const VOICES := 6
## Kinds with no voice of their own (static props) map to "", others could share a voice here.
const ALIAS := {"hive_node": "", "egg_sac": "", "spore_nest": "", "source_root": ""}
## Barks per beat type, with a volume (dB) and a chance.
const CUES := {
	"alerted": [0.0, 1.0], "spawned": [-3.0, 0.7], "revealed": [0.0, 1.0], "telegraph": [-2.0, 1.0],
	"boss_phase": [3.0, 1.0], "shot": [-4.0, 0.5], "ability": [-1.0, 0.8], "move": [-8.0, 0.12],
}
## Below this gap (seconds) a new bark is dropped, so a swarm doesn't turn into noise.
const MIN_GAP := 0.3

var _view: Node
var _players: Array[AudioStreamPlayer3D] = []
var _streams := {}
var _last := -10.0
var _last_unit := {}


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
	if type == "died":
		var uv := _unit(ev)
		if uv != null and (not uv.is_soldier or uv.turned):
			bark(uv, 0.0, true)
		return
	if not CUES.has(type):
		return
	var uv := _unit(ev)
	if uv == null or uv.is_soldier:
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


func bark(uv: Node3D, volume_db := 0.0, die := false) -> void:
	if not is_instance_valid(uv) or not uv.is_inside_tree() or (not uv.visible and not die):
		return
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
