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
const Palette := preload("res://view/palette.gd")
const Tips := preload("res://ui/tips/tips.gd")

var view: MissionView
var selected_id := -1
var mode := Mode.MOVE
var pending: Dictionary = {}       # action template while targeting an ability/mutation
var targets: Array = []            # shoot candidates: unit ids (int), then fuel barrels (Vector2i cells)
var unit_targets: Array = []       # legal targets of the pending unit-targeted ability ([] = not listed)
var pending_reach := 0             # the pending ability's reach, if it states one
var cell_targets: Array = []       # cells the pending cell ability can pick, when it lists them
var target_idx := 0
var hover_cell := NO_CELL
var _reach: Dictionary = {}


func _ready() -> void:
	var h := Tips.host()
	if h != null:
		h.world_tip = tile_tip


func _exit_tree() -> void:
	var h := Tips.host()
	if h != null and h.world_tip == Callable(self, "tile_tip"):
		h.world_tip = Callable()


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
	var t: Variant = _aimed()
	return view.state.get_unit(t) if t is int else null


## The fuel barrel being aimed at, or NO_CELL when the target is a unit (or nothing).
func current_barrel() -> Vector2i:
	var t: Variant = _aimed()
	return t if t is Vector2i else NO_CELL


func _aimed() -> Variant:
	if mode != Mode.SHOOT or targets.is_empty():
		return null
	return targets[target_idx % targets.size()]


## Everything `u` can Shoot, in cycling order: units first, then the fuel barrels in sight.
func shoot_candidates(u: Unit) -> Array:
	var out: Array = Combat.shot_targets(view.state, u).map(func(t: Unit) -> int: return t.id)
	out.append_array(Combat.shot_barrels(view.state, u))
	return out


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
## Actions left, or a pinned soldier who can still Struggle this turn.
func has_something_to_do(u: Unit) -> bool:
	return u.actions_left > 0 or Encounter.validate_struggle(view.state, u) == ""


func cycle(dir := 1) -> void:
	var list := controllable()
	if list.is_empty():
		deselect()
		return
	var with_actions := list.filter(func(u: Unit) -> bool: return has_something_to_do(u))
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
	if u == null or not has_something_to_do(u):
		if controllable().any(func(c: Unit) -> bool: return has_something_to_do(c)):
			cycle(1)
			return
		if u == null:
			selected_id = -1
	_set_mode(Mode.MOVE)


## Called as each queued event starts playing: hide stale overlays while input is locked.
func on_beat(_ev: Dictionary) -> void:
	if not can_act():
		view.board.clear_overlays()
		view.board.clear_sight()
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

## While the squad is shown Concealed: cells where a dormant enemy the squad can see would spot
## a soldier (never enemies under the fog).
func spotted_cells() -> Dictionary:
	var out := {}
	var fields := sight_fields()
	for id in fields:
		out.merge(fields[id].cells)
	return out


## Each visible dormant enemy's detection area (Concealment.sight_fields), while Concealed.
func sight_fields() -> Dictionary:
	if view.player == null or not view.player.concealed or not Concealment.active(view.state):
		return {}
	var watchers: Array = []
	for e in view.state.living(Types.Team.ENEMY):
		var uv = view.view_for(e.id)
		if uv != null and uv.visible and not uv.get_meta("ghost", false):
			watchers.append(e)
	return Concealment.sight_fields(view.state, watchers)


## Draws the enemy sight areas (Board.show_sight), lifting the hovered enemy's own area.
func _show_sight() -> void:
	if not can_act():
		view.board.clear_sight()
		return
	var fields := sight_fields()
	var focus := -1
	var uv: UnitView = view.unit_view_at(hover_cell) if hover_cell != NO_CELL else null
	if uv != null and fields.has(uv.unit_id):
		focus = uv.unit_id
	view.board.show_sight(fields, focus)


## Index of the first step of `path` a dormant enemy would see, or -1.
func spotted_step(path: Array[Vector2i]) -> int:
	var cells := spotted_cells()
	if cells.is_empty():
		return -1
	for i in path.size():
		if cells.has(path[i]):
			return i
	return -1

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
					view.board.show_range(_reach, spotted_cells())
			Mode.SHOOT:
				var t := current_target()
				var b := current_barrel()
				if t != null:
					view.view_for(t.id).set_targeted(true)
					view.board.mark_cells([t.pos], Color(0.9, 0.3, 0.2, 0.3))
				elif b != NO_CELL:
					_show_barrel_blast(b)
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
			var path := view.state.grid.find_path(u.pos, c, view.state.occupied(u.id), false, Grafts.climbs(u))
			view.board.show_path(path, spotted_step(path))
			view.board.show_cover(c, view.state.grid.cover_sides(c))
		elif mode == Mode.TARGET_CELL:
			view.board.mark_cells([c] + cell_targets + _item_area(c), Color(Palette.AMBER, 0.22), "aim")
			_show_blast(c)
		elif mode == Mode.TARGET_UNIT:
			_show_landing(u, c)
	_show_sight()
	if mode == Mode.MOVE and view.board != null:
		# Hovering a fuel barrel the soldier could shoot previews its blast (click to aim).
		if u != null and can_act() and c != NO_CELL and u.actions_left > 0 and Combat.shot_barrels(view.state, u).has(c):
			_show_barrel_blast(c)
		else:
			view.board.clear_blast()
	var other: UnitView = view.unit_view_at(c) if c != NO_CELL else null
	if other != null:
		view.hud.show_tooltip(other)
	else:
		view.hud.hide_tooltip()


## Area items (smoke, flashbang, flare, concussion): the square they cover around the aimed tile.
func _item_area(c: Vector2i) -> Array:
	var r := 0
	match str(pending.get("ability", "")):
		"item:smoke_grenade": r = GearFx.SMOKE_RADIUS
		"item:flashbang", "gear:flare_launcher": r = 1
		"gear:concussion_launcher":
			var u := selected_unit()
			r = 2 if u != null and GearFx.mk(u, "concussion_launcher") >= 2 else 1
	var out: Array = []
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			var cc := Vector2i(x, y)
			if cc != c and view.state.grid.in_bounds(cc) and view.state.grid.is_walkable(cc):
				out.append(cc)
	return out


## The hover card for the map tile under the pointer (TermTips.world_tip): {} over a soldier or
## an enemy (they have their own panel), a tile with nothing on it, or while aiming (the target
## panel has the floor then; the map key still explains the markings).
func tile_tip(_at: Vector2) -> Dictionary:
	if view == null or view.state == null or view.board == null or mode != Mode.MOVE:
		return {}
	var c := _mouse_cell()
	if c == NO_CELL:
		return {}
	var uv: UnitView = view.unit_view_at(c)
	if uv != null and uv.visible:
		return {}
	var terms := tile_terms(c)
	return {"terms": terms, "ctx": {}} if not terms.is_empty() else {}


## Glossary keys for what is on `c`, most pressing first: the blast or aim being previewed, a
## hazard, an objective zone, enemy sight, then the terrain (ways up, scaffolds, barrels, rubble).
func tile_terms(c: Vector2i) -> Array:
	var b: Board = view.board
	var g: Grid = view.state.grid
	var out: Array = []
	if b.in_blast(c):
		out.append("tile_blast")
	var hz := b.hazard_at(c)
	if hz != "":
		out.append(TileOverlays.term(hz))
	var z := b.zone_at(c)
	if z != "":
		out.append(TileOverlays.term(z))
	if b.in_sight(c):
		out.append("tile_sight")
	if g.is_ladder(c):
		out.append("ladder")
	elif g.is_stairs(c):
		out.append("stairs")
	if g.is_fragile(c):
		out.append("scaffold")
	if g.is_volatile(c):
		out.append("fuel_barrel")
	elif g.rubble.has(c) or g.wear.has(c):
		out.append("rubble")
	if g.level(c) > 0 and not g.is_fragile(c):
		out.append("high_ground")
	return out.filter(func(k) -> bool: return Glossary.has(str(k)))


## Grenades and demo charges: what the blast would cover and break (Destruction.preview).
func _show_blast(c: Vector2i) -> void:
	var st: GameState = view.state
	var p := {}
	match str(pending.get("ability", "")):
		"item:frag_grenade": p = Destruction.FRAG
		"item:demo_charge": p = Destruction.DEMO
	if p.is_empty():
		view.board.clear_blast()
		return
	var hits := Destruction.pattern(st.grid, c, p)
	view.board.show_blast(hits.keys(), Destruction.preview(st, hits))


## Aiming at a fuel barrel: every cell its blast (and any barrel it sets off) covers, what breaks.
func _show_barrel_blast(c: Vector2i) -> void:
	var st: GameState = view.state
	var cover := {}
	for b in Destruction.barrel_blasts(st, c):
		cover.merge(Destruction.pattern(st.grid, b, Destruction.BARREL))
	view.board.show_blast(cover.keys(), Destruction.preview(st, {c: 1}))


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
	if u.status.has("pinned_by"):
		# Pinned: the only thing left to do is fight the Lurker off.
		var why := Encounter.validate_struggle(view.state, u)
		out.append({"key": "struggle", "label": "Struggle", "targeting": "none", "type": Types.STRUGGLE,
			"enabled": why == "", "reason": why, "hotkey": "1",
			"desc": "%d%% chance to throw the Lurker off. Costs nothing, once a turn." % Encounter.STRUGGLE_CHANCE})
		return out
	var has_ap := u.actions_left > 0
	var gun: Dictionary = Weapons.of(u)
	out.append({"key": "shoot", "label": "Shoot", "targeting": "shoot", "type": Types.SHOOT, "enabled": has_ap,
		"desc": "%s: %s" % [gun.name, gun.desc]})
	out.append({"key": "overwatch", "label": "Overwatch", "targeting": "none", "type": Types.OVERWATCH, "enabled": has_ap})
	out.append({"key": "hunker", "label": "Hunker", "targeting": "none", "type": Types.HUNKER, "enabled": has_ap})
	if PartingBlow.enabled and PartingBlow.threatened(view.state, u):
		out.append({"key": "disengage", "label": "Disengage", "targeting": "cell", "type": Types.MOVE, "careful": true,
			"enabled": has_ap, "cells": PartingBlow.careful_cells(view.state, u),
			"desc": "Move up to %d tiles without a Parting blow." % PartingBlow.CAREFUL_RANGE})
	if Ammo.tracked(u):
		var dry := Ammo.reload_error(view.state, u)
		out.append({"key": "reload", "label": "Reload", "targeting": "none", "type": Types.RELOAD, "enabled": has_ap and dry == "",
			"reason": dry, "desc": "Refill the magazine (%d of %d rounds). Costs %s." % [Ammo.rounds(u), Ammo.mag_size(u),
			"no action" if Ammo.reload_is_free(view.state, u) else "1 action"]})
	for a in Combat.available_abilities(view.state, u):
		out.append({"key": "ability:%s" % a.id, "label": str(a.get("name", a.id)), "targeting": str(a.get("targeting", "none")),
			"type": Types.ABILITY, "id": a.id, "enabled": has_ap and a.get("ready", true), "desc": str(a.get("desc", "")),
			"targets": a.get("targets", []), "reach": int(a.get("reach", a.get("range", 0))), "new": a.get("new", false)})
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
			if not Ammo.can_fire(u):
				view.hud.toast("Out of ammo: Reload")
				view.sfx.play("dry_fire")
				return
			if mode == Mode.SHOOT:
				confirm_shot()
				return
			targets = shoot_candidates(u)
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
	elif a.type == Types.MOVE:
		act.careful = true
	return act


func cycle_target(dir := 1) -> void:
	if targets.is_empty():
		return
	target_idx = posmod(target_idx + dir, targets.size())
	var t := current_target()
	if t != null:
		view.camera_rig.focus(view.view_for(t.id).position)
	elif current_barrel() != NO_CELL:
		view.camera_rig.focus(Board.cell_to_world(current_barrel()))
	refresh()


func confirm_shot() -> void:
	var u := selected_unit()
	var t := current_target()
	if u != null and t != null:
		submit({"type": Types.SHOOT, "unit": u.id, "target": t.id})
	elif u != null and current_barrel() != NO_CELL:
		submit({"type": Types.SHOOT, "unit": u.id, "cell": current_barrel()})


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
			elif u != null and u.actions_left > 0 and (uv != null or view.state.grid.is_volatile(c)):
				# Clicking an enemy or a fuel barrel in sight aims at it.
				var picked: Variant = uv.unit_id if uv != null else c
				var vis := shoot_candidates(u)
				if vis.has(picked):
					targets = vis
					target_idx = targets.find(picked)
					_ui_sound("ui_click")
					_set_mode(Mode.SHOOT)
		Mode.SHOOT:
			var picked: Variant = uv.unit_id if uv != null else c
			if targets.has(picked):
				if targets[target_idx % targets.size()] == picked:
					confirm_shot()
				else:
					target_idx = targets.find(picked)
					refresh()
		Mode.TARGET_UNIT:
			if uv != null:
				var act := pending.duplicate()
				act.target = uv.unit_id
				submit(act)
		Mode.TARGET_CELL:
			var act := pending.duplicate()
			if act.get("type") == Types.MOVE:
				if not cell_targets.has(c):
					return
				act.to = c
			else:
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
