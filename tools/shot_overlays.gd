extends SceneTree
## Map markings showcase (dev check and PR screenshots): every floor marking on one small map
## (move range, spores, fire, acid, the evac pad with its label, enemy sight while Concealed),
## the map key listing them, hover cards for a spore tile and a ladder, and a grenade's blast.
## godot -s tools/shot_overlays.gd -- OUT_DIR            (PNG stills: OUT_DIR/overlays-*.png)

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")
const InputController := preload("res://view/input_controller.gd")
const Tips := preload("res://ui/tips/tips.gd")

const ROWS := [
	"....................",
	"....................",
	"....^^^^^...........",
	"....^^^^^......#....",
	"....^^^^^/.....#....",
	"....s=.........#....",
	"...........!........",
	"....................",
	"......=......=......",
	"....................",
	"....................",
	"....................",
]

const SPORES := [Vector2i(9, 7), Vector2i(10, 7), Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8), Vector2i(10, 9)]
const FIRE := [Vector2i(12, 5), Vector2i(13, 5), Vector2i(13, 6)]
const ACID := [Vector2i(4, 9), Vector2i(5, 9), Vector2i(5, 10)]
const EVAC := [Vector2i(16, 9), Vector2i(17, 9), Vector2i(16, 10), Vector2i(17, 10)]

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _wait := 0
var _sol := {}
var _steps: Array = [
	["wait", 30], ["idle"], ["select", "trooper"], ["hover", Vector2i(7, 9)], ["wait", 30], ["save", "1-overview"],
	["hover", Vector2i(10, 8)], ["wait", 10], ["card"], ["wait", 20], ["save", "2-spore-card"],
	["close"], ["hover", Vector2i(9, 4)], ["wait", 10], ["card"], ["wait", 20], ["save", "3-ladder-card"],
	["close"], ["hover", Vector2i(16, 10)], ["wait", 10], ["card"], ["wait", 20], ["save", "4-evac-card"],
	["close"], ["aim", "item:frag_grenade"], ["hover", Vector2i(11, 6)], ["wait", 20], ["save", "5-blast"],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	_s = GameState.new()
	_s.rng.seed = 11
	_s.grid = Grid.from_rows(PackedStringArray(ROWS))
	_s.grid.objective = "extract"
	_s.grid.markers["evac"] = EVAC
	_s.players.assign([0])
	Vision.disable(_s)
	for k in [["trooper", Vector2i(6, 9)], ["marksman", Vector2i(4, 7)], ["medic", Vector2i(3, 8)]]:
		var u := _s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = 0
		_sol[k[0]] = u
	_s.add_unit(EnemyRoster.make("runner"), Vector2i(15, 3))
	Encounter.setup(_s, {"concealed": true})
	Hazards.add(_s, SPORES, "spore", Hazards.PERMANENT)
	Hazards.add(_s, FIRE, "fire", 3)
	Hazards.add(_s, ACID, "acid", 3)
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
		_view.camera_rig._target_dist = 21.0
		_view.camera_rig.focus(Board.cell_to_world(Vector2i(11, 8)))
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		print("[shot-overlays] legend: ", _view.hud.map_key.shown())
		print("[shot-overlays] done")
		quit(0)
		return false
	var st: Array = _steps[0]
	var tips: Node = root.get_node_or_null("TermTips")
	match str(st[0]):
		"idle":
			if _view.player.is_busy():
				return false
		"wait":
			_wait = int(st[1])
		"save":
			if _out != "":
				var path := _out.path_join("overlays-%s.png" % st[1])
				root.get_texture().get_image().save_png(path)
				print("[shot-overlays] saved ", path)
		"select":
			_view.input.selected_id = _sol[st[1]].id
			_view.input.mode = InputController.Mode.MOVE
			_view.input.refresh()
		"hover":
			_view.input._forced_cell = st[1]
			_view.input._forced_at = _view.get_viewport().get_mouse_position()
			_view.input._update_hover(true)
		"card":
			# What TermTips shows after resting on the tile, opened at the tile on screen.
			var cell: Vector2i = _view.input._forced_cell
			var tip: Dictionary = _view.input.tile_tip(Vector2.ZERO)
			print("[shot-overlays] ", cell, " -> ", tip.get("terms", []))
			if tips != null and not tip.is_empty():
				tips._world.set_meta(Tips.META, tip)
				var at: Vector2 = _view.camera_rig.camera.unproject_position(Board.cell_to_world(cell))
				tips.show_for(tips._world, at + Vector2(24, 18))
		"close":
			if tips != null:
				tips.close_all()
		"aim":
			_view.input.pending = {"ability": st[1]}
			_view.input.mode = InputController.Mode.TARGET_CELL
			_view.input.refresh()
	_steps.pop_front()
	return false
