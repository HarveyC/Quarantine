class_name DeployOrders
extends RefCounted
## Deployment orders: the run-start pick. Before the first fight each soldier takes one order,
## a build-defining bundle that is stronger than a post-fight reward. Some orders are clean,
## others trade starting Infection for power (a Rare, a Prototype, an awake mutation).
##
## An order card is {"kind": "order", "id", "name", "desc", "infection", "contents": [cards]}.
## Contents are ordinary reward cards (gear, gun, mutation) that GearRun grants one by one;
## `infection` is the floor the soldier deploys at.

## One safe order (clean) and one risky order (starts infected) in every offer, then the rest.
const ORDERS := {
	"standard_issue": {"name": "Standard issue", "risk": false, "infection": 0,
		"desc": "An Uncommon item that fits the class."},
	"quartermaster": {"name": "Quartermaster", "risk": false, "infection": 0,
		"desc": "Two Common items in different slots, one that fits the class."},
	"requisition": {"name": "Requisition", "risk": false, "infection": 0,
		"desc": "An alternate gun for the class, carried from the first fight."},
	"bloom_cache": {"name": "Bloom-touched cache", "risk": true, "infection": 20,
		"desc": "A Rare item that fits the class, pulled from an infected depot."},
	"early_graft": {"name": "Early graft", "risk": true, "infection": 25,
		"desc": "An Exposed mutation, awake from the first fight."},
	"prototype_trial": {"name": "Prototype trial", "risk": true, "infection": 35,
		"desc": "A field Prototype, no tag requirement. The test rig leaks."},
}


static func is_risky(id: String) -> bool:
	return bool(ORDERS.get(id, {}).get("risk", false))


## `choices` order cards for one soldier: a clean one first, a risky one second, then any.
## Orders that can't be filled for this soldier (no gun left, no mutation hook) are left out.
static func roll(rng: RandomNumberGenerator, record, choices: int) -> Array:
	var safe: Array = ORDERS.keys().filter(func(k): return not is_risky(k))
	var risky: Array = ORDERS.keys().filter(func(k): return is_risky(k))
	safe.sort()
	risky.sort()
	var picked: Array = []
	var cards: Array = []
	_draw_into(rng, record, safe, picked, cards, 1)
	_draw_into(rng, record, risky, picked, cards, 1)
	_draw_into(rng, record, safe + risky, picked, cards, choices - cards.size())
	return cards


static func _draw_into(rng: RandomNumberGenerator, record, pool: Array, picked: Array, cards: Array, n: int) -> void:
	var left := pool.filter(func(k): return not picked.has(k))
	while n > 0 and not left.is_empty():
		var id: String = left[rng.randi_range(0, left.size() - 1)]
		left.erase(id)
		picked.append(id)
		var card := build(rng, record, id)
		if not card.is_empty():
			cards.append(card)
			n -= 1


## The order card for `id`, its contents drawn for this soldier, or {} if it can't be filled.
static func build(rng: RandomNumberGenerator, record, id: String) -> Dictionary:
	var o: Dictionary = ORDERS[id]
	var lanes: Array = GearData.CLASS_LANES.get(record.get("kind", ""), [])
	var contents: Array = []
	match id:
		"standard_issue":
			contents = _items(rng, ["uncommon"], lanes)
		"quartermaster":
			contents = _items(rng, ["common", "common"], lanes)
		"bloom_cache":
			contents = _items(rng, ["rare"], lanes)
		"requisition":
			var gun := GearRun.gun_card(rng, record, "uncommon") if Loadout.has_primary(record) else GearRun.primary_card(record)
			if not gun.is_empty():
				contents = [gun]
		"early_graft":
			var prog = GearTags.progression()
			if GearTags.provides(prog, "mutation_card"):
				var pool: Array = MutationData.regular_pool("exposed")
				if not pool.is_empty():
					pool.sort()
					contents = [prog.mutation_card_for(pool[rng.randi_range(0, pool.size() - 1)])]
		"prototype_trial":
			var proto := _prototype(rng, lanes)
			if proto != "":
				contents = [GearRun._gear_card(proto)]
	if contents.is_empty():
		return {}
	return {"kind": "order", "id": id, "name": o.name, "desc": o.desc, "infection": int(o.infection),
		"contents": contents}


## Items of the given rarities, each in a different slot and tag; the first is in a class lane.
static func _items(rng: RandomNumberGenerator, rarities: Array, lanes: Array) -> Array:
	var out: Array = []
	var used_tags: Array = []
	var used_slots: Array = []
	var exclude: Array = []
	for i in rarities.size():
		var allowed := GearData.TAGS.filter(func(t): return not used_tags.has(t) and (i > 0 or lanes.is_empty() or lanes.has(t)))
		var id := ""
		for _try in 6:
			id = GearDraw.draw_item(rng, {}, rarities[i], exclude, allowed)
			if id == "" or not used_slots.has(GearData.slot_of(id)):
				break
			exclude.append(id)
			id = ""
		if id == "":
			continue
		used_tags.append(GearData.ITEMS[id].tag)
		used_slots.append(GearData.slot_of(id))
		exclude.append(id)
		out.append(GearRun._gear_card(id))
	return out


## A Prototype that shares a tag with the class lanes (any Prototype if none does).
static func _prototype(rng: RandomNumberGenerator, lanes: Array) -> String:
	var all := GearData.PROTOTYPES.keys().filter(func(p): return not GearFx.is_pending(p) and not MetaUnlocks.is_locked(p))
	all.sort()
	var lane := all.filter(func(p): return GearData.PROTOTYPES[p].tags.any(func(t): return lanes.has(t)))
	var pool: Array = lane if not lane.is_empty() else all
	return "" if pool.is_empty() else pool[rng.randi_range(0, pool.size() - 1)]
