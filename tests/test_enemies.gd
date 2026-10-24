extends TestCase
## Enemy roster, elites, spawners, fight builder and bosses (enemies/).


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _enemy(s: GameState, spec: String, at: Vector2i, alerted := true) -> Unit:
	var u := s.add_unit(EnemyRoster.make(spec), at)
	if alerted:
		u.status["alerted"] = true
	return u


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


## Runs one enemy turn for `u` the way Rules.run_enemy_phase does.
func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


# --- roster -------------------------------------------------------------------------------

func test_specs_make_elites_and_affixes() -> void:
	var e := EnemyRoster.make("brute!armoured,hasted")
	assert_eq(e.max_hp, 20, "elite brute hp")
	assert_true(e.status.get("elite", false), "elite flag")
	assert_eq(e.status.affixes, ["armoured", "hasted"], "affixes")
	var r := EnemyRoster.make("runner+splitting")
	assert_eq(r.max_hp, 4, "affix-only regular keeps hp")
	assert_true(EnemyRoster.has_affix(r, "splitting"), "has splitting")
	assert_true(EnemyRoster.make("lurker").status.get("hidden", false), "lurker starts hidden")
	assert_eq(EnemyRoster.make("the_source").status.get("tether", ""), "source_root", "source tethered to roots")
	for k in EnemyRoster.COST:
		assert_true(UnitData.ENEMIES.has(k), "stats for " + k)


func test_fallen_hits_do_not_infect() -> void:
	var s := make_blank(_open(10, 3))
	var t := _soldier(s, "trooper", Vector2i(1, 1))
	var f := _enemy(s, "fallen", Vector2i(6, 1))
	Rules.deal_damage(s, t, 3, f)
	assert_eq(t.infection, 0, "bullets only")
	var r := _enemy(s, "runner", Vector2i(2, 1))
	Rules.deal_damage(s, t, 2, r)
	assert_true(t.infection > 0, "runner claws infect")


func test_fallen_takes_cover_and_shoots() -> void:
	var rows := PackedStringArray([
		"..............",
		"..............",
		".........=....",
		"..............",
	])
	var s := make_blank(rows)
	_soldier(s, "trooper", Vector2i(1, 2))
	var f := _enemy(s, "fallen", Vector2i(13, 0))
	_enemy_turn(s, f)
	var shots := _events(s, "shot").size()
	var cover := Combat.cover_against(s.grid, f.pos, Vector2i(1, 2))
	assert_true(shots > 0 or f.overwatch, "shoots or overwatches")
	assert_true(cover != Types.Cover.NONE, "ends in cover (at %s)" % str(f.pos))


func test_turned_soldier_uses_cover_shooter() -> void:
	var s := make_blank(_open(12, 3))
	_soldier(s, "trooper", Vector2i(1, 1))
	var t := s.add_unit(UnitData.make("trooper", Types.Team.ENEMY), Vector2i(10, 1))
	t.status["turned"] = true
	assert_true(EnemyBehaviours.handles(s, t), "turned routed to behaviours")
	_enemy_turn(s, t)
	assert_true(_events(s, "shot").size() > 0 or t.overwatch, "turned soldier acts")


# --- bloater ------------------------------------------------------------------------------

func test_bloater_swells_then_bursts() -> void:
	var s := make_blank(_open(10, 5))
	var a := _soldier(s, "trooper", Vector2i(3, 2))
	var b := _soldier(s, "medic", Vector2i(3, 3))
	var bl := _enemy(s, "bloater", Vector2i(6, 2))
	s.turn = 1
	_enemy_turn(s, bl)
	assert_true(bl.status.has("swelling"), "swells next to 2 soldiers (at %s)" % str(bl.pos))
	assert_eq(_events(s, "telegraph").size(), 1, "burst telegraphed")
	s.turn = 2
	_enemy_turn(s, bl)
	assert_true(not bl.is_alive(), "bursts and dies")
	assert_true(a.hp < a.max_hp and b.hp < b.max_hp, "both soldiers hit")
	assert_true(a.infection >= 15, "burst infects heavily (%d)" % a.infection)
	assert_true(Encounter.is_spore(s, bl.pos), "leaves spores")


func test_bloater_bursts_on_death() -> void:
	var s := make_blank(_open(8, 3))
	var t := _soldier(s, "breacher", Vector2i(2, 1))
	var bl := _enemy(s, "bloater", Vector2i(3, 1))
	Rules.deal_damage(s, bl, 10, t)
	assert_true(not bl.is_alive(), "dead")
	assert_true(t.hp < t.max_hp, "death burst hits adjacent soldier")
	assert_eq(_events(s, "died").size(), 1, "dies once")


# --- brute --------------------------------------------------------------------------------

func test_brute_winds_up_and_charges_through_cover() -> void:
	var rows := PackedStringArray([
		"............",
		"............",
		"............",
	])
	var s := make_blank(rows)
	var t := _soldier(s, "trooper", Vector2i(6, 1))
	var br := _enemy(s, "brute", Vector2i(11, 1))
	br.mobility = 0   # stays put so the wind-up comes from here
	s.turn = 1
	_enemy_turn(s, br)
	assert_eq(br.status.get("charge_dir", Vector2i.ZERO), Vector2i(-1, 0), "winds up toward soldier")
	EnemyAbilities.set_tile(s.grid, Vector2i(8, 1), Types.Tile.LOW)
	t.pos = Vector2i(5, 1)
	s.turn = 2
	_enemy_turn(s, br)
	assert_eq(s.grid.tile(Vector2i(8, 1)), Types.Tile.FLOOR, "half cover smashed")
	assert_eq(br.pos, Vector2i(6, 1), "stops next to target")
	assert_true(t.hp < t.max_hp, "slams target")
	assert_eq(t.pos, Vector2i(4, 1), "knocked back")
	assert_eq(_events(s, "cover_destroyed").size(), 1, "cover event")


func test_brute_armour_reduces_damage() -> void:
	var s := make_blank(_open(6, 3))
	var t := _soldier(s, "trooper", Vector2i(0, 1))
	var br := _enemy(s, "brute", Vector2i(4, 1))
	Rules.deal_damage(s, br, 4, t)
	assert_eq(br.hp, 7, "armour 1")
	var el := _enemy(s, "brute!armoured", Vector2i(4, 2))
	Rules.deal_damage(s, el, 2, t)
	assert_eq(el.hp, 19, "armoured + armour, min 1")


# --- lurker -------------------------------------------------------------------------------

func test_lurker_hidden_pounces_and_pins() -> void:
	var s := make_blank(_open(14, 3))
	var a := _soldier(s, "trooper", Vector2i(1, 1))
	var b := _soldier(s, "marksman", Vector2i(9, 1))
	var l := _enemy(s, "lurker", Vector2i(13, 1), false)
	assert_true(not Combat.visible_targets(s, b).has(l), "hidden from targeting")
	assert_true(Rules.validate(s, {"type": Types.SHOOT, "unit": b.id, "target": l.id}) != "" or b.actions_left == 0, "cannot shoot it")
	s.turn = 1
	_enemy_turn(s, l)
	assert_true(not l.status.get("hidden", false), "revealed by pounce")
	assert_eq(b.status.get("pinned_by", -1), l.id, "pins the isolated soldier in reach")
	Rules.start_team_phase(s)
	assert_eq(b.actions_left, 0, "pinned soldier cannot act")
	a.actions_left = 2
	Rules.deal_damage(s, l, 1, a)
	assert_true(not b.status.has("pinned_by"), "teammate hit frees them")


func test_lurker_stays_still_when_nobody_in_reach() -> void:
	var s := make_blank(_open(24, 3))
	_soldier(s, "trooper", Vector2i(0, 1))
	var l := _enemy(s, "lurker", Vector2i(22, 1), false)
	_enemy_turn(s, l)
	assert_eq(l.pos, Vector2i(22, 1), "still")
	assert_true(l.status.get("hidden", false), "still hidden")


# --- shrieker -----------------------------------------------------------------------------

func test_shrieker_screams_buffs_and_wakes_pods() -> void:
	var s := make_blank(_open(24, 5))
	_soldier(s, "trooper", Vector2i(0, 2))
	var sh := _enemy(s, "shrieker", Vector2i(16, 2))
	var r1 := _enemy(s, "runner", Vector2i(17, 1))
	var r2 := _enemy(s, "runner", Vector2i(17, 3))
	var far := _enemy(s, "runner", Vector2i(23, 4), false)
	var base_mob := r1.mobility
	s.turn = 1
	_enemy_turn(s, sh)
	assert_eq(_events(s, "ability").filter(func(e): return e.ability == "scream").size(), 1, "screams")
	assert_eq(r1.mobility, base_mob + 2, "+2 move")
	assert_true(EnemyAI.is_alerted(far), "dormant woken")
	Encounter.on_enemy_phase_end(s)
	assert_eq(r2.mobility, base_mob + 2, "buff lasts into next turn")
	s.turn = 2
	Encounter.on_enemy_phase_end(s)
	assert_eq(r1.mobility, base_mob, "buff expires")


# --- affixes and spawners ------------------------------------------------------------------

func test_tethered_immune_while_hive_lives() -> void:
	var s := make_blank(_open(10, 3))
	var t := _soldier(s, "trooper", Vector2i(0, 1))
	var e := _enemy(s, "fallen!tethered", Vector2i(5, 1))
	var hive := _enemy(s, "hive_node", Vector2i(8, 1))
	Rules.deal_damage(s, e, 5, t)
	assert_eq(e.hp, e.max_hp, "immune")
	Rules.deal_damage(s, hive, 99, t)
	Rules.deal_damage(s, e, 5, t)
	assert_eq(e.hp, e.max_hp - 5, "hurt after the node dies")


func test_splitting_hasted_regenerating_virulent() -> void:
	var s := make_blank(_open(10, 5))
	var t := _soldier(s, "trooper", Vector2i(0, 2))
	var sp := _enemy(s, "fallen!splitting", Vector2i(5, 2))
	Rules.deal_damage(s, sp, 99, t)
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "runner").size(), 2, "splits into 2 runners")
	var h := _enemy(s, "runner+hasted", Vector2i(8, 0))
	Encounter.on_unit_turn_start(s, h)
	assert_eq(h.actions_left, 3, "hasted")
	var rg := _enemy(s, "brute!regenerating", Vector2i(8, 4))
	rg.hp = 10
	Encounter.on_unit_turn_start(s, rg)
	assert_eq(rg.hp, 13, "regenerates 3")
	var v := _enemy(s, "runner+virulent", Vector2i(1, 2))
	Rules.deal_damage(s, t, 2, v)
	assert_eq(t.infection, Infection.damage_gain(2) + Encounter.VIRULENT_EXTRA, "virulent extra infection")


func test_hive_node_spawns_runners() -> void:
	var s := make_blank(_open(10, 5))
	_soldier(s, "trooper", Vector2i(0, 2))
	Encounter.setup(s, {"hive": true})
	var hive: Unit = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "hive_node")[0]
	s.turn = 1
	Encounter.on_enemy_phase_start(s)
	assert_eq(_events(s, "spawned").size(), 0, "not on turn 1")
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_eq(_events(s, "spawned").size(), 1, "spawns on turn 2")
	s.turn = 4
	Encounter.on_enemy_phase_start(s)
	assert_eq(_events(s, "spawned").size(), 2, "every 2 turns")
	assert_true(EnemyAI.is_alerted(s.get_unit(_events(s, "spawned")[0].unit)), "spawn is alerted")
	assert_true(hive.is_alive(), "node alive")


func test_waves_are_announced_a_turn_ahead() -> void:
	var s := make_blank(_open(12, 5))
	_soldier(s, "trooper", Vector2i(0, 2))
	s.grid.enemy_spawns.assign([Vector2i(11, 0), Vector2i(11, 4)])
	Encounter.setup(s, {"waves": [{"turn": 3, "every": 0, "kinds": ["runner", "spitter"]}]})
	s.turn = 1
	Encounter.on_enemy_phase_end(s)
	assert_eq(_events(s, "reinforcements_incoming").size(), 0, "too early")
	s.turn = 2
	Encounter.on_enemy_phase_end(s)
	assert_eq(_events(s, "reinforcements_incoming").size(), 1, "warned at end of turn 2")
	s.turn = 3
	Encounter.on_enemy_phase_start(s)
	assert_eq(_events(s, "spawned").size(), 2, "arrive on turn 3")


func test_spore_patches_and_spit_puddles_use_hazards() -> void:
	var s := make_blank(_open(14, 14))
	_soldier(s, "trooper", Vector2i(1, 12))
	Encounter.setup(s, {"act": 1, "spore_patches": 2})
	assert_true(Hazards.cells_of(s, "spore").size() >= 9, "outbreak spore patches placed")
	var sp := _enemy(s, "spitter", Vector2i(10, 2))
	Encounter.after_action(s, sp, {"type": Types.ABILITY, "ability": "spit", "cell": Vector2i(1, 1)})
	assert_true(Encounter.is_spore(s, Vector2i(1, 1)), "spit leaves a puddle")


# --- fight builder ------------------------------------------------------------------------

func test_fight_builder_respects_budget_cap_and_pool() -> void:
	for act in [1, 2, 3]:
		for seed in range(1, 40):
			for outbreak in [0, 4, 7, 10, 14]:
				var f := FightBuilder.build({"act": act, "node": "skirmish", "objective": "rescue", "outbreak": outbreak, "seed": seed})
				var n: int = f.enemies.size()
				assert_true(n >= 3 and n <= FightBuilder.ENEMY_CAP, "3-5 enemies (act %d, %d)" % [act, n])
				for e in f.enemies:
					var p := EnemyRoster.parse(e)
					if not p.elite:
						assert_true(EnemyRoster.FROM_ACT[p.kind] <= act, "%s not in act %d" % [p.kind, act])
	var a := FightBuilder.build({"act": 2, "node": "skirmish", "outbreak": 5, "seed": 9})
	var b := FightBuilder.build({"act": 2, "node": "skirmish", "outbreak": 5, "seed": 9})
	assert_eq(a, b, "deterministic")


func test_fight_builder_outbreak_stages() -> void:
	var calm := FightBuilder.build({"act": 1, "node": "skirmish", "outbreak": 0, "seed": 3})
	assert_true(calm.encounter.waves.is_empty(), "no waves when contained")
	var rampant := FightBuilder.build({"act": 1, "node": "skirmish", "outbreak": 7, "seed": 3})
	assert_eq(rampant.encounter.waves.size(), 1, "wave at Rampant")
	assert_eq(rampant.encounter.infect_bonus, 5, "+5 infection at Rampant")
	var collapse := FightBuilder.build({"act": 3, "node": "skirmish", "outbreak": 15, "seed": 3})
	assert_eq(collapse.encounter.start_infection, 10, "Collapse start infection")
	assert_eq(int(collapse.encounter.waves[0].every), 3, "reinforcements every 3 turns")
	var ambush := FightBuilder.build({"act": 1, "node": "ambush", "outbreak": 0, "seed": 3})
	assert_true(ambush.encounter.get("ambush", false), "ambush starts alerted")
	var fewer := FightBuilder.build({"act": 1, "node": "skirmish", "outbreak": 0, "seed": 3, "modifiers": {"enemies_dead_at_start": 1}})
	assert_eq(fewer.enemies.size(), calm.enemies.size() - 1, "event kills one")


func test_nest_and_boss_fights() -> void:
	var nest := FightBuilder.build({"act": 1, "node": "nest", "objective": "purge", "outbreak": 10, "seed": 11})
	assert_true(nest.encounter.hive, "hive node")
	var p := EnemyRoster.parse(nest.enemies[0])
	assert_true(p.elite, "elite first")
	assert_eq(p.affixes.size(), 2, "2 affixes at high outbreak")
	var prev := FightBuilder.preview({"act": 1, "node": "nest", "seed": 11, "outbreak": 0})
	assert_eq(prev.elite, p.kind, "preview matches build, independent of outbreak")
	for act in [1, 2, 3]:
		var boss := FightBuilder.build({"act": act, "node": "boss", "objective": "boss", "outbreak": 5, "seed": 2})
		assert_eq(boss.encounter.boss, EnemyRoster.BOSS_OF_ACT[act], "boss of act %d" % act)


# --- bosses -------------------------------------------------------------------------------

func _boss_state(boss: String, rows: PackedStringArray = PackedStringArray()) -> GameState:
	var s := make_blank(rows if not rows.is_empty() else _open(14, 14))
	_soldier(s, "trooper", Vector2i(2, 12))
	_soldier(s, "marksman", Vector2i(5, 12))
	_soldier(s, "medic", Vector2i(8, 12))
	_soldier(s, "breacher", Vector2i(11, 12))
	s.grid.enemy_spawns.assign([Vector2i(7, 2)])
	Encounter.setup(s, {"boss": boss, "node": "boss", "act": 1})
	return s


func _boss(s: GameState, kind: String) -> Unit:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == kind)[0]


func test_brood_mother_phases_and_death_ends_fight() -> void:
	var s := _boss_state("brood_mother")
	var bm := _boss(s, "brood_mother")
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "egg_sac").size(), 4, "4 egg sacs")
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, bm, 40, t)
	assert_true(bm.is_alive(), "survives into phase 2")
	assert_eq(int(bm.status.boss_phase), 2, "phase 2")
	assert_eq(bm.mobility, 3, "tears free")
	Rules.start_mission(s)
	Rules.deal_damage(s, bm, 40, t)
	Rules.check_end(s)
	assert_eq(_events(s, "boss_defeated").size(), 1, "defeated")
	assert_eq(s.result, Types.Result.VICTORY, "adds die with her")


func test_colonel_hale_airstrike_and_mutation() -> void:
	var s := _boss_state("colonel_hale")
	var h := _boss(s, "colonel_hale")
	h.cooldowns.clear()
	s.turn = 1
	_enemy_turn(s, h)
	var tel: Array = s.encounter.telegraphs
	assert_eq(tel.size(), 1, "airstrike telegraphed")
	var victims := s.living(Types.Team.PLAYER).filter(func(u): return tel[0].cells.has(u.pos))
	assert_true(victims.size() >= 1, "aimed at the squad")
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_true(victims[0].hp < victims[0].max_hp, "strike lands next phase")
	assert_eq(s.encounter.telegraphs.size(), 0, "resolved")
	Rules.deal_damage(s, h, 30, victims[0])
	assert_true(h.is_alive(), "mutates instead of dying")
	assert_eq(int(h.status.boss_phase), 2, "phase 2")
	assert_true(h.hp > 20, "+20 hp")
	assert_true(EnemyBehaviours.can_charge(h), "charges in phase 2")


func test_source_roots_core_and_carrier_twist() -> void:
	var s := _boss_state("the_source")
	var src := _boss(s, "the_source")
	var roots := s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root")
	assert_eq(roots.size(), 3, "3 roots")
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, src, 5, t)
	assert_eq(src.hp, src.max_hp, "immune while roots live")
	s.turn = 1
	Encounter.on_enemy_phase_start(s)
	assert_eq(t.infection, Encounter.SOURCE_PULSE, "phase 1 pulse")
	for r in roots:
		Rules.deal_damage(s, r, 99, t)
	assert_eq(int(src.status.boss_phase), 2, "core opens")
	Rules.deal_damage(s, src, 4, t)
	assert_eq(src.hp, src.max_hp - 4, "normal damage when clean")
	Infection.add(s, t, 60)
	Rules.deal_damage(s, src, 4, t)
	assert_eq(src.hp, src.max_hp - 10, "Mutating soldier deals +50%")
	var before := t.pos
	s.turn = 2
	src.actions_left = 2
	EnemyBehaviours.custom_turn(s, src)
	assert_true(Vector2(t.pos).distance_to(Vector2(src.pos)) < Vector2(before).distance_to(Vector2(src.pos)), "most infected is pulled in")
	assert_eq(s.encounter.telegraphs.size(), 1, "core slam telegraphed")


# --- whole fights ---------------------------------------------------------------------------

## Plays a built fight with soldiers that shoot whatever they see. Returns the final state.
func _play(fight: Dictionary, seed: int, turns := 14, resync_at := -1) -> GameState:
	var config := MatchConfig.make(1, seed)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	var s := MatchConfig.build(config)
	Rules.start_mission(s)
	for i in turns:
		if s.phase == Types.Phase.ENDED:
			break
		if i == resync_at:
			s = GameState.from_dict(s.to_dict())
		for u in s.controllable_units(0):
			var targets := Combat.visible_targets(s, u)
			if not targets.is_empty() and u.actions_left > 0:
				Rules.apply(s, {"type": Types.SHOOT, "unit": u.id, "target": targets[0].id})
		for p in s.players:
			Rules.set_ready(s, p, true)
	return s


func test_built_fights_play_out_deterministically() -> void:
	var specs := [
		{"act": 1, "node": "skirmish", "objective": "hold", "outbreak": 7},
		{"act": 2, "node": "nest", "objective": "purge", "outbreak": 10},
		{"act": 3, "node": "ambush", "objective": "extract", "outbreak": 14},
		{"act": 1, "node": "boss", "objective": "boss", "outbreak": 4},
		{"act": 2, "node": "boss", "objective": "boss", "outbreak": 6},
		{"act": 3, "node": "boss", "objective": "boss", "outbreak": 9},
	]
	for sp in specs:
		sp["seed"] = 21
		var fight := FightBuilder.build(sp)
		var a := _play(fight, 77)
		var b := _play(fight, 77, 14, 3)
		assert_eq(a.checksum(), b.checksum(), "same result after a snapshot resync (%s act %d)" % [sp.node, sp.act])
		assert_true(a.turn >= 2, "fight ran (%s act %d)" % [sp.node, sp.act])
