extends TestCase

const OPEN := [
	"................",
	"................",
]


func _add(s: GameState, kind: String, team: int, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
	return u


func _term(odds: Dictionary, label: String) -> Variant:
	for t in odds.breakdown:
		if t[0] == label:
			return t[1]
	return null


func test_every_class_has_a_distinct_weapon() -> void:
	var seen := {}
	for kind in UnitData.SOLDIERS:
		var id := Weapons.id_for(kind)
		assert_true(Weapons.TABLE.has(id), "%s weapon %s exists" % [kind, id])
		assert_true(not seen.has(id), "%s shares a weapon with %s" % [kind, seen.get(id, "")])
		seen[id] = kind


func test_marksman_rifle_has_no_range_falloff_but_hates_close_range() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var m := _add(s, "marksman", Types.Team.PLAYER, Vector2i(0, 0))
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(2, 0))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(13, 0))
	assert_eq(_term(Combat.hit_chance(s, m, far), "Long range"), null, "no long range penalty at 13")
	assert_eq(_term(Combat.hit_chance(s, m, near), "Too close to scope"), -10, "scope penalty up close")
	assert_eq(Combat.hit_chance(s, m, far).crit, Combat.FLANK_CRIT + 15, "DMR crit bonus")


func test_shotgun_and_pdw_are_close_range_weapons() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(0, 0))
	var md := _add(s, "medic", Types.Team.PLAYER, Vector2i(0, 1))
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 0))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(9, 0))
	assert_eq(_term(Combat.hit_chance(s, b, near), "Close range"), 25, "shotgun close bonus")
	assert_eq(_term(Combat.hit_chance(s, b, far), "Long range"), -32, "shotgun falloff past 5")
	b.aim = 30
	assert_eq(Combat.hit_chance(s, b, near).graze, 20, "shotgun spread widens the graze band")
	var odds := Combat.hit_chance(s, md, far, Vector2i(0, 0))
	assert_eq(_term(odds, "Long range"), -10, "PDW falloff past 7")


func test_lmg_miss_pins_the_target() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var h := _add(s, "hazmat", Types.Team.PLAYER, Vector2i(0, 0))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(5, 0))
	var events: Array = []
	s.event.connect(func(ev): events.append(ev))
	h.aim = -500   # always miss
	Combat.fire(s, h, t, false)
	assert_true(Combat.has_status(s, t, "suppressed"), "target pinned")
	assert_true(events.any(func(e): return e.type == "pinned"), "pinned event")
	var tr := _add(s, "trooper", Types.Team.PLAYER, Vector2i(0, 1))
	var t2 := _add(s, "runner", Types.Team.ENEMY, Vector2i(5, 1))
	tr.aim = -500
	Combat.fire(s, tr, t2, false)
	assert_true(not Combat.has_status(s, t2, "suppressed"), "rifle misses do not pin")


func test_carbine_snap_shots_skip_reaction_penalty() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var v := _add(s, "vector", Types.Team.PLAYER, Vector2i(0, 0))
	var tr := _add(s, "trooper", Types.Team.PLAYER, Vector2i(0, 1))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 0))
	assert_eq(Combat.hit_chance(s, v, t, v.pos, true).hit, Combat.hit_chance(s, v, t).hit, "no reaction penalty")
	assert_eq(_term(Combat.hit_chance(s, tr, t, tr.pos, true), "Reaction shot"), -Combat.REACTION_PENALTY, "rifle keeps it")


func test_enemies_use_matching_weapons() -> void:
	assert_eq(Weapons.id_for("sharpshooter"), "dmr", "sharpshooter has a DMR")
	assert_eq(Weapons.id_for("fallen"), "rifle", "fallen have rifles")
	assert_eq(Weapons.id_for("brute"), Weapons.DEFAULT, "unknown kinds use the default")


func test_every_gun_sound_exists() -> void:
	var GunFeel := load("res://view/gun_feel.gd")
	var Sfx := load("res://view/sfx.gd")
	for id in Weapons.TABLE:
		assert_true(GunFeel.FEEL.has(id), "%s has a gun feel" % id)
	for id in GunFeel.FEEL:
		var feel: Dictionary = GunFeel.FEEL[id]
		for key in ["sound", "tail", "mech"]:
			if feel.has(key):
				assert_true(Sfx.SOUNDS.has(feel[key]), "%s %s listed" % [id, feel[key]])
				assert_true(ResourceLoader.exists("res://audio/%s.wav" % feel[key]), "%s %s file" % [id, feel[key]])
