extends TestCase
## The faction packs of 2026-10-28: Scavengers (Packrat, Rigger, Lookout), Colony Security (Sergeant,
## Grenadier, Field medic) and Automata (Tender, Carrier, Arc-welder). Rules here; the same abilities
## through the 3D view are in test_faction_view.gd.

const NEW := {
	"scavengers": ["packrat", "rigger", "lookout"],
	"security": ["sergeant", "grenadier", "field_medic"],
	"automata": ["tender", "carrier", "arc_welder"],
}


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _enemy(s: GameState, spec: String, at: Vector2i) -> Unit:
	var u := s.add_unit(EnemyRoster.make(spec), at)
	u.status["alerted"] = true
	return u


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


func test_the_new_enemies_are_in_their_factions_pools_and_cards() -> void:
	for faction in NEW:
		for k in NEW[faction]:
			assert_true(EnemyRoster.FACTIONS[faction].has(k), k + " is in " + faction)
			assert_true(EnemyRoster.COST.has(k) and EnemyRoster.pool(3).has(k), k + " can be bought by act 3")
			assert_true(Glossary.has("enemy_" + k), "a hover card for " + k)
			assert_true(not EnemyRoster.infects(EnemyRoster.make(k)), k + " does not infect")
			for ab in UnitData.ENEMIES[k].abilities:
				assert_true(EnemyAbilities.handles(ab) or ab == "claw", k + " ability " + ab + " exists")
				assert_true(Glossary.has(ab) or ab == "claw", "a hover card for the " + ab + " ability")
	for faction in ["scavengers", "security", "automata"]:
		assert_eq(EnemyRoster.FACTIONS[faction].size(), 6, faction + " has its three old kinds and three new")
	for faction in EnemyRoster.FACTIONS:
		for k in EnemyRoster.FACTIONS[faction]:
			assert_true(UnitData.ENEMIES.has(k), "stats for " + k)
	assert_true(Automata.is_machine(EnemyRoster.make("tender")) and Automata.is_machine(EnemyRoster.make("arc_welder")), "machines")


# --- Scavengers ------------------------------------------------------------------------------

func test_a_packrat_loses_a_plate_and_two_damage_on_each_of_its_first_hits() -> void:
	var s := make_blank(_open(8, 8))
	var sol := _soldier(s, "trooper", Vector2i(1, 1))
	var pr := _enemy(s, "packrat", Vector2i(4, 4))
	for i in EnemyRoster.PACKRAT_PLATES:
		Rules.deal_damage(s, pr, 4, sol)
	assert_eq(pr.hp, pr.max_hp - 3 * (4 - EnemyRoster.PACKRAT_REDUCTION), "each plated hit lands for 2")
	assert_eq(int(pr.status.plates), 0, "stripped")
	assert_eq(_events(s, "scrap").size(), 3, "a beat per plate")
	Rules.deal_damage(s, pr, 4, sol)
	assert_true(not pr.is_alive(), "the next hit lands in full")


func test_a_packrat_still_takes_a_point_from_a_one_damage_hit() -> void:
	var s := make_blank(_open(8, 8))
	var sol := _soldier(s, "trooper", Vector2i(1, 1))
	var pr := _enemy(s, "packrat", Vector2i(4, 4))
	Rules.deal_damage(s, pr, 1, sol)
	assert_eq(pr.hp, pr.max_hp - 1, "never below 1 per hit")


func test_a_rigger_strings_a_snare_on_the_ground_beside_cover() -> void:
	var rows := _open(14, 7)
	rows[3] = ".........=...."
	var s := make_blank(rows)
	_soldier(s, "trooper", Vector2i(3, 3))
	var rig := _enemy(s, "rigger", Vector2i(12, 5))
	_enemy_turn(s, rig)
	var snares := Scavengers.snare_cells(s)
	assert_eq(snares.size(), 1, "one snare laid")
	assert_true(Scavengers.beside_cover(s.grid, snares[0]), "beside the cover piece")
	assert_true(s.grid.is_walkable(snares[0]), "on ground a soldier can step on")
	assert_eq(_events(s, "ability").filter(func(e): return e.ability == "snare").size(), 1, "a snare beat")
	rig.actions_left = 2
	rig.cooldowns.clear()
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": rig.id, "ability": "snare", "cell": Vector2i(1, 6)}), "Out of range", "not across the map")
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": rig.id, "ability": "snare", "cell": Vector2i(9, 3)}), "Nowhere to string it", "not on the cover itself")


func test_a_soldier_who_steps_on_a_snare_stops_there_and_loses_an_action() -> void:
	var rows := _open(14, 5)
	rows[1] = "....##########"
	rows[3] = "....##########"
	var s := make_blank(rows)
	var rig := _enemy(s, "rigger", Vector2i(13, 0))
	var sol := _soldier(s, "marksman", Vector2i(4, 2))
	Scavengers.lay_snare(s, rig, Vector2i(7, 2))
	s.phase = Types.Phase.TEAM
	sol.actions_left = 2
	var action := {"type": Types.MOVE, "unit": sol.id, "to": Vector2i(8, 2)}
	assert_eq(Rules.validate(s, action), "", "legal move")
	Rules.apply(s, action)
	assert_eq(sol.pos, Vector2i(7, 2), "the walk ends on the snare")
	assert_eq(sol.actions_left, 0, "the move and the snare cost the turn")
	assert_eq(_events(s, "snared").size(), 1, "a snared beat")
	assert_true(Scavengers.snare_cells(s).is_empty(), "the snare is spent")


func test_enemies_walk_over_snares_and_killing_the_rigger_cuts_them() -> void:
	var rows := _open(14, 5)
	var s := make_blank(rows)
	var rig := _enemy(s, "rigger", Vector2i(13, 0))
	_soldier(s, "trooper", Vector2i(0, 2))
	Scavengers.lay_snare(s, rig, Vector2i(6, 2))
	Scavengers.lay_snare(s, rig, Vector2i(11, 2))
	var runner := _enemy(s, "runner", Vector2i(4, 2))
	s.phase = Types.Phase.ENEMY
	runner.actions_left = 2
	Rules.apply(s, {"type": Types.MOVE, "unit": runner.id, "to": Vector2i(8, 2)})
	assert_eq(runner.pos, Vector2i(8, 2), "an enemy is not stopped")
	assert_eq(Scavengers.snare_cells(s).size(), 2, "and sets nothing off")
	Encounter.kill(s, rig)
	assert_true(Scavengers.snare_cells(s).is_empty(), "the lines are cut with the Rigger")
	assert_eq(_events(s, "snares_cut").size(), 1, "a beat for it")


func test_a_lookout_fires_one_flare_that_ends_concealment_and_calls_two_cutters() -> void:
	var s := make_blank(_open(14, 8))
	s.encounter["concealment"] = {"on": true, "lost_turn": -1, "cause": ""}
	var sol := _soldier(s, "trooper", Vector2i(2, 4))
	var look := _enemy(s, "lookout", Vector2i(9, 4))
	_enemy_turn(s, look)
	assert_true(not Concealment.active(s), "the squad is seen")
	assert_true(look.status.get("flared", false), "the flare is spent")
	var calls: Array = s.encounter.get("incoming", [])
	assert_eq(calls.size(), 1, "one call goes out")
	assert_eq(calls[0].kinds, ["cutter", "cutter"], "two Cutters")
	assert_eq(int(calls[0].turn), s.turn + 1, "next turn")
	assert_eq(_events(s, "reinforcements_incoming").size(), 1, "the vents glow")
	look.actions_left = 2
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": look.id, "ability": "flare", "target": sol.id}), "Already fired", "once a fight")
	Encounter.on_enemy_phase_start(s)   # the due wave arrives
	s.turn += 1
	Encounter._spawn_incoming(s)
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "cutter").size(), 2, "the Cutters arrive")


# --- Security --------------------------------------------------------------------------------

func test_a_sergeant_puts_armed_allies_in_sight_on_overwatch() -> void:
	var s := make_blank(_open(14, 8))
	_soldier(s, "trooper", Vector2i(0, 0))
	var sgt := _enemy(s, "sergeant", Vector2i(10, 4))
	var ow := _enemy(s, "overwatcher", Vector2i(12, 2))
	var shield := _enemy(s, "shieldman", Vector2i(9, 6))
	var gun := _enemy(s, "emplacement", Vector2i(11, 6))
	assert_eq(Security.order_targets(s, sgt), [ow] as Array[Unit], "only the armed one")
	_enemy_turn(s, sgt)
	assert_true(Combat.is_overwatching(s, ow), "the Overwatcher is on Overwatch")
	assert_true(not Combat.is_overwatching(s, shield) and not Combat.is_overwatching(s, gun), "melee and guns ignore it")
	var order_events := _events(s, "ability").filter(func(e): return e.ability == "order")
	assert_eq(order_events.size(), 1, "an order beat")
	assert_eq(order_events[0].units, [ow.id], "naming who was ordered")
	sgt.actions_left = 2
	sgt.cooldowns.clear()
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": sgt.id, "ability": "order"}), "Nobody to order", "nothing more to order")


func test_a_grenadier_lobs_a_frag_over_a_wall_and_leaves_cover_standing() -> void:
	var rows := _open(14, 10)
	for y in range(2, 9):
		rows[y] = rows[y].substr(0, 4) + "#" + rows[y].substr(5)
	rows[5] = "....#.=......."
	var s := make_blank(rows)
	var sol := _soldier(s, "trooper", Vector2i(7, 5))
	var gren := _enemy(s, "grenadier", Vector2i(1, 5))
	assert_true(not Combat.can_see(s, gren.pos, sol.pos), "the wall is between them")
	_enemy_turn(s, gren)
	var tel := (s.encounter.get("telegraphs", []) as Array).filter(func(t): return t.kind == "frag")
	assert_eq(tel.size(), 1, "a frag is down")
	assert_true(tel[0].cells.has(sol.pos), "on the soldier")
	var hp := sol.hp
	s.turn += 1
	Encounter._resolve_telegraphs(s)
	assert_eq(sol.hp, hp - EnemyRoster.FRAG_DAMAGE, "it goes off for 3")
	assert_eq(s.grid.tile(Vector2i(6, 5)), Types.Tile.LOW, "the cover is still there")


func test_a_field_medic_gets_a_fallen_security_back_up_after_two_rounds() -> void:
	var s := make_blank(_open(16, 8))
	_soldier(s, "trooper", Vector2i(0, 0))
	var shield := _enemy(s, "shieldman", Vector2i(8, 4))
	var medic := _enemy(s, "field_medic", Vector2i(12, 4))
	Encounter.kill(s, shield)
	assert_true(shield.status.get("downed", false), "down, with a medic alive")
	assert_eq(_events(s, "downed").size(), 1, "a beat for it")
	_enemy_turn(s, medic)
	assert_true(medic.status.has("reviving"), "the medic walks up and kneels")
	assert_true(EnemyAbilities._cheb(medic.pos, shield.pos) <= 1, "beside the body")
	var kneel_turn := s.turn
	s.turn += 1
	_enemy_turn(s, medic)
	assert_true(medic.status.has("reviving") and s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "shieldman").is_empty(), "one round on, still down")
	s.turn += 1
	_enemy_turn(s, medic)
	assert_true(not medic.status.has("reviving"), "two rounds on, done")
	var up: Array = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "shieldman")
	assert_eq(up.size(), 1, "it is back up")
	assert_eq(up[0].hp, (up[0].max_hp + 1) / 2, "on half health")
	assert_eq(_events(s, "revived").size(), 1, "a revived beat")
	assert_true(kneel_turn < s.turn, "it took rounds")
	Encounter.kill(s, up[0])
	assert_true(not up[0].status.get("downed", false), "each body gets up once")


func test_hurting_the_medic_breaks_the_revive_and_no_medic_means_no_revive() -> void:
	var s := make_blank(_open(16, 8))
	var sol := _soldier(s, "trooper", Vector2i(0, 0))
	var shield := _enemy(s, "overwatcher", Vector2i(8, 4))
	var medic := _enemy(s, "field_medic", Vector2i(9, 4))
	Encounter.kill(s, shield)
	_enemy_turn(s, medic)
	assert_true(medic.status.has("reviving"), "kneeling")
	Rules.deal_damage(s, medic, 1, sol)
	assert_true(not medic.status.has("reviving"), "a hit breaks it off")
	assert_eq(_events(s, "revive_broken").size(), 1, "a beat for it")
	var s2 := make_blank(_open(16, 8))
	_soldier(s2, "trooper", Vector2i(0, 0))
	var lone := _enemy(s2, "shieldman", Vector2i(8, 4))
	Encounter.kill(s2, lone)
	assert_true(not lone.status.get("downed", false), "no medic, no revive")


# --- Automata --------------------------------------------------------------------------------

func test_a_tender_mends_wounded_machines_in_sight_and_nothing_else() -> void:
	var s := make_blank(_open(14, 8))
	_soldier(s, "trooper", Vector2i(0, 0))
	var tender := _enemy(s, "tender", Vector2i(8, 4))
	var loader := _enemy(s, "loader", Vector2i(10, 4))
	var relay := _enemy(s, "relay", Vector2i(8, 7))
	var runner := _enemy(s, "runner", Vector2i(10, 6))
	loader.hp = 4
	relay.hp = 2
	runner.hp = 1
	_enemy_turn(s, tender)
	assert_eq(loader.hp, 4 + EnemyRoster.REPAIR_HEAL, "the Loader is mended")
	assert_eq(relay.hp, 2 + EnemyRoster.REPAIR_HEAL, "so is the Relay")
	assert_eq(runner.hp, 1, "the Infected are not machines")
	assert_eq(_events(s, "regenerate").size(), 2, "a number over each")
	assert_eq(_events(s, "ability").filter(func(e): return e.ability == "repair").size(), 1, "one repair beat")


func test_a_wall_cuts_a_tenders_repairs() -> void:
	var rows := _open(14, 8)
	for y in range(0, 8):
		rows[y] = rows[y].substr(0, 9) + "#" + rows[y].substr(10)
	var s := make_blank(rows)
	_soldier(s, "trooper", Vector2i(0, 0))
	var tender := _enemy(s, "tender", Vector2i(7, 4))
	var loader := _enemy(s, "loader", Vector2i(11, 4))
	loader.hp = 4
	assert_true(Automata.repair_targets(s, tender).is_empty(), "out of sight")
	tender.actions_left = 2
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": tender.id, "ability": "repair"}), "Nothing to mend", "so no repair")


func test_a_carrier_drops_two_hounds_every_third_round_until_it_is_shot_down() -> void:
	var s := make_blank(_open(14, 8))
	_soldier(s, "trooper", Vector2i(0, 0))
	var carrier := _enemy(s, "carrier", Vector2i(10, 4))
	assert_true(EnemyRoster.is_static(carrier), "it never moves")
	s.turn = 2
	Encounter._run_spawners(s)
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "hound").size(), EnemyRoster.CARRIER_DROP, "two Hounds")
	s.turn = 3
	Encounter._run_spawners(s)
	s.turn = 4
	Encounter._run_spawners(s)
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "hound").size(), 2, "nothing in between")
	s.turn = 5
	Encounter._run_spawners(s)
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "hound").size(), 4, "two more on the third round")
	Encounter.kill(s, carrier)
	s.turn = 8
	Encounter._run_spawners(s)
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "hound").size(), 4, "shot down, it drops no more")
	assert_eq(UnitData.ENEMIES.carrier.max_hp, 10, "a target worth shooting at")


func test_an_arc_welder_hits_one_soldier_and_jumps_through_the_ones_beside_it() -> void:
	var s := make_blank(_open(14, 8))
	var a := _soldier(s, "trooper", Vector2i(5, 4))
	var b := _soldier(s, "marksman", Vector2i(6, 4))
	var c := _soldier(s, "medic", Vector2i(7, 4))
	var d := _soldier(s, "breacher", Vector2i(8, 4))
	var welder := _enemy(s, "arc_welder", Vector2i(2, 4))
	var hp := {a: a.hp, b: b.hp, c: c.hp, d: d.hp}
	var action := {"type": Types.ABILITY, "unit": welder.id, "ability": "arc", "target": a.id}
	s.phase = Types.Phase.ENEMY
	welder.actions_left = 2
	assert_eq(Rules.validate(s, action), "", "in range")
	Rules.apply(s, action)
	assert_true(hp[a] - a.hp >= 2 and hp[a] - a.hp <= 3, "the first soldier takes the arc")
	assert_eq(hp[b] - b.hp, EnemyRoster.ARC_CHAIN_DAMAGE, "it jumps to the next")
	assert_eq(hp[c] - c.hp, EnemyRoster.ARC_CHAIN_DAMAGE, "and the one beside that")
	assert_eq(d.hp, hp[d], "but only twice")
	var far := _soldier(s, "vector", Vector2i(12, 1))
	welder.actions_left = 2
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": welder.id, "ability": "arc", "target": far.id}), "Out of range", "short range")


func test_an_arc_welder_walks_into_range_and_strikes_in_the_same_turn() -> void:
	var s := make_blank(_open(16, 8))
	var sol := _soldier(s, "trooper", Vector2i(8, 4))
	var welder := _enemy(s, "arc_welder", Vector2i(1, 4))
	_enemy(s, "relay", Vector2i(0, 7))   # no Relay, no third action: machines get one
	_enemy_turn(s, welder)
	assert_true(sol.hp < sol.max_hp, "the soldier is hit")
	assert_true(EnemyAbilities._cheb(welder.pos, sol.pos) <= EnemyRoster.ARC_RANGE, "from inside its range")
