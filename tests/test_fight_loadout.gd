extends TestCase
## The read-only loadout in a fight: opens over the HUD, shows the charges left in the unit's
## pouches (not the saved record's), and offers no way to change anything.

const MAIN := preload("res://scenes/main.tscn")


func test_fight_loadout_is_read_only_and_live() -> void:
	var l := LocalSession.new()
	l.save_enabled = false
	(Engine.get_meta("test_tree") as SceneTree).root.add_child(l)
	l.start_run(1, 31)
	RunAutoplay.settle(l.run, l.submit_run)
	l.submit_run({"type": RunRules.VOTE, "player": 0, "node": l.run.reachable_nodes()[0]})
	var u: Unit = l.state.living(Types.Team.PLAYER).filter(func(x: Unit) -> bool: return x.status.has("sid"))[0]
	var rec: Dictionary = l.run.get_soldier(int(u.status.sid))
	Loadout.add_consumable(rec, "medkit", 2)
	u.status["pockets"] = Loadout.pockets(rec).duplicate(true)
	for p in u.status.pockets:
		if p != null and p.id == "medkit":
			p.charges = 1
	var host := Control.new()
	(Engine.get_meta("test_tree") as SceneTree).root.add_child(host)
	var scr: Control = preload("res://ui/gear/loadout_screen.gd").open_in_fight(host, l.run, l, l.state, rec.id)
	assert_true(scr.fight != null, "fight loadout is read-only")
	assert_true(not scr._can_edit(rec), "no editing in a fight")
	assert_true(not scr._stash_box.visible, "stash hidden in a fight")
	var live: Dictionary = scr._live(rec)
	var left := 0
	for p in Loadout.pockets(live):
		if p != null and p.id == "medkit":
			left = int(p.charges)
	assert_eq(left, 1, "charges left come from the unit")
	host.queue_free()
	l.queue_free()
