extends TestCase
## High ground: stairs/ladder/drop pathing, three levels, the aim and cover rules, set_level and snapshots.

# Row 1 has a 3-wide roof (x 3..5) with a ladder at (2, 1); a low wall shields (4, 3).
const ROWS := ["..........", "../^^^....", "...^^^....", "....=.....", ".........."]


func _setup() -> Dictionary:
	var s := make_blank(PackedStringArray(ROWS))
	var sol := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(0, 0))
	sol.owner_player = 0
	var foe := s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(4, 4))
	return {"s": s, "sol": sol, "foe": foe}


func test_levels_parse_and_survive_snapshot() -> void:
	var s: GameState = _setup().s
	assert_eq(s.grid.level(Vector2i(4, 1)), 1, "roof")
	assert_eq(s.grid.level(Vector2i(2, 1)), 0, "ladder sits on the ground")
	assert_true(s.grid.is_ladder(Vector2i(2, 1)), "ladder")
	var g := Grid.from_dict(s.grid.to_dict())
	assert_eq(g.level(Vector2i(5, 2)), 1, "levels round-trip")
	assert_true(g.is_ladder(Vector2i(2, 1)), "ladders round-trip")
	assert_true(g.has_levels(), "has high ground")


func test_levels_change_only_by_ladder() -> void:
	var g: Grid = _setup().s.grid
	assert_true(g._can_step(Vector2i(2, 1), Vector2i(1, 0), {}), "ladder climbs onto the roof")
	assert_true(not g._can_step(Vector2i(2, 2), Vector2i(1, 0), {}), "no climbing a bare wall")
	assert_true(not g._can_step(Vector2i(2, 0), Vector2i(1, 1), {}), "no diagonal climb")
	var path := g.find_path(Vector2i(2, 3), Vector2i(4, 2))
	assert_true(path.has(Vector2i(2, 1)), "the way up goes through the ladder")
	assert_eq(g.find_path(Vector2i(2, 3), Vector2i(4, 2), {}, true).size(), 2, "leapers ignore levels")


func test_shooting_down_gains_aim_and_strips_cover() -> void:
	var d := _setup()
	var s: GameState = d.s
	var foe: Unit = d.foe
	var sol: Unit = d.sol
	# The foe at (4, 4) has half cover from (4, 3) against shots from the north.
	var flat := Combat.hit_chance(s, sol, foe, Vector2i(4, 0))
	var high := Combat.hit_chance(s, sol, foe, Vector2i(4, 2))
	assert_eq(flat.cover, Types.Cover.HALF, "half cover from the ground")
	assert_eq(high.cover, Types.Cover.NONE, "high ground strips half cover")
	assert_true(not high.flanked, "but it is not a flank")
	assert_true(high.breakdown.has(["High ground", Elevation.AIM_BONUS]), "aim bonus listed")


func test_shooting_up_meets_at_least_half_cover() -> void:
	var d := _setup()
	var s: GameState = d.s
	d.foe.pos = Vector2i(5, 1)
	var odds := Combat.hit_chance(s, d.foe, d.sol, Vector2i(5, 1))
	assert_eq(odds.cover, Types.Cover.NONE, "the roof gives a shot from above no cover to hide in")
	var up := Combat.hit_chance(s, d.sol, d.foe, Vector2i(8, 1))
	assert_eq(up.cover, Types.Cover.HALF, "a target on the roof has half cover from below")


func test_flying_counts_as_high() -> void:
	var d := _setup()
	d.foe.status["flying"] = true
	assert_eq(Elevation.height(d.s, d.foe), 1, "flyers are high")
	assert_eq(Elevation.advantage(d.s, d.foe, d.sol), 1, "and shoot down")


func test_set_level_collapses_a_roof() -> void:
	var s: GameState = _setup().s
	assert_true(Elevation.is_ledge(s.grid, Vector2i(3, 1)), "roof edge is a ledge")
	Elevation.set_level(s, Vector2i(3, 1), 0)
	assert_eq(s.grid.level(Vector2i(3, 1)), 0, "collapsed")
	assert_true(not s.grid.is_ladder(Vector2i(2, 1)), "the ladder to nowhere is gone")
	var ev := s.log.filter(func(e): return e.type == "level_changed")
	assert_eq(ev.size(), 1, "one event")
	assert_eq(ev[0].cell, Vector2i(3, 1), "for that cell")


# Three levels: a roof (x 2..6, y 1..3) with an upper roof (x 4..5, y 1..2) reached by stairs S
# at (3, 2); stairs s at (1, 2) and a ladder / at (7, 2) lead up from the ground; a fragile
# scaffold ~ at (2..3, 5) with a ladder at (1, 5).
const TALL := [
	"..........",
	"..^^22^...",
	".s^S22^/..",
	"..^^^^^...",
	"..........",
	"./~~......",
	"..........",
]


func test_stairs_are_a_step_ladders_cost_more() -> void:
	var g := Grid.from_rows(PackedStringArray(TALL))
	assert_eq(g.step_cost(Vector2i(1, 2), Vector2i(1, 0)), 1, "stairs: a normal step up")
	assert_eq(g.step_cost(Vector2i(7, 2), Vector2i(-1, 0)), Grid.LADDER_COST, "ladder climb costs more")
	assert_eq(g.step_cost(Vector2i(3, 2), Vector2i(1, 0)), 1, "roof stairs lead to the upper roof")
	assert_eq(g.step_cost(Vector2i(2, 4), Vector2i(0, -1)), -1, "no climbing a bare wall")
	assert_eq(g.level(Vector2i(4, 1)), 2, "upper roof")
	var d := g.reachable(Vector2i(0, 2), 99)
	assert_eq(d[Vector2i(4, 2)], 4, "ground -> stairs -> roof -> roof stairs -> upper roof, a step each")


func test_drop_down_anywhere_one_way() -> void:
	var g := Grid.from_rows(PackedStringArray(TALL))
	assert_eq(g.step_cost(Vector2i(2, 3), Vector2i(0, 1)), 1, "drop off a roof edge")
	assert_eq(g.step_cost(Vector2i(2, 4), Vector2i(0, -1)), -1, "but not back up")
	assert_eq(g.step_cost(Vector2i(4, 1), Vector2i(0, -1)), 2, "dropping two levels costs 2")
	assert_eq(g.step_cost(Vector2i(2, 3), Vector2i(-1, 1)), -1, "no diagonal drops")
	var path := g.find_path(Vector2i(5, 1), Vector2i(5, 5))
	assert_true(path.size() > 0, "the upper roof can always get back down")


func test_height_sees_over_lower_roofs() -> void:
	var s := make_blank(PackedStringArray(TALL))
	assert_true(not Combat.line_clear(s.grid, Vector2i(2, 0), Vector2i(2, 4), 0), "ground to ground: the roof blocks")
	assert_true(Combat.can_see(s, Vector2i(2, 3), Vector2i(6, 3)), "roof to roof across the same height")
	assert_true(not Combat.line_clear(s.grid, Vector2i(3, 1), Vector2i(6, 1), 1), "the upper roof blocks a roof-level line")
	assert_true(Combat.line_clear(s.grid, Vector2i(4, 1), Vector2i(4, 5), 2), "from the upper roof you see over the roof")


func test_buildings_give_full_cover_from_below_only() -> void:
	var s := make_blank(PackedStringArray(TALL))
	# A target at (3, 4) hugs the roof's south face.
	assert_eq(Combat.cover_against(s.grid, Vector2i(3, 4), Vector2i(3, 0)), Types.Cover.FULL, "wall face from the ground")
	assert_eq(Combat.cover_against(s.grid, Vector2i(3, 4), Vector2i(3, 2)), Types.Cover.NONE, "nothing from the roof itself")


func test_explosions_bring_down_scaffolds() -> void:
	var s := make_blank(PackedStringArray(TALL))
	var u := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(2, 5))
	var hp := u.hp
	assert_true(s.grid.is_fragile(Vector2i(3, 5)), "scaffold")
	var down := Elevation.blast(s, Vector2i(3, 5), 1)
	assert_eq(down.size(), 2, "both scaffold cells collapse")
	assert_eq(s.grid.level(Vector2i(2, 5)), 0, "back to ground")
	assert_true(not s.grid.is_ladder(Vector2i(1, 5)), "its ladder is gone")
	assert_eq(u.hp, hp - Elevation.FALL_DAMAGE_PER_LEVEL, "the soldier on it fell")
	assert_eq(Elevation.blast(s, Vector2i(3, 2), 2).size(), 0, "solid roofs don't collapse")


func test_new_layers_survive_snapshot() -> void:
	var g := Grid.from_dict(Grid.from_rows(PackedStringArray(TALL)).to_dict())
	assert_true(g.is_stairs(Vector2i(1, 2)) and g.is_stairs(Vector2i(3, 2)), "stairs round-trip")
	assert_true(g.is_fragile(Vector2i(2, 5)), "scaffolds round-trip")
	assert_eq(g.level(Vector2i(5, 2)), 2, "upper roof round-trips")


func test_sight_grows_with_each_level() -> void:
	var s := make_blank(PackedStringArray(TALL))
	var u := s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(0, 0))
	var base := Vision.sight(s, u)
	u.pos = Vector2i(2, 1)
	assert_eq(Vision.sight(s, u), base + Vision.HIGH_GROUND_BONUS, "roof")
	u.pos = Vector2i(4, 1)
	assert_eq(Vision.sight(s, u), base + 2 * Vision.HIGH_GROUND_BONUS, "upper roof")


# ---------------------------------------------------------------- melee across levels

func _tall_state() -> GameState:
	var s := make_blank(PackedStringArray(TALL))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	Vision.disable(s)
	return s


func _add(s: GameState, kind: String, team: int, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at) if team == Types.Team.PLAYER else s.add_unit(EnemyRoster.make(kind), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
	else:
		u.status["alerted"] = true
	return u


func test_melee_reach_needs_the_same_level_or_a_stair_step() -> void:
	var g: Grid = make_blank(PackedStringArray(TALL)).grid
	assert_true(g.touching(Vector2i(3, 4), Vector2i(3, 3)), "ground and roof edge are next to each other")
	assert_true(not g.melee_reach(Vector2i(3, 4), Vector2i(3, 3)), "but no claws up a bare wall")
	assert_true(not g.melee_reach(Vector2i(3, 3), Vector2i(3, 4)), "nor down off a ledge")
	assert_true(not g.melee_reach(Vector2i(1, 4), Vector2i(2, 3)), "nor diagonally up onto a roof")
	assert_true(not g.melee_reach(Vector2i(7, 2), Vector2i(6, 2)), "a ladder is a climb, not a step")
	assert_true(g.melee_reach(Vector2i(1, 2), Vector2i(2, 2)), "stairs up to the roof are a step")
	assert_true(g.melee_reach(Vector2i(2, 2), Vector2i(1, 2)), "and back down")
	assert_true(g.melee_reach(Vector2i(3, 2), Vector2i(4, 2)), "roof stairs reach the upper roof")
	assert_true(not g.melee_reach(Vector2i(3, 1), Vector2i(4, 1)), "but not beside the stairs")
	assert_true(g.melee_reach(Vector2i(2, 1), Vector2i(3, 2)), "diagonal along a roof")
	assert_true(not g.melee_reach(Vector2i(3, 3), Vector2i(4, 2)), "no diagonal from the roof onto the upper roof")
	assert_true(g.melee_reach(Vector2i(0, 4), Vector2i(1, 4)), "flat ground as before")


func test_claws_and_slams_cant_reach_a_roof_from_below() -> void:
	var s := _tall_state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 3))
	var runner := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 4))
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": runner.id, "ability": "claw", "target": t.id}), "Not adjacent",
		"claw refused from the ground")
	var brute := _add(s, "brute", Types.Team.ENEMY, Vector2i(4, 4))
	t.pos = Vector2i(4, 3)
	assert_true(EnemyAbilities.validate(s, brute, {"type": Types.ABILITY, "unit": brute.id, "ability": "slam", "target": t.id}) != "",
		"slam refused from the ground")
	runner.pos = Vector2i(1, 2)
	t.pos = Vector2i(2, 2)
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": runner.id, "ability": "claw", "target": t.id}), "",
		"claw allowed from the stairs")


func test_runner_climbs_instead_of_clawing_from_below() -> void:
	var s := _tall_state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 3))
	var runner := _add(s, "runner", Types.Team.ENEMY, Vector2i(2, 4))
	s.phase = Types.Phase.ENEMY
	EnemyAI.take_turn(s, runner)
	var claws := s.log.filter(func(e): return e.type == "ability" and e.get("ability") == "claw" and e.get("unit") == runner.id)
	assert_true(claws.is_empty() or s.grid.melee_reach(runner.pos, t.pos), "only claws from the roof or the stairs: %s" % [runner.pos])
	assert_true(runner.pos != Vector2i(2, 4), "doesn't stand below swiping at the roof")


func test_brute_charge_stops_at_a_ledge() -> void:
	var s := _tall_state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(5, 3))
	var brute := _add(s, "brute", Types.Team.ENEMY, Vector2i(5, 6))
	var lane := EnemyAbilities.charge_lane(s, brute, brute.pos, Vector2i(0, -1))
	assert_true(lane.hit == null, "no hit on the roof")
	assert_true(not lane.cells.has(t.pos), "charge doesn't run up the wall: %s" % [lane.cells])


func test_reaper_and_warden_stay_on_their_level() -> void:
	var s := _tall_state()
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 3))
	foe.max_hp = 99
	foe.hp = 99
	var reaper := _add(s, "reaper", Types.Team.PLAYER, Vector2i(4, 5))
	assert_eq(ClassAbilities.lunge_landing(s, reaper, foe, ClassAbilities.LUNGE_REACH), ClassAbilities.NO_CELL,
		"the cell under the roof isn't a landing; the roof is out of reach")
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": reaper.id, "ability": "lunge", "target": foe.id}), "Can't reach",
		"lunge refused")
	reaper.pos = Vector2i(1, 3)
	var landing := ClassAbilities.lunge_landing(s, reaper, foe, ClassAbilities.LUNGE_REACH)
	assert_true(landing != ClassAbilities.NO_CELL and s.grid.level(landing) == 1, "up the stairs onto the roof: %s" % [landing])
	var warden := _add(s, "warden", Types.Team.PLAYER, Vector2i(4, 4))
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": warden.id, "ability": "bash", "target": foe.id}), "Not adjacent",
		"bash refused from the ground")


func test_leaper_impact_still_reaches_a_raised_soldier() -> void:
	var s := _tall_state()
	var t := _add(s, "trooper", Types.Team.PLAYER, Vector2i(3, 3))
	var le := _add(s, "leaper", Types.Team.ENEMY, Vector2i(3, 4))
	le.status["leap_cell"] = Vector2i(3, 4)
	le.pos = Vector2i(9, 6)
	var hp := t.hp
	EnemyAbilities.apply(s, le, {"type": Types.ABILITY, "unit": le.id, "ability": "leap"})
	assert_true(t.hp < hp, "the landing hits the roof edge above it")
