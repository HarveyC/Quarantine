extends TestCase
## Gear screens: build out of the tree on a seeded run, refresh, and send legal actions.

const Demo := preload("res://ui/gear/gear_demo.gd")
const Tips := preload("res://ui/tips/tips.gd")


class FakeSession:
	extends RefCounted
	var run: RunState
	var sent: Array = []
	var player_names := {}
	var players: Array[int] = []

	func local_players() -> Array[int]:
		return players if not players.is_empty() else run.players

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


## A client viewing the host's soldier can still pick from the shared stash: the click jumps to
## their own soldier with the item held, and equipping sends the client's own action.
func test_client_takes_from_stash_while_viewing_teammate() -> void:
	GearTags.set_progression(false)
	var run := RunRules.new_run(2, 4242)
	RunRules.start_run(run)
	run.gear.offers.clear()
	Loadout.stash_add(run, "concussion_launcher")
	run.phase = RunState.Phase.MAP
	var s := _session(run)
	s.players = [1] as Array[int]
	var scr: Control = GearRun.loadout_screen().new()
	scr.setup(run, s)
	var mine: Array = scr._editable_soldiers()
	assert_true(not mine.is_empty(), "client has a soldier")
	var theirs: Array = run.squad().filter(func(r): return run.controller_of(r) == 0)
	assert_true(not theirs.is_empty(), "host has a soldier")
	scr.focus(theirs[0].id)
	var idx := Loadout.stash(run).find_custom(func(it): return it.id == "concussion_launcher")
	var tile = scr._stash_row.get_child(idx)
	assert_true(tile.clicked.is_valid(), "stash tile clickable while viewing a teammate")
	tile.clicked.call()
	assert_eq(scr._sid, mine[0].id, "jumped to the client's own soldier")
	assert_eq(scr._held, idx, "item held")
	var slot_tile = scr._slots.get_children().filter(func(c): return c.can_drop.call({"from": "stash", "id": "concussion_launcher", "index": idx}))[0]
	slot_tile.clicked.call()
	assert_eq(s.sent.back().player, 1, "action sent as the client")
	assert_eq(Loadout.item_at(run.get_soldier(mine[0].id), "gadget").id, "concussion_launcher", "equipped")
	scr.free()


func _release_click(tile: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	tile._gui_input(ev)


## Opened from the reward screen (the rank-up path), a plain click on a stash item equips it.
func test_stash_click_equips_through_the_reward_overlay() -> void:
	var run := Demo.make_run("reward")
	var s := _session(run)
	var scr: Control = GearRun.reward_screen().new()
	scr.setup(run, s)
	scr.open_loadout()
	var ov: Control = scr._overlay
	assert_true(is_instance_valid(ov), "overlay open")
	var r := run.get_soldier(ov._sid)
	var idx := Loadout.stash(run).find_custom(func(it): return it.id == "concussion_launcher")
	var tile: Control = ov._stash_row.get_child(idx)
	assert_true(tile.has_meta(Tips.META), "compare card attached")
	_release_click(tile)
	assert_eq(Loadout.item_at(run.get_soldier(r.id), "gadget").id, "concussion_launcher", "equipped by one click")
	assert_eq(s.sent.back().type, "gear_stash_take", "sent as a stash take")
	scr.free()


## Dragging shows itself: the source dims, slots that take the item are framed, the rest fade,
## and everything is restored when the drag ends.
func test_dragging_marks_sources_and_drop_targets() -> void:
	var run := Demo.make_run("loadout")
	run.phase = RunState.Phase.MAP
	var s := _session(run)
	var scr: Control = GearRun.loadout_screen().new()
	scr.setup(run, s)
	var idx := Loadout.stash(run).find_custom(func(it): return it.id == "concussion_launcher")
	var src: Control = scr._stash_row.get_child(idx)
	var data = src._get_drag_data(Vector2.ZERO)
	assert_true(data is Dictionary, "stash item can be dragged")
	assert_true(src.modulate.a < 1.0, "source tile dims")
	var valid := 0
	var faded := 0
	for t in scr._slots.get_children():
		t._mark_drag(data)
		if t.can_drop.call(data):
			valid += 1
			assert_true(t.has_theme_stylebox_override("panel"), "matching slot framed")
		else:
			faded += 1
			assert_true(t.modulate.a < 1.0, "other slots fade")
	assert_eq(valid, 1, "one slot takes a gadget")
	assert_true(faded > 0, "the rest fade")
	for t in scr._slots.get_children():
		t._unmark_drag()
		assert_eq(t.modulate.a, 1.0, "restored")
	var slot: Control = scr._slots.get_children().filter(func(t): return t.can_drop.call(data))[0]
	slot._drop_data(Vector2.ZERO, data)
	assert_eq(Loadout.item_at(run.get_soldier(scr._sid), "gadget").id, "concussion_launcher", "dropped and equipped")
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
