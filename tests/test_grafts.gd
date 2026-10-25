extends TestCase
## Grafts: body-part slots, Machine Refits and Bloom parts (progression/grafts.gd).

const OPEN := ["..........", "..........", "..........", "........##", "........#."]


## A 1-player run in Act 2 with a Rank 3 trooper, in the NODE phase.
func _run(kind := "trooper", act := 2, rank := 3) -> RunState:
	var run := RunRules.new_run(1, 41, {}, {0: kind})
	GearRun.init_run(run)
	run.act = act
	run.phase = RunState.Phase.NODE
	run.supplies = 200
	run.squad()[0].prog.rank = rank
	return run


func _rec(run: RunState) -> Dictionary:
	return run.squad()[0]


## Blank open map, team phase on turn 1, one soldier of `kind` at (0, 0) wearing `grafts`.
func _state(kind: String, grafts: Dictionary, infection := 0) -> GameState:
	var s := make_blank(PackedStringArray(OPEN))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	var u := s.add_unit(UnitData.make(kind, Types.Team.PLAYER), Vector2i(0, 0))
	u.owner_player = 0
	u.actions_left = Types.ACTIONS_PER_TURN
	var p := Progression.new_record(kind)
	p.grafts = grafts.duplicate()
	Progression.apply_record(u, p)
	u.infection = infection
	Infection.sync_passives(u)
	Kit.refresh_stats(s, u)
	s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 4))
	return s


func _me(s: GameState) -> Unit:
	return s.living(Types.Team.PLAYER)[0]


func test_data_has_one_of_each_path_per_slot() -> void:
	for slot in GraftData.SLOTS:
		for path in [GraftData.MACHINE, GraftData.BLOOM]:
			var id := GraftData.for_slot(slot, path)
			assert_true(id != "", "%s %s graft" % [slot, path])
			var d := GraftData.get_def(id)
			assert_true(d.name != "" and d.desc != "" and d.look != "", "%s has text" % id)
			assert_true(Progression.TAGS.has(d.tag), "%s tag" % id)


func test_grafts_open_from_act_2_and_rank_3() -> void:
	assert_eq(Grafts.eligible_error(_run("trooper", 1, 3), _rec(_run("trooper", 1, 3))), "Grafts open in Act 2", "act gate")
	var low := _run("trooper", 2, 2)
	assert_eq(Grafts.eligible_error(low, _rec(low)), "Needs Rank 3", "rank gate")
	var run := _run()
	assert_eq(Grafts.eligible_error(run, _rec(run)), "", "eligible")
	for slot in GraftData.SLOTS:
		Grafts.take(_rec(run), GraftData.for_slot(slot, GraftData.MACHINE))
	assert_eq(Grafts.eligible_error(run, _rec(run)), "Every slot is grafted", "full")


func test_machine_beds_in_and_bloom_costs_infection() -> void:
	var run := _run()
	var r := _rec(run)
	Grafts.take(r, "targeting_optic")
	assert_true(r.prog.bedding, "beds in")
	assert_eq(r.infection, 0, "machine adds no Infection")
	Grafts.take(r, "bloom_limb")
	assert_eq(r.infection, GraftData.BLOOM_INFECTION, "+15")
	assert_eq(Grafts.can_take_error(run, r, "servo_arm"), "Arm slot is taken", "slot is for life")
	var v := _run("vector")
	Grafts.take(_rec(v), "heart_knot")
	assert_eq(_rec(v).infection, GraftData.VECTOR_BLOOM_INFECTION, "Vector pays less")
	assert_eq(Grafts.refit_price(_rec(_run("hazmat"))), GraftData.HAZMAT_REFIT_PRICE, "Hazmat refits cheaper")
	var ribs := _run()
	var hp: int = _rec(ribs).max_hp
	Grafts.take(_rec(ribs), "plated_ribs")
	assert_eq(_rec(ribs).max_hp, hp + GraftData.RIBS_HP, "ribs HP on the record")


func test_bloom_floor_survives_serum_and_purges() -> void:
	var run := _run()
	var r := _rec(run)
	Grafts.take(r, "bloom_limb")
	Grafts.take(r, "runner_legs")
	assert_eq(Grafts.record_floor(r), 20, "10 per Bloom part")
	RunAccess.set_infection(run, r, 0)
	assert_eq(r.infection, 20, "purge stops at the floor")
	Progression.full_cure(r)
	assert_eq(r.infection, 20, "Serum stops at the floor")
	assert_eq(Grafts.of(r).size(), 2, "Serum keeps grafts")
	var s := _state("trooper", {"arm": "bloom_limb"}, 30)
	var u := _me(s)
	Infection.add(s, u, -50)
	assert_eq(u.infection, 10, "in a fight too")
	ClassAbilities.cure(s, u)
	assert_eq(u.infection, 10, "mid-fight Serum too")


func test_machine_parts_cut_infection_gain() -> void:
	var s := _state("trooper", {"head": "targeting_optic", "arm": "servo_arm", "chest": "plated_ribs", "legs": "hydraulic_legs"})
	var u := _me(s)
	Infection.add(s, u, 10)
	assert_eq(u.infection, 7, "-30% at most")
	var one := _state("trooper", {"arm": "servo_arm"})
	Infection.add(one, _me(one), 10)
	assert_eq(_me(one).infection, 9, "-10% per part")


func test_machine_stats_and_jam() -> void:
	var base := _state("trooper", {})
	var s := _state("trooper", {"head": "targeting_optic", "legs": "hydraulic_legs"})
	var u := _me(s)
	assert_eq(u.aim, _me(base).aim + GraftData.OPTIC_AIM, "+15 aim")
	assert_eq(u.mobility, _me(base).mobility + 1, "+1 move")
	var shrieker := s.add_unit(UnitData.make("shrieker", Types.Team.ENEMY), Vector2i(3, 0))
	s.phase = Types.Phase.ENEMY
	Grafts.jam(s, shrieker, 6.0)
	assert_eq(u.aim, _me(base).aim, "jammed optic")
	assert_eq(u.mobility, _me(base).mobility, "jammed legs")
	assert_true(s.log.any(func(e): return e.type == "jammed"), "jam event")
	var p := Progression.new_record("trooper")
	p.grafts = {"head": "targeting_optic"}
	p.bedding = true
	var fresh := UnitData.make("trooper", Types.Team.PLAYER)
	var plain := UnitData.make("trooper", Types.Team.PLAYER)
	Progression.apply_record(fresh, p)
	Progression.apply_record(plain, Progression.new_record("trooper"))
	assert_eq(fresh.mobility, plain.mobility + GraftData.BEDDING_MOBILITY, "beds in: -1 move")
	Progression.after_fight(p, fresh, 2)
	assert_true(not p.bedding, "bedded in after a fight")


func test_plated_ribs_halve_spitter_infection() -> void:
	var s := _state("trooper", {"chest": "plated_ribs"})
	var u := _me(s)
	var spitter := s.add_unit(UnitData.make("spitter", Types.Team.ENEMY), Vector2i(2, 2))
	var plain := _state("trooper", {})
	var pu := _me(plain)
	var ps := plain.add_unit(UnitData.make("spitter", Types.Team.ENEMY), Vector2i(2, 2))
	Infection.on_damaged(s, u, spitter, 2)
	Infection.on_damaged(plain, pu, ps, 2)
	assert_true(u.infection > 0 and u.infection < pu.infection, "halved (and cut 10%%): %d vs %d" % [u.infection, pu.infection])


func test_bloom_claw_strikes_and_heals_on_kill() -> void:
	var s := _state("trooper", {"arm": "bloom_limb"}, 55)
	var u := _me(s)
	assert_true(u.abilities.has("bloom_claw"), "claw granted")
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(1, 0))
	foe.hp = 1
	u.hp = u.max_hp - 2
	var hit := false
	for i in 20:   # roll until it lands
		if not foe.is_alive():
			break
		u.actions_left = 2
		u.cooldowns.erase("bloom_claw")
		var a := {"type": Types.ABILITY, "unit": u.id, "ability": "bloom_claw", "target": foe.id}
		assert_eq(Rules.validate(s, a), "", "claw usable")
		Rules.apply(s, a)
		hit = not foe.is_alive()
	assert_true(hit, "claw kills")
	assert_eq(u.hp, u.max_hp - 1, "kill heals 1")


func test_runner_leap_ignores_overwatch_once_per_fight() -> void:
	var s := _state("trooper", {"legs": "runner_legs"})
	var u := _me(s)
	var watcher := s.add_unit(UnitData.make("spitter", Types.Team.ENEMY), Vector2i(5, 2))
	watcher.overwatch = true
	var a := {"type": Types.ABILITY, "unit": u.id, "ability": "runner_leap", "cell": Vector2i(3, 1)}
	assert_eq(Rules.validate(s, a), "", "leap usable")
	assert_true(Rules.apply(s, a), "leap")
	assert_eq(u.pos, Vector2i(3, 1), "landed")
	assert_true(not s.log.any(func(e): return e.type == "shot" or e.get("reaction", false)), "no reaction shot")
	var again := {"type": Types.ABILITY, "unit": u.id, "ability": "runner_leap", "cell": Vector2i(4, 1)}
	assert_true(Rules.validate(s, again) != "", "once per fight")
	assert_true(Rules.validate(s, {"type": Types.ABILITY, "unit": u.id, "ability": "runner_leap", "cell": Vector2i(3, 9)}) != "", "range")


func test_heart_knot_regenerates_and_slows_melee() -> void:
	var s := _state("trooper", {"chest": "heart_knot"}, 55)
	var u := _me(s)
	u.hp = u.max_hp - 2
	Kit.on_team_phase_start(s)
	assert_eq(u.hp, u.max_hp - 1, "+1 HP at Mutating")
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(1, 0))
	var mob := foe.mobility
	Kit.after_melee(s, foe, u, 2)
	assert_eq(foe.mobility, mob + GraftData.HEART_SLOW, "attacker slowed")


func test_lattice_sight_senses_through_walls() -> void:
	var s := _state("trooper", {"head": "lattice_sight"})
	assert_eq(Vision.sense_radius(_me(s)), GraftData.LATTICE_RADIUS, "sense radius")


func test_targeting_optic_tags_last_longer() -> void:
	var s := _state("marksman", {"head": "targeting_optic"})
	var plain := _state("marksman", {})
	for st in [s, plain]:
		var foe: Unit = st.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(4, 0))
		Rules.apply(st, {"type": Types.ABILITY, "unit": _me(st).id, "ability": "tag", "target": foe.id})
	var a: int = s.units[-1].status.get("tagged", 0)
	var b: int = plain.units[-1].status.get("tagged", 0)
	assert_eq(a, b + 2, "one turn longer")


func test_hydraulic_legs_climb_ladders_for_one() -> void:
	var g := Grid.from_rows(PackedStringArray(["....", "...."]))
	g.levels.resize(g.width * g.height)
	g.levels[1] = 1
	g.ladders[Vector2i(0, 0)] = true
	assert_eq(g.step_cost(Vector2i(0, 0), Vector2i(1, 0)), Grid.LADDER_COST, "ladder")
	assert_eq(g.step_cost(Vector2i(0, 0), Vector2i(1, 0), {}, false, true), 1, "free climb")


func test_tags_count_for_set_bonuses() -> void:
	var run := _run()
	Grafts.take(_rec(run), "plated_ribs")
	Grafts.take(_rec(run), "hydraulic_legs")
	assert_eq(int(Progression.tag_counts(_rec(run)).get("Guard", 0)), 2, "Guard from two grafts")


func test_hospital_refit_and_amputate() -> void:
	var run := _run()
	var r := _rec(run)
	Grafts.take(r, "bloom_limb")
	var ns := NodeRules.enter(run, "hospital")
	var offered: String = ns.refits.get(r.id, "")
	assert_true(offered != "" and GraftData.path_of(offered) == GraftData.MACHINE, "a Machine part on offer")
	assert_true(FieldHospital.options(ns, r).has("refit") and FieldHospital.options(ns, r).has("amputate"), "both tiles")
	var supplies := run.supplies
	assert_true(NodeRules.apply(run, {"type": "node_treat", "player": 0, "soldier": r.id, "treatment": "refit"}), "refit")
	assert_eq(Grafts.of(r)[GraftData.slot_of(offered)], offered, "grafted")
	assert_eq(run.supplies, supplies - GraftData.REFIT_PRICE, "paid")
	assert_eq(run.outbreak, 0, "refit raises no Outbreak")
	var run2 := _run()
	var r2 := _rec(run2)
	Grafts.take(r2, "bloom_limb")
	r2.hp = r2.max_hp
	NodeRules.enter(run2, "hospital")
	assert_true(NodeRules.apply(run2, {"type": "node_treat", "player": 0, "soldier": r2.id, "treatment": "amputate"}), "amputate")
	assert_eq(Grafts.of(r2).arm, "servo_arm", "Bloom limb swapped for a Servo arm")
	assert_eq(r2.hp, r2.max_hp - GraftData.AMPUTATE_HP, "costs HP")
	assert_eq(Grafts.record_floor(r2), 0, "floor gone with the part")
	var early := _run("trooper", 1, 3)
	var ens := NodeRules.enter(early, "hospital")
	assert_true(not FieldHospital.options(ens, _rec(early)).has("refit"), "no refit in Act 1")


func test_depot_sells_a_refit() -> void:
	var run := _run()
	var ns := NodeRules.enter(run, "depot")
	var i: int = ns.stock.find_custom(func(e): return e.type == "graft")
	assert_true(i >= 0, "a Refit in stock")
	var id: String = ns.stock[i].id
	assert_true(NodeRules.apply(run, {"type": "node_buy", "player": 0, "index": i, "soldier": _rec(run).id}), "bought")
	assert_eq(Grafts.of(_rec(run)).get(GraftData.slot_of(id), ""), id, "grafted")
	var early := _run("trooper", 1, 3)
	var ens := NodeRules.enter(early, "depot")
	assert_true(not ens.stock.any(func(e): return e.type == "graft"), "none in Act 1")


func test_nest_and_critical_offer_a_bloom_card() -> void:
	var run := _run()
	run.phase = RunState.Phase.REWARD
	GearRun.on_fight_won(run, "nest")
	var cards: Array = GearRun.offer_for(run, _rec(run).id).cards
	var card: Dictionary = cards[-1]
	assert_eq(card.kind, "graft", "Bloom card after a nest")
	assert_eq(card.path, GraftData.BLOOM, "Bloom path")
	assert_true(GearRun.apply(run, {"type": "gear_pick", "player": 0, "soldier": _rec(run).id, "card": cards.size() - 1}), "picked")
	assert_eq(Grafts.of(_rec(run)).get(card.slot, ""), card.id, "grafted")
	var calm := _run()
	GearRun.on_fight_won(calm, "skirmish")
	assert_true(not GearRun.offer_for(calm, _rec(calm).id).cards.any(func(c): return c.kind == "graft"), "not after a calm skirmish")
	var hot := _run()
	_rec(hot).infection = 80
	GearRun.on_fight_won(hot, "skirmish")
	assert_true(GearRun.offer_for(hot, _rec(hot).id).cards.any(func(c): return c.kind == "graft"), "offered at Critical")


func test_choir_stall_roots_a_bloom_graft() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "choir_stall")
	var r := _rec(run)
	var pv := EventRules.preview(run, run.node_state, "root", 0, r.id)
	assert_true(pv.get(r.id, {}).has("graft"), "preview names the graft")
	assert_true(NodeRules.apply(run, {"type": "node_choose", "player": 0, "option": "root", "soldier": r.id}), "chosen")
	assert_eq(Grafts.count(Grafts.of(r), GraftData.BLOOM), 1, "took root")


func test_echo_wears_its_grafts() -> void:
	var s := _state("trooper", {})
	var plain := Story.setup_echo(s, {"key": "a", "kind": "trooper", "name": "Reyes"})
	var dressed := Story.setup_echo(s, {"key": "b", "kind": "trooper", "name": "Okafor",
		"grafts": {"arm": "bloom_limb", "chest": "heart_knot", "legs": "hydraulic_legs"}})
	assert_eq(Grafts.of_unit(dressed).size(), 3, "wears them")
	assert_eq(dressed.max_hp, plain.max_hp + 2 * Story.ECHO_BLOOM_HP, "Bloom parts make it tougher")
	assert_eq(dressed.mobility, plain.mobility - 1, "Machine parts slow it")
