extends TestCase
## HP pips wrap into rows of 10 (XCOM 2 style), so tough units grow taller, not wider.

const W := preload("res://ui/widgets.gd")
const Styles := preload("res://ui/styles.gd")


func test_rows_wrap_at_ten() -> void:
	assert_eq(W.HpPips.rows_for(5), 1, "a Runner is one row")
	assert_eq(W.HpPips.rows_for(10), 1, "10 HP still fits one row")
	assert_eq(W.HpPips.rows_for(22), 3, "a late Warden is three rows")
	assert_eq(W.HpPips.rows_for(40), 4, "the Brood Mother is four rows")


func test_width_stops_at_one_row() -> void:
	var small := W.HpPips.new(Vector2(7, 4))
	small.set_values(10, 10)
	var boss := W.HpPips.new(Vector2(7, 4))
	boss.set_values(40, 31, 5, Styles.DANGER)
	assert_eq(boss.custom_minimum_size.x, small.custom_minimum_size.x, "a 40 HP boss is no wider than 10 HP")
	assert_true(boss.custom_minimum_size.y > small.custom_minimum_size.y, "it grows taller instead")
	assert_eq(boss.lose, 5, "damage preview kept")
	small.free()
	boss.free()


func test_group_gap_after_five() -> void:
	var p := W.HpPips.new(Vector2(7, 4))
	p.set_values(10, 10)
	var step: float = p._pip_x(1) - p._pip_x(0)
	assert_true(p._pip_x(5) - p._pip_x(4) > step, "wider gap between pip 5 and 6")
	assert_eq(p._pip_x(10), p._pip_x(0), "pip 11 starts the next row")
	p.free()
