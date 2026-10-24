class_name Marks
extends RefCounted
## Co-op pings and map drawing: the shared vocabulary, limits and checks. View-only (nothing here
## touches GameState or RunState, so marks can never knock an online game out of sync).
##
## A mark is a Dictionary that travels through the session (LocalSession / NetSession.mark):
##   ping:   {"type": "ping", "player", "where", "kind", "cell" | "node" | "at", "unit"?}
##   stroke: {"type": "stroke", "player", "where", "id", "points", "end"?}
##   clear:  {"type": "clear", "player", "where"}
## `where` is FIGHT (cells and world points on the tactical map) or ROUTE (node ids and points on
## the route map, as fractions of the board so different window sizes agree).
## A long stroke goes out as several chunks with the same id; receivers append them.

const PING := "ping"
const STROKE := "stroke"
const CLEAR := "clear"
const FIGHT := "fight"
const ROUTE := "route"

## Every ping kind -> label, icon and sound. "look" is the plain quick ping.
const KINDS := {
	"look": {"label": "Look here", "icon": "ping", "sound": "ping"},
	"move": {"label": "Move here", "icon": "move", "sound": "ping"},
	"attack": {"label": "Attack", "icon": "attack", "sound": "ping_attack"},
	"overwatch": {"label": "Overwatch", "icon": "overwatch", "sound": "ping"},
	"danger": {"label": "Danger", "icon": "danger", "sound": "ping_danger"},
	"loot": {"label": "Loot", "icon": "supplies", "sound": "ping"},
}
## The ping wheel, clockwise from the top.
const WHEEL: Array[String] = ["move", "attack", "overwatch", "danger", "loot"]

## Seconds a ping stays up, and a stroke before it has faded out.
const PING_LIFE := 6.0
const STROKE_LIFE := 5.0
## Live pings per player: a new one replaces that player's oldest.
const MAX_PINGS := 3
## Live strokes per player, points per chunk and per stroke.
const MAX_STROKES := 12
const MAX_CHUNK := 32
const MAX_POINTS := 480
## Seconds between stroke chunks while drawing.
const CHUNK_SECONDS := 0.08

## Rate limits as token buckets: [burst, refill per second]. The sender checks them before
## sending and the host again before relaying, so one player can't flood the others.
const LIMITS := {PING: [4.0, 1.5], STROKE: [24.0, 14.0], CLEAR: [3.0, 1.0]}


static func kind_info(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS.look)


static func color(player: int) -> Color:
	return preload("res://ui/styles.gd").player_color(player)


## The quick ping's kind from what is under it (Marks.context): an enemy says attack, something
## that blows up or burns says danger, an objective says loot, a route node says go there,
## anything else says look.
static func quick_kind(context: String) -> String:
	match context:
		"enemy": return "attack"
		"hazard": return "danger"
		"loot": return "loot"
		"node": return "move"
	return "look"


## What a fight cell holds, for the quick ping and its label: enemy, ally, hazard, loot or "".
## An enemy only counts if `team` can see it, so a ping never gives away a hidden one.
static func fight_context(state: GameState, cell: Vector2i, team: int = Types.Team.PLAYER) -> String:
	if state == null or not state.grid.in_bounds(cell):
		return ""
	var u := state.unit_at(cell)
	if u != null and u.is_alive() and Vision.sees_unit(state, team, u):
		return "enemy" if u.team != team else "ally"
	if state.grid.is_volatile(cell) or state.hazards.has(cell):
		return "hazard"
	for key in ["beacon", "evac", "exit", "civilian"]:
		if state.grid.marker(key).has(cell):
			return "loot"
	return ""


# --- checking ---------------------------------------------------------------------------------

## A clean copy of `m` with only the fields its type uses and every value checked, or {} if it
## is malformed. Everything that arrives over the network goes through this.
static func sanitize(m: Variant) -> Dictionary:
	if not (m is Dictionary):
		return {}
	var d: Dictionary = m
	var where := str(d.get("where", ""))
	if where != FIGHT and where != ROUTE:
		return {}
	var out := {"type": str(d.get("type", "")), "player": int(d.get("player", -1)), "where": where}
	if out.player < 0 or out.player > 7:
		return {}
	match out.type:
		PING:
			out.kind = str(d.get("kind", "look"))
			if not KINDS.has(out.kind):
				return {}
			if d.get("cell") is Vector2i:
				out.cell = d.cell
				if d.get("unit") is int:
					out.unit = d.unit
			elif d.get("node") is int:
				out.node = d.node
			elif d.get("at") is Vector2:
				out.at = _clamp01(d.at)
			else:
				return {}
		STROKE:
			out.id = int(d.get("id", 0))
			var pts: Variant = d.get("points")
			if where == FIGHT and pts is PackedVector3Array:
				out.points = (pts as PackedVector3Array).slice(0, MAX_CHUNK)
			elif where == ROUTE and pts is PackedVector2Array:
				var clean := PackedVector2Array()
				for p in (pts as PackedVector2Array).slice(0, MAX_CHUNK):
					clean.append(_clamp01(p))
				out.points = clean
			else:
				return {}
			if d.get("end", false):
				out.end = true
		CLEAR:
			pass
		_:
			return {}
	return out


static func _clamp01(v: Vector2) -> Vector2:
	if not v.is_finite():
		return Vector2(0.5, 0.5)
	return v.clamp(Vector2.ZERO, Vector2.ONE)


## Token-bucket rate limit per player and mark type.
class Limiter extends RefCounted:
	## [player, type] key -> [tokens, last time]
	var _buckets := {}

	## Spends one token for `player` sending a `type` mark at time `now` (seconds). False if
	## they're out of tokens, in which case the mark should be dropped.
	func allow(player: int, type: String, now: float) -> bool:
		var lim: Array = LIMITS.get(type, LIMITS[PING])
		var key := "%d:%s" % [player, type]
		var b: Array = _buckets.get(key, [float(lim[0]), now])
		var tokens := minf(float(lim[0]), float(b[0]) + (now - float(b[1])) * float(lim[1]))
		if tokens < 1.0:
			_buckets[key] = [tokens, now]
			return false
		_buckets[key] = [tokens - 1.0, now]
		return true


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0
