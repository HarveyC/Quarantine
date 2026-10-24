extends Control
## Standalone preview of the gear screens on a seeded solo run, without playing the map:
##   godot res://scenes/gear_demo.tscn -- [--screen=reward|guns|loadout|doctrine|kit] [--shot=out.png]

const UI := preload("res://ui/gear/gear_ui.gd")

var run: RunState
var session := DemoSession.new()
var _shot := ""
var _frames := 0
var _preview := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var screen := "reward"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			screen = a.trim_prefix("--screen=")
		elif a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		elif a.begins_with("--preview="):
			_preview = a.trim_prefix("--preview=")
	run = make_run(screen)
	session.run = run
	var ctl: Control = (GearRun.loadout_screen() if screen == "loadout" else GearRun.reward_screen()).new()
	add_child(ctl)
	ctl.setup(run, session)
	if screen == "loadout" and _preview != "":
		ctl._held = Loadout.stash(run).find_custom(func(it): return it.id == _preview)
		ctl._set_preview(_preview)
	if screen == "reward" or screen == "guns":
		ctl._sid = run.squad()[1].id   # open on the Marksman, whose offer shows each card state
		ctl._refresh()
		if _shot != "":
			ctl.call_deferred("_select", 0)


## A solo run a few fights in: everyone has some gear, the stash has two items.
static func make_run(screen: String) -> RunState:
	GearTags.set_progression(false)
	var r := RunRules.new_run(1, 4242)
	RunRules.start_run(r)
	r.gear.offers.clear()
	if screen == "kit":
		GearRun.starting_kit_offers(r)
		r.phase = RunState.Phase.REWARD
		return r
	var sq := r.squad()
	var kits := [["kevlar_vest", "compensator", "shock_rounds"], ["laser_sight", "tracer_rounds", "light_harness"],
		["med_injector", "hazard_liner"], ["slug_rounds", "light_harness", "choke"]]
	for i in sq.size():
		for id in kits[i]:
			Loadout.equip(r, sq[i], id)
	for i in sq.size():   # a spare gun each; half of them carry theirs
		var alts := Weapons.alternates_for(sq[i].kind)
		if not alts.is_empty():
			Loadout.add_gun(sq[i], alts[0], i % 2 == 0)
	Loadout.add_consumable(sq[0], "frag_grenade", 2)
	Loadout.add_consumable(sq[0], "medkit", 1)
	Loadout.add_consumable(sq[2], "suppressant_shot", 2)
	Loadout.stash_add(r, "bipod")
	Loadout.stash_add(r, "incendiary_rounds")
	Loadout.stash_add(r, "concussion_launcher")
	r.act = 2
	r.supplies = 140
	r.gear.fights_won = 3
	if screen == "doctrine":
		r.phase = RunState.Phase.REWARD
		GearRun._open_doctrine_vote(r)
	elif screen == "reward" or screen == "guns":
		r.phase = RunState.Phase.REWARD
		GearRun.on_fight_won(r, "skirmish")
		# Make the Marksman's offer show a set completion, an upgrade and a Prototype (or guns).
		r.gear.offers[sq[1].id].cards = [GearRun._gear_card("flare_launcher"), GearRun._gear_card("tracer_rounds"),
			GearRun._gear_card("killbox")]
		if screen == "guns":
			r.gear.offers[sq[1].id].cards = [{"kind": "gun", "id": "battle_rifle", "rarity": "uncommon", "tags": ["Suppress"]}, GearRun._gear_card("flare_launcher"),
				{"kind": "gun", "id": "scout_carbine", "rarity": "uncommon", "tags": ["Close"]}]
		var first: Dictionary = r.gear.offers[sq[1].id]
		r.gear.offers.erase(sq[1].id)
		var rest: Dictionary = r.gear.offers.duplicate()
		r.gear.offers.clear()
		r.gear.offers[sq[1].id] = first
		for k in rest:
			r.gear.offers[k] = rest[k]
	return r


func _process(_d: float) -> void:
	if _shot == "":
		return
	_frames += 1
	if _frames == 45:
		get_viewport().get_texture().get_image().save_png(_shot)
		print("[gear-demo] saved ", _shot)
		get_tree().quit(0)


class DemoSession:
	extends RefCounted
	var run: RunState
	var player_names := {0: "Harvey"}

	func local_players() -> Array[int]:
		return run.players

	func submit_run(action: Dictionary) -> void:
		RunRules.apply(run, action)
