extends Node
## Autoload "UiFeel": the shared motion of the interface. Every button in the game gets a soft
## amber lantern halo that tightens around it on hover and a short flash when pressed (Soundscape adds the hover
## tick and the click). Screens call the static enter() / deal() to fade and slide in instead of
## popping, through `const Feel := preload("res://ui/ui_feel.gd")` (scripts run with -s can't see
## autoload names). A button opts out with set_meta("no_feel", true).

const Styles := preload("res://ui/styles.gd")

const HOVER_IN := 0.12
const HOVER_OUT := 0.18
const ENTER := 0.24


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	var b := n as BaseButton
	if b == null or b.has_meta("no_feel") or b is CheckBox or b is CheckButton:
		return
	var marks := HoverMarks.new()
	b.add_child(marks, false, Node.INTERNAL_MODE_BACK)
	b.mouse_entered.connect(marks.hover.bind(true))
	b.mouse_exited.connect(marks.hover.bind(false))
	b.button_down.connect(_flash.bind(b))


static func _flash(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.disabled:
		return
	var tw := b.create_tween()
	b.self_modulate = Color(1.35, 1.3, 1.15)
	tw.tween_property(b, "self_modulate", Color.WHITE, 0.22).set_ease(Tween.EASE_OUT)


## Fades `c` in (and slides it up by `rise` px when its parent doesn't lay it out).
static func enter(c: CanvasItem, delay := 0.0, rise := 14.0, secs := ENTER) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel()
	var ctl := c as Control
	if ctl != null and rise != 0.0 and not ctl.get_parent() is Container:
		var end := ctl.position
		ctl.position.y += rise
		tw.tween_property(ctl, "position", end, secs).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, secs).set_delay(delay)


## Deals a row of cards in one after another.
static func deal(items: Array, gap := 0.05, delay := 0.0) -> void:
	var i := 0
	for c in items:
		if c is CanvasItem:
			enter(c, delay + gap * i)
			i += 1


## Plays an interface sound through the Soundscape (open, close, page, pick, vote, ready, node...).
static func sound(kind: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var ss := tree.root.get_node_or_null("Soundscape") if tree != null else null
	if ss != null:
		ss.ui(kind)


## A soft amber halo drawn just outside a button, following its rounded shape; it tightens in
## from further out on hover.
class HoverMarks extends Control:
	var t := 0.0
	var _tw: Tween

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func hover(on: bool) -> void:
		var b := get_parent() as BaseButton
		if on and (b == null or b.disabled):
			return
		if _tw != null:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_method(_set_t, t, 1.0 if on else 0.0, HOVER_IN if on else HOVER_OUT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	func _set_t(v: float) -> void:
		t = v
		queue_redraw()

	func _draw() -> void:
		if t <= 0.01:
			return
		var b := get_parent() as Control
		var radius := 8.0
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat if b != null else null
		if sb != null:
			radius = minf(float(sb.corner_radius_top_left), minf(size.x, size.y) * 0.5)
		var out := 3.0 + (1.0 - t) * 6.0
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.set_border_width_all(2)
		box.border_color = Color(Styles.AMBER, 0.85 * t)
		box.set_corner_radius_all(int(radius + out))
		box.corner_detail = 12
		box.shadow_color = Color(Styles.AMBER, 0.25 * t)
		box.shadow_size = 8
		draw_style_box(box, Rect2(Vector2.ZERO, size).grow(out))
