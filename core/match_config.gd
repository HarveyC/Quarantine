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
	return {"map": MAP, "squad": squad, "enemies": ENEMIES.duplicate(), "seed": seed if seed != 0 else randi() % 1000000 + 1}


static func build(config: Dictionary) -> GameState:
	var enemies: Array[String] = []
	enemies.assign(config.enemies)
	return Rules.new_mission(config.map, config.squad, enemies, config.seed)
