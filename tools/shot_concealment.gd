extends SceneTree
## Concealment showcase (dev check and PR screenshots): the squad starts Concealed (blue screen
## edge, rings at their feet), the red ground shows where each sleeping enemy would spot them,
## hovering an enemy lifts its own area, a move path into the red shows the eye where you'd be
## seen, a smoke grenade carves a safe pocket, a Trooper walks into sight and the squad is
## Detected, then a flashbang stuns the pod.
## godot -s tools/shot_concealment.gd -- OUT_DIR            (PNG stills: OUT_DIR/concealment-*.png)

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")
const InputController := preload("res://view/input_controller.gd")

const ROWS := [
	"....................",
	"......=.............",
	"..............#.....",
	"...=..........#.....",
	"..............#.....",
	"........=...........",
	"....................",
	"...=........=.......",
	"....................",
	"....................",
	"..........=.........",
	"....................",
]

var _out := ""
var _view: MissionView
var _s: GameState
var _frames := 0
var _wait := 0
var _sol := {}
var _steps: Array = [
	["wait", 20], ["idle"], ["wait", 40], ["save", "1-start"],
	["select", "trooper"], ["hover", Vector2i(9, 7)], ["wait", 20], ["save", "2-path-spotted"],
	["hover", Vector2i(12, 6)], ["wait", 20], ["save", "3-enemy-sight"],
	["use", "marksman", "item:smoke_grenade", Vector2i(9, 7)], ["wait", 24], ["save", "4-smoke-throw"],
	["idle"], ["select", "trooper"], ["hover", Vector2i(9, 7)], ["wait", 40], ["save", "5-smoke-pocket"],
	["move", "trooper", Vector2i(10, 5)], ["until", "concealment_lost"], ["wait", 10], ["save", "6-spotted"],
	["idle"], ["wait", 20], ["save", "7-detected"],
	["use", "trooper", "item:flashbang", Vector2i(12, 6)], ["wait", 40], ["save", "8-flashbang"],
	["idle"], ["wait", 20], ["save", "9-stunned"],
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
	for k in [["trooper", Vector2i(6, 6)], ["marksman", Vector2i(4, 8)], ["medic", Vector2i(3, 6)]]:
		var u := _s.add_unit(UnitData.make(k[0], Types.Team.PLAYER), k[1])
		u.owner_player = 0
		_sol[k[0]] = u
	for k in [["runner", Vector2i(12, 6)], ["spitter", Vector2i(14, 3)], ["runner", Vector2i(14, 9)]]:
		_s.add_unit(EnemyRoster.make(k[0]), k[1])
	Encounter.setup(_s, {"concealed": true})
	GearTags.set_progression(null)
	for k in [["marksman", "smoke_grenade"], ["trooper", "flashbang"]]:
		var rec := {"id": _sol[k[0]].id, "kind": k[0]}
		Loadout.add_consumable(rec, k[1], 1)
		GearRun.apply_to_unit(_sol[k[0]], rec)
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
		_view.camera_rig._target_dist = 15.0
		_view.camera_rig.focus(Board.cell_to_world(Vector2i(10, 9)))
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		print("[shot-concealment] done")
		quit(0)
		return false
	var st: Array = _steps[0]
	match str(st[0]):
		"idle":
			if _view.player.is_busy():
				return false
		"until":
			if _view.player._cur.is_empty() or _view.player.concealed:
				return false
		"wait":
			_wait = int(st[1])
		"save":
			if _out != "":
				var path := _out.path_join("concealment-%s.png" % st[1])
				root.get_texture().get_image().save_png(path)
				print("[shot-concealment] saved ", path)
		"select":
			_view.input.selected_id = _sol[st[1]].id
			_view.input.mode = InputController.Mode.MOVE
			_view.input.refresh()
		"hover":
			if _view.player.is_busy():
				return false
			_view.input._forced_cell = st[1]
			_view.input._forced_at = _view.get_viewport().get_mouse_position()
			_view.input._update_hover(true)
		"move":
			_view.board.clear_overlays()
			_view.session.submit({"type": Types.MOVE, "unit": _sol[st[1]].id, "to": st[2]})
		"use":
			if _view.player.is_busy():
				return false
			_view.input._forced_cell = InputController.NO_CELL
			_view.board.clear_overlays()
			var u: Unit = _sol[st[1]]
			u.actions_left = maxi(u.actions_left, 1)
			_view.session.submit({"type": Types.ABILITY, "unit": u.id, "ability": st[2], "cell": st[3]})
	_steps.pop_front()
	return false
