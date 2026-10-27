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
		if Weapons.is_alternate(id):
			assert_true(GunFeel.FEEL.has(Weapons.look_of(id)) and GunFeel.VARIANTS.has(id), "%s has a gun feel" % id)
		else:
			assert_true(GunFeel.FEEL.has(id), "%s has a gun feel" % id)
	for id in Weapons.TABLE:
		var feel: Dictionary = GunFeel.for_weapon(id)
		for key in ["sound", "tail", "mech", "whiz"]:
			if feel.has(key):
				assert_true(Sfx.SOUNDS.has(feel[key]), "%s %s listed" % [id, feel[key]])
				assert_true(ResourceLoader.exists("res://audio/%s.wav" % feel[key]), "%s %s file" % [id, feel[key]])


func test_every_gun_feels_its_own() -> void:
	var GunFeel := load("res://view/gun_feel.gd")
	var reports := {}
	for id in Weapons.TABLE:
		var feel: Dictionary = GunFeel.for_weapon(id)
		assert_true(not reports.has(feel.sound), "%s has its own report (shared with %s)" % [id, reports.get(feel.sound, "")])
		reports[feel.sound] = id
		assert_true(str(feel.get("proj", "tracer")) in ["tracer", "heavy", "pellet", "slug", "flechette", "bio", "spore", "dart", "bolt"],
			"%s projectile style" % id)
		assert_true(str(feel.get("impact", "spark")) in ["spark", "heavy", "slug", "pellet", "needle", "bio", "dart", "shock"],
			"%s impact style" % id)
		assert_true(GunFeel.casing_of(feel) in ["", "brass", "big", "shell", "link", "cell"], "%s casing" % id)
		assert_true(str(feel.get("flash_style", "star")) in ["star", "cone", "brake", "bio", "quiet", "gas"], "%s flash style" % id)
	var lmg: Dictionary = GunFeel.for_weapon("lmg")
	assert_eq(GunFeel.proj_of(lmg, 1, 6), "ball", "LMG fires ball rounds between tracers")
	assert_eq(GunFeel.proj_of(lmg, 5, 6), "tracer", "the deciding round is always a tracer")
	assert_true(GunFeel.round_offset(lmg, 2, 0.1) > 0.2, "the LMG's rhythm stretches its burst")


func test_alternate_guns_are_well_formed() -> void:
	var GunModels := load("res://view/gun_models.gd")
	for id in Weapons.TABLE:
		if not Weapons.is_alternate(id):
			continue
		var g: Dictionary = Weapons.TABLE[id]
		assert_true(g.rarity in ["uncommon", "rare"], "%s rarity" % id)
		assert_true(GearData.TAGS.has(g.tag), "%s tag" % id)
		assert_true(Weapons.TABLE.has(g.look) and not Weapons.is_alternate(g.look), "%s look is a signature gun" % id)
		# Melee classes hold one-handed alternates in the sidearm's hand (view/melee_kit.gd).
		assert_true(GunModels.GUNS.has(g.look) or g.look in ["sidearm", "revolver"], "%s look has a model" % id)
		if g.look in ["sidearm", "revolver"]:
			assert_true(g.classes.all(func(k): return k in ["reaper", "warden"]), "%s pistol is melee-only" % id)
		for k in g.classes:
			assert_true(UnitData.SOLDIERS.has(k) or k in ["reaper", "warden"], "%s class %s" % [id, k])
	for kind in ["trooper", "marksman", "medic", "breacher", "hazmat", "vector", "reaper", "warden"]:
		assert_true(Weapons.alternates_for(kind).size() >= 2, "%s has at least 2 alternate guns" % kind)


func test_alternate_gun_changes_the_shot() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var m := _add(s, "marksman", Types.Team.PLAYER, Vector2i(0, 0))
	var aim := m.aim
	var dmg := m.damage
	var mob := m.mobility
	Weapons.equip_unit(m, "anti_materiel")
	assert_eq(Weapons.id_of(m), "anti_materiel", "carries the alternate")
	assert_eq(m.damage, dmg + Vector2i(2, 2), "+2 damage")
	assert_eq(m.mobility, mob - 1, "-1 movement")
	assert_eq(m.aim, aim, "aim unchanged")
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 0))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(15, 0))
	assert_eq(_term(Combat.hit_chance(s, m, near), "Too close to scope"), -20, "scope penalty out to 3")
	assert_eq(_term(Combat.hit_chance(s, m, far), "Long range"), null, "no falloff to 16")
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(0, 1))
	Weapons.equip_unit(t, "dmr")
	assert_eq(Weapons.id_of(t), "rifle", "a gun the class can't carry is ignored")


func test_auto_shotgun_pins_on_a_miss() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(0, 0))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(2, 0))
	assert_true(not Weapons.has_trait(b, "pin"), "signature shotgun doesn't pin")
	Weapons.equip_unit(b, "auto_shotgun")
	assert_true(Weapons.has_trait(b, "pin"), "auto shotgun pins")
	Weapons.after_miss(s, b, t)
	assert_true(t.status.has("suppressed"), "pinned")


func _armed(s: GameState, kind: String, gun: String, at: Vector2i) -> Unit:
	var u := _add(s, kind, Types.Team.PLAYER, at)
	Weapons.equip_unit(u, gun)
	Ammo.setup(u)
	return u


func _foe(s: GameState, at: Vector2i, hp := 30) -> Unit:
	var e := _add(s, "runner", Types.Team.ENEMY, at)
	e.max_hp = hp
	e.hp = hp
	return e


func test_pierce_carries_on_for_half_damage() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var u := _armed(s, "marksman", "anti_materiel", Vector2i(0, 0))
	var a := _foe(s, Vector2i(3, 0))
	var b := _foe(s, Vector2i(4, 0))
	Weapons.after_hit(s, u, a, 6, false)
	assert_eq(b.hp, 27, "the next enemy in line takes half")


func test_heavy_rounds_shove_and_close_quarters_return_a_round() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	var u := _armed(s, "trooper", "battle_rifle", Vector2i(0, 0))
	var a := _foe(s, Vector2i(3, 0))
	Weapons.after_hit(s, u, a, 3, false)
	assert_eq(a.pos, Vector2i(4, 0), "pushed a tile")
	var md := _add(s, "medic", Types.Team.PLAYER, Vector2i(0, 1))
	Ammo.setup(md)
	md.status["ammo"] = 2
	var d := _foe(s, Vector2i(2, 1), 1)
	d.hp = 0
	Weapons.after_hit(s, md, d, 2, false)
	assert_eq(Ammo.rounds(md), 3, "a close kill gives the round back")


func test_breach_and_door_kicker_take_cover_away() -> void:
	var s := make_blank(PackedStringArray(["........", "........"]))
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(0, 0))
	var bd: Array = []
	Weapons.odds_terms(s, b, _foe(s, Vector2i(2, 0)), b.pos, Types.Cover.FULL, bd)
	assert_eq(_term({"breakdown": bd}, "Breach"), Combat.COVER_FULL, "cover gone within 2 tiles")
	var far: Array = []
	Weapons.odds_terms(s, b, _foe(s, Vector2i(6, 0)), b.pos, Types.Cover.FULL, far)
	assert_eq(_term({"breakdown": far}, "Breach"), null, "but not further out")
	var sl := _armed(s, "breacher", "slug_gun", Vector2i(0, 1))
	var half: Array = []
	Weapons.odds_terms(s, sl, _foe(s, Vector2i(6, 1)), sl.pos, Types.Cover.HALF, half)
	assert_eq(_term({"breakdown": half}, "Door kicker"), Combat.COVER_HALF, "slugs ignore half cover")


func test_skirmisher_barbs_tranq_and_recoil() -> void:
	var s := make_blank(PackedStringArray(OPEN))
	s.turn = 2
	var sc := _armed(s, "marksman", "scout_carbine", Vector2i(0, 0))
	sc.status["gear_moved_turn"] = 2
	sc.status["gear_move_len"] = 4
	assert_true(Weapons.skirmish_free(s, sc), "a long move frees the first shot")
	assert_true(not Weapons.skirmish_free(s, sc), "only once a turn")
	var fl := _armed(s, "medic", "flechette_smg", Vector2i(0, 1))
	var e := _foe(s, Vector2i(2, 1))
	Weapons.after_hit(s, fl, e, 2, false)
	var start := e.pos
	e.pos = Vector2i(5, 1)
	var hp := e.hp
	Weapons.barbs_tick(s, e, start)
	assert_eq(e.hp, hp - 1, "a moving enemy pays for its barb")
	var dr := _armed(s, "medic", "dart_rifle", Vector2i(0, 0))
	var f := _foe(s, Vector2i(3, 0))
	Weapons.after_hit(s, dr, f, 2, false)
	assert_true(not f.status.get("k_skip_turn", false), "one hit does nothing")
	Weapons.after_hit(s, dr, f, 2, false)
	assert_true(f.status.get("k_skip_turn", false), "the second stuns")
	var hc := _armed(s, "reaper", "hand_cannon", Vector2i(0, 1))
	var g := _foe(s, Vector2i(2, 1))
	Weapons.after_hit(s, hc, g, 3, true)
	assert_true(g.status.get("k_skip_turn", false), "a crit ends its turn")
