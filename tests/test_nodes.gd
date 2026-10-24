extends TestCase

const OPS := ["supplies", "intel", "outbreak", "infection", "heal_pct", "hurt_pct", "mutation",
	"remove_mutation", "perk_pick", "serum", "recruit", "item", "modifier", "mark", "fight",
	"send_home", "chance", "if_infected", "sit_out"]


## A 2-player run in the NODE phase: trooper + marksman for player 0, medic + breacher for player 1,
## one reserve recruit each, 2 Serum samples each.
func _run(seed: int = 7) -> RunState:
	var run := RunRules.new_run(2, seed)
	GearRun.init_run(run)
	run.phase = RunState.Phase.NODE
	run.serum = {0: 2, 1: 2}
	return run


## The squad soldier of class `kind`.
func _s(run: RunState, kind: String) -> Dictionary:
	for r in run.squad():
		if r.kind == kind:
			return r
	return {}


func _events(run: RunState, type: String) -> Array:
	return run.log.filter(func(e): return e.type == type)


func _act(run, type: String, player: int, extra: Dictionary = {}) -> bool:
	var a := {"type": type, "player": player}
	a.merge(extra)
	return NodeRules.apply(run, a)


func _choose(run, player: int, option: String, soldier: int = -1) -> bool:
	return _act(run, "node_choose", player, {"option": option, "soldier": soldier})


func _check_effects(effects: Array, where: String) -> void:
	for e in effects:
		assert_true(e.op in OPS, "%s: unknown op %s" % [where, e.op])
		if e.op in ["chance", "if_infected"]:
			_check_effects(e.then, where)
			_check_effects(e.get("else", []), where)


func test_event_data_is_well_formed() -> void:
	assert_true(EventData.EVENTS.size() >= 15, "at least 15 events")
	for id in EventData.EVENTS:
		var ev: Dictionary = EventData.EVENTS[id]
		assert_true(ev.has("title") and ev.has("text") and ev.steps.has(ev.start), "%s header" % id)
		for sid in ev.steps:
			var step: Dictionary = ev.steps[sid]
			assert_true(step.kind in EventRules.KINDS, "%s.%s kind" % [id, sid])
			var seen := {}
			for opt in step.options:
				assert_true(not seen.has(opt.id), "%s.%s duplicate option %s" % [id, sid, opt.id])
				seen[opt.id] = true
				assert_true(opt.get("next", "") == "" or ev.steps.has(opt.next), "%s.%s.%s next" % [id, sid, opt.id])
				_check_effects(opt.get("effects", []), "%s.%s.%s" % [id, sid, opt.id])
			assert_true(step.options.size() >= 1 or step.has("generate"), "%s.%s has options" % [id, sid])
			var nb: Dictionary = step.get("nobody", {})
			assert_true(nb.get("next", "") == "" or ev.steps.has(nb.next), "%s.%s nobody next" % [id, sid])
			_check_effects(step.get("unanimous", {}).get("effects", []), "%s.%s unanimous" % [id, sid])


## Every event, in every act, runs to the end on timeouts alone without errors or stalls.
func test_every_event_finishes_on_timeouts() -> void:
	for id in EventData.EVENTS:
		for act in [1, 2, 3]:
			var run := _run(act * 31)
			run.act = act
			run.intel = 3
			run.soldiers[0].infection = 60
			run.soldiers[1].hp = 2
			NodeRules.enter(run, "event", id)
			var guard := 0
			while not run.node_state.finished and guard < 10:
				assert_true(_act(run, "node_timeout", 0), "%s timeout accepted" % id)
				guard += 1
			assert_true(run.node_state.finished, "%s act %d finished" % [id, act])
			assert_true(_act(run, "node_leave", 0) and _act(run, "node_leave", 1), "%s leave" % id)
			assert_true(NodeRules.is_done(run), "%s done" % id)


## The autoplay actions close every kind of node (used for absent players and the run tests).
func test_autoplay_closes_every_node() -> void:
	for kind in NodeRules.KINDS:
		var run := _run(5)
		NodeRules.enter(run, kind)
		for i in 10:
			if NodeRules.is_done(run):
				break
			for a in NodeRules.autoplay_actions(run):
				NodeRules.apply(run, a)
		assert_true(NodeRules.is_done(run), "%s closes" % kind)


func test_vote_majority_and_host_breaks_tie() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "last_broadcast")
	_choose(run, 0, "strip")
	_choose(run, 1, "broadcast")
	assert_eq(run.supplies, 80, "host's pick (strip) wins the split")
	assert_eq(run.outbreak, 0, "broadcast not applied")
	run = _run()
	run.players.assign([0, 1, 2])
	run.outbreak = 3
	NodeRules.enter(run, "event", "last_broadcast")
	_choose(run, 0, "strip")
	_choose(run, 1, "broadcast")
	assert_true(not run.node_state.finished, "waits for every vote")
	_choose(run, 2, "broadcast")
	assert_eq(run.outbreak, 1, "majority broadcast: outbreak -2")
	assert_eq(run.modifiers.get("extra_enemies"), 1, "next fight +1 enemy")


func test_event_leave_blocked_until_finished() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "last_broadcast")
	assert_true(not _act(run, "node_leave", 0), "can't leave mid-vote")
	_choose(run, 0, "strip")
	_choose(run, 1, "strip")
	assert_true(_act(run, "node_leave", 0), "can leave after")
	assert_true(not NodeRules.is_done(run), "not done until everyone leaves")
	_act(run, "node_leave", 1)
	assert_true(NodeRules.is_done(run), "done")


func test_supply_cache_all_share() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "supply_cache")
	_choose(run, 0, "share", 1)
	assert_true(not run.node_state.finished, "secret waits for every pick")
	_choose(run, 1, "share", 3)
	assert_eq(_events(run, "item_gained").size(), 2, "one item each")
	assert_eq(_events(run, "event_reveal").size(), 1, "picks revealed together")


func test_supply_cache_grab() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "supply_cache")
	_choose(run, 0, "share", 1)
	_choose(run, 1, "grab", 3)
	var gained := _events(run, "item_gained")
	assert_eq(gained.size(), 2, "grabber gets two")
	assert_true(gained.all(func(e): return e.sid == 3), "all to the grabber's soldier")
	assert_true(not _events(run, "event_choice").any(func(e): return e.option != ""), "secret picks hidden until reveal")


func test_trial_unanimous_gives_serum() -> void:
	var run := _run()
	run.serum = {0: 3, 1: 1}
	NodeRules.enter(run, "event", "the_trial")
	_choose(run, 0, "take", 2)
	_choose(run, 1, "take", 4)
	assert_eq(run.get_soldier(2).infection, 15, "+15 infection")
	assert_true(RunAccess.mutations_of(run.get_soldier(2)).size() <= 1, "at most one mutation")
	assert_eq(run.serum[1], 3, "2 samples to the player with least serum")
	var run2 := _run()
	NodeRules.enter(run2, "event", "the_trial")
	_choose(run2, 0, "take", 2)
	_choose(run2, 1, "refuse")
	assert_eq(run2.serum[0] + run2.serum[1], 4, "no bonus without everyone")


func test_checkpoint_volunteer_scan() -> void:
	var run := _run()
	run.get_soldier(3).infection = 30
	NodeRules.enter(run, "event", "checkpoint")
	_choose(run, 0, "scan")
	_choose(run, 1, "scan")
	assert_eq(run.node_state.step, "scan", "volunteer step")
	assert_true(not _choose(run, 1, "volunteer", 1), "can't volunteer someone else's soldier")
	assert_true(_choose(run, 1, "volunteer", 3), "volunteer accepted")
	assert_true(not _choose(run, 0, "volunteer", 1), "first claim only")
	assert_eq(run.get_soldier(3).sit_out, 1, "exposed volunteer held out")
	assert_eq(run.intel, 3, "+2 intel")
	assert_true(run.node_state.finished, "done")


func test_checkpoint_nobody_volunteers_then_force() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "checkpoint")
	_choose(run, 0, "scan")
	_choose(run, 1, "scan")
	_act(run, "node_pass", 0)
	_act(run, "node_pass", 1)
	assert_eq(run.node_state.step, "gate_again", "back to the gate")
	_choose(run, 0, "force")
	_choose(run, 1, "force")
	assert_eq(NodeRules.pending_fight(run).get("objective"), "extract", "extract fight")


func test_sealed_armoury_breacher_skips_volunteer() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "sealed_armoury")
	assert_eq(run.node_state.step, "loot", "breacher opens it")
	var opts := EventRules.options_for(run, run.node_state, 0)
	assert_eq(opts.size(), 2, "1 of 2 items")
	_choose(run, 0, opts[0].id, 1)
	_choose(run, 1, EventRules.options_for(run, run.node_state, 1)[1].id, 4)
	assert_eq(Loadout.equipped(run.get_soldier(1)).size(), 1, "equipped")
	assert_true(run.node_state.finished, "done")


func test_sealed_armoury_volunteer_hurts() -> void:
	var run := _run()
	run.soldiers[3].kind = "medic"
	NodeRules.enter(run, "event", "sealed_armoury")
	assert_eq(run.node_state.step, "door", "no breacher")
	_choose(run, 0, "force", 1)
	assert_eq(run.get_soldier(1).hp, 4, "trooper 7 HP loses 30% (3)")
	assert_eq(run.node_state.step, "loot", "then loot")


func test_whispers_needs_infection_and_owner_decides() -> void:
	var run := _run()
	assert_true(not EventRules.eligible(run, "whispers"), "not without a Mutating soldier")
	run.get_soldier(4).infection = 55
	assert_true(EventRules.eligible(run, "whispers"), "eligible")
	NodeRules.enter(run, "event", "whispers")
	assert_eq(run.node_state.subject, 4, "most infected")
	assert_true(not _choose(run, 0, "listen"), "only the owner")
	assert_true(_choose(run, 1, "listen"), "owner decides")
	assert_eq(run.get_soldier(4).infection, 65, "+10")
	assert_true(RunAccess.mutations_of(run.get_soldier(4)).size() <= 1, "mutation")


func test_last_seat_sends_home() -> void:
	var run := _run()
	run.get_soldier(2).hp = 1
	NodeRules.enter(run, "event", "last_seat")
	assert_eq(run.node_state.subject, 2, "most wounded")
	_choose(run, 0, "offer")
	_choose(run, 0, "send")
	_choose(run, 1, "send")
	assert_eq(run.get_soldier(2).status, RunSoldier.GONE, "left the run")
	assert_eq(run.reserve_of(0).size(), 2, "owner gets a recruit")
	assert_eq(_events(run, "perk_pick").size(), 1, "with a perk pick")


func test_spore_bloom_burn_cost_and_requirement() -> void:
	var run := _run()
	run.supplies = 20
	NodeRules.enter(run, "event", "spore_bloom")
	assert_true(not _choose(run, 0, "burn"), "can't afford fuel")
	_choose(run, 0, "push")
	_choose(run, 1, "push")
	assert_true(run.squad().all(func(r): return r.infection == 10), "+10 infection to all")
	assert_eq(run.supplies, 40, "+20 supplies")
	var run2 := _run()
	run2.supplies = 20
	run2.soldiers[2].kind = "hazmat"
	NodeRules.enter(run2, "event", "spore_bloom")
	assert_true(_choose(run2, 0, "burn") and _choose(run2, 1, "burn"), "hazmat burns for free")
	assert_eq(run2.supplies, 20, "no cost")


func test_back_alley_medic_per_player() -> void:
	var run := _run()
	run.get_soldier(1).infection = 40
	RunAccess._fallback_mutations(run.get_soldier(3)).append("surge")
	NodeRules.enter(run, "event", "back_alley_medic")
	assert_true(not _choose(run, 0, "sell", 1), "needs a mutation")
	_choose(run, 0, "purge", 1)
	assert_eq(run.get_soldier(1).infection, 10, "purged at once")
	assert_eq(run.supplies, 45, "paid 15")
	_choose(run, 1, "sell", 3)
	assert_eq(RunAccess.mutations_of(run.get_soldier(3)).size(), 0, "sold")
	assert_eq(run.serum[1], 3, "+1 sample")
	assert_true(run.node_state.finished, "done")


func test_stragglers_split_and_carrier() -> void:
	var run := _run()
	NodeRules.enter(run, "event", "stragglers")
	_choose(run, 0, "take")
	_choose(run, 1, "take")
	assert_eq(run.reserve_of(0).size(), 2, "one each")
	assert_eq(run.reserve_of(1).size(), 2, "one each")
	var carriers: Array = (run.reserve_of(0) + run.reserve_of(1)).filter(func(r): return r.get("hidden_carrier", false))
	assert_eq(carriers.size(), 1, "exactly one carrier")


func test_events_never_repeat_and_act_gating() -> void:
	var run := _run()
	assert_true(not EventRules.eligible(run, "source_signal"), "act 3 only")
	run.act = 3
	assert_true(EventRules.eligible(run, "source_signal"), "eligible in act 3")
	var seen := {}
	for i in 30:
		var ns := NodeRules.enter(run, "event")
		if ns.event == "quiet":
			break
		assert_true(not seen.has(ns.event), "no repeat %s" % ns.event)
		seen[ns.event] = true
	assert_eq(NodeRules.enter(run, "event").event, "quiet", "runs dry gracefully")


func test_events_are_deterministic() -> void:
	var a := _run(99)
	var b := _run(99)
	for run in [a, b]:
		NodeRules.enter(run, "event", "the_trial")
		_choose(run, 0, "take", 1)
		_choose(run, 1, "take", 3)
	assert_eq(RunAccess.mutations_of(a.get_soldier(1)), RunAccess.mutations_of(b.get_soldier(1)), "same mutation rolls")


func test_depot_stock_and_buy() -> void:
	var run := _run()
	run.supplies = 300
	var ns := NodeRules.enter(run, "depot")
	assert_eq(ns.stock.size(), 7, "7 items")
	assert_eq(ns.stock.map(func(e): return e.type), ["gear", "gear", "consumable", "consumable", "consumable", "serum", "service"], "layout")
	assert_true(not _act(run, "node_buy", 0, {"index": 0, "soldier": 3}), "only your own soldiers")
	var price: int = ns.stock[0].price
	assert_true(_act(run, "node_buy", 0, {"index": 0, "soldier": 1}), "buy gear")
	assert_eq(run.supplies, 300 - price, "paid")
	assert_true(not _act(run, "node_buy", 1, {"index": 0, "soldier": 3}), "sold out")
	assert_true(_act(run, "node_buy", 1, {"index": 5}), "buy serum")
	assert_eq(run.serum[1], 4, "+1 dose")
	assert_true(not _act(run, "node_buy", 0, {"index": 5}), "serum once per depot")
	assert_true(_act(run, "node_buy", 0, {"index": 2, "soldier": 2}), "buy consumable")
	assert_eq(Loadout.pockets(run.get_soldier(2))[0].id, ns.stock[2].id, "in pocket")


func test_depot_armorer_reroll_sell_quartermaster() -> void:
	var run := _run()
	run.supplies = 200
	Loadout.equip(run, run.get_soldier(1), "laser_sight")
	var ns := NodeRules.enter(run, "depot")
	ns.stock[6].id = "armorer"
	assert_true(not _act(run, "node_buy", 0, {"index": 6, "soldier": 1, "slot": "ammo"}), "empty slot")
	assert_true(_act(run, "node_buy", 0, {"index": 6, "soldier": 1, "slot": "weapon"}), "armorer")
	assert_eq(run.get_soldier(1).gear.slots.weapon.mk, 2, "Mk II")
	assert_eq(run.supplies, 170, "30 for a Common")
	var before: Array = ns.stock.slice(0, 5)
	assert_true(_act(run, "node_reroll", 1), "reroll")
	assert_eq(run.supplies, 150, "first reroll 20")
	assert_true(ns.stock[6].sold, "service kept")
	_act(run, "node_reroll", 1)
	assert_eq(run.supplies, 115, "then 35")
	assert_true(_act(run, "node_sell", 0, {"soldier": 1, "slot": "weapon"}), "sell")
	assert_eq(run.supplies, 129, "40% of 35")
	assert_true(run.get_soldier(1).gear.slots.weapon == null, "removed")
	run.modifiers["doctrines"] = ["quartermaster"]
	assert_eq(Depot.reroll_price(run, ns), 30, "quartermaster -15%")


func test_depot_duplicate_upgrades_and_stash() -> void:
	var run := _run()
	var rec: Dictionary = run.get_soldier(1)
	Loadout.equip(run, rec, "laser_sight")
	Loadout.equip(run, rec, "laser_sight")
	assert_eq(rec.gear.slots.weapon.mk, 2, "duplicate -> Mk II")
	Loadout.equip(run, rec, "smart_link")
	assert_eq(Loadout.stash(run).map(func(e): return e.id), ["laser_sight"], "old item to stash")


func test_hospital_treatments() -> void:
	var run := _run()
	run.get_soldier(1).hp = 2
	run.get_soldier(1).injuries = 1
	run.get_soldier(2).infection = 50
	run.get_soldier(3).infection = 80
	RunAccess._fallback_mutations(run.get_soldier(3)).assign(["surge", "sense"])
	run.serum[1] = 4
	NodeRules.enter(run, "hospital")
	assert_true(_act(run, "node_treat", 0, {"soldier": 2, "treatment": "train"}), "train")
	assert_eq(run.outbreak, 0, "train is free of Outbreak")
	assert_eq(_events(run, "perk_pick").size(), 1, "perk pick")
	assert_true(not _act(run, "node_treat", 0, {"soldier": 2, "treatment": "purge"}), "one treatment each")
	assert_true(_act(run, "node_treat", 0, {"soldier": 1, "treatment": "patch"}), "patch")
	assert_eq(run.get_soldier(1).hp, run.get_soldier(1).max_hp, "full HP")
	assert_eq(run.get_soldier(1).injuries, 0, "injury cleared")
	assert_eq(run.outbreak, 1, "+1 Outbreak")
	assert_true(not _act(run, "node_treat", 0, {"soldier": 3, "treatment": "cure"}), "not your soldier")
	assert_true(_act(run, "node_treat", 1, {"soldier": 3, "treatment": "cure"}), "cure")
	assert_eq(run.get_soldier(3).infection, 0, "clean")
	assert_eq(RunAccess.mutations_of(run.get_soldier(3)).size(), 0, "mutations gone")
	assert_eq(run.serum[1], 0, "2 doses spent")
	assert_eq(run.outbreak, 1, "Outbreak only once per visit")
	assert_true(not _act(run, "node_treat", 1, {"soldier": 4, "treatment": "cure"}), "needs serum")
	assert_true(not _act(run, "node_treat", 1, {"soldier": 4, "treatment": "purge"}), "already clean")


func test_hospital_purge_costs_supplies() -> void:
	var run := _run()
	run.get_soldier(1).infection = 45
	NodeRules.enter(run, "hospital")
	_act(run, "node_treat", 0, {"soldier": 1, "treatment": "purge"})
	assert_eq(run.get_soldier(1).infection, 15, "-30")
	assert_eq(run.supplies, 45, "15 Supplies")
	assert_eq(run.outbreak, 1, "+1 Outbreak")


func test_survivors_claim_and_default() -> void:
	var run := _run()
	var ns := NodeRules.enter(run, "survivors")
	assert_eq(run.supplies, 70, "+10 Supplies")
	assert_true(ns.text.contains(ns.recruit.name), "scene names the recruit")
	assert_true(_act(run, "node_claim", 1), "claim")
	assert_true(not _act(run, "node_claim", 0), "already claimed")
	assert_eq(run.reserve_of(1).size(), 2, "in player 1's reserve")
	var run2 := _run()
	RunRules.add_recruit(run2, 0)
	NodeRules.enter(run2, "survivors")
	_act(run2, "node_leave", 0)
	_act(run2, "node_leave", 1)
	assert_true(NodeRules.is_done(run2), "done")
	assert_eq(run2.reserve_of(1).size(), 2, "unclaimed -> smallest reserve")


func test_benched_player_does_not_block() -> void:
	var run := _run()
	run.benched[1] = true
	NodeRules.enter(run, "event", "supply_cache")
	assert_true(not _choose(run, 1, "share", 3), "benched can't pick")
	_choose(run, 0, "share", 1)
	assert_true(run.node_state.finished, "resolves with present players only")
	assert_eq(_events(run, "item_gained").size(), 1, "solo share = unanimous")
