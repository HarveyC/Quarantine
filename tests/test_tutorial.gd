extends TestCase
## Training mission lessons (tutorial/) and the onboarding flags in the profile.


func _session() -> TutorialSession:
	var t := TutorialSession.new()
	t.start_tutorial()
	Rules.start_mission(t.state)
	t.tick()
	return t


func _step(t: TutorialSession) -> String:
	return str(t.drill.current().get("id", "done"))


func _soldier(t: TutorialSession, kind: String) -> Unit:
	for u in t.state.living(Types.Team.PLAYER):
		if u.kind == kind:
			return u
	return null


func _mobile(t: TutorialSession) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in t.state.living(Types.Team.ENEMY):
		if u.kind == "runner":
			out.append(u)
	return out


func test_training_map_holds_its_lesson_cells() -> void:
	var t := _session()
	var g := t.state.grid
	for c in TutorialScript.MOVE_CELLS + TutorialScript.COVER_CELLS + TutorialScript.SCOUT_CELLS:
		assert_true(g.is_walkable(c) and g.level(c) == 0, "lesson cell %s is open ground" % c)
	assert_true(g.is_ladder(TutorialScript.ROOF_CELLS[0]), "the roof lesson starts at the ladder")
	for c in TutorialScript.ROOF_CELLS.slice(1):
		assert_eq(g.level(c), 1, "roof cell %s is raised" % c)
	var anchor := t.state.unit_at(TutorialScript.ANCHOR_CELL)
	assert_true(anchor != null and not Vision.sees_unit(t.state, Types.Team.PLAYER, anchor), "the anchor is hidden")
	assert_eq(t.state.phase, Types.Phase.TEAM, "the fight doesn't end with no Infected in play")
	t.free()


func test_lessons_play_through_to_the_end() -> void:
	var t := _session()
	var s := t.state
	assert_eq(_step(t), "welcome", "starts on the welcome card")
	t.proceed()
	assert_eq(_step(t), "move", "Continue moves on")
	var trooper := _soldier(t, "trooper")
	var marksman := _soldier(t, "marksman")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": trooper.id, "to": Vector2i(7, 18)}), "trooper moves up")
	t.tick()
	assert_eq(_step(t), "cover", "moving onto a marked tile passes the move lesson")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": marksman.id, "to": Vector2i(2, 17)}), "marksman takes cover")
	t.tick()
	assert_eq(_step(t), "ready", "cover lesson passed")
	Rules.set_ready(s, 0, true)
	t.tick()
	assert_eq(s.turn, 2, "enemy phase ran")
	assert_eq(_step(t), "fog", "ready lesson passed on the next turn")
	assert_eq(_mobile(t).size(), 1, "the fog lesson brings a Runner")
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, _mobile(t)[0]), "it starts in the fog")
	trooper.pos = Vector2i(5, 15)
	marksman.pos = Vector2i(4, 15)
	Vision.refresh(s)
	t.tick()
	assert_eq(_step(t), "shoot", "spotting the Runner passes the fog lesson")
	for r in _mobile(t):
		Rules.deal_damage(s, r, 99, trooper)
	t.tick()
	assert_eq(_step(t), "high_ground", "the Runner is down")
	marksman.pos = Vector2i(11, 11)
	t.tick()
	assert_eq(_step(t), "overwatch", "on the roof")
	assert_eq(_mobile(t).size(), 2, "the overwatch lesson sends two Runners")
	for r in _mobile(t):
		Rules.deal_damage(s, r, 99, trooper)
	t.tick()
	assert_eq(_step(t), "infection", "clearing the wave skips ahead to Infection")
	var dosed := t.drill.lesson_soldier(s)
	assert_true(dosed.infection >= TutorialScript.LESSON_INFECTION, "a soldier was dosed to Exposed")
	if dosed.actions_left <= 0:
		dosed.actions_left = 2
	assert_true(Rules.apply(s, {"type": Types.MUTATION, "unit": dosed.id, "mutation": "adrenal_surge"}), "Adrenal Surge is awake")
	t.tick()
	assert_eq(_step(t), "turning", "using the mutation passes the lesson")
	t.proceed()
	assert_eq(_step(t), "nest", "on to the nest")
	Rules.deal_damage(s, s.unit_at(TutorialScript.NEST_CELL), 99, trooper)
	t.tick()
	assert_true(t.drill.is_complete(), "training complete")
	assert_eq(s.result, Types.Result.VICTORY, "and the fight is won")
	t.free()


func test_restart_starts_over() -> void:
	var t := _session()
	t.proceed()
	t.restart()
	Rules.start_mission(t.state)
	t.tick()
	assert_eq(_step(t), "welcome", "a restart begins at the first lesson")
	assert_true(not t.save_enabled, "training never writes the run save")
	t.free()


func test_onboarding_flags_live_in_the_profile() -> void:
	var old := Onboarding.path
	Onboarding.path = "user://test_onboarding.cfg"
	DirAccess.remove_absolute(Onboarding.path)
	assert_true(Onboarding.should_offer_training(), "a new player is offered training")
	assert_true(Onboarding.hints_enabled(), "tips start on")
	Onboarding.set_flag("training_offered")
	assert_true(not Onboarding.should_offer_training(), "offered once")
	Onboarding.mark_hint("run_map")
	assert_true(Onboarding.hint_seen("run_map"), "hint remembered")
	Onboarding.set_hints_enabled(false)
	assert_true(not Onboarding.hints_enabled(), "tips off")
	Onboarding.mark_training_done()
	Onboarding.reset_hints()
	assert_true(not Onboarding.hint_seen("run_map") and Onboarding.hints_enabled(), "reset shows hints again")
	assert_true(Onboarding.training_done(), "training stays done after a reset")
	DirAccess.remove_absolute(Onboarding.path)
	Onboarding.path = old


class FakeSession extends Node:
	var run: RunState
	var mine := [0]

	func is_local(p: int) -> bool:
		return mine.has(p)


func _fake_app(session: Node) -> Node:
	var gd := GDScript.new()
	gd.source_code = "extends Node\nvar session\nvar view\nvar run_view\n"
	gd.reload()
	var app: Node = gd.new()
	app.session = session
	return app


func test_fight_tips_are_per_player() -> void:
	var Coach := load("res://ui/tutorial/coach.gd")
	var s := make_state(["runner"])
	var ids := {}
	for u in s.units:
		ids[u.kind] = u.id
	s.get_unit(ids.medic).owner_player = 1   # the medic is someone else's soldier online
	var sess := FakeSession.new()
	var app := _fake_app(sess)
	var coach: Control = Coach.new()
	coach.app = app
	coach.disabled = false
	coach._state = s
	coach._on_fight_event({"type": "infection", "unit": ids.medic, "value": 30, "tier": Infection.Tier.EXPOSED})
	assert_true(coach._queue.is_empty(), "another player's soldier gives this player no tip")
	coach._on_fight_event({"type": "infection", "unit": ids.trooper, "value": 10, "tier": Infection.Tier.CLEAN})
	assert_true(coach._queue.is_empty(), "no tip below Exposed")
	coach._on_fight_event({"type": "infection", "unit": ids.trooper, "value": 30, "tier": Infection.Tier.EXPOSED})
	coach._on_fight_event({"type": "lapse", "unit": ids.marksman})
	assert_eq(coach._queue.map(func(q: Dictionary) -> String: return q.id), ["infection", "lapse"], "own soldiers queue tips")
	for id in Coach.HINTS:
		assert_true(Coach.HINTS[id].text.length() <= 140, "tip %s stays short" % id)
	coach.free()
	app.free()
	sess.free()
