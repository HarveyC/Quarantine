class_name EnemyAI
extends RefCounted
## Decides actions for AI-controlled units: enemies, and soldiers that have Lapsed.
## OWNER: AI workstream. take_turn is the contract; the body is a placeholder.


## Spend `u.actions_left` by calling Rules.apply(s, action) until done.
## Must never call Rules.apply with an illegal action in a loop (always make progress).
static func take_turn(s: GameState, u: Unit) -> void:
	var guard := 0
	while u.is_alive() and u.actions_left > 0 and s.phase != Types.Phase.ENDED and guard < 4:
		guard += 1
		var targets := Combat.visible_targets(s, u)
		if not targets.is_empty():
			Rules.apply(s, {"type": Types.SHOOT, "unit": u.id, "target": targets[0].id})
			continue
		var nearest := _nearest_enemy(s, u)
		if nearest == null:
			return
		var best := u.pos
		for c in Rules.move_range(s, u):
			if c.distance_squared_to(nearest.pos) < best.distance_squared_to(nearest.pos):
				best = c
		if best == u.pos or not Rules.apply(s, {"type": Types.MOVE, "unit": u.id, "to": best}):
			return


static func _nearest_enemy(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	for t in s.units:
		if t.is_alive() and u.is_enemy_of(t):
			if best == null or u.pos.distance_squared_to(t.pos) < u.pos.distance_squared_to(best.pos):
				best = t
	return best
