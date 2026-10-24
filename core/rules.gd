class_name Rules
extends RefCounted
## Turn flow and action dispatch. The single entry point for changing GameState.
## Module-specific behaviour is delegated to Combat, Infection and EnemyAI.


## Builds a mission from a map file. `squad` is an Array of {"kind": String, "player": int}.
static func new_mission(map_path: String, squad: Array, enemies: Array[String], seed: int = 0) -> GameState:
	return new_mission_on_grid(Grid.load_file(map_path), squad, enemies, seed)


## Same, on a grid built elsewhere (MapGen). Squad entries from a run (they carry "sid") get
## their persistent HP, Infection, perks and gear through RunSoldier.apply_entry.
static func new_mission_on_grid(grid: Grid, squad: Array, enemies: Array[String], seed: int = 0) -> GameState:
	var s := GameState.new()
	s.rng.seed = seed if seed != 0 else randi()
	s.grid = grid
	var players := {}
	for i in squad.size():
		var u := UnitData.make(squad[i].kind, Types.Team.PLAYER)
		u.owner_player = squad[i].player
		players[u.owner_player] = true
		s.add_unit(u, s.grid.player_spawns[i])
		if squad[i].has("sid"):
			RunSoldier.apply_entry(s, u, squad[i])
		elif squad[i].has("prog"):
			Progression.apply_record(u, squad[i].prog)
	s.players.assign(players.keys())
	for i in enemies.size():
		var spawn := s.grid.enemy_spawns[i % s.grid.enemy_spawns.size()]
		if s.unit_at(spawn) != null:
			spawn = _nearest_free(s, spawn)
		s.add_unit(EnemyRoster.make(enemies[i]), spawn)
	Objectives.setup(s)
	return s


## Closest walkable unoccupied cell to `c` (for spawns beyond the map's spawn points).
static func _nearest_free(s: GameState, c: Vector2i) -> Vector2i:
	var dist := s.grid.reachable(c, 32, s.occupied())
	var best := c
	for cell in dist:
		if cell != c and (best == c or dist[cell] < dist[best]):
			best = cell
	return best


static func start_mission(s: GameState) -> void:
	s.turn = 0
	start_team_phase(s)


static func start_team_phase(s: GameState) -> void:
	s.turn += 1
	s.phase = Types.Phase.TEAM
	s.ready.clear()
	for p in s.players:
		s.ready[p] = not commands_a_soldier(s, p)   # a co-op player whose soldier is down just watches
	for u in s.living(Types.Team.PLAYER):
		u.actions_left = Types.ACTIONS_PER_TURN
		if s.turn == 1 and u.status.get("first_turn_action_loss", false):
			u.actions_left -= 1   # event: Whispers, "fight it"
		u.overwatch = false
		u.hunkered = false
		for k in u.cooldowns.keys():
			u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
	Vision.refresh(s)   # before the event: run saves snapshot the state on it
	s.emit({"type": "team_phase", "turn": s.turn})
	GearFx.on_team_phase_start(s)
	Deployables.on_team_phase_start(s)
	Infection.on_team_phase_start(s)
	Encounter.on_team_phase_start(s)
	Kit.on_team_phase_start(s)
	# Soldiers that have Lapsed act on their own before the squad gets to move.
	for u in s.living(Types.Team.PLAYER):
		if u.ai_controlled:
			u.actions_left = Types.ACTIONS_PER_TURN
			EnemyAI.take_turn(s, u)
			u.actions_left = 0
	Vision.refresh(s)
	check_end(s)


## Returns "" if the action is legal, otherwise a human-readable reason.
static func validate(s: GameState, action: Dictionary) -> String:
	if s.phase == Types.Phase.ENDED:
		return "Mission is over"
	var u := s.get_unit(action.get("unit", -1))
	if u == null or not u.is_alive():
		return "No such unit"
	if u.actions_left <= 0:
		return "No actions left"
	var blocked := Encounter.validate(s, u, action)
	if blocked != "":
		return blocked
	if action.get("type") == Types.ABILITY and EnemyAbilities.handles(str(action.get("ability", ""))):
		return EnemyAbilities.validate(s, u, action)
	var kit_err := Kit.validate(s, u, action)
	if kit_err != "":
		return kit_err
	match action.get("type"):
		Types.MOVE: return _validate_move(s, u, action.get("to", u.pos))
		Types.SHOOT, Types.OVERWATCH, Types.HUNKER, Types.ABILITY: return Combat.validate(s, u, action)
		Types.MUTATION: return Infection.validate_mutation(s, u, action)
	return "Unknown action"


## Validates and applies an action. Returns false (and changes nothing) if illegal.
static func apply(s: GameState, action: Dictionary) -> bool:
	var err := validate(s, action)
	if err != "":
		s.emit({"type": "rejected", "action": action, "reason": err})
		return false
	var u := s.get_unit(action.unit)
	_expose_attacker(s, u, action)
	if action.type == Types.ABILITY and EnemyAbilities.handles(str(action.ability)):
		EnemyAbilities.apply(s, u, action)
		Encounter.after_action(s, u, action)
		Vision.refresh(s)
		check_end(s)
		return true
	Kit.before_action(s, u, action)
	match action.type:
		Types.MOVE: _do_move(s, u, action.to)
		Types.SHOOT, Types.OVERWATCH, Types.HUNKER, Types.ABILITY: Combat.apply(s, u, action)
		Types.MUTATION: Infection.apply_mutation(s, u, action)
	Encounter.after_action(s, u, action)
	Kit.after_action(s, u, action)
	Vision.refresh(s)
	check_end(s)
	return true


## Fog of war: shooting at or attacking a hostile gives the attacker's position away, and so
## do the area attacks below (lobbed spit, airstrike calls). Anything that deals damage also
## exposes its source (deal_damage).
const EXPOSING_CELL_ABILITIES := ["spit", "brood_spit", "airstrike", "flashbang", "core_slam"]


static func _expose_attacker(s: GameState, u: Unit, action: Dictionary) -> void:
	if action.type != Types.SHOOT and action.type != Types.ABILITY:
		return
	var t := s.get_unit(action.get("target", -1))
	if (t != null and u.is_enemy_of(t)) or EXPOSING_CELL_ABILITIES.has(str(action.get("ability", ""))):
		Vision.expose(s, u)


## Whether `player` still has a living soldier to give orders to (deployables and civilians aside).
static func commands_a_soldier(s: GameState, player: int) -> bool:
	return Objectives.soldiers(s).any(func(u: Unit) -> bool: return u.owner_player == player)


## Player readiness for the simultaneous team phase. When everyone is ready the enemy phase runs.
static func set_ready(s: GameState, player: int, is_ready: bool) -> void:
	if s.phase != Types.Phase.TEAM:
		return
	s.ready[player] = is_ready
	s.emit({"type": "ready", "player": player, "ready": is_ready})
	if s.ready.keys().all(func(p): return s.ready[p] or not commands_a_soldier(s, p)):
		Hazards.on_team_phase_end(s)
		Objectives.on_team_phase_end(s)
		check_end(s)
		if s.phase != Types.Phase.ENDED:
			run_enemy_phase(s)


static func run_enemy_phase(s: GameState) -> void:
	s.phase = Types.Phase.ENEMY
	s.emit({"type": "enemy_phase", "turn": s.turn})
	Encounter.on_enemy_phase_start(s)
	Kit.on_enemy_phase_start(s)
	for u in s.living(Types.Team.ENEMY):
		if s.phase == Types.Phase.ENDED:
			return
		if not u.is_alive() or Kit.skips_turn(u):
			continue
		u.actions_left = Types.ACTIONS_PER_TURN
		for k in u.cooldowns.keys():
			u.cooldowns[k] = max(0, u.cooldowns[k] - 1)
		Encounter.on_unit_turn_start(s, u)
		EnemyAI.take_turn(s, u)
		u.actions_left = 0
		Encounter.on_unit_turn_end(s, u)
		Vision.refresh(s)
	if s.phase != Types.Phase.ENDED:
		Encounter.on_enemy_phase_end(s)
	if s.phase != Types.Phase.ENDED:
		Hazards.on_enemy_phase_end(s)
		Objectives.on_enemy_phase_end(s)
		check_end(s)
	if s.phase != Types.Phase.ENDED:
		start_team_phase(s)


## Cells `u` can move to with one move action.
static func move_range(s: GameState, u: Unit) -> Dictionary:
	return s.grid.reachable(u.pos, u.mobility, s.occupied(u.id))


static func _validate_move(s: GameState, u: Unit, to: Vector2i) -> String:
	if to == u.pos:
		return "Already there"
	if not move_range(s, u).has(to):
		return "Out of range"
	return ""


## Moves step by step so overwatch can interrupt. Emits one "move" event per uninterrupted segment.
static func _do_move(s: GameState, u: Unit, to: Vector2i) -> void:
	var path := s.grid.find_path(u.pos, to, s.occupied(u.id))
	u.actions_left -= 1
	u.hunkered = false
	GearFx.on_move(s, u)
	var segment: Array[Vector2i] = []
	var from := u.pos
	for c in path:
		u.pos = c
		segment.append(c)
		Vision.on_step(s, u)
		Kit.on_step(s, u, c)
		var reactors := Combat.reactions_to_move(s, u, c)
		if not reactors.is_empty():
			# Flush the movement so far, then let overwatch fire.
			s.emit({"type": "move", "unit": u.id, "from": from, "path": segment.duplicate()})
			from = c
			segment.clear()
			Combat.resolve_reactions(s, u, reactors)
		if not u.is_alive():
			return
	if not segment.is_empty():
		s.emit({"type": "move", "unit": u.id, "from": from, "path": segment})
	Hazards.on_move(s, u, path)


## Central damage entry point: every module deals damage through here.
static func deal_damage(s: GameState, target: Unit, amount: int, source: Unit = null) -> void:
	if not target.is_alive():
		return
	amount = GearFx.damage_taken(s, target, amount, source)
	amount = Encounter.modify_damage(s, target, amount, source)
	if amount <= 0:
		return
	amount = Kit.modify_incoming(s, target, amount, source)
	target.hp = max(0, target.hp - amount)
	s.emit({"type": "damage", "unit": target.id, "amount": amount, "hp": target.hp, "source": source.id if source else -1})
	if source != null and source.is_enemy_of(target):
		Vision.expose(s, source)
	if source and EnemyRoster.infects(source):
		Infection.on_damaged(s, target, source, amount)
	Encounter.on_damaged(s, target, source, amount)
	Kit.after_damage(s, target, amount, source)
	if not target.is_alive():
		target.overwatch = false
		s.emit({"type": "died", "unit": target.id})
		Encounter.on_died(s, target)
		Kit.on_death(s, target, source)


static func check_end(s: GameState) -> void:
	if s.phase == Types.Phase.ENDED:
		return
	var r := Types.Result.NONE
	if Objectives.soldiers(s).is_empty():
		# Turned soldiers have switched teams; Lapsed ones are still ours and will recover.
		r = Types.Result.DEFEAT
	else:
		r = Objectives.check(s)   # the fight's objective, or elimination where that wins
	if r != Types.Result.NONE:
		s.result = r
		s.phase = Types.Phase.ENDED
		s.emit({"type": "mission_end", "result": r})
