extends PanelContainer
## Rank-up perk picks and mutation offers, hosted inside the reward screen (Progression.pick_screen()).
## One soldier at a time: a strip of portraits along the top for every local soldier with
## something waiting (a solo player picks for all four), the chosen soldier's portrait, rank and
## stats on the left, and their three big cards to the right. A card shows a big icon, its tag
## with set-bonus pips, the numbers as stat chips and one short line; the full rule is on hover
## (TermTips, Shift for more). Hovering a card previews its stat change on the soldier.
## Sends prog_* run actions through session.submit_run. Amber = something to click,
## teal = Infection, a player-colour stripe marks whose soldier it is.

const Styles := preload("res://ui/styles.gd")
const W := preload("res://ui/widgets.gd")
const Feel := preload("res://ui/ui_feel.gd")
const Tips := preload("res://ui/tips/tips.gd")
const Icons := preload("res://ui/icons.gd")
const Draw := preload("res://ui/bloom_draw.gd")

const CARD_W := 250.0
const CARD_H := 460.0
const HERO_W := 330.0
const MAX_W := 1380.0
## Headroom above the soldier strip for the lit tab's glow (primary button glow is 16 px, 22 on hover).
const STRIP_GLOW := 24

var run: RunState
var session
var _list: VBoxContainer
## sid -> partner sid picked for a Bonded card
var _partner := {}
## The soldier whose cards are on screen.
var _sel := -1
## Stat tiles of the soldier on screen, by stat key, for the hover preview.
var _tiles := {}
var _portrait: W.Portrait


func setup(p_run: RunState, p_session) -> void:
	run = p_run
	session = p_session
	theme = Styles.make_theme()
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 16)
	add_child(_list)
	if run.has_signal("event"):
		run.event.connect(func(_ev): rebuild())
	rebuild()


func _players() -> Array:
	if session != null and session.has_method("local_players"):
		return session.local_players()
	return run.players


## [[player, record]] for every local soldier with a pick or offer waiting.
func _waiting() -> Array:
	var out := []
	for p in _players():
		for r in run.soldiers_of(p):
			if Progression.pending_picks(r) > 0 or not r.prog.get("offers", []).is_empty():
				out.append([p, r])
	return out


func rebuild() -> void:
	if _list == null:
		return
	# Out of the tree now, not at the end of the frame, so the old cards don't count toward
	# the reward screen's FitBox size for a frame.
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_tiles.clear()
	_portrait = null
	var waiting := _waiting()
	if waiting.is_empty():
		_list.add_child(Styles.caps("No rank-ups waiting", 18, Styles.MUTED))
		return
	var cur: Array = waiting[0]
	for w in waiting:
		if w[1].id == _sel:
			cur = w
	_sel = cur[1].id
	if waiting.size() > 1:
		# The scroll box clips, so leave room above the strip for the lit tab's glow.
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", STRIP_GLOW)
		pad.add_child(_strip(waiting))
		_list.add_child(pad)
	var intro := Signatures.intro_for(cur[1]) if Progression.pending_picks(cur[1]) > 0 else ""
	if intro != "":
		var rcap := CenterBox.new(MAX_W)
		rcap.add_child(_reveal(intro))
		_list.add_child(rcap)
	var main := Styles.hbox(18)
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(_hero(cur[0], cur[1]))
	var cards := _cards(cur[0], cur[1])
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(cards)
	# Cards share the width, up to MAX_W in all so they don't stretch thin on wide screens.
	var cap := CenterBox.new(MAX_W)
	cap.add_child(main)
	_list.add_child(cap)
	if is_inside_tree():
		Feel.deal(cards.get_children(), 0.06)
		# A different soldier or a reveal card changes the height; the zoom starts over.
		var fit := W.FitBox.above(self)
		if fit != null:
			fit.refit()


# ------------------------------------------------------------------ soldier strip

## Every waiting soldier as a portrait tab; the one on screen is lit.
func _strip(waiting: Array) -> Control:
	var h := Styles.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for w in waiting:
		var r: Dictionary = w[1]
		var on: bool = r.id == _sel
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = on
		Styles.style_button(b, "primary" if on else "ghost", 10)
		Styles.round_button(b, Styles.PILL)
		var row := Styles.hbox(10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		var por := W.Portrait.new(52)
		por.setup(r.kind, Styles.player_color(w[0]), int(r.get("infection", 0)), on)
		row.add_child(por)
		var names := Styles.vbox(0)
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.add_child(Styles.caps(str(r.get("name", "")), 18, Styles.GROUND if on else Styles.TEXT))
		var mut := Progression.pending_picks(r) == 0
		names.add_child(Styles.caps("Mutation" if mut else "Rank %d" % int(r.prog.get("rank", 1)), 14,
			Styles.GROUND if on else (Styles.TEAL if mut else Styles.AMBER)))
		row.add_child(names)
		b.add_child(row)
		b.custom_minimum_size = Vector2(0, 64)
		row.minimum_size_changed.connect(func() -> void:
			b.custom_minimum_size = Vector2(row.get_combined_minimum_size().x + 26, maxf(64.0, row.get_combined_minimum_size().y + 12)))
		b.custom_minimum_size.x = row.get_combined_minimum_size().x + 26
		var sid: int = r.id
		b.pressed.connect(func() -> void:
			Feel.sound("pick")
			_sel = sid
			rebuild())
		h.add_child(b)
	return h


# ------------------------------------------------------------------ the soldier

## Portrait, name and class, the rank badge and what the promotion gave, stats and Infection.
func _hero(p: int, r: Dictionary) -> Control:
	var pcol := Styles.player_color(p)
	var who := W.Frame.new(Vector4(20, 16, 18, 16))
	who.stripe = pcol
	who.set_look(Color(0.043, 0.065, 0.103, 0.92), Styles.BORDER_SOFT, Styles.AMBER, false)
	who.custom_minimum_size = Vector2(HERO_W, 0)
	var info := Styles.vbox(16)
	who.add_child(info)
	var head := Styles.hbox(14)
	var inf := int(r.get("infection", 0))
	_portrait = W.Portrait.new(116)
	_portrait.setup(r.kind, pcol, inf, true)
	head.add_child(_portrait)
	var names := Styles.vbox(2)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Styles.caps(str(r.get("name", "")), 30)
	Styles.fit_width(nm, HERO_W - 180)
	names.add_child(nm)
	var cls := Styles.caps(UnitData.SOLDIERS.get(r.kind, {}).get("name", r.kind), 18, Styles.DIM)
	Tips.soldier_class(cls, r.kind)
	names.add_child(cls)
	head.add_child(names)
	info.add_child(head)
	var picks := Progression.pending_picks(r)
	if picks > 0:
		info.add_child(_rank_row(r, picks))
	else:
		var g := Styles.hbox(10)
		g.add_child(_disc("mutation", Styles.TEAL, 64))
		var gv := Styles.vbox(0)
		gv.alignment = BoxContainer.ALIGNMENT_CENTER
		gv.add_child(Styles.caps("Graft a mutation", 22, Styles.TEAL))
		gv.add_child(Styles.label("Or skip it", 17, Styles.DIM))
		g.add_child(gv)
		info.add_child(g)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var st := _stats(r)
	for k in ["max_hp", "aim", "mobility", "defense"]:
		var t := StatTile.new(k, st[k])
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tiles[k] = t
		grid.add_child(t)
	info.add_child(grid)
	var ir := Styles.hbox(8)
	ir.add_child(W.Icon.new("infection", Styles.TEAL, 22, 1.9))
	var bar := W.InfBar.new(9.0)
	bar.set_value(inf)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ir.add_child(bar)
	ir.add_child(Styles.mono("%d" % inf, 19, Styles.TEAL))
	Tips.term(ir, "infection")
	info.add_child(ir)
	return who


## The rank badge with pips toward max rank, and what this pick is: a promotion (+1 max HP
## already earned) or a bonus pick from a reward card.
func _rank_row(r: Dictionary, picks: int) -> Control:
	var rank := int(r.prog.get("rank", 1))
	var row := Styles.hbox(12)
	var badge := RankBadge.new(rank)
	Tips.term(badge, "rank")
	row.add_child(badge)
	var v := Styles.vbox(5)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var promoted := int(r.prog.get("picks", 0)) > 0
	v.add_child(Styles.caps("Promoted" if promoted else "Bonus perk", 22, Styles.AMBER))
	var pips := W.Pips.new(Vector2(22, 8))
	pips.set_values(Progression.MAX_RANK, rank, 0, Styles.AMBER)
	v.add_child(pips)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	if promoted and rank > 1:
		chips.add_child(StatChip.new("+1", "max HP", Styles.HP, 24))
	if picks > 1:
		chips.add_child(W.chip("%d picks" % picks, Styles.AMBER, false, 14))
	if chips.get_child_count() > 0:
		v.add_child(chips)
	row.add_child(v)
	return row


## Max HP (rank and perks), aim, mobility and defense from perks, as the soldier spawns.
func _stats(r: Dictionary) -> Dictionary:
	var base: Dictionary = UnitData.SOLDIERS.get(r.kind, {})
	var out := {"max_hp": Progression.max_hp(r.kind, r.prog), "aim": int(base.get("aim", 0)),
		"mobility": int(base.get("mobility", 0)), "defense": 0}
	for id in r.prog.get("perks", []):
		var pk: Dictionary = PerkData.PERKS.get(id, {})
		out.mobility += int(pk.get("mobility", 0))
		out.defense += int(pk.get("defense", 0))
	return out


func _preview(perk: Dictionary) -> void:
	for k in _tiles:
		_tiles[k].set_delta(int(perk.get(k, 0)))


func _preview_inf(to: int) -> void:
	if _portrait != null and is_instance_valid(_portrait):
		_portrait.preview = to
		_portrait.queue_redraw()


# ------------------------------------------------------------------ new ability

## The soldier's signature ability, shown the first time they reach the unlock rank: its icon,
## name, how fast it recharges (one ready pip, then the dim ones it takes to come back), its
## rules and the gear tags it counts as.
func _reveal(id: String) -> Control:
	var def: Dictionary = ClassAbilities.ABILITIES[id]
	var frame := W.Frame.new(Vector4(20, 14, 20, 14))
	frame.set_look(Color(0.043, 0.065, 0.103, 0.92), Styles.BORDER_SOFT, Styles.AMBER, false)
	frame.stripe = Styles.AMBER
	var row := Styles.hbox(18)
	frame.add_child(row)
	var disc := _disc(Icons.ABILITY_ICON.get(id, "ability"), Styles.AMBER, 84)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(disc)
	var body := Styles.vbox(6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := Styles.hbox(14)
	top.add_child(Styles.caps(str(def.name), 30, Styles.AMBER))
	var cd := int(def.cooldown)
	var pips := W.Pips.new(Vector2(22, 8))
	pips.set_values(cd, 1, 0, Styles.AMBER)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(pips)
	var cdl := Styles.caps("Cooldown %d" % cd, 15, Styles.DIM)
	Tips.term(cdl, "cooldown")
	top.add_child(cdl)
	body.add_child(top)
	body.add_child(Tips.text(str(def.desc), 17, Styles.TEXT, MAX_W - 220.0))
	var tags := Styles.hbox(14)
	for tag in Signatures.TAGS[id]:
		var tl := Styles.caps(str(tag), 16, GearData.tag_color(str(tag)))
		Tips.term(tl, "tag_" + str(tag).to_lower())
		tags.add_child(tl)
	body.add_child(tags)
	row.add_child(body)
	return frame


# ------------------------------------------------------------------ cards

func _cards(p: int, r: Dictionary) -> Control:
	var row := Styles.hbox(14)
	var counts := GearTags.counts(r)
	if Progression.pending_picks(r) > 0:
		for id in Progression.perk_offer(run, r):
			var perk: Dictionary = PerkData.PERKS[id]
			var b := PerkBrief.perk(id)
			var col := GearData.tag_color(perk.tag) if perk.tag != "" else Styles.AMBER
			var card := _card(b.icon, col, perk.name, perk.tag, counts, b.chips, b.short, "", perk.desc, perk.rare, [],
				func(): _submit({"type": "prog_perk_pick", "player": p, "sid": r.id, "perk": id}))
			card.mouse_entered.connect(func(): _preview(perk))
			card.mouse_exited.connect(func(): _preview({}))
			row.add_child(card)
	else:
		var offer: Dictionary = r.prog.offers[0]
		var inf := int(r.get("infection", 0))
		for id in offer.cards:
			var c := Progression.mutation_card_for(id)
			var b := PerkBrief.mutation(id)
			var extra: Array = [_cost(c.graft), W.chip("%s" % Infection.tier_name(c.tier), Styles.TEAL_DIM, false, 14)]
			var card := _card(b.icon, Styles.TEAL, c.name, c.tag, counts, b.chips, b.short, b.drawback, c.desc, false, extra,
				func(): _graft(p, r, id))
			var graft: int = c.graft
			card.mouse_entered.connect(func(): _preview_inf(mini(100, inf + graft)))
			card.mouse_exited.connect(func(): _preview_inf(-1))
			if c.bonded:
				card.get_meta("body").add_child(_partner_picker(r))
			row.add_child(card)
		var skip := Styles.icon_button("Skip", "close", "ghost", 19, 54)
		skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		skip.pressed.connect(func(): _submit({"type": "prog_skip_offer", "player": p, "sid": r.id}))
		row.add_child(skip)
	return row


## "+15" next to the Infection icon: what grafting costs.
func _cost(n: int) -> Control:
	var h := Styles.hbox(4)
	h.add_child(W.Icon.new("infection", Styles.TEAL, 20, 1.8))
	h.add_child(Styles.mono("+%d" % n, 19, Styles.TEAL))
	Tips.term(h, "infection")
	return h


## A pick card: a big icon in a glowing disc, the name, the tag with its set pips, the numbers
## as stat chips, one short line (and a drawback line for mutations). Hover shows `full`.
func _card(icon: String, col: Color, title: String, tag: String, counts: Dictionary, stats: Array,
		short: String, drawback: String, full: String, rare: bool, extra: Array, on_pick: Callable) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = full
	Styles.style_button(b, "secondary")
	Styles.round_button(b, 24)
	var box := Styles.vbox(12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	b.resized.connect(func() -> void:
		box.position = Vector2(16, 16)
		box.size = b.size - Vector2(32, 32))
	b.set_meta("body", box)
	var top := CenterContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_disc(icon, col, 116))
	box.add_child(top)
	var name := Styles.keep_words(Styles.caps(title, 30))
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size.x = 60
	box.add_child(name)
	var tr := HFlowContainer.new()
	tr.alignment = FlowContainer.ALIGNMENT_CENTER
	tr.add_theme_constant_override("h_separation", 8)
	tr.add_theme_constant_override("v_separation", 6)
	if rare:
		tr.add_child(W.chip("Rare", Styles.AMBER, true, 14))
	tr.add_child(TagPips.new(tag, int(counts.get(tag, 0))))
	for e in extra:
		tr.add_child(e)
	box.add_child(tr)
	if not stats.is_empty():
		var sr := HFlowContainer.new()
		sr.alignment = FlowContainer.ALIGNMENT_CENTER
		sr.add_theme_constant_override("h_separation", 8)
		sr.add_theme_constant_override("v_separation", 8)
		for s in stats:
			sr.add_child(StatChip.new(str(s[0]), str(s[1]), col, 34))
		box.add_child(sr)
	var d := Tips.text(short, 22, Styles.TEXT, 0.0, null, true)
	box.add_child(d)
	if drawback != "":
		var dr := Styles.hbox(6)
		dr.alignment = BoxContainer.ALIGNMENT_CENTER
		var di := W.Icon.new("danger", Styles.DANGER_TEXT, 20, 1.8)
		di.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		dr.add_child(di)
		var dl := Tips.text(drawback, 19, Styles.DANGER_TEXT)
		dl.custom_minimum_size.x = 60
		dr.add_child(dl)
		box.add_child(dr)
	# The card is a Button (for its hover look), which doesn't size to what it holds: grow it
	# to fit, so big text sizes push the card taller instead of spilling out.
	box.minimum_size_changed.connect(func() -> void:
		b.custom_minimum_size = Vector2(CARD_W, maxf(CARD_H, box.get_combined_minimum_size().y + 32.0)))
	b.pressed.connect(func():
		Feel.sound("pick")
		on_pick.call())
	return b


func _disc(icon: String, col: Color, px: float) -> Control:
	var d := IconDisc.new(icon, col, px)
	return d


## Lays its one child out centred, as wide as it can be up to `max_w`.
class CenterBox extends Container:
	var max_w := 0.0

	func _init(w: float) -> void:
		max_w = w
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var m := Vector2.ZERO
		for c in get_children():
			if c is Control:
				m = m.max((c as Control).get_combined_minimum_size())
		return m

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					var w := maxf(minf(size.x, max_w), (c as Control).get_combined_minimum_size().x)
					fit_child_in_rect(c, Rect2((size.x - w) * 0.5, 0, w, size.y))


## A big icon in a dark disc with a soft glow in the card's colour.
class IconDisc extends Control:
	const Styles := preload("res://ui/styles.gd")
	const Icons := preload("res://ui/icons.gd")
	const Draw := preload("res://ui/bloom_draw.gd")
	var icon := ""
	var color := Styles.AMBER

	func _init(i: String, c: Color, px: float) -> void:
		icon = i
		color = c
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var R := minf(size.x, size.y) * 0.5
		Draw.glow(self, c, R * 1.25, color, 0.55)
		draw_circle(c, R - 1.0, Styles.GROUND)
		draw_circle(c, R - 3.0, Color(color, 0.12))
		draw_arc(c, R - 2.0, 0, TAU, 64, Color(color, 0.75), 2.0, true)
		var ip := R * 1.05
		Icons.draw(self, icon, Rect2(c - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), color, maxf(2.0, R * 0.07))


## The rank as a big numeral in a glowing amber disc.
class RankBadge extends PanelContainer:
	const Styles := preload("res://ui/styles.gd")

	func _init(rank: int) -> void:
		var sb := Styles.glow_box(Color(Styles.AMBER, 0.14), Styles.AMBER, Color(Styles.AMBER, 0.35), 10, 46)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		add_theme_stylebox_override("panel", sb)
		custom_minimum_size = Vector2(92, 92)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", -2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := Styles.caps("Rank", 12, Styles.AMBER_LIGHT)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cap)
		var n := Styles.display(str(rank), 40, Styles.AMBER)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		add_child(v)


## A number as a chip: the value big in mono, its label in small caps under it.
class StatChip extends PanelContainer:
	const Styles := preload("res://ui/styles.gd")

	func _init(value: String, what: String, col: Color, size := 26) -> void:
		var sb := Styles.panel_box(Color(col, 0.1), Color(col, 0.45), 12)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 5
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := Styles.mono(value, size, col.lerp(Styles.TEXT, 0.25))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		var l := Styles.caps(what, maxi(11, roundi(size * 0.45)), Styles.DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		add_child(v)


## One soldier stat: icon, big value, label; a hovered card's change shows as "+1" in amber.
class StatTile extends PanelContainer:
	const Styles := preload("res://ui/styles.gd")
	const W := preload("res://ui/widgets.gd")
	const INFO := {"max_hp": ["health", "Max HP", Styles.HP], "aim": ["shoot", "Aim", Styles.TEXT],
		"mobility": ["move", "Move", Styles.TEXT], "defense": ["armor", "Defense", Styles.TEXT]}
	var base := 0
	var _value: Label
	var _delta: Label
	var _sb: StyleBoxFlat

	func _init(key: String, v: int) -> void:
		base = v
		_sb = Styles.panel_box(Color(1, 1, 1, 0.03), Styles.BORDER_SOFT, 12)
		_sb.content_margin_left = 10
		_sb.content_margin_right = 8
		_sb.content_margin_top = 6
		_sb.content_margin_bottom = 6
		add_theme_stylebox_override("panel", _sb)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var info: Array = INFO[key]
		var h := Styles.hbox(8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := W.Icon.new(info[0], info[2], 26, 2.0)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var col := Styles.vbox(-3)
		var top := Styles.hbox(4)
		_value = Styles.mono(str(v), 28, Styles.TEXT)
		top.add_child(_value)
		_delta = Styles.mono("", 20, Styles.AMBER)
		_delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(_delta)
		col.add_child(top)
		col.add_child(Styles.caps(info[1], 13, Styles.DIM))
		h.add_child(col)
		add_child(h)

	func set_delta(d: int) -> void:
		_value.text = str(base + d)
		_value.add_theme_color_override("font_color", Styles.AMBER_LIGHT if d != 0 else Styles.TEXT)
		_delta.text = ("+%d" % d if d > 0 else str(d)) if d != 0 else ""
		_sb.border_color = Styles.AMBER if d != 0 else Styles.BORDER_SOFT


## A tag chip in the tag's own colour (Mark, Guard...) with its set-bonus pips: what the soldier
## has now, plus a ghost pip for this card. "SET" when this card completes the set.
class TagPips extends PanelContainer:
	const Styles := preload("res://ui/styles.gd")
	const W := preload("res://ui/widgets.gd")
	const Tips := preload("res://ui/tips/tips.gd")

	func _init(tag: String, have: int) -> void:
		var c := GearData.tag_color(tag) if tag != "" else Styles.DIM
		var sb := Styles.panel_box(Color(c, 0.1), Color(c, 0.7), Styles.PILL)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		add_theme_stylebox_override("panel", sb)
		mouse_filter = Control.MOUSE_FILTER_PASS
		var h := Styles.hbox(8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(Styles.caps(tag if tag != "" else "No tag", 17, c))
		if tag != "":
			var need := GearData.SET_THRESHOLD
			var pips := W.Pips.new(Vector2(16, 7))
			pips.set_values(need, mini(have, need), 0, c, 1 if have < need else 0)
			pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(pips)
			if have + 1 == need:
				h.add_child(Styles.caps("Set", 14, Styles.TEXT))
			Tips.term(self, "tag_" + tag.to_lower())
		add_child(h)


## Bonded mutations pick a partner: another player's soldier in co-op, any other soldier solo.
func _partner_picker(r: Dictionary) -> Control:
	var opt := OptionButton.new()
	opt.mouse_filter = Control.MOUSE_FILTER_STOP
	var sids: Array = []
	for o in Progression.bond_partners(run, r):
		sids.append(o.id)
		opt.add_item("Bond with %s" % o.get("name", "?"))
	if sids.is_empty():
		opt.add_item("Needs another player's soldier" if run.players.size() > 1 else "Needs a second soldier")
		opt.disabled = true
	else:
		_partner[r.id] = sids[0]
		opt.item_selected.connect(func(i): _partner[r.id] = sids[i])
	return opt


func _graft(p: int, r: Dictionary, id: String) -> void:
	var act := {"type": "prog_graft", "player": p, "sid": r.id, "mutation": id}
	if MutationData.get_def(id).get("bonded", false):
		act["partner"] = _partner.get(r.id, -1)
	_submit(act)


func _submit(action: Dictionary) -> void:
	if session != null and session.has_method("submit_run"):
		session.submit_run(action)
	else:
		RunRules.apply(run, action)
	rebuild()
