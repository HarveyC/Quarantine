extends RefCounted
## View side of the enemy roster (enemies/): animation beats and combat-log lines for the
## enemy events, and placeholder looks (scale, tint, hidden Lurkers) for the new kinds until
## the models workstream gives them their own rigs. Driven only by event data.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

## Placeholder body scale per kind: [width, height], for kinds still without their own
## model (ModelKit.CHARACTERS sizes the rest). Bosses and elites read bigger.
const SCALE := {
	"hive_node": [1.3, 0.7], "egg_sac": [0.9, 0.55], "spore_nest": [1.1, 0.6],
	"source_root": [1.2, 0.9], "the_source": [2.6, 2.2], "drifter": [1.1, 0.7],
}
const ELITE_SCALE := 1.2


const EVENTS: Array[String] = ["spawned", "telegraph", "strike", "cover_destroyed", "spores",
	"reinforcements_incoming", "spore_exposure", "source_pulse", "revealed", "pinned", "released",
	"regenerate", "immune", "untethered", "boss_phase", "boss_defeated", "burrowed", "lock_lost", "fell"]


static func handles(ev: Dictionary) -> bool:
	return EVENTS.has(str(ev.get("type", "")))


## Called by MissionView right after a UnitView is built.
static func dress(uv: Node3D, u: Unit) -> void:
	var sc: Array = SCALE.get(u.kind, [1.0, 1.0])
	var k := ELITE_SCALE if u.status.get("elite", false) else 1.0
	uv.scale = Vector3(sc[0] * k, sc[1] * k, sc[0] * k)
	if u.status.get("hidden", false):
		uv.visible = false
	if u.status.get("flying", false) and uv.get_child_count() > 0:
		(uv.get_child(0) as Node3D).position.y += 1.1   # placeholder: hover above the tile


## A beat for an enemy-module event, or {} if the event isn't one of ours.
static func beat(ep: Node, ev: Dictionary) -> Dictionary:
	var view: Node = ep.view
	var fx = view.fx
	var uv: Node3D = ep._uv(ev) if ev.has("unit") else null
	var head := func(n: Node3D) -> Vector3: return n.position + Vector3(0, 2.0 * n.scale.y, 0)
	match str(ev.get("type", "")):
		"spawned":
			if uv != null:
				uv.visible = true
				fx.puff(uv.position + Vector3(0, 0.3, 0), Palette.TEAL_DIM, 1.0, 0.9, 0.6)
				fx.burst(uv.position + Vector3(0, 0.2, 0), Vector3.UP, Palette.TEAL, 12, 2.0, true, 0.04)
				ep._focus(uv)
			ep._sfx("sting_enemy", -8.0)
			return {"dur": 0.45}
		"telegraph":
			var text := {"burst": "SWELLING", "charge": "WINDING UP", "airstrike": "AIRSTRIKE CALLED", "core_slam": "THE CORE RISES",
				"leap": "CROUCHING TO LEAP", "snipe": "LASER SIGHT", "erupt": "TUNNELLING"}
			if uv != null:
				fx.floating_text(head.call(uv), text.get(ev.get("kind", ""), "DANGER"), Palette.DANGER, 44)
			_flash_cells(fx, ev.get("cells", []), Palette.DANGER)
			ep._sfx("alert", -6.0)
			return {"dur": 0.6}
		"strike":
			for c in ev.get("cells", []):
				var w := Board.cell_to_world(c)
				fx.burst(w + Vector3(0, 0.2, 0), Vector3.UP, Palette.AMBER if ev.get("kind") == "airstrike" else Palette.TEAL, 6, 4.0, true, 0.05)
			if not (ev.get("cells", []) as Array).is_empty():
				var mid := Board.cell_to_world(ev.cells[ev.cells.size() / 2])
				fx.flash_light(mid + Vector3(0, 1.0, 0), Palette.AMBER, 8.0, 0.35, 6.0)
			view.camera_rig.shake(1.0)
			ep._sfx("breach")
			return {"dur": 0.8}
		"cover_destroyed":
			view.board.rebuild_tiles()
			for c in ev.get("cells", []):
				fx.puff(Board.cell_to_world(c) + Vector3(0, 0.3, 0), Color(0.5, 0.48, 0.42), 0.8, 0.8, 0.5)
			ep._sfx("concrete")
			return {"dur": 0.3}
		"spores", "reinforcements_incoming":
			_refresh_overlay(view)
			if ev.type == "reinforcements_incoming":
				_flash_cells(fx, ev.get("cells", []), Palette.AMBER)
				view.hud.banner("REINFORCEMENTS NEXT TURN", Palette.DANGER)
				return {"dur": 0.7}
			return {}
		"spore_exposure", "source_pulse":
			var ids: Array = ev.get("units", [ev.get("unit", -1)]) if ev.type == "source_pulse" else [ev.get("unit", -1)]
			for id in ids:
				var sv: Node3D = view.view_for(int(id))
				if sv != null:
					fx.puff(sv.position + Vector3(0, 0.5, 0), Palette.TEAL_DIM, 0.7, 0.8, 0.5)
			if ev.type == "source_pulse":
				view.hud.banner("THE SOURCE PULSES  +%d INFECTION" % int(ev.get("amount", 0)), Palette.TEAL)
			ep._sfx("infect", -6.0)
			return {"dur": 0.5}
		"revealed":
			if uv != null:
				uv.visible = true
				fx.floating_text(head.call(uv), "LURKER!", Palette.DANGER, 56)
				ep._focus(uv)
			ep._sfx("alert")
			return {"dur": 0.6}
		"burrowed":
			if uv != null:
				fx.puff(uv.position + Vector3(0, 0.2, 0), Color(0.45, 0.4, 0.33), 1.0, 0.8, 0.3)
				uv.visible = false
			ep._sfx("concrete")
			return {"dur": 0.5}
		"lock_lost":
			if uv != null:
				fx.floating_text(head.call(uv), "LOST THE SHOT", Color(0.8, 0.82, 0.8), 40)
			return {"dur": 0.3}
		"fell":
			if uv != null:
				fx.floating_text(head.call(uv), "FELL", Palette.DANGER, 48)
				uv.hit_react(uv.position + Vector3(0, 1, 0), 1.0)
			return {"dur": 0.4}
		"pinned", "released":
			if uv != null:
				fx.floating_text(head.call(uv), "PINNED" if ev.type == "pinned" else "FREED", Palette.DANGER if ev.type == "pinned" else Palette.AMBER, 48)
			return {"dur": 0.5}
		"regenerate":
			if uv != null:
				fx.floating_text(head.call(uv), "+%d" % int(ev.get("healed", 0)), Palette.TEAL, 52)
				uv.set_hp(int(ev.get("hp", 0)))
			return {"dur": 0.4}
		"immune":
			if uv != null:
				fx.floating_text(head.call(uv), "IMMUNE", Color(0.8, 0.82, 0.8), 48)
				fx.pulse(uv.position, Palette.TEAL)
			return {"dur": 0.4}
		"untethered":
			if uv != null:
				fx.floating_text(head.call(uv), "TETHER BROKEN", Palette.AMBER, 44)
			return {"dur": 0.5}
		"boss_phase":
			if uv != null:
				ep._focus(uv)
				uv.scale *= 1.15
				if ev.has("max_hp"):
					uv.max_hp = int(ev.max_hp)
					uv.set_hp(int(ev.get("hp", 0)))
				fx.burst(uv.position + Vector3(0, 1.0, 0), Vector3.UP, Palette.TEAL, 30, 4.0, true, 0.06)
			view.hud.banner(str(ev.get("text", "THE BOSS CHANGES")).to_upper(), Palette.DANGER)
			view.camera_rig.shake(1.2)
			ep._sfx("mutation")
			return {"dur": 1.4}
		"boss_defeated":
			view.hud.banner("%s IS DOWN" % view.unit_name(int(ev.get("unit", -1))).to_upper(), Palette.AMBER)
			ep._sfx("victory", -4.0)
			return {"dur": 1.2}
	return {}


## Combat-log line for an enemy-module event, or "".
static func describe(ev: Dictionary, name_of: Callable) -> String:
	var who := func(key: String) -> String: return "[b]%s[/b]" % name_of.call(int(ev.get(key, -1)))
	var red := Palette.DANGER.to_html(false)
	match str(ev.get("type", "")):
		"spawned": return "%s emerges" % who.call("unit")
		"telegraph": return "[color=#%s]%s: %s next turn[/color]" % [red, who.call("unit"), str(ev.get("kind", "")).replace("_", " ")]
		"strike": return "[color=#%s]%s lands[/color]" % [red, str(ev.get("kind", "strike")).replace("_", " ").capitalize()]
		"cover_destroyed": return "Cover destroyed"
		"spores": return "Spores spread"
		"spore_exposure": return "%s breathes spores (+%d Infection)" % [who.call("unit"), int(ev.get("amount", 0))]
		"source_pulse": return "The Source pulses (+%d Infection to the squad)" % int(ev.get("amount", 0))
		"reinforcements_incoming": return "[color=#%s]Reinforcements arrive next turn (%d)[/color]" % [red, int(ev.get("count", 0))]
		"revealed": return "[color=#%s]%s was hiding![/color]" % [red, who.call("unit")]
		"pinned": return "[color=#%s]%s is pinned by %s[/color]" % [red, who.call("unit"), who.call("by")]
		"released": return "%s breaks free" % who.call("unit")
		"regenerate": return "%s regenerates %d" % [who.call("unit"), int(ev.get("healed", 0))]
		"immune": return "%s is immune (tethered)" % who.call("unit")
		"untethered": return "%s is no longer tethered" % who.call("unit")
		"boss_phase": return "[color=#%s]%s[/color]" % [red, str(ev.get("text", "The boss changes"))]
		"burrowed": return "%s burrows underground" % who.call("unit")
		"lock_lost": return "%s loses its target" % who.call("unit")
		"fell": return "[color=#%s]%s falls off the ledge (%d)[/color]" % [red, who.call("unit"), int(ev.get("damage", 0))]
		"boss_defeated": return "[b]%s is defeated[/b]" % name_of.call(int(ev.get("unit", -1)))
	return ""


static func _flash_cells(fx, cells: Array, color: Color) -> void:
	for c in cells:
		fx.pulse(Board.cell_to_world(c), color, 0.9)


static func _refresh_overlay(view: Node) -> void:
	var ov: Node = view.get_node_or_null("World/IntentOverlay")
	if ov != null:
		ov.refresh()
