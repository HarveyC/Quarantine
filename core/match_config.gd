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


## Splits the 4-soldier squad across `num_players` (1: all four, 2: two each, 3: 2-1-1, 4: one each).
static func make(num_players: int, seed: int = 0) -> Dictionary:
	var n := clampi(num_players, 1, CLASSES.size())
	var squad: Array = []
	for i in CLASSES.size():
		squad.append({"kind": CLASSES[i], "player": i * n / CLASSES.size(),
			"prog": Progression.quick_play_record(CLASSES[i])})
	return {"map": MAP, "squad": squad, "enemies": ENEMIES.duplicate(), "seed": seed if seed != 0 else randi() % 1000000 + 1}


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
