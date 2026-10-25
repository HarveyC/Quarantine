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
	assert_eq(r.max_hp, UnitData.ENEMIES.runner.max_hp, "affix-only regular keeps hp")
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
	assert_eq(el.hp, 19, "armoured, min 1")
	Rules.deal_damage(s, el, 5, t)
	assert_eq(el.hp, 16, "Armoured replaces the Brute's own armour instead of stacking")


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


## Pins on b by a lurker at the far end of a corridor; returns [soldier a, soldier b, lurker].
func _pinned(s: GameState) -> Array:
	var a := _soldier(s, "trooper", Vector2i(1, 1))
	var b := _soldier(s, "marksman", Vector2i(9, 1))
	var l := _enemy(s, "lurker", Vector2i(13, 1), false)
	s.turn = 1
	_enemy_turn(s, l)
	assert_eq(b.status.get("pinned_by", -1), l.id, "pinned")
	return [a, b, l]


func test_pinned_soldier_can_struggle_once_a_turn() -> void:
	var s := make_blank(_open(14, 3))
	var p := _pinned(s)
	var b: Unit = p[1]
	var l: Unit = p[2]
	l.hp = 999   # outlives the test's maulings
	l.max_hp = 999
	b.hp = 999
	b.max_hp = 999
	var tries := 0
	var freed := false
	while not freed and tries < 30:
		Rules.start_team_phase(s)
		assert_eq(b.actions_left, 0, "pinned soldiers have no actions")
		assert_eq(Rules.validate(s, {"type": Types.MOVE, "unit": b.id, "to": b.pos + Vector2i(-1, 0)}), "No actions left", "can't move")
		assert_eq(Rules.validate(s, {"type": Types.STRUGGLE, "unit": b.id}), "", "can struggle")
		assert_true(Rules.apply(s, {"type": Types.STRUGGLE, "unit": b.id}), "struggle applies")
		tries += 1
		freed = not b.status.has("pinned_by")
		if not freed:
			assert_true(Rules.validate(s, {"type": Types.STRUGGLE, "unit": b.id}) != "", "once a turn")
			assert_true(str(Rules.action_losses(s, b)[0].text).contains("failed"), "the HUD says it failed")
			s.phase = Types.Phase.TEAM
			_enemy_turn(s, l)
	assert_true(freed, "a 50% struggle frees them within 30 turns")
	assert_true(not l.status.has("pinning"), "the lurker lets go")
	assert_eq(_events(s, "struggle").size(), tries, "one struggle event per try")
	assert_true(_events(s, "struggle")[-1].freed, "the last one freed them")
	assert_eq(_events(s, "released")[-1].get("why", ""), "struggle", "released by struggling")
	assert_eq(b.actions_left, 0, "struggling spends the turn")
	Rules.start_team_phase(s)
	assert_eq(b.actions_left, Types.ACTIONS_PER_TURN, "acts normally next turn")
	assert_true(Rules.action_losses(s, b).is_empty(), "nothing to explain")


func test_struggle_rolls_match_the_chance() -> void:
	var freed := 0
	for seed in 200:
		var s := make_blank(_open(14, 3), seed + 1)
		var p := _pinned(s)
		s.phase = Types.Phase.TEAM
		Rules.apply(s, {"type": Types.STRUGGLE, "unit": p[1].id})
		if not p[1].status.has("pinned_by"):
			freed += 1
	assert_true(freed > 70 and freed < 130, "about %d%% break free (%d / 200)" % [Encounter.STRUGGLE_CHANCE, freed])


func test_only_pinned_soldiers_struggle() -> void:
	var s := make_blank(_open(14, 3))
	var p := _pinned(s)
	s.phase = Types.Phase.TEAM
	assert_eq(Rules.validate(s, {"type": Types.STRUGGLE, "unit": p[0].id}), "Not pinned", "free soldier")
	s.phase = Types.Phase.ENEMY
	assert_true(Rules.validate(s, {"type": Types.STRUGGLE, "unit": p[1].id}) != "", "not in the enemy phase")


func test_pin_breaks_when_lurker_is_knocked_away() -> void:
	var s := make_blank(_open(14, 3))
	var p := _pinned(s)
	var b: Unit = p[1]
	var l: Unit = p[2]
	EnemyAbilities.knockback(s, l, Vector2i(signi(l.pos.x - b.pos.x), 0), 2)
	assert_true(not s.grid.melee_reach(l.pos, b.pos), "knocked out of reach")
	assert_true(not b.status.has("pinned_by"), "out of reach frees them")
	Rules.start_team_phase(s)
	assert_eq(b.actions_left, Types.ACTIONS_PER_TURN, "free to act")


func test_pin_breaks_when_lurker_is_stunned() -> void:
	var s := make_blank(_open(14, 3))
	var p := _pinned(s)
	var b: Unit = p[1]
	var l: Unit = p[2]
	l.status["k_skip_turn"] = true
	Encounter.check_pins(s)
	assert_true(not b.status.has("pinned_by"), "a stunned lurker lets go")


func test_pin_hud_reason_names_the_lurker() -> void:
	var s := make_blank(_open(14, 3))
	var p := _pinned(s)
	var b: Unit = p[1]
	Rules.start_team_phase(s)
	var why := Rules.action_losses(s, b)
	assert_eq(why.size(), 1, "one reason")
	assert_eq(str(why[0].title), "Pinned", "corner word")
	assert_eq(str(why[0].icon), "pinned", "icon")
	assert_true(str(why[0].text).contains("Lurker") and str(why[0].text).contains("teammate") \
		and str(why[0].text).contains("Struggle"), "says who and how to get free")
	assert_true(Glossary.has("pinned"), "glossary term for the hover card")
	assert_eq(Glossary.find("Pinned"), "pinned", "the word Pinned means the Lurker pin, not suppression")
	assert_true(Rules.action_losses(s, p[0]).is_empty(), "the free soldier has nothing to explain")


func test_action_losses_cover_partial_losses() -> void:
	var s := make_blank(_open(24, 3))
	var u := _soldier(s, "trooper", Vector2i(1, 1))
	_enemy(s, "runner", Vector2i(22, 1), false)   # keeps the fight going
	u.status["first_turn_action_loss"] = true
	Rules.start_mission(s)
	assert_eq(s.phase, Types.Phase.TEAM, "in the team phase")
	assert_eq(u.actions_left, 1, "Whispers costs one")
	var why := Rules.action_losses(s, u)
	assert_eq(why.size(), 1, "explained")
	assert_eq(int(why[0].lost), 1, "one action")


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
	assert_eq(_events(s, "spawned").size(), 1, "not again on turn 4")
	s.turn = 5
	Encounter.on_enemy_phase_start(s)
	assert_eq(_events(s, "spawned").size(), 2, "every 3 turns")
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


# --- vertical enemies ----------------------------------------------------------------------

func test_leaper_marks_a_landing_then_lands_and_knocks_back() -> void:
	var s := make_blank(_open(12, 5))
	var a := _soldier(s, "trooper", Vector2i(3, 2))
	var le := _enemy(s, "leaper", Vector2i(9, 2))   # one move short of reaching the soldier
	s.turn = 1
	_enemy_turn(s, le)
	assert_true(le.status.has("leap_cell"), "marks a landing spot")
	assert_eq(le.pos, Vector2i(9, 2), "waits instead of running in")
	var landing: Vector2i = le.status.leap_cell
	a.overwatch = true
	a.status["ow_until"] = 99
	s.turn = 2
	_enemy_turn(s, le)
	assert_eq(le.pos, landing, "lands on the marked spot")
	assert_eq(_events(s, "shot").size(), 0, "overwatch can't catch a leap")
	assert_true(a.hp < a.max_hp, "impact damage")
	assert_true(EnemyAI._cheb(a.pos, landing) >= 1, "knocked away")


func test_leaper_runs_in_to_claw_a_soldier_within_one_move() -> void:
	var s := make_blank(_open(12, 5))
	var a := _soldier(s, "trooper", Vector2i(3, 2))
	var le := _enemy(s, "leaper", Vector2i(7, 2))
	s.turn = 1
	_enemy_turn(s, le)
	assert_true(not le.status.has("leap_cell"), "no telegraph when it can just run in")
	assert_eq(EnemyAI._cheb(le.pos, a.pos), 1, "ran in next to the soldier")


func test_leaper_misses_when_soldier_steps_out_of_the_zone() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(3, 2))
	var le := _enemy(s, "leaper", Vector2i(9, 2))
	s.turn = 1
	_enemy_turn(s, le)
	a.pos = Vector2i(0, 4)
	s.turn = 2
	_enemy_turn(s, le)
	assert_eq(a.hp, a.max_hp, "dodged")


func test_drifter_flies_over_walls_and_drops() -> void:
	var rows := PackedStringArray([
		"..........",
		"....#.....",
		"....#.....",
		"....#.....",
		"..........",
	])
	var s := make_blank(rows)
	var a := _soldier(s, "trooper", Vector2i(1, 2))
	var d := _enemy(s, "drifter", Vector2i(7, 2))
	assert_true(EnemyRoster.is_flying(d), "flying")
	s.turn = 1
	_enemy_turn(s, d)
	assert_true(EnemyAI._cheb(d.pos, a.pos) <= 2, "drifted over the wall (at %s)" % str(d.pos))
	assert_true(a.hp < a.max_hp, "dropped on the soldier")
	assert_true(Encounter.is_spore(s, a.pos), "spore puddle under them")


func test_sharpshooter_locks_on_and_fires_unless_line_is_broken() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(1, 2))
	var sh := _enemy(s, "sharpshooter", Vector2i(10, 2))
	s.turn = 1
	_enemy_turn(s, sh)
	assert_eq(int(sh.status.get("sighted", -1)), a.id, "locks on")
	assert_eq(_events(s, "telegraph").filter(func(e): return e.kind == "snipe").size(), 1, "laser telegraphed")
	assert_eq(EnemyIntent.dangers(s).filter(func(d): return d.kind == "snipe").size(), 1, "shown as danger")
	s.turn = 2
	_enemy_turn(s, sh)
	assert_true(_events(s, "shot").filter(func(e): return e.get("snipe", false)).size() == 1, "fires")
	assert_true(a.hp < a.max_hp, "never misses")
	# Suppression breaks the lock.
	var b := make_blank(_open(14, 5))
	var t := _soldier(b, "trooper", Vector2i(1, 2))
	var sh2 := _enemy(b, "sharpshooter", Vector2i(10, 2))
	b.turn = 1
	_enemy_turn(b, sh2)
	sh2.status["suppressed"] = 99
	b.turn = 2
	_enemy_turn(b, sh2)
	assert_eq(t.hp, t.max_hp, "suppressed sharpshooter can't take the shot")
	assert_eq(_events(b, "lock_lost").size(), 1, "loses the lock")


func test_burrower_tunnels_hidden_and_erupts() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(2, 2))
	var bu := _enemy(s, "burrower", Vector2i(9, 2))
	s.turn = 1
	_enemy_turn(s, bu)
	assert_true(bu.status.get("burrowed", false) and bu.status.get("hidden", false), "underground")
	assert_true(not Combat.visible_targets(s, a).has(bu), "can't be shot while burrowed")
	Rules.start_team_phase(s)
	assert_true(bu.status.get("hidden", false), "proximity doesn't reveal a burrower")
	EnemyAbilities.set_tile(s.grid, a.pos + Vector2i(0, 1), Types.Tile.LOW)
	s.turn = 2
	_enemy_turn(s, bu)
	assert_true(not bu.status.get("hidden", false), "surfaced")
	assert_true(EnemyAI._cheb(bu.pos, a.pos) == 1, "erupts next to the target")
	assert_true(a.hp < a.max_hp, "eruption damage")


func test_burrower_collapses_high_ground_under_soldiers() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(2, 2))
	for c in EnemyAbilities.square(s.grid, a.pos, 1):
		s.grid.set_level(c, 1)
	var bu := _enemy(s, "burrower", Vector2i(9, 2))
	s.turn = 1
	_enemy_turn(s, bu)
	s.turn = 2
	_enemy_turn(s, bu)
	assert_eq(s.grid.level(a.pos), 0, "roof collapsed")
	assert_true(_events(s, "level_changed").size() > 0, "Elevation.set_level announced it")
	assert_eq(_events(s, "fell").size(), 1, "the soldier fell")
	assert_true(a.hp <= a.max_hp - EnemyAbilities.ERUPT_DAMAGE - EnemyTerrain.FALL_DAMAGE_PER_LEVEL, "eruption plus fall")


func test_knockback_off_a_ledge_hurts_and_stops_at_a_step_up() -> void:
	var s := make_blank(_open(10, 3))
	var a := _soldier(s, "trooper", Vector2i(3, 1))
	s.grid.set_level(Vector2i(3, 1), 1)
	EnemyAbilities.knockback(s, a, Vector2i(1, 0), 2)
	assert_eq(a.pos, Vector2i(5, 1), "pushed off the roof")
	assert_eq(a.hp, a.max_hp - EnemyTerrain.FALL_DAMAGE_PER_LEVEL, "fall damage")
	s.grid.set_level(Vector2i(6, 1), 1)
	EnemyAbilities.knockback(s, a, Vector2i(1, 0), 2)
	assert_eq(a.pos, Vector2i(5, 1), "can't be knocked up onto high ground")


func test_leaper_goes_for_the_soldier_on_the_watchtower() -> void:
	var s := make_blank(_open(14, 7))
	var low := _soldier(s, "trooper", Vector2i(6, 1))
	var high := _soldier(s, "marksman", Vector2i(6, 5))
	s.grid.set_level(high.pos, 1)
	var le := _enemy(s, "leaper", Vector2i(12, 3))   # out of running reach, in leaping range
	s.turn = 1
	_enemy_turn(s, le)
	assert_true(le.status.has("leap_cell"), "marks a landing")
	var landing: Vector2i = le.status.leap_cell
	assert_true(EnemyAI._cheb(landing, high.pos) <= 1 and EnemyAI._cheb(landing, low.pos) > 1, "picks the high soldier")


func test_sharpshooter_on_high_ground_beats_full_cover() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(2, 2))
	EnemyAbilities.set_tile(s.grid, Vector2i(3, 2), Types.Tile.WALL)
	assert_eq(Combat.cover_against(s.grid, a.pos, Vector2i(10, 2)), Types.Cover.FULL, "full cover on flat ground")
	var sh := _enemy(s, "sharpshooter", Vector2i(10, 2))
	s.grid.set_level(sh.pos, 1)
	sh.status["sighted"] = a.id
	EnemyAbilities.apply(s, sh, {"type": Types.ABILITY, "unit": sh.id, "ability": "snipe", "target": a.id})
	var shot: Dictionary = _events(s, "shot")[-1]
	assert_true(not shot.graze, "height drops full cover to half, so no halving")


func test_act_signature_enemies_show_up_more() -> void:
	var counts := {1: {}, 2: {}, 3: {}}
	for act in [1, 2, 3]:
		for seed in range(1, 120):
			for e in FightBuilder.build({"act": act, "node": "skirmish", "outbreak": 4, "seed": seed}).enemies:
				var k: String = EnemyRoster.parse(e).kind
				counts[act][k] = counts[act].get(k, 0) + 1
	assert_true(counts[1].get("leaper", 0) > 0, "leapers in act 1")
	assert_true(counts[2].get("drifter", 0) > counts[3].get("drifter", 0), "drifters lean act 2")
	assert_true(counts[3].get("burrower", 0) > 0 and counts[2].get("burrower", 0) == 0, "burrowers only from act 3")


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
	Rules.deal_damage(s, bm, 10, t)
	assert_eq(bm.hp, bm.max_hp, "shielded by her egg sacs")
	for sac in s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "egg_sac"):
		Rules.deal_damage(s, sac, 99, t)
	Rules.deal_damage(s, bm, 99, t)
	assert_true(bm.is_alive(), "survives into phase 2")
	assert_eq(int(bm.status.boss_phase), 2, "phase 2")
	assert_eq(bm.mobility, 3, "tears free")
	assert_eq(s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "egg_sac").size(), 2, "lays 2 new sacs")
	Rules.start_mission(s)
	Rules.deal_damage(s, bm, 99, t)
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


func test_fights_are_mostly_melee_with_runners_the_staple() -> void:
	for act in [1, 2, 3]:
		for squad in [1, 2, 3, 4]:
			var counts := {}
			var ranged := 0
			var total := 0
			for seed in range(1, 150):
				var f := FightBuilder.build({"act": act, "node": "skirmish", "outbreak": seed % 8, "seed": seed, "squad": squad})
				var n := 0
				for e in f.enemies:
					var k: String = EnemyRoster.parse(e).kind
					counts[k] = counts.get(k, 0) + 1
					if EnemyRoster.is_ranged(k):
						n += 1
				var cap := mini(FightBuilder.ENEMY_CAP, squad + 1)
				assert_true(n <= FightBuilder.ranged_limit(cap), "at most %d ranged (act %d, squad %d)" % [FightBuilder.ranged_limit(cap), act, squad])
				for w in f.encounter.waves:
					for k in w.kinds:
						assert_true(not EnemyRoster.is_ranged(k), "reinforcement waves are melee")
				ranged += n
				total += f.enemies.size()
			var top := ""
			for k in counts:
				if top == "" or counts[k] > counts[top]:
					top = k
			assert_eq(top, "runner", "Runners are the most common enemy (act %d, squad %d)" % [act, squad])
			if squad >= 2:   # a solo fight is only 1-2 enemies, so one shooter is a big share
				assert_true(ranged * 4 <= total, "ranged are at most a quarter of enemies (act %d, squad %d)" % [act, squad])
