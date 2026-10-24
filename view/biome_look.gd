class_name BiomeLook
extends RefCounted
## Per-act look of the tactical map: tile colours, lighting, fog and the props past the
## board's edge. Keyed by Grid.biome ("wall", "port", "bore"); anything else uses "wall".
## Board and MissionView read colours from here; the perimeter and lamp builders for the
## act 2 and 3 biomes live here so the board keeps only the act 1 checkpoint.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

const LOOKS := {
	# Act 1, the cordon checkpoint at night: sodium floodlights, moonlight, chain-link fence.
	"wall": {
		"floor": [Color("3b3d39"), Color("363834"), Color("41423d"), Color("33352f")],
		"wall": Color("24272a"), "trim": Color("3a3f44"), "crate": Color("4d4a35"), "ground": Color("1d1f1c"),
		"deck": Color("8a8f86"),
		"background": Color("07090a"), "ambient": Color("2c3a40"), "ambient_energy": 0.42,
		"fog": Color("131c1d"), "fog_density": 0.018, "volumetric": Color("8a9a90"),
		"moon": Color("8fa3b0"), "moon_energy": 0.35, "rim": Color("2f6f6a"),
		"lamp": Color("ffb767"), "lamp_bulb": Color("ffcf8a"), "lamp_energy": 5.0,
		"saturation": 0.82, "goo_every": 23,
	},
	# Act 2, Port Ardent: wet asphalt and concrete under cold mercury streetlights, lab-white
	# spill from the Halden-Voss blocks, harbour haze.
	"port": {
		"floor": [Color("34383b"), Color("2f3336"), Color("3a3e40"), Color("2c3032")],
		"wall": Color("2b2f35"), "trim": Color("4a525c"), "crate": Color("3f4a52"), "ground": Color("17191c"),
		"deck": Color("7d8790"),
		"background": Color("080a0e"), "ambient": Color("2a3446"), "ambient_energy": 0.46,
		"fog": Color("141a24"), "fog_density": 0.022, "volumetric": Color("8a96a8"),
		"moon": Color("9fb2c8"), "moon_energy": 0.3, "rim": Color("3a4f78"),
		"lamp": Color("cfe3ff"), "lamp_bulb": Color("e4f0ff"), "lamp_energy": 4.2,
		"saturation": 0.78, "goo_every": 19,
	},
	# Act 3, the Bore: raw rock and rusted mine steel in near dark, amber work lamps, and the
	# Bloom everywhere, its teal glow doing most of the lighting.
	"bore": {
		"floor": [Color("2e2a26"), Color("292522"), Color("332e29"), Color("26221f")],
		"wall": Color("2a2420"), "trim": Color("4a3f35"), "crate": Color("4a3a2a"), "ground": Color("120f0d"),
		"deck": Color("6f665a"),
		"background": Color("040505"), "ambient": Color("1c3633"), "ambient_energy": 0.4,
		"fog": Color("0c1716"), "fog_density": 0.03, "volumetric": Color("5aa894"),
		"moon": Color("6d8a86"), "moon_energy": 0.18, "rim": Color("2ef2c8"),
		"lamp": Color("ffa24a"), "lamp_bulb": Color("ffc27a"), "lamp_energy": 4.0,
		"saturation": 0.9, "goo_every": 9,
	},
}


static func of(biome: String) -> Dictionary:
	return LOOKS.get(biome, LOOKS.wall)


## Colours the WorldEnvironment and the two directional lights for `biome`.
static func light(env: Environment, moon: DirectionalLight3D, rim: DirectionalLight3D, biome: String) -> void:
	var look := of(biome)
	env.background_color = look.background
	env.ambient_light_color = look.ambient
	env.ambient_light_energy = look.ambient_energy
	env.fog_light_color = look.fog
	env.fog_density = look.fog_density
	env.volumetric_fog_albedo = look.volumetric
	env.adjustment_saturation = look.saturation
	moon.light_color = look.moon
	moon.light_energy = look.moon_energy
	rim.light_color = look.rim
	if biome == "bore":
		rim.light_energy = 0.45   # the Bloom's glow from below
		rim.rotation_degrees = Vector3(-12, 150, 0)


# ---------------------------------------------------------------- Port Ardent

## Apartment and lab facades along the board's edge, lit windows, and a harbour crane.
static func build_port_perimeter(parent: Node3D, grid: Grid) -> void:
	var concrete := [Board.grimy(Color("3b4048"), 0.9, 0.25), Board.grimy(Color("4a4640"), 0.9, 0.25),
		Board.grimy(Color("2f353d"), 0.9, 0.25)]
	var window_lit := Palette.emissive(Color("ffd9a0"), 1.6)
	var window_lab := Palette.emissive(Color("bfe6ff"), 2.0)
	var window_dark := Palette.mat(Color("12161b"), 0.2, 0.6)
	var w := float(grid.width)
	var h := float(grid.height)
	# Rows of blocks on the far side and the two flanks; the near side stays open for the camera.
	var rows := [[Vector3(-2.5, 0, -3.8), Vector3(1, 0, 0), w + 4.0], [Vector3(-3.8, 0, -2.5), Vector3(0, 0, 1), h + 4.0],
		[Vector3(w + 2.8, 0, -2.5), Vector3(0, 0, 1), h + 4.0]]
	var n := 0
	for row in rows:
		var start: Vector3 = row[0]
		var along: Vector3 = row[1]
		var length: float = row[2]
		var x := 0.0
		while x < length:
			var bw := 2.5 + float((n * 7) % 4)
			# Two or three storeys: tall enough to read as a street, low enough not to hide the board.
			var bh := 2.8 + float((n * 5) % 3) * 1.2
			var size := along * bw + Vector3(0, bh, 0) + (Vector3(0, 0, 2.5) if along.x != 0 else Vector3(2.5, 0, 0))
			var block := Palette.box(size, concrete[n % concrete.size()])
			var centre := start + along * (x + bw * 0.5)
			block.position = centre + Vector3(0, bh * 0.5, 0)
			parent.add_child(block)
			# Windows on the face toward the board, one floor every 1.4 m.
			var inward := Vector3(0, 0, 1.26) if along.x != 0 else (Vector3(1.26, 0, 0) if start.x < 0 else Vector3(-1.26, 0, 0))
			for fy in range(1, int(bh / 1.4)):
				for fx in int(bw / 1.1):
					var k := (n * 31 + fy * 7 + fx * 3) % 9
					var m: Material = window_dark if k < 5 else (window_lab if k == 8 else window_lit)
					var win := Palette.box(Vector3(0.5, 0.6, 0.02) if along.x != 0 else Vector3(0.02, 0.6, 0.5), m)
					win.position = centre + inward + along * (-bw * 0.5 + 0.55 + fx * 1.1) + Vector3(0, fy * 1.4, 0)
					parent.add_child(win)
			x += bw + 0.3
			n += 1
	_add_crane(parent, Vector3(w + 6.0, 0, -6.0))
	# Tram wires overhead across the board.
	var wire := Palette.mat(Color("15181b"), 0.4, 0.8)
	for i in 3:
		var cable := Palette.box(Vector3(w + 6.0, 0.03, 0.03), wire)
		cable.position = Vector3(w * 0.5 - 0.5, 6.5, 2.0 + i * (h - 4.0) / 2.0)
		parent.add_child(cable)


static func _add_crane(parent: Node3D, base: Vector3) -> void:
	var steel := Palette.mat(Color("8a5a2a"), 0.6, 0.5)
	var mast := Palette.box(Vector3(0.8, 14.0, 0.8), steel)
	mast.position = base + Vector3(0, 7.0, 0)
	parent.add_child(mast)
	var jib := Palette.box(Vector3(14.0, 0.6, 0.6), steel)
	jib.position = base + Vector3(-5.0, 14.0, 0)
	parent.add_child(jib)
	var cab := Palette.box(Vector3(1.4, 1.2, 1.2), Palette.mat(Color("3a3f44"), 0.6, 0.4))
	cab.position = base + Vector3(0.6, 13.2, 0)
	parent.add_child(cab)
	var warn := Palette.box(Vector3(0.2, 0.2, 0.2), Palette.emissive(Palette.DANGER, 6.0))
	warn.position = base + Vector3(-11.8, 14.4, 0)
	parent.add_child(warn)


## Cold streetlights on poles along the flanks, arms reaching over the board.
static func build_port_lights(parent: Node3D, grid: Grid) -> void:
	var look := of("port")
	var pole_mat := Palette.mat(Color("2d3033"), 0.5, 0.7)
	var bulb_mat := Palette.emissive(look.lamp_bulb, 3.0)
	var w := float(grid.width)
	var h := float(grid.height)
	var spots := [Vector3(-1.8, 0, 2.0), Vector3(-1.8, 0, h * 0.6), Vector3(w + 0.8, 0, h * 0.3), Vector3(w + 0.8, 0, h - 2.0),
		Vector3(w * 0.5, 0, -2.0)]
	for i in spots.size():
		var base: Vector3 = spots[i]
		var reach := Vector3(1.6, 0, 0) if base.x < 0 else (Vector3(-1.6, 0, 0) if base.x > w else Vector3(0, 0, 1.6))
		var pole := Palette.box(Vector3(0.12, 6.0, 0.12), pole_mat)
		pole.position = base + Vector3(0, 3.0, 0)
		parent.add_child(pole)
		var arm := Palette.box(Vector3(absf(reach.x) + 0.1, 0.08, absf(reach.z) + 0.1), pole_mat)
		arm.position = base + reach * 0.5 + Vector3(0, 6.0, 0)
		parent.add_child(arm)
		var head := Palette.box(Vector3(0.45, 0.12, 0.3), bulb_mat)
		head.position = base + reach + Vector3(0, 5.9, 0)
		parent.add_child(head)
		var spot := SpotLight3D.new()
		spot.light_color = look.lamp
		spot.light_energy = look.lamp_energy
		spot.spot_range = 14.0
		spot.spot_angle = 44.0
		spot.spot_attenuation = 0.7
		spot.shadow_enabled = i < 3
		spot.position = head.position + Vector3(0, -0.1, 0)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		parent.add_child(spot)
	# Lab-white spill from a doorway, and a Halden-Voss sign.
	var lab := OmniLight3D.new()
	lab.light_color = Color("bfe6ff")
	lab.light_energy = 1.4
	lab.omni_range = 6.0
	lab.position = Vector3(w * 0.25, 2.0, -1.8)
	parent.add_child(lab)
	var sign := Palette.box(Vector3(3.0, 0.5, 0.05), Palette.emissive(Color("2ec4f2"), 2.4))
	sign.position = Vector3(w * 0.25, 3.6, -2.2)
	parent.add_child(sign)


# ---------------------------------------------------------------- The Bore

## Rough rock walls around the gallery, timber shoring, Bloom veins, and the shaft beyond.
static func build_bore_perimeter(parent: Node3D, grid: Grid) -> void:
	var rocks := [Board.grimy(Color("2f2924"), 1.0, 0.6), Board.grimy(Color("3a322b"), 1.0, 0.6), Board.grimy(Color("26211d"), 1.0, 0.6)]
	var timber := Board.grimy(Color("4a3a28"), 0.95, 0.5)
	var vein := Palette.emissive(Palette.TEAL, 2.2)
	var w := float(grid.width)
	var h := float(grid.height)
	var ring: Array[Vector3] = []
	var step := 1.6
	var x := -2.0
	while x <= w + 1.0:
		ring.append(Vector3(x, 0, -2.8))
		x += step
	var z := -2.0
	while z <= h + 1.0:
		ring.append(Vector3(-2.8, 0, z))
		ring.append(Vector3(w + 1.8, 0, z))
		z += step
	for i in ring.size():
		var k := (i * 2654435761) & 0xffff
		var size := Vector3(1.6 + (k % 7) * 0.2, 3.0 + (k % 11) * 0.45, 1.6 + ((k >> 4) % 7) * 0.2)
		var rock := Palette.box(size, rocks[k % rocks.size()])
		rock.position = ring[i] + Vector3(0, size.y * 0.5 - 0.2, 0)
		rock.rotation = Vector3(((k >> 3) % 9 - 4) * 0.04, (k % 13) * 0.24, ((k >> 6) % 9 - 4) * 0.04)
		parent.add_child(rock)
		if k % 5 == 0:
			var v := Palette.box(Vector3(0.08, size.y * 0.7, 0.08), vein)
			v.position = rock.position + Vector3(0.0, 0.2, 0.0) + (Vector3(0, 0, size.z * 0.5) if ring[i].z < 0 else Vector3(size.x * 0.5 * signf(w * 0.5 - ring[i].x), 0, 0))
			v.rotation.z = 0.3
			parent.add_child(v)
	# Timber sets: two posts and a cap, every few metres along the flanks.
	for zi in range(0, int(h), 5):
		for side in [-1.6, w + 0.6]:
			for dz in [-0.8, 0.8]:
				var post := Palette.box(Vector3(0.22, 3.2, 0.22), timber)
				post.position = Vector3(side, 1.6, zi + 1.0 + dz)
				parent.add_child(post)
			var cap := Palette.box(Vector3(0.26, 0.22, 2.0), timber)
			cap.position = Vector3(side, 3.25, zi + 1.0)
			parent.add_child(cap)
	# The shaft: a great dark column beyond the far wall, glowing teal from far below.
	var shaft := Palette.box(Vector3(10.0, 0.2, 10.0), Palette.emissive(Palette.TEAL_DIM, 1.2))
	shaft.position = Vector3(w * 0.5, -6.0, -12.0)
	parent.add_child(shaft)
	var glow := OmniLight3D.new()
	glow.light_color = Palette.TEAL
	glow.light_energy = 2.5
	glow.omni_range = 16.0
	glow.position = Vector3(w * 0.5, -2.0, -8.0)
	parent.add_child(glow)


## Caged work lamps strung on cable over the gallery, plus Bloom glow pooling on the rock.
static func build_bore_lights(parent: Node3D, grid: Grid) -> void:
	var look := of("bore")
	var cable_mat := Palette.mat(Color("15120f"), 0.5, 0.6)
	var bulb_mat := Palette.emissive(look.lamp_bulb, 3.5)
	var w := float(grid.width)
	var h := float(grid.height)
	for i in 3:
		var z := 2.5 + i * (h - 5.0) / 2.0
		var cable := Palette.box(Vector3(w + 4.0, 0.03, 0.03), cable_mat)
		cable.position = Vector3(w * 0.5 - 0.5, 4.6, z)
		parent.add_child(cable)
		for j in 2:
			var x := w * (0.25 + 0.5 * j) + (i % 2) * 1.5
			var lamp := Palette.box(Vector3(0.22, 0.28, 0.22), bulb_mat)
			lamp.position = Vector3(x, 4.35, z)
			parent.add_child(lamp)
			var l := OmniLight3D.new()
			l.light_color = look.lamp
			l.light_energy = look.lamp_energy * 0.45
			l.omni_range = 7.5
			l.omni_attenuation = 1.2
			l.shadow_enabled = i == 1
			l.position = lamp.position + Vector3(0, -0.2, 0)
			parent.add_child(l)
	for p in [Vector3(-1.5, 0.6, h * 0.3), Vector3(w + 0.5, 0.6, h * 0.7), Vector3(w * 0.7, 0.6, -1.5)]:
		var l := OmniLight3D.new()
		l.light_color = Palette.TEAL
		l.light_energy = 1.6
		l.omni_range = 5.0
		l.position = p
		parent.add_child(l)
