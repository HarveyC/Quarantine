extends VBoxContainer
## The squad's state beside a node screen's choices: a SoldierCard per active soldier in a
## glass frame with the owner's colour stripe. Screens call `hook(button, preview)` so that
## hovering or focusing a choice previews it on the cards it touches (preview returns
## {soldier id: delta}, see EventRules.preview); the touched cards light up amber-edged and
## the head names the choice being previewed.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const SoldierCard := preload("res://ui/nodes/soldier_card.gd")

const WIDTH := 420.0
const IDLE_NOTE := "Hover a choice to see what it does"

var run: RunState
var session
var _cards := {}    # soldier id -> SoldierCard
var _frames := {}   # soldier id -> its Frame
var _head_note: Label
var _shown := ""


func setup(r: RunState, s) -> void:
	run = r
	session = s
	name = "SquadPanel"
	custom_minimum_size.x = WIDTH
	size_flags_horizontal = Control.SIZE_SHRINK_END
	add_theme_constant_override("separation", 8)
	var head := NodeUi.hbox(10)
	head.add_child(W.Icon.new("squad", NodeUi.DIM, 18, 1.8))
	head.add_child(NodeUi.caption("Squad", NodeUi.DIM, 14))
	add_child(head)
	_head_note = NodeUi.caption(IDLE_NOTE, NodeUi.FAINT, 12)
	_head_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_head_note)
	var squad: Array = RunAccess.active_soldiers(run)
	squad.sort_custom(func(a, b): return a.owner < b.owner or (a.owner == b.owner and a.id < b.id))
	for rec in squad:
		var frame := W.Frame.new(Vector4(16, 10, 14, 10))
		frame.stripe = NodeUi.player_color(rec.owner)
		frame.radius = 20
		add_child(frame)
		var card := SoldierCard.new()
		card.setup(run, session, rec, true)
		frame.add_child(card)
		_cards[rec.id] = card
		_frames[rec.id] = frame
		_look(rec, false)


## Shows `deltas` ({soldier id: delta}) on the cards; an empty map clears the preview.
func set_preview(deltas: Dictionary, what := "") -> void:
	for id in _cards:
		_cards[id].show_delta(deltas.get(id, {}))
		_look(_cards[id].rec, deltas.has(id))
	var on := what != "" and not deltas.is_empty()
	_head_note.text = ("Preview · " + what).to_upper() if on else IDLE_NOTE.to_upper()
	_head_note.add_theme_color_override("font_color", NodeUi.AMBER if on else NodeUi.FAINT)


func clear_preview() -> void:
	set_preview({})


## Hovering or focusing `c` previews what `preview` (a Callable returning {sid: delta}) says.
func hook(c: Control, what: String, preview: Callable) -> void:
	var key := "%s#%d" % [what, c.get_instance_id()]
	var on := func() -> void:
		_shown = key
		set_preview(preview.call(), what)
	var off := func() -> void:
		if _shown == key:
			_shown = ""
			clear_preview()
	c.mouse_entered.connect(on)
	c.focus_entered.connect(on)
	c.mouse_exited.connect(off)
	c.focus_exited.connect(off)


func _look(rec: Dictionary, lit: bool) -> void:
	var frame: Control = _frames[rec.id]
	var tier := Infection.tier(rec.infection)
	if lit:
		frame.set_look(Color(0.1, 0.085, 0.06, 0.94), Color(Styles.AMBER, 0.7), Styles.AMBER, false)
	elif tier >= Infection.Tier.MUTATING:
		frame.set_look(Color(0.03, 0.09, 0.1, 0.9), Color(Styles.TEAL, 0.4), Styles.AMBER, false)
	else:
		frame.set_look(Color(0.056, 0.082, 0.128, 0.92), Styles.BORDER_SOFT, Styles.AMBER, false)
