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
	for c in TutorialScript.WALL_CELLS:
		assert_eq(g.tile(c), Types.Tile.WALL, "the compound wall at %s stands" % c)
		assert_true(not g.hard.has(c), "and it can be broken")
	for c in TutorialScript.BARREL_CELLS:
		assert_true(g.volatile.has(c), "a fuel barrel sits at %s" % c)
	var anchor := t.state.unit_at(TutorialScript.ANCHOR_CELL)
	assert_true(anchor != null and not Vision.sees_unit(t.state, Types.Team.PLAYER, anchor), "the anchor is hidden")
	assert_eq(t.state.phase, Types.Phase.TEAM, "the fight doesn't end with no Infected in play")
	t.free()


func test_every_lesson_has_a_voiced_radio_line() -> void:
	for st in TutorialScript.STEPS:
		var line: String = StoryData.TRAINING_LINES.get(st.id, "")
		assert_true(line != "", "lesson %s has a radio line" % st.id)
		assert_true(VoiceLines.templates().any(func(e: Array) -> bool: return e[0] == "okafor" and e[1] == line),
			"and it is on the voice manifest")
	assert_true(StoryData.TRAINING_LINES.has("end"), "the finale has a line too")


func test_the_squad_carries_class_rigs_and_a_charge() -> void:
	var t := _session()
	var trooper := _soldier(t, "trooper")
	var breacher := _soldier(t, "breacher")
	assert_true(trooper.abilities.has("suppress"), "the Trooper's Suppress comes from the rig in their Utility slot")
	assert_true(breacher.abilities.has("breach"), "and the Breacher's Breach")
	var carried: Array = breacher.status.get("pockets", []).filter(func(p) -> bool: return p != null and p.id == "demo_charge")
	assert_eq(carried.size(), 1, "the Breacher brings a Demo charge")
	assert_true(trooper.display_name.contains("Reyes"), "soldiers are named")
	t.free()


func test_lessons_play_through_to_the_end() -> void:
	var t := _session()
	var s := t.state
	assert_eq(_step(t), "brief", "starts on the briefing card")
	t.proceed()
	assert_eq(_step(t), "move", "Continue moves on")
	var trooper := _soldier(t, "trooper")
	var breacher := _soldier(t, "breacher")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": trooper.id, "to": Vector2i(8, 20)}), "trooper moves up")
	t.tick()
	assert_eq(_step(t), "cover", "moving onto a marked tile passes the move lesson")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": breacher.id, "to": Vector2i(15, 21)}), "breacher takes cover")
	t.tick()
	assert_eq(_step(t), "ready", "cover lesson passed")
	Rules.set_ready(s, 0, true)
	t.tick()
	assert_eq(s.turn, 2, "enemy phase ran")
	assert_eq(_step(t), "fog", "ready lesson passed on the next turn")
	assert_eq(_mobile(t).size(), 1, "the fog lesson brings a Runner")
	assert_true(not Vision.sees_unit(s, Types.Team.PLAYER, _mobile(t)[0]), "it starts in the fog")
	trooper.pos = Vector2i(9, 16)
	breacher.pos = Vector2i(8, 16)
	Vision.refresh(s)
	t.tick()
	assert_eq(_step(t), "shoot", "spotting the Runner passes the fog lesson")
	for r in _mobile(t):
		Rules.deal_damage(s, r, 99, trooper)
	t.tick()
	assert_eq(_step(t), "high_ground", "the Runner is down")
	breacher.pos = Vector2i(4, 12)
	t.tick()
	assert_eq(_step(t), "overwatch", "on the roof")
	assert_eq(_mobile(t).size(), 2, "the overwatch lesson sends two Runners")
	for r in _mobile(t):
		Rules.deal_damage(s, r, 99, trooper)
	t.tick()
	assert_eq(_step(t), "parting_blow", "clearing the wave moves on to Parting blow")
	assert_eq(_mobile(t).size(), 1, "a Runner lands on the squad")
	var biter := _mobile(t)[0]
	assert_true(Kit.cheb(biter.pos, trooper.pos) == 1 or Kit.cheb(biter.pos, breacher.pos) == 1, "right in reach")
	trooper.actions_left = 2
	breacher.actions_left = 2
	var mover := trooper if Kit.cheb(biter.pos, trooper.pos) == 1 else breacher
	var away := Vector2i(mover.pos.x, mover.pos.y + 2)
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": mover.id, "to": away, "careful": true}), "Disengage")
	t.tick()
	assert_eq(_step(t), "rig", "a careful move passes the lesson")
	var target := _mobile(t)[_mobile(t).size() - 1]
	assert_true(_mobile(t).size() >= 1, "a Runner is in sight for the rig lesson")
	trooper.actions_left = 2
	Vision.refresh(s)
	var why := Rules.validate(s, {"type": Types.ABILITY, "unit": trooper.id, "ability": "suppress", "target": target.id})
	assert_eq(why, "", "Suppress is legal on it: %s" % why)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": trooper.id, "ability": "suppress", "target": target.id}), "the rig fires")
	t.tick()
	assert_eq(_step(t), "breach", "using the rig passes the lesson")
	for r in _mobile(t):
		Rules.deal_damage(s, r, 99, trooper)
	breacher.pos = Vector2i(9, 8)
	breacher.actions_left = 2
	Vision.refresh(s)
	var charge := {"type": Types.ABILITY, "unit": breacher.id, "ability": "item:demo_charge", "cell": Vector2i(9, 7)}
	assert_eq(Rules.validate(s, charge), "", "the charge can go on the wall")
	assert_true(Rules.apply(s, charge), "the Breacher plants it")
	t.tick()
	assert_eq(_step(t), "concealment", "the wall is open")
	t.proceed()
	assert_eq(_step(t), "infection", "Continue moves on to Infection")
	var dosed := t.drill.lesson_soldier(s)
	assert_true(dosed.infection >= TutorialScript.LESSON_INFECTION, "a soldier was dosed to Exposed")
	dosed.actions_left = 2
	var surge: String = Progression.QUICK_PLAY_MUTATIONS[dosed.kind].exposed
	var mut := {"type": Types.MUTATION, "unit": dosed.id, "mutation": surge}
	assert_eq(Rules.validate(s, mut), "", "the Exposed mutation %s is awake on %s" % [surge, dosed.kind])
	assert_true(Rules.apply(s, mut), "and fires")
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
	assert_eq(_step(t), "brief", "a restart begins at the first lesson")
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
