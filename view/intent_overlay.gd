extends Node3D
## Team-phase readability layer for enemies (design doc, Enemy AI and readability): an intent
## label over each enemy with a thin line to its likely target, red tiles for everything that
## hits next enemy phase, amber vents for incoming reinforcements,
## and a faint ripple over hidden Lurkers in sight. Fog of war markers: a dim red "?" where an
## enemy was last seen, and a pulsing red contact for Motion tracker blips.
## Reads GameState through EnemyIntent and Vision; never mutates it.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")

const ICON_TEXT := {
	"claw": "CLAW", "shoot": "SHOOT", "spit": "SPIT", "burst": "BURST", "charge": "CHARGE",
	"scream": "SCREAM", "spawn": "SPAWN", "strike": "AIRSTRIKE", "pull": "PULL", "pulse": "PULSE",
	"hide": "HIDE", "seek": "SEEK", "dormant": "zz", "pinning": "MAUL", "leap": "LEAP",
	"snipe": "AIMING", "drop": "DROP",
}

var view: Node
var _m_danger: StandardMaterial3D
var _m_spore: StandardMaterial3D
var _m_vent: StandardMaterial3D
var _m_line: StandardMaterial3D
var _m_ripple: StandardMaterial3D
var _m_ghost: StandardMaterial3D
var _m_blip: StandardMaterial3D
var _blips: Array[Node3D] = []


func _ready() -> void:
	name = "IntentOverlay"
	_m_danger = Palette.overlay(Color(Palette.DANGER, 0.42))
	_m_spore = Palette.overlay(Color(Palette.TEAL, 0.16))
	_m_vent = Palette.overlay(Color(Palette.AMBER, 0.5))
	_m_line = Palette.overlay(Color(Palette.DANGER, 0.55))
	_m_ripple = Palette.overlay(Color(Palette.TEAL, 0.25))
	_m_ghost = Palette.overlay(Color(Palette.DANGER, 0.22))
	_m_blip = Palette.overlay(Color(Palette.DANGER, 0.7))


func refresh() -> void:
	if _m_danger == null:
		_ready()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_blips.clear()
	var s: GameState = view.state if view != null else null
	if s == null or s.phase != Types.Phase.TEAM or (view.player != null and view.player.is_busy()):
		return
	for c in EnemyIntent.incoming(s):
		_tile(c, _m_vent, 0.02)
	for d in EnemyIntent.dangers(s):
		for c in d.cells:
			_tile(c, _m_danger, 0.022)
	for c in EnemyIntent.ripples(s):
		var r := Palette.ring(0.25, 0.42, _m_ripple)
		r.position = Board.cell_to_world(c, 0.04)
		add_child(r)
	for id in Vision.last_seen(s):
		var c: Vector2i = Vision.last_seen(s)[id]
		var r := Palette.ring(0.3, 0.4, _m_ghost)
		r.position = Board.cell_to_world(c, 0.04)
		add_child(r)
		var q := Palette.label3d("?", 40, Color(Palette.DANGER, 0.55))
		q.position = Board.cell_to_world(c, 0.9)
		add_child(q)
	var blips := Vision.blips(s)
	for id in blips:
		var b := Palette.ring(0.12, 0.2, _m_blip)
		b.position = Board.cell_to_world(blips[id], 0.05)
		add_child(b)
		_blips.append(b)
		var wave := Palette.ring(0.36, 0.42, _m_ghost)
		wave.position = b.position
		add_child(wave)
		_blips.append(wave)
	for it in EnemyIntent.intents(s):
		var uv: Node3D = view.view_for(it.unit)
		if uv == null or not uv.visible:
			continue
		var dormant: bool = it.icon == "dormant"
		var text: String = it.label if it.label != "" else ICON_TEXT.get(it.icon, "")
		if not it.affixes.is_empty():
			text += "\n" + " / ".join(it.affixes)
		if text == "":
			continue
		var col := Color(0.6, 0.62, 0.6) if dormant else (Palette.TEAL if it.icon in ["spawn", "pulse"] else Palette.DANGER)
		var l := Palette.label3d(text, 46, col)
		l.position = uv.position + Vector3(0, 2.3 * uv.scale.y + 0.2, 0)
		add_child(l)
		if int(it.target) >= 0:
			var tv: Node3D = view.view_for(int(it.target))
			if tv != null:
				_line(uv.position + Vector3(0, 0.08, 0), tv.position + Vector3(0, 0.08, 0))


func _tile(c: Vector2i, m: Material, y: float) -> void:
	var q := Palette.box(Vector3(0.9, 0.01, 0.9), m)
	q.position = Board.cell_to_world(c, y)
	add_child(q)


func _line(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var beam := Palette.box(Vector3(0.03, 0.01, length), _m_line)
	beam.position = (a + b) * 0.5
	beam.basis = Basis.looking_at(b - a, Vector3.UP)
	add_child(beam)


func _process(_delta: float) -> void:
	var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	for i in _blips.size():
		var b := _blips[i]
		if is_instance_valid(b):
			b.scale = Vector3.ONE * (1.0 + (k * 0.25 if i % 2 == 0 else (1.0 - k) * 0.8))
