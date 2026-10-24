extends TestCase
## Gear screens: build out of the tree on a seeded run, refresh, and send legal actions.

const Demo := preload("res://ui/gear/gear_demo.gd")


class FakeSession:
	extends RefCounted
	var run: RunState
	var sent: Array = []
	var player_names := {}

	func local_players() -> Array[int]:
		return run.players

	func submit_run(action: Dictionary) -> void:
		sent.append(action)
		RunRules.apply(run, action)


func _session(run: RunState) -> FakeSession:
	var s := FakeSession.new()
	s.run = run
	return s


func test_reward_screen_lists_every_soldier_and_picks() -> void:
	var run := Demo.make_run("reward")
	var s := _session(run)
	var scr: Control = GearRun.reward_screen().new()
	scr.setup(run, s)
	assert_eq(scr._my_soldiers().size(), 4, "solo picks for all four")
	assert_true(scr._sid != -1, "a soldier is selected")
	assert_eq(scr._cards.size(), 3, "three cards")
	scr._select(0)
	var a: Dictionary = scr._action(0)
	assert_eq(GearRun.validate(run, a), "", "card 0 is a legal pick: %s" % GearRun.validate(run, a))
	s.submit_run(a)
	scr._refresh()
	assert_eq(GearRun.offers(run).size(), 3, "one pick made")
	for i in 3:
		scr._skip_pick()
		scr._refresh()
	assert_true(not GearRun.has_pending(run), "all picked")
	scr.free()


func test_reward_screen_doctrine_vote() -> void:
	var run := Demo.make_run("doctrine")
	var s := _session(run)
	var scr: Control = GearRun.reward_screen().new()
	scr.setup(run, s)
	assert_eq(scr._sid, -1, "no gear picks")
	assert_eq(scr._center.get_child_count(), 3, "three Doctrine cards")
	s.submit_run({"type": "gear_doctrine", "player": 0, "doctrine": GearRun.doctrine_vote(run).options[2]})
	assert_eq(run.modifiers.doctrines.size(), 1, "solo vote resolves at once")
	scr._refresh()
	scr.free()


func test_loadout_screen_equips_from_stash_and_unequips() -> void:
	var run := Demo.make_run("loadout")
	run.phase = RunState.Phase.MAP
	var s := _session(run)
	var scr: Control = GearRun.loadout_screen().new()
	scr.setup(run, s)
	var r := run.get_soldier(scr._sid)
	var idx := Loadout.stash(run).find_custom(func(it): return it.id == "concussion_launcher")
	scr._set_preview("concussion_launcher")
	scr._refresh()
	scr._equip_from_stash(idx)
	assert_eq(Loadout.item_at(r, "gadget").id, "concussion_launcher", "equipped")
	assert_true(GearTags.has_set(GearTags.counts(r), "Suppress"), "Suppress set on")
	scr._unequip("armor")
	assert_eq(Loadout.item_at(r, "armor"), null, "armor to stash")
	assert_eq(s.sent.size(), 2, "two actions sent")
	scr._refresh()
	scr.free()
