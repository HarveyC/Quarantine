class_name PerkBrief
extends RefCounted
## The rank-up card face for every perk and mutation: an icon, one short line, and the numbers as
## stat chips ([value, label]). The full sentence (PerkData / MutationData "desc") stays the
## source of truth for the rules and is shown on hover. Mutations add a short drawback line.
## tests/test_progression.gd checks every perk and mutation has an entry here.

const PERKS := {
	# Trooper
	"lockdown": ["suppress", "Suppress no longer ends your turn", [["1", "action"]]],
	"pinned_down": ["suppress", "Suppressed enemies are slowed", [["-2", "enemy move"]]],
	"steadfast": ["trooper", "Shoulder to Shoulder hits harder", [["+20", "ally def"]]],
	"return_fire": ["overwatch", "Shoot back at the first shooter", [["1", "per enemy phase"]]],
	"hold_the_line": ["hunker", "Tougher, and Hunker holds firmer", [["+2", "max HP"], ["+10", "hunker def"]]],
	"last_stand": ["health", "Survive one killing blow", [["1", "HP left"], ["1", "per fight"]]],
	"squad_leader": ["squad", "Give an adjacent ally an action", [["+1", "ally action"], ["1", "per fight"]]],
	"battle_hardened": ["armor", "Tougher, and shrugs off the first hit", [["+1", "max HP"], ["-1", "first hit"]]],
	"suppressive_volley": ["suppress", "Suppress also wounds", [["1", "damage"]]],
	# Marksman
	"long_watch": ["overwatch", "Overwatch shots lose their penalty", [["+15", "reaction aim"]]],
	"expose": ["tag", "Tagged enemies lose cover for the squad", [["-1", "cover step"]]],
	"hunters_mark": ["tag", "Tag lasts longer and comes back faster", [["+1", "turn"], ["1", "cooldown"]]],
	"deadeye": ["tag", "Crits on Tagged enemies", [["+20", "crit"]]],
	"relocate": ["move", "Steady Aim survives a short move", [["+1", "move"], ["2", "tiles"]]],
	"double_tap": ["shoot", "A first-action kill refunds it", [["1", "per turn"]]],
	"kill_zone": ["overwatch", "Overwatch fires twice", [["2", "targets"]]],
	"high_perch": ["shoot", "Better aim from high ground", [["+10", "aim"]]],
	"headhunter": ["tag", "Hit Tagged enemies harder", [["+1", "damage"]]],
	# Medic
	"long_reach": ["medic", "Stim allies from range", [["3", "tiles"]]],
	"field_kit": ["clock", "Stim comes back faster", [["1", "cooldown"]]],
	"transfusion": ["health", "Stim heals as it cleans", [["+1", "HP per 5 Inf"]]],
	"purge": ["purge", "New ability: purge an adjacent ally", [["-30", "Infection"], ["3", "cooldown"]]],
	"calm_voice": ["vote", "Talk down a Lapse from range", [["3", "tiles"], ["-10", "Infection"]]],
	"triage_cover": ["cover_half", "Stim also shields the target", [["+20", "defense"]]],
	"overdrive": ["ability", "Stim also hands out an action", [["+1", "action"], ["+10", "Infection"]]],
	"steady_hands": ["guard", "Defend yourself after a Stim", [["+15", "defense"]]],
	"field_surgeon": ["health", "Stim also heals", [["+2", "HP"]]],
	# Breacher
	"kick_in": ["move", "Breach no longer ends your turn", [["1", "move left"]]],
	"long_fuse": ["breach", "Breach from further away", [["3", "range"]]],
	"frag_charge": ["grenade", "Breach hurts everything around it", [["2", "splash damage"]]],
	"run_and_gun": ["shoot", "Shoot after a double move", [["1", "per fight"]]],
	"brawler": ["attack", "Melee attackers get hurt", [["2", "damage back"]]],
	"shrapnel": ["suppress", "Breach survivors are Suppressed", []],
	"juggernaut": ["armor", "Tougher, and braver on flanks", [["+3", "max HP"], ["+10", "defense"]]],
	"door_kicker": ["move", "Faster on your feet", [["+1", "move"]]],
	"adrenaline": ["health", "Close kills heal you", [["+2", "HP"], ["3", "tiles"]]],
	# Hazmat
	"clean_burn": ["incinerate", "Your fire never hurts allies", []],
	"napalm": ["incinerate", "Fire burns longer", [["2", "turns"]]],
	"wide_nozzle": ["incinerate", "A longer Incinerate cone", [["4", "tiles"]]],
	"firewall": ["incinerate", "Incinerate becomes a line", [["4", "tile line"]]],
	"decon_shower": ["purge", "New ability: decon an adjacent ally", [["-10", "Infection"], ["1", "action"]]],
	"heavy_plating": ["armor", "Heavier armour", [["+2", "max HP"], ["+10", "defense"]]],
	"backdraft": ["clock", "Incinerate comes back faster", [["1", "cooldown"]]],
	"scorcher": ["incinerate", "Hit Burning enemies harder", [["+1", "damage"]]],
	"decon_protocol": ["purge", "Clean nearby allies every turn", [["-5", "ally Infection"]]],
	# Vector
	"deep_siphon": ["siphon", "A stronger, longer Siphon", [["25", "Infection"], ["3", "tiles"]]],
	"symbiote": ["mutation", "Stronger while Mutating", [["+1", "move"], ["+10", "aim"]]],
	"iron_will": ["lock", "Resist Lapses", [["x0.5", "Lapse chance"]]],
	"thick_blood": ["health", "Tougher", [["+2", "max HP"]]],
	"feed": ["health", "Kills heal you", [["+2", "HP"]]],
	"brink": ["turned", "Cheat Turning once", [["74", "Infection"], ["3", "damage"]]],
	"apex": ["mutation", "Mutations get cheaper", [["-5", "cost"]]],
	"carrier_wave": ["attack", "Hit harder while Mutating", [["+1", "damage"]]],
	"spore_veil": ["bloom", "Spores shield you", [["+10", "defense"]]],
	# Reaper
	"bleed_out": ["wound", "Melee hits make the target bleed", [["1", "per turn"], ["2", "turns"]]],
	"harvest": ["health", "Melee kills heal you", [["+2", "HP"]]],
	"long_stride": ["lunge", "A longer Lunge", [["6", "tiles"]]],
	"riposte": ["attack", "Strike back at the first claw", [["1", "per enemy phase"]]],
	"hamstring": ["wound", "Melee hits slow the target", [["-2", "enemy move"]]],
	"red_mist": ["attack", "Never miss in melee at Critical", [["100%", "melee hit"]]],
	"cleave": ["lunge", "Lunge hits everything around you", []],
	# Warden
	"vigilant": ["guard", "Guard bashes two enemies", [["2", "targets"]]],
	"sterilize": ["purge", "Bashes clean you", [["-5", "Infection"]]],
	"intimidate": ["suppress", "Bash also Suppresses its neighbours", []],
	"shield_charge": ["shield_charge", "New ability: charge and Bash", [["3", "tiles"], ["3", "cooldown"]]],
	"tower_shield": ["warden", "Bulwark gives full cover", []],
	"last_wall": ["health", "Survive one killing blow", [["1", "HP left"], ["1", "per fight"]]],
	"unbreakable": ["armor", "Tougher, and blunts close hits", [["+3", "max HP"], ["-1", "close hits"]]],
}

## Mutations: [icon, short, chips, drawback].
const MUTATIONS := {
	"spore_sense": ["reveal", "See infected enemies through walls", [["6", "tiles"]], "Spore zones infect you twice as fast"],
	"adrenal_surge": ["ability", "A third action this turn", [["+1", "action"]], "Only 1 action next turn"],
	"barbed_hide": ["attack", "Melee attackers get hurt", [["2", "damage back"]], "Infects allies next to you"],
	"hollow_bones": ["move", "Move further", [["+2", "move"]], "+1 damage from every hit"],
	"lure_scent": ["overwatch", "Draw enemies into overwatch", [["+15", "ally aim"], ["6", "tiles"]], "Enemies go for you, no Hunker"],
	"clotting_blood": ["health", "Heal every team phase", [["+1", "HP"]], "Medic heals are halved"],
	"chitin_plates": ["armor", "Armour plates blunt every hit", [["-2", "damage taken"]], "-1 move, no Hunker"],
	"leech_bite": ["attack", "Bite and heal for the damage", [["1", "action"]], "More Infection from infected prey"],
	"acid_spit": ["suppress", "Spit through cover and Suppress", [["3", "damage"], ["5", "tiles"]], "Infects allies near the target"],
	"second_heart": ["health", "Stay up at 1 HP once", [["1", "per fight"]], "+15 Infection when it triggers"],
	"rally_musk": ["squad", "Nearby allies move and aim better", [["+1", "move"], ["+10", "aim"]], "Each of them gains 3 Infection"],
	"hive_hush": ["concealed", "Dormant infected can't spot you far", [["4", "tiles"]], "Purge on you is half as strong"],
	"rampage": ["lunge", "Run and claw everything you pass", [["1", "action"]], "Roll for a Lapse afterwards"],
	"regenerator": ["health", "Heal every team phase", [["+3", "HP"]], "No Medic heals, +2 Infection a turn"],
	"hollow_voice": ["stun", "Turn an infected enemy on its pack", [["1", "action"]], "Your Lapse chance doubles"],
	"bloom": ["bloom", "Spores burst when you're hit", [["2", "splash damage"]], "Infects adjacent allies too"],
	"overgrowth": ["cover_half", "Grow fungal walls", [["3x3", "patch"], ["2", "turns"]], "The patch is a spore zone"],
	"martyr_strain": ["purge", "Cleanse the squad when you fall", [["-20", "squad Infection"]], "Nobody can talk you down"],
	"shared_blood": ["guard", "Split damage with a partner", [], "If one Lapses, both roll"],
	"twin_sight": ["overwatch", "Share overwatch sight with a partner", [], "Lose an action if far apart"],
	"mirror_graft": ["mutation", "Your partner copies your mutations free", [], "Both pay the Infection"],
	"host_body": ["purge", "Take an ally's Infection for them", [["2", "tiles"], ["1", "per turn"]], "All of it lands on you"],
	"spore_burst": ["bloom", "A spore cloud that eats enemies", [["2", "damage a turn"], ["2", "radius"]], "Allies inside gain Infection"],
	"hive_link": ["siphon", "Lend an ally your Exposed mutation", [["1", "per fight"]], "Your Lapse costs them an action"],
	"flies": ["tag", "Marked enemy takes more from every hit", [["+1", "damage"]], "Flies move on when it dies"],
	"ride_the_wave": ["turned", "Hold off Turning at 100", [["2", "team phases"]], "Turn if the squad fails"],
	"patient_zero": ["mutation", "Actives cost no Infection", [["0", "cost"]], "Lapse roll every enemy phase"],
}


## {"icon", "short", "chips"} for a perk, falling back to its tag's icon and full sentence.
static func perk(id: String) -> Dictionary:
	var b: Array = PERKS.get(id, [])
	if b.is_empty():
		return {"icon": "perk", "short": str(PerkData.PERKS.get(id, {}).get("desc", "")), "chips": []}
	return {"icon": b[0], "short": b[1], "chips": b[2]}


## {"icon", "short", "chips", "drawback"} for a mutation.
static func mutation(id: String) -> Dictionary:
	var b: Array = MUTATIONS.get(id, [])
	if b.is_empty():
		var m := MutationData.get_def(id)
		return {"icon": "mutation", "short": str(m.get("desc", "")), "chips": [], "drawback": str(m.get("drawback", ""))}
	return {"icon": b[0], "short": b[1], "chips": b[2], "drawback": b[3]}
