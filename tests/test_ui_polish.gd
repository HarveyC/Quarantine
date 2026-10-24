extends TestCase
## The UI polish pass: no emoji or pictograph characters anywhere the player can see text, the
## new icons all draw, the effect-chip parser reads the event and treatment lines, and the
## title, lobby-less menu, pause menu and run-end board build without errors.

const Icons := preload("res://ui/icons.gd")
const MainMenu := preload("res://ui/main_menu.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
## Folders whose scripts hold player-facing text.
const TEXT_DIRS := ["res://ui", "res://progression", "res://nodes", "res://gear", "res://run", "res://view",
	"res://enemies", "res://combat", "res://objectives", "res://infection", "res://core"]


## Emoji, dingbats, misc symbols and the emoji presentation selector. Arrows and the middle dot
## stay allowed: the UI fonts draw them.
static func _is_emoji(c: int) -> bool:
	return (c >= 0x1F000 and c <= 0x1FAFF) or (c >= 0x2600 and c <= 0x27BF) or (c >= 0x2B00 and c <= 0x2BFF) \
		or c == 0xFE0F or c == 0x200D or (c >= 0x2300 and c <= 0x23FF)


func _scripts(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_scripts(dir + "/" + sub, out)


func test_no_emoji_in_player_facing_text() -> void:
	var files: Array = []
	for dir in TEXT_DIRS:
		_scripts(dir, files)
	assert_true(files.size() > 50, "found the game's scripts")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var line := 1
		for i in text.length():
			var c := text.unicode_at(i)
			if c == 10:
				line += 1
			elif _is_emoji(c):
				failures.append("%s:%d has emoji U+%X" % [path, line, c])
				break


func test_every_icon_draws_its_own_shape() -> void:
	# An unknown id falls through to a plain circle; every id the UI asks for must be known.
	var ids := ["solo", "coop", "online", "hotseat", "join", "leave", "continue", "play", "pause", "quick", "settings",
		"sound", "mute", "music", "ambience", "effects", "interface", "keyboard", "close", "copy", "reveal", "loadout",
		"menu", "health", "infection", "kill", "wound", "skull", "turned", "rank", "perk", "route", "turn", "vote",
		"buy", "reroll", "sell", "recruit", "patch", "purge", "train", "cure", "lock", "doctrine", "squad", "waiting",
		"trophy", "weapon", "ammo", "armor", "gadget", "hazmat", "vector", "arrow_right", "arrow_left"]
	var src := FileAccess.get_file_as_string("res://ui/icons.gd")
	for id in ids:
		assert_true(src.contains('"%s"' % id), "icon %s is drawn" % id)
	assert_eq(Icons.for_class("hazmat"), "hazmat", "hazmat class icon")
	assert_eq(Icons.for_class("vector"), "vector", "vector class icon")


func test_effect_chips_read_effect_lines() -> void:
	var e := NodeUi.effects("Outbreak -2, but the next fight has +1 enemy (the Bloom hears it too)")
	assert_eq(e.chips.size(), 2, "outbreak and enemy chips")
	assert_eq(e.chips[0][1], "+1", "enemy count first (number-first match)")
	e = NodeUi.effects("That soldier gains a random mutation and +15 Infection")
	assert_eq(e.chips.size(), 1, "one infection chip")
	assert_eq(e.chips[0][0], "infection", "infection icon")
	assert_eq(e.rest, "That soldier gains a random mutation", "the clause is lifted out of the sentence")
	e = NodeUi.effects("-30 Supplies")
	assert_eq(e.rest, "", "a pure effect leaves no text")
	e = NodeUi.effects("-25% Infection from spore zones")
	assert_eq(e.chips[0][1], "-25%", "percent kept")
	e = NodeUi.effects("Nothing happens")
	assert_true(e.chips.is_empty(), "no chips for nothing")


func test_menus_build() -> void:
	var tree: SceneTree = Engine.get_meta("test_tree")
	var m: Control = MainMenu.new()
	tree.root.add_child(m)
	m._ready()
	m.show_menu("Lost connection")
	assert_true(m.find_children("*", "Button", true, false).size() >= 7, "title buttons")
	m.free()
	var p: Control = PauseMenu.new()
	tree.root.add_child(p)
	p._ready()
	var labels := p.find_children("*", "Button", true, false).map(func(b): return b.text)
	assert_true(labels.has("Resume") and labels.has("Controls"), "pause menu buttons: %s" % str(labels))
	p.free()


func test_run_end_board_builds() -> void:
	var run := RunRules.new_run(2, 5)
	RunRules.start_run(run)
	run.phase = RunState.Phase.ENDED
	run.result = Types.Result.DEFEAT
	var view := RunView.new()
	var s := LocalSession.new()
	s.run = run
	view.session = s
	view.run = run
	var board: Control = view._summary()
	assert_eq(view.end_cards.size(), 5 + run.soldiers.size(), "stat tiles and fate cards")
	board.free()
	view.free()
	s.free()


## Solo and hot-seat open the local lobby: squad size buttons grow and shrink the squad, class
## tiles set the selected soldier, and Start run hands App the picks.
func test_local_lobby_picks_squad_size() -> void:
	var tree: SceneTree = Engine.get_meta("test_tree")
	var m: Control = MainMenu.new()
	tree.root.add_child(m)
	m._ready()
	m.show_local_lobby(1)
	m._resize_squad(1)
	assert_eq(m._local_picks[0].size(), 1, "solo down to one soldier")
	m._resize_squad(3)
	assert_eq(m._local_picks[0].size(), 3, "and back up to three")
	assert_eq(m._sel, 2, "the newest soldier is selected")
	assert_eq(m._soldier_row.get_child_count(), 3, "a tile per soldier")
	m._sel = 0
	m._set_squad(["medic", "marksman", "breacher"])
	assert_eq(m._local_plan()[0], ["medic", "marksman", "breacher"], "classes set per soldier")
	var got := []
	m.local_run_requested.connect(func(players: int, picks: Dictionary) -> void: got.append([players, picks]))
	m._start_run_btn.pressed.emit()
	assert_eq(got.size(), 1, "start run asked for")
	assert_eq(got[0][1][0].size(), 3, "with the picked squad")
	assert_eq(Profile.last_squad("solo").get(0, []).size(), 3, "remembered for next time")
	m.show_local_lobby(2)
	m._edit_player = 0
	m._resize_squad(4)
	var plan: Dictionary = m._local_plan()
	assert_eq(plan[0].size() + plan[1].size(), 4, "hot-seat shares 4 soldiers")
	assert_eq(plan[1].size(), 1, "player 2 keeps one")
	assert_eq(m._squad_meter.cols.size(), 4, "the squad meter shows all 4")
	m.free()
