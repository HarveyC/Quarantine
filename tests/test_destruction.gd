extends TestCase
## Destruction: walls and cover breaking in steps, roofs collapsing into ramps, fuel barrels and
## their chains, the demo charge, Breach, noise, snapshots and map generation.

# A wall line at x = 5 (rows 0..4), half cover at (3, 3), barrels at (8, 1) and (9, 1) and a lone
# one at (8, 4); a roof block at x 1..3, y 5..6; an edge wall at (0, 7); a reinforced wall at (11, 3).
const ROWS := [
	"............",
	".....#..!!..",
	".....#......",
	"...=.#.....H",
	".....#..!...",
	".^^^........",
	".^^^........",
	"#...........",
]


func _state() -> GameState:
	var s := make_blank(PackedStringArray(ROWS))
	s.turn = 1
	Vision.disable(s)
	return s


func _add(s: GameState, kind: String, team: int, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
	return u


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(ev): return ev.type == type)


func test_wall_breaks_in_steps() -> void:
	var s := _state()
	var w := Vector2i(5, 2)
	assert_true(not Combat.line_clear(s.grid, Vector2i(3, 2), Vector2i(7, 2)), "wall blocks sight")
	Destruction.hit(s, {w: 1})
	assert_eq(s.grid.tile(w), Types.Tile.WALL, "one hit cracks it")
	assert_eq(int(s.grid.wear.get(w, 0)), 1, "crack recorded")
	Destruction.hit(s, {w: 1})
	assert_eq(s.grid.tile(w), Types.Tile.LOW, "two hits: rubble heap")
	assert_eq(s.grid.rubble.get(w), "heap", "heap remembered for the view")
	assert_true(Combat.line_clear(s.grid, Vector2i(3, 2), Vector2i(7, 2)), "heap is see-through")
	assert_eq(s.grid.cover_value(w), Types.Cover.HALF, "and half cover")
	Destruction.hit(s, {w: 1})
	assert_eq(s.grid.tile(w), Types.Tile.FLOOR, "three hits: floor")
	var ev: Dictionary = _events(s, "cover_destroyed")[-1]
	assert_eq(ev.changes[0].kind, "clear", "change kind for the view")


func test_extra_hits_carry_through() -> void:
	var s := _state()
	Destruction.hit(s, {Vector2i(5, 2): 3})
	assert_eq(s.grid.tile(Vector2i(5, 2)), Types.Tile.FLOOR, "3 hits go straight through a wall")
	assert_true(s.grid.is_walkable(Vector2i(5, 2)), "a doorway")


func test_half_cover_goes_in_one_hit_and_floor_is_untouched() -> void:
	var s := _state()
	var changed := Destruction.hit(s, {Vector2i(3, 3): 1, Vector2i(2, 2): 1})
	assert_eq(s.grid.tile(Vector2i(3, 3)), Types.Tile.FLOOR, "cover cleared")
	assert_eq(changed, [Vector2i(3, 3)] as Array[Vector2i], "plain floor doesn't change")


func test_edge_and_reinforced_walls_never_break() -> void:
	var s := _state()
	Destruction.hit(s, {Vector2i(0, 7): 5, Vector2i(11, 3): 5})
	assert_eq(s.grid.tile(Vector2i(0, 7)), Types.Tile.WALL, "map edge stays")
	assert_eq(s.grid.tile(Vector2i(11, 3)), Types.Tile.WALL, "H stays")
	assert_true(s.grid.is_hard(Vector2i(11, 3)), "H parsed")


func test_demo_charge_blows_a_doorway() -> void:
	var s := _state()
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(4, 2))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 2))
	b.status["pockets"] = [{"id": "demo_charge", "charges": 1}, null]
	var act := {"type": Types.ABILITY, "unit": b.id, "ability": "item:demo_charge", "cell": Vector2i(5, 2)}
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": b.id, "ability": "item:demo_charge", "cell": Vector2i(7, 2)}),
		"Too far", "range 1")
	var hp := foe.hp
	var bhp := b.hp
	assert_true(Rules.apply(s, act), "demo charge")
	assert_true(s.grid.is_walkable(Vector2i(5, 2)), "doorway through the wall")
	assert_eq(s.grid.tile(Vector2i(5, 1)), Types.Tile.WALL, "walls beside it only crack")
	assert_eq(int(s.grid.wear.get(Vector2i(5, 1), 0)), 1, "cracked")
	assert_eq(foe.hp, maxi(0, hp - 3), "3 damage beyond the wall")
	assert_eq(b.hp, bhp, "the Breacher is not hurt by their own charge")
	assert_eq(_events(s, "explosion")[0].kind, "demo", "explosion event")
	assert_true(Combat.can_see(s, Vector2i(3, 2), Vector2i(8, 2)), "sight through the new doorway")
	var path := s.grid.find_path(Vector2i(4, 2), Vector2i(7, 2))
	assert_eq(path.size(), 3, "and a straight path")


func test_shoot_barrel_chains_and_burns() -> void:
	var s := _state()
	var sol := _add(s, "trooper", Types.Team.PLAYER, Vector2i(8, 7))
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 0))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(10, 0))
	near.max_hp = 20
	near.hp = 20
	far.max_hp = 20
	far.hp = 20
	var ids := Combat.available_abilities(s, sol).map(func(a): return a.id)
	assert_true(ids.has("shoot_barrel"), "Shoot barrel offered: %s" % str(ids))
	assert_eq(Rules.validate(s, {"type": Types.ABILITY, "unit": sol.id, "ability": "shoot_barrel", "cell": Vector2i(2, 2)}),
		"No barrel there", "only barrels")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": sol.id, "ability": "shoot_barrel", "cell": Vector2i(8, 1)}), "shot")
	assert_eq(sol.actions_left, 0, "ends the turn")
	assert_true(not s.grid.is_volatile(Vector2i(8, 1)) and not s.grid.is_volatile(Vector2i(9, 1)), "both barrels went")
	assert_eq(_events(s, "explosion").size(), 2, "the second one chained")
	assert_eq(near.hp, 17, "hit by the first blast only")
	assert_eq(far.hp, 17, "hit by the chained blast")
	assert_true(s.grid.is_volatile(Vector2i(8, 4)), "the lone barrel two rows down survives (fire doesn't reach it)")
	assert_eq(Hazards.at(s, Vector2i(9, 2)).get("kind", ""), "fire", "burning")
	assert_true(s.grid.is_walkable(Vector2i(8, 1)), "barrel cell is floor now")


func test_fire_sets_off_a_barrel() -> void:
	var s := _state()
	Hazards.add(s, [Vector2i(7, 4)], "fire", 2)
	assert_true(not s.grid.is_volatile(Vector2i(8, 4)), "fire next to a barrel sets it off")
	assert_eq(_events(s, "explosion").size(), 1, "one blast")


func test_roof_collapses_into_a_ramp_and_drops_its_occupant() -> void:
	var s := _state()
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(2, 5))
	foe.max_hp = 20
	foe.hp = 20
	Destruction.hit(s, {Vector2i(2, 5): 1})
	assert_eq(s.grid.level(Vector2i(2, 5)), 1, "one hit cracks the roof")
	Destruction.hit(s, {Vector2i(2, 5): 1})
	assert_eq(s.grid.level(Vector2i(2, 5)), 0, "two hits drop it")
	assert_eq(foe.hp, 20 - Elevation.FALL_DAMAGE_PER_LEVEL, "fall damage")
	assert_eq(_events(s, "fell").size(), 1, "fell event")
	assert_eq(_events(s, "level_changed").size(), 1, "level_changed event")
	assert_true(s.grid.is_stairs(Vector2i(2, 5)), "rubble ramp")
	assert_true(s.grid.find_path(Vector2i(2, 5), Vector2i(2, 6)).size() == 1, "walk back up the ramp")


func test_frag_on_a_scaffold_still_drops_it() -> void:
	var s := make_blank(PackedStringArray(["......", ".~~...", "......"]))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(1, 1))
	Destruction.explode(s, Vector2i(1, 2), Destruction.FRAG, null, "frag")
	assert_eq(s.grid.level(Vector2i(2, 1)), 0, "scaffold down in one hit")
	assert_eq(s.grid.rubble.get(Vector2i(2, 1)), "scaffold", "scaffold debris")
	assert_eq(_events(s, "fell").size(), 1, "occupant fell")
	assert_true(foe.hp < foe.max_hp, "and got hurt")


func test_breach_knocks_cover_down() -> void:
	var s := _state()
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(3, 1))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 4))
	foe.max_hp = 30
	foe.hp = 30
	b.abilities = ["breach"]
	b.pos = Vector2i(3, 2)
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": b.id, "ability": "breach", "target": foe.id}), "breach")
	assert_eq(s.grid.tile(Vector2i(3, 3)), Types.Tile.FLOOR, "its half cover is gone")


func test_explosions_wake_dormant_enemies() -> void:
	var s := _state()
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(10, 6))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(1, 0))
	Destruction.explode(s, Vector2i(8, 4), Destruction.FRAG, null, "frag")
	assert_true(EnemyAI.is_alerted(foe), "within 6 tiles: awake")
	assert_true(not EnemyAI.is_alerted(far), "far away: still dormant")


func test_preview_matches_the_real_thing() -> void:
	var s := _state()
	var hits := Destruction.pattern(s.grid, Vector2i(8, 2), Destruction.FRAG)
	var before := s.grid.to_dict()
	var p := Destruction.preview(s, hits)
	assert_eq(s.grid.to_dict(), before, "preview changes nothing")
	assert_eq(p.get(Vector2i(8, 1)), "barrel", "barrel goes")
	assert_eq(p.get(Vector2i(9, 1)), "barrel", "and the chained one")
	Destruction.hit(s, hits)
	for c in p:
		assert_true(s.grid.rubble.has(c) or s.grid.wear.has(c), "%s changed for real" % c)


func test_damage_survives_snapshots_and_changes_the_checksum() -> void:
	var s := _state()
	var a := s.checksum()
	Destruction.hit(s, {Vector2i(5, 2): 1, Vector2i(2, 5): 1})
	assert_true(s.checksum() != a, "cracks change the checksum")
	var copy := GameState.from_dict(s.to_dict())
	assert_eq(copy.checksum(), s.checksum(), "same after a snapshot")
	assert_eq(int(copy.grid.wear.get(Vector2i(5, 2), 0)), 1, "wear round-trips")
	assert_true(copy.grid.is_volatile(Vector2i(8, 1)), "barrels round-trip")
	assert_true(copy.grid.is_hard(Vector2i(11, 3)), "reinforced walls round-trip")


func test_same_actions_same_board() -> void:
	var boards := []
	for i in 2:
		var s := _state()
		var sol := _add(s, "trooper", Types.Team.PLAYER, Vector2i(8, 7))
		Rules.apply(s, {"type": Types.ABILITY, "unit": sol.id, "ability": "shoot_barrel", "cell": Vector2i(8, 4)})
		Destruction.hit(s, {Vector2i(5, 2): 3, Vector2i(2, 6): 2})
		boards.append(s.checksum())
	assert_eq(boards[0], boards[1], "deterministic")


func test_generated_maps_get_barrels_near_pods() -> void:
	var with_barrels := 0
	for seed in 12:
		var g := MapGen.generate({"seed": seed, "biome": "wall", "objective": "skirmish"})
		var again := MapGen.generate({"seed": seed, "biome": "wall", "objective": "skirmish"})
		assert_eq(g.volatile.keys(), again.volatile.keys(), "same seed, same barrels")
		assert_true(g.volatile.size() <= MapGen.BARRELS, "at most %d" % MapGen.BARRELS)
		for c in g.volatile:
			assert_eq(g.tile(c), Types.Tile.LOW, "barrels are half cover")
			for d in g.player_spawns:
				assert_true(maxi(absi(d.x - c.x), absi(d.y - c.y)) >= MapGen.BARREL_DROP_GAP, "away from the drop zone")
		if not g.volatile.is_empty():
			with_barrels += 1
	assert_true(with_barrels >= 8, "most maps have barrels (%d of 12)" % with_barrels)


## The evac pad, beacon, ground, perimeter and lights must survive the prop rebuild that runs
## whenever cover breaks (they used to vanish the first time anything was smashed).
func test_objective_zones_survive_a_tile_rebuild() -> void:
	var g := MapGen.generate({"biome": "wall", "objective": "extract", "seed": 16})
	assert_true(not g.marker("evac").is_empty(), "the extract map has an evac zone")
	var board: Node3D = preload("res://view/board.gd").new()
	board.build(g)
	var counts := func() -> Vector2i:
		return Vector2i(board.get_node("Tiles").get_child_count(), board.get_node("Fixed").get_child_count())
	var before: Vector2i = counts.call()
	board.rebuild_tiles()
	assert_eq(counts.call(), before, "rebuild redraws every prop and keeps the zones, ground and lights")
	board.free()
