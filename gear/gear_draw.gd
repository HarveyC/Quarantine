class_name GearDraw
extends RefCounted
## Weighted draws for reward cards and depot stock. All randomness comes from the rng passed
## in (the run's), so every peer draws the same cards.

## Rarity odds [common, uncommon, rare] for a skirmish in each act ("Post-fight rewards").
const ACT_ODDS := {1: [65, 30, 5], 2: [55, 33, 12], 3: [45, 35, 20]}
const PITY_STEP := 2           # each Common seen adds +2% to the next Rare chance
const TAG_BASE_WEIGHT := 1
const TAG_WEIGHT_PER_POINT := 2
const TAG_WEIGHT_CAP := 6
const PROTOTYPE_CHANCE := 50   # a Rare card for a qualified soldier becomes a Prototype


## Draw weight for each of the 8 tags given a soldier's (or squad's) tag counts.
static func tag_weights(counts: Dictionary) -> Dictionary:
	var out := {}
	for t in GearData.TAGS:
		out[t] = TAG_BASE_WEIGHT + mini(TAG_WEIGHT_CAP, TAG_WEIGHT_PER_POINT * int(counts.get(t, 0)))
	return out


## Picks a key from {key: weight}. Keys are visited in sorted order so draws are deterministic.
static func weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> Variant:
	var keys := weights.keys().filter(func(k): return weights[k] > 0)
	if keys.is_empty():
		return null
	keys.sort()
	var total := 0
	for k in keys:
		total += weights[k]
	var roll := rng.randi_range(1, total)
	for k in keys:
		roll -= weights[k]
		if roll <= 0:
			return k
	return keys[-1]


## Rarity for one gear card: "common" | "uncommon" | "rare". `pity` is the bonus Rare % built up.
static func roll_rarity(rng: RandomNumberGenerator, act: int, pity: int = 0) -> String:
	var odds: Array = ACT_ODDS.get(clampi(act, 1, 3))
	var rare: int = mini(100, odds[2] + pity)
	var common: int = maxi(0, odds[0] - (rare - odds[2]))
	return weighted_pick(rng, {"common": common, "uncommon": odds[1], "rare": rare})


## An item of `rarity`, its tag drawn by `counts` weighting. `only_tags` limits the tags,
## `exclude` lists item ids not to offer. Falls back to other rarities if nothing fits.
## Returns "" if no item at all is available.
static func draw_item(rng: RandomNumberGenerator, counts: Dictionary, rarity: String,
		exclude: Array = [], only_tags: Array = []) -> String:
	var order: Array[String] = [rarity]
	for r in ["common", "uncommon", "rare"]:
		if r != rarity:
			order.append(r)
	var weights := tag_weights(counts)
	for r in order:
		var by_tag := {}
		for t in GearData.TAGS:
			if not only_tags.is_empty() and not only_tags.has(t):
				continue
			var pool := GearData.items_with(t, r).filter(func(id): return not exclude.has(id))
			if not pool.is_empty():
				by_tag[t] = pool
		if by_tag.is_empty():
			continue
		var w := {}
		for t in by_tag:
			w[t] = weights[t]
		var tag: String = weighted_pick(rng, w)
		var pool: Array = by_tag[tag]
		pool.sort()
		return pool[rng.randi_range(0, pool.size() - 1)]
	return ""


## A Prototype the soldier qualifies for and doesn't hold, or "".
static func draw_prototype(rng: RandomNumberGenerator, counts: Dictionary, exclude: Array = []) -> String:
	var pool := GearTags.qualified_prototypes(counts).filter(func(id): return not exclude.has(id))
	if pool.is_empty():
		return ""
	pool.sort()
	return pool[rng.randi_range(0, pool.size() - 1)]


static func draw_consumable(rng: RandomNumberGenerator) -> String:
	var ids := GearData.CONSUMABLES.keys()
	ids.sort()
	return ids[rng.randi_range(0, ids.size() - 1)]


## Depot gear stock: one item weighted to the squad's combined tags, one random.
static func depot_items(rng: RandomNumberGenerator, squad_counts: Dictionary, act: int) -> Array[String]:
	var a := draw_item(rng, squad_counts, roll_rarity(rng, act))
	var b := draw_item(rng, {}, roll_rarity(rng, act), [a])
	return [a, b]
