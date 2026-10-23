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
