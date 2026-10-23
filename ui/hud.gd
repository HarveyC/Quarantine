extends Control
## Root of the HUD: top bar, per-player squad panels, action bar, combat log,
## hover tooltip, toasts, phase banner and the mission-end overlay.
## Reads GameState and unit views; acts only through the input controller / Rules.

const Styles := preload("res://ui/styles.gd")
const Palette := preload("res://view/palette.gd")
const EventText := preload("res://ui/event_text.gd")
const PlayerPanel := preload("res://ui/player_panel.gd")
const ActionBar := preload("res://ui/action_bar.gd")
const CombatLog := preload("res://ui/combat_log.gd")
const EndOverlay := preload("res://ui/end_overlay.gd")
const UnitView := preload("res://view/unit_view.gd")

var view: MissionView
var panels: Dictionary = {}   # player id -> PlayerPanel
var action_bar: ActionBar
var combat_log: CombatLog
var end_overlay: EndOverlay
var _phase_label: Label
var _ready_label: Label
var _toast: Label
var _banner: Label
var _tooltip: PanelContainer
var _tooltip_text: RichTextLabel
var _toast_t := 0.0
var _banner_t := 0.0


func setup(v: MissionView) -> void:
	view = v
	name = "HUD"
	theme = Styles.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_player_panels()
	_build_bottom()
	_build_overlays()
	refresh()


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(bar)
	var box := VBoxContainer.new()
	bar.add_child(box)
	_phase_label = Styles.label("", 20)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_phase_label)
	_ready_label = Styles.label("", 13, Styles.MUTED)
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_ready_label)


func _build_player_panels() -> void:
	var left := _side_column(Control.PRESET_TOP_LEFT, Control.GROW_DIRECTION_END)
	var right := _side_column(Control.PRESET_TOP_RIGHT, Control.GROW_DIRECTION_BEGIN)
	for p in view.state.players:
		var panel := PlayerPanel.new()
		panel.build(p)
		panel.unit_clicked.connect(_on_unit_clicked)
		panel.ready_toggled.connect(_on_ready_toggled)
		(left if p % 2 == 0 else right).add_child(panel)
		panels[p] = panel


func _side_column(preset: Control.LayoutPreset, grow: Control.GrowDirection) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 12)
	col.grow_horizontal = grow
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	return col


func _build_bottom() -> void:
	action_bar = ActionBar.new()
	action_bar.build()
	action_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_bar.action_pressed.connect(func(key: String) -> void: view.input.trigger(key))
	add_child(action_bar)
	combat_log = CombatLog.new()
	combat_log.build()
	combat_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	combat_log.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	combat_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(combat_log)
	var help := Styles.label("LMB select/move   1-9 actions   Tab next soldier   RMB/Esc cancel\nWASD pan   Q/E rotate   wheel zoom   F focus", 12, Styles.MUTED)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(help)


func _build_overlays() -> void:
	_banner = Styles.label("", 40)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top -= 160
	_banner.offset_bottom -= 160
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.modulate.a = 0.0
	add_child(_banner)
	_toast = Styles.label("", 18, Color("ffcf8a"))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 80)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	add_child(_toast)
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip_text = RichTextLabel.new()
	_tooltip_text.bbcode_enabled = true
	_tooltip_text.fit_content = true
	_tooltip_text.scroll_active = false
	_tooltip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_text)
	add_child(_tooltip)
	end_overlay = EndOverlay.new()
	end_overlay.build()
	end_overlay.restart_pressed.connect(func() -> void: view.restart())
	end_overlay.leave_pressed.connect(func() -> void: view.leave())
	add_child(end_overlay)


# --- updates -----------------------------------------------------------------

func refresh() -> void:
	var s := view.state
	var can_act := view.input != null and view.input.can_act()
	# Turn and phase as currently shown by the event player, not the (ahead) rules state.
	var shown_turn := s.turn
	var phase := "SQUAD PHASE"
	if view.player != null:
		shown_turn = view.player.turn
		if view.player.ended:
			phase = "MISSION OVER"
		elif view.player.enemy_phase:
			phase = "ENEMY PHASE"
	_phase_label.text = "TURN %d   -   %s" % [shown_turn, phase]
	var waiting := PackedStringArray()
	if phase == "SQUAD PHASE":
		for p in s.players:
			waiting.append("P%d %s" % [p + 1, "ready" if s.ready.get(p, false) else "acting"])
	elif phase == "ENEMY PHASE":
		waiting.append("Hostiles moving...")
	waiting.append("·  " + view.session.status_text())
	_ready_label.text = "   ".join(waiting)
	var sel := view.input.selected_id if view.input != null else -1
	for p in panels:
		panels[p].refresh(view, sel, can_act)
	if view.input != null:
		action_bar.refresh(view)


## Called by the event player as each event starts playing.
func on_beat(ev: Dictionary) -> void:
	combat_log.add_line(EventText.describe(ev, view.unit_name))
	refresh()


func banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_t = 1.6


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.2


func show_tooltip(uv: UnitView) -> void:
	var lines := PackedStringArray()
	var col := Palette.player_ui(uv.owner_player) if uv.is_soldier else Palette.DANGER
	lines.append("[b][color=#%s]%s[/color][/b]" % [col.to_html(false), uv.label()])
	lines.append("HP %d/%d" % [uv.hp, uv.max_hp])
	if uv.is_soldier:
		lines.append("Infection %d - %s" % [uv.infection, Infection.tier_name(uv.tier)])
	var sel := view.input.selected_unit()
	var target := view.state.get_unit(uv.unit_id)
	if sel != null and target != null and sel.id != target.id and sel.is_enemy_of(target) \
			and Combat.visible_targets(view.state, sel).has(target):
		lines.append(ActionBar.hit_text(view.state, sel, target).split("\n", true, 2)[1])
	_tooltip_text.text = "\n".join(lines)
	_tooltip.visible = true
	if is_inside_tree():
		_tooltip.position = get_viewport().get_mouse_position() + Vector2(18, 18)
		_tooltip.reset_size()


func hide_tooltip() -> void:
	_tooltip.visible = false


func show_end(result: int) -> void:
	end_overlay.show_result(result, view.state.turn, view.session.can_restart())


func toast_text() -> String:
	return _toast.text if _toast_t > 0.0 else ""


func _process(delta: float) -> void:
	_toast_t = maxf(0.0, _toast_t - delta)
	_banner_t = maxf(0.0, _banner_t - delta)
	_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_banner.modulate.a = clampf(_banner_t / 0.4, 0.0, 1.0)


func _on_unit_clicked(id: int) -> void:
	if view.input.can_act():
		view.input.select(id)


func _on_ready_toggled(player: int, on: bool) -> void:
	if view.input.can_act():
		view.session.set_ready(player, on)
	else:
		refresh()
