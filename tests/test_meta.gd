extends TestCase
## Meta progression: Field Data, unlock packs, Severity, run log and achievements.

const FieldHQ := preload("res://ui/meta/field_hq.gd")


func _fresh_profile(name: String) -> void:
	Profile.path = "user://test_profile_%s.cfg" % name
	DirAccess.remove_absolute(Profile.path)


func _run_helpers() -> TestCase:
	return load("res://tests/test_run.gd").new()


func _done() -> void:
	MetaUnlocks.bind({})
	Profile.path = "user://test_profile.cfg"


## A finished run built by hand: `fights` maps kind -> wins, `boss_acts` the bosses beaten.
func _ended_run(players: int, won: bool, fights: Dictionary, boss_acts: Array, meta: Dictionary = {}) -> RunState:
	var run := RunRules.new_run(players, 4242, meta)
	run.tally = {"fights": fights, "boss_acts": boss_acts, "bonus": 0, "dead": 0, "turned": 0, "lost_fights": 0}
	run.phase = RunState.Phase.ENDED
	run.result = Types.Result.VICTORY if won else Types.Result.DEFEAT
	run.act = 3 if won else 2
	return run


func test_field_data_pays_by_fight_kind_and_severity() -> void:
	var run := _ended_run(1, true, {"skirmish": 2, "nest": 1, "boss": 2}, [1, 3])
	assert_eq(MetaProgress.field_data(run), 30 + 25 + 60 + 120, "15 a skirmish, 25 a nest, 60 an act boss, 120 the Source")
	run.meta["severity"] = 2
	assert_eq(MetaProgress.field_data(run), roundi(235 * 1.2), "+10% per Severity level")
	_done()


func test_finished_run_folds_into_profile_once() -> void:
	_fresh_profile("fold")
	var run := _ended_run(1, true, {"skirmish": 4, "boss": 3}, [1, 2, 3], {"packs": [], "severity": 0})
	Profile.record_run(run)
	Profile.record_run(run)
	assert_eq(Profile.field_data(), 60 + 120 + 120, "paid once")
	assert_eq(Profile.stat("runs"), 1, "one run")
	assert_eq(Profile.stat("wins"), 1, "one win")
	assert_eq(Profile.stat("bosses_killed"), 3, "bosses")
	assert_eq(Profile.severity_max(), 1, "a win at Severity 0 unlocks Severity 1")
	var log := Profile.run_log()
	assert_eq(log.size(), 1, "logged")
	assert_eq(log[0].classes.size(), 4, "solo logs all 4 soldiers")
	assert_true(log[0].won, "logged as a win")
	assert_true(Achievements.is_unlocked("source_sealed"), "win achievement")
	assert_true(Achievements.is_unlocked("lone_lantern"), "solo win achievement")
	assert_true(not Achievements.is_unlocked("full_company"), "not a 4-player run")
	_done()


func test_host_flags_do_not_leak_into_a_client_profile() -> void:
	_fresh_profile("leak")
	var run := RunRules.new_run(2, 5, {"hazmat_unlocked": true, "packs": []})
	run.meta["vector_unlocked"] = true   # earned during this run
	Profile.record_run(run, 1)
	var meta := Profile.meta()
	assert_true(not meta.get("hazmat_unlocked", false), "the host's starting flag stays the host's")
	assert_true(meta.get("vector_unlocked", false), "a flag earned in the run is kept")
	_done()


func test_buying_packs_needs_field_data_and_order() -> void:
	_fresh_profile("buy")
	var cf := ConfigFile.new()
	cf.set_value("field", "data", 500)
	cf.save(Profile.path)
	assert_eq(Profile.buy("gear_2"), "Needs Field issue", "packs unlock in order")
	assert_eq(Profile.buy("gear_1"), "", "bought")
	assert_eq(Profile.field_data(), 450, "paid 50")
	assert_eq(Profile.buy("gear_1"), "Owned", "no double buy")
	assert_eq(Profile.buy("gear_3"), "Needs Specialist", "still in order")
	assert_eq(Profile.buy("gear_2"), "", "second pack")
	assert_eq(Profile.buy("gear_3"), "Needs 350 Field Data", "can't afford")
	assert_eq(Profile.meta().packs, ["gear_1", "gear_2"], "meta carries packs")
	assert_true(Achievements.is_unlocked("researcher"), "first unlock achievement")
	_done()


func test_locked_content_never_drops() -> void:
	RunRules.new_run(1, 77, {"packs": []})
	assert_true(MetaUnlocks.is_locked("phosphor_rounds"), "pack gear is locked")
	assert_true(not MetaUnlocks.is_locked("laser_sight"), "base gear is not")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var locked := MetaUnlocks.locked_ids({"packs": []})
	for i in 300:
		var id := GearDraw.draw_item(rng, {}, ["common", "uncommon", "rare"][i % 3])
		assert_true(not locked.has(id), "drew locked %s" % id)
	assert_true(not MutationData.bonded_pool().has("shared_blood"), "bonded mutations locked")
	assert_true(not MutationData.regular_pool("critical").has("rampage"), "deep strains locked")
	RunRules.new_run(1, 77, {"packs": ["gear_1", "gear_2", "mutation_1"]})
	assert_true(not MetaUnlocks.is_locked("phosphor_rounds"), "owned pack unlocks its gear")
	assert_true(MutationData.bonded_pool().has("shared_blood"), "owned mutation pack")
	assert_true(MetaUnlocks.is_locked("rampage"), "unowned pack stays locked")
	RunRules.new_run(1, 77)
	assert_true(not MetaUnlocks.is_locked("rampage"), "no profile: nothing locked")
	var loaded := RunState.from_dict(RunRules.new_run(1, 78, {"packs": []}).to_dict())
	MetaUnlocks.bind({})
	RunState.from_dict(loaded.to_dict())
	assert_true(MetaUnlocks.is_locked("rampage"), "a loaded run binds its locks")
	_done()


func test_coop_runs_use_the_host_unlocks() -> void:
	_fresh_profile("host")
	var cf := ConfigFile.new()
	cf.set_value("field", "packs", ["gear_1"])
	cf.save(Profile.path)
	var net := NetSession.new()
	net.lobby = {1: {"name": "Host", "player": 0}, 7: {"name": "Friend", "player": 1, "packs": ["mutation_1"]}}
	assert_eq(net.run_meta().packs, ["gear_1"], "only the host's packs")
	net.free()
	_done()


func test_first_gear_pack_completes_every_tag() -> void:
	var meta := {"packs": ["gear_1"]}
	var locked := MetaUnlocks.locked_ids(meta)
	for tag in GearData.TAGS:
		var open := GearData.items_with(tag).filter(func(id): return not locked.has(id))
		assert_true(open.size() >= GearData.SET_THRESHOLD, "%s has enough pieces for its set bonus" % tag)
		assert_true(open.any(func(id): return GearData.slot_of(id) == "gadget"), "%s has a gadget" % tag)
	assert_true(MetaUnlocks.PACKS.gear_1.cost <= 60, "the first pack comes after a run or two")


func test_starting_perks() -> void:
	var run := RunRules.new_run(1, 9, {"packs": ["field_kit", "serum_reserve"]})
	RunRules.start_run(run)
	for sid in run.gear.offers:
		assert_eq(run.gear.offers[sid].cards.size(), 4, "Field kit: 4 starting choices")
	assert_eq(run.serum[0], 8, "Serum reserve: 2 samples per soldier")
	var plain := RunRules.new_run(1, 9, {"packs": []})
	RunRules.start_run(plain)
	assert_eq(plain.serum[0], 4, "1 sample per soldier")
	for sid in plain.gear.offers:
		assert_eq(plain.gear.offers[sid].cards.size(), 3, "3 starting choices")
	_done()


func test_severity_rules_stack() -> void:
	var easy := RunRules.new_run(1, 21, {"severity": 0})
	var hard := RunRules.new_run(1, 21, {"severity": 10})
	assert_eq(easy.outbreak, 0, "normal start")
	assert_eq(hard.outbreak, Severity.START_OUTBREAK, "1: Hot zone")
	assert_eq(hard.supplies, Severity.START_SUPPLIES, "3: Short rations")
	assert_eq(hard.modifiers.get("heal_after_fight"), Severity.HEAL_AFTER_FIGHT, "4: Thin medicine")
	assert_eq(hard.reserve_of(0).size(), 0, "7: No reserves")
	assert_eq(easy.reserve_of(0).size(), 1, "normal reserve")
	assert_true(hard.soldiers.all(func(r): return r.infection >= Severity.START_INFECTION), "10: Ground zero")
	assert_eq(Severity.income(hard, 40), 30, "6: Lean pickings")
	assert_eq(Severity.boss_outbreak_drop(hard, 3), 1, "9: Unbroken")
	assert_eq(Severity.depot_mult(hard), Severity.DEPOT_MULT, "2: Price gouging")
	var spec := {"node": "boss", "modifiers": {}}
	Severity.adjust_fight_spec(hard, spec)
	assert_eq(spec.modifiers.extra_enemies, 1, "8: Dense hive")
	assert_eq(spec.modifiers.boss_health_mult, Severity.BOSS_HEALTH_MULT, "5: Swollen hosts")
	var mid := RunRules.new_run(1, 21, {"severity": 4})
	assert_eq(mid.reserve_of(0).size(), 1, "level 4 keeps reserves")
	assert_eq(Severity.income(mid, 40), 40, "level 4 keeps full pay")
	_done()


func test_severity_selection_is_capped() -> void:
	_fresh_profile("sev")
	Profile.set_severity(5)
	assert_eq(Profile.severity(), 0, "locked levels can't be picked")
	var cf := ConfigFile.new()
	cf.load(Profile.path)
	cf.set_value("field", "severity_max", 3)
	cf.save(Profile.path)
	Profile.set_severity(5)
	assert_eq(Profile.severity(), 3, "clamped to the highest unlocked")
	assert_eq(Profile.meta().severity, 3, "runs read it from meta")
	_done()


func test_full_run_tallies_and_pays() -> void:
	_fresh_profile("full")
	var h := _run_helpers()
	var run := RunRules.new_run(1, 2024, Profile.meta())
	RunRules.start_run(run)
	h._rewards(run)
	var guard := 0
	while run.phase != RunState.Phase.ENDED and guard < 100:
		guard += 1
		match run.phase:
			RunState.Phase.MAP: h._vote_first(run)
			RunState.Phase.NODE:
				for a in NodeRules.autoplay_actions(run):
					RunRules.apply(run, a)
			RunState.Phase.REWARD: h._rewards(run)
			RunState.Phase.FIGHT: h._win_fight(run, true)
	failures.append_array(h.failures)
	assert_eq(run.result, Types.Result.VICTORY, "won")
	assert_eq(run.tally.boss_acts, [1, 2, 3], "three bosses tallied")
	var fights := 0
	for k in run.tally.fights:
		fights += run.tally.fights[k]
	assert_eq(fights, run.fights_won, "every won fight tallied")
	Profile.record_run(run)
	assert_eq(Profile.field_data(), MetaProgress.field_data(run), "paid into the profile")
	assert_true(Profile.field_data() >= 15 * 3 + 60 * 2 + 120, "at least the bosses and some fights")
	_done()


func test_achievement_listener_fires_once() -> void:
	_fresh_profile("ach")
	var got: Array = []
	var cb := func(id: String) -> void: got.append(id)
	Achievements.on_unlocked(cb)
	assert_true(Achievements.unlock("first_win"), "new")
	assert_true(not Achievements.unlock("first_win"), "not twice")
	assert_true(not Achievements.unlock("no_such_thing"), "unknown id")
	assert_eq(got, ["first_win"], "listener heard it once")
	assert_eq(Achievements.unlocked(), ["first_win"], "listed")
	assert_true(Achievements.stats().has("highest_severity"), "stats for Steam")
	Achievements._listeners.erase(cb)
	_done()


func test_field_hq_builds_every_tab() -> void:
	_fresh_profile("hq")
	var run := _ended_run(1, false, {"skirmish": 1}, [], {"packs": []})
	Profile.record_run(run)
	var hq := FieldHQ.new()
	hq._ready()
	for id in FieldHQ.TABS:
		hq.show_tab(id)
		assert_true(hq._body.get_child_count() > 0, "%s tab has content" % id)
	hq.free()
	_done()
