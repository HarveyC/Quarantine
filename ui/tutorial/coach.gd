extends Control
## First-time tips in real runs: the first time a player sees the route map, a reward, the
## loadout, each kind of node, a fight, Infection, a Lapse or a Turn, a short card points at
## the thing that matters. Each tip shows once per profile (Onboarding) and can be turned off
## from the card. Also hosts the "play training first?" card for new players.
##
## Lives on its own layer above the game (App adds it) and only watches: it polls App's run
## view and mission view and listens to the fight's events. Fight tips only fire for this
## machine's own soldiers, so in online co-op each player gets their own.

const Styles := preload("res://ui/styles.gd")
const CoachCard := preload("res://ui/tutorial/coach_card.gd")
const Pointer := preload("res://ui/tutorial/pointer.gd")

## id -> title, text, what to point at (a RunView.hint_target key, or ready / roster / unit /
## cells in a fight; "screen" means the whole open screen, so no arrow), optional visual.
const HINTS := {
	"run_map": {"title": "Route map", "target": "next_node",
		"text": "Click a lit node to vote for the next stop. Paths only go forward, and every act ends at a boss."},
	"outbreak": {"title": "Outbreak", "target": "outbreak",
		"text": "Rises by 1 at every node, and the Infected get tougher with it. Beating a boss knocks it back."},
	"reveal": {"title": "Intel", "target": "reveal",
		"text": "Spend Intel to see what a ? node really is before you vote."},
	"loadout": {"title": "Loadout", "target": "loadout_screen",
		"text": "Four gear slots and two pockets per soldier. Three items with the same tag unlock a set bonus."},
	"reward": {"title": "Spoils", "target": "screen",
		"text": "Each soldier takes one card: gear, a perk, a mutation or a consumable. Skipping gives +10 Supplies."},
	"hospital": {"title": "Field hospital", "target": "screen",
		"text": "One treatment per soldier. Patching up or purging anyone raises Outbreak by 1."},
	"depot": {"title": "Supply depot", "target": "screen",
		"text": "Spend Supplies on gear and pocket items. Serum fully cures a soldier's Infection."},
	"event": {"title": "Event", "target": "screen",
		"text": "Choices can cost HP, Infection or Supplies. Some are voted on, some each player answers alone."},
	"survivors": {"title": "Survivors", "target": "screen",
		"text": "Supplies and a recruit. Recruits wait in reserve and deploy when a soldier falls."},
	"fight": {"title": "Squad phase", "target": "ready",
		"text": "Move and shoot with your soldiers in any order, then press Ready. Enemies move once everyone is ready."},
	"infection": {"title": "Infection", "target": "roster", "visual": "tiers",
		"text": "Teal is Infection. At 25 a mutation wakes, from 50 a soldier can Lapse, at 100 they Turn."},
	"lapse": {"title": "Lapsed", "target": "unit",
		"text": "This soldier lost control and attacks whoever is near. They come back next turn."},
	"turned": {"title": "Turned", "target": "unit",
		"text": "Lost to the Bloom. They fight for the Infected now, and may return later in the run as an Echo."},
	"telegraph": {"title": "Incoming", "target": "cells",
		"text": "Marked tiles get hit next enemy phase. Get off them."},
	"reinforcements": {"title": "Reinforcements", "target": "cells",
		"text": "More Infected arrive at the marked vents next enemy phase."},
}
const TIP_WIDTH := 330.0
const NODE_HINTS := {"event": "event", "depot": "depot", "hospital": "hospital", "survivors": "survivors"}

## App, for its run view, mission view and session (duck-typed so tests can pass a stand-in).
var app: Node
var card: CoachCard
var pointer: Pointer
## Tips are off for headless autoplay and screenshot runs.
var disabled := false
## The tip on screen: {"id", plus "unit" / "cells" for fight tips}; empty when none.
var current := {}
var _queue: Array[Dictionary] = []
var _state: GameState
var _shown := {}
var _offer_play := Callable()
var _offer_skip := Callable()
var _alpha := 0.0
var _dim: ColorRect


func _init() -> void:
	name = "Coach"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Styles.make_theme()
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)
	pointer = Pointer.new()
	add_child(pointer)
	card = CoachCard.new()
	card.pressed.connect(_on_pressed)
	card.visible = false
	add_child(card)
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay" or a.contains("shot="):
			disabled = true
	if OS.get_cmdline_user_args().has("--hints"):   # dev aid: tips on in screenshot runs
		disabled = false


## New players: "play training first?" before their first run. `play` / `skip` are called
## with no arguments once the player picks; either way the question isn't asked again.
func offer_training(play: Callable, skip: Callable) -> void:
	_offer_play = play
	_offer_skip = skip
	current = {"id": "offer"}
	_dim.visible = true
	card.set_width(CoachCard.WIDTH)
	card.show_card("New to Carriers?", "Basic training",
		"A short drill teaches moving, cover, fog, overwatch, high ground and Infection. About five minutes.",
		[], "", [["offer_skip", "Skip, start the run", false], ["offer_play", "Play training", true]])
	card.visible = true
	_alpha = 1.0
	pointer.clear()
	_place(Rect2(), false)


func _on_pressed(id: String) -> void:
	match id:
		"offer_play", "offer_skip":
			Onboarding.set_flag("training_offered")
			var cb := _offer_play if id == "offer_play" else _offer_skip
			_offer_play = Callable()
			_offer_skip = Callable()
			_close()
			if cb.is_valid():
				cb.call()
		"ok":
			_close()
		"off":
			Onboarding.set_hints_enabled(false)
			_queue.clear()
			_close()


func _close() -> void:
	current = {}
	_dim.visible = false
	card.visible = false
	pointer.clear()


# --- watching ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if app == null:
		return
	if current.get("id", "") == "offer":
		return
	_watch_fight()
	if disabled or not Onboarding.hints_enabled() or _in_training():
		if not current.is_empty():
			_close()
		return
	if current.is_empty():
		var next := _next_hint()
		if not next.is_empty():
			_show(next)
	if current.is_empty():
		return
	var target := _target_rect(current)
	if not target.get("ok", false):
		_close()   # its screen went away; it was marked seen when shown
		return
	var busy := _view_busy()
	_alpha = move_toward(_alpha, 0.0 if busy else 1.0, delta * 6.0)
	card.modulate.a = _alpha
	pointer.modulate.a = _alpha
	card.mouse_filter = Control.MOUSE_FILTER_STOP if _alpha > 0.5 else Control.MOUSE_FILTER_IGNORE
	_place(target.rect, target.arrow)


func _show(hint: Dictionary) -> void:
	var def: Dictionary = HINTS[hint.id]
	current = hint
	_shown[hint.id] = true
	Onboarding.mark_hint(hint.id)
	card.set_width(TIP_WIDTH)
	card.show_card("Tip", def.title, def.text, [], def.get("visual", ""),
		[["off", "Turn tips off", false], ["ok", "Got it", true]])
	card.visible = true
	_alpha = 0.0


func _in_training() -> bool:
	return app.get("session") is TutorialSession


func _session() -> Node:
	return app.get("session")


func _mission() -> MissionView:
	var v: Variant = app.get("view")
	return v if v is MissionView and (v as MissionView).is_inside_tree() and (v as MissionView).state != null else null


func _run_view() -> Control:
	var rv: Variant = app.get("run_view")
	return rv if rv is Control and (rv as Control).is_visible_in_tree() else null


func _view_busy() -> bool:
	var v := _mission()
	return v != null and v.player != null and (v.player.is_busy() or v.player.in_cinematic)


func _seen(id: String) -> bool:
	return _shown.has(id) or Onboarding.hint_seen(id)


## The next tip whose moment is now, or {}.
func _next_hint() -> Dictionary:
	var s := _session()
	var run: RunState = s.get("run") if s != null else null
	var v := _mission()
	if v != null and run != null and run.phase == RunState.Phase.FIGHT:
		if v.state.phase != Types.Phase.TEAM or _view_busy():
			return {}
		if not _seen("fight"):
			return {"id": "fight"}
		while not _queue.is_empty():
			var q: Dictionary = _queue.pop_front()
			if not _seen(q.id):
				return q
		return {}
	var rv := _run_view()
	if rv == null or run == null:
		return {}
	var candidates: Array[String] = []
	if rv.hint_target("loadout_screen") != null:
		candidates.append("loadout")
	elif rv.hint_target("screen") != null:
		if run.phase == RunState.Phase.REWARD:
			candidates.append("reward")
		elif run.phase == RunState.Phase.NODE:
			candidates.append(NODE_HINTS.get(str(run.node_state.get("kind", "")), ""))
	elif run.phase == RunState.Phase.MAP:
		candidates.append_array(["run_map", "outbreak"])
		var reveal := rv.hint_target("reveal") as BaseButton
		if reveal != null and reveal.visible and not reveal.disabled:
			candidates.append("reveal")
	for id in candidates:
		if id != "" and not _seen(id):
			return {"id": id}
	return {}


## Queues fight tips from this fight's events (only for this machine's own soldiers).
func _watch_fight() -> void:
	var v := _mission()
	var s: GameState = v.state if v != null else null
	if s == _state:
		return
	if _state != null and _state.event.is_connected(_on_fight_event):
		_state.event.disconnect(_on_fight_event)
	_state = s
	_queue.clear()
	if _state != null:
		_state.event.connect(_on_fight_event)


func _on_fight_event(ev: Dictionary) -> void:
	if disabled or _in_training():
		return
	var mine := func(id: int) -> bool:
		var u := _state.get_unit(id)
		var sess := _session()
		return u != null and u.owner_player >= 0 and sess != null and sess.is_local(u.owner_player)
	match str(ev.get("type", "")):
		"infection":
			if int(ev.get("tier", 0)) >= Infection.Tier.EXPOSED and mine.call(int(ev.unit)):
				_queue.append({"id": "infection"})
		"lapse":
			if mine.call(int(ev.unit)):
				_queue.append({"id": "lapse", "unit": int(ev.unit)})
		"turned":
			var u := _state.get_unit(int(ev.unit))
			if u != null and u.status.get("sid") != null:
				_queue.append({"id": "turned", "unit": int(ev.unit)})
		"telegraph":
			if not ev.get("cells", []).is_empty():
				_queue.append({"id": "telegraph", "cells": ev.cells})
		"reinforcements_incoming":
			_queue.append({"id": "reinforcements", "cells": ev.get("cells", [])})


# --- layout ------------------------------------------------------------------------

## {"ok", "rect", "arrow"} for what the tip points at; ok = false once it's gone.
func _target_rect(hint: Dictionary) -> Dictionary:
	var def: Dictionary = HINTS.get(hint.id, {})
	var key := str(def.get("target", ""))
	var v := _mission()
	match key:
		"ready", "roster":
			if v == null:
				return {"ok": false}
			var c: Control = v.hud.action_bar.ready_button() if key == "ready" else v.hud.roster
			return {"ok": true, "rect": c.get_global_rect(), "arrow": true}
		"unit", "cells":
			if v == null:
				return {"ok": false}
			var w := Vector3.ZERO
			if key == "unit":
				var uv := v.view_for(int(hint.get("unit", -1)))
				if uv == null:
					return {"ok": true, "rect": Rect2(), "arrow": false}
				w = uv.position + Vector3(0, 1.0, 0)
			else:
				var cells: Array = hint.get("cells", [])
				for c in cells:
					w += v.board.cell_to_world(c, 0.3)
				w /= maxf(1.0, cells.size())
			var cam := v.camera_rig.camera if v.camera_rig != null else null
			if cam == null or cam.is_position_behind(w):
				return {"ok": true, "rect": Rect2(), "arrow": false}
			var p := cam.unproject_position(w)
			return {"ok": true, "rect": Rect2(p - Vector2(30, 30), Vector2(60, 60)), "arrow": true}
	var rv := _run_view()
	if rv == null or v != null:
		return {"ok": false}
	var t: Control = rv.hint_target(key)
	if t == null or not t.is_visible_in_tree():
		if key == "next_node" and rv.hint_target("map") != null and _session().run.phase == RunState.Phase.MAP:
			return {"ok": true, "rect": Rect2(), "arrow": false}
		return {"ok": false}
	return {"ok": true, "rect": t.get_global_rect(), "arrow": key != "screen" and key != "loadout_screen"}


## Puts the card beside what it points at (above it in the lower half of the screen, below
## it in the upper half), or in the top-left corner over a full screen.
func _place(target: Rect2, arrow: bool) -> void:
	var vp := size if size != Vector2.ZERO else get_viewport_rect().size
	card.reset_size()
	var cs := card.size
	var pos := Vector2(28, 28)   # over a full screen: the top-left corner, clear of titles and buttons
	if current.get("id", "") == "offer":
		pos = (vp - cs) * 0.5
	elif _mission() == null and _run_view() != null and str(HINTS.get(current.get("id", ""), {}).get("target", "")) != "screen" \
			and _run_view().hint_target("vote") != null and _run_view().hint_target("loadout_screen") == null:
		# Route map tips sit in the empty lower half of the vote panel, off the map itself.
		var vote: Control = _run_view().hint_target("vote")
		pos = Vector2(vp.x - cs.x - 40, maxf(vote.get_global_rect().end.y + 80, vp.y * 0.42))
	elif arrow and target.size != Vector2.ZERO:
		var c := target.get_center()
		var gap := 70.0
		pos.x = clampf(c.x - cs.x * 0.5, 20, vp.x - cs.x - 20)
		if c.y > vp.y * 0.5:
			pos.y = target.position.y - gap - cs.y
		else:
			pos.y = target.end.y + gap
		pos.y = clampf(pos.y, 20, vp.y - cs.y - 20)
	card.position = pos
	if arrow and target.size != Vector2.ZERO:
		pointer.point_at(Rect2(pos, cs), target, true)
	else:
		pointer.clear()
