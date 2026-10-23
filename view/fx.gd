extends Node3D
## Short-lived effects: tracers, muzzle flashes, floating text, pulses.
## Driven by `advance(delta)` from the event player's clock (not _process), so
## everything stays in step with the event queue and can be stepped in tests.

const Palette := preload("res://view/palette.gd")

var _items: Array[Dictionary] = []   # {node, life, max, kind, mat?, rise?}


func advance(delta: float) -> void:
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		it.life -= delta
		var k: float = clampf(1.0 - it.life / it.max, 0.0, 1.0)
		var node: Node3D = it.node
		match it.kind:
			"text":
				node.position.y = it.y0 + k * 0.9
				(node as Label3D).modulate.a = 1.0 - maxf(0.0, k - 0.6) / 0.4
			"fade":
				var m: StandardMaterial3D = it.mat
				m.albedo_color.a = it.a0 * (1.0 - k)
			"light":
				(node as OmniLight3D).light_energy = it.e0 * (1.0 - k)
			"ring":
				var s := 0.4 + k * 1.6
				node.scale = Vector3(s, 0.3, s)
				var rm: StandardMaterial3D = it.mat
				rm.emission_energy_multiplier = 4.0 * (1.0 - k)
		if it.life <= 0.0:
			_items.remove_at(i)
			node.queue_free()


func active_count() -> int:
	return _items.size()


func clear() -> void:
	for it in _items:
		(it.node as Node).queue_free()
	_items.clear()


func floating_text(at: Vector3, text: String, color: Color, size := 64, life := 1.1) -> void:
	var l := Palette.label3d(text, size, color)
	l.position = at
	add_child(l)
	_items.append({"node": l, "life": life, "max": life, "kind": "text", "y0": at.y})


func tracer(from: Vector3, to: Vector3, color: Color, life := 0.35) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var m := Palette.overlay(Color(color, 0.95))
	var beam := Palette.box(Vector3(0.035, 0.035, length), m)
	add_child(beam)
	beam.position = (from + to) * 0.5
	beam.basis = Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_items.append({"node": beam, "life": life, "max": life, "kind": "fade", "mat": m, "a0": 0.95})


func muzzle_flash(at: Vector3, color := Color(1.0, 0.8, 0.45)) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 3.0
	light.position = at
	add_child(light)
	_items.append({"node": light, "life": 0.18, "max": 0.18, "kind": "light", "e0": 4.0})
	var m := Palette.overlay(Color(color, 0.9))
	var spark := Palette.box(Vector3(0.18, 0.18, 0.18), m)
	spark.position = at
	add_child(spark)
	_items.append({"node": spark, "life": 0.12, "max": 0.12, "kind": "fade", "mat": m, "a0": 0.9})


func pulse(at: Vector3, color: Color, life := 0.7) -> void:
	var m := Palette.emissive(color, 4.0)
	var r := Palette.ring(0.4, 0.5, m)
	r.position = at + Vector3(0, 0.05, 0)
	add_child(r)
	_items.append({"node": r, "life": life, "max": life, "kind": "ring", "mat": m})
