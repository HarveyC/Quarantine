extends RefCounted
## View side of gadgets and pocket consumables (GearFx abilities "gear:<id>" / "item:<id>"),
## and of the soldier abilities that have no beat of their own in EventPlayer (SOLDIER):
## every one gets a beat that shows what it did, so nothing lands silently
## (tests/test_item_audit.gd fails on any that falls back to a bare label). Thrown items arc
## from the soldier's hand and go off where they land; the events that follow (stunned, gear
## mark / suppress, hazard, deployed) put the result on the units and tiles.
## Driven only by event data, like the rest of EventPlayer.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

## Cell items that are lobbed: [title, canister colour, landing].
const THROWN := {
	"item:flashbang": ["FLASHBANG", Color("6f7a6e"), "flash"],
	"item:smoke_grenade": ["SMOKE OUT", Color("5d6660"), "smoke"],
	"gear:flare_launcher": ["FLARE", Color("8a3a2c"), "flare"],
	"gear:concussion_launcher": ["CONCUSSION", Color("4f5436"), "shock"],
	"gear:thermite_charge": ["THERMITE", Color("6b4a2a"), "thermite"],
	"item:recon_drone": ["RECON DRONE", Color("3e4a52"), "drone"],
}
const SMOKE := Color(0.72, 0.74, 0.72)
const FLARE := Color(1.0, 0.36, 0.22)
const FLASH := Color(1.0, 0.97, 0.88)
const CONTAIN := Color("7fd8c9")
const FOAM := Color("e4ece9")
## Soldier abilities drawn here: title, colour, sound, shape. Shapes: "inject" (a jab into the
## target ally), "order" (a radio call to them, with a line of text), "cone" (Incinerate's
## flames over its cells), "tag" (a laser line, Marked), "drain" (Infection drawn into the user).
const SOLDIER := {
	"incinerate": {"title": "INCINERATE", "color": Color("ff7a45"), "sound": "vent", "fx": "cone"},
	"siphon": {"title": "SIPHON", "color": Palette.TEAL, "sound": "infect", "fx": "drain"},
	"purge": {"title": "FLUSH", "color": Color("e9e4d4"), "sound": "heal", "fx": "inject"},
	"decon": {"title": "DECON SHOWER", "color": Color("9fd8e8"), "sound": "smoke_hiss", "fx": "inject"},
	"serum": {"title": "SERUM", "color": Palette.TEAL, "sound": "mutation", "fx": "inject"},
	"squad_order": {"title": "SQUAD LEADER", "color": Palette.AMBER, "sound": "order_call", "fx": "order", "text": "+1 ACTION"},
	"talk_down": {"title": "TALK DOWN", "color": Palette.STEALTH, "sound": "order_call", "fx": "order", "text": "STAND DOWN"},
	"tag": {"title": "MARK", "color": Color("ff5c86"), "sound": "radio", "fx": "tag"},
	"runner_leap": {"title": "LEAP", "color": Palette.TEAL, "sound": "grapple", "fx": "leap"},
}
## Gadgets and pocket items with a beat here (the rest of item:/gear: are frag, demo and medkit,
## which EventPlayer plays itself).
const ITEMS := ["item:flashbang", "item:smoke_grenade", "item:recon_drone", "item:suppressant_shot", "item:antiviral_dose", "item:breather_mask", "item:stim",
	"item:containment_foam", "gear:flare_launcher", "gear:concussion_launcher", "gear:thermite_charge",
	"gear:med_injector", "gear:adrenal_pump", "gear:deployable_cover", "gear:grapple", "gear:containment_emitter",
	"gear:sentry_turret"]


static func handles(ev: Dictionary) -> bool:
	return has_look(str(ev.get("ability", "")))


static func has_look(id: String) -> bool:
	return ITEMS.has(id) or SOLDIER.has(id)


static func beat(ep: Node, ev: Dictionary) -> Dictionary:
	var id := str(ev.get("ability", ""))
	if SOLDIER.has(id):
		return _soldier(ep, ev, SOLDIER[id])
	if THROWN.has(id) and ev.get("cell") is Vector2i:
		return _thrown(ep, ev, THROWN[id])
	match id:
		"gear:deployable_cover":
			return _deploy_cover(ep, ev)
		"gear:containment_emitter":
			return _containment(ep, ev)
		"gear:grapple":
			var b: Dictionary = _title(ep, ev, "GRAPPLE", Palette.AMBER, "grapple")
			var uv: Node3D = ep._uv(ev)
			if uv != null and ev.get("cell") is Vector2i:
				var to := Board.cell_to_world(ev.cell) + Vector3(0, 0.3, 0)
				ep.view.fx.tracer(uv.position + Vector3(0, 1.2, 0), to, Palette.AMBER, 0.6)
				ep.view.fx.burst(to, Vector3.UP, Color(0.6, 0.58, 0.5), 10, 3.0, false, 0.04)
			return b
		"item:containment_foam":
			return _foam(ep, ev)
		"gear:adrenal_pump":
			var b: Dictionary = _title(ep, ev, "ADRENAL PUMP", Palette.TEAL, "infect")
			var uv: Node3D = ep._uv(ev)
			if uv != null:
				ep.view.fx.puff(uv.position + Vector3(0, 1.0, 0), Palette.TEAL_DIM, 0.8, 0.7, 0.4)
				uv.flash(Palette.TEAL)
			return b
		"item:breather_mask":
			var b: Dictionary = _title(ep, ev, "BREATHER MASK", Palette.TEAL, "emitter_hum")
			var uv: Node3D = ep._uv(ev)
			if uv != null:
				ep.view.fx.puff(uv.position + Vector3(0, 1.0, 0), Palette.TEAL_DIM, 0.8, 0.7, 0.4)
				uv.flash(Palette.TEAL)
			return b
		"gear:med_injector", "item:suppressant_shot", "item:antiviral_dose":
			var b: Dictionary = ep._power_beat(ev, _name(ev), Palette.HEAL)
			ep._sfx("heal", -4.0)
			return b
		"item:stim":
			var b: Dictionary = _title(ep, ev, "STIM", Palette.HEAL, "heal")
			var uv: Node3D = ep._uv(ev)
			if uv != null:
				uv.flash(Palette.HEAL)
				ep.view.fx.pulse(uv.position, Palette.HEAL)
				ep.view.fx.floating_text(ep._head(uv) + Vector3(0, 0.35, 0), "+1 ACTION", Palette.HEAL, 40)
			return b
		"gear:sentry_turret":
			return _title(ep, ev, "SENTRY TURRET", Palette.AMBER, "gadget_deploy")
	ep.generic_log.append("ability:" + id)
	return ep._power_beat(ev, _name(ev), Palette.AMBER)


## The item's display name ("Smoke grenade"), never the raw id.
static func _name(ev: Dictionary) -> String:
	var n := str(ev.get("name", ""))
	if n == "":
		n = GearData.item_name(str(ev.get("ability", "")).substr(5))
	return n


static func _title(ep: Node, ev: Dictionary, title: String, color: Color, sound: String) -> Dictionary:
	var uv: Node3D = ep._uv(ev)
	if uv == null:
		return {}
	ep._focus(uv)
	ep.view.fx.floating_text(ep._head(uv), title, color, 44)
	ep._sfx(sound, -3.0)
	return {"dur": 0.5}


## A canister lobbed in an arc; it goes off on landing.
static func _thrown(ep: Node, ev: Dictionary, spec: Array) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev)
	var w := Board.cell_to_world(ev.cell)
	var landing: String = spec[2]
	var from := w + Vector3(0, 6.0, 0) if uv == null else uv.position + Vector3(0, 1.3, 0)
	if uv != null:
		ep._focus(uv)
		uv.face_towards(w)
		fx.floating_text(ep._head(uv), spec[0], CONTAIN if landing == "drone" else Palette.AMBER, 44)
	ep._sfx("ui_click", -2.0)
	var drone := landing == "drone"
	var to := w + Vector3(0, 2.4 if drone else 0.12, 0)
	var can: Node3D = fx.spawn_round("slug", spec[1], 2.6 if drone else 2.2, false)
	can.set_meta("arc", (0.4 if drone else 2.2) / maxf(0.1, from.distance_to(to)))
	var flight := 0.9 if drone else 0.6
	var after: float = {"flash": 0.45, "smoke": 0.7, "flare": 0.55, "shock": 0.45, "thermite": 0.3, "drone": 0.8}.get(landing, 0.4)
	var dur: float = flight + after
	var st := {"landed": false}
	var update := func(k: float) -> void:
		var t := k * dur
		fx.place_bullet(can, from, to, clampf(t / flight, 0.0, 1.0))
		if t >= flight and not st.landed:
			st.landed = true
			if not drone:
				fx.remove(can)
			_land(ep, ev, landing, w)
	var finish := func() -> void: fx.remove(can)
	return {"dur": dur, "update": update, "finish": finish}


static func _land(ep: Node, ev: Dictionary, landing: String, w: Vector3) -> void:
	var view: Node = ep.view
	var fx = view.fx
	var units: Array = ev.get("units", [])
	match landing:
		"flash":
			fx.flash_light(w + Vector3(0, 0.8, 0), FLASH, 14.0, 0.35, 7.0)
			fx.burst(w + Vector3(0, 0.3, 0), Vector3.UP, FLASH, 26, 4.5, true, 0.04)
			fx.puff(w + Vector3(0, 0.4, 0), Color(0.85, 0.85, 0.8), 1.6, 0.8, 0.3)
			_ring(fx, w, 1, FLASH)
			view.camera_rig.shake(0.5)
			ep._sfx("flashbang")
		"smoke":
			for i in 7:
				var a := TAU * float(i) / 7.0
				fx.puff(w + Vector3(cos(a) * 0.9, 0.35, sin(a) * 0.9), SMOKE, 1.4, 1.4, 0.6)
			fx.puff(w + Vector3(0, 0.5, 0), SMOKE, 2.0, 1.6, 0.8)
			ep._sfx("smoke_hiss", -2.0)
		"flare":
			fx.flash_light(w + Vector3(0, 1.4, 0), FLARE, 7.0, 1.2, 6.0)
			fx.burst(w + Vector3(0, 0.2, 0), Vector3.UP, FLARE, 18, 3.0, true, 0.04)
			fx.puff(w + Vector3(0, 0.5, 0), FLARE.darkened(0.3), 1.0, 1.2, 0.8)
			_ring(fx, w, 1, FLARE)
			ep._sfx("flare_pop", -2.0)
		"shock":
			fx.flash_light(w + Vector3(0, 0.6, 0), Palette.AMBER, 6.0, 0.3, 5.0)
			fx.puff(w + Vector3(0, 0.3, 0), Color(0.55, 0.52, 0.45), 1.6, 0.7, 0.2)
			_ring(fx, w, int(ev.get("radius", 1)), Palette.AMBER)
			view.camera_rig.shake(0.6)
			ep._sfx("impact_shock")
		"thermite":
			fx.flash_light(w + Vector3(0, 0.5, 0), Color("ff7a2a"), 8.0, 0.4, 5.0)
			fx.burst(w + Vector3(0, 0.2, 0), Vector3.UP, Color("ffb05a"), 20, 3.5, true, 0.04)
			ep._sfx("breach", -4.0)
		"drone":
			fx.pulse(w, CONTAIN, 1.2)
			_ring(fx, w, Vision.DRONE_RADIUS, CONTAIN)
			fx.flash_light(w + Vector3(0, 2.4, 0), CONTAIN, 4.0, 0.8, 8.0)
			ep._sfx("drone", -2.0)
			ep._sfx("radio", -4.0, 0.3)
	if not units.is_empty() and landing in ["flash", "flare", "shock"]:
		for id in units:
			var tv: Node3D = ep._uv({"unit": id})
			if tv != null and tv.visible:
				tv.flash(FLASH if landing == "flash" else (FLARE if landing == "flare" else Palette.AMBER))


## A square ring on the floor marking a radius-r area (Chebyshev, like the rules).
static func _ring(fx: Node, w: Vector3, r: int, color: Color) -> void:
	var side := 2.0 * r + 1.0
	var off := side * 0.5
	for k in 4:
		var bar := Palette.box(Vector3(side, 0.03, 0.07) if k < 2 else Vector3(0.07, 0.03, side), Palette.overlay(Color(color, 0.95)))
		bar.position = w + (Vector3(0, 0.06, off * (1 if k == 0 else -1)) if k < 2 else Vector3(off * (1 if k == 2 else -1), 0.06, 0))
		fx.add_child(bar)
		fx.fade_out(bar, 1.1)
	var fill := Palette.box(Vector3(side, 0.02, side), Palette.overlay(Color(color, 0.16)))
	fill.position = w + Vector3(0, 0.04, 0)
	fx.add_child(fill)
	fx.fade_out(fill, 1.1)


static func _deploy_cover(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var uv: Node3D = ep._uv(ev)
	view.board.rebuild_tiles()
	if ev.get("cell") is Vector2i:
		var w := Board.cell_to_world(ev.cell)
		if uv != null:
			uv.face_towards(w)
		view.fx.puff(w + Vector3(0, 0.4, 0), Color(0.5, 0.48, 0.42), 1.0, 0.8, 0.4)
		view.fx.pulse(w, Palette.AMBER)
	if uv != null:
		ep._focus(uv)
		view.fx.floating_text(ep._head(uv), "COVER DEPLOYED", Palette.AMBER, 44)
	ep._sfx("gadget_deploy")
	view.input.refresh()
	return {"dur": 0.6}


static func _containment(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var uv: Node3D = ep._uv(ev)
	if uv == null:
		return {}
	ep._focus(uv)
	view.fx.floating_text(ep._head(uv), "CONTAINMENT FIELD", CONTAIN, 44)
	_ring(view.fx, uv.position, 2, CONTAIN)
	view.fx.flash_light(uv.position + Vector3(0, 1.0, 0), CONTAIN, 4.0, 0.6, 5.0)
	var until := int(ev.get("until", -1))
	for id in ev.get("units", []):
		var tv: Node3D = ep._uv({"unit": id})
		if tv != null:
			tv.flash(CONTAIN)
			if until >= 0:
				tv.set_tag("contained", until)
	ep._sfx("emitter_hum")
	return {"dur": 0.6}


## Containment foam: sprayed onto the Lapsed or Turned soldier, which sets hard round them.
static func _foam(ep: Node, ev: Dictionary) -> Dictionary:
	var uv: Node3D = ep._uv(ev)
	var tv: Node3D = ep._uv(ev, "target")
	if uv == null or tv == null:
		return {}
	var fx = ep.view.fx
	ep._focus(uv)
	uv.face_towards(tv.position)
	fx.floating_text(ep._head(uv), "CONTAINMENT FOAM", FOAM, 44)
	ep._sfx("foam_spray")
	var src: Vector3 = uv.position + Vector3(0, 1.2, 0)
	var st := {"n": 0}
	var update := func(k: float) -> void:
		while st.n < int(k * 8.0) and st.n < 8:
			st.n += 1
			var to: Vector3 = tv.aim_point() + Vector3(sin(st.n * 1.9) * 0.2, cos(st.n * 2.7) * 0.2, 0)
			fx.tracer(src, to, FOAM, 0.25)
			fx.puff(to, FOAM, 0.7, 1.6, 0.05)
	var finish := func() -> void:
		fx.puff(tv.position + Vector3(0, 0.5, 0), FOAM, 1.6, 2.0, 0.1)
		fx.decal(tv.position, FOAM.darkened(0.2), 0.6)
		tv.flash(FOAM)
		tv.set_tag("restrained", ep.phase_now() + GearFx.FOAM_PHASES)
		fx.floating_text(ep._head(tv) + Vector3(0, 0.35, 0), "RESTRAINED", FOAM, 40, 1.5)
	return {"dur": 0.9, "update": update, "finish": finish}


## Soldier abilities in SOLDIER (Incinerate, Siphon, Purge, Decon, Serum, orders, Marksman Tag).
static func _soldier(ep: Node, ev: Dictionary, look: Dictionary) -> Dictionary:
	var uv: Node3D = ep._uv(ev)
	if uv == null:
		return {}
	var fx = ep.view.fx
	var col: Color = look.color
	ep._focus(uv)
	fx.floating_text(ep._head(uv), look.title, col, 44)
	var tv: Node3D = ep._uv(ev, "target") if ev.has("target") else null
	if tv != null and tv != uv:
		uv.face_towards(tv.position)
	ep._sfx(look.sound)
	match str(look.fx):
		"inject":
			var on: Node3D = tv if tv != null else uv
			if on != uv:
				fx.tracer(uv.position + Vector3(0, 1.2, 0), on.aim_point(), col, 0.35)
			fx.puff(on.position + Vector3(0, 0.9, 0), col, 1.0, 0.9, 0.5)
			fx.burst(on.aim_point(), Vector3.UP, col, 14, 2.0, true, 0.03)
			fx.flash_light(on.position + Vector3(0, 1.0, 0), col, 3.0, 0.5)
			fx.pulse(on.position, col)
			on.flash(col)
			return {"dur": 0.7}
		"order":
			if tv != null:
				fx.pulse(tv.position, col)
				fx.flash_light(tv.position + Vector3(0, 1.2, 0), col, 2.0, 0.5)
				fx.floating_text(ep._head(tv) + Vector3(0, 0.35, 0), str(look.get("text", "")), col, 40, 1.4)
			return {"dur": 0.7}
		"tag":
			ep._sfx("ui_confirm", -4.0, 0.2)
			if tv != null:
				fx.tracer(uv.muzzle_world(), tv.aim_point(), col, 0.9)
				fx.pulse(tv.position, col)
				tv.flash(col)
				fx.floating_text(ep._head(tv) + Vector3(0, 0.35, 0), "MARKED", col, 40, 1.4)
			return {"dur": 0.7}
		"leap":
			# Runner legs: dust where it took off, a burst of spores where it lands.
			var from: Vector2i = ev.get("from", Vector2i(-1, -1))
			if from.x >= 0:
				fx.puff(Board.cell_to_world(from) + Vector3(0, 0.2, 0), Color(0.45, 0.42, 0.36), 1.0, 0.8, 0.5)
			fx.burst(uv.position + Vector3(0, 0.15, 0), Vector3.UP, col, 14, 2.5, true, 0.04)
			fx.pulse(uv.position, col)
			ep._sfx("step3", -4.0, 0.15)
			return {"dur": 0.55}
		"drain":
			if tv != null:
				for i in 3:
					fx.tracer(tv.aim_point(), uv.aim_point() + Vector3(0, 0.1 * i, 0), col, 0.6 + 0.15 * i)
				fx.burst(tv.aim_point(), Vector3.UP, col, 10, 1.5, true, 0.03)
			fx.pulse(uv.position, col)
			return {"dur": 0.7}
		"cone":
			var cells: Array = ev.get("cells", [])
			ep._sfx("explosion", -10.0)
			uv.set_aim(1.0)
			var from: Vector3 = uv.muzzle_world()
			var st := {"n": 0}
			var update := func(k: float) -> void:
				while st.n < int(k * cells.size()) and st.n < cells.size():
					var w := Board.cell_to_world(cells[st.n])
					fx.burst(w + Vector3(0, 0.3, 0), (w - from).normalized() + Vector3.UP * 0.4, col, 10, 4.0, true, 0.05)
					fx.puff(w + Vector3(0, 0.5, 0), col.lerp(Color(0.25, 0.2, 0.18), 0.5), 1.2, 0.9, 0.7)
					if st.n % 3 == 0:
						fx.flash_light(w + Vector3(0, 0.6, 0), col, 4.0, 0.4, 4.0)
					st.n += 1
			var finish := func() -> void: uv.set_aim(0.0)
			ep.view.camera_rig.shake(0.4)
			return {"dur": 0.8, "update": update, "finish": finish}
	return {"dur": 0.5}
