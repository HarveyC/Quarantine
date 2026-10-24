extends RefCounted
## Effects for the melee classes' strikes (view/melee_kit.gd has their props), played by
## the event player's melee beat at the moment of impact. View-only, from event data.

const Palette := preload("res://view/palette.gd")

## Stun-maul discharge colour (the Warden's maul and Stunned).
const SHOCK := Color(0.45, 0.75, 1.0)
const BLEED := Color("8a1e16")


## Impact effects of one strike at `at` (the target's chest), `dir` from striker to target.
##   "blade": the machete's teal-edged arc across the target, sparks of Bloom on a hit.
##   "shock": the shield slams in and the maul discharges, blue-white and amber sparks.
static func strike(fx, kind: String, at: Vector3, dir: Vector3, hit: bool) -> void:
	var right := dir.cross(Vector3.UP).normalized()
	match kind:
		"blade":
			var a := at - dir * 0.25 + right * 0.45 + Vector3(0, 0.35, 0)
			var b := at - dir * 0.15 - right * 0.4 - Vector3(0, 0.3, 0)
			fx.tracer(a, b, Color(0.75, 1.0, 0.95), 0.18)
			fx.tracer(a + Vector3(0, -0.04, 0), b + Vector3(0, -0.04, 0), Palette.TEAL, 0.3)
			if hit:
				fx.burst(at, dir + Vector3(0, 0.2, 0), Palette.TEAL, 8, 2.6, true, 0.025)
		"shock":
			var n := 18 if hit else 8
			fx.flash_light(at, SHOCK, 5.0 if hit else 2.0, 0.25, 3.5)
			fx.burst(at - dir * 0.2, -dir + Vector3(0, 0.3, 0), SHOCK, n, 5.0, true, 0.022)
			fx.burst(at - dir * 0.2, -dir, Palette.AMBER, int(n * 0.5), 4.0, true, 0.02)


## A few dark red drops falling from `at` (Bleed Out).
static func drip(fx, at: Vector3, ground: Vector3, heavy := false) -> void:
	fx.burst(at, Vector3.DOWN + Vector3(0, -0.5, 0), BLEED, 10 if heavy else 6, 1.4, false, 0.03)
	fx.decal(ground, BLEED.darkened(0.4), 0.22 if heavy else 0.16)


## Stunned: blue sparks crawling over the body and a crackle of light.
static func stun(fx, chest: Vector3) -> void:
	fx.flash_light(chest, SHOCK, 3.0, 0.4, 3.0)
	fx.burst(chest, Vector3.UP, SHOCK, 14, 1.8, true, 0.02)
