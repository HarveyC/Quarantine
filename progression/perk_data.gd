class_name PerkData
extends RefCounted
## Class passives and perk pools. OWNER: progression workstream.
## Effects are read by Kit (in-mission hooks) and ClassAbilities; this file is only data.
##
## Perk: {"class", "name", "tag" ("" = untagged), "rare": bool, "desc", optional stat
## grants "max_hp" / "defense" / "mobility" (applied when the soldier spawns), optional
## "ability" (a new ability id granted by the perk).

## One passive per class, always on.
const PASSIVES := {
	"trooper": {"id": "shoulder_to_shoulder", "name": "Shoulder to Shoulder",
		"desc": "Allies adjacent to you get +10 defense."},
	"marksman": {"id": "steady_aim", "name": "Steady Aim",
		"desc": "+10 aim on shots taken without moving this turn."},
	"medic": {"id": "containment", "name": "Containment",
		"desc": "Allies adjacent to you at the start of the team phase lose 5 Infection."},
	"breacher": {"id": "point_blank", "name": "Point Blank",
		"desc": "+1 damage on shots within 3 tiles."},
	"hazmat": {"id": "sealed_suit", "name": "Sealed Suit",
		"desc": "You gain half Infection from every source, but mutations cost 5 more to use."},
	"vector": {"id": "willing_host", "name": "Willing Host",
		"desc": "Start every fight at 25 Infection or more. Mutations cost 5 less to use (minimum 5)."},
}

const PERKS := {
	# Trooper: Guard and Suppress
	"lockdown": {"class": "trooper", "name": "Lockdown", "tag": "Suppress", "rare": false,
		"desc": "Suppress costs 1 action instead of ending your turn."},
	"pinned_down": {"class": "trooper", "name": "Pinned Down", "tag": "Suppress", "rare": false,
		"desc": "Enemies you Suppress also lose 2 mobility."},
	"steadfast": {"class": "trooper", "name": "Steadfast", "tag": "Guard", "rare": false,
		"desc": "Shoulder to Shoulder gives +20 defense instead of +10."},
	"return_fire": {"class": "trooper", "name": "Return Fire", "tag": "Overwatch", "rare": false,
		"desc": "Once per enemy phase, shoot back at the first enemy that shoots you."},
	"hold_the_line": {"class": "trooper", "name": "Hold the Line", "tag": "Guard", "rare": false, "max_hp": 2,
		"desc": "+2 max HP, and Hunker gives +10 more defense."},
	"last_stand": {"class": "trooper", "name": "Last Stand", "tag": "Guard", "rare": true,
		"desc": "The first time you would die in a fight, drop to 1 HP instead."},
	"squad_leader": {"class": "trooper", "name": "Squad Leader", "tag": "Guard", "rare": true, "ability": "squad_order",
		"desc": "Once per fight, 1 action: an adjacent ally gains +1 action this turn."},
	"battle_hardened": {"class": "trooper", "name": "Battle Hardened", "tag": "Guard", "rare": false, "max_hp": 1,
		"desc": "+1 max HP, and the first hit you take each fight deals 1 less damage."},
	"suppressive_volley": {"class": "trooper", "name": "Suppressive Volley", "tag": "Suppress", "rare": true,
		"desc": "Enemies you Suppress also take 1 damage."},
	# Marksman: Mark and Overwatch
	"long_watch": {"class": "marksman", "name": "Long Watch", "tag": "Overwatch", "rare": false,
		"desc": "Overwatch shots ignore the -15 reaction penalty."},
	"expose": {"class": "marksman", "name": "Expose", "tag": "Mark", "rare": false,
		"desc": "Allies treat a Tagged enemy's cover as one step lower."},
	"hunters_mark": {"class": "marksman", "name": "Hunter's Mark", "tag": "Mark", "rare": false,
		"desc": "Tag lasts one extra turn and its cooldown drops to 1."},
	"deadeye": {"class": "marksman", "name": "Deadeye", "tag": "Mark", "rare": false,
		"desc": "+20 crit chance against Tagged enemies."},
	"relocate": {"class": "marksman", "name": "Relocate", "tag": "Overwatch", "rare": false, "mobility": 1,
		"desc": "+1 mobility, and Steady Aim still applies after moving up to 2 tiles."},
	"double_tap": {"class": "marksman", "name": "Double Tap", "tag": "Mark", "rare": true,
		"desc": "Once per turn, a kill with your first action refunds it."},
	"kill_zone": {"class": "marksman", "name": "Kill Zone", "tag": "Overwatch", "rare": true,
		"desc": "Overwatch can fire at up to 2 enemies."},
	"high_perch": {"class": "marksman", "name": "High Perch", "tag": "Overwatch", "rare": false,
		"desc": "+10 aim when you shoot from higher ground than your target."},
	"headhunter": {"class": "marksman", "name": "Headhunter", "tag": "Mark", "rare": true,
		"desc": "+1 damage against Tagged enemies."},
	# Medic: Purge and Guard
	"long_reach": {"class": "medic", "name": "Long Reach", "tag": "Purge", "rare": false,
		"desc": "Stim works on allies up to 3 tiles away."},
	"field_kit": {"class": "medic", "name": "Field Kit", "tag": "Purge", "rare": false,
		"desc": "Stim cooldown drops to 1."},
	"transfusion": {"class": "medic", "name": "Transfusion", "tag": "Purge", "rare": false,
		"desc": "Stim heals +1 HP for every 5 Infection it removes."},
	"purge": {"class": "medic", "name": "Purge", "tag": "Purge", "rare": false, "ability": "purge",
		"desc": "New ability: remove 30 Infection from an adjacent ally. Ends turn, cooldown 3."},
	"calm_voice": {"class": "medic", "name": "Calm Voice", "tag": "Purge", "rare": false,
		"desc": "Talking down a Lapsed ally works from 3 tiles and also removes 10 Infection."},
	"triage_cover": {"class": "medic", "name": "Triage Cover", "tag": "Guard", "rare": false,
		"desc": "Stim also gives the target +20 defense until the next team phase."},
	"overdrive": {"class": "medic", "name": "Overdrive", "tag": "Strain", "rare": true,
		"desc": "Stim also gives the target +1 action this turn, but adds 10 Infection."},
	"steady_hands": {"class": "medic", "name": "Steady Hands", "tag": "Guard", "rare": false,
		"desc": "After you Stim an ally, you get +15 defense until the next team phase."},
	"field_surgeon": {"class": "medic", "name": "Field Surgeon", "tag": "Purge", "rare": true,
		"desc": "Stim also heals 2 HP."},
	# Breacher: Close and Suppress
	"kick_in": {"class": "breacher", "name": "Kick In", "tag": "Close", "rare": false,
		"desc": "After Breach you keep 1 move action instead of ending your turn."},
	"long_fuse": {"class": "breacher", "name": "Long Fuse", "tag": "Close", "rare": false,
		"desc": "Breach range becomes 3."},
	"frag_charge": {"class": "breacher", "name": "Frag Charge", "tag": "Close", "rare": false,
		"desc": "Breach also deals 2 damage to every unit adjacent to the target."},
	"run_and_gun": {"class": "breacher", "name": "Run and Gun", "tag": "Close", "rare": false,
		"desc": "Once per fight, after moving twice in a turn you can still shoot."},
	"brawler": {"class": "breacher", "name": "Brawler", "tag": "Close", "rare": false,
		"desc": "Enemies that hit you in melee take 2 damage."},
	"shrapnel": {"class": "breacher", "name": "Shrapnel", "tag": "Suppress", "rare": true,
		"desc": "Enemies that survive Breach are Suppressed."},
	"juggernaut": {"class": "breacher", "name": "Juggernaut", "tag": "Guard", "rare": true, "max_hp": 3,
		"desc": "+3 max HP, and +10 defense on turns you shoot a flanked enemy."},
	"door_kicker": {"class": "breacher", "name": "Door Kicker", "tag": "Close", "rare": false, "mobility": 1,
		"desc": "+1 mobility."},
	"adrenaline": {"class": "breacher", "name": "Adrenaline", "tag": "Close", "rare": true,
		"desc": "Once per turn, a kill within 3 tiles heals you 2 HP."},
	# Hazmat: Burn and Purge
	"clean_burn": {"class": "hazmat", "name": "Clean Burn", "tag": "Burn", "rare": false,
		"desc": "Incinerate and its fire never hurt allies."},
	"napalm": {"class": "hazmat", "name": "Napalm", "tag": "Burn", "rare": false,
		"desc": "Fire lasts 2 turns."},
	"wide_nozzle": {"class": "hazmat", "name": "Wide Nozzle", "tag": "Burn", "rare": false,
		"desc": "The Incinerate cone reaches 4 tiles."},
	"firewall": {"class": "hazmat", "name": "Firewall", "tag": "Burn", "rare": false,
		"desc": "Incinerate becomes a 4-tile line instead of a cone."},
	"decon_shower": {"class": "hazmat", "name": "Decon Shower", "tag": "Purge", "rare": false, "ability": "decon",
		"desc": "New ability, 1 action: an adjacent ally loses 10 Infection and gains none until the next team phase."},
	"heavy_plating": {"class": "hazmat", "name": "Heavy Plating", "tag": "", "rare": false, "max_hp": 2, "defense": 10,
		"desc": "+2 max HP and +10 defense."},
	"backdraft": {"class": "hazmat", "name": "Backdraft", "tag": "Burn", "rare": true,
		"desc": "Incinerate cooldown drops to 1."},
	"scorcher": {"class": "hazmat", "name": "Scorcher", "tag": "Burn", "rare": false,
		"desc": "+1 damage against Burning enemies."},
	"decon_protocol": {"class": "hazmat", "name": "Decon Protocol", "tag": "Purge", "rare": true,
		"desc": "Allies adjacent to you at the start of the team phase lose 5 Infection."},
	# Vector: Strain and Purge
	"deep_siphon": {"class": "vector", "name": "Deep Siphon", "tag": "Purge", "rare": false,
		"desc": "Siphon moves up to 25 Infection and reaches 3 tiles."},
	"symbiote": {"class": "vector", "name": "Symbiote", "tag": "Strain", "rare": false,
		"desc": "At Mutating or above, a further +1 mobility and +10 aim."},
	"iron_will": {"class": "vector", "name": "Iron Will", "tag": "Purge", "rare": false,
		"desc": "Your Lapse chance is halved."},
	"thick_blood": {"class": "vector", "name": "Thick Blood", "tag": "", "rare": false, "max_hp": 2,
		"desc": "+2 max HP."},
	"feed": {"class": "vector", "name": "Feed", "tag": "Strain", "rare": false,
		"desc": "Kills heal you for 2."},
	"brink": {"class": "vector", "name": "Brink", "tag": "Strain", "rare": true,
		"desc": "Once per fight, when you would Turn, drop to 74 Infection and take 3 damage instead."},
	"apex": {"class": "vector", "name": "Apex", "tag": "Strain", "rare": true,
		"desc": "Mutations cost a further 5 less to use (minimum 5)."},
	"carrier_wave": {"class": "vector", "name": "Carrier Wave", "tag": "Strain", "rare": false,
		"desc": "+1 damage while you're Mutating or higher."},
	"spore_veil": {"class": "vector", "name": "Spore Veil", "tag": "Strain", "rare": true,
		"desc": "+10 defense while you're Exposed or higher."},
}


## Perk ids in a class's pool, in table order.
static func pool(kind: String) -> Array[String]:
	var out: Array[String] = []
	for id in PERKS:
		if PERKS[id]["class"] == kind:
			out.append(id)
	return out


static func passive(kind: String) -> Dictionary:
	return PASSIVES.get(kind, {})
