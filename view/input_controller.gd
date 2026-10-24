extends Node
## Mouse/keyboard/gamepad input for the squad phase: selection, move preview, action
## targeting. Keys and pad buttons are InputMap actions (view/game_settings.gd). Only ever calls Rules.apply / read-only queries; never touches state.
## Hot-seat: whoever is at the keyboard may command any player's soldiers.

signal changed   # selection, mode or target changed; HUD should refresh

enum Mode { MOVE, SHOOT, TARGET_UNIT, TARGET_CELL }

const NO_CELL := Vector2i(-999, -999)
## Abilities that close in on their target before striking -> default reach in tiles of path
## (the ability's own "reach" / "range", e.g. raised by a perk, wins).
const LANDING_REACH := {"lunge": 4, "shield_charge": 3}
const Board := preload("res://view/board.gd")
const UnitView := preload("res://view/unit_view.gd")
const EventPlayer := preload("res://view/event_player.gd")
const Sfx := preload("res://view/sfx.gd")
const QuickMenu := preload("res://ui/quick_menu.gd")

var view: MissionView
var selected_id := -1
var mode := Mode.MOVE
var pending: Dictionary = {}       # action template while targeting an ability/mutation
var targets: Array[int] = []       # shoot candidates
var unit_targets: Array = []       # legal targets of the pending unit-targeted ability ([] = not listed)
var pending_reach := 0             # the pending ability's reach, if it states one
var cell_targets: Array = []       # cells the pending cell ability can pick, when it lists them (Shoot barrel)
var target_idx := 0
var hover_cell := NO_CELL
var _reach: Dictionary = {}


func can_act() -> bool:
	return view.state != null and view.state.phase == Types.Phase.TEAM \
		and not view.player.is_busy() and not view.autoplay


func controllable() -> Array[Unit]:
	var out: Array[Unit] = []
	for p in view.session.local_players():
		out.append_array(view.state.controllable_units(p))
	return out


func selected_unit() -> Unit:
	if selected_id < 0 or view.state == null:
		return null
	var u := view.state.get_unit(selected_id)
	return u if u != null and controllable().has(u) else null


func current_target() -> Unit:
	if mode != Mode.SHOOT or targets.is_empty():
		return null
	return view.state.get_unit(targets[target_idx % targets.size()])


# --- selection ---------------------------------------------------------------

func select(id: int) -> void:
	if id != selected_id:
		_ui_sound("ui_click")
	selected_id = id
	_set_mode(Mode.MOVE)
	var uv := view.view_for(id)
	if uv != null and view.camera_rig != null:
		view.camera_rig.focus(uv.position)


func deselect() -> void:
	selected_id = -1
	_set_mode(Mode.MOVE)


## Next controllable soldier, preferring ones that still have actions.
func cycle(dir := 1) -> void:
	var list := controllable()
	if list.is_empty():
		deselect()
		return
	var with_actions := list.filter(func(u: Unit) -> bool: return u.actions_left > 0)
	if not with_actions.is_empty():
		list.assign(with_actions)
	var idx := -1
	for i in list.size():
		if list[i].id == selected_id:
			idx = i
	select(list[posmod(idx + dir, list.size())].id)


## Called when the event queue has finished playing.
func on_drained() -> void:
	var u := selected_unit()
	if u == null or u.actions_left <= 0:
		if controllable().any(func(c: Unit) -> bool: return c.actions_left > 0):
			cycle(1)
			return
		if u == null:
			selected_id = -1
	_set_mode(Mode.MOVE)


## Called as each queued event starts playing: hide stale overlays while input is locked.
func on_beat(_ev: Dictionary) -> void:
	if not can_act():
		view.board.clear_overlays()
		view.hud.hide_tooltip()
		hover_cell = NO_CELL


func _set_mode(m: Mode) -> void:
	mode = m
	if m != Mode.SHOOT:
		targets.clear()
	if m == Mode.MOVE:
		pending = {}
	if m != Mode.TARGET_UNIT:
		unit_targets = []
	if m != Mode.TARGET_CELL:
		cell_targets = []
	refresh()


# --- overlays ----------------------------------------------------------------

func refresh() -> void:
	if view.board == null:
		return
	view.board.clear_overlays()
	_reach = {}
	var u := selected_unit()
	if u == null:
		selected_id = -1
	for uv in view.unit_views.values():
		uv.set_selected(uv.unit_id == selected_id)
		uv.set_targeted(false)
	if u != null and can_act():
		match mode:
			Mode.MOVE:
				if u.actions_left > 0:
					_reach = Rules.move_range(view.state, u)
					_reach.erase(u.pos)
					view.board.show_range(_reach)
			Mode.SHOOT:
				var t := current_target()
				if t != null:
					view.view_for(t.id).set_targeted(true)
					view.board.mark_cells([t.pos], Color(0.9, 0.3, 0.2, 0.3))
			Mode.TARGET_UNIT:
				# The ability's own target list when it gives one (Combat "targets"), else anyone.
				var cells: Array = []
				for o in view.state.living():
					if o.id != u.id and (unit_targets.is_empty() or unit_targets.has(o.id)):
						cells.append(o.pos)
						if not unit_targets.is_empty():
							view.view_for(o.id).set_targeted(true)
				view.board.mark_cells(cells, Color(0.9, 0.7, 0.3, 0.25))
	_update_hover(true)
	changed.emit()


func _process(_delta: float) -> void:
	_update_hover(false)


func _mouse_cell() -> Vector2i:
	if _forced_cell != NO_CELL:
		# The d-pad parked the pointer on a cell; keep it until the mouse really moves.
		if not is_inside_tree() or DisplayServer.get_name() == "headless" \
				or get_viewport().get_mouse_position().distance_to(_forced_at) < 3.0:
			return _forced_cell
		_forced_cell = NO_CELL
	if not is_inside_tree() or view.camera_rig == null:
		return NO_CELL
	var hit: Variant = view.camera_rig.screen_to_world(get_viewport().get_mouse_position())
	if hit == null:
		return NO_CELL
	var c := Board.world_to_cell(hit)
	return c if view.state.grid.in_bounds(c) else NO_CELL



func _update_hover(force: bool) -> void:
	var c := _mouse_cell()
	if c == hover_cell and not force:
		return
	hover_cell = c
	view.board.set_hover(c, c != NO_CELL and can_act())
	view.board.clear_path()
	var u := selected_unit()
	if u != null and can_act() and c != NO_CELL:
		if mode == Mode.MOVE and _reach.has(c):
			view.board.show_path(view.state.grid.find_path(u.pos, c, view.state.occupied(u.id)))
			view.board.show_cover(c, view.state.grid.cover_sides(c))
		elif mode == Mode.TARGET_CELL:
			view.board.mark_cells([c] + cell_targets, Color(0.18, 0.95, 0.78, 0.35))
			_show_blast(c)
		elif mode == Mode.TARGET_UNIT:
			_show_landing(u, c)
	var other: UnitView = view.unit_view_at(c) if c != NO_CELL else null
	if other != null:
		view.hud.show_tooltip(other)
	else:
		view.hud.hide_tooltip()


## Grenades, demo charges and barrel shots: what the blast would cover and break (Destruction.preview).
func _show_blast(c: Vector2i) -> void:
	var st: GameState = view.state
	var p := {}
	match str(pending.get("ability", "")):
		"item:frag_grenade": p = Destruction.FRAG
		"item:demo_charge": p = Destruction.DEMO
		"shoot_barrel":
			if st.grid.is_volatile(c):
				p = Destruction.BARREL
	if p.is_empty():
		view.board.clear_blast()
		return
	var hits := Destruction.pattern(st.grid, c, p)
	var changes := Destruction.preview(st, {c: 1} if pending.ability == "shoot_barrel" else hits)
	view.board.show_blast(hits.keys(), changes)


## Lunge / Shield Charge: hovering a target shows the path to the cell the soldier will
## strike from (ClassAbilities.lunge_landing, looked up late so the view builds without it).
func _show_landing(u: Unit, c: Vector2i) -> void:
	var id := str(pending.get("ability", ""))
	if not LANDING_REACH.has(id):
		return
	var t := view.state.unit_at(c)
	if t == null or (not unit_targets.is_empty() and not unit_targets.has(t.id)):
		return
	var reach: int = pending_reach if pending_reach > 0 else LANDING_REACH[id]
	var land: Variant = RunHooks.call_static("ClassAbilities", "lunge_landing", [view.state, u, t, reach], Vector2i(-1, -1))
	if not (land is Vector2i) or land.x < 0:
		return
	var path: Array[Vector2i] = [u.pos]
	if land != u.pos:
		path = view.state.grid.find_path(u.pos, land, view.state.occupied(u.id))
	view.board.show_path(path)


# --- actions -----------------------------------------------------------------

## Buttons for the action bar: {key, label, hotkey, enabled, targeting, type, id}.
func actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var u := selected_unit()
	if u == null:
		return out
	var has_ap := u.actions_left > 0
	var gun: Dictionary = Weapons.of(u)
	out.append({"key": "shoot", "label": "Shoot", "targeting": "shoot", "type": Types.SHOOT, "enabled": has_ap,
		"desc": "%s: %s" % [gun.name, gun.desc]})
	out.append({"key": "overwatch", "label": "Overwatch", "targeting": "none", "type": Types.OVERWATCH, "enabled": has_ap})
	out.append({"key": "hunker", "label": "Hunker", "targeting": "none", "type": Types.HUNKER, "enabled": has_ap})
	for a in Combat.available_abilities(view.state, u):
		out.append({"key": "ability:%s" % a.id, "label": str(a.get("name", a.id)), "targeting": str(a.get("targeting", "none")),
			"type": Types.ABILITY, "id": a.id, "enabled": has_ap and a.get("ready", true), "desc": str(a.get("desc", "")),
			"targets": a.get("targets", []), "reach": int(a.get("reach", a.get("range", 0)))})
	for m in Infection.available_mutations(view.state, u):
		var lbl := str(m.get("name", m.id))
		if m.has("cost"):
			lbl += " (%s)" % str(m.cost)
		out.append({"key": "mutation:%s" % m.id, "label": lbl, "targeting": str(m.get("targeting", "none")),
			"type": Types.MUTATION, "id": m.id, "enabled": has_ap and m.get("ready", true), "mutation": true,
			"name": str(m.get("name", m.id)), "cost": int(m.get("cost", 0)), "desc": str(m.get("desc", "")), "reason": str(m.get("reason", ""))})
	for i in out.size():
		out[i].hotkey = str(i + 1) if i < 9 else ""
	return out


func trigger(key: String) -> void:
	if not can_act():
		return
	var u := selected_unit()
	if u == null:
		view.hud.toast("Select a soldier first")
		return
	for a in actions():
		if a.key == key:
			_trigger(u, a)
			return


func _trigger(u: Unit, a: Dictionary) -> void:
	if not a.enabled:
		view.hud.toast("%s is not available" % a.label)
		return
	match a.targeting:
		"shoot":
			if mode == Mode.SHOOT:
				confirm_shot()
				return
			targets.assign(Combat.shot_targets(view.state, u).map(func(t: Unit) -> int: return t.id))
			if targets.is_empty():
				view.hud.toast("No visible targets")
				return
			target_idx = 0
			_ui_sound("ui_click")
			_set_mode(Mode.SHOOT)
		"unit", "cell":
			pending = _template(u, a)
			unit_targets = Array(a.get("targets", []))
			cell_targets = Array(a.get("cells", []))
			pending_reach = int(a.get("reach", 0))
			_set_mode(Mode.TARGET_UNIT if a.targeting == "unit" else Mode.TARGET_CELL)
		_:
			submit(_template(u, a))


func _template(u: Unit, a: Dictionary) -> Dictionary:
	var act := {"type": a.type, "unit": u.id}
	if a.type == Types.ABILITY:
		act.ability = a.id
	elif a.type == Types.MUTATION:
		act.mutation = a.id
	return act


func cycle_target(dir := 1) -> void:
	if targets.is_empty():
		return
	target_idx = posmod(target_idx + dir, targets.size())
	var t := current_target()
	if t != null:
		view.camera_rig.focus(view.view_for(t.id).position)
	refresh()


func confirm_shot() -> void:
	var u := selected_unit()
	var t := current_target()
	if u != null and t != null:
		submit({"type": Types.SHOOT, "unit": u.id, "target": t.id})


func submit(action: Dictionary) -> void:
	if not can_act():
		return
	mode = Mode.MOVE
	pending = {}
	targets.clear()
	view.board.clear_overlays()
	_ui_sound("ui_confirm")
	view.session.submit(action)
	changed.emit()


func _ui_sound(s: String) -> void:
	if view.sfx != null:
		view.sfx.play(s, 0.0, 0.03)


func cancel() -> void:
	_ui_sound("ui_hover")
	if mode != Mode.MOVE:
		_set_mode(Mode.MOVE)
	else:
		deselect()


func click_cell(c: Vector2i) -> void:
	if not can_act() or c == NO_CELL:
		return
	var uv := view.unit_view_at(c)
	var u := selected_unit()
	match mode:
		Mode.MOVE:
			if uv != null and controllable().any(func(x: Unit) -> bool: return x.id == uv.unit_id):
				select(uv.unit_id)
			elif u != null and _reach.has(c):
				submit({"type": Types.MOVE, "unit": u.id, "to": c})
			elif u != null and uv != null:
				var vis := Combat.shot_targets(view.state, u).map(func(t: Unit) -> int: return t.id)
				if vis.has(uv.unit_id):
					targets.assign(vis)
					target_idx = targets.find(uv.unit_id)
					_set_mode(Mode.SHOOT)
		Mode.SHOOT:
			if uv != null and targets.has(uv.unit_id):
				if targets[target_idx] == uv.unit_id:
					confirm_shot()
				else:
					target_idx = targets.find(uv.unit_id)
					refresh()
		Mode.TARGET_UNIT:
			if uv != null:
				var act := pending.duplicate()
				act.target = uv.unit_id
				submit(act)
		Mode.TARGET_CELL:
			var act := pending.duplicate()
			act.cell = c
			submit(act)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: click_cell(_mouse_cell())
			MOUSE_BUTTON_RIGHT: cancel()
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
		GameSettings.ensure_input_map()
		_action_input(event)


## Keys and gamepad buttons go through InputMap actions (rebindable in Settings > Controls).
func _action_input(e: InputEvent) -> void:
	var back := e is InputEventKey and (e as InputEventKey).shift_pressed
	if e.is_action_pressed("next_soldier") or e.is_action_pressed("prev_soldier"):
		var dir := -1 if back or e.is_action_pressed("prev_soldier") else 1
		if mode == Mode.SHOOT:
			cycle_target(dir)
		elif can_act():
			cycle(dir)
	elif e.is_action_pressed("cancel"):
		if mode == Mode.MOVE and selected_id < 0:
			view.toggle_pause()
		else:
			cancel()
	elif e.is_action_pressed("confirm"):
		if mode == Mode.SHOOT:
			confirm_shot()
	elif e.is_action_pressed("ready"):
		# Ready fires while aiming, otherwise it's the READY button's shortcut.
		if mode == Mode.SHOOT:
			confirm_shot()
		elif view.hud != null:
			view.hud.toggle_ready()
	elif e.is_action_pressed("shot_cams"):
		GameSettings.set_value("gameplay", "shot_cams", not EventPlayer.cinematics)
		view.hud.toast("Shot cameras " + ("on" if EventPlayer.cinematics else "off"))
	elif e.is_action_pressed("mute"):
		view.sfx.set_muted(not Sfx.muted)
		view.hud.toast("Sound " + ("off" if Sfx.muted else "on"))
	elif e.is_action_pressed("focus"):
		var uv := view.view_for(selected_id)
		if uv != null:
			view.camera_rig.focus(uv.position)
	elif e.is_action_pressed("quick_menu"):
		open_quick_menu()
	elif e.is_action_pressed("cell_left"): step_cursor(Vector2i(-1, 0))
	elif e.is_action_pressed("cell_right"): step_cursor(Vector2i(1, 0))
	elif e.is_action_pressed("cell_up"): step_cursor(Vector2i(0, -1))
	elif e.is_action_pressed("cell_down"): step_cursor(Vector2i(0, 1))
	else:
		for i in 9:
			if e.is_action_pressed("action_%d" % (i + 1)):
				var list := actions()
				if i < list.size():
					trigger(list[i].key)
				return
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- gamepad -----------------------------------------------------------------

## D-pad: moves the pointer one cell in screen terms (up is away from the camera) and
## parks it on that cell, so a gamepad can pick cells precisely.
func step_cursor(screen_dir: Vector2i) -> void:
	if view.camera_rig == null or view.state == null:
		return
	var from := hover_cell
	if from == NO_CELL:
		var u := selected_unit()
		from = u.pos if u != null else Vector2i(view.state.grid.width / 2, view.state.grid.height / 2)
	# Pick the grid step whose on-screen direction best matches the d-pad direction.
	var basis := (view.camera_rig.transform * view.camera_rig.camera.transform).basis
	var right := Vector2(basis.x.x, basis.x.z).normalized()
	var up := -Vector2(basis.z.x, basis.z.z).normalized()   # away from the camera
	var best := Vector2i.ZERO
	var best_dot := -2.0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var dot := Vector2(d).dot(right * screen_dir.x - up * screen_dir.y)
		if dot > best_dot:
			best_dot = dot
			best = d
	var to: Vector2i = from + best
	if not view.state.grid.in_bounds(to):
		to = from
	var at := Vector2.ZERO
	if is_inside_tree():
		at = view.camera_rig.camera.unproject_position(Board.cell_to_world(to, Board.lift(to)))
	view.camera_rig.focus(Board.cell_to_world(to))
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		get_viewport().warp_mouse(at)
	hover_cell = NO_CELL
	_forced_cell = to
	_forced_at = at
	_update_hover(true)


var _forced_cell := NO_CELL
var _forced_at := Vector2.ZERO


## Quick action menu (Y on a gamepad, R on keys): the selected soldier's actions as a
## focusable list, so a gamepad never has to reach the action bar.
func open_quick_menu() -> void:
	if not can_act():
		return
	var u := selected_unit()
	if u == null:
		cycle(1)
		u = selected_unit()
		if u == null:
			return
	var parent := view.hud.get_parent() if view.hud != null else null
	if parent == null:
		return
	var menu := QuickMenu.new()
	menu.setup(u.display_name if u.display_name != "" else u.kind.capitalize(), actions())
	menu.picked.connect(trigger)
	parent.add_child(menu)
