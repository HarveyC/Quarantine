extends RefCounted
## Gives sim soldiers a build of a chosen quality, so the balance sim can measure how much a
## build is worth. Every level gets the same number of pieces for the act; the levels differ in
## how well the pieces overlap on tags:
##   none       no gear, mutations or Grafts (random class perks only, as the sim always did)
##   scattered  the same pieces drawn at random from any tag
##   lane       pieces drawn from the class's two lane tags (see the class build atlas)
##   full       everything on the first lane tag (second lane tag only where a slot has none),
##              best rarity on offer, and Mk II upgrades. The sim's stand-in for a capstone build
##              until capstones exist: `capstones()` counts tags at CAPSTONE_AT pieces.
## Nothing here ships in the game. The bot does not fire active gadgets or mutations, so gear
## whose value is an active ability reads lower than it plays.

const LEVELS: Array[String] = ["none", "scattered", "lane", "full"]
const CAPSTONE_AT := 6

## Class lane tags, first is the primary tag of a "full" build.
const LANES := {
	"trooper": ["Guard", "Suppress"], "marksman": ["Mark", "Overwatch"], "medic": ["Purge", "Guard"],
	"breacher": ["Close", "Suppress"], "hazmat": ["Burn", "Purge"], "vector": ["Strain", "Purge"],
	"reaper": ["Close", "Strain"], "warden": ["Guard", "Purge"],
}

## Pieces a soldier typically owns on entering each act of a run (rank-ups come after fights
## 1/3/5/7, Grafts open from Act 2 and Rank 3).
const BUDGET := {
	1: {"gear": 1, "gun": 0, "mut": 0, "graft": 0},
	2: {"gear": 3, "gun": 1, "mut": 1, "graft": 1},
	3: {"gear": 4, "gun": 1, "mut": 2, "graft": 2},
}
## Highest item rarity on offer by act.
const RARITY_CAP := {1: 0, 2: 1, 3: 2}
const RARITY_ORDER := {"common": 0, "uncommon": 1, "rare": 2}
## Mk II upgrades by level and act (full is "everything upgraded but one").
const MK2 := {"lane": {2: 0, 3: 1}, "full": {2: 1, 3: 3}}
const SLOT_ORDER: Array[String] = ["body", "head", "offhand", "weapon", "ammo", "utility", "utility2"]


## A run-style soldier record {kind, prog, gear, infection, hp, max_hp} with the build.
static func make(rng: RandomNumberGenerator, kind: String, act: int, rank: int, level: String) -> Dictionary:
	var prog := Progression.new_record(kind)
	prog.rank = rank
	var rec := {"kind": kind, "prog": prog, "infection": 0, "hp": 10, "max_hp": 10}
	var prefs := _prefs(kind, level)
	_pick_perks(rng, prog, kind, rank, prefs, level)
	if level == "none":
		return rec
	var budget: Dictionary = BUDGET[act]
	_pick_gear(rng, rec, act, int(budget.gear), prefs, level)
	if int(budget.gun) > 0:
		_pick_gun(rng, rec, act, prefs, level)
	_pick_mutations(rng, rec, int(budget.mut), prefs, level)
	if act >= 2:
		_pick_grafts(rng, rec, int(budget.graft), prefs, level)
	prog.bedding = false   # the parts have long since settled in
	# A soldier who carries mutations has the Infection to wake them.
	var need := 0
	for slot in prog.mutations:
		need = maxi(need, Infection.THRESHOLDS[MutationData.SLOT_TIER.get(slot, 1)])
	rec.infection = maxi(int(rec.infection), mini(need, Infection.MUTATING_AT))
	return rec


## Tag counts of the record (gear, gun, perks, awake-or-not mutations, Grafts).
static func tags(rec: Dictionary) -> Dictionary:
	return GearTags.counts(rec)


## How many tags sit at CAPSTONE_AT pieces or more.
static func capstones(rec: Dictionary) -> int:
	var n := 0
	var c := tags(rec)
	for t in c:
		if int(c[t]) >= CAPSTONE_AT:
			n += 1
	return n


static func _prefs(kind: String, level: String) -> Array:
	match level:
		"lane", "full":
			return LANES.get(kind, [])
		_:
			return []


## Candidates whose tag comes first in `prefs` (or all of them when none match). `full` always
## takes the best-ranked tag, `lane` any lane tag.
static func _best(cands: Array, tag_of: Callable, prefs: Array, level: String) -> Array:
	if prefs.is_empty() or cands.is_empty():
		return cands
	if level == "full":
		for t in prefs:
			var hit := cands.filter(func(c): return tag_of.call(c) == t)
			if not hit.is_empty():
				return hit
		return cands
	var lane := cands.filter(func(c): return prefs.has(tag_of.call(c)))
	return lane if not lane.is_empty() else cands


static func _pick_perks(rng: RandomNumberGenerator, prog: Dictionary, kind: String, rank: int, prefs: Array, level: String) -> void:
	var pool: Array = []
	for id in PerkData.PERKS:
		var p: Dictionary = PerkData.PERKS[id]
		if p["class"] == kind and (not p.rare or rank >= 4):
			pool.append(id)
	var tag_of := func(id): return PerkData.PERKS[id].get("tag", "")
	for k in mini(rank - 1, 4):
		if pool.is_empty():
			break
		var from := _best(pool, tag_of, prefs, level)
		var id: String = from[rng.randi() % from.size()]
		pool.erase(id)
		prog.perks.append(id)


static func _pick_gear(rng: RandomNumberGenerator, rec: Dictionary, act: int, count: int, prefs: Array, level: String) -> void:
	var cap: int = RARITY_CAP[act]
	var slots := SLOT_ORDER.duplicate()
	if level == "scattered":
		_shuffle(rng, slots)
	var holder := {"gear": {}}
	var mk2: int = MK2.get(level, {}).get(act, 0)
	var tag_of := func(id): return GearData.ITEMS[id].tag
	var taken := 0
	for slot in slots:
		if taken >= count:
			break
		var cands: Array = []
		for id in GearData.ITEMS:
			var it: Dictionary = GearData.ITEMS[id]
			if it.slot == slot and RARITY_ORDER.get(it.rarity, 9) <= cap:
				cands.append(id)
		if cands.is_empty():
			continue
		var from := _best(cands, tag_of, prefs, level)
		if level == "full":   # best rarity on offer within the chosen tag
			var top := 0
			for id in from:
				top = maxi(top, RARITY_ORDER[GearData.ITEMS[id].rarity])
			from = from.filter(func(id): return RARITY_ORDER[GearData.ITEMS[id].rarity] == top)
		var pick: String = from[rng.randi() % from.size()]
		Loadout.equip(holder, rec, pick, 2 if taken < mk2 else 1)
		taken += 1


static func _pick_gun(rng: RandomNumberGenerator, rec: Dictionary, act: int, prefs: Array, level: String) -> void:
	var cap: int = RARITY_CAP[act]
	var cands: Array = Weapons.alternates_for(rec.kind).filter(func(id): return RARITY_ORDER.get(Weapons.rarity_of(id), 9) <= cap)
	if cands.is_empty():
		return
	var from := _best(cands, func(id): return Weapons.tag_of(id), prefs, level)
	Loadout.add_gun(rec, from[rng.randi() % from.size()])


static func _pick_mutations(rng: RandomNumberGenerator, rec: Dictionary, count: int, prefs: Array, level: String) -> void:
	var slots: Array = ["exposed", "mutating"]
	if rec.kind == "vector":
		slots.push_front("strain")
	var tag_of := func(id): return MutationData.get_def(id).get("tag", "")
	var taken := 0
	for slot in slots:
		if taken >= count:
			break
		var cands: Array = []
		for id in MutationData.MUTATIONS:
			var m: Dictionary = MutationData.MUTATIONS[id]
			if m.slot == slot and not m.get("bonded", false) and Progression.graft_error(rec, id) == "":
				cands.append(id)
		if cands.is_empty():
			continue
		var from := _best(cands, tag_of, prefs, level)
		Progression.graft(rec, from[rng.randi() % from.size()])
		taken += 1


static func _pick_grafts(rng: RandomNumberGenerator, rec: Dictionary, count: int, prefs: Array, level: String) -> void:
	var slots := GraftData.SLOTS.duplicate()
	_shuffle(rng, slots)
	var tag_of := func(id): return GraftData.get_def(id).get("tag", "")
	var taken := 0
	for slot in slots:
		if taken >= count:
			break
		var cands: Array = []
		for id in GraftData.GRAFTS:
			if GraftData.slot_of(id) == slot:
				cands.append(id)
		var from := _best(cands, tag_of, prefs, level)
		Grafts.take(rec, from[rng.randi() % from.size()])
		taken += 1


static func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
