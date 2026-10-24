extends RefCounted
## Pings and drawing on the route map (see ui/marks/mark_layer.gd). Pings snap to the nearest
## node; anywhere else they sit at a point on the board. Points travel as fractions of the board
## so players with different window sizes see marks in the same places.

const NodeInfo := preload("res://ui/run/node_info.gd")
## How close (px, beyond the ring) the pointer must be for a ping to land on a node.
const SNAP := 26.0

var board: Control   # ui/run/map_board.gd
var run_view: Control


func _init(b: Control, rv: Control) -> void:
	board = b
	run_view = rv


func where() -> String:
	return Marks.ROUTE


func active() -> bool:
	if board == null or board.run == null or not board.is_visible_in_tree():
		return false
	if run_view == null:
		return true
	var full: Variant = run_view.get("_full_holder")
	var pause: Variant = run_view.get("_pause")
	return not (full is CanvasItem and (full as CanvasItem).visible) and not (pause is Node and is_instance_valid(pause))


func player() -> int:
	var s: Node = run_view.get("session") if run_view != null else null
	if s is NetSession:
		return (s as NetSession).my_player
	var local: Array = s.local_players() if s != null else []
	return local[0] if not local.is_empty() else 0


func _rect() -> Rect2:
	return board.get_global_rect()


func target(at: Vector2) -> Dictionary:
	var r := _rect()
	if not r.grow(8.0).has_point(at):
		return {}
	var best := -1
	var best_d := INF
	for n in board.run.map:
		var d: float = (r.position + board.node_pos(n)).distance_to(at) - board._r(n.id)
		if d < best_d:
			best_d = d
			best = n.id
	if best >= 0 and best_d <= SNAP:
		var out := {"node": best, "context": "node"}
		out.subject = describe(out)
		return out
	return {"at": ((at - r.position) / r.size).clamp(Vector2.ZERO, Vector2.ONE), "context": ""}


func point(at: Vector2) -> Variant:
	var r := _rect()
	if not r.has_point(at) or r.size.x <= 0.0 or r.size.y <= 0.0:
		return null
	return (at - r.position) / r.size


func ping_screen(m: Dictionary) -> Variant:
	var r := _rect()
	if m.has("node"):
		var n: Dictionary = board.run.get_node(m.node)
		if n.is_empty():
			return null
		return r.position + board.node_pos(n)
	if m.has("at"):
		return r.position + (m.at as Vector2) * r.size
	return null


func point_screen(p: Variant) -> Variant:
	if not (p is Vector2):
		return null
	var r := _rect()
	return r.position + (p as Vector2) * r.size


func ping_ring(m: Dictionary) -> float:
	return board._r(m.node) + 4.0 if m.has("node") else 0.0


func behind_dir(_m: Dictionary) -> Variant:
	return null


func describe(m: Dictionary) -> String:
	if m.has("node") and board.run != null:
		var n: Dictionary = board.run.get_node(m.node)
		return NodeInfo.title(n) if not n.is_empty() else ""
	return ""


func spawn(_m: Dictionary) -> Node3D:
	return null
