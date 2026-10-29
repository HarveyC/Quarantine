class_name GearRun
extends RefCounted
## The equipment system's run-level entry points: post-fight reward offers, the starting kit,
## player choices as replicable actions, and stamping gear onto mission Units.
##
## Works on a RunState (see "Run framework" in docs/ARCHITECTURE.md); tests may pass a plain
## Dictionary with the same fields. Reads `supplies`, `act`, `rng`, `phase`, `soldiers` (records
## with `id`, `kind`, `owner`, `status`). Owns `run.gear`:
##   {"stash": [{id, mk}], "offers": {soldier id: {"source", "cards": [...]}},
##    "pity": {player: int}, "fights_won": int, "doctrine_vote": {"options", "votes"},
##    "reward_source": what the open picks are for ("kit" | "skirmish" | "nest" | "boss")}
## and `record.gear` on each soldier (see Loadout). Doctrines go to `run.modifiers.doctrines`.
##
## Actions ({"type", "player", ...}; validate returns "" or a reason):
##   gear_pick        {"soldier", "card": index or -1 to skip, optional "to_stash": true}  REWARD
##                    (the run-start deployment order can't be skipped)
##   gear_doctrine    {"doctrine": id}  vote after an act boss                               REWARD
##   gear_stash_take  {"soldier", "index"}  equip a stash item (swapped-out item takes its place)  MAP/REWARD
##   gear_unequip     {"soldier", "slot"}   move an item to the stash                        MAP/REWARD
## `player` -1 acts for anyone (only reachable from tests; RunRules rejects it).

const SKIP_SUPPLIES := 10
const CACHE_SUPPLIES := 25
## Odds (percent) per fight won that a reward offer carries the soldier's class gun while they are
## still on the sidearm; the third offer always does.
const PRIMARY_CHANCE := [50, 85, 100]
const CARD_WEIGHTS := {"gear": 37, "gun": 8, "perk": 15, "mutation": 15, "consumable": 15, "cache": 10}
const ACTION_TYPES: Array[String] = ["gear_pick", "gear_doctrine", "gear_stash_take", "gear_unequip"]
## Odds (percent) that a gun card from act 2 on is Rare rather than Uncommon.
const RARE_GUN_CHANCE := 35
const HAZARD_PAY := 10
const FIELD_RATIONS_HEAL := 0.5


# --- Run access (works on an object or a Dictionary) -------------------------------------

static func _rget(run, key: String, default: Variant = null) -> Variant:
	var v = run.get(key)
	return default if v == null else v


static func state(run) -> Dictionary:
	var gs = _rget(run, "gear")
	if not gs is Dictionary or gs.is_empty():
		gs = {"stash": [], "offers": {}, "pity": {}, "fights_won": 0, "doctrine_vote": {}}
		run["gear"] = gs
	return gs


static func add_supplies(run, n: int, reason: String = "gear") -> void:
	if run is RunState:
		RunRules.add_supplies(run, n, reason)
	else:
		run["supplies"] = int(_rget(run, "supplies", 0)) + n


static func soldiers(run) -> Array:
	return _rget(run, "soldiers", [])


## Soldiers who deploy and get reward picks.
static func squad(run) -> Array:
	if run is RunState:
		return run.squad()
	return soldiers(run).filter(func(r): return r.get("status", "active") == "active")


static func owner_of(record) -> int:
	var o = record.get("owner")
	if o == null:
		o = record.get("player")
	return int(o) if o != null else 0


## Who may make this soldier's choices: the owner, or the host while the owner is benched.
static func controller_of(run, record) -> int:
	return run.controller_of(record) if run is RunState else owner_of(record)


static func _phase_is(run, names: Array) -> bool:
	if not run is RunState:
		return true
	for n in names:
		if run.phase == RunState.Phase[n]:
			return true
	return false


static func _modifiers(run) -> Dictionary:
	var m = _rget(run, "modifiers")
	if not m is Dictionary:
		m = {}
		run["modifiers"] = m
	return m


static func soldier(run, id: int):
	for r in soldiers(run):
		if int(r.get("id")) == id:
			return r
	return null


static func _rng(run) -> RandomNumberGenerator:
	var r = _rget(run, "rng")
	assert(r is RandomNumberGenerator, "run.rng must be a RandomNumberGenerator")
	return r


## Sets up run.gear and a loadout for every soldier (squad and reserve), each with its
## starting consumable.
static func init_run(run) -> void:
	state(run)
	for r in soldiers(run):
		Loadout.of(r)
		give_starter(run, r)


## A recruit joining mid-run (RunRules.add_recruit) gets its starting consumable too.
static func on_recruit(run, record) -> void:
	Loadout.of(record)
	give_starter(run, record)


## One charge of the soldier's class consumable in a pocket (random fallback for other classes).
static func give_starter(run, record) -> void:
	var id: String = GearData.STARTER_CONSUMABLES.get(record.get("kind", ""), "")
	if id == "":
		var pool := GearData.STARTER_FALLBACK.filter(func(c): return not GearFx.is_pending(c))
		id = pool[_rng(run).randi_range(0, pool.size() - 1)]
	Loadout.add_consumable(record, id, GearData.STARTER_CHARGES)


# --- Offers ----------------------------------------------------------------------------

static func offers(run) -> Dictionary:
	return state(run).offers


static func offer_for(run, soldier_id: int) -> Dictionary:
	return offers(run).get(soldier_id, {})


## True once every pending offer has been picked or skipped.
static func all_picked(run) -> bool:
	return offers(run).is_empty()


## The run waits in REWARD while this is true (picks or a Doctrine vote open).
static func has_pending(run) -> bool:
	return not offers(run).is_empty() or not state(run).get("doctrine_vote", {}).is_empty()


## A soldier at run start: ranged classes begin on the sidearm.
static func start_soldier(record) -> void:
	Loadout.start_on_sidearm(record)
	Loadout.give_class_kit(record)


## Before the first fight each soldier picks 1 of 3 deployment orders (1 of 4 with the Field kit
## unlock): build-defining bundles, some of which start the soldier infected. See DeployOrders.
static func starting_kit_offers(run) -> void:
	var rng := _rng(run)
	var choices := 4 if MetaUnlocks.owns(_rget(run, "meta", {}), "field_kit") else 3
	state(run).reward_source = "kit"
	for r in squad(run):
		offers(run)[int(r.id)] = {"source": "kit", "cards": DeployOrders.roll(rng, r, choices)}


## What the open picks are for: "kit" before the first fight, else the fight kind that paid them.
## Lasts until the next offers open, so screens waiting on teammates still read it.
static func reward_source(run) -> String:
	return str(state(run).get("reward_source", "skirmish"))


## After a won fight: one 1-of-3 offer per living soldier. fight_kind: "skirmish" | "nest" | "boss".
static func on_fight_won(run, fight_kind: String = "skirmish") -> void:
	var gs := state(run)
	gs.fights_won += 1
	gs.reward_source = fight_kind
	var prog = GearTags.progression()
	for r in squad(run):
		var cards := roll_offer(run, r, fight_kind)
		if GearTags.provides(prog, "add_graft_card"):
			prog.add_graft_card(run, r, fight_kind, cards)
		offers(run)[int(r.id)] = {"source": fight_kind, "cards": cards}
	if doctrines(run).has("hazard_pay"):
		add_supplies(run, HAZARD_PAY, "Hazard pay")
	if fight_kind == "boss":
		_open_doctrine_vote(run)


# --- Doctrines -------------------------------------------------------------------------

static func doctrines(run) -> Array:
	return _modifiers(run).get("doctrines", [])


static func doctrine_vote(run) -> Dictionary:
	return state(run).get("doctrine_vote", {})


static func _open_doctrine_vote(run) -> void:
	var have := doctrines(run)
	var pool := GearData.DOCTRINES.keys().filter(func(d): return not have.has(d) and not MetaUnlocks.is_locked(d))
	pool.sort()
	if pool.is_empty():
		return
	var rng := _rng(run)
	var options: Array = []
	while options.size() < 3 and not pool.is_empty():
		options.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	state(run)["doctrine_vote"] = {"options": options, "votes": {}}


static func _voters(run) -> Array:
	if run is RunState:
		return run.present_players()
	var ps := {}
	for r in squad(run):
		ps[owner_of(r)] = true
	return ps.keys()


static func _resolve_doctrine_vote(run) -> void:
	var v := doctrine_vote(run)
	var tally := {}
	for p in v.votes:
		tally[v.votes[p]] = tally.get(v.votes[p], 0) + 1
	var best := ""
	var host := int(_rget(run, "host_player", 0))
	for d in v.options:
		if not tally.has(d):
			continue
		if best == "" or tally[d] > tally[best] or (tally[d] == tally[best] and v.votes.get(host) == d):
			best = d
	if best == "":
		best = v.options[0]
	var m := _modifiers(run)
	var list: Array = m.get("doctrines", [])
	list.append(best)
	m["doctrines"] = list
	if best == "field_rations":
		m["heal_after_fight"] = FIELD_RATIONS_HEAL
	state(run)["doctrine_vote"] = {}
	if run is RunState:
		run.emit({"type": "doctrine", "doctrine": best, "votes": v.votes.duplicate()})


## Three cards for one soldier. Gear is weighted to their tags; from the second fight every
## offer has a card in their lead tag and one outside their top two tags (the pivot).
static func roll_offer(run, record, fight_kind: String) -> Array:
	var rng := _rng(run)
	var gs := state(run)
	var act := int(_rget(run, "act", 1))
	var counts := GearTags.counts(record)
	var ranked := GearTags.ranked(counts)
	var player := owner_of(record)
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
				var cid := GearDraw.draw_consumable(rng)
				# Full pockets can't take it: offer gear instead of a card that can't be picked.
				if Loadout.can_add_consumable(record, cid):
					card = {"kind": "consumable", "id": cid, "charges": GearData.CONSUMABLE_CHARGES}
			"cache":
				card = {"kind": "cache", "supplies": CACHE_SUPPLIES}
			"gun":
				card = gun_card(rng, record, "rare" if act >= 2 and rng.randi_range(1, 100) <= RARE_GUN_CHANCE else "uncommon", _ids(cards))
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
	_offer_primary(rng, gs, record, cards)
	if fight_kind == "boss" and not cards.any(func(c): return c.get("kind") == "gun"):
		# Bosses always drop a gun: the last card becomes one, Rare when there is one left.
		var gun := gun_card(rng, record, "rare", _ids(cards))
		if not gun.is_empty():
			cards[cards.size() - 1] = gun
	return cards


## The soldier's class gun as a reward card, for soldiers still on the starting sidearm.
static func primary_card(record) -> Dictionary:
	var id := Weapons.id_for(str(record.get("kind", "")))
	var g := Weapons.get_gun(id)
	return {"kind": "gun", "id": id, "rarity": str(g.get("rarity", "rare")), "tags": [], "primary": true}


## Swaps the last card for the class gun on a rising chance until the soldier has it.
static func _offer_primary(rng: RandomNumberGenerator, gs: Dictionary, record, cards: Array) -> void:
	if Loadout.has_primary(record) or cards.any(func(c): return c.get("primary", false)):
		return
	var chance: int = PRIMARY_CHANCE[clampi(int(gs.fights_won) - 1, 0, PRIMARY_CHANCE.size() - 1)]
	if rng.randi_range(1, 100) <= chance:
		cards[cards.size() - 1] = primary_card(record)


## A card for an alternate gun this soldier's class can carry and doesn't own yet, preferring
## `rarity` (falls back to the other one). {} when every gun for the class is owned.
static func gun_card(rng: RandomNumberGenerator, record, rarity: String, exclude: Array = []) -> Dictionary:
	var pool := Loadout.gun_pool(record, rarity).filter(func(id): return not exclude.has(id))
	if pool.is_empty():
		pool = Loadout.gun_pool(record).filter(func(id): return not exclude.has(id))
	if pool.is_empty():
		return {}
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	return {"kind": "gun", "id": id, "rarity": Weapons.rarity_of(id), "tags": [Weapons.tag_of(id)]}


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
	var player := int(action.get("player", -1))
	if action.get("type") == "gear_doctrine":
		var v := doctrine_vote(run)
		if v.is_empty() or not _phase_is(run, ["REWARD"]):
			return "No Doctrine vote open"
		if not v.options.has(action.get("doctrine", "")):
			return "Not one of the options"
		if player != -1 and not _voters(run).has(player):
			return "Benched players don't vote"
		return ""
	var r = soldier(run, int(action.get("soldier", -1)))
	if r == null:
		return "No such soldier"
	if player != -1 and controller_of(run, r) != player:
		return "Not your soldier"
	match action.get("type"):
		"gear_pick":
			if not _phase_is(run, ["REWARD"]):
				return "No rewards to pick now"
			var offer := offer_for(run, int(r.id))
			if offer.is_empty():
				return "No reward to pick"
			var i := int(action.get("card", -1))
			if i == -1:
				return "Pick a deployment order" if offer.source == "kit" else ""
			if i < 0 or i >= offer.cards.size():
				return "No such card"
			var card: Dictionary = offer.cards[i]
			if card.kind == "order":
				for c in card.contents:
					var err := _card_error(r, c)
					if err != "":
						return err
				return ""
			if card.kind == "gear" and action.get("to_stash", false) and Loadout.stash_full(run):
				return "Stash is full"
			return _card_error(r, card)
		"gear_stash_take", "gear_unequip":
			# Between fights: on the map, at rewards, and at node screens (open the loadout there).
			if not _phase_is(run, ["MAP", "REWARD", "NODE"]):
				return "Change gear between fights"
	match action.get("type"):
		"gear_stash_take":
			var i := int(action.get("index", -1))
			if i < 0 or i >= Loadout.stash(run).size():
				return "No such stash item"
			var held: String = str(Loadout.stash(run)[i].id)
			if Weapons.is_item(held) and not Weapons.can_carry(str(r.get("kind", "")), held):
				return "They can't use that gun"
			return ""
		"gear_unequip":
			if Loadout.item_at(r, str(action.get("slot", ""))) == null or action.get("slot", "") == "gun":
				return "Nothing equipped there"
			if Loadout.stash_full(run):
				return "Stash is full"
			return ""
	return "Unknown gear action"


## Validates and applies. Returns false (and changes nothing) if illegal.
static func apply(run, action: Dictionary) -> bool:
	if validate(run, action) != "":
		return false
	if action.type == "gear_doctrine":
		var v := doctrine_vote(run)
		v.votes[int(action.get("player", 0))] = action.doctrine
		if run is RunState:
			run.emit({"type": "gear", "action": "gear_doctrine", "player": int(action.get("player", -1)), "doctrine": str(action.doctrine)})
		if _voters(run).all(func(p): return v.votes.has(p)) or int(action.get("player", 0)) == -1:
			_resolve_doctrine_vote(run)
		return true
	var r = soldier(run, int(action.soldier))
	if run is RunState:
		run.emit({"type": "gear", "action": action.type, "soldier": int(action.soldier), "player": int(action.get("player", -1))})
	match action.type:
		"gear_pick": _pick(run, r, action)
		"gear_stash_take": Loadout.take_from_stash(run, r, int(action.index))
		"gear_unequip": Loadout.unequip(run, r, str(action.slot))
	return true


## Why one reward card can't be granted to `r`, or "".
static func _card_error(r, card: Dictionary) -> String:
	if card.kind == "consumable" and not Loadout.can_add_consumable(r, card.id):
		return "Pockets are full"
	if card.kind in ["perk", "mutation", "graft"] and not GearTags.provides(GearTags.progression(), "apply_card"):
		return "Can't take that card yet"
	if card.kind == "gun" and not Weapons.can_carry(str(r.get("kind", "")), card.id):
		return "Wrong class for that gun"
	return ""


static func _pick(run, r, action: Dictionary) -> void:
	var offer: Dictionary = offers(run)[int(r.id)]
	offers(run).erase(int(r.id))
	var i := int(action.get("card", -1))
	if i == -1:
		if offer.source != "kit":
			add_supplies(run, SKIP_SUPPLIES, "Skipped a reward")
		return
	var card: Dictionary = offer.cards[i]
	if card.kind == "order":
		for c in card.contents:
			_grant(run, r, c, false)
		if int(card.get("infection", 0)) > int(r.get("infection", 0)):
			r["infection"] = int(card.infection)
		return
	_grant(run, r, card, bool(action.get("to_stash", false)))


static func _grant(run, r, card: Dictionary, to_stash: bool) -> void:
	match card.kind:
		"gear":
			if to_stash:
				Loadout.stash_add(run, card.id, 2 if card.rarity == "prototype" else 1)
			else:
				Loadout.equip(run, r, card.id)
		"perk", "mutation", "graft":
			GearTags.progression().apply_card(r, card)
		"consumable":
			Loadout.add_consumable(r, card.id, int(card.get("charges", GearData.CONSUMABLE_CHARGES)))
		"gun":
			Loadout.take_gun(r, card.id, run)
		"cache":
			add_supplies(run, int(card.get("supplies", CACHE_SUPPLIES)), "Supply cache")


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
	var docs: Array = record.get("doctrines", [])
	if not docs.is_empty():
		u.status["doctrines"] = docs.duplicate()
	Weapons.equip_unit(u, Loadout.gun(record))
	var worn := Grafts.worn_gear(record)
	if not worn.is_empty():
		var have: Dictionary = u.status.get("grafts", {})
		have.merge(worn)
		u.status["grafts"] = have
	for a in Loadout.kit_abilities(record):
		u.abilities.erase(a)
	for e in Loadout.equipped(record):
		var sig := GearData.signature_of(e.id)
		if sig != "" and not u.abilities.has(sig):
			u.abilities.append(sig)
	u.status["gear"] = g
	u.status["gear_tags"] = Loadout.gear_tags(record)
	u.status["pockets"] = Loadout.pockets(record).duplicate(true)
	if total.get("armor", 0) > 0:
		u.status["armor"] = total.armor
	Ammo.setup(u)


## After a mission (RunSoldier.absorb): consumables used in the fight are spent on the record.
static func absorb(record, u: Unit) -> void:
	sync_from_unit(u, record)


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


# --- Screens ---------------------------------------------------------------------------

## Control script for the REWARD phase: `setup(run, session)`, sends gear_pick / gear_doctrine.
static func reward_screen() -> Script:
	return load("res://ui/gear/reward_screen.gd")


## Control script for the map's loadout button: `setup(run, session)`, emits `closed`.
static func loadout_screen() -> Script:
	return load("res://ui/gear/loadout_screen.gd")


## Actions that settle every open pick and vote, for headless autoplay: the first card when it's
## legal (else a skip) for each pending offer, and the first Doctrine for each voter who hasn't voted.
static func autoplay_actions(run) -> Array:
	var out: Array = []
	for sid in offers(run).keys():
		var r = soldier(run, int(sid))
		if r == null:
			continue
		var a := {"type": "gear_pick", "player": controller_of(run, r), "soldier": int(sid), "card": 0}
		if validate(run, a) != "":
			a.card = -1
		out.append(a)
	var v := doctrine_vote(run)
	if not v.is_empty():
		for p in _voters(run):
			if not v.votes.has(p):
				out.append({"type": "gear_doctrine", "player": p, "doctrine": v.options[0]})
	return out
