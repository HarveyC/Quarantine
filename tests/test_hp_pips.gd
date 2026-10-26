extends TestCase
## HP pips: one per HP in rows of 10 up to 30 HP, then each pip stands for several HP and an
## xN multiplier appears, so a 100+ HP monster stays two short rows.

const W := preload("res://ui/widgets.gd")
const Styles := preload("res://ui/styles.gd")
const Tips := preload("res://ui/tips/tips.gd")


func test_small_units_keep_one_pip_per_hp() -> void:
	assert_eq(W.HpPips.per_pip(5), 1, "a Runner is one pip per HP")
	assert_eq(W.HpPips.per_pip(22), 1, "a late Warden too")
	assert_eq(W.HpPips.per_pip(30), 1, "up to 30 HP")
	assert_eq(W.HpPips.rows_for(22), 3, "22 HP is three rows")


func test_big_monsters_chunk_into_at_most_two_rows() -> void:
	assert_eq(W.HpPips.per_pip(40), 2, "40 HP is x2")
	assert_eq(W.HpPips.per_pip(100), 5, "100 HP is x5")
	assert_eq(W.HpPips.per_pip(150), 10, "150 HP is x10")
	for hp in [31, 40, 48, 99, 100, 101, 250, 999, 5000]:
		assert_true(W.HpPips.pips_for(hp) <= W.HpPips.MAX_CHUNKED_PIPS, "%d HP fits 20 pips" % hp)
		assert_true(W.HpPips.rows_for(hp) <= 2, "%d HP is at most two rows" % hp)


func test_width_and_multiplier() -> void:
	var small := W.HpPips.new(Vector2(7, 4))
	small.set_values(10, 10)
	var boss := W.HpPips.new(Vector2(7, 4))
	boss.set_values(120, 90, 15, Styles.DANGER)
	assert_eq(boss.per, 10, "120 HP is x10")
	assert_eq(boss.lose, 15, "damage preview kept")
	assert_true(boss.has_meta(Tips.META), "the multiplier is hoverable")
	assert_eq(boss.mouse_filter, Control.MOUSE_FILTER_PASS, "and catches the pointer")
	assert_true(Glossary.has(W.HpPips.TIP_KEY), "its glossary card exists")
	assert_true(not small.has_meta(Tips.META), "one pip per HP has no multiplier card")
	assert_eq(W.HpPips.TIP_META, Tips.META, "the meta name matches")
	small.free()
	boss.free()


func test_group_gap_after_five() -> void:
	var p := W.HpPips.new(Vector2(7, 4))
	p.set_values(10, 10)
	var step: float = p._pip_x(1) - p._pip_x(0)
	assert_true(p._pip_x(5) - p._pip_x(4) > step, "wider gap between pip 5 and 6")
	assert_eq(p._pip_x(10), p._pip_x(0), "pip 11 starts the next row")
	p.free()
