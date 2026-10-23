extends TestCase
## Cross-module behaviour that no single workstream owns.


func test_extra_enemies_get_their_own_cells() -> void:
	var s := make_state(["runner", "runner", "spitter", "spitter", "runner", "spitter"])
	var cells := {}
	for u in s.units:
		assert_true(not cells.has(u.pos), "unit %d shares a cell" % u.id)
		assert_true(s.grid.is_walkable(u.pos), "unit %d on walkable cell" % u.id)
		cells[u.pos] = true


func test_runners_cannot_shoot() -> void:
	var s := make_blank(PackedStringArray(["........"]))
	var soldier := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(0, 0))
	var runner := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(4, 0))
	runner.actions_left = 2
	assert_eq(Rules.validate(s, {"type": Types.SHOOT, "unit": runner.id, "target": soldier.id}), "Melee only")


func test_hive_sense_ignores_cover() -> void:
	var s := make_blank(PackedStringArray([
		"........",
		"......=.",
		"........",
	]))
	s.turn = 1
	var soldier := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(0, 1))
	var enemy := s.add_unit(UnitData.make("spitter", Types.Team.ENEMY), Vector2i(7, 1))
	var covered: int = Combat.hit_chance(s, soldier, enemy).hit
	soldier.status["hive_sense"] = s.turn
	var sensed: int = Combat.hit_chance(s, soldier, enemy).hit
	assert_eq(sensed - covered, Combat.COVER_HALF, "half cover removed")


## Full mission where every player readies and the AI plays both sides' enemies. Must finish cleanly.
func test_full_mission_soak_many_seeds() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var s := make_state(["runner", "runner", "spitter", "runner", "spitter"], seed)
		var rejected: Array = []  # lambdas capture ints by value, so collect into an array
		s.event.connect(func(ev): if ev.type == "rejected": rejected.append(ev))
		Rules.start_mission(s)
		for i in 60:
			if s.phase == Types.Phase.ENDED:
				break
			for p in s.players:
				Rules.set_ready(s, p, true)
		assert_eq(rejected.size(), 0, "seed %d: AI never applied a rejected action" % seed)
