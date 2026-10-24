extends SceneTree
## Before/after renders of generated maps: the whole map from high up and a closer tactical view of
## the busiest corner (where most edge walls are, else the middle). HUD and fog off.
## godot -s tools/shot_maps.gd -- out_dir tag biome:objective:seed [biome:objective:seed ...]
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3).

const MAIN := preload("res://scenes/main.tscn")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var tag: String = args[1]
	root.size = Vector2i(1600, 1000)
	for spec in args.slice(2):
		var p: PackedStringArray = spec.split(":")
		var config := MatchConfig.make(2, int(p[2]))
		config.map_spec = {"biome": p[0], "objective": p[1], "seed": int(p[2])}
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
		for c in v.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		v.camera_rig._target_dist = v.camera_rig.MAX_DIST
		v.camera_rig.focus(v.board.center())
		v.camera_rig.snap()
		for i in 30:
			await process_frame
		_save("%s/%s-%s-map.png" % [out, tag, p[0]])
		v.camera_rig._target_dist = 13.0
		v.camera_rig.focus(_busy_spot(s.grid))
		v.camera_rig.snap()
		for i in 20:
			await process_frame
		_save("%s/%s-%s-close.png" % [out, tag, p[0]])
		v.queue_free()
		await process_frame
	quit()


func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("[shot_maps] ", path)


## World point at the centre of the 8x8 window holding the most edge walls (the map centre when the
## grid has none, e.g. on builds before edge walls).
static func _busy_spot(g: Grid) -> Vector3:
	var edges: Variant = g.get("edges")
	var best := Vector2((g.width - 1) * 0.5, (g.height - 1) * 0.5)
	if edges == null or (edges as Dictionary).is_empty():
		return Vector3(best.x, 0, best.y)
	var top := -1
	for y in range(0, g.height - 7):
		for x in range(0, g.width - 7):
			var n := 0
			for k in edges:
				if k.x >= x and k.x < x + 8 and k.y >= y and k.y < y + 8:
					n += 1
			if n > top:
				top = n
				best = Vector2(x + 3.5, y + 3.5)
	return Vector3(best.x, 0, best.y)
