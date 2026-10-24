extends SceneTree
## Renders a story scene to a PNG (dev check), part-way through its captions:
## godot -s tools/shot_story.gd -- out.png <scene> [seconds] [players]
## scene: intro | act2 | act3 | brood_mother | colonel_hale | the_source | burn | sample | carry | ending_vote

const StoryScene := preload("res://ui/story/story_scene.gd")
const Director := preload("res://ui/story/story_director.gd")
const EndingScreen := preload("res://ui/story/ending_screen.gd")

var _scene: Control
var _out := ""
var _secs := 5.0
var _t := 0.0
var _frames := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://story.png"
	var which: String = args[1] if args.size() > 1 else "intro"
	_secs = float(args[2]) if args.size() > 2 else 5.0
	var players := int(args[3]) if args.size() > 3 else 1
	root.size = Vector2i(1600, 900)
	var run := RunRules.new_run(players, 77, {"story": {"wave": 9, "runs": 2, "last_result": "won",
		"last_ending": "burn", "last_wave": 8, "lore": [StoryData.CARRY_LORE], "echoes": []}})
	for i in run.squad().size():
		run.squad()[i].infection = [10, 35, 60, 88][i % 4]
	var spec := {}
	match which:
		"intro": spec = Director.intro_spec(run)
		"act2": spec = Director.act_spec(run, 2)
		"act3": spec = Director.act_spec(run, 3)
		"burn", "sample", "carry":
			run.story.ending = which
			run.story.carrier = Story.carrier(run).get("id", -1)
			spec = Director.ending_spec(run)
		"ending_vote":
			run.seen_events.append("the_trial")
			run.story.open = true
			run.phase = RunState.Phase.REWARD
			var l := LocalSession.new()
			l.save_enabled = false
			l.run = run
			root.add_child(l)
			var bg := ColorRect.new()
			bg.color = Color(0.02, 0.025, 0.025)
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.add_child(bg)
			var es := EndingScreen.new()
			es.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.add_child(es)
			es.setup(run, l)
			_scene = es
			return
		_: spec = Director.boss_spec(run, which)
	_scene = StoryScene.new()
	root.add_child(_scene)
	_scene.play(spec)


func _process(delta: float) -> bool:
	_frames += 1
	_t += minf(delta, 0.1)
	if _t >= _secs and _frames > 20:
		root.get_texture().get_image().save_png(_out)
		print("[shot-story] saved ", _out)
		quit(0)
	return false
