extends TestCase
## Glossary hover cards: every term is well formed and links only to real terms, text linking
## finds terms by name and alias, every card builds compact and expanded, and the TermTips host
## opens, nests and closes cards and reads plain tooltip_text too.

const Tips := preload("res://ui/tips/tips.gd")
const TipCard := preload("res://ui/tips/tip_card.gd")
const TipArt := preload("res://ui/tips/tip_art.gd")
const TermTips := preload("res://ui/tips/term_tips.gd")
const Icons := preload("res://ui/icons.gd")
const Styles := preload("res://ui/styles.gd")


func _root() -> Window:
	return (Engine.get_meta("test_tree") as SceneTree).root


func test_every_term_is_well_formed() -> void:
	var all := Glossary.all()
	assert_true(all.size() >= 40, "the glossary covers the game's terms")
	var link := RegEx.create_from_string("\\{([a-z0-9_]+)")
	for k in all:
		var e: Dictionary = all[k]
		assert_true(str(e.get("name", "")) != "", "%s has a name" % k)
		assert_true(str(e.get("line", "")).length() <= 110, "%s keeps its line short" % k)
		assert_true(e.get("stats", []).size() <= 3, "%s shows at most three numbers" % k)
		assert_true(e.get("more", []).size() <= 4, "%s keeps the detail view short" % k)
		var art := str(e.get("art", ""))
		assert_true(art == "" or TipArt.supports(art), "%s art %s is drawable" % [k, art])
		for see in e.get("see", []):
			assert_true(Glossary.has(str(see)), "%s links to a real term (%s)" % [k, see])
		var texts: Array = [str(e.line)] + e.get("more", [])
		for st in e.get("stats", []):
			texts.append(str(st[1]))
		for t in texts:
			for m in link.search_all(str(t)):
				assert_true(Glossary.has(m.get_string(1)), "%s links {%s}" % [k, m.get_string(1)])


func test_term_icons_exist() -> void:
	# Icons.draw falls back silently, so check every id is a real case in icons.gd.
	var src := FileAccess.get_file_as_string("res://ui/icons.gd")
	for k in Glossary.all():
		var id := str(Glossary.entry(k).get("icon", ""))
		assert_true(src.contains("\"%s\"" % id), "%s icon %s is drawn by Icons" % [k, id])


func test_text_linking() -> void:
	assert_eq(Glossary.find("Half cover"), "cover", "an alias finds its term")
	assert_eq(Glossary.find("Aim"), "hit_chance", "a breakdown label finds its term")
	assert_eq(Glossary.find("High ground"), "high_ground")
	assert_eq(Glossary.find("Close"), "tag_close", "gear tag names resolve exactly")
	var found := Glossary.scan("Hunkered behind half cover, Infection 60, close to the wall")
	assert_eq(found, ["hunker", "cover", "infection"] as Array[String], "prose links names and aliases, not gear tag words")
	var bb := Glossary.bbcode("Lapses at 50. A {turning|Turned} soldier. Lapse again.")
	assert_true(bb.contains("[url=lapse]"), "a name becomes a link")
	assert_true(bb.contains("[url=turning]") and bb.contains("Turned"), "{key|text} links with its own words")
	assert_eq(bb.count("[url=lapse]"), 1, "only the first mention is linked")
	assert_eq(Glossary.plain("{lapse|Lapses} and {outbreak}"), "Lapses and Outbreak")


func test_every_card_builds() -> void:
	var holder := Control.new()
	holder.theme = Styles.make_theme()
	_root().add_child(holder)
	for k in Glossary.all():
		for wide in [false, true]:
			var c := TipCard.new([k], "", {"value": 40, "count": 2})
			c.set_expanded(wide)
			holder.add_child(c)
			assert_true(c.get_child(0).get_child_count() >= 2, "%s card has content" % k)
			if wide:
				assert_true(c.custom_minimum_size.x >= TipCard.WIDE, "expanded card is wider")
			c.free()
	var text := TipCard.new([], "Healing raises Outbreak by 1.", {})
	text.set_expanded(true)
	holder.add_child(text)
	assert_true(text.get_child(0).get_child_count() >= 3, "a text card shows its linked terms when expanded")
	holder.free()


func test_host_opens_nests_and_closes() -> void:
	var tips := TermTips.new()
	_root().add_child(tips)
	tips._ready()   # the tree isn't running yet in the test runner
	var b := Button.new()
	b.size = Vector2(80, 30)
	_root().add_child(b)
	Tips.term(b, "cover")
	assert_eq(TermTips.content_of(b).terms, ["cover"])
	tips.show_for(b)
	assert_eq(tips.cards.size(), 1, "a card opens for a tagged control")
	assert_eq(tips.cards[0].key, "cover")
	tips.open_nested(0, "hunker")
	assert_eq(tips.cards.size(), 2, "a term inside a card opens its own card")
	tips.open_nested(0, "flank")
	assert_eq(tips.cards.size(), 2, "a new link replaces the nested card")
	assert_eq(tips.cards[1].key, "flank")
	tips.set_expanded(true)
	assert_true(tips.cards[0].expanded and tips.cards[1].expanded, "Shift expands every open card")
	tips.close_all()
	assert_eq(tips.cards.size(), 0)
	var plain := Label.new()
	plain.mouse_filter = Control.MOUSE_FILTER_STOP
	plain.tooltip_text = "Rises by 1 at every node."
	_root().add_child(plain)
	assert_eq(TermTips.content_of(plain).text, "Rises by 1 at every node.", "plain tooltips use the same card")
	Tips.off(plain)
	assert_true(TermTips.content_of(plain).is_empty(), "Tips.off silences a control")
	var inner := Label.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	b.add_child(inner)
	assert_eq(TermTips.source_of(inner), b, "a child passing the mouse up shows its parent's card")
	tips.free()
	b.free()
	plain.free()


func test_godot_tooltips_are_replaced() -> void:
	assert_true(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")) > 1000.0,
		"the engine's own tooltip never shows; TermTips draws them")
	assert_true(GameSettings.ACTIONS.any(func(a) -> bool: return a[0] == "tip_more"), "the detail key is rebindable")


func test_class_cards() -> void:
	var ClassTip := preload("res://ui/tips/class_tip.gd")
	var holder := Control.new()
	holder.theme = Styles.make_theme()
	_root().add_child(holder)
	for k in UnitData.SOLDIERS:
		assert_true(ClassTip.ROLES.has(k), "%s has a role line" % k)
		assert_true(PerkData.PASSIVES.has(k), "%s has a passive to show" % k)
		for id in UnitData.SOLDIERS[k].abilities:
			assert_true(not ClassTip.ability(str(id)).is_empty(), "%s ability %s has rules text" % [k, id])
			assert_true(ClassTip.short_lines().has(str(id)), "%s ability %s has a one-liner" % [k, id])
			assert_true(ClassTip.ability_icon(str(id)) != "ability", "%s ability %s has its own icon" % [k, id])
		for locked in [false, true]:
			for wide in [false, true]:
				var c := TipCard.new([], "", {"class": k, "locked": locked})
				c.set_expanded(wide)
				holder.add_child(c)
				assert_true(c.custom_minimum_size.x >= (TipCard.CLASS_WIDE if wide else TipCard.CLASS_WIDTH), "%s card width" % k)
				assert_true(c.get_child(0).get_child_count() >= 10, "%s card shows stats, gun, abilities and passive" % k)
				c.free()
	var dmr := Weapons.get_gun("dmr")
	assert_eq(ClassTip.range_aim(dmr, 1.0), -10, "the scope penalty shows up close")
	assert_eq(ClassTip.range_aim(Weapons.get_gun("shotgun"), 7.0), -16, "shotgun falls off 8 a tile past 5")
	var b := Button.new()
	Tips.soldier_class(b, "warden", true)
	assert_eq(TermTips.content_of(b).ctx, {"class": "warden", "locked": true}, "a tile opens the class card")
	holder.free()
	b.free()
