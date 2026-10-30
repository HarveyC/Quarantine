extends RefCounted
## Line icons drawn with CanvasItem primitives on a 24x24 grid, so the HUD needs no
## image assets. draw() scales the grid into `rect`.

const IconArt := preload("res://ui/icon_art.gd")

const CLASS_ICON := {"trooper": "trooper", "marksman": "marksman", "medic": "medic", "breacher": "breacher",
	"hazmat": "hazmat", "vector": "vector", "reaper": "reaper", "warden": "warden"}
const ABILITY_ICON := {"suppress": "suppress", "tag": "tag", "stim": "medic", "breach": "breach",
	"incinerate": "incinerate", "siphon": "siphon", "lunge": "lunge", "bash": "bash", "swap_weapon": "reload", "guard": "guard", "shield_charge": "shield_charge",
	"item:frag_grenade": "grenade", "item:demo_charge": "charge",
	"item:smoke_grenade": "smoke", "item:flashbang": "flash", "item:medkit": "medic", "item:stim": "medic",
	"item:suppressant_shot": "purge", "item:antiviral_dose": "purge", "item:breather_mask": "cure", "item:recon_drone": "drone", "gear:flare_launcher": "tag",
	"gear:concussion_launcher": "suppress", "gear:thermite_charge": "incinerate", "gear:med_injector": "purge",
	"gear:adrenal_pump": "mutation", "gear:deployable_cover": "cover_half", "gear:grapple": "move",
	"gear:containment_emitter": "cure", "gear:sentry_turret": "overwatch", "item:containment_foam": "lock",
	"bloom_claw": "bloom_claw", "runner_leap": "runner_leap",
	"lockdown": "lockdown", "deadeye": "deadeye", "quarantine_field": "quarantine_field", "bring_down": "bring_down",
	"flashover": "flashover", "vent": "vent", "death_sweep": "death_sweep", "provoke": "provoke"}


static func for_class(kind: String) -> String:
	return CLASS_ICON.get(kind, "enemy")


static func for_action(a: Dictionary) -> String:
	if a.get("mutation", false):
		return "mutation"
	match str(a.get("key", "")):
		"shoot":
			return "shoot"
		"overwatch":
			return "overwatch"
		"hunker":
			return "hunker"
		"reload":
			return "reload"
		"struggle":
			return "pinned"
	return ABILITY_ICON.get(str(a.get("id", "")), "ability")


## Art replaces the line glyphs from 12px up. It is trimmed to its drawing, so it is drawn a
## little larger than the 24-grid glyphs' rect (which carry a margin) and fitted by aspect.
const ART_MIN := 12.0
const ART_SCALE := 1.25


static func draw(ci: CanvasItem, id: String, rect: Rect2, color: Color, width := 2.0) -> void:
	if minf(rect.size.x, rect.size.y) >= ART_MIN:
		var art := IconArt.vocab(id)
		if art != null:
			var box := rect.size * ART_SCALE
			var k := minf(box.x / art.get_width(), box.y / art.get_height())
			var sz := Vector2(art.get_size()) * k
			ci.draw_texture_rect(art, Rect2(rect.get_center() - sz * 0.5, sz), false, color)
			return
	var s := minf(rect.size.x, rect.size.y) / 24.0
	var o := rect.position + (rect.size - Vector2(24, 24) * s) * 0.5
	var w := width
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(o + Vector2(p[0], p[1]) * s)
		return out
	var line := func(pts: Array) -> void:
		ci.draw_polyline(P.call(pts), color, w, true)
	var circle := func(cx: float, cy: float, r: float) -> void:
		ci.draw_arc(o + Vector2(cx, cy) * s, r * s, 0, TAU, 32, color, w, true)
	var dot := func(cx: float, cy: float, r: float) -> void:
		ci.draw_circle(o + Vector2(cx, cy) * s, r * s, color)
	var arc := func(cx: float, cy: float, r: float, a0: float, a1: float) -> void:
		ci.draw_arc(o + Vector2(cx, cy) * s, r * s, a0, a1, 24, color, w, true)
	match id:
		"trooper":
			line.call([[5, 13], [12, 8], [19, 13]])
			line.call([[5, 19], [12, 14], [19, 19]])
		"marksman":
			circle.call(12, 12, 7)
			line.call([[12, 2], [12, 7]])
			line.call([[12, 17], [12, 22]])
			line.call([[2, 12], [7, 12]])
			line.call([[17, 12], [22, 12]])
		"medic":
			line.call([[9, 3], [15, 3], [15, 9], [21, 9], [21, 15], [15, 15], [15, 21], [9, 21], [9, 15], [3, 15], [3, 9], [9, 9], [9, 3]])
		"breacher":
			line.call([[12, 3], [20, 6], [20, 12], [17.5, 17.5], [12, 21], [6.5, 17.5], [4, 12], [4, 6], [12, 3]])
		"reaper":   # a machete, saw teeth along its spine
			line.call([[5, 20], [8, 17]])
			line.call([[7, 21], [10, 18], [6, 14], [3, 17], [7, 21]])
			line.call([[8, 15], [19, 4], [21, 5], [12, 18]])
			line.call([[10, 13], [10.5, 11], [12, 11], [12.5, 9], [14, 9], [14.5, 7], [16, 7]])
		"warden":   # a riot shield with its viewport slit
			line.call([[7, 3], [17, 3], [20, 6], [20, 18], [17, 21], [7, 21], [4, 18], [4, 6], [7, 3]])
			line.call([[8, 8], [16, 8]])
			line.call([[7, 16], [9, 18]])
			line.call([[11, 16], [13, 18]])
			line.call([[15, 16], [17, 18]])
		"lunge":   # a blade thrust forward with speed lines
			line.call([[3, 21], [6, 18]])
			line.call([[5, 16], [9, 20]])
			line.call([[7, 18], [20, 5]])
			line.call([[17, 4], [21, 4], [21, 8]])
			line.call([[3, 10], [8, 10]])
			line.call([[3, 14], [6, 14]])
		"bash":   # a shield face-on, impact marks off its edge
			line.call([[4, 4], [13, 4], [13, 20], [4, 20], [4, 4]])
			line.call([[6, 8], [11, 8]])
			line.call([[16, 7], [20, 4]])
			line.call([[17, 12], [22, 12]])
			line.call([[16, 17], [20, 20]])
		"guard":   # a shield behind a raised bar
			line.call([[6, 3], [18, 3], [18, 13], [12, 21], [6, 13], [6, 3]])
			line.call([[2, 9], [22, 9]])
		"shield_charge":   # a shield moving fast
			line.call([[11, 4], [20, 4], [20, 20], [11, 20], [11, 4]])
			line.call([[13, 8], [18, 8]])
			line.call([[2, 8], [8, 8]])
			line.call([[4, 12], [8, 12]])
			line.call([[2, 16], [8, 16]])
		"enemy":
			line.call([[12, 3], [15.5, 8], [17, 12.5], [16, 16], [12, 18.5], [8, 16], [7, 12.5], [8.5, 8], [12, 3]])
		"shoot":
			line.call([[9, 21], [9, 10], [12, 4], [15, 10], [15, 21], [9, 21]])
			line.call([[9, 16], [15, 16]])
		"overwatch":
			line.call([[2, 12], [5, 8.5], [8.5, 6], [12, 5], [15.5, 6], [19, 8.5], [22, 12], [19, 15.5], [15.5, 18], [12, 19], [8.5, 18], [5, 15.5], [2, 12]])
			circle.call(12, 12, 3)
		"reload":
			line.call([[8, 3], [16, 3], [16, 15], [8, 15], [8, 3]])
			line.call([[8, 7], [16, 7]])
			arc.call(12, 18, 4, 0.0, PI)
			line.call([[6.5, 17], [8, 19.5], [10.5, 18.5]])
		"hunker":
			line.call([[3, 20], [21, 20]])
			line.call([[6, 20], [6, 14]])
			line.call([[18, 20], [18, 14]])
			arc.call(12, 14, 6, PI, TAU)
		"tag":
			line.call([[3, 12], [3, 3], [12, 3], [21, 12], [12, 21], [3, 12]])
			circle.call(7.5, 7.5, 1.5)
		"suppress":
			for y in [7, 12, 17]:
				line.call([[3, y], [6, y - 2], [9, y], [12, y + 2], [15, y], [18, y - 2], [21, y]])
		"breach":
			line.call([[4, 21], [4, 3], [14, 3], [14, 21]])
			line.call([[17, 8], [21, 6]])
			line.call([[17, 12], [22, 12]])
			line.call([[17, 16], [21, 18]])
		"barrel":   # a fuel drum with its hazard band, in the sights
			line.call([[7, 6], [17, 6], [17, 21], [7, 21], [7, 6]])
			line.call([[7, 11], [17, 11]])
			line.call([[7, 14], [17, 14]])
			line.call([[19, 3], [22, 3], [22, 6]])
			line.call([[2, 6], [2, 3], [5, 3]])
		"grenade":   # a frag body, lever and pin ring
			circle.call(11, 14, 6.5)
			line.call([[9, 7.5], [9, 5], [15, 5], [15, 7.5]])
			line.call([[15, 5], [19, 9]])
			circle.call(19.5, 4, 2)
		"charge":   # a block charge on a wall with its timer
			line.call([[3, 3], [3, 21]])
			line.call([[6, 8], [18, 8], [18, 18], [6, 18], [6, 8]])
			circle.call(12, 13, 2.5)
			line.call([[18, 11], [22, 9]])
		"mutation":
			circle.call(12, 7, 3.5)
			circle.call(7, 15.5, 3.5)
			circle.call(17, 15.5, 3.5)
		"ability":
			circle.call(12, 14, 6)
			line.call([[10, 8], [10, 5], [14, 5], [14, 8]])
		"flag":
			line.call([[5, 21], [5, 4], [16, 4], [14, 8], [16, 12], [5, 12]])
		"check":
			line.call([[4, 12], [9, 17], [20, 6]])
		"clock":
			circle.call(12, 12, 8)
			line.call([[12, 8], [12, 12], [15, 14]])
		"smoke":   # a canister under a rolling cloud
			arc.call(8, 10, 4, PI * 0.6, PI * 1.9)
			arc.call(14, 7.5, 4.5, PI * 1.05, PI * 2.1)
			arc.call(18, 11.5, 3.5, PI * 1.5, PI * 2.6)
			line.call([[4.5, 13], [20.5, 13]])
			line.call([[9, 15], [15, 15], [15, 21], [9, 21], [9, 15]])
		"flash":   # a starburst
			for k in 8:
				var a := TAU * k / 8.0
				var r0 := 3.5
				var r1 := 10.0 if k % 2 == 0 else 7.0
				line.call([[12 + cos(a) * r0, 12 + sin(a) * r0], [12 + cos(a) * r1, 12 + sin(a) * r1]])
			dot.call(12, 12, 2)
		"pinned":   # three claw rakes coming down onto a figure's ground line
			line.call([[6, 3], [8.5, 10], [7, 16]])
			line.call([[12, 2], [13, 9.5], [11.5, 16]])
			line.call([[18, 3], [17.5, 10], [16, 16]])
			line.call([[3.5, 20.5], [20.5, 20.5]])
		"stun":   # a jagged bolt
			line.call([[14, 2.5], [7, 13], [12, 13], [9, 21.5], [17, 10], [12, 10], [14, 2.5]])
		"drone":   # four rotors round a body
			line.call([[7, 7], [17, 17]])
			line.call([[17, 7], [7, 17]])
			for c in [[6, 6], [18, 6], [6, 18], [18, 18]]:
				circle.call(c[0], c[1], 3)
			dot.call(12, 12, 2.4)
		"concealed":   # a closed eye, lashes down, struck through
			line.call([[2, 11], [6, 14.5], [12, 16], [18, 14.5], [22, 11]])
			line.call([[6, 14.5], [4.5, 17.5]])
			line.call([[12, 16], [12, 19.5]])
			line.call([[18, 14.5], [19.5, 17.5]])
			line.call([[4, 4], [20, 20]])
		"detected":   # a wide-open eye
			line.call([[1.5, 12], [6, 7], [12, 5.5], [18, 7], [22.5, 12], [18, 17], [12, 18.5], [6, 17], [1.5, 12]])
			dot.call(12, 12, 3.6)
		"alert":
			circle.call(12, 12, 9)
			line.call([[12, 7], [12, 13]])
			dot.call(12, 16.5, 1.2)
		"dot":
			dot.call(12, 12, 10)
		# Co-op pings (coop/marks.gd).
		"ping":   # a map pin over a ripple
			line.call([[12, 16], [8, 11.5], [7.2, 8.5], [8.5, 5], [12, 3.5], [15.5, 5], [16.8, 8.5], [16, 11.5], [12, 16]])
			circle.call(12, 8.5, 1.8)
			line.call([[5, 18.5], [8, 20], [12, 20.5], [16, 20], [19, 18.5]])
		"move":   # a chevron coming down onto a ground ring
			line.call([[7, 4], [12, 9], [17, 4]])
			line.call([[7, 9], [12, 14], [17, 9]])
			line.call([[3, 18], [6, 16], [12, 15.2], [18, 16], [21, 18], [18, 20], [12, 20.8], [6, 20], [3, 18]])
		"attack":   # a reticle with a strike through it
			circle.call(12, 12, 7.5)
			line.call([[12, 1.5], [12, 6]])
			line.call([[12, 18], [12, 22.5]])
			line.call([[1.5, 12], [6, 12]])
			line.call([[18, 12], [22.5, 12]])
			line.call([[9, 15], [15, 9]])
		"danger":   # a warning triangle
			line.call([[12, 3], [22, 20.5], [2, 20.5], [12, 3]])
			line.call([[12, 9], [12, 14.5]])
			dot.call(12, 17.5, 1.2)
		"draw":   # a marker pen and its stroke
			line.call([[14, 4], [20, 10], [10, 20], [5.5, 20], [4, 18.5], [4, 14], [14, 4]])
			line.call([[11.5, 6.5], [17.5, 12.5]])
			line.call([[3, 22], [9, 22]])
		"cover_half":
			line.call([[3, 20], [21, 20]])
			line.call([[6, 20], [6, 14], [18, 14], [18, 20]])
		# Run map node types and currencies.
		"skirmish":
			line.call([[4, 4], [17, 17]])
			line.call([[20, 4], [7, 17]])
			line.call([[14, 20], [20, 14]])
			line.call([[4, 14], [10, 20]])
		"ambush":
			line.call([[4, 4], [17, 17]])
			line.call([[14, 20], [20, 14]])
			line.call([[17, 3], [17, 9]])
			dot.call(17, 12.5, 1.2)
		"nest":
			circle.call(12, 7, 3.5)
			circle.call(7, 15.5, 3.5)
			circle.call(17, 15.5, 3.5)
			dot.call(12, 12.5, 1.3)
		"depot":
			line.call([[3, 8], [12, 3], [21, 8], [21, 17], [12, 22], [3, 17], [3, 8]])
			line.call([[3, 8], [12, 13], [21, 8]])
			line.call([[12, 13], [12, 22]])
		"hospital":
			line.call([[3, 6], [21, 6], [21, 20], [3, 20], [3, 6]])
			line.call([[12, 9], [12, 17]])
			line.call([[8, 13], [16, 13]])
			line.call([[9, 6], [9, 3], [15, 3], [15, 6]])
		"survivors":
			circle.call(8.5, 7.5, 3)
			arc.call(8.5, 20, 6, PI, TAU)
			circle.call(16.5, 9, 2.5)
			arc.call(16.5, 20, 4.5, PI, TAU)
		"boss":
			line.call([[5, 11], [5, 8], [8, 4], [16, 4], [19, 8], [19, 11], [16, 15], [16, 20], [8, 20], [8, 15], [5, 11]])
			dot.call(9.5, 10.5, 1.8)
			dot.call(14.5, 10.5, 1.8)
			line.call([[11, 17], [11, 20]])
			line.call([[13, 17], [13, 20]])
		"event":
			line.call([[12, 3], [12, 15]])
			dot.call(12, 20, 1.6)
		"unknown":
			line.call([[7.5, 8], [8.5, 5], [12, 3.5], [15.5, 5], [16.5, 8], [15, 11], [12, 13], [12, 16]])
			dot.call(12, 20.5, 1.6)
		"supplies":
			line.call([[3, 8], [21, 8], [21, 20], [3, 20], [3, 8]])
			line.call([[5, 4], [19, 4], [21, 8]])
			line.call([[5, 4], [3, 8]])
			line.call([[10, 12], [14, 12]])
		"intel":
			line.call([[6, 3], [15, 3], [19, 7], [19, 21], [6, 21], [6, 3]])
			line.call([[9, 11], [16, 11]])
			line.call([[9, 15], [16, 15]])
		"serum":
			line.call([[9, 3], [15, 3]])
			line.call([[10, 3], [10, 9], [5, 19], [7, 21], [17, 21], [19, 19], [14, 9], [14, 3]])
			line.call([[7.5, 15], [16.5, 15]])
		"outbreak":
			circle.call(12, 12, 4)
			for k in 8:
				var a := k * TAU / 8.0
				var d := Vector2(cos(a), sin(a))
				line.call([[12 + d.x * 6, 12 + d.y * 6], [12 + d.x * 9.5, 12 + d.y * 9.5]])
				dot.call(12 + d.x * 10, 12 + d.y * 10, 1.1)
		# Classes added after the first four.
		"hazmat":
			line.call([[6, 10], [6, 7], [9, 4], [15, 4], [18, 7], [18, 10]])
			line.call([[4, 10], [20, 10], [18, 15], [6, 15], [4, 10]])
			circle.call(9, 18.5, 2.5)
			circle.call(15, 18.5, 2.5)
		"vector":
			for k in 3:
				var y0 := 3.0 + k * 6.5
				line.call([[7, y0], [17, y0 + 3.2], [7, y0 + 6.5]])
			dot.call(17, 6.2, 1.3)
			dot.call(17, 19.2, 1.3)
		# Gear slots.
		"weapon":
			circle.call(12, 12, 7)
			circle.call(12, 12, 2.5)
			line.call([[12, 1.5], [12, 6]])
			line.call([[12, 18], [12, 22.5]])
			line.call([[1.5, 12], [6, 12]])
			line.call([[18, 12], [22.5, 12]])
		"ammo":
			for bx in [6.5, 12, 17.5]:
				line.call([[bx - 2, 21], [bx - 2, 9], [bx, 4], [bx + 2, 9], [bx + 2, 21], [bx - 2, 21]])
		"armor", "body", "head", "offhand":
			line.call([[12, 3], [20, 6], [20, 12], [17.5, 17.5], [12, 21], [6.5, 17.5], [4, 12], [4, 6], [12, 3]])
			line.call([[12, 7], [12, 17]])
		"gadget", "utility", "utility2", "consumable":
			line.call([[12, 2.5], [20.5, 7.25], [20.5, 16.75], [12, 21.5], [3.5, 16.75], [3.5, 7.25], [12, 2.5]])
			line.call([[13, 6.5], [9.5, 12.5], [14.5, 12.5], [11, 18]])
		# Menus.
		"solo":
			circle.call(12, 7.5, 3.5)
			arc.call(12, 21, 7.5, PI, TAU)
		"coop":
			circle.call(8, 8, 3)
			arc.call(8, 20, 6, PI, TAU)
			circle.call(16.5, 8, 3)
			arc.call(16.5, 20, 6, PI, 1.75 * PI)
		"online":
			circle.call(12, 12, 9)
			line.call([[3, 12], [21, 12]])
			line.call([[12, 3], [9, 7], [8, 12], [9, 17], [12, 21]])
			line.call([[12, 3], [15, 7], [16, 12], [15, 17], [12, 21]])
		"hotseat":
			line.call([[3, 5], [21, 5], [21, 16], [3, 16], [3, 5]])
			line.call([[9, 20], [15, 20]])
			line.call([[12, 16], [12, 20]])
			circle.call(9, 10.5, 1.8)
			circle.call(15, 10.5, 1.8)
		"join":
			line.call([[13, 4], [20, 4], [20, 20], [13, 20]])
			line.call([[3, 12], [15, 12]])
			line.call([[11, 8], [15, 12], [11, 16]])
		"leave":
			line.call([[11, 4], [4, 4], [4, 20], [11, 20]])
			line.call([[9, 12], [21, 12]])
			line.call([[17, 8], [21, 12], [17, 16]])
		"continue":
			line.call([[6, 4], [18, 12], [6, 20], [6, 4]])
		"play":
			line.call([[7, 4], [19, 12], [7, 20], [7, 4]])
		"pause":
			line.call([[8, 5], [8, 19]])
			line.call([[16, 5], [16, 19]])
		"quick":
			line.call([[13, 2], [5, 13], [11, 13], [10, 22], [19, 10], [13, 10], [13, 2]])
		"settings":
			circle.call(12, 12, 3.5)
			for k in 8:
				var a := k * TAU / 8.0 + TAU / 16.0
				var d := Vector2(cos(a), sin(a))
				line.call([[12 + d.x * 6.5, 12 + d.y * 6.5], [12 + d.x * 9.5, 12 + d.y * 9.5]])
			circle.call(12, 12, 6.5)
		"sound", "master":
			line.call([[3, 9], [7, 9], [12, 4], [12, 20], [7, 15], [3, 15], [3, 9]])
			arc.call(12, 12, 5, -0.9, 0.9)
			arc.call(12, 12, 9, -0.9, 0.9)
		"mute":
			line.call([[3, 9], [7, 9], [12, 4], [12, 20], [7, 15], [3, 15], [3, 9]])
			line.call([[15, 9], [21, 15]])
			line.call([[21, 9], [15, 15]])
		"music":
			line.call([[9, 18], [9, 4], [20, 2], [20, 16]])
			circle.call(6.5, 18, 2.5)
			circle.call(17.5, 16, 2.5)
			line.call([[9, 8], [20, 6]])
		"ambience":
			line.call([[3, 9], [6, 7], [9, 9], [12, 11], [15, 9], [18, 7], [21, 9]])
			line.call([[3, 15], [6, 13], [9, 15], [12, 17], [15, 15], [18, 13], [21, 15]])
		"effects":
			line.call([[12, 3], [14, 10], [21, 12], [14, 14], [12, 21], [10, 14], [3, 12], [10, 10], [12, 3]])
		"interface":
			line.call([[6, 3], [6, 18], [10, 14.5], [13, 21], [15.5, 20], [12.5, 13.5], [18, 13.5], [6, 3]])
		"keyboard":
			line.call([[2, 6], [22, 6], [22, 18], [2, 18], [2, 6]])
			for x in [6, 10, 14, 18]:
				dot.call(x, 10, 1.1)
			line.call([[7, 14], [17, 14]])
		"close", "cross":
			line.call([[5, 5], [19, 19]])
			line.call([[19, 5], [5, 19]])
		"copy":
			line.call([[8, 8], [20, 8], [20, 21], [8, 21], [8, 8]])
			line.call([[4, 16], [4, 3], [16, 3]])
		"plus":
			line.call([[12, 4], [12, 20]])
			line.call([[4, 12], [20, 12]])
		"minus":
			line.call([[4, 12], [20, 12]])
		"arrow_right":
			line.call([[4, 12], [20, 12]])
			line.call([[14, 6], [20, 12], [14, 18]])
		"arrow_left":
			line.call([[20, 12], [4, 12]])
			line.call([[10, 6], [4, 12], [10, 18]])
		"reveal":
			line.call([[2, 12], [5, 8.5], [8.5, 6], [12, 5], [15.5, 6], [19, 8.5], [22, 12], [19, 15.5], [15.5, 18], [12, 19], [8.5, 18], [5, 15.5], [2, 12]])
			line.call([[10.2, 10.5], [10.8, 9.2], [12, 8.8], [13.2, 9.2], [13.8, 10.5], [12, 12.5], [12, 13.5]])
			dot.call(12, 15.5, 0.9)
		"loadout":
			line.call([[8, 3], [16, 3], [16, 6], [20, 8], [20, 21], [4, 21], [4, 8], [8, 6], [8, 3]])
			line.call([[4, 12], [20, 12]])
			line.call([[10, 12], [10, 15], [14, 15], [14, 12]])
		"menu":
			line.call([[4, 6], [20, 6]])
			line.call([[4, 12], [20, 12]])
			line.call([[4, 18], [20, 18]])
		# Stats and effects.
		"health", "heart":
			line.call([[12, 20], [4, 12], [3, 8.5], [4.5, 5.5], [8, 4.5], [12, 7.5], [16, 4.5], [19.5, 5.5], [21, 8.5], [20, 12], [12, 20]])
		"infection":
			circle.call(12, 12, 3)
			for k in 6:
				var a := k * TAU / 6.0
				var d := Vector2(cos(a), sin(a))
				circle.call(12 + d.x * 7.5, 12 + d.y * 7.5, 1.7)
		"kill":
			circle.call(12, 12, 8)
			line.call([[12, 2], [12, 8]])
			line.call([[12, 16], [12, 22]])
			line.call([[2, 12], [8, 12]])
			line.call([[16, 12], [22, 12]])
			dot.call(12, 12, 1.4)
		"wound":
			line.call([[5, 19], [10, 12], [8, 10], [14, 4]])
			line.call([[11, 20], [15, 14], [13, 12.5], [19, 6]])
		"skull":
			line.call([[5, 11], [5, 8], [8, 4], [16, 4], [19, 8], [19, 11], [16, 15], [16, 20], [8, 20], [8, 15], [5, 11]])
			dot.call(9.5, 10.5, 1.8)
			dot.call(14.5, 10.5, 1.8)
		"turned":
			circle.call(12, 9, 5)
			line.call([[12, 14], [12, 21]])
			line.call([[7, 17], [12, 21], [17, 17]])
			dot.call(10, 8.5, 1.1)
			dot.call(14, 8.5, 1.1)
		"rank":
			line.call([[5, 10], [12, 5], [19, 10]])
			line.call([[5, 15], [12, 10], [19, 15]])
			line.call([[5, 20], [12, 15], [19, 20]])
		"perk", "star":
			line.call([[12, 3], [14.6, 9], [21, 9.4], [16, 13.6], [17.6, 20], [12, 16.5], [6.4, 20], [8, 13.6], [3, 9.4], [9.4, 9], [12, 3]])
		"route":
			circle.call(5, 18, 2.2)
			circle.call(19, 6, 2.2)
			line.call([[7, 17], [11, 15], [9, 11], [13, 9], [17, 7]])
		"turn":
			arc.call(12, 12, 8, -PI * 0.5, PI * 1.25)
			line.call([[3.5, 7], [6.3, 6.4], [6, 3.5]])
		"vote":
			line.call([[4, 10], [20, 10], [20, 21], [4, 21], [4, 10]])
			line.call([[8, 14], [16, 14]])
			line.call([[9, 10], [9, 3], [15, 3], [15, 10]])
		"cart", "buy":
			line.call([[2, 4], [5, 4], [8, 16], [19, 16], [21, 8], [6.2, 8]])
			circle.call(9, 19.5, 1.6)
			circle.call(18, 19.5, 1.6)
		"reroll":
			arc.call(12, 12, 7.5, PI * 0.1, PI * 1.6)
			line.call([[15, 3.5], [18.5, 5.5], [16.5, 9]])
			arc.call(12, 12, 7.5, PI * 1.1, PI * 1.25)
		"sell":
			line.call([[3, 12], [12, 3], [21, 3], [21, 12], [12, 21], [3, 12]])
			line.call([[14, 14], [10, 10]])
			line.call([[10, 14], [14, 14], [14, 10]])
		"recruit":
			circle.call(10, 8, 3.5)
			arc.call(10, 21, 7, PI, TAU)
			line.call([[19, 6], [19, 14]])
			line.call([[15, 10], [23, 10]])
		"patch":
			line.call([[7, 4], [20, 17], [17, 20], [4, 7], [7, 4]])
			dot.call(10.5, 12, 0.9)
			dot.call(12, 10.5, 0.9)
			dot.call(13.5, 12, 0.9)
			dot.call(12, 13.5, 0.9)
		"purge":
			line.call([[12, 3], [17, 11], [18, 15], [16, 19], [12, 21], [8, 19], [6, 15], [7, 11], [12, 3]])
			line.call([[8, 15], [16, 15]])
		"incinerate":
			# A flame over the nozzle.
			line.call([[12, 3], [16, 9], [17, 13], [15, 17], [12, 18], [9, 17], [7, 13], [8, 9], [10, 11], [12, 3]])
			line.call([[12, 11], [14, 14], [12, 16], [10, 14], [12, 11]])
			line.call([[8, 21], [16, 21]])
		"siphon":
			# Infection drawn out of a drop and into the user.
			line.call([[7, 4], [11, 10], [11, 13], [9, 15], [5, 15], [3, 13], [3, 10], [7, 4]])
			line.call([[11, 15], [16, 20], [20, 20]])
			line.call([[17, 17], [20, 20], [17, 23]])
		"lockdown":   # a fire lane: a cone fanning out to a barrier
			line.call([[12, 20], [4, 7]])
			line.call([[12, 20], [20, 7]])
			line.call([[3, 5], [21, 5]])
			line.call([[12, 17], [12, 9]])
			dot.call(12, 12, 1.4)
		"deadeye":   # a crosshair with a hot centre
			circle.call(12, 12, 7)
			line.call([[12, 2], [12, 7]])
			line.call([[12, 17], [12, 22]])
			line.call([[2, 12], [7, 12]])
			line.call([[17, 12], [22, 12]])
			dot.call(12, 12, 1.8)
		"quarantine_field":   # a sealed ring round a cross
			circle.call(12, 12, 9)
			line.call([[12, 8], [12, 16]])
			line.call([[8, 12], [16, 12]])
		"bring_down":   # a wall coming apart onto the ground
			line.call([[3, 21], [21, 21]])
			line.call([[4, 4], [11, 4], [11, 11], [4, 11], [4, 4]])
			line.call([[14, 9], [20, 9], [20, 15], [14, 15], [14, 9]])
			line.call([[8, 14], [8, 18]])
		"flashover":   # a flame bursting outward
			line.call([[12, 7], [15, 11], [16, 14], [14, 17], [12, 18], [10, 17], [8, 14], [9, 11], [12, 7]])
			line.call([[12, 2], [12, 4]])
			line.call([[4, 8], [6, 9]])
			line.call([[20, 8], [18, 9]])
			line.call([[3, 15], [6, 15]])
			line.call([[21, 15], [18, 15]])
		"vent":   # a drop letting go of a spore burst
			circle.call(12, 12, 4)
			line.call([[12, 3], [12, 6]])
			line.call([[12, 18], [12, 21]])
			line.call([[3, 12], [6, 12]])
			line.call([[18, 12], [21, 12]])
			line.call([[6, 6], [8, 8]])
			line.call([[18, 6], [16, 8]])
			line.call([[6, 18], [8, 16]])
			line.call([[18, 18], [16, 16]])
		"death_sweep":   # a blade swinging round in an arc
			arc.call(12, 13, 8, PI * 1.05, PI * 1.95)
			line.call([[20, 13], [17, 10]])
			line.call([[20, 13], [23, 10]])
			line.call([[12, 13], [12, 21]])
		"provoke":   # a shield with a call-out mark
			line.call([[6, 3], [18, 3], [18, 13], [12, 21], [6, 13], [6, 3]])
			line.call([[12, 7], [12, 12]])
			dot.call(12, 15, 1.2)
		"train":
			line.call([[4, 12], [20, 12]])
			line.call([[4, 8], [4, 16]])
			line.call([[7, 6], [7, 18]])
			line.call([[17, 6], [17, 18]])
			line.call([[20, 8], [20, 16]])
		"cure":
			line.call([[9, 3], [15, 3]])
			line.call([[10, 3], [10, 9], [5, 19], [7, 21], [17, 21], [19, 19], [14, 9], [14, 3]])
			line.call([[9, 15.5], [11.5, 18], [15.5, 13]])
		"lock":
			line.call([[5, 11], [19, 11], [19, 21], [5, 21], [5, 11]])
			arc.call(12, 11, 5, PI, TAU)
			dot.call(12, 16, 1.3)
		"doctrine":
			line.call([[4, 4], [20, 4], [20, 16], [12, 21], [4, 16], [4, 4]])
			line.call([[8, 9], [12, 13], [16, 9]])
		"squad":
			circle.call(12, 6.5, 2.6)
			circle.call(5.5, 10, 2.2)
			circle.call(18.5, 10, 2.2)
			arc.call(12, 20, 5.5, PI, TAU)
			arc.call(5.5, 20.5, 4, PI, 1.7 * PI)
			arc.call(18.5, 20.5, 4, 1.3 * PI, TAU)
		"waiting":
			dot.call(6, 12, 1.6)
			dot.call(12, 12, 1.6)
			dot.call(18, 12, 1.6)
		"trophy", "victory":
			line.call([[7, 3], [17, 3], [17, 9], [15, 13], [12, 14], [9, 13], [7, 9], [7, 3]])
			line.call([[7, 5], [3, 5], [4, 9], [7, 10]])
			line.call([[17, 5], [21, 5], [20, 9], [17, 10]])
			line.call([[12, 14], [12, 18]])
			line.call([[7, 21], [17, 21], [16, 18], [8, 18], [7, 21]])
		"lantern":
			line.call([[8, 2.5], [16, 2.5]])
			line.call([[12, 2.5], [12, 5]])
			line.call([[6.5, 7], [17.5, 7], [16.5, 19.5], [7.5, 19.5], [6.5, 7]])
			line.call([[5, 22], [19, 22]])
			var flame := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				flame.append(o + Vector2(12 + cos(a) * 2.6, 13.2 + sin(a) * 3.8) * s)
			ci.draw_colored_polygon(flame, color)
		"bloom":
			circle.call(12, 12, 4)
			for k in 5:
				var a := -PI * 0.5 + TAU * k / 5.0
				var p0 := Vector2(12, 12) + Vector2(cos(a), sin(a)) * 4.0
				var p1 := Vector2(12, 12) + Vector2(cos(a + 0.35), sin(a + 0.35)) * 8.5
				line.call([[p0.x, p0.y], [p1.x, p1.y]])
				dot.call(p1.x, p1.y, 1.4)
		"refit", "graft":   # a hex bolt head in a spanner's jaw
			line.call([[12, 7], [16.3, 9.5], [16.3, 14.5], [12, 17], [7.7, 14.5], [7.7, 9.5], [12, 7]])
			circle.call(12, 12, 1.8)
			line.call([[17, 4], [20, 7]])
			line.call([[18.5, 5.5], [21, 3]])
			line.call([[4, 17], [7, 20]])
			line.call([[3, 21], [5.5, 18.5]])
		"amputate":   # a limb cut across, the cut line dashed
			line.call([[5, 20], [10, 13]])
			line.call([[14, 9], [19, 4]])
			line.call([[3, 18], [7, 22]])
			line.call([[12, 7], [16, 11]])
			for i in 4:
				dot.call(6 + i * 4, 15 - i * 2, 1.0)
		"bloom_claw":   # three hooked claws raking down
			for i in 3:
				var x := 6.0 + i * 5.0
				line.call([[x, 3], [x + 2, 10], [x + 1, 17], [x - 2, 21]])
			dot.call(11, 3, 1.2)
		"runner_leap":   # a jump arc over a low wall
			arc.call(12, 17, 8, PI, TAU)
			line.call([[17, 9], [20, 17], [22, 13]])
			line.call([[10, 21], [14, 21], [14, 17], [10, 17], [10, 21]])
		_:
			circle.call(12, 12, 8)
