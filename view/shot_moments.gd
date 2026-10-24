extends RefCounted
## Which shots and strikes earn the shot camera. Most of a fight plays on the tactical
## camera; the over-the-shoulder cut is saved for the moments worth watching. Pure rules on
## a few facts about the shot (EventPlayer gathers them from the event and what follows it),
## so they are easy to test and identical on every peer.
##
## Facts: squad (the shooter is one of ours, not an enemy or a Turned soldier), hit, crit,
## kill, last_enemy (the kill ends the enemy side), boss_target, boss_shooter, soldier_target,
## dist (tiles), high_ground (shooting down from a perch), chance (to hit, 0 when unknown).
## `moment` returns why the shot is epic ("kill", "crit", ...), or "" when it is not.

const LONG_SHOT := 10.0      # tiles
const PERCH_SHOT := 6.0      # tiles, shooting down from high ground
const LONG_ODDS := 35        # hitting at this chance or lower


static func moment(f: Dictionary) -> String:
	if not f.get("hit", false):
		return ""
	var kill: bool = f.get("kill", false)
	if not f.get("squad", false):
		# Enemies and Turned soldiers: a soldier going down, a crit on one, or the boss landing a blow.
		if kill and f.get("soldier_target", false):
			return "soldier_down"
		if f.get("boss_shooter", false):
			return "boss"
		if f.get("crit", false) and f.get("soldier_target", false):
			return "crit"
		return ""
	if kill and f.get("last_enemy", false):
		return "last_enemy"
	if kill:
		return "kill"
	if f.get("crit", false):
		return "crit"
	if f.get("boss_target", false):
		return "boss"
	var dist := float(f.get("dist", 0.0))
	if dist >= LONG_SHOT:
		return "long_shot"
	if f.get("high_ground", false) and dist >= PERCH_SHOT:
		return "high_ground"
	var chance := int(f.get("chance", 0))
	if chance > 0 and chance <= LONG_ODDS:
		return "long_odds"
	return ""
