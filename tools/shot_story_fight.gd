extends SceneTree
## Renders a run fight with an Echo in it, radio chatter and a Source whisper (dev check):
## godot -s tools/shot_story_fight.gd -- out.png

const MAIN := preload("res://scenes/main.tscn")
const Director := preload("res://ui/story/story_director.gd")


class Holder extends Node:
	var session: Node


var _frames := 0
var _out := ""
var _view: MissionView
var _s: GameState
var _d: CanvasLayer
var _t := 0.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://story_fight.png"
	root.size = Vector2i(1600, 900)
	var l := LocalSession.new()
	l.save_enabled = false
	root.add_child(l)
	l.run = RunRules.new_run(1, 31, {"story": {"wave": 9, "runs": 2, "lore": [],
		"echoes": [{"key": "x", "kind": "breacher", "name": "Halloran", "wave": 8}]}})
	RunRules.start_run(l.run)
	l.run.fights_won = 1
	RunAutoplay.settle(l.run, l.submit_run)
	var holder := Holder.new()
	holder.session = l
	root.add_child(holder)
	_d = Director.new()
	var d := _d
	d.app = holder
	root.add_child(d)
	var node: int = l.run.reachable_nodes()[0]
	l.submit_run({"type": RunRules.VOTE, "player": 0, "node": node})
	_s = l.state
	var echo: Unit = _s.units.filter(func(u: Unit) -> bool: return u.status.has("echo"))[0]
	# stand the Echo where the squad can see it
	echo.pos = Rules._nearest_free(_s, _s.living(Types.Team.PLAYER)[0].pos + Vector2i(2, 2))
	Vision.refresh(_s)
	_view = MAIN.instantiate()
	_view.auto_start = false
	_view.session = l
	root.add_child(_view)
	_view.start(_s, true)
	_view.player.flush()


func _process(delta: float) -> bool:
	_frames += 1
	_t += delta
	if _frames == 5:
		var u: Unit = _s.living(Types.Team.PLAYER)[0]
		Infection.add(_s, u, 55)
		_d._bark("echo", {"name": "Halloran", "wave": 8})
		_d._bark("contact", {})
	if _frames > 30 and _t > 3.0:
		root.get_texture().get_image().save_png(_out)
		print("[shot-story-fight] saved ", _out)
		quit(0)
	return false
