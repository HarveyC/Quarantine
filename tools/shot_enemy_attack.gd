extends SceneTree
## Renders enemy attacks in cramped spots to PNGs (dev check for the enemy shot camera and the
## attack callout): godot -s tools/shot_enemy_attack.gd -- out_dir [scenes,comma,separated] [frames|all]
## Scenes: alley (a Fallen crits a soldier down a walled alley), corner (a Runner claws a soldier
## down in a room corner under a roof), roof (a Fallen on a roof fires down past a wall),
## tactical (a Fallen hits a soldier with no cut, as most enemy shots play).
## `all` saves every frame (for a clip: ffmpeg -framerate 60 -i <scene>_%04d.png).
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3).

const MAIN := preload("res://scenes/main.tscn")

const SCENES := {
	"alley": [
		"..............",
		"..^^^^^.......",
		"..^^^^^.......",
		".###########..",
		"..P....E......",
		".###########..",
		"..............",
		"..............",
	],
	"corner": [
		"##########",
		"#^^^.....#",
		"#^^^.....#",
		"#PE......#",
		"#........#",
		"#####.####",
		"..........",
		"..........",
	],
	"roof": [
		"............",
		"..^^^^^^....",
		"..^^E^^^....",
		"..^^^^^^....",
		"....#####...",
		"............",
		"......P.....",
		"............",
	],
	"tactical": [
		"..............",
		"..^^^^^.......",
		"..^^^^^.......",
		".#####.#####..",
		"..P......E....",
		".#####.#####..",
		"..............",
		"..............",
	],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var names: PackedStringArray = (args[1] if args.size() > 1 else "alley,corner,roof,tactical").split(",")
	var every := args.size() > 2 and args[2] == "all"
	var frames: Array = [] if every or args.size() <= 2 else Array(args[2].split(",")).map(func(x: String) -> int: return int(x))
	if frames.is_empty() and not every:
		frames = [20, 45, 70, 100, 140, 190]
	root.size = Vector2i(1280, 720)
	for scene in names:
		var g := Grid.from_rows(PackedStringArray(SCENES[scene]))
		var enemy := "runner" if scene == "corner" else "fallen"
		var s := Rules.new_mission_on_grid(g, [{"kind": "trooper", "player": 0}], [enemy], 7)
		Vision.disable(s)
		var a: Unit = s.living(Types.Team.ENEMY)[0]
		var t: Unit = s.living(Types.Team.PLAYER)[0]
		var v: MissionView = MAIN.instantiate()
		v.auto_start = false
		root.add_child(v)
		v.start(s, true)
		v.player.flush()
		for we in v.find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.ambient_light_energy = 2.2
			(we as WorldEnvironment).environment.tonemap_exposure = 1.8
		v.camera_rig.focus((v.view_for(a.id).position + v.view_for(t.id).position) * 0.5)
		v.camera_rig.snap()
		for i in 20:
			await process_frame
		v.player.set_process(false)
		v.player.enemy_phase = true
		var hp := t.hp
		match scene:
			"corner":
				v.player.enqueue({"type": "ability", "ability": "claw", "unit": a.id, "target": t.id, "hit": true, "chance": 78})
				v.player.enqueue({"type": "damage", "unit": t.id, "amount": hp, "hp": 0})
				v.player.enqueue({"type": "died", "unit": t.id})
			"tactical":
				v.player.enqueue({"type": "shot", "unit": a.id, "target": t.id, "hit": true, "crit": false, "graze": false,
					"chance": 62, "damage": 3})
				v.player.enqueue({"type": "damage", "unit": t.id, "amount": 3, "hp": hp - 3})
				v.player.enqueue({"type": "infection", "unit": t.id, "value": t.infection + 10, "tier": t.infection_tier() if t.has_method("infection_tier") else 0})
			_:
				v.player.enqueue({"type": "shot", "unit": a.id, "target": t.id, "hit": true, "crit": true, "graze": false,
					"chance": 48, "damage": 6})
				v.player.enqueue({"type": "damage", "unit": t.id, "amount": 6, "hp": hp - 6})
				v.player.enqueue({"type": "infection", "unit": t.id, "value": t.infection + 10, "tier": 0})
				v.player.enqueue({"type": "pinned", "unit": a.id, "target": t.id})
		var f := 0
		var last: int = 240 if every else frames.max()
		while f <= last and (v.player.is_busy() or not every):
			v.player.advance(1.0 / 60.0)
			await process_frame
			if every or frames.has(f):
				var path := "%s/%s_%04d.png" % [out, scene, f]
				root.get_texture().get_image().save_png(path)
				if not every:
					print("[shot_enemy_attack] ", path)
			f += 1
		v.queue_free()
		await process_frame
	quit()
