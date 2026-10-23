extends Node3D
## Entry point. Builds a mission and hands it to the view.
## OWNER: view/HUD workstream (this is a placeholder).

var state: GameState


func _ready() -> void:
	var squad := [
		{"kind": "trooper", "player": 0}, {"kind": "marksman", "player": 0},
		{"kind": "medic", "player": 1}, {"kind": "breacher", "player": 1},
	]
	var enemies: Array[String] = ["runner", "runner", "spitter", "runner", "spitter"]
	state = Rules.new_mission("res://maps/mission_01.txt", squad, enemies)
	state.event.connect(func(ev): print(ev))
	Rules.start_mission(state)
