extends TestCase
## Magazines: every soldier gun has a size, shots spend rounds, Reload refills for one action,
## an empty gun can't shoot, watch or Suppress, and the gear, perks and mutation that touch it.

const OPEN := [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]
const U_AT := Vector2i(2, 2)
const FOE_AT := Vector2i(7, 2)


func _state() -> GameState:
	var s := make_blank(PackedStringArray(OPEN))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	return s


func _soldier(s: GameState, kind := "trooper", at := U_AT) -> Unit:
	var u := s.add_unit(UnitData.make(kind, Types.Team.PLAYER), at)
	u.owner_player = 0
	u.actions_left = Types.ACTIONS_PER_TURN
	Ammo.setup(u)
	return u


func _foe(s: GameState, at := FOE_AT) -> Unit:
	var e := s.add_unit(UnitData.make("spitter", Types.Team.ENEMY), at)
	e.max_hp = 60
	e.hp = 60
	return e


func _geared(u: Unit, items: Array) -> void:
	GearTags.set_progression(null)
	var rec := {"id": u.id, "kind": u.kind}
	var run := {"supplies": 0, "soldiers": [rec]}
	for it in items:
		Loadout.equip(run, rec, it)
	GearRun.apply_to_unit(u, rec)
	GearTags.set_progression(false)


func _shoot(s: GameState, u: Unit, t: Unit) -> bool:
	return Rules.apply(s, {"type": Types.SHOOT, "unit": u.id, "target": t.id})


func _reload(s: GameState, u: Unit) -> bool:
	return Rules.apply(s, {"type": Types.RELOAD, "unit": u.id})


func test_every_gun_has_a_magazine() -> void:
	for id in Weapons.TABLE:
		assert_true(int(Weapons.TABLE[id].get("mag", 0)) > 0, "%s has a mag size" % id)


func test_soldiers_start_loaded_and_enemies_never_run_dry() -> void:
	var s := make_state(["runner"])
	for u in s.living(Types.Team.PLAYER):
		assert_true(Ammo.tracked(u), "%s has a magazine" % u.kind)
		assert_eq(Ammo.rounds(u), Ammo.mag_size(u), "%s starts full" % u.kind)
	for e in s.living(Types.Team.ENEMY):
		assert_true(not Ammo.tracked(e) and Ammo.can_fire(e), "enemies are unlimited")


func test_a_shot_spends_a_round_and_the_event_says_how_many_are_left() -> void:
	var s := _state()
	var u := _soldier(s)
	var foe := _foe(s)
	var before := Ammo.rounds(u)
	var shots: Array = []
	s.event.connect(func(ev): if ev.type == "shot": shots.append(ev))
	assert_true(_shoot(s, u, foe), "shot accepted")
	assert_eq(Ammo.rounds(u), before - 1, "one round spent")
	assert_eq(int(shots[0].ammo), before - 1, "the event carries the count")


func test_an_empty_gun_cannot_shoot_or_watch_until_reloaded() -> void:
	var s := _state()
	var u := _soldier(s)
	var foe := _foe(s)
	u.status["ammo"] = 0
	assert_eq(Rules.validate(s, {"type": Types.SHOOT, "unit": u.id, "target": foe.id}), "Out of ammo", "no shot")
	assert_eq(Rules.validate(s, {"type": Types.OVERWATCH, "unit": u.id}), "Out of ammo", "no watch")
	assert_true(_reload(s, u), "reload accepted")
	assert_eq(Ammo.rounds(u), Ammo.mag_size(u), "magazine full")
	assert_eq(u.actions_left, 1, "a reload costs one action")
	assert_eq(Rules.validate(s, {"type": Types.SHOOT, "unit": u.id, "target": foe.id}), "", "shoots again")


func test_a_full_magazine_has_nothing_to_reload() -> void:
	var s := _state()
	var u := _soldier(s)
	assert_eq(Rules.validate(s, {"type": Types.RELOAD, "unit": u.id}), "Magazine is full", "full")


func test_overwatch_reactions_spend_rounds_and_a_dry_gun_does_not_react() -> void:
	var s := _state()
	var u := _soldier(s)
	var foe := _foe(s)
	u.overwatch = true
	var before := Ammo.rounds(u)
	assert_true(Combat.reactions_to_move(s, foe, Vector2i(6, 2)).has(u), "loaded gun reacts")
	Combat.resolve_reactions(s, foe, [u])
	assert_eq(Ammo.rounds(u), before - 1, "reaction spent a round")
	u.overwatch = true
	u.status["ammo"] = 0
	assert_true(not Combat.reactions_to_move(s, foe, Vector2i(6, 2)).has(u), "dry gun stays quiet")


func test_suppress_spends_two_rounds_and_belt_fed_none() -> void:
	var s := _state()
	var u := _soldier(s)
	var foe := _foe(s)
	var before := Ammo.rounds(u)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "suppress", "target": foe.id}), "suppress")
	assert_eq(Ammo.rounds(u), before - Ammo.SUPPRESS_ROUNDS, "two rounds")
	var s2 := _state()
	var h := _soldier(s2, "hazmat")
	h.status["perks"] = ["belt_fed"]
	Ammo.setup(h)
	h.abilities.append("suppress")
	var foe2 := _foe(s2)
	var full := Ammo.rounds(h)
	assert_eq(full, Weapons.TABLE.lmg.mag + Ammo.BELT_FED, "belt fed adds rounds")
	assert_true(Rules.apply(s2, {"type": Types.ABILITY, "unit": h.id, "ability": "suppress", "target": foe2.id}), "suppress")
	assert_eq(Ammo.rounds(h), full, "Belt Fed spends none")


func test_a_lapsed_soldier_never_runs_dry() -> void:
	var s := _state()
	var u := _soldier(s)
	u.status["ammo"] = 0
	u.ai_controlled = true
	assert_true(Ammo.can_fire(u), "AI soldiers are unlimited")


func test_bandolier_adds_rounds() -> void:
	var s := _state()
	var u := _soldier(s)
	var base := Ammo.mag_size(u)
	var t := _soldier(s, "trooper", Vector2i(3, 3))
	t.status["perks"] = ["bandolier"]
	Ammo.setup(t)
	assert_eq(Ammo.rounds(t), base + Ammo.BANDOLIER, "Bandolier")


func test_speed_loader_makes_the_first_reload_each_turn_free() -> void:
	var s := _state()
	var u := _soldier(s)
	_foe(s)
	_geared(u, ["speed_loader"])
	u.status["ammo"] = 1
	assert_true(_reload(s, u), "reload")
	assert_eq(u.actions_left, 2, "free")
	u.status["ammo"] = 1
	assert_true(_reload(s, u), "second reload")
	assert_eq(u.actions_left, 1, "the second one costs")


func test_shell_game_reload_is_always_free() -> void:
	var s := _state()
	var u := _soldier(s, "breacher")
	u.status["perks"] = ["shell_game"]
	u.status["ammo"] = 0
	assert_true(_reload(s, u), "reload")
	assert_eq(u.actions_left, 2, "no action spent")


func test_scavenger_rounds_give_one_back_on_a_kill() -> void:
	var s := _state()
	var u := _soldier(s)
	_geared(u, ["scavenger_rounds"])
	var foe := _foe(s)
	foe.hp = 1
	foe.max_hp = 1
	u.aim = 500   # sure hit
	var before := Ammo.rounds(u)
	assert_true(_shoot(s, u, foe), "shot")
	assert_true(not foe.is_alive(), "dead")
	assert_eq(Ammo.rounds(u), before, "spent one, got one back")


func test_fresh_mag_perk_gives_aim_on_the_turn_you_reload() -> void:
	var s := _state()
	var u := _soldier(s, "marksman")
	u.status["perks"] = ["fresh_mag"]
	var foe := _foe(s)
	u.status["ammo"] = 1
	var plain := int(Combat.hit_chance(s, u, foe).hit)
	assert_true(_reload(s, u), "reload")
	assert_eq(int(Combat.hit_chance(s, u, foe).hit), mini(100, plain + Kit.FRESH_MAG_AIM), "+15 aim")


func test_bone_magazine_wakes_with_infection_and_costs_it_per_reload() -> void:
	var s := _state()
	var u := _soldier(s)
	u.status["mutations"] = {"exposed": "bone_magazine"}
	Infection.add(s, u, 30)
	Ammo.setup(u)
	assert_eq(Ammo.mag_size(u), Weapons.TABLE.rifle.mag + Ammo.BONE_MAG, "awake bonus")
	u.status["ammo"] = 1
	var inf := u.infection
	assert_true(_reload(s, u), "reload")
	assert_eq(u.infection, inf + Ammo.BONE_MAG_INFECTION, "the reload costs Infection")


func test_lockdown_reloads_the_gun() -> void:
	var s := _state()
	var u := _soldier(s)
	u.abilities.append("lockdown")
	u.status["ammo"] = 1
	_foe(s)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "lockdown"}), "lockdown")
	assert_eq(Ammo.rounds(u), Ammo.mag_size(u), "full magazine")
