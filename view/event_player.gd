extends Node
## Plays GameState events in order as short animation "beats".
## Rules resolves whole turns synchronously; this queue is what makes them readable.
## Beats animate from event data only (paths, ids, hp in the event), never from the
## final GameState, so positions and numbers are right at every step.
##
## A beat is {dur, pad, update: Callable(t 0..1) or null, finish: Callable or null}.
## `_beat_<type>(ev)` builds one; unknown types fall back to `_beat_unknown`.

signal beat_started(ev: Dictionary)
signal drained

const Board := preload("res://view/board.gd")
const Palette := preload("res://view/palette.gd")
const UnitView := preload("res://view/unit_view.gd")
const ENEMY_PAD := 0.3   # extra hold after each enemy-phase action

var view: MissionView
var speed := 1.0
var enemy_phase := false   # displayed phase, which lags GameState while the queue plays
var turn := 0
var ended := false
var _queue: Array[Dictionary] = []
var _cur: Dictionary = {}


func enqueue(ev: Dictionary) -> void:
	_queue.append(ev)


func is_busy() -> bool:
	return not _queue.is_empty() or not _cur.is_empty()


func pending() -> int:
	return _queue.size() + (0 if _cur.is_empty() else 1)


func _process(delta: float) -> void:
	advance(delta)


## Plays everything left immediately (tests, skipping).
func flush() -> void:
	var guard := 0
	while is_busy() and guard < 10000:
		guard += 1
		advance(1000.0)


func advance(delta: float) -> void:
	var budget := delta * speed
	view.fx.advance(budget)
	for uv in view.unit_views.values():
		uv.tick(budget)
	var was_busy := is_busy()
	while true:
		if _cur.is_empty():
			if _queue.is_empty():
				if was_busy:
					drained.emit()
				return
			_start(_queue.pop_front())
		var total: float = _cur.dur + _cur.pad
		var need: float = total - _cur.t
		if budget >= need:
			budget -= need
			_cur.t = total
			_end_current()
		else:
			_cur.t += budget
			_update_current()
			return


func _start(ev: Dictionary) -> void:
	beat_started.emit(ev)
	var method := "_beat_" + str(ev.get("type", ""))
	var beat: Dictionary = call(method, ev) if has_method(method) else _beat_unknown(ev)
	beat.merge({"dur": 0.0, "pad": 0.0, "update": null, "finish": null, "t": 0.0})
	if enemy_phase and beat.dur > 0.0 and ev.get("type") in ["move", "shot", "ability", "mutation", "overwatch", "hunker"]:
		beat.pad += ENEMY_PAD
	_cur = beat


func _update_current() -> void:
	if _cur.update != null and _cur.dur > 0.0:
		(_cur.update as Callable).call(minf(_cur.t / _cur.dur, 1.0))


func _end_current() -> void:
	var b := _cur
	_cur = {}
	if b.update != null:
		(b.update as Callable).call(1.0)
	if b.finish != null:
		(b.finish as Callable).call()


func _uv(ev: Dictionary, key := "unit") -> UnitView:
	return view.view_for(int(ev.get(key, -1)))


func _head(uv: UnitView) -> Vector3:
	return uv.position + Vector3(0, 1.5, 0)


func _focus(uv: UnitView) -> void:
	if enemy_phase and uv != null:
		view.camera_rig.focus(uv.position)


# --- beats -------------------------------------------------------------------

func _beat_team_phase(ev: Dictionary) -> Dictionary:
	enemy_phase = false
	turn = int(ev.get("turn", turn))
	for uv in view.unit_views.values():
		uv.set_statuses(false, false)
	view.hud.banner("TURN %d  -  SQUAD PHASE" % int(ev.get("turn", 0)), Palette.player_ui(0))
	return {"dur": 0.9}


func _beat_enemy_phase(ev: Dictionary) -> Dictionary:
	enemy_phase = true
	turn = int(ev.get("turn", turn))
	view.hud.banner("ENEMY ACTIVITY", Palette.DANGER)
	return {"dur": 0.9}


func _beat_ready(_ev: Dictionary) -> Dictionary:
	return {}


func _beat_rejected(ev: Dictionary) -> Dictionary:
	if not enemy_phase:
		view.hud.toast(str(ev.get("reason", "Not allowed")))
	return {}


func _beat_move(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	var pts: Array[Vector3] = [Board.cell_to_world(ev.get("from", uv.cell))]
	for c in ev.get("path", []):
		pts.append(Board.cell_to_world(c))
	if pts.size() < 2:
		return {}
	_focus(uv)
	var last: Vector2i = ev.path[ev.path.size() - 1]
	var steps := pts.size() - 1
	var update := func(t: float) -> void:
		var f := t * steps
		var i := mini(int(f), steps - 1)
		uv.position = pts[i].lerp(pts[i + 1], f - i)
		uv.face_towards(pts[i + 1])
		if enemy_phase:
			view.camera_rig.focus(uv.position)
	var finish := func() -> void: uv.set_cell(last)
	return {"dur": 0.14 * steps, "update": update, "finish": finish}


func _beat_shot(ev: Dictionary) -> Dictionary:
	var shooter := _uv(ev)
	var target := _uv(ev, "target")
	if shooter == null or target == null:
		return {}
	shooter.face_towards(target.position)
	_focus(target)
	var muzzle := shooter.position + Vector3(0, 0.75, 0) + (target.position - shooter.position).normalized() * 0.45
	var aim := target.position + Vector3(0, 0.7, 0)
	if not ev.get("hit", false):
		var side := (target.position - shooter.position).cross(Vector3.UP).normalized()
		aim += side * 0.6 + Vector3(0, 0.3, 0)
	view.fx.muzzle_flash(muzzle)
	view.fx.tracer(muzzle, aim, Color(1.0, 0.85, 0.5) if shooter.is_soldier else Palette.TEAL)
	if ev.get("reaction", false):
		view.fx.floating_text(_head(shooter), "REACTION", Palette.AMBER, 40)
	var word := ""
	if not ev.get("hit", false):
		word = "MISS"
	elif ev.get("crit", false):
		word = "CRIT"
	elif ev.get("graze", false):
		word = "GRAZE"
	if word != "":
		view.fx.floating_text(_head(target) + Vector3(0, 0.3, 0), word, Color(0.85, 0.85, 0.85) if word == "MISS" else Palette.AMBER, 52)
	return {"dur": 0.5}


func _beat_damage(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_hp(int(ev.get("hp", uv.hp)))
	uv.flash(Palette.DANGER)
	view.fx.floating_text(_head(uv), "-%d" % int(ev.get("amount", 0)), Color("ff6b4f"), 64)
	return {"dur": 0.4}


func _beat_died(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_targeted(false)
	uv.set_selected(false)
	return {"dur": 0.8, "update": func(t: float) -> void: uv.set_death_progress(t)}


func _status_beat(ev: Dictionary, ow: bool, text: String) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_statuses(ow or uv.overwatch, (not ow) or uv.hunkered)
	view.fx.floating_text(_head(uv), text, Palette.AMBER, 40)
	return {"dur": 0.5}


func _beat_overwatch(ev: Dictionary) -> Dictionary:
	return _status_beat(ev, true, "OVERWATCH")


func _beat_hunker(ev: Dictionary) -> Dictionary:
	return _status_beat(ev, false, "HUNKER DOWN")


func _power_beat(ev: Dictionary, title: String, color: Color) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_focus(uv)
	view.fx.floating_text(_head(uv), title.capitalize().to_upper(), color, 44)
	var src := uv.position + Vector3(0, 0.9, 0)
	if ev.has("target"):
		var tv := _uv(ev, "target")
		if tv != null:
			uv.face_towards(tv.position)
			view.fx.tracer(src, tv.position + Vector3(0, 0.8, 0), color, 0.5)
			view.fx.pulse(tv.position, color)
	if ev.has("cell") and ev.cell is Vector2i:
		var w := Board.cell_to_world(ev.cell)
		uv.face_towards(w)
		view.fx.tracer(src, w + Vector3(0, 0.1, 0), color, 0.5)
		view.fx.pulse(w, color)
	return {"dur": 0.6}


func _beat_ability(ev: Dictionary) -> Dictionary:
	return _power_beat(ev, str(ev.get("ability", "ability")), Palette.AMBER)


func _beat_mutation(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv != null:
		view.fx.pulse(uv.position, Palette.TEAL)
	return _power_beat(ev, str(ev.get("mutation", "mutation")), Palette.TEAL)


func _beat_infection(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	var value := int(ev.get("value", uv.infection))
	var t := int(ev.get("tier", uv.tier))
	var rising := value > uv.infection
	if t != uv.tier:
		view.fx.floating_text(_head(uv), Infection.tier_name(t).to_upper(), Palette.tier_color(t), 44)
	elif rising:
		view.fx.floating_text(_head(uv), "+%d INF" % (value - uv.infection), Palette.TEAL, 34)
	uv.set_infection(value, t)
	if not rising:
		return {"dur": 0.2}
	return {"dur": 0.5, "update": func(k: float) -> void: uv.pulse_infection(k)}


func _beat_lapse(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_focus(uv)
	uv.set_lapsed(true)
	uv.flash(Palette.DANGER)
	view.fx.pulse(uv.position, Palette.DANGER, 0.9)
	view.fx.floating_text(_head(uv), "LAPSED!", Palette.DANGER, 56)
	return {"dur": 1.0}


func _beat_recover(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_lapsed(false)
	view.fx.floating_text(_head(uv), "RECOVERED", Palette.player_ui(0), 44)
	return {"dur": 0.6}


func _beat_turned(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_focus(uv)
	uv.set_turned()
	uv.flash(Palette.TEAL)
	view.fx.pulse(uv.position, Palette.TEAL, 1.2)
	view.fx.floating_text(_head(uv), "TURNED", Palette.TEAL, 60)
	return {"dur": 1.2}


func _beat_mission_end(ev: Dictionary) -> Dictionary:
	ended = true
	enemy_phase = false
	view.hud.show_end(int(ev.get("result", Types.Result.NONE)))
	return {}


func _beat_unknown(ev: Dictionary) -> Dictionary:
	print("[view] unhandled event: ", ev)
	var uv := _uv(ev)
	if uv != null:
		view.fx.floating_text(_head(uv), str(ev.get("type", "?")).to_upper(), Color(0.8, 0.8, 0.8), 32)
		return {"dur": 0.3}
	return {}
