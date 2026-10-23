class_name TestCase
extends RefCounted
## Minimal assertion base for headless tests. Each test file extends this and
## defines methods named test_*. Run all with: godot --headless -s tests/run_tests.gd

var failures: Array[String] = []


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		failures.append(msg)


func assert_eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s expected %s, got %s" % [msg, str(expected), str(actual)])


## A fresh mission on the standard test map with a fixed seed.
func make_state(enemies: Array[String] = ["runner"], seed: int = 1234) -> GameState:
	var squad := [
		{"kind": "trooper", "player": 0}, {"kind": "marksman", "player": 0},
		{"kind": "medic", "player": 1}, {"kind": "breacher", "player": 1},
	]
	return Rules.new_mission("res://maps/mission_01.txt", squad, enemies, seed)


## A tiny state built from map rows, with no units. Add them with s.add_unit.
func make_blank(rows: PackedStringArray, seed: int = 1234) -> GameState:
	var s := GameState.new()
	s.rng.seed = seed
	s.grid = Grid.from_rows(rows)
	s.players.assign([0])
	return s
