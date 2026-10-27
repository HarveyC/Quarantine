class_name Ammo
extends RefCounted
## Magazines. A soldier's gun holds a few rounds; every shot spends one, and a Reload (one
## action) puts the magazine back to full. A gun with no rounds can't shoot, overwatch or
## Suppress until it is reloaded. Every fight starts with full magazines.
## Pure rules. The round count lives in `unit.status["ammo"]` (set by `setup`); a unit without
## it (enemies, Lapsed or Turned soldiers, quick-match test units) never
## runs dry. The gun's size is `mag` in Weapons.TABLE; gear, perks, Grafts and mutations move it.
##
## Status keys owned here: "ammo" (rounds left), "ammo_free_turn" (turn the free reload was used).

const UNLIMITED := -1
const DEFAULT_MAG := 6
const SUPPRESS_ROUNDS := 2
const RELOAD_COST := 1
## Rounds the ammo levers add (see GearFx and Kit for the hooks that use them).
const EXTENDED_MAG := [2, 3]       # Extended mag, Mk I and Mk II
const SCAVENGER := [1, 2]          # rounds a kill gives back, Scavenger rounds Mk I and Mk II
const FRESH_AIM := 10              # Speed loader Mk II: aim on the shot after a reload
const BANDOLIER := 2
const BELT_FED := 4
const BONE_SHOT_INFECTION := 5


## True when `u` has a magazine to run dry.
static func tracked(u: Unit) -> bool:
	return u != null and u.status.has("ammo") and not u.ai_controlled


## Rounds left, or UNLIMITED.
static func rounds(u: Unit) -> int:
	return int(u.status["ammo"]) if tracked(u) else UNLIMITED


static func can_fire(u: Unit) -> bool:
	return not tracked(u) or int(u.status["ammo"]) > 0 or Kit.awake(u, "bone_magazine")


## Full magazine size right now: the gun's own plus everything that adds rounds.
static func mag_size(u: Unit) -> int:
	var n := Weapons.mag_of(u)
	n += GearFx.mag_bonus(u)
	n += Kit.mag_bonus(u)
	return maxi(1, n)


## Gives a mission soldier a full magazine. Call after gear, perks and Grafts are stamped.
## Enemies stay unlimited.
static func setup(u: Unit) -> void:
	if u.team != Types.Team.PLAYER or not UnitData.SOLDIERS.has(u.kind):
		return
	u.status["ammo"] = mag_size(u)


## Sets the magazine to its (possibly new) full size.
static func refill(u: Unit) -> void:
	if tracked(u):
		u.status["ammo"] = mag_size(u)


## Bone Magazine: a shot from an empty magazine is paid for in Infection.
static func bone_shot(s: GameState, u: Unit) -> void:
	if tracked(u) and int(u.status["ammo"]) <= 0 and Kit.awake(u, "bone_magazine"):
		Infection.add(s, u, BONE_SHOT_INFECTION)
		s.emit({"type": "perk", "unit": u.id, "perk": "bone_magazine"})


## Spends `n` rounds (never below 0). Returns the rounds actually spent.
static func spend(u: Unit, n: int = 1) -> int:
	if not tracked(u):
		return 0
	var had := int(u.status["ammo"])
	u.status["ammo"] = maxi(0, had - n)
	return had - int(u.status["ammo"])


## A kill that hands a round back (Scavenger rounds), up to a full magazine.
static func give(u: Unit, n: int = 1) -> int:
	if not tracked(u):
		return 0
	var had := int(u.status["ammo"])
	u.status["ammo"] = mini(mag_size(u), had + n)
	return int(u.status["ammo"]) - had


## Rounds a Suppress spends (Belt Fed spends none).
static func suppress_rounds(u: Unit) -> int:
	return 0 if Kit.has_perk(u, "belt_fed") else SUPPRESS_ROUNDS


## A kill with the gun: Scavenger rounds hand rounds back.
static func on_kill(s: GameState, u: Unit) -> void:
	if not tracked(u):
		return
	var back := GearFx.kill_rounds(u)
	if back > 0:
		var got := give(u, back)
		if got > 0:
			s.emit({"type": "gear", "unit": u.id, "item": "rounds_back", "ammo": rounds(u), "rounds": got})


## True when the next Reload costs no action (Speed loader once a turn, Shell Game perk).
static func reload_is_free(s: GameState, u: Unit) -> bool:
	if Kit.free_reload(u):
		return true
	return GearFx.free_reload(u) and int(u.status.get("ammo_free_turn", -1)) != s.turn


## "" if `u` may reload now, else why not.
static func reload_error(s: GameState, u: Unit) -> String:
	if not tracked(u):
		return "No magazine"
	if int(u.status["ammo"]) >= mag_size(u):
		return "Magazine is full"
	return ""


## A reload a perk gives for nothing (Walking Fire, Field Surgeon): refills the magazine and runs
## every reload hook, costing no action.
static func free_reload(s: GameState, u: Unit, why: String) -> void:
	if not tracked(u) or rounds(u) >= mag_size(u):
		return
	var had := int(u.status["ammo"])
	refill(u)
	s.emit({"type": "reload", "unit": u.id, "ammo": int(u.status["ammo"]), "mag": mag_size(u), "had": had, "free": true, "why": why})
	GearFx.after_reload(s, u, had)
	Kit.after_reload(s, u, had)


static func apply_reload(s: GameState, u: Unit) -> void:
	var free := reload_is_free(s, u)
	if free and not Kit.free_reload(u):
		u.status["ammo_free_turn"] = s.turn
	if not free:
		u.actions_left = maxi(0, u.actions_left - RELOAD_COST)
	var had := int(u.status["ammo"])
	refill(u)
	s.emit({"type": "reload", "unit": u.id, "ammo": int(u.status["ammo"]), "mag": mag_size(u), "had": had, "free": free})
	GearFx.after_reload(s, u, had)
	Kit.after_reload(s, u, had)
