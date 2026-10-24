extends "res://ui/nodes/node_screen.gd"
## Survivors: the rescue scene and the recruit. The first player to claim them takes them into
## their reserve; if nobody does, they go to the smallest reserve when everyone leaves.


func _build(into: VBoxContainer) -> void:
	var s := ns()
	into.add_child(header("Survivors · Act %d" % run.act, "Someone made it", NodeUi.HEALTH, wallet()))
	var scene := NodeUi.panel()
	scene.add_child(NodeUi.label(s.text, 19, NodeUi.TEXT, true))
	into.add_child(scene)
	var card := NodeUi.panel()
	card.custom_minimum_size.x = 420
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var v := NodeUi.vbox(10)
	card.add_child(v)
	v.add_child(NodeUi.caption("Recruit"))
	v.add_child(NodeUi.label(NodeUi.soldier_title(s.recruit).to_upper(), 26))
	v.add_child(NodeUi.label("+%d Supplies from their stash." % Survivors.SUPPLIES, 14, NodeUi.DIM))
	if s.claimed_by != -1:
		v.add_child(NodeUi.caption("Joins %s's reserve" % NodeUi.player_name(session, s.claimed_by), NodeUi.player_color(s.claimed_by), 15))
	else:
		for p in local_players():
			var t := "Take into my reserve" if local_players().size() == 1 else "Take · %s" % NodeUi.player_name(session, p)
			var b := NodeUi.button(t)
			b.pressed.connect(submit.bind({"type": "node_claim", "player": p}))
			v.add_child(b)
	into.add_child(card)
	var note := "" if s.claimed_by != -1 else "If nobody takes them, they join the smallest reserve."
	into.add_child(footer(note, true, "Move on"))
