extends TestCase
## Reaper and Warden: Lunge, Bloodlust, Shield Bash, Guard, Bulwark, perks, unlocks.

const OPEN := [
	"............",
	"............",
	"............",
	"............",
	"............",
	"............",
]


func _state(rows: Array = OPEN, seed: int = 1234) -> GameState:
	var s := make_blank(PackedStringArray(rows), seed)
	s.turn = 1
	s.phase = Types.Phase.TEAM
	return s


func _add(s: GameState, kind: String, team: int, at: Vector2i, perks: Array = []) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
		u.status["perks"] = perks.duplicate()
		for id in perks:
			var grant: String = PerkData.PERKS[id].get("ability", "")
			if grant != "":
				u.abilities.append(grant)
	else:
		u.status["alerted"] = true
	Vision.refresh(s)
	return u


func _events(s: GameState) -> Array:
	var events: Array = []
	s.event.connect(func(ev): events.append(ev))
	return events


func _of(events: Array, type: String, key := "", value: Variant = null) -> Array:
	return events.filter(func(e): return e.type == type and (key == "" or e.get(key) == value))


func _lunge(s: GameState, u: Unit, t: Unit) -> bool:
	return Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "lunge", "target": t.id})


# ------------------------------------------------------------------ Reaper

func test_lunge_dashes_next_to_target_and_strikes() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(1, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(5, 2))
	t.max_hp = 99
	t.hp = 99
	var ev := _events(s)
	assert_eq(ClassAbilities.lunge_landing(s, r, t, 4), Vector2i(4, 2), "closest cell next to the target")
	assert_true(_lunge(s, r, t), "lunge accepted")
	assert_eq(r.pos, Vector2i(4, 2), "dashed in")
	assert_eq(_of(ev, "move", "unit", r.id).size(), 1, "one move event")
	var strikes := _of(ev, "ability", "ability", "lunge")
	assert_eq(strikes.size(), 1, "one strike")
	assert_eq(r.actions_left, 0, "ends the turn")


func test_lunge_out_of_reach_rejected() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(1, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(7, 2))
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": r.id, "ability": "lunge", "target": t.id}), "Can't reach")
	r.status["perks"] = ["long_stride"]
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": r.id, "ability": "lunge", "target": t.id}), "", "Long Stride reaches 6")


func test_strike_odds_add_melee_aim_and_red_mist() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(3, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(4, 2))
	assert_eq(ClassAbilities.strike_odds(s, r, t).hit, r.aim + ClassAbilities.MELEE_AIM, "aim + 15 in the open")
	r.status["perks"] = ["red_mist"]
	r.infection = 80
	assert_eq(ClassAbilities.strike_odds(s, r, t).hit, 100, "Red Mist at Critical")


func test_bloodlust_refunds_an_action_once_per_turn_and_feeds() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(3, 2))
	var a := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	var b := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 3))
	a.hp = 1
	b.hp = 1
	var ev := _events(s)
	r.status["perks"] = ["red_mist", "harvest"]
	r.infection = 80   # Critical: never misses, +3 damage
	r.hp = 3
	assert_true(_lunge(s, r, a), "first lunge")
	assert_true(not a.is_alive(), "killed")
	assert_eq(r.actions_left, 1, "Bloodlust gave an action back")
	assert_eq(r.infection, 85, "Feeds on It: +5 from an Infected kill")
	assert_eq(r.hp, 5, "Harvest healed 2")
	assert_true(_lunge(s, r, b), "second lunge on the refund")
	assert_true(not b.is_alive(), "second kill")
	assert_eq(r.actions_left, 0, "only once per turn")
	assert_eq(_of(ev, "perk", "perk", "bloodlust").size(), 1, "one bloodlust event")


func test_low_profile_penalises_overwatch_on_a_reaper() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(2, 2))
	var e := _add(s, "fallen", Types.Team.ENEMY, Vector2i(8, 2))
	var normal: int = Combat.hit_chance(s, e, r, e.pos, false).hit
	var reaction: int = Combat.hit_chance(s, e, r, e.pos, true).hit
	assert_eq(normal - reaction, Combat.REACTION_PENALTY + Kit.LOW_PROFILE, "reaction -15 and Low Profile -15")


func test_cleave_hits_every_adjacent_enemy() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(1, 2), ["cleave"])
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(4, 2))
	var o := _add(s, "spitter", Types.Team.ENEMY, Vector2i(3, 3))
	t.hp = 99
	o.hp = 99
	var ev := _events(s)
	assert_true(_lunge(s, r, t), "lunge")
	var strikes := _of(ev, "ability", "ability", "lunge")
	assert_eq(strikes.size(), 2, "main strike + cleave")
	assert_true(strikes[1].get("cleave", false) and strikes[1].target == o.id, "cleave on the neighbour")


func test_bleed_out_ticks_two_turns() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.PLAYER, Vector2i(3, 2), ["bleed_out", "red_mist"])
	r.infection = 80
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(4, 2))
	t.max_hp = 99
	t.hp = 99
	var ev := _events(s)
	_lunge(s, r, t)
	var hp := t.hp
	assert_eq(int(t.status.get("k_bleed", 0)), 2, "bleeding 2 turns")
	s.phase = Types.Phase.ENEMY
	Kit.on_enemy_phase_start(s)
	Kit.on_enemy_phase_start(s)
	Kit.on_enemy_phase_start(s)
	assert_eq(t.hp, hp - 2, "two ticks of 1, then stops")
	assert_eq(_of(ev, "bleed").size(), 2, "two bleed events")


# ------------------------------------------------------------------ Warden

func test_bash_knocks_back_and_stuns() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(3, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(4, 2))
	t.max_hp = 99
	t.hp = 99
	w.aim = 200   # always hits
	var ev := _events(s)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": w.id, "ability": "bash", "target": t.id}), "bash")
	assert_eq(t.pos, Vector2i(5, 2), "knocked back a tile")
	assert_true(t.status.get("k_skip_turn", false), "stunned")
	assert_eq(_of(ev, "stunned").size(), 1, "stunned event")
	assert_eq(w.actions_left, 1, "costs 1 action")
	assert_eq(int(w.cooldowns.get("bash", 0)), 1, "once per turn")
	assert_true(Kit.skips_turn(t), "skips its next turn")


func test_bash_turned_soldier_bonus_and_boss_stands_firm() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(3, 2))
	w.aim = 200
	var turned := _add(s, "trooper", Types.Team.ENEMY, Vector2i(4, 2))
	turned.status["turned"] = true
	turned.max_hp = 99
	turned.hp = 99
	var ev := _events(s)
	ClassAbilities.strike(s, w, turned, "bash")
	var dmg: int = _of(ev, "ability", "ability", "bash")[0].damage
	assert_true(dmg >= ClassAbilities.MAUL_DAMAGE.x + ClassAbilities.QUARANTINE_DAMAGE, "Quarantine +2 on Turned")
	var boss := _add(s, "spitter", Types.Team.ENEMY, Vector2i(3, 3))
	boss.status["boss"] = "test"
	boss.max_hp = 99
	boss.hp = 99
	ClassAbilities.strike(s, w, boss, "bash")
	assert_eq(boss.pos, Vector2i(3, 3), "bosses aren't knocked back")
	assert_true(not boss.status.get("k_skip_turn", false), "or stunned")


func test_guard_bashes_the_first_enemy_that_steps_adjacent() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(3, 2))
	w.aim = 200
	var r := _add(s, "runner", Types.Team.ENEMY, Vector2i(9, 2))
	r.max_hp = 99
	r.hp = 99
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": w.id, "ability": "guard"}), "guard")
	assert_eq(w.actions_left, 0, "ends turn")
	s.phase = Types.Phase.ENEMY
	r.actions_left = 2
	var ev := _events(s)
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": r.id, "to": Vector2i(4, 2)}), "runner moves in")
	var bashes := _of(ev, "ability", "ability", "bash")
	assert_eq(bashes.size(), 1, "guard bashed it")
	assert_true(bashes[0].get("reaction", false), "as a reaction")
	assert_eq(r.actions_left, 0, "stopped in its tracks")
	assert_true(not ClassAbilities.is_guarding(s, w), "guard spent")


func test_bulwark_gives_cover_and_tower_shield_full() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(4, 2))
	var ally := _add(s, "marksman", Types.Team.PLAYER, Vector2i(3, 2))
	var e := _add(s, "fallen", Types.Team.ENEMY, Vector2i(9, 2))
	assert_eq(Combat.hit_chance(s, e, ally).cover, Types.Cover.HALF, "half cover behind the Warden")
	assert_true(not Combat.hit_chance(s, e, ally).flanked, "not flanked")
	w.status["perks"] = ["tower_shield"]
	assert_eq(Combat.hit_chance(s, e, ally).cover, Types.Cover.FULL, "Tower Shield: full")
	var side := _add(s, "fallen", Types.Team.ENEMY, Vector2i(3, 5))
	assert_eq(Combat.hit_chance(s, side, ally).cover, Types.Cover.NONE, "nothing from the side")


func test_shield_charge_moves_then_bashes() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(1, 2), ["shield_charge"])
	w.aim = 200
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(4, 2))
	t.max_hp = 99
	t.hp = 99
	var ev := _events(s)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": w.id, "ability": "shield_charge", "target": t.id}), "charge")
	assert_eq(w.pos, Vector2i(3, 2), "charged in")
	var bash := _of(ev, "ability", "ability", "bash")
	assert_true(bash.size() == 1 and bash[0].get("charge", false), "charge bash")
	assert_eq(w.actions_left, 0, "ends turn")


func test_unbreakable_and_last_wall() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(3, 2), ["unbreakable", "last_wall"])
	var e := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	var hp := w.hp
	Rules.deal_damage(s, w, 3, e)
	assert_eq(w.hp, hp - 3, "no flat cut now")
	e.max_hp = 30
	e.hp = 30
	Rules.deal_damage(s, w, 1, e)
	Rules.deal_damage(s, w, 1, e)
	assert_true(e.hp < 30 and e.status.get("k_skip_turn", false), "third hit: shockwave hurts and stuns the attacker")
	Rules.deal_damage(s, w, 50, e)
	assert_eq(w.hp, 1, "Last Wall holds at 1")


# ------------------------------------------------------------------ AI and unlocks

func test_turned_reaper_lunges_at_the_squad() -> void:
	var s := _state()
	var r := _add(s, "reaper", Types.Team.ENEMY, Vector2i(1, 2))
	r.status["turned"] = true
	r.ai_controlled = true
	var sol := _add(s, "trooper", Types.Team.PLAYER, Vector2i(5, 2))
	sol.max_hp = 99
	sol.hp = 99
	s.phase = Types.Phase.ENEMY
	var ev := _events(s)
	EnemyAI.take_turn(s, r)
	assert_eq(_of(ev, "ability", "ability", "lunge").size(), 1, "it lunged")


func test_melee_unlocks() -> void:
	var run := RunState.new()
	var reaper := UnitData.make("breacher", Types.Team.PLAYER)
	reaper.status["close_kills"] = 3
	var tank := UnitData.make("trooper", Types.Team.PLAYER)
	tank.status["hits_taken"] = 4
	Progression.on_fight_end(run, {"result": Types.Result.VICTORY, "soldiers": [{"unit": reaper.to_dict()}, {"unit": tank.to_dict()}]})
	assert_true(run.meta.get("reaper_unlocked", false), "3 close kills unlock the Reaper")
	assert_true(not run.meta.get("warden_unlocked", false), "the Warden is retired, its role is gear now")
	var classes := Progression.unlocked_classes(run.meta)
	assert_true(classes.has("reaper") and not classes.has("warden"), "listed")
	assert_true(Progression.CLASS_UNLOCK_HINTS.has("reaper"), "hint")


func test_close_kills_and_hits_taken_are_counted() -> void:
	var s := _state()
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(3, 2))
	var e := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	Rules.deal_damage(s, b, 1, e)
	assert_eq(int(b.status.get("hits_taken", 0)), 1, "hit counted")
	Rules.deal_damage(s, e, 99, b)
	assert_eq(int(b.status.get("close_kills", 0)), 1, "adjacent kill counted")
