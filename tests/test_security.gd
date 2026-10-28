extends TestCase
## Colony Security: Shieldman (front arc blocks all damage), Overwatcher (full-aim reactions), Emplacement (crossfire cone).


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


func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


func test_security_joins_act_two_and_has_cards() -> void:
	for k in ["shieldman", "overwatcher", "emplacement"]:
		assert_true(not EnemyRoster.pool(1).has(k) and EnemyRoster.pool(2).has(k), k + " from act 2")
		assert_true(Glossary.has("enemy_" + k), "a hover card for " + k)
		assert_true(not EnemyRoster.infects(EnemyRoster.make(k)), k + " is human")


func test_shield_blocks_the_front_arc_and_not_the_flank() -> void:
	var s := make_blank(_open(10, 10))
	var shield := _enemy(s, "shieldman", Vector2i(5, 5))
	shield.status["facing"] = Vector2i(-1, 0)
	var front := _soldier(s, "trooper", Vector2i(2, 5))
	var flank := _soldier(s, "trooper", Vector2i(8, 5))
	assert_eq(Encounter.modify_damage(s, shield, 4, front), 0, "the front takes nothing")
	assert_eq(Encounter.modify_damage(s, shield, 4, flank), 4, "a flank hits for full damage")


func test_overwatcher_reaction_shots_have_no_penalty() -> void:
	var s := make_blank(_open(12, 5))
	var ow := _enemy(s, "overwatcher", Vector2i(10, 2))
	var sol := _soldier(s, "trooper", Vector2i(2, 2))
	var normal := Combat.hit_chance(s, ow, sol, ow.pos, false)
	var reaction := Combat.hit_chance(s, ow, sol, ow.pos, true)
	assert_eq(reaction.hit, normal.hit, "same odds on a reaction")
	var trooper_shot := Combat.hit_chance(s, sol, ow, sol.pos, true)
	var trooper_normal := Combat.hit_chance(s, sol, ow, sol.pos, false)
	assert_true(trooper_shot.hit < trooper_normal.hit, "soldiers still pay the penalty")


func test_overwatcher_holds_overwatch_when_nothing_is_in_view() -> void:
	var s := make_blank(_open(12, 12))
	var ow := _enemy(s, "overwatcher", Vector2i(10, 10))
	var start := ow.pos
	_soldier(s, "trooper", Vector2i(0, 0))
	Vision.disable(s)
	_enemy_turn(s, ow)
	assert_eq(ow.pos, start, "never advances")


func test_emplacement_marks_a_cone_that_hits_soldiers_and_the_infected() -> void:
	var s := make_blank(_open(14, 9))
	var gun := _enemy(s, "emplacement", Vector2i(2, 4))
	var sol := _soldier(s, "trooper", Vector2i(6, 4))
	var runner := _enemy(s, "runner", Vector2i(7, 4))
	Vision.disable(s)
	_enemy_turn(s, gun)
	assert_eq(gun.status.facing, Vector2i(1, 0), "faces the squad")
	var tel := (s.encounter.get("telegraphs", []) as Array).filter(func(t): return t.kind == "crossfire")
	assert_eq(tel.size(), 1, "a cone is down")
	assert_true(tel[0].cells.has(Vector2i(6, 4)) and not tel[0].cells.has(Vector2i(2, 8)), "the cone covers the lane, not the side")
	var hp := sol.hp
	var rhp := runner.hp
	s.turn += 1
	Encounter._resolve_telegraphs(s)
	assert_eq(sol.hp, hp - EnemyRoster.CROSSFIRE_DAMAGE, "the soldier is hit")
	assert_true(runner.hp < rhp, "so are the Infected")
	assert_eq(gun.hp, gun.max_hp, "it does not shoot itself")
