extends TestCase
## Capstones (6 of a tag), the Burn mutation, and the build cuts from the class build atlas:
## the four capstone rules, their beats and sounds, the easy builds reaching them, and the
## renames, merges and retags that shipped with them.

const Sfx := preload("res://view/sfx.gd")
const EventPlayer := preload("res://view/event_player.gd")

const OPEN := [
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
	"..............",
]


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
	else:
		u.max_hp = 40
		u.hp = 40
	return u


## A soldier with `n` pieces of `tag` and no gear, enough for the set bonus and the capstone.
func _stack(u: Unit, tag: String, n: int) -> void:
	GearTags.set_progression(null)
	u.status["gear"] = {}
	u.status["gear_tags"] = {tag: n}


func _logged(s: GameState, key: String, value: Variant) -> bool:
	return s.log.any(func(ev): return ev.get("type") == "gear" and ev.get(key) == value)


func _term(odds: Dictionary, label: String) -> int:
	for t in odds.breakdown:
		if t[0] == label:
			return int(t[1])
	return 0


# --- the table ---------------------------------------------------------------------------

func test_every_capstone_has_a_name_text_beat_and_sound() -> void:
	assert_eq(GearData.capstone_tags(), ["Burn", "Mark", "Overwatch", "Guard"] as Array[String], "the first four tags have capstones")
	assert_eq(GearData.CAPSTONE_THRESHOLD, 6, "six pieces")
	for tag in GearData.capstone_tags():
		var info: Dictionary = GearData.TAG_INFO[tag]
		assert_true(str(info.capstone_name) != "" and str(info.capstone) != "", "%s capstone is written up" % tag)
		assert_true(Glossary.has("cap_" + tag.to_lower()), "%s capstone has a glossary card" % tag)
	for item in ["wildfire", "warrant", "warrant_served", "field_of_fire", "aegis_hold", "aegis_return"]:
		assert_true(EventPlayer.GEAR_PROCS.has(item), "%s has a beat" % item)
		var snd: String = EventPlayer.GEAR_PROCS[item].get("sound", "")
		assert_true(snd != "" and Sfx.SOUNDS.has(snd), "%s has a sound" % item)
		assert_true(ResourceLoader.exists("res://audio/%s.wav" % snd), "%s.wav is generated" % snd)


func test_capstone_counts_and_preview_flags() -> void:
	var c := {"Guard": 6, "Mark": 5}
	assert_true(GearTags.has_capstone(c, "Guard"), "Guard at 6")
	assert_true(not GearTags.has_capstone(c, "Mark"), "Mark at 5")
	assert_true(not GearTags.has_capstone({"Close": 9}, "Close"), "Close has no capstone yet")
	assert_eq(GearTags.active_capstones(c), ["Guard"] as Array[String], "active capstones")
	var d := GearTags.diff({"Mark": 5, "Close": 5}, {"Mark": 6, "Close": 6})
	assert_true(d[0].cap_unlocks and d[0].tag == "Mark", "the sixth Mark piece completes the capstone")
	assert_true(not d[1].has("cap_unlocks"), "tags without a capstone carry no flag")


# --- Wildfire (Burn) ---------------------------------------------------------------------

func test_wildfire_spreads_burning_and_ignores_armour() -> void:
	var s := _state()
	var u := _add(s, "hazmat", Types.Team.PLAYER, Vector2i(1, 4))
	var a := _add(s, "runner", Types.Team.ENEMY, Vector2i(5, 4))
	var b := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	var far := _add(s, "runner", Types.Team.ENEMY, Vector2i(10, 4))
	a.status["armour"] = 2
	_stack(u, "Burn", 6)
	GearFx.ignite(s, u, a, 1)
	var hp := a.hp
	GearFx.on_team_phase_start(s)
	assert_eq(a.hp, hp - GearFx.BURN_DAMAGE, "the burn tick ignores armour")
	assert_true(GearFx.is_burning(s, b), "the neighbour caught fire")
	assert_true(not GearFx.is_burning(s, far), "the far one did not")
	assert_true(_logged(s, "item", "wildfire"), "Wildfire shows its beat")
	# One ring a turn: the far enemy next to the newly lit one burns the turn after.
	far.pos = Vector2i(7, 4)
	GearFx.on_team_phase_start(s)
	assert_true(GearFx.is_burning(s, far), "the fire keeps walking")
	# Without the capstone the same armour blunts the tick and nothing spreads.
	var s2 := _state()
	var u2 := _add(s2, "hazmat", Types.Team.PLAYER, Vector2i(1, 4))
	var a2 := _add(s2, "runner", Types.Team.ENEMY, Vector2i(5, 4))
	var b2 := _add(s2, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	a2.status["armour"] = 2
	_stack(u2, "Burn", 5)
	GearFx.ignite(s2, u2, a2, 1)
	var hp2 := a2.hp
	GearFx.on_team_phase_start(s2)
	assert_eq(a2.hp, hp2 - 1, "armour still blunts it at 5 pieces")
	assert_true(not GearFx.is_burning(s2, b2), "and no spread")
	GearTags.set_progression(false)


func test_wildfire_fire_tiles_ignore_armour_too() -> void:
	var s := _state()
	var u := _add(s, "hazmat", Types.Team.PLAYER, Vector2i(1, 4))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(5, 4))
	foe.status["armour"] = 2
	_stack(u, "Burn", 6)
	var hp := foe.hp
	GearFx.hazard_damage(s, foe, {"kind": "fire", "source": u.id}, 2)
	assert_eq(foe.hp, hp - 2, "fire from a Wildfire soldier ignores armour")
	assert_true(not foe.status.has("ignore_armour"), "and the flag does not stick")
	GearTags.set_progression(false)


# --- Warrant (Mark) ----------------------------------------------------------------------

func test_warrant_marks_never_expire_and_the_squad_aims_better() -> void:
	var s := _state()
	var u := _add(s, "marksman", Types.Team.PLAYER, Vector2i(1, 4))
	var ally := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 4))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(8, 4))
	_stack(u, "Mark", 6)
	Rules.apply(s, {"type": Types.ABILITY, "unit": u.id, "ability": "tag", "target": foe.id})
	assert_true(foe.status.get("warrant", false), "the Marksman's Mark is a Warrant")
	assert_eq(_term(Combat.hit_chance(s, ally, foe), "Warrant"), GearFx.WARRANT_AIM, "+20 aim for the squad")
	s.turn = 40
	Combat._sweep(s)
	assert_true(Combat.has_status(s, foe, "tagged"), "forty turns later it is still Marked")
	# A Mark from a soldier without the capstone is an ordinary one.
	var s2 := _state()
	var u2 := _add(s2, "marksman", Types.Team.PLAYER, Vector2i(1, 4))
	var foe2 := _add(s2, "runner", Types.Team.ENEMY, Vector2i(8, 4))
	_stack(u2, "Mark", 5)
	Rules.apply(s2, {"type": Types.ABILITY, "unit": u2.id, "ability": "tag", "target": foe2.id})
	assert_true(not foe2.status.get("warrant", false), "five pieces is just the set bonus")
	GearTags.set_progression(false)


func test_warrant_kill_refunds_an_action_once_a_turn_and_the_mark_jumps() -> void:
	var s := _state()
	var u := _add(s, "marksman", Types.Team.PLAYER, Vector2i(1, 4))
	var a := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	var b := _add(s, "runner", Types.Team.ENEMY, Vector2i(8, 4))
	var c := _add(s, "runner", Types.Team.ENEMY, Vector2i(9, 4))
	_stack(u, "Mark", 6)
	GearFx._mark(s, a, 1, u)
	u.actions_left = 1
	a.hp = 0
	GearFx.on_kill(s, u, a, false)
	assert_eq(u.actions_left, 2, "killing a Warrant target gives an action back")
	assert_true(b.status.get("warrant", false), "and the Warrant jumps to the nearest enemy")
	assert_true(_logged(s, "item", "warrant_served"), "with a beat")
	b.hp = 0
	GearFx.on_kill(s, u, b, false)
	assert_eq(u.actions_left, 2, "once a turn")
	assert_true(c.status.get("warrant", false), "the Mark still jumps")
	GearTags.set_progression(false)


# --- Field of Fire (Overwatch) -----------------------------------------------------------

func test_field_of_fire_keeps_overwatch_up_for_every_mover() -> void:
	var s := _state()
	var w := _add(s, "marksman", Types.Team.PLAYER, Vector2i(1, 4))
	var e1 := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	var e2 := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 5))
	w.overwatch = true
	w.status["ow_until"] = Combat.phase_index(s) + 2
	_stack(w, "Overwatch", 6)
	s.phase = Types.Phase.ENEMY
	assert_true(Kit.keep_overwatch(s, w, e1), "the first shot keeps overwatch up")
	assert_true(not Kit.can_react(w, e1), "but never the same mover twice running")
	assert_true(Kit.can_react(w, e2), "the next enemy to move draws a shot")
	assert_true(Kit.keep_overwatch(s, w, e2), "and the one after that")
	assert_true(_logged(s, "item", "field_of_fire"), "Field of Fire shows its beat")
	Combat.resolve_reactions(s, e1, [w] as Array[Unit])
	assert_true(w.overwatch, "a real reaction shot leaves the watcher on overwatch")
	# Five pieces: a reaction shot spends overwatch as usual.
	var s2 := _state()
	var w2 := _add(s2, "marksman", Types.Team.PLAYER, Vector2i(1, 4))
	var e3 := _add(s2, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	w2.overwatch = true
	w2.status["ow_until"] = Combat.phase_index(s2) + 2
	_stack(w2, "Overwatch", 5)
	assert_true(not Kit.keep_overwatch(s2, w2, e3), "five pieces: one shot")
	GearTags.set_progression(false)


# --- Aegis (Guard) -----------------------------------------------------------------------

func test_aegis_returns_intercepted_damage_and_cannot_be_one_shot() -> void:
	var s := _state()
	var g := _add(s, "trooper", Types.Team.PLAYER, Vector2i(4, 4))
	var ally := _add(s, "medic", Types.Team.PLAYER, Vector2i(5, 4))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	_stack(g, "Guard", 6)
	s.phase = Types.Phase.ENEMY
	var g_hp := g.hp
	var foe_hp := foe.hp
	var ally_hp := ally.hp
	Rules.deal_damage(s, ally, 3, foe)
	assert_eq(g.hp, g_hp - 3, "the Guard soldier took the hit meant for the ally")
	assert_eq(ally.hp, ally_hp, "the ally is untouched")
	assert_eq(foe.hp, foe_hp - 3, "and the attacker takes the same damage back")
	assert_true(_logged(s, "item", "aegis_return"), "with a beat")
	# Nothing kills them from above 1 HP in one hit.
	g.hp = 4
	Rules.deal_damage(s, g, 12, foe)
	assert_eq(g.hp, 1, "left on 1 HP")
	assert_true(g.is_alive(), "still standing")
	assert_true(_logged(s, "item", "aegis_hold"), "Aegis shows its beat")
	Rules.deal_damage(s, g, 1, foe)
	assert_true(not g.is_alive(), "but at 1 HP the next hit counts")
	# Five pieces: the same hit kills.
	var s2 := _state()
	var g2 := _add(s2, "trooper", Types.Team.PLAYER, Vector2i(4, 4))
	var foe2 := _add(s2, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	_stack(g2, "Guard", 5)
	s2.phase = Types.Phase.ENEMY
	g2.hp = 4
	Rules.deal_damage(s2, g2, 12, foe2)
	assert_true(not g2.is_alive(), "five pieces: no Aegis")
	GearTags.set_progression(false)


func test_aegis_keeps_last_stand_for_later() -> void:
	var s := _state()
	var g := _add(s, "trooper", Types.Team.PLAYER, Vector2i(4, 4))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	_stack(g, "Guard", 6)
	g.status["perks"] = ["last_stand"]
	g.hp = 4
	s.phase = Types.Phase.ENEMY
	Rules.deal_damage(s, g, 12, foe)
	assert_eq(g.hp, 1, "Aegis took the first lethal hit")
	assert_true(not g.status.has("k_last_stand"), "Last Stand is still unspent")
	GearTags.set_progression(false)


# --- Kindled Spores (the Burn mutation) --------------------------------------------------

func test_kindled_spores_ignite_the_target_and_burn_off_spores() -> void:
	var s := _state()
	var u := _add(s, "trooper", Types.Team.PLAYER, Vector2i(1, 4))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(6, 4))
	GearTags.set_progression(null)
	u.status["gear"] = {}
	u.status["mutations"] = {"mutating": "kindled_spores"}
	u.infection = 60
	Hazards.add(s, [Vector2i(6, 5), Vector2i(7, 4)], "spore", 3)
	var inf := u.infection
	GearFx.after_shot(s, u, foe, true, false, 3)
	assert_true(GearFx.is_burning(s, foe), "the hit sets the target Burning")
	assert_eq(Hazards.at(s, Vector2i(6, 5)).get("kind", ""), "fire", "spores next to it flare into fire")
	assert_eq(u.infection, inf + GearFx.KINDLED_INFECTION, "the drawback: Infection")
	assert_eq(MutationData.get_def("kindled_spores").tag, "Burn", "it counts toward Burn")
	var asleep := _add(s, "trooper", Types.Team.PLAYER, Vector2i(2, 4))
	asleep.status["gear"] = {}
	asleep.status["mutations"] = {"mutating": "kindled_spores"}
	asleep.infection = 10
	var foe2 := _add(s, "runner", Types.Team.ENEMY, Vector2i(9, 6))
	GearFx.after_shot(s, asleep, foe2, true, false, 3)
	assert_true(not GearFx.is_burning(s, foe2), "dormant below Mutating")
	GearTags.set_progression(false)


# --- the easy builds ---------------------------------------------------------------------

func test_easy_builds_are_legal_and_reach_six_in_their_tag() -> void:
	assert_eq(Builds.EASY.size(), 8, "eight easy builds")
	var classes := {}
	for id in Builds.BUILDS:
		var b: Dictionary = Builds.BUILDS[id]
		if id in Builds.EASY:
			classes[b.class] = true
		var pool := PerkData.pool(b.class)
		assert_true((b.perks as Array).size() <= 4, "%s takes at most four perks" % id)
		for p in b.perks:
			assert_true(pool.has(p), "%s: %s is a %s perk" % [id, p, b.class])
		var slots := {}
		for item in b.gear:
			assert_true(GearData.exists(item), "%s: %s exists" % [id, item])
			slots[GearData.slot_of(item)] = true
		assert_eq(slots.size(), (b.gear as Array).size(), "%s: one item per gear slot" % id)
		var graft_slots := {}
		for slot in b.grafts:
			assert_eq(GraftData.get_def(b.grafts[slot]).slot, slot, "%s: graft in its slot" % id)
			graft_slots[slot] = true
		for slot in b.mutations:
			assert_eq(MutationData.get_def(b.mutations[slot]).slot, slot, "%s: mutation in its slot" % id)
		if b.gun != "":
			assert_true((Weapons.get_gun(b.gun).classes as Array).has(b.class), "%s: %s fits the class" % [id, b.gun])
		var counts := Builds.counts(id)
		assert_true(int(counts.get(b.tag, 0)) >= GearData.CAPSTONE_THRESHOLD, "%s reaches %d %s (has %d)" % [id, GearData.CAPSTONE_THRESHOLD, b.tag, counts.get(b.tag, 0)])
		if GearData.has_capstone(b.tag):
			assert_true(GearTags.active_capstones(counts).has(b.tag), "%s switches its capstone on" % id)
	assert_eq(classes.size(), 8, "one easy build per class")
	for tag in GearData.capstone_tags():
		assert_true(Builds.BUILDS.values().any(func(b): return b.tag == tag), "a build reaches the %s capstone" % tag)
	GearTags.set_progression(false)


# --- renames, merges and retags ----------------------------------------------------------

func test_renames_merges_and_retags() -> void:
	assert_eq(Combat.ABILITIES.tag.name, "Mark", "Marksman Tag is Mark")
	assert_eq(ClassAbilities.ABILITIES.guard.name, "Brace", "Warden Guard is Brace")
	assert_eq(PerkData.PERKS.purge.name, "Flush", "Medic perk Purge is Flush")
	assert_eq(ClassAbilities.ABILITIES.purge.name, "Flush", "and so is its ability")
	assert_true(not PerkData.PERKS.has("door_kicker"), "Door Kicker folded into Kick In")
	assert_eq(PerkData.PERKS.kick_in.mobility, 1, "Kick In carries the +1 move")
	assert_eq(PerkData.PERKS.thick_blood.tag, "Strain", "Thick Blood counts")
	assert_eq(PerkData.PERKS.heavy_plating.tag, "Guard", "Heavy Plating counts")
	assert_eq(GraftData.get_def("lattice_sight").tag, "Overwatch", "Lattice sight is Overwatch")
	assert_true(PerkData.PERKS.has("shaped_charge"), "Shaped Charge is a Breacher perk")
	assert_true(MetaUnlocks.PACKS.gear_2.content.has("crossfire") and MetaUnlocks.PACKS.gear_2.content.has("quarantine_field"),
		"Crossfire and Quarantine field moved to Specialist")
	assert_true(not MetaUnlocks.PACKS.gear_3.content.has("crossfire"), "and left Prototype")


func test_last_wall_shields_the_allies_next_to_it() -> void:
	var s := _state()
	var w := _add(s, "warden", Types.Team.PLAYER, Vector2i(4, 4))
	var ally := _add(s, "medic", Types.Team.PLAYER, Vector2i(5, 4))
	var far := _add(s, "trooper", Types.Team.PLAYER, Vector2i(0, 0))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(7, 4))
	w.status["perks"] = ["last_wall"]
	w.hp = 3
	s.phase = Types.Phase.ENEMY
	Rules.deal_damage(s, w, 9, foe)
	assert_eq(w.hp, 1, "dropped to 1 HP instead of dying")
	assert_eq(_term(Combat.hit_chance(s, foe, ally), "Last Wall"), -Kit.LAST_WALL_DEFENSE, "the adjacent ally gets +20 defense")
	assert_eq(_term(Combat.hit_chance(s, foe, far), "Last Wall"), 0, "the far one does not")


func test_shaped_charge_breach_brings_down_the_walls_around_the_target() -> void:
	var rows := [
		"..............",
		"..............",
		"..............",
		"....##........",
		"....##........",
		"..............",
	]
	var s := make_blank(PackedStringArray(rows))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	var b := _add(s, "breacher", Types.Team.PLAYER, Vector2i(2, 2))
	var foe := _add(s, "runner", Types.Team.ENEMY, Vector2i(3, 3))
	foe.max_hp = 60
	foe.hp = 60
	b.status["perks"] = ["shaped_charge"]
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": b.id, "ability": "breach", "target": foe.id}), "breach")
	assert_true(s.grid.tile(Vector2i(4, 3)) != Types.Tile.WALL or s.grid.rubble.has(Vector2i(4, 3)), "the wall beside the target is cracked open")
	assert_true(s.log.any(func(ev): return ev.get("type") == "perk" and ev.get("perk") == "shaped_charge"), "with a beat")
	# Without the perk the wall stands.
	var s2 := make_blank(PackedStringArray(rows))
	s2.turn = 1
	s2.phase = Types.Phase.TEAM
	var b2 := _add(s2, "breacher", Types.Team.PLAYER, Vector2i(2, 2))
	var foe2 := _add(s2, "runner", Types.Team.ENEMY, Vector2i(3, 3))
	foe2.max_hp = 60
	foe2.hp = 60
	assert_true(Rules.apply(s2, {"type": Types.ABILITY, "unit": b2.id, "ability": "breach", "target": foe2.id}), "breach")
	assert_eq(s2.grid.tile(Vector2i(4, 3)), Types.Tile.WALL, "no perk, no hole")
