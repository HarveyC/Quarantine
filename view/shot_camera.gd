extends RefCounted
## Picks shot-camera spots that stay out of the scenery. The board is a height field
## (floor lift + wall / low cover blocks, a fence ring around the map), so a camera spot
## is good when the lens has room around it and the lines to its subjects pass above
## every block on the way. Static and grid-only so tests can check it without a view.

const Board := preload("res://view/board.gd")

const WALL_TOP := 2.35   # wall box + cap above the floor
const LOW_TOP := 1.15    # tallest low cover (crate + lid)
const OUTSIDE_TOP := 2.8 # fence and containers beyond the map edge
const EDGE_TOP := 2.0    # edge wall + cap above its floor
const EDGE_HALF := 0.14  # half an edge wall's thickness, plus a little
const LENS := 0.35       # room the camera needs around it so the near plane doesn't cut in
const STEP := 0.12       # sample spacing along a line of sight
const TWO_SHOT_FOV := 50.0  # degrees, vertical: the tactical camera's lens


## Height of the solid scenery in the cell under a world point.
static func solid_top(grid: Grid, p: Vector3) -> float:
	if p.x < -1.3 or p.z < -1.3 or p.x > grid.width + 0.3 or p.z > grid.height + 0.3:
		return OUTSIDE_TOP
	var c := Board.world_to_cell(p)
	if not grid.in_bounds(c):
		return 0.0
	var floor_y := Board.RAISE * grid.level(c)
	# Edge walls stand on cell borders: a point close to one is inside it.
	var fx := p.x - c.x
	var fz := p.z - c.y
	for d in Grid.DIRS4:
		var near := (fx * d.x + fz * d.y) > 0.5 - EDGE_HALF
		if near and grid.edge(c, d) in [Grid.EDGE_WALL, Grid.EDGE_WINDOW, Grid.EDGE_DOOR, Grid.EDGE_CLOSED]:
			return Board.RAISE * grid.edge_top(c, d) - Board.RAISE + EDGE_TOP
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


## A wide two-shot for an attack the player watches rather than takes (enemy shots and strikes):
## side-on from the attacker's side, far enough back that attacker and target both fit with room
## round them, raised as the scenery closes in, and above it all when nothing lower is clear.
## Returns {eye, look, fov}; the camera may drift from `eye` a tenth of the way to `look`.
static func two_shot(grid: Grid, attacker: Vector3, target: Vector3, aspect := 16.0 / 9.0) -> Dictionary:
	var a := attacker + Vector3(0, 1.1, 0)
	var b := target + Vector3(0, 1.0, 0)
	var look := (attacker + target) * 0.5 + Vector3(0, 0.95, 0)
	var axis := Vector3(target.x - attacker.x, 0, target.z - attacker.z)
	var span := axis.length()
	axis = axis.normalized() if span > 0.01 else Vector3.FORWARD
	var perp := axis.cross(Vector3.UP)
	# Back far enough that the pair spans no more than ~70% of the frame width side-on.
	var half_w := tan(deg_to_rad(TWO_SHOT_FOV * 0.5)) * aspect
	var fit := clampf((span * 0.5 + 1.4) / (half_w * 0.75), 4.2, 17.0)
	var subjects := [a, b]
	for el in [26.0, 38.0, 50.0, 62.0]:
		for d in [fit, fit * 1.2, fit * 0.85]:
			for turn in [35.0, 15.0, 55.0, 0.0, 75.0]:
				for side in [1.0, -1.0]:
					var t := deg_to_rad(turn)
					var flat: Vector3 = perp * side * cos(t) - axis * sin(t)
					var e: float = deg_to_rad(el)
					var eye: Vector3 = look + flat * cos(e) * d + Vector3.UP * sin(e) * d
					var drift := eye.lerp(look, 0.1)
					if framed(eye, look, TWO_SHOT_FOV, aspect, subjects) and sees(grid, eye, subjects) \
							and eye_clear(grid, drift) and line_clear(grid, eye, drift):
						return {"eye": eye, "look": look, "fov": TWO_SHOT_FOV}
	# Nothing lower is clear: look down on the pair from high on one side, the pair still running
	# across the frame, raised above the scenery until both are in view.
	var best := Vector3.ZERO
	for side in [1.0, -1.0]:
		var e := deg_to_rad(72.0)
		var eye: Vector3 = look + perp * side * cos(e) * fit * 1.25 + Vector3.UP * sin(e) * fit * 1.25
		eye.y = maxf(eye.y, top_near(grid, eye, 2.0) + 2.5)
		var guard := 0
		while not sees(grid, eye, subjects) and guard < 12:
			eye.y += 1.0
			guard += 1
		if best == Vector3.ZERO or eye.y < best.y:
			best = eye
	var eye := best
	return {"eye": eye, "look": look, "fov": TWO_SHOT_FOV}


## The FOV that keeps a 3.2 m tall slice round a unit in frame from `dist` away, for a push-in
## that ends close in a tight spot (otherwise a long lens there frames only a chest).
static func fit_fov(dist: float, narrowest := 30.0, widest := 50.0) -> float:
	return clampf(rad_to_deg(2.0 * atan(1.6 / maxf(dist, 0.1))), narrowest, widest)


## Every point in `pts` sits inside the frame of a camera at `eye` looking at `look`.
static func framed(eye: Vector3, look: Vector3, fov: float, aspect: float, pts: Array) -> bool:
	var basis := Transform3D().looking_at(look - eye, Vector3.UP).basis.inverse()
	var tv := tan(deg_to_rad(fov * 0.5)) * 0.92
	for p in pts:
		var l: Vector3 = basis * (p - eye)
		if l.z >= -0.1 or absf(l.y / -l.z) > tv or absf(l.x / -l.z) > tv * aspect:
			return false
	return true
