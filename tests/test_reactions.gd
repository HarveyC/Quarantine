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
