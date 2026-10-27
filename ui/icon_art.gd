extends RefCounted
## Generated glow art (tools/gen_icon_set.py): white masks under assets/icons/, tinted by the
## caller. Missing files return null, so the line glyphs in icons.gd stay the fallback.

const DIR := "res://assets/icons/"
static var _cache := {}


static func vocab(id: String) -> Texture2D:
	return _load(DIR + id + ".png")


## Gear, guns, consumables and deployment orders, by their data id.
static func item(id: String) -> Texture2D:
	return _load(DIR + "items/" + id + ".png")


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
