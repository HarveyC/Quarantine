extends Node
## Speaks story lines: recorded clips for Okafor, the Source, Hale and Halden-Voss
## (story/voice_lines.gd picks them), mask babble for soldiers (view/babble.gd). Owned by the
## Soundscape autoload; callers use Soundscape.say(). One line at a time: a new line cuts the
## last one off, like a radio. Local presentation only.

const Babble := preload("res://view/babble.gd")

const RADIO_IN := "res://audio/voice/radio_in.ogg"
const RADIO_OUT := "res://audio/voice/radio_out.ogg"
const STATIC := "res://audio/voice/radio_static.ogg"
## Seconds the voice drops out for each word a broken-up line loses.
const DROPOUT := 0.35
const DB := {"okafor": -1.0, "source": 0.0, "hale": -1.0, "hale_turned": 0.0, "hv": -2.0, "squad": -5.0}

var _voice: AudioStreamPlayer
var _fx: AudioStreamPlayer
var _queue: Array[AudioStream] = []
var _drops: Array[float] = []   # seconds into the line
var _t := 0.0
var _drop_until := -1.0
var _db := 0.0
var _streams := {}
var _scene_line := false   # the line being spoken is a cutscene caption


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voices"
	add_child(_voice)
	_voice.finished.connect(_play_next)
	_fx = AudioStreamPlayer.new()
	_fx.bus = "Voices"
	add_child(_fx)


## Speaks `text` as `speaker` (a caption speaker: "OKAFOR", "MAJOR OKAFOR", "SOURCE", "HALE",
## "HALDEN-VOSS", or a soldier like "Trooper Reyes"). Returns its length in seconds, 0 if the
## line has no voice.
##   radio: a soldier speaks over the squad comms (click in and out)
##   dropouts: positions (0..1 through the spoken words) where the signal breaks up
##   scene: a cutscene caption; radio chatter and barks never cut one off
func say(speaker: String, text: String, opts := {}) -> float:
	if not opts.get("scene", false) and _scene_line and is_speaking():
		return 0.0
	var parts: Array[AudioStream] = []
	var voice := VoiceLines.voice_of(speaker)
	if voice != "":
		for path in VoiceLines.plan(speaker, text):
			var s := _stream(path)
			if s != null:
				parts.append(s)
	else:
		var klass := Babble.class_of(speaker)
		if klass != "":
			voice = "squad"
			parts.append(Babble.make(text, klass, speaker.get_slice(" ", 1).to_lower(), opts.get("radio", false)))
	if parts.is_empty():
		return 0.0
	var speech := 0.0
	for s in parts:
		speech += s.get_length()
	var lead := 0.0
	if voice in VoiceLines.RADIO:
		var a := _stream(RADIO_IN)
		var b := _stream(RADIO_OUT)
		if a != null:
			parts.push_front(a)
			lead = a.get_length()
		if b != null:
			parts.append(b)
	stop()
	_scene_line = opts.get("scene", false)
	_queue = parts
	_drops.clear()
	for f in opts.get("dropouts", []):
		_drops.append(lead + clampf(float(f), 0.0, 1.0) * speech)
	_t = 0.0
	_db = DB.get(voice, 0.0)
	_play_next()
	var total := 0.0
	for s in parts:
		total += s.get_length()
	return total


func stop() -> void:
	_queue.clear()
	_drops.clear()
	_voice.stop()
	_fx.stop()


func is_speaking() -> bool:
	return _voice.playing or not _queue.is_empty()


func _play_next() -> void:
	if _queue.is_empty():
		return
	_voice.stream = _queue.pop_front()
	_voice.volume_db = _db
	_voice.play()


func _process(delta: float) -> void:
	if not _voice.playing:
		return
	_t += delta
	if not _drops.is_empty() and _t >= _drops[0]:
		_drops.pop_front()
		_drop_until = _t + DROPOUT
		var s := _stream(STATIC)
		if s != null:
			_fx.stream = s
			_fx.volume_db = _db - 2.0
			_fx.play()
	_voice.volume_db = _db - (30.0 if _t < _drop_until else 0.0)


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## Where StoryData.garble(clean, salt) drops words from `clean`, as positions 0..1 by character.
## A negative salt is a clean line.
static func dropouts(clean: String, salt: int) -> Array[float]:
	var out: Array[float] = []
	if salt < 0 or clean.length() == 0:
		return out
	var words := clean.split(" ")
	var at := 0
	for i in words.size():
		if (i + salt) % StoryData.STATIC_EVERY == StoryData.STATIC_EVERY - 1 and words[i].length() > 2:
			out.append((at + words[i].length() * 0.5) / float(clean.length()))
		at += words[i].length() + 1
	return out
