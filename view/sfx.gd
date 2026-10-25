extends Node
## Sound effects. All sounds are synthesized by tools/gen_sfx.py into audio/ (no third-party
## audio). View-only: driven by the event player and UI, never by the rules, so it cannot
## affect online sync. Music, ambience and enemy voices live in view/soundscape.gd.
##
## `play(name)` picks a free voice from a small pool; pitch is jittered a little so
## repeated shots do not sound identical. Voices play on the SFX bus, ui_* sounds on UI.

const VOICES := 28
const SOUNDS := [
	"rifle", "sniper", "shotgun", "spit", "claw", "whiz", "impact_flesh", "impact_armor",
	"ricochet", "concrete", "alert", "kill_hit", "spore_burst", "body_fall", "body_fall_heavy", "soldier_death", "turned", "infect",
	"mutation", "heal", "lapse", "breach", "ui_click", "ui_hover", "ui_confirm", "ui_deny",
	"radio", "sting_squad", "sting_enemy", "cinematic", "victory", "defeat", "step1", "step2", "step3",
	"smg", "lmg", "carbine", "tail_rifle", "tail_heavy", "pump", "bolt",
	"pistol", "revolver", "blade", "bash",
	"battle_rifle", "burst_carbine", "anti_materiel", "scout_carbine", "flechette_smg", "dart_rifle",
	"slug_gun", "auto_shotgun", "pump_shotgun", "heavy_mg", "spore_rifle",
	"belt", "vent", "cylinder", "bolt_heavy", "whiz_pellets", "whiz_heavy", "whiz_bio", "whiz_dart", "whiz_needle",
	"impact_bio", "impact_slug", "impact_pellets", "impact_dart", "brass", "shell_drop",
	"machine_pistol", "bloom_pistol", "hand_cannon", "stun_pistol", "longslide", "whiz_zap", "impact_shock",
	"explosion", "collapse",
	"smoke_hiss", "flashbang", "gadget_deploy", "foam_spray", "drone", "grapple", "flare_pop", "emitter_hum", "order_call",
	"hook_whip", "satchel_arm", "weave_hum", "plate_clang",
]
## Gunfire, bullet impacts and melee strikes play on the Weapons bus (the music ducks under it).
const WEAPON := [
	"rifle", "sniper", "shotgun", "smg", "lmg", "carbine", "tail_rifle", "tail_heavy", "pump", "bolt",
	"whiz", "impact_flesh", "impact_armor", "ricochet", "concrete", "breach",
	"pistol", "revolver", "blade", "bash",
	"battle_rifle", "burst_carbine", "anti_materiel", "scout_carbine", "flechette_smg", "dart_rifle",
	"slug_gun", "auto_shotgun", "pump_shotgun", "heavy_mg", "spore_rifle",
	"belt", "vent", "cylinder", "bolt_heavy", "whiz_pellets", "whiz_heavy", "whiz_bio", "whiz_dart", "whiz_needle",
	"impact_bio", "impact_slug", "impact_pellets", "impact_dart", "brass", "shell_drop",
	"machine_pistol", "bloom_pistol", "hand_cannon", "stun_pistol", "longslide", "whiz_zap", "impact_shock",
	"explosion", "collapse", "kill_hit",
]
## Mix levels in dB per sound (default 0).
const LEVELS := {
	"ui_hover": -14.0, "ui_click": -8.0, "ui_confirm": -6.0, "ui_deny": -6.0, "step1": -12.0,
	"step2": -12.0, "step3": -12.0, "whiz": -6.0, "cinematic": -5.0, "radio": -8.0,
	"sting_squad": -6.0, "sting_enemy": -4.0, "infect": -4.0, "concrete": -4.0,
	"smg": -2.0, "tail_rifle": -5.0, "tail_heavy": -4.0, "pump": -3.0, "bolt": -4.0,
	"scout_carbine": -2.0, "flechette_smg": -3.0, "dart_rifle": -2.0, "belt": -6.0, "vent": -7.0, "cylinder": -5.0,
	"bolt_heavy": -3.0, "whiz_pellets": -5.0, "whiz_heavy": -4.0, "whiz_bio": -6.0, "whiz_dart": -7.0,
	"whiz_needle": -7.0, "impact_pellets": -2.0, "impact_dart": -3.0, "brass": -15.0, "shell_drop": -13.0,
	"machine_pistol": -2.0, "stun_pistol": -2.0, "whiz_zap": -6.0, "impact_shock": -2.0,
	"smoke_hiss": -4.0, "drone": -6.0, "emitter_hum": -5.0, "foam_spray": -3.0, "order_call": -6.0,
}

static var muted := false

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "Sfx"
	for s in SOUNDS:
		var path := "res://audio/%s.wav" % s
		if ResourceLoader.exists(path):
			_streams[s] = load(path)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)


func _ready() -> void:
	var ss := get_node_or_null("/root/Soundscape")
	if ss != null:
		muted = ss.is_muted()


func has_sound(s: String) -> bool:
	return _streams.has(s)


## Plays a sound. `delay` (seconds, real time) is for sounds that land after another,
## e.g. an impact after the shot. `bus` overrides the default (SFX, or UI for ui_* sounds).
func play(s: String, volume_db := 0.0, pitch_jitter := 0.06, delay := 0.0, bus := "") -> void:
	if muted or not _streams.has(s) or not is_inside_tree():
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(play.bind(s, volume_db, pitch_jitter, 0.0, bus))
		return
	var v := _free_voice()
	if bus == "":
		bus = "UI" if s.begins_with("ui_") else ("Weapons" if s in WEAPON and AudioServer.get_bus_index("Weapons") >= 0 else "SFX")
	v.bus = bus
	v.stream = _streams[s]
	v.volume_db = volume_db + LEVELS.get(s, 0.0)
	v.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	v.play()


func footstep() -> void:
	play("step%d" % _rng.randi_range(1, 3), 0.0, 0.12)


## Mutes everything (the Master bus, via the Soundscape so the choice is saved).
func set_muted(on: bool) -> void:
	muted = on
	var ss := get_node_or_null("/root/Soundscape") if is_inside_tree() else null
	if ss != null:
		ss.set_muted(on)
	if on:
		for v in _voices:
			v.stop()


func _free_voice() -> AudioStreamPlayer:
	var oldest := _voices[0]
	var best := -1.0
	for v in _voices:
		if not v.playing:
			return v
		var pos := v.get_playback_position()
		if pos > best:
			best = pos
			oldest = v
	return oldest
