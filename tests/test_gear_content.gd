extends TestCase
## Content pack 2 gear (acts 2 and 3): the new items and Prototypes through the GearFx hooks.

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
func _gear(u: Unit, items: Array) -> void:
	GearTags.set_progression(null)
	var rec := {"id": u.id, "kind": u.kind}
	var run := {"supplies": 0, "soldiers": [rec]}
	for it in items:
		var id: String = it if it is String else it[0]
		Loadout.equip(run, rec, id)
		if it is Array and it[1] >= 2:
			Loadout.upgrade(rec, GearData.slot_of(id))
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


func test_damage_items() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	t.max_hp = 40
	t.hp = 40
	_gear(u, [["pilot_light", 2]])
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_eq(Hazards.cells_of(s, "fire").size(), 0, "no Wick on a target that isn't Burning")
	t.status["burning"] = 2
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_eq(Hazards.cells_of(s, "fire").size(), 4, "Wick Mk II lights 4 tiles behind a Burning target")
	_gear(u, ["hollow_points"])
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_true(not GearTricks.is_rooted(s, t), "Pin shot needs a Suppressed target")
	t.status["suppressed"] = Combat.phase_index(s) + 2
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_true(GearTricks.is_rooted(s, t), "Pin shot roots a Suppressed target")
	assert_eq(Rules.move_range(s, t).size(), 1, "a rooted enemy can only stay put")


func test_aim_items() -> void:
	var s := _state()
	var u := _add(s, "marksman", Types.Team.PLAYER, Vector2i(2, 2))
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 2))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(10, 2))
	far.max_hp = 40
	far.hp = 40
	_gear(u, ["spotter_scope", "match_rounds"])
	assert_eq(_term(Combat.hit_chance(s, u, far, u.pos, false), "Dead reckoning"), 0, "not unless Marked")
	far.status["tagged"] = Combat.phase_index(s) + 2
	assert_eq(_term(Combat.hit_chance(s, u, far, u.pos, false), "Dead reckoning"), 100, "a Marked enemy can't be missed")
	GearFx.after_shot(s, u, far, true, false, 3)
	assert_true(Combat.has_status(s, near, "tagged") == false, "the second Mark only reaches enemies within 3 tiles")
	var friend := _add(s, "runner", Types.Team.ENEMY, Vector2i(11, 3))
	GearFx.after_shot(s, u, far, true, false, 3)
	assert_true(Combat.has_status(s, friend, "tagged"), "Dead reckoning Marks the nearest other enemy")
	var first := far.hp
	GearFx.after_shot(s, u, far, true, false, 4)
	GearFx.after_shot(s, u, far, true, false, 4)
	assert_eq(far.hp, first - 3 - 3, "Tight group repeats the first hit's damage on later hits")


func test_defense_items() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	var ally := _add(s, "medic", Types.Team.PLAYER, Vector2i(3, 2))
	var e := _add(s, "spitter", Types.Team.ENEMY, Vector2i(8, 2))
	_gear(u, ["ghillie_cloak"])
	e.status["alerted"] = false
	assert_eq(_term(Combat.hit_chance(s, u, e, u.pos, false), "Still life"), 0, "only on overwatch shots")
	assert_eq(_term(Combat.hit_chance(s, u, e, u.pos, true), "Still life"), 100, "an unaware enemy can't dodge an overwatch shot")
	GearFx.after_shot(s, u, e, true, true, 3)
	assert_true(Combat.has_status(s, e, "tagged"), "and gets Marked")
	e.status["alerted"] = true
	_gear(u, ["overlook"])
	u.overwatch = true
	assert_eq(_term(Combat.hit_chance(s, e, ally, e.pos, false), "Overlook"), -10, "adjacent ally covered by Overlook")
	u.overwatch = false
	assert_eq(_term(Combat.hit_chance(s, e, ally, e.pos, false), "Overlook"), 0, "not off overwatch")
	_gear(u, [["mycelial_weave", 2]])
	Rules.deal_damage(s, u, 2, e)
	assert_eq(Hazards.at(s, e.pos).get("kind", ""), "acid", "Acid blister on the attacker's tile")
	assert_eq(Hazards.at(s, e.pos + Vector2i(1, 0)).get("kind", ""), "acid", "and around it at Mk II")


func test_ember_plating_ignites_attackers() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 2))
	var e := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 2))
	_gear(u, ["ember_plating"])
	Rules.deal_damage(s, u, 2, e)
	assert_true(GearFx.is_burning(s, e), "attacker Burning")


func test_leech_rounds_and_purge_canister() -> void:
	var s := _state()
	var u := _add(s, "vector", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "brute", Types.Team.ENEMY, Vector2i(6, 2))
	t.max_hp = 50
	t.hp = 50
	_gear(u, ["leech_rounds"])
	u.infection = 30
	u.hp = u.max_hp - 2
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_eq(u.hp, u.max_hp - 1, "healed 1")
	assert_true(u.infection > 30, "and took Infection")
	_gear(u, [["purge_canister", 2]])
	var before := u.infection
	t.hp = 0
	GearFx.on_kill(s, u, t, false)
	assert_true(u.infection < before, "kill purges")


func test_prototypes() -> void:
	var s := _state()
	var u := _add(s, "breacher", Types.Team.PLAYER, Vector2i(2, 2))
	var t := _add(s, "brute", Types.Team.ENEMY, Vector2i(4, 2))
	t.max_hp = 50
	t.hp = 50
	_gear(u, ["firestarter"])
	GearFx.after_shot(s, u, t, true, false, 3)
	assert_true(GearFx.is_burning(s, t), "Firestarter ignites up close")
	_gear(u, ["pinpoint"])
	GearFx.on_suppress(s, u, t)
	assert_true(Combat.has_status(s, t, "tagged"), "Pinpoint marks the suppressed")
	_gear(u, ["cauterizer"])
	var hit := GearFx.hazard_hit(s, u, {"kind": "fire", "source": -1}, 2, 0)
	assert_eq(hit.x, 0, "fire doesn't hurt")
	for id in ["firestarter", "pinpoint", "overlook", "cauterizer"]:
		assert_eq(GearData.PROTOTYPES[id].tags.size(), 2, id + " has a tag pair")
