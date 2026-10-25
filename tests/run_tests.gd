extends SceneTree
## Discovers res://tests/test_*.gd and runs every test_* method. Exits 1 on failure.


func _init() -> void:
	# Tests run before the tree is live (Engine.get_main_loop() is still null here).
	# Expose the tree so a test can add nodes to root; their _ready runs on the first frame.
	Engine.set_meta("test_tree", self)
	# Keep the player's real profile out of the tests.
	Profile.path = "user://test_profile.cfg"
	DirAccess.remove_absolute(Profile.path)
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()
	var only := OS.get_environment("TEST_ONLY")   # e.g. TEST_ONLY=destruction runs test_destruction.gd; commas list several
	if only != "":
		var wanted := Array(only.split(","))
		files = files.filter(func(f): return wanted.any(func(w): return f.contains(w)))
	# TEST_SHARD="i/n" runs every nth file starting at i, so CI can split the suite across jobs.
	var shard := OS.get_environment("TEST_SHARD")
	if shard.contains("/"):
		var parts := shard.split("/")
		var idx := int(parts[0])
		var n := maxi(int(parts[1]), 1)
		var mine: Array = []
		for i in files.size():
			if i % n == idx:
				mine.append(files[i])
		files = mine
	for f in files:
		var t0 := Time.get_ticks_msec()
		# Every file starts from the real Progression: some tests install a fake or null one and
		# leave it, which made results depend on which files ran before (and so on CI sharding).
		GearTags.set_progression(false)
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			if not m.name.begins_with("test_"):
				continue
			total += 1
			var inst: TestCase = script.new()
			inst.call(m.name)
			if inst.failures.is_empty():
				print("  ok    %s::%s" % [f, m.name])
			else:
				failed += 1
				print("  FAIL  %s::%s" % [f, m.name])
				for msg in inst.failures:
					print("        - " + msg)
		print("  file  %s %d ms" % [f, Time.get_ticks_msec() - t0])
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
