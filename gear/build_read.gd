class_name BuildRead
extends RefCounted
## How a build reads on screen: the 8 gear tags sorted into three jobs (Setup opens a window,
## Payoff spends it, Sustain keeps the carrier alive), each class's two lane tags and which tags a
## new profile sees. Data only, no UI.

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
