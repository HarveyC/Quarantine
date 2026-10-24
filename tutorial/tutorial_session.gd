class_name TutorialSession
extends LocalSession
## The training mission on this machine: a LocalSession whose fight is TutorialScript's map,
## with the script advancing its lessons after every change. Nothing is saved: training never
## touches the run save slot.

signal step_changed(step: int)

var drill: TutorialScript
var _tick_queued := false


func status_text() -> String:
	return "Training"


func can_restart() -> bool:
	return true


func start_tutorial() -> void:
	run = null
	save_enabled = false
	drill = TutorialScript.new()
	state = drill.build_state()
	state.event.connect(_on_event)
	match_started.emit(state)


func start_new(_num_players: int = 1, _seed: int = 0) -> void:
	start_tutorial()


func restart() -> void:
	start_tutorial()


## Continue on an info lesson (the overlay's button).
func proceed() -> void:
	drill.proceed(state)
	step_changed.emit(drill.step)


func jump_to(n: int) -> void:
	drill.jump_to(state, n)
	step_changed.emit(drill.step)


func _on_event(ev: Dictionary) -> void:
	drill.observe(state, ev)
	# Lessons set up with their own events, so they wait until the action that met the
	# last goal has finished applying.
	if not _tick_queued:
		_tick_queued = true
		tick.call_deferred()


func tick() -> void:
	_tick_queued = false
	if drill != null and state != null and drill.update(state):
		step_changed.emit(drill.step)
