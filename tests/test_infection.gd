extends TestCase

const ROWS := ["........", "........", "........", "........"]


## Blank map with one trooper (player 0) at (1,1) and one runner at (6,2), in a team phase on turn 1.
func _setup() -> Dictionary:
	var s := make_blank(PackedStringArray(ROWS))
	var sol := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(1, 1))
	sol.owner_player = 0
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(6, 2))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	sol.actions_left = Types.ACTIONS_PER_TURN
	return {"s": s, "sol": sol, "foe": foe}


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


## A seed whose first randf() is below (or not below) `p`, so lapse rolls are deterministic.
func _seed_for(p: float, below: bool) -> int:
	for seed in range(1, 10000):
		var r := RandomNumberGenerator.new()
		r.seed = seed
		if (r.randf() < p) == below:
			return seed
	return 1


func _mutate(s: GameState, u: Unit, id: String) -> bool:
	return Rules.apply(s, {"type": Types.MUTATION, "unit": u.id, "mutation": id})


func test_tier_boundaries() -> void:
	var I := Infection
	assert_eq(I.tier(0), I.Tier.CLEAN, "0")
	assert_eq(I.tier(24), I.Tier.CLEAN, "24")
	assert_eq(I.tier(25), I.Tier.EXPOSED, "25")
	assert_eq(I.tier(49), I.Tier.EXPOSED, "49")
	assert_eq(I.tier(50), I.Tier.MUTATING, "50")
	assert_eq(I.tier(74), I.Tier.MUTATING, "74")
	assert_eq(I.tier(75), I.Tier.CRITICAL, "75")
	assert_eq(I.tier(99), I.Tier.CRITICAL, "99")
	assert_eq(I.tier(100), I.Tier.TURNED, "100")
	assert_eq(I.tier_name(I.Tier.MUTATING), "Mutating", "name")
	for t in I.THRESHOLDS.size():
		assert_eq(I.tier(I.THRESHOLDS[t]), t, "threshold %d" % t)
	assert_true(I.tier_color(I.Tier.CLEAN) != I.tier_color(I.Tier.CRITICAL), "colors differ")


func test_add_clamps_and_emits() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	Infection.add(s, sol, 30)
	assert_eq(sol.infection, 30, "value")
	Infection.add(s, sol, -50)
	assert_eq(sol.infection, 0, "clamped at 0")
	var ev: Array = _events(s, "infection")
	assert_eq(ev.size(), 2, "two infection events")
	assert_eq(ev[0].tier, Infection.Tier.EXPOSED, "event tier")


func test_gain_from_enemy_damage_only() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	var foe: Unit = d.foe
	Rules.deal_damage(s, sol, 2, foe)
	assert_eq(sol.infection, Infection.damage_gain(2), "infected by enemy")
	assert_eq(Infection.damage_gain(2), 10, "6 + 2*2")
	assert_eq(Infection.damage_gain(9), 15, "capped")
	var before := sol.infection
	# Soldier-on-soldier (e.g. a Lapsed ally) does not infect.
	var ally := s.add_unit(UnitData.make("medic", Types.Team.PLAYER), Vector2i(2, 2))
	ally.status["lapsed"] = true
	Rules.deal_damage(s, sol, 1, ally)
	assert_eq(sol.infection, before, "no infection from lapsed ally")
	# Sourceless damage does not infect; enemies are not infected by soldiers.
	Rules.deal_damage(s, sol, 1)
	assert_eq(sol.infection, before, "no infection without source")
	Rules.deal_damage(s, foe, 1, sol)
	assert_eq(foe.infection, 0, "enemies not infected")


func test_passives_apply_and_revert() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	var mob := sol.mobility
	var aim := sol.aim
	Infection.add(s, sol, 50)
	assert_eq(sol.mobility, mob + 1, "mutating mobility")
	assert_eq(sol.aim, aim, "mutating aim")
	Infection.add(s, sol, 30)
	assert_eq(sol.mobility, mob + 1, "critical mobility (not stacked)")
	assert_eq(sol.aim, aim + 10, "critical aim")
	Infection.add(s, sol, -15)  # Medic stim: 80 -> 65
	assert_eq(sol.mobility, mob + 1, "back to mutating mobility")
	assert_eq(sol.aim, aim, "critical aim removed")
	Infection.add(s, sol, -40)
	assert_eq(sol.mobility, mob, "mobility restored")
	assert_eq(sol.aim, aim, "aim restored")
	assert_true(not sol.status.has("tier_mobility") and not sol.status.has("tier_aim"), "status cleaned")


func _graft(u: Unit, slots: Dictionary) -> void:
	u.status["mutations"] = slots.duplicate()


func test_no_mutations_when_ungrafted() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	Infection.add(s, sol, 30)
	assert_true(Infection.available_mutations(s, sol).is_empty(), "none listed without grafts")
	assert_true(not _mutate(s, sol, "adrenal_surge"), "ungrafted rejected")
	assert_true(not _mutate(s, sol, "bogus"), "unknown rejected")
	assert_eq(sol.actions_left, 2, "nothing spent")


func test_available_mutations_shape_and_dormancy() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	_graft(sol, {"exposed": "adrenal_surge", "mutating": "acid_spit", "critical": "regenerator"})
	Infection.add(s, sol, 30)
	var list := Infection.available_mutations(s, sol)
	assert_eq(list.size(), 2, "passives are not listed")
	var by_id := {}
	for m in list:
		by_id[m.id] = m
		for k in ["id", "name", "desc", "cost", "actions", "targeting", "ready", "reason", "cooldown"]:
			assert_true(m.has(k), "%s has %s" % [m.id, k])
	assert_true(by_id.adrenal_surge.ready, "surge ready")
	assert_eq(by_id.adrenal_surge.cost, 5, "exposed actives cost 5")
	assert_true(not by_id.acid_spit.ready, "acid spit dormant at Exposed")
	assert_eq(by_id.acid_spit.reason, "Dormant until Mutating", "dormant reason")
	assert_eq(by_id.acid_spit.cost, 10, "mutating actives cost 10")


func test_surge_happy_once_per_turn_and_penalty() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	_graft(sol, {"exposed": "adrenal_surge"})
	Infection.add(s, sol, 25)
	assert_true(_mutate(s, sol, "adrenal_surge"), "surge ok")
	assert_eq(sol.actions_left, 3, "+1 action, costs none")
	assert_eq(sol.infection, 30, "+5 infection")
	assert_eq(_events(s, "mutation").size(), 1, "mutation event")
	assert_true(not _mutate(s, sol, "adrenal_surge"), "second surge rejected")
	assert_eq(sol.infection, 30, "no extra infection")
	s.players.assign([0])
	Rules.set_ready(s, 0, true)
	assert_eq(s.turn, 2, "next turn")
	assert_eq(sol.actions_left, 1, "drawback: only 1 action next turn")


func test_mutation_can_turn() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	_graft(sol, {"exposed": "adrenal_surge"})
	Infection.add(s, sol, 97)
	assert_true(_mutate(s, sol, "adrenal_surge"), "surge ok")
	assert_eq(sol.team, Types.Team.ENEMY, "turned by mutation cost")
	assert_eq(sol.actions_left, 0, "turned unit loses its team-phase actions")


func test_lapse_chance() -> void:
	assert_eq(Infection.lapse_chance(0), 0.0, "clean")
	assert_eq(Infection.lapse_chance(40), 0.0, "exposed")
	assert_eq(Infection.lapse_chance(50), 0.10, "mutating")
	assert_eq(Infection.lapse_chance(80), 0.30, "critical")


func test_lapse_and_recover() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	Infection.add(s, sol, 80)
	s.rng.seed = _seed_for(0.30, true)
	Infection.on_team_phase_start(s)
	assert_true(Infection.is_lapsed(sol), "lapsed")
	assert_true(sol.ai_controlled, "ai controlled")
	assert_eq(_events(s, "lapse").size(), 1, "lapse event")
	assert_true(s.controllable_units(0).is_empty(), "players lose control")
	assert_true(sol.is_enemy_of(d.foe) and d.foe.is_enemy_of(sol), "hostile to all")
	# Next phase: recovers and cannot lapse again even with a roll that would succeed.
	s.turn = 2
	s.rng.seed = _seed_for(0.30, true)
	Infection.on_team_phase_start(s)
	assert_true(not Infection.is_lapsed(sol), "recovered")
	assert_true(not sol.ai_controlled, "control returned")
	assert_eq(_events(s, "recover").size(), 1, "recover event")
	assert_eq(_events(s, "lapse").size(), 1, "no second lapse")
	# Phase after: rolls again; a failing roll keeps the soldier.
	s.turn = 3
	s.rng.seed = _seed_for(0.30, false)
	Infection.on_team_phase_start(s)
	assert_true(not Infection.is_lapsed(sol), "roll failed, not lapsed")


func test_no_lapse_below_mutating() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	Infection.add(s, sol, 49)
	for i in 50:
		Infection.on_team_phase_start(s)
	assert_eq(_events(s, "lapse").size(), 0, "never lapses while exposed")


func test_turning_at_100() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	sol.status["lapsed"] = true
	sol.ai_controlled = true
	Infection.add(s, sol, 99)
	assert_eq(sol.team, Types.Team.PLAYER, "still a soldier at 99")
	Infection.add(s, sol, 5)
	assert_eq(sol.infection, 100, "capped")
	assert_eq(sol.team, Types.Team.ENEMY, "team enemy")
	assert_true(sol.ai_controlled, "ai controlled")
	assert_eq(sol.owner_player, -1, "no owner")
	assert_true(not Infection.is_lapsed(sol), "lapse cleared")
	assert_eq(_events(s, "turned").size(), 1, "turned event")
	assert_true(sol.is_enemy_of(s.add_unit(UnitData.make("medic", Types.Team.PLAYER), Vector2i(0, 0))), "hostile to squad")
	# Permanent: curing does nothing.
	Infection.add(s, sol, -50)
	assert_eq(sol.infection, 100, "cannot cure a turned unit")
	assert_eq(sol.team, Types.Team.ENEMY, "still enemy")


func test_turning_last_soldier_is_defeat() -> void:
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	Infection.add(s, sol, 100)
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.DEFEAT, "defeat when no soldiers remain")


func test_enemy_hit_through_move_infects() -> void:
	# Integration via Rules: damage from an enemy pushes a soldier up a tier, and Medic-style cure brings it back.
	var d := _setup()
	var s: GameState = d.s
	var sol: Unit = d.sol
	Infection.add(s, sol, 45)
	Rules.deal_damage(s, sol, 1, d.foe)
	assert_eq(sol.infection, 53, "45 + 8")
	assert_eq(Infection.tier(sol.infection), Infection.Tier.MUTATING, "mutating")
	var mob := sol.mobility
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": sol.pos + Vector2i(mob, 0)}), "uses boosted mobility")
	Infection.add(s, sol, -15)
	assert_eq(sol.mobility, mob - 1, "bonus removed after cure")
