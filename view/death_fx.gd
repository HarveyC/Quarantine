extends RefCounted
## Effects for a unit's death, split at its two beats: the killing blow (`blow`) and the
## body hitting the floor (`land`). The infected spill dark ichor and a burst of glowing
## spores, the Bloom's props rupture in a bigger spore cloud, soldiers bleed. Bosses get
## all of it larger. Sounds are named here and played by the caller (EventPlayer._sfx).

const Palette := preload("res://view/palette.gd")
const ModelKit := preload("res://view/model_kit.gd")

const ICHOR := Color("24100c")       # infected flesh and the dark ooze under the glow
const BLOOD := Color("6a1a14")
const DUST := Color(0.42, 0.4, 0.36)


## What kind of death `uv` has: "soldier", "infected", "prop" (no skeleton) or "boss".
static func kind_of(uv: Node3D) -> String:
	if EnemyRoster.BOSSES.has(uv.kind):
		return "boss"
	if uv.soldier_body and not uv.turned and uv.is_soldier:
		return "soldier"
	if uv.get("_skin") == null:
		return "prop"
	return "infected"


## The killing blow at the chest: gore thrown out the far side along `away` (flat, from the
## killer), spores and a cold flash for the infected. Returns the sounds to play.
static func blow(fx: Node3D, uv: Node3D, away: Vector3, heavy: bool) -> Array[String]:
	var k := kind_of(uv)
	var at: Vector3 = uv.aim_point()
	var big := 1.6 if k == "boss" else (1.3 if heavy else 1.0)
	var out := (away + Vector3(0, 0.35, 0)).normalized()
	if k == "soldier":
		fx.burst(at, out, BLOOD, int(14 * big), 3.6 * big, false, 0.05)
		fx.puff(at + away * 0.2, BLOOD.darkened(0.2), 0.35, 0.5, 0.1)
		return ["kill_hit", "soldier_death"]
	var mass := 1.6 if k == "prop" else 1.0
	fx.burst(at, out, ICHOR, int(18 * big * mass), 4.2 * big, false, 0.06)
	fx.burst(at, out + Vector3.UP * 0.6, Palette.TEAL, int(12 * big * mass), 2.8 * big, true, 0.03)
	fx.puff(at + away * 0.25, Palette.TEAL_DIM, 0.6 * big * mass, 0.9, 0.35)
	fx.puff(at, ICHOR.lightened(0.1), 0.45 * big, 0.6, 0.15)
	fx.flash_light(at, Palette.TEAL, 3.0 * big * mass, 0.3, 3.5)
	if k == "prop":
		# a hive node or sac ruptures: spores blow out all round
		for i in 6:
			var a := TAU * i / 6.0
			fx.burst(at, Vector3(cos(a), 0.7, sin(a)), Palette.TEAL, 5, 2.4, true, 0.03)
		fx.puff(at + Vector3(0, 0.3, 0), Palette.TEAL_DIM, 1.5 * big, 1.6, 0.9)
	return ["kill_hit", "spore_burst"]


## The body hits the floor: a dust kick and a pool spreading under it; the infected keep
## breathing out a last thin wisp of spores. Returns the sounds to play.
static func land(fx: Node3D, uv: Node3D) -> Array[String]:
	var k := kind_of(uv)
	var chest: Vector3 = uv.aim_point()   # the fall carries the body off its cell
	var at := Vector3(chest.x, uv.position.y, chest.z)
	var big := 1.5 if k == "boss" or ModelKit.size_of(uv.kind) > 1.15 else 1.0
	fx.puff(at + Vector3(0, 0.12, 0), DUST, 0.7 * big, 0.7, 0.12)
	if k == "soldier":
		fx.decal(at, BLOOD.darkened(0.35), 0.38)
		return ["body_fall"]
	fx.decal(at, ICHOR.darkened(0.3), 0.42 * big)
	fx.decal(at + Vector3(0.08, 0, -0.05), Palette.TEAL_DIM.darkened(0.45), 0.28 * big, true)
	fx.puff(at + Vector3(0, 0.25, 0), Palette.TEAL_DIM, 0.55 * big, 1.8, 0.7)
	return ["body_fall_heavy" if big > 1.0 or k == "prop" else "body_fall"]

