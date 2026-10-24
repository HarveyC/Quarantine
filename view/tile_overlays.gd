class_name TileOverlays
extends RefCounted
## One look per floor marking, shared by the 3D board (Board), the HUD legend (OverlayLegend)
## and the hover cards (TipArt "tile"), so the legend swatch always matches what is on the floor.
##
## Every marking gets its own colour AND its own pattern, so two never read alike even in a
## dim corner: teal stays Infection only (spores), red is danger (enemy sight, blast), amber is
## what the player is doing (path, aim), objective zones are solid with a bright edge and a label.
##
##   pattern  how the floor is painted (Board) and the swatch drawn (draw_swatch):
##            "fill" soft fill + outline, "wash" faint fill + outline, "hatch" diagonal stripes,
##            "cross" crosshatch,
##            "dots" spore dots, "puddle" acid blotches, "haze" smoke, "zone" fill + bright edge,
##            "brackets" corner brackets

const Palette := preload("res://view/palette.gd")

const EVAC := Color("59f273")
const FIRE := Color("ff7a2a")
const ACID := Color("c8e03a")
const SMOKE := Color("b9bdb8")
const MOVE := Color("b8cde0")

## Legend order. `term` is the Glossary key for the hover card; `label` names objective zones
## on the map.
const KINDS := {
	"move": {"term": "tile_move", "name": "Move range", "color": MOVE, "pattern": "fill"},
	"sight": {"term": "tile_sight", "name": "Enemy sight", "color": Palette.DANGER, "pattern": "wash"},
	"aim": {"term": "tile_aim", "name": "Aim area", "color": Palette.AMBER, "pattern": "brackets"},
	"blast": {"term": "tile_blast", "name": "Blast", "color": Palette.DANGER, "pattern": "cross"},
	"fire": {"term": "hazard_fire", "name": "Fire", "color": FIRE, "pattern": "hatch"},
	"spore": {"term": "hazard_spore", "name": "Spores", "color": Palette.TEAL, "pattern": "dots"},
	"acid": {"term": "hazard_acid", "name": "Acid", "color": ACID, "pattern": "puddle"},
	"smoke": {"term": "smoke", "name": "Smoke", "color": SMOKE, "pattern": "haze"},
	"evac": {"term": "zone_evac", "name": "Evac zone", "color": EVAC, "pattern": "zone", "label": "EVAC"},
	"beacon": {"term": "zone_beacon", "name": "Beacon", "color": Palette.AMBER, "pattern": "zone", "label": "BEACON"},
	"exit": {"term": "zone_drop", "name": "Drop zone", "color": EVAC, "pattern": "zone", "label": "DROP ZONE"},
}

## Objective zones, drawn from Grid.markers.
const ZONES: Array[String] = ["evac", "beacon", "exit"]


static func color(key: String) -> Color:
	return KINDS.get(key, {}).get("color", Color.WHITE)


static func term(key: String) -> String:
	return str(KINDS.get(key, {}).get("term", ""))


static func pattern(key: String) -> String:
	return str(KINDS.get(key, {}).get("pattern", "fill"))


# --- 3D floor textures -----------------------------------------------------------------------

static var _tex := {}


## A white pattern on transparent for `pat` ("hatch", "cross", "dots", "puddle"), tiling every
## world unit.
## Board tints it per marking and maps it in world space so it runs on across cells.
static func texture(pat: String) -> Texture2D:
	if _tex.has(pat):
		return _tex[pat]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var a := 0.0
			match pat:
				"hatch":   # two stripes per tile, like warning tape
					a = 1.0 if posmod(x + y, 32) < 11 else 0.0
				"cross":   # a crosshatch: unlike fire's stripes at a glance
					a = 1.0 if posmod(x + y, 32) < 6 or posmod(x - y, 32) < 6 else 0.0
				"dots":    # a staggered field of round spores
					var row := floori(y / 16.0)
					var off := 8 * (row % 2)
					var cx := 16.0 * floorf((x + off) / 16.0) + 8.0 - off
					var d := Vector2(x, y).distance_to(Vector2(cx, 16.0 * row + 8.0))
					a = clampf(4.2 - d, 0.0, 1.0)
				"puddle":  # soft blotches, wrapping at the edges
					for b in [[18.0, 20.0, 13.0], [46.0, 42.0, 15.0], [50.0, 10.0, 8.0], [14.0, 52.0, 9.0]]:
						var dx := absf(x - b[0])
						var dy := absf(y - b[1])
						dx = minf(dx, n - dx)
						dy = minf(dy, n - dy)
						a = maxf(a, clampf((b[2] - Vector2(dx, dy).length()) / 4.0, 0.0, 1.0))
			# The ground between the marks keeps a faint tint so a whole area still reads as one.
			img.set_pixel(x, y, Color(1, 1, 1, lerpf(0.3, 1.0, a)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[pat] = t
	return t


## An unshaded see-through floor material with `pat` mapped in world space.
static func floor_material(col: Color, pat: String, per_unit := 1.0) -> StandardMaterial3D:
	var m := Palette.overlay(col)
	m.albedo_texture = texture(pat)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_unit
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


# --- 2D swatch (legend rows and hover cards) -------------------------------------------------

## Draws the marking `key` on a small floor tile filling `r`.
static func draw_swatch(ci: CanvasItem, r: Rect2, key: String) -> void:
	var col := color(key)
	ci.draw_rect(r, Color("24261f"))
	match pattern(key):
		"fill":
			ci.draw_rect(r, Color(col, 0.2))
			ci.draw_rect(r.grow(-1), Color(col, 0.85), false, 2.0)
		"wash":
			ci.draw_rect(r, Color(col, 0.22))
			ci.draw_rect(r.grow(-1), Color(col, 0.9), false, 2.0)
		"zone":
			ci.draw_rect(r, Color(col, 0.26))
			ci.draw_rect(r.grow(-1.5), col, false, 3.0)
		"hatch":
			ci.draw_rect(r, Color(col, 0.16))
			_hatch(ci, r, Color(col, 0.8), r.size.y * 0.45)
			ci.draw_rect(r.grow(-1), Color(col, 0.9), false, 1.5)
		"cross":
			ci.draw_rect(r, Color(col, 0.16))
			_hatch(ci, r, Color(col, 0.8), r.size.y * 0.5, 2.0)
			_hatch(ci, r, Color(col, 0.8), r.size.y * 0.5, 2.0, true)
			ci.draw_rect(r.grow(-1), Color(col, 0.9), false, 1.5)
		"dots":
			ci.draw_rect(r, Color(col, 0.14))
			var step := r.size.y / 3.0
			for iy in 3:
				for ix in int(ceilf(r.size.x / step)):
					var p := r.position + Vector2((ix + 0.5 + 0.5 * (iy % 2)) * step, (iy + 0.5) * step)
					if r.has_point(p):
						ci.draw_circle(p, step * 0.2, col)
			ci.draw_rect(r.grow(-1), Color(col, 0.7), false, 1.5)
		"puddle":
			ci.draw_rect(r, Color(col, 0.14))
			ci.draw_set_transform(r.position + r.size * Vector2(0.34, 0.45), 0.0, Vector2(1.4, 1.0))
			ci.draw_circle(Vector2.ZERO, r.size.y * 0.22, Color(col, 0.75))
			ci.draw_set_transform(r.position + r.size * Vector2(0.72, 0.62), 0.0, Vector2(1.3, 1.0))
			ci.draw_circle(Vector2.ZERO, r.size.y * 0.15, Color(col, 0.75))
			ci.draw_set_transform(Vector2.ZERO)
			ci.draw_rect(r.grow(-1), Color(col, 0.7), false, 1.5)
		"haze":
			ci.draw_rect(r, Color(col, 0.18))
			for b in [[0.3, 0.55, 0.32], [0.62, 0.4, 0.38], [0.8, 0.68, 0.26]]:
				ci.draw_circle(r.position + r.size * Vector2(b[0], b[1]), r.size.y * b[2], Color(col, 0.28))
		"brackets":
			ci.draw_rect(r, Color(col, 0.18))
			var k := minf(r.size.x, r.size.y) * 0.32
			for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				var sx := 1.0 if corner.x == r.position.x else -1.0
				var sy := 1.0 if corner.y == r.position.y else -1.0
				ci.draw_polyline(PackedVector2Array([corner + Vector2(0, sy * k), corner, corner + Vector2(sx * k, 0)]), col, 2.5)


## Diagonal stripes clipped to `r`, `gap` apart (`flip` runs them the other way).
static func _hatch(ci: CanvasItem, r: Rect2, col: Color, gap: float, w := 3.0, flip := false) -> void:
	var k := -r.size.y
	while k < r.size.x:
		# Segment of the line x - y = k (local) inside the rect.
		var a := Vector2(maxf(k, 0.0), maxf(k, 0.0) - k)
		var b := Vector2(minf(k + r.size.y, r.size.x), minf(k + r.size.y, r.size.x) - k)
		if b.x > a.x:
			if flip:
				a.x = r.size.x - a.x
				b.x = r.size.x - b.x
			ci.draw_line(r.position + a, r.position + b, col, w, true)
		k += gap
