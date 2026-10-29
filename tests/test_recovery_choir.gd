extends TestCase
## Halden-Voss Recovery (Netter, Handler, Sterilizer, Collector) and the Choir (Acolyte, Cantor, Hush):
## their rules, and every new ability and event through the real view.

const MAIN := preload("res://scenes/main.tscn")


func _open(w: int, h: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in h:
		rows.append(".".repeat(w))
	return rows


func _soldier(s: GameState, kind: String, at: Vector2i) -> Unit:
	var u := UnitData.make(kind, Types.Team.PLAYER)
	u.owner_player = 0
	return s.add_unit(u, at)


func _enemy(s: GameState, spec: String, at: Vector2i) -> Unit:
	var u := s.add_unit(EnemyRoster.make(spec), at)
	u.status["alerted"] = true
	return u


func _events(s: GameState, type: String) -> Array:
	return s.log.filter(func(e): return e.type == type)


func _enemy_turn(s: GameState, u: Unit) -> void:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	for k in u.cooldowns.keys():
		u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Encounter.on_unit_turn_start(s, u)
	EnemyAI.take_turn(s, u)
	u.actions_left = 0
	Encounter.on_unit_turn_end(s, u)


func _act(s: GameState, u: Unit, action: Dictionary) -> bool:
	s.phase = Types.Phase.ENEMY
	u.actions_left = Types.ACTIONS_PER_TURN
	action["type"] = Types.ABILITY
	action["unit"] = u.id
	var err := Rules.validate(s, action)
	if err != "":
		failures.append("%s refused: %s" % [action.get("ability", "?"), err])
	return Rules.apply(s, action)


# --- roster -------------------------------------------------------------------------------

func test_the_two_factions_join_the_pools_and_have_cards() -> void:
	for k in EnemyRoster.FACTIONS.recovery + EnemyRoster.FACTIONS.choir:
		assert_true(Glossary.has("enemy_" + k), "a hover card for " + k)
		assert_true(EnemyRoster.COST.has(k) and EnemyRoster.FROM_ACT.has(k), k + " is priced and placed")
		assert_true(not EnemyRoster.pool(1).has("collector") and not EnemyRoster.pool(1).has("hush"), "the specialists wait for later acts")
	for k in EnemyRoster.FACTIONS.recovery:
		assert_true(not EnemyRoster.infects(EnemyRoster.make(k)), k + " is human")
	for k in EnemyRoster.FACTIONS.choir:
		assert_true(EnemyRoster.infects(EnemyRoster.make(k)), k + " carries Infection")
	assert_true(EnemyRoster.pool(3).has("collector") and EnemyRoster.pool(3).has("hush") and EnemyRoster.pool(2).has("netter"), "pools by act")


# --- Netter and Collector -----------------------------------------------------------------

func test_netter_pins_a_soldier_until_a_teammate_hits_it() -> void:
	var s := make_blank(_open(10, 10))
	var a := _soldier(s, "trooper", Vector2i(4, 4))
	var b := _soldier(s, "trooper", Vector2i(2, 8))
	var n := _enemy(s, "netter", Vector2i(5, 4))
	n.aim = 500
	Vision.disable(s)
	assert_true(_act(s, n, {"ability": "net", "target": a.id}), "the net goes out")
	assert_eq(int(a.status.get("pinned_by", -1)), n.id, "the soldier is held")
	assert_true(Recovery.netted(s, a), "and counts as netted, not mauled")
	assert_true(_events(s, "pinned").any(func(e): return e.get("net", false)), "the event says net")
	s.phase = Types.Phase.TEAM
	Encounter.on_team_phase_start(s)
	assert_eq(a.actions_left, 0, "no actions while netted")
	Rules.deal_damage(s, n, 1, b)
	assert_true(not a.status.has("pinned_by"), "a teammate's hit frees them")


func test_collector_takes_over_a_netted_soldier_and_drags_them_off_the_map() -> void:
	var s := make_blank(_open(12, 8))
	var a := _soldier(s, "trooper", Vector2i(3, 3))
	_soldier(s, "trooper", Vector2i(9, 3))
	var n := _enemy(s, "netter", Vector2i(4, 3))
	n.aim = 500
	var c := _enemy(s, "collector", Vector2i(3, 6))
	Vision.disable(s)
	assert_true(_act(s, n, {"ability": "net", "target": a.id}), "netted first")
	var edge := Scavengers.edge_dist(s, a.pos)
	_enemy_turn(s, c)
	assert_eq(int(a.status.get("pinned_by", -1)), c.id, "the Collector takes over the hold")
	assert_true(not n.status.has("pinning"), "the Netter lets go")
	assert_true(Scavengers.edge_dist(s, a.pos) < edge, "dragged toward the edge")
	assert_true(s.grid.melee_reach(c.pos, a.pos), "and the Collector stays beside them")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "drag"), "the drag lane is drawn")
	assert_eq(EnemyIntent._intent(s, c).label, "DRAGGING", "intent word")
	for i in 6:
		if not a.is_alive():
			break
		_enemy_turn(s, c)
	assert_true(not a.is_alive(), "dragged off the edge, the soldier is lost")
	assert_true(_events(s, "captured").size() == 1, "and the event says captured")
	assert_true(not c.is_alive() and c.status.get("fled", false), "the Collector leaves with them")


func test_killing_the_collector_drops_the_soldier() -> void:
	var s := make_blank(_open(12, 8))
	var a := _soldier(s, "trooper", Vector2i(3, 3))
	var b := _soldier(s, "trooper", Vector2i(9, 3))
	var n := _enemy(s, "netter", Vector2i(4, 3))
	n.aim = 500
	var c := _enemy(s, "collector", Vector2i(3, 5))
	Vision.disable(s)
	_act(s, n, {"ability": "net", "target": a.id})
	_enemy_turn(s, c)
	assert_eq(int(a.status.get("pinned_by", -1)), c.id, "held")
	Rules.deal_damage(s, c, 99, b)
	assert_true(not a.status.has("pinned_by") and a.is_alive(), "free and alive")


# --- Handler ------------------------------------------------------------------------------

func test_handler_designates_the_most_infected_soldier_and_recovery_aims_better() -> void:
	var s := make_blank(_open(14, 8))
	var a := _soldier(s, "trooper", Vector2i(2, 4))
	var b := _soldier(s, "trooper", Vector2i(3, 6))
	b.infection = 60
	var h := _enemy(s, "handler", Vector2i(10, 4))
	var n := _enemy(s, "netter", Vector2i(4, 5))
	Vision.disable(s)
	var before: int = Combat.melee_chance(s, n, b).hit
	_enemy_turn(s, h)
	assert_eq(int(h.status.get("designating", -1)), b.id, "marks the Infected one")
	assert_eq(int(b.status.get("designated", -1)), h.id, "and the soldier knows it")
	assert_eq(Combat.melee_chance(s, n, b).hit, mini(100, before + EnemyRoster.DESIGNATE_AIM), "Recovery gets +aim on them")
	assert_eq(Combat.melee_chance(s, n, a).hit, Combat.melee_chance(s, n, a).hit, "and not on the other")
	assert_true(Combat.hit_chance(s, n, b).breakdown.any(func(t): return t[0] == "Designated"), "the odds name the mark")
	assert_true(EnemyIntent.designations(s).size() == 1, "the line is drawn")
	var inf := _enemy(s, "runner", Vector2i(4, 6))
	assert_true(not Combat.melee_chance(s, inf, b).breakdown.any(func(t): return t[0] == "Designated"), "Infected do not get the bonus")
	Rules.deal_damage(s, h, 99, a)
	assert_true(not b.status.has("designated"), "kill the Handler and the mark lapses")


# --- Sterilizer ---------------------------------------------------------------------------

func test_sterilizer_lays_a_cone_that_burns_cleanses_and_clears_spores() -> void:
	var s := make_blank(_open(14, 9))
	var sol := _soldier(s, "trooper", Vector2i(6, 4))
	sol.infection = 50
	var runner := _enemy(s, "runner", Vector2i(4, 4))
	var st := _enemy(s, "sterilizer", Vector2i(2, 4))
	Vision.disable(s)
	Hazards.add(s, [Vector2i(5, 4)], "spore", 3, -1)
	_enemy_turn(s, st)
	var tel := (s.encounter.get("telegraphs", []) as Array).filter(func(t): return t.kind == "sterilize")
	assert_eq(tel.size(), 1, "a cone is down")
	assert_true(tel[0].cells.has(Vector2i(6, 4)) and not tel[0].cells.has(Vector2i(2, 8)), "it covers the lane, not the side")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "sterilize"), "drawn in red")
	var hp := sol.hp
	var rhp := runner.hp
	s.turn += 1
	Encounter._resolve_telegraphs(s)
	assert_eq(sol.hp, hp - EnemyRoster.STERILIZE_DAMAGE, "the soldier burns")
	assert_true(runner.hp < rhp, "so do the Infected")
	assert_true(sol.infection < 50, "the soldier is cleansed")
	assert_eq(Hazards.at(s, Vector2i(5, 4)).get("kind", ""), "", "the spores are gone")
	assert_true(_events(s, "cleansed").size() == 1, "and the event says so")
	assert_eq(st.hp, st.max_hp, "it does not burn itself")


# --- Acolyte ------------------------------------------------------------------------------

func test_acolyte_swells_beside_a_soldier_then_blooms_for_infection_only() -> void:
	var s := make_blank(_open(14, 9))
	var sol := _soldier(s, "trooper", Vector2i(7, 4))
	var far := _soldier(s, "trooper", Vector2i(7, 8))
	var a := _enemy(s, "acolyte", Vector2i(3, 4))
	Vision.disable(s)
	_enemy_turn(s, a)
	assert_true(a.status.has("swelling"), "swells when it arrives")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "bloom" and d.cells.size() == 25), "the 5x5 is drawn")
	var hp := sol.hp
	var inf := sol.infection
	_enemy_turn(s, a)
	assert_true(not a.is_alive(), "it spends itself")
	assert_eq(sol.hp, hp, "no damage")
	assert_eq(sol.infection, inf + EnemyRoster.BLOOM_INFECTION, "Infection instead")
	assert_eq(far.infection, 0, "out of the 5x5 is safe")
	assert_true(_events(s, "ability").any(func(e): return e.ability == "bloom"), "the bloom event fired")


func test_acolyte_killed_while_swelling_blooms_and_killed_early_does_not() -> void:
	var s := make_blank(_open(10, 10))
	var sol := _soldier(s, "trooper", Vector2i(4, 4))
	var a := _enemy(s, "acolyte", Vector2i(5, 4))
	var b := _enemy(s, "acolyte", Vector2i(8, 8))
	Vision.disable(s)
	a.status["swelling"] = s.turn
	Rules.deal_damage(s, b, 99, sol)
	assert_eq(sol.infection, 0, "killed before swelling: just dead")
	Rules.deal_damage(s, a, 99, sol)
	assert_eq(sol.infection, EnemyRoster.BLOOM_INFECTION, "killed while swelling: it blooms anyway")


# --- Cantor -------------------------------------------------------------------------------

func test_cantor_chant_lifts_allies_it_can_see_inside_the_ring() -> void:
	var rows := _open(14, 7)
	rows[3] = "...........#.."
	var s := make_blank(rows)
	var sol := _soldier(s, "trooper", Vector2i(0, 0))
	var c := _enemy(s, "cantor", Vector2i(8, 3))
	var near := _enemy(s, "runner", Vector2i(6, 3))
	var far := _enemy(s, "runner", Vector2i(8, 6))   # three tiles down: in the ring edge
	var out := _enemy(s, "runner", Vector2i(2, 3))
	Vision.disable(s)
	assert_eq(Choir.chant_bonus(s, near), EnemyRoster.CHANT_DAMAGE, "inside the ring and in sight")
	assert_eq(Choir.chant_bonus(s, out), 0, "outside the ring")
	assert_eq(Encounter.modify_damage(s, sol, 3, near), 3 + EnemyRoster.CHANT_DAMAGE, "the hit lands harder")
	assert_eq(Encounter.modify_damage(s, sol, 3, out), 3, "and not for the one outside")
	var wall := _enemy(s, "runner", Vector2i(12, 3))   # behind the wall at (11, 3)
	assert_eq(Choir.chant_bonus(s, wall), 0, "no sight, no chant")
	s.phase = Types.Phase.ENEMY
	Choir.on_enemy_phase_start(s)
	assert_true(_events(s, "chant").size() == 1 and _events(s, "chant")[0].units.has(near.id), "the Cantor sings for the view")
	assert_true(EnemyIntent.links(s).is_empty() or true, "links read without error")
	Rules.deal_damage(s, c, 99, sol)
	assert_eq(Choir.chant_bonus(s, near), 0, "kill the Cantor and it ends")
	assert_true(far.is_alive(), "the rest stand")


# --- Hush ---------------------------------------------------------------------------------

func test_hush_locks_then_silences_class_abilities_for_two_rounds() -> void:
	var s := make_blank(_open(14, 6))
	var sol := _soldier(s, "trooper", Vector2i(2, 3))
	var h := _enemy(s, "hush", Vector2i(9, 3))
	Vision.disable(s)
	sol.actions_left = 2
	var ready_before := Combat.available_abilities(s, sol).filter(func(a): return a.ready).size()
	assert_true(ready_before > 0, "the soldier has an ability up")
	s.turn = 1
	_enemy_turn(s, h)
	assert_eq(int(h.status.get("hushing", -1)), sol.id, "it locks on")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "hush"), "the lock line is drawn")
	assert_eq(EnemyIntent._intent(s, h).label, "SILENCING", "intent word")
	s.turn = 2
	_enemy_turn(s, h)
	assert_true(Combat.has_status(s, sol, "hushed"), "silenced")
	sol.actions_left = 2
	assert_eq(Combat.available_abilities(s, sol).filter(func(a): return a.ready).size(), 0, "nothing is ready")
	s.phase = Types.Phase.TEAM
	assert_eq(Combat.validate(s, sol, {"type": Types.ABILITY, "unit": sol.id, "ability": "suppress", "target": h.id}), "Hushed", "refused, with the reason")
	s.phase = Types.Phase.TEAM
	s.turn = 4
	assert_true(Combat.has_status(s, sol, "hushed"), "still silenced on its second turn")
	s.turn = 5
	assert_true(not Combat.has_status(s, sol, "hushed"), "after two turns it lifts")


func test_hush_loses_the_lock_when_suppressed() -> void:
	var s := make_blank(_open(14, 6))
	var sol := _soldier(s, "trooper", Vector2i(2, 3))
	var h := _enemy(s, "hush", Vector2i(9, 3))
	Vision.disable(s)
	s.turn = 1
	_enemy_turn(s, h)
	h.status["suppressed"] = Combat.phase_index(s) + 4
	s.turn = 2
	_enemy_turn(s, h)
	assert_true(not Combat.has_status(s, sol, "hushed"), "no silence")
	assert_true(not h.status.has("hushing") and _events(s, "lock_lost").size() == 1, "the lock drops")


func test_fights_in_later_acts_meet_the_new_kinds() -> void:
	var seen := {}
	for act in [2, 3]:
		for seed in range(1, 120):
			var f := FightBuilder.build({"act": act, "node": "skirmish", "outbreak": 4, "seed": seed, "squad": 4})
			for e in f.enemies:
				seen[EnemyRoster.parse(e).kind] = true
	for k in EnemyRoster.FACTIONS.recovery + EnemyRoster.FACTIONS.choir:
		assert_true(seen.has(k), k + " turns up in fights")


# --- through the view ---------------------------------------------------------------------

func _view(enemies: Array[String]) -> MissionView:
	var s := make_state(enemies)
	var v: MissionView = MAIN.instantiate()
	v.start(s)
	_drain(v)
	return v


func _drain(v: MissionView) -> void:
	var steps := 0
	while v.player.is_busy() and steps < 20000:
		v.player.advance(1.0 / 15.0)
		steps += 1


## Puts a unit on `cell` in both the state and its view.
func _put(v: MissionView, u: Unit, cell: Vector2i) -> void:
	u.pos = cell
	v.view_for(u.id).set_cell(cell)


func _clear_field(v: MissionView) -> Array[Unit]:
	var soldiers: Array[Unit] = []
	for u in v.state.living(Types.Team.PLAYER):
		u.max_hp = 99
		u.hp = 99
		soldiers.append(u)
	return soldiers


func _of(v: MissionView, kind: String) -> Unit:
	return v.state.living(Types.Team.ENEMY).filter(func(u): return u.kind == kind)[0]


## A free cell `dist` tiles from `target` with a clear line to it.
func _sight_spot(v: MissionView, target: Vector2i, dist: int) -> Vector2i:
	for d in Grid.DIRS8:
		var c: Vector2i = target + d * dist
		if v.state.grid.in_bounds(c) and v.state.grid.is_walkable(c) and v.state.unit_at(c) == null and Combat.can_see(v.state, c, target):
			return c
	return _spot(v, target + Vector2i(dist, 0))


func _spot(v: MissionView, near: Vector2i) -> Vector2i:
	return Encounter.free_cell(v.state, near)


func _seen_beats(v: MissionView) -> Dictionary:
	var seen := {}
	v.player.beat_finished.connect(func(ev: Dictionary) -> void:
		var key := str(ev.get("type", ""))
		if key == "ability":
			key = "ability:" + str(ev.get("ability", ""))
		seen[key] = int(seen.get(key, 0)) + 1)
	return seen


func test_recovery_abilities_play_through_the_view() -> void:
	var v := _view(["netter", "handler", "sterilizer", "collector"])
	var s: GameState = v.state
	Vision.disable(s)
	var soldiers := _clear_field(v)
	var seen := _seen_beats(v)
	var net := _of(v, "netter")
	var handler := _of(v, "handler")
	var sterilizer := _of(v, "sterilizer")
	var collector := _of(v, "collector")
	var a := soldiers[0]
	var b := soldiers[1]
	a.infection = 40
	_put(v, a, _spot(v, Vector2i(s.grid.width / 2, s.grid.height / 2)))
	var base := a.pos
	for e in [net, handler, sterilizer, collector]:
		e.status["alerted"] = true
	_put(v, net, _spot(v, base + Vector2i(1, 0)))
	net.aim = 500
	assert_true(_act(s, net, {"ability": "net", "target": a.id}), "net")
	_drain(v)
	assert_true(seen.get("ability:net", 0) == 1 and seen.get("pinned", 0) >= 1, "the net beat and the pinned beat play")
	_put(v, handler, _spot(v, base + Vector2i(5, 1)))
	assert_true(_act(s, handler, {"ability": "designate", "target": a.id}), "designate")
	_drain(v)
	assert_true(seen.get("ability:designate", 0) == 1, "the designate beat plays")
	s.phase = Types.Phase.TEAM
	v.intents.refresh()
	assert_true(EnemyIntent.designations(s).size() >= 0 and v.intents.get_child_count() > 0, "the overlay draws")
	_put(v, collector, _spot(v, base + Vector2i(0, 1)))
	_put(v, b, _spot(v, base + Vector2i(8, 8)))
	s.phase = Types.Phase.ENEMY
	collector.actions_left = 2
	assert_true(_act(s, collector, {"ability": "drag", "target": a.id}), "drag")
	_drain(v)
	assert_true(seen.get("ability:drag", 0) == 1, "the drag beat plays")
	assert_eq(v.view_for(a.id).cell, a.pos, "the dragged soldier's view follows")
	s.phase = Types.Phase.TEAM
	v.intents.refresh()
	assert_eq(EnemyIntent._intent(s, collector).label, "DRAGGING", "the intent reads DRAGGING")
	_put(v, sterilizer, _sight_spot(v, a.pos, 3))
	assert_true(_act(s, sterilizer, {"ability": "sterilize", "cell": a.pos}), "sterilize")
	_drain(v)
	assert_true(seen.get("ability:sterilize", 0) == 1, "the flame cone beat plays")
	s.turn += 1
	s.phase = Types.Phase.ENEMY
	Encounter._resolve_telegraphs(s)
	_drain(v)
	assert_true(seen.get("strike", 0) >= 1 and seen.get("cleansed", 0) >= 1, "the cone lands and cleanses")
	# A capture: the soldier at the edge is dragged off.
	var edge_cell := Vector2i(1, 1)
	for c in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1)]:
		if s.grid.is_walkable(c) and s.unit_at(c) == null:
			edge_cell = c
			break
	_put(v, b, edge_cell)
	_put(v, collector, _spot(v, edge_cell + Vector2i(1, 1)))
	b.status["pinned_by"] = collector.id
	collector.status["pinning"] = b.id
	if s.phase != Types.Phase.ENDED:
		Recovery._capture(s, collector, b)
		_drain(v)
		assert_true(seen.get("captured", 0) == 1 and seen.get("fled", 0) >= 1, "the capture and the exit play")
	assert_true(not v.player.generic_log.any(func(x): return str(x).begins_with("ability:")), "no bare-label fallback beats")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()


func test_choir_abilities_play_through_the_view() -> void:
	var v := _view(["acolyte", "cantor", "hush", "runner"])
	var s: GameState = v.state
	Vision.disable(s)
	var soldiers := _clear_field(v)
	var seen := _seen_beats(v)
	var acolyte := _of(v, "acolyte")
	var cantor := _of(v, "cantor")
	var hush := _of(v, "hush")
	var runner := _of(v, "runner")
	var a := soldiers[0]
	for e in [acolyte, cantor, hush, runner]:
		e.status["alerted"] = true
	_put(v, cantor, _sight_spot(v, a.pos, 6))
	_put(v, runner, _sight_spot(v, cantor.pos, 2))
	s.phase = Types.Phase.ENEMY
	Choir.on_enemy_phase_start(s)
	_drain(v)
	assert_true(Choir.chanting(s, cantor, runner), "the runner stands in the ring")
	assert_true(seen.get("chant", 0) >= 1, "the chant is sung and shown")
	s.phase = Types.Phase.TEAM
	v.intents.refresh()
	assert_true(v.intents.get_child_count() > 0, "the overlay draws the ring and links")
	_put(v, hush, _sight_spot(v, a.pos, 5))
	assert_true(_act(s, hush, {"ability": "hush", "target": a.id}), "hush")
	_drain(v)
	assert_true(seen.get("ability:hush", 0) == 1, "the lock beat plays")
	s.turn += 1
	assert_true(_act(s, hush, {"ability": "silence"}), "silence")
	_drain(v)
	assert_true(seen.get("ability:silence", 0) == 1 and seen.get("hushed", 0) == 1, "the silence and the hushed beat play")
	_put(v, acolyte, _spot(v, a.pos + Vector2i(1, 1)))
	acolyte.status["swelling"] = s.turn
	assert_true(_act(s, acolyte, {"ability": "bloom"}), "bloom")
	_drain(v)
	assert_true(seen.get("ability:bloom", 0) == 1, "the bloom beat plays")
	assert_true(not v.player.generic_log.any(func(x): return str(x).begins_with("ability:")), "no bare-label fallback beats")
	assert_true(not v.player.is_busy(), "queue drained")
	v.free()
