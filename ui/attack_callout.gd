extends Control
## Who hit whom, at a glance, while an attack plays: attacker and target portraits either side
## of the attack's icon (with the odds), then the outcome as it lands: a one-word result, the
## target's HP pips with the damage marked, and icons for what it picked up (Infection, Pinned,
## Stunned, Bleeding, down). It sits bottom centre over a soft haze, above the letterbox bar
## during a shot cinematic. Words are kept to one or two, set bold, and open their glossary
## card on hover.
##
## Driven by the event player: `begin` as the attack starts, `result` on impact, `follow` for
## each consequence event, `release` once the action is over (it lingers, then fades).

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const Tips := preload("res://ui/tips/tips.gd")
const Frame := preload("res://ui/frame.gd")

const PORTRAIT := 50.0
const HOLD := 1.1     # seconds the outcome stays up once the action is over
const FADE := 0.35
## Melee abilities -> the icon drawn between the portraits.
const STRIKE_ICON := {"claw": "bloom_claw", "maul": "bloom_claw", "pounce": "runner_leap", "slam": "bash",
	"spore_drop": "infection", "bloom_claw": "bloom_claw", "lunge": "lunge", "riposte": "lunge", "bash": "bash",
	"charge": "shield_charge", "spit": "infection", "suppress": "suppress", "breach": "breach"}

var active := false
var cinematic := false   # a shot cinematic is on: sit above its letterbox bar
## Bottom of the letterbox bar's middle, set by the HUD (0: the bottom edge).
var bar_height := 0.0
var target_id := -1
var attacker_id := -1

var _frame: Frame
var _a_portrait: W.Portrait
var _t_portrait: W.Portrait
var _a_name: Label
var _t_name: Label
var _icon: W.Icon
var _arrow: Control
var _chance: Label
var _gun: Label
var _pips: W.HpPips
var _dmg: Label
var _word: Label
var _statuses: HBoxContainer
var _t_hp := 0
var _t_max := 0
var _t_kind := ""
var _t_color := Styles.TEXT
var _t_inf := 0
var _lost := 0
var _alpha := 0.0
var _hold := 0.0
var _keys: Array[String] = []   # statuses shown, for tests


func build() -> void:
	name = "AttackCallout"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = Frame.new(Vector4(26, 10, 30, 10))
	_frame.set_haze(0.62)
	add_child(_frame)
	var row := Styles.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_frame.add_child(row)

	var a_box := _unit_box()
	_a_portrait = a_box.get_child(0)
	_a_name = a_box.get_child(1)
	row.add_child(a_box)

	var mid := Styles.vbox(2)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_arrow = Control.new()
	_arrow.custom_minimum_size = Vector2(86, 30)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	_icon = W.Icon.new("shoot", Styles.DANGER, 26.0, 2.2)
	_arrow.add_child(_icon)
	# Centre by hand on the arrow's real size, so the icon sits over the hit % whatever its art.
	_arrow.resized.connect(func() -> void: _icon.position = ((_arrow.size - _icon.size) * 0.5).round())
	mid.add_child(_arrow)
	_chance = Styles.caps("", 13, Styles.AMBER)
	_chance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chance.custom_minimum_size.x = _arrow.custom_minimum_size.x  # the column keeps the arrow's width
	Tips.term(_chance, "hit_chance")
	mid.add_child(_chance)
	_gun = Styles.caps("", 11, Styles.DIM)
	_gun.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_gun)
	row.add_child(mid)

	var t_box := _unit_box()
	_t_portrait = t_box.get_child(0)
	_t_name = t_box.get_child(1)
	row.add_child(t_box)

	var out := Styles.vbox(4)
	out.alignment = BoxContainer.ALIGNMENT_CENTER
	out.custom_minimum_size = Vector2(150, 0)
	_word = Styles.caps("", 24, Styles.TEXT)
	_word.mouse_filter = Control.MOUSE_FILTER_PASS
	out.add_child(_word)
	var hp_row := Styles.hbox(8)
	_pips = W.HpPips.new(Vector2(7, 5), 2.0)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_pips)
	_dmg = Styles.caps("", 15, Styles.DANGER_TEXT)
	hp_row.add_child(_dmg)
	out.add_child(hp_row)
	_statuses = Styles.hbox(10)
	out.add_child(_statuses)
	row.add_child(out)
	modulate.a = 0.0
	visible = false


func _unit_box() -> VBoxContainer:
	var box := Styles.vbox(3)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var p := W.Portrait.new(PORTRAIT)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(p)
	var n := Styles.caps("", 11, Styles.DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(n)
	return box


## A new attack: `a` and `t` are {id, kind, name, soldier, color, hp, max_hp, infection};
## `icon` names the attack (Icons), `chance` its odds (0 hides them), `reaction` marks
## overwatch fire.
func begin(a: Dictionary, t: Dictionary, icon: String, chance: int, reaction := false) -> void:
	active = true
	_hold = 0.0
	attacker_id = int(a.get("id", -1))
	target_id = int(t.get("id", -1))
	_a_portrait.setup(_portrait_kind(a), a.get("color", Styles.DANGER), int(a.get("infection", 0)) if a.get("soldier", false) else 0)
	_a_name.text = str(a.get("name", "")).to_upper()
	_t_kind = _portrait_kind(t)
	_t_color = t.get("color", Styles.TEXT)
	_t_inf = int(t.get("infection", 0)) if t.get("soldier", false) else 0
	_t_portrait.setup(_t_kind, _t_color, _t_inf)
	_t_portrait.modulate = Color.WHITE
	_t_name.text = str(t.get("name", "")).to_upper()
	var hostile: bool = not a.get("soldier", false)
	_icon.set_icon("overwatch" if reaction else icon, Styles.DANGER if hostile else Styles.AMBER)
	Tips.off(_icon)
	_chance.text = "%d%%" % chance if chance > 0 else ""
	var shooting := icon == "shoot" or reaction
	_gun.text = str(a.get("gun", "")).to_upper() if shooting else ""
	_gun.visible = _gun.text != ""
	_t_hp = int(t.get("hp", 0))
	_t_max = maxi(int(t.get("max_hp", _t_hp)), 1)
	_lost = 0
	_pips.set_values(_t_max, _t_hp)
	_dmg.text = ""
	_word.text = ""
	for c in _statuses.get_children():
		c.queue_free()
	_keys.clear()
	_arrow.queue_redraw()
	visible = true


static func _portrait_kind(u: Dictionary) -> String:
	if u.get("boss", false):
		return "boss"
	return str(u.get("kind", "")) if u.get("soldier", false) else "enemy"


## The roll's outcome: "hit", "crit", "graze" or "miss".
func result(kind: String) -> void:
	var col: Color = {"crit": Styles.DANGER, "graze": Styles.GRAZE, "miss": Styles.MUTED}.get(kind, Styles.AMBER)
	_word.text = {"crit": "Crit", "graze": "Graze", "miss": "Miss"}.get(kind, "Hit").to_upper()
	_word.add_theme_color_override("font_color", col)
	_word.remove_meta(Tips.META)
	Tips.term(_word, {"crit": "crit", "graze": "graze"}.get(kind, "hit_chance"))


## Damage to the target: its pips drop to `hp` with what it lost marked.
func damage(amount: int, hp: int) -> void:
	_lost += amount
	_t_hp = maxi(hp, 0)
	# Pips mark their top `lose` filled segments red: fill to the HP before the hit.
	var lost := mini(_lost, _t_max - _t_hp)
	_pips.set_values(_t_max, _t_hp + lost, lost)
	_dmg.text = "-%d" % _lost
	if _word.text == "":
		result("hit")


## Infection the target picked up (its portrait ring fills to `value`).
func infection(value: int, gained: int) -> void:
	_t_inf = value
	_t_portrait.setup(_t_kind, _t_color, _t_inf)
	if gained > 0:
		status("infection", "+%d" % gained, "infection", Styles.TEAL)


## A status the attack left: an icon and a word (or number), hoverable when `key` is a term.
func status(key: String, text: String, icon: String, color: Color) -> void:
	if _keys.has(key):
		for c in _statuses.get_children():
			if c.get_meta("key", "") == key:
				(c.get_child(1) as Label).text = text
		return
	_keys.append(key)
	var item := Styles.hbox(4)
	item.set_meta("key", key)
	item.add_child(W.Icon.new(icon, color, 16.0, 1.8))
	item.add_child(Styles.caps(text, 13, color))
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	Tips.term(item, key)
	_statuses.add_child(item)


## The target went down (a soldier) or was killed.
func downed(soldier: bool) -> void:
	_t_portrait.modulate = Color(1, 1, 1, 0.45)
	status("down", "Down" if soldier else "Killed", "skull", Styles.DANGER)


## The action is over: hold the outcome a moment, then fade.
func release() -> void:
	if active:
		active = false
		_hold = HOLD


## Hides it at once (the fight ended, a new screen).
func clear() -> void:
	active = false
	_hold = 0.0
	_alpha = 0.0
	modulate.a = 0.0
	visible = false


func shown() -> bool:
	return visible and (active or _hold > 0.0)


## What it shows, for tests: {attacker, target, word, damage, statuses, chance}.
func summary() -> Dictionary:
	return {"attacker": attacker_id, "target": target_id, "word": _word.text, "damage": _lost,
		"statuses": _keys.duplicate(), "chance": _chance.text, "gun": _gun.text, "icon": _icon.id}


## How opaque it is now (the HUD fades the action bar under it).
func alpha() -> float:
	return _alpha


func _process(delta: float) -> void:
	if not active and _hold > 0.0:
		_hold = maxf(0.0, _hold - delta)
	var want := 1.0 if active or _hold > 0.0 else 0.0
	_alpha = move_toward(_alpha, want, delta / (0.15 if want > 0.0 else FADE))
	modulate.a = _alpha
	visible = _alpha > 0.0
	_place()


func _place() -> void:
	var parent := get_parent_area_size()
	var want := _frame.get_combined_minimum_size()
	_frame.size = want
	size = want
	# Just above the letterbox bar during a cut, above the screen's bottom edge otherwise.
	var y := parent.y - bar_height - want.y - 14.0
	position = Vector2(roundf((parent.x - want.x) * 0.5), roundf(y))


func _draw_arrow() -> void:
	var h := _arrow.size.y * 0.5
	var col := Color(_icon.color, 0.55)
	var gap := 19.0
	var cx := _arrow.size.x * 0.5
	_arrow.draw_line(Vector2(2, h), Vector2(cx - gap, h), col, 2.0, true)
	_arrow.draw_line(Vector2(cx + gap, h), Vector2(_arrow.size.x - 4, h), col, 2.0, true)
	var tip := Vector2(_arrow.size.x - 2, h)
	_arrow.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, -5), tip + Vector2(-8, 5)]), col)
