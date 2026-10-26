class_name Signatures
extends RefCounted
## Rank 2 signature abilities: one cooldown ability per class, unlocked when a soldier reaches Rank 2.
## Each carries a gear tag (TAGS) so tag gear, mutations and the capstones build on it. Definitions
## live in ClassAbilities.ABILITIES (so the glossary, cards and hotkeys see them); the rules are here.
## OWNER: progression.

## Class -> signature ability id.
const OF_CLASS := {
	"trooper": "lockdown", "marksman": "deadeye", "medic": "quarantine_field", "breacher": "bring_down",
	"hazmat": "flashover", "vector": "vent", "reaper": "death_sweep", "warden": "provoke",
}
## The gear tags each signature counts as.
const TAGS := {
	"lockdown": ["Overwatch", "Suppress"], "deadeye": ["Mark"], "quarantine_field": ["Purge", "Guard"],
	"bring_down": ["Close"], "flashover": ["Burn"], "vent": ["Strain"],
	"death_sweep": ["Close", "Guard"], "provoke": ["Guard"],
}
const UNLOCK_RANK := 2

const DEADEYE_BONUS := 3
const BRING_DOWN_RANGE := 5
const BRING_DOWN_DAMAGE := 4
const BRING_DOWN_SPLASH := 2
const FIELD_RADIUS := 2
const FIELD_TURNS := 4   # phases: two full turns
const FIELD_HEAL := 1
const FIELD_AIM := 15
const FLASHOVER_DAMAGE := 4
const FLASHOVER_SPLASH := 2
const VENT_AMOUNT := 25
const VENT_MIN := 10
const VENT_RADIUS := 2
const VENT_BASE := 3
const SWEEP_DAMAGE := 3
const PROVOKE_DEFENSE := 20
const PROVOKE_BIAS := 1000.0


static func for_class(kind: String) -> String:
	return str(OF_CLASS.get(kind, ""))


static func is_signature(id: String) -> bool:
	return TAGS.has(id)


static func _active(s: GameState, u: Unit, key: String) -> bool:
	return u.is_alive() and u.status.has(key) and Combat.has_status(s, u, key)


# ---------------------------------------------------------------- validation

## Why `id` can't be used right now ("" if it can). Targets are checked by target_error.
static func extra_error(s: GameState, u: Unit, id: String) -> String:
	match id:
		"deadeye":
			if not Ammo.can_fire(u):
				return "Out of ammo"
		"flashover":
			if burning_targets(s, u).is_empty():
				return "Nothing is burning"
		"vent":
			if u.infection < VENT_MIN:
				return "Not enough Infection"
		"death_sweep":
			if adjacent_enemies(s, u).is_empty():
				return "No enemy adjacent"
	return ""


static func target_error(s: GameState, u: Unit, id: String, t: Unit) -> String:
	if not u.is_enemy_of(t):
		return "Not an enemy"
	if not Combat.visible_targets(s, u).has(t):
		return "No line of sight"
	if id == "bring_down" and Kit.cheb(u.pos, t.pos) > BRING_DOWN_RANGE:
		return "Too far"
	return ""


static func adjacent_enemies(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o in s.living():
		if u.is_enemy_of(o) and s.grid.melee_reach(u.pos, o.pos):
			out.append(o)
	return out


## Enemies in sight that are Burning or standing in fire.
static func burning_targets(s: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for t in Combat.visible_targets(s, u):
		if GearFx.is_burning(s, t) or Hazards.at(s, t.pos).get("kind", "") == "fire":
			out.append(t)
	return out


# ---------------------------------------------------------------- rules

static func apply(s: GameState, u: Unit, id: String, t: Unit) -> void:
	match id:
		"lockdown":
			u.overwatch = true
			u.status["ow_until"] = Combat.phase_index(s) + 2
			u.status["k_lockdown"] = Combat.phase_index(s) + 2
			Ammo.refill(u)
			s.emit({"type": "overwatch", "unit": u.id})
			s.emit({"type": "ability", "unit": u.id, "ability": id})
		"deadeye":
			_deadeye(s, u, t)
		"quarantine_field":
			u.status["k_field"] = Combat.phase_index(s) + FIELD_TURNS
			u.status["k_field_pos"] = u.pos
			s.emit({"type": "ability", "unit": u.id, "ability": id, "radius": FIELD_RADIUS})
		"bring_down":
			_bring_down(s, u, t)
		"flashover":
			_flashover(s, u)
		"vent":
			_vent(s, u)
		"death_sweep":
			_death_sweep(s, u)
		"provoke":
			u.status["k_provoke"] = Combat.phase_index(s) + 2
			s.emit({"type": "ability", "unit": u.id, "ability": id})


## A shot that never misses, ignores cover and hits for +3. It Marks, so Mark gear and Warrant apply.
static func _deadeye(s: GameState, u: Unit, t: Unit) -> void:
	var dmg := s.rng.randi_range(u.damage.x, u.damage.y) + DEADEYE_BONUS
	dmg = Kit.shot_damage(s, u, t, dmg)
	dmg = GearFx.shot_damage(s, u, t, dmg, false)
	u.status.erase("suppressed")
	Ammo.spend(u)
	s.emit({"type": "ability", "unit": u.id, "ability": "deadeye", "target": t.id})
	s.emit({"type": "shot", "unit": u.id, "target": t.id, "hit": true, "graze": false, "crit": false,
		"damage": dmg, "chance": 100, "reaction": false, "ammo": Ammo.rounds(u)})
	t.status["tagged"] = Combat.phase_index(s) + (2 if s.phase != Types.Phase.ENEMY else 3)
	GearFx.on_marked(s, u, t)
	Rules.deal_damage(s, t, dmg, u)
	GearFx.after_shot(s, u, t, true, false, dmg)


## Brings the target's cover down and the roof with it: 4 to the target, 2 to enemies next to it.
static func _bring_down(s: GameState, u: Unit, t: Unit) -> void:
	s.emit({"type": "ability", "unit": u.id, "ability": "bring_down", "target": t.id, "hit": true,
		"damage": BRING_DOWN_DAMAGE})
	var cover := Destruction.cover_cells(s.grid, t.pos, u.pos)
	var near: Array[Unit] = []
	for o in s.living():
		if o != t and u.is_enemy_of(o) and Kit.cheb(o.pos, t.pos) == 1:
			near.append(o)
	Rules.deal_damage(s, t, BRING_DOWN_DAMAGE, u)
	for o in near:
		if o.is_alive() and s.phase != Types.Phase.ENDED:
			Rules.deal_damage(s, o, BRING_DOWN_SPLASH, u)
	if s.phase != Types.Phase.ENDED:
		var hits := {}
		for c in cover:
			hits[c] = 1
		var blast := Destruction.pattern(s.grid, t.pos, Destruction.SHAPED)
		for c in blast:
			hits[c] = maxi(int(hits.get(c, 0)), int(blast[c]))
		Destruction.hit(s, hits, u)


## Burning enemies in sight erupt and the fire is spent. Wildfire fire ignores armour and spreads.
static func _flashover(s: GameState, u: Unit) -> void:
	var lit := burning_targets(s, u)
	s.emit({"type": "ability", "unit": u.id, "ability": "flashover",
		"units": lit.map(func(x: Unit) -> int: return x.id), "damage": FLASHOVER_DAMAGE})
	var wild := GearFx.has_capstone(u, "Burn")
	var fire_cells: Array = []
	for t in lit:
		if t.is_alive():
			fire_cells.append(t.pos)
	for t in lit:
		if not t.is_alive() or s.phase == Types.Phase.ENDED:
			continue
		t.status.erase("burning")
		GearFx.fire_damage(s, t, FLASHOVER_DAMAGE, wild)
		for o in s.living():
			if o != t and not lit.has(o) and u.is_enemy_of(o) and Kit.cheb(o.pos, t.pos) == 1 and s.phase != Types.Phase.ENDED:
				GearFx.fire_damage(s, o, FLASHOVER_SPLASH, wild)
				if wild and o.is_alive():
					GearFx.ignite(s, u, o, GearFx.WILDFIRE_TURNS)
	Hazards.remove(s, fire_cells, "fire")


## Pushes 25 of the Vector's own Infection out as a spore burst. Enemies near take more at higher tiers.
static func _vent(s: GameState, u: Unit) -> void:
	var amount := mini(VENT_AMOUNT, u.infection)
	var dmg := VENT_BASE + mini(Infection.tier(u.infection), Infection.Tier.CRITICAL)
	var hit: Array[Unit] = []
	for o in s.living():
		if u.is_enemy_of(o) and Kit.cheb(o.pos, u.pos) <= VENT_RADIUS:
			hit.append(o)
	s.emit({"type": "ability", "unit": u.id, "ability": "vent", "radius": VENT_RADIUS,
		"units": hit.map(func(x: Unit) -> int: return x.id), "damage": dmg, "amount": amount})
	Infection.add(s, u, -amount)
	for o in hit:
		if o.is_alive() and s.phase != Types.Phase.ENDED:
			Rules.deal_damage(s, o, dmg, u)
	var cells: Array[Vector2i] = []
	for d in Grid.DIRS8:
		var c: Vector2i = u.pos + d
		if s.grid.in_bounds(c) and not s.grid.blocks_los(c):
			cells.append(c)
	Hazards.add(s, cells, "spore", 2, u.id, u.team)


## Cuts every adjacent enemy for 3 and leaves them bleeding. Any kill resets Lunge and gives an action back.
static func _death_sweep(s: GameState, u: Unit) -> void:
	var foes := adjacent_enemies(s, u)
	s.emit({"type": "ability", "unit": u.id, "ability": "death_sweep",
		"units": foes.map(func(x: Unit) -> int: return x.id), "damage": SWEEP_DAMAGE})
	var killed := false
	for t in foes:
		if not u.is_alive() or s.phase == Types.Phase.ENDED:
			break
		Rules.deal_damage(s, t, SWEEP_DAMAGE, u)
		if t.is_alive():
			t.status["k_bleed"] = ClassAbilities.BLEED_TURNS
			t.status["k_bleed_by"] = u.id
			s.emit({"type": "bleeding", "unit": t.id, "turns": ClassAbilities.BLEED_TURNS})
		else:
			killed = true
			ClassAbilities._after_melee_kill(s, u, t)
	if killed and u.is_alive():
		u.cooldowns.erase("lunge")
		u.actions_left += 1


# ---------------------------------------------------------------- hooks (called from Kit)

## Lockdown: overwatch that survives every shot, and pins whoever it shoots.
static func keeps_overwatch(s: GameState, w: Unit) -> bool:
	return _active(s, w, "k_lockdown")


static func after_reaction(s: GameState, w: Unit, mover: Unit) -> void:
	if _active(s, w, "k_lockdown") and mover.is_alive():
		mover.status["suppressed"] = Combat.phase_index(s) + 2
		mover.overwatch = false
		GearFx.on_suppress(s, w, mover)


## The Quarantine Field (if any) of a living soldier that covers `cell`.
static func field_over(s: GameState, cell: Vector2i, team: int) -> Unit:
	for v in s.living(team):
		if _active(s, v, "k_field") and Kit.cheb(v.status.get("k_field_pos", v.pos), cell) <= FIELD_RADIUS:
			return v
	return null


## Start of the squad's turn: soldiers inside a field heal.
static func on_team_phase_start(s: GameState) -> void:
	for u in s.living(Types.Team.PLAYER):
		if Kit.is_soldier(u) and u.hp < u.max_hp and field_over(s, u.pos, Types.Team.PLAYER) != null:
			Kit._heal(s, u, FIELD_HEAL, "quarantine_field")


static func field_blocks_infection(s: GameState, u: Unit) -> bool:
	return field_over(s, u.pos, u.team) != null


## Aim an enemy loses while it stands in a Quarantine Field.
static func field_aim_penalty(s: GameState, attacker: Unit) -> int:
	if attacker.team == Types.Team.PLAYER:
		return 0
	return FIELD_AIM if field_over(s, attacker.pos, Types.Team.PLAYER) != null else 0


static func provoking(s: GameState, t: Unit) -> bool:
	return _active(s, t, "k_provoke")
