extends Control
## Root of the combat HUD: turn banner and objective (top left), squad readiness (top
## right), squad roster (left), field log (bottom left), action bar (bottom centre),
## shot preview (bottom right), unit nameplates, hover card, toasts, phase banner and
## the mission-end overlay. Reads GameState and unit views; acts only through the
## input controller / session.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const EventText := preload("res://ui/event_text.gd")
const SquadRoster := preload("res://ui/squad_roster.gd")
const ReadinessPanel := preload("res://ui/readiness_panel.gd")
const ActionBar := preload("res://ui/action_bar.gd")
const TargetPanel := preload("res://ui/target_panel.gd")
const Nameplates := preload("res://ui/nameplates.gd")
const CombatLog := preload("res://ui/combat_log.gd")
const EndOverlay := preload("res://ui/end_overlay.gd")
const FightDebrief := preload("res://ui/fight_debrief.gd")
const CinematicOverlay := preload("res://ui/cinematic_overlay.gd")
const UnitView := preload("res://view/unit_view.gd")
const InputController := preload("res://view/input_controller.gd")

const MARGIN := 22.0

var view: MissionView
## Per-player readiness rows (player id -> row with ready_button()).
var panels: Dictionary = {}
var roster: SquadRoster
var readiness: ReadinessPanel
var action_bar: ActionBar
var target_panel: TargetPanel
var nameplates: Nameplates
var combat_log: CombatLog
var end_overlay: EndOverlay
## Run fights end on this instead of the overlay: banner, squad summary, then on to the rewards.
var debrief: FightDebrief
var cine_overlay: CinematicOverlay
## HUD pieces hidden while a shot cinematic plays.
var _tactical: Array[Control] = []
var _tactical_a := 1.0
var _cinematic := false
var _debriefing := false
var _turn_label: Label
var _phase_squad: PanelContainer
var _phase_enemy: PanelContainer
var _objective: Label
var _hostiles: Label
var _session_label: Label
var _hint: PanelContainer
var _hint_label: Label
var _toast: Label
var _banner: Label
var _tooltip: Control
var _toast_t := 0.0
var _banner_t := 0.0
## The Bloom creeping in from the screen's right edge, further as the squad's Infection climbs.
var _veins: W.Veins


func setup(v: MissionView) -> void:
	view = v
	name = "HUD"
	theme = Styles.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The HUD draws its own nameplates instead of the floating 3D letters.
	UnitView.world_labels = false
	for uv in view.unit_views.values():
		uv.set_overlays_visible(true)
	_veins = W.Veins.new("right", 0.05, 5, 31)
	_veins.alpha = 0.32
	_veins.branching = 0.12
	_veins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_veins)
	nameplates = Nameplates.new()
	nameplates.build(view)
	add_child(nameplates)
	_build_turn_banner()
	_build_readiness()
	_build_roster()
	_build_bottom()
	_build_overlays()
	for c in get_children():
		if c is Control and c != _banner and c != _toast and c != end_overlay and c != debrief:
			_tactical.append(c)
	cine_overlay = CinematicOverlay.new()
	cine_overlay.build()
	add_child(cine_overlay)
	move_child(end_overlay, get_child_count() - 1)
	move_child(debrief, get_child_count() - 1)
	refresh()


func _corner(preset: Control.LayoutPreset, c: Control, gh: Control.GrowDirection, gv: Control.GrowDirection) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	c.grow_horizontal = gh
	c.grow_vertical = gv
	add_child(c)


func _build_turn_banner() -> void:
	var box := Styles.vbox(10)
	var top := Styles.hbox(14)
	_turn_label = Styles.caps("Turn 01", 46)
	_turn_label.add_theme_constant_override("outline_size", 8)
	_turn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	top.add_child(_turn_label)
	var phases := Styles.hbox(8)
	phases.size_flags_vertical = Control.SIZE_SHRINK_END
	_phase_squad = W.chip("Squad phase", Styles.AMBER)
	phases.add_child(_phase_squad)
	phases.add_child(W.Icon.new("check", Color(0, 0, 0, 0), 6.0))
	_phase_enemy = W.chip("Enemy phase", Styles.DANGER, false)
	phases.add_child(_phase_enemy)
	var pad := Styles.vbox(0)
	pad.add_child(phases)
	pad.add_child(Control.new())
	pad.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(pad)
	box.add_child(top)
	var obj := Styles.hbox(8)
	obj.add_child(W.Icon.new("flag", Styles.AMBER, 17.0, 2.0))
	_objective = Styles.label("Clear the checkpoint", 15)
	obj.add_child(_objective)
	obj.add_child(Styles.label("·", 15, Styles.MUTED))
	_hostiles = Styles.mono("", 13, Styles.DANGER_TEXT)
	obj.add_child(_hostiles)
	box.add_child(obj)
	_session_label = Styles.label("", 12, Styles.MUTED)
	box.add_child(_session_label)
	_corner(Control.PRESET_TOP_LEFT, box, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)


func _build_readiness() -> void:
	readiness = ReadinessPanel.new()
	readiness.build(view.state.players)
	readiness.ready_toggled.connect(_on_ready_toggled)
	panels = readiness.rows
	_corner(Control.PRESET_TOP_RIGHT, readiness, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)


func _build_roster() -> void:
	roster = SquadRoster.new()
	roster.build()
	roster.unit_clicked.connect(_on_unit_clicked)
	_corner(Control.PRESET_TOP_LEFT, roster, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	roster.offset_top = 150


func _build_bottom() -> void:
	combat_log = CombatLog.new()
	combat_log.build()
	_corner(Control.PRESET_BOTTOM_LEFT, combat_log, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)

	var mid := Styles.vbox(8)
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", Styles.panel_box(Color(0.04, 0.055, 0.09, 0.9), Styles.BORDER, Styles.PILL))
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label = Styles.label("", 14, Styles.TEXT)
	_hint.add_child(_hint_label)
	mid.add_child(_hint)
	action_bar = ActionBar.new()
	action_bar.build()
	action_bar.action_pressed.connect(func(key: String) -> void: view.input.trigger(key))
	action_bar.ready_pressed.connect(_on_ready_pressed)
	mid.add_child(action_bar)
	_corner(Control.PRESET_CENTER_BOTTOM, mid, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)

	var right := Styles.vbox(10)
	target_panel = TargetPanel.new()
	target_panel.build()
	target_panel.visible = false
	right.add_child(target_panel)
	right.add_child(_key_legend())
	_corner(Control.PRESET_BOTTOM_RIGHT, right, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)


## Four keys worth knowing, as keycaps; Esc opens the menu with the full list.
func _key_legend() -> Control:
	var row := Styles.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	for k in [["1-9", "Actions"], ["Tab", "Next"], ["Space", "Ready"], ["Esc", "Menu"]]:
		row.add_child(W.keycap(k[0], 11))
		var l := Styles.caps(k[1], 11, Styles.MUTED)
		row.add_child(l)
		if k[0] != "Esc":
			var gap := Control.new()
			gap.custom_minimum_size.x = 6
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
	return row


func _build_overlays() -> void:
	_banner = Styles.caps("", 56)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top -= 170
	_banner.offset_bottom -= 170
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_banner.modulate.a = 0.0
	add_child(_banner)
	_toast = Styles.caps("", 17, Styles.AMBER)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 92)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_toast.modulate.a = 0.0
	add_child(_toast)
	end_overlay = EndOverlay.new()
	end_overlay.build()
	end_overlay.restart_pressed.connect(func() -> void: view.restart())
	end_overlay.leave_pressed.connect(func() -> void: view.leave())
	add_child(end_overlay)
	debrief = FightDebrief.new()
	debrief.finished.connect(view.on_debrief_finished)
	add_child(debrief)


# --- updates -----------------------------------------------------------------

func refresh() -> void:
	var s := view.state
	var can_act := view.input != null and view.input.can_act()
	# Turn and phase as currently shown by the event player, not the (ahead) rules state.
	var shown_turn := s.turn
	var enemy := false
	var over := false
	if view.player != null:
		shown_turn = view.player.turn
		over = view.player.ended
		enemy = view.player.enemy_phase
	_turn_label.text = "TURN %02d" % shown_turn
	_set_chip(_phase_squad, Styles.AMBER, not enemy and not over)
	_set_chip(_phase_enemy, Styles.DANGER, enemy and not over)
	var hostiles := s.living(Types.Team.ENEMY).size()
	_hostiles.text = "%d hostile%s" % [hostiles, "" if hostiles == 1 else "s"]
	_objective.text = Objectives.describe(s)
	_session_label.text = view.session.status_text()
	var sel := view.input.selected_id if view.input != null else -1
	roster.refresh(view, sel, can_act)
	readiness.refresh(view, can_act)
	if view.input != null:
		action_bar.refresh(view)
		_refresh_targeting()
	nameplates.refresh()
	var worst := 0
	for u in s.living(Types.Team.PLAYER):
		worst = maxi(worst, u.infection)
	var reach := 0.04 + worst / 100.0 * 0.26
	if absf(reach - _veins.reach) > 0.01:
		_veins.set_reach(reach)


func _set_chip(chip: PanelContainer, col: Color, on: bool) -> void:
	var sb := chip.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = col if on else Color.TRANSPARENT
	sb.border_color = col if on else Styles.BORDER_STRONG
	var l := chip.get_child(0) as Label
	l.add_theme_color_override("font_color", Styles.GROUND if on else Styles.DIM)


func _refresh_targeting() -> void:
	var input: InputController = view.input
	var hint := ""
	target_panel.visible = false
	match input.mode:
		InputController.Mode.SHOOT:
			var t := input.current_target()
			var u := input.selected_unit()
			if t != null and u != null:
				target_panel.show_shot(view.state, u, t)
				target_panel.visible = true
		InputController.Mode.TARGET_UNIT:
			hint = "Pick a target unit  ·  Esc to cancel"
		InputController.Mode.TARGET_CELL:
			hint = "Pick a target tile  ·  Esc to cancel"
	_hint_label.text = hint
	_hint.modulate.a = 1.0 if hint != "" else 0.0


## Called by the event player as each event starts playing.
func on_beat(ev: Dictionary) -> void:
	if not ev.get("_hidden", false):
		combat_log.add_line(EventText.describe(ev, view.unit_name))
	refresh()


func banner(text: String, color: Color) -> void:
	_banner.text = text.to_upper()
	_banner.add_theme_color_override("font_color", color)
	_banner_t = 1.6


func toast(text: String) -> void:
	_toast.text = text.to_upper()
	_toast_t = 2.2


## Hover card for a unit: name, owner, HP, Infection and statuses, plus the hit chance
## when the selected soldier could shoot it.
func show_tooltip(uv: UnitView) -> void:
	hide_tooltip()
	if _debriefing:
		return
	var col := Styles.player_color(uv.owner_player) if uv.is_soldier else Styles.DANGER
	var f := W.Frame.new(Vector4(12, 9, 12, 10))
	f.custom_minimum_size = Vector2(230, 0)
	var box := Styles.vbox(6)
	f.add_child(box)
	var head := Styles.hbox(8)
	head.add_child(Styles.caps(uv.display_name, 17))
	head.add_child(Styles.spacer())
	if uv.is_soldier:
		head.add_child(Styles.caps(SquadRoster.owner_name(view, uv.owner_player), 12, col))
	box.add_child(head)
	var sub := Styles.hbox(8)
	var kind_name: String = UnitData.SOLDIERS.get(uv.kind, UnitData.ENEMIES.get(uv.kind, {})).get("name", uv.kind.capitalize())
	sub.add_child(Styles.label("%s · HP %d/%d" % [kind_name, uv.hp, uv.max_hp], 13, Styles.DIM))
	sub.add_child(Styles.spacer())
	var hp := W.Pips.new(Vector2(9, 5))
	hp.set_values(uv.max_hp, uv.hp, 0, Styles.HP if uv.is_soldier else Styles.DANGER)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_child(hp)
	box.add_child(sub)
	if uv.is_soldier:
		var inf := Styles.hbox(8)
		var bar := W.InfBar.new(5.0)
		bar.set_value(uv.infection)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inf.add_child(bar)
		inf.add_child(Styles.mono("%d %s" % [uv.infection, Infection.tier_name(uv.tier).to_upper()], 10, Styles.TEAL))
		box.add_child(inf)
	var chips := Styles.hbox(6)
	if uv.overwatch:
		chips.add_child(W.chip("Overwatch", Styles.AMBER, false, 11))
	if uv.hunkered:
		chips.add_child(W.chip("Hunkered", Styles.AMBER, false, 11))
	var sel := view.input.selected_unit()
	var target := view.state.get_unit(uv.unit_id)
	if sel != null and target != null and sel.id != target.id and sel.is_enemy_of(target) \
			and Combat.shot_targets(view.state, sel).has(target):
		var odds := Combat.hit_chance(view.state, sel, target)
		chips.add_child(W.chip("Hit %d%%" % int(odds.get("hit", 0)), Styles.AMBER, true, 11))
		if odds.get("flanked", false):
			chips.add_child(W.chip("Flanked", Styles.DANGER, true, 11))
	if chips.get_child_count() > 0:
		box.add_child(chips)
	_tooltip = f
	add_child(f)
	if is_inside_tree():
		f.reset_size()
		var mp := get_local_mouse_position() + Vector2(18, 18)
		f.position = Vector2(minf(mp.x, size.x - f.size.x - 8), minf(mp.y, size.y - f.size.y - 8))


func hide_tooltip() -> void:
	if _tooltip != null:
		remove_child(_tooltip)
		_tooltip.queue_free()
		_tooltip = null


func show_end(result: int) -> void:
	if view.session.get("run") != null:
		_debriefing = true
		hide_tooltip()
		debrief.play(view.state, view.session, view.autoplay)
		return
	end_overlay.show_result(result, view.state.turn, view.session.can_restart(), false)


func set_cinematic(on: bool) -> void:
	_cinematic = on
	cine_overlay.set_active(on)
	if on:
		hide_tooltip()


func cine_caption(text: String, sub: String) -> void:
	cine_overlay.caption(text, sub)


func cine_result(word: String, color: Color) -> void:
	cine_overlay.result(word, color)


func toast_text() -> String:
	return _toast.text if _toast_t > 0.0 else ""


func _process(delta: float) -> void:
	_toast_t = maxf(0.0, _toast_t - delta)
	_banner_t = maxf(0.0, _banner_t - delta)
	_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_banner.modulate.a = clampf(_banner_t / 0.4, 0.0, 1.0)
	_tactical_a = move_toward(_tactical_a, 0.0 if _cinematic or _debriefing else 1.0, delta * 6.0)
	for c in _tactical:
		c.modulate.a = _tactical_a
		c.visible = _tactical_a > 0.01


func _on_unit_clicked(id: int) -> void:
	if view.input.can_act():
		view.input.select(id)


## Toggles Ready for the local player the READY button acts for (Space shortcut).
func toggle_ready() -> void:
	_on_ready_pressed()


func _on_ready_pressed() -> void:
	var p := ActionBar.ready_player(view)
	if p >= 0:
		_on_ready_toggled(p, not view.state.ready.get(p, false))


func _on_ready_toggled(player: int, on: bool) -> void:
	if view.input.can_act():
		if view.sfx != null:
			view.sfx.play("ui_confirm" if on else "ui_click")
		view.session.set_ready(player, on)
	else:
		refresh()
