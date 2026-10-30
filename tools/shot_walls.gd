extends SceneTree
## Wall look check (dev): a reinforced wall block beside a thin wall room, before and after a demo
## charge opens the thin wall.
## godot -s tools/shot_walls.gd -- OUT_DIR     (PNG stills: OUT_DIR/walls-*.png)

const MAIN := preload("res://scenes/main.tscn")

# Double resolution (see Grid.from_edge_rows): a block of reinforced wall at x 1..3, y 4..6 and
# a thin walled room at x 6..10, y 1..3 with a window and a doorway.
const ROWS := [
	"+ + + + + + + + + + + + +",
	" . . . . . . . . . . . . ",
	"+ + + + + + +-+-+-+-+-+ +",
	" . . . . . .|. . . . .|. ",
	"+ + + + + + + + + + + + +",
	" . . . . . .|. . . . .|. ",
	"+ + + + + + + + + + + + +",
	" . . . . . .|. . . . .|. ",
	"+ + + + + + +o+-+d+-+-+ +",
	" . # # # . . . . . . . . ",
	"+ + + + + + + + + + + + +",
	" . # # # . . . . . . . . ",
	"+ + + + + + + + + + + + +",
	" . # # # . . . . . . . . ",
	"+ + + + + + + + + + + + +",
	" . . . . . . . . . . . . ",
	"+ + + + + + + + + + + + +",
]

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _stage := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	_s = GameState.new()
	_s.rng.seed = 7
	_s.grid = Grid.from_edge_rows(PackedStringArray(ROWS))
	_s.players.assign([0])
	_s.turn = 1
	Vision.disable(_s)
	var b := _s.add_unit(UnitData.make("breacher", Types.Team.PLAYER), Vector2i(7, 4))
	b.owner_player = 0
	b.actions_left = 2
	b.status["pockets"] = [{"id": "demo_charge", "charges": 1}, null]
	var t := _s.add_unit(UnitData.make("trooper", Types.Team.PLAYER), Vector2i(5, 5))
	t.owner_player = 0
	var e := _s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 2))
	e.status["alerted"] = true
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.state = _s
	_view = MAIN.instantiate()
	_view.auto_start = false
	_view.session = l
	root.add_child(_view)
	_view.start(_s, true)
	_view.player.flush()
	# The software renderer under xvfb comes out much darker than a real GPU: lift it.
	for we in _view.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.ambient_light_energy *= 6.0
		(we as WorldEnvironment).environment.tonemap_exposure = 1.8
	if _view.fog != null:
		_view.fog.visible = false
	for c in _view.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_view.camera_rig._target_dist = 13.0
		_view.camera_rig.focus(Vector3(6, 0, 3.5))
	if _frames == 70 and _stage == 0:
		_save("1-both")
		_stage = 1
		_view.session.submit({"type": Types.ABILITY, "unit": _s.units[0].id, "ability": "item:demo_charge", "cell": Vector2i(7, 3)})
	if _frames == 140 and _stage == 1:
		_save("2-breached")
		quit(0)
	return false


func _save(name: String) -> void:
	if _out != "":
		var path := _out.path_join("walls-%s.png" % name)
		root.get_texture().get_image().save_png(path)
		print("[shot-walls] saved ", path)
