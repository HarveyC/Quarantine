class_name MatchConfig
extends RefCounted
## Describes a mission to start. Every peer builds the same GameState from the same config,
## so this is what the host sends to clients when a match starts.
##
## Keys: map (file path, used when there is no map_spec or MapGen hasn't landed), map_spec
## (MapGen.generate input), squad (Array of {"kind", "player"} plus RunSoldier.squad_entry keys
## for run fights), enemies (Array of enemy spec strings), encounter (Encounter.setup input),
## seed, and for run fights "fight" (the fight spec, see RunRules / docs/ARCHITECTURE.md).

const MAP := "res://maps/mission_01.txt"
const CLASSES: Array[String] = ["trooper", "marksman", "medic", "breacher"]
const ENEMIES: Array[String] = ["runner", "runner", "spitter", "runner", "spitter"]


## Most soldiers a squad can field, across every player.
const MAX_SQUAD := 4


## Who controls what. Every player picks their own squad of 1 to 4 soldiers; the whole squad is
## at most MAX_SQUAD. `picks` maps player -> Array of classes (a String counts as one soldier;
## "" is "any free class"). A player without picks gets the full squad when alone, else one
## soldier. Each player keeps at least one soldier: when the picks add up to more than
## MAX_SQUAD, the biggest squads (latest player first on a tie) give one up until they fit.
static func squad_plan(num_players: int, picks: Dictionary = {}) -> Array:
	var n := clampi(num_players, 1, MAX_SQUAD)
	var want := squads(n, picks)
	var taken := {}
	for p in n:
		for k in want[p]:
			if k != "":
				taken[k] = true
	var out: Array = []
	var i := 0
	for p in n:
		for k in want[p]:
			var kind: String = k
			if kind == "":
				for c in CLASSES:
					if not taken.has(c):
						kind = c
						break
				if kind == "":
					kind = CLASSES[i % CLASSES.size()]
				taken[kind] = true
			out.append({"kind": kind, "player": p})
			i += 1
	return out


## player -> Array of picked classes ("" = any free class), trimmed to fit MAX_SQUAD.
static func squads(num_players: int, picks: Dictionary = {}) -> Dictionary:
	var n := clampi(num_players, 1, MAX_SQUAD)
	var want := {}
	for p in n:
		var v = picks.get(p, null)
		var list: Array = []
		if v is String:
			list = [v]
		elif v is Array:
			list = (v as Array).slice(0, MAX_SQUAD).map(func(k) -> String: return str(k))
		if list.is_empty():
			list = CLASSES.duplicate() if n == 1 else [""]
		want[p] = list
	var total := func() -> int:
		var t := 0
		for p in want:
			t += want[p].size()
		return t
	while total.call() > MAX_SQUAD:
		var big := 0
		for p in n:
			if want[p].size() >= want[big].size():
				big = p
		want[big].pop_back()
	return want


## How many soldiers `player` could field, given what everyone else picked.
static func room_for(num_players: int, picks: Dictionary, player: int) -> int:
	var want := squads(num_players, picks)
	var others := 0
	for p in want:
		if p != player:
			others += want[p].size()
	return clampi(MAX_SQUAD - others, 1, MAX_SQUAD)


static func make(num_players: int, seed: int = 0, picks: Dictionary = {}) -> Dictionary:
	var squad: Array = []
	for e in squad_plan(num_players, picks):
		e["prog"] = Progression.quick_play_record(e.kind)
		squad.append(e)
	var s := seed if seed != 0 else randi() % 1000000 + 1
	# Quick matches outside a run roll an act 1 skirmish layout from their seed, and start Concealed.
	return {"map": MAP, "squad": squad, "enemies": ENEMIES.slice(0, 1 + squad.size()), "seed": s,
		"map_spec": {"biome": "wall", "objective": "skirmish", "seed": s}, "encounter": {"concealed": true}}


## The mission for a fight step of a run. `st` is {"kind", "objective", "seed"} from RunRules.
static func for_fight(run: RunState, st: Dictionary) -> Dictionary:
	var seed: int = st.get("seed", 0) if st.get("seed", 0) != 0 else run.rng.randi() % 1000000 + 1
	var spec := {
		"act": run.act, "row": run.row, "node": st.kind, "objective": st.objective,
		"outbreak": run.outbreak, "seed": seed, "players": run.players.size(),
		"modifiers": run.modifiers.duplicate(true),
	}
	var squad: Array = []
	for r in run.squad():
		if r.sit_out <= 0:
			squad.append(RunSoldier.squad_entry(run, r))
	# Fights stay scaled for the biggest squad the run has fielded: losing a soldier is not a discount.
	run.peak_squad = maxi(run.peak_squad, run.squad().size())
	spec["squad"] = clampi(maxi(squad.size(), run.peak_squad), 1, 4)
	Severity.adjust_fight_spec(run, spec)
	var built: Dictionary = RunHooks.call_static("FightBuilder", "build", [spec], {})
	var enemies: Array = built.get("enemies", default_enemies(spec))
	var echo: Dictionary = RunHooks.call_static("Story", "fight_echo", [run, st], {})
	if not echo.is_empty() and enemies.size() > 1:
		enemies = enemies.slice(0, enemies.size() - 1)   # the Echo takes the last enemy's place
	return {
		"echo": echo,
		"map": MAP, "map_spec": {"biome": RunMap.biome(run.act), "objective": st.objective, "seed": seed,
			"act": run.act, "row": run.row, "outbreak": run.outbreak},
		"squad": squad, "enemies": enemies, "encounter": built.get("encounter", {}), "seed": seed, "fight": spec,
	}


## Stand-in roster until FightBuilder lands: grows with act, row and Outbreak.
static func default_enemies(spec: Dictionary) -> Array:
	var n: int = 3 + spec.act - 1 + (1 if spec.node in ["nest", "boss"] else 0) + mini(2, RunRules.outbreak_stage(spec.outbreak))
	var out: Array = []
	for i in n:
		out.append("spitter" if i % 3 == 2 else "runner")
	return out


static func build(config: Dictionary) -> GameState:
	var grid: Grid = null
	if config.has("map_spec"):
		grid = RunHooks.call_static("MapGen", "generate", [config.map_spec])
	if grid == null:
		grid = Grid.load_file(config.map)
	var enemies: Array[String] = []
	enemies.assign(config.enemies)
	var s := Rules.new_mission_on_grid(grid, config.squad, enemies, config.seed)
	if config.has("encounter"):
		RunHooks.call_static("Encounter", "setup", [s, config.encounter])
	if not config.get("echo", {}).is_empty():
		RunHooks.call_static("Story", "setup_echo", [s, config.echo])
	return s
