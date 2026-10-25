class_name BuildRead
extends RefCounted
## How a build reads on screen: the 8 gear tags sorted into three jobs (Setup opens a window,
## Payoff spends it, Sustain keeps the carrier alive), each class's two lane tags, which tags a
## new profile sees, and the class pairs the lobby calls out. Data only, no UI.

const JOBS: Array[String] = ["Setup", "Payoff", "Sustain"]
const JOB_TAGS := {
	"Setup": ["Mark", "Suppress", "Burn"],
	"Payoff": ["Overwatch", "Close", "Strain"],
	"Sustain": ["Guard", "Purge"],
}
const JOB_INFO := {
	"Setup": {"line": "Make an enemy easy to hit or stop.", "color": Color("#e8a83a")},
	"Payoff": {"line": "Cash the window in with a big or free shot.", "color": Color("#ff7a45")},
	"Sustain": {"line": "Stay alive and under 100 Infection.", "color": Color("#a9c46c")},
}

## The two tags each class builds around.
const LANES := {
	"trooper": ["Guard", "Suppress"], "marksman": ["Mark", "Overwatch"], "medic": ["Purge", "Guard"],
	"breacher": ["Close", "Suppress"], "hazmat": ["Burn", "Purge"], "vector": ["Strain", "Purge"],
	"reaper": ["Close", "Strain"], "warden": ["Guard", "Purge"],
}

## Best partner for each class: `a` helps `b`, for one concrete reason.
const PAIRS: Array[Dictionary] = [
	{"a": "marksman", "b": "breacher", "text": "Expose drops Tagged cover one step for the Breach."},
	{"a": "breacher", "b": "reaper", "text": "Breach a wall, Lunge through."},
	{"a": "reaper", "b": "hazmat", "text": "Hamstrung enemies cannot leave the fire."},
	{"a": "hazmat", "b": "vector", "text": "Scorched earth burns Infection off allies."},
	{"a": "vector", "b": "medic", "text": "Siphon moves Infection, Purge cleans it."},
	{"a": "medic", "b": "warden", "text": "Quarantine field: no Infection when hunkered."},
	{"a": "warden", "b": "trooper", "text": "Two Guard sets stack on one front."},
	{"a": "trooper", "b": "marksman", "text": "Suppress plus Crossfire gives free overwatch shots."},
]


static func job_of(tag: String) -> String:
	for j in JOBS:
		if (JOB_TAGS[j] as Array).has(tag):
			return j
	return ""


static func lane(kind: String) -> Array:
	return LANES.get(kind, [])


## A profile that has never finished a run sees only lane tags (and any tag it owns a piece of).
static func first_run() -> bool:
	return Profile.stat("runs") == 0


## Tags to list for a soldier of `kind` holding `counts`. `all` shows all 8 (the Field HQ switch,
## or a profile past its first run).
static func visible_tags(kind: String, counts: Dictionary, all: bool) -> Array[String]:
	var out: Array[String] = []
	var lanes := lane(kind)
	for t in GearData.TAGS:
		if all or counts.get(t, 0) > 0 or lanes.has(t):
			out.append(t)
	return out


## The strongest tag of each job, "" where the soldier has none: {"Setup": "Mark", ...}.
static func leads(counts: Dictionary) -> Dictionary:
	var out := {}
	for j in JOBS:
		var best := ""
		for t in JOB_TAGS[j]:
			if counts.get(t, 0) > 0 and (best == "" or counts[t] > counts[best]):
				best = t
		out[j] = best
	return out


## Tag count that turns on the capstone, or 0 while capstones are not in the build.
static func capstone_at() -> int:
	return int((GearData as GDScript).get_script_constant_map().get("CAPSTONE_THRESHOLD", 0))


## Pairs formed by two classes in `kinds` (one entry per soldier), each once, in PAIRS order.
static func pairs_in(kinds: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in PAIRS:
		if kinds.has(p.a) and kinds.has(p.b):
			out.append(p)
	return out


## Classes that would complete a pair with any class in `kinds`.
static func partners_of(kinds: Array) -> Array[String]:
	var out: Array[String] = []
	for p in PAIRS:
		for pair in [[p.a, p.b], [p.b, p.a]]:
			if kinds.has(pair[0]) and not out.has(pair[1]):
				out.append(pair[1])
	return out
