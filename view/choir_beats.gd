extends RefCounted
## Animation beats for the Choir Prophet (ChoirProphet): the verse, the fix and the compelling, Hush,
## the Crescendo, and the ring and hymn events. Every ability is aimed on the ground or with a teal
## link a turn before it lands, so a beat only has to sell the call. Driven only by event data.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

const IDS := ["verse", "fix", "compel", "quell", "crescendo"]
const EVENTS := ["ring", "hymn"]
const HUSH := Color(0.55, 0.62, 0.66)


static func handles(id: String) -> bool:
	return IDS.has(id)


static func handles_event(ev: Dictionary) -> bool:
	return EVENTS.has(str(ev.get("type", "")))


static func beat(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev)
	if uv == null:
		return {}
	var head: Vector3 = ep._head(uv)
	var cells: Array = ev.get("cells", [])
	ep._focus(uv)
	match str(ev.get("ability", "")):
		"verse":   # a phrase of the hymn rings out and lands on the marked ground
			fx.floating_text(head, "VERSE", Palette.TEAL, 48)
			if ev.get("cell") is Vector2i:
				var at := Board.cell_to_world(ev.cell)
				fx.tracer(head, at + Vector3(0, 0.4, 0), Palette.TEAL, 0.6)
				fx.flash_light(at + Vector3(0, 1.0, 0), Palette.TEAL, 3.5, 0.5, 4.0)
			for c in cells:
				fx.pulse(Board.cell_to_world(c), Palette.TEAL, 0.8)
			ep._sfx("weave_hum", -2.0)
			return {"dur": 0.6}
		"fix":   # a teal thread lands on the soldier and the Prophet's eyes lock
			fx.floating_text(head, "THE HYMN FINDS", Palette.TEAL, 44)
			var tv: Node3D = ep._uv(ev, "target")
			if tv != null:
				fx.tracer(head, tv.aim_point(), Palette.TEAL, 0.9)
				fx.pulse(tv.position, Palette.TEAL, 0.9)
				fx.floating_text(ep._head(tv), "FIXED", Palette.TEAL, 52)
			ep._sfx("infect", -2.0)
			return {"dur": 0.8}
		"compel":   # the thread pulls tight; the soldier's head turns toward the song
			fx.floating_text(head, "COMPEL", Palette.TEAL, 52)
			var tv: Node3D = ep._uv(ev, "target")
			if tv != null:
				fx.tracer(head, tv.aim_point(), Palette.TEAL, 0.5)
				fx.burst(tv.position + Vector3(0, 1.0, 0), Vector3.UP, Palette.TEAL, 12, 2.0, true, 0.04)
				tv.flash(Palette.TEAL)
			ep._sfx("mutation", -3.0)
			return {"dur": 0.6}
		"quell":   # the song folds over one soldier and takes their voice
			fx.floating_text(head, "HUSH", HUSH, 48)
			var tv: Node3D = ep._uv(ev, "target")
			if tv != null:
				fx.tracer(head, tv.aim_point(), HUSH, 0.6)
				fx.pulse(tv.position, HUSH, 0.9)
				fx.floating_text(ep._head(tv), "SILENCED", HUSH, 48)
			ep._sfx("alert", -6.0)
			return {"dur": 0.7}
		"crescendo":   # the whole room lights up teal
			fx.floating_text(head, "CRESCENDO", Palette.DANGER, 60)
			fx.pulse(uv.position, Palette.TEAL, 1.4)
			var step := maxi(1, cells.size() / 28)
			for i in range(0, cells.size(), step):
				fx.pulse(Board.cell_to_world(cells[i]), Palette.DANGER, 0.9)
			fx.flash_light(uv.position + Vector3(0, 2.0, 0), Palette.TEAL, 8.0, 0.8, 12.0)
			view.camera_rig.shake(0.8)
			ep._sfx("mutation", -2.0)
			return {"dur": 0.9}
	return {}


## The chant ring pressing Infection into the soldiers inside it; the hymn building; .
static func event_beat(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev)
	match str(ev.get("type", "")):
		"ring":
			if uv == null:
				return {}
			ep._focus(uv)
			fx.pulse(uv.position, Palette.TEAL, 1.2)
			var r := float(ev.get("radius", 4.0))
			for i in 12:
				var a := TAU * i / 12.0
				var at := uv.position + Vector3(cos(a) * r, 0.1, sin(a) * r)
				fx.burst(at, Vector3.UP, Palette.TEAL, 3, 1.5, true, 0.04)
			for id in ev.get("units", []):
				var tv: Node3D = view.view_for(int(id))
				if tv != null:
					fx.floating_text(ep._head(tv), "+%d" % int(ev.get("amount", 0)), Palette.TEAL, 40)
					fx.burst(tv.position + Vector3(0, 1.0, 0), Vector3.UP, Palette.TEAL, 6, 1.2, true, 0.03)
			ep._sfx("infect", -6.0)
			return {"dur": 0.6}
		"hymn":
			if uv == null:
				return {}
			ep._focus(uv)
			var peak := int(ev.get("charge", 0)) >= int(ev.get("max", 3))
			fx.floating_text(ep._head(uv), "THE HYMN PEAKS" if peak else "HYMN %d/%d" % [int(ev.get("charge", 0)), int(ev.get("max", 3))],
				Palette.DANGER if peak else Palette.TEAL, 44)
			fx.pulse(uv.position, Palette.TEAL, 0.7 + 0.2 * float(ev.get("charge", 0)))
			ep._sfx("weave_hum", -4.0)
			return {"dur": 0.5}
	return {}
