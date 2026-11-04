extends RefCounted
## The hover card for an action button (docs style guide: one card, same parts in the same order):
## header (icon, name, kind), one effect line, an optional diagram, a fact row (cost first, then
## range, damage, cooldown), a state line when the action is blocked or cooling down, and the rest
## of the rules under Shift. Cost is only ever shown in the first fact cell, never in a sentence.
## Hook a control with Tips.action(control, action); TipCard calls build().

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Icons := preload("res://ui/icons.gd")
const TipArt := preload("res://ui/tips/tip_art.gd")
const Tips := preload("res://ui/tips/tips.gd")

## Range and damage per ability id, read from the rules constants. Anything not listed shows
## neither cell (a Mark has no damage, Hunker has no range).
static func facts_for(id: String, a: Dictionary) -> Dictionary:
	var f := {}
	match id:
		"breach": f = {"range": Combat.BREACH_RANGE, "damage": "4-6"}
		"spit": f = {"range": int(Combat.SPIT_RANGE), "damage": str(Combat.SPIT_DAMAGE)}
		"incinerate": f = {"damage": str(ClassAbilities.INCINERATE_DAMAGE)}
		"lunge": f = {"range": ClassAbilities.LUNGE_REACH, "damage": "%d-%d" % [ClassAbilities.BLADE_DAMAGE.x, ClassAbilities.BLADE_DAMAGE.y]}
		"bash": f = {"damage": "%d-%d" % [ClassAbilities.MAUL_DAMAGE.x, ClassAbilities.MAUL_DAMAGE.y]}
		"shield_charge": f = {"range": ClassAbilities.CHARGE_REACH}
		"runner_leap": f = {"range": GraftData.LEAP_RANGE}
		"disengage": f = {"range": PartingBlow.CAREFUL_RANGE}
		"stim": f = {"range": 1}
	if a.has("range") and not f.has("range"):
		f["range"] = int(a.range)
	return f


## Full cooldown in turns for an ability id (0 when it has none).
static func max_cooldown(id: String) -> int:
	var def: Dictionary = Combat.ABILITIES.get(id, ClassAbilities.ABILITIES.get(id, {}))
	return int(def.get("cooldown", 0))


## Splits a rules string into its effect line and the remaining sentences.
static func split(desc: String) -> Array:
	var s := desc.strip_edges()
	var cut := -1
	var i := 0
	while i < s.length():
		if s[i] == "." and (i + 1 >= s.length() or s[i + 1] == " ") and not (i > 0 and s[i - 1].is_valid_int() and i + 1 < s.length() and s[i + 1].is_valid_int()):
			cut = i
			break
		i += 1
	if cut < 0:
		return [s, []]
	var rest: Array = []
	for part in s.substr(cut + 1).split(". ", false):
		var p := str(part).strip_edges().trim_suffix(".")
		if p != "":
			rest.append(p + ".")
	return [s.substr(0, cut + 1), rest]


## The lines a card shows: [effect line, more lines].
static func lines(a: Dictionary) -> Array:
	var term := _term(a)
	var desc := str(a.get("desc", ""))
	var more: Array = []
	if desc == "":
		var e := Glossary.entry(term) if term != "" else {}
		return [str(e.get("line", "")), e.get("more", []).duplicate()]
	var sp := split(desc)
	more = sp[1]
	if term != "":
		more.append_array(Glossary.entry(term).get("more", []))
	return [sp[0], more]


static func has_more(a: Dictionary) -> bool:
	return not (lines(a)[1] as Array).is_empty()


static func _term(a: Dictionary) -> String:
	var k := Glossary.find(str(a.get("label", "")))
	return k if k != "" and str(Glossary.entry(k).get("kind", "")) in ["action", "ability"] else ""


static func build(card: Control, box: VBoxContainer, a: Dictionary, inner: float, expanded: bool) -> void:
	var tone := Styles.AMBER
	var head := Styles.hbox(8)
	var ic := W.Icon.new(Icons.for_action(a), tone, 18, 1.8)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	head.add_child(Styles.caps(str(a.get("label", "")), 17, tone))
	head.add_child(Styles.spacer())
	var kind := Styles.caps("Ability" if a.has("id") else "Action", 10, Styles.MUTED, false)
	kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(kind)
	box.add_child(head)
	var ls := lines(a)
	box.add_child(card.rich(str(ls[0]), inner, 14, Styles.TEXT))
	var term := _term(a)
	var art := str(Glossary.entry(term).get("art", "")) if term != "" else ""
	if TipArt.supports(art):
		var actx: Dictionary = Glossary.entry(term).get("art_ctx", {}).duplicate()
		box.add_child(TipArt.new(art, actx, tone, inner))
	var cells: Array = [_cost_cell(a)]
	var f := facts_for(str(a.get("id", a.get("key", ""))), a)
	if f.has("range"):
		cells.append([str(f.range), "Tiles", false])
	if f.has("damage"):
		cells.append([str(f.damage), "Damage", false])
	var cd := max_cooldown(str(a.get("id", "")))
	if cd > 0:
		cells.append([str(cd), "Cooldown", false])
	box.add_child(fact_row(cells, inner, tone))
	var state := ""
	var cooling := int(a.get("cooldown", 0))
	if cooling > 0:
		state = "Ready in %d turn%s" % [cooling, "" if cooling == 1 else "s"]
	elif str(a.get("reason", "")) != "":
		state = str(a.reason)
	if state != "":
		var s := Styles.hbox(7)
		s.add_child(W.Icon.new("clock" if cooling > 0 else "cross", Styles.DANGER_TEXT, 14, 1.6))
		s.add_child(card.rich(state, inner - 22, 13, Styles.DANGER_TEXT))
		box.add_child(s)
	if expanded:
		for line in ls[1]:
			var r := Styles.hbox(8)
			var dot := ColorRect.new()
			dot.color = tone
			dot.custom_minimum_size = Vector2(4, 4)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot_box := MarginContainer.new()
			dot_box.add_theme_constant_override("margin_top", 8)
			dot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot_box.add_child(dot)
			r.add_child(dot_box)
			r.add_child(card.rich(str(line), inner - 12, 13, Styles.DIM))
			box.add_child(r)


## The fact row: cells are [value, label, ...]; the first is the cost and is amber. "END" draws
## the ends-turn glyph. Shared by action cards and gear cards.
static func fact_row(cells: Array, inner: float, tone := Styles.AMBER, hover_terms := false) -> HBoxContainer:
	var row := Styles.hbox(10)
	for i in cells.size():
		var cell := Styles.vbox(0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if cells[i][0] == "END":
			cell.add_child(EndGlyph.new(tone))
		else:
			cell.add_child(Styles.mono(str(cells[i][0]), 20, tone if i == 0 else Styles.TEXT))
		var l := Styles.caps(str(cells[i][1]), 10, Styles.MUTED, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = (inner - 10 * (cells.size() - 1)) / cells.size()
		cell.add_child(l)
		var term: String = {"Cooldown": "cooldown", "Per fight": "once_per_fight", "Ends turn": "actions", "Action": "actions", "Actions": "actions"}.get(str(cells[i][1]), "")
		if term != "" and hover_terms:
			Tips.term(cell, term)
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(cell)
	return row


## Fact cells for a gear gadget or consumable (cost first, then tiles, cooldown, uses per fight);
## empty for gear that has no action.
static func gear_cells(id: String, mk: int) -> Array:
	var d: Dictionary = {}
	if GearFx.GADGETS.has(id):
		var g: Dictionary = GearFx.GADGETS[id]
		d = {"cost": g.cost, "range": g.get("range", 0.0), "cooldown": g.cooldown[mk - 1], "uses": g.uses[mk - 1]}
	elif GearFx.CONSUMABLE_USE.has(id):
		var c: Dictionary = GearFx.CONSUMABLE_USE[id]
		d = {"cost": c.cost, "range": c.get("range", 0.0), "cooldown": 0, "uses": 0}
	if d.is_empty():
		return []
	var cells: Array = [_cost_cell({"cost": d.cost})]
	if float(d.range) >= 2.0:
		cells.append([str(int(d.range)), "Tiles", false])
	if int(d.cooldown) > 0:
		cells.append([str(d.cooldown), "Cooldown", false])
	if int(d.uses) > 0:
		cells.append([str(d.uses), "Per fight", false])
	return cells


## Gear effect text without its leading limit ("Once per fight:", "Cooldown 3:"), which the fact
## row shows instead.
static func gear_effect(text: String) -> String:
	var re := RegEx.create_from_string("^(Once per fight|Twice per fight|Cooldown \\d)(, free)?: ")
	var m := re.search(text)
	if m == null:
		return text
	var rest := text.substr(m.get_end())
	return rest.substr(0, 1).to_upper() + rest.substr(1)


## Cost cell: [value, label]. "1 Action", the ends-turn glyph, or "0 Actions" when free.
static func _cost_cell(a: Dictionary) -> Array:
	var c := int(a.get("cost", 1))
	if c < 0:
		return ["END", "Ends turn", true]
	if c == 0:
		return ["0", "Actions", true]
	return [str(c), "Action" if c == 1 else "Actions", true]


## The ends-turn glyph: an arrow running into a bar.
class EndGlyph extends Control:
	var color := Color.WHITE

	func _init(col: Color) -> void:
		color = col
		custom_minimum_size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(2, y), Vector2(17, y), color, 2.4, true)
		draw_line(Vector2(11, y - 6), Vector2(17, y), color, 2.4, true)
		draw_line(Vector2(11, y + 6), Vector2(17, y), color, 2.4, true)
		draw_line(Vector2(22, y - 8), Vector2(22, y + 8), color, 2.8, true)
