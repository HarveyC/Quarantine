extends SceneTree
## Renders the Breaker fight at its key moments from the tactical camera, plus the rig up close:
## godot -s tools/shot_breaker.gd -- out_dir [seed]
## Needs a real renderer (xvfb-run ... --rendering-driver opengl3).

const MAIN := preload("res://scenes/main.tscn")
const Board := preload("res://view/board.gd")

var _out := "user://"
var _seed := 4


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	_seed = int(args[1]) if args.size() > 1 else 4
	root.size = Vector2i(1280, 720)
	await _fight_shots()
	quit()


func _fight() -> MissionView:
	var fight := FightBuilder.build({"act": 1, "node": "boss", "objective": "boss", "outbreak": 4, "seed": _seed, "squad": 2, "players": 2, "boss": "breaker"})
	var config := MatchConfig.make(2, _seed)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	config["map_spec"] = {"biome": "wall", "objective": "boss", "seed": _seed, "act": 1, "row": 5, "boss": "breaker"}
	var s := MatchConfig.build(config)
	Vision.disable(s)
	var v: MissionView = MAIN.instantiate()
	v.auto_start = false
	root.add_child(v)
	v.start(s, true)
	for we in v.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.ambient_light_energy *= 6.0
		(we as WorldEnvironment).environment.tonemap_exposure = 1.8
	if v.fog != null:
		v.fog.visible = false
	return v


func _drain(v: MissionView) -> void:
	var n := 0
	while v.player.is_busy() and n < 20000:
		v.player.advance(1.0 / 15.0)
		n += 1


func _round(v: MissionView) -> void:
	for u in v.state.living(Types.Team.PLAYER):
		u.max_hp = 99
		u.hp = 99
	for p in v.state.players:
		Rules.set_ready(v.state, p, true)
	_drain(v)


func _shot(v: MissionView, name: String, at: Vector2i, dist := 16.0) -> void:
	v.intents.refresh()
	v.camera_rig._target_dist = dist
	v.camera_rig.focus(Board.cell_to_world(at))
	v.camera_rig.snap()
	for i in 20:
		await process_frame
	var path := "%s/%s.png" % [_out, name]
	root.get_texture().get_image().save_png(path)
	print("[shot_breaker] ", path)


func _fight_shots() -> void:
	var v := _fight()
	_drain(v)
	var s: GameState = v.state
	var b: Unit = s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "breaker")[0]
	await _shot(v, "breaker_0_start", Vector2i(10, 10), 24.0)
	await _shot(v, "breaker_0_close", b.pos, 7.0)
	for i in 3:
		_round(v)
		if b.status.has("charge_dir"):
			break
	await _shot(v, "breaker_1_lane_marked", b.pos, 16.0)
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, b, 999, soldier)
	_drain(v)
	var high: Unit = s.living(Types.Team.PLAYER)[0]
	high.pos = Encounter.free_cell(s, b.pos + Vector2i(0, 5))
	s.grid.set_level(high.pos, 1)
	v.board.rebuild_tiles()
	v.view_for(high.id).set_cell(high.pos)
	b.cooldowns.erase("debris")
	for i in 3:
		_round(v)
		if s.encounter.telegraphs.any(func(t): return t.kind == "debris"):
			break
	await _shot(v, "breaker_2_debris_marked", high.pos, 14.0)
	Rules.deal_damage(s, b, 999, soldier)
	_drain(v)
	for i in 4:
		_round(v)
		if b.status.has("charge_dir2"):
			break
	await _shot(v, "breaker_3_double_charge", b.pos, 16.0)
	v.queue_free()
	await process_frame
