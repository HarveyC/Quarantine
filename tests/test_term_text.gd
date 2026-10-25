extends TestCase
## Game terms in body text: rules text on screens names its mechanics in bold, each bold word
## opens that term's hover card, and every mechanical term the game's rules text uses has a
## glossary entry (standing UI rule: any term in UI text is bold and explained on hover).

const TermText := preload("res://ui/tips/term_text.gd")
const TermTips := preload("res://ui/tips/term_tips.gd")
const Tips := preload("res://ui/tips/tips.gd")
const Styles := preload("res://ui/styles.gd")
const GearCard := preload("res://ui/gear/gear_card.gd")

## Where the rules text players read comes from, and the fields that hold it.
const SOURCES := ["res://gear/gear_data.gd", "res://combat/weapons.gd", "res://combat/combat.gd",
	"res://progression/class_abilities.gd", "res://progression/perk_data.gd", "res://progression/perk_brief.gd",
	"res://progression/mutation_data.gd", "res://progression/graft_data.gd", "res://nodes/hospital.gd",
	"res://nodes/event_data.gd", "res://gear/deploy_orders.gd", "res://meta/meta_unlocks.gd",
	"res://meta/severity.gd"]
const FIELDS := ["desc", "desc_mk2", "effect", "rule", "about", "short", "drawback", "bonus"]

## Capitalised words in rules text that are not mechanics: fiction, flavour lead-ins on gun
## lines, rarities and slot words. Anything else capitalised mid-sentence, or any "Label:"
## lead-in, must be a glossary term. Names of items, guns, perks, mutations, grafts, classes
## and enemies are allowed automatically.
const NOT_TERMS := ["Bloom", "Source", "Command", "Hive", "Whispers", "Infected", "Infested",
	"Backup pistol", "Heavier rounds", "Light and quick", "Single slugs", "Sprays up close", "Steady",
	"Bursts", "Bursts out", "Shoulder", "New ability", "Build basics", "Common", "Uncommon", "Rare", "Rares", "Machine",
	# "Turn" as in becoming Infected: linking it would also catch every "this turn".
	"Turn"]


func _root() -> Window:
	return (Engine.get_meta("test_tree") as SceneTree).root


func test_body_text_bolds_terms() -> void:
	var t: RichTextLabel = TermText.make("Infection from spores is halved. Beds in: -1 move next fight.", 15, Styles.DIM, 280)
	assert_true(t.terms.has("bedding_in"), "\"Beds in\" is a term")
	assert_true(t.terms.has("mobility") and t.terms.has("infection"), "move and Infection are terms")
	assert_true(t.text.contains("[url=bedding_in][b]"), "a term is a bold link")
	assert_eq(t.text.count("[url="), t.terms.size(), "each term is linked once")
	assert_eq(t.mouse_filter, Control.MOUSE_FILTER_PASS, "text with terms takes hover, passes clicks on")
	var plain: RichTextLabel = TermText.make("Reliable at any range.", 15)
	assert_true(plain.terms.is_empty())
	assert_eq(plain.mouse_filter, Control.MOUSE_FILTER_IGNORE, "text without terms stays out of the mouse's way")
	t.free()
	plain.free()


func test_hovering_a_bold_word_opens_its_card() -> void:
	var holder := Control.new()
	holder.theme = Styles.make_theme()
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.tooltip_text = "The card under the text."
	_root().add_child(holder)
	var t: RichTextLabel = Tips.text("Once per fight, 1 action: an adjacent ally loses 15 Infection", 15, Styles.DIM, 280)
	holder.add_child(t)
	assert_eq(TermTips.source_of(t), holder, "off the bold words, the control underneath shows its own card")
	t.call("_on_hover", "once_per_fight")
	assert_eq(TermTips.source_of(t), t, "on a bold word, the text is the source")
	assert_eq(TermTips.content_of(t).terms, ["once_per_fight"], "...and shows that word's card")
	var tips := TermTips.new()
	_root().add_child(tips)
	tips._ready()
	tips.show_for(t)
	assert_eq(tips.cards.size(), 1)
	assert_eq(tips.cards[0].key, "once_per_fight")
	t.call("_on_unhover", null)
	assert_eq(TermTips.source_of(t), holder, "leaving the word hands back to the control underneath")
	tips.free()
	holder.free()


func test_term_links_in_cards_are_bold() -> void:
	assert_true(Glossary.bbcode("Hunker behind cover").contains("[b]"), "links in hover cards are bold too")


func test_cards_use_bold_terms() -> void:
	# A Refit offer reads "... Beds in: -1 move next fight."; a gear card's effect line is
	# rules text too. Both must come out as linked text, not a plain label.
	var holder := Control.new()
	holder.theme = Styles.make_theme()
	_root().add_child(holder)
	var run := RunRules.new_run(1, 5)
	RunRules.start_run(run)
	var rec: Dictionary = run.squad()[0]
	var c := GearCard.new()
	holder.add_child(c)
	c.setup({"kind": "gear", "id": "thermite_charge"}, rec, 0)
	var linked := c.find_children("*", "RichTextLabel", true, false).filter(
		func(n) -> bool: return n.get_script() == TermText and n.terms.has("once_per_fight"))
	assert_true(not linked.is_empty(), "a gear card's effect names \"Once per fight\" as a hoverable term")
	holder.free()


func test_screens_put_rules_text_in_term_text() -> void:
	# Rules text (an effect, a bonus, a rule) must go through Tips.text / UI.text, never a plain
	# label, so its terms are bold and hoverable. Story screens tell fiction and are exempt.
	var rx := RegEx.create_from_string("label\\([^)]*(\\.desc|\\.bonus|\\.rule|\\.about|drawback|\\.short\\b)")
	var files: Array[String] = []
	_gd_files("res://ui", files)
	files.append("res://progression/pick_screen.gd")
	for f in files:
		if f.contains("/story/"):
			continue
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			assert_true(rx.search(lines[i]) == null,
				"%s:%d puts rules text in a plain label; use Tips.text so its terms are bold" % [f, i + 1])


func test_rules_text_terms_have_glossary_entries() -> void:
	var texts := _rules_texts()
	assert_true(texts.size() > 300, "found the game's rules text (%d lines)" % texts.size())
	var names := _known_names()
	var cap := RegEx.create_from_string("(?<=[a-z0-9,;)] )([A-Z][a-z]+(?: [A-Z][a-z]+)*)")
	var lead := RegEx.create_from_string("(?:^|[.:] )([A-Z][a-z]+(?: [a-z]+){0,2}):")
	var missing := {}
	for t in texts:
		for rx in [cap, lead]:
			for m in rx.search_all(t):
				var w: String = m.get_string(1)
				if Glossary.find(w) == "" and Glossary.scan(w).is_empty() and not names.has(w.to_lower()) \
						and not NOT_TERMS.has(w):
					missing[w] = t
	for w in missing:
		assert_true(false, "\"%s\" reads like a game term but has no glossary entry (in \"%s\"). Add it to data/glossary.gd, or to NOT_TERMS if it isn't a mechanic." % [w, missing[w]])


func _rules_texts() -> Array[String]:
	var out: Array[String] = []
	for p in SOURCES:
		var m := (load(p) as Script).get_script_constant_map()
		for k in m:
			_collect(m[k], "", out)
	for id in GearData.TAG_INFO:
		out.append(str(GearData.TAG_INFO[id].bonus))
	return out


func _collect(v: Variant, under: String, out: Array[String]) -> void:
	if v is Dictionary:
		for k in v:
			_collect(v[k], str(k), out)
	elif v is Array:
		for x in v:
			_collect(x, under, out)
	elif v is String and FIELDS.has(under):
		out.append(v)


## Lower-case names of things (items, guns, perks, mutations, grafts, classes, enemies), and
## their plurals: proper names, not mechanics.
func _known_names() -> Dictionary:
	var out := {}
	var tables: Array = [GearData.ITEMS, GearData.PROTOTYPES, GearData.CONSUMABLES, GearData.DOCTRINES,
		Weapons.TABLE, PerkData.PERKS, PerkData.PASSIVES, MutationData.MUTATIONS, GraftData.GRAFTS,
		UnitData.SOLDIERS, UnitData.ENEMIES, EnemyAbilities.DEFS]
	for table in tables:
		for id in table:
			var e: Variant = table[id]
			if e is Dictionary and e.has("name"):
				var n := str(e.name).to_lower()
				out[n] = true
				out[n + "s"] = true
	for s in GraftData.SLOT_NAMES.values():
		out[str(s).to_lower()] = true
	return out


func _gd_files(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_gd_files(dir + "/" + sub, out)
