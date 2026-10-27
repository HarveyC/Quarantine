extends SceneTree
## Mark showcase (dev check and PR screenshots): a Marksman Marks one of three enemies.
## godot -s tools/shot_marks.gd -- OUT_DIR            (PNG stills: OUT_DIR/marks-*.png)

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")
const InputController := preload("res://view/input_controller.gd")

const ROWS := [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
]

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _wait := 0
var _sol := {}
var _foes := []
var _steps: Array = [
	["wait", 30], ["idle"], ["save", "1-before"],
	["tag"], ["wait", 6], ["save", "2-beat"], ["idle"], ["wait", 40], ["save", "3-after"],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	_s = GameState.new()
	_s.rng.seed = 11
	_s.grid = Grid.from_rows(PackedStringArray(ROWS))
	_s.players.assign([0])
	Vision.disable(_s)
	for k in [["trooper", Vector2i(6, 6)], ["marksman", Vector2i(4, 7)], ["medic", Vector2i(3, 5)]]:
		var u := _s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = 0
		_sol[k[0]] = u
	for k in [["runner", Vector2i(10, 5)], ["spitter", Vector2i(11, 7)], ["brute", Vector2i(9, 3)]]:
		_foes.append(_s.add_unit(EnemyRoster.make(k[0]), k[1]))
	GearTags.set_progression(null)
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.state = _s
	_view = MAIN.instantiate()
	_view.auto_start = false
	_view.session = l
	root.add_child(_view)
	_view.start(_s, true)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	if _frames == 10:
		_view.camera_rig._target_dist = 14.0
		_view.camera_rig.focus(Board.cell_to_world(Vector2i(8, 6)))
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		print("[shot-marks] done")
		quit(0)
		return false
	var st: Array = _steps[0]
	match str(st[0]):
		"idle":
			if _view.player.is_busy():
				return false
		"wait":
			_wait = int(st[1])
		"save":
			if _out != "":
				var path := _out.path_join("marks-%s.png" % st[1])
				root.get_texture().get_image().save_png(path)
				print("[shot-marks] saved ", path)
		"tag":
			var u: Unit = _sol["marksman"]
			u.actions_left = maxi(u.actions_left, 2)
			_view.session.submit({"type": Types.ABILITY, "unit": u.id, "ability": "tag", "target": _foes[0].id})
	_steps.pop_front()
	return false
