class_name EnemyRoster
extends RefCounted
## The enemy roster: threat costs, which act each enemy joins the pool, elites and affixes.
## Stat blocks live in UnitData.ENEMIES. OWNER: enemies workstream.
##
## An enemy "spec" is a String used in MatchConfig enemy lists:
##   "runner"                 a regular enemy
##   "brute!armoured,hasted"  an elite (double HP, larger) with affixes
##   "runner+hasted"          a regular enemy that bought an affix with spare budget
##
## Status keys owned by the enemies module (see docs/ARCHITECTURE.md, Enemies):
##   "elite": bool, "affixes": Array[String], "armour": int, "hidden": bool (Lurker),
##   "boss": String (boss id), "boss_phase": int, "spawner": Dictionary, "tether": String (kind
##   whose living units make this one immune), "pinning"/"pinned_by": int, "swelling": int (turn),
##   "charge_dir": Vector2i, "frenzy": int (turn it lasts through), "frenzy_mob"/"frenzy_aim": int.

## Threat budget each regular enemy spends when a fight is built.
const COST := {"runner": 1, "spitter": 1, "fallen": 2, "bloater": 2, "lurker": 2, "shrieker": 2, "brute": 3,
	"leaper": 2, "drifter": 1, "sharpshooter": 2, "burrower": 2,
	"hooker": 2, "sapper": 2, "carapace": 2, "stalker": 3, "weaver": 3,
	"cutter": 2, "torchman": 2, "fence": 2}
## First act an enemy appears in as a regular.
const FROM_ACT := {"runner": 1, "spitter": 1, "fallen": 1, "bloater": 1, "leaper": 1, "brute": 2, "lurker": 2,
	"drifter": 2, "sharpshooter": 2, "shrieker": 3, "burrower": 3,
	"hooker": 1, "sapper": 2, "carapace": 2, "stalker": 3, "weaver": 3,
	"cutter": 1, "torchman": 1, "fence": 2}
## Each act's signature enemies are twice as likely to be bought there, so acts feel different:
## act 1 the cordon (Fallen, Leaper), act 2 the port (Drifter, Sharpshooter, Brute), act 3 the bore.
const SIGNATURE := {1: ["fallen", "leaper", "cutter", "torchman"], 2: ["drifter", "sharpshooter", "brute", "sapper", "carapace", "fence"],
	3: ["burrower", "shrieker", "lurker", "stalker", "weaver"]}
## Ranged enemies: they shoot or spit from a distance. Fights are built mostly from melee infected
## that rush the squad; ranged kinds are supporting threats (FightBuilder caps their share).
const RANGED: Array[String] = ["spitter", "fallen", "sharpshooter", "hooker"]
## How often a kind is bought in each act relative to the others (1 when missing). The Runner is
## the staple infected, the most common enemy at any budget; later acts lean on their signatures.
const WEIGHT := {"runner": {1: 3, 2: 2, 3: 2}}
## First act an enemy can be an elite in.
const ELITE_FROM_ACT := {"brute": 1, "lurker": 1, "fallen": 1, "leaper": 1, "bloater": 2, "shrieker": 2,
	"sharpshooter": 2, "burrower": 3, "hooker": 2, "sapper": 2, "carapace": 2, "stalker": 3, "weaver": 3,
	"cutter": 2, "torchman": 2}
const AFFIXES: Array[String] = ["armoured", "regenerating", "splitting", "virulent", "hasted", "tethered", "volatile", "rallying"]
const AFFIX_INFO := {
	"armoured": {"name": "Armoured", "desc": "Takes 2 less damage per hit (min 1). Doesn't stack with natural armour.", "counter": "Needs big hits or a Mark."},
	"regenerating": {"name": "Regenerating", "desc": "Heals 3 HP each turn unless burned this turn.", "counter": "Needs Burn to stop the healing."},
	"splitting": {"name": "Splitting", "desc": "Splits into 2 Runners on death.", "counter": "Needs area damage for the Runners."},
	"virulent": {"name": "Virulent", "desc": "Its hits add +25 Infection instead of +10.", "counter": "Needs Guard or Purge for the Infection."},
	"hasted": {"name": "Hasted", "desc": "Takes 3 actions a turn.", "counter": "Needs Suppress or Overwatch to slow it."},
	"tethered": {"name": "Tethered", "desc": "Immune to damage while the Hive node lives.", "counter": "Needs Close range, or a Breach on the node."},
	"volatile": {"name": "Volatile", "desc": "Explodes on death: 2 damage in a 3x3 to everyone and it cracks cover.", "counter": "Kill it from range, or Guard the soldier beside it."},
	"rallying": {"name": "Rallying", "desc": "Infected within 3 tiles hit for +1 damage.", "counter": "Needs a Mark and focus fire, or Suppress."},
}
## Ground rules for the kinds added in the 2026-10-25 enemy sprint.
const HOOK_RANGE := 7
const HOOK_MIN := 3
const HOOK_PULL := 3
const HOOK_DAMAGE := 2
const SATCHEL_RANGE := 5
const SATCHEL_DAMAGE := 3
const PLATE_REDUCTION := 3
const STALK_BONUS_MOVE := 3
const STALK_BONUS_DAMAGE := 2
const STALK_ISOLATION := 4
const MEND_RANGE := 6
const MEND_HEAL := 3
const RALLY_RADIUS := 3
const RALLY_DAMAGE := 1
const VOLATILE_BLAST := {"radius": 1, "centre": 1, "ring": 1, "damage": 2}
## Scavengers (enemies/scavengers.gd).
const FIREBOMB_DAMAGE := 2
const FIREBOMB_FIRE_TURNS := 2
const TANK_FIRE_TURNS := 2
const FENCE_LEAVES_TURN := 6
const FENCE_SUPPLIES := 25
const BOSSES: Array[String] = ["brood_mother", "colonel_hale", "the_source"]
const BOSS_OF_ACT := {1: "brood_mother", 2: "colonel_hale", 3: "the_source"}
const ARMOURED_REDUCTION := 2
const ELITE_HP_MULT := 2


## Builds an enemy Unit from a spec string.
static func make(spec: String) -> Unit:
	var parsed := parse(spec)
	var u := UnitData.make(parsed.kind, Types.Team.ENEMY)
	var stats: Dictionary = UnitData.ENEMIES.get(parsed.kind, {})
	if stats.get("armour", 0) > 0:
		u.status["armour"] = stats.armour
	if parsed.elite:
		u.status["elite"] = true
		u.max_hp *= ELITE_HP_MULT
		u.hp = u.max_hp
		u.display_name = "Elite " + u.display_name
	if not parsed.affixes.is_empty():
		u.status["affixes"] = parsed.affixes.duplicate()
		if parsed.affixes.has("tethered"):
			u.status["tether"] = "hive_node"
	if parsed.kind == "lurker":
		u.status["hidden"] = true
	if BOSSES.has(parsed.kind):
		u.status["boss"] = parsed.kind
		u.status["boss_phase"] = 1
		u.status["alerted"] = true
	if parsed.kind == "the_source":
		u.status["tether"] = "source_root"
	if parsed.kind == "brood_mother":
		u.status["tether"] = "egg_sac"
	if stats.get("flying", false):
		u.status["flying"] = true
	if stats.get("plate", false):
		u.status["plate"] = true
		u.status["facing"] = Vector2i(0, 1)
	return u


## {"kind": String, "elite": bool, "affixes": Array[String]}
static func parse(spec: String) -> Dictionary:
	var elite := spec.contains("!")
	var parts := spec.split("!" if elite else "+", true, 1)
	var affixes: Array[String] = []
	if parts.size() > 1:
		for a in parts[1].split(",", false):
			if AFFIXES.has(a):
				affixes.append(a)
	return {"kind": parts[0], "elite": elite, "affixes": affixes}


static func spec(kind: String, elite := false, affixes: Array[String] = []) -> String:
	if affixes.is_empty():
		return kind + ("!" if elite else "")
	return kind + ("!" if elite else "+") + ",".join(affixes)


## Melee kinds count double against the ranged ones, so adding a shooter to the pool does not
## crowd out the Infected who rush the squad.
static func weight(kind: String, act: int) -> int:
	return WEIGHT.get(kind, {}).get(act, 1) * (1 if is_ranged(kind) else 2)


static func is_ranged(kind: String) -> bool:
	return RANGED.has(kind)


static func is_static(u: Unit) -> bool:
	return UnitData.ENEMIES.get(u.kind, {}).get("static", false)


static func is_flying(u: Unit) -> bool:
	return u.status.get("flying", false)


static func is_boss(u: Unit) -> bool:
	return u.status.has("boss")


static func has_affix(u: Unit, affix: String) -> bool:
	return u.status.get("affixes", []).has(affix)


## False for enemies whose hits deal damage only (the Fallen fire bullets).
static func infects(source: Unit) -> bool:
	if source.status.get("turned", false):
		return true
	return UnitData.ENEMIES.get(source.kind, {}).get("infects", true)


## Regular enemies available in `act` (1-3).
static func pool(act: int) -> Array[String]:
	var out: Array[String] = []
	for k in FROM_ACT:
		if FROM_ACT[k] <= act:
			out.append(k)
	return out


static func elite_pool(act: int) -> Array[String]:
	var out: Array[String] = []
	for k in ELITE_FROM_ACT:
		if ELITE_FROM_ACT[k] <= act:
			out.append(k)
	return out
