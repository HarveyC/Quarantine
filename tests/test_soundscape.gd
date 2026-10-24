extends TestCase
## Music and soundscape: assets present, stems line up, and the layer logic.

const Soundscape := preload("res://view/soundscape.gd")
const EnemyVoices := preload("res://view/enemy_voices.gd")


func test_music_and_ambience_files_exist() -> void:
	for key in Soundscape.TRACKS:
		for name in Soundscape.TRACKS[key]:
			assert_true(ResourceLoader.exists("res://audio/music/%s.ogg" % name), "track %s" % name)
	for name in Soundscape.STINGERS:
		assert_true(ResourceLoader.exists("res://audio/music/%s.ogg" % name), "stinger %s" % name)
	var beds: Array = Soundscape.ACT_BEDS.values() + ["amb_map"]
	for bed in beds:
		assert_true(ResourceLoader.exists("res://audio/amb/%s.ogg" % bed), "bed %s" % bed)
	for bed in Soundscape.SPOTS:
		for s in Soundscape.SPOTS[bed]:
			assert_true(ResourceLoader.exists("res://audio/amb/%s.ogg" % s), "spot %s" % s)
	for kind in Soundscape.UI_SOUNDS:
		assert_true(ResourceLoader.exists(Soundscape.UI_SOUNDS[kind]), "ui %s" % kind)


func test_stems_share_one_length() -> void:
	for key in ["combat", "boss"]:
		var first := -1.0
		for name in Soundscape.TRACKS[key]:
			var s: AudioStream = load("res://audio/music/%s.ogg" % name)
			if first < 0.0:
				first = s.get_length()
			assert_true(absf(s.get_length() - first) < 0.01, "%s is %.3fs, base is %.3fs" % [name, s.get_length(), first])


func test_every_enemy_has_a_voice() -> void:
	for kind in UnitData.ENEMIES:
		var path := EnemyVoices.voice_for(kind)
		if path == "":
			continue
		assert_true(ResourceLoader.exists(path), "bark for %s" % kind)
		assert_true(ResourceLoader.exists(EnemyVoices.voice_for(kind, true)), "death cry for %s" % kind)


func test_bus_layout() -> void:
	for bus in ["Music", "Ambience", "SFX", "Weapons", "Voices", "UI"]:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "bus %s" % bus)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Weapons")), &"SFX", "weapons feed effects")


func test_combat_layers_follow_the_fight() -> void:
	var calm := Soundscape.combat_mix({"threat": 0.0, "engaged": false})
	assert_eq(calm, [1.0, 0.0, 0.0, 0.0], "nothing in sight: base only")
	var one := Soundscape.combat_mix({"threat": 1.0})
	assert_eq(one[1], 1.0, "an enemy in sight brings the pulse in")
	assert_eq(one[2], 0.0, "one enemy isn't heavy contact")
	var held := Soundscape.combat_mix({"threat": 0.0, "engaged": true})
	assert_eq(held[1], 1.0, "the pulse holds a while after contact")
	assert_eq(Soundscape.combat_mix({"threat": 4.0})[2], 1.0, "a big fight is full danger")
	assert_eq(Soundscape.combat_mix({"threat": 1.0, "low_hp": true})[2], 0.8, "a soldier near death")
	assert_eq(Soundscape.combat_mix({"threat": 1.0, "enemy_phase": true})[2], 0.6, "enemy turn with contact")
	assert_eq(Soundscape.combat_mix({"infection": 0.1})[3], 0.0, "low Infection: no Bloom")
	var assault := Soundscape.combat_mix({"threat": 0.0, "engaged": false, "assault": true})
	assert_eq([assault[1], assault[2]], [1.0, 1.0], "just spotted: pulse and danger come in at once")
	assert_eq(Soundscape.combat_mix({"infection": 0.8})[3], 1.0, "high Infection: full Bloom")
	assert_eq(Soundscape.combat_mix({"lost": true})[3], 1.0, "a Lapsed or Turned soldier: full Bloom")


func test_boss_layers() -> void:
	var fresh := Soundscape.boss_mix({"boss_hurt": 0.0}, "brood_mother")
	assert_true(fresh[1] < 0.5, "a fresh boss keeps the high layer low")
	assert_eq(Soundscape.boss_mix({"boss_hurt": 0.6}, "brood_mother")[1], 1.0, "a hurt boss is full intensity")
	assert_eq(Soundscape.boss_mix({"boss_phase": 2}, "colonel_hale")[1], 1.0, "later phases are full intensity")
	assert_eq(Soundscape.boss_mix({}, "the_source")[2], 1.0, "the Source always sings")
	assert_eq(Soundscape.boss_mix({}, "colonel_hale")[2], 0.0, "Hale doesn't")


func test_combat_info_reads_the_views() -> void:
	var s := make_state(["runner", "spitter"])
	var v: MissionView = load("res://scenes/main.tscn").instantiate()
	v.auto_start = false
	v.start(s, false)
	for uv in v.unit_views.values():
		uv.visible = uv.is_soldier
	var info := Soundscape.combat_info(v)
	assert_eq(info.visible, 0, "hidden enemies don't count")
	var shown := 0
	for uv in v.unit_views.values():
		if not uv.is_soldier:
			uv.visible = true
			shown += 1
	info = Soundscape.combat_info(v)
	assert_eq(info.visible, shown, "visible enemies count")
	assert_true(info.threat >= float(shown), "threat grows with them")
	v.free()
