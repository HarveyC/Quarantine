extends TestCase
## Active abilities go on cooldown when used, say so in the HUD list, and count down one per team
## turn. Playtest v0.22.4: "active items sometimes don't go on cooldown". Other actions (moves,
## Adrenal Surge's extra action) must neither clear nor skip the timer.

const ROWS := ["..........", "..........", "..........", "..........", ".........."]


func _setup(kind: String) -> Dictionary:
	var s := make_blank(PackedStringArray(ROWS))
	var sol := s.add_unit(UnitData.make(kind, Types.Team.PLAYER), Vector2i(1, 2))
	sol.owner_player = 0
	s.add_unit(UnitData.make("runner", Types.Team.ENEMY), Vector2i(9, 4))
	s.turn = 1
	s.phase = Types.Phase.TEAM
	s.players.assign([0])
	sol.actions_left = Types.ACTIONS_PER_TURN
	return {"s": s, "sol": sol}


func _entry(s: GameState, u: Unit, id: String) -> Dictionary:
	for a in Combat.available_abilities(s, u):
		if a.id == id:
			return a
	return {}


func test_stim_cooldown_is_set_listed_and_counts_down() -> void:
	var d := _setup("medic")
	var s: GameState = d.s
	var sol: Unit = d.sol
	if not sol.abilities.has("stim"):
		sol.abilities.append("stim")
	assert_true(_entry(s, sol, "stim").get("ready", false), "ready before use")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": sol.id, "ability": "stim", "target": sol.id}), "stim accepted")
	assert_eq(int(sol.cooldowns.get("stim", 0)), 2, "cooldown set")
	var e := _entry(s, sol, "stim")
	assert_eq(int(e.get("cooldown", -1)), 2, "list reports the cooldown")
	assert_true(not e.get("ready", true), "not ready while cooling")
	assert_true(Rules.apply(s, {"type": Types.MOVE, "unit": sol.id, "to": Vector2i(2, 2)}) or sol.actions_left == 0, "other actions are fine")
	assert_eq(int(sol.cooldowns.get("stim", 0)), 2, "a move leaves the timer alone")
	Rules.set_ready(s, 0, true)
	assert_eq(s.turn, 2, "next turn")
	assert_eq(int(sol.cooldowns.get("stim", 0)), 1, "one turn later")
	assert_true(not _entry(s, sol, "stim").get("ready", true), "still cooling")
	Rules.set_ready(s, 0, true)
	assert_eq(s.turn, 3, "turn after")
	assert_eq(int(sol.cooldowns.get("stim", 0)), 0, "recharged")
	assert_true(_entry(s, sol, "stim").get("ready", false), "ready again")


func test_signature_cooldown_survives_adrenal_surge() -> void:
	var d := _setup("trooper")
	var s: GameState = d.s
	var sol: Unit = d.sol
	sol.abilities.append("lockdown")
	sol.status["mutations"] = {"exposed": "adrenal_surge"}
	Infection.add(s, sol, 25)
	assert_true(Rules.apply(s, {"type": Types.MUTATION, "unit": sol.id, "mutation": "adrenal_surge"}), "surge accepted")
	assert_eq(sol.actions_left, 3, "three actions")
	assert_true(Rules.apply(s, {"type": Types.ABILITY, "unit": sol.id, "ability": "lockdown"}), "lockdown accepted")
	assert_eq(int(sol.cooldowns.get("lockdown", 0)), ClassAbilities.ABILITIES.lockdown.cooldown, "signature on cooldown")
	assert_true(not _entry(s, sol, "lockdown").get("ready", true), "listed as not ready")
