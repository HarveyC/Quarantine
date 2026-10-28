extends TestCase
## The item audit: every gadget, pocket item, soldier ability, gear item, Prototype, set bonus,
## doctrine and deployment order has to do something in the rules, and every active one has to
## play a beat of its own (a look and a sound, never the bare label fallback).
##
## Adding an item without a case here fails test_every_*_has_a_case, so a new item can't ship
## doing nothing the way the smoke grenade did in v0.13.0.

const MAIN := preload("res://scenes/main.tscn")
const ItemBeats := preload("res://view/item_beats.gd")
const EventPlayer := preload("res://view/event_player.gd")
const Sfx := preload("res://view/sfx.gd")
const EnemyBeats := preload("res://view/enemy_beats.gd")

const OPEN := [
	"..............",
	"..............",
	"......!.......",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]
const U_AT := Vector2i(4, 5)
const ALLY_AT := Vector2i(5, 5)
const FOE_AT := Vector2i(8, 5)
const NEAR_AT := Vector2i(3, 6)   # an enemy next to the user


func _state() -> GameState:
	var s := make_blank(PackedStringArray(OPEN))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	return s


func _add(s: GameState, kind: String, team: int, at: Vector2i) -> Unit:
	var u := s.add_unit(UnitData.make(kind, team), at)
	u.actions_left = Types.ACTIONS_PER_TURN
	if team == Types.Team.PLAYER:
		u.owner_player = 0
	return u


## Gives `u` gear: items are ids (Mk I) or [id, mk] pairs; pockets get 2 charges each.
func _gear(u: Unit, items: Array, pockets: Array = []) -> void:
	GearTags.set_progression(null)
	var rec := {"id": u.id, "kind": u.kind}
	var run := {"supplies": 0, "soldiers": [rec]}
	for it in items:
		var id: String = it if it is String else it[0]
		Loadout.equip(run, rec, id)
		if it is Array and it[1] >= 2 and not GearData.PROTOTYPES.has(id):
			Loadout.upgrade(rec, GearData.slot_of(id))
	for p in pockets:
		Loadout.add_consumable(rec, p, 2)
	GearRun.apply_to_unit(u, rec)


func _term(odds: Dictionary, label: String) -> int:
	for t in odds.breakdown:
		if t[0] == label:
			return t[1]
	return 0


func _logged(s: GameState, type: String, key := "", value: Variant = null) -> bool:
	for ev in s.log:
		if ev.get("type") == type and (key == "" or ev.get(key) == value):
			return true
	return false


# --- active: gadgets, pocket items and soldier abilities -------------------------------------

## One case per ability id: who uses it ("kind"), their gear and pockets, any extra ability ids,
## a setup that returns the action's extra fields, and a check on the state afterwards that
## returns "" when the effect landed. `c` = {s, u, ally, foe, near}.
func _cases() -> Dictionary:
	var c := {}
	c["gear:flare_launcher"] = {"items": ["flare_launcher"], "act": func(x): return {"cell": FOE_AT},
		"check": func(x): return "" if Combat.has_status(x.s, x.foe, "tagged") else "target not Marked"}
	c["gear:concussion_launcher"] = {"items": ["concussion_launcher"], "act": func(x): return {"cell": FOE_AT},
		"check": func(x): return "" if Combat.has_status(x.s, x.foe, "suppressed") else "target not Suppressed"}
	c["gear:thermite_charge"] = {"items": ["thermite_charge"], "act": func(x): return {"cell": Vector2i(6, 5)},
		"check": func(x): return "" if Hazards.at(x.s, FOE_AT).get("kind", "") == "fire" else "no fire line"}
	c["gear:med_injector"] = {"items": ["med_injector"], "pre": func(x): x.ally.infection = 30,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.infection == 15 else "ally still at %d" % x.ally.infection}
	c["gear:adrenal_pump"] = {"items": ["adrenal_pump"], "act": func(x): return {},
		"check": func(x): return "" if x.u.infection == 15 else "no Infection gained"}
	c["gear:deployable_cover"] = {"items": ["deployable_cover"], "act": func(x): return {"cell": Vector2i(4, 4)},
		"check": func(x): return "" if x.s.grid.tile(Vector2i(4, 4)) == Types.Tile.WALL else "no barricade"}
	c["gear:grapple"] = {"items": ["grapple"], "act": func(x): return {"cell": Vector2i(4, 1)},
		"check": func(x): return "" if x.u.pos == Vector2i(4, 1) else "didn't move"}
	c["gear:containment_emitter"] = {"items": ["containment_emitter"], "act": func(x): return {},
		"check": func(x):
			Infection.add(x.s, x.ally, 10)
			return "" if Combat.has_status(x.s, x.ally, "contained") and x.ally.infection == 0 else "ally not contained"}
	c["gear:sentry_turret"] = {"items": ["sentry_turret"], "act": func(x): return {"cell": Vector2i(3, 4)},
		"check": func(x):
			var t: Unit = x.s.unit_at(Vector2i(3, 4))
			return "" if t != null and Deployables.is_deployable(t) else "no turret"}
	c["item:medkit"] = {"pockets": ["medkit"], "pre": func(x): x.ally.hp = 2,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.hp == 6 else "hp %d" % x.ally.hp}
	c["item:suppressant_shot"] = {"pockets": ["suppressant_shot"], "pre": func(x): x.ally.infection = 30,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.infection == 15 else "ally still at %d" % x.ally.infection}
	c["item:antiviral_dose"] = {"pockets": ["antiviral_dose"], "pre": func(x): x.ally.infection = 50,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.infection == 15 else "ally still at %d" % x.ally.infection}
	c["item:breather_mask"] = {"pockets": ["breather_mask"], "act": func(x): return {},
		"check": func(x): return "" if Combat.has_status(x.s, x.ally, "contained") and Combat.has_status(x.s, x.u, "contained") else "not sealed"}
	c["item:stim"] = {"pockets": ["stim"], "act": func(x): return {},
		"check": func(x): return "" if x.u.actions_left == 3 and x.u.infection == 5 else "actions %d" % x.u.actions_left}
	c["item:frag_grenade"] = {"pockets": ["frag_grenade"], "act": func(x): return {"cell": FOE_AT},
		"check": func(x): return "" if x.foe.hp < x.foe.max_hp else "no damage"}
	c["item:demo_charge"] = {"pockets": ["demo_charge"], "act": func(x): return {"cell": Vector2i(4, 4)},
		"check": func(x): return "" if _logged(x.s, "explosion") else "no blast"}
	c["item:flashbang"] = {"pockets": ["flashbang"], "act": func(x): return {"cell": FOE_AT},
		"check": func(x):
			return "" if x.foe.status.get("k_skip_turn", false) and _logged(x.s, "stunned") else "target not Stunned"}
	c["item:smoke_grenade"] = {"pockets": ["smoke_grenade"], "act": func(x): return {"cell": ALLY_AT},
		"check": func(x):
			if not GearFx.in_smoke(x.s, x.u) or not GearFx.in_smoke(x.s, x.ally):
				return "no cloud over the squad"
			return "" if _term(Combat.hit_chance(x.s, x.foe, x.u), "Smoke") == -GearFx.SMOKE_DEFENSE else "no defense"}
	c["item:recon_drone"] = {"pockets": ["recon_drone"], "act": func(x): return {"cell": Vector2i(10, 2)},
		"check": func(x): return "" if not (x.s.vision.get("reveals", []) as Array).is_empty() else "nothing revealed"}
	c["item:containment_foam"] = {"pockets": ["containment_foam"],
		"pre": func(x):
			x.ally.status["lapsed"] = true
			x.ally.ai_controlled = true,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x):
			if not GearFx.is_restrained(x.s, x.ally):
				return "not restrained"
			x.ally.actions_left = 2
			var before: Vector2i = x.ally.pos
			EnemyAI.take_turn(x.s, x.ally)
			return "" if x.ally.pos == before and _logged(x.s, "gear", "item", "restrained") else "acted anyway"}
	# Soldier abilities: class kit, perk abilities and the any-soldier actions.
	c["suppress"] = {"kind": "trooper", "act": func(x): return {"target": x.foe.id},
		"check": func(x): return "" if Combat.has_status(x.s, x.foe, "suppressed") else "not Suppressed"}
	c["tag"] = {"kind": "marksman", "act": func(x): return {"target": x.foe.id},
		"check": func(x): return "" if Combat.has_status(x.s, x.foe, "tagged") else "not Marked"}
	c["stim"] = {"kind": "medic", "pre": func(x): x.ally.hp = 2, "act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.hp > 2 else "no heal"}
	c["breach"] = {"kind": "breacher", "act": func(x): return {"target": x.near.id},
		"check": func(x): return "" if x.near.hp < x.near.max_hp else "no damage"}
	c["incinerate"] = {"kind": "hazmat", "act": func(x): return {"cell": Vector2i(6, 5)},
		"check": func(x): return "" if not Hazards.cells_of(x.s, "fire").is_empty() else "no fire"}
	c["siphon"] = {"kind": "vector", "pre": func(x): x.ally.infection = 30, "act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.u.infection > 0 and x.ally.infection < 30 else "nothing moved"}
	c["purge"] = {"kind": "medic", "abilities": ["purge"], "pre": func(x): x.ally.infection = 40,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.infection < 40 else "not purged"}
	c["decon"] = {"kind": "medic", "abilities": ["decon"], "pre": func(x): x.ally.infection = 40,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.infection == 30 and Combat.has_status(x.s, x.ally, "k_decon") else "no decon"}
	c["squad_order"] = {"kind": "trooper", "abilities": ["squad_order"], "act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.actions_left == 3 else "no extra action"}
	c["talk_down"] = {"kind": "trooper", "pre": func(x):
			x.ally.status["lapsed"] = true
			x.ally.ai_controlled = true,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if not Infection.is_lapsed(x.ally) else "still Lapsed"}
	c["serum"] = {"kind": "trooper", "pre": func(x):
			x.u.status["serum"] = 1
			x.ally.infection = 40,
		"act": func(x): return {"target": x.ally.id},
		"check": func(x): return "" if x.ally.infection == 0 else "not cured"}
	c["guard"] = {"kind": "warden", "act": func(x): return {},
		"check": func(x): return "" if ClassAbilities.is_guarding(x.s, x.u) else "not guarding"}
	c["bash"] = {"kind": "warden", "act": func(x): return {"target": x.near.id},
		"check": func(x): return "" if _logged(x.s, "ability", "ability", "bash") else "no strike"}
	c["shield_charge"] = {"kind": "warden", "abilities": ["shield_charge"], "act": func(x): return {"target": x.foe.id},
		"check": func(x): return "" if _logged(x.s, "ability", "ability", "bash") else "no strike"}
	c["lunge"] = {"kind": "reaper", "act": func(x): return {"target": x.foe.id},
		"check": func(x): return "" if _logged(x.s, "ability", "ability", "lunge") else "no strike"}
	# Rank 2 signatures (Signatures).
	c["lockdown"] = {"abilities": ["lockdown"], "kind": "trooper", "act": func(x): return {},
		"check": func(x): return "" if x.u.overwatch and Signatures.keeps_overwatch(x.s, x.u) else "not watching"}
	c["deadeye"] = {"abilities": ["deadeye"], "kind": "marksman", "act": func(x): return {"target": x.foe.id},
		"check": func(x): return "" if x.foe.hp < x.foe.max_hp and Combat.has_status(x.s, x.foe, "tagged") else "no hit or Mark"}
	c["quarantine_field"] = {"abilities": ["quarantine_field"], "kind": "medic", "act": func(x): return {},
		"check": func(x): return "" if Signatures.field_blocks_infection(x.s, x.u) else "no field"}
	c["bring_down"] = {"abilities": ["bring_down"], "kind": "breacher", "act": func(x): return {"target": x.foe.id},
		"check": func(x): return "" if x.foe.hp < x.foe.max_hp else "no damage"}
	c["flashover"] = {"abilities": ["flashover"], "kind": "hazmat", "pre": func(x): x.foe.status["burning"] = 2, "act": func(x): return {},
		"check": func(x): return "" if x.foe.hp < x.foe.max_hp and not x.foe.status.has("burning") else "fire not spent"}
	c["vent"] = {"abilities": ["vent"], "kind": "vector", "pre": func(x): x.u.infection = 40, "act": func(x): return {},
		"check": func(x): return "" if x.u.infection == 15 and x.near.hp < x.near.max_hp else "nothing vented"}
	c["death_sweep"] = {"abilities": ["death_sweep"], "kind": "reaper", "act": func(x): return {},
		"check": func(x): return "" if x.near.hp < x.near.max_hp else "no cut"}
	c["provoke"] = {"abilities": ["provoke"], "kind": "warden", "act": func(x): return {},
		"check": func(x): return "" if Signatures.provoking(x.s, x.u) else "not provoking"}
	# Bloom graft abilities (Grafts): the arm's claw and the legs' leap.
	c["bloom_claw"] = {"kind": "trooper", "pre": func(x): Grafts.apply_to_unit(x.u, {"grafts": {"arm": "bloom_limb"}}),
		"act": func(x): return {"target": x.near.id},
		"check": func(x): return "" if x.near.hp < 30 else "no damage"}
	c["runner_leap"] = {"kind": "trooper", "pre": func(x): Grafts.apply_to_unit(x.u, {"grafts": {"legs": "runner_legs"}}),
		"act": func(x): return {"cell": Vector2i(6, 7)},
		"check": func(x): return "" if x.u.pos == Vector2i(6, 7) else "didn't land"}
	return c


## Every ability a soldier can be handed: gadgets, pocket items, class and perk abilities,
## the any-soldier actions and soldier abilities built into Combat.
func _all_active_ids() -> Array[String]:
	var out: Array[String] = []
	for k in GearFx.GADGETS:
		out.append("gear:" + k)
	for k in GearFx.CONSUMABLE_USE:
		out.append("item:" + k)
	for k in ClassAbilities.ABILITIES:
		out.append(k)
	for kind in UnitData.SOLDIERS:
		for a in UnitData.SOLDIERS[kind].get("abilities", []):
			if not out.has(a):
				out.append(a)
	return out


func test_every_active_item_and_ability_has_a_case() -> void:
	var cases := _cases()
	for id in _all_active_ids():
		assert_true(cases.has(id), "%s has no audit case in tests/test_item_audit.gd" % id)
	for id in GearData.CONSUMABLES:
		assert_true(GearFx.CONSUMABLE_USE.has(id), "consumable %s can't be used in a fight" % id)


## Plays each case in a real mission view: the action is accepted, the effect lands, and the view
## gives it a beat of its own with sound (no label fallback, no unhandled event).
func test_every_active_item_and_ability_works_and_shows() -> void:
	var cases := _cases()
	for id in cases:
		var cs: Dictionary = cases[id]
		var s := _state()
		var u := _add(s, str(cs.get("kind", "trooper")), Types.Team.PLAYER, U_AT)
		var ally := _add(s, "medic", Types.Team.PLAYER, ALLY_AT)
		var foe := _add(s, "spitter", Types.Team.ENEMY, FOE_AT)
		var near := _add(s, "runner", Types.Team.ENEMY, NEAR_AT)
		for e in [foe, near]:
			e.max_hp = 30
			e.hp = 30
		u.max_hp = 10
		u.hp = 10
		for a in cs.get("abilities", []):
			u.abilities.append(a)
		_gear(u, cs.get("items", []), cs.get("pockets", []))
		var x := {"s": s, "u": u, "ally": ally, "foe": foe, "near": near}
		if cs.has("pre"):
			(cs.pre as Callable).call(x)
		var v: MissionView = MAIN.instantiate()
		v.start(s, false)
		v.player.flush()
		v.player.generic_log.clear()
		v.player.sfx_log.clear()
		var action := {"type": Types.ABILITY, "unit": u.id, "ability": id}
		action.merge((cs.act as Callable).call(x))
		var why := Rules.validate(s, action)
		assert_eq(why, "", "%s is usable" % id)
		if why == "":
			var from := s.log.size()
			var declared := _declared_cooldown(u, id)
			assert_true(Rules.apply(s, action), "%s applied" % id)
			if declared > 0:
				assert_eq(int(u.cooldowns.get(id, 0)), declared, "%s goes on cooldown" % id)
				for a in Combat.available_abilities(s, u):
					if a.id == id:
						assert_true(not a.ready and int(a.cooldown) == declared, "%s is listed as cooling down" % id)
			var err: String = (cs.check as Callable).call(x)
			assert_eq(err, "", "%s has its effect" % id)
			var events := s.log.slice(from)
			var shown: String = "bash" if id == "shield_charge" else id   # a charge ends in a Bash
			assert_true(events.any(func(ev): return ev.get("type") == "ability" and ev.get("ability") == shown) or id == "guard",
				"%s emits its ability event" % id)
			v.player.flush()
			assert_eq(v.player.generic_log, [] as Array[String], "%s plays dedicated beats" % id)
			assert_true(not v.player.sfx_log.is_empty(), "%s makes a sound" % id)
		v.free()
	GearTags.set_progression(false)


## The cooldown an ability's definition promises, read before it is used (a spent item stops listing).
func _declared_cooldown(u: Unit, id: String) -> int:
	if GearFx.owns(id):
		return int(GearFx._def(u, id).get("cooldown", 0))
	if ClassAbilities.ABILITIES.has(id):
		return int(ClassAbilities.ABILITIES[id].cooldown)
	if Combat.ABILITIES.has(id):
		return int(Combat.ABILITIES[id].cooldown)
	return 0


func test_every_gadget_and_pocket_item_has_a_look() -> void:
	var own := ["item:medkit", "item:frag_grenade", "item:demo_charge"]   # dedicated beats in EventPlayer
	for k in GearFx.GADGETS:
		assert_true(ItemBeats.has_look("gear:" + k), "gear:%s has a look" % k)
	for k in GearFx.CONSUMABLE_USE:
		assert_true(ItemBeats.has_look("item:" + k) or own.has("item:" + k), "item:%s has a look" % k)
	for id in ItemBeats.SOLDIER:
		var look: Dictionary = ItemBeats.SOLDIER[id]
		assert_true(Sfx.SOUNDS.has(look.sound), "%s sound %s exists" % [id, look.sound])
		assert_true(ResourceLoader.exists("res://audio/%s.wav" % look.sound), "%s.wav is generated" % look.sound)
	for snd in ["smoke_hiss", "flashbang", "gadget_deploy", "foam_spray", "drone", "grapple", "flare_pop", "emitter_hum", "order_call"]:
		assert_true(Sfx.SOUNDS.has(snd) and ResourceLoader.exists("res://audio/%s.wav" % snd), "%s sound is wired" % snd)


# --- passive: gear items, Prototypes, set bonuses ---------------------------------------------

## A probe per passive item and Prototype: sets up a tiny fight and returns "" when the item's
## effect shows up in the rules. Stat-only items are checked from their `stats` instead.
func _probes() -> Dictionary:
	var p := {}
	p["flame_coat"] = func(x): return _expect(GearFx.hazard_hit(x.s, x.u, {"kind": "fire", "source": -1}, 2, 0).x == 0, "fire still hurts")
	p["igniter_barrel"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Hazards.at(x.s, x.foe.pos).get("kind", "") == "fire", "no fire on the target's tile")
	p["incendiary_rounds"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(GearFx.is_burning(x.s, x.foe), "target not Burning")
	p["phosphor_rounds"] = func(x):
		x.near.pos = x.foe.pos + Vector2i(0, 1)
		x.foe.status["burning"] = 2
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(GearFx.is_burning(x.s, x.near), "neighbour not set Burning")
	p["laser_sight"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Combat.has_status(x.s, x.foe, "tagged"), "first shot didn't Mark")
	p["light_harness"] = func(x):
		x.u.status["gear_move_len"] = 5
		x.u.actions_left = 1
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(x.u.actions_left == 2, "no refunded action")
	p["kevlar_vest"] = func(x): return _expect(GearFx.damage_taken(x.s, x.u, 4, x.foe) == 1, "first hit not cut")
	p["ballistic_plate"] = func(x):
		GearFx.damage_taken(x.s, x.u, 4, x.near)
		return _expect(x.near.hp < x.near.max_hp, "adjacent enemy untouched")
	p["pilot_light"] = func(x):
		x.foe.status["burning"] = 2
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Hazards.cells_of(x.s, "fire").size() > 0, "no fire behind the target")
	p["ember_plating"] = func(x):
		GearFx.damage_taken(x.s, x.u, 2, x.foe)
		return _expect(GearFx.is_burning(x.s, x.foe), "attacker not Burning")
	p["extended_mag"] = func(x):
		x.foe.status["suppressed"] = Combat.phase_index(x.s) + 2
		var before := Ammo.rounds(x.u)
		GearFx.after_reload(x.s, x.u, 0)
		return _expect(Ammo.rounds(x.u) == before - 1, "no free shot at the Suppressed enemy")
	p["speed_loader"] = func(x):
		x.u.status["ammo"] = 1
		Rules.apply(x.s, {"type": Types.RELOAD, "unit": x.u.id})
		return _expect(x.u.actions_left == 2 and Ammo.rounds(x.u) == Ammo.mag_size(x.u), "reload still cost an action")
	p["scavenger_rounds"] = func(x):
		x.u.status["ammo"] = 2
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(Ammo.rounds(x.u) == 3, "no round back")
	p["chain_link"] = func(x):
		x.near.pos = x.foe.pos + Vector2i(0, 1)
		GearFx._mark(x.s, x.foe, 2, x.u)
		return _expect(GearFx.is_marked(x.s, x.near), "neighbour not Marked")
	p["echo_array"] = func(x):
		x.near.pos = x.foe.pos + Vector2i(0, 2)
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		x.near.status["tagged"] = Combat.phase_index(x.s) + 2
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(x.near.hp == x.near.max_hp - 1, "other Marked enemy untouched")
	p["cinder_lens"] = func(x):
		GearFx.ignite(x.s, x.u, x.foe, 2)
		return _expect(GearFx.is_marked(x.s, x.foe), "burning enemy not Marked")
	p["flash_fry"] = func(x):
		x.foe.pos = x.u.pos + Vector2i(2, 0)
		x.near.pos = x.foe.pos + Vector2i(0, 1)
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(GearFx.is_burning(x.s, x.near), "neighbour not Burning")
	p["pressure_nozzle"] = func(x):
		GearFx._suppress(x.s, x.u, x.foe)
		return _expect(GearFx.is_burning(x.s, x.foe), "suppressed enemy not Burning")
	p["cascade_rounds"] = func(x):
		x.near.pos = x.foe.pos + Vector2i(0, 1)
		GearFx._suppress(x.s, x.u, x.foe)
		return _expect(Combat.has_status(x.s, x.near, "suppressed"), "neighbour not Suppressed")
	p["pin_tag_rounds"] = func(x):
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Combat.has_status(x.s, x.foe, "suppressed"), "Marked target not Suppressed")
	p["hair_trigger"] = func(x):
		x.u.overwatch = true
		x.u.status["ow_until"] = Combat.phase_index(x.s) + 2
		x.foe.pos = x.u.pos + Vector2i(3, 0)
		var before: int = x.foe.hp
		GearFx._mark(x.s, x.foe, 2, x.ally)
		return _expect(x.foe.hp < before or _logged(x.s, "gear", "item", "hair_trigger"), "no shot at the new Mark")
	p["patient_eye"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, true, 3)
		return _expect(GearFx.is_marked(x.s, x.foe), "overwatch hit did not Mark")
	p["kill_spill"] = func(x):
		x.foe.pos = x.u.pos + Vector2i(2, 0)
		x.near.pos = x.foe.pos + Vector2i(0, 1)
		x.u.status["link_dmg"] = 4
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(x.near.hp == x.near.max_hp - 2, "spill missed the neighbour")
	p["retaliation_plate"] = func(x):
		GearFx.damage_taken(x.s, x.u, 2, x.foe)
		return _expect(GearFx.is_marked(x.s, x.foe), "attacker not Marked")
	p["serum_lance"] = func(x):
		x.near.pos = x.ally.pos + Vector2i(0, 1)
		GearFx.on_purge(x.s, x.u, x.ally, 10)
		return _expect(GearFx.is_marked(x.s, x.near) and x.near.hp < x.near.max_hp, "enemy beside the purged ally untouched")
	p["volatile_spores"] = func(x):
		x.u.infection = 30
		x.near.pos = x.foe.pos + Vector2i(0, 1)
		x.foe.status["burning"] = 2
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(x.near.hp == x.near.max_hp - 2, "burst missed the neighbour")
	p["signal_drum"] = func(x):
		x.u.status["ammo"] = 1
		Rules.apply(x.s, {"type": Types.RELOAD, "unit": x.u.id})
		return _expect(GearFx.is_marked(x.s, x.foe) or GearFx.is_marked(x.s, x.near), "reload Marked nobody")
	p["ember_loader"] = func(x):
		x.u.status["ammo"] = 1
		Rules.apply(x.s, {"type": Types.RELOAD, "unit": x.u.id})
		return _expect(GearFx.is_burning(x.s, x.near), "reload lit nobody")
	p["ready_stance"] = func(x):
		x.u.status["ammo"] = 1
		Rules.apply(x.s, {"type": Types.RELOAD, "unit": x.u.id})
		return _expect(x.u.overwatch, "reload did not set overwatch")
	p["bounty_ledger"] = func(x):
		x.u.cooldowns["lockdown"] = 4
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(int(x.u.cooldowns["lockdown"]) == 3, "cooldown not cut")
	p["blood_clock"] = func(x):
		x.u.cooldowns["lockdown"] = 4
		x.foe.pos = x.u.pos + Vector2i(2, 0)
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(int(x.u.cooldowns["lockdown"]) == 3, "cooldown not cut")
	p["tracer_rounds"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Combat.has_status(x.s, x.foe, "tagged"), "not Marked")
	p["suppressor"] = func(x):
		x.foe.status["alerted"] = false
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Combat.has_status(x.s, x.foe, "tagged"), "unaware target not Marked")
	p["smart_link"] = func(x):
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		return _expect(GearFx.smart_link_shot(x.s, x.u, x.foe), "no smart-link shot")
	p["spotter_scope"] = func(x):
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		return _expect(_term(Combat.hit_chance(x.s, x.u, x.foe), "Dead reckoning") == 100, "a Marked enemy can still be missed")
	p["compensator"] = func(x):
		x.near.pos = x.foe.pos + Vector2i(1, 0)
		x.u.abilities.append("suppress")
		Rules.apply(x.s, {"type": Types.ABILITY, "unit": x.u.id, "ability": "suppress", "target": x.foe.id})
		return _expect(Combat.has_status(x.s, x.near, "suppressed"), "the neighbour wasn't pinned")
	p["shock_rounds"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(Combat.has_status(x.s, x.foe, "suppressed"), "not Suppressed")
	p["rotary_feed"] = func(x):
		x.near.pos = x.foe.pos + Vector2i(1, 0)
		GearFx.on_suppress(x.s, x.u, x.foe)
		return _expect(Combat.has_status(x.s, x.near, "suppressed"), "cone missed the neighbour")
	p["hollow_points"] = func(x):
		x.foe.status["suppressed"] = Combat.phase_index(x.s) + 2
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(GearTricks.is_rooted(x.s, x.foe), "target not rooted")
	p["bipod"] = func(x):
		var before := Ammo.rounds(x.u)
		GearFx.after_shot(x.s, x.u, x.foe, true, true, 3)
		return _expect(Ammo.rounds(x.u) == before - 1, "no second overwatch shot")
	p["motion_tracker"] = func(x):
		x.s.phase = Types.Phase.ENEMY
		x.foe.pos = x.u.pos + Vector2i(6, 0)
		Vision.on_step(x.s, x.foe)
		return _expect((x.s.vision.get("blips", {}) as Dictionary).has(x.foe.id), "no blip")
	p["rangefinder"] = func(x): return _expect(GearFx.overwatch_range_bonus(x.u) >= 20, "no range")
	p["expanding_rounds"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, true, true, 3)
		var hp: int = x.foe.hp
		GearFx.on_team_phase_start(x.s)
		return _expect(x.foe.status.get("wound") == null and x.foe.hp == hp - 3, "the wound didn't open")
	p["ghillie_cloak"] = func(x):
		x.foe.status["alerted"] = false
		return _expect(_term(Combat.hit_chance(x.s, x.u, x.foe, x.u.pos, true), "Still life") == 100, "no sure shot at the unaware")
	p["match_rounds"] = func(x):
		var hp: int = x.foe.hp
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(x.foe.hp == hp - 3, "the second hit didn't repeat")
	p["slug_rounds"] = func(x):
		var at: Vector2i = x.near.pos
		GearFx.after_shot(x.s, x.u, x.near, true, false, 3)
		return _expect(x.near.pos != at or x.near.hp < x.near.max_hp, "target not shoved")
	p["choke"] = func(x):
		x.foe.pos = x.u.pos + Vector2i(2, 0)
		x.near.pos = x.foe.pos + Vector2i(1, 0)
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 4)
		return _expect(x.near.hp < x.near.max_hp, "neighbour untouched")
	p["exo_frame"] = func(x): return _expect(Loadout.pocket_count(x.rec) == GearData.POCKETS + 1, "no 3rd pocket")
	p["bayonet"] = func(x):
		x.foe.pos = Vector2i(5, 4)
		x.near.hp = 0
		GearFx.on_kill(x.s, x.u, x.near, false)
		return _expect(x.foe.hp < x.foe.max_hp, "no stab at the adjacent enemy")
	p["bio_mesh"] = func(x):
		x.u.infection = 30
		x.u.hp = x.u.max_hp - 5
		var hp: int = x.u.hp
		GearFx.on_team_phase_start(x.s)
		return _expect(x.u.hp > hp, "no heal per awake mutation")
	p["spore_rounds"] = func(x):
		GearFx.after_shot(x.s, x.u, x.foe, false, false)
		return _expect(x.u.infection == 2, "no self Infection")
	p["symbiotic_suit"] = func(x):
		var left := GearFx.mutation_cost(x.s, x.u, 10)
		return _expect(left == 0 and x.u.hp == x.u.max_hp - 2, "cost not paid in HP")
	p["mycelial_weave"] = func(x):
		GearFx.damage_taken(x.s, x.u, 2, x.foe)
		return _expect(Hazards.at(x.s, x.foe.pos).get("kind", "") == "acid", "no acid on the attacker")
	p["leech_rounds"] = func(x):
		x.u.infection = 30
		x.u.hp = 3
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(x.u.hp == 4, "no heal")
	p["filter_mask"] = func(x): return _expect(GearFx.hazard_hit(x.s, x.u, {"kind": "spore"}, 0, 10).y == 0, "spores still infect")
	p["hazard_liner"] = func(x): return _expect(GearFx.bite_infection(x.s, x.u, 10) == 5, "full Infection")
	p["purifier_rounds"] = func(x):
		x.u.infection = 20
		GearFx.after_shot(x.s, x.u, x.foe, true, false, 3)
		return _expect(x.u.infection == 17, "no Infection removed")
	p["purge_canister"] = func(x):
		x.u.infection = 20
		x.foe.hp = 0
		GearFx.on_kill(x.s, x.u, x.foe, false)
		return _expect(x.u.infection == 15, "no Infection removed")
	p["plated_rig"] = func(x): return _expect(GearFx.damage_taken(x.s, x.u, 4, x.foe) == 2, "a hit wasn't halved")
	p["riot_shield"] = func(x):
		var own := _term(Combat.hit_chance(x.s, x.foe, x.u), "Riot shield") == -Combat.COVER_HALF
		var shared := _term(Combat.hit_chance(x.s, x.foe, x.ally), "Shield cover") == -Combat.COVER_HALF
		return _expect(own and shared, "no cover (own %s, ally %s)" % [own, shared])
	# Prototypes
	p["spotter_flare"] = func(x):
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		return _expect(GearFx.hazard_hit(x.s, x.foe, {"kind": "fire", "source": x.u.id}, 2, 0).x == 4, "not doubled")
	p["scorched_earth"] = func(x):
		x.ally.infection = 30
		var hit := GearFx.hazard_hit(x.s, x.ally, {"kind": "fire", "source": x.u.id}, 2, 0)
		return _expect(hit == Vector2i.ZERO and x.ally.infection == 20, "fire hurt the squad or burned nothing off")
	p["killbox"] = func(x):
		x.foe.status["tagged"] = Combat.phase_index(x.s) + 2
		return _expect(_term(Combat.hit_chance(x.s, x.u, x.foe, x.u.pos, true), "Killbox") == 100, "no aim term")
	p["crossfire"] = func(x):
		x.s.phase = Types.Phase.ENEMY
		x.u.overwatch = true
		x.u.status["ow_until"] = Combat.phase_index(x.s) + 2
		x.foe.status["suppressed"] = Combat.phase_index(x.s) + 2
		GearFx.on_enemy_phase_end(x.s)
		return _expect(_logged(x.s, "shot", "unit", x.u.id), "no crossfire shot")
	p["breach_and_clear"] = func(x):
		x.s.grid.set_tile(x.near.pos + Vector2i(-1, 0), Types.Tile.LOW)
		x.u.pos = x.near.pos + Vector2i(2, 0)
		x.near.status["suppressed"] = Combat.phase_index(x.s) + 2
		var odds := Combat.hit_chance(x.s, x.u, x.near)
		return _expect(_term(odds, "Breach and clear") > 0 or odds.get("cover", 0) == 0, "cover still counts")
	p["hold_position"] = func(x):
		x.u.abilities.append("suppress")
		Rules.apply(x.s, {"type": Types.ABILITY, "unit": x.u.id, "ability": "suppress", "target": x.foe.id})
		return _expect(x.u.actions_left == 1, "Suppress still ended the turn")
	p["feral_grip"] = func(x):
		x.u.hp = 3
		GearFx.after_shot(x.s, x.u, x.near, true, false, 3)
		return _expect(x.u.hp == 4, "no heal")
	p["bloodletting"] = func(x):
		x.u.actions_left = 1
		GearFx.on_purge(x.s, x.u, x.ally, 15)
		return _expect(x.u.actions_left == 2 and x.u.infection == 15, "no action or Infection taken")
	p["quarantine_field"] = func(x):
		x.u.hunkered = true
		x.u.status["hunker_until"] = Combat.phase_index(x.s) + 2
		return _expect(GearFx.bite_infection(x.s, x.ally, 10) == 0, "ally still infected")
	p["firestarter"] = func(x):
		GearFx.after_shot(x.s, x.u, x.near, true, false, 3)
		return _expect(GearFx.is_burning(x.s, x.near), "not Burning")
	p["pinpoint"] = func(x):
		GearFx.on_suppress(x.s, x.u, x.foe)
		return _expect(Combat.has_status(x.s, x.foe, "tagged"), "not Marked")
	p["overlook"] = func(x):
		x.u.overwatch = true
		return _expect(_term(Combat.hit_chance(x.s, x.foe, x.ally), "Overlook") == -10, "ally gets no defense")
	p["cauterizer"] = func(x):
		Hazards.add(x.s, [x.u.pos], "fire", 2)
		var safe := GearFx.hazard_hit(x.s, x.u, {"kind": "fire", "source": -1}, 2, 0).x == 0
		return _expect(safe and _term(Combat.hit_chance(x.s, x.foe, x.u), "Cauterizer") == -10, "fire hurts or no defense")
	p["reaper_blade"] = func(x): return _expect(x.u.abilities.has("lunge"), "Lunge not granted")
	p["trench_maul"] = func(x): return _expect(x.u.abilities.has("bash"), "Bash not granted")
	for sig in ["lockdown", "deadeye", "quarantine_field", "bring_down", "flashover", "vent", "death_sweep", "provoke"]:
		p["sig_" + sig] = func(x): return _expect(x.u.abilities.has(sig), "%s not granted" % sig)
	return p


func _expect(ok: bool, why: String) -> String:
	return "" if ok else why


func _passive_ctx(id: String) -> Dictionary:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, U_AT)
	var ally := _add(s, "medic", Types.Team.PLAYER, ALLY_AT)
	var foe := _add(s, "spitter", Types.Team.ENEMY, FOE_AT)
	var near := _add(s, "runner", Types.Team.ENEMY, Vector2i(4, 6))
	for e in [foe, near]:
		e.max_hp = 30
		e.hp = 30
	u.max_hp = 10
	u.hp = 10
	GearTags.set_progression(null)
	var rec := {"id": u.id, "kind": u.kind}
	Loadout.equip({"supplies": 0, "soldiers": [rec]}, rec, id)
	GearRun.apply_to_unit(u, rec)
	return {"s": s, "u": u, "ally": ally, "foe": foe, "near": near, "rec": rec}


## Items that are only flat stats: the stats land on the unit.
func _stat_ok(id: String) -> String:
	var st := GearData.stats(id, 1)
	if st.is_empty():
		return ""
	var base := _add(_state(), "trooper", Types.Team.PLAYER, U_AT)
	base.max_hp = 10
	var x := _passive_ctx(id)
	var u: Unit = x.u
	for k in st:
		match k:
			"aim": if u.aim != base.aim + int(st.aim): return "aim %d" % u.aim
			"mobility": if u.mobility != base.mobility + int(st.mobility): return "mobility %d" % u.mobility
			"max_hp": if u.max_hp != base.max_hp + int(st.max_hp): return "max HP %d" % u.max_hp
			"armor": if int(u.status.get("armor", 0)) != int(st.armor): return "armor"
			"defense": if u.defense != base.defense + int(st.defense): return "defense %d" % u.defense
	return ""


func test_every_item_and_prototype_has_a_case() -> void:
	var probes := _probes()
	for id in GearData.ITEMS.keys() + GearData.PROTOTYPES.keys():
		var gadget := GearFx.GADGETS.has(id)
		var stat_only := not GearData.stats(id, 1).is_empty() and not probes.has(id)
		assert_true(gadget or stat_only or probes.has(id), "%s has no audit probe in tests/test_item_audit.gd" % id)
		assert_true(not GearFx.is_pending(id), "%s is still parked in GearFx.PENDING" % id)


func test_every_passive_item_and_prototype_works() -> void:
	var probes := _probes()
	for id in probes:
		var x := _passive_ctx(id)
		var from: int = x.s.log.size()
		var err: String = (probes[id] as Callable).call(x)
		assert_eq(err, "", "%s has its effect" % id)
		for ev in x.s.log.slice(from):
			assert_eq(_beat_gap(ev), "", "%s: event %s has a view beat" % [id, ev.get("type")])
	for id in GearData.ITEMS:
		assert_eq(_stat_ok(id), "", "%s stats land on the soldier" % id)
	GearTags.set_progression(false)


## "" if the event player has a beat of its own for `ev`.
func _beat_gap(ev: Dictionary) -> String:
	var type := str(ev.get("type", ""))
	if type == "gear":
		var item := str(ev.get("item", ""))
		return "" if EventPlayer.GEAR_PROCS.has(item) or item in ["mark", "suppress"] or GearData.exists(item) else "gear proc %s has no name" % item
	if type == "ability":
		var ab := str(ev.get("ability", ""))
		return "" if ItemBeats.has_look(ab) or EventPlayer.OWN_ABILITY_BEATS.has(ab) else "ability %s" % ab
	var ep: Object = EventPlayer.new()
	var ok: bool = ep.has_method("_beat_" + type) or EnemyBeats.handles(ev)
	ep.free()
	return "" if ok else "no _beat_%s" % type


## Every set bonus does both halves of what the tag card says.
func test_set_bonuses_do_what_they_say() -> void:
	var x := _passive_ctx("laser_sight")
	var s: GameState = x.s
	var u: Unit = x.u
	var set_on := func(tag: String) -> void: u.status["gear_tags"] = {tag: GearData.SET_THRESHOLD}
	# Burn: +1 Burning turn.
	set_on.call("Burn")
	GearFx.ignite(s, u, x.foe, 1)
	assert_eq(int(x.foe.status.burning), 2, "Burn set: +1 turn")
	# Mark: the second hit each turn on a Marked enemy deals double.
	set_on.call("Mark")
	x.foe.status["tagged"] = Combat.phase_index(s) + 2
	var fhp: int = x.foe.hp
	GearFx.after_shot(s, u, x.foe, true, false, 2)
	GearFx.after_shot(s, u, x.foe, true, false, 2)
	assert_eq(x.foe.hp, fhp - 2, "Mark set: second hit doubles")
	# Suppress: a Suppressed enemy that moves draws a free shot.
	set_on.call("Suppress")
	GearFx._suppress(s, u, x.foe)
	assert_true(GearFx.suppress_shot_ready(s, u, x.foe, x.foe.pos + Vector2i(1, 0)), "Suppress set: free shot ready")
	assert_true(Combat.reactions_to_move(s, x.foe, x.foe.pos + Vector2i(1, 0)).has(u), "Suppress set: reacts to the move")
	Combat.resolve_reactions(s, x.foe, [u] as Array[Unit])
	assert_true(_logged(s, "gear", "item", "suppress_set"), "Suppress set: took the shot")
	assert_true(not GearFx.suppress_shot_ready(s, u, x.foe, x.foe.pos), "only once per Suppress")
	# Overwatch: a kill on overwatch keeps the watch up (covered in test_gear_fx).
	# Strain: mutations cost 5 less.
	set_on.call("Strain")
	u.infection = 30
	assert_eq(Mutations.use_cost(u, "adrenal_surge"), maxi(5, MutationData.base_use_cost("adrenal_surge") - 5), "Strain set: cheaper mutations")
	# Purge: purged allies heal 1, and no Infection for you that turn.
	set_on.call("Purge")
	u.infection = 0
	x.ally.hp = 3
	GearFx.on_purge(s, u, x.ally, 10)
	assert_eq(x.ally.hp, 4, "Purge set: ally heals")
	Infection.add(s, u, 10)
	assert_eq(u.infection, 0, "Purge set: no Infection on a purge turn")
	# Guard: +5 to adjacent allies, and takes one hit meant for them each enemy phase.
	set_on.call("Guard")
	assert_eq(_term(Combat.hit_chance(s, x.foe, x.ally), "Guarded"), -5, "Guard set: defense")
	s.phase = Types.Phase.ENEMY
	var hp := u.hp
	Rules.deal_damage(s, x.ally, 2, x.foe)
	assert_eq(u.hp, hp - 2, "Guard set: took the hit")
	var ally_hp: int = x.ally.hp
	Rules.deal_damage(s, x.ally, 2, x.foe)
	assert_eq(x.ally.hp, ally_hp - 2, "only once per enemy phase")
	# Survival halves: statused enemies, and the Infected at Exposed, hit for 1 less.
	for pair in [["Burn", "burning", 2], ["Mark", "tagged", Combat.phase_index(s) + 2], ["Suppress", "suppressed", Combat.phase_index(s) + 2]]:
		set_on.call(pair[0])
		x.foe.status[pair[1]] = pair[2]
		assert_eq(GearFx.survival_cut(s, u, x.foe), 1, "%s set: statused enemy hits for 1 less" % pair[0])
		x.foe.status.erase(pair[1])
	# Close: a kill within 3 refunds a move (covered in test_gear_fx).
	GearTags.set_progression(false)


func test_doctrines_are_wired() -> void:
	# Spore filters: a quarter less spore Infection. Steady nerves: talking down is free.
	var x := _passive_ctx("laser_sight")
	x.u.status["doctrines"] = ["spore_filters", "steady_nerves"]
	assert_eq(GearFx.hazard_hit(x.s, x.u, {"kind": "spore"}, 0, 12).y, 9, "Spore filters")
	x.ally.status["lapsed"] = true
	x.ally.ai_controlled = true
	assert_true(Rules.apply(x.s, {"type": Types.ABILITY, "unit": x.u.id, "ability": "talk_down", "target": x.ally.id}), "talk down")
	assert_eq(x.u.actions_left, Types.ACTIONS_PER_TURN, "Steady nerves: no action spent")
	# Every doctrine id is read somewhere in the rules (not just listed in GearData).
	var code := ""
	for path in ["res://gear/gear_fx.gd", "res://gear/gear_run.gd", "res://run/run_rules.gd", "res://nodes/depot.gd",
			"res://progression/class_abilities.gd", "res://gear/deploy_orders.gd"]:
		code += FileAccess.get_file_as_string(path)
	for id in GearData.DOCTRINES:
		assert_true(code.contains("\"%s\"" % id), "doctrine %s has no rules effect" % id)
	GearTags.set_progression(false)


func test_every_deployment_order_fills_for_some_class() -> void:
	var rng := RandomNumberGenerator.new()
	for id in DeployOrders.ORDERS:
		var filled := false
		for kind in GearData.CLASS_LANES:
			rng.seed = 3
			var card := DeployOrders.build(rng, {"id": 1, "kind": kind, "player": 0}, id)
			if not card.is_empty() and not (card.contents as Array).is_empty():
				filled = true
				break
		assert_true(filled, "order %s can be filled" % id)
