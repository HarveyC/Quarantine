extends "res://ui/nodes/node_screen.gd"
## Text event: the scene, the current choice and its co-op rule, then the outcome.
## With more than one player, the host's screen closes an open choice 20 seconds after the
## first pick (missing picks take the default), like the route vote.

const CHOICE_SECONDS := 20.0
const Icons := preload("res://ui/icons.gd")

var _timer_step := ""


const KIND_ICON := {"vote": "vote", "secret": "lock", "per_player": "solo", "volunteer": "recruit", "owner": "solo"}


func _build(into: VBoxContainer) -> void:
	var s := ns()
	into.add_child(header("Event · Act %d" % run.act, EventRules.title(s), NodeUi.DIM, wallet(), "event"))
	var main := NodeUi.vbox(22)
	into.add_child(with_squad(main))
	var scene := NodeUi.bare()
	var text := NodeUi.label(EventRules.scene(run, s), 19, NodeUi.TEXT, true)
	text.custom_minimum_size.x = 520
	scene.add_child(text)
	main.add_child(scene)
	if not s.results.is_empty():
		var res := NodeUi.vbox(8)
		for line in s.results:
			var row := NodeUi.hbox(10)
			var ic := W.Icon.new("arrow_right", NodeUi.AMBER, 16, 1.8)
			ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(ic)
			var e := NodeUi.effect_row(line, 16)
			e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(e)
			res.add_child(row)
		main.add_child(res)
	if s.finished:
		var fight: Dictionary = s.get("fight", {})
		if not fight.is_empty():
			var fr := NodeUi.hbox(10)
			fr.add_child(W.Icon.new("skirmish", NodeUi.BAD, 22, 1.9))
			fr.add_child(NodeUi.caption("Fight ahead: %s" % str(fight.objective).capitalize(), NodeUi.BAD, 18))
			main.add_child(fr)
		into.add_child(footer("", true, "Continue"))
		return
	main.add_child(_choice())
	_arm_timer()


func _choice() -> Control:
	var s := ns()
	var box := NodeUi.vbox(14)
	var head := NodeUi.hbox(16)
	var prompt := NodeUi.label(EventRules.prompt(run, s), 22, NodeUi.TEXT, true)
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt.custom_minimum_size.x = 320
	head.add_child(prompt)
	var kind: String = EventRules.step_def(s).kind
	var kl := EventRules.kind_label(run, s)
	if kl != "":
		var chip := NodeUi.chip(KIND_ICON.get(kind, "event"), kl.to_upper(), NodeUi.AMBER, 14)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
	var status := _status()
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status)
	box.add_child(head)
	var deciders := EventRules.deciders(run, s)
	var cols := HFlowContainer.new()
	cols.add_theme_constant_override("h_separation", 18)
	cols.add_theme_constant_override("v_separation", 18)
	var any := false
	for p in local_players():
		if not p in deciders:
			continue
		if kind != "vote" and (s.choices.has(p) or p in s.passed):
			continue
		if kind == "volunteer" and s.choices.size() > 0:
			continue
		cols.add_child(_player_options(p))
		any = true
	if any:
		box.add_child(cols)
	elif not local_players().is_empty():
		var waiting := "Waiting for the others" if kind != "owner" else "Waiting for %s's owner" % EventRules._fill(run, s, "{subject}")
		var w := NodeUi.hbox(10)
		w.add_child(W.Icon.new("waiting", NodeUi.FAINT, 20, 1.8))
		w.add_child(NodeUi.caption(waiting, NodeUi.FAINT, 16))
		box.add_child(w)
	return box


## Who has picked: a chip per player, with their pick shown live in a vote.
func _status() -> Control:
	var s := ns()
	var row := NodeUi.hbox(14)
	var kind: String = EventRules.step_def(s).kind
	if run.present_players().size() <= 1:
		return row
	for p in EventRules.deciders(run, s):
		var col := NodeUi.player_color(p)
		var t := NodeUi.player_name(session, p)
		var icon := "waiting"
		if s.choices.has(p):
			icon = "check"
			if kind == "vote":
				t += " · " + _option_label(p, s.choices[p].option)
		elif p in s.passed:
			icon = "close"
		var h := NodeUi.hbox(6)
		h.add_child(W.Icon.new(icon, col if icon != "waiting" else NodeUi.FAINT, 16, 1.8))
		h.add_child(NodeUi.caption(t, col, 13))
		row.add_child(h)
	return row


func _option_label(p: int, id: String) -> String:
	for o in EventRules.options_for(run, ns(), p):
		if o.id == id:
			return o.label
	return id


## One player's options: a row per option with its effects as chips and its button(s).
func _player_options(p: int) -> Control:
	var s := ns()
	# One box per player when several decide side by side; alone, the rows need no box at all.
	var many := run.present_players().size() > 1
	var card := NodeUi.panel(NodeUi.player_color(p)) if many else NodeUi.bare()
	card.custom_minimum_size.x = 560
	var v := NodeUi.vbox(12)
	card.add_child(v)
	if many:
		v.add_child(player_caption(p))
	var step := EventRules.step_def(s)
	var opts := EventRules.options_for(run, s, p)
	for i in opts.size():
		var o: Dictionary = opts[i]
		if i > 0:
			var sep := ColorRect.new()
			sep.color = NodeUi.BORDER
			sep.custom_minimum_size.y = 1
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(sep)
		var row := NodeUi.hbox(16)
		var info := NodeUi.vbox(6)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(NodeUi.title(o.label, 20, NodeUi.TEXT if o.ok else NodeUi.FAINT))
		if o.desc != "":
			info.add_child(NodeUi.effect_row(o.desc, 14))
		row.add_child(info)
		var act := NodeUi.vbox(6)
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not o.ok:
			var why := NodeUi.hbox(6)
			why.add_child(W.Icon.new("lock", NodeUi.BAD, 16, 1.7))
			why.add_child(NodeUi.label(o.reason, 13, NodeUi.BAD))
			act.add_child(why)
		elif o.target == "own_soldier":
			for rec in _eligible(p, o.id):
				var b := NodeUi.button(rec.name, true, false, NodeUi.soldier_title(rec), Icons.for_class(rec.kind))
				b.custom_minimum_size.x = 170
				b.pressed.connect(submit.bind({"type": "node_choose", "player": p, "option": o.id, "soldier": rec.id}))
				_hook(b, "%s · %s" % [o.label, rec.name], p, o.id, rec.id)
				act.add_child(b)
		else:
			var voted: bool = step.kind == "vote" and s.choices.get(p, {}).get("option", "") == o.id
			var b := NodeUi.button("Voted" if voted else ("Vote" if step.kind == "vote" else "Choose"), not voted, false, "",
				"check" if voted else ("vote" if step.kind == "vote" else "arrow_right"))
			b.custom_minimum_size.x = 150
			b.pressed.connect(submit.bind({"type": "node_choose", "player": p, "option": o.id}))
			_hook(b, o.label, p, o.id, -1)
			act.add_child(b)
		row.add_child(act)
		v.add_child(row)
	if step.kind == "volunteer":
		var pass_b := NodeUi.button("Not me", true, false, "", "close")
		pass_b.size_flags_horizontal = Control.SIZE_SHRINK_END
		pass_b.pressed.connect(submit.bind({"type": "node_pass", "player": p}))
		v.add_child(pass_b)
	return card


## Hovering `b` previews option `id` (for soldier `sid`, or -1) on the squad panel.
func _hook(b: Control, what: String, p: int, id: String, sid: int) -> void:
	if squad_panel == null:
		return
	var s := ns()
	squad_panel.hook(b, what, func() -> Dictionary: return EventRules.preview(run, s, id, p, sid))


## Soldiers of `p` the rules accept for option `id` (checked with validate, so the screen and
## the rules never disagree).
func _eligible(p: int, id: String) -> Array:
	return run.soldiers_of(p).filter(func(rec):
		return NodeRules.validate(run, {"type": "node_choose", "player": p, "option": id, "soldier": rec.id}) == "")


func _arm_timer() -> void:
	var s := ns()
	if not is_inside_tree() or run.present_players().size() <= 1 or not run.host_player in local_players():
		return
	if s.choices.is_empty() and s.passed.is_empty():
		return
	var key := "%s/%s" % [s.event, s.step]
	if _timer_step == key:
		return
	_timer_step = key
	get_tree().create_timer(CHOICE_SECONDS).timeout.connect(func():
		if not run.node_state.is_empty() and "%s/%s" % [run.node_state.event, run.node_state.step] == key and not run.node_state.finished:
			submit({"type": "node_timeout", "player": run.host_player}))
