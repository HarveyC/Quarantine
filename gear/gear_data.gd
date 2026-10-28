class_name GearData
extends RefCounted
## Item, Prototype, consumable and tag tables for the equipment system ("Equipment and builds"
## in the design doc). Tuning lives here. Ids are snake_case; tags are the 8 capitalised names.
##
## Item fields: name, tag, slot, rarity, desc (Mk I), desc_mk2, and optional `stats` /
## `stats_mk2` (flat stat changes applied when a soldier spawns, see GearRun.apply_to_unit).
## Rule effects are keyed by item id in GearFx.

## Soldier slots. Items declare a slot TYPE (`slot_of`); "utility" fits either utility slot.
const SLOTS: Array[String] = ["head", "body", "offhand", "weapon", "ammo", "utility", "utility2"]
const SLOT_NAMES := {"head": "Head", "body": "Body", "offhand": "Offhand", "weapon": "Weapon mod", "ammo": "Ammo",
	"utility": "Utility", "utility2": "Utility"}
const POCKETS := 2
const STASH_SIZE := 4
const SET_THRESHOLD := 3        # one set bonus per tag at 3
const CAPSTONE_THRESHOLD := 6   # one rule-bending capstone per tag at 6 (see TAG_INFO "capstone")
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
		"bonus": "Burning lasts 1 extra turn, an enemy that dies Burning sets the tiles around it on fire, and Burning enemies hit you for 1 less",
		"capstone_name": "Wildfire", "capstone": "Each turn a Burning enemy sets every enemy next to it Burning, and your fire ignores armour"},
	"Mark": {"color": Color("#ff5c86"), "about": "Marked enemies",
		"bonus": "the second hit each turn on a Marked enemy deals double, when a Marked enemy dies the Mark jumps to the nearest visible enemy, and Marked enemies hit you for 1 less",
		"capstone_name": "Warrant", "capstone": "Your Marks never expire, squad shots at a Marked enemy get +20 aim, and your kills on one refund an action"},
	"Suppress": {"color": Color("#b9a7ff"), "about": "Pinning enemies down",
		"bonus": "a Suppressed enemy that moves gives you a free shot, and Suppressed enemies hit you for 1 less"},
	"Overwatch": {"color": Color("#6fc3ff"), "about": "Reaction fire in the enemy phase",
		"bonus": "an overwatch kill keeps your overwatch up and heals you 1 HP",
		"capstone_name": "Field of Fire", "capstone": "Your overwatch fires at every enemy that moves in range, not just the first"},
	"Close": {"color": Color("#e0a050"), "about": "Fighting within 3 tiles",
		"bonus": "once per turn a kill within 3 tiles refunds a move and heals you 1 HP"},
	"Strain": {"color": Color("#3fe0c5"), "about": "Powers fed by Infection",
		"bonus": "active mutations cost 5 less Infection, and while Exposed or higher Infected hit you for 1 less"},
	"Purge": {"color": Color("#e9e4d4"), "about": "Removing or moving Infection",
		"bonus": "Allies you purge also heal 1 HP, you gain no Infection on a turn you purge someone, and you and allies within 2 tiles take a quarter less Infection"},
	"Guard": {"color": Color("#a9c46c"), "about": "Protecting adjacent allies",
		"bonus": "Adjacent allies get +5 defense, you and adjacent allies take a quarter less Infection, and once per enemy phase you take a hit meant for an adjacent ally",
		"capstone_name": "Aegis", "capstone": "One hit can't kill you from above 1 HP, and damage you take for an ally goes back to the attacker"},
}

const ITEMS := {
	# Burn
	"flame_coat": {"name": "Flame-retardant coat", "tag": "Burn", "slot": "body", "rarity": "common",
		"desc": "Immune to fire tiles; +1 move when you start a turn in fire",
		"desc_mk2": "Immune to fire tiles; +2 move when you start a turn in fire"},
	"igniter_barrel": {"name": "Igniter barrel", "tag": "Burn", "slot": "weapon", "rarity": "uncommon",
		"desc": "Once per turn, a hit sets the target's tile on fire for 1 turn",
		"desc_mk2": "Once per turn, a hit sets the target's tile on fire for 2 turns"},
	"incendiary_rounds": {"name": "Incendiary rounds", "tag": "Burn", "slot": "ammo", "rarity": "uncommon",
		"desc": "Hits set the target Burning",
		"desc_mk2": "Hits set the target Burning for 1 extra turn"},
	"thermite_charge": {"name": "Thermite charge", "tag": "Burn", "slot": "utility", "rarity": "uncommon",
		"desc": "Once per fight: a 3-tile line of fire for 2 turns",
		"desc_mk2": "Once per fight: a 5-tile line of fire for 2 turns"},
	"phosphor_rounds": {"name": "Phosphor rounds", "tag": "Burn", "slot": "ammo", "rarity": "rare",
		"desc": "An enemy you kill while it's Burning sets every adjacent enemy Burning",
		"desc_mk2": "An enemy you kill while it's Burning sets every enemy within 2 tiles Burning"},
	# Mark
	"laser_sight": {"name": "Painter", "tag": "Mark", "slot": "weapon", "rarity": "common",
		"desc": "Your first shot each turn Marks the target and ignores its cover",
		"desc_mk2": "Your first shot each turn Marks the target for 3 turns and ignores its cover"},
	"tracer_rounds": {"name": "Tracer rounds", "tag": "Mark", "slot": "ammo", "rarity": "common",
		"desc": "Hits Mark the target until the end of the turn",
		"desc_mk2": "Hits Mark the target until the end of the next turn"},
	"flare_launcher": {"name": "Flare launcher", "tag": "Mark", "slot": "utility", "rarity": "uncommon",
		"desc": "Cooldown 3: Mark every enemy in a radius-1 area",
		"desc_mk2": "Cooldown 2: Mark every enemy in a radius-1 area"},
	"suppressor": {"name": "Suppressor", "tag": "Mark", "slot": "weapon", "rarity": "uncommon",
		"desc": "Shots at enemies that haven't spotted you Mark them and don't give you away",
		"desc_mk2": "Shots at enemies that haven't spotted you Mark them, +10 aim, and don't give you away"},
	"smart_link": {"name": "Smart-link", "tag": "Mark", "slot": "weapon", "rarity": "rare",
		"desc": "Shoot a Marked enemy any ally can see, even without line of sight",
		"desc_mk2": "Shoot a Marked enemy any ally can see, even without line of sight, at +10 aim"},
	# Suppress
	"compensator": {"name": "Recoil lock", "tag": "Suppress", "slot": "weapon", "rarity": "common",
		"desc": "Your Suppress also pins every enemy next to the target",
		"desc_mk2": "Your Suppress also pins every enemy within 2 tiles of the target"},
	"scavenger_rounds": {"name": "Scavenger rounds", "tag": "Suppress", "slot": "ammo", "rarity": "uncommon",
		"desc": "A kill gives 1 round back",
		"desc_mk2": "A kill gives 2 rounds back"},
	"shock_rounds": {"name": "Shock rounds", "tag": "Suppress", "slot": "ammo", "rarity": "uncommon",
		"desc": "Hits Suppress the target (-15 aim on its next shot)",
		"desc_mk2": "Hits Suppress the target (-25 aim on its next shot)"},
	"concussion_launcher": {"name": "Concussion launcher", "tag": "Suppress", "slot": "utility", "rarity": "uncommon",
		"desc": "Once per fight: Suppress every enemy in a radius-1 area",
		"desc_mk2": "Once per fight: Suppress every enemy in a radius-2 area"},
	"rotary_feed": {"name": "Rotary feed", "tag": "Suppress", "slot": "weapon", "rarity": "rare",
		"desc": "Your Suppress becomes a 3-tile cone that hits every enemy in it",
		"desc_mk2": "Your Suppress becomes a 4-tile cone that hits every enemy in it"},
	# Overwatch
	"extended_mag": {"name": "Drum swap", "tag": "Overwatch", "slot": "weapon", "rarity": "common",
		"desc": "A Reload also fires one free shot at a Suppressed enemy you can see",
		"desc_mk2": "A Reload also fires two free shots at Suppressed enemies you can see"},
	"bipod": {"name": "Dug in", "tag": "Overwatch", "slot": "weapon", "rarity": "common",
		"desc": "An enemy that ends its move in the open takes your Overwatch shot twice",
		"desc_mk2": "An enemy that ends its move in half cover or the open takes your Overwatch shot twice"},
	"motion_tracker": {"name": "Motion tracker", "tag": "Overwatch", "slot": "utility", "rarity": "common",
		"desc": "Shows every enemy that moves within 8 tiles in the enemy phase",
		"desc_mk2": "Shows every enemy that moves within 12 tiles in the enemy phase"},
	"rangefinder": {"name": "Long line", "tag": "Overwatch", "slot": "weapon", "rarity": "uncommon",
		"desc": "Overwatch reaches as far as you can see, and treats full cover as half",
		"desc_mk2": "Overwatch reaches as far as you can see, and ignores cover"},
	"expanding_rounds": {"name": "Wounding rounds", "tag": "Overwatch", "slot": "ammo", "rarity": "uncommon",
		"desc": "Overwatch hits leave a wound that deals the same damage again when your next turn starts",
		"desc_mk2": "Overwatch hits leave a wound that deals the same damage again when your next turn starts, and roots the target"},
	"sentry_turret": {"name": "Sentry turret", "tag": "Overwatch", "slot": "utility", "rarity": "rare",
		"desc": "Once per fight: deploy a sentry turret within 3 tiles that fires each turn for 3 turns (aim 60, 2 damage)",
		"desc_mk2": "Once per fight: deploy a sentry turret within 3 tiles that fires each turn for 4 turns (aim 70, 3 damage)"},
	# Close
	"speed_loader": {"name": "Speed loader", "tag": "Close", "slot": "weapon", "rarity": "uncommon",
		"desc": "The first Reload each turn costs no action",
		"desc_mk2": "The first Reload each turn costs no action, and shots that turn get +10 aim"},
	"light_harness": {"name": "Slipstream", "tag": "Close", "slot": "body", "rarity": "common",
		"desc": "After a move of 4 or more tiles, your next shot costs no action",
		"desc_mk2": "After a move of 3 or more tiles, your next shot costs no action"},
	"slug_rounds": {"name": "Knock rounds", "tag": "Close", "slot": "ammo", "rarity": "common",
		"desc": "Close hits shove the target a tile. Into a wall or unit, both take 2 damage and it is stunned",
		"desc_mk2": "Close hits shove the target a tile. Into a wall or unit, both take 3 damage and it is stunned"},
	"choke": {"name": "Choke", "tag": "Close", "slot": "weapon", "rarity": "uncommon",
		"desc": "Shots within 3 tiles also hit an enemy next to the target for half damage",
		"desc_mk2": "Shots within 3 tiles also hit an enemy next to the target for full damage"},
	"grapple": {"name": "Grapple", "tag": "Close", "slot": "utility", "rarity": "uncommon",
		"desc": "Once per fight, 1 action: move 5 tiles in a straight line, walls included",
		"desc_mk2": "Twice per fight, 1 action: move 5 tiles in a straight line, walls included"},
	"exo_frame": {"name": "Exo frame", "tag": "Close", "slot": "body", "rarity": "rare",
		"desc": "A third pocket. A move that ends next to an enemy slams it back a tile and Suppresses it",
		"desc_mk2": "A third pocket. A move that ends next to an enemy slams it back a tile, Suppresses it and deals 2 damage"},
	# Strain
	"bio_mesh": {"name": "Graft weave", "tag": "Strain", "slot": "body", "rarity": "common",
		"desc": "Each awake mutation heals you 2 HP every team phase",
		"desc_mk2": "Each awake mutation heals you 3 HP every team phase"},
	"spore_rounds": {"name": "Spore-laced rounds", "tag": "Strain", "slot": "ammo", "rarity": "uncommon",
		"desc": "+1 damage per awake mutation; each shot adds 2 Infection to you",
		"desc_mk2": "+1 damage per awake mutation, +1 more; each shot adds 2 Infection to you"},
	"adrenal_pump": {"name": "Adrenal pump", "tag": "Strain", "slot": "utility", "rarity": "uncommon",
		"desc": "Once per fight, free: +15 Infection to yourself, to reach a tier fast",
		"desc_mk2": "Twice per fight, free: +15 Infection to yourself, to reach a tier fast"},
	"symbiotic_suit": {"name": "Symbiotic suit", "tag": "Strain", "slot": "body", "rarity": "rare",
		"desc": "Pay mutation use costs with HP instead of Infection, 1 HP per 5 (not if it would drop you)",
		"desc_mk2": "Pay mutation use costs with HP instead of Infection, 1 HP per 10 (not if it would drop you)"},
	# Purge
	"filter_mask": {"name": "Filter mask", "tag": "Purge", "slot": "head", "rarity": "common",
		"desc": "Spore zones don't infect you", "desc_mk2": "Spore zones don't infect you, and a Purge on you also heals 3 HP"},
	"med_injector": {"name": "Med-injector", "tag": "Purge", "slot": "utility", "rarity": "common",
		"desc": "Once per fight, 1 action: an adjacent ally loses 15 Infection",
		"desc_mk2": "Once per fight, 1 action: an adjacent ally loses 25 Infection"},
	"hazard_liner": {"name": "Hazard liner", "tag": "Purge", "slot": "body", "rarity": "uncommon",
		"desc": "Half Infection from spores and bites", "desc_mk2": "Two thirds less Infection from spores and bites"},
	"purifier_rounds": {"name": "Purifier rounds", "tag": "Purge", "slot": "ammo", "rarity": "uncommon",
		"desc": "Each hit on an infected enemy removes 3 Infection from you",
		"desc_mk2": "Each hit on an infected enemy removes 5 Infection from you"},
	"containment_emitter": {"name": "Containment emitter", "tag": "Purge", "slot": "utility", "rarity": "rare",
		"desc": "Cooldown 3: allies within 2 tiles gain no Infection until your next turn",
		"desc_mk2": "Cooldown 2: allies within 2 tiles gain no Infection until your next turn"},
	# Guard
	"kevlar_vest": {"name": "Trauma plate", "tag": "Guard", "slot": "body", "rarity": "common",
		"desc": "The first hit each fight is cut to 1 damage. The plate cracks until you Reload",
		"desc_mk2": "The first two hits each fight are cut to 1 damage. A Reload re-seats the plate"},
	"plated_rig": {"name": "Planted rig", "tag": "Guard", "slot": "body", "rarity": "uncommon",
		"desc": "If you haven't moved this turn, hits on you deal half damage",
		"desc_mk2": "If you haven't moved this turn, hits on you deal a third of their damage"},
	"deployable_cover": {"name": "Deployable cover", "tag": "Guard", "slot": "utility", "rarity": "uncommon",
		"desc": "Once per fight: place a full-cover barricade next to you",
		"desc_mk2": "Twice per fight: place a full-cover barricade next to you"},
	"riot_shield": {"name": "Riot shield", "tag": "Guard", "slot": "offhand", "rarity": "rare",
		"desc": "You always count as in half cover, and adjacent allies share your cover",
		"desc_mk2": "You always count as in half cover, adjacent allies share your cover, and the first adjacent enemy to hit you each turn is stunned"},
	# Content pack 2 (acts 2 and 3): one or two more per tag so runs draw wider.
	"pilot_light": {"name": "Wick", "tag": "Burn", "slot": "weapon", "rarity": "common",
		"desc": "Hitting a Burning enemy sets 2 tiles of fire behind it",
		"desc_mk2": "Hitting a Burning enemy sets 4 tiles of fire behind it"},
	"ember_plating": {"name": "Ember plating", "tag": "Burn", "slot": "body", "rarity": "uncommon",
		"desc": "An enemy that damages you starts Burning",
		"desc_mk2": "An enemy that damages you starts Burning for 1 extra turn"},
	"spotter_scope": {"name": "Dead reckoning", "tag": "Mark", "slot": "weapon", "rarity": "uncommon",
		"desc": "Your shots at a Marked enemy cannot miss, and Mark the nearest other enemy within 3 tiles",
		"desc_mk2": "Your shots at a Marked enemy cannot miss, and Mark the nearest other enemy within 3 tiles for 2 turns"},
	"hollow_points": {"name": "Pin shot", "tag": "Suppress", "slot": "ammo", "rarity": "uncommon",
		"desc": "Hitting a Suppressed enemy roots it in place for a turn",
		"desc_mk2": "Hitting a Suppressed enemy roots it in place for 2 turns"},
	"ghillie_cloak": {"name": "Still life", "tag": "Overwatch", "slot": "head", "rarity": "uncommon",
		"desc": "Your Overwatch shots at enemies that haven't spotted you cannot miss and Mark the target",
		"desc_mk2": "Your Overwatch shots at enemies that haven't spotted you cannot miss and Mark the target for 3 turns"},
	"match_rounds": {"name": "Tight group", "tag": "Overwatch", "slot": "ammo", "rarity": "common",
		"desc": "Each further hit on the same target in a turn repeats your first hit's damage",
		"desc_mk2": "Each further hit on the same target in a turn repeats your first hit's damage, Overwatch shots included"},
	"bayonet": {"name": "Fixed blade", "tag": "Close", "slot": "weapon", "rarity": "common",
		"desc": "A kill within 2 tiles stabs an adjacent enemy for 3 damage, once a turn",
		"desc_mk2": "A kill within 2 tiles stabs an adjacent enemy for 5 damage, once a turn"},
	"mycelial_weave": {"name": "Acid blister", "tag": "Strain", "slot": "body", "rarity": "uncommon",
		"desc": "When you are hit, the attacker's tile is splashed with acid for 2 turns, once a turn",
		"desc_mk2": "When you are hit, the attacker's tile and the tiles around it are splashed with acid for 2 turns"},
	"leech_rounds": {"name": "Leech rounds", "tag": "Strain", "slot": "ammo", "rarity": "rare",
		"desc": "While Exposed or higher, hits heal you 1 HP and add 2 Infection to you",
		"desc_mk2": "While Exposed or higher, hits heal you 1 HP and add 1 Infection to you"},
	"purge_canister": {"name": "Purge canister", "tag": "Purge", "slot": "ammo", "rarity": "common",
		"desc": "Each kill removes 5 Infection from you", "desc_mk2": "Each kill removes 10 Infection from you"},
	"ballistic_plate": {"name": "Spall liner", "tag": "Guard", "slot": "body", "rarity": "common",
		"desc": "A hit on you throws half its damage back at every adjacent enemy",
		"desc_mk2": "A hit on you throws its full damage back at every adjacent enemy"},
	# Links: items that feed each other. Each one takes a status in, puts a status out, or spreads one,
	# so the right pair multiplies instead of adding.
	"chain_link": {"name": "Chain-link rounds", "tag": "Mark", "slot": "ammo", "rarity": "rare",
		"desc": "Marking an enemy also Marks every enemy next to it",
		"desc_mk2": "Marking an enemy also Marks every enemy within 2 tiles of it"},
	"echo_array": {"name": "Echo array", "tag": "Mark", "slot": "weapon", "rarity": "rare",
		"desc": "A hit on a Marked enemy deals 1 damage to every other Marked enemy you can see",
		"desc_mk2": "A hit on a Marked enemy deals 2 damage to every other Marked enemy you can see"},
	"cinder_lens": {"name": "Cinder lens", "tag": "Burn", "slot": "weapon", "rarity": "rare",
		"desc": "Enemies you set Burning are also Marked while they burn",
		"desc_mk2": "Enemies you set Burning are also Marked, and the Mark outlasts the fire"},
	"flash_fry": {"name": "Flash-fry grips", "tag": "Close", "slot": "offhand", "rarity": "rare",
		"desc": "A kill within 3 tiles sets every enemy next to the victim Burning",
		"desc_mk2": "A kill within 3 tiles sets every enemy within 2 tiles of the victim Burning"},
	"pressure_nozzle": {"name": "Pressure nozzle", "tag": "Suppress", "slot": "weapon", "rarity": "rare",
		"desc": "Suppressing an enemy also sets it Burning",
		"desc_mk2": "Suppressing an enemy also sets it Burning for 2 turns"},
	"cascade_rounds": {"name": "Cascade rounds", "tag": "Suppress", "slot": "ammo", "rarity": "rare",
		"desc": "Suppressing an enemy also Suppresses every enemy next to it",
		"desc_mk2": "Suppressing an enemy also Suppresses every enemy within 2 tiles of it"},
	"pin_tag_rounds": {"name": "Pin-tag rounds", "tag": "Suppress", "slot": "ammo", "rarity": "rare",
		"desc": "Hits on a Marked enemy Suppress it",
		"desc_mk2": "Hits on a Marked enemy Suppress it, with a further -10 aim"},
	"hair_trigger": {"name": "Hair-trigger harness", "tag": "Overwatch", "slot": "body", "rarity": "rare",
		"desc": "While on overwatch, you fire at any enemy in sight that becomes Marked",
		"desc_mk2": "While on overwatch, you fire at any enemy in sight that becomes Marked, and the shot keeps your overwatch"},
	"patient_eye": {"name": "Patient eye", "tag": "Overwatch", "slot": "weapon", "rarity": "uncommon",
		"desc": "Your overwatch hits Mark the target",
		"desc_mk2": "Your overwatch hits Mark the target and Mark the enemies next to it"},
	"kill_spill": {"name": "Kill spill", "tag": "Close", "slot": "ammo", "rarity": "uncommon",
		"desc": "A kill within 3 tiles deals half the shot's damage to an enemy next to the victim",
		"desc_mk2": "A kill within 3 tiles deals the shot's full damage to an enemy next to the victim"},
	"retaliation_plate": {"name": "Retaliation plate", "tag": "Guard", "slot": "offhand", "rarity": "rare",
		"desc": "An enemy that damages you is Marked",
		"desc_mk2": "An enemy that damages you is Marked and Suppressed"},
	"serum_lance": {"name": "Serum lance", "tag": "Purge", "slot": "weapon", "rarity": "rare",
		"desc": "When you purge an ally, enemies next to them are Marked and take 2 damage",
		"desc_mk2": "When you purge an ally, enemies within 2 tiles of them are Marked and take 3 damage"},
	"volatile_spores": {"name": "Volatile spores", "tag": "Strain", "slot": "ammo", "rarity": "rare",
		"desc": "While Exposed or higher, a hit on a Burning enemy bursts it: 2 damage to enemies next to it",
		"desc_mk2": "While Exposed or higher, a hit on a Burning enemy bursts it: 3 damage to enemies next to it"},
	# Links into reloading and Rank 2 signatures.
	"signal_drum": {"name": "Signal drum", "tag": "Mark", "slot": "ammo", "rarity": "uncommon",
		"desc": "Reloading Marks the nearest enemy you can see",
		"desc_mk2": "Reloading Marks the two nearest enemies you can see"},
	"ember_loader": {"name": "Ember loader", "tag": "Burn", "slot": "weapon", "rarity": "uncommon",
		"desc": "Reloading sets the nearest enemy within 4 tiles Burning",
		"desc_mk2": "Reloading sets every enemy within 3 tiles Burning"},
	"ready_stance": {"name": "Ready stance", "tag": "Overwatch", "slot": "ammo", "rarity": "uncommon",
		"desc": "Reloading puts you on overwatch",
		"desc_mk2": "Reloading puts you on overwatch with +10 aim on its next shot"},
	"bounty_ledger": {"name": "Bounty ledger", "tag": "Mark", "slot": "head", "rarity": "rare",
		"desc": "A kill on a Marked enemy cuts your signature ability's cooldown by 1",
		"desc_mk2": "A kill on a Marked enemy cuts your signature ability's cooldown by 2"},
	"blood_clock": {"name": "Blood clock", "tag": "Close", "slot": "weapon", "rarity": "rare",
		"desc": "Once a turn, a kill within 3 tiles cuts your signature ability's cooldown by 1",
		"desc_mk2": "Once a turn, a kill within 3 tiles cuts your signature ability's cooldown by 2"},
	# Signature rigs: any soldier can carry a class signature (GearRun.apply_to_unit grants the ability)
	"sig_lockdown": {"name": "Lockdown rig", "tag": "Overwatch", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Lockdown ability",
		"desc_mk2": "Grants the Lockdown ability"},
	"sig_deadeye": {"name": "Deadeye scope", "tag": "Mark", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Deadeye ability",
		"desc_mk2": "Grants the Deadeye ability"},
	"sig_quarantine_field": {"name": "Field projector", "tag": "Purge", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Quarantine Field ability",
		"desc_mk2": "Grants the Quarantine Field ability"},
	"sig_bring_down": {"name": "Demolition rig", "tag": "Close", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Bring Down ability",
		"desc_mk2": "Grants the Bring Down ability"},
	"sig_flashover": {"name": "Flashover igniter", "tag": "Burn", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Flashover ability",
		"desc_mk2": "Grants the Flashover ability"},
	"sig_vent": {"name": "Vent valve", "tag": "Strain", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Vent ability",
		"desc_mk2": "Grants the Vent ability"},
	"sig_death_sweep": {"name": "Sweep blade", "tag": "Close", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Death Sweep ability",
		"desc_mk2": "Grants the Death Sweep ability"},
	"sig_provoke": {"name": "Provoke horn", "tag": "Guard", "slot": "utility", "rarity": "rare",
		"desc": "Grants the Provoke ability",
		"desc_mk2": "Grants the Provoke ability"},
}

## Combo items: need both tags at 2+ on the soldier, count for both, start at Mk II, never sold.
const PROTOTYPES := {
	"spotter_flare": {"name": "Spotter flare", "tags": ["Burn", "Mark"], "slot": "utility",
		"desc": "Marked enemies take double damage from fire"},
	"scorched_earth": {"name": "Scorched earth", "tags": ["Burn", "Purge"], "slot": "ammo",
		"desc": "Your fire doesn't hurt allies and burns 10 Infection off any ally standing in it"},
	"killbox": {"name": "Killbox", "tags": ["Mark", "Overwatch"], "slot": "weapon",
		"desc": "Overwatch never misses a Marked enemy"},
	"crossfire": {"name": "Crossfire", "tags": ["Suppress", "Overwatch"], "slot": "weapon",
		"desc": "At the end of the enemy turn, your overwatch fires at a Suppressed enemy that didn't move"},
	"breach_and_clear": {"name": "Breach and clear", "tags": ["Close", "Suppress"], "slot": "ammo",
		"desc": "Enemies you Suppress within 3 tiles lose their cover bonus"},
	"hold_position": {"name": "Hold position", "tags": ["Guard", "Suppress"], "slot": "offhand",
		"desc": "Suppress costs 1 action instead of ending your turn"},
	"feral_grip": {"name": "Feral grip", "tags": ["Close", "Strain"], "slot": "body",
		"desc": "Every hit within 3 tiles, mutation attacks included, heals you 1 HP"},
	"bloodletting": {"name": "Bloodletting", "tags": ["Strain", "Purge"], "slot": "utility",
		"desc": "Once a turn, when you purge an ally you take the Infection yourself and gain 1 action"},
	"quarantine_field": {"name": "Quarantine field", "tags": ["Guard", "Purge"], "slot": "utility",
		"desc": "Adjacent allies gain no Infection while you're hunkered"},
	"firestarter": {"name": "Firestarter", "tags": ["Burn", "Close"], "slot": "weapon",
		"desc": "Hits within 3 tiles set the target Burning"},
	"pinpoint": {"name": "Pinpoint", "tags": ["Mark", "Suppress"], "slot": "ammo",
		"desc": "Enemies you Suppress are also Marked until the end of the next turn"},
	"overlook": {"name": "Overlook", "tags": ["Overwatch", "Guard"], "slot": "head",
		"desc": "While you're on overwatch, adjacent allies get +10 defense"},
	"cauterizer": {"name": "Cauterizer", "tags": ["Burn", "Guard"], "slot": "body",
		"desc": "Fire tiles don't hurt you, and you get +10 defense while standing in fire"},
}

## Pocket consumables, used up. Charges stack per pocket.
const CONSUMABLES := {
	"medkit": {"name": "Medkit", "price": 12, "desc": "Heal 4 HP and clear Burning, Suppressed and stun. At full HP it gives a one-hit shield instead."},
	"flashbang": {"name": "Flashbang", "price": 15, "desc": "Stuns enemies in radius 1: they lose their next turn"},
	"smoke_grenade": {"name": "Smoke grenade", "price": 15, "desc": "A 3x3 smoke cloud for 2 turns: +20 defense inside, and you can't be spotted in it"},
	"recon_drone": {"name": "Recon drone", "price": 15, "desc": "Reveals a 6-tile radius for the fight and Marks every enemy in it."},
	"suppressant_shot": {"name": "Suppressant shot", "price": 20, "desc": "-15 Infection, and blocks the next 3 Infection you would gain."},
	"frag_grenade": {"name": "Frag grenade", "price": 20, "desc": "3 damage in radius 1. Strips half cover, cracks walls and roofs, brings down scaffolds"},
	"demo_charge": {"name": "Demo charge", "price": 20, "desc": "Place on a tile or wall next to you: blows a doorway through a wall, 3 damage around it"},
	"antiviral_dose": {"name": "Antiviral dose", "price": 28, "desc": "-35 Infection from an ally within reach. The Infection removed bursts as spores, hurting enemies near them."},
	"breather_mask": {"name": "Breather mask", "price": 25, "desc": "You and allies within 2 tiles gain no Infection for 2 turns"},
	"stim": {"name": "Stim", "price": 25, "desc": "+1 action this turn, +5 Infection"},
	"containment_foam": {"name": "Containment foam", "price": 30, "desc": "Restrains a Lapsed or Turned soldier within 4 tiles for 2 turns without killing them"},
}
const CONSUMABLE_CHARGES := 2  # a consumable reward card gives 2 charges
## Every soldier starts a run (or joins as a recruit) with one charge of a class consumable.
## A class not listed here gets a random one from STARTER_FALLBACK.
const STARTER_CONSUMABLES := {
	"trooper": "frag_grenade", "marksman": "smoke_grenade", "medic": "medkit",
	"breacher": "demo_charge", "hazmat": "suppressant_shot", "vector": "stim",
}
const STARTER_FALLBACK: Array[String] = ["medkit", "flashbang", "smoke_grenade"]
const STARTER_CHARGES := 1

## Squad-wide passives voted on after each act boss (stored in run.modifiers.doctrines).
const DOCTRINES := {
	"buddy_system": {"name": "Buddy system", "desc": "+10 aim while next to a teammate"},
	"field_rations": {"name": "Field rations", "desc": "Heal 50% after fights instead of 35%"},
	"quartermaster": {"name": "Quartermaster", "desc": "Depot prices -15%"},
	"hazard_pay": {"name": "Hazard pay", "desc": "+10 Supplies per fight"},
	"spore_filters": {"name": "Spore filters", "desc": "-25% Infection from spore zones"},
	"steady_nerves": {"name": "Steady nerves", "desc": "Talking down a Lapse costs no action"},
	# Doctrine pack (Field Data unlock, see MetaUnlocks); effects live in RunRules.
	"scavengers": {"name": "Scavengers", "desc": "+1 Intel at the start of each act"},
	"supply_drop": {"name": "Supply drop", "desc": "+25 Supplies at the start of each act"},
	"triage_drills": {"name": "Triage drills", "desc": "Heal 2 more HP after every fight"},
	"serum_cache": {"name": "Serum cache", "desc": "+1 Serum sample per soldier after each boss"},
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


## The soldier slots an item of this slot type can sit in, in fill order.
static func slots_for(type: String) -> Array[String]:
	var out: Array[String] = []
	if type == "utility":
		out.append_array(["utility", "utility2"])
	else:
		out.append(type)
	return out


## The class signature ability a signature rig grants, or "".
static func signature_of(id: String) -> String:
	return id.trim_prefix("sig_") if id.begins_with("sig_") else ""


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


## Does this tag have a capstone built yet? (Burn, Mark, Overwatch and Guard so far.)
static func has_capstone(tag: String) -> bool:
	return TAG_INFO.get(tag, {}).has("capstone")


## Tags with a capstone, in TAGS order.
static func capstone_tags() -> Array[String]:
	var out: Array[String] = []
	for t in TAGS:
		if has_capstone(t):
			out.append(t)
	return out


static func tag_color(tag: String) -> Color:
	return TAG_INFO.get(tag, {}).get("color", Color.WHITE)
