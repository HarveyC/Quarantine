class_name GearData
extends RefCounted
## Item, Prototype, consumable and tag tables for the equipment system ("Equipment and builds"
## in the design doc). Tuning lives here. Ids are snake_case; tags are the 8 capitalised names.
##
## Item fields: name, tag, slot, rarity, desc (Mk I), desc_mk2, and optional `stats` /
## `stats_mk2` (flat stat changes applied when a soldier spawns, see GearRun.apply_to_unit).
## Rule effects are keyed by item id in GearFx.

const SLOTS: Array[String] = ["weapon", "ammo", "armor", "gadget"]
const SLOT_NAMES := {"weapon": "Weapon mod", "ammo": "Ammo", "armor": "Armor", "gadget": "Gadget"}
const POCKETS := 2
const STASH_SIZE := 4
const SET_THRESHOLD := 3        # one set bonus per tag at 3
const PROTOTYPE_THRESHOLD := 2  # a Prototype needs both of its tags at 2

const RARITIES: Array[String] = ["common", "uncommon", "rare", "prototype"]
const RARITY_NAMES := {"common": "Common", "uncommon": "Uncommon", "rare": "Rare", "prototype": "Prototype"}
const RARITY_COLORS := {
	"common": Color("#a8aa98"), "uncommon": Color("#8fc46a"), "rare": Color("#c08cff"), "prototype": Color("#f2c14e"),
}
const PRICES := {"common": 35, "uncommon": 55, "rare": 90}
const UPGRADE_PRICES := {"common": 30, "uncommon": 30, "rare": 50}

const TAGS: Array[String] = ["Burn", "Mark", "Suppress", "Overwatch", "Close", "Strain", "Purge", "Guard"]
const TAG_INFO := {
	"Burn": {"color": Color("#ff7a45"), "about": "Fire tiles and Burning enemies",
		"bonus": "Burning lasts 1 extra turn, and an enemy that dies Burning sets the tiles around it on fire"},
	"Mark": {"color": Color("#ff5c86"), "about": "Tagged or Marked enemies",
		"bonus": "+1 damage against Marked enemies; when a Marked enemy dies the Mark jumps to the nearest visible enemy"},
	"Suppress": {"color": Color("#b9a7ff"), "about": "Pinning enemies down",
		"bonus": "+15 aim against Suppressed enemies, and a Suppressed enemy that moves gives you a free shot"},
	"Overwatch": {"color": Color("#6fc3ff"), "about": "Reaction fire in the enemy phase",
		"bonus": "+10 overwatch aim, and an overwatch kill keeps your overwatch up"},
	"Close": {"color": Color("#e0a050"), "about": "Fighting within 3 tiles",
		"bonus": "+1 movement, and once per turn a kill within 3 tiles refunds a move"},
	"Strain": {"color": Color("#3fe0c5"), "about": "Powers fed by Infection",
		"bonus": "+1 damage while Exposed or higher, and active mutations cost 5 less Infection"},
	"Purge": {"color": Color("#e9e4d4"), "about": "Removing or moving Infection",
		"bonus": "Allies you purge also heal 1 HP, and you gain no Infection on a turn you purge someone"},
	"Guard": {"color": Color("#a9c46c"), "about": "Protecting adjacent allies",
		"bonus": "Adjacent allies get +5 defense, and once per enemy phase you take a hit meant for an adjacent ally"},
}

const ITEMS := {
	# Burn
	"flame_coat": {"name": "Flame-retardant coat", "tag": "Burn", "slot": "armor", "rarity": "common",
		"desc": "Immune to fire tiles; +1 move when you start a turn in fire",
		"desc_mk2": "Immune to fire tiles; +2 move when you start a turn in fire"},
	"igniter_barrel": {"name": "Igniter barrel", "tag": "Burn", "slot": "weapon", "rarity": "uncommon",
		"desc": "Once per turn, a hit sets the target's tile on fire for 1 turn",
		"desc_mk2": "Once per turn, a hit sets the target's tile on fire for 2 turns"},
	"incendiary_rounds": {"name": "Incendiary rounds", "tag": "Burn", "slot": "ammo", "rarity": "uncommon",
		"desc": "Hits set the target Burning",
		"desc_mk2": "Hits set the target Burning for 1 extra turn"},
	"thermite_charge": {"name": "Thermite charge", "tag": "Burn", "slot": "gadget", "rarity": "uncommon",
		"desc": "Once per fight: a 3-tile line of fire for 2 turns",
		"desc_mk2": "Once per fight: a 5-tile line of fire for 2 turns"},
	"phosphor_rounds": {"name": "Phosphor rounds", "tag": "Burn", "slot": "ammo", "rarity": "rare",
		"desc": "An enemy you kill while it's Burning sets every adjacent enemy Burning",
		"desc_mk2": "An enemy you kill while it's Burning sets every enemy within 2 tiles Burning"},
	# Mark
	"laser_sight": {"name": "Laser sight", "tag": "Mark", "slot": "weapon", "rarity": "common",
		"desc": "+10 aim", "desc_mk2": "+15 aim",
		"stats": {"aim": 10}, "stats_mk2": {"aim": 15}},
	"tracer_rounds": {"name": "Tracer rounds", "tag": "Mark", "slot": "ammo", "rarity": "common",
		"desc": "Hits Mark the target until the end of the turn",
		"desc_mk2": "Hits Mark the target until the end of the next turn"},
	"flare_launcher": {"name": "Flare launcher", "tag": "Mark", "slot": "gadget", "rarity": "uncommon",
		"desc": "Cooldown 3: Mark every enemy in a radius-1 area",
		"desc_mk2": "Cooldown 2: Mark every enemy in a radius-1 area"},
	"suppressor": {"name": "Suppressor", "tag": "Mark", "slot": "weapon", "rarity": "uncommon",
		"desc": "Shots at enemies that haven't spotted you Mark them and don't give you away",
		"desc_mk2": "Shots at enemies that haven't spotted you Mark them, +10 aim, and don't give you away"},
	"smart_link": {"name": "Smart-link", "tag": "Mark", "slot": "weapon", "rarity": "rare",
		"desc": "Shoot a Marked enemy any ally can see, even without line of sight",
		"desc_mk2": "Shoot a Marked enemy any ally can see, even without line of sight, at +10 aim"},
	# Suppress
	"compensator": {"name": "Compensator", "tag": "Suppress", "slot": "weapon", "rarity": "common",
		"desc": "Your Suppress gives a further -10 aim", "desc_mk2": "Your Suppress gives a further -15 aim"},
	"shock_rounds": {"name": "Shock rounds", "tag": "Suppress", "slot": "ammo", "rarity": "uncommon",
		"desc": "Hits Suppress the target (-15 aim on its next shot)",
		"desc_mk2": "Hits Suppress the target (-25 aim on its next shot)"},
	"concussion_launcher": {"name": "Concussion launcher", "tag": "Suppress", "slot": "gadget", "rarity": "uncommon",
		"desc": "Once per fight: Suppress every enemy in a radius-1 area",
		"desc_mk2": "Once per fight: Suppress every enemy in a radius-2 area"},
	"rotary_feed": {"name": "Rotary feed", "tag": "Suppress", "slot": "weapon", "rarity": "rare",
		"desc": "Your Suppress becomes a 3-tile cone that hits every enemy in it",
		"desc_mk2": "Your Suppress becomes a 4-tile cone that hits every enemy in it"},
	# Overwatch
	"bipod": {"name": "Bipod", "tag": "Overwatch", "slot": "weapon", "rarity": "common",
		"desc": "+10 overwatch aim if you didn't move", "desc_mk2": "+15 overwatch aim if you didn't move"},
	"motion_tracker": {"name": "Motion tracker", "tag": "Overwatch", "slot": "gadget", "rarity": "common",
		"desc": "Shows every enemy that moves within 8 tiles in the enemy phase",
		"desc_mk2": "Shows every enemy that moves within 12 tiles in the enemy phase"},
	"rangefinder": {"name": "Rangefinder", "tag": "Overwatch", "slot": "weapon", "rarity": "uncommon",
		"desc": "+2 overwatch range; overwatch treats full cover as half",
		"desc_mk2": "+3 overwatch range; overwatch treats full cover as half"},
	"expanding_rounds": {"name": "Expanding rounds", "tag": "Overwatch", "slot": "ammo", "rarity": "uncommon",
		"desc": "Overwatch hits deal +2 damage", "desc_mk2": "Overwatch hits deal +3 damage"},
	"sentry_turret": {"name": "Sentry turret", "tag": "Overwatch", "slot": "gadget", "rarity": "rare",
		"desc": "Once per fight: deploy a sentry turret within 3 tiles that fires each turn for 3 turns (aim 60, 2 damage)",
		"desc_mk2": "Once per fight: deploy a sentry turret within 3 tiles that fires each turn for 4 turns (aim 70, 3 damage)"},
	# Close
	"light_harness": {"name": "Light harness", "tag": "Close", "slot": "armor", "rarity": "common",
		"desc": "+1 movement", "desc_mk2": "+2 movement",
		"stats": {"mobility": 1}, "stats_mk2": {"mobility": 2}},
	"slug_rounds": {"name": "Slug rounds", "tag": "Close", "slot": "ammo", "rarity": "common",
		"desc": "+1 damage within 3 tiles", "desc_mk2": "+2 damage within 3 tiles"},
	"choke": {"name": "Choke", "tag": "Close", "slot": "weapon", "rarity": "uncommon",
		"desc": "Shots within 3 tiles also hit an enemy next to the target for half damage",
		"desc_mk2": "Shots within 3 tiles also hit an enemy next to the target for full damage"},
	"grapple": {"name": "Grapple", "tag": "Close", "slot": "gadget", "rarity": "uncommon",
		"desc": "Once per fight, 1 action: move 5 tiles in a straight line, walls included",
		"desc_mk2": "Twice per fight, 1 action: move 5 tiles in a straight line, walls included"},
	"exo_frame": {"name": "Exo frame", "tag": "Close", "slot": "armor", "rarity": "rare",
		"desc": "+1 movement, a 3rd pocket, and dashing doesn't end your turn",
		"desc_mk2": "+2 movement, a 3rd pocket, and dashing doesn't end your turn",
		"stats": {"mobility": 1}, "stats_mk2": {"mobility": 2}},
	# Strain
	"bio_mesh": {"name": "Bio-mesh", "tag": "Strain", "slot": "armor", "rarity": "common",
		"desc": "+1 max HP per awake mutation", "desc_mk2": "+2 max HP per awake mutation"},
	"spore_rounds": {"name": "Spore-laced rounds", "tag": "Strain", "slot": "ammo", "rarity": "uncommon",
		"desc": "+1 damage per awake mutation; each shot adds 2 Infection to you",
		"desc_mk2": "+1 damage per awake mutation, +1 more; each shot adds 2 Infection to you"},
	"adrenal_pump": {"name": "Adrenal pump", "tag": "Strain", "slot": "gadget", "rarity": "uncommon",
		"desc": "Once per fight, free: +15 Infection to yourself, to reach a tier fast",
		"desc_mk2": "Twice per fight, free: +15 Infection to yourself, to reach a tier fast"},
	"symbiotic_suit": {"name": "Symbiotic suit", "tag": "Strain", "slot": "armor", "rarity": "rare",
		"desc": "Pay mutation use costs with HP instead of Infection, 1 HP per 5",
		"desc_mk2": "Pay mutation use costs with HP instead of Infection, 1 HP per 10"},
	# Purge
	"filter_mask": {"name": "Filter mask", "tag": "Purge", "slot": "armor", "rarity": "common",
		"desc": "Spore zones don't infect you", "desc_mk2": "Spore zones don't infect you; +1 max HP",
		"stats_mk2": {"max_hp": 1}},
	"med_injector": {"name": "Med-injector", "tag": "Purge", "slot": "gadget", "rarity": "common",
		"desc": "Once per fight, 1 action: an adjacent ally loses 15 Infection",
		"desc_mk2": "Once per fight, 1 action: an adjacent ally loses 25 Infection"},
	"hazard_liner": {"name": "Hazard liner", "tag": "Purge", "slot": "armor", "rarity": "uncommon",
		"desc": "Half Infection from spores and bites", "desc_mk2": "Two thirds less Infection from spores and bites"},
	"purifier_rounds": {"name": "Purifier rounds", "tag": "Purge", "slot": "ammo", "rarity": "uncommon",
		"desc": "Each hit on an infected enemy removes 3 Infection from you",
		"desc_mk2": "Each hit on an infected enemy removes 5 Infection from you"},
	"containment_emitter": {"name": "Containment emitter", "tag": "Purge", "slot": "gadget", "rarity": "rare",
		"desc": "Cooldown 3: allies within 2 tiles gain no Infection until your next turn",
		"desc_mk2": "Cooldown 2: allies within 2 tiles gain no Infection until your next turn"},
	# Guard
	"kevlar_vest": {"name": "Kevlar vest", "tag": "Guard", "slot": "armor", "rarity": "common",
		"desc": "+2 max HP", "desc_mk2": "+3 max HP",
		"stats": {"max_hp": 2}, "stats_mk2": {"max_hp": 3}},
	"plated_rig": {"name": "Plated rig", "tag": "Guard", "slot": "armor", "rarity": "uncommon",
		"desc": "+1 armor, -1 movement", "desc_mk2": "+2 armor, -1 movement",
		"stats": {"armor": 1, "mobility": -1}, "stats_mk2": {"armor": 2, "mobility": -1}},
	"deployable_cover": {"name": "Deployable cover", "tag": "Guard", "slot": "gadget", "rarity": "uncommon",
		"desc": "Once per fight: place a full-cover barricade next to you",
		"desc_mk2": "Twice per fight: place a full-cover barricade next to you"},
	"riot_shield": {"name": "Riot shield", "tag": "Guard", "slot": "armor", "rarity": "rare",
		"desc": "You always count as in half cover, and adjacent allies share your cover",
		"desc_mk2": "You always count as in half cover, +5 defense, and adjacent allies share your cover",
		"stats_mk2": {"defense": 5}},
}

## Combo items: need both tags at 2+ on the soldier, count for both, start at Mk II, never sold.
const PROTOTYPES := {
	"spotter_flare": {"name": "Spotter flare", "tags": ["Burn", "Mark"], "slot": "gadget",
		"desc": "Marked enemies take double damage from fire"},
	"scorched_earth": {"name": "Scorched earth", "tags": ["Burn", "Purge"], "slot": "ammo",
		"desc": "Your fire doesn't hurt allies and burns 10 Infection off any ally standing in it"},
	"killbox": {"name": "Killbox", "tags": ["Mark", "Overwatch"], "slot": "weapon",
		"desc": "Overwatch never misses a Marked enemy"},
	"crossfire": {"name": "Crossfire", "tags": ["Suppress", "Overwatch"], "slot": "weapon",
		"desc": "Overwatch also fires at Suppressed enemies that don't move"},
	"breach_and_clear": {"name": "Breach and clear", "tags": ["Close", "Suppress"], "slot": "ammo",
		"desc": "Enemies you Suppress within 3 tiles lose their cover bonus"},
	"hold_position": {"name": "Hold position", "tags": ["Guard", "Suppress"], "slot": "armor",
		"desc": "While hunkered, Suppress costs 1 action and doesn't end your turn"},
	"feral_grip": {"name": "Feral grip", "tags": ["Close", "Strain"], "slot": "armor",
		"desc": "Every hit within 3 tiles, mutation attacks included, heals you 1 HP"},
	"bloodletting": {"name": "Bloodletting", "tags": ["Strain", "Purge"], "slot": "gadget",
		"desc": "When you purge an ally you may take the Infection yourself and gain 1 action"},
	"quarantine_field": {"name": "Quarantine field", "tags": ["Guard", "Purge"], "slot": "gadget",
		"desc": "Adjacent allies gain no Infection while you're hunkered"},
}

## Pocket consumables, used up. Charges stack per pocket.
const CONSUMABLES := {
	"medkit": {"name": "Medkit", "price": 12, "desc": "Heal 4 HP"},
	"flashbang": {"name": "Flashbang", "price": 15, "desc": "Enemies in radius 1 lose their next action"},
	"smoke_grenade": {"name": "Smoke grenade", "price": 15, "desc": "+20 defense in radius 1 for 2 turns"},
	"recon_drone": {"name": "Recon drone", "price": 15, "desc": "Reveals a 6-tile radius for the fight"},
	"suppressant_shot": {"name": "Suppressant shot", "price": 20, "desc": "-15 Infection"},
	"frag_grenade": {"name": "Frag grenade", "price": 20, "desc": "3 damage in radius 1, destroys cover"},
	"stim": {"name": "Stim", "price": 25, "desc": "+1 action this turn, +5 Infection"},
	"containment_foam": {"name": "Containment foam", "price": 30, "desc": "Restrains a Lapsed or Turned soldier for 2 turns without killing them"},
}
const CONSUMABLE_CHARGES := 2  # a consumable reward card gives 2 charges

## Squad-wide passives voted on after each act boss (stored in run.modifiers.doctrines).
const DOCTRINES := {
	"buddy_system": {"name": "Buddy system", "desc": "+10 aim while next to a teammate"},
	"field_rations": {"name": "Field rations", "desc": "Heal 40% after fights instead of 25%"},
	"quartermaster": {"name": "Quartermaster", "desc": "Depot prices -15%"},
	"hazard_pay": {"name": "Hazard pay", "desc": "+10 Supplies per fight"},
	"spore_filters": {"name": "Spore filters", "desc": "-25% Infection from spore zones"},
	"steady_nerves": {"name": "Steady nerves", "desc": "Talking down a Lapse costs no action"},
}

## Natural tag lanes per class (starting kit and the "on build" card before a soldier has tags).
const CLASS_LANES := {
	"trooper": ["Guard", "Suppress"], "marksman": ["Mark", "Overwatch"], "medic": ["Purge", "Guard"],
	"breacher": ["Close", "Suppress"], "hazmat": ["Burn", "Purge"], "vector": ["Strain", "Purge"],
	"reaper": ["Close", "Strain"], "warden": ["Guard", "Purge"],
}


static func exists(id: String) -> bool:
	return ITEMS.has(id) or PROTOTYPES.has(id)


## Item or Prototype entry, with `rarity` and `tags` filled in for both kinds.
static func get_item(id: String) -> Dictionary:
	if ITEMS.has(id):
		var d: Dictionary = ITEMS[id].duplicate()
		d["tags"] = [d.tag]
		d["id"] = id
		return d
	if PROTOTYPES.has(id):
		var p: Dictionary = PROTOTYPES[id].duplicate()
		p["rarity"] = "prototype"
		p["desc_mk2"] = p.desc
		p["id"] = id
		return p
	return {}


static func item_name(id: String) -> String:
	if CONSUMABLES.has(id):
		return CONSUMABLES[id].name
	return get_item(id).get("name", id)


static func tags_of(id: String) -> Array:
	return get_item(id).get("tags", [])


static func slot_of(id: String) -> String:
	return get_item(id).get("slot", "")


static func rarity_of(id: String) -> String:
	return get_item(id).get("rarity", "")


## Effect text for a given mark (1 or 2).
static func desc(id: String, mk: int = 1) -> String:
	if CONSUMABLES.has(id):
		return CONSUMABLES[id].desc
	var d := get_item(id)
	return d.get("desc_mk2" if mk >= 2 else "desc", "")


## Flat stat changes this item gives at the given mark: {aim, mobility, max_hp, defense, armor}.
static func stats(id: String, mk: int = 1) -> Dictionary:
	var d := get_item(id)
	if mk >= 2 and d.has("stats_mk2"):
		return d.stats_mk2
	return d.get("stats", {})


## Depot price; Prototypes are never sold (-1).
static func price(id: String) -> int:
	if CONSUMABLES.has(id):
		return CONSUMABLES[id].price
	return PRICES.get(rarity_of(id), -1)


## Armorer Mk II price; -1 if it can't be upgraded (Prototypes start at Mk II).
static func upgrade_price(id: String) -> int:
	return UPGRADE_PRICES.get(rarity_of(id), -1)


static func items_with(tag: String = "", rarity: String = "", slot: String = "") -> Array[String]:
	var out: Array[String] = []
	for id in ITEMS:
		var d: Dictionary = ITEMS[id]
		if (tag == "" or d.tag == tag) and (rarity == "" or d.rarity == rarity) and (slot == "" or d.slot == slot):
			out.append(id)
	return out


static func tag_color(tag: String) -> Color:
	return TAG_INFO.get(tag, {}).get("color", Color.WHITE)
