extends TestCase
## Automata: Hound drone (hunts the weakest), Loader frame (charges), Relay (actions near it).


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


func test_automata_are_act_three_and_have_cards() -> void:
	for k in ["hound", "loader", "relay"]:
		assert_true(not EnemyRoster.pool(2).has(k) and EnemyRoster.pool(3).has(k), k + " from act 3")
		assert_true(Glossary.has("enemy_" + k), "a hover card for " + k)
	assert_true(Automata.is_machine(EnemyRoster.make("hound")) and not Automata.is_machine(EnemyRoster.make("runner")), "machines")


func test_a_hound_goes_for_the_weakest_soldier() -> void:
	var s := make_blank(_open(12, 5))
	var healthy := _soldier(s, "trooper", Vector2i(3, 1))
	var hurt := _soldier(s, "medic", Vector2i(10, 3))
	hurt.hp = 2
	var targets := Automata.hound_targets([healthy, hurt] as Array[Unit])
	assert_eq(targets.size(), 1, "one target")
	assert_eq(targets[0], hurt, "the wounded one, however far")


func test_relay_gives_a_third_action_and_its_loss_stalls_machines() -> void:
	var s := make_blank(_open(14, 6))
	_soldier(s, "trooper", Vector2i(0, 0))
	var relay := _enemy(s, "relay", Vector2i(5, 3))
	var hound := _enemy(s, "hound", Vector2i(7, 3))
	hound.actions_left = Types.ACTIONS_PER_TURN
	Encounter.on_unit_turn_start(s, hound)
	assert_eq(hound.actions_left, Types.ACTIONS_PER_TURN + 1, "three actions near a Relay")
	Encounter.kill(s, relay)
	hound.actions_left = Types.ACTIONS_PER_TURN
	Encounter.on_unit_turn_start(s, hound)
	assert_eq(hound.actions_left, 1, "one action with no Relay left")
	assert_eq(s.log.filter(func(e): return e.type == "stalled").size(), 1, "a stalled beat, once")


func test_loader_charges_like_a_brute() -> void:
	var s := make_blank(_open(12, 5))
	var loader := _enemy(s, "loader", Vector2i(1, 2))
	_soldier(s, "trooper", Vector2i(7, 2))
	assert_true(EnemyBehaviours.can_charge(loader), "loaders wind up charges")
	EnemyBehaviours.end_turn(s, loader)
	assert_true(loader.status.has("charge_dir"), "it winds up a charge down the lane")
