class_name Glossary
extends RefCounted
## Game terms for the hover cards (ui/tips/). One entry per term, kept visual: a one-line
## summary, a small diagram ("art", drawn by ui/tips/tip_art.gd), up to three big numbers
## ("stats") and, for the Shift view, a few short lines ("more") and related terms ("see").
## Numbers come from the rules constants so the cards never drift from the game.
##
## Entry fields:
##   name     display name
##   kind     small caps label: status, mechanic, meter, resource, gear tag, ...
##   icon     Icons id for the header
##   tone     "teal" (Infection only), "amber", "danger", "hp", "text" or a Color
##   line     one short sentence; {key} or {key|shown text} links another term
##   art      TipArt diagram kind, or ""
##   stats    [[value, label], ...] shown as big numbers
##   more     extra lines for the Shift view (links allowed)
##   see      related term keys, shown as hoverable chips in the Shift view
##   aliases  other spellings found in UI text ("Half cover", "Flanked", ...); linked anywhere
##   labels   exact labels that mean this term (a breakdown row "Aim"), never linked in prose
##   scan     false keeps the name out of text linking (the gear tags: "Close", "Guard", ...)

const Styles := preload("res://ui/styles.gd")

static var _terms := {}
static var _regex: RegEx
static var _lookup := {}   # lower-case name or alias -> key (linked in text)
static var _labels := {}   # lower-case exact labels -> key (find() only)


static func all() -> Dictionary:
	if _terms.is_empty():
		_terms = _build()
		_lookup.clear()
		_labels.clear()
		for k in _terms:
			var e: Dictionary = _terms[k]
			var names: Array = e.get("aliases", []).duplicate()
			if e.get("scan", true):
				names.push_front(e.name)
			else:
				_labels[str(e.name).to_lower()] = k
			for n in names:
				if not _lookup.has(str(n).to_lower()):
					_lookup[str(n).to_lower()] = k
			for n in e.get("labels", []):
				_labels[str(n).to_lower()] = k
	return _terms


static func has(key: String) -> bool:
	return all().has(key)


static func entry(key: String) -> Dictionary:
	return all().get(key, {})


## The key whose name or alias is exactly `text` (any case), else "".
static func find(text: String) -> String:
	all()
	var t := text.strip_edges().to_lower()
	# "Half cover (+hunker)" style labels: also try the part before a bracket or colon.
	var tries := [t]
	for sep in [" (", ":"]:
		var i := t.find(sep)
		if i > 0:
			tries.append(t.substr(0, i))
	for x in tries:
		if _labels.has(x):
			return _labels[x]
		if _lookup.has(x):
			return _lookup[x]
	return ""


## Keys of every term named in `text`, in order of first appearance, no repeats.
static func scan(text: String) -> Array[String]:
	var out: Array[String] = []
	for m in _matches(_strip_links(text)):
		if not out.has(m[2]):
			out.append(m[2])
	for k in _links(text):
		if not out.has(k):
			out.append(k)
	return out


## `text` as BBCode for a RichTextLabel: {key|shown} links and any glossary name or alias in
## the plain text become [url=key] links coloured by the term's tone.
static func bbcode(text: String, skip: Array = []) -> String:
	var seen: Array = skip.duplicate()
	var out := ""
	var rx := RegEx.create_from_string("\\{([a-z0-9_]+)(?:\\|([^}]*))?\\}")
	var at := 0
	for m in rx.search_all(text):
		out += _auto_links(text.substr(at, m.get_start() - at), seen)
		var key := m.get_string(1)
		var shown := m.get_string(2) if m.get_string(2) != "" else str(entry(key).get("name", key))
		out += _link(key, shown) if has(key) and not seen.has(key) else _esc(shown)
		seen.append(key)
		at = m.get_end()
	return out + _auto_links(text.substr(at), seen)


## `text` with link markup reduced to the words shown.
static func plain(text: String) -> String:
	var rx := RegEx.create_from_string("\\{([a-z0-9_]+)(?:\\|([^}]*))?\\}")
	var out := text
	for m in rx.search_all(text):
		var shown := m.get_string(2) if m.get_string(2) != "" else str(entry(m.get_string(1)).get("name", m.get_string(1)))
		out = out.replace(m.get_string(0), shown)
	return out


## The term's tone as a colour (read at call time so a restyled palette carries through).
static func tone(key_or_tone: Variant) -> Color:
	var t: Variant = key_or_tone
	if t is String and has(t):
		t = entry(t).get("tone", "amber")
	if t is Color:
		return t
	match str(t):
		"teal": return Styles.TEAL
		"danger": return Styles.DANGER_TEXT
		"hp": return Styles.HP
		"text": return Styles.TEXT
		"dim": return Styles.DIM
	return Styles.AMBER


# --- internals -----------------------------------------------------------------------------

static func _link(key: String, shown: String) -> String:
	return "[url=%s][color=#%s]%s[/color][/url]" % [key, tone(key).to_html(false), _esc(shown)]


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


## Links each term's first mention only; `seen` collects keys already linked.
static func _auto_links(s: String, seen: Array) -> String:
	var out := ""
	var at := 0
	for m in _matches(s):
		if seen.has(m[2]):
			continue
		seen.append(m[2])
		out += _esc(s.substr(at, m[0] - at))
		out += _link(m[2], s.substr(m[0], m[1] - m[0]))
		at = m[1]
	return out + _esc(s.substr(at))


static func _strip_links(text: String) -> String:
	return RegEx.create_from_string("\\{[^}]*\\}").sub(text, " ", true)


static func _links(text: String) -> Array[String]:
	var out: Array[String] = []
	for m in RegEx.create_from_string("\\{([a-z0-9_]+)").search_all(text):
		if has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


## [start, end, key] for each whole-word name or alias in `s`, longest names first.
static func _matches(s: String) -> Array:
	all()
	if _regex == null:
		var names: Array = _lookup.keys()
		names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
		var alts := PackedStringArray()
		for n in names:
			alts.append(_rx_escape(n))
		_regex = RegEx.create_from_string("(?i)\\b(" + "|".join(alts) + ")\\b")
	var out := []
	for m in _regex.search_all(s):
		out.append([m.get_start(), m.get_end(), _lookup[m.get_string(1).to_lower()]])
	return out


static func _rx_escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ".+*?^$()[]{}|\\-".contains(ch) else ch
	return out


static func _build() -> Dictionary:
	var t := {}
	# --- Infection -------------------------------------------------------------------------
	t["infection"] = {"name": "Infection", "kind": "meter", "icon": "infection", "tone": "teal",
		"line": "The Bloom inside a soldier, 0 to 100. It only goes up on its own.",
		"art": "tiers",
		"stats": [["+%d" % Infection.DAMAGE_GAIN_BASE, "per hit taken"], ["%d" % Infection.EXPOSED_AT, "{mutation} wakes"], ["%d" % Infection.TURNED_AT, "{turning|Turns}"]],
		"more": ["Each hit from the Infected adds %d, +%d per damage, %d at most." % [Infection.DAMAGE_GAIN_BASE, Infection.DAMAGE_GAIN_PER_DAMAGE, Infection.DAMAGE_GAIN_MAX],
			"From %d a soldier can {lapse}." % Infection.MUTATING_AT,
			"Mutating: +1 move. Critical: +1 move and +10 aim.",
			"Lower it with {stim}, {serum} or a {purge} at the field hospital."],
		"see": ["lapse", "turning", "mutation", "serum"],
		"aliases": ["Exposed", "Mutating", "Infection tier"], "labels": ["Clean", "Critical"]}
	t["lapse"] = {"name": "Lapse", "kind": "status", "icon": "alert", "tone": "teal",
		"line": "The soldier loses control for a turn and attacks whoever is near.",
		"art": "lapse",
		"stats": [["%d%%" % roundi(Infection.LAPSE_CHANCE[Infection.Tier.MUTATING] * 100), "Mutating"], ["%d%%" % roundi(Infection.LAPSE_CHANCE[Infection.Tier.CRITICAL] * 100), "Critical"], ["1", "turn"]],
		"more": ["Rolled at the start of every squad phase.", "They come back next turn and can't lapse twice in a row.", "Keep {infection} under %d and it never happens." % Infection.MUTATING_AT],
		"see": ["infection", "turning"],
		"aliases": ["Lapsed", "Lapses", "Lapsing"]}
	t["turning"] = {"name": "Turning", "kind": "mechanic", "icon": "turned", "tone": "teal",
		"line": "At %d {infection} the soldier is lost to the Bloom. Permanent." % Infection.TURNED_AT,
		"art": "turning",
		"stats": [["%d" % Infection.TURNED_AT, "Infection"], ["0", "way back"]],
		"more": ["A Turned soldier fights for the Infected.", "They can come back in a later run as an {echo}."],
		"see": ["infection", "echo", "lapse"],
		"aliases": ["Turned"]}
	t["mutation"] = {"name": "Mutation", "kind": "power", "icon": "mutation", "tone": "teal",
		"line": "A Bloom power grafted onto a soldier. Asleep until {infection} reaches its tier.",
		"art": "tiers",
		"stats": [["3", "slots"], ["%d" % Infection.EXPOSED_AT, "first wakes"]],
		"more": ["Below its tier a mutation goes dormant again.", "Active ones cost Infection to use.", "Each awake mutation counts as 1 {tag_strain|Strain}."],
		"see": ["infection", "tag_strain", "set_bonus"],
		"aliases": ["Mutations", "Dormant", "Awake"]}
	t["echo"] = {"name": "Echo", "kind": "enemy", "icon": "skull", "tone": "danger",
		"line": "A soldier who {turning|Turned} in an earlier run, back as a named elite.",
		"art": "",
		"stats": [["%d" % Story.ECHOES_PER_RUN, "per run"]],
		"more": ["Beat one to recover an intel log."],
		"see": ["turning"],
		"aliases": ["Echoes"]}
	# --- Shooting --------------------------------------------------------------------------
	t["hit_chance"] = {"name": "Hit chance", "kind": "mechanic", "icon": "shoot", "tone": "amber",
		"line": "Aim minus the target's cover and defense. One roll from 1 to 100.",
		"art": "hit_roll",
		"stats": [["%d%%" % Combat.MIN_CHANCE, "floor"], ["+%d" % Combat.GRAZE_BAND, "graze band"]],
		"more": ["Roll under hit: full damage, sometimes a {crit}.", "Just over it: a {graze} for half.", "{cover}, {high_ground} and {mark|Marks} move the number."],
		"see": ["cover", "graze", "crit", "high_ground"],
		"labels": ["Hit", "Aim", "Odds", "To hit"]}
	t["graze"] = {"name": "Graze", "kind": "result", "icon": "shoot", "tone": Styles.GRAZE,
		"line": "A near miss that still lands half damage.",
		"art": "damage",
		"stats": [["%d" % Combat.GRAZE_BAND, "points over hit"], ["1/2", "damage"]],
		"see": ["hit_chance", "crit"],
		"aliases": ["Grazes", "Grazed"]}
	t["crit"] = {"name": "Critical hit", "kind": "result", "icon": "kill", "tone": "amber",
		"line": "A hit that deals half again. {flank|Flanking} makes them far likelier.",
		"art": "damage",
		"stats": [["x1.5", "damage"], ["+%d" % Combat.FLANK_CRIT, "crit if flanked"]],
		"see": ["flank", "hit_chance"],
		"aliases": ["Crit", "Crits", "Critical hits"]}
	t["cover"] = {"name": "Cover", "kind": "mechanic", "icon": "cover_half", "tone": "amber",
		"line": "A wall between you and the shooter cuts their aim.",
		"art": "cover",
		"stats": [["-%d" % Combat.COVER_HALF, "half cover"], ["-%d" % Combat.COVER_FULL, "full cover"]],
		"more": ["Cover only counts on the side facing the shot.", "{hunker|Hunker} to double it.", "Melee only feels half cover, -%d." % Combat.MELEE_COVER, "No cover from that side means {flank|flanked}."],
		"see": ["hunker", "flank", "high_ground"],
		"aliases": ["Half cover", "Full cover", "Covered"]}
	t["flank"] = {"name": "Flanked", "kind": "status", "icon": "alert", "tone": "danger",
		"line": "Shot from a side with no cover. Easy to hit, easy to crit.",
		"art": "flank",
		"stats": [["0", "cover"], ["+%d" % Combat.FLANK_CRIT, "crit"]],
		"more": ["{high_ground|High ground} can strip cover, but only a real flank adds the crit."],
		"see": ["cover", "crit"],
		"aliases": ["Flank", "Flanking", "Flanks"]}
	t["high_ground"] = {"name": "High ground", "kind": "mechanic", "icon": "rank", "tone": "amber",
		"line": "Shooting down from a roof: better aim, and their cover drops a step.",
		"art": "high_ground",
		"stats": [["+%d" % Elevation.AIM_BONUS, "aim"], ["-1", "cover step"], ["%d" % Elevation.FALL_DAMAGE_PER_LEVEL, "fall dmg / level"]],
		"more": ["Full cover becomes half, half becomes none.", "Shooting up at a roof: they always have half cover.", "One level or two, the bonus is the same."],
		"see": ["cover", "flank"],
		"aliases": ["Height", "Elevation", "Roof", "Rooftop"]}
	t["overwatch"] = {"name": "Overwatch", "kind": "action", "icon": "overwatch", "tone": "amber",
		"line": "End the turn watching: shoot the first enemy that moves in sight.",
		"art": "overwatch",
		"stats": [["1", "reaction shot"], ["-%d" % Combat.REACTION_PENALTY, "aim"]],
		"more": ["Fires in the enemy phase.", "A {suppress|Suppressed} soldier loses their overwatch."],
		"see": ["suppress", "hit_chance", "tag_overwatch"],
		"aliases": ["Reaction shot", "On overwatch"]}
	t["hunker"] = {"name": "Hunker down", "kind": "action", "icon": "hunker", "tone": "amber",
		"line": "Get low behind {cover} until your next turn. Doubles it.",
		"art": "cover", "art_ctx": {"hunker": true},
		"stats": [["x2", "cover"], ["-%d" % (Combat.COVER_HALF * 2), "half"], ["-%d" % (Combat.COVER_FULL * 2), "full"]],
		"more": ["Does nothing in the open."],
		"see": ["cover"],
		"aliases": ["Hunker", "Hunkered", "Hunkering"]}
	t["suppress"] = {"name": "Suppressed", "kind": "status", "icon": "suppress", "tone": "danger",
		"line": "Pinned down: worse aim on the next shot, and no overwatch.",
		"art": "",
		"stats": [["-%d" % Combat.SUPPRESS_PENALTY, "aim"], ["1", "shot"]],
		"more": ["The Trooper's Suppress ends their turn.", "With 3 {tag_suppress|Suppress} gear, moving while suppressed gives a free shot."],
		"see": ["overwatch", "tag_suppress"],
		"aliases": ["Suppression", "Pinned"], "labels": ["Suppress"]}
	t["mark"] = {"name": "Marked", "kind": "status", "icon": "tag", "tone": Color("#ff5c86"),
		"line": "Tagged by a Marksman: every soldier aims better against it.",
		"art": "",
		"stats": [["+%d" % Combat.TAG_BONUS, "aim for all"], ["1", "round"]],
		"more": ["Lasts until the end of the next enemy phase."],
		"see": ["tag_mark", "hit_chance"],
		"aliases": ["Tagged", "Marksman Tag"], "labels": ["Mark", "Tag"]}
	t["burning"] = {"name": "Burning", "kind": "status", "icon": "alert", "tone": Color("#ff7a45"),
		"line": "On fire: damage at the start of each of its turns.",
		"art": "hazards",
		"stats": [["2", "dmg / turn"]],
		"see": ["hazards", "tag_burn"],
		"aliases": ["Burn status", "On fire", "Ignite", "Ignites"]}
	t["hazards"] = {"name": "Tile hazards", "kind": "terrain", "icon": "alert", "tone": "danger",
		"line": "Fire, spores and acid on the ground. Hurts whoever stands in it.",
		"art": "hazards",
		"stats": [["%d" % Hazards.KINDS.fire.damage, "fire dmg"], ["+%d" % Hazards.KINDS.spore.infection, "spore Infection"], ["%d" % Hazards.KINDS.acid.damage, "acid dmg"]],
		"more": ["Spores don't hurt the Infected.", "Fire burns spores away."],
		"see": ["burning", "infection"],
		"aliases": ["Hazard", "Spores", "Acid", "Fire tiles", "Fire tile"]}
	t["actions"] = {"name": "Actions", "kind": "rule", "icon": "turn", "tone": "amber",
		"line": "Each soldier gets %d actions in a squad phase, in any order." % Types.ACTIONS_PER_TURN,
		"art": "",
		"stats": [["%d" % Types.ACTIONS_PER_TURN, "per turn"]],
		"more": ["Moving costs 1. Big moves like Suppress or Breach end the turn.", "Press Ready when done; enemies move once everyone is ready."],
		"see": ["overwatch", "hunker"],
		"aliases": ["Action", "Action points"]}
	t["line_of_sight"] = {"name": "Line of sight", "kind": "rule", "icon": "reveal", "tone": "text",
		"line": "You can only shoot what you can see. Walls block it.",
		"art": "",
		"stats": [["%d" % Vision.SOLDIER_SIGHT, "tiles sight"], ["%d" % Vision.KIND_SIGHT.marksman, "Marksman"]],
		"more": ["Tiles nobody sees are under {fog}."],
		"see": ["fog", "cover"],
		"aliases": ["LOS", "No line of sight"]}
	t["fog"] = {"name": "Fog of war", "kind": "rule", "icon": "reveal", "tone": "dim",
		"line": "Enemies outside your squad's sight are hidden. They still move.",
		"art": "",
		"stats": [["%d" % Vision.SOLDIER_SIGHT, "tiles sight"]],
		"see": ["line_of_sight"],
		"aliases": ["Fog", "Unexplored"]}
	t["stim"] = {"name": "Stim", "kind": "ability", "icon": "medic", "tone": "hp",
		"line": "Medic shot: heals and pushes back {infection}.",
		"art": "",
		"stats": [["+%d" % Combat.STIM_HEAL, "HP"], ["-%d" % Combat.STIM_CURE, "Infection"]],
		"see": ["infection"],
		"aliases": ["Stims"]}
	# --- Soldiers and gear -----------------------------------------------------------------
	t["gear_tag"] = {"name": "Gear tag", "kind": "gear", "icon": "doctrine", "tone": "amber",
		"line": "Every item has one of 8 tags. Stack 3 of a tag for its {set_bonus}.",
		"art": "set",
		"stats": [["8", "tags"], ["%d" % GearData.SET_THRESHOLD, "for a bonus"]],
		"more": ["Perks and awake mutations count toward tags too."],
		"see": ["set_bonus"] + _tag_keys(),
		"aliases": ["Gear tags"], "labels": ["Tags"]}
	t["set_bonus"] = {"name": "Set bonus", "kind": "gear", "icon": "perk", "tone": "amber",
		"line": "%d of the same {gear_tag|tag} on one soldier switch on that tag's bonus." % GearData.SET_THRESHOLD,
		"art": "set",
		"stats": [["%d" % GearData.SET_THRESHOLD, "same tag"], ["1", "bonus per tag"]],
		"more": ["Gear, perks and awake mutations all count.", "Purging a mutation mid-fight can switch a bonus off."],
		"see": ["gear_tag", "mutation", "perk"],
		"aliases": ["Set bonuses"], "labels": ["Set"]}
	for tag in GearData.TAGS:
		var info: Dictionary = GearData.TAG_INFO[tag]
		t["tag_" + tag.to_lower()] = {"name": tag, "kind": "gear tag", "icon": "doctrine", "tone": info.color,
			"line": str(info.about) + ".",
			"art": "set",
			"stats": [["%d" % GearData.SET_THRESHOLD, "for the bonus"]],
			"more": ["Set bonus: " + str(info.bonus) + "."],
			"see": ["set_bonus", "gear_tag"],
			"aliases": [tag + " tag"], "scan": false}
	t["mk2"] = {"name": "Mk II", "kind": "gear", "icon": "plus", "tone": "amber",
		"line": "The upgraded version of an item: same idea, bigger numbers.",
		"art": "",
		"stats": [["2", "copies merge"]],
		"aliases": ["Mk 2", "Mk I"]}
	t["pocket"] = {"name": "Pocket", "kind": "gear", "icon": "consumable", "tone": "amber",
		"line": "Two slots for one-use items like grenades and medkits.",
		"art": "",
		"stats": [["4", "gear slots"], ["2", "pockets"]],
		"aliases": ["Pockets", "Consumable", "Consumables"]}
	t["rank"] = {"name": "Rank", "kind": "progress", "icon": "rank", "tone": "amber",
		"line": "Soldiers rank up after set fights and pick a {perk}.",
		"art": "rank",
		"stats": [["%d" % Progression.MAX_RANK, "max rank"], ["%d" % Progression.RARE_FROM_RANK, "rare perks from"]],
		"see": ["perk"],
		"aliases": ["Ranks", "Rank up", "Rank-up", "Promotion"]}
	t["perk"] = {"name": "Perk", "kind": "progress", "icon": "perk", "tone": "amber",
		"line": "A class skill picked at each {rank}.",
		"art": "",
		"stats": [["4", "per soldier"]],
		"more": ["Some perks also count toward {gear_tag|tags}."],
		"see": ["rank", "set_bonus"],
		"aliases": ["Perks"], "labels": ["Doctrine"]}
	t["reserve"] = {"name": "Reserve", "kind": "squad", "icon": "recruit", "tone": "hp",
		"line": "Recruits waiting to replace a soldier who falls.",
		"art": "",
		"stats": [["%d" % RunRules.START_RESERVE, "to start"]],
		"more": ["Survivor nodes add more.", "Dead soldiers sit out and come back as recruits."],
		"aliases": ["Recruit", "Recruits", "Reserves"]}
	# --- The run ---------------------------------------------------------------------------
	t["outbreak"] = {"name": "Outbreak", "kind": "run meter", "icon": "outbreak", "tone": "teal",
		"line": "How far the Bloom has spread. Higher stages make every fight harder.",
		"art": "outbreak",
		"stats": [["+1", "per node"], ["-%d" % RunRules.BOSS_OUTBREAK_DROP, "per boss"]],
		"more": ["Healing or purging at the field hospital adds 1.", "{severity} can start it higher."],
		"see": ["severity", "infection"],
		"aliases": ["Outbreak stage", "Contained", "Spreading", "Rampant", "Collapse"]}
	t["supplies"] = {"name": "Supplies", "kind": "resource", "icon": "supplies", "tone": Color("#e0b44a"),
		"line": "The squad's shared money for the depot and the hospital.",
		"art": "",
		"stats": [["%d" % RunRules.START_SUPPLIES, "to start"], ["+%d" % RunRules.INCOME[RunMap.SKIRMISH].supplies, "per fight"]],
		"see": ["serum", "intel"],
		"aliases": ["Supply"]}
	t["intel"] = {"name": "Intel", "kind": "resource", "icon": "intel", "tone": "text",
		"line": "Spend 1 to reveal what a hidden ? node really is.",
		"art": "intel",
		"stats": [["%d" % RunRules.START_INTEL, "to start"], ["1", "per reveal"]],
		"see": ["supplies"],
		"labels": ["Reveal"]}
	t["serum"] = {"name": "Serum", "kind": "resource", "icon": "serum", "tone": "teal",
		"line": "Samples that cure a soldier's {infection}.",
		"art": "",
		"stats": [["+1", "per nest or boss"]],
		"more": ["Each player keeps their own samples."],
		"see": ["infection", "purge"],
		"aliases": ["Serum samples", "Samples"]}
	t["purge"] = {"name": "Purge", "kind": "treatment", "icon": "purge", "tone": "teal",
		"line": "Field hospital treatment: burns {infection} out of one soldier.",
		"art": "",
		"stats": [["-30", "Infection"], ["+1", "Outbreak"]],
		"see": ["infection", "outbreak", "tag_purge"],
		"aliases": ["Purged", "Purging"]}
	t["healing"] = {"name": "Healing", "kind": "rule", "icon": "health", "tone": "hp",
		"line": "HP carries between fights. Everyone heals a little after each win.",
		"art": "healing",
		"stats": [["%d%%" % roundi(RunRules.HEAL_AFTER_FIGHT * 100), "after a fight"]],
		"more": ["Patch up at the field hospital heals to full.", "{stim|Stims} and medkits heal in a fight."],
		"see": ["stim", "outbreak"],
		"aliases": ["Patch up"], "labels": ["HP", "Heal"]}
	t["severity"] = {"name": "Severity", "kind": "difficulty", "icon": "outbreak", "tone": "danger",
		"line": "Optional difficulty from 0 to %d. Beat the Source to unlock the next." % Severity.MAX,
		"art": "severity",
		"stats": [["%d" % Severity.MAX, "levels"], ["+%d%%" % roundi(Severity.FIELD_DATA_BONUS * 100), "{field_data} each"]],
		"more": ["Each level keeps every rule below it."],
		"see": ["field_data", "outbreak"],
		"aliases": ["Severity level"]}
	t["field_data"] = {"name": "Field Data", "kind": "meta", "icon": "intel", "tone": "amber",
		"line": "Earned every run, won or lost. Spend it at Field HQ on unlocks.",
		"art": "",
		"stats": [["+%d%%" % roundi(Severity.FIELD_DATA_BONUS * 100), "per Severity"]],
		"see": ["severity"],
		"aliases": ["FD"]}
	# --- Route map nodes (keys are "node_" + the RunMap type) ------------------------------
	var inc: Dictionary = RunRules.INCOME
	var nodes := {
		RunMap.SKIRMISH: ["Skirmish", "skirmish", "danger", "A standard fight with an objective.", [["+%d" % inc[RunMap.SKIRMISH].supplies, "{supplies}"], ["1", "gear pick each"]]],
		RunMap.AMBUSH: ["Ambush", "ambush", "danger", "A fight where the enemy is alerted and strikes first.", [["+%d" % inc[RunMap.AMBUSH].supplies, "{supplies}"]]],
		RunMap.NEST: ["Nest", "nest", "danger", "An elite guards a nest. Harder fight, better loot.", [["+%d" % inc[RunMap.NEST].supplies, "{supplies}"], ["+1", "{serum}"]]],
		RunMap.BOSS: ["Boss", "boss", "danger", "The end of an act. Win to push deeper and knock back {outbreak}.", [["-%d" % RunRules.BOSS_OUTBREAK_DROP, "{outbreak}"], ["+1", "{serum}"]]],
		RunMap.EVENT: ["Event", "event", "text", "A choice with a price, decided together.", []],
		RunMap.DEPOT: ["Depot", "depot", Color("c9a24a"), "A shop: spend {supplies} on gear, pockets and Serum.", []],
		RunMap.HOSPITAL: ["Field hospital", "hospital", "hp", "One treatment per soldier: patch up, {purge} or train.", [["+1", "{outbreak} if used"]]],
		RunMap.SURVIVORS: ["Survivors", "survivors", "hp", "People to bring home: a recruit for the {reserve}.", [["+%d" % RunRules.BONUS_SUPPLIES, "{supplies}"], ["1", "recruit"]]],
		RunMap.UNKNOWN: ["Hidden node", "unknown", "dim", "Usually an event. Spend {intel} to see it first.", [["1", "{intel} to reveal"]]],
	}
	for type in nodes:
		var n: Array = nodes[type]
		t["node_" + type] = {"name": n[0], "kind": "map node", "icon": n[1], "tone": n[2], "line": n[3],
			"art": "intel" if type == RunMap.UNKNOWN else "", "stats": n[4], "see": ["outbreak"], "scan": false}
	return t


static func _tag_keys() -> Array:
	var out := []
	for tag in GearData.TAGS:
		out.append("tag_" + tag.to_lower())
	return out
