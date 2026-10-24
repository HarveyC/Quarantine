extends RefCounted
## Picks shot-camera spots that stay out of the scenery. The board is a height field
## (floor lift + wall / low cover blocks, a fence ring around the map), so a camera spot
## is good when the lens has room around it and the lines to its subjects pass above
## every block on the way. Static and grid-only so tests can check it without a view.

const Board := preload("res://view/board.gd")

const WALL_TOP := 2.35   # wall box + cap above the floor
const LOW_TOP := 1.15    # tallest low cover (crate + lid)
const OUTSIDE_TOP := 2.8 # fence and containers beyond the map edge
const LENS := 0.35       # room the camera needs around it so the near plane doesn't cut in
const STEP := 0.12       # sample spacing along a line of sight


## Height of the solid scenery in the cell under a world point.
static func solid_top(grid: Grid, p: Vector3) -> float:
	if p.x < -1.3 or p.z < -1.3 or p.x > grid.width + 0.3 or p.z > grid.height + 0.3:
		return OUTSIDE_TOP
	var c := Board.world_to_cell(p)
	if not grid.in_bounds(c):
		return 0.0
	var floor_y := Board.RAISE * grid.level(c)
	match grid.tile(c):
		Types.Tile.WALL: return floor_y + WALL_TOP
		Types.Tile.LOW: return floor_y + LOW_TOP
	return floor_y


## The camera at `eye` has room: nothing solid within LENS of it.
static func eye_clear(grid: Grid, eye: Vector3) -> bool:
	for off in [Vector3.ZERO, Vector3(LENS, 0, 0), Vector3(-LENS, 0, 0), Vector3(0, 0, LENS), Vector3(0, 0, -LENS),
			Vector3(LENS, 0, LENS) * 0.7, Vector3(-LENS, 0, LENS) * 0.7, Vector3(LENS, 0, -LENS) * 0.7, Vector3(-LENS, 0, -LENS) * 0.7]:
		if eye.y < solid_top(grid, eye + off) + 0.2:
			return false
	return true


## Nothing solid between `a` and `b`.
static func line_clear(grid: Grid, a: Vector3, b: Vector3) -> bool:
	var n := maxi(2, ceili(a.distance_to(b) / STEP))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		if p.y < solid_top(grid, p) + 0.05:
			return false
	return true


## A camera spot `eye` that has room and sees every point in `subjects`.
static func sees(grid: Grid, eye: Vector3, subjects: Array) -> bool:
	if not eye_clear(grid, eye):
		return false
	for s in subjects:
		if not line_clear(grid, eye, s):
			return false
	return true


## Highest scenery within `r` of a point, for a fallback camera above it all.
static func top_near(grid: Grid, p: Vector3, r := 1.5) -> float:
	var top := 0.0
	for dx in [-r, 0.0, r]:
		for dz in [-r, 0.0, r]:
			top = maxf(top, solid_top(grid, p + Vector3(dx, 0, dz)))
	return top
