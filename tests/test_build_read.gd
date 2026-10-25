extends TestCase
## Build readability: tag jobs, class lanes, first-run tag hiding and the lobby class pairs.


func test_every_tag_has_exactly_one_job() -> void:
	for t in GearData.TAGS:
		assert_true(BuildRead.job_of(t) != "", "%s has a job" % t)
	var n := 0
	for j in BuildRead.JOBS:
		n += (BuildRead.JOB_TAGS[j] as Array).size()
	assert_eq(n, GearData.TAGS.size(), "no tag in two jobs")


func test_every_class_has_two_lane_tags() -> void:
	for k in UnitData.SOLDIERS:
		var lane := BuildRead.lane(k)
		assert_eq(lane.size(), 2, "%s lane" % k)
		for t in lane:
			assert_true(GearData.TAGS.has(t), "%s is a tag" % t)


func test_first_run_hides_off_lane_tags_until_owned() -> void:
	var shown := BuildRead.visible_tags("marksman", {}, false)
	assert_eq(shown, ["Mark", "Overwatch"] as Array[String], "lane only")
	shown = BuildRead.visible_tags("marksman", {"Burn": 1}, false)
	assert_true(shown.has("Burn"), "owning a piece reveals the tag")
	assert_eq(BuildRead.visible_tags("marksman", {}, true).size(), GearData.TAGS.size(), "switch shows all")


func test_profile_shows_all_tags_after_a_run_or_with_the_switch() -> void:
	var old := Profile.path
	Profile.path = "user://test_build_read.cfg"
	DirAccess.remove_absolute(Profile.path)
	assert_true(not Profile.tags_all_shown(), "fresh profile hides")
	Profile.set_show_all_tags(true)
	assert_true(Profile.tags_all_shown(), "switch on")
	DirAccess.remove_absolute(Profile.path)
	Profile.path = old


func test_leads_pick_the_strongest_tag_per_job() -> void:
	var l := BuildRead.leads({"Mark": 1, "Suppress": 2, "Guard": 1})
	assert_eq(l.Setup, "Suppress", "setup lead")
	assert_eq(l.Payoff, "", "no payoff")
	assert_eq(l.Sustain, "Guard", "sustain lead")


func test_pairs_form_a_ring_over_all_classes() -> void:
	assert_eq(BuildRead.PAIRS.size(), UnitData.SOLDIERS.size(), "one pair per class")
	for k in UnitData.SOLDIERS:
		assert_true(BuildRead.PAIRS.any(func(p): return p.a == k) and BuildRead.PAIRS.any(func(p): return p.b == k), "%s in the ring" % k)
	assert_eq(BuildRead.pairs_in(["marksman", "breacher", "medic"]).size(), 1, "one pair formed")
	assert_eq(BuildRead.pairs_in(["marksman", "medic"]).size(), 0, "none formed")
	assert_true(BuildRead.partners_of(["marksman"]).has("breacher") and BuildRead.partners_of(["marksman"]).has("trooper"), "both neighbours")


func test_loadout_strip_and_first_run_rows() -> void:
	var old := Profile.path
	Profile.path = "user://test_build_read2.cfg"
	DirAccess.remove_absolute(Profile.path)
	var Demo := preload("res://ui/gear/gear_demo.gd")
	var run := Demo.make_run("reward")
	var scr: Control = load("res://ui/gear/loadout_screen.gd").new()
	scr.setup(run, null)
	var r := run.get_soldier(scr._sid)
	var rows := 0
	for c in scr._tags.get_children():
		if c is PanelContainer:
			rows += 1
	var counts := GearTags.counts(r)
	assert_eq(rows, BuildRead.visible_tags(str(r.kind), counts, false).size(), "first run lists lane and owned tags")
	scr.free()
	DirAccess.remove_absolute(Profile.path)
	Profile.path = old
