class_name Infection
extends RefCounted
## Infection meter (0-100), tiers, Lapse rolls and Turning. Mutation powers are grafted per soldier
## and live in progression/ (MutationData, Mutations, Kit); this file delegates to them.
## OWNER: infection workstream (mutations: progression workstream).
##
## Status keys owned by this module (see docs/ARCHITECTURE.md, cross-module contracts):
##   "lapsed": bool          soldier is temporarily AI-controlled and hostile to everyone
##   "lapsed_turn": int      turn the soldier lapsed on
##   "turned": bool          soldier has permanently Turned (team is ENEMY)
##   "hive_sense": int       turn number on which Hive Sense is active (ignore enemy cover; legacy, unused)
##   "tier_mobility": int    mobility bonus currently applied by tier passives
##   "tier_aim": int         aim bonus currently applied by tier passives

enum Tier { CLEAN, EXPOSED, MUTATING, CRITICAL, TURNED }

const MAX := 100
## Lowest infection value of each tier, indexed by Tier.
const THRESHOLDS: Array[int] = [0, 25, 50, 75, 100]
const EXPOSED_AT := 25
const MUTATING_AT := 50
const CRITICAL_AT := 75
const TURNED_AT := 100

## Gain from being damaged by an Infected: BASE + PER_DAMAGE * amount, capped at MAX_GAIN.
const DAMAGE_GAIN_BASE := 6
const DAMAGE_GAIN_PER_DAMAGE := 2
const DAMAGE_GAIN_MAX := 15

## Chance (0-1) to Lapse at the start of a team phase, per tier.
const LAPSE_CHANCE := {Tier.MUTATING: 0.10, Tier.CRITICAL: 0.30}

## Passive bonuses per tier: {mobility, aim}. TURNED keeps the CRITICAL bonuses.
const PASSIVES := {
	Tier.MUTATING: {"mobility": 1, "aim": 0},
	Tier.CRITICAL: {"mobility": 1, "aim": 10},
	Tier.TURNED: {"mobility": 1, "aim": 10},
}

static func tier(value: int) -> int:
	if value >= TURNED_AT:
		return Tier.TURNED
	if value >= CRITICAL_AT:
		return Tier.CRITICAL
	if value >= MUTATING_AT:
		return Tier.MUTATING
	if value >= EXPOSED_AT:
		return Tier.EXPOSED
	return Tier.CLEAN


static func tier_name(t: int) -> String:
	return Tier.keys()[t].capitalize()


## HUD color for a tier: grey-green when clean, through to bioluminescent teal, sickly bright when Turned.
static func tier_color(t: int) -> Color:
	match t:
		Tier.EXPOSED: return Color("#9fbf6a")
		Tier.MUTATING: return Color("#4fd89a")
		Tier.CRITICAL: return Color("#2ef2c8")
		Tier.TURNED: return Color("#d4ff3a")
	return Color("#7f9483")


## Change a unit's infection and emit {"type": "infection", "unit", "value", "tier"}.
## Negative amounts cure (e.g. Medic stim calls add(s, u, -15)). Tier passives are
## re-applied on every change, and reaching 100 Turns the soldier. Turning is permanent:
## a Turned unit's infection no longer changes.
static func add(s: GameState, u: Unit, amount: int) -> void:
	if u.status.get("turned", false) or u.status.has("deployable"):
		return
	if amount != 0:
		amount = Kit.infection_change(s, u, amount)
		if amount == 0:
			return
	var before := tier(u.infection)
	u.infection = clampi(u.infection + amount, 0, MAX)
	var after := tier(u.infection)
	s.emit({"type": "infection", "unit": u.id, "value": u.infection, "tier": after})
	if after != before:
		_apply_passives(u, after)
		Kit.refresh_stats(s, u)
	if after == Tier.TURNED and not Kit.prevent_turn(s, u):
		_turn(s, u)


## Re-applies the tier passives for the current value (after setting `infection` directly at spawn).
static func sync_passives(u: Unit) -> void:
	_apply_passives(u, tier(u.infection))


## Turns a soldier now (Ride the Wave running out).
static func force_turn(s: GameState, u: Unit) -> void:
	if not u.status.get("turned", false):
		_turn(s, u)


## Mobility/aim bonuses of the unit's current tier. Removes the previously applied bonus first.
static func _apply_passives(u: Unit, t: int) -> void:
	var old_mob: int = u.status.get("tier_mobility", 0)
	var old_aim: int = u.status.get("tier_aim", 0)
	u.mobility -= old_mob
	u.aim -= old_aim
	var p: Dictionary = PASSIVES.get(t, {})
	var mob: int = p.get("mobility", 0)
	var aim: int = p.get("aim", 0)
	u.mobility += mob
	u.aim += aim
	if mob != 0:
		u.status["tier_mobility"] = mob
	else:
		u.status.erase("tier_mobility")
	if aim != 0:
		u.status["tier_aim"] = aim
	else:
		u.status.erase("tier_aim")


static func _turn(s: GameState, u: Unit) -> void:
	u.team = Types.Team.ENEMY
	u.ai_controlled = true
	u.owner_player = -1
	u.overwatch = false
	u.hunkered = false
	u.status.erase("lapsed")
	u.status.erase("lapsed_turn")
	u.status["turned"] = true
	u.actions_left = 0
	s.emit({"type": "turned", "unit": u.id})
	Kit.on_turned(s, u)


## Chance (0-1) that a soldier at `value` infection Lapses at the start of a team phase.
static func lapse_chance(value: int) -> float:
	return LAPSE_CHANCE.get(tier(value), 0.0)


static func is_lapsed(u: Unit) -> bool:
	return u.status.get("lapsed", false)


## Called by Rules at the start of every team phase (Lapse rolls, recovery).
## A soldier lapsed at the previous phase start recovers now and cannot lapse again this phase.
static func on_team_phase_start(s: GameState) -> void:
	for u in s.living(Types.Team.PLAYER):
		if is_lapsed(u):
			end_lapse(s, u)
			continue
		roll_lapse(s, u)


## Rolls for a Lapse now (phase start, Rampage, Patient Zero). Returns true if the soldier lapsed.
static func roll_lapse(s: GameState, u: Unit) -> bool:
	if is_lapsed(u) or u.team != Types.Team.PLAYER or not u.is_alive():
		return false
	var chance := Kit.lapse_chance(u, lapse_chance(u.infection))
	if chance <= 0.0 or s.rng.randf() >= chance:
		return false
	u.status["lapsed"] = true
	u.status["lapsed_turn"] = s.turn
	u.ai_controlled = true
	u.overwatch = false
	s.emit({"type": "lapse", "unit": u.id})
	Kit.on_lapse(s, u)
	return true


## Ends a Lapse (recovery at the next team phase, or an ally talked them down / cured them).
static func end_lapse(s: GameState, u: Unit) -> void:
	u.status.erase("lapsed")
	u.status.erase("lapsed_turn")
	u.ai_controlled = false
	s.emit({"type": "recover", "unit": u.id})


## Called by Rules.deal_damage whenever `source` damages `target`.
## Only the Infected (enemy-team units, including Turned soldiers) infect soldiers.
## Lapsed soldiers hurting allies do not infect.
static func on_damaged(s: GameState, target: Unit, source: Unit, amount: int) -> void:
	if source == null or target == null or amount <= 0:
		return
	if source.team != Types.Team.ENEMY or target.team != Types.Team.PLAYER or not target.is_alive():
		return
	add(s, target, GearFx.bite_infection(s, target, damage_gain(amount)))


## Infection gained from taking `amount` damage from an Infected.
static func damage_gain(amount: int) -> int:
	return mini(DAMAGE_GAIN_MAX, DAMAGE_GAIN_BASE + DAMAGE_GAIN_PER_DAMAGE * amount)


## True while `u` ignores enemy cover (Hive Sense). Combat should check this in hit_chance.
static func has_hive_sense(s: GameState, u: Unit) -> bool:
	return u.status.get("hive_sense", -1) == s.turn


## Mutation powers `u` could use: Array of
## {"id", "name", "desc", "cost" (infection added), "actions", "targeting": "none"|"unit"|"cell",
##  "ready": bool, "reason": String (why not ready, "" if ready), "cooldown", "source", "tier"}.
## Lists the soldier's grafted active mutations (dormant ones with ready = false), plus any lent
## by Hive Link or mirrored by Mirror Graft. See Mutations.available.
static func available_mutations(s: GameState, u: Unit) -> Array[Dictionary]:
	return Mutations.available(s, u)


static func validate_mutation(s: GameState, u: Unit, action: Dictionary) -> String:
	return Mutations.validate(s, u, action)


## Applies a validated mutation. Effects resolve first, then the infection cost is added
## (which may Turn the unit). Emits {"type": "mutation", "unit", "mutation", ...}.
static func apply_mutation(s: GameState, u: Unit, action: Dictionary) -> void:
	Mutations.apply(s, u, action)
