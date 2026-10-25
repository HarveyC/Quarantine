extends SceneTree
## Side-on renders of a Trooper shooting at each kind of target, to check that the rifle and
## the rounds go where the target's body really is (egg sacs on the floor, the floating
## Drifter, targets on a roof or below one) rather than at a fixed chest height:
## godot -s tools/shot_aim.gd -- out_dir [cases,comma,separated] [frames,comma,separated]
## A case is a target kind, optionally with the shooter's and the target's floor levels:
## "egg_sac", "egg_sac@1/0" (shooter on a roof shooting down), "runner@0/1" (shooting up).
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3).

const MAIN := preload("res://scenes/main.tscn")
const CASES := "egg_sac,spore_nest,hive_node,lurker,burrower,drifter,runner,egg_sac@1/0,runner@0/1"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var cases: PackedStringArray = (args[1] if args.size() > 1 and args[1] != "" else CASES).split(",")
	var frames: Array = Array((args[2] if args.size() > 2 else "12,17").split(",")).map(func(x: String) -> int: return int(x))
	root.size = Vector2i(960, 540)
	for entry in cases:
		var kind := entry.get_slice("@", 0)
		var lv := entry.get_slice("@", 1).split("/") if entry.contains("@") else PackedStringArray(["0", "0"])
		var s := MissionView.default_mission(1234)
		Vision.disable(s)
		var a: Unit = s.living(Types.Team.PLAYER)[0]
		var t: Unit = s.living(Types.Team.ENEMY)[0]
		t.kind = kind
		t.display_name = UnitData.ENEMIES[kind].name
		# A clear strip across the middle of the map: shooter at one end, target 5 tiles on.
		var y := s.grid.height / 2
		var x0 := s.grid.width / 2 - 3
		for dy in range(-2, 3):
			for dx in range(-1, 8):
				var c := Vector2i(x0 + dx, y + dy)
				s.grid.set_tile(c, Types.Tile.FLOOR)
				s.grid.set_level(c, 0)
		for dy in range(-2, 3):
			for dx in range(-1, 3):
				s.grid.set_level(Vector2i(x0 + dx, y + dy), int(lv[0]))
				s.grid.set_level(Vector2i(x0 + 5 + dx, y + dy), int(lv[1]))
		s.units = s.units.filter(func(u: Unit) -> bool: return u == a or u == t)
		a.pos = Vector2i(x0, y)
		t.pos = Vector2i(x0 + 5, y)
		var v: MissionView = MAIN.instantiate()
		v.auto_start = false
		root.add_child(v)
		v.start(s, true)
		v.player.flush()
		for we in v.find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.ambient_light_energy = 2.2
			(we as WorldEnvironment).environment.tonemap_exposure = 1.8
		v.player.cinematics = false
		v.hud.visible = false
		var cam := Camera3D.new()
		cam.fov = 50.0
		v.add_child(cam)
		var mid := (v.view_for(a.id).position + v.view_for(t.id).position) * 0.5
		cam.look_at_from_position(mid + Vector3(0, 1.1, 5.6), mid + Vector3(0, 0.6, 0))
		cam.current = true
		v.view_for(a.id).face_towards(v.view_for(t.id).position, true)
		for i in 20:
			await process_frame
		v.player.set_process(false)
		v.player.enqueue({"type": "shot", "unit": a.id, "target": t.id, "hit": true, "graze": false,
			"crit": false, "damage": 1, "chance": 80, "reaction": false})
		var f := 0
		var last: int = frames.max()
		while f <= last:
			v.player.advance(1.0 / 60.0)
			await process_frame
			if frames.has(f):
				var path := "%s/aim_%s_%d.png" % [out, entry.replace("@", "_").replace("/", "-"), f]
				root.get_texture().get_image().save_png(path)
				print("[shot_aim] ", path)
			f += 1
		v.queue_free()
		await process_frame
	quit()
