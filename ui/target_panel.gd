extends "res://ui/frame.gd"
## Shot preview while aiming: the hit chance as a big lantern ring gauge (graze after it),
## crit and graze, a hit/graze/miss strip,
## every modifier as a signed row, and the damage range shown on the target's HP pips.
## Aimed at a fuel barrel (show_barrel) the foot shows the blast instead: who it catches.

const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")

var _target: Label
var _hit: Label
var _ring: W.Ring
var _crit: Label
var _graze: Label
var _strip: HBoxContainer
var _rows: GridContainer
var _dmg: Label
var _hp: Control
var _note: Label


func _init() -> void:
	super(Vector4(18, 14, 18, 14))


func build() -> void:
	name = "TargetPanel"
	custom_minimum_size = Vector2(330, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	var box := Styles.vbox(8)
	add_child(box)
	var head := Styles.hbox(6)
	_target = Styles.caps("", 13, Styles.DIM)
	head.add_child(_target)
	head.add_child(Styles.spacer())
	head.add_child(W.keycap("Tab"))
	head.add_child(Styles.caps("next", 11, Styles.MUTED, false))
	box.add_child(head)
	var big := Styles.hbox(18)
	_ring = W.Ring.new(118.0, 9.0, Styles.AMBER)
	_ring.extra_color = Styles.GRAZE
	var inner := Styles.vbox(-4)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit = Styles.display("", 34, Styles.TEXT)
	_hit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_hit)
	var th := Styles.label("to hit", 13, Styles.DIM)
	th.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(th)
	_ring.add_child(inner)
	big.add_child(_ring)
	var side := Styles.vbox(6)
	side.alignment = BoxContainer.ALIGNMENT_END
	var cr := Styles.hbox(8)
	var cl := Styles.caps("Crit", 11, Styles.MUTED)
	cl.custom_minimum_size = Vector2(40, 0)
	cr.add_child(cl)
	_crit = Styles.mono("", 16, Styles.TEXT)
	cr.add_child(_crit)
	side.add_child(cr)
	var gr := Styles.hbox(8)
	var gl := Styles.caps("Graze", 11, Styles.MUTED)
	gl.custom_minimum_size = Vector2(40, 0)
	gr.add_child(gl)
	_graze = Styles.mono("", 16, Styles.GRAZE)
	gr.add_child(_graze)
	side.add_child(gr)
	big.add_child(side)
	box.add_child(big)
	_strip = Styles.hbox(3)
	_strip.custom_minimum_size = Vector2(0, 7)
	box.add_child(_strip)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("v_separation", 3)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_rows)
	var sep := ColorRect.new()
	sep.color = Styles.BORDER_SOFT
	sep.custom_minimum_size = Vector2(0, 1)
	box.add_child(sep)
	var dmg := Styles.hbox(6)
	_dmg = Styles.caps("", 13)
	dmg.add_child(_dmg)
	dmg.add_child(Styles.spacer())
	_hp = W.Pips.new(Vector2(14, 6))
	_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dmg.add_child(_hp)
	box.add_child(dmg)
	_note = Styles.label("", 13, Styles.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(294, 0)
	box.add_child(_note)
	var foot := Styles.hbox(8)
	foot.add_child(W.keycap("Enter"))
	foot.add_child(Styles.label("fire", 13))
	foot.add_child(Control.new())
	foot.add_child(W.keycap("Esc"))
	foot.add_child(Styles.label("cancel", 13))
	box.add_child(foot)


## Fills the panel for `u` shooting `t`. Returns the odds used.
func show_shot(s: GameState, u: Unit, t: Unit) -> Dictionary:
	var odds := Combat.hit_chance(s, u, t)
	_target.text = "TARGET · %s" % t.display_name.to_upper()
	_target.remove_meta(Tips.META)
	_odds(odds)
	var hit := int(odds.get("hit", 0))
	var lo := u.damage.x
	var hi := u.damage.y
	_dmg.text = "DAMAGE %d–%d" % [lo, hi]
	_dmg.add_theme_color_override("font_color", Styles.TEXT)
	_hp.visible = true
	(_hp as W.Pips).set_values(t.max_hp, t.hp, mini(hi, t.hp), Styles.DANGER)
	var notes := PackedStringArray()
	if odds.get("flanked", false):
		notes.append("Flanked: no cover, crits more likely")
		Tips.term(_note, "flank")
	else:
		_note.remove_meta(Tips.META)
	if lo >= t.hp and hit > 0:
		notes.append("A hit kills")
	elif hi >= t.hp and hit > 0:
		notes.append("Kill possible")
	_note.text = " · ".join(notes)
	_note.add_theme_color_override("font_color", Styles.DANGER_TEXT if odds.get("flanked", false) else Styles.DIM)
	_note.visible = not notes.is_empty()
	return odds


## Fills the panel for `u` shooting the fuel barrel on `c`: the same odds layout, then the blast
## (Destruction.barrel_blasts): its damage and who it catches. Returns the odds used.
func show_barrel(s: GameState, u: Unit, c: Vector2i) -> Dictionary:
	var odds := Combat.barrel_chance(s, u, c)
	_target.text = "TARGET · FUEL BARREL"
	Tips.term(_target, "fuel_barrel")
	_odds(odds)
	var blasts := Destruction.barrel_blasts(s, c)
	var foes := 0
	var kills := 0
	var friends := 0
	for o in s.living():
		if not Vision.sees_unit(s, u.team, o) and o.team != u.team:
			continue
		var n := blasts.filter(func(b: Vector2i) -> bool: return Kit.cheb(b, o.pos) <= 1).size()
		if n == 0:
			continue
		if u.is_enemy_of(o):
			foes += 1
			if o.hp <= n * Destruction.BARREL.damage:
				kills += 1
		else:
			friends += 1
	_dmg.text = "BLAST %d DAMAGE · 3x3" % Destruction.BARREL.damage
	_dmg.add_theme_color_override("font_color", Styles.AMBER)
	_hp.visible = false
	var notes := PackedStringArray()
	notes.append("Catches %d %s" % [foes, "enemy" if foes == 1 else "enemies"] if foes > 0 else "No enemies in the blast")
	if kills > 0:
		notes.append("%d would drop" % kills)
	if blasts.size() > 1:
		notes.append("Sets off %d more %s" % [blasts.size() - 1, "barrel" if blasts.size() == 2 else "barrels"])
	if friends > 0:
		notes.append("%d of your squad in the blast" % friends)
	_note.text = " · ".join(notes)
	_note.add_theme_color_override("font_color", Styles.DANGER_TEXT if friends > 0 else Styles.DIM)
	_note.remove_meta(Tips.META)
	_note.visible = true
	return odds


## Ring, crit/graze, the hit/graze/miss strip and the modifier rows for `odds`.
func _odds(odds: Dictionary) -> void:
	var hit := int(odds.get("hit", 0))
	var graze := int(odds.get("graze", 0))
	_hit.text = "%d%%" % hit
	_ring.set_value(hit / 100.0, Styles.AMBER, graze / 100.0)
	_crit.text = "%d%%" % int(odds.get("crit", 0))
	_graze.text = "%d%%" % graze
	Tips.term(_hit, "hit_chance", {"hit": hit, "graze": graze})
	Tips.term(_strip, "hit_chance", {"hit": hit, "graze": graze})
	Tips.term(_crit, "crit")
	Tips.term(_graze, "graze")
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	for part in [[hit, Styles.AMBER], [graze, Styles.GRAZE.darkened(0.3)], [100 - hit - graze, Styles.HP_OFF]]:
		if int(part[0]) <= 0:
			continue
		var r := Panel.new()
		r.add_theme_stylebox_override("panel", Styles.panel_box(part[1], Color(0, 0, 0, 0), Styles.PILL))
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.custom_minimum_size = Vector2(0, 7)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_stretch_ratio = float(part[0])
		_strip.add_child(r)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for row in odds.get("breakdown", []):
		if not (row is Array and row.size() >= 2):
			continue
		var n := Styles.label(str(row[0]), 14, Styles.DIM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Tips.auto(n)
		_rows.add_child(n)
		var v := int(row[1])
		var txt := str(v) if str(row[0]) == "Aim" else "%+d" % v
		var col := Styles.TEXT if str(row[0]) == "Aim" else (Styles.HP if v > 0 else (Styles.DANGER_TEXT if v < 0 else Styles.DIM))
		var vl := Styles.mono(txt.replace("-", "−"), 13, col)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rows.add_child(vl)
