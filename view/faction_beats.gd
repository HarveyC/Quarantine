extends RefCounted
## Animation beats and combat-log lines for the Halden-Voss Recovery and the Choir (enemies/recovery.gd,
## enemies/choir.gd): each ability is shown where it is aimed before it lands, so the beat only has
## to sell the call. Driven only by event data, like EnemyBeats.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

const ABILITIES := ["net", "designate", "sterilize", "drag", "bloom", "hush", "silence"]
const EVENTS := ["chant", "hushed", "captured", "mark_lapsed", "cleansed"]
const FLAME := Color(1.0, 0.55, 0.18)


static func handles_ability(id: String) -> bool:
	return ABILITIES.has(id)


static func handles(ev: Dictionary) -> bool:
	return EVENTS.has(str(ev.get("type", "")))


## The beat for an ability event of the two factions.
static func ability_beat(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev)
	if uv == null:
		return {}
	var id := str(ev.get("ability", ""))
	var cells: Array = ev.get("cells", [])
	var head: Vector3 = ep._head(uv)
	match id:
		"net":   # a weighted net thrown at the soldier beside it
			return ep._melee_beat(ev, {"sound": "grapple", "title": "NET", "fx": "shock"})
		"designate":   # the Handler paints one soldier for the whole company
			ep._sfx("order_call", -2.0)
			var db: Dictionary = ep._power_beat(ev, "designate", Palette.DANGER)
			var dt: Node3D = ep._uv(ev, "target")
			if dt != null:
				fx.floating_text(ep._head(dt), "DESIGNATED", Palette.DANGER, 48)
				fx.pulse(dt.position, Palette.DANGER, 1.0)
			db["dur"] = 0.8
			return db
		"sterilize":   # the flame cone: the marked ground blooms with fire a turn before it lands
			ep._focus(uv)
			fx.floating_text(head, "STERILIZE", FLAME, 48)
			for c in cells:
				var w := Board.cell_to_world(c)
				fx.pulse(w, FLAME, 0.9)
				fx.burst(w + Vector3(0, 0.2, 0), Vector3.UP, FLAME, 4, 2.5, true, 0.04)
			if ev.get("cell") is Vector2i:
				uv.face_towards(Board.cell_to_world(ev.cell))
			ep._sfx("flare_pop", -2.0)
			return {"dur": 0.8}
		"drag":   # hauls the netted soldier along the ground toward the edge
			ep._sfx("grapple", -2.0)
			var gb: Dictionary = ep._power_beat(ev, "drag", Palette.DANGER)
			gb["dur"] = 0.5
			return gb
		"bloom":   # the Acolyte opens up: spores and a teal ring over the 5x5
			ep._focus(uv)
			fx.floating_text(head, "BLOOM", Palette.TEAL, 52)
			for c in cells:
				var w2 := Board.cell_to_world(c, 0.3)
				fx.puff(w2, Palette.TEAL_DIM, 0.9, 1.2, 0.5)
				fx.pulse(Board.cell_to_world(c), Palette.TEAL, 0.9)
			fx.burst(uv.position + Vector3(0, 0.8, 0), Vector3.UP, Palette.TEAL, 24, 4.0, true, 0.06)
			view.camera_rig.shake(0.6)
			ep._sfx("spore_burst", -2.0)
			return {"dur": 0.8}
		"hush":   # the lock: a teal thread to the soldier it will silence
			ep._sfx("emitter_hum", -4.0)
			var hb: Dictionary = ep._power_beat(ev, "hush", Palette.TEAL)
			hb["dur"] = 0.6
			return hb
		"silence":
			ep._sfx("drone", -4.0)
			var sb: Dictionary = ep._power_beat(ev, "silence", Palette.TEAL)
			sb["dur"] = 0.6
			return sb
	return {}


## The beat for one of the factions' own events.
static func beat(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev) if ev.has("unit") else null
	match str(ev.get("type", "")):
		"chant":   # the Cantor sings: a ring on the floor and a pulse on every voice it lifts
			if uv != null:
				fx.floating_text(ep._head(uv), "CHANT", Palette.TEAL, 44)
				fx.pulse(uv.position, Palette.TEAL, 1.2)
			for id in ev.get("units", []):
				var av: Node3D = view.view_for(int(id))
				if av != null:
					fx.pulse(av.position, Palette.TEAL, 0.7)
					fx.tracer(uv.position + Vector3(0, 1.4, 0), av.aim_point(), Palette.TEAL, 0.4)
			ep._sfx("emitter_hum", -8.0)
			return {"dur": 0.5}
		"hushed":
			if uv != null:
				fx.floating_text(ep._head(uv), "HUSHED", Palette.TEAL, 52)
				fx.pulse(uv.position, Palette.TEAL, 1.0)
				uv.flash(Palette.TEAL)
			ep._sfx("impact_shock", -6.0)
			return {"dur": 0.5}
		"captured":
			if uv != null:
				ep._focus(uv)
				fx.floating_text(ep._head(uv), "CAPTURED", Palette.DANGER, 60)
				fx.burst(uv.aim_point(), Vector3.UP, Palette.DANGER, 14, 3.0, true, 0.05)
			view.camera_rig.shake(1.0)
			ep._sfx("alert")
			return {"dur": 0.9}
		"mark_lapsed":
			if uv != null:
				fx.floating_text(ep._head(uv), "MARK LAPSED", Palette.AMBER, 40)
			return {"dur": 0.3}
		"cleansed":
			if uv != null:
				fx.floating_text(ep._head(uv), "-%d INFECTION" % int(ev.get("amount", 0)), Palette.HEAL, 44)
			ep._sfx("heal", -6.0)
			return {"dur": 0.4}
	return {}


static func describe(ev: Dictionary, name_of: Callable) -> String:
	var who := func(key: String) -> String: return "[b]%s[/b]" % name_of.call(int(ev.get(key, -1)))
	var red := Palette.DANGER.to_html(false)
	match str(ev.get("type", "")):
		"chant": return "%s chants (%d allies lifted)" % [who.call("unit"), (ev.get("units", []) as Array).size()]
		"hushed": return "[color=#%s]%s is hushed: class abilities silenced[/color]" % [red, who.call("unit")]
		"captured": return "[color=#%s]%s is dragged off the map[/color]" % [red, who.call("unit")]
		"mark_lapsed": return "%s is no longer designated" % who.call("unit")
		"cleansed": return "%s is cleansed of %d Infection" % [who.call("unit"), int(ev.get("amount", 0))]
	return ""
