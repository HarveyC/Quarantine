class_name MatchConfig
extends RefCounted
## Describes a mission to start. Every peer builds the same GameState from the same config,
## so this is what the host sends to clients when a match starts.

const MAP := "res://maps/mission_01.txt"
const CLASSES: Array[String] = ["trooper", "marksman", "medic", "breacher"]
const ENEMIES: Array[String] = ["runner", "runner", "spitter", "runner", "spitter"]


## Splits the 4-soldier squad across `num_players` (1: all four, 2: two each, 3: 2-1-1, 4: one each).
static func make(num_players: int, seed: int = 0) -> Dictionary:
	var n := clampi(num_players, 1, CLASSES.size())
	var squad: Array = []
	for i in CLASSES.size():
		squad.append({"kind": CLASSES[i], "player": i * n / CLASSES.size()})
	var s := seed if seed != 0 else randi() % 1000000 + 1
	# Until fight nodes supply their own, every match rolls an act 1 skirmish layout from its seed.
	return {"map": MAP, "squad": squad, "enemies": ENEMIES.duplicate(), "seed": s,
		"map_spec": {"biome": "wall", "objective": "skirmish", "seed": s}}


static func build(config: Dictionary) -> GameState:
	var enemies: Array[String] = []
	enemies.assign(config.enemies)
	# "map_spec" generates the layout (MapGen); without it the handmade "map" file is loaded.
	if config.has("map_spec"):
		return Rules.new_mission_on_grid(MapGen.generate(config.map_spec), config.squad, enemies, config.seed)
	return Rules.new_mission(config.map, config.squad, enemies, config.seed)
