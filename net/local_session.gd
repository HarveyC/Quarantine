class_name LocalSession
extends Node
## Hot-seat play on one machine: every player is local and actions apply immediately.
## NetSession has the same interface; the view only talks to a session, never to Rules directly.

signal match_started(state: GameState)
signal rejected(reason: String)

var state: GameState
var player_names := {}


func local_players() -> Array[int]:
	return state.players if state else ([] as Array[int])


func is_local(player: int) -> bool:
	return true


func can_restart() -> bool:
	return true


func start_new(num_players: int = 2, seed: int = 0) -> void:
	state = MatchConfig.build(MatchConfig.make(num_players, seed))
	match_started.emit(state)


func use_state(s: GameState) -> void:
	state = s


func submit(action: Dictionary) -> void:
	Rules.apply(state, action)


func set_ready(player: int, on: bool) -> void:
	Rules.set_ready(state, player, on)


func restart() -> void:
	start_new(state.players.size())


func status_text() -> String:
	return "Local hot-seat"
