extends TestCase
## The 2026-10-25 enemy sprint: Hooker, Sapper, Carapace, Stalker, Weaver, the Volatile and Rallying
## affixes, and the pack AI that reads the board (enemies/).


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


# --- roster -------------------------------------------------------------------------------

func test_new_kinds_are_in_the_pools_of_their_acts() -> void:
	assert_true(EnemyRoster.pool(1).has("hooker"), "Hooker from act 1")
	assert_true(not EnemyRoster.pool(1).has("sapper") and EnemyRoster.pool(2).has("sapper") and EnemyRoster.pool(2).has("carapace"), "Sapper and Carapace from act 2")
	assert_true(not EnemyRoster.pool(2).has("stalker") and EnemyRoster.pool(3).has("stalker") and EnemyRoster.pool(3).has("weaver"), "Stalker and Weaver from act 3")
	assert_true(EnemyRoster.is_ranged("hooker"), "a Hooker counts against the ranged cap")
	for k in ["hooker", "sapper", "carapace", "stalker", "weaver"]:
		assert_true(Glossary.has("enemy_" + k), "a hover card for " + k)


func test_every_act_meets_a_new_enemy_often_enough() -> void:
	var new_kinds := {1: ["hooker", "cutter", "torchman"], 2: ["hooker", "sapper", "carapace", "cutter", "torchman", "fence"],
		3: ["hooker", "sapper", "carapace", "stalker", "weaver", "cutter", "torchman", "fence"]}
	for act in [1, 2, 3]:
		var seen := 0
		for seed in range(1, 80):
			var f := FightBuilder.build({"act": act, "node": "skirmish", "outbreak": 3, "seed": seed, "squad": 4})
			for e in f.enemies:
				if new_kinds[act].has(EnemyRoster.parse(e).kind):
					seen += 1
					break
		assert_true(seen >= (15 if act == 1 else 25), "act %d: a new kind in %d of 79 fights" % [act, seen])


# --- Hooker -------------------------------------------------------------------------------

func test_hooker_locks_a_line_then_reels_the_soldier_in() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(2, 2))
	var h := _enemy(s, "hooker", Vector2i(9, 2))
	Vision.disable(s)
	s.turn = 1
	_enemy_turn(s, h)
	assert_eq(int(h.status.get("hooked", -1)), a.id, "locks onto the soldier")
	assert_true(EnemyIntent.dangers(s).any(func(d): return d.kind == "hook"), "the line is shown as a danger")
	assert_eq(EnemyIntent._intent(s, h).label, "HOOKING", "intent word")
	var at := a.pos
	s.turn = 2
	_enemy_turn(s, h)
	assert_true(not h.status.has("hooked"), "the lock is spent")
	assert_eq(a.hp, a.max_hp - EnemyRoster.HOOK_DAMAGE, "2 damage")
	assert_eq(a.pos.x - at.x, EnemyRoster.HOOK_PULL, "pulled 3 tiles toward the Hooker")
	assert_eq(_events(s, "move").filter(func(e): return e.get("hooked", false)).size(), 1, "the pull is a move event")


func test_hook_breaks_without_line_of_sight_or_when_suppressed() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(2, 2))
	var h := _enemy(s, "hooker", Vector2i(9, 2))
	Vision.disable(s)
	s.turn = 1
	_enemy_turn(s, h)
	h.status["suppressed"] = 99
	s.turn = 2
	_enemy_turn(s, h)
	assert_eq(a.hp, a.max_hp, "a suppressed Hooker cannot reel")
	assert_eq(_events(s, "lock_lost").size(), 1, "the lock is lost")
	# A wall dropped between them cuts the line.
	var b := make_blank(_open(14, 5))
	var t := _soldier(b, "trooper", Vector2i(2, 2))
	var h2 := _enemy(b, "hooker", Vector2i(9, 2))
	Vision.disable(b)
	b.turn = 1
	_enemy_turn(b, h2)
	EnemyAbilities.set_tile(b.grid, Vector2i(5, 2), Types.Tile.WALL)
	b.turn = 2
	_enemy_turn(b, h2)
	assert_eq(t.hp, t.max_hp, "no line of sight, no pull")


func test_the_first_soldier_on_the_line_takes_the_hook() -> void:
	var s := make_blank(_open(14, 5))
	var far := _soldier(s, "marksman", Vector2i(2, 2))
	var near := _soldier(s, "warden", Vector2i(5, 2))
	var h := _enemy(s, "hooker", Vector2i(10, 2))
	Vision.disable(s)
	h.status["hooked"] = far.id
	s.turn = 2
	_enemy_turn(s, h)
	assert_eq(near.hp, near.max_hp - EnemyRoster.HOOK_DAMAGE, "the closer soldier is yanked instead")
	assert_eq(far.hp, far.max_hp, "the one behind is spared")


func test_a_pull_off_high_ground_adds_fall_damage() -> void:
	var s := make_blank(_open(14, 5))
	s.grid.set_level(Vector2i(4, 2), 1)
	var a := _soldier(s, "trooper", Vector2i(4, 2))
	var h := _enemy(s, "hooker", Vector2i(10, 2))
	Vision.disable(s)
	h.status["hooked"] = a.id
	s.turn = 2
	_enemy_turn(s, h)
	assert_eq(a.hp, a.max_hp - EnemyRoster.HOOK_DAMAGE - EnemyTerrain.FALL_DAMAGE_PER_LEVEL, "hook plus the drop")


# --- Sapper -------------------------------------------------------------------------------

func test_sapper_throws_a_satchel_that_survives_it_and_then_runs() -> void:
	var s := make_blank(_open(16, 7))
	var a := _soldier(s, "trooper", Vector2i(3, 3))
	var sp := _enemy(s, "sapper", Vector2i(8, 3))
	Vision.disable(s)
	s.turn = 1
	_enemy_turn(s, sp)
	var tel := (s.encounter.get("telegraphs", []) as Array).filter(func(t): return t.kind == "satchel")
	assert_eq(tel.size(), 1, "a satchel is down")
	assert_true(tel[0].cells.has(a.pos), "on the soldier")
	assert_true(tel[0].smash, "it breaks cover")
	assert_eq(sp.cooldowns.get("satchel", 0), 2, "on cooldown")
	assert_true(EnemyAI._cheb(sp.pos, a.pos) >= 5, "it ran back out of reach: %s" % str(sp.pos))
	Rules.deal_damage(s, sp, 99, a)   # killing the Sapper does not defuse it
	s.turn = 2
	Encounter.on_enemy_phase_start(s)
	assert_eq(a.hp, a.max_hp - EnemyRoster.SATCHEL_DAMAGE, "the satchel still goes off")


func test_sapper_will_not_blow_up_its_own_side() -> void:
	var s := make_blank(_open(16, 7))
	_soldier(s, "trooper", Vector2i(3, 3))
	_enemy(s, "runner", Vector2i(3, 4))
	_enemy(s, "brute", Vector2i(4, 3))
	var sp := _enemy(s, "sapper", Vector2i(8, 3))
	Vision.disable(s)
	var throw := EnemyBehaviours._best_satchel(s, sp, sp.pos, EnemyAI._hostiles(s, sp))
	assert_true(throw.is_empty() or EnemyAI._cheb(throw.cell, Vector2i(3, 4)) > 1, "no throw that catches the Runner")


# --- Carapace -----------------------------------------------------------------------------

func test_carapace_plate_takes_the_edge_off_front_hits_only() -> void:
	var s := make_blank(_open(12, 7))
	var front := _soldier(s, "trooper", Vector2i(2, 3))
	var side := _soldier(s, "trooper", Vector2i(6, 0))
	var c := _enemy(s, "carapace", Vector2i(6, 3))
	c.status["facing"] = Vector2i(-1, 0)
	Rules.deal_damage(s, c, 5, front)
	assert_eq(c.max_hp - c.hp, 2, "5 damage from the front is 5 - 3")
	c.hp = c.max_hp
	Rules.deal_damage(s, c, 5, side)
	assert_eq(c.max_hp - c.hp, 5, "full damage from the side")
	assert_eq(_events(s, "plated").size(), 1, "the plate shows when it works")
	# From higher ground the plate does not help.
	c.hp = c.max_hp
	s.grid.set_level(Vector2i(2, 3), 1)
	Rules.deal_damage(s, c, 5, front)
	assert_eq(c.max_hp - c.hp, 5, "a shot from above goes over the plate")


func test_carapace_turns_its_plate_toward_the_nearest_soldier() -> void:
	var s := make_blank(_open(14, 7))
	_soldier(s, "trooper", Vector2i(2, 3))
	var c := _enemy(s, "carapace", Vector2i(10, 3))
	Vision.disable(s)
	s.turn = 1
	_enemy_turn(s, c)
	assert_eq(c.status.facing, Vector2i(-1, 0), "faces the soldier")
	assert_eq(EnemyIntent.plates(s).size(), 1, "the overlay shows the plated side")


# --- Stalker ------------------------------------------------------------------------------

func test_stalker_freezes_while_watched_and_closes_when_not() -> void:
	var s := make_blank(_open(20, 5))
	var a := _soldier(s, "trooper", Vector2i(1, 2))
	var st := _enemy(s, "stalker", Vector2i(8, 2))
	Vision.refresh(s)
	assert_true(EnemyBehaviours.is_watched(s, st), "in the trooper's sight")
	var at := st.pos
	s.turn = 1
	_enemy_turn(s, st)
	assert_eq(st.pos, at, "frozen while watched")
	assert_eq(EnemyIntent._intent(s, st).label, "FROZEN", "intent word")
	# Out of sight (no soldier looking), it covers the ground with the extra moves.
	var b := make_blank(_open(30, 5))
	var t := _soldier(b, "trooper", Vector2i(1, 2))
	var st2 := _enemy(b, "stalker", Vector2i(27, 2))
	Vision.refresh(b)
	assert_true(not EnemyBehaviours.is_watched(b, st2), "unseen at range")
	b.turn = 1
	_enemy_turn(b, st2)
	assert_eq(27 - st2.pos.x, 2 * (UnitData.ENEMIES.stalker.mobility + EnemyRoster.STALK_BONUS_MOVE), "moves 3 further each action unseen")
	assert_eq(st2.mobility, UnitData.ENEMIES.stalker.mobility, "the bonus is only for the turn")
	assert_eq(t.hp, t.max_hp)


func test_stalker_hits_hard_on_a_soldier_alone() -> void:
	var s := make_blank(_open(30, 5))
	var lone := _soldier(s, "trooper", Vector2i(2, 2))
	_soldier(s, "medic", Vector2i(20, 2))
	var st := _enemy(s, "stalker", Vector2i(4, 2))
	Vision.disable(s)
	st.status["stalking"] = true
	st.damage = Vector2i(2, 2)
	Rules.deal_damage(s, lone, 2, st)
	assert_eq(lone.max_hp - lone.hp, 2 + EnemyRoster.STALK_BONUS_DAMAGE, "first hit on an isolated soldier")
	st.status["stalking"] = true
	lone.hp = lone.max_hp
	s.get_unit(2).pos = Vector2i(3, 3)
	Rules.deal_damage(s, lone, 2, st)
	assert_eq(lone.max_hp - lone.hp, 2, "no bonus with a teammate close")
	# A lone soldier has nobody to be cut off from.
	var solo := make_blank(_open(10, 5))
	var only := _soldier(solo, "trooper", Vector2i(2, 2))
	var st3 := _enemy(solo, "stalker", Vector2i(4, 2))
	st3.status["stalking"] = true
	Rules.deal_damage(solo, only, 2, st3)
	assert_eq(only.max_hp - only.hp, 2, "solo squads never get cut off")


# --- Weaver -------------------------------------------------------------------------------

func test_weaver_mends_the_most_wounded_in_sight_and_a_wall_cuts_the_thread() -> void:
	var s := make_blank(_open(14, 5))
	_soldier(s, "trooper", Vector2i(0, 0))
	var w := _enemy(s, "weaver", Vector2i(8, 2))
	var hurt := _enemy(s, "brute", Vector2i(6, 2))
	var worse := _enemy(s, "runner", Vector2i(10, 3))
	Vision.disable(s)
	hurt.hp = hurt.max_hp - 2
	worse.hp = 1
	assert_eq(EnemyAbilities.mend_target(s, w), worse, "the most HP lost wins")
	s.turn = 1
	_enemy_turn(s, w)
	assert_eq(worse.hp, 1 + EnemyRoster.MEND_HEAL, "healed 3")
	assert_eq(_events(s, "regenerate").size(), 1, "shows as a heal on the target")
	s.turn = 2
	_enemy_turn(s, w)
	assert_eq(hurt.hp, hurt.max_hp, "next turn the other one, capped at max HP")
	# Wall between them: no thread.
	var b := make_blank(_open(14, 5))
	_soldier(b, "trooper", Vector2i(0, 0))
	var w2 := _enemy(b, "weaver", Vector2i(8, 2))
	var h2 := _enemy(b, "brute", Vector2i(4, 2))
	Vision.disable(b)
	h2.hp = 3
	for y in 5:
		EnemyAbilities.set_tile(b.grid, Vector2i(6, y), Types.Tile.WALL)
	assert_eq(EnemyAbilities.mend_target(b, w2), null, "the wall cuts the thread")


func test_weaver_does_not_mend_bosses_props_or_the_healthy() -> void:
	var s := make_blank(_open(14, 5))
	_soldier(s, "trooper", Vector2i(0, 0))
	var w := _enemy(s, "weaver", Vector2i(8, 2))
	var node := _enemy(s, "hive_node", Vector2i(6, 2))
	node.hp = 1
	var well := _enemy(s, "runner", Vector2i(9, 2))
	Vision.disable(s)
	assert_eq(EnemyAbilities.mend_target(s, w), null, "nothing worth mending")
	assert_eq(well.hp, well.max_hp)


# --- affixes ------------------------------------------------------------------------------

func test_volatile_elite_blows_up_on_death() -> void:
	var s := make_blank(_open(10, 5))
	var a := _soldier(s, "trooper", Vector2i(4, 2))
	var v := _enemy(s, "runner+volatile", Vector2i(5, 2))
	var friend := _enemy(s, "runner", Vector2i(6, 2))
	Rules.deal_damage(s, v, 99, a)
	assert_eq(a.hp, a.max_hp - EnemyRoster.VOLATILE_BLAST.damage, "2 damage to a soldier beside it")
	assert_eq(friend.hp, friend.max_hp - EnemyRoster.VOLATILE_BLAST.damage, "and to its friends")
	assert_eq(_events(s, "explosion").filter(func(e): return e.kind == "volatile").size(), 1, "an explosion event")


func test_rallying_elite_makes_nearby_infected_hit_harder() -> void:
	var s := make_blank(_open(14, 5))
	var a := _soldier(s, "trooper", Vector2i(2, 2))
	var r := _enemy(s, "brute!rallying", Vector2i(10, 2))
	var near := _enemy(s, "runner", Vector2i(8, 2))
	var far := _enemy(s, "runner", Vector2i(3, 2))
	Rules.deal_damage(s, a, 3, near)
	assert_eq(a.max_hp - a.hp, 3 + EnemyRoster.RALLY_DAMAGE, "within 3 tiles of the elite")
	a.hp = a.max_hp
	Rules.deal_damage(s, a, 3, far)
	assert_eq(a.max_hp - a.hp, 3, "out of its reach")
	assert_eq(EnemyIntent.rallies(s).size(), 1 if Vision.sees_unit(s, Types.Team.PLAYER, r) else 0, "ring shown")


# --- pack AI ------------------------------------------------------------------------------

func test_rushers_do_not_walk_into_a_marked_blast() -> void:
	var s := make_blank(_open(14, 7))
	var a := _soldier(s, "trooper", Vector2i(4, 3))
	var r := _enemy(s, "runner", Vector2i(10, 3))
	Vision.disable(s)
	var cells: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			cells.append(a.pos + Vector2i(dx, dy))
	Encounter.add_telegraph(s, {"kind": "satchel", "cells": cells, "turn": s.turn + 1, "damage": 3, "source": -1, "unit": -1})
	s.turn = 1
	_enemy_turn(s, r)
	assert_true(not cells.has(r.pos), "the Runner waits outside the marked tiles, at %s" % str(r.pos))


func test_packs_prefer_the_soldier_who_strayed() -> void:
	var s := make_blank(_open(24, 7))
	var a := _soldier(s, "trooper", Vector2i(2, 3))
	var b := _soldier(s, "medic", Vector2i(3, 3))
	var lone := _soldier(s, "breacher", Vector2i(14, 3))
	var r := _enemy(s, "runner", Vector2i(9, 3))
	assert_true(EnemyAI.isolation(s, lone) > EnemyAI.isolation(s, a), "the stray scores higher")
	assert_eq(EnemyAI.isolation(s, a), 0.0, "squad-mates close together do not")
	assert_true(r != null and b != null)
