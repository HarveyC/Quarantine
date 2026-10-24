class_name LocalSession
extends Node
## Solo and hot-seat play on one machine: every player is local and actions apply immediately.
## NetSession has the same interface; the view only talks to a session, never to Rules directly.

signal match_started(state: GameState)
## A fight resumed from a save: the view shows it without calling Rules.start_mission.
signal resynced(state: GameState)
signal rejected(reason: String)
signal run_changed(run: RunState)
## A ping, map stroke or clear (see coop/marks.gd) to show. View-only; never touches the state.
signal marked(m: Dictionary)

var state: GameState
var run: RunState
var player_names := {}
## Tests turn saving off so they don't touch the player's save slot.
var save_enabled := true
var _picks := {}
var _mark_limit := Marks.Limiter.new()


func local_players() -> Array[int]:
	if run != null:
		return run.players
	return state.players if state else ([] as Array[int])


func is_local(player: int) -> bool:
	return true


func can_restart() -> bool:
	return run == null


## A single fight. `picks` maps player -> Array of classes (see MatchConfig.squad_plan).
func start_new(num_players: int = 2, seed: int = 0, picks: Dictionary = {}) -> void:
	run = null
	_picks = picks.duplicate(true)
	state = MatchConfig.build(MatchConfig.make(num_players, seed, picks))
	match_started.emit(state)


func use_state(s: GameState) -> void:
	state = s


func submit(action: Dictionary) -> void:
	Rules.apply(state, action)


func set_ready(player: int, on: bool) -> void:
	Rules.set_ready(state, player, on)


## Shows a ping or map stroke. Every player is at this screen, so it goes straight to the view
## (through the same checks and rate limit as online, so hot-seat behaves the same).
func mark(m: Dictionary) -> bool:
	var clean := Marks.sanitize(m)
	if clean.is_empty() or not _mark_limit.allow(clean.player, clean.type, Marks.now()):
		return false
	marked.emit(clean)
	return true


func restart() -> void:
	if run == null:
		start_new(state.players.size(), 0, _picks)


func status_text() -> String:
	if run != null:
		return "Solo run" if run.is_solo() else "Local hot-seat run"
	return "Local hot-seat"


# --- runs ------------------------------------------------------------------------

## A new run for 1 (solo) to 4 local players, each with the squad in `picks` (player -> Array
## of classes; left out, solo gets 4 soldiers and hot-seat players 1 each).
func start_run(num_players: int = 1, seed: int = 0, picks: Dictionary = {}) -> void:
	run = RunRules.new_run(num_players, seed, Profile.meta(), picks)
	state = null
	RunRules.start_run(run)
	_after_run()


## Picks up a saved run, including a fight in progress.
func resume_run(saved: RunState) -> void:
	run = saved
	state = null
	if run.phase == RunState.Phase.FIGHT and not run.fight_snapshot.is_empty():
		state = GameState.from_dict(run.fight_snapshot)
		state.event.connect(_on_mission_event)
		resynced.emit(state)
		run_changed.emit(run)
		return
	_after_run()


func submit_run(action: Dictionary) -> void:
	if not RunRules.apply(run, action):
		rejected.emit(RunRules.validate(run, action) if run.phase != RunState.Phase.ENDED else "The run is over")
		return
	_after_run()


func _after_run() -> void:
	if save_enabled:
		RunSave.write(run)
	if run.phase == RunState.Phase.ENDED:
		Profile.record_run(run)
	if run.phase == RunState.Phase.FIGHT and (state == null or state.phase == Types.Phase.ENDED):
		state = MatchConfig.build(run.fight_config)
		state.event.connect(_on_mission_event)
		match_started.emit(state)
	run_changed.emit(run)


func _on_mission_event(ev: Dictionary) -> void:
	if run == null:
		return
	match ev.type:
		"team_phase":
			run.fight_snapshot = state.to_dict()
			if save_enabled:
				RunSave.write(run)
		"mission_end":
			submit_run({"type": RunRules.FIGHT_END, "player": run.host_player, "outcome": RunRules.fight_outcome(state)})
