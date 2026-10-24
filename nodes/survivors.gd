class_name Survivors
extends RefCounted
## Survivors node: +10 Supplies and one rescued colonist for a player's reserve. The first
## player to claim them takes them; if nobody does, they go to the smallest reserve.
## OWNER: nodes workstream.

const SUPPLIES := 10

## Short scenes for the rescue; {name} is the recruit.
const SCENES: Array[String] = [
	"A grain-co foreman has held a cold-storage room for nine days with a bolt gun and a bad knee. {name} asks for a rifle before asking for water.",
	"Three kids and a militia deserter in a school gym, the doors welded shut from inside. The deserter, {name}, cuts the way out to meet you.",
	"A Cordon signaller is still at the post in a relay hut, logging every Bloom sighting by hand. {name} packs the logbook and falls in.",
	"A Halden-Voss technician who ran when the labs went dark. {name} won't say what the work was, and keeps checking both arms for glow.",
	"A Choir convert who changed their mind, bleeding teal from the ears and desperate to be useful. {name} swears the voice has stopped.",
	"A sniper on a water tower who has kept one street clear for a week. {name} climbs down at the sight of the Lantern glow.",
]


static func enter(run) -> Dictionary:
	var recruit := {"kind": RunAccess.random_recruit_kind(run),
		"name": RunAccess.unused_name(run)}
	var scene: String = SCENES[run.rng.randi_range(0, SCENES.size() - 1)]
	var ns := {"kind": "survivors", "recruit": recruit, "text": scene.replace("{name}", recruit.name),
		"claimed_by": -1, "left": [], "finished": false}
	run.node_state = ns
	RunAccess.add_supplies(run, SUPPLIES)
	RunAccess.emit(run, {"type": "survivors_found", "recruit": recruit.duplicate(true)})
	return ns


static func validate(run, ns: Dictionary, action: Dictionary) -> String:
	if action.type != "node_claim":
		return "unknown action"
	if ns.claimed_by != -1:
		return "already claimed"
	return "" if RunAccess.is_active(run, action.get("player", -1)) else "not in the squad"


static func apply(run, ns: Dictionary, action: Dictionary) -> void:
	_give(run, ns, action.player)


## Nobody claimed them: the smallest reserve gets them.
static func settle(run, ns: Dictionary) -> void:
	if ns.claimed_by == -1:
		_give(run, ns, RunAccess.fewest_recruits(run))


static func _give(run, ns: Dictionary, player: int) -> void:
	ns.claimed_by = player
	ns.finished = true
	if player != -1:
		var r := RunAccess.add_recruit(run, player, ns.recruit.kind, 0, ns.recruit.name)
		ns.recruit["sid"] = r.id
