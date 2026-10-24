class_name GearRun
extends RefCounted
## The equipment system's run-level entry points: post-fight reward offers, the starting kit,
## player choices as replicable actions, and stamping gear onto mission Units.
##
## Reads from the run (object or Dictionary): `supplies`, `act`, `rng`, `soldiers` (records
## with `id`, `kind`, `player`). Owns `run.gear`:
##   {"stash": [{id, mk}], "offers": {soldier id: {"source", "cards": [...]}},
##    "pity": {player: int}, "fights_won": int}
## and `record.gear` on each soldier (see Loadout).
##
## Actions ({"type", "player", ...}; validate returns "" or a reason):
##   gear_pick        {"soldier", "card": index or -1 to skip, optional "to_stash": true}
##   gear_stash_take  {"soldier", "index"}  equip a stash item (the swapped-out item takes its place)
##   gear_unequip     {"soldier", "slot"}   move an item to the stash
## `player` -1 acts for anyone (host benching an absent player's soldiers).

const SKIP_SUPPLIES := 10
const CACHE_SUPPLIES := 25
const CARD_WEIGHTS := {"gear": 45, "perk": 15, "mutation": 15, "consumable": 15, "cache": 10}
const ACTION_TYPES: Array[String] = ["gear_pick", "gear_stash_take", "gear_unequip"]


# --- Run access (works on an object or a Dictionary) -------------------------------------

static func _rget(run, key: String, default: Variant = null) -> Variant:
	var v = run.get(key)
	return default if v == null else v


static func state(run) -> Dictionary:
	var gs = _rget(run, "gear")
	if not gs is Dictionary or gs.is_empty():
		gs = {"stash": [], "offers": {}, "pity": {}, "fights_won": 0}
		run["gear"] = gs
	return gs


static func add_supplies(run, n: int) -> void:
	run["supplies"] = int(_rget(run, "supplies", 0)) + n


static func soldiers(run) -> Array:
	return _rget(run, "soldiers", [])


static func soldier(run, id: int):
	for r in soldiers(run):
		if int(r.get("id")) == id:
			return r
	return null


static func _rng(run) -> RandomNumberGenerator:
	var r = _rget(run, "rng")
	assert(r is RandomNumberGenerator, "run.rng must be a RandomNumberGenerator")
	return r


## Sets up run.gear and an empty loadout for every soldier.
static func init_run(run) -> void:
	state(run)
	for r in soldiers(run):
		Loadout.of(r)


# --- Offers ----------------------------------------------------------------------------

static func offers(run) -> Dictionary:
	return state(run).offers


static func offer_for(run, soldier_id: int) -> Dictionary:
	return offers(run).get(soldier_id, {})


## True once every pending offer has been picked or skipped.
static func all_picked(run) -> bool:
	return offers(run).is_empty()


## Before the first fight each soldier picks 1 of 3 Common items with different tags,
## at least one in the class's natural lanes.
static func starting_kit_offers(run) -> void:
	var rng := _rng(run)
	for r in soldiers(run):
		var lanes: Array = GearData.CLASS_LANES.get(r.kind, [])
		var cards: Array = []
		var used_tags: Array = []
		for i in 3:
			var only: Array = []
			if i == 0 and not lanes.is_empty():
				only = lanes
			var allowed := GearData.TAGS.filter(func(t): return not used_tags.has(t) and (only.is_empty() or only.has(t)))
			var id := GearDraw.draw_item(rng, {}, "common", [], allowed)
			if id == "":
				continue
			used_tags.append(GearData.ITEMS[id].tag)
			cards.append(_gear_card(id))
		offers(run)[int(r.id)] = {"source": "kit", "cards": cards}


## After a won fight: one 1-of-3 offer per living soldier. fight_kind: "skirmish" | "nest" | "boss".
static func on_fight_won(run, fight_kind: String = "skirmish") -> void:
	var gs := state(run)
	gs.fights_won += 1
	for r in soldiers(run):
		if r.get("dead") == true or r.get("alive") == false or r.get("turned") == true:
			continue
		offers(run)[int(r.id)] = {"source": fight_kind, "cards": roll_offer(run, r, fight_kind)}


## Three cards for one soldier. Gear is weighted to their tags; from the second fight every
## offer has a card in their lead tag and one outside their top two tags (the pivot).
static func roll_offer(run, record, fight_kind: String) -> Array:
	var rng := _rng(run)
	var gs := state(run)
	var act := int(_rget(run, "act", 1))
	var counts := GearTags.counts(record)
	var ranked := GearTags.ranked(counts)
	var player := int(record.get("player")) if record.get("player") != null else 0
	var prog = GearTags.progression()
	var vector: bool = GearTags.provides(prog, "is_vector") and prog.is_vector(record)
	var exclude := _maxed_items(record)
	var cards: Array = []
	var mutation_cards := 0
	for i in 3:
		var card := {}
		var rarity := ""
		if fight_kind == "boss":
			rarity = "rare"
		elif fight_kind == "nest" and i == 0:
			rarity = "rare"
		var kind: String = "gear" if rarity != "" else GearDraw.weighted_pick(rng, CARD_WEIGHTS)
		if vector and i < 2:
			kind = "mutation"
		if kind == "mutation" and (mutation_cards >= (2 if vector else 1)):
			kind = "gear"
		match kind:
			"perk", "mutation":
				if GearTags.provides(prog, kind + "_card"):
					card = prog.call(kind + "_card", rng, record)
					if not card.is_empty() and cards.any(func(c): return c.get("id") == card.get("id")):
						card = {}
				if not card.is_empty():
					card["kind"] = kind
					if kind == "mutation":
						mutation_cards += 1
			"consumable":
				card = {"kind": "consumable", "id": GearDraw.draw_consumable(rng), "charges": GearData.CONSUMABLE_CHARGES}
			"cache":
				card = {"kind": "cache", "supplies": CACHE_SUPPLIES}
		if card.is_empty():
			if rarity == "":
				rarity = GearDraw.roll_rarity(rng, act, gs.pity.get(player, 0))
			var only: Array = [ranked[0]] if fight_kind == "nest" and i == 0 and not ranked.is_empty() else []
			card = _draw_gear_card(rng, counts, rarity, exclude + _ids(cards), only)
			if card.is_empty():
				card = {"kind": "cache", "supplies": CACHE_SUPPLIES}
			else:
				_track_pity(gs, player, card.rarity)
		cards.append(card)
	if gs.fights_won >= 2 and not ranked.is_empty() and fight_kind != "boss":
		_ensure_on_and_off(rng, cards, counts, ranked, act, exclude)
	return cards


static func _draw_gear_card(rng: RandomNumberGenerator, counts: Dictionary, rarity: String, exclude: Array, only: Array = []) -> Dictionary:
	if rarity == "rare" and rng.randi_range(1, 100) <= GearDraw.PROTOTYPE_CHANCE:
		var proto := GearDraw.draw_prototype(rng, counts, exclude)
		if proto != "":
			return _gear_card(proto)
	var id := GearDraw.draw_item(rng, counts, rarity, exclude, only)
	return {} if id == "" else _gear_card(id)


static func _gear_card(id: String) -> Dictionary:
	return {"kind": "gear", "id": id, "rarity": GearData.rarity_of(id), "tags": GearData.tags_of(id)}


static func _track_pity(gs: Dictionary, player: int, rarity: String) -> void:
	if rarity == "common":
		gs.pity[player] = gs.pity.get(player, 0) + GearDraw.PITY_STEP
	elif rarity == "rare" or rarity == "prototype":
		gs.pity[player] = 0


static func card_tags(card: Dictionary) -> Array:
	if card.has("tags"):
		return card.tags
	var t := GearTags.normalize(str(card.get("tag", "")))
	return [t] if t != "" else []


static func _ids(cards: Array) -> Array:
	return cards.map(func(c): return c.get("id", ""))


## Items the soldier already holds at Mk II (a duplicate would do nothing).
static func _maxed_items(record) -> Array:
	return Loadout.equipped(record).filter(func(e): return e.mk >= 2).map(func(e): return e.id)


static func _ensure_on_and_off(rng: RandomNumberGenerator, cards: Array, counts: Dictionary, ranked: Array, act: int, exclude: Array) -> void:
	var lead: String = ranked[0]
	var top2: Array = ranked.slice(0, 2)
	var on := cards.find_custom(func(c): return card_tags(c).has(lead))
	if on == -1:
		on = _replace_index(cards, -1)
		var c := _draw_gear_card(rng, counts, GearDraw.roll_rarity(rng, act), exclude + _ids(cards), [lead])
		if not c.is_empty():
			cards[on] = c
	var off := cards.find_custom(func(c): return not card_tags(c).is_empty() and card_tags(c).all(func(t): return not top2.has(t)))
	if off == -1:
		off = _replace_index(cards, on)
		var others := GearData.TAGS.filter(func(t): return not top2.has(t))
		var id := GearDraw.draw_item(rng, counts, GearDraw.roll_rarity(rng, act), exclude + _ids(cards), others)
		if id != "":
			cards[off] = _gear_card(id)


## Which card to overwrite: prefer untagged filler (cache, consumable), never `keep`.
static func _replace_index(cards: Array, keep: int) -> int:
	for i in range(cards.size() - 1, -1, -1):
		if i != keep and card_tags(cards[i]).is_empty():
			return i
	return cards.size() - 1 if keep != cards.size() - 1 else cards.size() - 2


# --- Actions ---------------------------------------------------------------------------

static func handles(action: Dictionary) -> bool:
	return ACTION_TYPES.has(action.get("type", ""))


static func validate(run, action: Dictionary) -> String:
	var r = soldier(run, int(action.get("soldier", -1)))
	if r == null:
		return "No such soldier"
	var player := int(action.get("player", -1))
	if player != -1 and int(r.get("player")) != player:
		return "Not your soldier"
	match action.get("type"):
		"gear_pick":
			var offer := offer_for(run, int(r.id))
			if offer.is_empty():
				return "No reward to pick"
			var i := int(action.get("card", -1))
			if i == -1:
				return ""
			if i < 0 or i >= offer.cards.size():
				return "No such card"
			var card: Dictionary = offer.cards[i]
			if card.kind == "gear" and action.get("to_stash", false) and Loadout.stash_full(run):
				return "Stash is full"
			if card.kind == "consumable" and not Loadout.can_add_consumable(r, card.id):
				return "Pockets are full"
			if (card.kind == "perk" or card.kind == "mutation") and not GearTags.provides(GearTags.progression(), "apply_card"):
				return "Can't take that card yet"
			return ""
		"gear_stash_take":
			var i := int(action.get("index", -1))
			if i < 0 or i >= Loadout.stash(run).size():
				return "No such stash item"
			return ""
		"gear_unequip":
			if Loadout.item_at(r, str(action.get("slot", ""))) == null:
				return "Nothing equipped there"
			if Loadout.stash_full(run):
				return "Stash is full"
			return ""
	return "Unknown gear action"


## Validates and applies. Returns false (and changes nothing) if illegal.
static func apply(run, action: Dictionary) -> bool:
	if validate(run, action) != "":
		return false
	var r = soldier(run, int(action.soldier))
	match action.type:
		"gear_pick": _pick(run, r, action)
		"gear_stash_take": Loadout.take_from_stash(run, r, int(action.index))
		"gear_unequip": Loadout.unequip(run, r, str(action.slot))
	return true


static func _pick(run, r, action: Dictionary) -> void:
	var offer: Dictionary = offers(run)[int(r.id)]
	offers(run).erase(int(r.id))
	var i := int(action.get("card", -1))
	if i == -1:
		if offer.source != "kit":
			add_supplies(run, SKIP_SUPPLIES)
		return
	var card: Dictionary = offer.cards[i]
	match card.kind:
		"gear":
			if action.get("to_stash", false):
				Loadout.stash_add(run, card.id, 2 if card.rarity == "prototype" else 1)
			else:
				Loadout.equip(run, r, card.id)
		"perk", "mutation":
			GearTags.progression().apply_card(r, card)
		"consumable":
			Loadout.add_consumable(r, card.id, int(card.get("charges", GearData.CONSUMABLE_CHARGES)))
		"cache":
			add_supplies(run, int(card.get("supplies", CACHE_SUPPLIES)))


# --- Missions --------------------------------------------------------------------------

## Stamps a soldier's gear onto their mission Unit: flat stats (aim, mobility, defense,
## max HP), and in `unit.status`: "gear" {slot: {id, mk}}, "gear_tags", "pockets", "armor".
## Call before restoring carried-over HP, and clamp that HP to unit.max_hp.
static func apply_to_unit(u: Unit, record) -> void:
	var g := {}
	var total := {}
	for e in Loadout.equipped(record):
		g[e.slot] = {"id": e.id, "mk": e.mk}
		var st := GearData.stats(e.id, e.mk)
		for k in st:
			total[k] = total.get(k, 0) + st[k]
	u.aim += total.get("aim", 0)
	u.defense += total.get("defense", 0)
	u.mobility = maxi(1, u.mobility + total.get("mobility", 0))
	u.max_hp += total.get("max_hp", 0)
	u.hp = clampi(u.hp + total.get("max_hp", 0), 1, u.max_hp)
	u.status["gear"] = g
	u.status["gear_tags"] = Loadout.gear_tags(record)
	u.status["pockets"] = Loadout.pockets(record).duplicate(true)
	if total.get("armor", 0) > 0:
		u.status["armor"] = total.armor


## After a mission: write consumables used in the fight back to the record's pockets.
static func sync_from_unit(u: Unit, record) -> void:
	if u.status.has("pockets"):
		Loadout.of(record).pockets = u.status.pockets.duplicate(true)


## Combined tag counts of the squad (for the depot's weighted slot).
static func squad_counts(run) -> Dictionary:
	var out := {}
	for r in soldiers(run):
		var c := GearTags.counts(r)
		for t in c:
			out[t] = out.get(t, 0) + c[t]
	return out
