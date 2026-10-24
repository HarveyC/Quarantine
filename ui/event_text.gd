extends RefCounted
## Turns GameState events into one-line BBCode for the combat log.
## `name_of` is Callable(id: int) -> String. Unknown event types are listed raw.

const Palette := preload("res://view/palette.gd")
const EnemyBeats := preload("res://view/enemy_beats.gd")
## Melee class abilities that roll to hit -> verb for the log.
const MELEE := {"lunge": "lunges at", "riposte": "ripostes", "bash": "shield-bashes"}


static func describe(ev: Dictionary, name_of: Callable) -> String:
	var who := func(key: String) -> String:
		return "[b]%s[/b]" % name_of.call(int(ev.get(key, -1)))
	match str(ev.get("type", "")):
		"team_phase":
			return _c("--- Turn %d: squad phase ---" % int(ev.get("turn", 0)), Palette.player_ui(0))
		"enemy_phase":
			return _c("--- Enemy phase ---", Palette.DANGER)
		"ready":
			if ev.get("auto", false):
				return _c("Player %d has no soldiers left to act, ready" % (int(ev.get("player", 0)) + 1), Color(0.6, 0.6, 0.6))
			return _c("Player %d %s" % [int(ev.get("player", 0)) + 1, "is ready" if ev.get("ready", false) else "is not ready"], Color(0.6, 0.6, 0.6))
		"rejected":
			return _c("Rejected: %s" % str(ev.get("reason", "")), Color(0.75, 0.5, 0.45))
		"move":
			return "%s moves %d" % [who.call("unit"), (ev.get("path", []) as Array).size()]
		"shot":
			var res := "misses"
			if ev.get("hit", false):
				res = "CRITS" if ev.get("crit", false) else ("grazes" if ev.get("graze", false) else "hits")
			var pre := "Reaction: " if ev.get("reaction", false) else ""
			return "%s%s %s %s (%d%%)" % [pre, who.call("unit"), res, who.call("target"), int(ev.get("chance", 0))]
		"pinned":
			return "%s is pinned down by %s" % [who.call("target"), who.call("unit")]
		"damage":
			return "%s takes %s (HP %d)" % [who.call("unit"), _c(str(ev.get("amount", 0)), Palette.DANGER), int(ev.get("hp", 0))]
		"died":
			return _c("%s is down" % who.call("unit"), Palette.DANGER)
		"overwatch":
			return "%s goes on overwatch" % who.call("unit")
		"hunker":
			return "%s hunkers down" % who.call("unit")
		"ability" when ev.get("ability") in MELEE:
			var res := "misses"
			if ev.get("hit", false):
				res = "grazes" if ev.get("graze", false) else "hits"
			var verb: String = MELEE[ev.ability]
			if ev.get("cleave", false):
				verb = "cleaves into"
			elif ev.get("charge", false):
				verb = "shield-charges"
			elif ev.get("reaction", false):
				verb = "guard-bashes"
			return "%s %s %s: %s (%d%%)" % [who.call("unit"), verb, who.call("target"), res, int(ev.get("chance", 0))]
		"guard":
			return "%s raises their shield (Guard)" % who.call("unit")
		"perk":
			if ev.get("perk") == "bloodlust":
				return _c("%s: Bloodlust, the kill refunds an action" % who.call("unit"), Palette.TEAL)
			return "%s: %s" % [who.call("unit"), str(ev.get("perk", "?")).capitalize()]
		"bleeding":
			return _c("%s is bleeding (%d turns)" % [who.call("unit"), int(ev.get("turns", 0))], Palette.DANGER)
		"bleed":
			return "%s bleeds (%d)" % [who.call("unit"), int(ev.get("damage", 0))]
		"stunned":
			return "%s is stunned by %s" % [who.call("unit"), who.call("by")]
		"ability":
			return "%s uses %s%s" % [who.call("unit"), str(ev.get("name", str(ev.get("ability", "?")).capitalize())), _target_text(ev, who)]
		"mutation":
			return _c("%s mutates: %s%s" % [who.call("unit"), str(ev.get("mutation", "?")).capitalize(), _target_text(ev, who)], Palette.TEAL)
		"infection":
			var t := int(ev.get("tier", 0))
			return "%s infection %d (%s)" % [who.call("unit"), int(ev.get("value", 0)), _c(Infection.tier_name(t), Palette.tier_color(t))]
		"lapse":
			return _c("%s has LAPSED and acts on their own!" % who.call("unit"), Palette.DANGER)
		"recover":
			return "%s regains control" % who.call("unit")
		"alerted":
			return _c("%s has spotted the squad" % who.call("unit"), Palette.DANGER)
		"turned":
			return _c("%s has TURNED" % who.call("unit"), Palette.TEAL)
		"mission_end":
			var r := int(ev.get("result", 0))
			return _c("=== MISSION %s ===" % ("COMPLETE" if r == Types.Result.VICTORY else "FAILED"), Palette.AMBER)
	if EnemyBeats.handles(ev):
		return EnemyBeats.describe(ev, name_of)
	return _c(("[%s] %s" % [str(ev.get("type", "?")), str(ev)]).replace("[", "[lb]"), Color(0.55, 0.55, 0.55))


static func _target_text(ev: Dictionary, who: Callable) -> String:
	if ev.has("target"):
		return " on %s" % who.call("target")
	if ev.has("cell"):
		return " at %s" % str(ev.cell)
	return ""


static func _c(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]
