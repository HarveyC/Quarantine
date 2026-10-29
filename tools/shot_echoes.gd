extends SceneTree
## Renders the Lantern Echoes boss fight at its key moments from the tactical camera:
## godot -s tools/shot_echoes.gd -- out_dir [seed]
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
	await _fight()
	quit()


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
	print("[shot_echoes] ", path)


func _fight() -> void:
	var fight := FightBuilder.build({"act": 3, "node": "boss", "objective": "boss", "outbreak": 6, "seed": _seed, "squad": 3, "players": 1, "boss": "lantern_echoes"})
	var config := MatchConfig.make(1, _seed)
	config["enemies"] = []
	config["encounter"] = fight.encounter
	config["map_spec"] = {"biome": "bore", "objective": "boss", "seed": _seed, "act": 3, "boss": "lantern_echoes"}
	config["squad"] = [{"kind": "trooper", "player": 0}, {"kind": "medic", "player": 0}, {"kind": "breacher", "player": 0}]
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
	_drain(v)
	var boss := LanternEchoes.boss_of(s)
	await _shot(v, "echoes_1_formation", boss.pos + Vector2i(0, 5), 20.0)
	_round(v)
	_round(v)
	await _shot(v, "echoes_2_advance", boss.pos + Vector2i(0, 5), 20.0)
	var soldier: Unit = s.living(Types.Team.PLAYER)[0]
	Rules.deal_damage(s, LanternEchoes.echoes(s)[0], 999, soldier)
	_drain(v)
	await _shot(v, "echoes_3_falls_to_spores", boss.pos + Vector2i(0, 6), 18.0)
	_round(v)
	await _shot(v, "echoes_4_taken", boss.pos + Vector2i(0, 6), 18.0)
	for e in LanternEchoes.echoes(s):
		Rules.deal_damage(s, e, 999, soldier)
	_drain(v)
	_round(v)
	await _shot(v, "echoes_5_last_echo", boss.pos + Vector2i(0, 4), 16.0)
	v.queue_free()
	await process_frame
