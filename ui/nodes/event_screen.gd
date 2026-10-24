extends "res://ui/nodes/node_screen.gd"
## Text event: the scene, the current choice and its co-op rule, then the outcome.
## With more than one player, the host's screen closes an open choice 20 seconds after the
## first pick (missing picks take the default), like the route vote.

const CHOICE_SECONDS := 20.0

var _timer_step := ""


func _build(into: VBoxContainer) -> void:
	var s := ns()
	into.add_child(header("Event · Act %d" % run.act, EventRules.title(s), NodeUi.DIM, wallet()))
	var scene := NodeUi.panel()
	var text := NodeUi.label(EventRules.scene(run, s), 19, NodeUi.TEXT, true)
	scene.add_child(text)
	into.add_child(scene)
	if not s.results.is_empty():
		var res := NodeUi.vbox(6)
		for line in s.results:
			res.add_child(NodeUi.label(line, 16, NodeUi.DIM, true))
		into.add_child(res)
	if s.finished:
		var fight: Dictionary = s.get("fight", {})
		if not fight.is_empty():
			into.add_child(NodeUi.label("This ends in a fight: %s." % str(fight.objective).capitalize(), 17, NodeUi.BAD))
		into.add_child(footer("", true, "Continue"))
		return
	into.add_child(_choice())
	_arm_timer()


func _choice() -> Control:
	var s := ns()
	var box := NodeUi.vbox(14)
	var head := NodeUi.vbox(4)
	head.add_child(NodeUi.label(EventRules.prompt(run, s), 22))
	head.add_child(NodeUi.caption(EventRules.kind_label(run, s), NodeUi.AMBER, 14))
	box.add_child(head)
	box.add_child(_status())
	var deciders := EventRules.deciders(run, s)
	var kind: String = EventRules.step_def(s).kind
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
		var waiting := "Waiting for the others." if kind != "owner" else "Waiting for %s's owner." % EventRules._fill(run, s, "{subject}")
		box.add_child(NodeUi.label(waiting, 16, NodeUi.FAINT))
	return box


## Who has picked: live pins for a vote, "chosen" for secret and per-player picks.
func _status() -> Control:
	var s := ns()
	var row := NodeUi.hbox(18)
	var kind: String = EventRules.step_def(s).kind
	if run.present_players().size() <= 1:
		return row
	for p in EventRules.deciders(run, s):
		var t := NodeUi.player_name(session, p) + ": "
		if s.choices.has(p):
			t += _option_label(p, s.choices[p].option) if kind == "vote" else "chosen"
		elif p in s.passed:
			t += "passed"
		else:
			t += "deciding"
		row.add_child(NodeUi.label(t, 14, NodeUi.player_color(p)))
	return row


func _option_label(p: int, id: String) -> String:
	for o in EventRules.options_for(run, ns(), p):
		if o.id == id:
			return o.label
	return id


func _player_options(p: int) -> Control:
	var s := ns()
	var card := NodeUi.panel(NodeUi.player_color(p))
	card.custom_minimum_size.x = 420
	var v := NodeUi.vbox(10)
	card.add_child(v)
	if run.present_players().size() > 1:
		v.add_child(player_caption(p))
	var step := EventRules.step_def(s)
	for o in EventRules.options_for(run, s, p):
		var row := NodeUi.vbox(6)
		row.add_child(NodeUi.label(o.label.to_upper(), 19, NodeUi.TEXT if o.ok else NodeUi.FAINT))
		if o.desc != "":
			row.add_child(NodeUi.label(o.desc, 14, NodeUi.DIM, true))
		if not o.ok:
			row.add_child(NodeUi.label(o.reason, 13, NodeUi.BAD))
		elif o.target == "own_soldier":
			var picks := HFlowContainer.new()
			picks.add_theme_constant_override("h_separation", 8)
			for rec in _eligible(p, o.id):
				var b := NodeUi.button(NodeUi.soldier_title(rec))
				b.pressed.connect(submit.bind({"type": "node_choose", "player": p, "option": o.id, "soldier": rec.id}))
				picks.add_child(b)
			row.add_child(picks)
		else:
			var voted: bool = step.kind == "vote" and s.choices.get(p, {}).get("option", "") == o.id
			var b := NodeUi.button("Voted" if voted else ("Vote" if step.kind == "vote" else "Choose"), not voted)
			b.pressed.connect(submit.bind({"type": "node_choose", "player": p, "option": o.id}))
			row.add_child(b)
		v.add_child(row)
	if step.kind == "volunteer":
		var pass_b := NodeUi.button("Not me")
		pass_b.pressed.connect(submit.bind({"type": "node_pass", "player": p}))
		v.add_child(pass_b)
	return card


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
