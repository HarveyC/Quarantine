extends RefCounted
## The hover card for a soldier class (lobby class picker and squad tiles): role, stat bars,
## signature gun with its range profile, abilities with their cost, the passive, and how to
## unlock the class while it's locked. Shift adds the full ability text, the gun's trait and
## the gear tags the class's perks build around. Numbers come from UnitData, Weapons, Combat,
## ClassAbilities, PerkData and Vision, so the card follows any retune.
## Hook a control with Tips.soldier_class(control, kind, locked); TipCard calls build().

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const Tips := preload("res://ui/tips/tips.gd")

## Role word and one-line pitch per class.
const ROLES := {
	"trooper": ["Frontline", "Holds the line and pins enemies down for the squad."],
	"marksman": ["Long range", "Picks targets off from far away and marks them for everyone."],
	"medic": ["Support", "Keeps the squad alive and pulls {infection|Infection} back down."],
	"breacher": ["Close assault", "Kicks in the door: shotgun range, smashes cover."],
	"hazmat": ["Area denial", "Burns groups out of cover, shrugs off {infection|Infection}."],
	"vector": ["Infection user", "Feeds on {infection|Infection} to fuel {mutation|mutations}."],
	"reaper": ["Melee duelist", "Dashes in with a machete, stronger the more Infected."],
	"warden": ["Tank", "Shield and maul: stuns, guards and shelters the soldier behind."],
}

## Short one-liners for the compact card; Shift shows the ability's full rules text.
static func short_lines() -> Dictionary:
	return {
		"suppress": "Pin an enemy: -%d aim on its next shot, cancels its {overwatch}." % Combat.SUPPRESS_PENALTY,
		"tag": "{mark|Mark} an enemy: the whole squad gets +%d aim against it." % Combat.TAG_BONUS,
		"stim": "Heal %d and remove %d {infection|Infection}, self or adjacent ally." % [Combat.STIM_HEAL, Combat.STIM_CURE],
		"breach": "Never misses within %d tiles, ignores {cover} and knocks it down." % Combat.BREACH_RANGE,
		"incinerate": "Cone of fire: %d damage to everything in it, allies too." % ClassAbilities.INCINERATE_DAMAGE,
		"siphon": "Take up to %d {infection|Infection} off an ally, heal from it." % ClassAbilities.SIPHON_AMOUNT,
		"lunge": "Dash up to %d tiles and cut for %d-%d, more when Infected." % [ClassAbilities.LUNGE_REACH, ClassAbilities.BLADE_DAMAGE.x, ClassAbilities.BLADE_DAMAGE.y],
		"bash": "Hit an adjacent enemy for %d-%d, knock it back and stun it." % [ClassAbilities.MAUL_DAMAGE.x, ClassAbilities.MAUL_DAMAGE.y],
		"guard": "Bash the first enemy that steps next to you before your next turn.",
	}


## Stat bar scales: segments drawn per stat (the best class sits near the top, not at it).
const HP_SEGS := 10
const MOVE_SEGS := 8
const SIGHT_SEGS := 12
const DMG_SEGS := 8
const RANGE_TILES := 14


static func role(kind: String) -> String:
	return str(ROLES.get(kind, ["", ""])[0])


## Full ability definition (base abilities live in Combat, class abilities in ClassAbilities).
static func ability(id: String) -> Dictionary:
	return Combat.ABILITIES.get(id, ClassAbilities.ABILITIES.get(id, {}))


static func ability_icon(id: String) -> String:
	return Icons.ABILITY_ICON.get(id, "ability")


## Gear tags the class's perks build around, most common first.
static func perk_tags(kind: String) -> Array[String]:
	var count := {}
	for p in PerkData.PERKS.values():
		if p.get("class", "") == kind and str(p.get("tag", "")) != "":
			count[p.tag] = int(count.get(p.tag, 0)) + 1
	var out: Array[String] = []
	out.assign(count.keys())
	out.sort_custom(func(a, b) -> bool: return count[a] > count[b] or (count[a] == count[b] and a < b))
	return out


## Aim the signature gun adds at `d` tiles (its close bonus, or the falloff past its range).
static func range_aim(gun: Dictionary, d: float) -> int:
	return RangeStrip.aim_at(gun, d)


static func build(card: Control, box: VBoxContainer, kind: String, locked: bool, inner: float, full: bool) -> void:
	var u: Dictionary = UnitData.SOLDIERS.get(kind, {})
	if u.is_empty():
		return
	var head := Styles.hbox(10)
	var ic := W.Icon.new(Icons.for_class(kind), Styles.MUTED if locked else Styles.TEXT, 30, 2.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var names := Styles.vbox(0)
	names.add_child(Styles.caps(str(u.name), 19, Styles.TEXT))
	names.add_child(Styles.caps(role(kind), 10, Styles.MUTED, false))
	head.add_child(names)
	box.add_child(head)
	if locked:
		box.add_child(_locked_row(card, kind, inner))
	box.add_child(card.rich(str(ROLES.get(kind, ["", ""])[1]), inner, 14, Styles.DIM))
	box.add_child(_rule())

	var sight: int = Vision.KIND_SIGHT.get(kind, Vision.SOLDIER_SIGHT)
	var dmg: Array = u.damage
	box.add_child(StatRow.new("HP", int(u.max_hp), 0, HP_SEGS, Styles.HP, "%d" % u.max_hp))
	box.add_child(StatRow.new("Aim", int(round(u.aim / 10.0)), 0, 10, Styles.TEXT, "%d" % u.aim))
	box.add_child(StatRow.new("Move", int(u.mobility), 0, MOVE_SEGS, Styles.TEXT, "%d" % u.mobility))
	box.add_child(StatRow.new("Sight", sight, 0, SIGHT_SEGS, Styles.TEXT, "%d" % sight))
	box.add_child(StatRow.new("Damage", int(dmg[0]), int(dmg[1]), DMG_SEGS, Styles.TEXT, "%d-%d" % [dmg[0], dmg[1]]))
	box.add_child(_rule())

	if Weapons.starts_on_sidearm(kind):
		box.add_child(_gun_block(card, kind, inner, full, Weapons.START_GUN, "Starts with"))
		box.add_child(_gun_block(card, kind, inner, full, "", "Class gun, found in a run"))
	else:
		box.add_child(_gun_block(card, kind, inner, full))
	box.add_child(_rule())

	for id in u.abilities:
		box.add_child(_ability_row(card, str(id), inner, full))
	var pas: Dictionary = PerkData.PASSIVES.get(kind, {})
	if not pas.is_empty():
		var r := Styles.hbox(8)
		var star := W.Icon.new("perk", Styles.DIM, 18, 1.8)
		star.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		r.add_child(star)
		var col := Styles.vbox(1)
		var top := Styles.hbox(6)
		top.add_child(Styles.caps(str(pas.name), 13, Styles.TEXT))
		top.add_child(Styles.caps("passive", 9, Styles.MUTED, false))
		col.add_child(top)
		col.add_child(card.rich(str(pas.desc), inner - 26, 12, Styles.DIM))
		r.add_child(col)
		box.add_child(r)

	if full:
		var tags := perk_tags(kind)
		if not tags.is_empty():
			box.add_child(_rule())
			var row := Styles.hbox(6)
			row.add_child(Styles.caps("perks build", 10, Styles.MUTED, false))
			for t in tags.slice(0, 3):
				var key := "tag_" + str(t).to_lower()
				row.add_child(Tips.chip(key, 10) if Glossary.has(key) else Styles.caps(str(t), 10, Styles.DIM))
			box.add_child(row)


static func _locked_row(card: Control, kind: String, inner: float) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Styles.TEXT, 0.05)
	sb.border_color = Styles.BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := Styles.hbox(8)
	var lock := W.Icon.new("lock", Styles.DIM, 18, 1.8)
	lock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(lock)
	var hint := str(Progression.CLASS_UNLOCK_HINTS.get(kind, "Unlock it in a run."))
	r.add_child(card.rich("To unlock: " + hint, inner - 46, 12, Styles.TEXT))
	p.add_child(r)
	return p


static func _gun_block(card: Control, kind: String, inner: float, full: bool, gun_id := "", caption := "") -> Control:
	var id := gun_id if gun_id != "" else Weapons.id_for(kind)
	var gun := Weapons.get_gun(id)
	var v := Styles.vbox(5)
	if caption != "":
		v.add_child(Styles.caps(caption, 10, Styles.MUTED, false))
	var top := Styles.hbox(8)
	var ic := W.Icon.new("weapon", Styles.TEXT, 18, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ic)
	top.add_child(Styles.caps(str(gun.get("name", id)), 13, Styles.TEXT))
	top.add_child(Styles.spacer())
	var mag := Weapons.mag_for(id, kind)
	var mag_pips := W.AmmoPips.new(10.0)
	mag_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mag_pips.set_values(mag, mag)
	mag_pips.mouse_filter = Control.MOUSE_FILTER_PASS
	Tips.term(mag_pips, "ammo")
	top.add_child(mag_pips)
	if int(gun.get("crit", 0)) > 0:
		top.add_child(Styles.mono("+%d%% crit" % gun.crit, 11, Styles.DIM))
	var tr := str(gun.get("trait", ""))
	if tr != "":
		top.add_child(Styles.caps({"pin": "pins", "snap": "snap shots", "spread": "spread", "quarters": "close quarters", "heavy": "heavy rounds", "pierce": "pierce", "skirmish": "skirmisher", "tranq": "tranquiliser", "doorkick": "door kicker", "recoil": "recoil"}.get(tr, tr), 10, Styles.DIM))
	v.add_child(top)
	v.add_child(RangeStrip.new(gun, inner))
	if full and gun_id == "":
		v.add_child(card.rich(str(gun.get("desc", "")), inner, 12, Styles.DIM))
		var alts := Weapons.alternates_for(kind).size()
		if alts > 0:
			v.add_child(Styles.caps("%d alternate gun%s to find" % [alts, "" if alts == 1 else "s"], 10, Styles.MUTED, false))
	return v


static func _ability_row(card: Control, id: String, inner: float, full: bool) -> Control:
	var def := ability(id)
	var r := Styles.hbox(8)
	var ic := W.Icon.new(ability_icon(id), Styles.AMBER, 18, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(ic)
	var col := Styles.vbox(1)
	var top := Styles.hbox(6)
	top.add_child(Styles.caps(str(def.get("name", id)), 13, Styles.TEXT))
	top.add_child(Styles.spacer())
	top.add_child(CostPips.new(int(def.get("cost", 1))))
	var cd := int(def.get("cooldown", 0))
	if cd > 0:
		var clock := W.Icon.new("clock", Styles.MUTED, 12, 1.5)
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(clock)
		top.add_child(Styles.mono("%d" % cd, 11, Styles.MUTED))
	col.add_child(top)
	var short := short_lines()
	var line := str(def.get("desc", "")) if full or not short.has(id) else str(short[id])
	col.add_child(card.rich(line, inner - 26, 12, Styles.DIM))
	r.add_child(col)
	return r


static func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Styles.BORDER_SOFT
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Label, a row of segments (filled to `lo`, faded to `hi` for a range) and the number.
class StatRow extends Control:
	var label := ""
	var lo := 0
	var hi := 0
	var segs := 10
	var col := Color.WHITE
	var value := ""

	func _init(l: String, a: int, b: int, n: int, c: Color, v: String) -> void:
		label = l
		lo = a
		hi = b
		segs = n
		col = c
		value = v
		custom_minimum_size = Vector2(0, Styles.fs(16))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := Styles.FONT_COND
		var fs := Styles.fs(11)
		var cy := size.y * 0.5
		var base := cy + fs * 0.35
		draw_string(font, Vector2(0, base), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Styles.MUTED)
		var mono := Styles.FONT_BODY_BOLD
		var vw := 44.0
		draw_string(mono, Vector2(size.x - vw, base), value, HORIZONTAL_ALIGNMENT_RIGHT, vw, Styles.fs(12), Styles.TEXT)
		var x0 := 64.0
		var w := size.x - x0 - vw - 8.0
		var gap := 3.0
		var sw := (w - gap * (segs - 1)) / segs
		var h := 6.0
		for i in segs:
			var r := Rect2(x0 + i * (sw + gap), cy - h * 0.5, sw, h)
			var c := Styles.HP_OFF
			if i < lo:
				c = col
			elif i < hi:
				c = Color(col, 0.38)
			draw_rect(r, c)


## Action cost: one diamond per action, or a bar reading "ends turn" for all actions.
class CostPips extends Control:
	var cost := 1

	func _init(c: int) -> void:
		cost = c
		custom_minimum_size = Vector2(56 if c < 0 else 12 * maxi(c, 1), 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cy := size.y * 0.5
		if cost < 0:
			var fs := Styles.fs(9)
			draw_string(Styles.FONT_COND, Vector2(0, cy + fs * 0.35), "ENDS TURN", HORIZONTAL_ALIGNMENT_RIGHT, size.x, fs, Styles.AMBER)
			return
		for i in cost:
			var c := Vector2(size.x - 6 - i * 12, cy)
			var d := PackedVector2Array([c + Vector2(0, -4.5), c + Vector2(4.5, 0), c + Vector2(0, 4.5), c + Vector2(-4.5, 0)])
			draw_colored_polygon(d, Styles.AMBER)


## The gun's aim by distance: one cell per tile, amber where it gains aim, pink where it loses.
class RangeStrip extends Control:
	var gun := {}

	func _init(g: Dictionary, w: float) -> void:
		gun = g
		custom_minimum_size = Vector2(w, Styles.fs(30))
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	static func aim_at(g: Dictionary, d: float) -> int:
		if d <= float(g.get("close", 0.0)):
			return int(g.get("close_aim", 0))
		var past := d - float(g.get("falloff", 99.0))
		return -int(ceil(past)) * int(g.get("falloff_aim", 0)) if past > 0.0 else 0

	func _draw() -> void:
		var n: int = RANGE_TILES
		var gap := 2.0
		var cw := (size.x - gap * (n - 1)) / n
		var h := 10.0
		var fs := Styles.fs(9)
		for i in n:
			var d := float(i + 1)
			var a := aim_at(gun, d)
			var c := Styles.HP_OFF
			if a > 0:
				c = Color(Styles.AMBER, clampf(0.3 + a / 30.0, 0.3, 1.0))
			elif a < 0:
				c = Color(Styles.DANGER, clampf(0.3 + -a / 30.0, 0.3, 1.0))
			else:
				c = Color(Styles.TEXT, 0.22)
			draw_rect(Rect2(i * (cw + gap), 0, cw, h), c)
		# Labels under the strip: the close bonus at its edge and the falloff start.
		var close := float(gun.get("close", 0.0))
		var ca := int(gun.get("close_aim", 0))
		if ca != 0 and close >= 1.0:
			var x := minf(close, n) * (cw + gap) - gap
			draw_line(Vector2(x + 1, h + 1), Vector2(x + 1, h + 6), Styles.MUTED, 1.0)
			draw_string(Styles.FONT_COND, Vector2(0, h + 6 + fs), "%+d aim within %d" % [ca, int(close)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Styles.AMBER if ca > 0 else Styles.DANGER_TEXT)
		var fall := float(gun.get("falloff", 99.0))
		var right := "no falloff in sight"
		if fall < n:
			var fx := fall * (cw + gap) - gap
			draw_line(Vector2(fx + 1, h + 1), Vector2(fx + 1, h + 6), Styles.MUTED, 1.0)
			right = "-%d per tile past %d" % [int(gun.get("falloff_aim", 0)), int(fall)]
		draw_string(Styles.FONT_COND, Vector2(0, h + 6 + fs), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x, fs,
			Styles.DANGER_TEXT if fall < n else Styles.MUTED)
