class_name Onboarding
extends RefCounted
## What this player has been taught, kept in the profile (`user://profile.cfg`, section
## "onboarding") so it carries between runs. Each machine has its own profile, so in online
## co-op every player sees their own first-time hints.
##
## Keys: `training_done` (finished or skipped the training mission), `training_offered` (the
## "play training first?" card was answered), `hints_off` (the player turned tips off), and
## one `hint_<id>` per contextual hint already shown (see ui/tutorial/coach.gd).

const SECTION := "onboarding"

## Tests point this at a scratch file so they never touch the player's profile.
static var path := Profile.PATH


static func _load() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(path)
	return cf


static func get_flag(key: String) -> bool:
	return bool(_load().get_value(SECTION, key, false))


static func set_flag(key: String, on := true) -> void:
	var cf := _load()
	if bool(cf.get_value(SECTION, key, false)) == on:
		return
	cf.set_value(SECTION, key, on)
	cf.save(path)


static func training_done() -> bool:
	return get_flag("training_done")


static func mark_training_done() -> void:
	set_flag("training_done")


## True the first time a new player starts a run without having played or skipped training.
static func should_offer_training() -> bool:
	return not training_done() and not get_flag("training_offered")


static func hints_enabled() -> bool:
	return not get_flag("hints_off")


static func set_hints_enabled(on: bool) -> void:
	set_flag("hints_off", not on)


static func hint_seen(id: String) -> bool:
	return get_flag("hint_" + id)


static func mark_hint(id: String) -> void:
	set_flag("hint_" + id)


## Shows every hint again (and turns tips back on). Training stays marked as done.
static func reset_hints() -> void:
	var cf := _load()
	if not cf.has_section(SECTION):
		return
	for k in cf.get_section_keys(SECTION):
		if k.begins_with("hint_") or k == "hints_off":
			cf.erase_section_key(SECTION, k)
	cf.save(path)
