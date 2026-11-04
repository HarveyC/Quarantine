extends TestCase
## Card style guide: an action's cost lives only in the card's first fact cell, never in its rules
## text, and an action button shows one card (no plain tooltip stacked over it).

const ActionCard := preload("res://ui/tips/action_card.gd")
const Tips := preload("res://ui/tips/tips.gd")
const TermTips := preload("res://ui/tips/term_tips.gd")
const TipCard := preload("res://ui/tips/tip_card.gd")
const COST_WORDS := ["Ends turn", "ends turn", "Costs "]
## "1 action." / "2 actions," as a cost, but not "+1 action" (a gain).
static var _cost_re := RegEx.create_from_string("(^|[^+\\d])\\d actions?[.,]")


func _no_cost_words(desc: String, who: String) -> void:
	for w in COST_WORDS:
		assert_true(not desc.contains(w), "%s: no cost words in '%s'" % [who, desc])
	assert_true(_cost_re.search(desc) == null, "%s: no action count in '%s'" % [who, desc])


func test_ability_text_has_no_cost_words() -> void:
	for id in Combat.ABILITIES:
		_no_cost_words(str(Combat.ABILITIES[id].desc), id)
	for id in ClassAbilities.ABILITIES:
		_no_cost_words(str(ClassAbilities.ABILITIES[id].desc), id)


func test_every_ability_declares_its_cost() -> void:
	for id in ClassAbilities.ABILITIES:
		assert_true(ClassAbilities.ABILITIES[id].has("cost"), "%s has a cost" % id)
	for id in Combat.ABILITIES:
		assert_true(Combat.ABILITIES[id].has("cost"), "%s has a cost" % id)


func test_split_takes_first_sentence() -> void:
	var sp := ActionCard.split("Dash to a foe for 4-6. Only half cover counts. Kills add 5.")
	assert_eq(sp[0], "Dash to a foe for 4-6.")
	assert_eq(sp[1].size(), 2)
	assert_eq(ActionCard.split("One line.")[1].size(), 0)


func test_action_button_gets_one_card() -> void:
	var b := Button.new()
	Tips.action(b, {"key": "reload", "label": "Reload", "cost": 1, "desc": "Refill the magazine (5 of 6 rounds)."})
	assert_eq(b.tooltip_text, "", "no plain tooltip stacked over the card")
	var c := TermTips.content_of(b)
	assert_true(c.ctx.has("action"), "the card is the action card")
	b.free()


func test_action_cards_build() -> void:
	for a in [
		{"key": "reload", "label": "Reload", "cost": 1, "desc": "Refill the magazine (5 of 6 rounds)."},
		{"key": "ability:lunge", "id": "lunge", "label": "Lunge", "cost": -1, "cooldown": 2, "desc": "Dash to a foe. Only half cover counts.", "reason": "Gun drawn: swap weapon first"},
		{"key": "hunker", "label": "Hunker", "cost": -1},
		{"key": "ability:tag", "id": "tag", "label": "Mark", "cost": 1, "desc": "Mark a visible enemy."}]:
		for full in [false, true]:
			var c := TipCard.new([], "", {"action": a})
			c.set_expanded(full)
			assert_true(c.get_child_count() > 0, "%s builds (expanded %s)" % [a.label, full])
			c.free()


func test_gear_facts() -> void:
	assert_eq(ActionCard.gear_effect("Once per fight, free: +15 Infection to yourself"), "+15 Infection to yourself")
	assert_eq(ActionCard.gear_effect("Cooldown 3: Mark every enemy"), "Mark every enemy")
	assert_eq(ActionCard.gear_effect("Hits Mark the target"), "Hits Mark the target")
	var flare := ActionCard.gear_cells("flare_launcher", 1)
	assert_eq(flare[0][1], "Action", "cost comes first")
	assert_true(flare.any(func(c): return c[1] == "Cooldown" and c[0] == "3"), "cooldown cell")
	var pump := ActionCard.gear_cells("adrenal_pump", 2)
	assert_eq(pump[0][0], "0", "a free action shows 0")
	assert_true(pump.any(func(c): return c[1] == "Per fight" and c[0] == "2"), "uses per fight")
	assert_eq(ActionCard.gear_cells("tracer_rounds", 1).size(), 0, "passive gear has no fact row")
	for id in GearFx.GADGETS:
		for mk in [1, 2]:
			assert_true(ActionCard.gear_effect(GearData.desc(id, mk)).length() > 0, "%s mk%d effect" % [id, mk])
