extends SceneTree
## Renders each class's weapon firing on the shot camera to PNGs (dev check for gun feel):
## godot -s tools/shot_guns.gd -- out_dir [kinds,comma,separated] [hit|miss] [frames,comma,separated] [tactical]
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3). Frames are 60 fps steps
## of the beat clock from the start of the shot (defaults catch the burst and the impacts).

const MAIN := preload("res://scenes/main.tscn")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var kinds: PackedStringArray = (args[1] if args.size() > 1 else "trooper,marksman,medic,breacher,hazmat,vector").split(",")
	var outcome: String = args[2] if args.size() > 2 else "miss"
	var frames: Array = Array((args[3] if args.size() > 3 else "48,62,80").split(",")).map(func(x: String) -> int: return int(x))
	root.size = Vector2i(1280, 720)
	for kind in kinds:
		var s := MissionView.default_mission(1234)
		Vision.disable(s)
		var a: Unit = s.living(Types.Team.PLAYER)[0]
		a.kind = kind
		a.display_name = UnitData.SOLDIERS[kind].name
		var t := _place_target(s, a, outcome == "miss")
		var v: MissionView = MAIN.instantiate()
		v.auto_start = false
		root.add_child(v)
		v.start(s, true)
		v.player.flush()
		# The software renderer under xvfb comes out much darker than a real GPU: lift it.
		for we in v.find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.ambient_light_energy = 2.2
			(we as WorldEnvironment).environment.tonemap_exposure = 1.8
		for i in 20:
			await process_frame
		v.player.set_process(false)
		if args.has("tactical"):
			v.player.cinematics = false
			v.camera_rig._target_dist = 7.0
			v.camera_rig.focus((v.view_for(a.id).position + v.view_for(t.id).position) * 0.5)
			v.camera_rig.snap()
		var hit := outcome == "hit"
		v.player.enqueue({"type": "shot", "unit": a.id, "target": t.id, "hit": hit, "graze": false,
			"crit": false, "damage": 4 if hit else 0, "chance": 64, "reaction": false})
		var f := 0
		var last: int = frames.max()
		while f <= last:
			v.player.advance(1.0 / 60.0)
			await process_frame
			if frames.has(f):
				var path := "%s/%s_%s_%d.png" % [out, kind, outcome, f]
				root.get_texture().get_image().save_png(path)
				print("[shot_guns] ", path)
			f += 1
		v.queue_free()
		await process_frame
	quit()


## Moves the nearest enemy to a cell 5-8 tiles from `a` it can see, behind cover if `cover`.
func _place_target(s: GameState, a: Unit, cover: bool) -> Unit:
	var t: Unit = s.living(Types.Team.ENEMY)[0]
	var best := t.pos
	var best_score := -INF
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			var d := a.pos.distance_to(c)
			if d < 5.0 or d > 8.0 or not s.grid.is_walkable(c) or s.unit_at(c) != null or not Combat.can_see(s, a.pos, c):
				continue
			var score := -absf(d - 6.5)
			if cover and Combat.cover_against(s.grid, c, a.pos) != Types.Cover.NONE:
				score += 10.0
			if score > best_score:
				best_score = score
				best = c
	t.pos = best
	return t
