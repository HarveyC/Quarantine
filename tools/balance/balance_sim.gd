extends SceneTree
## Headless balance simulator. Plays whole fights with the real rules: SquadBot plays the squad,
## EnemyAI plays the enemies. Prints one JSON line per fight; tools/balance/report.py sums them up.
##
##   godot --headless -s tools/balance/balance_sim.gd -- squad=trooper,medic act=1 node=skirmish n=50
##
## Args: squad (comma classes), act (1-3), node (skirmish|nest|boss), objective (default skirmish/boss), outbreak, n (fights),
## boss (forces a boss kind, e.g. broker), bosshp (multiplies boss health), seed (first seed), enemies (comma enemy specs: overrides FightBuilder), rank (default by act),
## tag (free text echoed in every line), guns (comma weapon ids lined up with squad; "-" keeps
## the signature gun), order (a DeployOrders id every soldier deploys with, e.g. bloom_cache;
## "none" or unset means no starting gear), build (none|scattered|lane|full: gear, perks, mutations and
## Grafts of that quality, see build_quality.gd; node=act plays a whole act, three skirmishes then
## the boss, with HP, Infection and deaths carried over and the after-fight heal).

const SquadBot := preload("res://tools/balance/squad_bot.gd")
const BuildQuality := preload("res://tools/balance/build_quality.gd")
const TURN_CAP := 25
## Rank a soldier typically has when reaching each act (rank-ups after fights 1/3/5/7).
const RANK_BY_ACT := {1: 1, 2: 3, 3: 5}
## node=act: skirmishes before the boss, and the run Outbreak the act starts at (the mid-act value
## from run_sims.py, less one, then +1 per fight).
const ACT_SKIRMISHES := 3
const ACT_OUTBREAK := {1: 2, 2: 5, 3: 8}


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
	objective_override = str(args.get("objective", ""))
	boss_hp = float(args.get("bosshp", 1.0))
	boss_kind = str(args.get("boss", ""))
	build_level = str(args.get("build", "none"))
	aspect_override = str(args.get("aspect", ""))
	PartingBlow.enabled = not args.has("nopb")
	SquadBot.skip_signatures = args.has("nosig")
	SquadBot.skip_gear = args.has("nogear")
	SquadBot.skip_purge = args.has("nopurge")
	for i in n:
		var seed := seed0 + i
		if node == "act":
			print(JSON.stringify(run_act(squad_kinds, act, seed, rank, str(args.get("tag", "")))))
			continue
		print(JSON.stringify(run_fight(squad_kinds, act, node, int(args.get("outbreak", 0)), seed, rank,
			str(args.get("enemies", "")), str(args.get("tag", "")), str(args.get("guns", "")), str(args.get("order", "")))))
	quit(0)


var boss_kind := ""   # boss= forces the act's boss (else the seed rolls it)
var boss_hp := 1.0   # bosshp= scales the boss's health on top of FightBuilder's (for tuning)
var objective_override := ""   # objective= (purge: the bot shoots the spore nests)
var build_level := "none"       # build= (see build_quality.gd)
var aspect_override := ""       # aspect=hunger|remembers|regrown for Source boss fights


func run_fight(kinds: PackedStringArray, act: int, node: String, outbreak: int, seed: int, rank: int,
		enemy_override: String, tag: String, guns: String = "", order: String = "", pre: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	# `pre` is a squad already built (node=act): {squad, records, carry} with carry[i] = {hp, infection}.
	var made: Dictionary = pre if not pre.is_empty() else _make_squad(rng, kinds, act, rank, order)
	var squad: Array = made.squad
	var records: Array = made.records
	var carry: Array = made.get("carry", [])
	var objective := "boss" if node == "boss" else "skirmish"
	if objective_override != "":
		objective = objective_override
	var spec := {"act": act, "row": 2, "node": node, "objective": objective, "outbreak": outbreak,
		"seed": seed, "players": kinds.size(), "squad": kinds.size(), "boss": boss_kind,
		"modifiers": {"boss_health_mult": boss_hp} if boss_hp != 1.0 else {}}
	if boss_kind != "":
		spec["boss"] = boss_kind
	if aspect_override != "":
		spec["aspect"] = aspect_override
		spec["echo_names"] = ["Reyes", "Osei"]
	var built := FightBuilder.build(spec)
	var enemies: Array = built.enemies
	var enc: Dictionary = built.encounter
	if enemy_override != "":
		enemies = Array(enemy_override.split(","))
		enc = {}
	var config := {"map": MatchConfig.MAP, "squad": squad, "enemies": enemies, "encounter": enc, "seed": seed,
		"map_spec": {"biome": RunMap.biome(act), "objective": objective, "seed": seed, "act": act, "row": 2, "outbreak": outbreak,
			"boss": str(enc.get("boss", ""))}}
	var s := MatchConfig.build(config)
	if guns != "":
		var gl := guns.split(",")
		var sq := s.units.filter(func(u): return Kit.is_soldier(u))
		for i in mini(gl.size(), sq.size()):
			if gl[i] != "-":
				Weapons.equip_unit(sq[i], gl[i])
	var squad_units := s.units.filter(func(u): return Kit.is_soldier(u))
	if not records.is_empty():
		for i in mini(records.size(), squad_units.size()):
			GearRun.apply_to_unit(squad_units[i], records[i])
			squad_units[i].hp = squad_units[i].max_hp
			var inf := int(carry[i].infection) if carry.size() > i else int(records[i].infection)
			if inf > 0:
				Infection.add(s, squad_units[i], inf)
	for i in mini(carry.size(), squad_units.size()):
		squad_units[i].hp = clampi(int(carry[i].hp), 1, squad_units[i].max_hp)
		if records.is_empty() and int(carry[i].infection) > 0:
			Infection.add(s, squad_units[i], int(carry[i].infection))
	var slot_of := {}   # unit id -> squad index
	var hp_start := 0
	for i in squad_units.size():
		slot_of[squad_units[i].id] = i
		hp_start += squad_units[i].hp
	var tag_peak: Array = []
	for i in records.size():
		var c := BuildQuality.tags(records[i])
		var peak := 0
		for t in c:
			peak = maxi(peak, int(c[t]))
		tag_peak.append(peak)
	var stats := {}   # unit id -> {dealt, taken, kills}
	for u in s.units:
		stats[u.id] = {"dealt": 0, "taken": 0}
	var boss_acts := {}   # what the boss did: ability ids, "moved" tiles, "phase2"/"phase3" turn reached
	var boss_ids := {}
	for u in s.units:
		if EnemyRoster.is_boss(u):
			boss_ids[u.id] = true
	var counter := {"lapses": 0, "explosions": 0, "barrels": 0, "barrel_shots": 0, "barrel_hits": 0, "walls": 0, "cover": 0, "roofs": 0}
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
		elif ev.type == "barrel_shot":
			counter.barrel_shots += 1
			if ev.hit:
				counter.barrel_hits += 1
		elif ev.type == "cover_destroyed":
			for ch in ev.get("changes", []):
				match str(ch.kind):
					"break": counter.walls += 1
					"clear": counter.cover += 1
		elif ev.type == "level_changed":
			counter.roofs += 1
		if ev.type in ["ability", "hunker", "overwatch"] and s.get_unit(int(ev.get("unit", -1))) != null \
				and s.get_unit(int(ev.unit)).status.get("lantern_echo", false):
			var key := "echo:" + str(ev.get("ability", ev.type))
			boss_acts[key] = int(boss_acts.get(key, 0)) + 1
		if boss_ids.has(int(ev.get("unit", -1))):
			if ev.type == "ability":
				boss_acts[str(ev.ability)] = int(boss_acts.get(str(ev.ability), 0)) + 1
			elif ev.type == "move":
				boss_acts["moved"] = int(boss_acts.get("moved", 0)) + ev.path.size()
			elif ev.type == "boss_phase":
				boss_acts["phase%d" % int(ev.phase)] = s.turn
		if ev.type == "pinned" and boss_ids.has(int(ev.get("by", -1))):
			boss_acts["pins"] = int(boss_acts.get("pins", 0)) + 1
		if ev.type == "shot" and boss_ids.has(int(ev.get("unit", -1))):
			boss_acts["shot"] = int(boss_acts.get("shot", 0)) + 1)
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
			soldiers.append({"slot": slot_of.get(u.id, -1), "peak_tag": tag_peak[slot_of[u.id]] if slot_of.has(u.id) and slot_of[u.id] < tag_peak.size() else 0,
				"kind": u.kind, "max_hp": u.max_hp, "hp": u.hp, "dealt": st.dealt, "taken": st.taken,
				"kills": int(u.status.get("kills", 0)), "weapon": Weapons.id_of(u), "infection": u.infection, "turned": u.status.get("turned", false)})
		elif u.team == Types.Team.ENEMY and not Objectives.is_civilian(u):
			foes.append({"kind": u.kind, "elite": u.status.get("elite", false), "max_hp": u.max_hp,
				"alive": u.is_alive(), "dealt": st.dealt, "taken": st.taken})
	var res := "timeout"
	if s.phase == Types.Phase.ENDED:
		res = "win" if s.result == Types.Result.VICTORY else "loss"
	return {"tag": tag, "order": order, "build": build_level, "hp_start": hp_start, "act": act, "node": node, "squad": kinds.size(), "seed": seed, "result": res,
		"turns": s.turn, "lapses": counter.lapses,
		"terrain": {"explosions": counter.explosions, "barrels": counter.barrels,
			"barrel_shots": counter.barrel_shots, "barrel_hits": counter.barrel_hits, "walls": counter.walls,
			"cover": counter.cover, "roofs": counter.roofs},
		"soldiers": soldiers, "enemies": foes, "spawned": enemies, "boss_acts": boss_acts}


## Gives every soldier the deployment order `id`: a record carrying its gear, gun and
## Infection (mutations graft straight into the squad entry's prog). [] when there's no order.
func _deploy(rng: RandomNumberGenerator, squad: Array, id: String) -> Array:
	if id == "" or id == "none":
		return []
	var holder := {"gear": {}}
	var out: Array = []
	for e in squad:
		var rec := {"kind": e.kind, "prog": e.prog, "infection": 0, "hp": 10, "max_hp": 10}
		var card := DeployOrders.build(rng, rec, id)
		for c in card.get("contents", []):
			match str(c.kind):
				"gear": Loadout.equip(holder, rec, c.id)
				"gun": Loadout.add_gun(rec, c.id)
				"mutation": Progression.graft(rec, c.id)
		rec.infection = maxi(int(rec.infection), int(card.get("infection", 0)))
		out.append(rec)
	return out


## The squad for a fight or act: entries for MatchConfig plus the run records that carry the gear
## ([] when the build is "none" and no deployment order is set).
func _make_squad(rng: RandomNumberGenerator, kinds: PackedStringArray, act: int, rank: int, order: String) -> Dictionary:
	var squad: Array = []
	var records: Array = []
	for i in kinds.size():
		var rec := BuildQuality.make(rng, kinds[i], act, rank, build_level)
		squad.append({"kind": kinds[i], "player": i if kinds.size() < 4 else 0, "prog": rec.prog})
		records.append(rec)
	if build_level == "none":
		records = _deploy(rng, squad, order)
	return {"squad": squad, "records": records}


## One act as a run plays it: ACT_SKIRMISHES skirmishes, then the boss. Survivors heal 35% of max
## HP after each won fight and carry their Infection; the fallen stay down. The act is lost when
## any fight is, or when the squad is gone.
func run_act(kinds: PackedStringArray, act: int, seed: int, rank: int, tag: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var made := _make_squad(rng, kinds, act, rank, "")
	var records: Array = made.records
	if records.is_empty():   # no build: the fights still need run records to hold HP and Infection
		for k in kinds:
			records.append({"infection": 0})
	var alive: Array = range(kinds.size())
	var carry: Array = []
	for r in records:
		carry.append({"hp": 99, "infection": int(r.get("infection", 0))})
	var fights: Array = []
	var result := "win"
	for f in ACT_SKIRMISHES + 1:
		var boss := f == ACT_SKIRMISHES
		var pre := {"squad": alive.map(func(i): return made.squad[i]),
			"records": alive.map(func(i): return made.records[i]) if not made.records.is_empty() else [],
			"carry": alive.map(func(i): return carry[i])}
		var kinds_now := PackedStringArray(alive.map(func(i): return kinds[i]))
		var res := run_fight(kinds_now, act, "boss" if boss else "skirmish", ACT_OUTBREAK[act] + f, seed * 10 + f, rank, "", tag, "", "", pre)
		var taken := 0
		var pool := 0
		for sd in res.soldiers:
			taken += int(sd.taken)
			pool += int(sd.max_hp)
		fights.append({"node": "boss" if boss else "skirmish", "result": res.result, "turns": res.turns, "taken": taken, "pool": pool,
			"hp_start": res.hp_start, "boss_acts": res.boss_acts})
		if res.result != "win":
			result = res.result
			break
		var next: Array = []
		for sd in res.soldiers:
			if sd.slot >= 0 and sd.hp > 0 and not sd.turned:
				var i: int = alive[sd.slot]
				carry[i] = {"hp": mini(int(sd.max_hp), int(sd.hp) + ceili(int(sd.max_hp) * RunRules.HEAL_AFTER_FIGHT)),
					"infection": int(sd.infection)}
				next.append(i)
		alive = next
		if alive.is_empty():
			result = "loss"
			break
	var peak := 0
	for r in records:
		if r.has("prog"):
			for t in BuildQuality.tags(r).values():
				peak = maxi(peak, int(t))
	return {"tag": tag, "build": build_level, "node": "act", "act": act, "squad": kinds.size(), "seed": seed, "result": result,
		"fights": fights, "peak_tag": peak, "capstones": records.filter(func(r): return r.has("prog") and BuildQuality.capstones(r) > 0).size()}
