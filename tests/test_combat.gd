extends TestCase

const OPEN_12 := [
	"............",
	"............",
	"............",
	"............",
	"............",
]

## 12x12 with a target spot at (6,6): wall to the west (5,6), low cover to the north (6,5).
const COVER_MAP := [
	"............",
	"............",
	"............",
	"............",
	"............",
	"......=.....",
	".....#......",
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


func _events(s: GameState) -> Array:
	var events: Array = []
	s.event.connect(func(ev): events.append(ev))
	return events


# ------------------------------------------------------------------ line of sight

func test_wall_blocks_los_low_does_not() -> void:
	var s := make_blank(PackedStringArray(["..........", "..........", "....#.....", "..........", ".........."]))
	assert_true(not Combat.can_see(s, Vector2i(1, 2), Vector2i(7, 2)), "wall blocks")
	assert_true(Combat.can_see(s, Vector2i(1, 0), Vector2i(7, 0)), "open row visible")
	var s2 := make_blank(PackedStringArray(["..........", "..........", "....=.....", "..........", ".........."]))
	assert_true(Combat.can_see(s2, Vector2i(1, 2), Vector2i(7, 2)), "low cover does not block")


func test_units_do_not_block_and_range_limit() -> void:
	var s := make_blank(PackedStringArray(["....................", "...................."]))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(5, 0))
	assert_true(Combat.can_see(s, Vector2i(0, 0), Vector2i(10, 0)), "unit does not block")
	assert_true(Combat.can_see(s, Vector2i(0, 0), Vector2i(14, 0)), "14 tiles visible")
	assert_true(not Combat.can_see(s, Vector2i(0, 0), Vector2i(15, 0)), "15 tiles too far")


func test_step_out_around_wall() -> void:
	var s := make_blank(PackedStringArray(["..........", "..........", "....#.....", "..........", ".........."]))
	assert_true(not Combat.line_clear(s.grid, Vector2i(3, 2), Vector2i(7, 2)), "direct line blocked")
	assert_true(Combat.can_see(s, Vector2i(3, 2), Vector2i(7, 2)), "can lean out from beside the wall")


# ------------------------------------------------------------------ cover and odds

func test_cover_direction_and_flanking() -> void:
	var s := make_blank(PackedStringArray(COVER_MAP))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 6))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(6, 1))
	var north := Combat.hit_chance(s, a, t)
	assert_eq(north.cover, Types.Cover.HALF, "north: half cover")
	assert_true(not north.flanked, "north not flanked")
	assert_eq(north.hit, 45, "65 - 20")
	assert_eq(north.crit, 0, "no crit unflanked")
	var east := Combat.hit_chance(s, a, t, Vector2i(11, 6))
	assert_eq(east.cover, Types.Cover.NONE, "east: no cover")
	assert_true(east.flanked, "east flanked")
	assert_eq(east.hit, 65, "flanked chance")
	assert_eq(east.crit, 40, "flank crit")
	var nw := Combat.hit_chance(s, a, t, Vector2i(2, 2))
	assert_eq(nw.cover, Types.Cover.FULL, "diagonal takes best cover")
	assert_eq(nw.hit, 25, "65 - 40")
	var west := Combat.hit_chance(s, a, t, Vector2i(1, 6))
	assert_eq(west.cover, Types.Cover.FULL, "west: full cover")
	assert_eq(west.hit, 0, "no LOS through wall")


func test_hunker_doubles_cover_and_clamps() -> void:
	var s := make_blank(PackedStringArray(COVER_MAP))
	var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 6))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(6, 1))
	assert_true(Rules.apply(s, {"type": Types.HUNKER, "unit": t.id}), "hunker accepted")
	assert_eq(t.actions_left, 0, "hunker ends turn")
	assert_eq(Combat.hit_chance(s, a, t).hit, 25, "half cover doubled")
	assert_eq(Combat.hit_chance(s, a, t, Vector2i(2, 2)).hit, Combat.MIN_CHANCE, "full cover doubled, clamped to min")
	a.aim = 300
	assert_eq(Combat.hit_chance(s, a, t).hit, 100, "clamped to 100")


func test_range_modifiers_and_breakdown_labels() -> void:
	var s := make_blank(PackedStringArray(["................", "................"]))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(0, 0))
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(2, 0))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(13, 0))
	var n := Combat.hit_chance(s, a, near)
	assert_eq(n.hit, 65 + 15, "close range bonus")
	var f := Combat.hit_chance(s, a, far)
	assert_eq(f.hit, 65 - 3 * 3, "long range penalty")
	var labels: Array = f.breakdown.map(func(x): return x[0])
	assert_true(labels.has("Aim") and labels.has("Long range"), "breakdown labels: %s" % str(labels))


func test_resolve_roll_and_graze_damage() -> void:
	var odds := {"hit": 50, "graze": 10, "crit": 40}
	assert_eq(Combat.resolve_roll(50, odds), {"hit": true, "graze": false, "crit": false}, "roll 50")
	assert_eq(Combat.resolve_roll(20, odds), {"hit": true, "graze": false, "crit": true}, "roll 20 crits")
	assert_eq(Combat.resolve_roll(55, odds), {"hit": false, "graze": true, "crit": false}, "roll 55 grazes")
	assert_eq(Combat.resolve_roll(61, odds), {"hit": false, "graze": false, "crit": false}, "roll 61 misses")
	assert_eq(Combat.final_damage(5, true, false), 2, "graze halves")
	assert_eq(Combat.final_damage(1, true, false), 1, "graze min 1")
	assert_eq(Combat.final_damage(4, false, true), 6, "crit +50%")
	assert_eq(Combat.final_damage(3, false, true), 5, "crit rounds up")


## Scans seeds for a real graze from a shot and checks the damage applied matches the event.
func test_graze_shot_applies_reduced_damage() -> void:
	var found := false
	for seed in range(1, 300):
		var s := make_blank(PackedStringArray(OPEN_12), seed)
		var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(0, 2))
		var t := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 2))
		t.max_hp = 50
		t.hp = 50
		a.aim = 50
		var events := _events(s)
		assert_true(Rules.apply(s, {"type": Types.SHOOT, "unit": a.id, "target": t.id}), "shot accepted")
		var shot: Dictionary = events.filter(func(e): return e.type == "shot")[0]
		if shot.graze:
			found = true
			assert_true(shot.damage >= 1 and shot.damage <= a.damage.y / 2, "graze damage halved")
			assert_eq(t.hp, 50 - int(shot.damage), "graze damage applied")
			break
	assert_true(found, "found a graze")


# ------------------------------------------------------------------ shoot / overwatch

func test_shoot_ends_turn_and_rejects_without_los() -> void:
	var s := make_blank(PackedStringArray(["..........", "..........", "....#.....", "..........", ".........."]))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 2))
	var hidden := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 2))
	assert_true(not Rules.apply(s, {"type": Types.SHOOT, "unit": a.id, "target": hidden.id}), "no LOS rejected")
	var seen := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 0))
	assert_true(Rules.apply(s, {"type": Types.SHOOT, "unit": a.id, "target": seen.id}), "visible accepted")
	assert_eq(a.actions_left, 0, "shot ends turn")


func test_overwatch_interrupts_move() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var w := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 2))
	w.aim = 300
	var r := _add(s, "runner", Types.Team.ENEMY, Vector2i(10, 2))
	r.max_hp = 50
	r.hp = 50
	assert_true(Rules.apply(s, {"type": Types.OVERWATCH, "unit": w.id}), "overwatch accepted")
	assert_eq(Combat.reactions_to_move(s, r, Vector2i(9, 2)), [w] as Array[Unit], "reactor found")
	assert_true(w.overwatch, "reactions_to_move is pure")
	var events := _events(s)
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": r.id, "to": Vector2i(6, 2)}), "move accepted")
	var types: Array = events.map(func(e): return e.type)
	assert_true(types.size() >= 3, "events: %s" % str(types))
	assert_eq(types[0], "move", "move first")
	assert_eq(types[1], "shot", "then the reaction shot")
	var shot: Dictionary = events[1]
	assert_true(shot.reaction, "reaction flag")
	assert_true(shot.hit, "forced hit")
	assert_true(not w.overwatch, "overwatch spent")
	assert_eq(r.pos, Vector2i(6, 2), "mover finished its move")
	assert_eq(types.count("shot"), 1, "only one reaction")


func test_enemy_overwatch_persists_until_its_next_phase() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var e := _add(s, "spitter", Types.Team.ENEMY, Vector2i(10, 2))
	var sol := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 2))
	s.turn = 1
	s.phase = Types.Phase.ENEMY
	assert_true(Rules.apply(s, {"type": Types.OVERWATCH, "unit": e.id}), "enemy overwatch")
	s.turn = 2
	s.phase = Types.Phase.TEAM
	assert_eq(Combat.reactions_to_move(s, sol, Vector2i(2, 2)).size(), 1, "active in the team phase")
	s.phase = Types.Phase.ENEMY
	assert_true(not Combat.is_overwatching(s, e), "expired at its next phase")
	assert_true(Combat.reactions_to_move(s, sol, Vector2i(2, 2)).is_empty(), "no reaction after expiry")


# ------------------------------------------------------------------ abilities

func test_available_abilities_fields() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 2))
	_add(s, "runner", Types.Team.ENEMY, Vector2i(6, 2))
	var list := Combat.available_abilities(s, a)
	assert_eq(list.size(), 1, "one ability")
	var ab: Dictionary = list[0]
	for k in ["id", "name", "targeting", "ready", "cooldown", "desc"]:
		assert_true(ab.has(k), "has " + k)
	assert_eq(ab.id, "suppress", "id")
	assert_true(ab.ready, "ready")


func test_suppress() -> void:
	var s := make_blank(PackedStringArray(["..........", "..........", "....#.....", "..........", ".........."]))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 2))
	var r := _add(s, "spitter", Types.Team.ENEMY, Vector2i(7, 0))
	var hidden := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 2))
	a.actions_left = 2
	assert_true(not Rules.apply(s, {"type": Types.ABILITY, "unit": a.id, "ability": "suppress", "target": hidden.id}), "no LOS rejected")
	r.overwatch = true
	var before: int = Combat.hit_chance(s, r, a).hit
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": a.id, "ability": "suppress", "target": r.id}), "suppress")
	assert_true(Combat.has_status(s, r, "suppressed"), "suppressed")
	assert_true(not r.overwatch, "overwatch cancelled")
	assert_eq(a.actions_left, 0, "ends turn")
	assert_eq(a.cooldowns.get("suppress"), 2, "cooldown")
	assert_eq(Combat.hit_chance(s, r, a).hit, before - 30, "-30 aim")
	r.actions_left = 2
	assert_true(Rules.apply(s, {"type": Types.SHOOT, "unit": r.id, "target": a.id}), "suppressed shot")
	assert_true(not Combat.has_status(s, r, "suppressed"), "consumed by the shot")


func test_tag() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var m := _add(s, "marksman", Types.Team.PLAYER, Vector2i(1, 2))
	var ally := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 4))
	var r := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 2))
	var before: int = Combat.hit_chance(s, ally, r).hit
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": m.id, "ability": "tag", "target": r.id}), "tag")
	assert_eq(m.actions_left, 1, "costs one action")
	assert_eq(Combat.hit_chance(s, ally, r).hit, before + 15, "+15 for allies")
	assert_eq(Rules.validate(s, {"type": Types.SHOOT, "unit": m.id, "target": r.id}), "", "can still shoot")
	assert_true(not Rules.apply(s, {"type": Types.ABILITY, "unit": m.id, "ability": "tag", "target": r.id}), "cooldown rejects")
	s.phase = Types.Phase.ENEMY
	assert_true(Combat.has_status(s, r, "tagged"), "lasts through the enemy phase")
	s.turn += 1
	s.phase = Types.Phase.TEAM
	assert_true(not Combat.has_status(s, r, "tagged"), "expired next team phase")


func test_stim() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var med := _add(s, "medic", Types.Team.PLAYER, Vector2i(1, 2))
	var ally := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 3))
	var far := _add(s, "trooper", Types.Team.PLAYER, Vector2i(4, 2))
	ally.hp = 2
	ally.infection = 40
	assert_true(not Rules.apply(s, {"type": Types.ABILITY, "unit": med.id, "ability": "stim", "target": far.id}), "too far rejected")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": med.id, "ability": "stim", "target": ally.id}), "stim")
	assert_eq(ally.hp, 5, "healed 3")
	assert_eq(ally.infection, 25, "infection -15")
	assert_eq(med.actions_left, 1, "one action")
	assert_eq(med.cooldowns.get("stim"), 2, "cooldown")


func test_breach() -> void:
	var s := make_blank(PackedStringArray(COVER_MAP))
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(6, 4))
	var r := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 6))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 9))
	r.max_hp = 20
	r.hp = 20
	assert_true(not Rules.apply(s, {"type": Types.ABILITY, "unit": b.id, "ability": "breach", "target": far.id}), "3 tiles rejected")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": b.id, "ability": "breach", "target": r.id}), "breach")
	assert_true(r.hp >= 14 and r.hp <= 16, "4-6 damage through cover, hp %d" % r.hp)
	assert_eq(b.actions_left, 0, "ends turn")
	assert_eq(b.cooldowns.get("breach"), 3, "cooldown 3")


func test_claw() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var r := _add(s, "runner", Types.Team.ENEMY, Vector2i(5, 2))
	var near := _add(s, "trooper", Types.Team.PLAYER, Vector2i(6, 3))
	var far := _add(s, "trooper", Types.Team.PLAYER, Vector2i(8, 2))
	r.aim = 300
	near.max_hp = 20
	near.hp = 20
	assert_true(not Rules.apply(s, {"type": Types.ABILITY, "unit": r.id, "ability": "claw", "target": far.id}), "not adjacent rejected")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": r.id, "ability": "claw", "target": near.id}), "claw")
	assert_true(near.hp >= 16 and near.hp <= 18, "2-4 damage, hp %d" % near.hp)
	assert_eq(r.actions_left, 0, "ends turn")


func test_claw_only_half_cover() -> void:
	var s := make_blank(PackedStringArray(COVER_MAP))
	var r := _add(s, "runner", Types.Team.ENEMY, Vector2i(5, 5))
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(6, 6))
	assert_eq(Combat.melee_chance(s, r, t).hit, 50, "full cover counts as 20")


func test_spit() -> void:
	var s := make_blank(PackedStringArray(OPEN_12))
	var sp := _add(s, "spitter", Types.Team.ENEMY, Vector2i(1, 2))
	var a := _add(s, "trooper", Types.Team.PLAYER, Vector2i(6, 2))
	var b := _add(s, "medic", Types.Team.PLAYER, Vector2i(7, 3))
	var c := _add(s, "marksman", Types.Team.PLAYER, Vector2i(8, 2))
	assert_true(not Rules.apply(s, {"type": Types.ABILITY, "unit": sp.id, "ability": "spit", "cell": Vector2i(11, 2)}), "too far rejected")
	var events := _events(s)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": sp.id, "ability": "spit", "cell": Vector2i(6, 3)}), "spit")
	assert_eq(a.hp, a.max_hp - 2, "a hit")
	assert_eq(b.hp, b.max_hp - 2, "b hit")
	assert_eq(c.hp, c.max_hp, "c outside radius")
	var ev: Dictionary = events.filter(func(e): return e.type == "ability")[0]
	assert_eq(ev.units, [a.id, b.id], "affected ids")
	assert_eq(sp.actions_left, 0, "ends turn")
	assert_eq(sp.cooldowns.get("spit"), Combat.ABILITIES.spit.cooldown, "cooldown")
