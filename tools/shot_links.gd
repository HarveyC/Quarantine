extends SceneTree
## Renders the link readability views: the map (colours, chevrons, letters), a hover on a cellar hatch,
## and the move range with a link exit ringed while a soldier stands near a zipline top.
## godot -s tools/shot_links.gd -- out_dir tag biome seed   (needs a real renderer, see shot_maps.gd)

const MAIN := preload("res://scenes/main.tscn")
const BoardScript := preload("res://view/board.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var tag: String = args[1]
	root.size = Vector2i(1600, 1000)
	var config := MatchConfig.make(2, int(args[3]))
	config.map_spec = {"biome": args[2], "objective": "skirmish", "seed": int(args[3]), "act": 2}
	var s := MatchConfig.build(config)
	Vision.disable(s)
	var zip: Dictionary = {}
	var cellar: Dictionary = {}
	for l in s.grid.links:
		if l.kind == "zip" and zip.is_empty():
			zip = l
		if l.kind == "cellar" and cellar.is_empty():
			cellar = l
	var v: MissionView = MAIN.instantiate()
	v.auto_start = false
	root.add_child(v)
	v.start(s, true)
	for we in v.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.ambient_light_energy *= 6.0
		(we as WorldEnvironment).environment.tonemap_exposure = 1.8
	for c in v.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	if v.fog != null:
		v.fog.visible = false
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	if not zip.is_empty():
		# Stand the soldier two tiles from the zipline top so the exit is in range.
		var near: Vector2i = zip.a
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 0), Vector2i(-1, 0)]:
			if s.grid.is_walkable(zip.a + d) and s.grid.level(zip.a + d) == s.grid.level(zip.a) and s.unit_at(zip.a + d) == null:
				near = zip.a + d
				break
		soldier.pos = near
		v.view_for(soldier.id).set_cell(near)
		v.board.show_range(Rules.move_range(s, soldier))
		if v.board.has_method("show_link_hint"):
			v.board.call("show_link_hint", zip.a)
		var path := s.grid.find_path(near, zip.b, s.occupied(soldier.id))
		var args3: bool = v.board.get_method_list().any(func(m): return m.name == "show_path" and m.args.size() >= 3)
		v.board.callv("show_path", [path, -1, near] if args3 else [path])
		await _shot(v, zip.a.lerp(zip.b, 0.5) if false else Vector2(zip.a + zip.b) * 0.5, 15.0, "%s/%s-zipline.png" % [out, tag], zip.a)
	if not cellar.is_empty():
		v.board.show_range({})
		v.board.show_path([] as Array[Vector2i])
		if v.board.has_method("show_link_hint"):
			v.board.call("show_link_hint", cellar.a)
		await _shot(v, Vector2(cellar.a + cellar.b) * 0.5, 22.0, "%s/%s-cellar.png" % [out, tag], cellar.a)
	quit()


func _shot(v: MissionView, mid: Vector2, dist: float, path: String, hint := Vector2i(-1, -1)) -> void:
	v.camera_rig._target_dist = dist
	v.camera_rig.focus(BoardScript.cell_to_world(Vector2i(roundi(mid.x), roundi(mid.y))))
	v.camera_rig.snap()
	for i in 30:
		await process_frame
	if hint.x >= 0 and v.board.has_method("show_link_hint"):   # the pointer's hover would have cleared it
		v.input.set_process(false)
		v.input.set_process_input(false)
		v.board.call("show_link_hint", hint)
		for i in 3:
			await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot_links] ", path)
