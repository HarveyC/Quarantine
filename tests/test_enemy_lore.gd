extends TestCase
## Every enemy kind has a short in-world line for its Shift card.


func test_every_enemy_has_a_lore_line() -> void:
	for kind in UnitData.ENEMIES:
		assert_true(EnemyLore.line(kind) != "", "no lore line for %s" % kind)
