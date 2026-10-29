extends RefCounted
## Animation beats for the Act 2 and 3 boss abilities (ColonelHale, SourceBoss): each one shows
## where it is aimed on the ground a turn before it lands, so the beat only has to sell the call.
## Driven only by event data, like EnemyBeats.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")
const ChoirBeats := preload("res://view/choir_beats.gd")

const IDS := ["airstrike", "smoke_screen", "stomp", "hurl", "danger_close", "lash", "core_slam", "pull", "rockfall", "debris", "charge", "piston", "bite",
	"sight", "flag", "retrieve"]
const SMOKE := Color(0.62, 0.64, 0.62)
const DUST := Color(0.5, 0.42, 0.32)


static func handles(id: String) -> bool:
	return IDS.has(id) or ChoirBeats.handles(id)


static func beat(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev)
	if uv == null:
		return {}
	var id := str(ev.get("ability", ""))
	if ChoirBeats.handles(id):
		return ChoirBeats.beat(ep, ev)
	var cells: Array = ev.get("cells", [])
	var head: Vector3 = ep._head(uv)
	ep._focus(uv)
	match id:
		"airstrike":   # the radio call, then a flare drops on the target
			fx.floating_text(head, "FIRE MISSION", Palette.AMBER, 48)
			if ev.get("cell") is Vector2i:
				var at := Board.cell_to_world(ev.cell)
				fx.tracer(at + Vector3(0, 9.0, 0), at + Vector3(0, 0.2, 0), Palette.AMBER, 0.6)
				fx.flash_light(at + Vector3(0, 1.2, 0), Palette.AMBER, 5.0, 0.5, 5.0)
				fx.puff(at + Vector3(0, 0.2, 0), Color(0.9, 0.35, 0.25), 0.7, 1.2, 0.8)
			ep._sfx("alert", -4.0)
			return {"dur": 0.7}
		"smoke_screen":
			fx.floating_text(head, "SMOKE SCREEN", SMOKE, 44)
			for c in cells:
				fx.puff(Board.cell_to_world(c, 0.3), SMOKE, 1.3, 1.6, 0.6)
			ep._sfx("concrete", -4.0)
			return {"dur": 0.6}
		"stomp":
			fx.floating_text(head, "STOMP", Palette.DANGER, 52)
			for c in cells:
				fx.burst(Board.cell_to_world(c, 0.1), Vector3.UP, DUST, 5, 3.0, false, 0.07)
				fx.pulse(Board.cell_to_world(c), Palette.DANGER, 0.8)
			view.camera_rig.shake(0.9)
			ep._sfx("collapse", -4.0)
			return {"dur": 0.7}
		"hurl":
			fx.floating_text(head, "HURLS WRECKAGE", Palette.DANGER, 44)
			if ev.get("cell") is Vector2i:
				var at := Board.cell_to_world(ev.cell)
				fx.spark_arc(uv.position + Vector3(0, 2.0, 0), at + Vector3(0, 0.3, 0), Color("6a6d70"), 0.5)
				fx.crumble(uv.position, 0.8, Color("4a4d50"))
				fx.pulse(at, Palette.DANGER, 0.9)
			ep._sfx("collapse", -6.0)
			return {"dur": 0.7}
		"rockfall":   # she heaves the ground up: rocks arc high and come down on the marked tiles
			fx.floating_text(head, "ROCKS!", Palette.DANGER, 52)
			for c in cells:
				var at := Board.cell_to_world(c)
				fx.spark_arc(uv.position + Vector3(0, 2.2, 0), at + Vector3(0, 0.3, 0), Color("6a6d70"), 0.6)
				fx.pulse(at, Palette.DANGER, 0.8)
			fx.crumble(uv.position, 1.0, Color("4a4d50"))
			view.camera_rig.shake(0.7)
			ep._sfx("collapse", -4.0)
			return {"dur": 0.9}
		"debris":   # the rig tears rubble down on the marked tiles
			fx.floating_text(head, "RUBBLE!", Palette.DANGER, 52)
			for c in cells:
				var at := Board.cell_to_world(c)
				fx.spark_arc(uv.position + Vector3(0, 2.4, 0), at + Vector3(0, 0.3, 0), Color("6a6d70"), 0.6)
				fx.pulse(at, Palette.DANGER, 0.8)
			fx.crumble(uv.position, 1.0, Color("4a4d50"))
			view.camera_rig.shake(0.6)
			ep._sfx("collapse", -4.0)
			return {"dur": 0.8}
		"charge":   # a run that hit nobody: the cover it flattened and the shake say it
			fx.floating_text(head, "CHARGE", Palette.DANGER, 48)
			for c in ev.get("path", []):
				fx.burst(Board.cell_to_world(c, 0.1), Vector3.UP, DUST, 4, 3.0, false, 0.07)
			view.camera_rig.shake(0.5)
			ep._sfx("collapse", -6.0)
			return {"dur": 0.4}
		"danger_close":
			fx.floating_text(head, "DANGER CLOSE", Palette.DANGER, 56)
			for c in cells:
				fx.pulse(Board.cell_to_world(c), Palette.AMBER, 0.9)
			fx.tracer(uv.position + Vector3(0, 9.0, 0), uv.position + Vector3(0, 0.2, 0), Palette.AMBER, 0.6)
			ep._sfx("alert")
			return {"dur": 0.8}
		"lash":   # tendrils whip out of the roots (or the core) to the marked ground
			fx.floating_text(head, "LASH", Palette.TEAL, 44)
			if ev.get("cell") is Vector2i:
				var at := Board.cell_to_world(ev.cell)
				fx.tracer(uv.position + Vector3(0, 0.8, 0), at + Vector3(0, 0.1, 0), Palette.TEAL, 0.6)
				for c in cells:
					fx.burst(Board.cell_to_world(c, 0.1), Vector3.UP, Palette.TEAL, 4, 2.0, true, 0.05)
			ep._sfx("infect", -4.0)
			return {"dur": 0.6}
		"core_slam":
			fx.floating_text(head, "THE CORE RISES", Palette.DANGER, 48)
			for c in cells:
				fx.pulse(Board.cell_to_world(c), Palette.DANGER, 0.9)
			view.camera_rig.shake(0.8)
			ep._sfx("mutation", -6.0)
			return {"dur": 0.7}
		"piston":   # the rams hammer out along the marked row or column
			fx.floating_text(head, "PISTONS", Palette.DANGER, 44)
			for c in cells:
				fx.pulse(Board.cell_to_world(c), Palette.DANGER, 0.7)
			if not cells.is_empty():
				fx.tracer(uv.position + Vector3(0, 0.6, 0), Board.cell_to_world(cells[0], 0.3), Palette.AMBER, 0.5)
				fx.tracer(uv.position + Vector3(0, 0.6, 0), Board.cell_to_world(cells[cells.size() - 1], 0.3), Palette.AMBER, 0.5)
			view.camera_rig.shake(0.6)
			ep._sfx("concrete", -2.0)
			return {"dur": 0.6}
		"bite":    # the jaws of the collar clamp shut round the shaft
			fx.floating_text(head, "THE ENGINE BITES", Palette.DANGER, 52)
			for c in cells:
				fx.pulse(Board.cell_to_world(c), Palette.DANGER, 0.9)
			fx.crumble(uv.position, 1.2, Color("4a4d50"))
			view.camera_rig.shake(1.0)
			ep._sfx("collapse", -4.0)
			return {"dur": 0.8}
		"pull":
			fx.floating_text(head, "PULL", Palette.TEAL, 48)
			var tv: Node3D = ep._uv(ev, "target")
			if tv != null:
				fx.tracer(uv.position + Vector3(0, 1.0, 0), tv.aim_point(), Palette.TEAL, 0.6)
				fx.pulse(tv.position, Palette.TEAL)
			ep._sfx("infect", -4.0)
			return {"dur": 0.6}
		"sight":   # the laser sight settles on a soldier: the lock a turn before the shot
			fx.floating_text(head, "LOCKED", Palette.DANGER, 44)
			var sv: Node3D = ep._uv(ev, "target")
			if sv != null:
				fx.tracer(uv.position + Vector3(0, 1.6, 0), sv.aim_point(), Palette.DANGER, 0.7)
				fx.pulse(sv.position, Palette.DANGER, 0.9)
			ep._sfx("alert", -6.0)
			return {"dur": 0.6}
		"flag":   # the Director tags a soldier for retrieval
			fx.floating_text(head, "RETRIEVAL ORDER", Palette.AMBER, 48)
			var fv: Node3D = ep._uv(ev, "target")
			if fv != null:
				fx.tracer(uv.position + Vector3(0, 1.6, 0), fv.aim_point(), Palette.AMBER, 0.7)
				fx.pulse(fv.position, Palette.AMBER, 1.0)
				fx.floating_text(ep._head(fv), "MARKED", Palette.AMBER, 44)
			ep._sfx("alert", -4.0)
			return {"dur": 0.8}
		"retrieve":   # the cage is called down on the ground a turn before it lands
			fx.floating_text(head, "RETRIEVAL CAGE", Palette.AMBER, 48)
			for c in cells:
				fx.pulse(Board.cell_to_world(c), Palette.AMBER, 0.9)
			if ev.get("cell") is Vector2i:
				var at := Board.cell_to_world(ev.cell)
				fx.tracer(at + Vector3(0, 9.0, 0), at + Vector3(0, 0.2, 0), Palette.AMBER, 0.6)
			ep._sfx("alert", -4.0)
			return {"dur": 0.7}
	return {}
