class_name GearTags
extends RefCounted
## Tag counting for set bonuses and Prototypes. A soldier's count for a tag is their gear plus
## their class perks and awake mutations (each awake mutation also adds 1 Strain). The perk
## and mutation part comes from Progression (ranks/perks/mutations module), loaded by path so
## this module works with or without it.

const PROGRESSION_PATH := "res://progression/progression.gd"

static var _progression: Variant = false  # false = not looked up yet, null = absent


## The Progression script if it's in the build, else null.
static func progression():
	return _prog()


static func _prog():
	if typeof(_progression) == TYPE_BOOL:
		_progression = load(PROGRESSION_PATH) if ResourceLoader.exists(PROGRESSION_PATH) else null
	return _progression


## Test hook: swap in a fake Progression (any object with tag_counts / unit_tag_counts), or
## null to ignore perks and mutations. Pass false to go back to the real one.
static func set_progression(p: Variant) -> void:
	_progression = p


## Does the Progression script (or a test fake object) provide `method`?
static func provides(p, method: String) -> bool:
	if p == null:
		return false
	if p is Script:
		return (p as Script).get_script_method_list().any(func(m): return m.name == method)
	return p.has_method(method)


## Total tag counts for a run soldier record: {"Mark": 2, ...} (only tags above 0).
static func counts(record) -> Dictionary:
	var out := Loadout.gear_tags(record)
	var p = _prog()
	if provides(p, "tag_counts"):
		_merge(out, p.tag_counts(record))
	return out


## Live tag counts for a soldier in a mission (gear stamped by GearRun.apply_to_unit, plus
## perks and awake mutations right now, so purging mid-fight can switch a set bonus off).
static func unit_counts(u: Unit) -> Dictionary:
	var out: Dictionary = u.status.get("gear_tags", {}).duplicate()
	var p = _prog()
	if provides(p, "unit_tag_counts"):
		_merge(out, p.unit_tag_counts(u))
	return out


static func _merge(into: Dictionary, extra) -> void:
	if not extra is Dictionary:
		return
	for k in extra:
		var t := normalize(str(k))
		if t != "" and int(extra[k]) > 0:
			into[t] = into.get(t, 0) + int(extra[k])


## "burn" / "BURN" / "Burn" -> "Burn"; "" if it isn't one of the 8 tags.
static func normalize(tag: String) -> String:
	for t in GearData.TAGS:
		if t.to_lower() == tag.to_lower():
			return t
	return ""


static func has_set(c: Dictionary, tag: String) -> bool:
	return c.get(tag, 0) >= GearData.SET_THRESHOLD


static func unit_has_set(u: Unit, tag: String) -> bool:
	return has_set(unit_counts(u), tag)


## Tags whose set bonus is on.
static func active_sets(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t in GearData.TAGS:
		if has_set(c, t):
			out.append(t)
	return out


## Tags sorted by count, highest first (ties in GearData.TAGS order); only tags above 0.
static func ranked(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for t in GearData.TAGS:
		if c.get(t, 0) > 0:
			out.append(t)
	out.sort_custom(func(a, b): return c[a] > c[b] or (c[a] == c[b] and GearData.TAGS.find(a) < GearData.TAGS.find(b)))
	return out


static func lead_tag(c: Dictionary) -> String:
	var r := ranked(c)
	return r[0] if not r.is_empty() else ""


## Prototype ids whose two tags are both at 2+.
static func qualified_prototypes(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in GearData.PROTOTYPES:
		var tags: Array = GearData.PROTOTYPES[id].tags
		if tags.all(func(t): return c.get(t, 0) >= GearData.PROTOTYPE_THRESHOLD):
			out.append(id)
	return out


## What taking `id` would do to the soldier's tags, for the card's threshold preview:
## [{"tag", "from", "to", "unlocks": bool}]. Accounts for the item it would replace.
static func preview(record, id: String) -> Array[Dictionary]:
	var before := counts(record)
	var after := before.duplicate()
	var p := Loadout.preview_equip(record, id)
	if p.mode == "upgrade" or p.mode == "stash":
		return []
	if p.mode == "replace":
		for t in GearData.tags_of(p.old.id):
			after[t] = after.get(t, 0) - 1
	for t in GearData.tags_of(id):
		after[t] = after.get(t, 0) + 1
	var out: Array[Dictionary] = []
	for t in GearData.TAGS:
		var a: int = before.get(t, 0)
		var b: int = after.get(t, 0)
		if a != b:
			out.append({"tag": t, "from": a, "to": b,
				"unlocks": a < GearData.SET_THRESHOLD and b >= GearData.SET_THRESHOLD,
				"loses": a >= GearData.SET_THRESHOLD and b < GearData.SET_THRESHOLD})
	return out
