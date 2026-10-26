extends RefCounted
## How each weapon (combat/weapons.gd) looks and sounds when it fires. View-only.
## Every gun has its own report, round and impact, so a shot reads without the HUD.
##
## "rounds": rounds per trigger pull (the last one carries the shot's outcome; earlier ones
##   hit too on a hit, or chew up cover on a miss), "gap": seconds between rounds,
## "rhythm": per-round multipliers on "gap", cycled (an LMG's uneven chug, a stutter),
## "pellets": >0 makes each round a spread of pellets, "spread": how wide (default 0.28),
## "flash" / "recoil" / "shake" / "kick": scale of the muzzle flash, weapon recoil, camera
##   shake and camera kick per round,
## "flash_style": "star" (default), "cone" (shotguns), "brake" (side blast of a muzzle brake),
##   "bio" (a glowing spore bloom), "quiet" (suppressed), "gas" (a pneumatic puff, no fire),
## "sound": per round, "tail": once, after the first round (the echo off the buildings),
## "mech": once after the last round (pump, bolt, belt, vent), "mech_delay" seconds later,
## "proj": what flies (view/fx.gd spawn_round): "tracer", "heavy", "pellet", "slug",
##   "flechette", "bio", "spore", "dart", "bolt" (an electric arc),
## "tracer_every": on bursts only every Nth round (and the last) is a bright tracer,
## "flight": scale on the rounds' flight time (slow bio globs, fast rifle rounds),
## "arc": how high a lobbed round climbs, as a share of the distance,
## "bullet": size of the round, "color": round tint (else amber squad / red hostile),
## "whiz": the round going past, "impact": how it lands ("spark", "heavy", "slug", "pellet",
##   "needle", "bio", "dart", "shock"),
## "casing": what ejects ("brass", "big", "shell", "link", "cell", or none; true = brass),
## "eject": "mech" holds the casing until the pump / bolt is worked.

const Palette := preload("res://view/palette.gd")

const SQUAD := Color(1.0, 0.78, 0.4)
const HOSTILE := Color(1.0, 0.42, 0.28)
const BIO := Color(0.62, 1.0, 0.45)
const NEEDLE := Color(0.78, 0.9, 1.0)
const DART := Color(0.7, 0.95, 1.0)
const SHOCK := Color(0.72, 0.85, 1.0)

const FEEL := {
	"rifle": {"rounds": 3, "gap": 0.075, "flash": 1.0, "recoil": 0.9, "shake": 0.3, "kick": 0.5,
		"sound": "rifle", "tail": "tail_rifle", "proj": "tracer", "bullet": 1.0, "casing": "brass"},
	"dmr": {"rounds": 1, "gap": 0.0, "flash": 1.7, "recoil": 1.7, "shake": 0.75, "kick": 1.4,
		"sound": "sniper", "tail": "tail_heavy", "mech": "bolt", "mech_delay": 0.5, "proj": "heavy", "bullet": 1.5,
		"flight": 0.75, "whiz": "whiz_heavy", "impact": "heavy", "casing": "brass", "eject": "mech", "smoke": true},
	"pdw": {"rounds": 5, "gap": 0.05, "rhythm": [1.0, 0.8, 1.2, 0.9], "flash": 0.7, "recoil": 0.45, "shake": 0.18,
		"kick": 0.3, "sound": "smg", "tail": "tail_rifle", "proj": "tracer", "bullet": 0.8, "casing": "brass"},
	"shotgun": {"rounds": 1, "gap": 0.0, "pellets": 9, "flash": 2.0, "flash_style": "cone", "recoil": 1.9, "shake": 0.95,
		"kick": 1.6, "sound": "shotgun", "tail": "tail_heavy", "mech": "pump", "mech_delay": 0.42, "proj": "pellet",
		"bullet": 0.6, "whiz": "whiz_pellets", "impact": "pellet", "casing": "shell", "eject": "mech", "smoke": true},
	"lmg": {"rounds": 6, "gap": 0.085, "rhythm": [1.0, 1.15, 0.9, 1.1, 0.95], "flash": 1.25, "recoil": 0.8, "shake": 0.4,
		"kick": 0.7, "sound": "lmg", "tail": "tail_heavy", "mech": "belt", "mech_delay": 0.12, "proj": "tracer",
		"tracer_every": 3, "bullet": 1.1, "casing": "link"},
	"carbine": {"rounds": 2, "gap": 0.09, "flash": 0.9, "flash_style": "bio", "recoil": 0.7, "shake": 0.28, "kick": 0.5,
		"sound": "carbine", "tail": "tail_rifle", "mech": "vent", "mech_delay": 0.25, "proj": "bio", "bullet": 1.0,
		"flight": 1.3, "whiz": "whiz_bio", "impact": "bio", "casing": "cell", "color": BIO},
	"sidearm": {"rounds": 1, "gap": 0.0, "flash": 0.55, "recoil": 0.5, "shake": 0.15, "kick": 0.25,
		"sound": "pistol", "tail": "tail_rifle", "proj": "tracer", "bullet": 0.75, "casing": "brass"},
	"revolver": {"rounds": 1, "gap": 0.0, "flash": 1.1, "recoil": 1.1, "shake": 0.45, "kick": 0.8,
		"sound": "revolver", "tail": "tail_heavy", "mech": "cylinder", "mech_delay": 0.35, "proj": "heavy", "bullet": 1.1,
		"impact": "heavy", "smoke": true},
	"spit": {"rounds": 1, "gap": 0.0, "flash": 0.0, "recoil": 0.6, "shake": 0.2, "kick": 0.0,
		"sound": "spit", "proj": "spore", "bullet": 1.6, "flight": 1.6, "arc": 0.18, "whiz": "whiz_bio", "impact": "bio",
		"color": Palette.TEAL},
}


## Alternate guns: their look's feel with these keys changed (null removes a key).
const VARIANTS := {
	"battle_rifle": {"rounds": 2, "gap": 0.11, "flash": 1.3, "recoil": 1.25, "shake": 0.45, "kick": 0.8,
		"sound": "battle_rifle", "tail": "tail_heavy", "proj": "heavy", "bullet": 1.2, "impact": "heavy"},
	"burst_carbine": {"rounds": 3, "gap": 0.055, "rhythm": [1.0, 0.9], "sound": "burst_carbine", "flash_style": null,
		"mech": null, "proj": "tracer", "flight": 0.9, "whiz": null, "impact": null, "casing": "brass", "color": null},
	"anti_materiel": {"flash": 2.3, "flash_style": "brake", "recoil": 2.4, "shake": 1.15, "kick": 2.0, "bullet": 1.9,
		"sound": "anti_materiel", "mech": "bolt_heavy", "mech_delay": 0.65, "flight": 0.6, "impact": "slug", "casing": "big"},
	"scout_carbine": {"rounds": 3, "gap": 0.07, "rhythm": null, "flash": 0.4, "flash_style": "quiet", "recoil": 0.4,
		"sound": "scout_carbine", "tail": null, "bullet": 0.65},
	"flechette_smg": {"rounds": 6, "gap": 0.04, "pellets": 3, "spread": 0.12, "bullet": 0.6, "recoil": 0.4,
		"sound": "flechette_smg", "proj": "flechette", "flight": 0.85, "whiz": "whiz_needle", "impact": "needle",
		"color": NEEDLE},
	"dart_rifle": {"sound": "dart_rifle", "tail": null, "mech": null, "flash": 0.6, "flash_style": "gas", "recoil": 0.8,
		"shake": 0.3, "kick": 0.6, "smoke": null, "proj": "dart", "bullet": 0.9, "flight": 1.7, "arc": 0.05,
		"whiz": "whiz_dart", "impact": "dart", "casing": null, "color": DART},
	"slug_gun": {"pellets": null, "sound": "slug_gun", "flash_style": "star", "proj": "slug", "bullet": 1.5,
		"flight": 0.9, "whiz": "whiz_heavy", "impact": "slug"},
	"auto_shotgun": {"rounds": 3, "gap": 0.16, "rhythm": [1.0, 0.85], "pellets": 6, "mech": null, "recoil": 1.4,
		"shake": 0.7, "sound": "auto_shotgun", "eject": null},
	"pump_shotgun": {"pellets": 8, "spread": 0.4, "sound": "pump_shotgun"},
	"heavy_mg": {"rounds": 7, "gap": 0.1, "rhythm": [1.0, 1.2, 0.9, 1.1], "flash": 1.6, "recoil": 1.1, "shake": 0.6,
		"kick": 0.9, "sound": "heavy_mg", "proj": "heavy", "tracer_every": 2, "bullet": 1.3, "impact": "heavy",
		"casing": "big"},
	"machine_pistol": {"rounds": 4, "gap": 0.045, "rhythm": [1.0, 0.8, 1.15], "recoil": 0.4, "sound": "machine_pistol",
		"bullet": 0.65, "flash_style": "quiet", "flash": 0.6},
	"bloom_pistol": {"flash": 0.8, "flash_style": "bio", "sound": "bloom_pistol", "mech": "vent", "mech_delay": 0.2,
		"proj": "bio", "bullet": 0.9, "flight": 1.25, "whiz": "whiz_bio", "impact": "bio", "casing": "cell",
		"color": Palette.TEAL},
	"hand_cannon": {"flash": 1.5, "recoil": 1.5, "shake": 0.7, "kick": 1.2, "sound": "hand_cannon",
		"proj": "heavy", "bullet": 1.4, "flight": 0.8, "whiz": "whiz_heavy", "impact": "slug", "casing": "big", "smoke": true},
	"stun_pistol": {"rounds": 2, "gap": 0.12, "sound": "stun_pistol", "flash": 0.7, "flash_style": "quiet",
		"proj": "bolt", "bullet": 0.9, "flight": 1.15, "whiz": "whiz_zap", "impact": "shock", "casing": null,
		"mech": "cylinder", "mech_delay": 0.3, "color": SHOCK},
	"longslide": {"flash": 0.75, "recoil": 0.6, "sound": "longslide", "tail": "tail_heavy", "proj": "heavy",
		"bullet": 0.9, "flight": 0.8, "whiz": "whiz_heavy"},
	"spore_rifle": {"rounds": 1, "flash": 1.1, "recoil": 1.0, "kick": 0.8, "sound": "spore_rifle", "proj": "spore",
		"bullet": 1.5, "flight": 1.6, "arc": 0.08, "color": Palette.TEAL},
}


## The reload sound of each gun, by mechanism: box or stick mag, shell tube, cylinder, belt box,
## bolt action, pneumatic canister. Only the alien guns (bio-carbine, spore rifle, bloom pistol) use the energy cell. Anything unlisted falls back to the rifle swap.
const RELOADS := {
	"rifle": "reload_rifle", "battle_rifle": "reload_rifle", "burst_carbine": "reload_rifle",
	"pdw": "reload_smg", "scout_carbine": "reload_smg", "flechette_smg": "reload_smg", "machine_pistol": "reload_smg",
	"dmr": "reload_bolt", "anti_materiel": "reload_bolt",
	"shotgun": "reload_shotgun", "slug_gun": "reload_shotgun", "pump_shotgun": "reload_shotgun", "auto_shotgun": "reload_rifle",
	"lmg": "reload_lmg", "heavy_mg": "reload_lmg",
	"carbine": "reload_cell", "spore_rifle": "reload_cell", "bloom_pistol": "reload_cell", "stun_pistol": "reload_pistol",
	"dart_rifle": "reload_dart",
	"sidearm": "reload_pistol", "longslide": "reload_pistol",
	"revolver": "reload_revolver", "hand_cannon": "reload_revolver",
}


static func reload_sound(weapon_id: String) -> String:
	return RELOADS.get(weapon_id, "reload_rifle")


## What a round sounds like landing in a body of this kind: plate, bile bag, a man, or meat.
static func body_impact(kind: String, is_squad: bool) -> String:
	if is_squad:
		return "impact_armor"
	if kind in ["carapace", "brute", "burrower", "brood_mother", "lurker", "leaper", "stalker"]:
		return "impact_chitin"
	if kind in ["bloater", "spitter", "broodling", "drifter", "weaver"]:
		return "impact_ichor"
	if kind in ["fallen", "sharpshooter", "colonel_hale", "sapper"]:
		return "impact_human"
	return "impact_flesh"


static func for_kind(kind: String) -> Dictionary:
	return for_weapon(Weapons.id_for(kind))


## Feel for a weapon id; alternates build theirs from their look's.
static func for_weapon(id: String) -> Dictionary:
	if FEEL.has(id):
		return FEEL[id]
	var base: Dictionary = FEEL.get(Weapons.look_of(id), FEEL.rifle).duplicate()
	var v: Dictionary = VARIANTS.get(id, {})
	for k in v:
		if v[k] == null:
			base.erase(k)
		else:
			base[k] = v[k]
	return base


## Tracer / round colour for a shooter: amber for the squad, red for hostile guns,
## teal for spit and Turned soldiers.
static func color(feel: Dictionary, is_squad: bool, turned: bool) -> Color:
	if feel.has("color"):
		return feel.color
	if turned:
		return Palette.TEAL
	return SQUAD if is_squad else HOSTILE


## What a gun ejects per round: "" for nothing ("casing": true in older rows means brass).
static func casing_of(feel: Dictionary) -> String:
	var c: Variant = feel.get("casing", "")
	if c is bool:
		return "brass" if c else ""
	return str(c)


## Seconds from the first round to round `i`, with the burst's rhythm applied.
static func round_offset(feel: Dictionary, i: int, gap: float) -> float:
	var rhythm: Array = feel.get("rhythm", [])
	var at := 0.0
	for k in i:
		at += gap * (float(rhythm[k % rhythm.size()]) if not rhythm.is_empty() else 1.0)
	return at


## Projectile style of round `i` of `n`: bursts with "tracer_every" fly plain ball rounds
## between their tracers (the last round, which carries the outcome, is always a tracer).
static func proj_of(feel: Dictionary, i: int, n: int) -> String:
	var every := int(feel.get("tracer_every", 0))
	if every > 1 and i != n - 1 and i % every != 0:
		return "ball"
	return str(feel.get("proj", "tracer"))
