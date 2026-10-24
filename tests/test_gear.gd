extends TestCase
## Equipment system: data, loadout rules, tags, reward offers, actions, mission stamping.


func make_run(seed: int = 7) -> Dictionary:
	GearTags.set_progression(null)  # gear alone unless a test installs a fake
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var run := {"supplies": 60, "act": 1, "rng": rng, "soldiers": [
		{"id": 1, "kind": "trooper", "player": 0}, {"id": 2, "kind": "marksman", "player": 0},
		{"id": 3, "kind": "medic", "player": 1}, {"id": 4, "kind": "breacher", "player": 1},
	]}
	GearRun.init_run(run)
	return run


func test_item_tables_are_consistent() -> void:
	assert_eq(GearData.ITEMS.size(), 37, "items")
	assert_eq(GearData.PROTOTYPES.size(), 9, "prototypes")
	for id in GearData.ITEMS:
		var d: Dictionary = GearData.ITEMS[id]
		assert_true(GearData.TAGS.has(d.tag), "%s tag" % id)
		assert_true(GearData.SLOTS.has(d.slot), "%s slot" % id)
		assert_true(["common", "uncommon", "rare"].has(d.rarity), "%s rarity" % id)
		assert_true(d.desc != "" and d.desc_mk2 != "", "%s text" % id)
	for t in GearData.TAGS:
		assert_true(GearData.items_with(t).size() >= 4, "%s has 4+ items" % t)
	for id in GearData.PROTOTYPES:
		for t in GearData.PROTOTYPES[id].tags:
			assert_true(GearData.TAGS.has(t), "%s tag %s" % [id, t])
	assert_eq(GearData.price("laser_sight"), 35, "common price")
	assert_eq(GearData.price("killbox"), -1, "prototypes not sold")
	assert_eq(GearData.upgrade_price("smart_link"), 50, "rare upgrade")


func test_equip_duplicate_upgrades_and_replace_goes_to_stash() -> void:
	var run := make_run()
	var r: Dictionary = run.soldiers[1]
	assert_eq(Loadout.equip(run, r, "laser_sight").mode, "equip", "empty slot")
	assert_eq(Loadout.equip(run, r, "laser_sight").mode, "upgrade", "duplicate")
	assert_eq(Loadout.mk_of(r, "laser_sight"), 2, "now Mk II")
	var res := Loadout.equip(run, r, "smart_link")
	assert_eq(res.mode, "replace", "same slot")
	assert_eq(Loadout.stash(run), [{"id": "laser_sight", "mk": 2}], "old item kept at Mk II in stash")
	# Another soldier takes it from the stash.
	Loadout.take_from_stash(run, run.soldiers[0], 0)
	assert_eq(Loadout.mk_of(run.soldiers[0], "laser_sight"), 2, "teammate gets the Mk II")
	assert_true(Loadout.stash(run).is_empty(), "stash emptied")


func test_full_stash_scraps_for_supplies() -> void:
	var run := make_run()
	for i in GearData.STASH_SIZE:
		assert_true(Loadout.stash_add(run, "bipod"), "stash slot %d" % i)
	var before: int = run.supplies
	var r: Dictionary = run.soldiers[0]
	Loadout.equip(run, r, "kevlar_vest")
	var res := Loadout.equip(run, r, "plated_rig")
	assert_true(res.scrapped, "scrapped")
	assert_eq(run.supplies, before + Loadout.SCRAP_SUPPLIES, "scrap value")


func test_take_from_full_stash_swaps_without_loss() -> void:
	var run := make_run()
	var r: Dictionary = run.soldiers[0]
	Loadout.equip(run, r, "kevlar_vest")
	for i in GearData.STASH_SIZE:
		Loadout.stash_add(run, "bipod" if i < 3 else "plated_rig")
	var res := Loadout.take_from_stash(run, r, 3)
	assert_true(not res.scrapped, "swap fits in the freed slot")
	assert_eq(Loadout.item_at(r, "armor").id, "plated_rig", "equipped")
	assert_true(Loadout.stash(run).has({"id": "kevlar_vest", "mk": 1}), "vest in stash")


func test_tags_sets_and_prototypes() -> void:
	var run := make_run()
	var r: Dictionary = run.soldiers[1]
	Loadout.equip(run, r, "laser_sight")
	Loadout.equip(run, r, "tracer_rounds")
	var c := GearTags.counts(r)
	assert_eq(c.get("Mark"), 2, "two Mark")
	var pv := GearTags.preview(r, "flare_launcher")
	assert_eq(pv.size(), 1, "one tag changes")
	assert_true(pv[0].unlocks and pv[0].from == 2 and pv[0].to == 3, "threshold preview 2->3")
	Loadout.equip(run, r, "flare_launcher")
	assert_true(GearTags.has_set(GearTags.counts(r), "Mark"), "Mark set on at 3")
	assert_true(GearTags.qualified_prototypes(GearTags.counts(r)).is_empty(), "needs a second tag")
	Loadout.equip(run, r, "kevlar_vest")
	Loadout.equip(run, r, "plated_rig")  # replaces vest; still one Guard
	assert_eq(GearTags.counts(r).get("Guard"), 1, "replace keeps count")


func test_progression_tags_add_on_top() -> void:
	var run := make_run()
	var fake := FakeProgression.new()
	GearTags.set_progression(fake)
	var r: Dictionary = run.soldiers[1]
	Loadout.equip(run, r, "laser_sight")
	Loadout.equip(run, r, "bipod")  # replaces laser sight (same slot)
	Loadout.equip(run, r, "tracer_rounds")
	var c := GearTags.counts(r)
	assert_eq(c.get("Mark"), 2, "gear 1 + perk 1")
	assert_eq(c.get("Overwatch"), 2, "gear 1 + perk 1")
	assert_eq(GearTags.qualified_prototypes(c), ["killbox"], "Mark + Overwatch opens Killbox")
	GearTags.set_progression(null)


func test_starting_kit_has_three_tags_and_a_class_lane() -> void:
	var run := make_run()
	GearRun.starting_kit_offers(run)
	for r in run.soldiers:
		var cards: Array = GearRun.offer_for(run, r.id).cards
		assert_eq(cards.size(), 3, "three cards")
		var tags := cards.map(func(c): return c.tags[0])
		assert_eq(tags.size(), 3, "tags")
		assert_true(tags[0] != tags[1] and tags[1] != tags[2] and tags[0] != tags[2], "different tags")
		assert_true(cards.all(func(c): return c.rarity == "common"), "commons")
		assert_true(tags.any(func(t): return GearData.CLASS_LANES[r.kind].has(t)), "a class lane")


func test_reward_pick_skip_and_ownership() -> void:
	var run := make_run()
	GearRun.on_fight_won(run, "skirmish")
	assert_eq(GearRun.offers(run).size(), 4, "one offer per soldier")
	assert_eq(GearRun.validate(run, {"type": "gear_pick", "player": 1, "soldier": 1, "card": 0}), "Not your soldier", "ownership")
	var before: int = run.supplies
	assert_true(GearRun.apply(run, {"type": "gear_pick", "player": 0, "soldier": 1, "card": -1}), "skip")
	assert_eq(run.supplies, before + GearRun.SKIP_SUPPLIES, "skip gives +10")
	assert_true(not GearRun.apply(run, {"type": "gear_pick", "player": 0, "soldier": 1, "card": 0}), "already picked")
	for id in [2, 3, 4]:
		var cards: Array = GearRun.offer_for(run, id).cards
		var pick := cards.find_custom(func(c): return c.kind != "consumable")
		var p: int = run.soldiers[id - 1].player
		assert_true(GearRun.apply(run, {"type": "gear_pick", "player": p, "soldier": id, "card": maxi(pick, 0)}), "pick %d" % id)
	assert_true(GearRun.all_picked(run), "all done")


func test_boss_offers_are_rare_and_nest_has_one_rare() -> void:
	var run := make_run()
	GearRun.on_fight_won(run, "boss")
	for r in run.soldiers:
		for c in GearRun.offer_for(run, r.id).cards:
			assert_true(c.rarity == "rare" or c.rarity == "prototype", "boss card rare")
	run.gear.offers.clear()
	GearRun.on_fight_won(run, "nest")
	for r in run.soldiers:
		var c: Dictionary = GearRun.offer_for(run, r.id).cards[0]
		assert_true(c.kind == "gear" and (c.rarity == "rare" or c.rarity == "prototype"), "nest rare")


func test_offers_lean_on_build_and_keep_a_pivot() -> void:
	var run := make_run(99)
	var r: Dictionary = run.soldiers[1]
	Loadout.equip(run, r, "laser_sight")
	Loadout.equip(run, r, "tracer_rounds")
	Loadout.equip(run, r, "bipod")  # replaces laser sight -> Mark 1, Overwatch 1
	Loadout.equip(run, r, "flare_launcher")  # Mark 2, Overwatch 1
	run.gear.fights_won = 3
	var on_build := 0
	var total := 0
	for i in 60:
		var cards := GearRun.roll_offer(run, r, "skirmish")
		var ranked := GearTags.ranked(GearTags.counts(r))
		assert_true(cards.any(func(c): return GearRun.card_tags(c).has("Mark")), "lead-tag card")
		assert_true(cards.any(func(c): return not GearRun.card_tags(c).is_empty() and GearRun.card_tags(c).all(func(t): return not ranked.slice(0, 2).has(t))), "pivot card")
		for c in cards:
			if c.kind == "gear":
				total += 1
				if c.tags.has("Mark"):
					on_build += 1
		var ids := cards.map(func(c): return c.get("id", ""))
		for id in ids:
			if id != "":
				assert_eq(ids.count(id), 1, "no duplicate card")
	assert_true(on_build * 100 / total >= 35, "gear leans on Mark (%d of %d)" % [on_build, total])


func test_pity_raises_rare_odds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var rares_base := 0
	var rares_pity := 0
	for i in 2000:
		if GearDraw.roll_rarity(rng, 1, 0) == "rare":
			rares_base += 1
		if GearDraw.roll_rarity(rng, 1, 20) == "rare":
			rares_pity += 1
	assert_true(rares_base > 50 and rares_base < 160, "about 5%% rare (%d)" % rares_base)
	assert_true(rares_pity > rares_base * 3, "pity helps (%d vs %d)" % [rares_pity, rares_base])


func test_offers_are_deterministic_for_peers() -> void:
	var a := make_run(42)
	var b := make_run(42)
	GearRun.on_fight_won(a, "skirmish")
	GearRun.on_fight_won(b, "skirmish")
	assert_eq(var_to_str(a.gear.offers), var_to_str(b.gear.offers), "same seed, same cards")


func test_consumable_pockets_stack_and_fill() -> void:
	var run := make_run()
	var r: Dictionary = run.soldiers[2]
	Loadout.of(r).pockets = [null, null]  # drop the starting medkit
	assert_true(Loadout.add_consumable(r, "medkit", 2), "first pocket")
	assert_true(Loadout.add_consumable(r, "medkit", 1), "stacks")
	assert_true(Loadout.add_consumable(r, "frag_grenade", 2), "second pocket")
	assert_true(not Loadout.can_add_consumable(r, "flashbang"), "pockets full")
	Loadout.equip(run, r, "exo_frame")
	assert_eq(Loadout.pockets(r).size(), 3, "exo frame gives a third pocket")
	assert_true(Loadout.add_consumable(r, "flashbang"), "third pocket")
	assert_true(Loadout.use_consumable(r, "medkit"), "use")
	assert_eq(Loadout.pockets(r)[0].charges, 2, "charge spent")


func test_apply_to_unit_stamps_stats_and_tags() -> void:
	var run := make_run()
	var r: Dictionary = run.soldiers[0]
	Loadout.equip(run, r, "laser_sight")
	Loadout.equip(run, r, "laser_sight")
	Loadout.equip(run, r, "kevlar_vest")
	var u := UnitData.make("trooper", Types.Team.PLAYER)
	var aim := u.aim
	var hp := u.max_hp
	GearRun.apply_to_unit(u, r)
	assert_eq(u.aim, aim + 15, "Mk II laser sight")
	assert_eq(u.max_hp, hp + 2, "vest")
	assert_eq(u.hp, u.max_hp, "full HP")
	assert_eq(u.status.gear_tags, {"Mark": 1, "Guard": 1}, "tags stamped")
	assert_eq(GearTags.unit_counts(u).get("Mark"), 1, "live count")
	var v := Unit.from_dict(u.to_dict())
	assert_eq(v.status.gear, u.status.gear, "survives snapshot")


class FakeProgression:
	extends RefCounted

	func tag_counts(_record) -> Dictionary:
		return {"Mark": 1, "Overwatch": 1}

	func unit_tag_counts(_u) -> Dictionary:
		return {}


func test_run_state_kit_rewards_and_doctrine_vote() -> void:
	GearTags.set_progression(null)
	var run := RunRules.new_run(2, 321)
	RunRules.start_run(run)
	assert_eq(run.phase, RunState.Phase.REWARD, "starting kit waits in REWARD")
	assert_true(GearRun.has_pending(run), "pending")
	var r: Dictionary = run.soldiers_of(1)[0]
	assert_eq(RunRules.validate(run, {"type": "gear_pick", "player": 0, "soldier": r.id, "card": 0}), "Not your soldier", "owner key")
	for sid in run.gear.offers.keys():
		var rec := run.get_soldier(sid)
		assert_true(RunRules.apply(run, {"type": "gear_pick", "player": rec.owner, "soldier": sid, "card": 0}), "kit pick")
	assert_eq(run.phase, RunState.Phase.MAP, "run moves on once all picked")
	assert_true(run.squad().all(func(x): return Loadout.equipped(x).size() == 1), "everyone has a starting item")
	assert_eq(RunRules.validate(run, {"type": "gear_pick", "player": 0, "soldier": r.id, "card": 0}).is_empty(), false, "no picks on the map")
	# A boss opens a Doctrine vote; a split goes to the host.
	run.phase = RunState.Phase.REWARD
	GearRun.on_fight_won(run, "boss")
	var v: Dictionary = GearRun.doctrine_vote(run)
	assert_eq(v.options.size(), 3, "three Doctrines")
	RunRules.apply(run, {"type": "gear_doctrine", "player": 1, "doctrine": v.options[1]})
	assert_true(GearRun.has_pending(run), "waits for everyone")
	RunRules.apply(run, {"type": "gear_doctrine", "player": 0, "doctrine": v.options[0]})
	assert_eq(run.modifiers.doctrines, [v.options[0]], "host breaks the split")


func test_field_rations_and_hazard_pay() -> void:
	var run := make_run()
	run["modifiers"] = {"doctrines": ["hazard_pay"]}
	var before: int = run.supplies
	GearRun.on_fight_won(run, "skirmish")
	assert_eq(run.supplies, before + GearRun.HAZARD_PAY, "hazard pay")
	run.gear.offers.clear()
	run.gear.doctrine_vote = {"options": ["field_rations"], "votes": {}}
	GearRun.apply(run, {"type": "gear_doctrine", "player": -1, "doctrine": "field_rations"})
	assert_eq(run.modifiers.heal_after_fight, GearRun.FIELD_RATIONS_HEAL, "rations")


func test_autoplay_actions_settle_rewards() -> void:
	GearTags.set_progression(null)
	var run := RunRules.new_run(2, 99)
	RunRules.start_run(run)
	run.phase = RunState.Phase.REWARD
	GearRun.on_fight_won(run, "boss")
	for a in GearRun.autoplay_actions(run):
		assert_true(RunRules.apply(run, a), "autoplay action %s" % str(a))
	assert_true(not GearRun.has_pending(run), "nothing left pending")


func test_max_hp_gear_moves_record_hp() -> void:
	var run := make_run()
	var r: Dictionary = run.soldiers[2]
	r["max_hp"] = 6
	r["hp"] = 5
	Loadout.equip(run, r, "kevlar_vest")
	assert_eq([r.max_hp, r.hp], [8, 7], "+2 max and current")
	Loadout.equip(run, r, "kevlar_vest")
	assert_eq([r.max_hp, r.hp], [9, 8], "Mk II adds one more")
	Loadout.unequip(run, r, "armor")
	assert_eq([r.max_hp, r.hp], [6, 5], "taking it off removes it")
	r.hp = 1
	Loadout.equip(run, r, "kevlar_vest", 2)
	Loadout.unequip(run, r, "armor")
	assert_eq(r.hp, 1, "never drops below 1")


func test_everyone_starts_with_a_consumable() -> void:
	var run := make_run()
	var want := {"trooper": "frag_grenade", "marksman": "smoke_grenade", "medic": "medkit", "breacher": "flashbang"}
	for r in run.soldiers:
		assert_eq(Loadout.pockets(r)[0], {"id": want[r.kind], "charges": 1}, "%s starter" % r.kind)
		assert_eq(Loadout.pockets(r)[1], null, "one pocket used")
	var odd := {"id": 9, "kind": "mystery", "player": 0}
	run.soldiers.append(odd)
	GearRun.on_recruit(run, odd)
	assert_true(GearData.STARTER_FALLBACK.has(Loadout.pockets(odd)[0].id), "random fallback for other classes")


func test_run_recruits_get_a_starter() -> void:
	var run := RunRules.new_run(1, 3)
	RunRules.start_run(run)
	for r in run.soldiers:
		assert_true(Loadout.pockets(r)[0] != null, "%s (%s) has a starter" % [r.kind, r.status])
	var rec := RunRules.add_recruit(run, 0, "medic")
	assert_eq(Loadout.pockets(rec)[0].id, "medkit", "mid-run recruit too")
