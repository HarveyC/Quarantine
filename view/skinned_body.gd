extends RefCounted
## Drives a skinned character (assets/characters, built by tools/build_characters.py):
## clips from the Quaternius Universal Animation Library, picked from the unit view's
## animation state, crossfaded, and advanced by hand from `tick` so slow motion in a shot
## cinematic slows them too.
##
## Armed units carry their weapon on its own "gun" bone under the chest. After each
## advance the weapon is posed procedurally (low ready to shouldered, recoil kick) and
## both arms are bent by two-bone IK so the hands stay on the grip and the support grip,
## whatever the legs and torso are playing.

const LIBS: Array[PackedScene] = [
	preload("res://assets/characters/anims_ual1.glb"),
	preload("res://assets/characters/anims_ual2.glb"),
]
## Clips per pose (the importer drops the "_Loop" suffix and sets those clips looping).
const SOLDIER := {
	"idle": "Idle", "walk": "Jog_Fwd", "aim": "Idle", "crouch": "Crouch_Idle",
	"hit": "Hit_Chest", "death": "Death01", "melee": "Punch_Cross", "throw": "OverhandThrow",
	"call": "Idle_Rail_Call",
}
const FERAL := {
	"idle": "Zombie_Idle", "walk": "Zombie_Walk_Fwd", "aim": "Zombie_Idle", "crouch": "Crouch_Idle",
	"shoot": "Spell_Simple_Shoot", "hit": "Hit_Chest", "death": "Death01",
	"melee": "Zombie_Scratch", "throw": "OverhandThrow", "call": "Consume",
}
## Melee classes (view/melee_kit.gd) hold no rifle: the clips pose the arms, with a
## one-handed pistol stance to shoot, a strike or a shield bash for melee and (the
## Warden) a shield-up guard stance.
const MELEE := {
	"reaper": {"aim": "Pistol_Aim_Neutral", "shoot": "Pistol_Shoot", "melee": "Punch_Cross"},
	"warden": {"aim": "Pistol_Aim_Neutral", "shoot": "Pistol_Shoot", "melee": "Shield_OneShot", "guard": "Idle_Shield"},
}
## Single-pose clips used as base loops (they would otherwise stop after one play).
const HELD := ["Pistol_Aim_Neutral", "Pistol_Idle", "Idle_Shield"]
## Warden aiming: where the shield hand is held (character space, riding the chest).
const SHIELD_BRACE := Vector3(-0.02, 1.08, 0.34)
const FADE := 0.18
## Weapon grip in character space (+Z forward, right hand at -X): shouldered and aimed,
## and at low ready (muzzle down and across the body).
const GUN_AIM := Transform3D(Basis.IDENTITY, Vector3(-0.1, 1.37, 0.24))
## Aiming blades the chest (left shoulder forward) so the off hand reaches the fore-end.
const AIM_TWIST := -0.42
static var GUN_LOW := Transform3D(Basis.from_euler(Vector3(0.65, 0.75, -0.35)), Vector3(-0.1, 1.1, 0.24))

static var _library: AnimationLibrary

var player: AnimationPlayer
var skel: Skeleton3D
var clips := SOLDIER
var speed := 1.0          # walk cycle rate (fast movers run their loop quicker)
var armed := false        # has a gun bone to pose and hold
var melee := ""           # a melee class's kind: no rifle, its own clips
var _calm := SOLDIER      # clips while not Turned
var _base := ""
var _shot := ""           # a one-shot playing over the base loop
var _shot_left := 0.0
var _dying := false
var _bones := {}          # name -> index, for IK and sockets


## Puts an AnimationPlayer on `model` (the imported character scene).
## Unarmed enemies lurch with the infected clips; the armed (turned snipers, Hale) and
## the squad move like soldiers.
func setup(model: Node3D, enemy: bool) -> void:
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var own := model.find_children("*", "AnimationPlayer", true, false)
	if not own.is_empty():
		# a creature on its own rig, with its own clips
		player = own[0]
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		clips = creature_clips(player)
		play_base("idle")
		return
	player = AnimationPlayer.new()
	player.name = "Anim"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.add_child(player)
	player.add_animation_library("", library())
	for b in ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "gun", "support", "muzzle", "Head", "spine_03"]:
		_bones[b] = skel.find_bone(b)
	armed = _bones.gun >= 0 and _bones.support >= 0
	melee = str(model.get_meta("melee", ""))
	if MELEE.has(melee):
		armed = false
		_calm = SOLDIER.merged(MELEE[melee], true)
	clips = FERAL if enemy and not armed and melee == "" else _calm
	play_base("idle")


## Turned soldiers lurch like the infected.
func set_feral(on: bool) -> void:
	armed = armed and not on    # the rifle hangs forgotten
	clips = FERAL if on else _calm
	var pose := _base
	_base = ""
	play_base(_pose_of(pose))


## Pose -> clip for a creature's own clips ("..._Idle", "..._Walk", "..._Attack", ...).
static func creature_clips(ap: AnimationPlayer) -> Dictionary:
	var out := {}
	var by := {"_Idle": ["idle", "aim", "crouch"], "_Walk": ["walk"], "_Run": ["walk"], "_Attack": ["melee", "shoot"],
		"_Death": ["death"], "_Jump": ["leap"]}
	for nm in ap.get_animation_list():
		for suffix in by:
			if String(nm).ends_with(suffix):
				for pose in by[suffix]:
					if not out.has(pose) or suffix == "_Walk":
						out[pose] = nm
				if suffix in ["_Idle", "_Walk", "_Run"]:
					ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	return out


func _pose_of(clip: String) -> String:
	for k in _calm:
		if _calm[k] == clip or FERAL.get(k, "") == clip:
			return k
	return "idle"


## All clips from the animation libraries, with position tracks kept only for the root
## and pelvis so they fit any body's proportions.
static func library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	for scene in LIBS:
		var root := scene.instantiate()
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		for nm in ap.get_animation_list():
			var a: Animation = ap.get_animation(nm).duplicate(true)
			for t in range(a.get_track_count() - 1, -1, -1):
				var bone := String(a.track_get_path(t)).get_slice(":", 1)
				if a.track_get_type(t) == Animation.TYPE_SCALE_3D:
					a.remove_track(t)
				elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and bone not in ["root", "pelvis"]:
					a.remove_track(t)
			if nm in HELD:
				a.loop_mode = Animation.LOOP_LINEAR
			_library.add_animation(nm, a)
		root.free()
	return _library


func has_clip(pose: String) -> bool:
	return clips.has(pose) and player.has_animation(clips[pose])


## Switches the looping pose (idle / walk / aim / crouch).
func play_base(pose: String) -> void:
	var clip: String = clips.get(pose, clips.get("idle", ""))
	if clip == _base or _dying:
		return
	_base = clip
	if _shot == "":
		player.play(clip, FADE)


## Plays a one-shot (shoot / hit / melee / throw), then fades back to the base loop.
func play_once(pose: String, rate := 1.0) -> void:
	if _dying or not has_clip(pose):
		return
	_shot = clips[pose]
	player.play(_shot, 0.08, rate)
	player.seek(0.0, false)
	_shot_left = player.current_animation_length / rate - FADE


## Death clips per style: "collapse" crumples and falls (the rig's own death clip),
## "knockdown" is blown off the feet by a heavy hit. Seconds into each clip when the body
## hits the floor; clips not listed land just past half way.
const DEATH_CLIPS := {"knockdown": "Hit_Knockback"}
const LAND_AT := {"Death01": 0.95, "Hit_Knockback": 0.3, "SpiderArmature|Spider_Death": 0.5}


## Death: plays a death clip from its start, advanced by `advance` like any other clip (so
## slow motion slows the fall), holding the last frame with the body on the floor.
## Returns the seconds until the body lands at `rate`, or 0 if it has no death clip.
func start_death(style := "collapse", rate := 1.0) -> float:
	var clip: String = DEATH_CLIPS.get(style, "")
	if clip == "" or not player.has_animation(clip):
		clip = clips.get("death", "")
	if clip == "" or not player.has_animation(clip):
		return 0.0
	_dying = true
	_shot = ""
	armed = false
	player.play(clip, 0.06, rate)
	player.seek(0.0, true)
	var length := player.get_animation(clip).length
	return float(LAND_AT.get(clip, length * 0.55)) / rate


## `aim` 0..1 from low ready to shouldered; `recoil` 0..1 kicks the weapon back.
func advance(delta: float, aim := 0.0, recoil := 0.0) -> void:
	if _shot != "":
		_shot_left -= delta
		if _shot_left <= 0.0:
			_shot = ""
			if not _dying:
				player.play(_base, FADE)
	if _dying:
		player.advance(delta)
		return
	var rate := speed if _base == clips.walk and _shot == "" else 1.0
	player.advance(delta * rate)
	if melee == "warden" and aim > 0.3 and _shot != clips.get("melee", ""):
		# the revolver is one-handed: the shield stays braced low across the body
		_reach("l", SHIELD_BRACE + _global(_bones.spine_03).origin - skel.get_bone_global_rest(_bones.spine_03).origin, Vector3(1.0, -0.4, 0.2))
	if armed:
		_pose_gun(aim, recoil)
		_reach("r", bone_pose("gun").origin, Vector3(-1.0, -1.0, -0.3))
		_reach("l", bone_pose("support").origin, Vector3(1.0, -1.0, -0.2))


## Skeleton-space transform of a bone (or socket bone such as "muzzle").
func bone_pose(bone: String) -> Transform3D:
	var i: int = _bones.get(bone, skel.find_bone(bone))
	return _global(i) if i >= 0 else Transform3D.IDENTITY


## Skeleton-space pose composed from the local poses. The skeleton's own global pose
## cache only refreshes on its deferred update, which would leave the IK a frame behind.
func _global(i: int) -> Transform3D:
	var t := skel.get_bone_pose(i)
	var p := skel.get_bone_parent(i)
	while p >= 0:
		t = skel.get_bone_pose(p) * t
		p = skel.get_bone_parent(p)
	return t


## Places the weapon between low ready and aimed; it rides the chest's bob and crouch.
func _pose_gun(aim: float, recoil: float) -> void:
	var spine: int = _bones.spine_03
	var twist := AIM_TWIST * clampf(aim, 0.0, 1.0)
	if twist != 0.0:
		var g_spine := _global(spine)
		var parent := _global(skel.get_bone_parent(spine))
		var turned := Basis(Vector3.UP, twist) * g_spine.basis
		skel.set_bone_pose_rotation(spine, (parent.basis.inverse() * turned).get_rotation_quaternion())
	var chest := _global(spine)
	var g := GUN_LOW.interpolate_with(GUN_AIM, clampf(aim, 0.0, 1.0))
	g.origin += chest.origin - skel.get_bone_global_rest(spine).origin
	g.origin.z -= recoil * 0.07
	g.basis = g.basis * Basis(Vector3.RIGHT, -recoil * 0.22)
	var local := chest.affine_inverse() * g
	skel.set_bone_pose_position(_bones.gun, local.origin)
	skel.set_bone_pose_rotation(_bones.gun, local.basis.get_rotation_quaternion())


## Two-bone IK on one arm: bend the upper arm and forearm so the hand lands on `target`
## (skeleton space), the elbow bending towards `pole`; the wrist is kept straight.
func _reach(side: String, target: Vector3, pole: Vector3) -> void:
	var up: int = _bones["upperarm_" + side]
	var lo: int = _bones["lowerarm_" + side]
	var hand: int = _bones["hand_" + side]
	if up < 0 or lo < 0 or hand < 0:
		return
	skel.set_bone_pose_rotation(hand, skel.get_bone_rest(hand).basis.get_rotation_quaternion())
	var g_up := _global(up)
	var g_lo := _global(lo)
	var g_hand := _global(hand)
	var a := g_up.origin
	var l1 := a.distance_to(g_lo.origin)
	var l2 := g_lo.origin.distance_to(g_hand.origin)
	var to := target - a
	if to.length() < 0.001:
		return
	var dir := to.normalized()
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.DOWN
	bend = bend.normalized()
	var e := a + (dir * cos_a + bend * sqrt(1.0 - cos_a * cos_a)) * l1
	var parent := _global(skel.get_bone_parent(up))
	var new_up := Transform3D(_turn(g_lo.origin - a, e - a) * g_up.basis, a)
	skel.set_bone_pose_rotation(up, (parent.basis.inverse() * new_up.basis).get_rotation_quaternion())
	var new_lo := new_up * skel.get_bone_pose(lo)
	var hand_now := new_lo * skel.get_bone_pose(hand).origin
	var fixed := _turn(hand_now - new_lo.origin, a + dir * d - new_lo.origin) * new_lo.basis
	skel.set_bone_pose_rotation(lo, (new_up.basis.inverse() * fixed).get_rotation_quaternion())


static func _turn(from: Vector3, to: Vector3) -> Basis:
	var f := from.normalized()
	var t := to.normalized()
	var axis := f.cross(t)
	if axis.length() < 1e-5:
		return Basis.IDENTITY
	return Basis(axis.normalized(), acos(clampf(f.dot(t), -1.0, 1.0)))
