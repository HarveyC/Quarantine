extends TestCase
## Card style guide: an action's cost lives only in the card's first fact cell, never in its rules
## text, and an action button shows one card (no plain tooltip stacked over it).

const ActionCard := preload("res://ui/tips/action_card.gd")
const Tips := preload("res://ui/tips/tips.gd")
const COST_WORDS := ["Ends turn", "ends turn", "1 action", "2 actions", "Costs "]


func _no_cost_words(desc: String, who: String) -> void:
	for w in COST_WORDS:
		assert_true(not desc.contains(w), "%s: no cost words in '%s'" % [who, desc])


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
