class_name GearLinks
extends RefCounted
## Link items: gear whose effect takes a status in, puts one out, or spreads it, so a pair
## multiplies instead of adding (Chain-link rounds feeding Echo array, Cinder lens turning
## every fire into a Mark, Hair-trigger harness shooting whatever gets Marked...). Rules only;
## GearFx calls these from its hooks and the beats live in EventPlayer.GEAR_PROCS.

const PIN_TAG_AIM := 10
const ECHO := [1, 2]
const SPILL_MK2_FULL := true
const LANCE_DAMAGE := [2, 3]
const SPORE_DAMAGE := [2, 3]

static var _busy := false   # a link never sets off a link of its own kind


static func _has(u: Unit, id: String) -> bool:
	return GearFx.has(u, id)


static func _mk(u: Unit, id: String) -> int:
	return GearFx.mk(u, id)


static func _foes_near(s: GameState, u: Unit, centre: Vector2i, radius: int, skip: Unit = null) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in s.living():
		if o != skip and u.is_enemy_of(o) and GearFx._cheb(o.pos, centre) <= radius:
			out.append(o)
	return out


static func _tag(s: GameState, o: Unit, phases: int) -> void:
	var until := Combat.phase_index(s) + phases
	if int(o.status.get("tagged", 0)) < until:
		o.status["tagged"] = until


## A Mark landed on `t` (`was` = it was already Marked). Chain-link spreads it; Hair-trigger fires on it.
static func on_marked(s: GameState, u: Unit, t: Unit, was: bool) -> void:
	if _busy or t == null or not t.is_alive():
		return
	_busy = true
	if u != null and _has(u, "chain_link"):
		var r := 1 if _mk(u, "chain_link") < 2 else 2
		for o in _foes_near(s, u, t.pos, r, t):
			if not GearFx.is_marked(s, o):
				_tag(s, o, maxi(1, int(t.status.get("tagged", 0)) - Combat.phase_index(s)))
				s.emit({"type": "gear", "unit": u.id, "item": "chain_link", "target": o.id, "from": t.id})
	if not was:
		for w in s.living(Types.Team.PLAYER):
			if not _has(w, "hair_trigger") or not w.is_enemy_of(t) or not t.is_alive():
				continue
			if Combat.is_overwatching(s, w) and Vision.overwatch_sees(s, w, t, t.pos):
				s.emit({"type": "gear", "unit": w.id, "item": "hair_trigger", "target": t.id})
				if _mk(w, "hair_trigger") < 2 and not Kit.keep_overwatch(s, w, t):
					w.overwatch = false
					w.status.erase("ow_until")
				Combat.fire(s, w, t, true)
	_busy = false


## After a shot resolved (GearFx.after_shot), before kills are handled.
static func after_shot(s: GameState, u: Unit, t: Unit, hit: bool, reaction: bool, dmg: int) -> void:
	u.status["link_dmg"] = dmg
	if not hit:
		return
	if _has(u, "echo_array") and GearFx.is_marked(s, t) and not _busy:
		_busy = true
		var amount: int = ECHO[clampi(_mk(u, "echo_array"), 1, 2) - 1]
		for o in s.living():
			if o != t and u.is_enemy_of(o) and GearFx.is_marked(s, o) and Combat.can_see(s, u.pos, o.pos):
				s.emit({"type": "gear", "unit": u.id, "item": "echo_array", "target": o.id, "damage": amount})
				Rules.deal_damage(s, o, amount, u)
		_busy = false
	if t.is_alive() and _has(u, "pin_tag_rounds") and GearFx.is_marked(s, t):
		GearFx._suppress(s, u, t, PIN_TAG_AIM if _mk(u, "pin_tag_rounds") >= 2 else 0)
		s.emit({"type": "gear", "unit": u.id, "item": "pin_tag_rounds", "target": t.id})
	if t.is_alive() and reaction and _has(u, "patient_eye"):
		GearFx._mark(s, t, 2, u)
		if _mk(u, "patient_eye") >= 2:
			for o in _foes_near(s, u, t.pos, 1, t):
				_tag(s, o, 2)
		s.emit({"type": "gear", "unit": u.id, "item": "patient_eye", "target": t.id})
	if t.is_alive() and _has(u, "volatile_spores") and GearFx.is_burning(s, t) and Infection.tier(u.infection) >= Infection.Tier.EXPOSED \
			and not _busy:
		_busy = true
		var amount: int = SPORE_DAMAGE[clampi(_mk(u, "volatile_spores"), 1, 2) - 1]
		t.status.erase("burning")
		s.emit({"type": "gear", "unit": u.id, "item": "volatile_spores", "target": t.id})
		for o in _foes_near(s, u, t.pos, 1, t):
			Rules.deal_damage(s, o, amount, u)
		_busy = false


## `t` was just set Burning by `u`.
static func on_ignite(s: GameState, u: Unit, t: Unit) -> void:
	if u != null and _has(u, "cinder_lens") and t.is_alive():
		GearFx._mark(s, t, 2 + (2 if _mk(u, "cinder_lens") >= 2 else 0), u)
		s.emit({"type": "gear", "unit": u.id, "item": "cinder_lens", "target": t.id})


## `t` was just Suppressed by `u` (any route).
static func on_suppressed(s: GameState, u: Unit, t: Unit) -> void:
	if _busy or u == null or not t.is_alive():
		return
	_busy = true
	if _has(u, "pressure_nozzle"):
		GearFx.ignite(s, u, t, _mk(u, "pressure_nozzle"))
		s.emit({"type": "gear", "unit": u.id, "item": "pressure_nozzle", "target": t.id})
	if _has(u, "cascade_rounds"):
		var r := 1 if _mk(u, "cascade_rounds") < 2 else 2
		for o in _foes_near(s, u, t.pos, r, t):
			GearFx._suppress(s, u, o)
			s.emit({"type": "gear", "unit": u.id, "item": "cascade_rounds", "target": o.id})
	_busy = false


## `u` killed `t` (GearFx.on_kill).
static func on_kill(s: GameState, u: Unit, t: Unit) -> void:
	if GearFx._dist(u.pos, t.pos) > GearFx.CLOSE or _busy:
		return
	_busy = true
	if _has(u, "flash_fry"):
		var r := 1 if _mk(u, "flash_fry") < 2 else 2
		for o in _foes_near(s, u, t.pos, r):
			GearFx.ignite(s, u, o, 1)
		s.emit({"type": "gear", "unit": u.id, "item": "flash_fry", "target": t.id})
	if _has(u, "kill_spill"):
		var dmg := int(u.status.get("link_dmg", 2))
		if _mk(u, "kill_spill") < 2:
			dmg = maxi(1, dmg / 2)
		for o in _foes_near(s, u, t.pos, 1):
			s.emit({"type": "gear", "unit": u.id, "item": "kill_spill", "target": o.id, "damage": dmg})
			Rules.deal_damage(s, o, dmg, u)
			break
	_busy = false


## `target` was damaged by `source` (GearFx.damage_taken).
static func on_hurt(s: GameState, target: Unit, source: Unit) -> void:
	if _busy or source == null or not source.is_alive() or not _has(target, "retaliation_plate"):
		return
	_busy = true
	GearFx._mark(s, source, 2, target)
	if _mk(target, "retaliation_plate") >= 2:
		GearFx._suppress(s, target, source)
	s.emit({"type": "gear", "unit": target.id, "item": "retaliation_plate", "target": source.id})
	_busy = false


## `u` purged `t` (GearFx.on_purge).
static func on_purge(s: GameState, u: Unit, t: Unit) -> void:
	if _busy or not _has(u, "serum_lance"):
		return
	_busy = true
	var mk2 := _mk(u, "serum_lance") >= 2
	for o in _foes_near(s, u, t.pos, 2 if mk2 else 1):
		_tag(s, o, 2)
		s.emit({"type": "gear", "unit": u.id, "item": "serum_lance", "target": o.id, "damage": LANCE_DAMAGE[1 if mk2 else 0]})
		Rules.deal_damage(s, o, LANCE_DAMAGE[1 if mk2 else 0], u)
	_busy = false


## `u` reloaded (GearFx.after_reload).
static func on_reload(s: GameState, u: Unit) -> void:
	if _has(u, "signal_drum"):
		for o in _nearest_visible(s, u, 1 if _mk(u, "signal_drum") < 2 else 2, 99):
			GearFx._mark(s, o, 2, u)
			s.emit({"type": "gear", "unit": u.id, "item": "signal_drum", "target": o.id})
	if _has(u, "ember_loader"):
		var mk2 := _mk(u, "ember_loader") >= 2
		for o in _nearest_visible(s, u, 9 if mk2 else 1, 3 if mk2 else 4):
			GearFx.ignite(s, u, o, 1)
			s.emit({"type": "gear", "unit": u.id, "item": "ember_loader", "target": o.id})
	if _has(u, "ready_stance"):
		u.overwatch = true
		u.status["ow_until"] = Combat.phase_index(s) + 2
		s.emit({"type": "gear", "unit": u.id, "item": "ready_stance"})


## The `n` nearest enemies `u` can see within `reach` tiles.
static func _nearest_visible(s: GameState, u: Unit, n: int, reach: int) -> Array[Unit]:
	var seen: Array[Unit] = []
	for o in s.living():
		if u.is_enemy_of(o) and GearFx._cheb(o.pos, u.pos) <= reach and Combat.can_see(s, u.pos, o.pos):
			seen.append(o)
	seen.sort_custom(func(a, b): return GearFx._dist(a.pos, u.pos) < GearFx._dist(b.pos, u.pos))
	return seen.slice(0, n)


## Cuts the cooldown on `u`'s Rank 2 signature by `n`.
static func cut_signature(s: GameState, u: Unit, n: int, item: String) -> void:
	var id := Signatures.for_class(u.kind)
	if id == "" or int(u.cooldowns.get(id, 0)) <= 0:
		return
	u.cooldowns[id] = maxi(0, int(u.cooldowns[id]) - n)
	s.emit({"type": "gear", "unit": u.id, "item": item})


## `u` killed `t`; `was_marked` says `t` was Marked when it died.
static func on_kill_signature(s: GameState, u: Unit, t: Unit, was_marked: bool) -> void:
	if was_marked and _has(u, "bounty_ledger"):
		cut_signature(s, u, _mk(u, "bounty_ledger"), "bounty_ledger")
	if _has(u, "blood_clock") and GearFx._dist(u.pos, t.pos) <= GearFx.CLOSE and int(u.status.get("clock_turn", -1)) != s.turn:
		u.status["clock_turn"] = s.turn
		cut_signature(s, u, _mk(u, "blood_clock"), "blood_clock")
