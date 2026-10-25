extends SceneTree
## Records enemy deaths to PNG frames (dev check for death animation and effects):
## godot -s tools/shot_deaths.gd -- out_dir [kinds,comma,separated] [cine|tactical] [crit]
## Each kind is shot dead by a Marksman; frames are 30 fps steps of the beat clock from
## the shot to a moment after the body lands (out_dir/<kind>_<mode>_NNN.png).
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3). Also writes
## <kind>_<mode>_sfx.txt: "frame sound" per line (sound effects, and "vo:<path>" for the
## death cry), for laying the audio under the frames. Headless, it writes only that.

const MAIN := preload("res://scenes/main.tscn")
const FRAMES := 150
const EnemyVoices := preload("res://view/enemy_voices.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var kinds: PackedStringArray = (args[1] if args.size() > 1 else "runner,brute,lurker,hive_node").split(",")
	var tactical := args.has("tactical")
	var crit := args.has("crit")
	root.size = Vector2i(960, 540)
	for kind in kinds:
		var s := MissionView.default_mission(1234)
		Vision.disable(s)
		var a: Unit = s.living(Types.Team.PLAYER)[0]
		a.kind = "marksman"
		a.display_name = UnitData.SOLDIERS["marksman"].name
		Weapons.equip_unit(a, "")
		var t := _place_target(s, a)
		t.kind = kind
		t.display_name = kind.capitalize()
		s.units = s.units.filter(func(u: Unit) -> bool: return u.team == Types.Team.PLAYER or u == t)
		var v: MissionView = MAIN.instantiate()
		v.auto_start = false
		root.add_child(v)
		v.start(s, true)
		v.player.flush()
		for we in v.find_children("*", "WorldEnvironment", true, false):
			(we as WorldEnvironment).environment.ambient_light_energy = 2.2
			(we as WorldEnvironment).environment.tonemap_exposure = 1.8
		for i in 20:
			await process_frame
		v.player.set_process(false)
		if tactical:
			v.player.cinematics = false
			v.camera_rig._target_dist = 6.0
			v.camera_rig.focus(v.view_for(t.id).position)
			v.camera_rig.snap()
		v.player.enqueue({"type": "shot", "unit": a.id, "target": t.id, "hit": true, "graze": false,
			"crit": crit, "damage": t.hp, "chance": 64, "reaction": false})
		v.player.enqueue({"type": "damage", "unit": t.id, "amount": t.hp, "hp": 0, "source": a.id})
		v.player.enqueue({"type": "died", "unit": t.id, "source": a.id})
		var tag := "%s/%s_%s%s" % [out, kind, "tactical" if tactical else "cine", "_crit" if crit else ""]
		var log := FileAccess.open(tag + "_sfx.txt", FileAccess.WRITE)
		var frame := [0]
		var cry := func(_x: Variant) -> void:
			log.store_line("%d vo:%s" % [frame[0], EnemyVoices.voice_for(kind, true)])
		if v.player.has_signal("unit_killed"):
			v.player.unit_killed.connect(cry)
		else:   # before the death rework the cry went up with the died event
			v.player.beat_started.connect(func(ev: Dictionary) -> void:
				if ev.get("type") == "died":
					cry.call(null))
		v.player.drained.connect(func() -> void: log.store_line("%d drained" % frame[0]), CONNECT_ONE_SHOT)
		var heard := v.player.sfx_log.size()
		var headless := DisplayServer.get_name() == "headless"
		for f in FRAMES:
			frame[0] = f
			v.player.advance(1.0 / 30.0)
			for i in range(heard, v.player.sfx_log.size()):
				log.store_line("%d %s" % [f, v.player.sfx_log[i]])
			heard = v.player.sfx_log.size()
			await process_frame
			if not headless:
				root.get_texture().get_image().save_png("%s_%03d.png" % [tag, f])
		log.close()
		print("[shot_deaths] ", kind)
		v.queue_free()
		await process_frame
	quit()


## Moves the nearest enemy to an open cell 5-7 tiles from `a` that it can see.
func _place_target(s: GameState, a: Unit) -> Unit:
	var t: Unit = s.living(Types.Team.ENEMY)[0]
	var best := t.pos
	var best_score := -INF
	for y in s.grid.height:
		for x in s.grid.width:
			var c := Vector2i(x, y)
			var d := a.pos.distance_to(c)
			if d < 5.0 or d > 7.0 or not s.grid.is_walkable(c) or s.unit_at(c) != null or not Combat.can_see(s, a.pos, c):
				continue
			var score := -absf(d - 6.0)
			if Combat.cover_against(s.grid, c, a.pos) == Types.Cover.NONE:
				score += 5.0
			if score > best_score:
				best_score = score
				best = c
	t.pos = best
	return t
