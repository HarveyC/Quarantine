class_name LanternEchoes
extends RefCounted
## The Act 3 boss fight "the Lantern Echoes". The Source raises Lantern Company's dead: one Echo per
## soldier in the squad, each wearing that soldier's class and using its Suppress, Overwatch,
## Hunker and signature, never its items. Three phases:
##   1 Formation: the Echoes advance together and fight with the squad's own kit. The Last Echo
##     waits on the dais behind them and cannot be hurt while any Echo stands.
##   2 Taken (the first Echo falls): every Echo that falls collapses into spores, and the Source
##     takes its body for a Taken husk. Each husk alive pulses Infection through the squad.
##   3 The Last Echo (no Echo left): the husks collapse into spores and the Last Echo takes the
##     shape of the lowest HP soldier, using that soldier's class, Suppress and signature.
## Encounter, EnemyBehaviours and FightBuilder call in here. OWNER: enemies workstream.

## Boss HP as a share of its 30, by squad size (FightBuilder, instead of SQUAD_BOSS_HEALTH).
const HEALTH := {1: 0.6, 2: 0.8, 3: 1.0, 4: 1.2}
## An Echo's HP as a multiple of its class's, and its hits as a share of damage, by squad size.
const ECHO_HP := {1: 1.2, 2: 1.3, 3: 1.45, 4: 1.6}
const ECHO_DAMAGE := {1: 0.6, 2: 0.65, 3: 0.75, 4: 0.85}
const ECHO_AIM := 5
## Infection a Taken husk pulses through every soldier each enemy phase, per husk alive.
const TAKEN_PULSE := {1: 1, 2: 2, 3: 2, 4: 3}
const SPORE_TURNS := 3
const HUNKER_GAP := 3                  # a hurt Echo hunkers one turn in three (staggered by id)
## The Last Echo's stats once it wears a soldier's shape.
const LAST_MOBILITY := 5
const GAZE_DAMAGE := Vector2i(1, 2)    # what it fires from the dais while its Echoes stand


# --- setup ---------------------------------------------------------------------------------

## Raises one Echo per soldier of the squad (classes cycle through the soldiers on the field).
static func setup(s: GameState, boss: Unit, squad: int) -> void:
	boss.status["alerted"] = true
	boss.damage = GAZE_DAMAGE
	var soldiers := s.living(Types.Team.PLAYER)
	var spawns: Array[Vector2i] = []
	spawns.assign(s.grid.enemy_spawns)
	var step := maxi(1, spawns.size() / maxi(squad, 1))
	for i in squad:
		var model: Unit = soldiers[i % soldiers.size()] if not soldiers.is_empty() else null
		var kind: String = model.kind if model != null else "trooper"
		var who: String = model.display_name if model != null else UnitData.SOLDIERS[kind].name
		var cell: Vector2i = spawns[(i * step) % spawns.size()] if not spawns.is_empty() else boss.pos + Vector2i(i - 1, 3)
		make_echo(s, kind, who, cell, squad)


static func make_echo(s: GameState, kind: String, who: String, cell: Vector2i, squad: int) -> Unit:
	var u := UnitData.make(kind, Types.Team.ENEMY)
	u.owner_player = -1
	u.status["turned"] = true
	u.status["alerted"] = true
	u.status["lantern_echo"] = true
	u.infection = 100
	u.max_hp = maxi(1, roundi(u.max_hp * float(ECHO_HP[squad])))
	u.hp = u.max_hp
	u.aim += ECHO_AIM
	u.display_name = "Echo %s" % who
	_learn_signature(u, kind)
	s.add_unit(u, Encounter.free_cell(s, cell))
	return u


## The Echo's class signature joins its class ability (the Rank 3 unlock, copied; no items).
static func _learn_signature(u: Unit, kind: String) -> void:
	var sig := Signatures.for_class(kind)
	if sig != "" and not u.abilities.has(sig):
		u.abilities.append(sig)


static func echoes(s: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in s.living(Types.Team.ENEMY):
		if u.status.get("lantern_echo", false):
			out.append(u)
	return out


static func taken(s: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in s.living(Types.Team.ENEMY):
		if u.status.get("taken", false):
			out.append(u)
	return out


static func boss_of(s: GameState) -> Unit:
	for u in s.living(Types.Team.ENEMY):
		if u.kind == "lantern_echoes":
			return u
	return null


# --- damage and phases ---------------------------------------------------------------------

## The Last Echo cannot be hurt while an Echo stands.
static func clamp_damage(s: GameState, u: Unit, amount: int, source: Unit) -> int:
	if int(u.status.get("boss_phase", 1)) < 3 and not echoes(s).is_empty():
		s.emit({"type": "immune", "unit": u.id, "source": source.id if source else -1, "reason": "echoes"})
		return 0
	return amount


## An Echo's hits on soldiers, scaled for the squad.
static func scale_hit(s: GameState, source: Unit, amount: int) -> int:
	if source == null or not source.status.get("lantern_echo", false):
		return amount
	return maxi(1, roundi(amount * float(ECHO_DAMAGE[_squad(s)])))


static func on_died(s: GameState, u: Unit) -> void:
	if not u.status.get("lantern_echo", false) or s.encounter.get("over", false):
		return
	var boss := boss_of(s)
	_fall(s, u, boss)
	if boss == null or s.phase == Types.Phase.ENDED:
		return
	var left := echoes(s).size()
	if left == 0:
		_last_echo(s, boss)
		return
	if int(boss.status.get("boss_phase", 1)) == 1:
		boss.status.boss_phase = 2
		s.emit({"type": "boss_phase", "unit": boss.id, "phase": 2, "boss": boss.kind,
			"text": "The Source takes %s!" % u.display_name})
	if not s.encounter.has("taken_queue"):
		s.encounter["taken_queue"] = []
	s.encounter.taken_queue.append({"cell": u.pos, "name": u.display_name.trim_prefix("Echo ")})


## A fallen Echo (or husk) collapses into spores where it stood.
static func _fall(s: GameState, u: Unit, boss: Unit) -> void:
	s.emit({"type": "echo_fell", "unit": u.id, "cell": u.pos, "name": u.display_name})
	Encounter.add_spores(s, EnemyAbilities.square(s.grid, u.pos, 1), SPORE_TURNS, boss)


## The last Echo is down: the husks fall to spores and the Last Echo wears the weakest soldier.
static func _last_echo(s: GameState, boss: Unit) -> void:
	if int(boss.status.get("boss_phase", 1)) >= 3:
		return
	boss.status.boss_phase = 3
	s.encounter["taken_queue"] = []
	for t in taken(s):
		t.hp = 0
		s.emit({"type": "died", "unit": t.id})
		_fall(s, t, boss)
	var model := weakest_soldier(s)
	var kind := "trooper"
	var who := ""
	if model != null:
		kind = model.kind
		who = model.display_name
	var stats: Dictionary = UnitData.SOLDIERS[kind]
	boss.status["mirror"] = kind
	boss.display_name = "Echo %s, the Last" % who if who != "" else "The Last Echo"
	boss.aim = int(stats.aim) + 10
	boss.damage = Vector2i(stats.damage[0], stats.damage[1])
	boss.mobility = maxi(LAST_MOBILITY, int(stats.mobility))
	boss.abilities.assign(stats.abilities)
	_learn_signature(boss, kind)
	boss.cooldowns.clear()
	s.emit({"type": "boss_phase", "unit": boss.id, "phase": 3, "boss": boss.kind,
		"hp": boss.hp, "max_hp": boss.max_hp,
		"text": "The Last Echo takes %s's shape!" % who if who != "" else "The Last Echo rises!"})


## The soldier with the least HP (most Infection breaks a tie): the one the Last Echo mirrors.
static func weakest_soldier(s: GameState) -> Unit:
	var best: Unit = null
	for u in s.living(Types.Team.PLAYER):
		if best == null or u.hp < best.hp or (u.hp == best.hp and u.infection > best.infection):
			best = u
	return best


## Enemy phase start: the Source takes the bodies of the fallen, then every husk pulses Infection.
static func on_enemy_phase_start(s: GameState) -> void:
	var boss := boss_of(s)
	if boss == null:
		return
	var queue: Array = s.encounter.get("taken_queue", [])
	s.encounter["taken_queue"] = []
	for q in queue:
		if int(boss.status.get("boss_phase", 1)) >= 3:
			break
		var husk := Encounter.spawn(s, "fallen", q.cell, boss)
		husk.display_name = "Taken %s" % q.name
		husk.status["taken"] = true
		husk.status["turned"] = true
		Encounter.frenzy(s, husk)
		s.emit({"type": "echo_taken", "unit": husk.id, "boss": boss.id, "name": husk.display_name})
	var husks := taken(s)
	if husks.is_empty():
		return
	var amount: int = int(TAKEN_PULSE[_squad(s)]) * husks.size()
	var hit: Array[int] = []
	for u in s.living(Types.Team.PLAYER):
		hit.append(u.id)
	s.emit({"type": "source_pulse", "unit": boss.id, "units": hit, "amount": amount})
	for id in hit:
		Infection.add(s, s.get_unit(id), amount)


static func _squad(s: GameState) -> int:
	return clampi(int(s.encounter.get("squad", 4)), 1, 4)


# --- turns ---------------------------------------------------------------------------------

## True while the Last Echo is scripted (it fires from the dais); once it wears a shape it plays
## like any Echo.
static func scripted(u: Unit) -> bool:
	return u.kind == "lantern_echoes" and int(u.status.get("boss_phase", 1)) < 3


## The Last Echo's turn on the dais: it fires at whoever the dais sees, else watches the nave.
static func boss_turn(s: GameState, u: Unit) -> void:
	for step in 2:
		if u.actions_left <= 0 or not u.is_alive() or s.phase == Types.Phase.ENDED:
			return
		var shot := EnemyAI._best_shot(s, u)
		var action: Dictionary = shot.action if not shot.is_empty() else EnemyAI._check(s, {"type": Types.OVERWATCH, "unit": u.id})
		if action.is_empty() or not Rules.apply(s, action):
			return


## Echoes and the mirrored Last Echo fight with the class they wear.
static func choose(s: GameState, u: Unit, hostiles: Array[Unit]) -> Dictionary:
	if u.hp * 2 <= u.max_hp and (s.turn + u.id) % HUNKER_GAP == 0:
		var hunker := EnemyAI._check(s, {"type": Types.HUNKER, "unit": u.id})
		if not hunker.is_empty():
			return hunker
	for id in _kit(u):
		var use := _use(s, u, id, hostiles)
		if not use.is_empty():
			return use
	return EnemyBehaviours.cover_shooter(s, u, hostiles)


## Signature first, then the class ability.
static func _kit(u: Unit) -> Array[String]:
	var out: Array[String] = []
	var sig := Signatures.for_class(str(u.status.get("mirror", u.kind)))
	if sig != "" and u.abilities.has(sig):
		out.append(sig)
	for id in u.abilities:
		if id != sig and id in ["tag", "suppress", "stim", "breach", "incinerate", "siphon"]:
			out.append(id)
	return out


## A valid action using ability `id` where it is worth spending, or {}.
static func _use(s: GameState, u: Unit, id: String, hostiles: Array[Unit]) -> Dictionary:
	if int(u.cooldowns.get(id, 0)) > 0:
		return {}
	var base := {"type": Types.ABILITY, "unit": u.id, "ability": id}
	var def: Dictionary = ClassAbilities.ABILITIES.get(id, Combat.ABILITIES.get(id, {}))
	if def.is_empty():
		return {}
	var near := false
	for h in hostiles:
		near = near or Kit.cheb(u.pos, h.pos) <= 2
	match id:
		"stim":
			var hurt: Unit = null
			for o in s.living(u.team):
				if o.hp < o.max_hp and Kit.cheb(u.pos, o.pos) <= 1 and (hurt == null or o.hp < hurt.hp):
					hurt = o
			if hurt == null:
				return {}
			base["target"] = hurt.id
			return EnemyAI._check(s, base)
		"siphon":
			return {}   # it would drain its own side
		"vent":
			if not near:
				return {}
		"quarantine_field", "provoke", "lockdown":
			var seen := false
			for h in hostiles:
				seen = seen or (Kit.cheb(u.pos, h.pos) <= 7 and Combat.can_see(s, u.pos, h.pos))
			if not seen:
				return {}
			if id == "quarantine_field" and not _ally_hurt_near(s, u):
				return {}
		"death_sweep":
			if not near:
				return {}
	match str(def.get("targeting", "none")):
		"none":
			return EnemyAI._check(s, base)
		"unit":
			var best := {}
			var best_score := -INF
			for h in hostiles:
				var a := base.duplicate()
				a["target"] = h.id
				var score := EnemyAI._target_score(s, u, h, u.pos)
				if score > best_score:
					var ok := EnemyAI._check(s, a)
					if not ok.is_empty():
						best = ok
						best_score = score
			return best
		"cell":
			for h in hostiles:
				var a := base.duplicate()
				a["cell"] = h.pos
				var ok := EnemyAI._check(s, a)
				if not ok.is_empty():
					return ok
	return {}


static func _ally_hurt_near(s: GameState, u: Unit) -> bool:
	for o in s.living(u.team):
		if o.hp < o.max_hp and Kit.cheb(u.pos, o.pos) <= 2:
			return true
	return false
