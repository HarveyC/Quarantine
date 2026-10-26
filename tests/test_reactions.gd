extends TestCase
## Status reactions: pairs of statuses that fire without any gear. Never listed in the UI; the
## hit-chance breakdown, a label or the fire shows them when they happen.

const OPEN := [
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
	"..........",
]


func _setup() -> Dictionary:
	var s := make_blank(PackedStringArray(OPEN))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	var u := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(2, 2))
	u.owner_player = 0
	var foe := s.add_unit(UnitData.make("spitter", Types.Team.ENEMY), Vector2i(4, 2))
	foe.max_hp = 30
	foe.hp = 30
	return {"s": s, "u": u, "foe": foe}


func test_crosshair_marked_enemy_is_easier_to_hit_on_overwatch() -> void:
	var x := _setup()
	var plain := 0
	for t in Combat.hit_chance(x.s, x.u, x.foe, x.u.pos, true).breakdown:
		if t[0] == "Crosshair":
			plain = t[1]
	assert_eq(plain, 0, "no term on an unmarked enemy")
	x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
	var got := 0
	for t in Combat.hit_chance(x.s, x.u, x.foe, x.u.pos, true).breakdown:
		if t[0] == "Crosshair":
			got = t[1]
	assert_eq(got, GearFx.CROSSHAIR_AIM, "Crosshair term on a Marked enemy")


func test_pinned_suppressed_enemy_takes_extra_close_damage() -> void:
	var x := _setup()
	x.foe.pos = x.u.pos + Vector2i(6, 0)
	assert_eq(GearFx.shot_damage(x.s, x.u, x.foe, 3, false), 3, "far, not suppressed")
	x.foe.status["suppressed"] = Combat.phase_index(x.s) + 2
	assert_eq(GearFx.shot_damage(x.s, x.u, x.foe, 3, false), 3, "suppressed but far")
	x.foe.pos = x.u.pos + Vector2i(2, 0)
	assert_eq(GearFx.shot_damage(x.s, x.u, x.foe, 3, false), 4, "suppressed and close: +1")


func test_flare_up_burning_enemy_in_smoke_sets_fire_around_it() -> void:
	var x := _setup()
	Hazards.add(x.s, [x.foe.pos], "smoke", 2, x.u.id)
	x.foe.status["burning"] = 2
	GearFx.on_team_phase_start(x.s)
	assert_eq(Hazards.at(x.s, x.foe.pos + Vector2i(1, 0)).get("kind", ""), "fire", "fire spread to the next tile")


func test_resonance_is_a_small_aim_bonus_for_committing_to_one_tag() -> void:
	var x := _setup()
	x.u.status["gear_tags"] = {"Mark": 1}
	assert_eq(GearFx.resonance_aim(x.u), 0, "one piece: nothing")
	x.u.status["gear_tags"] = {"Mark": 4, "Burn": 2}
	assert_eq(GearFx.resonance_aim(x.u), 6, "four pieces of a tag: +6")
	x.u.status["gear_tags"] = {"Mark": 9}
	assert_eq(GearFx.resonance_aim(x.u), GearFx.RESONANCE_CAP, "capped")


func test_guard_and_purge_sets_ward_infection() -> void:
	var x := _setup()
	var buddy: Unit = x.s.add_unit(UnitData.make("medic", Types.Team.PLAYER), Vector2i(3, 2))
	buddy.owner_player = 0
	buddy.status["gear"] = {}
	assert_eq(GearFx.infection_gain(x.s, x.u, 20), 20, "no wards")
	buddy.status["gear_tags"] = {"Guard": GearData.SET_THRESHOLD}
	assert_eq(GearFx.infection_gain(x.s, x.u, 20), 15, "Guard-set neighbour: a quarter less")
	buddy.status["gear_tags"] = {"Guard": GearData.SET_THRESHOLD, "Purge": GearData.SET_THRESHOLD}
	assert_eq(GearFx.infection_gain(x.s, x.u, 20), 12, "Guard and Purge wards multiply, rounded up")
	buddy.pos = Vector2i(9, 5)
	assert_eq(GearFx.infection_gain(x.s, x.u, 20), 20, "out of range: no ward")
