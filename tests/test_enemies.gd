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


# --- intent matches the AI -------------------------------------------------------------------

## The overlay's target is the soldier the enemy then actually shoots, including after a kill or a move
## changes who is best, and after the plan goes stale (a lone survivor, nobody left).
func test_intent_target_follows_the_ai_decision() -> void:
	var s := make_blank(_open(14, 6))
	var a := _soldier(s, "trooper", Vector2i(2, 1))
	var b := _soldier(s, "trooper", Vector2i(2, 4))
	var f := _enemy(s, "fallen", Vector2i(10, 2))
	s.phase = Types.Phase.TEAM
	for round in 3:
		var it: Dictionary = EnemyIntent._intent(s, f)
		var plan := EnemyAI.preview(s, f)
		if plan.has("target"):
			assert_eq(int(it.target), int(plan.target), "intent names the planned target")
		var seen := s.log.size()
		_enemy_turn(s, f)
		for e in s.log.slice(seen):
			if e.type == "shot" and plan.get("type") == Types.SHOOT and e.get("target", -1) != -1:
				assert_eq(int(e.target), int(it.target), "the shot lands on the shown target")
				break
		s.phase = Types.Phase.TEAM
		# a kill or a step by the squad changes the pick
		if round == 0:
			b.hp = 0
			b.pos = Vector2i(3, 5)
	assert_true(EnemyIntent._intent(s, f).has("target"), "still has a target entry")
	for u in s.living(Types.Team.PLAYER):
		u.hp = 0
	assert_eq(int(EnemyIntent._intent(s, f).target), -1, "no hostiles, no target")


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


func test_every_outbreak_point_counts() -> void:
	var want := {0: 0, 2: 1, 3: 2, 5: 3, 6: 4, 8: 5, 9: 6, 14: 6}
	for o in want:
		assert_eq(FightBuilder.outbreak_budget(o), want[o], "budget at Outbreak %d" % o)
	var boss := FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "outbreak": 5, "seed": 2})
	var boss_hi := FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "outbreak": 4, "seed": 2})
	assert_eq(boss.enemies.size(), boss_hi.enemies.size(), "bosses only follow the stage")


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


func _sacs(s: GameState) -> Array:
	return s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "egg_sac")


func test_brood_mother_phases_and_death_ends_fight() -> void:
	var s := _boss_state("brood_mother")
	var bm := _boss(s, "brood_mother")
	assert_eq(_sacs(s).size(), BroodMother.SACS[4], "starts behind her sacs")
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, bm, 10, t)
	assert_eq(bm.hp, bm.max_hp, "shielded by her egg sacs")
	for sac in _sacs(s):
		Rules.deal_damage(s, sac, 99, t)
	Rules.deal_damage(s, bm, 999, t)
	assert_eq(int(bm.status.boss_phase), 2, "phase 2")
	assert_eq(bm.hp, BroodMother.gates(bm)[0], "one hit stops at the phase 2 gate")
	assert_eq(bm.mobility, BroodMother.MOBILITY[2], "tears free")
	Rules.deal_damage(s, bm, 999, t)
	assert_eq(int(bm.status.boss_phase), 3, "phase 3")
	assert_eq(bm.hp, BroodMother.gates(bm)[1], "and stops again at the phase 3 gate")
	Rules.start_mission(s)
	Rules.deal_damage(s, bm, 999, t)
	Rules.check_end(s)
	assert_eq(_events(s, "boss_defeated").size(), 1, "defeated")
	assert_eq(s.result, Types.Result.VICTORY, "adds die with her")


func test_brood_mother_health_scales_with_squad() -> void:
	for squad in [1, 2, 4]:
		var enc: Dictionary = FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "seed": 3,
			"players": squad, "squad": squad}).encounter
		assert_true(absf(float(enc.get("boss_health_mult", 1.0)) - float(BroodMother.HEALTH[squad])) < 0.001,
			"health share for %d soldiers" % squad)
	assert_true(40 * BroodMother.HEALTH[2] >= 30, "a pair faces at least 30 HP")


func test_brood_mother_rains_acid_that_lands_next_turn() -> void:
	var s := _boss_state("brood_mother")
	var bm := _boss(s, "brood_mother")
	for u in s.living(Types.Team.PLAYER):
		u.pos.y = 9   # within reach of her acid
	bm.cooldowns.clear()
	s.turn = 1
	_enemy_turn(s, bm)
	var tel: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "acid_rain")
	assert_eq(tel.size(), 1, "acid rain marked")
	var victims := s.living(Types.Team.PLAYER).filter(func(u): return tel[0].cells.has(u.pos))
	assert_true(victims.size() >= 1, "on the squad")
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_true(victims[0].hp < victims[0].max_hp, "lands next enemy phase")
	assert_true(Encounter.is_spore(s, tel[0].cells[4]), "leaves spores")


func test_brood_mother_relays_a_sac_once_all_are_dead() -> void:
	var s := _boss_state("brood_mother")
	var bm := _boss(s, "brood_mother")
	var t := s.living(Types.Team.PLAYER)[0]
	for sac in _sacs(s):
		Rules.deal_damage(s, sac, 99, t)
	assert_true(not bm.status.has("tether"), "open once the sacs are dead")
	bm.cooldowns.clear()
	s.turn = 3
	_enemy_turn(s, bm)
	assert_eq(_sacs(s).size(), 1, "lays a fresh sac")
	assert_eq(str(bm.status.get("tether", "")), "egg_sac", "shielded again")
	assert_eq(int(bm.cooldowns.lay), BroodMother.RELAY, "then waits before the next")


func test_brood_mother_burrows_and_surfaces_with_a_sac() -> void:
	var s := _boss_state("brood_mother")
	s.encounter["squad"] = 2
	var bm := _boss(s, "brood_mother")
	var t := s.living(Types.Team.PLAYER)[0]
	for sac in _sacs(s):
		Encounter.kill(s, sac)
	bm.status.erase("tether")
	Rules.deal_damage(s, bm, 999, t)
	assert_eq(int(bm.status.boss_phase), 2, "phase 2")
	assert_true(bm.status.has("burrowed") and bm.status.has("emerge_cell"), "breaking free dives at once, even on the squad's turn")
	s.turn = 4
	_enemy_turn(s, bm)
	assert_true(bm.status.has("burrowed"), "still digging through her first enemy phase")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "erupt"), "the eruption shows as danger")
	s.turn = 5
	_enemy_turn(s, bm)
	assert_true(not bm.status.has("burrowed"), "surfaced")
	var rocks: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "rockfall")
	assert_eq(rocks.size(), 1, "the eruption throws up rocks")
	assert_true(rocks[0].cells.size() >= BroodMother.ROCKS[2] - 1, "a spray of tiles")
	assert_true(rocks[0].cells.has(t.pos), "a soldier's own tile is marked, so they must move")
	var hp := t.hp
	s.turn = 6
	Encounter.on_enemy_phase_start(s)
	assert_true(t.hp < hp, "a soldier who stays on a marked tile is hit")
	assert_eq(_sacs(s).size(), BroodMother.SURFACE_SACS[2], "with a fresh sac")
	assert_eq(str(bm.status.get("tether", "")), "egg_sac", "that shields her")
	s.turn = 6
	assert_true(not BroodMother.will_burrow(s, bm), "stays up for a turn before diving again")


func test_brood_mother_berserk_bursts_her_sacs() -> void:
	var s := _boss_state("brood_mother")
	var bm := _boss(s, "brood_mother")
	var t := s.living(Types.Team.PLAYER)[0]
	for sac in _sacs(s):
		Encounter.kill(s, sac)
	Rules.deal_damage(s, bm, 999, t)
	BroodMother.lay_sac(s, bm, bm.pos + Vector2i(0, 2), 9)
	bm.status.erase("tether")   # as if the squad found a way through
	Rules.deal_damage(s, bm, 999, t)
	assert_eq(int(bm.status.boss_phase), 3, "berserk")
	assert_eq(_sacs(s).size(), 0, "sacs burst")
	assert_true(s.living(Types.Team.ENEMY).any(func(u): return u.kind == "broodling"), "into Broodlings")
	BroodMother.lay_sac(s, bm, bm.pos + Vector2i(0, 2), 9)
	assert_true(not bm.status.has("tether"), "a sac can't shield her any more")


func test_berserk_brood_mother_leaps_at_a_soldier_on_high_ground() -> void:
	var s := _boss_state("brood_mother")
	var bm := _boss(s, "brood_mother")
	for o in s.living(Types.Team.ENEMY):
		if o != bm:
			Encounter.kill(s, o)
	bm.status.boss_phase = 3
	bm.status.erase("tether")
	bm.mobility = BroodMother.MOBILITY[3]
	bm.pos = Vector2i(7, 6)
	var ps := s.living(Types.Team.PLAYER)
	for i in ps.size():
		ps[i].pos = Vector2i(0 + i, 13)   # far from her
		ps[i].hp = 99
		ps[i].max_hp = 99
	var high := ps[0]
	high.pos = Vector2i(7, 10)
	s.grid.set_level(high.pos, 1)
	s.turn = 5
	_enemy_turn(s, bm)
	assert_true(bm.status.has("leap_cell"), "crouches to leap at the raised soldier")
	var landing: Vector2i = bm.status.leap_cell
	assert_true(EnemyAI._cheb(landing, high.pos) <= 1, "lands beside them")
	assert_eq(EnemyIntent._intent(s, bm).label, "LEAPING", "intent shows the leap")
	var hp := high.hp
	s.turn = 6
	_enemy_turn(s, bm)
	assert_eq(bm.pos, landing, "she lands on the marked cell")
	assert_true(high.hp < hp, "the impact reaches the raised soldier")
	assert_true(not bm.status.has("leap_cell"), "the mark is spent")
	assert_eq(int(bm.cooldowns.leap_cd), BroodMother.LEAP_COOLDOWN, "and she waits before the next")


func test_colonel_hale_airstrike_and_mutation() -> void:
	var s := _boss_state("colonel_hale")
	var h := _boss(s, "colonel_hale")
	h.cooldowns.clear()
	s.turn = 1
	_enemy_turn(s, h)
	var tel: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "airstrike")
	assert_eq(tel.size(), 1, "airstrike telegraphed")
	var victims := s.living(Types.Team.PLAYER).filter(func(u): return tel[0].cells.has(u.pos))
	assert_true(victims.size() >= 1, "aimed at the squad")
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_true(victims[0].hp < victims[0].max_hp, "strike lands next phase")
	Rules.deal_damage(s, h, 999, victims[0])
	assert_true(h.is_alive(), "mutates instead of dying")
	assert_eq(int(h.status.boss_phase), 2, "phase 2")
	assert_eq(h.hp, ColonelHale.gates(h)[0] + roundi(h.max_hp * ColonelHale.HEAL), "the Bloom mends part of the hit")
	assert_true(EnemyBehaviours.can_charge(h), "charges in phase 2")


func test_hale_holds_the_high_ground() -> void:
	var s := make_blank(_open(14, 14))
	EnemyAbilities.set_tile(s.grid, Vector2i(5, 3), Types.Tile.LOW)
	s.grid.set_level(Vector2i(6, 3), 1)
	assert_eq(ColonelHale.post_near(s.grid, Vector2i(7, 2)), Vector2i(6, 3), "the one raised tile near his start")
	var enc: Dictionary = FightBuilder.build({"act": 2, "node": "boss", "objective": "boss", "seed": 3, "players": 2, "squad": 2}).encounter
	enc["boss"] = "colonel_hale"
	_soldier(s, "trooper", Vector2i(6, 12))
	s.grid.enemy_spawns.assign([Vector2i(7, 2)])
	Encounter.setup(s, enc)
	assert_eq(_boss(s, "colonel_hale").pos, Vector2i(6, 3), "he starts on it")
	assert_true(not s.encounter.waves.is_empty(), "a recovery team is on its way")


func test_hale_phases_are_gated_and_the_last_one_ends_the_fight() -> void:
	var s := _boss_state("colonel_hale")
	var h := _boss(s, "colonel_hale")
	var t := s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, h, 999, t)
	assert_eq(int(h.status.boss_phase), 2, "one hit cannot skip the Brute form")
	assert_eq(int(h.status.armour), 1, "plated")
	assert_eq(h.mobility, ColonelHale.MOBILITY[2], "faster")
	Rules.deal_damage(s, h, 999, t)
	assert_eq(int(h.status.boss_phase), 3, "nor the wreck")
	assert_eq(h.hp, ColonelHale.gates(h)[1], "stopped at the second gate")
	assert_true(not h.status.has("armour"), "the plating tears away")
	Rules.start_mission(s)
	Rules.deal_damage(s, h, 999, t)
	Rules.check_end(s)
	assert_eq(_events(s, "boss_defeated").size(), 1, "defeated")
	assert_eq(s.result, Types.Result.VICTORY, "his escort dies with him")


func test_hale_health_scales_with_squad() -> void:
	for squad in [1, 2, 4]:
		var enc: Dictionary = FightBuilder.build({"act": 2, "node": "boss", "objective": "boss", "seed": 3,
			"players": squad, "squad": squad}).encounter
		assert_true(absf(float(enc.get("boss_health_mult", 1.0)) - float(ColonelHale.HEALTH[squad])) < 0.001, "Hale's share for %d" % squad)
		var src: Dictionary = FightBuilder.build({"act": 3, "node": "boss", "objective": "boss", "seed": 3,
			"players": squad, "squad": squad}).encounter
		assert_true(absf(float(src.get("boss_health_mult", 1.0)) - float(SourceBoss.HEALTH[squad])) < 0.001, "the Source's share for %d" % squad)


func test_hale_strikes_the_rooftop_and_falls_back_behind_smoke() -> void:
	var s := make_blank(_open(16, 16))
	var low := _soldier(s, "trooper", Vector2i(3, 12))
	var high := _soldier(s, "marksman", Vector2i(12, 12))
	s.grid.set_level(high.pos, 1)
	var h := _enemy(s, "colonel_hale", Vector2i(8, 3))
	s.turn = 1
	h.cooldowns.clear()
	var strike := ColonelHale.strike_cell(s, h, EnemyAI._hostiles(s, h))
	assert_true(EnemyAI._cheb(strike.cell, high.pos) <= 1 and EnemyAI._cheb(strike.cell, low.pos) > 1, "the airstrike goes where the soldier on the roof is")
	# A soldier closing in sends him back behind a smoke screen.
	low.pos = Vector2i(8, 6)
	h.status.armour = 0
	h.cooldowns["airstrike"] = 5
	h.cooldowns["flashbang"] = 5
	var before := h.pos
	_enemy_turn(s, h)
	assert_true(Hazards.at(s, before).get("kind", "") == "smoke", "pops smoke on the way out")
	assert_true(EnemyAI._cheb(h.pos, low.pos) > EnemyAI._cheb(before, low.pos), "and falls back")
	assert_eq(EnemyIntent._intent(s, h).label, "FALLING BACK" if EnemyAI._cheb(h.pos, low.pos) <= ColonelHale.FALL_BACK else EnemyIntent._intent(s, h).label, "intent")


func test_hale_brute_stomps_a_crowd_and_charges_down_the_roofs() -> void:
	var s := make_blank(_open(16, 8))
	var a := _soldier(s, "trooper", Vector2i(7, 4))
	var b := _soldier(s, "medic", Vector2i(9, 4))
	var h := _enemy(s, "colonel_hale", Vector2i(8, 4))
	h.status.boss_phase = 2
	h.mobility = ColonelHale.MOBILITY[2]
	s.turn = 1
	_enemy_turn(s, h)
	var tel: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "stomp")
	assert_eq(tel.size(), 1, "two soldiers in reach: he stamps")
	assert_true(tel[0].cells.has(a.pos) and tel[0].cells.has(b.pos), "on both")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "stomp"), "the stamp shows as red tiles")
	# The charge brings the roofs along its lane down.
	var s2 := make_blank(_open(16, 5))
	var v := _soldier(s2, "trooper", Vector2i(12, 2))
	for x in range(5, 12):
		s2.grid.set_level(Vector2i(x, 2), 1)
	var h2 := _enemy(s2, "colonel_hale", Vector2i(3, 2))
	s2.grid.set_level(h2.pos, 1)
	h2.status.boss_phase = 2
	h2.status["charge_dir"] = Vector2i(1, 0)
	s2.grid.set_level(Vector2i(4, 2), 1)
	s2.turn = 1
	_enemy_turn(s2, h2)
	assert_eq(s2.grid.level(Vector2i(8, 2)), 0, "the lane's roofs are down")
	assert_true(_events(s2, "level_changed").size() > 0, "announced")


func test_hale_wreck_hurls_and_calls_danger_close() -> void:
	var s := make_blank(_open(16, 16))
	var a := _soldier(s, "trooper", Vector2i(8, 11))
	var b := _soldier(s, "medic", Vector2i(9, 11))
	var h := _enemy(s, "colonel_hale", Vector2i(8, 4))
	h.status.boss_phase = 3
	h.mobility = ColonelHale.MOBILITY[3]
	s.turn = 1
	_enemy_turn(s, h)
	var kinds: Array = s.encounter.telegraphs.map(func(x): return x.kind)
	assert_true(kinds.has("hurl"), "wreckage is marked on the pair")
	# Crowded, he calls danger close on his own position.
	var s2 := make_blank(_open(16, 16))
	var c := _soldier(s2, "trooper", Vector2i(8, 6))
	var h2 := _enemy(s2, "colonel_hale", Vector2i(8, 5))
	h2.status.boss_phase = 3
	s2.turn = 1
	_enemy_turn(s2, h2)
	var dc: Array = s2.encounter.telegraphs.filter(func(x): return x.kind == "danger_close")
	assert_eq(dc.size(), 1, "danger close")
	assert_eq(dc[0].cells.size(), 25, "a 5x5 on himself")
	s2.turn = 2
	Encounter.on_enemy_phase_start(s2)
	assert_eq(h2.hp, h2.max_hp, "he is not caught in his own strike")


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


func test_source_lashes_the_highest_ground_while_the_roots_live() -> void:
	var s := _boss_state("the_source")
	var src := _boss(s, "the_source")
	var ground := s.living(Types.Team.PLAYER)[0]
	var roof := s.living(Types.Team.PLAYER)[1]
	s.grid.set_level(roof.pos, 1)
	s.turn = 1
	_enemy_turn(s, src)
	var lashes: Array = s.encounter.telegraphs.filter(func(x): return x.kind == "lash")
	assert_eq(lashes.size(), SourceBoss.LASH[4], "lashes per turn")
	assert_true(lashes[0].cells.has(roof.pos), "the first lash is for the soldier on the roof")
	assert_eq(EnemyIntent._intent(s, src).icon, "pulse", "the intent names the pulse")
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_true(roof.hp < roof.max_hp, "and it lands next phase")
	assert_true(Encounter.is_spore(s, roof.pos), "leaving spores")
	assert_true(ground.hp > 0)


func test_source_collapse_regrows_roots_and_drops_the_floor() -> void:
	var s := _boss_state("the_source")
	s.encounter["squad"] = 2
	var src := _boss(s, "the_source")
	var t := s.living(Types.Team.PLAYER)[0]
	var roof := s.living(Types.Team.PLAYER)[1]
	for c in EnemyAbilities.square(s.grid, roof.pos, 1):
		s.grid.set_level(c, 1)
	for r in s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root"):
		Rules.deal_damage(s, r, 99, t)
	assert_eq(int(src.status.boss_phase), 2, "core open")
	Rules.deal_damage(s, src, 999, t)
	assert_eq(int(src.status.boss_phase), 3, "one hit cannot skip the collapse")
	assert_eq(src.hp, SourceBoss.gate(src), "stopped at the gate")
	assert_eq(str(src.status.get("tether", "")), "source_root", "it is shielded again")
	var roots := s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root")
	assert_eq(roots.size(), SourceBoss.REGROW[2], "roots regrown")
	Rules.deal_damage(s, src, 5, t)
	assert_eq(src.hp, SourceBoss.gate(src), "and immune")
	assert_true(s.encounter.telegraphs.any(func(x): return x.kind == "collapse"), "the floor is marked")
	assert_true(s.grid.level(roof.pos) == 1, "still up this turn")
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_eq(s.grid.level(roof.pos), 0, "then it falls")
	assert_true(roof.hp < roof.max_hp, "with the soldier on it")
	for r in roots:
		Rules.deal_damage(s, r, 99, t)
	assert_true(not src.status.has("tether"), "the regrown roots can be burned out")
	assert_eq(int(src.status.boss_phase), 3, "and it stays in the collapse")


func test_source_core_phase_raises_echoes_and_the_ring_runs_faster_in_the_collapse() -> void:
	var s := _boss_state("the_source")
	var src := _boss(s, "the_source")
	var t := s.living(Types.Team.PLAYER)[0]
	for r in s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root"):
		Rules.deal_damage(s, r, 99, t)
	s.turn = 1
	_enemy_turn(s, src)
	var echoes := s.living(Types.Team.ENEMY).filter(func(u): return u.display_name == "Echo")
	assert_eq(echoes.size(), 1, "an Echo climbs out of the shaft")
	assert_true(s.encounter.telegraphs.any(func(x): return x.kind == "core_slam"), "and the core slams")
	# The ring: turn 3 normally reaches ring 2; in the collapse it has already run on to ring 3.
	s.turn = 3
	Encounter.on_enemy_phase_end(s)
	assert_true(not Encounter.is_spore(s, Vector2i(3, 7)), "ring 3 is still to come")
	src.status.boss_phase = 3
	src.status["phase3_turn"] = 2
	Encounter.on_enemy_phase_end(s)
	assert_true(Encounter.is_spore(s, Vector2i(3, 7)), "the collapse runs the ring on ahead")


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
