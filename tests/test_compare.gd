extends TestCase
## Item compare (GearCompare + the reward screen's compare column + depot / event hover cards)
## and opening the loadout from the reward and node screens.

const Demo := preload("res://ui/gear/gear_demo.gd")


class FakeSession:
	extends RefCounted
	var run: RunState
	var players: Array[int] = []
	var player_names := {}

	func local_players() -> Array[int]:
		return players

	func submit_run(action: Dictionary) -> void:
		RunRules.apply(run, action)


func _run() -> RunState:
	GearTags.set_progression(false)
	var run := RunRules.new_run(1, 77)
	RunRules.start_run(run)
	run.gear.offers.clear()
	return run


func _trooper(run: RunState) -> Dictionary:
	return run.squad().filter(func(r): return r.kind == "trooper")[0] if run.squad().any(func(r): return r.kind == "trooper") else run.squad()[0]


func _row(d: Dictionary, key: String) -> Dictionary:
	for r in d.stats:
		if r.key == key:
			return r
	return {}


func test_replace_names_the_old_item_and_where_it_goes() -> void:
	var run := _run()
	var r := _trooper(run)
	Loadout.equip(run, r, "ballistic_plate")
	var before := r.duplicate(true)
	var d := GearCompare.compare(run, r, {"kind": "gear", "id": "light_harness"})
	assert_eq(r, before, "compare leaves the record alone")
	assert_eq(d.swaps.size(), 1, "one swap")
	var s: Dictionary = d.swaps[0]
	assert_eq(s.mode, "replace", "replaces the armor")
	assert_eq(s.old.id, "ballistic_plate", "names the plate")
	assert_eq(s.fate, "stash", "plate goes to the stash")
	assert_eq(d.stash, [Loadout.stash(run).size(), Loadout.stash(run).size() + 1], "stash count moves")
	var mob := _row(d, "mobility")
	var dfn := _row(d, "defense")
	assert_eq(mob.to - mob.from, 1, "+1 move")
	assert_true(mob.better, "more move is better")
	assert_eq(dfn.from - dfn.to, 5, "-5 defense")
	assert_true(not dfn.better, "less defense is worse")
	assert_eq(d.tags, GearTags.preview(r, "light_harness"), "tag rows match the card's preview")


func test_full_stash_scraps_the_old_item() -> void:
	var run := _run()
	var r := _trooper(run)
	Loadout.equip(run, r, "ballistic_plate")
	while not Loadout.stash_full(run):
		Loadout.stash_add(run, "bipod")
	var d := GearCompare.compare(run, r, {"kind": "gear", "id": "light_harness"})
	assert_eq(d.swaps[0].fate, "scrap", "no room: scrapped")
	assert_eq(d.supplies, Loadout.SCRAP_SUPPLIES, "for the scrap Supplies")


func test_duplicate_shows_the_mk2_upgrade() -> void:
	var run := _run()
	var r := _trooper(run)
	Loadout.equip(run, r, "laser_sight")
	var d := GearCompare.compare(run, r, {"kind": "gear", "id": "laser_sight"})
	assert_eq(d.swaps[0].fate, "upgrade", "merges into Mk II")
	assert_eq(d.swaps[0].new.mk, 2, "offered side is Mk II")
	var aim := _row(d, "aim")
	assert_eq(aim.to - aim.from, 5, "+15 vs +10 aim")


func test_gun_keeps_the_old_one_as_a_spare() -> void:
	var run := _run()
	var r := _trooper(run)
	if r.kind != "trooper":
		return
	Loadout.unlock_primary(r)   # runs start on the sidearm; this is a soldier who has found their class gun
	var d := GearCompare.compare(run, r, {"kind": "gun", "id": "battle_rifle"})
	assert_eq(d.swaps[0].fate, "spare", "old gun kept")
	assert_eq(d.swaps[0].old.id, Weapons.id_for("trooper"), "the signature gun is in hand now")
	var dmg := _row(d, "damage")
	assert_eq(dmg.to.x - dmg.from.x, 1, "+1 damage")
	assert_eq(_row(d, "aim").to - _row(d, "aim").from, -5, "-5 aim")


## The predicted after-stats are what the soldier really has once the pick is applied.
func test_prediction_matches_the_real_pick() -> void:
	var n := 0
	for screen in ["reward", "guns", "reward_grafts", "kit"]:
		n += _check_predictions(Demo.make_run(screen))
	assert_true(n >= 30, "checked every card (%d)" % n)


func _check_predictions(run: RunState) -> int:
	var n := 0
	for sid in GearRun.offers(run).keys():
		var r := run.get_soldier(int(sid))
		var cards: Array = GearRun.offer_for(run, int(sid)).cards
		for i in cards.size():
			var copy := RunState.from_save_string(run.save_string())
			var rc: Dictionary = copy.get_soldier(int(sid))
			var d := GearCompare.compare(copy, rc, cards[i])
			var want := GearCompare.stats(rc)
			for row in d.stats:
				want[row.key] = row.to
			assert_eq(GearRun.validate(copy, {"type": "gear_pick", "player": copy.controller_of(rc), "soldier": rc.id, "card": i}), "", "legal pick")
			RunRules.apply(copy, {"type": "gear_pick", "player": copy.controller_of(rc), "soldier": rc.id, "card": i})
			assert_eq(GearCompare.stats(copy.get_soldier(int(sid))), want, "%s card %d stats" % [r.name, i])
			assert_eq(GearTags.counts(copy.get_soldier(int(sid))), _apply_tags(GearTags.counts(r), d.tags), "%s card %d tags" % [r.name, i])
			n += 1
	return n


func _apply_tags(before: Dictionary, rows: Array) -> Dictionary:
	var out := before.duplicate()
	for t in rows:
		out[t.tag] = t.to
		if t.to == 0:
			out.erase(t.tag)
	return out


func test_reward_screen_compare_column_and_loadout() -> void:
	var run := Demo.make_run("reward")
	var s := FakeSession.new()
	s.run = run
	s.players.assign(run.players)
	var scr: Control = GearRun.reward_screen().new()
	scr.setup(run, s)
	assert_true(scr._compare != null, "compare column built")
	assert_eq(scr._compare_for, -1, "idle: the soldier's kit")
	assert_true(_texts(scr._compare).has("EQUIPPED"), "kit view heading")
	scr._hovered = 0
	scr._show_compare()
	assert_eq(scr._compare_for, 0, "hover: card 0")
	assert_true(_texts(scr._compare).has("COMPARE"), "compare heading")
	scr._hovered = -1
	scr._select(1)
	assert_eq(scr._compare_for, 1, "falls back to the picked card")
	scr.open_loadout()
	assert_true(is_instance_valid(scr._overlay), "loadout opens over the pick")
	assert_eq(scr._overlay._sid, scr._sid, "on the soldier picking")
	scr._overlay.closed.emit()
	assert_eq(scr._card, 1, "the pick is still there")
	scr.free()


## In co-op each player compares against their own soldier.
func test_coop_compares_the_picking_players_soldier() -> void:
	GearTags.set_progression(false)
	var run := RunRules.new_run(2, 515)
	RunRules.start_run(run)
	run.gear.offers.clear()
	run.phase = RunState.Phase.REWARD
	GearRun.on_fight_won(run, "skirmish")
	var s := FakeSession.new()
	s.run = run
	s.players.assign([1])
	var scr: Control = GearRun.reward_screen().new()
	scr.setup(run, s)
	assert_eq(run.controller_of(run.get_soldier(scr._sid)), 1, "player 2 picks for their own soldier")
	assert_eq(scr.compare_data(0).sid, scr._sid, "and compares against that soldier")
	scr.free()


func test_node_screens_open_the_loadout_and_allow_gear_changes() -> void:
	var run := RunRules.new_run(1, 31)
	GearRun.init_run(run)
	run.phase = RunState.Phase.NODE
	run.supplies = 300
	NodeRules.enter(run, "depot", "")
	var s := FakeSession.new()
	s.run = run
	s.players.assign(run.players)
	var scr: Control = NodeRules.screen("depot").new()
	scr.setup(run, s)
	assert_true(scr.find_child("LoadoutButton", true, false) != null, "loadout button in the header")
	scr.open_loadout()
	assert_true(is_instance_valid(scr.loadout), "loadout opens over the depot")
	var r: Dictionary = run.squad()[0]
	Loadout.stash_add(run, "bipod")
	var a := {"type": "gear_stash_take", "player": run.controller_of(r), "soldier": r.id, "index": 0}
	assert_eq(GearRun.validate(run, a), "", "gear changes are allowed at a node")
	var hooked := scr.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("tip") and b.get_meta("tip").ctx is Callable)
	assert_true(not hooked.is_empty(), "depot buys carry a compare card")
	var ctx: Dictionary = hooked[0].get_meta("tip").ctx.call()
	assert_true(ctx.compare.has("swaps"), "compare data on hover")
	scr.free()


func _texts(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return out



func test_gun_swap_shows_magazine_change() -> void:
	var run := _run()
	var r := _trooper(run)
	var d := GearCompare.compare(run, r, {"kind": "gun", "id": "battle_rifle"})
	var row := _row(d, "mag")
	assert_true(not row.is_empty(), "magazine row shows for a gun swap")
	assert_eq(row.to - row.from, Weapons.mag_for("battle_rifle", r.kind) - Weapons.mag_for(Loadout.gun_id(r), r.kind), "magazine follows the gun")
	assert_eq(Weapons.mag_for("sidearm", "trooper"), Weapons.STARTER_MAG, "starter sidearm is short")
	assert_eq(Weapons.mag_for("lmg"), int(Weapons.TABLE.lmg.mag), "plain gun reads its table row")
