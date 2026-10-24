class_name GameState
extends RefCounted
## The whole mission state. Mutated only through Rules so it can later be
## replicated over the network by sending actions instead of state.

## Every state change is announced as an event Dictionary (see docs/ARCHITECTURE.md).
signal event(ev: Dictionary)

var grid: Grid
var units: Array[Unit] = []
var phase: int = Types.Phase.TEAM
var turn := 0
var result: int = Types.Result.NONE
var rng := RandomNumberGenerator.new()
var players: Array[int] = [0, 1]   # participating player ids
var ready := {}                     # player id -> bool, for the current team phase
var log: Array[Dictionary] = []
var objective := {}                 # fight objective progress, owned by Objectives
## Fight-level state owned by Encounter (enemies/): waves, spawners, spore zones, telegraphs, boss.
var encounter := {}
var hazards := {}                   # cell -> {"kind", "turns", "source", "spare"}, owned by Hazards
var zones: Array = []               # Spore Burst clouds and Overgrowth walls, see progression/zones.gd
var _next_id := 1


func add_unit(u: Unit, at: Vector2i) -> Unit:
	u.id = _next_id
	_next_id += 1
	u.pos = at
	units.append(u)
	return u


func get_unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func unit_at(c: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and u.pos == c:
			return u
	return null


func living(team: int = -1) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and (team == -1 or u.team == team):
			out.append(u)
	return out


## Set of cells occupied by living units, optionally ignoring one unit.
func occupied(except_id: int = -1) -> Dictionary:
	var out := {}
	for u in units:
		if u.is_alive() and u.id != except_id:
			out[u.pos] = true
	return out


## Soldiers a given player may command right now.
func controllable_units(player: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in living(Types.Team.PLAYER):
		if u.owner_player == player and not u.ai_controlled:
			out.append(u)
	return out


func emit(ev: Dictionary) -> void:
	log.append(ev)
	event.emit(ev)


## Full snapshot for network resync and save games. The event log is not included.
func to_dict() -> Dictionary:
	return {
		"grid": grid.to_dict(), "units": units.map(func(u: Unit) -> Dictionary: return u.to_dict()),
		"phase": phase, "turn": turn, "result": result, "rng_seed": rng.seed, "rng_state": rng.state,
		"players": players.duplicate(), "ready": ready.duplicate(), "next_id": _next_id,
		"encounter": encounter.duplicate(true),
		"hazards": hazards.duplicate(true), "objective": objective.duplicate(true),
		"zones": zones.duplicate(true),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.grid = Grid.from_dict(d.grid)
	for ud in d.units:
		s.units.append(Unit.from_dict(ud))
	s.phase = d.phase
	s.turn = d.turn
	s.result = d.result
	s.rng.seed = d.rng_seed
	s.rng.state = d.rng_state
	s.players.assign(d.players)
	s.ready = d.ready.duplicate()
	s._next_id = d.next_id
	s.encounter = d.get("encounter", {}).duplicate(true)
	s.hazards = d.get("hazards", {}).duplicate(true)
	s.objective = d.get("objective", {}).duplicate(true)
	s.zones = d.get("zones", []).duplicate(true)
	return s


## Order-independent fingerprint of the game state, used to detect peers drifting apart.
func checksum() -> int:
	var d := to_dict()
	d.erase("grid")
	return JSON.stringify(d, "", true).hash()
