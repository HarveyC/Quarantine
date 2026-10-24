extends SceneTree
## Renders the Field HQ tabs with a sample profile (dev check):
## godot -s tools/shot_field_hq.gd -- out_prefix   ->  out_prefix-unlocks.png, -severity, -record, -achievements

const FieldHQ := preload("res://ui/meta/field_hq.gd")


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://hq"
	Profile.path = "user://shot_profile.cfg"
	DirAccess.remove_absolute(Profile.path)
	_sample_profile()
	root.size = Vector2i(1600, 900)
	var hq := FieldHQ.new()
	root.add_child(hq)
	await process_frame
	for tab in FieldHQ.TABS:
		hq.show_tab(tab)
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s-%s.png" % [out, tab])
	DirAccess.remove_absolute(Profile.path)
	quit()


## A few finished runs, some Field Data spent, Severity 3 picked.
func _sample_profile() -> void:
	var runs := [
		[1, false, {"skirmish": 2}, [], 0, 1],
		[2, false, {"skirmish": 3, "nest": 1, "boss": 1}, [1], 0, 2],
		[1, true, {"skirmish": 4, "nest": 2, "boss": 3}, [1, 2, 3], 0, 3],
		[4, true, {"skirmish": 5, "nest": 3, "boss": 3}, [1, 2, 3], 1, 4],
		[1, false, {"skirmish": 4, "nest": 1, "boss": 2}, [1, 2], 2, 5],
		[2, true, {"skirmish": 4, "nest": 1, "boss": 3}, [1, 2, 3], 2, 6],
	]
	for r in runs:
		var run := RunRules.new_run(r[0], r[5] * 101, {"packs": [], "severity": r[4]})
		run.tally = {"fights": r[2], "boss_acts": r[3], "bonus": 2, "dead": 1 if not r[1] else 0, "turned": 1 if r[5] == 5 else 0, "lost_fights": 0}
		run.phase = RunState.Phase.ENDED
		run.result = Types.Result.VICTORY if r[1] else Types.Result.DEFEAT
		run.act = 3 if r[1] else r[3].size() + 1
		run.row = 5 if r[1] else 3
		run.meta["start_flags"] = []
		if r[5] >= 2:
			run.meta["act1_boss_beaten"] = true
		Profile.record_run(run)
	var cf := ConfigFile.new()
	cf.load(Profile.path)
	cf.set_value("field", "data", cf.get_value("field", "data", 0) + 300)
	cf.save(Profile.path)
	Profile.buy("gear_1")
	Profile.buy("field_kit")
	Profile.set_severity(3)
