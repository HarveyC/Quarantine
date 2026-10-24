class_name RunHooks
extends RefCounted
## Late-bound calls into modules owned by other workstreams (GearRun, Progression, NodeRules,
## FightBuilder, Encounter, MapGen). The run framework calls them by class name so it builds and
## runs before those modules land: a missing class or method returns `fallback`.
## See "Run framework" in docs/ARCHITECTURE.md for every hook and when it is called.

static var _scripts := {}


## The global script registered under `cls`, or null if that module hasn't landed yet.
static func script_of(cls: String) -> Script:
	if not _scripts.has(cls):
		var found: Script = null
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == cls:
				found = load(entry["path"])
				break
		_scripts[cls] = found
	return _scripts[cls]


static func has(cls: String, method: String) -> bool:
	var sc := script_of(cls)
	if sc == null:
		return false
	for m in sc.get_script_method_list():
		if m.name == method:
			return true
	return false


## Calls the static function `cls.method(args...)`, or returns `fallback` if it doesn't exist.
static func call_static(cls: String, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	if not has(cls, method):
		return fallback
	return script_of(cls).callv(method, args)
