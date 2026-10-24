extends SceneTree
## Renders a generated map of each biome from the tactical camera (dev check for the act looks):
## godot -s tools/shot_biomes.gd -- out_dir [biomes,comma,separated] [objective] [seed]
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3).

const MAIN := preload("res://scenes/main.tscn")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var biomes: PackedStringArray = (args[1] if args.size() > 1 else "wall,port,bore").split(",")
	var objective: String = args[2] if args.size() > 2 else "skirmish"
	var seed := int(args[3]) if args.size() > 3 else 7
	root.size = Vector2i(1280, 720)
	for biome in biomes:
		var config := MatchConfig.make(2, seed)
		config.map_spec = {"biome": biome, "objective": objective, "seed": seed}
		var s := MatchConfig.build(config)
		Vision.disable(s)
		var v: MissionView = MAIN.instantiate()
		v.auto_start = false
		root.add_child(v)
		v.start(s, true)
		# The software renderer under xvfb comes out much darker than a real GPU: lift it.
		for we in v.find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.ambient_light_energy *= 6.0
			(we as WorldEnvironment).environment.tonemap_exposure = 1.8
		if v.fog != null:
			v.fog.visible = false
		v.camera_rig._target_dist = v.camera_rig.MAX_DIST
		v.camera_rig.focus(v.board.center())
		v.camera_rig.snap()
		for i in 30:
			await process_frame
		var path := "%s/biome_%s_%s.png" % [out, biome, objective]
		root.get_texture().get_image().save_png(path)
		print("[shot_biomes] ", path)
		v.queue_free()
		await process_frame
	quit()
