class_name UnitData
extends RefCounted
## Stat blocks for soldier classes and enemy types. Tuning lives here.

const SOLDIERS := {
	"trooper": {"name": "Trooper", "max_hp": 7, "aim": 65, "mobility": 5, "damage": [3, 5], "abilities": ["suppress"]},
	"marksman": {"name": "Marksman", "max_hp": 5, "aim": 75, "mobility": 4, "damage": [4, 6], "abilities": ["tag"]},
	"medic": {"name": "Medic", "max_hp": 6, "aim": 60, "mobility": 5, "damage": [2, 4], "abilities": ["stim"]},
	"breacher": {"name": "Breacher", "max_hp": 8, "aim": 60, "mobility": 6, "damage": [4, 7], "abilities": ["breach"]},
}

const ENEMIES := {
	"runner": {"name": "Runner", "max_hp": 4, "aim": 70, "mobility": 7, "damage": [2, 4], "abilities": ["claw"], "melee_only": true},
	"spitter": {"name": "Spitter", "max_hp": 5, "aim": 60, "mobility": 4, "damage": [2, 3], "abilities": ["spit"]},
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
