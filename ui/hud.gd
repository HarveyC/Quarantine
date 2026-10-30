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
const OverlayLegend := preload("res://ui/overlay_legend.gd")
const CinematicOverlay := preload("res://ui/cinematic_overlay.gd")
const AttackCallout := preload("res://ui/attack_callout.gd")
const UnitView := preload("res://view/unit_view.gd")
const InputController := preload("res://view/input_controller.gd")
const Tips := preload("res://ui/tips/tips.gd")
const LoadoutScreen := preload("res://ui/gear/loadout_screen.gd")
const Feel := preload("res://ui/ui_feel.gd")

const MARGIN := 22.0

var view: MissionView
## Per-player readiness rows (player id -> row with ready_button()).
var panels: Dictionary = {}
var roster: SquadRoster
var readiness: ReadinessPanel
var action_bar: ActionBar
var target_panel: TargetPanel
## Lists the floor markings on screen (move range, hazards, zones...).
var map_key: OverlayLegend
var nameplates: Nameplates
var combat_log: CombatLog
var end_overlay: EndOverlay
## Run fights end on this instead of the overlay: banner, squad summary, then on to the rewards.
var debrief: FightDebrief
var cine_overlay: CinematicOverlay
var callout: AttackCallout
## HUD pieces hidden while a shot cinematic plays.
var _tactical: Array[Control] = []
var _tactical_a := 1.0
var _cinematic := false
var _debriefing := false
var _turn_label: Label
## One word for whose phase it is, no pills.
var _phase: Label
var _objective: Label
var _hostiles: Label
var _stealth_icon: W.Icon
var _stealth_row: Control
var _stealth_word: Label
var _stealth_shown := -1   # 1 concealed, 0 detected, -1 not built yet
var _session_label: Label
var _banner_box: Control
var _hint: PanelContainer
var _hint_label: Label
var _keys: Control
var _toast: Label
var _banner: Label
var _tooltip: Control
var _tooltip_uv: UnitView
var _move_warning: Control
var _loadout: Control
var _toast_t := 0.0
var _banner_t := 0.0
## The Bloom creeping in from the screen's right edge, further as the squad's Infection climbs.
var _veins: W.Veins
## Concealed: a cold-blue edge round the whole screen; it flares red the moment the squad is seen.
var _stealth_edge: TextureRect
var _stealth_edge_mat: GradientTexture2D
var _alarm_t := 0.0


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
	_build_stealth_edge()
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
	callout = AttackCallout.new()
	callout.build()
	add_child(callout)
	move_child(end_overlay, get_child_count() - 1)
	move_child(debrief, get_child_count() - 1)
	refresh()


func _build_stealth_edge() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.58, 0.84, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.75)])
	_stealth_edge_mat = GradientTexture2D.new()
	_stealth_edge_mat.gradient = g
	_stealth_edge_mat.fill = GradientTexture2D.FILL_RADIAL
	_stealth_edge_mat.fill_from = Vector2(0.5, 0.5)
	_stealth_edge_mat.fill_to = Vector2(1.0, 1.0)
	_stealth_edge_mat.width = 256
	_stealth_edge_mat.height = 256
	_stealth_edge = TextureRect.new()
	_stealth_edge.name = "StealthEdge"
	_stealth_edge.texture = _stealth_edge_mat
	_stealth_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stealth_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_stealth_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stealth_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()   # a glow on the edge, not a darker frame
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_stealth_edge.material = add
	_stealth_edge.modulate = Color(Styles.STEALTH, 0.0)
	add_child(_stealth_edge)


## The red flare on the screen edge when concealment breaks (EventPlayer).
func alarm() -> void:
	_alarm_t = 1.6


func stealth_edge_alpha() -> float:
	return _stealth_edge.modulate.a


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
	_phase = Styles.caps("Squad phase", 15, Styles.AMBER)
	_phase.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_outline(_phase)
	top.add_child(_phase)
	box.add_child(top)
	var obj := Styles.hbox(8)
	obj.add_child(W.Icon.new("flag", Styles.AMBER, 17.0, 2.0))
	_objective = Styles.label("Clear the checkpoint", 15)
	_outline(_objective)
	obj.add_child(_objective)
	obj.add_child(Styles.label("·", 15, Styles.MUTED))
	_hostiles = Styles.mono("", 13, Styles.DANGER_TEXT)
	_outline(_hostiles)
	obj.add_child(_hostiles)
	box.add_child(obj)
	var stealth := Styles.hbox(8)
	_stealth_icon = W.Icon.new("concealed", Styles.STEALTH, 17.0, 2.0)
	stealth.add_child(_stealth_icon)
	_stealth_word = Styles.caps("Concealed", 13, Styles.STEALTH)
	_outline(_stealth_word)
	stealth.add_child(_stealth_word)
	Tips.term(stealth, "concealed")
	_stealth_row = stealth
	box.add_child(stealth)
	# Only online games say anything here ("Waiting for Kestrel"); a local run needs no line.
	_session_label = Styles.label("", 12, Styles.MUTED)
	_outline(_session_label)
	box.add_child(_session_label)
	_banner_box = box
	_corner(Control.PRESET_TOP_LEFT, box, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)


## A dark outline so text reads straight on the scene without a box behind it.
static func _outline(l: Label, px := 5) -> void:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", Color(Styles.GROUND, 0.8))


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
	# The roster starts under the turn banner, which grows with the text size.
	if _banner_box != null:
		_banner_box.resized.connect(func() -> void:
			roster.offset_top = maxf(150.0, _banner_box.position.y + _banner_box.size.y + 16.0))


func _build_bottom() -> void:
	combat_log = CombatLog.new()
	combat_log.build()
	_corner(Control.PRESET_BOTTOM_LEFT, combat_log, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)

	var mid := Styles.vbox(8)
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label = Styles.label("", 14, Styles.TEXT)
	_outline(_hint_label, 6)
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
	map_key = OverlayLegend.new()
	map_key.build(view)
	right.add_child(map_key)
	_keys = _key_legend()
	right.add_child(_keys)
	_corner(Control.PRESET_BOTTOM_RIGHT, right, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)


## Four keys worth knowing, as keycaps; Esc opens the menu with the full list.
func _key_legend() -> Control:
	var row := Styles.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	# Quiet reminders, at half strength: they matter on the first fight, not every turn.
	row.modulate.a = 0.55
	for k in [["1-9", "Actions"], ["Tab", "Next"], ["I", "Loadout"], ["Space", "Ready"], ["Esc", "Menu"]]:
		var item := Styles.hbox(6)
		item.add_child(W.keycap(k[0], 11))
		var l := Styles.caps(k[1], 11, Styles.MUTED)
		_outline(l, 4)
		item.add_child(l)
		if k[0] == "I":
			# The one legend entry that is also a button.
			item.mouse_filter = Control.MOUSE_FILTER_STOP
			item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			item.tooltip_text = "Gear, pockets and grafts of your squad  [I]"
			item.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					open_loadout())
		row.add_child(item)
		if k[0] != "Esc":
			var gap := Control.new()
			gap.custom_minimum_size.x = 6
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
	return row


## A read-only look at the selected soldier's loadout over the fight; any soldier in the squad
## can be viewed, teammates' included. Runs only: a lone mission has no loadouts.
func open_loadout() -> void:
	if is_instance_valid(_loadout):
		return
	var run: RunState = view.session.get("run") if view.session != null else null
	if run == null or view.state == null or _debriefing:
		return
	var sid := -1
	var sel := view.state.get_unit(view.input.selected_id) if view.input != null else null
	if sel != null and sel.status.has("sid"):
		sid = int(sel.status.sid)
	_loadout = LoadoutScreen.open_in_fight(self, run, view.session, view.state, sid)
	Feel.sound("open")


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

var _last_left := {}   # player -> actions left as of the last refresh
var _auto_readied := {}   # player -> turn auto ready already fired


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
	_phase.text = "ENEMY PHASE" if enemy else "SQUAD PHASE"
	_phase.add_theme_color_override("font_color", Styles.DANGER_TEXT if enemy else Styles.AMBER)
	_phase.visible = not over
	var hostiles := s.living(Types.Team.ENEMY).size()
	_hostiles.text = "%d hostile%s" % [hostiles, "" if hostiles == 1 else "s"]
	_objective.text = Objectives.describe(s)
	_refresh_stealth()
	_session_label.text = "" if view.session is LocalSession else view.session.status_text()
	_session_label.visible = _session_label.text != ""
	var sel := view.input.selected_id if view.input != null else -1
	roster.refresh(view, sel, can_act)
	readiness.refresh(view, can_act)
	if can_act:
		_auto_ready()
	if view.input != null:
		action_bar.refresh(view)
		_refresh_targeting()
	if view.player == null or not view.player.is_busy():
		for uv in view.unit_views.values():
			var mu := view.state.get_unit(uv.unit_id)
			if mu != null and mu.team == Types.Team.ENEMY:
				uv.sync_mark(mu.is_alive() and Combat.has_status(view.state, mu, "tagged"), view.player.phase_now() + 1 if view.player != null else 1)
	if view.intents != null:   # any HUD change (a kill, a move, a shove) can change what enemies plan
		view.intents.refresh()
	nameplates.refresh()
	var worst := 0
	for u in s.living(Types.Team.PLAYER):
		worst = maxi(worst, u.infection)
	var reach := 0.04 + worst / 100.0 * 0.26
	if absf(reach - _veins.reach) > 0.01:
		_veins.set_reach(reach)


## The Concealed / Detected line (the coach points at it).
func stealth_chip() -> Control:
	return _stealth_row


## Concealed (cold blue) until the event player shows the squad being spotted, then Detected
## (enemy pink) for the rest of the fight.
func _refresh_stealth() -> void:
	var on := view.player.concealed if view.player != null else Concealment.active(view.state)
	if int(on) == _stealth_shown:
		return
	_stealth_shown = int(on)
	var col := Styles.STEALTH if on else Styles.DANGER
	_stealth_icon.set_icon("concealed" if on else "detected", col)
	_stealth_word.text = "CONCEALED" if on else "DETECTED"
	_stealth_word.add_theme_color_override("font_color", col if on else Styles.DANGER_TEXT)


func _refresh_targeting() -> void:
	var input: InputController = view.input
	var hint := ""
	target_panel.visible = false
	match input.mode:
		InputController.Mode.SHOOT:
			var t := input.current_target()
			var b := input.current_barrel()
			var u := input.selected_unit()
			if t != null and u != null:
				target_panel.show_shot(view.state, u, t)
				target_panel.visible = true
			elif b != InputController.NO_CELL and u != null:
				target_panel.show_barrel(view.state, u, b)
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
	_tooltip_uv = uv
	var tips := Tips.host()
	if tips != null and not tips.expanded_changed.is_connected(_on_tips_expanded):
		tips.expanded_changed.connect(_on_tips_expanded)
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
	var hp := W.HpPips.new(Vector2(9, 5), 3.0)
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
	_unit_terms(box, uv, target, sel)
	_tooltip = f
	add_child(f)
	if is_inside_tree():
		f.reset_size()
		var mp := get_local_mouse_position() + Vector2(18, 18)
		f.position = Vector2(minf(mp.x, size.x - f.size.x - 8), minf(mp.y, size.y - f.size.y - 8))


## What the unit's statuses mean: a "Shift more" hint, or with Shift held one short row each.
func _unit_terms(box: VBoxContainer, uv: UnitView, u: Unit, sel: Unit) -> void:
	var keys: Array[String] = []
	if uv.turned:
		keys.append("turning")
	elif uv.lapsed:
		keys.append("lapse")
	elif uv.is_soldier and uv.infection > 0:
		keys.append("infection")
	if uv.overwatch:
		keys.append("overwatch")
	if uv.hunkered:
		keys.append("hunker")
	if u != null and view.state != null:
		if Combat.has_status(view.state, u, "suppressed"):
			keys.append("suppress")
		if Combat.has_status(view.state, u, "tagged"):
			keys.append("mark")
		if int(u.status.get("burning", 0)) > 0:
			keys.append("burning")
		if Combat.has_status(view.state, u, "contained"):
			keys.append("contained")
		if GearFx.is_restrained(view.state, u):
			keys.append("restrained")
		if sel != null and sel.id != u.id and sel.is_enemy_of(u) and Combat.shot_targets(view.state, sel).has(u):
			keys.append("flank" if Combat.hit_chance(view.state, sel, u).get("flanked", false) else "cover")
	if keys.is_empty():
		return
	if not Tips.expanded():
		var hint := Styles.hbox(6)
		hint.add_child(Styles.spacer())
		hint.add_child(W.keycap("Shift", 10))
		hint.add_child(Styles.caps("what this means", 10, Styles.MUTED, false))
		box.add_child(hint)
		return
	for k in keys:
		var e := Glossary.entry(k)
		var col := Glossary.tone(k)
		var sep := ColorRect.new()
		sep.color = Styles.BORDER_SOFT
		sep.custom_minimum_size = Vector2(0, 1)
		box.add_child(sep)
		var head := Styles.hbox(6)
		head.add_child(W.Icon.new(str(e.icon), col, 14, 1.6))
		head.add_child(Styles.caps(str(e.name), 12, col))
		head.add_child(Styles.spacer())
		var stats: Array = e.get("stats", [])
		if not stats.is_empty():
			head.add_child(Styles.mono(str(stats[0][0]), 11, Styles.TEXT))
			head.add_child(Styles.caps(Glossary.plain(str(stats[0][1])), 9, Styles.MUTED, false))
		box.add_child(head)
		var line := Styles.label(Glossary.plain(str(e.line)), 12, Styles.DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(230, 0)
		box.add_child(line)


func _on_tips_expanded(_on: bool) -> void:
	if _tooltip != null and _tooltip_uv != null and is_instance_valid(_tooltip_uv):
		show_tooltip(_tooltip_uv)


## Warning card for a move that provokes {parting_blow|Parting blows}: `lines` name each swinger.
func show_move_warning(lines: Array, pinned: bool) -> void:
	hide_move_warning()
	const W_CARD := 300.0
	var f := W.Frame.new(Vector4(12, 9, 12, 10))
	f.custom_minimum_size = Vector2(W_CARD + 24.0, 0)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Styles.vbox(4)
	f.add_child(box)
	box.add_child(Tips.text("Leaving melee reach: {parting_blow|Parting blow}", 15, Styles.DANGER, W_CARD))
	for l in lines:
		box.add_child(Tips.text(str(l), 13, Styles.TEXT, W_CARD))
	box.add_child(Tips.text("Click again to move anyway." if pinned else "Click to pick this tile, click again to move anyway.", 13, Styles.DIM, W_CARD))
	_move_warning = f
	add_child(f)
	if is_inside_tree():
		f.reset_size()
		f.position = Vector2((size.x - f.size.x) * 0.5, 96.0)


func hide_move_warning() -> void:
	if _move_warning != null:
		remove_child(_move_warning)
		_move_warning.queue_free()
		_move_warning = null


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
	end_overlay.show_result(result, view.state.turn, view.session.can_restart(), false, Objectives.loss_cause(view.state))


func set_cinematic(on: bool) -> void:
	_cinematic = on
	cine_overlay.set_active(on)
	if on:
		hide_tooltip()


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
	_alarm_t = maxf(0.0, _alarm_t - delta)
	var hidden := view.player != null and view.player.concealed and not view.player.ended
	var want := 0.0
	var col := Styles.STEALTH
	if _alarm_t > 0.0:
		col = Styles.DANGER
		want = 0.9 * clampf(_alarm_t / 1.0, 0.0, 1.0)
	elif hidden:
		want = (0.7 + 0.1 * sin(Time.get_ticks_msec() * 0.0021)) * _tactical_a
	var a := move_toward(_stealth_edge.modulate.a, want, delta * (6.0 if _alarm_t > 0.0 else 1.5))
	_stealth_edge.modulate = Color(col, a)
	callout.cinematic = _cinematic
	callout.bar_height = cine_overlay.bar_height()
	for c in _tactical:
		c.modulate.a = _tactical_a
		c.visible = _tactical_a > 0.01 and (c != readiness or readiness.wanted())
	# An attack callout takes the action bar's spot while it plays (nothing to press then).
	action_bar.modulate.a = 1.0 - callout.alpha()


func _on_unit_clicked(id: int) -> void:
	if view.input.can_act():
		view.input.select(id)


## Auto ready setting: a local player whose soldiers have all spent their actions is marked Ready
## once per turn, so pressing Ready again afterwards still takes it back.
func _auto_ready() -> void:
	if not GameSettings.auto_ready():
		return
	var s := view.state
	for p in s.players:
		if not view.session.is_local(p) or s.ready.get(p, false) or _auto_readied.get(p, -1) == s.turn:
			continue
		var any := false
		var left := 0
		for u in s.units:
			if u.team == Types.Team.PLAYER and u.owner_player == p and u.is_alive() and not u.ai_controlled:
				any = true
				left += u.actions_left
		# Only fires on the refresh that sees the last action go, never on a turn that starts empty.
		var before: int = _last_left.get(p, 0)
		_last_left[p] = left
		if any and left == 0 and before > 0:
			_auto_readied[p] = s.turn
			_on_ready_toggled(p, true)


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
