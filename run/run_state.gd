class_name RunState
extends RefCounted
## One roguelike run: squad, currencies, Outbreak and the node map. Mutated only through RunRules
## (and the modules it routes actions to), so online co-op replicates it by sending run actions,
## exactly like GameState and Rules. Plain data, fully serializable for save/resume and resync.

## Every run-level change is announced as an event Dictionary (see docs/ARCHITECTURE.md).
signal event(ev: Dictionary)

enum Phase { MAP, NODE, FIGHT, REWARD, ENDED }

const ACTS := 3
const ROWS := 5

var seed := 0
var rng := RandomNumberGenerator.new()
var phase: int = Phase.MAP
var result: int = Types.Result.NONE

## Players in the run, 0..n-1 (1 = solo). Player 0 is the host and breaks split votes.
var players: Array[int] = [0]
var host_player := 0
## player -> true while that player is absent; their soldiers are played by the host and they don't vote.
var benched := {}

var act := 1
var row := 0                 # row of the current node, 0 before the first node of an act
var node := -1               # id of the current node, -1 at the start of an act
## Node map of the current act: see RunMap.generate for the node fields.
var map: Array = []

var supplies := 60
var intel := 1
var outbreak := 0
var serum := {}              # player -> samples (2 samples = 1 dose)
var fights_won := 0          # fights survived this run (XP / rank-ups are per soldier, see soldiers)

## Every soldier of the run: active squad, reserve, dead and turned. Dictionaries, see RunSoldier.
var soldiers: Array = []
var _next_sid := 1

## player -> node id for the open route vote.
var votes := {}
## Steps still to run for the current node, e.g. ["fight", "reward"], see RunRules.
var steps: Array = []
## The current fight's MatchConfig while phase == FIGHT (every peer builds the same GameState from it).
var fight_config := {}
## Snapshot of the running fight for save/resume (GameState.to_dict), written by the session.
var fight_snapshot := {}

## Owned by the events/depot/hospital module (NodeRules): the open non-fight node's screen state.
var node_state := {}
## Owned by GearRun: stash, reward offers, pity. Opaque to the framework.
var gear := {}
## Next-fight / map effects set by events, consumed by RunRules and FightBuilder.
## Keys: extra_enemies, enemies_dead_at_start, first_turn_action_loss, ambush, boss_health_mult,
## force_nest_next, remove_column, pending_fight ({"kind", "objective"}). Squad-wide doctrine
## passives live under "doctrines" (Array of ids).
var modifiers := {}
## Event ids already used this run (events never repeat).
var seen_events: Array = []
## Hidden "?" nodes that resolved to a non-fight in a row: each adds +10% fight chance.
var unknown_streak := 0
## Soldiers who Turned this run, kept for Echoes later: [{"sid", "kind", "name", "act"}].
var echoes: Array = []
## Owned by Story: wave, Echoes met, intel recovered, the ending vote. Opaque to the framework.
var story := {}
## Read-only copy of the player profile's meta flags (unlocks, Outbreak level) for this run.
var meta := {}
var log: Array[Dictionary] = []


func emit(ev: Dictionary) -> void:
	log.append(ev)
	event.emit(ev)


# --- queries ------------------------------------------------------------------

func present_players() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if not benched.get(p, false):
			out.append(p)
	return out


func is_solo() -> bool:
	return players.size() == 1


func get_node(id: int) -> Dictionary:
	for n in map:
		if n.id == id:
			return n
	return {}


func current_node() -> Dictionary:
	return get_node(node)


## Node ids the squad can move to next.
func reachable_nodes() -> Array[int]:
	var out: Array[int] = []
	if node < 0:
		for n in map:
			if n.row == 1:
				out.append(n.id)
	else:
		out.assign(current_node().get("links", []))
	return out


func get_soldier(sid: int) -> Dictionary:
	for r in soldiers:
		if r.id == sid:
			return r
	return {}


## The squad that deploys: active soldiers, at most 4.
func squad() -> Array:
	return soldiers.filter(func(r: Dictionary) -> bool: return r.status == RunSoldier.ACTIVE)


func soldiers_of(player: int) -> Array:
	return squad().filter(func(r: Dictionary) -> bool: return r.owner == player)


func reserve_of(player: int) -> Array:
	return soldiers.filter(func(r: Dictionary) -> bool: return r.status == RunSoldier.RESERVE and r.owner == player)


## Who gives orders to a soldier in a fight: its owner, or the host while the owner is benched.
func controller_of(record: Dictionary) -> int:
	if benched.get(record.owner, false):
		var present := present_players()
		return present[0] if not present.is_empty() else host_player
	return record.owner


func new_sid() -> int:
	_next_sid += 1
	return _next_sid - 1


# --- save / sync ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"seed": seed, "rng_seed": rng.seed, "rng_state": rng.state, "phase": phase, "result": result,
		"players": players.duplicate(), "host_player": host_player, "benched": benched.duplicate(),
		"act": act, "row": row, "node": node, "map": map.duplicate(true),
		"supplies": supplies, "intel": intel, "outbreak": outbreak, "serum": serum.duplicate(),
		"fights_won": fights_won, "soldiers": soldiers.duplicate(true), "next_sid": _next_sid,
		"votes": votes.duplicate(), "steps": steps.duplicate(), "fight_config": fight_config.duplicate(true),
		"fight_snapshot": fight_snapshot.duplicate(true), "node_state": node_state.duplicate(true),
		"gear": gear.duplicate(true), "modifiers": modifiers.duplicate(true), "seen_events": seen_events.duplicate(),
		"unknown_streak": unknown_streak, "echoes": echoes.duplicate(true), "meta": meta.duplicate(true),
		"story": story.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RunState:
	var r := RunState.new()
	r.seed = d.seed
	r.rng.seed = d.rng_seed
	r.rng.state = d.rng_state
	r.players.assign(d.players)
	r._next_sid = d.next_sid
	for key in ["phase", "result", "host_player", "act", "row", "node", "supplies", "intel", "outbreak",
			"fights_won", "unknown_streak", "benched", "map", "serum", "soldiers", "votes", "steps",
			"fight_config", "fight_snapshot", "node_state", "gear", "modifiers", "seen_events", "echoes", "meta", "story"]:
		if d.has(key):
			var v: Variant = d[key]
			r.set(key, v.duplicate(true) if v is Dictionary or v is Array else v)
	return r


## Save games use Godot's own text format (var_to_str), not JSON, so ints, int keys and
## Vector2i survive the round trip.
func save_string() -> String:
	return var_to_str(to_dict())


static func from_save_string(text: String) -> RunState:
	var d: Variant = str_to_var(text)
	return from_dict(d) if d is Dictionary else null


## Order-independent fingerprint, used to detect peers drifting apart.
func checksum() -> int:
	var d := to_dict()
	d.erase("fight_snapshot")
	return JSON.stringify(d, "", true).hash()
