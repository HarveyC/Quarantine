extends SceneTree
## Discovers res://tests/test_*.gd and runs every test_* method. Exits 1 on failure.


func _init() -> void:
	# Tests run before the tree is live (Engine.get_main_loop() is still null here).
	# Expose the tree so a test can add nodes to root; their _ready runs on the first frame.
	Engine.set_meta("test_tree", self)
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()
	for f in files:
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
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
