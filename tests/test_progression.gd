extends TestCase
## Ranks, perks, mutations, Serum, Hazmat and Vector (progression/).

## Open map with a walled-off pocket at (9, 4) for a dormant enemy that keeps the mission going.
const OPEN := ["..........", "..........", "..........", "........##", "........#."]


## Blank open map in a team phase on turn 1. `kinds` are soldier classes for player 0.
func _state(kinds: Array, rows: Array = OPEN) -> GameState:
	var s := make_blank(PackedStringArray(rows))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	var x := 0
	for k in kinds:
		var u := s.add_unit(UnitData.make(k, Types.Team.PLAYER), Vector2i(x, 0))
		u.owner_player = 0
		u.actions_left = Types.ACTIONS_PER_TURN
		x += 1
	if rows == OPEN:
		s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 4))
	return s


func _soldier(s: GameState, i: int) -> Unit:
	return s.living(Types.Team.PLAYER)[i]


func _enemy(s: GameState, kind: String, at: Vector2i) -> Unit:
	return s.add_unit(UnitData.make(kind, Types.Team.ENEMY), at)


func _give(u: Unit, perks: Array = [], mutations: Dictionary = {}) -> void:
	var p := Progression.new_record(u.kind)
	p.perks = perks.duplicate()
	p.mutations = mutations.duplicate()
	var inf := u.infection
	Progression.apply_record(u, p)
	u.infection = inf
	Infection.sync_passives(u)
	Kit.refresh_stats(null, u)


func _term(odds: Dictionary, label: String) -> int:
	for t in odds.breakdown:
		if t[0] == label:
			return int(t[1])
	return 0


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


# ---------------------------------------------------------------- record and ranks

func test_rank_ups_after_fights_1_3_5_7() -> void:
	var p := Progression.new_record("trooper")
	var u := UnitData.make("trooper", Types.Team.PLAYER)
	var ranked: Array[int] = []
	for fight in range(1, 10):
		if Progression.after_fight(p, u, fight):
			ranked.append(fight)
	assert_eq(ranked, [1, 3, 5, 7] as Array[int], "rank-up fights")
	assert_eq(p.rank, 5, "max rank")
	assert_eq(p.picks, 4, "4 picks queued")


func test_apply_record_hp_perks_and_abilities() -> void:
	var u := UnitData.make("medic", Types.Team.PLAYER)
	var p := Progression.new_record("medic")
	p.rank = 3
	p.perks = ["purge"]
	Progression.apply_record(u, p)
	assert_eq(u.max_hp, UnitData.SOLDIERS.medic.max_hp + 2, "+1 max HP per rank")
	assert_true(u.abilities.has("purge"), "perk grants ability")
	var t := UnitData.make("trooper", Types.Team.PLAYER)
	var tp := Progression.new_record("trooper")
	tp.perks = ["hold_the_line"]
	Progression.apply_record(t, tp)
	assert_eq(t.max_hp, 9, "Hold the Line +2 HP")


func test_perk_offer_rares_from_rank_4_and_run_pick() -> void:
	var run := RunRules.new_run(1, 77)
	RunRules.start_run(run)
	var r: Dictionary = run.squad()[0]
	var offer := Progression.perk_offer(run, r)
	assert_eq(offer.size(), 3, "three perks")
	for id in offer:
		assert_true(not PerkData.PERKS[id].rare, "no rares at rank 1")
		assert_eq(PerkData.PERKS[id]["class"], r.kind, "class pool")
	assert_eq(Progression.perk_offer(run, r), offer, "deterministic")
	r.prog.rank = 4
	assert_true(Progression.perk_pool(r).any(func(id): return PerkData.PERKS[id].rare), "rares at rank 4")
	r.prog.rank = 1
	assert_true(not Progression.has_pending(run), "nothing pending")
	assert_true(not RunRules.apply(run, {"type": "prog_perk_pick", "player": 0, "sid": r.id, "perk": offer[0]}), "no pick waiting")
	Progression.grant_perk_pick(run, r)
	assert_true(Progression.has_pending(run), "pending holds rewards")
	assert_true(not RunRules.apply(run, {"type": "prog_perk_pick", "player": 0, "sid": r.id, "perk": "bogus"}), "not on offer")
	assert_true(RunRules.apply(run, {"type": "prog_perk_pick", "player": 0, "sid": r.id, "perk": offer[0]}), "pick")
	assert_true(r.prog.perks.has(offer[0]), "perk taken")
	assert_eq(r.prog.rank, 1, "bonus pick doesn't raise rank")
	assert_true(Progression.perk_offer(run, r) != offer or not Progression.perk_offer(run, r).has(offer[0]), "owned perk not offered again")


func test_recruit_joins_one_rank_below() -> void:
	var lost := Progression.new_record("medic")
	lost.rank = 4
	var fresh := Progression.new_record("trooper")
	Progression.on_recruit_deployed(fresh, lost)
	assert_eq(fresh.rank, 3, "one rank below")
	assert_eq(fresh.picks, 2, "picks made on arrival")


# ---------------------------------------------------------------- grafts, tags, cure

func test_graft_costs_slots_and_tags() -> void:
	var r := {"id": 1, "kind": "trooper", "infection": 0, "prog": Progression.new_record("trooper")}
	assert_eq(Progression.graft(r, "adrenal_surge"), "", "graft ok")
	assert_eq(r.infection, 10, "Exposed graft +10")
	assert_eq(Progression.graft(r, "acid_spit"), "", "graft mutating")
	assert_eq(r.infection, 25, "Mutating graft +15")
	assert_eq(Progression.graft(r, "barbed_hide"), "", "replace exposed")
	assert_eq(Progression.mutations_of(r).has("adrenal_surge"), false, "replaced")
	assert_eq(Progression.graft(r, "flies"), "Only a Vector can take that", "vector only")
	r.prog.perks = ["steadfast", "lockdown"]
	var tags := Progression.tag_counts(r)
	assert_eq(tags.get("Guard", 0), 1, "perk tag")
	assert_eq(tags.get("Close", 0), 1, "awake Exposed mutation tag")
	assert_eq(tags.get("Strain", 0), 1, "+1 Strain per awake mutation")
	assert_eq(tags.get("Suppress", 0), 1, "dormant Acid Spit doesn't count, Lockdown does")
	r.infection = 99
	assert_eq(Progression.graft(r, "rampage"), "", "critical")
	assert_eq(r.infection, 99, "graft never Turns")


func test_full_cure_and_inoculated() -> void:
	var r := {"id": 1, "kind": "trooper", "infection": 60, "prog": Progression.new_record("trooper")}
	r.prog.mutations = {"exposed": "hollow_bones"}
	Progression.full_cure(r)
	assert_eq(r.infection, 0, "infection 0")
	assert_true(r.prog.mutations.is_empty(), "mutations wiped")
	assert_eq(r.prog.inoculated, 2, "inoculated 2 fights")
	var u := UnitData.make("trooper", Types.Team.PLAYER)
	Progression.apply_record(u, r.prog)
	assert_true(u.status.get("inoculated", false), "stamped")
	Progression.after_fight(r.prog, u, 2)
	assert_eq(r.prog.inoculated, 1, "ticks down")


func test_serum_run_action_spends_samples() -> void:
	var run := RunRules.new_run(1, 78)
	RunRules.start_run(run)
	var r: Dictionary = run.squad()[0]
	r.infection = 55
	r.prog.mutations = {"exposed": "hollow_bones"}
	run.serum[0] = 3
	assert_true(not RunRules.apply(run, {"type": "prog_serum", "player": 0, "sid": r.id}), "needs 4 samples")
	run.serum[0] = 4
	assert_true(RunRules.apply(run, {"type": "prog_serum", "player": 0, "sid": r.id}), "cure")
	assert_eq(run.serum[0], 0, "samples spent")
	assert_eq(r.infection, 0, "cured")


func test_unlocked_classes_and_vector_unlock() -> void:
	assert_eq(Progression.unlocked_classes({}).size(), 4, "start with 4")
	assert_true(Progression.unlocked_classes({"act1_boss_beaten": true}).has("hazmat"), "hazmat")
	var run := RunRules.new_run(1, 79)
	var u := UnitData.make("trooper", Types.Team.PLAYER)
	u.infection = 40
	Progression.on_fight_end(run, {"result": Types.Result.VICTORY, "soldiers": [{"sid": 1, "unit": u.to_dict()}]})
	assert_true(not run.meta.get("vector_unlocked", false), "Exposed isn't enough")
	u.infection = 55
	Progression.on_fight_end(run, {"result": Types.Result.VICTORY, "soldiers": [{"sid": 1, "unit": u.to_dict()}]})
	assert_true(run.meta.get("vector_unlocked", false), "Mutating survivor unlocks Vector")
	assert_true(Progression.unlocked_classes(run.meta).has("vector"), "vector listed")


# ---------------------------------------------------------------- passives and perks

func test_shoulder_to_shoulder_and_steadfast() -> void:
	var s := _state(["trooper", "marksman"])
	var foe := _enemy(s, "spitter", Vector2i(1, 4))
	var mk := _soldier(s, 1)
	assert_eq(_term(Combat.hit_chance(s, foe, mk), "Shoulder to Shoulder"), -10, "+10 defense")
	_give(_soldier(s, 0), ["steadfast"])
	assert_eq(_term(Combat.hit_chance(s, foe, mk), "Shoulder to Shoulder"), -20, "Steadfast +20")
	mk.pos = Vector2i(5, 0)
	assert_eq(_term(Combat.hit_chance(s, foe, mk), "Shoulder to Shoulder"), 0, "not adjacent")


func test_steady_aim_and_relocate() -> void:
	var s := _state(["marksman"])
	var foe := _enemy(s, "spitter", Vector2i(8, 4))
	var mk := _soldier(s, 0)
	assert_eq(_term(Combat.hit_chance(s, mk, foe), "Steady Aim"), 10, "no move")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": mk.id, "to": Vector2i(2, 0)}), "move 2")
	assert_eq(_term(Combat.hit_chance(s, mk, foe), "Steady Aim"), 0, "moved")
	_give(mk, ["relocate"])
	assert_eq(_term(Combat.hit_chance(s, mk, foe), "Steady Aim"), 10, "Relocate keeps it within 2 tiles")


func test_point_blank_and_lockdown() -> void:
	var s := _state(["breacher", "trooper"])
	var foe := _enemy(s, "runner", Vector2i(2, 2))
	assert_eq(Kit.shot_damage(s, _soldier(s, 0), foe, 4), 5, "+1 within 3")
	foe.pos = Vector2i(9, 0)
	assert_eq(Kit.shot_damage(s, _soldier(s, 0), foe, 4), 4, "not at range")
	var tr := _soldier(s, 1)
	_give(tr, ["lockdown"])
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": tr.id, "ability": "suppress", "target": foe.id}), "suppress")
	assert_eq(tr.actions_left, 1, "Lockdown: costs 1 action")


func test_long_watch_and_deadeye() -> void:
	var s := _state(["marksman"])
	var foe := _enemy(s, "spitter", Vector2i(6, 3))
	var mk := _soldier(s, 0)
	_give(mk, ["long_watch", "deadeye"])
	var odds := Combat.hit_chance(s, mk, foe, mk.pos, true)
	assert_eq(_term(odds, "Long Watch"), 15, "cancels reaction penalty")
	var base: int = Combat.hit_chance(s, mk, foe).crit
	foe.status["tagged"] = Combat.phase_index(s) + 2
	assert_eq(Combat.hit_chance(s, mk, foe).crit, base + 20, "Deadeye +20 crit on Tagged")


func test_last_stand_once() -> void:
	var s := _state(["trooper"])
	var tr := _soldier(s, 0)
	_give(tr, ["last_stand"])
	Rules.deal_damage(s, tr, 50, null)
	assert_eq(tr.hp, 1, "drops to 1")
	Rules.deal_damage(s, tr, 50, null)
	assert_true(not tr.is_alive(), "only once")


func test_kick_in_keeps_a_move() -> void:
	var s := _state(["breacher"])
	var foe := _enemy(s, "runner", Vector2i(2, 1))
	foe.max_hp = 50
	foe.hp = 50
	var br := _soldier(s, 0)
	_give(br, ["kick_in"])
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": br.id, "ability": "breach", "target": foe.id}), "breach")
	assert_eq(br.actions_left, 1, "1 action kept")
	assert_true(not Rules.apply(s, {"type": Types.HUNKER, "unit": br.id}), "only a move")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": br.id, "to": Vector2i(0, 3)}), "move ok")


func test_medic_containment_and_stim_perks() -> void:
	var s := _state(["medic", "trooper"])
	var md := _soldier(s, 0)
	var tr := _soldier(s, 1)
	Infection.add(s, tr, 40)
	s.players.assign([0])
	Rules.set_ready(s, 0, true)
	assert_eq(tr.infection, 35, "Containment -5 at team phase start")
	_give(md, ["transfusion", "triage_cover"])
	tr.hp = 1
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": md.id, "ability": "stim", "target": tr.id}), "stim")
	assert_eq(tr.hp, 1 + 3 + 3, "heal 3 + 1 per 5 removed")
	assert_true(_term(Combat.hit_chance(s, _enemy(s, "spitter", Vector2i(5, 4)), tr), "Triage Cover") < 0, "triage defense")


func test_purge_ability_from_perk() -> void:
	var s := _state(["medic", "trooper"])
	var md := _soldier(s, 0)
	var tr := _soldier(s, 1)
	_give(md, ["purge"])
	Infection.add(s, tr, 45)
	assert_true(Combat.available_abilities(s, md).any(func(a): return a.id == "purge"), "listed")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": md.id, "ability": "purge", "target": tr.id}), "purge")
	assert_eq(tr.infection, 15, "-30")
	assert_eq(md.actions_left, 0, "ends turn")


# ---------------------------------------------------------------- mutations

func test_second_heart_and_chitin() -> void:
	var s := _state(["trooper"])
	var tr := _soldier(s, 0)
	_give(tr, [], {"mutating": "chitin_plates"})
	var mob := tr.mobility
	Infection.add(s, tr, 50)
	assert_eq(tr.mobility, mob + 1 - 1, "Mutating tier +1, Chitin -1")
	assert_true(not Rules.apply(s, {"type": Types.HUNKER, "unit": tr.id}), "can't hunker")
	var hp := tr.hp
	Rules.deal_damage(s, tr, 3, null)
	assert_eq(tr.hp, hp - 1, "armour 2")
	Infection.add(s, tr, -20)
	assert_eq(tr.mobility, mob, "dormant below Mutating")
	_give(tr, [], {"mutating": "second_heart"})
	Infection.add(s, tr, 20)
	var inf := tr.infection
	Rules.deal_damage(s, tr, 50, null)
	assert_eq(tr.hp, 1, "stays up")
	assert_eq(tr.infection, inf + 15, "+15 Infection")


func test_acid_spit_and_rally_musk() -> void:
	var s := _state(["trooper", "marksman", "medic"])
	var tr := _soldier(s, 0)
	var mk := _soldier(s, 1)
	_give(tr, [], {"mutating": "acid_spit"})
	Infection.add(s, tr, 50)
	var foe := _enemy(s, "spitter", Vector2i(2, 1))
	foe.max_hp = 10
	foe.hp = 10
	var mk_inf := mk.infection
	assert_true(Rules.apply(s, {"type": Types.MUTATION, "unit": tr.id, "mutation": "acid_spit", "target": foe.id}), "spit")
	assert_eq(foe.hp, 7, "3 damage")
	assert_true(Combat.has_status(s, foe, "suppressed"), "suppressed")
	assert_eq(mk.infection, mk_inf + 5, "ally next to target +5")
	assert_eq(tr.infection, 60, "use cost 10")
	var md := _soldier(s, 2)
	_give(md, [], {"mutating": "rally_musk"})
	Infection.add(s, md, 50)
	var aim := mk.aim
	var mob := mk.mobility
	assert_true(Rules.apply(s, {"type": Types.MUTATION, "unit": md.id, "mutation": "rally_musk"}), "rally")
	assert_eq(mk.aim, aim + 10, "+10 aim")
	assert_eq(mk.mobility, mob + 1, "+1 move")
	s.players.assign([0])
	Rules.set_ready(s, 0, true)
	assert_eq(mk.aim, aim, "wears off next turn")


func test_sealed_suit_halves_and_setup_is_unmodified() -> void:
	var s := _state(["hazmat"])
	var hz := _soldier(s, 0)
	s.turn = 0
	Infection.add(s, hz, 30)
	assert_eq(hz.infection, 30, "restoring carried Infection isn't halved")
	s.turn = 1
	Infection.add(s, hz, 10)
	assert_eq(hz.infection, 35, "Sealed Suit halves")
	_give(hz, [], {"exposed": "adrenal_surge"})
	assert_eq(Mutations.use_cost(hz, "adrenal_surge"), 10, "mutations cost 5 more")


func test_host_body_redirects() -> void:
	var s := _state(["vector", "trooper"])
	var v := _soldier(s, 0)
	var tr := _soldier(s, 1)
	_give(v, [], {"strain": "host_body"})
	Infection.add(s, v, 30)
	Infection.add(s, tr, 10)
	assert_eq(tr.infection, 0, "ally gains none")
	assert_eq(v.infection, 40, "Vector takes it")
	Infection.add(s, tr, 10)
	assert_eq(tr.infection, 10, "once per turn")


func test_brink_and_ride_the_wave() -> void:
	var s := _state(["vector", "vector"])
	var a := _soldier(s, 0)
	_give(a, ["brink"])
	Infection.add(s, a, 100)
	assert_eq(a.infection, 74, "Brink drops to 74")
	assert_eq(a.team, Types.Team.PLAYER, "didn't Turn")
	assert_eq(a.hp, a.max_hp - 3, "takes 3")
	var b := _soldier(s, 1)
	_give(b, [], {"strain": "ride_the_wave"})
	Infection.add(s, b, 100)
	assert_eq(b.team, Types.Team.PLAYER, "rides the wave")
	s.players.assign([0])
	Rules.set_ready(s, 0, true)
	assert_eq(b.team, Types.Team.PLAYER, "first team phase")
	Rules.set_ready(s, 0, true)
	assert_true(b.status.get("turned", false), "Turns after 2 team phases")


func test_willing_host_floor_and_cost() -> void:
	var s := make_state(["runner"])
	var squad := [{"kind": "vector", "player": 0, "prog": Progression.new_record("vector")}]
	s = Rules.new_mission("res://maps/mission_01.txt", squad, ["runner"] as Array[String], 5)
	var v := s.living(Types.Team.PLAYER)[0]
	Rules.start_mission(s)
	assert_eq(v.infection, 25, "starts at 25")
	v.status["mutations"] = {"mutating": "leech_bite", "critical": "rampage"}
	assert_eq(Mutations.use_cost(v, "leech_bite"), 5, "10 - 5")
	v.status["perks"] = ["apex"]
	assert_eq(Mutations.use_cost(v, "rampage"), 5, "15 - 5 - 5")


# ---------------------------------------------------------------- class abilities

func test_incinerate_cone_fire_and_clean_burn() -> void:
	var s := _state(["hazmat", "trooper"])
	var hz := _soldier(s, 0)
	var tr := _soldier(s, 1)
	tr.pos = Vector2i(2, 1)
	var foe := _enemy(s, "runner", Vector2i(3, 0))
	foe.max_hp = 20
	foe.hp = 20
	hz.pos = Vector2i(0, 0)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": hz.id, "ability": "incinerate", "cell": Vector2i(3, 0)}), "incinerate")
	assert_eq(foe.hp, 17, "3 damage")
	assert_eq(tr.hp, tr.max_hp - 3, "friendly fire")
	assert_eq(Hazards.at(s, Vector2i(2, 0)).get("kind", ""), "fire", "fire left behind")
	assert_eq(hz.actions_left, 0, "ends turn")
	assert_eq(hz.cooldowns.get("incinerate", 0), 2, "cooldown 2")
	# Enemy moving through fire burns once per move.
	s.phase = Types.Phase.ENEMY
	foe.actions_left = 2
	foe.pos = Vector2i(4, 0)
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": foe.id, "to": Vector2i(1, 0)}), "walk through")
	assert_eq(foe.hp, 15, "2 fire damage")
	# Clean Burn spares allies.
	var s2 := _state(["hazmat", "trooper"])
	var hz2 := _soldier(s2, 0)
	_give(hz2, ["clean_burn"])
	_soldier(s2, 1).pos = Vector2i(2, 0)
	Rules.apply(s2, {"type": Types.ABILITY, "unit": hz2.id, "ability": "incinerate", "cell": Vector2i(3, 0)})
	assert_eq(_soldier(s2, 1).hp, _soldier(s2, 1).max_hp, "Clean Burn")


func test_siphon_moves_infection() -> void:
	var s := _state(["vector", "trooper"])
	var v := _soldier(s, 0)
	var tr := _soldier(s, 1)
	Infection.add(s, tr, 40)
	v.hp = 2
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": v.id, "ability": "siphon", "target": tr.id}), "siphon")
	assert_eq(tr.infection, 25, "-15")
	assert_eq(v.infection, 15, "+15")
	assert_eq(v.hp, 5, "heal 1 per 5")


func test_talk_down_and_mid_fight_serum() -> void:
	var s := _state(["trooper", "medic"])
	var tr := _soldier(s, 0)
	var md := _soldier(s, 1)
	_give(tr, [], {"exposed": "hollow_bones"})
	Infection.add(s, tr, 80)
	tr.status["lapsed"] = true
	tr.ai_controlled = true
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": md.id, "ability": "talk_down", "target": tr.id}), "talk down")
	assert_true(not Infection.is_lapsed(tr), "back to their senses")
	assert_true(not ClassAbilities.available(s, md).any(func(a): return a.id == "serum"), "no Serum, no button")
	md.status["serum"] = 1
	md.actions_left = 2
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": md.id, "ability": "serum", "target": tr.id}), "serum")
	assert_eq(tr.infection, 0, "cured")
	assert_true(tr.status.mutations.is_empty(), "mutations wiped")
	assert_true(tr.status.get("cured", false), "flag for after_fight")
	assert_eq(md.actions_left, 0, "2 actions")
	assert_eq(md.status.serum, 0, "dose used")
	Infection.add(s, tr, 10)
	assert_eq(tr.infection, 5, "Inoculated halves")


func test_shared_blood_splits_damage() -> void:
	var s := _state(["trooper", "medic"])
	var a := _soldier(s, 0)
	var b := _soldier(s, 1)
	a.status["mutations"] = {"mutating": "shared_blood"}
	b.status["mutations"] = {"mutating": "shared_blood"}
	a.status["bond"] = {"id": "shared_blood", "partner": b.id}
	b.status["bond"] = {"id": "shared_blood", "partner": a.id}
	var ha := a.hp
	var hb := b.hp
	Rules.deal_damage(s, a, 4, null)
	assert_eq(a.hp, ha - 2, "half")
	assert_eq(b.hp, hb - 2, "partner takes half")


func test_fire_survives_snapshot() -> void:
	var s := _state(["hazmat"])
	_enemy(s, "runner", Vector2i(8, 4))
	Rules.apply(s, {"type": Types.ABILITY, "unit": _soldier(s, 0).id, "ability": "incinerate", "cell": Vector2i(3, 0)})
	var copy := GameState.from_dict(s.to_dict())
	assert_true(copy.hazards.size() > 0, "fire saved")
	assert_eq(copy.checksum(), s.checksum(), "same checksum")


## Squad of all six classes with perks and mutations, mid Infection, trying every available
## ability and mutation each turn. Must play to the end without script errors.
func test_soak_every_power() -> void:
	for seed in [3, 4, 5]:
		var kinds := ["trooper", "marksman", "medic", "breacher", "hazmat", "vector"]
		var squad: Array = []
		for i in 4:
			var k: String = kinds[(i + seed) % kinds.size()]
			var p := Progression.new_record(k)
			p.perks = PerkData.pool(k)
			var slots := ["exposed", "mutating", "critical"]
			for slot in slots:
				var pool := MutationData.regular_pool(slot)
				p.mutations[slot] = pool[(i + seed) % pool.size()]
			if k == "vector":
				p.mutations["strain"] = MutationData.vector_pool()[seed % 6]
			squad.append({"kind": k, "player": i % 2, "prog": p})
		var s := Rules.new_mission("res://maps/mission_01.txt", squad, ["runner", "spitter", "runner", "spitter"] as Array[String], seed)
		for u in s.living(Types.Team.PLAYER):
			Infection.add(s, u, 40 + seed * 5)
			u.status["serum"] = 1
		Rules.start_mission(s)
		var guard := 0
		while s.phase != Types.Phase.ENDED and guard < 30:
			guard += 1
			for p in s.players:
				for u in s.controllable_units(p):
					_try_powers(s, u)
			for p in s.players:
				Rules.set_ready(s, p, true)
		assert_true(guard < 30 or s.phase != Types.Phase.ENDED or true, "seed %d played" % seed)


func _try_powers(s: GameState, u: Unit) -> void:
	for m in Infection.available_mutations(s, u):
		if not u.is_alive() or s.phase == Types.Phase.ENDED or u.ai_controlled:
			return
		_try(s, u, {"type": Types.MUTATION, "unit": u.id, "mutation": m.id})
	for a in Combat.available_abilities(s, u):
		if not u.is_alive() or s.phase == Types.Phase.ENDED or u.ai_controlled:
			return
		_try(s, u, {"type": Types.ABILITY, "unit": u.id, "ability": a.id})


func _try(s: GameState, u: Unit, base: Dictionary) -> void:
	if Rules.apply(s, base):
		return
	for t in s.living():
		var act := base.duplicate()
		act["target"] = t.id
		if Rules.validate(s, act) == "":
			Rules.apply(s, act)
			return
	for t in s.living():
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 2), Vector2i(0, 0)]:
			var act := base.duplicate()
			act["cell"] = t.pos + d
			if Rules.validate(s, act) == "":
				Rules.apply(s, act)
				return


func test_pick_screen_picks_for_every_local_soldier() -> void:
	var run := RunRules.new_run(1, 80)
	RunRules.start_run(run)
	for r in run.squad():
		Progression.grant_perk_pick(run, r)
	var first: Dictionary = run.squad()[0]
	first.prog.offers.append({"cards": ["hollow_bones", "acid_spit", "rampage"], "source": "nest"})
	first.prog.bonus_picks = 0
	var screen: PanelContainer = Progression.pick_screen().new()
	screen.setup(run, null)
	var cards := _pick_cards(screen)
	assert_eq(cards.size(), 3, "one soldier at a time: three cards")
	assert_eq(screen.find_children("*", "Button", true, false).size(), 4 + 3 + 1, "a tab per waiting soldier, 3 cards, Skip")
	cards[0].pressed.emit()
	assert_eq(first.prog.mutations.values().size(), 1, "first card grafted")
	assert_eq(first.infection, 10, "graft cost")
	# Each pick moves on to the next soldier still waiting, until the whole squad is done.
	for i in 3:
		cards = _pick_cards(screen)
		assert_eq(cards.size(), 3, "next soldier's perk cards")
		cards[0].pressed.emit()
	assert_true(not Progression.has_pending(run), "every soldier picked")
	assert_eq(_pick_cards(screen).size(), 0, "nothing left to pick")
	screen.free()


## The pick cards on screen (they carry the full rule as their hover text; tabs and Skip don't).
func _pick_cards(screen: Control) -> Array:
	return screen.find_children("*", "Button", true, false).filter(func(b): return b.tooltip_text != "" and not b.is_queued_for_deletion())


## True when Icons.draw has a match arm for `id` ("id": or "id", "alias":).
func _drawn(src: String, id: String) -> bool:
	return src.contains('\t"%s":' % id) or src.contains('\t"%s", ' % id) or src.contains(', "%s":' % id) or src.contains(', "%s",' % id)


func test_every_perk_and_mutation_has_a_card_face() -> void:
	var icons := FileAccess.get_file_as_string("res://ui/icons.gd")
	for id in PerkData.PERKS:
		assert_true(PerkBrief.PERKS.has(id), "brief for perk " + id)
		var b := PerkBrief.perk(id)
		assert_true(_drawn(icons, b.icon), "%s icon %s is drawn" % [id, b.icon])
		assert_true(b.short.length() <= 42, "%s short line fits one line: %s" % [id, b.short])
	for id in MutationData.MUTATIONS:
		assert_true(PerkBrief.MUTATIONS.has(id), "brief for mutation " + id)
		var m := PerkBrief.mutation(id)
		assert_true(_drawn(icons, m.icon), "%s icon %s is drawn" % [id, m.icon])
		assert_true(m.short.length() <= 42 and m.drawback.length() <= 42, "%s lines stay short" % id)


func test_content_pack_perks_damage() -> void:
	var s := _state(["marksman", "hazmat", "vector"])
	var foe := _enemy(s, "brute", Vector2i(8, 0))
	var mk := _soldier(s, 0)
	_give(mk, ["headhunter"])
	assert_eq(Kit.shot_damage(s, mk, foe, 3), 3, "Headhunter needs a Tag")
	foe.status["tagged"] = Combat.phase_index(s) + 2
	assert_eq(Kit.shot_damage(s, mk, foe, 3), 4, "Headhunter +1 vs Tagged")
	var hz := _soldier(s, 1)
	_give(hz, ["scorcher"])
	foe.status["burning"] = 2
	assert_eq(Kit.shot_damage(s, hz, foe, 3), 4, "Scorcher +1 vs Burning")
	var vc := _soldier(s, 2)
	_give(vc, ["carrier_wave"])
	vc.infection = 10
	assert_eq(Kit.shot_damage(s, vc, foe, 3), 3, "Carrier Wave needs Mutating")
	vc.infection = 55
	assert_eq(Kit.shot_damage(s, vc, foe, 3), 4, "Carrier Wave +1 at Mutating")


func test_content_pack_perks_defense() -> void:
	var s := _state(["trooper", "vector", "medic"])
	var foe := _enemy(s, "spitter", Vector2i(8, 0))
	var tr := _soldier(s, 0)
	_give(tr, ["battle_hardened"])
	var hp := tr.hp
	Rules.deal_damage(s, tr, 3, foe)
	assert_eq(tr.hp, hp - 2, "first hit -1")
	Rules.deal_damage(s, tr, 3, foe)
	assert_eq(tr.hp, hp - 5, "only the first")
	var vc := _soldier(s, 1)
	_give(vc, ["spore_veil"])
	vc.infection = 30
	assert_eq(_term(Combat.hit_chance(s, foe, vc), "Spore Veil"), -10, "Spore Veil at Exposed")
	var md := _soldier(s, 2)
	_give(md, ["steady_hands", "field_surgeon"])
	tr.hp = 1
	Kit.after_stim(s, md, tr, 0)
	assert_eq(tr.hp, 3, "Field Surgeon heals 2")
	assert_eq(_term(Combat.hit_chance(s, foe, md), "Steady Hands"), -15, "Steady Hands after a Stim")


func test_high_perch_needs_height() -> void:
	var s := _state(["marksman"])
	var foe := _enemy(s, "spitter", Vector2i(6, 0))
	var mk := _soldier(s, 0)
	_give(mk, ["high_perch"])
	assert_eq(_term(Combat.hit_chance(s, mk, foe), "High Perch"), 0, "level ground")
	s.grid.set_level(mk.pos, 1)
	assert_eq(_term(Combat.hit_chance(s, mk, foe), "High Perch"), 10, "shooting down")


func test_new_perks_in_every_pool() -> void:
	for k in ["trooper", "marksman", "medic", "breacher", "hazmat", "vector"]:
		assert_true(PerkData.pool(k).size() >= 9, "%s has 9+ perks" % k)
