extends Node
## Mouse/keyboard input for the squad phase: selection, move preview, action
## targeting. Only ever calls Rules.apply / read-only queries; never touches state.
## Hot-seat: whoever is at the keyboard may command any player's soldiers.

signal changed   # selection, mode or target changed; HUD should refresh

enum Mode { MOVE, SHOOT, TARGET_UNIT, TARGET_CELL }

const NO_CELL := Vector2i(-999, -999)
const Board := preload("res://view/board.gd")
const UnitView := preload("res://view/unit_view.gd")
const EventPlayer := preload("res://view/event_player.gd")
const Sfx := preload("res://view/sfx.gd")

var view: MissionView
var selected_id := -1
var mode := Mode.MOVE
var pending: Dictionary = {}       # action template while targeting an ability/mutation
var targets: Array[int] = []       # shoot candidates
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
				var cells: Array = []
				for o in view.state.living():
					if o.id != u.id:
						cells.append(o.pos)
				view.board.mark_cells(cells, Color(0.9, 0.7, 0.3, 0.25))
	_update_hover(true)
	changed.emit()


func _process(_delta: float) -> void:
	_update_hover(false)


func _mouse_cell() -> Vector2i:
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
			view.board.mark_cells([c], Color(0.18, 0.95, 0.78, 0.35))
	var other: UnitView = view.unit_view_at(c) if c != NO_CELL else null
	if other != null:
		view.hud.show_tooltip(other)
	else:
		view.hud.hide_tooltip()


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
			"type": Types.ABILITY, "id": a.id, "enabled": has_ap and a.get("ready", true)})
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
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_TAB:
			if mode == Mode.SHOOT:
				cycle_target(-1 if k.shift_pressed else 1)
			elif can_act():
				cycle(-1 if k.shift_pressed else 1)
		KEY_ESCAPE: cancel()
		KEY_ENTER, KEY_KP_ENTER:
			if mode == Mode.SHOOT:
				confirm_shot()
		KEY_SPACE:
			# Space fires while aiming, otherwise it's the READY button's shortcut.
			if mode == Mode.SHOOT:
				confirm_shot()
			elif view.hud != null:
				view.hud.toggle_ready()
		KEY_C:
			EventPlayer.cinematics = not EventPlayer.cinematics
			view.hud.toast("Shot cameras " + ("on" if EventPlayer.cinematics else "off"))
		KEY_M:
			view.sfx.set_muted(not Sfx.muted)
			view.hud.toast("Sound " + ("off" if Sfx.muted else "on"))
		KEY_F:
			var uv := view.view_for(selected_id)
			if uv != null:
				view.camera_rig.focus(uv.position)
		_:
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				var list := actions()
				var i := int(k.keycode - KEY_1)
				if i < list.size():
					trigger(list[i].key)
