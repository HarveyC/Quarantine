class_name Infection
extends RefCounted
## Infection meter (0-100), tiers, mutation powers, Lapse rolls and Turning.
## OWNER: infection workstream.
##
## Status keys owned by this module (see docs/ARCHITECTURE.md, cross-module contracts):
##   "lapsed": bool          soldier is temporarily AI-controlled and hostile to everyone
##   "lapsed_turn": int      turn the soldier lapsed on
##   "turned": bool          soldier has permanently Turned (team is ENEMY)
##   "hive_sense": int       turn number on which Hive Sense is active (ignore enemy cover)
##   "surge_turn": int       turn on which Adrenal Surge was last used
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

const MUTATIONS := {
	"surge": {
		"name": "Adrenal Surge", "cost": 15, "actions": 0, "targeting": "none", "min_tier": Tier.EXPOSED,
		"desc": "Gain +1 action this turn. Once per turn.",
	},
	"regenerate": {
		"name": "Regenerate", "cost": 10, "actions": 1, "targeting": "none", "min_tier": Tier.EXPOSED,
		"cooldown": 2, "heal": 3, "desc": "Heal 3 HP. Cooldown 2.",
	},
	"sense": {
		"name": "Hive Sense", "cost": 10, "actions": 1, "targeting": "none", "min_tier": Tier.MUTATING,
		"desc": "Ignore enemy cover for the rest of this turn. Requires Mutating.",
	},
}
## Display order for the HUD.
const MUTATION_ORDER: Array[String] = ["surge", "regenerate", "sense"]


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
	var before := tier(u.infection)
	u.infection = clampi(u.infection + amount, 0, MAX)
	var after := tier(u.infection)
	s.emit({"type": "infection", "unit": u.id, "value": u.infection, "tier": after})
	if after != before:
		_apply_passives(u, after)
	if after == Tier.TURNED:
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
			u.status.erase("lapsed")
			u.status.erase("lapsed_turn")
			u.ai_controlled = false
			s.emit({"type": "recover", "unit": u.id})
			continue
		var chance := lapse_chance(u.infection)
		if chance > 0.0 and s.rng.randf() < chance:
			u.status["lapsed"] = true
			u.status["lapsed_turn"] = s.turn
			u.ai_controlled = true
			u.overwatch = false
			s.emit({"type": "lapse", "unit": u.id})


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
##  "ready": bool, "reason": String (why not ready, "" if ready)}.
## Empty for units that are not soldiers or are below EXPOSED.
static func available_mutations(s: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if u.team != Types.Team.PLAYER or tier(u.infection) < Tier.EXPOSED:
		return out
	for id in MUTATION_ORDER:
		var m: Dictionary = MUTATIONS[id]
		var reason := _mutation_reason(s, u, id)
		out.append({
			"id": id, "name": m.name, "desc": m.desc, "cost": m.cost, "actions": m.actions,
			"targeting": m.targeting, "ready": reason == "", "reason": reason,
			"cooldown": int(u.cooldowns.get(id, 0)),
		})
	return out


static func _mutation_reason(s: GameState, u: Unit, id: String) -> String:
	if not MUTATIONS.has(id):
		return "Unknown mutation"
	var m: Dictionary = MUTATIONS[id]
	if not u.is_alive():
		return "No such unit"
	if u.team != Types.Team.PLAYER:
		return "Only soldiers can mutate"
	var min_tier: int = m.min_tier
	if tier(u.infection) < min_tier:
		return "Requires %s infection" % tier_name(min_tier)
	var actions: int = m.actions
	if u.actions_left < maxi(1, actions):
		return "No actions left"
	if int(u.cooldowns.get(id, 0)) > 0:
		return "Cooling down (%d)" % int(u.cooldowns[id])
	if id == "surge" and u.status.get("surge_turn", -1) == s.turn:
		return "Already used this turn"
	if id == "regenerate" and u.hp >= u.max_hp:
		return "Already at full health"
	if id == "sense" and has_hive_sense(s, u):
		return "Already active"
	return ""


static func validate_mutation(s: GameState, u: Unit, action: Dictionary) -> String:
	return _mutation_reason(s, u, str(action.get("mutation", "")))


## Applies a validated mutation. Effects resolve first, then the infection cost is added
## (which may Turn the unit). Emits {"type": "mutation", "unit", "mutation", ...}.
static func apply_mutation(s: GameState, u: Unit, action: Dictionary) -> void:
	var id: String = action.mutation
	var m: Dictionary = MUTATIONS[id]
	var actions: int = m.actions
	u.actions_left -= actions
	var ev := {"type": "mutation", "unit": u.id, "mutation": id}
	match id:
		"surge":
			u.actions_left += 1
			u.status["surge_turn"] = s.turn
		"regenerate":
			var heal: int = m.heal
			var healed := mini(heal, u.max_hp - u.hp)
			u.hp += healed
			u.cooldowns[id] = m.cooldown
			ev["healed"] = healed
			ev["hp"] = u.hp
		"sense":
			u.status["hive_sense"] = s.turn
	s.emit(ev)
	var cost: int = m.cost
	add(s, u, cost)
