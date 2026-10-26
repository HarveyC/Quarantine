extends SceneTree
## Renders the Act 2 and 3 boss fights at their key moments from the tactical camera:
## godot -s tools/shot_bosses.gd -- out_dir [seed]
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
	await _hale()
	await _source()
	quit()


func _fight(act: int) -> MissionView:
	var fight := FightBuilder.build({"act": act, "node": "boss", "objective": "boss", "outbreak": 6, "seed": _seed, "squad": 2, "players": 2})
	var config := MatchConfig.make(2, _seed)
	config["enemies"] = fight.enemies
	config["encounter"] = fight.encounter
	config["map_spec"] = {"biome": RunMap.biome(act), "objective": "boss", "seed": _seed, "act": act, "row": 5}
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
		u.infection = 0
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
	print("[shot_bosses] ", path)


func _boss(v: MissionView, kind: String) -> Unit:
	return v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == kind)[0]


func _hale() -> void:
	var v := _fight(2)
	_drain(v)
	var h := _boss(v, "colonel_hale")
	var s: GameState = v.state
	# Phase 1: the strike is marked a turn before it lands.
	for i in 6:
		_round(v)
		if s.encounter.telegraphs.any(func(t): return t.kind == "airstrike"):
			break
	await _shot(v, "hale_1_fire_mission", h.pos)
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, h, 999, soldier)
	_drain(v)
	var pair := s.living(Types.Team.PLAYER)
	for i in mini(2, pair.size()):
		pair[i].pos = Encounter.free_cell(s, h.pos + Vector2i(1 - 2 * i, 1))
		v.view_for(pair[i].id).set_cell(pair[i].pos)
	_round(v)
	await _shot(v, "hale_2_stomp", h.pos, 12.0)
	Rules.deal_damage(s, h, 999, soldier)
	_drain(v)
	for i in 5:
		_round(v)
		if s.encounter.telegraphs.any(func(t): return t.kind in ["danger_close", "hurl"]):
			break
	await _shot(v, "hale_3_wreck", h.pos, 14.0)
	v.queue_free()
	await process_frame


func _source() -> void:
	var v := _fight(3)
	_drain(v)
	var src := _boss(v, "the_source")
	var s: GameState = v.state
	for c in EnemyAbilities.square(s.grid, src.pos + Vector2i(4, 4), 2):
		s.grid.set_level(c, 1)
	v.board.rebuild_tiles()
	_round(v)
	await _shot(v, "source_1_lash", src.pos, 18.0)
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	for r in s.living(Types.Team.ENEMY).filter(func(u): return u.kind == "source_root"):
		Rules.deal_damage(s, r, 99, soldier)
	_drain(v)
	for i in 3:
		_round(v)
	await _shot(v, "source_2_core_open", src.pos, 18.0)
	Rules.deal_damage(s, src, 999, soldier)
	_drain(v)
	await _shot(v, "source_3_collapse_marked", src.pos, 18.0)
	_round(v)
	await _shot(v, "source_3_collapsed", src.pos, 18.0)
	v.queue_free()
	await process_frame
