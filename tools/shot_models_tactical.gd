extends SceneTree
## Dev check: the same small fight at tactical and close camera, for comparing unit models.
## godot -s tools/shot_models_tactical.gd -- OUT_PREFIX     (OUT_PREFIX-tactical.png, -mid.png, -close.png)

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")

const ROWS := [
	"....................",
	"....................",
	"......=.............",
	"..............#.....",
	"..............#.....",
	"....................",
	"........=...........",
	"....................",
	"....................",
	"....................",
]

var _out := ""
var _view: MissionView
var _frames := 0
var _shots := [["tactical", 15.0], ["mid", 9.0], ["close", 5.5]]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	var s := GameState.new()
	s.rng.seed = 11
	s.grid = Grid.from_rows(PackedStringArray(ROWS))
	s.players.assign([0])
	Vision.disable(s)
	for k in [["trooper", Vector2i(6, 6)], ["trooper", Vector2i(7, 4)], ["trooper", Vector2i(5, 4)]]:
		var u := s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = 0
	for k in [["runner", Vector2i(9, 5)], ["runner", Vector2i(10, 7)], ["brute", Vector2i(11, 4)]]:
		s.add_unit(EnemyRoster.make(k[0]), k[1])
	Encounter.setup(s, {})
	GearTags.set_progression(null)
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.state = s
	_view = MAIN.instantiate()
	_view.auto_start = false
	_view.session = l
	root.add_child(_view)
	_view.start(s, true)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	var i := (_frames - 30) / 25
	var phase := (_frames - 30) % 25
	if i >= _shots.size():
		quit(0)
		return false
	if phase == 0:
		_view.camera_rig._target_dist = _shots[i][1]
		_view.camera_rig.focus(Board.cell_to_world(Vector2i(8, 5)))
	elif phase == 22 and _out != "":
		var path := "%s-%s.png" % [_out, _shots[i][0]]
		root.get_texture().get_image().save_png(path)
		print("[shot-models] saved ", path)
	return false
