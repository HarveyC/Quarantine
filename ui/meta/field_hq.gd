extends Control
## Field HQ, opened from the main menu: everything that carries between runs. Four tabs:
## Field Data unlocks (and classes), Severity (difficulty for the next run), the run record and
## achievements. Reads and writes the Profile directly; nothing here touches a run.

signal closed

const Styles := preload("res://ui/styles.gd")
const Widgets := preload("res://ui/widgets.gd")
const Frame := preload("res://ui/frame.gd")
const Icons := preload("res://ui/icons.gd")
const Tips := preload("res://ui/tips/tips.gd")

const TABS := {"unlocks": "Unlocks", "severity": "Severity", "record": "Record", "achievements": "Achievements"}
const PACK_ICON := {"gear": "depot", "doctrine": "flag", "mutation": "mutation"}
const PERK_ICON := {"field_kit": "ability", "serum_reserve": "serum"}
const OWNED := Styles.HP
## How each locked class unlocks, unless Progression publishes CLASS_UNLOCK_HINTS.
const CLASS_HINTS := {
	"hazmat": "Beat the act 1 boss",
	"vector": "Win a fight with a soldier at Mutating or higher who didn't Turn",
	"reaper": "Get 3 kills on adjacent enemies with one soldier in a won fight",
	"warden": "Survive a won fight after being hit 4 or more times",
}

var tab := "unlocks"
var _body: VBoxContainer
var _fd: Label
var _tab_buttons := {}


var _fit: Widgets.FitBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Styles.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(Styles.GROUND, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var fit := Widgets.FitBox.new()
	fit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit = fit
	add_child(fit)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	fit.add_child(margin)
	var root := Styles.vbox(16)
	margin.add_child(root)
	root.add_child(_header())
	var tabs := Styles.hbox(6)
	root.add_child(tabs)
	for id in TABS:
		var b := Button.new()
		b.text = TABS[id].to_upper()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(show_tab.bind(id))
		tabs.add_child(b)
		_tab_buttons[id] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = Styles.vbox(14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	show_tab(tab)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


func show_tab(id: String) -> void:
	tab = id
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == id
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_fd.text = str(Profile.field_data())
	match id:
		"unlocks": _build_unlocks()
		"severity": _build_severity()
		"record": _build_record()
		"achievements": _build_achievements()
	if _fit != null:
		_fit.refit()


func _header() -> Control:
	var row := Styles.hbox(14)
	var titles := Styles.vbox(0)
	titles.add_child(Styles.caps("Field HQ", 38, Styles.TEXT))
	titles.add_child(Styles.caps("Lantern Company · between runs", 14, Styles.MUTED, false))
	row.add_child(titles)
	row.add_child(Styles.spacer())
	var fd := Frame.new(Vector4(16, 8, 18, 8))
	fd.set_look(Styles.BG_SOFT, Styles.BORDER)
	var fd_row := Styles.hbox(10)
	fd.add_child(fd_row)
	fd_row.add_child(_icon_tile("intel", Styles.AMBER, 40))
	var fd_text := Styles.vbox(-4)
	_fd = Styles.mono("0", 28, Styles.AMBER)
	fd_text.add_child(_fd)
	fd_text.add_child(Styles.caps("Field Data", 12, Styles.MUTED))
	fd_row.add_child(fd_text)
	Tips.term(fd, "field_data")
	row.add_child(fd)
	var back := Button.new()
	back.text = "BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(120, 52)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(close)
	row.add_child(back)
	return row


# --- Unlocks ------------------------------------------------------------------------------

func _build_unlocks() -> void:
	_section("Field Data unlocks", "Earned every run, win or lose. In co-op, everyone plays with the host's unlocks.")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	var have := Profile.packs()
	var fd := Profile.field_data()
	for id in MetaUnlocks.ORDER:
		grid.add_child(_pack_card(id, have, fd))
	_section("Classes", "Unlocked by play, not Field Data.")
	var classes := Styles.hbox(12)
	_body.add_child(classes)
	var open := Progression.unlocked_classes(Profile.meta())
	for kind in UnitData.SOLDIERS:
		classes.add_child(_class_card(kind, open.has(kind)))
	_section("Loadout", "")
	var all := CheckBox.new()
	all.text = "Show all gear tags"
	all.focus_mode = Control.FOCUS_NONE
	all.button_pressed = Profile.tags_all_shown()
	all.disabled = Profile.stat("runs") > 0   # after a first run every tag shows anyway
	all.toggled.connect(func(on: bool) -> void: Profile.set_show_all_tags(on))
	Tips.term(all, "gear_tag")
	_body.add_child(all)


func _pack_card(id: String, have: Array, fd: int) -> Control:
	var p: Dictionary = MetaUnlocks.PACKS[id]
	var owned := have.has(id)
	var why := MetaUnlocks.can_buy(have, fd, id)
	var card := Frame.new(Vector4(14, 12, 14, 12))
	card.custom_minimum_size = Vector2(0, 200)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_look(Styles.BG_SOFT, OWNED.darkened(0.45) if owned else Styles.BORDER, Styles.AMBER if why == "" else Styles.BORDER_STRONG, not owned)
	var box := Styles.vbox(8)
	card.add_child(box)
	var top := Styles.hbox(10)
	box.add_child(top)
	var icon: String = PERK_ICON.get(id, PACK_ICON.get(p.kind, "ability"))
	top.add_child(_icon_tile(icon, OWNED if owned else (Styles.AMBER if why == "" else Styles.DIM), 44))
	var names := Styles.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(Styles.caps(p.short, 20, Styles.TEXT))
	names.add_child(Tips.text(p.about, 13, Styles.DIM))
	top.add_child(names)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 5)
	chips.add_theme_constant_override("v_separation", 5)
	chips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(chips)
	for c in p.content:
		chips.add_child(_content_chip(p.kind, c))
	var bottom := Styles.hbox(8)
	box.add_child(bottom)
	if owned:
		bottom.add_child(Widgets.Icon.new("check", OWNED, 20))
		bottom.add_child(Styles.caps("Unlocked", 15, OWNED))
		return card
	bottom.add_child(Widgets.Icon.new("intel", Styles.AMBER if why == "" else Styles.MUTED, 18))
	bottom.add_child(Styles.mono(str(p.cost), 18, Styles.AMBER if why == "" else Styles.MUTED))
	bottom.add_child(Styles.spacer())
	if why == "":
		var buy := Button.new()
		buy.text = "UNLOCK"
		buy.focus_mode = Control.FOCUS_NONE
		buy.custom_minimum_size = Vector2(110, 34)
		buy.add_theme_color_override("font_color", Styles.AMBER)
		buy.add_theme_stylebox_override("normal", Styles.panel_box(Styles.AMBER_DARK, Styles.AMBER))
		buy.pressed.connect(func() -> void:
			if Profile.buy(id) == "":
				show_tab("unlocks"))
		bottom.add_child(buy)
	else:
		bottom.add_child(Styles.caps(why, 13, Styles.MUTED, false))
	return card


func _content_chip(kind: String, id: String) -> Control:
	var text := id
	var col := Styles.BORDER_STRONG
	var tip := ""
	var terms: Array = []
	match kind:
		"gear":
			if GearData.exists(id):
				text = GearData.item_name(id)
				tip = GearData.desc(id)
				var tags := GearData.tags_of(id)
				if not tags.is_empty():
					col = GearData.tag_color(tags[0])
					terms.append("tag_" + str(tags[0]).to_lower())
		"doctrine":
			text = GearData.DOCTRINES.get(id, {}).get("name", id)
			tip = str(GearData.DOCTRINES.get(id, {}).get("desc", ""))
			col = Styles.AMBER.darkened(0.3)
		"mutation":
			text = MutationData.get_def(id).get("name", id)
			tip = str(MutationData.get_def(id).get("desc", ""))
			col = Styles.TEAL_DIM
			terms.append("mutation")
	var p := PanelContainer.new()
	var sb := Styles.panel_box(Color(col, 0.12), Color(col, 0.7))
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE if tip == "" else Control.MOUSE_FILTER_PASS
	p.tooltip_text = tip
	Tips.terms(p, terms)
	p.add_child(Styles.label(text, 12, Styles.TEXT))
	return p


func _class_card(kind: String, open: bool) -> Control:
	var card := Frame.new(Vector4(10, 10, 12, 10))
	card.custom_minimum_size = Vector2(178, 0)
	card.set_look(Styles.BG_SOFT, Styles.BORDER, Styles.AMBER, open)
	var row := Styles.hbox(10)
	card.add_child(row)
	var glyph := Widgets.glyph(kind, Styles.TEXT if open else Styles.MUTED, 42)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(glyph)
	var box := Styles.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(Styles.caps(UnitData.SOLDIERS[kind].name, 17, Styles.TEXT if open else Styles.MUTED))
	if open:
		box.add_child(Styles.caps("Ready", 12, OWNED))
	else:
		box.add_child(Tips.text(_class_hint(kind), 12, Styles.DIM, 110))
	row.add_child(box)
	return card


func _class_hint(kind: String) -> String:
	var consts: Dictionary = (Progression as Script).get_script_constant_map()
	var hints: Dictionary = consts.get("CLASS_UNLOCK_HINTS", CLASS_HINTS)
	return hints.get(kind, CLASS_HINTS.get(kind, "Unlocked by play"))


# --- Severity -------------------------------------------------------------------------------

func _build_severity() -> void:
	var top := Profile.severity_max()
	var pick := Profile.severity()
	_section("Severity", "Harder runs for more Field Data. Each level keeps every rule below it. Beat the Source to unlock the next level.")
	var ladder := Styles.hbox(6)
	_body.add_child(ladder)
	for n in Severity.MAX + 1:
		ladder.add_child(_severity_step(n, pick, top))
	var detail := Frame.new(Vector4(20, 16, 20, 18))
	detail.set_look(Styles.BG_SOFT, Styles.BORDER)
	_body.add_child(detail)
	var box := Styles.vbox(10)
	detail.add_child(box)
	var head := Styles.hbox(14)
	box.add_child(head)
	head.add_child(Tips.term(Styles.caps("Severity %d" % pick, 28, Styles.AMBER), "severity", {"value": pick}))
	if pick > 0:
		head.add_child(Styles.caps(Severity.LEVELS[pick - 1].name, 22, Styles.TEXT))
	head.add_child(Styles.spacer())
	head.add_child(Widgets.Icon.new("intel", Styles.AMBER, 20))
	head.add_child(Styles.mono("+%d%%" % roundi(Severity.FIELD_DATA_BONUS * 100 * pick), 22, Styles.AMBER))
	head.add_child(Styles.caps("Field Data", 13, Styles.MUTED))
	if pick == 0:
		box.add_child(Styles.label("The standard run. No extra rules.", 16, Styles.DIM))
	for i in pick:
		var lv: Dictionary = Severity.LEVELS[i]
		var row := Styles.hbox(12)
		row.add_child(Styles.mono("%2d" % (i + 1), 16, Styles.MUTED))
		row.add_child(Widgets.Icon.new(lv.icon, Styles.DANGER_TEXT, 22))
		var name := Styles.caps(lv.name, 16, Styles.TEXT)
		name.custom_minimum_size = Vector2(170, 0)
		row.add_child(name)
		row.add_child(Tips.text(lv.rule, 16, Styles.DIM))
		Tips.terms(row, Glossary.scan(lv.rule))
		box.add_child(row)
	if top < Severity.MAX:
		box.add_child(Styles.label("Win a run at Severity %d to unlock Severity %d." % [top, top + 1], 14, Styles.MUTED))


func _severity_step(n: int, pick: int, top: int) -> Control:
	var open := n <= top
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = n == pick
	b.disabled = not open
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 116)
	b.pressed.connect(func() -> void:
		Profile.set_severity(n)
		show_tab("severity"))
	b.tooltip_text = Severity.LEVELS[n - 1].rule if n > 0 else "The standard run. No extra rules."
	Tips.term(b, "severity", {"value": n})
	var box := Styles.vbox(4)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(box)
	var col := Styles.AMBER if n == pick else (Styles.TEXT if open else Color("39465a"))
	var num := Styles.mono(str(n), 34, col)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(num)
	var icon := Widgets.Icon.new(Severity.LEVELS[n - 1].icon if n > 0 else "check", col if open else Color("2f3a4c"), 20)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var name := Styles.keep_words(Styles.caps(Severity.LEVELS[n - 1].name if n > 0 else "Standard", 11, col if open else Color("39465a")))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name)
	# A Button doesn't size to what it holds: grow the step to fit two-line names.
	box.minimum_size_changed.connect(func() -> void:
		b.custom_minimum_size.y = maxf(116.0, box.get_combined_minimum_size().y + 12.0))
	return b


# --- Record ---------------------------------------------------------------------------------

func _build_record() -> void:
	var st := Profile.stats()
	_section("Service record", "")
	var tiles := Styles.hbox(10)
	_body.add_child(tiles)
	var rate := "%d%%" % roundi(100.0 * st.wins / st.runs) if st.runs > 0 else "-"
	for t in [["Runs", str(st.runs), "flag"], ["Wins", str(st.wins), "check"], ["Win rate", rate, "intel"],
			["Fights won", str(st.fights_won), "skirmish"], ["Bosses", str(st.bosses_killed), "boss"],
			["Nests", str(st.nests_cleared), "nest"], ["Turned", str(st.soldiers_turned), "enemy"],
			["Best Severity", str(st.highest_severity) if st.wins > 0 else "-", "outbreak"],
			["Field Data earned", str(st.field_data_earned), "intel"]]:
		tiles.add_child(_stat_tile(t[0], t[1], t[2]))
	_section("Recent runs", "")
	var log := Profile.run_log()
	if log.is_empty():
		_body.add_child(Styles.label("No runs yet. Finished runs show up here, newest first.", 16, Styles.DIM))
	for e in log:
		_body.add_child(_run_row(e))


func _stat_tile(label: String, value: String, icon: String) -> Control:
	var f := Frame.new(Vector4(12, 10, 12, 10))
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.set_look(Styles.BG_SOFT, Styles.BORDER, Styles.AMBER, false)
	var box := Styles.vbox(2)
	f.add_child(box)
	var top := Styles.hbox(8)
	top.add_child(Widgets.Icon.new(icon, Styles.MUTED, 18))
	top.add_child(Styles.mono(value, 26, Styles.TEXT))
	box.add_child(top)
	box.add_child(Styles.caps(label, 12, Styles.MUTED))
	return f


func _run_row(e: Dictionary) -> Control:
	var won: bool = e.get("won", false)
	var f := Frame.new(Vector4(16, 8, 16, 8))
	f.set_look(Styles.BG_SOFT, Styles.BORDER, Styles.AMBER, false)
	f.stripe = OWNED if won else Styles.DANGER
	var row := Styles.hbox(16)
	f.add_child(row)
	var result := Styles.caps("Won" if won else "Lost", 18, OWNED if won else Styles.DANGER_TEXT)
	result.custom_minimum_size = Vector2(56, 0)
	row.add_child(result)
	var track := RunTrack.new()
	track.act = int(e.get("act", 1))
	track.row = int(e.get("row", 0))
	track.won = won
	row.add_child(track)
	var lvl := int(e.get("severity", 0))
	var sev := Widgets.chip("Sev %d" % lvl, Styles.DANGER.darkened(0.15) if lvl > 0 else Styles.BORDER_STRONG, lvl > 0, 12)
	sev.custom_minimum_size = Vector2(64, 0)
	row.add_child(sev)
	var glyphs := Styles.hbox(4)
	glyphs.custom_minimum_size = Vector2(4 * 34, 0)
	for k in e.get("classes", []):
		if UnitData.SOLDIERS.has(k):
			glyphs.add_child(Widgets.glyph(k, Styles.TEXT, 30))
	row.add_child(glyphs)
	row.add_child(_mini_stat("skirmish", str(e.get("fights", 0))))
	row.add_child(_mini_stat("boss", str(e.get("bosses", 0))))
	row.add_child(_mini_stat("enemy", str(e.get("turned", 0))))
	row.add_child(_mini_stat("survivors", "%d" % int(e.get("players", 1))))
	row.add_child(Styles.spacer())
	if e.has("ending"):
		row.add_child(Styles.caps(str(e.ending), 13, Styles.DIM))
	row.add_child(Widgets.Icon.new("intel", Styles.AMBER, 18))
	row.add_child(Styles.mono("+%d" % int(e.get("field_data", 0)), 18, Styles.AMBER))
	var when := Styles.label(Time.get_datetime_string_from_unix_time(int(e.get("time", 0)), true).substr(0, 16), 13, Styles.MUTED)
	when.custom_minimum_size = Vector2(130, 0)
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(when)
	return f


func _mini_stat(icon: String, value: String) -> Control:
	var b := Styles.hbox(5)
	b.custom_minimum_size = Vector2(52, 0)
	b.add_child(Widgets.Icon.new(icon, Styles.MUTED, 18))
	b.add_child(Styles.mono(value, 16, Styles.TEXT))
	return b


## How far a run got: each act's rows as segments, filled up to the act and row reached.
class RunTrack extends Control:
	var act := 1
	var row := 0
	var won := false

	func _init() -> void:
		custom_minimum_size = Vector2((RunState.BASE_ROWS + 2 * RunState.LONG_ROWS) * 11 + 2 * 8, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		var y := (size.y - 8) * 0.5
		for a in range(1, RunState.ACTS + 1):
			for r in range(1, RunState.rows_for(a) + 1):
				var done := won or a < act or (a == act and r <= row)
				var col := Styles.HP if won else (Styles.AMBER if done else Styles.HP_OFF)
				if not won and a == act and r == row:
					col = Styles.DANGER
				draw_rect(Rect2(x, y, 9, 8), col)
				x += 11
			x += 8


# --- Achievements -----------------------------------------------------------------------------

func _build_achievements() -> void:
	var have := Achievements.unlocked()
	_section("Achievements  %d / %d" % [have.size(), Achievements.DEFS.size()], "")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(grid)
	var cf := ConfigFile.new()
	cf.load(Profile.path)
	for id in Achievements.DEFS:
		var d: Dictionary = Achievements.DEFS[id]
		var got := have.has(id)
		var f := Frame.new(Vector4(12, 12, 12, 12))
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.set_look(Styles.BG_SOFT if got else Color(Styles.BG, 0.6), Styles.BORDER if got else Styles.BORDER_SOFT, Styles.AMBER, got)
		var row := Styles.hbox(12)
		f.add_child(row)
		row.add_child(_icon_tile(d.icon, Styles.AMBER if got else Color("39465a"), 52))
		var box := Styles.vbox(2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(Styles.caps(d.name, 17, Styles.TEXT if got else Styles.MUTED))
		box.add_child(Tips.text(d.desc, 13, Styles.DIM if got else Color("6b6e60")))
		if got:
			var t := int(cf.get_value("achievements", id, 0))
			box.add_child(Styles.mono(Time.get_date_string_from_unix_time(t), 11, Styles.MUTED))
		row.add_child(box)
		grid.add_child(f)


# --- helpers --------------------------------------------------------------------------------

func _section(title: String, sub: String) -> void:
	var box := Styles.vbox(2)
	box.add_child(Styles.caps(title, 20, Styles.TEXT))
	if sub != "":
		box.add_child(Styles.label(sub, 14, Styles.MUTED))
	_body.add_child(box)


func _icon_tile(id: String, col: Color, px: float) -> Control:
	var p := PanelContainer.new()
	var sb := Styles.panel_box(Styles.BG_RAISED, Color(col, 0.5), Styles.PILL)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Widgets.Icon.new(id, col, px * 0.55, 1.8)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	return p
