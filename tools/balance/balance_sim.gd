extends SceneTree
## Headless balance simulator. Plays whole fights with the real rules: SquadBot plays the squad,
## EnemyAI plays the enemies. Prints one JSON line per fight; tools/balance/report.py sums them up.
##
##   godot --headless -s tools/balance/balance_sim.gd -- squad=trooper,medic act=1 node=skirmish n=50
##
## Args: squad (comma classes), act (1-3), node (skirmish|nest|boss), outbreak, n (fights),
## seed (first seed), enemies (comma enemy specs: overrides FightBuilder), rank (default by act),
## tag (free text echoed in every line), guns (comma weapon ids lined up with squad; "-" keeps
## the signature gun).

const SquadBot := preload("res://tools/balance/squad_bot.gd")
const TURN_CAP := 25
## Rank a soldier typically has when reaching each act (rank-ups after fights 1/3/5/7).
const RANK_BY_ACT := {1: 1, 2: 3, 3: 5}


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var squad_kinds: PackedStringArray = str(args.get("squad", "trooper,marksman,medic,breacher")).split(",")
	var act := int(args.get("act", 1))
	var node := str(args.get("node", "skirmish"))
	var n := int(args.get("n", 20))
	var seed0 := int(args.get("seed", 1))
	var rank := int(args.get("rank", RANK_BY_ACT[act]))
	for i in n:
		var seed := seed0 + i
		print(JSON.stringify(run_fight(squad_kinds, act, node, int(args.get("outbreak", 0)), seed, rank,
			str(args.get("enemies", "")), str(args.get("tag", "")), str(args.get("guns", "")))))
	quit(0)


func run_fight(kinds: PackedStringArray, act: int, node: String, outbreak: int, seed: int, rank: int,
		enemy_override: String, tag: String, guns: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var squad: Array = []
	for i in kinds.size():
		var prog := Progression.new_record(kinds[i])
		prog.rank = rank
		var pool: Array = []
		for id in PerkData.PERKS:
			var p: Dictionary = PerkData.PERKS[id]
			if p["class"] == kinds[i] and (not p.rare or rank >= 4):
				pool.append(id)
		for k in mini(rank - 1, 4):
			if pool.is_empty():
				break
			prog.perks.append(pool.pop_at(rng.randi() % pool.size()))
		squad.append({"kind": kinds[i], "player": i if kinds.size() < 4 else 0, "prog": prog})
	var objective := "boss" if node == "boss" else "skirmish"
	var spec := {"act": act, "row": 2, "node": node, "objective": objective, "outbreak": outbreak,
		"seed": seed, "players": kinds.size(), "squad": kinds.size(), "modifiers": {}}
	var built := FightBuilder.build(spec)
	var enemies: Array = built.enemies
	var enc: Dictionary = built.encounter
	if enemy_override != "":
		enemies = Array(enemy_override.split(","))
		enc = {}
	var config := {"map": MatchConfig.MAP, "squad": squad, "enemies": enemies, "encounter": enc, "seed": seed,
		"map_spec": {"biome": RunMap.biome(act), "objective": objective, "seed": seed, "act": act, "row": 2, "outbreak": outbreak}}
	var s := MatchConfig.build(config)
	if guns != "":
		var gl := guns.split(",")
		var sq := s.units.filter(func(u): return Kit.is_soldier(u))
		for i in mini(gl.size(), sq.size()):
			if gl[i] != "-":
				Weapons.equip_unit(sq[i], gl[i])
	var stats := {}   # unit id -> {dealt, taken, kills}
	for u in s.units:
		stats[u.id] = {"dealt": 0, "taken": 0}
	var counter := {"lapses": 0, "explosions": 0, "barrels": 0, "walls": 0, "cover": 0, "roofs": 0}
	s.event.connect(func(ev: Dictionary) -> void:
		if ev.type == "damage":
			var src := int(ev.source)
			if not stats.has(int(ev.unit)):
				stats[int(ev.unit)] = {"dealt": 0, "taken": 0}
			stats[int(ev.unit)].taken += int(ev.amount)
			if src >= 0:
				if not stats.has(src):
					stats[src] = {"dealt": 0, "taken": 0}
				stats[src].dealt += int(ev.amount)
		elif ev.type == "lapsed":
			counter.lapses += 1
		elif ev.type == "explosion":
			counter.explosions += 1
			if ev.kind == "barrel":
				counter.barrels += 1
		elif ev.type == "cover_destroyed":
			for ch in ev.get("changes", []):
				match str(ch.kind):
					"break": counter.walls += 1
					"clear": counter.cover += 1
		elif ev.type == "level_changed":
			counter.roofs += 1)
	Rules.start_mission(s)
	while s.phase != Types.Phase.ENDED and s.turn <= TURN_CAP:
		var turn := s.turn
		for p in s.players.duplicate():
			if s.phase != Types.Phase.TEAM or s.turn != turn:
				break
			SquadBot.play_player(s, p)
		if s.phase == Types.Phase.TEAM and s.turn == turn:
			for p in s.players:   # safety: never stall the phase
				Rules.set_ready(s, p, true)
	var soldiers: Array = []
	var foes: Array = []
	for u in s.units:
		var st: Dictionary = stats.get(u.id, {"dealt": 0, "taken": 0})
		if Kit.is_soldier(u) or u.status.has("turned"):
			soldiers.append({"kind": u.kind, "max_hp": u.max_hp, "hp": u.hp, "dealt": st.dealt, "taken": st.taken,
				"kills": int(u.status.get("kills", 0)), "weapon": Weapons.id_of(u), "infection": u.infection, "turned": u.status.get("turned", false)})
		elif u.team == Types.Team.ENEMY and not Objectives.is_civilian(u):
			foes.append({"kind": u.kind, "elite": u.status.get("elite", false), "max_hp": u.max_hp,
				"alive": u.is_alive(), "dealt": st.dealt, "taken": st.taken})
	var res := "timeout"
	if s.phase == Types.Phase.ENDED:
		res = "win" if s.result == Types.Result.VICTORY else "loss"
	return {"tag": tag, "act": act, "node": node, "squad": kinds.size(), "seed": seed, "result": res,
		"turns": s.turn, "lapses": counter.lapses,
		"terrain": {"explosions": counter.explosions, "barrels": counter.barrels, "walls": counter.walls,
			"cover": counter.cover, "roofs": counter.roofs},
		"soldiers": soldiers, "enemies": foes, "spawned": enemies}
