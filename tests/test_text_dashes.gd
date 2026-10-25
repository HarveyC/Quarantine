extends TestCase
## No "---", stray "--" or em dash in any text the player reads: story lines, radio static, the combat
## log and every string literal in the game's scripts. Lines are written without dashes instead.

const EventText := preload("res://ui/event_text.gd")
## Script folders whose strings never reach the screen.
const SKIP_DIRS := ["res://tests", "res://addons", "res://tools", "res://.godot"]
## Files whose dashed strings only go to log files, never the screen.
const SKIP_FILES := ["res://platform/crash_reporter.gd"]


## "---", an em dash, or a free-standing "--" ("--seed=" style command line flags are fine).
static var _dash_re := RegEx.create_from_string("---|—|(^|[^\\w-])--([^\\w-]|$)")


func _dashed(text: String) -> bool:
	return _dash_re.search(text) != null


func _scripts(dir_path: String, out: Array) -> void:
	if dir_path in SKIP_DIRS:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if not d.begins_with("."):
			_scripts(dir_path.path_join(d), out)


func _story_lines(v: Variant, out: Array) -> void:
	if v is String:
		out.append(v)
	elif v is Array:
		for e in v:
			_story_lines(e, out)
	elif v is Dictionary:
		for k in v:
			_story_lines(v[k], out)


func test_story_text_has_no_dashes() -> void:
	var lines: Array = []
	var story: GDScript = load("res://story/story_data.gd")
	for c in story.get_script_constant_map().values():
		_story_lines(c, lines)
	assert_true(lines.size() > 50, "story text found")
	for l in lines:
		assert_true(not _dashed(l), "story line without dashes: %s" % l)
		for salt in StoryData.STATIC_EVERY:
			assert_true(not _dashed(StoryData.garble(l, salt)), "radio static without dashes: %s" % l)


func test_combat_log_phases_have_no_dashes() -> void:
	var name_of := func(_id: int) -> String: return "X"
	for ev in [{"type": "team_phase", "turn": 3}, {"type": "enemy_phase"}, {"type": "mission_end", "result": Types.Result.VICTORY}]:
		var t := EventText.describe(ev, name_of)
		assert_true(not _dashed(t) and not t.contains("==="), "log line without dash rules: %s" % t)


func test_script_strings_have_no_dashes() -> void:
	var files: Array = []
	_scripts("res://", files)
	assert_true(files.size() > 50, "scripts found")
	var re := RegEx.create_from_string("\"[^\"\\n]*\"")
	for path in files:
		if path in SKIP_FILES:
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for m in re.search_all(code):
				var lit := m.get_string()
				if lit.begins_with("\"#") or lit == "\"--\"":   # a trailing comment, or the flag prefix
					continue
				assert_true(not _dashed(lit), "%s:%d has a dashed string %s" % [path, n, lit])
