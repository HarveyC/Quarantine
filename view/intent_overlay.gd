extends Node3D
## Team-phase readability layer for enemies (design doc, Enemy AI and readability): an intent
## label over each enemy with a thin line to its likely target, red tiles for everything that
## hits next enemy phase, amber vents for incoming reinforcements, teal threads from shields to
## the enemy they keep immune,
## and a faint ripple over hidden Lurkers in sight. Fog of war markers: a dim red "?" where an
## enemy was last seen, and a pulsing red contact for Motion tracker blips.
## Reads GameState through EnemyIntent and Vision; never mutates it.

const Palette := preload("res://view/palette.gd")
const Board := preload("res://view/board.gd")
const UnitView := preload("res://view/unit_view.gd")

const ICON_TEXT := {
	"claw": "CLAW", "shoot": "SHOOT", "spit": "SPIT", "burst": "BURST", "charge": "CHARGE",
	"scream": "SCREAM", "spawn": "SPAWN", "strike": "AIRSTRIKE", "pull": "PULL", "pulse": "PULSE",
	"hide": "HIDE", "seek": "SEEK", "dormant": "zz", "pinning": "MAUL", "leap": "LEAP",
	"snipe": "AIMING", "drop": "DROP", "hook": "HOOK", "satchel": "SATCHEL", "firebomb": "FIREBOMB", "mend": "MEND",
	"snare": "SNARE", "flare": "FLARE", "order": "ORDERS", "frag": "FRAG", "revive": "REVIVE", "repair": "REPAIR", "arc": "ARC",
	"net": "NET", "designate": "DESIGNATE", "flame": "STERILIZE", "drag": "DRAG", "bloom": "BLOOM", "chant": "CHANT", "hush": "HUSH",
}

var view: Node
var _m_danger: StandardMaterial3D
var _m_spore: StandardMaterial3D
var _m_vent: StandardMaterial3D
var _m_line: StandardMaterial3D
var _m_tether: StandardMaterial3D
var _m_trail: StandardMaterial3D
var _m_ripple: StandardMaterial3D
var _m_ghost: StandardMaterial3D
var _m_blip: StandardMaterial3D
var _m_plate: StandardMaterial3D
var _m_exit: StandardMaterial3D
var _m_rally: StandardMaterial3D
var _blips: Array[Node3D] = []


func _ready() -> void:
	name = "IntentOverlay"
	_m_danger = Palette.overlay(Color(Palette.DANGER, 0.42))
	_m_spore = Palette.overlay(Color(Palette.TEAL, 0.16))
	_m_vent = Palette.overlay(Color(Palette.AMBER, 0.5))
	_m_line = Palette.overlay(Color(Palette.DANGER, 0.55))
	_m_tether = Palette.overlay(Color(Palette.TEAL, 0.6))
	_m_trail = Palette.overlay(Color(0.62, 0.5, 0.34, 0.5))
	_m_ripple = Palette.overlay(Color(Palette.TEAL, 0.25))
	_m_ghost = Palette.overlay(Color(Palette.DANGER, 0.22))
	_m_blip = Palette.overlay(Color(Palette.DANGER, 0.7))
	_m_plate = Palette.overlay(Color(Palette.AMBER, 0.3))
	_m_exit = Palette.overlay(Color(Palette.AMBER, 0.45))
	_m_rally = Palette.overlay(Color(Palette.AMBER, 0.35))


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
		var dig: bool = d.kind == "trail"
		for c in d.cells:
			_tile(c, _m_trail if dig else (_m_exit if d.kind == "exit" else _m_danger), 0.022)
		if d.kind == "exit" and not d.cells.is_empty():
			var gate := Palette.label3d("EXIT", 46, Palette.AMBER)
			gate.position = Board.cell_to_world(d.cells[d.cells.size() / 2], 1.4)
			add_child(gate)
		if d.kind == "erupt" and not d.cells.is_empty():   # the boss itself is underground and unlabelled
			var q := Palette.label3d("ERUPTS", 46, Palette.DANGER)
			q.position = Board.cell_to_world(d.cells[d.cells.size() / 2], 1.4)
			add_child(q)
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
	# A Carapace's armoured side, and the reach of a Rallying elite's war cry.
	for p in EnemyIntent.plates(s):
		for c in p.cells:
			_tile(c, _m_plate, 0.024)
	for r in EnemyIntent.rallies(s):
		var ring := Palette.ring(EnemyRoster.RALLY_RADIUS - 0.08, EnemyRoster.RALLY_RADIUS, _m_rally)
		ring.position = Board.cell_to_world(r.cell, 0.04)
		add_child(ring)
	for pair in EnemyIntent.hoards(s):   # amber threads from the Broker to the soldiers whose items he holds
		var ba: Node3D = view.view_for(pair[0])
		var bb: Node3D = view.view_for(pair[1])
		if ba != null and bb != null and ba.visible and bb.visible:
			_line(ba.position + Vector3(0, 1.2, 0), bb.position + Vector3(0, 1.2, 0), _m_exit, 0.04)
	for c in EnemyIntent.chants(s):
		var chant_ring := Palette.ring(EnemyRoster.CHANT_RADIUS - 0.08, EnemyRoster.CHANT_RADIUS, _m_tether)
		chant_ring.position = Board.cell_to_world(c.cell, 0.04)
		add_child(chant_ring)
	for ch in EnemyIntent.rings(s):
		var cring := Palette.ring(ch.radius - 0.08, ch.radius, _m_tether)
		cring.position = Board.cell_to_world(ch.cell, 0.04)
		add_child(cring)
	for pair in EnemyIntent.designations(s):
		var ha: Node3D = view.view_for(pair[0])
		var hb: Node3D = view.view_for(pair[1])
		if ha != null and hb != null and ha.visible and hb.visible:
			_line(ha.position + Vector3(0, 1.4, 0), hb.position + Vector3(0, 1.4, 0), _m_line, 0.05)
	for pair in EnemyIntent.links(s):
		var wa: Node3D = view.view_for(pair[0])
		var wb: Node3D = view.view_for(pair[1])
		if wa != null and wb != null and wa.visible and wb.visible:
			_line(wa.position + Vector3(0, 1.0, 0), wb.position + Vector3(0, 1.0, 0), _m_tether, 0.04)
	# Teal threads from each shield (egg sac, root, hive node) to the enemy it keeps immune.
	for pair in EnemyIntent.tethers(s) + ChoirProphet.guards(s):
		var a: Node3D = view.view_for(pair[0])
		var b: Node3D = view.view_for(pair[1])
		if a != null and b != null and a.visible and b.visible:
			_line(a.position + Vector3(0, 0.1, 0), b.position + Vector3(0, 0.1, 0), _m_tether, 0.05)
	for it in EnemyIntent.intents(s):
		var uv: Node3D = view.view_for(it.unit)
		if uv == null or not uv.visible:
			continue
		var dormant: bool = it.icon == "dormant"
		var text := word(it)
		if not it.affixes.is_empty():
			text += "\n" + " / ".join(it.affixes)
		if text == "":
			continue
		# With the HUD up the intent word rides on the enemy's nameplate instead (one label per
		# enemy, not two stacked); the line to its target stays here.
		if UnitView.world_labels:
			var col := Color(0.6, 0.62, 0.6) if dormant else (Palette.TEAL if it.icon in ["spawn", "pulse"] else Palette.DANGER)
			var l := Palette.label3d(text, 46, col)
			l.position = uv.position + Vector3(0, 2.3 * uv.scale.y + 0.2, 0)
			add_child(l)
		if int(it.target) >= 0:
			var tv: Node3D = view.view_for(int(it.target))
			if tv != null:
				_line(uv.position + Vector3(0, 0.08, 0), tv.position + Vector3(0, 0.08, 0))


## The intent word for an EnemyIntent entry ("CLAW", "SPAWNS IN 2"), "" for none.
static func word(it: Dictionary) -> String:
	return str(it.label) if str(it.label) != "" else str(ICON_TEXT.get(it.icon, ""))


func _tile(c: Vector2i, m: Material, y: float) -> void:
	var q := Palette.box(Vector3(0.9, 0.01, 0.9), m)
	q.position = Board.cell_to_world(c, y)
	add_child(q)


func _line(a: Vector3, b: Vector3, m: Material = null, width := 0.03) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var beam := Palette.box(Vector3(width, 0.01, length), m if m != null else _m_line)
	beam.position = (a + b) * 0.5
	beam.basis = Basis.looking_at(b - a, Vector3.UP)
	add_child(beam)


func _process(_delta: float) -> void:
	var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	for i in _blips.size():
		var b := _blips[i]
		if is_instance_valid(b):
			b.scale = Vector3.ONE * (1.0 + (k * 0.25 if i % 2 == 0 else (1.0 - k) * 0.8))
