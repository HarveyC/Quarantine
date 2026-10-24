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
## After an event's beat has played out (the body has fallen, the flash has faded).
signal beat_finished(ev: Dictionary)
signal drained

const Board := preload("res://view/board.gd")
const Palette := preload("res://view/palette.gd")
const UnitView := preload("res://view/unit_view.gd")
const CameraRig := preload("res://view/camera_rig.gd")
const EnemyBeats := preload("res://view/enemy_beats.gd")
const ItemBeats := preload("res://view/item_beats.gd")
const ShotCamera := preload("res://view/shot_camera.gd")
const GunFeel := preload("res://view/gun_feel.gd")
const MeleeFx := preload("res://view/melee_beats.gd")
const ShotMoments := preload("res://view/shot_moments.gd")
const ENEMY_PAD := 0.3   # extra hold after each enemy-phase action
const HEAL_TEXT_LIFT := Vector3(0, 0.35, 0)   # "+N HP" sits above the ability title
## Events that keep an open shot cinematic on screen (the shot's consequences).
## A knockback `move` (Shield Bash, Brute slam) also stays on the cinematic.
const CINE_FOLLOW := ["damage", "died", "infection", "turned", "alerted", "pinned", "stunned", "perk", "bleeding"]
const STEP_TIME := 0.2   # seconds per tile when walking
## Above this game speed (autoplay, skipping) shots never cut to the shot camera.
const CINE_MAX_SPEED := 3.0
## At raised game speeds a shot cinematic plays faster too, but only by this share of the
## extra speed (3x game speed plays it at 1.7x), so the slow motion still reads.
const CINE_SPEEDUP := 0.35

## Player setting: false skips shot cameras (shots still get the full effects). When on,
## only epic moments cut to the shot camera (view/shot_moments.gd).
static var cinematics := true

var view: MissionView
var speed := 1.0
var enemy_phase := false   # displayed phase, which lags GameState while the queue plays
## Displayed squad concealment (Concealment), which also lags GameState: the HUD chip, the red
## detection tiles and the stealth music follow this, so the alarm lands when it plays.
var concealed := false:
	set(on):
		concealed = on
		if view != null:
			for uv in view.unit_views.values():
				uv.set_concealed(on)
var turn := 0
var ended := false
## Slows unit animation and effects (not the beat clock) for slow motion and hit-stop.
var world_scale := 1.0
var in_cinematic := false
var _queue: Array[Dictionary] = []
var _cur: Dictionary = {}
## For tests/test_item_audit.gd: events that fell through to a bare label (the generic power
## beat or an unknown event type), and the sounds asked for (newest last, capped).
var generic_log: Array[String] = []
var sfx_log: Array[String] = []


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


## The beat clock's speed: the game speed, eased off while a shot cinematic plays.
func clock_speed() -> float:
	if in_cinematic and speed > 1.0:
		return 1.0 + (speed - 1.0) * CINE_SPEEDUP
	return speed


func advance(delta: float) -> void:
	var budget := delta * clock_speed()
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
	if in_cinematic and not CINE_FOLLOW.has(str(ev.get("type", ""))) and not ev.get("knockback", false):
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
	beat["ev"] = ev
	if enemy_phase and beat.dur > 0.0 and ev.get("type") in ["move", "shot", "barrel_shot", "ability", "mutation", "overwatch", "hunker"]:
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
	beat_finished.emit(b.ev)


func _uv(ev: Dictionary, key := "unit") -> UnitView:
	return view.view_for(int(ev.get(key, -1)))


func _head(uv: UnitView) -> Vector3:
	return uv.head_world()


func _focus(uv: UnitView) -> void:
	if enemy_phase and uv != null and uv.visible and not in_cinematic:
		view.camera_rig.focus(uv.position)


func _sfx(sound: String, volume_db := 0.0, delay := 0.0) -> void:
	sfx_log.append(sound)
	if sfx_log.size() > 200:
		sfx_log.pop_front()
	if view.sfx != null and speed <= 3.0:
		view.sfx.play(sound, volume_db, 0.06, delay)


## Only epic moments cut to the shot camera (kills, crits, boss hits, long and high-ground
## shots: view/shot_moments.gd), at any game speed up to CINE_MAX_SPEED (autoplay / skipping
## runs them as quick beats). In co-op the camera only cuts for your own soldiers' shots: a
## teammate's soldier shoots without taking over your camera. Enemies and Turned (AI)
## soldiers still cut. `ev` is the shot or strike; empty skips the epic check.
func _use_cinematic(shooter: UnitView = null, ev := {}) -> bool:
	if not cinematics or speed > CINE_MAX_SPEED:
		return false
	if shooter != null and _teammate_owned(shooter):
		return false
	return ev.is_empty() or shot_moment(ev) != ""


## Why the shot or strike `ev` is worth the shot camera, or "" (see view/shot_moments.gd).
## Reads the shooter and target views and the events queued behind it (its damage and
## death), so call it as the event starts.
func shot_moment(ev: Dictionary) -> String:
	var shooter := _uv(ev)
	var target := _uv(ev, "target")
	if shooter == null or target == null:
		return ""
	var kill := _dies_next(target.unit_id)
	var f := {
		"squad": shooter.is_soldier and not shooter.turned,
		"hit": ev.get("hit", false),
		"crit": ev.get("crit", false),
		"kill": kill,
		"last_enemy": kill and _last_enemy(target),
		"boss_target": _is_boss(target),
		"boss_shooter": _is_boss(shooter),
		"soldier_target": target.is_soldier and not target.turned,
		"dist": _flat(target.position - shooter.position).length(),
		"high_ground": shooter.position.y - target.position.y > Board.RAISE * 0.5,
		"chance": int(ev.get("chance", 0)),
	}
	return ShotMoments.moment(f)


## True when a `died` event for `unit_id` follows in the queue before the action ends.
func _dies_next(unit_id: int) -> bool:
	for e in _queue:
		var t := str(e.get("type", ""))
		if t == "died" and int(e.get("unit", -1)) == unit_id:
			return true
		if not CINE_FOLLOW.has(t) and not e.get("knockback", false):
			return false
	return false


## No other hostile (enemy or Turned soldier) is left standing once `target` falls.
func _last_enemy(target: UnitView) -> bool:
	for uv in view.unit_views.values():
		if uv != target and not uv.dead and (not uv.is_soldier or uv.turned):
			return false
	return true


func _is_boss(uv: UnitView) -> bool:
	if EnemyRoster.BOSSES.has(uv.kind):
		return true
	var u: Unit = view.state.get_unit(uv.unit_id) if view.state != null else null
	return u != null and EnemyRoster.is_boss(u)


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


## Over-the-shoulder camera eye behind `from` looking at `at`. Tries the right then the
## left shoulder at a few distances and heights, wanting room for the lens and clear lines
## to the shooter and the target (and to where the camera drifts during the aim). Settles
## for seeing just the shooter, then for a high angle above the scenery.
func _ots_eye(from: Vector3, at: Vector3, drift: Vector3) -> Vector3:
	var dir := _flat(at - from).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	var shoulder := from + Vector3(0, 1.3, 0)
	var target := at + Vector3(0, 1.3, 0)
	var opts: Array[Vector3] = []   # side, back, height
	for h in [1.8, 2.4]:
		for b in [2.4, 1.8, 1.3]:
			for sd in [0.85, -0.85]:
				opts.append(Vector3(sd, b, h))
	for o in [Vector3(0.5, 1.9, 3.0), Vector3(-0.5, 1.9, 3.0), Vector3(0.3, 1.2, 3.8), Vector3(-0.3, 1.2, 3.8)]:
		opts.append(o)
	var eyes: Array[Vector3] = []
	for o in opts:
		eyes.append(from - dir * o.y + right * o.x + Vector3(0, o.z, 0))
	var grid := _grid()
	if grid == null:
		return eyes[0]
	for eye in eyes:
		if ShotCamera.sees(grid, eye, [shoulder, target]) and ShotCamera.sees(grid, eye + drift, [shoulder, target]) \
				and ShotCamera.line_clear(grid, eye, eye + drift):
			return eye
	for eye in eyes:
		if ShotCamera.sees(grid, eye, [shoulder]) and ShotCamera.eye_clear(grid, eye + drift):
			return eye
	var high := from - dir * 0.8
	high.y = maxf(from.y + 3.8, ShotCamera.top_near(grid, high) + 1.6)
	return high


## Where the camera pushes in to watch the round land: off the target's shoulder, at a
## spot it can glide to from `cur` without passing through scenery. Null if none works.
func _push_eye(cur: Vector3, shooter: Vector3, target: Vector3, look: Vector3) -> Variant:
	var dir := _flat(target - shooter).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	var dist := _flat(target - shooter).length()
	var stand_off := clampf(dist * 0.55, 3.2, 5.5)
	var grid := _grid()
	for h in [1.5, 2.2, 3.0]:
		for b in [stand_off, stand_off * 0.75, 2.6]:
			for sd in [1.0, -1.0, 0.4]:
				var eye: Vector3 = target - dir * b + right * sd + Vector3(0, h, 0)
				if grid == null:
					return eye
				if ShotCamera.sees(grid, eye, [look, look + Vector3(0, 0.4, 0)]) and ShotCamera.line_clear(grid, cur, eye):
					return eye
	return null


## A clear line of sight from `eye` to `subject`, with room around the camera.
func _clear_view(eye: Vector3, subject: Vector3) -> bool:
	var grid := _grid()
	return grid == null or ShotCamera.sees(grid, eye, [subject])


func _grid() -> Grid:
	return view.state.grid if view.state != null else null


func _blood(uv: UnitView) -> Color:
	return Color("6a1a14") if uv.is_soldier and not uv.turned else Palette.TEAL


func _feel(uv: UnitView) -> Dictionary:
	return GunFeel.for_weapon(uv.weapon) if uv.weapon != "" else GunFeel.for_kind(uv.kind)


# --- beats -------------------------------------------------------------------

## The displayed phase as Combat.phase_index counts it (timed statuses end on these).
func phase_now() -> int:
	return turn * 2 + (1 if enemy_phase else 0)


func _expire_tags() -> void:
	for uv in view.unit_views.values():
		uv.expire_tags(phase_now())


func _beat_team_phase(ev: Dictionary) -> Dictionary:
	enemy_phase = false
	turn = int(ev.get("turn", turn))
	_expire_tags()
	for uv in view.unit_views.values():
		uv.set_statuses(false, false)
		if uv.guard:
			uv.set_guard(false)
	if turn == 1 and concealed:
		view.hud.banner("SQUAD CONCEALED", Palette.STEALTH)
		view.hud.toast("Unseen. Stay out of the red ground and hold fire to stay hidden")
		_sfx("sting_squad", -4.0)
		return {"dur": 1.4}
	if turn == 1 and not Concealment.used(view.state) and not view.state.encounter.is_empty():
		view.hud.toast("No cover of darkness: they know you're here")
	view.hud.banner("TURN %d  -  SQUAD PHASE" % int(ev.get("turn", 0)), Palette.player_ui(0))
	_sfx("sting_squad")
	return {"dur": 0.9}


func _beat_enemy_phase(ev: Dictionary) -> Dictionary:
	enemy_phase = true
	turn = int(ev.get("turn", turn))
	_expire_tags()
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
	# Knocked back (Brute slam, Shield Bash): shoved along the path facing the blow, not walking.
	var shoved: bool = ev.get("knockback", false)
	if shoved:
		uv.hit_react(pts[0] - (pts[1] - pts[0]), 1.4)
	uv.set_moving(not shoved)
	uv.set_aim(0.0)
	var update := func(t: float) -> void:
		var f := (1.0 - pow(1.0 - t, 2.0) if shoved else t) * steps
		var i := mini(int(f), steps - 1)
		uv.position = pts[i].lerp(pts[i + 1], f - i)
		if not shoved:
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
	return {"dur": STEP_TIME * steps * (0.6 if shoved else 1.0), "update": update, "finish": finish}


## The shot timeline. Quick version (no camera, no slow motion) when cinematics are off.
## Times are in seconds of beat time; slow motion only slows `world_scale` (bodies, FX)
## and the rounds' flight is spread over a longer window. Each weapon fires its own
## pattern (view/gun_feel.gd): bursts, a single heavy round, or a spread of pellets. The
## last round carries the shot's outcome; on a miss every round hits the target's cover
## (or the ground and walls behind it).
func _beat_shot(ev: Dictionary) -> Dictionary:
	var shooter := _uv(ev)
	var target := _uv(ev, "target")
	if shooter == null or target == null:
		return {}
	var hit: bool = ev.get("hit", false)
	var crit: bool = ev.get("crit", false)
	var graze: bool = ev.get("graze", false)
	var reaction: bool = ev.get("reaction", false)
	var feel := _feel(shooter)
	var cine := _use_cinematic(shooter, ev)
	var hero := shooter.is_soldier and not shooter.turned and not reaction
	var n_rounds: int = feel.rounds
	# Bursts play out in the slow motion, so space them out further on the shot camera.
	var gap: float = feel.gap * (2.2 if cine else 1.0)
	var span := GunFeel.round_offset(feel, n_rounds - 1, gap)
	var flight := ((0.55 if hero else 0.4) if cine else 0.12) * float(feel.get("flight", 1.0))
	var t_fire := (0.55 if hero else 0.4) if cine else 0.12
	var t_hit := t_fire + span + flight
	var dur := t_hit + ((0.9 if hero else 0.7) if cine else 0.3)
	shooter.face_towards(target.position)
	shooter.set_aim(1.0)
	_focus(target)
	var dir := _flat(target.position - shooter.position).normalized()
	var right := dir.cross(Vector3.UP)
	var col := GunFeel.color(feel, shooter.is_soldier and not shooter.turned, shooter.turned)
	var seed := int(ev.get("unit", 0)) * 31 + int(ev.get("target", 0)) * 7 + turn
	var rounds: Array[Dictionary] = []
	for i in n_rounds:
		var last := i == n_rounds - 1
		var t0 := t_fire + GunFeel.round_offset(feel, i, gap)
		var r := {"t0": t0, "t1": t0 + flight, "last": last, "proj": GunFeel.proj_of(feel, i, n_rounds),
			"fired": false, "landed": false, "bullets": [], "from": Vector3.ZERO}
		# Earlier rounds of a hit mostly connect; on a miss (or the first rounds of a graze) they chew up cover.
		var connects := hit and (last or (i + seed) % 3 != 0) and not (graze and not last)
		r.hit = connects
		r.impacts = _round_impacts(shooter, target, feel, connects, last and graze, seed + i * 13)
		rounds.append(r)
	var chance := int(ev.get("chance", 0))
	var word := "MISS"
	if hit:
		word = "CRITICAL" if crit else ("GRAZE" if graze else "HIT")
	var word_col := Color(0.8, 0.82, 0.8) if not hit else (Palette.DANGER if crit else Palette.AMBER)
	if reaction:
		view.fx.floating_text(_head(shooter), "REACTION", Palette.AMBER, 40)
	if cine:
		_begin_cinematic()
		var look := target.position + Vector3(0, 0.9, 0)
		var eye_a := _ots_eye(shooter.position, target.position, dir * 0.5)
		view.camera_rig.cine(CameraRig.look_pose(eye_a, look), CameraRig.look_pose(eye_a + dir * 0.5, look), Vector2(46, 40))
		var cap := "%s  >  %s" % [shooter.label(), target.label()]
		view.hud.cine_caption(("REACTION FIRE  -  " if reaction else "") + cap, "%d%% to hit" % chance if chance > 0 else "")
		_sfx("cinematic")
	var casing := GunFeel.casing_of(feel)
	var impact_style := str(feel.get("impact", "spark"))
	var mech_t := -1.0
	if feel.get("eject", "") == "mech" and casing != "":
		mech_t = rounds[n_rounds - 1].t0 + float(feel.get("mech_delay", 0.4)) * (2.0 if cine else 1.0)
	var st := {"pushed": false, "done": false, "ejected": mech_t < 0.0}
	var eject := func(i: int) -> void:
		# Once the shot camera has pushed down the line of fire it passes the shooter's
		# ejection port: a late casing (pump, bolt) would flash across the lens, so only hear it.
		if not (cine and st.pushed):
			view.fx.casing(shooter.muzzle_world() - dir * 0.35, right, casing)
		# The first casings of a burst are heard landing; after that they blur into the gunfire.
		if i < 2:
			_sfx("shell_drop" if casing == "shell" else "brass", 0.0, 0.45 + 0.07 * i)
	var fire_round := func(i: int) -> void:
		var r: Dictionary = rounds[i]
		r.fired = true
		r.from = shooter.muzzle_world()
		var barrel: Vector3 = (target.chest_world() - (r.from as Vector3)).normalized()
		var style := str(feel.get("flash_style", "star"))
		view.fx.muzzle_flash(r.from, col if feel.flash > 0.0 else Palette.TEAL, barrel, feel.flash, style)
		if (feel.get("smoke", false) or i == 0) and style != "gas" and style != "bio":
			view.fx.puff(r.from + dir * 0.35, Color(0.6, 0.6, 0.55), 0.2 + 0.12 * feel.flash, 0.6, 0.2)
		if casing != "" and mech_t < 0.0:
			eject.call(i)
		shooter.recoil(feel.recoil)
		for imp in r.impacts:
			var b := view.fx.spawn_round(r.proj, col, feel.bullet, r.impacts.size() == 1)
			b.set_meta("arc", float(feel.get("arc", 0.0)))
			r.bullets.append(b)
		_sfx(feel.sound, 0.0 if i == 0 else -1.5)
		if i == 0 and feel.has("tail"):
			_sfx(feel.tail, -3.0, 0.03)
		if r.last:
			_sfx(str(feel.get("whiz", "whiz")), -4.0, 0.08)
			if feel.has("mech"):
				_sfx(feel.mech, -2.0, feel.mech_delay * (2.0 if cine else 1.0))
		view.camera_rig.shake(feel.shake)
		view.camera_rig.kick(feel.kick)
	var land_round := func(i: int) -> void:
		var r: Dictionary = rounds[i]
		r.landed = true
		for b in r.bullets:
			view.fx.remove(b)
		r.bullets = []
		for k in r.impacts.size():
			var imp: Dictionary = r.impacts[k]
			if feel.get("smoke", false) and k == 0:
				view.fx.smoke_trail(r.from, imp.pos)
			_impact_at(shooter, target, imp, r.last and k == 0, crit, graze, cine, impact_style, col, k == 0)
		if r.last and r.hit:
			target.hit_react(shooter.position, 1.6 if crit else (0.6 if graze else 1.0))
			target.flash(Color(1.0, 0.85, 0.7) if crit else Palette.DANGER)
			view.camera_rig.shake(1.0 if crit else (0.4 if graze else 0.7))
		elif r.hit:
			target.hit_react(shooter.position, 0.45)
		elif r.last:
			target.hit_react(shooter.position + _flat((r.impacts[0].pos as Vector3) - target.position) * 4.0, 0.35)
	var update := func(k: float) -> void:
		var s := k * dur
		if cine and s < t_fire:
			view.camera_rig.cine_progress(s / t_fire)
		if not st.ejected and s >= mech_t:
			st.ejected = true
			eject.call(0)
		for i in rounds.size():
			var r: Dictionary = rounds[i]
			if not r.fired and s >= r.t0:
				fire_round.call(i)
			if r.fired and not r.landed:
				var f := clampf((s - r.t0) / (r.t1 - r.t0), 0.0, 1.0)
				for j in r.bullets.size():
					view.fx.place_bullet(r.bullets[j], r.from, r.impacts[j].pos, f)
				if s >= r.t1:
					land_round.call(i)
		if cine and rounds[0].fired and not st.pushed:
			# Push along the line of fire towards the target as the rounds fly.
			# Stop short of the target so its whole body stays in frame.
			st.pushed = true
			var pose_b := view.camera_rig.transform * view.camera_rig.camera.transform
			var eye: Variant = _push_eye(pose_b.origin, shooter.position, target.position, target.chest_world())
			if eye == null:
				eye = pose_b.origin
			view.camera_rig.cine(pose_b, CameraRig.look_pose(eye, target.chest_world()), Vector2(40, 30))
			world_scale = 0.3
		if cine and st.pushed and s < t_hit:
			view.camera_rig.cine_progress(clampf((s - t_fire) / (t_hit - t_fire), 0.0, 1.0))
		if s >= t_hit and not st.done:
			st.done = true
			if cine:
				view.hud.cine_result(word, word_col)
			elif not hit or crit or graze:
				view.fx.floating_text(_head(target) + Vector3(0, 0.3, 0), word, word_col, 52)
		# Hit-stop right after impact, then ease back to full speed.
		if cine and s >= t_hit:
			world_scale = lerpf(0.08, 1.0, clampf((s - t_hit - 0.12) / 0.35, 0.0, 1.0))
		if s > dur - 0.3:
			shooter.set_aim(0.0)
	var finish := func() -> void:
		for r in rounds:
			for b in r.bullets:
				view.fx.remove(b)
		if not st.ejected:
			st.ejected = true
			eject.call(0)
		shooter.set_aim(0.0)
	return {"dur": dur, "update": update, "finish": finish}


## Where one round's projectiles end up: [{pos, normal, kind: "body"|"cover"|"ground"}],
## one per pellet. `graze` nicks the edge of the body.
func _round_impacts(shooter: UnitView, target: UnitView, feel: Dictionary, hit: bool, graze: bool, seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dir := _flat(target.position - shooter.position).normalized()
	var right := dir.cross(Vector3.UP)
	var out: Array[Dictionary] = []
	var pellets: int = maxi(1, int(feel.get("pellets", 0)))
	var spread := 0.0 if pellets == 1 else 0.28
	var miss: Dictionary = {} if hit else _miss_point(shooter, target, rng)
	for p in pellets:
		var j := Vector3(rng.randf_range(-1, 1) * right.x, rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1) * right.z) * spread
		if hit:
			var at := target.chest_world() + j
			if graze:
				at += right * 0.22 + Vector3(0, 0.2, 0)
			elif pellets == 1:
				at += Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.08, 0.1), rng.randf_range(-0.06, 0.06))
			out.append({"pos": at, "normal": -dir, "kind": "body"})
		else:
			var m: Dictionary = miss.duplicate()
			var lateral: Vector3 = (miss.normal as Vector3).cross(Vector3.UP).normalized()
			if lateral == Vector3.ZERO:
				lateral = right
			m.pos = (miss.pos as Vector3) + lateral * rng.randf_range(-0.3, 0.3) * (2.0 if pellets > 1 else 1.0)
			if m.kind == "cover":
				m.pos += Vector3(0, rng.randf_range(-0.15, 0.15), 0) * (2.0 if pellets > 1 else 1.0)
			out.append(m)
	return out


## A missed round's landing spot: the face of the target's cover toward the shooter if it
## has any, else the first wall or low cover a few tiles behind it, else the ground there.
func _miss_point(shooter: UnitView, target: UnitView, rng: RandomNumberGenerator) -> Dictionary:
	var grid := _grid()
	var dir := _flat(target.position - shooter.position).normalized()
	var right := dir.cross(Vector3.UP)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	if grid != null:
		var tc := target.cell
		var sc := shooter.cell
		var best := Types.Cover.NONE
		var cover_cell := tc
		for step in [Vector2i(signi(sc.x - tc.x), 0), Vector2i(0, signi(sc.y - tc.y))]:
			if step != Vector2i.ZERO and grid.cover_toward(tc, step) > best:
				best = grid.cover_toward(tc, step)
				cover_cell = tc + step
		if best != Types.Cover.NONE:
			return _cover_face(grid, cover_cell, cover_cell - tc, best, rng)
		# Nothing in front: the round flies past and finds whatever is behind.
		var start := Board.cell_to_world(tc)
		for k in range(1, 6):
			var p := start + dir * k + right * side * 0.4
			var c := Board.world_to_cell(p)
			if not grid.in_bounds(c):
				break
			var cv := grid.cover_value(c)
			if cv != Types.Cover.NONE:
				var back := Board.world_to_cell(p - dir)
				var face := back - c
				if absi(face.x) + absi(face.y) != 1:
					face = Vector2i(-signi(roundi(dir.x)), 0) if absf(dir.x) > absf(dir.z) else Vector2i(0, -signi(roundi(dir.z)))
				return _cover_face(grid, c, -face, cv, rng)
	var ground := target.position + dir * rng.randf_range(1.6, 2.8) + right * side * rng.randf_range(0.4, 0.9)
	ground.y = Board.lift(Board.world_to_cell(ground)) + 0.02
	return {"pos": ground, "normal": Vector3.UP, "kind": "ground"}


## A point on the side of cover cell `c` that faces away from `toward_target`
## (the side the shooter sees).
func _cover_face(grid: Grid, c: Vector2i, toward_target: Vector2i, cover: int, rng: RandomNumberGenerator) -> Dictionary:
	var n := Vector3(-toward_target.x, 0, -toward_target.y).normalized()
	if n == Vector3.ZERO:
		n = Vector3.BACK
	var full := cover == Types.Cover.FULL
	var base := Board.cell_to_world(c)
	var h := rng.randf_range(0.5, 1.5) if full else rng.randf_range(0.25, 0.6)
	var pos := base + n * (0.5 if full else 0.42) + Vector3(0, h, 0)
	return {"pos": pos, "normal": n, "kind": "cover"}


## One projectile landing. `style` is the gun's "impact" (view/gun_feel.gd): it adds its own
## splash, debris and sound on top of the surface's; `col` is the round's colour; `lead` is
## the first projectile of its round (pellet spreads only sound once).
func _impact_at(shooter: UnitView, target: UnitView, imp: Dictionary, main: bool, crit: bool, graze: bool, cine: bool,
		style := "spark", col := Color.WHITE, lead := true) -> void:
	var at: Vector3 = imp.pos
	var dir := _flat(target.position - shooter.position).normalized()
	var big := style in ["heavy", "slug"]
	var small := style in ["pellet", "needle"]
	match imp.kind:
		"body":
			var normal := -dir + Vector3(0, 0.3, 0)
			var blood := _blood(target)
			var glow := blood == Palette.TEAL
			var huge := main and (crit or style == "slug")
			view.fx.burst(at, -normal * 0.3 + dir, blood, (22 if huge else 14) if main else 6, (4.5 if huge else 3.2) if main else 2.4, glow, 0.05 if main else 0.035)
			if style not in ["bio", "dart", "shock"]:
				view.fx.burst(at, normal, Color(1.0, 0.75, 0.4), 6 if main else 3, 5.0, true, 0.025)
			if main:
				view.fx.flash_light(at, blood.lightened(0.3), 2.2 if crit else 1.4, 0.2, 3.0)
				view.fx.decal(target.position + dir * 0.7, blood.darkened(0.3), 0.3 if graze else 0.42, glow)
				_sfx("impact_armor" if target.is_soldier and not target.turned else "impact_flesh", 2.0 if crit else 0.0)
			elif lead:
				_sfx("impact_armor" if target.is_soldier and not target.turned else "impact_flesh", -7.0)
			if big and main:
				view.camera_rig.shake(0.35)
		"cover":
			var n: Vector3 = imp.normal
			var chips := 10 if main else 5
			if big:
				chips = 18 if main else 9
			elif small:
				chips = 4 if main else 2
			view.fx.burst(at, n + Vector3(0, 0.4, 0), Color(0.55, 0.53, 0.48), chips, 4.0 if big else 3.2, false, 0.06 if big else 0.04)
			if style not in ["bio", "dart"]:
				view.fx.burst(at, n, Color(1.0, 0.8, 0.4), (8 if style == "needle" else 5) if main else 3, 4.5, true, 0.02)
			view.fx.puff(at + n * 0.1, Color(0.55, 0.52, 0.47), (1.0 if big else 0.6) if main else 0.35, 0.9, 0.25)
			if style == "dart":
				view.fx.stuck_dart(at, -dir, col)
			else:
				view.fx.bullet_hole(at, n, 0.13 if big else (0.04 if small else 0.07))
			if main:
				view.fx.flash_light(at + n * 0.1, Color(1.0, 0.8, 0.5), 1.2, 0.12, 2.0)
			if lead and style not in ["dart", "pellet", "slug"]:
				_sfx(("ricochet" if cine else "concrete") if main else "concrete", 0.0 if main else -6.0)
		_:
			view.fx.burst(at, Vector3.UP - dir * 0.3, Color(0.42, 0.4, 0.36), (16 if big else 9) if main else 4, 2.6, false, 0.035)
			view.fx.puff(at + Vector3(0, 0.15, 0), Color(0.5, 0.47, 0.42), (0.9 if big else 0.55) if main else 0.3, 0.8, 0.35)
			if style == "dart":
				view.fx.stuck_dart(at, -dir + Vector3(0, 0.4, 0), col)
			else:
				view.fx.decal(at, Color(0.1, 0.09, 0.08), 0.14 if big else 0.08)
			if lead and style not in ["dart", "pellet", "slug"]:
				_sfx("concrete", -3.0 if main else -8.0)
	_impact_style(at, imp, dir, style, col, main, lead)


## The gun's own mark on an impact: bio rounds splash and smoke with culture, slugs knock a
## crater of debris loose, pellets spatter, darts thock in, shock rounds crackle.
func _impact_style(at: Vector3, imp: Dictionary, dir: Vector3, style: String, col: Color, main: bool, lead: bool) -> void:
	var n: Vector3 = imp.get("normal", -dir)
	match style:
		"bio":
			view.fx.burst(at, n + Vector3(0, 0.5, 0), col, 16 if main else 8, 3.0, true, 0.04)
			view.fx.puff(at + n * 0.15, col.darkened(0.45), 0.9 if main else 0.5, 1.4, 0.3)
			view.fx.flash_light(at + n * 0.2, col, 2.2 if main else 1.2, 0.35, 3.0)
			if imp.kind != "body":
				view.fx.decal(at, col.darkened(0.55), 0.22, true)
			if lead:
				_sfx("impact_bio", 0.0 if main else -5.0)
		"slug":
			view.fx.burst(at, n + Vector3(0, 0.6, 0), Color(0.5, 0.48, 0.44), 12, 5.0, false, 0.07)
			view.fx.puff(at + n * 0.2, Color(0.55, 0.52, 0.47), 1.3, 1.2, 0.35)
			if lead:
				_sfx("impact_slug", 0.0 if main else -4.0)
		"pellet":
			if lead:
				_sfx("impact_pellets", 0.0 if main else -4.0)
		"dart":
			view.fx.puff(at + n * 0.1, Color(0.85, 0.92, 0.95), 0.3, 0.6, 0.1)
			if lead:
				_sfx("impact_dart", 0.0 if main else -5.0)
		"shock":
			for k in 3:
				var off := Vector3(sin(k * 2.1), 0.6 + cos(k * 1.3) * 0.4, cos(k * 2.1)) * 0.35
				view.fx.spark_arc(at, at + off, col, 0.25)
			view.fx.flash_light(at, col, 2.5, 0.2, 3.0)
			if lead:
				_sfx("impact_shock", 0.0 if main else -5.0)
		"needle":
			if lead and imp.kind == "body":
				_sfx("ricochet", -9.0)


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


## Warden's Guard stance: shield up until the next squad phase or until it bashes.
func _beat_guard(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_guard(true)
	view.fx.floating_text(_head(uv), "GUARD", Palette.AMBER, 40)
	view.fx.pulse(uv.position, Palette.AMBER, 0.6)
	_sfx("radio")
	_sfx("bash", -14.0, 0.1)
	return {"dur": 0.5}


## A perk that visibly triggered (Bloodlust's refunded action, Last Stand, ...).
func _beat_perk(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	var perk := str(ev.get("perk", ""))
	var col := Palette.TEAL if perk == "bloodlust" else Palette.AMBER
	view.fx.floating_text(_head(uv) + Vector3(0, 0.25, 0), perk.capitalize().to_upper() + ("  +1 ACTION" if perk == "bloodlust" else ""), col, 40)
	uv.flash(col)
	if perk == "bloodlust":
		view.fx.flash_light(uv.chest_world(), Palette.TEAL, 2.5, 0.35, 3.0)
		view.fx.burst(uv.chest_world(), Vector3.UP, Palette.TEAL, 10, 1.6, true, 0.025)
	_sfx("mutation" if perk == "bloodlust" else "ui_confirm", -8.0)
	return {"dur": 0.45}


## Bleed Out: the target starts bleeding.
func _beat_bleeding(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	view.fx.floating_text(_head(uv), "BLEEDING", MeleeFx.BLEED.lightened(0.35), 36)
	MeleeFx.drip(view.fx, uv.chest_world(), uv.position, true)
	return {"dur": 0.35}


## Bleed tick at the start of a phase (its damage event follows).
func _beat_bleed(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_focus(uv)
	view.fx.floating_text(_head(uv) + Vector3(0, 0.3, 0), "BLEED", MeleeFx.BLEED.lightened(0.35), 34)
	MeleeFx.drip(view.fx, uv.chest_world(), uv.position)
	return {"dur": 0.3}


## Shield Bash stun: the target loses its next turn.
func _beat_stunned(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	uv.set_tag("stunned", phase_now() + (1 if enemy_phase else 2))
	view.fx.floating_text(_head(uv) + Vector3(0, 0.3, 0), "STUNNED", MeleeFx.SHOCK, 44)
	MeleeFx.stun(view.fx, uv.chest_world())
	uv.flash(MeleeFx.SHOCK)
	return {"dur": 0.5 if in_cinematic else 0.35}


## A heal lands on `uv`: its HP pips refill to `hp` (the HUD and nameplates read them), a
## green "+N HP" rises over its head, a soft green glow, and the heal chime unless `chime` is off.
func _show_heal(uv: UnitView, amount: int, hp: int, chime := true) -> void:
	if uv == null:
		return
	uv.set_hp(hp)
	if amount <= 0:
		return
	view.fx.floating_text(_head(uv) + HEAL_TEXT_LIFT, "+%d HP" % amount, Palette.HEAL, 72 if in_cinematic else 64, 1.4)
	view.fx.puff(uv.position + Vector3(0, 0.8, 0), Palette.HEAL, 0.9, 0.9, 0.6)
	view.fx.burst(uv.position + Vector3(0, 1.0, 0), Vector3.UP, Palette.HEAL, 12, 1.5, true, 0.03)
	view.fx.flash_light(uv.position + Vector3(0, 1.0, 0), Palette.HEAL, 2.5, 0.4)
	view.fx.pulse(uv.position, Palette.HEAL)
	uv.flash(Palette.HEAL)
	if chime:
		_sfx("heal")


## Perk and passive heals (Transfusion, Field surgeon, ...: Kit._heal).
func _beat_heal(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_show_heal(uv, int(ev.get("amount", 0)), int(ev.get("hp", uv.hp)))
	return {"dur": 0.5}


## Gear procs that aren't item names: what to call them, and whether the label sits on the
## target (the unit acted on) rather than the soldier whose gear fired.
const GEAR_PROCS := {
	"close_set": {"text": "MOVE REFUNDED", "color": Color("e0a050")},
	"mark_set": {"text": "MARK JUMPS", "color": Color("ff5c86"), "on_target": true},
	"suppress_set": {"text": "PINNED SHOT", "color": Color("b9a7ff")},
	"guard_set": {"text": "TAKES THE HIT", "color": Color("a9c46c")},
	"purge_set": {"text": "PURGE SET", "color": Color("e9e4d4")},
	"restrained": {"text": "RESTRAINED", "color": Color("e4ece9")},
	"bloodletting": {"text": "BLOODLETTING  +1 ACTION", "color": Palette.TEAL},
	"crossfire": {"text": "CROSSFIRE", "color": Color("6fc3ff")},
	"scorched_earth": {"text": "SCORCHED EARTH", "color": Color("ff8a3d")},
	"symbiotic": {"text": "SYMBIOTIC SUIT", "color": Palette.TEAL},
}


## Gear procs (Leech rounds, Feral grip, Choke, set bonuses...). Heals refill HP, an HP cost
## (Symbiotic suit) drains it, mark and suppress tag the enemy hit, anything else names the
## item or proc over whoever it hit.
func _beat_gear(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	if ev.has("heal"):
		_show_heal(uv, int(ev.heal), int(ev.get("hp", uv.hp)))
		return {"dur": 0.4}
	var item := str(ev.get("item", "gear"))
	if item in ["mark", "suppress"]:
		# Flare, tracer, concussion and the like: the tag goes on the enemy it landed on.
		var tv := _uv(ev, "target")
		if tv == null:
			return {}
		var marked := item == "mark"
		tv.set_tag("marked" if marked else "suppressed", phase_now() + (3 if marked else 2))
		if tv.visible:
			view.fx.floating_text(_head(tv) + Vector3(0, 0.3, 0), "MARKED" if marked else "SUPPRESSED", Palette.DANGER if marked else Palette.AMBER, 36)
		return {"dur": 0.15}
	var proc: Dictionary = GEAR_PROCS.get(item, {})
	var text: String = proc.get("text", GearData.item_name(item).to_upper())
	var col: Color = proc.get("color", Palette.AMBER)
	var tv := _uv(ev, "target") if ev.has("target") else null
	var on := tv if tv != null and proc.get("on_target", false) else uv
	if ev.has("hp") and ev.has("damage"):
		uv.set_hp(int(ev.hp))
		text = "%s  -%d HP" % [text, int(ev.damage)]
		col = Palette.DANGER
		uv.flash(Palette.TEAL)
	if tv != null and tv != uv:
		view.fx.tracer(uv.chest_world(), tv.chest_world(), col, 0.35)
	view.fx.floating_text(_head(on) + Vector3(0, 0.2, 0), text, col, 34, 1.3)
	view.fx.pulse(on.position, col, 0.5)
	if not GEAR_PROCS.has(item) or item in ["restrained", "bloodletting", "guard_set"]:
		_sfx("ui_confirm", -6.0)
	return {"dur": 0.4}


## Set Burning (Incendiary rounds, Ember plating, Firestarter, Phosphor rounds...).
func _beat_burning(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	var col: Color = Board.HAZARD_COLORS.fire
	view.fx.floating_text(_head(uv) + Vector3(0, 0.3, 0), "BURNING", col, 36)
	view.fx.burst(uv.chest_world(), Vector3.UP, col, 12, 2.0, true, 0.04)
	view.fx.flash_light(uv.position + Vector3(0, 1.0, 0), col, 2.5, 0.4)
	_sfx("breach", -10.0)
	return {"dur": 0.35}


## A Burning tick at the start of a team phase (the damage event follows).
func _beat_burn(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	var col: Color = Board.HAZARD_COLORS.fire
	view.fx.burst(uv.chest_world(), Vector3.UP, col, 16, 2.5, true, 0.05)
	view.fx.puff(uv.position + Vector3(0, 1.0, 0), Color(0.3, 0.27, 0.24), 1.0, 0.9, 0.7)
	view.fx.flash_light(uv.position + Vector3(0, 1.0, 0), col, 3.0, 0.4)
	_sfx("breach", -8.0)
	return {"dur": 0.35}


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


## Ability ids with a beat of their own below; the rest go to ItemBeats (gadgets, pocket items,
## class abilities) or, failing that, a bare label that tests/test_item_audit.gd catches.
const OWN_ABILITY_BEATS := ["claw", "slam", "pounce", "maul", "spore_drop", "lunge", "riposte", "bash", "charge",
	"breach", "item:frag_grenade", "item:demo_charge", "spit", "suppress", "stim", "item:medkit"]


func _beat_ability(ev: Dictionary) -> Dictionary:
	match str(ev.get("ability", "")):
		"claw", "slam", "pounce", "maul", "spore_drop":
			return _melee_beat(ev)
		"lunge", "riposte":
			var title := "RIPOSTE" if ev.ability == "riposte" else ("CLEAVE" if ev.get("cleave", false) else "LUNGE")
			return _melee_beat(ev, {"sound": "blade", "title": title, "fx": "blade"})
		"bash":
			var tag := "SHIELD CHARGE" if ev.get("charge", false) else ("GUARD" if ev.get("reaction", false) else "SHIELD BASH")
			var wv := _uv(ev)
			if wv != null and ev.get("reaction", false):
				wv.set_guard(false)   # the Guard stance is spent
			return _melee_beat(ev, {"sound": "bash", "title": tag, "fx": "shock"})
		"charge":
			if int(ev.get("target", -1)) >= 0:
				return _melee_beat(ev)
		"breach":
			return _breach_beat(ev)
		"item:frag_grenade", "item:demo_charge":
			return _throw_beat(ev)
		"spit":
			return _spit_beat(ev)
		"suppress":
			return _suppress_beat(ev)
		"stim", "item:medkit":
			_sfx("heal")
			var beat := _power_beat(ev, "stim" if ev.ability == "stim" else "medkit", Palette.HEAL)
			var tv := _uv(ev, "target")
			if tv == null:
				tv = _uv(ev)
			_show_heal(tv, int(ev.get("heal", 0)), int(ev.get("hp", tv.hp if tv else 0)), false)
			if tv != null and int(ev.get("heal", 0)) <= 0 and tv.hp >= tv.max_hp:
				view.fx.floating_text(_head(tv) + HEAL_TEXT_LIFT, "FULL HP", Color(0.78, 0.8, 0.76), 40)
			beat.dur = maxf(float(beat.get("dur", 0.0)), 0.9)
			return beat
		"siphon":
			_show_heal(_uv(ev), int(ev.get("heal", 0)), int(ev.get("hp", 0)), false)
	if ItemBeats.handles(ev):
		return ItemBeats.beat(self, ev)
	generic_log.append("ability:" + str(ev.get("ability", "")))
	return _power_beat(ev, str(ev.get("name", str(ev.get("ability", "ability")).replace("_", " "))), Palette.AMBER)


## Melee strike: wind-up, lunge, impact. Runner claws and the like get a side-on camera;
## a soldier's strike (Reaper lunge, Warden bash) cuts over the striker's shoulder like
## a shot does, and in co-op only for your own soldiers. `style`: "sound" (default
## "claw"), "title" (a floating label: LUNGE, SHIELD BASH, ...), "fx" ("claw", "blade":
## a teal-edged cut, "shock": a stun-maul discharge).
func _melee_beat(ev: Dictionary, style := {}) -> Dictionary:
	var uv := _uv(ev)
	var tv := _uv(ev, "target")
	var title: String = style.get("title", "")
	if uv == null or tv == null:
		return _power_beat(ev, title if title != "" else "claw", Palette.DANGER)
	var hit: bool = ev.get("hit", false)
	var graze: bool = hit and ev.get("graze", false)
	var fx: String = style.get("fx", "claw")
	var cine := _use_cinematic(uv, ev)
	var hero := uv.is_soldier and not uv.turned
	var t_hit := 0.6 if cine else 0.2
	var dur := t_hit + (0.8 if cine else 0.3)
	uv.set_aim(0.0)
	uv.face_towards(tv.position)
	_focus(tv)
	if title != "":
		view.fx.floating_text(_head(uv), title, Palette.TEAL if fx == "blade" else Palette.AMBER, 44)
	if cine:
		_begin_cinematic()
		var mid := (uv.position + tv.position) * 0.5
		var look := mid + Vector3(0, 0.8, 0)
		var eye: Vector3
		if hero:
			# Over the striker's shoulder, pulled back and out to the side so both bodies fit
			# at arm's length; the shot camera's search if none of these is clear.
			var dir := _flat(tv.position - uv.position).normalized()
			var right := dir.cross(Vector3.UP)
			look = mid + Vector3(0, 0.95, 0)
			eye = Vector3.INF
			var opts: Array[Vector3] = []   # side, back, height: backing off less as room runs out
			for b in [3.2, 2.4, 1.6, 0.8]:
				for h in [2.3, 3.0]:
					for sd in [2.0, -2.0, 2.6, -2.6]:
						opts.append(Vector3(sd, b, h))
			for o in opts:
				var e: Vector3 = uv.position - dir * o.y + right * o.x + Vector3(0, o.z, 0)
				if _clear_view(e, uv.position + Vector3(0, 1.1, 0)) and _clear_view(e, tv.position + Vector3(0, 1.0, 0)) \
						and (_grid() == null or ShotCamera.eye_clear(_grid(), e)):
					eye = e
					break
			if eye == Vector3.INF:
				eye = _ots_eye(uv.position, tv.position, dir * 0.4)
		else:
			var perp := _flat(tv.position - uv.position).normalized().cross(Vector3.UP)
			eye = mid + Vector3(0, 3.5, 0) - perp * 1.2
			for o in [Vector2(2.6, 1.3), Vector2(-2.6, 1.3), Vector2(1.9, 2.0), Vector2(-1.9, 2.0), Vector2(1.4, 3.0), Vector2(-1.4, 3.0)]:
				var e: Vector3 = mid + perp * o.x + Vector3(0, o.y, 0)
				if _clear_view(e, mid + Vector3(0, 1, 0)) and _clear_view(e.lerp(look, 0.25), mid + Vector3(0, 1, 0)):
					eye = e
					break
			if _grid() != null and not ShotCamera.eye_clear(_grid(), eye):
				eye.y = maxf(eye.y, ShotCamera.top_near(_grid(), eye) + 1.6)
		var push := 0.12 if hero else 0.25
		view.camera_rig.cine(CameraRig.look_pose(eye, look), CameraRig.look_pose(eye.lerp(look, push), look), Vector2(50, 44) if hero else Vector2(48, 40))
		var pre := (title + "  -  ") if title != "" else ""
		view.hud.cine_caption(pre + "%s  >  %s" % [uv.label(), tv.label()], "%d%% to hit" % int(ev.get("chance", 0)) if ev.has("chance") else "")
	# Time the sound so its impact (`lead` seconds into the file) lands with the strike.
	var lead: float = {"blade": 0.2, "bash": 0.0}.get(style.get("sound", "claw"), 0.35)
	_sfx(str(style.get("sound", "claw")), 0.0, maxf(0.0, t_hit - lead))
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
			var dir := _flat(tv.position - uv.position).normalized()
			if hit:
				view.fx.burst(at, dir, _blood(tv), 10 if graze else 16, 3.5, _blood(tv) == Palette.TEAL)
				view.fx.decal(tv.position, _blood(tv).darkened(0.3), 0.25 if graze else 0.35)
				tv.hit_react(uv.position, (0.6 if graze else 1.2) * (1.4 if fx == "shock" else 1.0))
				tv.flash(MeleeFx.SHOCK if fx == "shock" else Palette.DANGER)
				if fx == "claw":
					_sfx("impact_armor" if tv.is_soldier else "impact_flesh")
				view.camera_rig.shake((0.5 if graze else 0.8) * (1.4 if fx == "shock" else 1.0))
			else:
				tv.hit_react(uv.position, 0.5)
			MeleeFx.strike(view.fx, fx, at, dir, hit)
			if cine:
				var word := ("GRAZE" if graze else "HIT") if hit else "MISS"
				view.hud.cine_result(word, (Palette.AMBER if graze else Palette.DANGER) if hit else Color(0.8, 0.82, 0.8))
			elif not hit or graze:
				view.fx.floating_text(_head(tv) + Vector3(0, 0.3, 0), "GRAZE" if hit else "MISS", Palette.AMBER if hit else Color(0.8, 0.82, 0.8), 48)
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
		_sfx("breach", -2.0, 0.35 if _use_cinematic(uv, shot) else 0.0)
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
	var glob := view.fx.spawn_round("spore", Palette.TEAL, 1.6)
	glob.set_meta("arc", 1.6 / maxf(0.1, from.distance_to(w)))
	_sfx("spit")
	view.fx.floating_text(_head(uv), "SPIT", Palette.TEAL, 44)
	var st := {"landed": false}
	var update := func(t: float) -> void:
		var f := clampf(t / 0.7, 0.0, 1.0)
		view.fx.place_bullet(glob, from, w + Vector3(0, 0.1, 0), f)
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


## Frag grenade (lobbed in an arc) or demo charge (set down against the wall, its light blinking
## twice). The blast itself is the "explosion" event that follows.
func _throw_beat(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null or not (ev.get("cell") is Vector2i):
		return _power_beat(ev, str(ev.get("name", "grenade")), Palette.AMBER)
	_focus(uv)
	var w := Board.cell_to_world(ev.cell)
	uv.face_towards(w)
	var demo: bool = ev.ability == "item:demo_charge"
	view.fx.floating_text(_head(uv), "DEMO CHARGE" if demo else "FRAG OUT", Palette.AMBER, 44)
	_sfx("ui_click", -2.0)
	var from := uv.position + Vector3(0, 1.3, 0)
	var to := w + Vector3(0, 0.6 if demo and _grid().tile(ev.cell) == Types.Tile.WALL else 0.12, 0)
	if demo:
		from = uv.position + Vector3(0, 0.6, 0)
	var nade := view.fx.spawn_round("slug", Color("3a4031"), 2.4, false)
	nade.set_meta("arc", 0.0 if demo else 2.2 / maxf(0.1, from.distance_to(to)))
	var flight := 0.35 if demo else 0.6
	var dur := flight + (0.55 if demo else 0.12)
	var st := {"blink": 0}
	var update := func(k: float) -> void:
		var t := k * dur
		view.fx.place_bullet(nade, from, to, clampf(t / flight, 0.0, 1.0))
		if demo and t > flight and st.blink < 2 and t > flight + 0.22 * st.blink:
			st.blink += 1
			view.fx.flash_light(to + Vector3(0, 0.2, 0), Palette.DANGER, 3.0, 0.15, 2.0)
			_sfx("ui_hover", 4.0)
	var finish := func() -> void: view.fx.remove(nade)
	return {"dur": dur, "update": update, "finish": finish}


## A Shoot at a fuel barrel: one aimed shot at the drum. On a hit the explosion event follows
## straight after; a miss sails past it and kicks up dirt behind.
func _beat_barrel_shot(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null or not (ev.get("cell") is Vector2i):
		return {}
	_focus(uv)
	var w := Board.cell_to_world(ev.cell) + Vector3(0, 0.45, 0)
	uv.face_towards(w)
	var feel := _feel(uv)
	var from := uv.muzzle_world()
	var hit: bool = ev.get("hit", false)
	if ev.get("reaction", false):
		view.fx.floating_text(_head(uv), "REACTION", Palette.AMBER, 40)
	var end := w if hit else w + (w - from).normalized() * 1.6 + Vector3(0.35, -0.4, 0.0)
	view.fx.muzzle_flash(from, Color(1.0, 0.8, 0.45), (w - from).normalized(), float(feel.get("flash", 1.0)), str(feel.get("flash_style", "star")))
	view.fx.tracer(from, end, Palette.AMBER, 0.25)
	uv.recoil(float(feel.get("recoil", 1.0)))
	_sfx(str(feel.get("sound", "rifle")))
	if hit:
		view.fx.burst(w, (from - w).normalized(), Color(1.0, 0.7, 0.3), 10, 3.0, true, 0.03)
		return {"dur": 0.3}
	view.fx.burst(end, Vector3.UP, Color(0.55, 0.5, 0.42), 8, 2.0, false, 0.03)
	view.fx.floating_text(w + Vector3(0, 0.9, 0), "MISS", Color(0.78, 0.8, 0.76), 34)
	return {"dur": 0.5}


## Destruction: a blast at a cell. Debris, fire and smoke from Fx.explosion, camera shake by size.
func _beat_explosion(ev: Dictionary) -> Dictionary:
	if not (ev.get("cell") is Vector2i):
		return {}
	var w := Board.cell_to_world(ev.cell)
	var kind := str(ev.get("kind", "frag"))
	view.camera_rig.focus(w)
	view.fx.explosion(w + Vector3(0, 0.2, 0), int(ev.get("radius", 1)), kind)
	view.camera_rig.shake(1.6 if kind == "barrel" else 1.3)
	_sfx("explosion", 0.0 if kind != "frag" else -2.0)
	for id in ev.get("units", []):
		var tv: UnitView = view.view_for(int(id))
		if tv != null:
			tv.hit_react(w, 1.2)
	return {"dur": 0.75 if kind == "barrel" else 0.6}


## Trooper suppression: a long burst of tracers chewing up the target's cover.
func _suppress_beat(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	var tv := _uv(ev, "target")
	if uv == null or tv == null:
		return _power_beat(ev, "suppress", Palette.AMBER)
	_focus(tv)
	uv.face_towards(tv.position)
	uv.set_aim(1.0)
	tv.set_tag("suppressed", phase_now() + 2)
	view.fx.floating_text(_head(uv), "SUPPRESS", Palette.AMBER, 44)
	var st := {"n": 0}
	var update := func(t: float) -> void:
		var want := int(t * 6.0)
		while st.n < want and st.n < 6:
			st.n += 1
			var from := uv.muzzle_world()
			var jitter := Vector3(sin(st.n * 2.3) * 0.5, absf(cos(st.n * 1.7)) * 0.4, cos(st.n * 3.1) * 0.5)
			var to := tv.chest_world() + jitter
			var feel := _feel(uv)
			var col := GunFeel.color(feel, uv.is_soldier and not uv.turned, uv.turned)
			view.fx.muzzle_flash(from, col, to - from, feel.flash, str(feel.get("flash_style", "star")))
			var proj := GunFeel.proj_of(feel, st.n - 1, 6)
			view.fx.tracer(from, to, col if proj != "ball" else col.darkened(0.4), 0.15)
			view.fx.burst(to, (from - to).normalized(), Color(0.55, 0.53, 0.48), 4, 2.5, false, 0.03)
			var casing := GunFeel.casing_of(feel)
			if casing != "":
				view.fx.casing(from, (to - from).cross(Vector3.UP).normalized(), casing)
			uv.recoil(0.6)
			view.camera_rig.kick(feel.kick * 0.5)
			_sfx(feel.sound, -3.0)
			if st.n == 1 and feel.has("tail"):
				_sfx(feel.tail, -4.0)
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
	if value < uv.infection:   # a cure (Stim, Purge, Suppressant shot): show what it took off
		view.fx.floating_text(_head(uv) + Vector3(0, -0.3, 0), "-%d INF" % (uv.infection - value), Palette.TEAL_DIM, 34)
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


## The squad has been seen: the alarm, a look at who saw them, and the music breaks (Soundscape).
func _beat_concealment_lost(ev: Dictionary) -> Dictionary:
	concealed = false
	var uv := _uv(ev)
	var who := ""
	if uv != null and uv.visible:
		who = UnitData.ENEMIES.get(uv.kind, {}).get("name", uv.display_name)
		who = ("an " if who.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + who
		view.fx.floating_text(_head(uv), "!", Palette.DANGER, 84, 1.6)
		if not in_cinematic:
			view.camera_rig.focus(uv.position)
	view.hud.banner("SQUAD DETECTED", Palette.DANGER)
	view.hud.alarm()
	view.hud.toast(Concealment.cause_text(str(ev.get("cause", "")), who))
	if get_node_or_null("/root/Soundscape") == null:
		_sfx("alert")
	view.input.refresh()
	return {"dur": 1.3}


func _beat_mission_end(ev: Dictionary) -> Dictionary:
	ended = true
	enemy_phase = false
	var result := int(ev.get("result", Types.Result.NONE))
	if get_node_or_null("/root/Soundscape") == null:   # otherwise the Soundscape plays a music stinger
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
	_sfx({"fire": "breach", "smoke": "vent"}.get(kind, "spit"), -4.0)
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


## A sentry turret (or decoy) unfolds on its tile.
func _beat_deployed(ev: Dictionary) -> Dictionary:
	var uv := _uv(ev)
	if uv == null:
		return {}
	_focus(uv)
	view.fx.puff(uv.position + Vector3(0, 0.3, 0), Color(0.5, 0.48, 0.42), 0.9, 0.7, 0.4)
	view.fx.pulse(uv.position, Palette.AMBER)
	var title := "SENTRY ONLINE" if str(ev.get("kind", "")) == "turret" else str(ev.get("kind", "")).to_upper()
	view.fx.floating_text(_head(uv), title, Palette.AMBER, 40)
	_sfx("gadget_deploy")
	return {"dur": 0.4}


## Recon drone: the fog itself lifts (FogOverlay); the drone beat already showed the sweep.
func _beat_revealed_area(_ev: Dictionary) -> Dictionary:
	return {"dur": 0.2}


func _beat_unknown(ev: Dictionary) -> Dictionary:
	if EnemyBeats.handles(ev):
		return EnemyBeats.beat(self, ev)
	generic_log.append("event:" + str(ev.get("type", "")))
	print("[view] unhandled event: ", ev)
	var uv := _uv(ev)
	if uv != null:
		view.fx.floating_text(_head(uv), str(ev.get("type", "?")).to_upper(), Color(0.8, 0.8, 0.8), 32)
		return {"dur": 0.3}
	return {}
