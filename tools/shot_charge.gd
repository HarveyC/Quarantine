extends SceneTree
## Charge site shots (dev check): idle labels, a soldier on a site, then armed with its fuse.
## godot -s tools/shot_charge.gd -- OUT_DIR

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _steps: Array = [["save", "1-idle"], ["step"], ["save", "2-on-site"], ["end"], ["save", "3-armed"]]
var _wait := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	var grid := MapGen.generate({"biome": "wall", "objective": "demolish", "seed": 3})
	_s = Rules.new_mission_on_grid(grid, [{"kind": "trooper", "player": 0}, {"kind": "breacher", "player": 0}], ["runner"], 3)
	Rules.start_mission(_s)
	Vision.disable(_s)
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
	if _frames < 30:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		quit(0)
		return false
	var st: Array = _steps.pop_front()
	var site: Vector2i = _s.grid.marker("charge")[0]
	match str(st[0]):
		"save":
			_view.camera_rig._target_dist = 9.0
			_view.camera_rig.focus(Board.cell_to_world(site))
			_view.hud.refresh()
			_wait = 40
			_steps.push_front(["write", st[1]])
		"write":
			root.get_texture().get_image().save_png(_out.path_join("charge-%s.png" % st[1]))
		"step":
			var u: Unit = Objectives.soldiers(_s)[0]
			u.pos = site
			_view.hud.refresh()
		"end":
			for e in _s.living(Types.Team.ENEMY):
				e.status["alerted"] = false
				e.mobility = 0
			Rules.set_ready(_s, 0, true)
			_view.player.flush()
			_view.hud.refresh()
	return false
