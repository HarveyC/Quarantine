extends TestCase
## Rank 2 signature abilities: one per class, unlocked at Rank 2, each a cooldown ability that
## carries a gear tag.

const OPEN := [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]


func _state() -> GameState:
	var s := make_blank(PackedStringArray(OPEN), 99)
	s.turn = 1
	s.phase = Types.Phase.TEAM
	return s


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, Types.Team.PLAYER), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	u.owner_player = 0
	u.abilities.append(Signatures.for_class(kind))
	return u


func _foe(s: GameState, at: Vector2i, hp: int = 40) -> Unit:
	var e := s.add_unit(UnitData.make("fallen", Types.Team.ENEMY), at)
	e.max_hp = hp
	e.hp = hp
	e.status["alerted"] = true
	return e


func _use(s: GameState, u: Unit, id: String, target: Unit = null) -> bool:
	var action := {"type": Types.ABILITY, "unit": u.id, "ability": id}
	if target != null:
		action["target"] = target.id
	return Rules.apply(s, action)


func test_every_class_has_one_signature_with_tags_and_a_cooldown() -> void:
	assert_eq(Signatures.OF_CLASS.size(), UnitData.SOLDIERS.size(), "one per class")
	for kind in UnitData.SOLDIERS:
		var id := Signatures.for_class(kind)
		assert_true(ClassAbilities.ABILITIES.has(id), "%s signature is defined" % kind)
		assert_true(int(ClassAbilities.ABILITIES[id].cooldown) >= 4, "%s signature recharges slowly" % kind)
		assert_true(not (Signatures.TAGS[id] as Array).is_empty(), "%s signature has a tag" % kind)
		for tag in Signatures.TAGS[id]:
			assert_true(GearData.TAG_INFO.has(tag), "%s is a real tag" % tag)


func test_signature_unlocks_at_rank_three() -> void:
	assert_eq(Signatures.UNLOCK_RANK, 3, "after the third fight")
	for kind in ["trooper", "vector"]:
		var u1 := UnitData.make(kind, Types.Team.PLAYER)
		Progression.apply_record(u1, {"kind": kind, "rank": Signatures.UNLOCK_RANK - 1, "perks": []})
		assert_true(not u1.abilities.has(Signatures.for_class(kind)), "%s has no signature one rank early" % kind)
		var u2 := UnitData.make(kind, Types.Team.PLAYER)
		Progression.apply_record(u2, {"kind": kind, "rank": Signatures.UNLOCK_RANK, "perks": []})
		assert_true(u2.abilities.has(Signatures.for_class(kind)), "%s gets it at Rank 3" % kind)
		assert_true(u2.status.get("sig_new", false), "and it is flagged as new")


func test_new_flag_clears_once_the_signature_is_used() -> void:
	var s := _state()
	var t := _soldier(s, "trooper", Vector2i(3, 2))
	t.status["sig_new"] = true
	var entry := ClassAbilities.available(s, t).filter(func(e): return e.id == "lockdown")
	assert_true(not entry.is_empty() and entry[0].get("new", false), "new before first use")
	_use(s, t, "lockdown")
	var after := ClassAbilities.available(s, t).filter(func(e): return e.id == "lockdown")
	assert_true(after.is_empty() or not after[0].get("new", false), "not new after use")
	var prog := {"kind": "trooper", "rank": 3, "perks": []}
	Progression.after_fight(prog, t, 99)
	assert_true(prog.get("sig_used", false), "the run record remembers it was used")


func test_intro_shows_once_at_the_unlock_rank() -> void:
	var rec := {"kind": "medic", "prog": {"rank": Signatures.UNLOCK_RANK}}
	assert_eq(Signatures.intro_for(rec), "quarantine_field", "shown at the unlock rank")
	rec.prog["sig_seen"] = true
	assert_eq(Signatures.intro_for(rec), "", "not shown again")
	assert_eq(Signatures.intro_for({"kind": "medic", "prog": {"rank": 2}}), "", "not before")


func test_deadeye_never_misses_and_marks() -> void:
	var s := _state()
	var m := _soldier(s, "marksman", Vector2i(1, 2))
	var foe := _foe(s, Vector2i(10, 2))
	Vision.refresh(s)
	assert_true(_use(s, m, "deadeye", foe), "deadeye")
	assert_true(foe.hp <= 40 - (m.damage.x + Signatures.DEADEYE_BONUS), "hit for the bonus")
	assert_true(Combat.has_status(s, foe, "tagged"), "marked")
	assert_true(int(m.cooldowns.get("deadeye", 0)) >= 4, "on cooldown")


func test_death_sweep_hits_all_adjacent_and_a_kill_resets_lunge() -> void:
	var s := _state()
	var r := _soldier(s, "reaper", Vector2i(3, 3))
	r.abilities.append("lunge")
	r.cooldowns["lunge"] = 2
	var weak := _foe(s, Vector2i(4, 3), 2)
	var tough := _foe(s, Vector2i(2, 3))
	Vision.refresh(s)
	assert_true(_use(s, r, "death_sweep"), "sweep")
	assert_true(not (weak.is_alive()), "the weak one dies")
	assert_eq(tough.hp, 40 - Signatures.SWEEP_DAMAGE, "the other takes 3")
	assert_true(tough.status.has("k_bleed"), "and bleeds")
	assert_true(not (r.cooldowns.has("lunge")), "Lunge reset")
	assert_true(r.actions_left >= Types.ACTIONS_PER_TURN, "action refunded")


func test_flashover_needs_fire_and_spends_it() -> void:
	var s := _state()
	var h := _soldier(s, "hazmat", Vector2i(1, 2))
	var foe := _foe(s, Vector2i(5, 2))
	var near := _foe(s, Vector2i(6, 2))
	Vision.refresh(s)
	assert_true(ClassAbilities.validate(s, h, {"ability": "flashover"}) != "", "nothing burning yet")
	foe.status["burning"] = 2
	assert_eq(ClassAbilities.validate(s, h, {"ability": "flashover"}), "", "now it can fire")
	assert_true(_use(s, h, "flashover"), "flashover")
	assert_eq(foe.hp, 40 - Signatures.FLASHOVER_DAMAGE, "burning enemy erupts")
	assert_eq(near.hp, 40 - Signatures.FLASHOVER_SPLASH, "neighbour splashed")
	assert_true(not (foe.status.has("burning")), "fire spent")


func test_vent_spends_own_infection_for_damage() -> void:
	var s := _state()
	var v := _soldier(s, "vector", Vector2i(3, 2))
	v.infection = 60
	var foe := _foe(s, Vector2i(4, 2))
	Vision.refresh(s)
	assert_true(_use(s, v, "vent"), "vent")
	assert_eq(v.infection, 35, "25 Infection gone")
	assert_true(foe.hp < 40, "enemy hurt")
	var clean := _soldier(s, "vector", Vector2i(8, 4))
	clean.infection = 5
	assert_true(ClassAbilities.validate(s, clean, {"ability": "vent"}) != "", "needs 10 Infection")


func test_quarantine_field_blocks_infection() -> void:
	var s := _state()
	var m := _soldier(s, "medic", Vector2i(3, 2))
	assert_true(_use(s, m, "quarantine_field"), "field")
	Infection.add(s, m, 20)
	assert_eq(m.infection, 0, "no Infection inside")
	m.pos = Vector2i(10, 4)
	Infection.add(s, m, 20)
	assert_eq(m.infection, 20, "gains it outside the field")


func test_provoke_pulls_aggro_and_cuts_damage() -> void:
	var s := _state()
	var w := _soldier(s, "warden", Vector2i(3, 2))
	var other := _soldier(s, "trooper", Vector2i(3, 3))
	var foe := _foe(s, Vector2i(6, 2))
	assert_true(_use(s, w, "provoke"), "provoke")
	assert_true(Kit.target_bias(s, foe, w) > Kit.target_bias(s, foe, other), "enemies pick the Warden")
	assert_eq(Kit.modify_incoming(s, w, 3, foe), 2, "one less damage")
	assert_eq(Kit.modify_incoming(s, other, 3, foe), 3, "others unchanged")


func test_lockdown_keeps_overwatch_and_pins() -> void:
	var s := _state()
	var t := _soldier(s, "trooper", Vector2i(3, 2))
	var foe := _foe(s, Vector2i(9, 2))
	Vision.refresh(s)
	assert_true(_use(s, t, "lockdown"), "lockdown")
	assert_true(t.overwatch, "on overwatch")
	s.phase = Types.Phase.ENEMY
	foe.actions_left = Types.ACTIONS_PER_TURN
	Rules.move_along(s, foe, Vector2i(7, 2))
	assert_true(t.overwatch, "still watching after the shot")


func test_bring_down_hits_target_and_neighbours() -> void:
	var s := _state()
	var b := _soldier(s, "breacher", Vector2i(2, 2))
	var foe := _foe(s, Vector2i(5, 2))
	var near := _foe(s, Vector2i(6, 2))
	Vision.refresh(s)
	assert_true(_use(s, b, "bring_down", foe), "bring down")
	assert_eq(foe.hp, 40 - Signatures.BRING_DOWN_DAMAGE, "4 to the target")
	assert_eq(near.hp, 40 - Signatures.BRING_DOWN_SPLASH, "2 to the neighbour")
	assert_eq(b.actions_left, 0, "ends the turn")
