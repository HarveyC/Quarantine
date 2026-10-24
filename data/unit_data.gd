class_name UnitData
extends RefCounted
## Stat blocks for soldier classes and enemy types. Tuning lives here.

const SOLDIERS := {
	"trooper": {"name": "Trooper", "max_hp": 7, "aim": 65, "mobility": 5, "damage": [3, 5], "abilities": ["suppress"]},
	"marksman": {"name": "Marksman", "max_hp": 5, "aim": 75, "mobility": 4, "damage": [4, 6], "abilities": ["tag"]},
	"medic": {"name": "Medic", "max_hp": 7, "aim": 60, "mobility": 5, "damage": [2, 4], "abilities": ["stim"]},
	"breacher": {"name": "Breacher", "max_hp": 8, "aim": 60, "mobility": 6, "damage": [4, 7], "abilities": ["breach"]},
	"hazmat": {"name": "Hazmat", "max_hp": 8, "aim": 60, "mobility": 4, "damage": [2, 4], "abilities": ["incinerate"]},
	"vector": {"name": "Vector", "max_hp": 7, "aim": 65, "mobility": 6, "damage": [3, 5], "abilities": ["siphon"]},
}

const ENEMIES := {
	"runner": {"name": "Runner", "max_hp": 5, "aim": 70, "mobility": 7, "damage": [3, 4], "abilities": ["claw"], "melee_only": true},
	"spitter": {"name": "Spitter", "max_hp": 4, "aim": 55, "mobility": 4, "damage": [2, 3], "abilities": ["spit"]},
	# Enemy roster (enemies/ module). Extra keys: "infects" (false = hits deal damage only),
	# "armour" (damage taken per hit is reduced by this), "static" (never moves or acts on its own).
	"fallen": {"name": "Fallen", "max_hp": 6, "aim": 60, "mobility": 5, "damage": [3, 5], "abilities": [], "infects": false},
	"bloater": {"name": "Bloater", "max_hp": 6, "aim": 0, "mobility": 3, "damage": [0, 0], "abilities": ["burst"], "melee_only": true},
	"brute": {"name": "Brute", "max_hp": 10, "aim": 70, "mobility": 5, "damage": [4, 6], "abilities": ["slam", "charge"], "melee_only": true, "armour": 1},
	"lurker": {"name": "Lurker", "max_hp": 5, "aim": 75, "mobility": 6, "damage": [2, 2], "abilities": ["pounce", "maul", "claw"], "melee_only": true},
	"shrieker": {"name": "Shrieker", "max_hp": 4, "aim": 0, "mobility": 4, "damage": [0, 0], "abilities": ["scream"], "melee_only": true},
	"leaper": {"name": "Leaper", "max_hp": 6, "aim": 70, "mobility": 4, "damage": [2, 3], "abilities": ["leap", "claw"], "melee_only": true},
	"drifter": {"name": "Drifter", "max_hp": 5, "aim": 0, "mobility": 5, "damage": [2, 3], "abilities": ["drift", "spore_drop"], "melee_only": true, "flying": true},
	"sharpshooter": {"name": "Sharpshooter", "max_hp": 6, "aim": 80, "mobility": 4, "damage": [5, 7], "abilities": ["sight", "snipe"], "infects": false},
	"burrower": {"name": "Burrower", "max_hp": 6, "aim": 70, "mobility": 5, "damage": [3, 4], "abilities": ["burrow", "erupt", "claw"], "melee_only": true},
	"broodling": {"name": "Broodling", "max_hp": 3, "aim": 0, "mobility": 3, "damage": [0, 0], "abilities": ["burst"], "melee_only": true},
	"hive_node": {"name": "Hive node", "max_hp": 12, "aim": 0, "mobility": 0, "damage": [0, 0], "abilities": [], "melee_only": true, "static": true},
	"egg_sac": {"name": "Egg sac", "max_hp": 4, "aim": 0, "mobility": 0, "damage": [0, 0], "abilities": [], "melee_only": true, "static": true},
	"spore_nest": {"name": "Spore nest", "max_hp": 6, "aim": 0, "mobility": 0, "damage": [0, 0], "abilities": [], "melee_only": true, "static": true},
	"source_root": {"name": "Root", "max_hp": 12, "aim": 0, "mobility": 0, "damage": [0, 0], "abilities": [], "melee_only": true, "static": true},
	# Bosses
	"brood_mother": {"name": "The Brood Mother", "max_hp": 40, "aim": 65, "mobility": 0, "damage": [3, 5], "abilities": ["claw", "spit", "brood_spit"], "melee_only": true},
	"colonel_hale": {"name": "Colonel Hale", "max_hp": 24, "aim": 70, "mobility": 5, "damage": [3, 5], "abilities": ["airstrike", "flashbang", "slam", "charge"]},
	"the_source": {"name": "The Source", "max_hp": 30, "aim": 0, "mobility": 0, "damage": [0, 0], "abilities": ["pull", "core_slam"], "melee_only": true},
}


static func is_melee_only(kind: String) -> bool:
	return ENEMIES.get(kind, {}).get("melee_only", false)


static func make(kind: String, team: int) -> Unit:
	var stats: Dictionary = SOLDIERS.get(kind, ENEMIES.get(kind, {}))
	assert(not stats.is_empty(), "unknown unit kind %s" % kind)
	var u := Unit.new()
	u.kind = kind
	u.team = team
	u.display_name = stats.name
	u.max_hp = stats.max_hp
	u.hp = stats.max_hp
	u.aim = stats.aim
	u.mobility = stats.mobility
	u.damage = Vector2i(stats.damage[0], stats.damage[1])
	u.abilities.assign(stats.abilities)
	u.ai_controlled = team == Types.Team.ENEMY
	return u
