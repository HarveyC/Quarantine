extends Node
## Plays GameState events in order as short animation "beats".
## Rules resolves whole turns synchronously; this queue is what makes them readable.
## Beats animate from event data only (paths, ids, hp in the event), never from the
## final GameState, so positions and numbers are right at every step.
##
## A beat is {dur, pad, update: Callable(t 0..1) or null, finish: Callable or null}.
## `_beat_<type>(ev)` builds one; unknown types fall back to `_beat_unknown`.
##
## Shots and melee play as XCOM-style cinematics: the camera cuts over the shooter's
## shoulder, pushes in, the round flies in slow motion, and the camera holds on the
## target through the damage / death that follow. It is all view-side and driven only
## by event data, so every peer in an online match sees the same cinematic.

signal beat_started(ev: Dictionary)
signal drained

const Board := preload("res://view/board.gd")
const Palette := preload("res://view/palette.gd")
const UnitView := preload("res://view/unit_view.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const EnemyBeats := preload("res://view/enemy_beats.gd")
const ENEMY_PAD := 0.3   # extra hold after each enemy-phase action
## Events that keep an open shot cinematic on screen (the shot's consequences).
const CINE_FOLLOW := ["damage", "died", "infection", "turned", "alerted"]
const STEP_TIME := 0.2   # seconds per tile when walking

## Player setting: false skips shot cameras (shots still get the full effects).
static var cinematics := true

var view: MissionView
var speed := 1.0
var enemy_phase := false   # displayed phase, which lags GameState while the queue plays
var turn := 0
var ended := false
## Slows unit animation and effects (not the beat clock) for slow motion and hit-stop.
var world_scale := 1.0
var in_cinematic := false
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
	view.fx.advance(budget * world_scale)
	for uv in view.unit_views.values():
		uv.tick(budget * world_scale)
	var was_busy := is_busy()
	while true:
		if _cur.is_empty():
			if _queue.is_empty():
				if in_cinematic:
					_end_cinematic()
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
	if in_cinematic and not CINE_FOLLOW.has(str(ev.get("type", ""))):
		_end_cinematic()
	beat_started.emit(ev)
	var squad_move: bool = ev.get("type") == "move" and not ev.has("_seen")
	if not squad_move:
		view.show_vision(ev)
	var method := "_beat_" + str(ev.get("type", ""))
	var beat: Dictionary = {} if ev.get("_hidden", false) else (call(method, ev) if has_method(method) else _beat_unknown(ev))
	if squad_move:   # the fog lifts as the soldier arrives
		var fin: Variant = beat.get("finish")
		beat["finish"] = func() -> void:
			if fin != null:
				(fin as Callable).call()
			view.show_vision(ev)
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
	world_scale = 1.0
	if b.update != null:
		(b.update as Callable).call(1.0)
	if b.finish != null:
		(b.finish as Callable).call()


func _uv(ev: Dictionary, key := "unit") -> UnitView:
	return view.view_for(int(ev.get(key, -1)))


func _head(uv: UnitView) -> Vector3:
	return uv.head_world()


func _focus(uv: UnitView) -> void:
	if enemy_phase and uv != null and uv.visible and not in_cinematic:
		view.camera_rig.focus(uv.position)


func _sfx(sound: String, volume_db := 0.0, delay := 0.0) -> void:
	if view.sfx != null and speed <= 3.0:
		view.sfx.play(sound, volume_db, 0.06, delay)


## Cinematics play at normal speed only (autoplay / skipping runs them as quick beats).
## In co-op the camera only cuts for your own soldiers' shots: a teammate's soldier
## shoots without taking over your camera. Enemies and Turned (AI) soldiers still cut.
func _use_cinematic(shooter: UnitView = null) -> bool:
	if not cinematics or speed > 1.5:
		return false
	return shooter == null or not _teammate_owned(shooter)


func _teammate_owned(uv: UnitView) -> bool:
	if not uv.is_soldier or uv.turned or uv.owner_player < 0:
		return false
	return view.session != null and not view.session.is_local(uv.owner_player)


func _begin_cinematic() -> void:
	if not in_cinematic:
		in_cinematic = true
		for uv in view.unit_views.values():
			uv.set_overlays_visible(false)
		view.hud.set_cinematic(true)
		view.board.clear_overlays()


func _end_cinematic() -> void:
	in_cinematic = false
	world_scale = 1.0
	view.camera_rig.end_cinematic()
	for uv in view.unit_views.values():
		uv.set_overlays_visible(true)
	view.hud.set_cinematic(false)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## Over-the-shoulder camera pose behind `from` looking at `at`, trying the right then
## the left shoulder, then a high angle if walls are in the way.
func _ots_pose(from: Vector3, at: Vector3, back := 2.4, side := 0.85, height := 1.8) -> Transform3D:
	var dir := _flat(at - from).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	var look := at + Vector3(0, 0.9, 0)
	for opt in [[side, back, height], [-side, back, height], [side * 0.6, back * 0.8, 2.9], [0.0, 0.6, 3.6]]:
		var eye: Vector3 = from - dir * opt[1] + right * opt[0] + Vector3(0, opt[2], 0)
		if _clear_view(eye, from + Vector3(0, 1.2, 0)):
			return CameraRig.look_pose(eye, look)
	return CameraRig.look_pose(from - dir * 0.6 + Vector3(0, 3.6, 0), look)


## True if no wall cell sits between the camera and its subject (walls are 2.2 high).
func _clear_view(eye: Vector3, subject: Vector3) -> bool:
	var grid: Grid = view.state.grid if view.state != null else null
	if grid == null:
		return true
	for i in 7:
		var p := eye.lerp(subject, i / 6.0)
		if p.y > 2.35:
			continue
		var c := Board.world_to_cell(p)
		if grid.in_bounds(c) and grid.tile(c) == Types.Tile.WALL:
			return false
	return true


func _blood(uv: UnitView) -> Color:
	return Color("6a1a14") if uv.is_soldier and not uv.turned else Palette.TEAL


func _gun_sound(uv: UnitView) -> String:
	if not uv.is_soldier:
		return "spit"
	match uv.kind:
		"marksman": return "sniper"
		"breacher": return "shotgun"
	return "rifle"


# --- beats -------------------------------------------------------------------

func _beat_team_phase(ev: Dictionary) -> Dictionary:
	enemy_phase = false
	turn = int(ev.get("turn", turn))
	for uv in view.unit_views.values():
		uv.set_statuses(false, false)
	view.hud.banner("TURN %d  -  SQUAD PHASE" % int(ev.get("turn", 0)), Palette.player_ui(0))
	_sfx("sting_squad")
	return {"dur": 0.9}


func _beat_enemy_phase(ev: Dictionary) -> Dictionary:
	enemy_phase = true
	turn = int(ev.get("turn", turn))
	view.hud.banner("ENEMY ACTIVITY", Palette.DANGER)
	_sfx("sting_enemy")
	return {"dur": 0.9}


func _beat_ready(_ev: Dictionary) -> Dictionary:
	return {}


func _beat_rejected(ev: Dictionary) -> Dictionary:
	if not enemy_phase:
		view.hud.toast(str(ev.get("reason", "Not allowed")))
		_sfx("ui_deny")
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
	var last: Vector2i = ev.path[ev.path.size() - 1]
	var steps := pts.size() - 1
	# Fog of war: an enemy is only drawn on the cells of its path the squad can see.
	var seen: Array = ev.get("_seen", [])
	if not seen.is_empty() and not seen.has(true):
		uv.set_cell(last)
		uv.visible = false
		return {}
	var shown := func(i: int) -> bool:
		return seen.is_empty() or bool(seen[mini(i, seen.size() - 1)]) or (i > 0 and bool(seen[i - 1]))
	if shown.call(0):
		_focus(uv)
	uv.set_moving(true)
	uv.set_aim(0.0)
	var update := func(t: float) -> void:
		var f := t * steps
		var i := mini(int(f), steps - 1)
		uv.position = pts[i].lerp(pts[i + 1], f - i)
		uv.face_towards(pts[i + 1])
		if not seen.is_empty():
			uv.visible = shown.call(i)
		if enemy_phase and uv.visible:
			view.camera_rig.focus(uv.position)
	var finish := func() -> void:
		uv.set_cell(last)
		uv.set_moving(false)
		if not seen.is_empty():
			uv.visible = bool(seen[seen.size() - 1])
	return {"dur": STEP_TIME * steps, "update": update, "finish": finish}


## The shot timeline. Quick version (no camera, no slow motion) when cinematics are off.
## Times are in seconds of beat time; slow motion only slows `world_scale` (bodies, FX)
## and the round's flight is spread over a longer window.
func _beat_shot(ev: Dictionary) -> Dictionary:
	var shooter := _uv(ev)
	var target := _uv(ev, "target")
	if shooter == null or target == null:
		return {}
	var hit: bool = ev.get("hit", false)
	var crit: bool = ev.get("crit", false)
	var graze: bool = ev.get("graze", false)
	var reaction: bool = ev.get("reaction", false)
	var cine := _use_cinematic(shooter)
	var hero := shooter.is_soldier and not shooter.turned and not reaction
	var t_fire := (0.55 if hero else 0.4) if cine else 0.12
	var t_hit := t_fire + ((0.55 if hero else 0.4) if cine else 0.12)
	var dur := t_hit + ((0.9 if hero else 0.7) if cine else 0.3)
	shooter.face_towards(target.position)
	shooter.set_aim(1.0)
	_focus(target)
	var dir := _flat(target.position - shooter.position).normalized()
	var right := dir.cross(Vector3.UP)
	var aim := target.chest_world()
	if not hit:
		var side := 1.0 if (int(ev.get("unit", 0)) + int(ev.get("target", 0))) % 2 == 0 else -1.0
		aim += right * side * 0.7 + Vector3(0, 0.25, 0) + dir * 2.5
	elif graze:
		aim += right * 0.22 + Vector3(0, 0.2, 0)
	var col := Color(1.0, 0.78, 0.4) if shooter.is_soldier and not shooter.turned else Palette.TEAL
	var chance := int(ev.get("chance", 0))
	var word := "MISS"
	if hit:
		word = "CRITICAL" if crit else ("GRAZE" if graze else "HIT")
	var word_col := Color(0.8, 0.82, 0.8) if not hit else (Palette.DANGER if crit else Palette.AMBER)
	if reaction:
		view.fx.floating_text(_head(shooter), "REACTION", Palette.AMBER, 40)
	if cine:
		_begin_cinematic()
		var pose_a := _ots_pose(shooter.position, target.position)
		var pose_b := pose_a.translated(dir * 0.5)
		view.camera_rig.cine(pose_a, pose_b, Vector2(46, 40))
		var cap := "%s  >  %s" % [shooter.label(), target.label()]
		view.hud.cine_caption(("REACTION FIRE  -  " if reaction else "") + cap, "%d%% to hit" % chance if chance > 0 else "")
		_sfx("cinematic")
	var st := {"fired": false, "landed": false, "bullet": null, "from": Vector3.ZERO, "pose": Transform3D()}
	var update := func(k: float) -> void:
		var s := k * dur
		if not st.fired:
			if cine:
				view.camera_rig.cine_progress(s / t_fire)
			if s < t_fire:
				return
			st.fired = true
			st.from = shooter.muzzle_world()
			view.fx.muzzle_flash(st.from, col)
			view.fx.puff(st.from + dir * 0.35, Color(0.6, 0.6, 0.55), 0.22, 0.5, 0.2)
			if shooter.is_soldier:
				view.fx.casing(st.from - dir * 0.3, right)
			shooter.recoil(1.4 if shooter.kind in ["marksman", "breacher"] else 1.0)
			st.bullet = view.fx.spawn_bullet(col, shooter.kind == "breacher")
			_sfx(_gun_sound(shooter))
			_sfx("whiz", -4.0, 0.08)
			view.camera_rig.shake(0.35)
			if cine:
				# Push along the line of fire towards the target as the round flies.
				# Stop short of the target so its whole body stays in frame.
				var dist := _flat(target.position - shooter.position).length()
				var stand_off := clampf(dist * 0.55, 3.2, 5.5)
				var eye := target.position - dir * stand_off + right * 1.0 + Vector3(0, 1.5, 0)
				if not _clear_view(eye, target.chest_world()):
					eye = view.camera_rig.transform * view.camera_rig.camera.transform.origin
				var pose_b := view.camera_rig.camera.transform
				pose_b = view.camera_rig.transform * pose_b
				view.camera_rig.cine(pose_b, CameraRig.look_pose(eye, target.chest_world()), Vector2(40, 30))
				world_scale = 0.3
		if not st.landed:
			var f := clampf((s - t_fire) / (t_hit - t_fire), 0.0, 1.0)
			view.fx.place_bullet(st.bullet, st.from, aim, f)
			if cine:
				view.camera_rig.cine_progress(f)
			if s < t_hit:
				return
			st.landed = true
			view.fx.remove(st.bullet)
			st.bullet = null
			_impact(shooter, target, aim, hit, crit, graze, cine)
			if cine:
				view.hud.cine_result(word, word_col)
			elif not hit or crit or graze:
				view.fx.floating_text(_head(target) + Vector3(0, 0.3, 0), word, word_col, 52)
		# Hit-stop right after impact, then ease back to full speed.
		if cine:
			world_scale = lerpf(0.08, 1.0, clampf((s - t_hit - 0.12) / 0.35, 0.0, 1.0))
		if s > dur - 0.3:
			shooter.set_aim(0.0)
	var finish := func() -> void:
		view.fx.remove(st.bullet)
		shooter.set_aim(0.0)
	return {"dur": dur, "update": update, "finish": finish}


func _impact(shooter: UnitView, target: UnitView, at: Vector3, hit: bool, crit: bool, graze: bool, cine: bool) -> void:
	var dir := _flat(target.position - shooter.position).normalized()
	if hit:
		var normal := -dir + Vector3(0, 0.3, 0)
		var blood := _blood(target)
		var glow := blood == Palette.TEAL
		view.fx.burst(at, -normal * 0.3 + dir, blood, 22 if crit else 14, 4.5 if crit else 3.2, glow, 0.05)
		view.fx.burst(at, normal, Color(1.0, 0.75, 0.4), 6, 5.0, true, 0.025)
		view.fx.flash_light(at, blood.lightened(0.3), 2.2 if crit else 1.4, 0.2, 3.0)
		view.fx.decal(target.position + dir * 0.7, blood.darkened(0.3), 0.3 if graze else 0.42, glow)
		target.hit_react(shooter.position, 1.6 if crit else (0.6 if graze else 1.0))
		target.flash(Color(1.0, 0.85, 0.7) if crit else Palette.DANGER)
		_sfx("impact_armor" if target.is_soldier else "impact_flesh", 2.0 if crit else 0.0)
		view.camera_rig.shake(1.0 if crit else (0.4 if graze else 0.7))
	else:
		view.fx.burst(at, -dir + Vector3.UP, Color(0.55, 0.53, 0.48), 10, 3.0, false, 0.04)
		view.fx.puff(at, Color(0.55, 0.52, 0.47), 0.7, 0.9, 0.3)
		view.fx.burst(at, -dir, Color(1.0, 0.8, 0.4), 5, 4.0, true, 0.02)
		target.hit_react(shooter.position + _flat(at - target.position) * 4.0, 0.35)
		_sfx("ricochet" if cine else "concrete")


func _beat_damage(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_hp(int(ev.get("hp", uv.hp)))
	uv.flash(Palette.DANGER)
	view.fx.floating_text(_head(uv), "-%d" % int(ev.get("amount", 0)), Color("ff6b4f"), 72 if in_cinematic else 64)
	return {"dur": 0.6 if in_cinematic else 0.4}


func _beat_died(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_targeted(false)
	uv.set_selected(false)
	var infected := not uv.is_soldier or uv.turned
	_sfx("soldier_death" if not infected else "enemy_death")
	var dur := 1.4 if in_cinematic else 0.8
	var st := {"dissolved": false}
	var update := func(t: float) -> void:
		if in_cinematic:
			world_scale = lerpf(0.35, 1.0, t)
		uv.set_death_progress(t)
		if infected and t > 0.55 and not st.dissolved:
			st.dissolved = true
			view.fx.puff(uv.position + Vector3(0, 0.3, 0), Palette.TEAL_DIM, 1.2, 1.2, 0.6)
			view.fx.burst(uv.position + Vector3(0, 0.3, 0), Vector3.UP, Palette.TEAL, 16, 2.0, true, 0.04)
			view.fx.decal(uv.position, Palette.TEAL_DIM.darkened(0.4), 0.55, true)
	return {"dur": dur, "update": update}


func _status_beat(ev: Dictionary, ow: bool, text: String) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_statuses(ow or uv.overwatch, (not ow) or uv.hunkered)
	view.fx.floating_text(_head(uv), text, Palette.AMBER, 40)
	_sfx("radio")
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
	match str(ev.get("ability", "")):
		"claw", "slam", "pounce", "maul", "spore_drop":
			return _melee_beat(ev)
		"charge":
			if int(ev.get("target", -1)) >= 0:
				return _melee_beat(ev)
		"breach":
			return _breach_beat(ev)
		"spit":
			return _spit_beat(ev)
		"suppress":
			return _suppress_beat(ev)
		"stim":
			_sfx("heal")
			var tv := _uv(ev, "target")
			if tv != null:
				view.fx.puff(tv.position + Vector3(0, 0.8, 0), Color("8fd16a"), 0.9, 0.9, 0.6)
				view.fx.burst(tv.position + Vector3(0, 1.0, 0), Vector3.UP, Color("8fd16a"), 10, 1.5, true, 0.03)
		"tag":
			_sfx("radio")
			_sfx("ui_confirm", -4.0, 0.2)
	return _power_beat(ev, str(ev.get("ability", "ability")), Palette.AMBER)


## Runner claw: side-on camera, wind-up, lunge, slash.
func _melee_beat(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	var tv := _uv(ev, "target")
	if uv == null or tv == null:
		return _power_beat(ev, "claw", Palette.DANGER)
	var hit: bool = ev.get("hit", false)
	var cine := _use_cinematic(uv)
	var t_hit := 0.6 if cine else 0.2
	var dur := t_hit + (0.8 if cine else 0.3)
	uv.face_towards(tv.position)
	_focus(tv)
	if cine:
		_begin_cinematic()
		var mid := (uv.position + tv.position) * 0.5
		var perp := _flat(tv.position - uv.position).normalized().cross(Vector3.UP)
		var eye := mid + perp * 2.6 + Vector3(0, 1.3, 0)
		if not _clear_view(eye, mid + Vector3(0, 1, 0)):
			eye = mid - perp * 2.6 + Vector3(0, 1.3, 0)
			if not _clear_view(eye, mid + Vector3(0, 1, 0)):
				eye = mid + Vector3(0, 3.5, 0) - perp * 1.2
		var look := mid + Vector3(0, 0.8, 0)
		view.camera_rig.cine(CameraRig.look_pose(eye, look), CameraRig.look_pose(eye.lerp(look, 0.25), look), Vector2(48, 40))
		view.hud.cine_caption("%s  >  %s" % [uv.label(), tv.label()], "%d%% to hit" % int(ev.get("chance", 0)) if ev.has("chance") else "")
	_sfx("claw", 0.0, 0.25 if cine else 0.0)
	var st := {"landed": false}
	var update := func(k: float) -> void:
		var s := k * dur
		if cine:
			view.camera_rig.cine_progress(k)
		if s < t_hit:
			var w := s / t_hit
			uv.set_lunge(-0.25 * sin(w * PI) if w < 0.6 else (w - 0.6) / 0.4)
			return
		if not st.landed:
			st.landed = true
			var at := tv.chest_world()
			if hit:
				view.fx.burst(at, _flat(tv.position - uv.position).normalized(), _blood(tv), 16, 3.5, _blood(tv) == Palette.TEAL)
				view.fx.decal(tv.position, _blood(tv).darkened(0.3), 0.35)
				tv.hit_react(uv.position, 1.2)
				tv.flash(Palette.DANGER)
				_sfx("impact_armor" if tv.is_soldier else "impact_flesh")
				view.camera_rig.shake(0.8)
			else:
				tv.hit_react(uv.position, 0.5)
			if cine:
				view.hud.cine_result("HIT" if hit else "MISS", Palette.DANGER if hit else Color(0.8, 0.82, 0.8))
		if cine:
			world_scale = lerpf(0.1, 1.0, clampf((s - t_hit - 0.1) / 0.35, 0.0, 1.0))
		uv.set_lunge(maxf(0.0, 1.0 - (s - t_hit) / 0.4))
	var finish := func() -> void: uv.set_lunge(0.0)
	return {"dur": dur, "update": update, "finish": finish}


## Breacher: point-blank shotgun blast, reusing the shot timeline as a guaranteed hit.
func _breach_beat(ev: Dictionary) -> Dictionary:
	var shot := {"type": "shot", "unit": ev.get("unit"), "target": ev.get("target"), "hit": true,
		"crit": true, "graze": false, "chance": 100}
	var beat := _beat_shot(shot)
	var uv := _uv(ev)
	if uv != null:
		_sfx("breach", -2.0, 0.35 if _use_cinematic(uv) else 0.0)
		view.fx.floating_text(_head(uv), "BREACH", Palette.AMBER, 44)
	return beat


## Spitter: a glowing glob lobbed onto a cell, splashing infection.
func _spit_beat(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null or not (ev.get("cell") is Vector2i):
		return _power_beat(ev, "spit", Palette.TEAL)
	_focus(uv)
	var w := Board.cell_to_world(ev.cell)
	uv.face_towards(w)
	var from := uv.muzzle_world()
	var glob := view.fx.spawn_bullet(Palette.TEAL, true)
	_sfx("spit")
	view.fx.floating_text(_head(uv), "SPIT", Palette.TEAL, 44)
	var st := {"landed": false}
	var update := func(t: float) -> void:
		var f := clampf(t / 0.7, 0.0, 1.0)
		var p := from.lerp(w + Vector3(0, 0.1, 0), f) + Vector3(0, sin(f * PI) * 1.6, 0)
		view.fx.place_bullet(glob, p, p + (w - from).normalized() * 0.1, 0.0)
		if f >= 1.0 and not st.landed:
			st.landed = true
			view.fx.remove(glob)
			view.fx.burst(w + Vector3(0, 0.1, 0), Vector3.UP, Palette.TEAL, 24, 3.0, true, 0.05)
			view.fx.puff(w + Vector3(0, 0.3, 0), Palette.TEAL_DIM, 1.6, 1.4, 0.4)
			view.fx.decal(w, Palette.TEAL_DIM.darkened(0.3), 0.8, true)
			view.fx.pulse(w, Palette.TEAL, 0.9)
			view.fx.flash_light(w + Vector3(0, 0.5, 0), Palette.TEAL, 4.0, 0.5, 5.0)
			_sfx("impact_flesh")
			view.camera_rig.shake(0.4)
	var finish := func() -> void: view.fx.remove(glob)
	return {"dur": 1.0, "update": update, "finish": finish}


## Trooper suppression: a long burst of tracers chewing up the target's cover.
func _suppress_beat(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	var tv := _uv(ev, "target")
	if uv == null or tv == null:
		return _power_beat(ev, "suppress", Palette.AMBER)
	_focus(tv)
	uv.face_towards(tv.position)
	uv.set_aim(1.0)
	view.fx.floating_text(_head(uv), "SUPPRESS", Palette.AMBER, 44)
	var st := {"n": 0}
	var update := func(t: float) -> void:
		var want := int(t * 6.0)
		while st.n < want and st.n < 6:
			st.n += 1
			var from := uv.muzzle_world()
			var jitter := Vector3(sin(st.n * 2.3) * 0.5, absf(cos(st.n * 1.7)) * 0.4, cos(st.n * 3.1) * 0.5)
			var to := tv.chest_world() + jitter
			view.fx.muzzle_flash(from)
			view.fx.tracer(from, to, Color(1.0, 0.8, 0.45), 0.15)
			view.fx.burst(to, (from - to).normalized(), Color(0.55, 0.53, 0.48), 4, 2.5, false, 0.03)
			uv.recoil(0.6)
			_sfx("rifle", -3.0)
	var finish := func() -> void:
		uv.set_aim(0.0)
		view.fx.puff(tv.position + Vector3(0, 0.6, 0), Color(0.5, 0.5, 0.45), 1.2, 1.0, 0.4)
	return {"dur": 1.0, "update": update, "finish": finish}


func _beat_mutation(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv != null:
		view.fx.pulse(uv.position, Palette.TEAL)
		view.fx.puff(uv.position + Vector3(0, 0.9, 0), Palette.TEAL_DIM, 1.0, 1.0, 0.5)
		view.fx.flash_light(uv.position + Vector3(0, 1, 0), Palette.TEAL, 3.0, 0.6)
	_sfx("mutation")
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
	_sfx("infect", 0.0 if t != uv.tier else -4.0)
	view.fx.burst(uv.position + Vector3(0, 1.0, 0), Vector3.UP, Palette.TEAL, 8, 1.2, true, 0.03)
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
	_sfx("lapse")
	view.camera_rig.shake(0.4)
	return {"dur": 1.0}


func _beat_recover(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_lapsed(false)
	view.fx.floating_text(_head(uv), "RECOVERED", Palette.player_ui(0), 44)
	_sfx("ui_confirm")
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
	view.fx.flash_light(uv.position + Vector3(0, 1, 0), Palette.TEAL, 6.0, 1.0, 5.0)
	view.fx.puff(uv.position + Vector3(0, 0.8, 0), Palette.TEAL_DIM, 1.6, 1.4, 0.6)
	_sfx("turned")
	view.camera_rig.shake(0.6)
	return {"dur": 1.2}


func _beat_alerted(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	view.fx.floating_text(_head(uv), "!", Palette.DANGER, 60)
	_sfx("alert", -3.0)
	return {"dur": 0.3}


func _beat_mission_end(ev: Dictionary) -> Dictionary:
	ended = true
	enemy_phase = false
	var result := int(ev.get("result", Types.Result.NONE))
	_sfx("victory" if result == Types.Result.VICTORY else "defeat")
	view.hud.show_end(result)
	return {}


func _beat_hazard(ev: Dictionary) -> Dictionary:
	var cells: Array = ev.get("cells", [])
	if cells.is_empty():
		return {}
	var kind := str(ev.get("kind", ""))
	view.board.set_hazard(cells, kind)
	var mid := Vector3.ZERO
	for c in cells:
		mid += Board.cell_to_world(c)
	mid /= cells.size()
	var color: Color = Board.HAZARD_COLORS.get(kind, Color.WHITE)
	view.fx.floating_text(mid + Vector3(0, 1.2, 0), str(Hazards.KINDS.get(kind, {}).get("name", kind)).to_upper(), color, 40)
	view.fx.flash_light(mid + Vector3(0, 1, 0), color, 2.5, 0.5)
	_sfx("spit" if kind != "fire" else "breach", -4.0)
	return {"dur": 0.4}


func _beat_hazard_tick(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	var kind := str(ev.get("kind", ""))
	var label: String = {"fire": "BURNING", "spore": "SPORES", "acid": "ACID"}.get(kind, kind.to_upper())
	view.fx.floating_text(_head(uv) + Vector3(0, 0.3, 0), label, Board.HAZARD_COLORS.get(kind, Color.WHITE), 36)
	return {"dur": 0.3}


## A tile rose or collapsed (Elevation.set_level): redraw the props and re-seat anyone on it.
func _beat_level_changed(ev: Dictionary) -> Dictionary:
	view.board.rebuild_tiles()
	for id in view.unit_views:
		var uv: UnitView = view.unit_views[id]
		if uv.cell == ev.get("cell"):
			uv.set_cell(uv.cell)
	view.fx.puff(Board.cell_to_world(ev.cell) + Vector3(0, 0.3, 0), Color(0.5, 0.48, 0.42), 0.8, 0.8, 0.5)
	return {"dur": 0.3}


func _beat_hazard_end(ev: Dictionary) -> Dictionary:
	view.board.clear_hazard(ev.get("cells", []))
	return {"dur": 0.0}


func _beat_objective(ev: Dictionary) -> Dictionary:
	if view.hud != null:
		view.hud.refresh()
	return {"dur": 0.0}


func _beat_rescued(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	view.fx.floating_text(_head(uv), "SAFE", Color(0.45, 0.95, 0.55), 44)
	_sfx("radio")
	return {"dur": 0.5}


func _beat_left_behind(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_focus(uv)
	view.fx.floating_text(_head(uv), "LEFT BEHIND", Palette.DANGER, 44)
	return {"dur": 0.7}


func _beat_unknown(ev: Dictionary) -> Dictionary:
	if EnemyBeats.handles(ev):
		return EnemyBeats.beat(self, ev)
	print("[view] unhandled event: ", ev)
	var uv := _uv(ev)
	if uv != null:
		view.fx.floating_text(_head(uv), str(ev.get("type", "?")).to_upper(), Color(0.8, 0.8, 0.8), 32)
		return {"dur": 0.3}
	return {}
