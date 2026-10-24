extends TestCase
## Gear effects in a mission (GearFx through the Combat / Rules / Infection hooks).

const OPEN := [
	"............",
	"............",
	"............",
	"............",
	"............",
	"............",
]


func _add(s: GameState, kind: String, team: int, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
	return u


## Gives `u` gear: items is an Array of ids (Mk I) or [id, mk] pairs.
func _gear(u: Unit, items: Array, pockets: Array = []) -> void:
	GearTags.set_progression(null)
	var rec := {"id": u.id, "kind": u.kind}
	var run := {"supplies": 0, "soldiers": [rec]}
	for it in items:
		var id: String = it if it is String else it[0]
		Loadout.equip(run, rec, id)
		if it is Array and it[1] >= 2:
			Loadout.upgrade(rec, GearData.slot_of(id))
	for p in pockets:
		Loadout.add_consumable(rec, p, 2)
	GearRun.apply_to_unit(u, rec)


func _state() -> GameState:
	var s := make_blank(PackedStringArray(OPEN))
	s.turn = 1
	return s


func _term(odds: Dictionary, label: String) -> int:
	for t in odds.breakdown:
		if t[0] == label:
			return t[1]
	return 0


func test_slug_rounds_add_close_damage() -> void:
	var s := _state()
	var u := _add(s, "breacher", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(10, 2))
	_gear(u, [["slug_rounds", 2]])
	assert_eq(GearFx.shot_damage(s, u, t, 4, false), 6, "Mk II +2 within 3")
	assert_eq(GearFx.shot_damage(s, u, far, 4, false), 4, "no bonus at range")


func test_tracer_rounds_mark_and_shock_rounds_suppress() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(6, 2))
	t.max_hp = 50
	t.hp = 50
	_gear(u, ["tracer_rounds"])
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_true(Combat.has_status(s, t, "tagged"), "Marked")
	_gear(u, ["shock_rounds"])
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_true(Combat.has_status(s, t, "suppressed"), "Suppressed")


func test_mark_set_bonus_and_jump() -> void:
	var s := _state()
	var u := _add(s, "marksman", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 2))
	var next := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 3))
	_gear(u, ["laser_sight", "tracer_rounds", "flare_launcher"])
	assert_true(GearFx.has_set(u, "Mark"), "Mark set on")
	t.status["tagged"] = Combat.phase_index(s) + 2
	assert_eq(GearFx.shot_damage(s, u, t, 4, false), 5, "+1 vs Marked")
	t.hp = 0
	GearFx.on_kill(s, u, t, false)
	assert_true(Combat.has_status(s, next, "tagged"), "Mark jumped")


func test_overwatch_terms() -> void:
	var s := _state()
	var u := _add(s, "marksman", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(8, 2))
	_gear(u, ["bipod", "expanding_rounds", "rangefinder"])  # rangefinder replaces bipod
	assert_eq(GearFx.mk(u, "bipod"), 0, "bipod replaced")
	_gear(u, ["bipod", "expanding_rounds"])
	var odds := Combat.hit_chance(s, u, t, u.pos, true)
	assert_eq(_term(odds, "Bipod"), 10, "bipod on reaction")
	assert_eq(_term(Combat.hit_chance(s, u, t, u.pos, false), "Bipod"), 0, "not on a normal shot")
	u.status["gear_moved_turn"] = s.turn
	assert_eq(_term(Combat.hit_chance(s, u, t, u.pos, true), "Bipod"), 0, "not after moving")
	assert_eq(GearFx.shot_damage(s, u, t, 3, true), 5, "expanding +2 on reaction")


func test_armor_reduces_damage_to_one_minimum() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	var e := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 2))
	_gear(u, [["plated_rig", 2]])
	var hp := u.hp
	Rules.deal_damage(s, u, 3, e)
	assert_eq(u.hp, hp - 1, "3 - 2 armor")
	Rules.deal_damage(s, u, 1, e)
	assert_eq(u.hp, hp - 2, "never below 1")


func test_hazard_liner_halves_bite_infection() -> void:
	var s := _state()
	var u := _add(s, "medic", Types.Team.PLAYER, Vector2i(2, 2))
	var e := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 2))
	_gear(u, ["hazard_liner"])
	Infection.on_damaged(s, u, e, 2)
	assert_eq(u.infection, Infection.damage_gain(2) / 2, "half")


func test_close_set_adds_mobility_and_refunds_on_kill() -> void:
	var s := _state()
	var u := _add(s, "breacher", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(10, 5))
	_gear(u, ["light_harness", "slug_rounds", "choke"])
	var mob := u.mobility
	GearFx.on_team_phase_start(s)
	assert_eq(u.mobility, mob + 1, "Close set +1 move")
	GearFx.on_team_phase_start(s)
	assert_eq(u.mobility, mob + 1, "not stacked")
	u.actions_left = 0
	t.hp = 0
	GearFx.on_kill(s, u, t, false)
	assert_eq(u.actions_left, 1, "refund")
	GearFx.on_kill(s, u, t, false)
	assert_eq(u.actions_left, 1, "once per turn")


func test_incendiary_burns_each_team_phase() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(6, 2))
	_gear(u, ["incendiary_rounds"])
	GearFx.after_shot(s, u, t, true, false, 2)
	var hp := t.hp
	s.turn = 2
	GearFx.on_team_phase_start(s)
	assert_eq(t.hp, hp - GearFx.BURN_DAMAGE, "burn tick")
	s.turn = 3
	GearFx.on_team_phase_start(s)
	assert_eq(t.hp, hp - GearFx.BURN_DAMAGE, "burned out")


func test_gadget_and_pocket_abilities_through_rules() -> void:
	var s := _state()
	var u := _add(s, "medic", Types.Team.PLAYER, Vector2i(2, 2))
	var ally := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 2))
	var e := _add(s, "runner", Types.Team.ENEMY, Vector2i(8, 2))
	_gear(u, ["med_injector"], ["medkit", "frag_grenade"])
	ally.infection = 30
	ally.hp = 2
	var ids := Combat.available_abilities(s, u).map(func(a): return a.id)
	assert_true(ids.has("gear:med_injector") and ids.has("item:medkit") and ids.has("item:frag_grenade"), "listed: %s" % str(ids))
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "gear:med_injector", "target": ally.id}), "injector")
	assert_eq(ally.infection, 15, "-15 Infection")
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": u.id, "ability": "gear:med_injector", "target": ally.id}), "Used up this fight", "once per fight")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "item:medkit", "target": ally.id}), "medkit")
	assert_eq(ally.hp, 6, "+4 HP")
	assert_eq(GearFx.charges(u, "medkit"), 1, "charge used")
	u.actions_left = 1
	var ehp := e.hp
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "item:frag_grenade", "cell": e.pos}), "frag")
	assert_eq(e.hp, maxi(0, ehp - 3), "frag damage")


func test_full_shot_runs_through_hooks() -> void:
	var s := _state()
	var u := _add(s, "marksman", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "spitter", Types.Team.ENEMY, Vector2i(5, 2))
	t.max_hp = 100
	t.hp = 100
	_gear(u, [["laser_sight", 2], "tracer_rounds"])
	u.aim = 200
	assert_true(Rules.apply(s, {"type": Types.SHOOT, "unit": u.id, "target": t.id}), "shot")
	assert_true(t.hp < 100, "hit")
	assert_true(Combat.has_status(s, t, "tagged"), "tracer marked through the real shot")


func test_pending_items_never_drawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 300:
		var id := GearDraw.draw_item(rng, {}, ["common", "uncommon", "rare"][i % 3])
		assert_true(not GearFx.is_pending(id), "%s is pending" % id)


func test_sentry_turret_deploys_a_turret() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(9, 2))
	_gear(u, [["sentry_turret", 2]])
	var a := {"type": Types.ABILITY, "unit": u.id, "ability": "gear:sentry_turret", "cell": Vector2i(8, 2)}
	assert_eq(Rules.validate(s, a), "Too far", "range 3")
	a.cell = u.pos
	assert_eq(Rules.validate(s, a), "Cell is occupied", "needs an empty tile")
	a.cell = Vector2i(4, 2)
	assert_true(Rules.apply(s, a), "deployed")
	var t := s.unit_at(Vector2i(4, 2))
	assert_true(t != null and Deployables.is_deployable(t), "turret on the field")
	assert_eq(t.aim, 70, "Mk II aim")
	assert_eq(t.damage, Vector2i(3, 3), "Mk II damage")
	assert_eq(int(t.status.expires_turn), s.turn + 4, "Mk II lasts 4 turns")
	u.actions_left = 2
	a.cell = Vector2i(3, 3)
	assert_eq(Rules.validate(s, a), "Used up this fight", "once per fight")
