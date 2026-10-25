extends TestCase
## Story voices: which clips speak a line, the recorded clips are all there, mask babble, and the
## act 2 radio breakup.

const Babble := preload("res://view/babble.gd")
const VoicePlayer := preload("res://view/voice_player.gd")
const EnemyVoices := preload("res://view/enemy_voices.gd")


func test_filled_lines_match_their_template() -> void:
	assert_eq(VoiceLines.match_line("We lost {name}.", "We lost Reyes."), {"name": "Reyes"})
	assert_eq(VoiceLines.match_line("We lost {name}.", "We lost."), null)
	assert_eq(VoiceLines.match_line("Contact. That's {name}, wave {wave}. They aren't ours any more.",
		"Contact. That's Osei, wave 12. They aren't ours any more."), {"name": "Osei", "wave": "12"})
	assert_eq(VoiceLines.match_line("They've seen us.", "They've seen us."), {})


func test_pieces_split_around_names_and_numbers() -> void:
	var p := VoiceLines.pieces("Wave {last_wave}'s carrier is still down there.")
	assert_eq(p.size(), 3)
	assert_eq(p[0], {"text": "Wave"})
	assert_eq(p[1], {"var": "last_wave", "poss": true})
	assert_eq(p[2], {"text": "carrier is still down there."})
	assert_eq(VoiceLines.say_value("last_wave", "12", true), "twelve's")
	assert_eq(VoiceLines.number_words(47), "forty-seven")
	assert_eq(VoiceLines.say_value("name", "Reyes"), "Reyes")


func test_speakers_map_to_voices() -> void:
	assert_eq(VoiceLines.voice_of("MAJOR OKAFOR"), "okafor")
	assert_eq(VoiceLines.voice_of("OKAFOR"), "okafor")
	assert_eq(VoiceLines.voice_of("SOURCE"), "source")
	assert_eq(VoiceLines.voice_of("Trooper Reyes"), "")
	assert_eq(Babble.class_of("Trooper Reyes"), "trooper")
	assert_eq(Babble.class_of("MEDIC ADEYEMI"), "medic")
	assert_eq(Babble.class_of("LANTERN"), "")


func test_manifest_file_is_current() -> void:
	var f := FileAccess.open("res://tools/voice_manifest.json", FileAccess.READ)
	assert_true(f != null, "tools/voice_manifest.json exists")
	if f == null:
		return
	var saved: Variant = JSON.parse_string(f.get_as_text())
	assert_eq(saved, JSON.parse_string(JSON.stringify(VoiceLines.manifest())),
		"voice lines changed: run tools/voice_manifest.gd, then tools/gen_voices.py")


func test_every_voice_clip_exists() -> void:
	for e in VoiceLines.manifest():
		assert_true(ResourceLoader.exists(VoiceLines.DIR + e.file), "clip %s (%s: %s)" % [e.file, e.voice, e.text])
	for path in [VoicePlayer.RADIO_IN, VoicePlayer.RADIO_OUT, VoicePlayer.STATIC]:
		assert_true(ResourceLoader.exists(path), path)


func test_every_story_line_by_a_voice_has_clips() -> void:
	var lines: Array = []
	for k in StoryData.BOSS_SCENES:
		lines.append_array(StoryData.BOSS_SCENES[k].lines)
	for k in StoryData.ACT_SCENES:
		lines.append_array(StoryData.ACT_SCENES[k].lines)
	for l in lines:
		if VoiceLines.voice_of(l[0]) != "":
			assert_true(not VoiceLines.plan(l[0], l[1]).is_empty(), "no clips for %s: %s" % l)
	assert_eq(VoiceLines.plan("MAJOR OKAFOR", "We lost Reyes.").size(), 2)
	var echo := VoiceLines.plan("MAJOR OKAFOR", "Contact. That's Osei, wave 12. They aren't ours any more.")
	assert_eq(echo.size(), 5)
	assert_true(VoiceLines.plan("MAJOR OKAFOR", "Not a line anyone says.").is_empty(), "unknown line is silent")


func test_hale_talks() -> void:
	for phase in [1, 2]:
		var lines := EnemyVoices.talk_lines("colonel_hale", phase)
		assert_eq(lines.size(), StoryData.HALE_BARKS[phase].size())
		for path in lines:
			assert_true(ResourceLoader.exists(path), path)
	assert_true(EnemyVoices.talk_lines("runner", 1).is_empty(), "runners don't talk")


func test_babble_is_deterministic_and_per_class() -> void:
	var a := Babble.make("Contact. Here they come.", "trooper", "reyes")
	var b := Babble.make("Contact. Here they come.", "trooper", "reyes")
	var c := Babble.make("Contact. Here they come.", "breacher", "reyes")
	assert_true(a.get_length() > 0.6 and a.get_length() < 4.0, "babble length %.2f" % a.get_length())
	assert_eq(a.data, b.data, "same line, same soldier, same sound")
	assert_true(a.data != c.data, "classes sound different")
	var r := Babble.make("Contact.", "medic", "", true)
	assert_true(r.get_length() > Babble.make("Contact.", "medic", "").get_length(), "comms click adds length")
	for k in UnitData.SOLDIERS:
		assert_true(Babble.CLASSES.has(k), "babble for %s" % k)


func test_babble_counts_syllables() -> void:
	var s := Babble.syllables("Charges set. Light it.")
	assert_eq(s.size(), 5)   # char-ges set light it
	assert_true(s[2][2] > 0.3, "full stop pauses")


func test_breakup_positions() -> void:
	var clean := "Survivors. Alive, for now."
	var d := VoicePlayer.dropouts(clean, StoryData.garble(clean, 0))
	assert_eq(d.size(), 1)
	assert_true(d[0] > 0.8, "the last word drops out")
	assert_true(VoicePlayer.dropouts(clean, clean).is_empty(), "a clean line has no dropouts")
