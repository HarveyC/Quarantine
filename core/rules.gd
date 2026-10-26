class_name Rules
extends RefCounted
## Turn flow and action dispatch. The single entry point for changing GameState.
## Module-specific behaviour is delegated to Combat, Infection and EnemyAI (Concealment hooks
## into moves, attacks and damage).


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
		s.ready[p] = false
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
	_auto_ready(s)


## Returns "" if the action is legal, otherwise a human-readable reason.
static func validate(s: GameState, action: Dictionary) -> String:
	if s.phase == Types.Phase.ENDED:
		return "Mission is over"
	var u := s.get_unit(action.get("unit", -1))
	if u == null or not u.is_alive():
		return "No such unit"
	if action.get("type") == Types.STRUGGLE:
		return Encounter.validate_struggle(s, u)
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
	if action.type == Types.STRUGGLE:
		Encounter.struggle(s, u)
		Vision.refresh(s)
		return true
	_expose_attacker(s, u, action)
	if action.type == Types.ABILITY and EnemyAbilities.handles(str(action.ability)):
		EnemyAbilities.apply(s, u, action)
		Encounter.after_action(s, u, action)
		Vision.refresh(s)
		check_end(s)
		_auto_ready(s)
		return true
	Kit.before_action(s, u, action)
	match action.type:
		Types.MOVE: _do_move(s, u, action.to)
		Types.SHOOT, Types.OVERWATCH, Types.HUNKER, Types.ABILITY: Combat.apply(s, u, action)
		Types.MUTATION: Infection.apply_mutation(s, u, action)
	Concealment.after_action(s, u, action)
	Encounter.after_action(s, u, action)
	Kit.after_action(s, u, action)
	Vision.refresh(s)
	check_end(s)
	_auto_ready(s)   # this action may have cost a player their last soldier
	return true


## How many action pips the HUD draws for `u`: the usual two, more while a bonus action
## (Adrenal Surge, a stim, a kill refund) has them above that, so the extra one shows.
static func action_slots(u: Unit) -> int:
	return maxi(Types.ACTIONS_PER_TURN, u.actions_left) if u != null else Types.ACTIONS_PER_TURN


## Why `u` started this team phase short of actions, for the HUD: one entry per cause, each
## {"key": glossary term, "icon": Icons id, "title": short caps word, "text": one plain line,
## "lost": actions taken (Types.ACTIONS_PER_TURN = the whole turn)}. Pure; [] when nothing.
static func action_losses(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if u == null or not u.is_alive() or u.team != Types.Team.PLAYER or u.ai_controlled:
		return out
	if u.status.has("pinned_by"):
		var l := s.get_unit(int(u.status.pinned_by))
		var who := l.display_name if l != null and l.display_name != "" else "a Lurker"
		var tried: bool = u.status.get("struggled", -1) == s.turn
		out.append({"key": "pinned", "icon": "pinned", "title": "Pinned", "lost": Types.ACTIONS_PER_TURN,
			"text": "Pinned by %s: can't act. %s, or a teammate hitting it frees them." % [who,
				"Struggled this turn and failed, try again next turn" if tried
				else "Struggle for a %d%% chance to break free" % Encounter.STRUGGLE_CHANCE]})
	if s.phase != Types.Phase.TEAM:
		return out
	if s.turn == 1 and u.status.get("first_turn_action_loss", false):
		out.append({"key": "", "icon": "event", "title": "Shaken", "lost": 1,
			"text": "Whispers: fighting the voices costs 1 action this first turn."})
	if u.status.get("k_lose_action") == s.turn:
		out.append({"key": "", "icon": "mutation", "title": "Twin Sight", "lost": 1,
			"text": "Twin Sight: strayed too far from the bonded soldier, 1 action lost this turn."})
	if u.status.get("k_surge_penalty") == s.turn:
		out.append({"key": "", "icon": "mutation", "title": "Crash", "lost": 1,
			"text": "Adrenal Surge crash: only 1 action this turn."})
	return out


## Fog of war: shooting at or attacking a hostile gives the attacker's position away, and so
## do the area attacks below (lobbed spit, airstrike calls). Anything that deals damage also
## exposes its source (deal_damage).
const EXPOSING_CELL_ABILITIES := ["spit", "acid_rain", "airstrike", "item:flashbang", "gear:concussion_launcher", "gear:flare_launcher", "core_slam", "lash", "hurl", "smoke_screen"]


static func _expose_attacker(s: GameState, u: Unit, action: Dictionary) -> void:
	if action.type != Types.SHOOT and action.type != Types.ABILITY:
		return
	var t := s.get_unit(action.get("target", -1))
	if (t != null and u.is_enemy_of(t)) or EXPOSING_CELL_ABILITIES.has(str(action.get("ability", ""))):
		Vision.expose(s, u)


## Player readiness for the simultaneous team phase. When everyone is ready the enemy phase runs.
## A player with no soldier left to control (all dead, Turned or Lapsed) is ready automatically.
static func set_ready(s: GameState, player: int, is_ready: bool) -> void:
	if s.phase != Types.Phase.TEAM:
		return
	if not is_ready and s.controllable_units(player).is_empty():
		return
	s.ready[player] = is_ready
	s.emit({"type": "ready", "player": player, "ready": is_ready})
	_auto_ready(s)


## Readies every player who has nobody left to act with, then ends the team phase if
## everyone is ready. Runs whenever a soldier might have dropped out of the team phase.
static func _auto_ready(s: GameState) -> void:
	if s.phase != Types.Phase.TEAM:
		return
	for p in s.players:
		if not s.ready.get(p, false) and s.controllable_units(p).is_empty():
			s.ready[p] = true
			s.emit({"type": "ready", "player": p, "ready": true, "auto": true})
	if s.players.all(func(p): return s.ready.get(p, false)):
		# Objectives move their civilians through Rules.apply, which calls _auto_ready again: without
		# this guard that re-ran the whole end of turn (and the enemy phase) once per move.
		if s.settling:
			return
		s.settling = true
		Hazards.on_team_phase_end(s)
		Objectives.on_team_phase_end(s)
		check_end(s)
		s.settling = false
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
		GearFx.on_enemy_phase_end(s)
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
	return s.grid.reachable(u.pos, u.mobility, s.occupied(u.id), false, Grafts.climbs(u))


static func _validate_move(s: GameState, u: Unit, to: Vector2i) -> String:
	if to == u.pos:
		return "Already there"
	if not move_range(s, u).has(to):
		return "Out of range"
	return ""


static func _do_move(s: GameState, u: Unit, to: Vector2i) -> void:
	u.actions_left -= 1
	move_along(s, u, to)


## Moves step by step so overwatch can interrupt. Emits one "move" event per uninterrupted segment.
## Spends no actions (a MOVE action costs one; Lunge and Shield Charge move as part of a strike).
## A Warden's Guard bash can stop the move short (ClassAbilities.resolve_guards).
static func move_along(s: GameState, u: Unit, to: Vector2i) -> void:
	var path := s.grid.find_path(u.pos, to, s.occupied(u.id), false, Grafts.climbs(u))
	u.hunkered = false
	GearFx.on_move(s, u)
	var segment: Array[Vector2i] = []
	var walked: Array[Vector2i] = []
	var from := u.pos
	for c in path:
		u.pos = c
		segment.append(c)
		walked.append(c)
		Vision.on_step(s, u)
		var spot := Concealment.spotter(s, u)
		if not spot.is_empty():
			# Show the walk up to here before the squad is spotted, so the alarm lands on time.
			s.emit({"type": "move", "unit": u.id, "from": from, "path": segment.duplicate()})
			from = c
			segment.clear()
			Concealment.lose(s, "spotted", spot[0], spot[1])
		Kit.on_step(s, u, c)
		var reactors := Combat.reactions_to_move(s, u, c)
		var guards := ClassAbilities.guards_against(s, u, c)
		if not reactors.is_empty() or not guards.is_empty():
			# Flush the movement so far, then let overwatch fire.
			s.emit({"type": "move", "unit": u.id, "from": from, "path": segment.duplicate()})
			from = c
			segment.clear()
			Combat.resolve_reactions(s, u, reactors)
			if u.is_alive() and not guards.is_empty() and ClassAbilities.resolve_guards(s, u, guards):
				if u.is_alive():
					Hazards.on_move(s, u, walked)
				return
		if not u.is_alive():
			return
	if not segment.is_empty():
		s.emit({"type": "move", "unit": u.id, "from": from, "path": segment})
	Hazards.on_move(s, u, path)


## Central damage entry point: every module deals damage through here.
static func deal_damage(s: GameState, target: Unit, amount: int, source: Unit = null) -> void:
	if not target.is_alive():
		return
	var struck := target
	target = GearFx.guard_redirect(s, target, source)
	var intercepted := target != struck
	amount = GearFx.damage_taken(s, target, amount, source)
	amount = Encounter.modify_damage(s, target, amount, source)
	if amount <= 0:
		return
	amount = Kit.modify_incoming(s, target, amount, source)
	amount = GearFx.aegis_hold(s, target, amount)
	target.hp = max(0, target.hp - amount)
	s.emit({"type": "damage", "unit": target.id, "amount": amount, "hp": target.hp, "source": source.id if source else -1})
	if intercepted:
		GearFx.aegis_return(s, target, source, amount)
	if source != null and source.is_enemy_of(target):
		Vision.expose(s, source)
	Concealment.on_damage(s, target, source)
	if source and EnemyRoster.infects(source):
		Infection.on_damaged(s, target, source, amount)
	Encounter.on_damaged(s, target, source, amount)
	Kit.after_damage(s, target, amount, source)
	if not target.is_alive():
		target.overwatch = false
		if source != null and source.is_enemy_of(target):
			source.status["kills"] = int(source.status.get("kills", 0)) + 1
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
		s.emit({"type": "mission_end", "result": r, "cause": Objectives.loss_cause(s)})
