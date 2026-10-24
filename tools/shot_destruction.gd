extends SceneTree
## Destruction showcase (dev check, screenshots and the PR video): a Breacher blows a doorway
## through a wall, a Trooper shoots a fuel barrel that chains into a second one, and a Marksman's
## two frag grenades bring a roof down under a Runner.
## godot -s tools/shot_destruction.gd -- OUT_DIR            (PNG stills: OUT_DIR/destruction-*.png)
## Add `--fixed-fps 30 --write-movie x.avi` before -s to record the whole sequence.

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")
const InputController := preload("res://view/input_controller.gd")

# Roof x2..5 / y2..4 with stairs at (6, 4); half cover (12, 2) beside fuel barrels (13, 2) and
# (13, 3); a wall line on row 7 with a gap at (7, 7), a reinforced section at (13, 7), open from x 15.
const ROWS := [
	"....................",
	"....................",
	"..^^^^......=!......",
	"..^^^^.......!......",
	"..^^^^s.............",
	"....................",
	"...=................",
	"#######.#####H#.....",
	"....................",
	"..........=.........",
	"....................",
	"....................",
]

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _wait := 0
var _sol := {}
## The script: ["idle"] waits for the event queue, ["wait", n] for n frames, ["save", name],
## ["aim", soldier, ability, cell] shows the aim preview, ["act", soldier, ability, cell].
## The ability "shoot" aims the normal Shoot at a fuel barrel on `cell`.
var _steps: Array = [
	["aim", "breacher", "item:demo_charge", Vector2i(10, 7)], ["wait", 25], ["save", "1-demo-aim"],
	["act", "breacher", "item:demo_charge", Vector2i(10, 7)], ["wait", 34], ["save", "2-demo-blast"],
	["idle"], ["wait", 30], ["save", "3-doorway"],
	["aim", "trooper", "shoot", Vector2i(13, 2)], ["wait", 25], ["save", "4-barrel-aim"],
	["act", "trooper", "shoot", Vector2i(13, 2)], ["wait", 16], ["save", "5-barrel-blast"],
	["idle"], ["wait", 40], ["save", "6-barrel-after"],
	["aim", "marksman", "item:frag_grenade", Vector2i(3, 3)], ["wait", 25], ["save", "7-frag-aim"],
	["act", "marksman", "item:frag_grenade", Vector2i(3, 3)], ["idle"], ["wait", 10],
	["aim", "marksman", "item:frag_grenade", Vector2i(3, 3)], ["wait", 25], ["save", "8-frag-aim-cracked"],
	["act", "marksman", "item:frag_grenade", Vector2i(3, 3)], ["idle"], ["wait", 40], ["save", "9-roof-down"],
	["wide"], ["wait", 60], ["save", "10-aftermath"],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	root.size = Vector2i(1600, 900)
	_s = GameState.new()
	_s.rng.seed = 7
	_s.grid = Grid.from_rows(PackedStringArray(ROWS))
	_s.players.assign([0])
	_s.turn = 1
	Vision.disable(_s)
	for k in [["breacher", Vector2i(10, 8)], ["trooper", Vector2i(16, 9)], ["marksman", Vector2i(7, 6)]]:
		var u := _s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = 0
		u.actions_left = 2
		_sol[k[0]] = u
	_sol.breacher.status["pockets"] = [{"id": "demo_charge", "charges": 1}, null]
	_sol.marksman.status["pockets"] = [{"id": "frag_grenade", "charges": 2}, null]
	for k in [["runner", Vector2i(3, 3)], ["spitter", Vector2i(12, 1)], ["runner", Vector2i(14, 2)], ["runner", Vector2i(10, 5)]]:
		var e := _s.add_unit(UnitData.make(k[0], Types.Team.ENEMY), k[1])
		e.max_hp = 12
		e.hp = 12
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
	if _frames == 20:
		_view.camera_rig._target_dist = 15.0
		_view.camera_rig.focus(Vector3(9, 0, 5))
		_wait = 30
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		print("[shot-destruction] done")
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
				var path := _out.path_join("destruction-%s.png" % st[1])
				root.get_texture().get_image().save_png(path)
				print("[shot-destruction] saved ", path)
		"aim":
			_aim(_sol[st[1]], st[2], st[3])
		"act":
			_act(_sol[st[1]], st[2], st[3])
		"wide":
			_view.camera_rig._target_dist = 19.0
			_view.camera_rig.focus(Vector3(9, 0, 5))
	_steps.pop_front()
	return false


## Puts the input into cell targeting for `ability` and hovers `cell`, as a player aiming would.
func _aim(u: Unit, ability: String, cell: Vector2i) -> void:
	if ability == "shoot":   # a fuel barrel as a Shoot target: the panel and the blast preview
		_view.input.selected_id = u.id
		_view.input.targets = [cell]
		_view.input.target_idx = 0
		_view.input._set_mode(InputController.Mode.SHOOT)
		_view.camera_rig.focus(Board.cell_to_world(cell))
		return
	_view.input.pending = {"type": Types.ABILITY, "unit": u.id, "ability": ability}
	_view.input.mode = InputController.Mode.TARGET_CELL
	_view.board.mark_cells([cell], Color(0.18, 0.95, 0.78, 0.35))
	_view.input._show_blast(cell)
	_view.camera_rig.focus(Board.cell_to_world(cell))


func _act(u: Unit, ability: String, cell: Vector2i) -> void:
	_view.board.clear_overlays()
	_view.input.mode = InputController.Mode.MOVE
	_view.input.pending = {}
	u.actions_left = maxi(u.actions_left, 1)
	var a := {"type": Types.ABILITY, "unit": u.id, "ability": ability, "cell": cell}
	if ability == "shoot":
		u.aim = 100   # the showcase needs the barrel to go up
		a = {"type": Types.SHOOT, "unit": u.id, "cell": cell}
	var why := Rules.validate(_s, a)
	if why != "":
		push_error("[shot-destruction] %s rejected: %s" % [ability, why])
	_view.session.submit(a)
