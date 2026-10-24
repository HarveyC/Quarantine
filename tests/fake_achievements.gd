extends RefCounted
## Stand-in for meta progression's Achievements class (static API).

static var listeners: Array[Callable] = []


static func unlocked() -> Array[String]:
	return ["first_win"] as Array[String]


static func on_unlocked(cb: Callable) -> void:
	listeners.append(cb)


static func stats() -> Dictionary:
	return {"runs": 3, "wins": 1}


static func earn(id: String) -> void:
	for cb in listeners:
		cb.call(id)
