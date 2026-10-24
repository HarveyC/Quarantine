extends RefCounted
## View side of gadgets and pocket consumables (GearFx abilities "gear:<id>" / "item:<id>"):
## every one gets a beat that shows what it did, so nothing lands silently. Thrown items arc
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


static func handles(ev: Dictionary) -> bool:
	var id := str(ev.get("ability", ""))
	return id.begins_with("item:") or id.begins_with("gear:")


static func beat(ep: Node, ev: Dictionary) -> Dictionary:
	var id := str(ev.get("ability", ""))
	if THROWN.has(id) and ev.get("cell") is Vector2i:
		return _thrown(ep, ev, THROWN[id])
	match id:
		"gear:deployable_cover":
			return _deploy_cover(ep, ev)
		"gear:containment_emitter":
			return _containment(ep, ev)
		"gear:grapple":
			return _title(ep, ev, "GRAPPLE", Palette.AMBER, "pump")
		"gear:adrenal_pump":
			var b: Dictionary = _title(ep, ev, "ADRENAL PUMP", Palette.TEAL, "infect")
			var uv: Node3D = ep._uv(ev)
			if uv != null:
				ep.view.fx.puff(uv.position + Vector3(0, 1.0, 0), Palette.TEAL_DIM, 0.8, 0.7, 0.4)
				uv.flash(Palette.TEAL)
			return b
		"gear:med_injector", "item:suppressant_shot":
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
			return _title(ep, ev, "SENTRY TURRET", Palette.AMBER, "ui_confirm")
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
			ep._sfx("explosion", -10.0)
			ep._sfx("impact_shock", -2.0)
		"smoke":
			for i in 7:
				var a := TAU * float(i) / 7.0
				fx.puff(w + Vector3(cos(a) * 0.9, 0.35, sin(a) * 0.9), SMOKE, 1.4, 1.4, 0.6)
			fx.puff(w + Vector3(0, 0.5, 0), SMOKE, 2.0, 1.6, 0.8)
			ep._sfx("vent", -2.0)
		"flare":
			fx.flash_light(w + Vector3(0, 1.4, 0), FLARE, 7.0, 1.2, 6.0)
			fx.burst(w + Vector3(0, 0.2, 0), Vector3.UP, FLARE, 18, 3.0, true, 0.04)
			fx.puff(w + Vector3(0, 0.5, 0), FLARE.darkened(0.3), 1.0, 1.2, 0.8)
			_ring(fx, w, 1, FLARE)
			ep._sfx("ping_attack", -4.0)
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
			ep._sfx("radio", -2.0)
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
	ep._sfx("concrete", -2.0)
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
	ep._sfx("vent", -4.0)
	return {"dur": 0.6}
