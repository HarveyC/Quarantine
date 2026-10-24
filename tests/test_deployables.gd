extends TestCase


func test_turret_shoots_and_expires() -> void:
	var s := make_state(["runner"])
	Rules.start_mission(s)
	var owner := s.controllable_units(0)[0]
	var cell := owner.pos
	for c in Rules.move_range(s, owner):
		if c != owner.pos:
			cell = c
			break
	var t := Deployables.spawn(s, "turret", cell, owner)
	assert_true(t != null, "spawned")
	assert_true(not s.controllable_units(0).has(t), "no player commands it")
	Infection.add(s, t, 50)
	assert_eq(t.infection, 0, "machines don't get infected")
	assert_eq(t.status.expires_turn, s.turn + 3, "lasts 3 team phases")
	s.turn = t.status.expires_turn
	Deployables.on_team_phase_start(s)
	assert_true(not t.is_alive(), "turret gone after its turns")


func test_deployables_dont_keep_the_squad_alive() -> void:
	var s := make_state(["runner"])
	Rules.start_mission(s)
	var owner := s.controllable_units(0)[0]
	var cell := owner.pos
	for c in Rules.move_range(s, owner):
		if c != owner.pos:
			cell = c
			break
	assert_true(Deployables.spawn(s, "decoy", cell, owner) != null, "decoy placed")
	for u in Deployables.soldiers(s):
		u.hp = 0
	Rules.check_end(s)
	assert_eq(s.result, Types.Result.DEFEAT, "only a decoy left is a defeat")
