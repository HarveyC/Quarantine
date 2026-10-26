extends Control
## The small diagram on a term card (Glossary "art"): cover walls, a roof shot, the hit roll,
## Infection tiers and so on. Pure drawing, sized by `kind`; `ctx` can mark the live value
## ("value", "count", "hit", "graze", "color").

const Styles := preload("res://ui/styles.gd")
const Icons := preload("res://ui/icons.gd")

const HEIGHTS := {"tiers": 58, "cover": 66, "high_ground": 72, "flank": 74, "hit_roll": 44,
	"damage": 50, "overwatch": 62, "lapse": 46, "turning": 40, "set": 30, "outbreak": 52,
	"severity": 40, "hazards": 50, "rank": 42, "intel": 46, "healing": 30, "hp_pips": 36, "magazine": 44, "tile": 44, "climb": 58}

var kind := ""
var ctx := {}
var tone := Color.WHITE


func _init(art_kind: String, art_ctx := {}, col := Color.WHITE, width := 270.0) -> void:
	kind = art_kind
	ctx = art_ctx
	tone = col
	custom_minimum_size = Vector2(width, HEIGHTS.get(kind, 40))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func supports(art_kind: String) -> bool:
	return HEIGHTS.has(art_kind)


func _draw() -> void:
	match kind:
		"tiers": _tiers()
		"cover": _cover()
		"high_ground": _high_ground()
		"flank": _flank()
		"hit_roll": _hit_roll()
		"damage": _damage()
		"overwatch": _overwatch()
		"lapse": _lapse()
		"turning": _turning()
		"set": _set_pips()
		"outbreak": _outbreak()
		"severity": _severity()
		"hazards": _hazards()
		"rank": _rank()
		"intel": _intel()
		"healing": _healing()
		"hp_pips": _hp_pips()
		"magazine": _magazine()
		"tile": _tile()
		"climb": _climb()


# --- helpers -------------------------------------------------------------------------------

func _text(at: Vector2, s: String, px := 10, col := Styles.DIM, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, mono := false) -> void:
	var f: Font = Styles.FONT_MONO if mono else Styles.FONT_COND_BOLD
	var x := at.x
	if w > 0 and align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif w > 0 and align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var t := s.to_upper() if not mono else s
	var size := Styles.fs(px)
	# A word wider than its slot (big text sizes) steps down to fit instead of being cut.
	if w > 0:
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if tw > w:
			size = maxi(6, floori(size * w / tw))
	draw_string(f, Vector2(x, at.y), t, align, w, size, col)


func _num(at: Vector2, s: String, px := 13, col := Styles.TEXT, align := HORIZONTAL_ALIGNMENT_CENTER, w := 60.0) -> void:
	_text(at, s, px, col, align, w, true)


func _icon(id: String, c: Vector2, px: float, col: Color, width := 1.6) -> void:
	Icons.draw(self, id, Rect2(c - Vector2(px, px) * 0.5, Vector2(px, px)), col, width)


func _soldier(c: Vector2, col: Color, r := 6.0) -> void:
	draw_circle(c + Vector2(0, -r * 1.7), r * 0.62, col)
	draw_rect(Rect2(c.x - r * 0.6, c.y - r * 1.05, r * 1.2, r * 1.6), col)


func _dashed(a: Vector2, b: Vector2, col: Color, dash := 4.0, w := 1.5) -> void:
	draw_dashed_line(a, b, col, w, dash)


func _arrow_head(at: Vector2, dir: Vector2, col: Color, s := 6.0) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([at, at - d * s + n * s * 0.6, at - d * s - n * s * 0.6]), col)


func _ground(y: float, x0: float, x1: float) -> void:
	draw_line(Vector2(x0, y), Vector2(x1, y), Styles.BORDER_STRONG, 1.0)


# --- diagrams ------------------------------------------------------------------------------

## Infection 0-100 split in tiers, with what happens at each threshold above the bar.
func _tiers() -> void:
	var x0 := 4.0
	var w := size.x - 24.0
	var y := 22.0
	var h := 10.0
	for i in 4:
		var a := x0 + w * Infection.THRESHOLDS[i] / 100.0
		var b := x0 + w * Infection.THRESHOLDS[i + 1] / 100.0
		draw_rect(Rect2(a, y, b - a - 2, h), Color(Infection.tier_color(i), 0.85 if i > 0 else 0.45))
	var marks := {Infection.EXPOSED_AT: "WAKE", Infection.MUTATING_AT: "%d%%" % roundi(Infection.LAPSE_CHANCE[Infection.Tier.MUTATING] * 100),
		Infection.CRITICAL_AT: "%d%%" % roundi(Infection.LAPSE_CHANCE[Infection.Tier.CRITICAL] * 100)}
	for v in marks:
		var x: float = x0 + w * v / 100.0
		draw_line(Vector2(x, y - 4), Vector2(x, y + h + 2), Styles.GROUND, 2.0)
		_text(Vector2(x, 12), str(marks[v]), 10, Styles.TEAL if v > Infection.EXPOSED_AT else Styles.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 50)
	_icon("turned", Vector2(x0 + w + 10, y + h * 0.5), 16, Infection.tier_color(Infection.Tier.TURNED))
	var names := ["Clean", "Exposed", "Mutating", "Critical"]
	for i in 4:
		var a := x0 + w * Infection.THRESHOLDS[i] / 100.0
		_num(Vector2(a, y + h + 12), str(Infection.THRESHOLDS[i]), 9, Styles.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 30)
		_text(Vector2(a, y + h + 24), names[i], 9, Infection.tier_color(i).lightened(0.1), HORIZONTAL_ALIGNMENT_LEFT, 60)
	if ctx.has("value"):
		var x := x0 + w * clampf(float(ctx.value), 0, 100) / 100.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, y + h + 1), Vector2(x - 5, y + h + 8), Vector2(x + 5, y + h + 8)]), Styles.TEXT)
		draw_line(Vector2(x, y - 2), Vector2(x, y + h + 1), Styles.TEXT, 2.0)


## Two side views: a low wall (-20) and a tall one (-40), shooter on the left.
func _cover() -> void:
	var hunker: bool = ctx.get("hunker", false)
	var half_w := size.x * 0.5
	for i in 2:
		var ox := i * half_w
		var gy := 46.0
		_ground(gy, ox + 4, ox + half_w - 8)
		var shooter := Vector2(ox + 14, gy)
		_soldier(shooter, Styles.AMBER)
		var wall_h := 14.0 if i == 0 else 28.0
		var wx := ox + half_w - 44
		draw_rect(Rect2(wx, gy - wall_h, 7, wall_h), Styles.TEXT.darkened(0.25))
		var target := Vector2(wx + 18, gy)
		_soldier(target, Styles.DANGER_TEXT)
		var from := shooter + Vector2(4, -10)
		var to := target + Vector2(-2, -10)
		var over := Vector2(wx + 3, gy - wall_h - 3)
		_dashed(from, over, Styles.AMBER, 3.0, 1.2)
		_dashed(over, to, Color(Styles.AMBER, 0.35), 3.0, 1.2)
		_text(Vector2(ox + 4, gy + 15), ("half" if i == 0 else "full") + (" + hunker" if hunker else ""), 10, Styles.MUTED)
		if hunker:
			_soldier(target, Styles.DANGER_TEXT, 4.5)


## A roof shot: shooter up on a block aiming down past a low wall.
func _high_ground() -> void:
	var gy := 56.0
	_ground(gy, 4, size.x * 0.62)
	var roof := Rect2(8, gy - 30, 46, 30)
	draw_rect(roof, Styles.BG_RAISED)
	draw_rect(roof, Styles.BORDER_STRONG, false, 1.0)
	for k in 3:
		draw_line(Vector2(roof.position.x + 46, gy - 4 - k * 9), Vector2(roof.position.x + 52, gy - 4 - k * 9), Styles.BORDER_STRONG, 1.0)
	var shooter := Vector2(30, gy - 30)
	_soldier(shooter, Styles.AMBER)
	var wx := size.x * 0.62 - 40
	draw_rect(Rect2(wx, gy - 14, 7, 14), Styles.TEXT.darkened(0.25))
	var target := Vector2(wx + 18, gy)
	_soldier(target, Styles.DANGER_TEXT)
	var a := shooter + Vector2(6, -10)
	var b := target + Vector2(-3, -9)
	draw_line(a, b, Styles.AMBER, 1.5)
	_arrow_head(b, b - a, Styles.AMBER)
	var tx := size.x * 0.68
	_text(Vector2(tx, 14), "their cover", 9, Styles.MUTED)
	for i in 2:
		var y := 32.0 + i * 18
		_text(Vector2(tx, y), ["full", "half"][i], 10, Styles.DIM)
		draw_line(Vector2(tx + 28, y - 4), Vector2(tx + 42, y - 4), Styles.MUTED, 1.2)
		_arrow_head(Vector2(tx + 46, y - 4), Vector2.RIGHT, Styles.MUTED, 4)
		_text(Vector2(tx + 52, y), ["half", "none"][i], 10, Styles.AMBER)


## Top-down: a wall on the target's left. From the front it's covered; from the side, flanked.
func _flank() -> void:
	var cell := 13.0
	var cols := 7
	var rows := 5
	var o := Vector2(6, 4)
	for x in cols:
		for y in rows:
			draw_rect(Rect2(o + Vector2(x, y) * cell, Vector2(cell - 1, cell - 1)), Color(1, 1, 1, 0.035))
	var t := Vector2(4, 1)
	var tc := o + (t + Vector2(0.5, 0.5)) * cell
	draw_rect(Rect2(o + Vector2(t.x, t.y) * cell - Vector2(3, 0), Vector2(3, cell * 1.0)), Styles.TEXT.darkened(0.2))
	draw_rect(Rect2(o + Vector2(t.x - 1, t.y) * cell, Vector2(3, cell)), Styles.TEXT.darkened(0.2))
	draw_circle(tc, 4.5, Styles.DANGER_TEXT)
	var blocked := o + Vector2(0.5, 1.5) * cell
	draw_circle(blocked, 4.5, Styles.MUTED)
	_dashed(blocked, tc - Vector2(8, 0), Styles.MUTED, 3.0, 1.2)
	var flanker := o + Vector2(4.5, 4.5) * cell
	draw_circle(flanker, 4.5, Styles.AMBER)
	draw_line(flanker, tc + Vector2(0, 7), Styles.AMBER, 1.5)
	_arrow_head(tc + Vector2(0, 6), Vector2(0, -1), Styles.AMBER)
	var tx := o.x + cols * cell + 14
	draw_circle(Vector2(tx + 4, 17), 4, Styles.MUTED)
	_text(Vector2(tx + 14, 21), "front: wall in the way", 10, Styles.MUTED)
	draw_circle(Vector2(tx + 4, 51), 4, Styles.AMBER)
	_text(Vector2(tx + 14, 55), "side: open, flanked", 10, Styles.AMBER)


## The 1-100 roll: hit, graze band, miss.
func _hit_roll() -> void:
	var hit := int(ctx.get("hit", 65))
	var graze := int(ctx.get("graze", mini(Combat.GRAZE_BAND, 100 - hit)))
	var x0 := 2.0
	var w := size.x - 4.0
	var y := 16.0
	var parts := [[hit, Styles.AMBER, "hit"], [graze, Styles.GRAZE, "graze"], [100 - hit - graze, Styles.HP_OFF, "miss"]]
	var x := x0
	for p in parts:
		var pw: float = w * int(p[0]) / 100.0
		if pw <= 0:
			continue
		draw_rect(Rect2(x, y, pw - 1, 10), p[1])
		if pw > 34:
			_text(Vector2(x, y - 4), "%s %d" % [p[2], p[0]], 10, p[1] if p[2] != "miss" else Styles.MUTED, HORIZONTAL_ALIGNMENT_LEFT, pw)
		x += pw
	_num(Vector2(x0, y + 24), "1", 9, Styles.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 20)
	_num(Vector2(x0 + w, y + 24), "100", 9, Styles.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 30)
	_text(Vector2(x0 + w * 0.5, y + 24), "roll under to hit", 9, Styles.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 140)


## Damage of a graze, a hit and a crit, as bars.
func _damage() -> void:
	var base := 4
	var rows := [["graze", Combat.final_damage(base, true, false), Styles.GRAZE], ["hit", base, Styles.AMBER],
		["crit", Combat.final_damage(base, false, true), Styles.DANGER_TEXT]]
	var unit := (size.x - 90) / 6.0
	for i in rows.size():
		var y := 4.0 + i * 15
		_text(Vector2(0, y + 9), rows[i][0], 10, Styles.MUTED)
		for k in int(rows[i][1]):
			draw_rect(Rect2(46 + k * unit, y + 1, unit - 2, 8), rows[i][2])
		_num(Vector2(size.x, y + 9), ["x1/2", "x1", "x1.5"][i], 10, rows[i][2], HORIZONTAL_ALIGNMENT_RIGHT, 40)


## A watching soldier, their cone, and an enemy stepping into it.
func _overwatch() -> void:
	var c := Vector2(18, size.y * 0.5 + 6)
	var r := 92.0
	var pts := PackedVector2Array([c])
	for k in 9:
		var ang := deg_to_rad(-28 + k * 7.0)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, Color(Styles.AMBER, 0.12))
	draw_polyline(pts + PackedVector2Array([c]), Color(Styles.AMBER, 0.5), 1.0)
	_soldier(c + Vector2(0, 6), Styles.AMBER, 5.5)
	var e0 := c + Vector2(76, -40)
	var e1 := c + Vector2(70, -14)
	_dashed(e0, e1, Styles.DANGER_TEXT, 3.0, 1.2)
	draw_circle(e1, 4.5, Styles.DANGER_TEXT)
	draw_line(c + Vector2(6, -4), e1 - Vector2(5, -1), Styles.AMBER, 1.5)
	_arrow_head(e1 - Vector2(5, -1), e1 - c, Styles.AMBER, 5)
	_text(Vector2(118, 30), "enemy phase", 10, Styles.MUTED)
	_text(Vector2(118, 46), "first to move in the cone", 10, Styles.DIM)


## Lapse odds as ten cells per tier, the chance filled in.
func _lapse() -> void:
	var rows := [[Infection.Tier.MUTATING, "Mutating"], [Infection.Tier.CRITICAL, "Critical"]]
	for i in rows.size():
		var y := 4.0 + i * 20
		var t: int = rows[i][0]
		_text(Vector2(0, y + 11), rows[i][1], 10, Infection.tier_color(t))
		var n := roundi(Infection.LAPSE_CHANCE[t] * 10)
		for k in 10:
			var r := Rect2(70 + k * 16, y + 2, 12, 12)
			if k < n:
				draw_rect(r, Infection.tier_color(t))
			else:
				draw_rect(r, Styles.HP_OFF)
		_num(Vector2(size.x, y + 12), "%d%%" % (n * 10), 11, Infection.tier_color(t), HORIZONTAL_ALIGNMENT_RIGHT, 40)


## A full meter tipping a soldier over to the Infected.
func _turning() -> void:
	var y := 12.0
	var w := size.x * 0.48
	draw_rect(Rect2(0, y, w, 10), Infection.tier_color(Infection.Tier.CRITICAL))
	_num(Vector2(w, y + 26), "100", 10, Styles.TEAL, HORIZONTAL_ALIGNMENT_RIGHT, 40)
	draw_line(Vector2(w + 8, y + 5), Vector2(w + 36, y + 5), Styles.MUTED, 1.5)
	_arrow_head(Vector2(w + 40, y + 5), Vector2.RIGHT, Styles.MUTED)
	_soldier(Vector2(w + 60, y + 14), Styles.MUTED)
	draw_line(Vector2(w + 74, y + 5), Vector2(w + 96, y + 5), Styles.MUTED, 1.5)
	_arrow_head(Vector2(w + 100, y + 5), Vector2.RIGHT, Styles.MUTED)
	_icon("turned", Vector2(w + 116, y + 5), 20, Infection.tier_color(Infection.Tier.TURNED))


## Pips toward a set bonus (3 by default), filled to `count`. A tag with a capstone runs on to 6.
func _set_pips() -> void:
	var col: Color = ctx.get("color", tone)
	var capstone: bool = GearData.has_capstone(str(ctx.get("tag", "")))
	var need := GearData.SET_THRESHOLD
	var have := int(ctx.get("count", need))
	var n := GearData.CAPSTONE_THRESHOLD if capstone else maxi(need, have)
	n = maxi(n, mini(have, GearData.CAPSTONE_THRESHOLD))
	var step := 22.0 if n > 4 else 26.0
	for i in n:
		var c := Vector2(10 + i * step, 13)
		if i < have:
			draw_circle(c, 9 if i < need else 7, col)
		else:
			draw_arc(c, 8.5 if i < need else 6.5, 0, TAU, 28, Color(col, 0.6), 1.5, true)
	var x := n * step + 4
	draw_line(Vector2(x, 13), Vector2(x + 22, 13), Styles.MUTED, 1.5)
	_arrow_head(Vector2(x + 26, 13), Vector2.RIGHT, Styles.MUTED)
	var label := "bonus on"
	var on := have >= need
	if capstone and have >= need:
		on = true
		label = "capstone on" if have >= GearData.CAPSTONE_THRESHOLD else "%d to capstone" % (GearData.CAPSTONE_THRESHOLD - have)
	elif not on:
		label = "%d more" % (need - have)
	_icon("perk", Vector2(x + 44, 13), 18, col if on else Styles.MUTED)
	_text(Vector2(x + 58, 18), label, 10, col if on else Styles.MUTED)


## Outbreak track with its stages; the marker sits on the run's value. Stage names that don't
## fit their segment are left to the current stage's label.
func _outbreak() -> void:
	var top := 16
	var w := size.x - 4
	var y := 20.0
	var starts := [0, 3, 6, 9, 13]
	var cur := RunRules.outbreak_stage(int(ctx.get("value", -1))) if ctx.has("value") else -1
	var f: Font = Styles.FONT_COND_BOLD
	for i in starts.size():
		var a: float = 2 + w * starts[i] / float(top)
		var b: float = 2 + w * (starts[i + 1] if i + 1 < starts.size() else top) / float(top)
		var col := Styles.TEAL.lerp(Styles.DANGER, i / 4.0)
		draw_rect(Rect2(a, y, b - a - 2, 8), Color(col, 0.35 + i * 0.15) if i != cur else col)
		var name: String = RunRules.OUTBREAK_NAMES[i].to_upper()
		if f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, Styles.fs(9)).x <= b - a - 2 or i == cur:
			_text(Vector2(a, y + 22), name, 9, col.lightened(0.15) if i == cur or cur < 0 else Color(col, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1)
		_num(Vector2(a, y - 6), str(starts[i]), 9, Styles.MUTED, HORIZONTAL_ALIGNMENT_LEFT, 20)
	if ctx.has("value"):
		var x := 2 + w * clampf(float(ctx.value), 0, top) / float(top)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y + 9), Vector2(x - 5, y + 15), Vector2(x + 5, y + 15)]), Styles.TEXT)
		draw_line(Vector2(x, y - 2), Vector2(x, y + 9), Styles.TEXT, 2.0)


## Severity 0-10 as rising steps; the current level is lit.
func _severity() -> void:
	var cur := int(ctx.get("value", -1))
	var n := Severity.MAX
	var step := (size.x - 4) / (n + 1)
	for i in n + 1:
		var h := 6.0 + i * 2.6
		var r := Rect2(2 + i * step, size.y - 12 - h, step - 3, h)
		var col := Styles.DANGER if i <= cur else Styles.HP_OFF
		if i == cur:
			col = Styles.AMBER
		draw_rect(r, col)
		if i == 0 or i == n or i == cur:
			_num(Vector2(r.position.x + r.size.x * 0.5, size.y - 1), str(i), 9, Styles.MUTED if i != cur else Styles.AMBER, HORIZONTAL_ALIGNMENT_CENTER, 20)


## The three ground hazards as tiles with their numbers.
func _hazards() -> void:
	var kinds := [["fire", "%d dmg" % Hazards.KINDS.fire.damage],
		["spore", "+%d inf" % Hazards.KINDS.spore.infection], ["acid", "%d dmg" % Hazards.KINDS.acid.damage]]
	var w := size.x / 3.0
	for i in kinds.size():
		var r := Rect2(i * w + 4, 4, 26, 26)
		var col := TileOverlays.color(kinds[i][0])
		TileOverlays.draw_swatch(self, r, kinds[i][0])
		_text(Vector2(i * w + 36, 14), Hazards.KINDS[kinds[i][0]].name, 10, col)
		_num(Vector2(i * w + 36, 28), kinds[i][1], 10, Styles.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 36)


## Fights along a run; stars where a rank-up comes.
func _rank() -> void:
	var n := 9
	var step := (size.x - 10) / n
	var y := 14.0
	draw_line(Vector2(6, y), Vector2(6 + step * (n - 1), y), Styles.BORDER_STRONG, 1.0)
	for i in n:
		var c := Vector2(6 + step * i, y)
		var up := Progression.RANK_FIGHTS.has(i + 1)
		if up:
			_icon("perk", c, 16, Styles.AMBER)
		else:
			draw_circle(c, 3.0, Styles.MUTED)
		_num(Vector2(c.x, y + 22), str(i + 1), 9, Styles.AMBER if up else Styles.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 20)
	_text(Vector2(size.x, y + 22), "", 9)


## A ? node, 1 Intel, and what it really was.
func _intel() -> void:
	var c := Vector2(22, 22)
	draw_arc(c, 15, 0, TAU, 32, Styles.DIM, 1.5)
	_text(c + Vector2(0, 6), "?", 18, Styles.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 20)
	var a := Vector2(46, 22)
	draw_line(a, a + Vector2(70, 0), Styles.MUTED, 1.5)
	_arrow_head(a + Vector2(74, 0), Vector2.RIGHT, Styles.MUTED)
	_icon("intel", a + Vector2(24, -12), 14, Styles.TEXT)
	_num(a + Vector2(42, -7), "-1", 11, Styles.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 30)
	var d := Vector2(146, 22)
	draw_arc(d, 15, 0, TAU, 32, Styles.AMBER, 1.5)
	_icon("depot", d, 16, Styles.AMBER)
	_text(d + Vector2(24, 4), "now you know", 10, Styles.MUTED)


## HP pips with the after-fight heal hatched in.
func _healing() -> void:
	var max_hp := 10
	var hp := 5
	var heal := ceili(max_hp * RunRules.HEAL_AFTER_FIGHT)
	for i in max_hp:
		var r := Rect2(i * 17, 8, 14, 8)
		if i < hp:
			draw_rect(r, Styles.HP)
		elif i < hp + heal:
			draw_rect(r, Color(Styles.HP, 0.35))
			draw_rect(r, Styles.HP, false, 1.0)
		else:
			draw_rect(r, Styles.HP_OFF)
	_num(Vector2(max_hp * 17 + 6, 17), "+%d%%" % roundi(RunRules.HEAL_AFTER_FIGHT * 100), 12, Styles.HP, HORIZONTAL_ALIGNMENT_LEFT, 60)


## Three pips of a big monster's bar: full, half, empty, with what one pip is worth (ctx.per).
func _hp_pips() -> void:
	var per := int(ctx.get("per", 5))
	var w := 34.0
	for i in 3:
		var r := Rect2(i * (w + 8), 6, w, 10)
		draw_rect(r, Styles.HP_OFF)
		if i == 0:
			draw_rect(r, Styles.HP)
		elif i == 1:
			draw_rect(Rect2(r.position, Vector2(w * 0.5, 10)), Styles.HP)
	_num(Vector2(0, 30), "1 pip = %d HP" % per, 11, Styles.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 120)


## A magazine of rounds, some spent, then the same magazine full again after a Reload.
func _magazine() -> void:
	var n := 6
	var spent := 3
	var rw := 7.0
	var rh := 18.0
	for pass_i in 2:
		var ox := 4.0 + pass_i * (size.x * 0.5 + 8.0)
		for i in n:
			var x := ox + i * (rw + 5.0)
			var loaded: bool = pass_i == 1 or i >= spent
			var col := Styles.AMBER if loaded else Color(Styles.DIM, 0.5)
			var body := Rect2(x, 14, rw, rh - 5)
			var tip := PackedVector2Array([Vector2(x, 15), Vector2(x + rw * 0.5, 6), Vector2(x + rw, 15)])
			if loaded:
				draw_rect(body, col)
				draw_colored_polygon(tip, col.lightened(0.25))
			else:
				draw_rect(body, col, false, 1.0)
				draw_polyline(tip, col, 1.0)
		_text(Vector2(ox, 40), "after shots" if pass_i == 0 else "reloaded", 9, Styles.MUTED)
	_icon("reload", Vector2(size.x * 0.5 + 2.0, 22), 16, Styles.AMBER)


## A strip of floor with the marking ctx.overlay (a TileOverlays key) painted on the middle
## tiles, exactly as on the map; objective zones carry their map label over it.
func _tile() -> void:
	var key := str(ctx.get("overlay", ""))
	var n := 7
	var gap := 2.0
	var t := minf(30.0, (size.x - 8.0 - gap * (n - 1)) / n)
	var y := size.y - t - 4.0
	var lit := [2, 3, 4]
	for i in n:
		var r := Rect2(4.0 + i * (t + gap), y, t, t)
		if lit.has(i):
			TileOverlays.draw_swatch(self, r, key)
		else:
			draw_rect(r, Color("24261f"))
	var label := str(TileOverlays.KINDS.get(key, {}).get("label", ""))
	if label != "":
		var mid := 4.0 + 3 * (t + gap) + t * 0.5
		_text(Vector2(mid, y - 1.0), label, 10, TileOverlays.color(key), HORIZONTAL_ALIGNMENT_CENTER, 120.0)


## Side view of a way up (ctx.way: "ladder", "stairs" or "scaffold"): ground, a roof, and the
## way between them, with its cost in moves.
func _climb() -> void:
	var way := str(ctx.get("way", "ladder"))
	var ground := size.y - 8.0
	var top := ground - 34.0
	var x0 := 70.0
	var x1 := 170.0
	draw_line(Vector2(6, ground), Vector2(size.x - 6, ground), Styles.BORDER_STRONG, 1.5)
	var roof := Rect2(x1, top, size.x - 6 - x1, ground - top)
	if way == "scaffold":
		# Thin planks on poles: it can come down.
		draw_rect(Rect2(x0, top, x1 - x0 + 40, 4), Color("7a5a36"))
		for px in [x0 + 4, x0 + 60, x1 + 30]:
			draw_line(Vector2(px, top + 4), Vector2(px, ground), Styles.MUTED, 2.0)
		for k in 3:
			var cx := x0 + 18 + k * 28
			draw_line(Vector2(cx, top + 8), Vector2(cx + 8, top + 16), Styles.DANGER, 1.5)
			draw_line(Vector2(cx + 8, top + 16), Vector2(cx + 4, top + 22), Styles.DANGER, 1.5)
		_text(Vector2(x0, top - 4), "collapses", 10, Styles.DANGER_TEXT)
		_num(Vector2(x1 + 50, ground - 10), "-%d / level" % Elevation.FALL_DAMAGE_PER_LEVEL, 11, Styles.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 90)
		return
	draw_rect(roof, Color(0.66, 0.78, 0.8, 0.12))
	draw_line(roof.position, Vector2(roof.end.x, roof.position.y), Styles.BORDER_STRONG, 2.0)
	var col := Styles.AMBER
	if way == "stairs":
		var steps := 4
		for k in steps:
			var sx := x1 - (steps - k) * 22.0
			var sy := ground - (k + 1) * (ground - top) / steps
			draw_line(Vector2(sx, sy), Vector2(sx + 22, sy), col, 2.0)
			draw_line(Vector2(sx, sy), Vector2(sx, sy + (ground - top) / steps), col, 2.0)
		_num(Vector2(x0 - 40, ground - 26), "1 move", 11, Styles.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 60)
	else:
		for rx in [x1 - 16, x1 - 4]:
			draw_line(Vector2(rx, ground), Vector2(rx, top - 6), col, 2.0)
		var k := ground - 6
		while k > top:
			draw_line(Vector2(x1 - 16, k), Vector2(x1 - 4, k), col, 1.5)
			k -= 7
		_num(Vector2(x0 - 40, ground - 26), "%d moves" % Grid.LADDER_COST, 11, Styles.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 60)
	_text(Vector2(roof.position.x + 8, top + 16), "roof", 10, Styles.DIM)
