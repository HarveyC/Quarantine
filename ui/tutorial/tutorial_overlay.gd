extends Control
## The training mission's coach, on top of the combat HUD: the current lesson's card at the
## top of the screen, an arrow to the HUD piece or the tiles it is about, amber markers on
## those tiles, and the "Training complete" card at the end. Waits while the event player is
## busy so it never talks over a shot. Reads the session's TutorialScript; acts only through
## `session.proceed()` and its own signals.

signal skip_requested
## Training is over (won): `start_run` if the player asked to go straight into a solo run.
signal finished(start_run: bool)

const Styles := preload("res://ui/styles.gd")
const CoachCard := preload("res://ui/tutorial/coach_card.gd")
const Pointer := preload("res://ui/tutorial/pointer.gd")
const CellMarkers := preload("res://ui/tutorial/cell_markers.gd")
const InputController := preload("res://view/input_controller.gd")

const TOP := 140.0

var view: MissionView
var session: TutorialSession
var card: CoachCard
var pointer: Pointer
var markers: CellMarkers
var _shown_step := -1
var _complete := false
var _alpha := 0.0


func setup(v: MissionView, s: TutorialSession) -> void:
	view = v
	session = s
	name = "TutorialOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer = Pointer.new()
	add_child(pointer)
	card = CoachCard.new()
	card.pressed.connect(_on_pressed)
	add_child(card)
	markers = CellMarkers.new()
	view.board.add_child(markers)
	card.modulate.a = 0.0
	_show_step()


func _show_step() -> void:
	var d := session.drill
	_shown_step = d.step
	if d.is_complete():
		_show_complete()
		return
	var st := d.current()
	var buttons: Array = [["skip", "Skip training", false]]
	if st.get("info", false):
		buttons.append(["next", "Continue", true])
	var line: String = StoryData.TRAINING_LINES.get(st.id, "")
	card.show_card("Training  %d / %d" % [d.step + 1, TutorialScript.STEPS.size()], st.title, st.text,
		st.get("keys", []), st.get("visual", ""), buttons, d.step, TutorialScript.STEPS.size(),
		"Major Okafor", line)
	_say("OKAFOR", line)
	markers.set_cells(_cells(st))
	if not markers.cells.is_empty() and view.camera_rig != null:
		view.camera_rig.focus(markers.world_center())
	if st.id == "infection" and d.dosed >= 0 and view.input != null:
		view.input.select(d.dosed)   # the soldier whose mutation just woke
	if view.sfx != null:
		view.sfx.play("ui_confirm")


func _show_complete() -> void:
	_complete = true
	Onboarding.mark_training_done()
	markers.set_cells([])
	pointer.clear()
	card.show_card("Training complete", "Ready for the Wall", "",
		[], "", [["menu", "Main menu", false], ["run", "Start a solo run", true]], 0, 0,
		"Major Okafor", StoryData.TRAINING_LINES.end)
	var line_len := _say("OKAFOR", StoryData.TRAINING_LINES.end)
	# The nest answers: the Source, once, a moment after the radio clicks off.
	get_tree().create_timer(line_len + 0.8).timeout.connect(func() -> void:
		if _complete:
			card.set_radio("Source", StoryData.TRAINING_LINES.whisper, Styles.TEAL)
			_say("SOURCE", StoryData.TRAINING_LINES.whisper))


## The nest lesson marks wherever the nest is; the others use their fixed cells.
func _cells(st: Dictionary) -> Array:
	return st.get("cells", [])


func _on_pressed(id: String) -> void:
	match id:
		"next":
			session.proceed()
		"skip":
			Onboarding.mark_training_done()
			var sc := get_node_or_null("/root/Soundscape")
			if sc != null:
				sc.stop_speech()
			skip_requested.emit()
		"menu":
			finished.emit(false)
		"run":
			finished.emit(true)


func _process(delta: float) -> void:
	if view == null or session == null or session.drill == null:
		return
	if session.drill.step != _shown_step:
		_show_step()
	var busy: bool = view.player != null and view.player.is_busy()
	var show := _complete or not busy
	_alpha = move_toward(_alpha, 1.0 if show else 0.0, delta * (5.0 if show else 8.0))
	card.modulate.a = _alpha
	pointer.modulate.a = _alpha
	markers.visible = not _complete
	card.mouse_filter = Control.MOUSE_FILTER_STOP if _alpha > 0.5 else Control.MOUSE_FILTER_IGNORE
	_place_card()
	if _complete:
		# Our own card replaces the generic Victory screen.
		if view.hud.end_overlay.visible:
			view.hud.end_overlay.visible = false
		return
	_aim_pointer()


## Speaks a radio line through the Soundscape; its length in seconds, 0 when unvoiced or silent.
func _say(who: String, text: String) -> float:
	var sc := get_node_or_null("/root/Soundscape")
	if sc == null or text == "":
		return 0.0
	return sc.say(who, text, {"radio": who == "OKAFOR", "scene": true})


func _place_card() -> void:
	var vp := size if size != Vector2.ZERO else get_viewport_rect().size
	card.reset_size()
	if _complete:
		card.position = (vp - card.size) * 0.5
	else:
		# Top right, under the readiness panel: the board's middle stays clear.
		var top := TOP
		if view.hud.readiness != null and view.hud.readiness.is_visible_in_tree():
			top = view.hud.readiness.get_global_rect().end.y + 18.0
		card.position = Vector2(vp.x - card.size.x - 22.0, top)


func _aim_pointer() -> void:
	var st := session.drill.current()
	var rect := Rect2()
	var found := false
	var hud := str(st.get("hud", ""))
	var target: Control = null
	match hud:
		"ready":
			target = view.hud.action_bar.ready_button()
		"overwatch", "mutation", "disengage":
			target = view.hud.action_bar.find_button(hud)
		"suppress":
			target = view.hud.action_bar.find_button("ability:suppress")
		"aim":
			if view.input.mode == InputController.Mode.SHOOT and view.hud.target_panel.visible:
				target = view.hud.target_panel
			else:
				target = view.hud.action_bar.find_button("shoot")
	if hud != "" and target == null:
		target = view.hud.roster   # nobody selected yet: point at the squad list
	if target != null and target.is_visible_in_tree():
		rect = target.get_global_rect()
		found = true
	elif not markers.cells.is_empty() and view.camera_rig != null:
		var cam := view.camera_rig.camera
		var w := markers.world_center()
		if cam != null and not cam.is_position_behind(w):
			var p := cam.unproject_position(w)
			rect = Rect2(p - Vector2(28, 28), Vector2(56, 56))
			found = true
	if found:
		pointer.point_at(card.get_global_rect(), rect, target != null)
	else:
		pointer.clear()


func _exit_tree() -> void:
	if markers != null and is_instance_valid(markers):
		markers.queue_free()
