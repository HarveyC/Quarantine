extends "res://ui/nodes/node_screen.gd"
## Survivors: the rescue scene and the recruit. The first player to claim them takes them into
## their reserve; if nobody does, they go to the smallest reserve when everyone leaves.


func _build(into: VBoxContainer) -> void:
	var s := ns()
	into.add_child(header("Survivors · Act %d" % run.act, "Someone made it", NodeUi.HEALTH, wallet(), "survivors"))
	var scene := NodeUi.bare()
	scene.add_child(NodeUi.label(s.text, 19, NodeUi.TEXT, true))
	into.add_child(scene)
	var card := NodeUi.panel()
	card.custom_minimum_size.x = 420
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var v := NodeUi.vbox(10)
	card.add_child(v)
	var head := NodeUi.hbox(14)
	head.add_child(W.glyph(s.recruit.kind, NodeUi.HEALTH, 58.0))
	var names := NodeUi.vbox(2)
	names.add_child(NodeUi.caption("Recruit", NodeUi.FAINT, 12))
	names.add_child(NodeUi.title(s.recruit.name, 30))
	names.add_child(NodeUi.label(UnitData.SOLDIERS.get(s.recruit.kind, {}).get("name", ""), 14, NodeUi.DIM))
	head.add_child(names)
	v.add_child(head)
	v.add_child(NodeUi.effect_row("+%d Supplies" % Survivors.SUPPLIES, 15))
	if s.claimed_by != -1:
		var j := NodeUi.hbox(8)
		j.add_child(W.Icon.new("check", NodeUi.player_color(s.claimed_by), 18, 2.0))
		j.add_child(NodeUi.caption("Joins %s's reserve" % NodeUi.player_name(session, s.claimed_by), NodeUi.player_color(s.claimed_by), 15))
		v.add_child(j)
	else:
		for p in local_players():
			var t := "Take into my reserve" if local_players().size() == 1 else "Take · %s" % NodeUi.player_name(session, p)
			var b := NodeUi.button(t, true, false, "", "recruit")
			b.pressed.connect(submit.bind({"type": "node_claim", "player": p}))
			v.add_child(b)
	into.add_child(card)
	var f := footer("", true, "Move on")
	if s.claimed_by == -1:
		f.tooltip_text = "If nobody takes them, they join the smallest reserve."
	into.add_child(f)
