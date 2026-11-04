class_name Shield
extends RefCounted
## Shield: a pip row above HP that nobody starts with. Gear and perks add pips on triggers (a kill, an
## Overwatch shot), the pips soak damage before HP, and they are gone when the fight ends. Infection
## from the blow still lands. Rules only; the pips are drawn by Widgets.HpPips and the beats live in
## EventPlayer (_beat_shield, GEAR_PROCS).

const CAP := 8
## Capacitor vest: reaching this many pips gives an action, once a turn.
const CHARGED_AT := 4

const KEY := "shield_pips"


static func pips(u: Unit) -> int:
	return int(u.status.get(KEY, 0))


## Adds pips from `item` (a gear or perk id, for the beat).
static func add(s: GameState, u: Unit, n: int, item: String) -> void:
	if n <= 0 or not u.is_alive():
		return
	var was := pips(u)
	var now := mini(CAP, was + n)
	if now == was:
		return
	u.status[KEY] = now
	s.emit({"type": "shield", "unit": u.id, "pips": now, "delta": now - was, "item": item})
	if now >= CHARGED_AT and was < CHARGED_AT:
		_charged(s, u)


## Soaks `amount` into the pips; returns what is left for HP.
static func absorb(s: GameState, target: Unit, amount: int, source: Unit) -> int:
	var have := pips(target)
	if have <= 0 or amount <= 0:
		return amount
	var soak := mini(have, amount)
	target.status[KEY] = have - soak
	s.emit({"type": "shield", "unit": target.id, "pips": have - soak, "delta": -soak, "item": "shield_hit", "source": source.id if source else -1})
	if have - soak == 0:
		_broke(s, target)
	return amount - soak


## Capacitor vest: a full charge gives an action, once a turn.
static func _charged(s: GameState, u: Unit) -> void:
	if not GearFx.has(u, "capacitor_vest") or s.phase != Types.Phase.TEAM or int(u.status.get("charge_turn", -1)) == s.turn:
		return
	u.status["charge_turn"] = s.turn
	u.actions_left += 1
	s.emit({"type": "gear", "unit": u.id, "item": "capacitor_vest", "actions": u.actions_left})


## The last pip went: Reactive plating Marks every enemy next to the soldier.
static func _broke(s: GameState, u: Unit) -> void:
	if not GearFx.has(u, "reactive_plating"):
		return
	var turns := 3 if GearFx.mk(u, "reactive_plating") >= 2 else 2
	for e in s.living(Types.Team.ENEMY):
		if max(abs(e.pos.x - u.pos.x), abs(e.pos.y - u.pos.y)) == 1:
			GearFx._mark(s, e, turns, u)
			s.emit({"type": "gear", "unit": u.id, "item": "reactive_plating", "target": e.id})
