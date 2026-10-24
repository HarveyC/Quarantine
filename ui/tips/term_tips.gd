extends Node
## Autoload TermTips: draws every hover card in the game. It watches the control under the
## pointer and, after a short rest, shows a TipCard for it: glossary terms set with Tips.term()
## or the control's plain tooltip_text (Godot's own tooltips are switched off in project
## settings so there is one look). Hold the "tip_more" action (Shift) for the detailed view.
## Hovering a link or chip inside a card opens that term's card beside it, and so on down; a
## short grace period lets the pointer travel from a control into its card.
##
## Gamepad: the left stick drives the real pointer (SettingsHost), so hovering just works;
## resting the pointer on a card for PAD_DWELL seconds opens the detailed view.

signal expanded_changed(on: bool)

const Tips := preload("res://ui/tips/tips.gd")
const TipCard := preload("res://ui/tips/tip_card.gd")
const Styles := preload("res://ui/styles.gd")

const SHOW_DELAY := 0.35
## Map tiles under the pointer wait a little longer, so sweeping the mouse across the board
## doesn't flash cards.
const WORLD_DELAY := 0.6
const NEST_DELAY := 0.2
const GRACE := 0.3
const PAD_DWELL := 0.9
const OFFSET := Vector2(18, 22)
const MARGIN := 8.0

var expanded := false
## Cards on screen, root first; each nested one was opened from a link in the one before.
var cards: Array = []
## Cards for things in the game world rather than on a control (map tiles): called with the
## pointer position when it is over no control, returns {"terms": [...], "ctx": {}} or {}.
## The mission's input controller sets it.
var world_tip := Callable()

var _layer: CanvasLayer
var _root: Control
var _source: Control
var _cand: Control
var _cand_t := 0.0
var _nest_cand := ""
var _nest_t := 0.0
var _away_t := 0.0
var _nest_away_t := 0.0
var _blocked: Control
var _pad := false
var _dwell := 0.0
var _dwell_done := false
var _last_mouse := Vector2.ZERO
var _world: Control   # stands in as the source control for world_tip cards
var _world_key := ""


func _ready() -> void:
	name = "TermTips"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Styles.make_theme()
	_layer.add_child(_root)
	_world = Control.new()
	_world.name = "WorldTip"
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_world)
	if not InputMap.has_action("tip_more"):
		InputMap.add_action("tip_more")
		var k := InputEventKey.new()
		k.keycode = KEY_SHIFT
		InputMap.action_add_event("tip_more", k)


## 0..1 while the gamepad pointer rests on a card, toward the detailed view.
func dwell_progress() -> float:
	return 1.0 if _dwell_done else clampf(_dwell / PAD_DWELL, 0.0, 1.0)


## Opens the card for `c` right away (screenshots, tests, and the coach pointing at a term).
func show_for(c: Control, at := Vector2(-1, -1)) -> void:
	close_all()
	var content := content_of(c)
	if content.is_empty():
		return
	_source = c
	var p := at if at.x >= 0 else c.get_global_rect().get_center()
	_open(content, Rect2(p, Vector2.ZERO), null)


## Opens the card for a term from the card at `index` (screenshots and tests).
func open_nested(index: int, key: String) -> void:
	if index < cards.size():
		_trim(index + 1)
		var parent: TipCard = cards[index]
		var r: Rect2 = parent.get_global_rect()
		_open({"terms": [key], "text": "", "ctx": {}}, Rect2(Vector2(r.end.x, r.position.y + 40), Vector2.ZERO), parent)


func set_expanded(on: bool) -> void:
	if on == expanded:
		return
	expanded = on
	for c in cards:
		c.set_expanded(on, _pad)
	expanded_changed.emit(on)


func close_all() -> void:
	_trim(0)
	_source = null
	_dwell = 0.0
	_dwell_done = false


## What a control's card shows: {"terms", "text", "ctx"}, or {} for nothing.
static func content_of(c: Control) -> Dictionary:
	if c == null or not is_instance_valid(c) or c.has_meta(Tips.META_OFF):
		return {}
	var text := c.get_tooltip(c.get_local_mouse_position()) if c.is_inside_tree() else c.tooltip_text
	var tip: Variant = c.get_meta(Tips.META) if c.has_meta(Tips.META) else null
	if c.has_method("tip_at") and c.is_inside_tree():
		var at: Variant = c.call("tip_at", c.get_local_mouse_position())
		if at is Dictionary and not at.is_empty():
			tip = at
	if tip is Dictionary:
		var ctx: Variant = tip.get("ctx", {})
		if ctx is Callable:
			ctx = (ctx as Callable).call()
		return {"terms": tip.get("terms", []), "text": text, "ctx": ctx if ctx is Dictionary else {}}
	if text.strip_edges() != "":
		return {"terms": [], "text": text, "ctx": {}}
	return {}


## The control whose card `hov` should show: `hov` or a parent it passes the mouse to.
static func source_of(hov: Control) -> Control:
	var n: Node = hov
	while n is Control:
		var c := n as Control
		if c.has_meta(Tips.META_OFF):
			return null
		if not content_of(c).is_empty():
			return c
		if c.mouse_filter != Control.MOUSE_FILTER_PASS:
			return null
		n = c.get_parent()
	return null


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.4):
		_pad = true
	elif e is InputEventKey and e.is_pressed() and not e.is_action("tip_more"):
		_pad = false


func _process(dt: float) -> void:
	dt = minf(dt, 0.1)   # a frame hitch shouldn't close a card the pointer is travelling to
	var vp := get_viewport()
	if vp == null:
		return
	var mouse := vp.get_mouse_position()
	var moved := mouse.distance_squared_to(_last_mouse) > 1.0
	_last_mouse = mouse
	_update_expanded(dt, moved)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if not cards.is_empty() and _card_index(vp.gui_get_hovered_control()) < 0:
			_blocked = _source
			close_all()
		return
	cards = cards.filter(func(c) -> bool: return is_instance_valid(c))
	var hov := vp.gui_get_hovered_control()
	var ci := _card_index(hov)
	if ci >= 0:
		# Reading a card keeps it open even if its source was rebuilt underneath (HUD refresh).
		_on_card(ci, hov, dt)
		return
	if _source != null and (not is_instance_valid(_source) or not _source.is_visible_in_tree()):
		close_all()
	_nest_cand = ""
	var src := source_of(hov)
	if src == null and hov == null:
		src = _world_source(mouse)
	if src != _blocked:
		_blocked = null
	elif src != null:
		src = null
	if src != null and src == _source and not cards.is_empty():
		if content_of(src).get("terms", []) == cards[0].terms:
			_away_t = 0.0
			_close_nested_after(1, dt)
			return
		close_all()   # a control with several parts (map legend): the pointer moved to another
	if not cards.is_empty():
		_away_t += dt
		if _away_t >= GRACE:
			close_all()
	if src == null:
		_cand = null
		return
	if src != _cand:
		_cand = src
		_cand_t = 0.0
	_cand_t += dt
	if _cand_t >= (WORLD_DELAY if src == _world else SHOW_DELAY) and cards.is_empty():
		var content := content_of(src)
		if not content.is_empty():
			_source = src
			_away_t = 0.0
			_open(content, Rect2(mouse, Vector2.ZERO), null)


## The pointer is over the game world: the stand-in control carrying what world_tip says is
## there, or null. Moving to a tile with other markings starts the wait again.
func _world_source(mouse: Vector2) -> Control:
	var tip: Variant = world_tip.call(mouse) if world_tip.is_valid() else {}
	if not (tip is Dictionary) or tip.get("terms", []).is_empty():
		_world_key = ""
		return null
	var key := str(tip.terms)
	if key != _world_key:
		_world_key = key
		_cand = null
		if _blocked == _world:
			_blocked = null
	_world.set_meta(Tips.META, {"terms": tip.terms, "ctx": tip.get("ctx", {})})
	return _world


func _update_expanded(dt: float, moved: bool) -> void:
	var want := Input.is_action_pressed("tip_more")
	if _pad and not cards.is_empty():
		if moved and not _dwell_done:
			_dwell = 0.0
		_dwell += dt
		if _dwell >= PAD_DWELL:
			_dwell_done = true
		want = want or _dwell_done
	set_expanded(want)


## The pointer is on card `ci`: keep it, close deeper cards it left, open a hovered link.
func _on_card(ci: int, hov: Control, dt: float) -> void:
	_away_t = 0.0
	var term: String = cards[ci].term_at(hov)
	var child_key: String = cards[ci + 1].key if cards.size() > ci + 1 else ""
	if term != "" and term == child_key:
		_nest_away_t = 0.0
		return
	_close_nested_after(ci + 1, dt)
	if term == "" or term == cards[ci].key:
		_nest_cand = ""
		return
	if term != _nest_cand:
		_nest_cand = term
		_nest_t = 0.0
	_nest_t += dt
	if _nest_t >= NEST_DELAY:
		_trim(ci + 1)
		var at := hov.get_global_rect()
		if hov is RichTextLabel:
			at = Rect2(get_viewport().get_mouse_position() - Vector2(0, 8), Vector2(1, 16))
		_open({"terms": [term], "text": "", "ctx": {}}, at, cards[ci])
		_nest_cand = ""


## Closes cards past the first `keep` once the pointer has been off them for GRACE.
func _close_nested_after(keep: int, dt: float) -> void:
	if cards.size() > keep:
		_nest_away_t += dt
		if _nest_away_t >= GRACE:
			_trim(keep)
	else:
		_nest_away_t = 0.0


func _trim(n: int) -> void:
	while cards.size() > n:
		var c = cards.pop_back()
		if is_instance_valid(c):
			c.queue_free()
	_nest_away_t = 0.0


func _card_index(hov: Control) -> int:
	if hov == null:
		return -1
	for i in range(cards.size() - 1, -1, -1):
		var c: Control = cards[i]
		if is_instance_valid(c) and (c == hov or c.is_ancestor_of(hov)):
			return i
	return -1


func _open(content: Dictionary, at: Rect2, parent: Control) -> void:
	var card := TipCard.new(content.get("terms", []), str(content.get("text", "")), content.get("ctx", {}))
	card.set_expanded(expanded, _pad)
	card.anchor = at
	card.parent_card = parent
	_root.add_child(card)
	cards.append(card)
	card.resized.connect(_place.bind(card))
	_place(card)


## Root cards sit below-right of the pointer (flipped at screen edges); nested cards sit beside
## their parent card, level with the link.
func _place(card: TipCard) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	var view := _root.get_viewport_rect().size
	var s := card.size
	var at: Rect2 = card.anchor
	var parent: Control = card.parent_card
	var p := Vector2.ZERO
	if parent != null and is_instance_valid(parent):
		var pr: Rect2 = parent.get_global_rect()
		p = Vector2(pr.end.x + 6, at.position.y - 12)
		if p.x + s.x > view.x - MARGIN:
			p.x = pr.position.x - s.x - 6
	else:
		p = at.position + OFFSET
		if p.x + s.x > view.x - MARGIN:
			p.x = at.position.x - s.x - 12
		if p.y + s.y > view.y - MARGIN:
			p.y = at.position.y - s.y - 12
	p.x = clampf(p.x, MARGIN, maxf(MARGIN, view.x - s.x - MARGIN))
	p.y = clampf(p.y, MARGIN, maxf(MARGIN, view.y - s.y - MARGIN))
	card.position = p
