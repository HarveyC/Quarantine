extends SceneTree
## Stairs check (dev aid, before/after screenshots): every body kind standing on a flight of
## stairs up to a roof, a Lurker and a Runner on the roof stairs above, and a Brute on a
## collapsed-roof rubble ramp. Close views, team phase, so the enemy intent tags show too.
## godot -s tools/shot_stairs.gd -- OUT_DIR            (PNG stills: OUT_DIR/stairs-*.png)

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")

# A roof x 2..15 / y 2..4 with an upper roof x 6..9 / y 2..3; stairs s along row 5 climb north
# to the roof, stairs S on row 4 climb to the upper roof, a ramp of rubble at (13, 5).
const ROWS := [
	"....................",
	"....................",
	"..^^^^2222^^^^^^....",
	"..^^^^2222^^^^^^....",
	"..^^^^SS^S^^^^^^....",
	"..s.s.s.s.s.s.s.....",
	"....................",
	"....................",
	"....................",
	"....................",
]
const ENEMIES := [
	["lurker!", Vector2i(2, 5)], ["runner", Vector2i(4, 5)], ["burrower!", Vector2i(6, 5)],
	["brute", Vector2i(8, 5)], ["lurker", Vector2i(6, 4)], ["runner", Vector2i(9, 4)],
	["leaper", Vector2i(10, 5)], ["broodling", Vector2i(12, 5)], ["brute!", Vector2i(14, 5)],
]
const SQUAD := [["trooper", Vector2i(7, 4)], ["breacher", Vector2i(3, 7)], ["medic", Vector2i(11, 7)]]
## [file name, focus cell, camera distance]
const SHOTS := [["1-lurker", Vector2i(2, 5), 5.0], ["2-row", Vector2i(8, 5), 13.0], ["3-roof-stairs", Vector2i(7, 4), 6.0],
	["4-ramp", Vector2i(14, 5), 5.5]]

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _shot := -1
var _wait := 0
var _lamp: OmniLight3D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	_s = GameState.new()
	_s.rng.seed = 3
	_s.grid = Grid.from_rows(PackedStringArray(ROWS))
	# Roof (14, 4) came down onto (14, 5): a rubble ramp where stairs were.
	_s.grid.rubble[Vector2i(14, 5)] = "roof"
	_s.players.assign([0])
	_s.turn = 1
	Vision.disable(_s)
	for k in SQUAD:
		var u := _s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = 0
		u.actions_left = 2
	for k in ENEMIES:
		var e := _s.add_unit(EnemyRoster.make(k[0]), k[1])
		e.status.erase("hidden")
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


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _shot >= 0 and _out != "":
		var path := _out.path_join("stairs-%s.png" % SHOTS[_shot][0])
		root.get_texture().get_image().save_png(path)
		print("[shot-stairs] saved ", path)
	_shot += 1
	if _shot >= SHOTS.size():
		quit(0)
		return false
	if _shot == 0:
		_view.input.selected_id = -1   # no action bar over the steps
		_view.hud.refresh()
		_lamp = OmniLight3D.new()   # the dark biome hides the steps; a work lamp over each view
		_lamp.light_energy = 9.0
		_lamp.omni_range = 10.0
		_view.add_child(_lamp)
	var at := Board.cell_to_world(SHOTS[_shot][1])
	_lamp.position = at + Vector3(1.0, 3.0, 2.5)
	_view.camera_rig._target_dist = SHOTS[_shot][2]
	_view.camera_rig.focus(at)
	_wait = 40
	return false
