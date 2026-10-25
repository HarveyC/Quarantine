extends "res://ui/frame.gd"
## The map key: a short list over the bottom-right corner (on a soft haze, no box) listing every floor marking on screen
## right now (Board.active_overlays), each with the same swatch as on the floor (TileOverlays).
## Hovering an entry opens its glossary card. Hidden when nothing is marked.

const W := preload("res://ui/widgets.gd")
const Tips := preload("res://ui/tips/tips.gd")

const SWATCH := Vector2(22, 15)
const POLL := 0.15

var view: Node   # MissionView; its board is read each time, so a restarted fight is followed
var _flow: HFlowContainer
var _shown: Array[String] = []
var _t := 0.0


func _init() -> void:
	super(Vector4(12, 8, 12, 9))


func build(v: Node) -> void:
	view = v
	name = "OverlayLegend"
	custom_minimum_size = Vector2(300, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	set_haze(0.45)
	var box := Styles.vbox(6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head := Styles.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(Styles.caps("Map key", 11, Styles.MUTED))
	box.add_child(head)
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 12)
	_flow.add_theme_constant_override("v_separation", 6)
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_flow)
	visible = false
	refresh()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = POLL
		refresh()


## Rebuilds the entries when the set of markings on screen changed.
func refresh() -> void:
	var board: Node = view.get("board") if view != null else null
	if board == null or not is_instance_valid(board) or not board.has_method("active_overlays"):
		return
	var now: Array[String] = board.active_overlays()
	if now == _shown:
		return
	_shown = now
	for c in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	for key in now:
		_flow.add_child(entry(key))
	visible = not now.is_empty()


## The keys listed right now, in order.
func shown() -> Array[String]:
	return _shown


## One entry: the floor swatch and the marking's name, hoverable for its card.
static func entry(key: String) -> Control:
	var row := Styles.hbox(6)
	row.name = "Key_" + key
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_default_cursor_shape = Control.CURSOR_HELP
	var sw := Swatch.new()
	sw.key = key
	sw.custom_minimum_size = SWATCH
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var col := TileOverlays.color(key)
	row.add_child(Styles.caps(str(TileOverlays.KINDS[key].name), 11, col.lightened(0.25) if col.v < 0.6 else col))
	Tips.term(row, TileOverlays.term(key))
	return row


class Swatch extends Control:
	var key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		TileOverlays.draw_swatch(self, Rect2(Vector2.ZERO, size), key)
