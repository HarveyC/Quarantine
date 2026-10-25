extends Control
## End-of-fight debrief in a run. A short beat on the last thing that happened (the final kill or
## the objective; longer after a loss, while the camera shows what lost it), then a "Mission
## complete" / "Mission failed" / "Squad lost" banner over the battlefield that names the cause of a
## loss, with each soldier's kills, wounds and Infection, then `finished` so the app fades into the
## rewards.
##
## Skippable: a key or click during the beat shows the summary at once, the next one continues;
## it also continues on its own after AUTO_CONTINUE seconds. It is local presentation only: every
## peer builds it from its own copy of the (checksummed, identical) GameState, the run has
## already moved on with the host's fight_end, and skipping only moves this player along.

signal finished

const NodeUi := preload("res://ui/nodes/node_ui.gd")
const CornerPanel := preload("res://ui/nodes/corner_panel.gd")
const Styles := preload("res://ui/styles.gd")

## Seconds the camera stays on the final beat before the banner comes in.
const HOLD := 0.9
## The same after a loss: long enough to see the overrun beacon or the last soldier fall.
const LOSS_HOLD := 2.0
const AUTO_CONTINUE := 8.0
const DIM := 0.62
## Column widths: soldier, kills, wounds, Infection, status.
const COLS := [200, 70, 90, 120, 110]

var shown := false
var done := false
var summary := {}
var _t := 0.0
var _left := 0.0
var _autoplay := false
var _dim: ColorRect
var _banner: PanelContainer
var _card: PanelContainer
var _hint: Label
var _continue: Button


func _init() -> void:
	name = "FightDebrief"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Kills, wounds and Infection for every run soldier in `s`, plus the fight's headline numbers.
static func summarize(s: GameState) -> Dictionary:
	var soldiers: Array = []
	var by_unit := {}
	for u in s.units:
		if u.status.has("sid"):
			var start_hp := int(u.status.get("start_hp", u.max_hp))
			var start_inf := int(u.status.get("start_infection", 0))
			var fate := "fit"
			if u.status.get("turned", false):
				fate = "turned"
			elif u.status.get("left_behind", false):
				fate = "left_behind"
			elif not u.is_alive():
				fate = "kia"
			elif u.hp < start_hp:
				fate = "wounded"
			var row := {"sid": u.status.sid, "unit": u.id, "name": u.display_name, "kind": u.kind,
				"player": u.owner_player, "kills": int(u.status.get("kills", 0)),
				"wounds": maxi(0, start_hp - u.hp) if u.is_alive() else start_hp,
				"hp": u.hp, "max_hp": u.max_hp, "infection": u.infection,
				"infection_gained": u.infection - start_inf, "fate": fate}
			soldiers.append(row)
			by_unit[u.id] = row
	# Turrets and decoys score for the soldier who placed them.
	for u in s.units:
		var owner := int(u.status.get("owner_unit", -1))
		if u.status.has("deployable") and by_unit.has(owner):
			by_unit[owner].kills += int(u.status.get("kills", 0))
	var kills := 0
	var infection := 0
	var turned := 0
	for r in soldiers:
		kills += r.kills
		infection += maxi(0, r.infection_gained)
		turned += 1 if r.fate == "turned" else 0
	var bonus: bool = s.result == Types.Result.VICTORY and Objectives.bonus_met(s)
	# Run fights only (their encounter names the node): what the fight did to Outbreak.
	var outbreak: Array = []
	if s.encounter.has("node"):
		outbreak = RunRules.fight_outbreak(str(s.encounter.node), str(s.encounter.get("objective", "")),
			s.result == Types.Result.VICTORY, bonus, turned)
	return {"result": s.result, "turns": s.turn, "objective": Objectives.kind(s), "cause": Objectives.loss_cause(s),
		"bonus": bonus, "kills": kills, "infection": infection, "soldiers": soldiers, "outbreak": outbreak}


## Starts the debrief for the fight that just ended in `s`. Rows go to every soldier (online too,
## so the whole squad's fight is on screen); the local players' own soldiers sort first.
func play(s: GameState, session = null, autoplay := false) -> void:
	summary = summarize(s)
	_autoplay = autoplay
	_build(session)
	shown = false
	done = false
	_t = 0.0
	_left = AUTO_CONTINUE
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if autoplay:
		_reveal(true)


## Skip: the first press shows the summary, the next continues.
func skip() -> void:
	if done:
		return
	if not shown:
		_reveal(true)
	elif _t > 0.25:
		finish()


func finish() -> void:
	if done:
		return
	done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()


func _process(delta: float) -> void:
	if not visible or done:
		return
	_t += delta
	if not shown:
		if _t >= (HOLD if summary.result == Types.Result.VICTORY else LOSS_HOLD):
			_reveal(false)
		return
	_left -= delta
	if _autoplay and _t > 0.3:
		finish()
		return
	_hint.text = "SPACE TO CONTINUE  ·  %d" % ceili(maxf(0.0, _left))
	if _left <= 0.0:
		finish()


func _input(ev: InputEvent) -> void:
	if not visible or done:
		return
	var press: bool = (ev is InputEventKey and ev.pressed and not ev.echo) or (ev is InputEventMouseButton and ev.pressed)
	if press:
		get_viewport().set_input_as_handled()
		skip()


func _reveal(instant: bool) -> void:
	shown = true
	_t = 0.0
	if instant or not is_inside_tree():
		_dim.color.a = DIM
		_banner.modulate.a = 1.0
		_card.modulate.a = 1.0
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "color:a", DIM, 0.35)
	_banner.modulate.a = 0.0
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(1.08, 1.08)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.3)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.35)
	_card.modulate.a = 0.0
	tw.tween_property(_card, "modulate:a", 1.0, 0.35).set_delay(0.3)


func _build(session) -> void:
	NodeUi.clear(self)
	var win: bool = summary.result == Types.Result.VICTORY
	_dim = ColorRect.new()
	_dim.color = Color(0.017, 0.025, 0.043, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := NodeUi.vbox(14)
	col.custom_minimum_size.x = 680
	center.add_child(col)

	_banner = NodeUi.panel(NodeUi.HEALTH if win else NodeUi.BAD, 18)
	var head := NodeUi.vbox(2)
	_banner.add_child(head)
	var title := Styles.caps(headline(summary), 54, NodeUi.TEXT if win else NodeUi.BAD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var sub := NodeUi.caption(_subtitle(win), NodeUi.DIM, 16)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	if not win and Objectives.LOSS.has(summary.cause):
		head.add_child(_cause_row(Objectives.LOSS[summary.cause]))
	col.add_child(_banner)

	_card = NodeUi.panel(Color(0, 0, 0, 0), 16)
	var body := NodeUi.vbox(8)
	_card.add_child(body)
	body.add_child(_header_row())
	var local: Array = session.local_players() if session != null and session.has_method("local_players") else []
	var rows: Array = summary.soldiers.duplicate()
	rows.sort_custom(func(a, b) -> bool:
		var am := local.has(a.player)
		var bm := local.has(b.player)
		return am and not bm if am != bm else a.unit < b.unit)
	for r in rows:
		body.add_child(_soldier_row(r, session))
	var foot := NodeUi.hbox(12)
	foot.add_child(NodeUi.caption(_totals(), NodeUi.DIM, 14))
	var ob := _outbreak_chip()
	if ob != null:
		foot.add_child(ob)
	foot.add_child(Styles.spacer())
	_hint = NodeUi.caption("", NodeUi.FAINT, 12)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_hint)
	_continue = NodeUi.button("Continue", true, true)
	_continue.custom_minimum_size.x = 140
	_continue.pressed.connect(finish)
	foot.add_child(_continue)
	body.add_child(HSeparator.new())
	body.add_child(foot)
	col.add_child(_card)
	_banner.modulate.a = 0.0
	_card.modulate.a = 0.0


## "Mission complete", "Squad lost" when nobody is left, or "Mission failed" when soldiers
## survived a lost objective.
static func headline(sum: Dictionary) -> String:
	if sum.result == Types.Result.VICTORY:
		return "Mission complete"
	return "Mission failed" if sum.get("cause", "") == "beacon" else "Squad lost"


func _subtitle(win: bool) -> String:
	var obj: String = Objectives.TEXT.get(summary.objective, "Clear the zone")
	var turns := "%d turn%s" % [summary.turns, "" if summary.turns == 1 else "s"]
	if not win:
		return "%s  ·  lost on turn %d" % [obj, summary.turns]
	return "%s  ·  %s" % [obj, turns]


## The cause of a loss: icon and headline in a red pill, the detail line under it.
func _cause_row(loss: Dictionary) -> Control:
	var col := NodeUi.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var pill := NodeUi.chip(str(loss.icon), str(loss.title).to_upper(), NodeUi.BAD, 18)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	col.add_child(gap)
	col.add_child(pill)
	var line := NodeUi.caption(str(loss.line), NodeUi.DIM, 14)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(line)
	return col


func _totals() -> String:
	var parts := ["%d kill%s" % [summary.kills, "" if summary.kills == 1 else "s"]]
	if summary.infection > 0:
		parts.append("+%d Infection" % summary.infection)
	if summary.bonus:
		parts.append("Bonus objective met")
	return "  ·  ".join(parts)


## The fight's net Outbreak change as one chip; the causes are in its tooltip.
func _outbreak_chip() -> Control:
	var changes: Array = summary.get("outbreak", [])
	if changes.is_empty():
		return null
	var net := 0
	var why: Array[String] = []
	for c in changes:
		net += int(c[0])
		var reason := str(c[1])
		why.append("%s%s %+d" % [reason.left(1).to_upper(), reason.substr(1), int(c[0])])
	var chip := NodeUi.chip("outbreak", "OUTBREAK %+d" % net, NodeUi.TEAL if net <= 0 else NodeUi.BAD, 14, "\n".join(why))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


func _header_row() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 9)   # lines up with the rows' border + padding
	var h := NodeUi.hbox(12)
	m.add_child(h)
	for i in 5:
		var l := NodeUi.caption(["Soldier", "Kills", "Wounds", "Infection", "Status"][i], NodeUi.FAINT, 12)
		l.custom_minimum_size.x = COLS[i]
		h.add_child(l)
	return m


func _soldier_row(r: Dictionary, session) -> Control:
	var p = NodeUi.panel(NodeUi.player_color(r.player), 8)
	p.marks = false
	var h := NodeUi.hbox(12)
	p.add_child(h)
	var who := NodeUi.vbox(0)
	who.custom_minimum_size.x = COLS[0]
	who.add_child(NodeUi.label(str(r.name), 15))
	if _multiplayer():
		who.add_child(NodeUi.caption(NodeUi.player_name(session, r.player), NodeUi.player_color(r.player), 11))
	h.add_child(who)
	var cells := [
		[str(r.kills), NodeUi.TEXT],
		["0" if r.wounds == 0 else "-%d HP" % r.wounds, NodeUi.DIM if r.wounds == 0 else NodeUi.BAD],
		[_infection(r), NodeUi.TEAL if r.infection_gained != 0 else NodeUi.DIM],
		[_fate(r.fate), NodeUi.BAD if r.fate in ["kia", "turned", "left_behind"] else NodeUi.DIM],
	]
	for i in cells.size():
		var l := NodeUi.label(cells[i][0], 15, cells[i][1])
		l.custom_minimum_size.x = COLS[i + 1]
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	return p


func _multiplayer() -> bool:
	return summary.soldiers.any(func(r: Dictionary) -> bool: return r.player != summary.soldiers[0].player)


func _infection(r: Dictionary) -> String:
	var g: int = r.infection_gained
	if g == 0:
		return "%d" % r.infection
	return "%s%d  (%d)" % ["+" if g > 0 else "", g, r.infection]


func _fate(f: String) -> String:
	return {"fit": "Fit", "wounded": "Wounded", "kia": "KIA", "turned": "Turned", "left_behind": "Left behind"}.get(f, f)
