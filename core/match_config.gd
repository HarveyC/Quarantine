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


## Who controls what: solo is a full squad of 4 for player 0; co-op is one soldier per player.
## `picks` maps player -> class; a player without a pick gets the first class nobody has.
static func squad_plan(num_players: int, picks: Dictionary = {}) -> Array:
	var n := clampi(num_players, 1, CLASSES.size())
	var out: Array = []
	if n == 1:
		for k in CLASSES:
			out.append({"kind": k, "player": 0})
		return out
	var taken := {}
	for p in n:
		if picks.has(p):
			taken[picks[p]] = true
	for p in n:
		var kind: String = picks.get(p, "")
		if kind == "":
			for k in CLASSES:
				if not taken.has(k):
					kind = k
					break
			if kind == "":
				kind = CLASSES[p % CLASSES.size()]
			taken[kind] = true
		out.append({"kind": kind, "player": p})
	return out


static func make(num_players: int, seed: int = 0, picks: Dictionary = {}) -> Dictionary:
	var squad: Array = []
	for e in squad_plan(num_players, picks):
		e["prog"] = Progression.quick_play_record(e.kind)
		squad.append(e)
	var s := seed if seed != 0 else randi() % 1000000 + 1
	# Quick matches outside a run roll an act 1 skirmish layout from their seed.
	return {"map": MAP, "squad": squad, "enemies": ENEMIES.slice(0, 1 + squad.size()), "seed": s,
		"map_spec": {"biome": "wall", "objective": "skirmish", "seed": s}}


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
	spec["squad"] = squad.size()
	Severity.adjust_fight_spec(run, spec)
	var built: Dictionary = RunHooks.call_static("FightBuilder", "build", [spec], {})
	var enemies: Array = built.get("enemies", default_enemies(spec))
	return {
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
	return s
